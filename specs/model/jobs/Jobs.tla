------------------------------- MODULE Jobs -------------------------------
\* Generated from specs/jobs.json — edit the requirements, not this file.
\* Scope: FEAT-101 execution, leases and recovery · FEAT-102 retries and dead letters ·
\*        FEAT-105 cancellation, requeue and deletion · queue pause / maintenance (FEAT-104 part) ·
\*        routing (REQ-124, REQ-125) · retention (REQ-145).
\* Uniqueness is in Jobs_Unique.tla, throttling/priority in Jobs_Throttle.tla,
\* continuations/chains/batches in Jobs_Flow.tla.
EXTENDS Naturals, FiniteSets

CONSTANTS Jobs,         \* Job slots (entity.bound = 3; 2 here, see cfg)
          Nodes,        \* hosting.Node instances (bound = 2)
          WorkerNodes,  \* nodes with the worker registered (hosting REQ-20)
          MaxAttempts,  \* @req REQ-100 (5 by default; 2 in the model)
          NodeLimit,    \* @req REQ-106 (2 x ProcessorCount; 1 in the model)
          MaxToken,     \* modeling artefact: bound on lease tokens per job slot (CONSTRAINT)
          QueueOps,     \* whether operators pause queues / maintenance in this run (keeps runs < 120 s)
          NULL

ASSUME MaxAttempts \in Nat \ {0}                 \* @req REQ-100
ASSUME NodeLimit \in Nat \ {0}                   \* @req REQ-106
ASSUME WorkerNodes \subseteq Nodes

VARIABLES job, runs, node, queue, maint
vars == <<job, runs, node, queue, maint>>

Status == {"none", "Scheduled", "Enqueued", "Processing", "Succeeded", "Failed",
           "DeadLettered", "Cancelled", "Unroutable"}
Finished == {"Succeeded", "Cancelled", "DeadLettered"}
\* history tags (history variable only, never read by an action)
Hist == {"Failed", "DeadLettered", "Interrupted", "Released", "Timeout", "Unroutable",
         "Requeued", "ShutdownFailure", "Abandoned", "LeaseCancel", "StaleCancel", "DrainLeft"}

JobRec == [status: Status, attempt: 0..MaxAttempts, token: Nat, owner: Nodes \cup {NULL},
           due: BOOLEAN,          \* scheduledAt / retryAt has passed (A-1)
           leaseExpired: BOOLEAN, \* leaseExpiresAt has passed (A-1)
           longWait: BOOLEAN,     \* enqueued for longer than UnroutableAfter (A-1, REQ-183)
           cancelReq: BOOLEAN, cancelTok: Nat, hist: SUBSET Hist]
RunRec == [node: Nodes, job: Jobs, token: Nat, mode: {"running", "abandoned", "released"},
           cSig: BOOLEAN, tSig: BOOLEAN, graceOver: BOOLEAN, sSig: BOOLEAN]
NodeRec == [st: {"Running", "Draining", "Stopped"}, handler: BOOLEAN, shutdownPassed: BOOLEAN]

TypeInv ==
  /\ job \in [Jobs -> JobRec]
  /\ runs \subseteq RunRec
  /\ node \in [Nodes -> NodeRec]
  /\ queue \in {"Active", "Paused"}
  /\ maint \in {"Off", "On"}

Init ==
  /\ job = [j \in Jobs |-> [status |-> "none", attempt |-> 0, token |-> 0, owner |-> NULL,
                            due |-> FALSE, leaseExpired |-> FALSE, longWait |-> FALSE,
                            cancelReq |-> FALSE, cancelTok |-> 0, hist |-> {}]]
  /\ runs = {}
  /\ node = [n \in Nodes |-> [st |-> "Running", handler |-> TRUE, shutdownPassed |-> FALSE]]
     \* other node states (stopped, no handler) are reached by Crash / NodeStart
  /\ queue = "Active"
  /\ maint = "Off"

RunsOn(n)   == {r \in runs : r.node = n}
Current(r)  == job[r.job].status = "Processing" /\ job[r.job].token = r.token
\* Claims a node holds: processing jobs whose current lease token is held by the node's live run (A-4).
\* Run 3: REQ-123 and INV-106 use this one measure.
Claims(n)   == {j \in Jobs : job[j].status = "Processing"
                             /\ \E r \in RunsOn(n) : r.job = j /\ r.mode = "running" /\ Current(r)}
WorkerUp    == \E n \in WorkerNodes : node[n].st = "Running"
HandlerUp   == \E n \in WorkerNodes : node[n].st = "Running" /\ node[n].handler
SetJob(j, f) == job' = [job EXCEPT ![j] = f]

\* ---------------------------------------------------------------- creation
\* @req REQ-120  enqueue -> Enqueued.  @req REQ-182  schedule for a time not in the future -> Enqueued at once.
\* @req REQ-147  payload between soft and hard limit is stored too (the warning is not state).
Enqueue(j) ==
  /\ job[j].status = "none"
  /\ SetJob(j, [job[j] EXCEPT !.status = "Enqueued", !.attempt = 0, !.owner = NULL, !.due = FALSE,
                 !.leaseExpired = FALSE, !.longWait = FALSE, !.cancelReq = FALSE, !.hist = {}])
  /\ UNCHANGED <<runs, node, queue, maint>>

\* @req REQ-121  schedule for a future time -> Scheduled.
Schedule(j) ==
  /\ job[j].status = "none"
  /\ SetJob(j, [job[j] EXCEPT !.status = "Scheduled", !.attempt = 0, !.owner = NULL, !.due = FALSE,
                 !.leaseExpired = FALSE, !.longWait = FALSE, !.cancelReq = FALSE, !.hist = {}])
  /\ UNCHANGED <<runs, node, queue, maint>>

\* ---------------------------------------------------------------- time (A-1: no clocks)
\* modeling artefact: scheduledAt / retryAt passes.
DuePasses(j) ==
  /\ job[j].status \in {"Scheduled", "Failed"} /\ ~job[j].due
  /\ SetJob(j, [job[j] EXCEPT !.due = TRUE])
  /\ UNCHANGED <<runs, node, queue, maint>>

\* modeling artefact: UnroutableAfter (REQ-183) passes for an unclaimed job.
WaitPasses(j) ==
  /\ job[j].status = "Enqueued" /\ ~job[j].longWait
  /\ SetJob(j, [job[j] EXCEPT !.longWait = TRUE])
  /\ UNCHANGED <<runs, node, queue, maint>>

\* modeling artefact: a heartbeat did not reach the store in time (crash, partition, pause) — A-2.
LeaseExpires(j) ==
  /\ job[j].status = "Processing" /\ ~job[j].leaseExpired
  /\ SetJob(j, [job[j] EXCEPT !.leaseExpired = TRUE])
  /\ UNCHANGED <<runs, node, queue, maint>>

\* ---------------------------------------------------------------- scheduler
\* @req REQ-122  (INV-115: promotion is one atomic step, so it happens once)
Promote(j) ==
  /\ job[j].status = "Scheduled" /\ job[j].due
  /\ SetJob(j, [job[j] EXCEPT !.status = "Enqueued", !.due = FALSE, !.longWait = FALSE])
  /\ UNCHANGED <<runs, node, queue, maint>>

\* @req REQ-130
RetryDue(j) ==
  /\ job[j].status = "Failed" /\ job[j].due
  /\ SetJob(j, [job[j] EXCEPT !.status = "Enqueued", !.due = FALSE, !.longWait = FALSE])
  /\ UNCHANGED <<runs, node, queue, maint>>

\* @req REQ-123  claim: active queue, maintenance off, running worker node with the handler that holds
\*               claims on fewer processing jobs than its limit; new leaseToken, attempt + 1, fresh lease.
\*               (INV-113, INV-114, hosting REQ-20)  Keys / rate limits / priority order: Jobs_Throttle.tla.
Claim(n, j) ==
  /\ job[j].status = "Enqueued"
  /\ queue = "Active" /\ maint = "Off"
  /\ n \in WorkerNodes /\ node[n].st = "Running" /\ node[n].handler
  /\ Cardinality(Claims(n)) < NodeLimit                     \* run 3: "fewer claims than its limit"
  /\ LET t == job[j].token + 1 IN
       /\ SetJob(j, [job[j] EXCEPT !.status = "Processing", !.owner = n, !.token = t,
                      !.attempt = @ + 1, !.leaseExpired = FALSE, !.longWait = FALSE])
       /\ runs' = runs \cup {[node |-> n, job |-> j, token |-> t, mode |-> "running",
                              cSig |-> FALSE, tSig |-> FALSE, graceOver |-> FALSE, sSig |-> FALSE]}
  /\ UNCHANGED <<node, queue, maint>>

\* @req REQ-124  sweep (run by a running worker node, hosting REQ-40)
MarkUnroutable(j) ==
  /\ job[j].status = "Enqueued" /\ job[j].longWait
  /\ WorkerUp /\ ~HandlerUp
  /\ SetJob(j, [job[j] EXCEPT !.status = "Unroutable", !.hist = @ \cup {"Unroutable"}])
  /\ UNCHANGED <<runs, node, queue, maint>>

\* ---------------------------------------------------------------- lease
\* @req REQ-126  heartbeat renews the lease of the run that holds the current token (INV-128 fences it).
\*               An on-time renewal is a no-op in the abstraction; this is the late one (A-2).
Renew(r) ==
  /\ r \in runs /\ r.mode = "running" /\ node[r.node].st # "Stopped"
  /\ Current(r) /\ job[r.job].leaseExpired
  /\ SetJob(r.job, [job[r.job] EXCEPT !.leaseExpired = FALSE])
  /\ UNCHANGED <<runs, node, queue, maint>>

\* Tags an outcome decided by a cancellation request recorded on an earlier run of the same job (REQ-135).
\* Run 3: REQ-141..143 clear the request on requeue, so Gap_StaleCancelRequest is expected to hold.
Stale(j) == IF job[j].token > job[j].cancelTok THEN {"StaleCancel"} ELSE {}

\* @req REQ-132 REQ-133 REQ-190  lease expired: any running worker node recovers (one event, complementary
\*                              guards); cancellation requested with attempts left -> Cancelled (REQ-190).
Recover(n, j) ==
  /\ n \in WorkerNodes /\ node[n].st = "Running"
  /\ job[j].status = "Processing" /\ job[j].leaseExpired
  /\ IF job[j].attempt < MaxAttempts /\ job[j].cancelReq
       THEN SetJob(j, [job[j] EXCEPT !.status = "Cancelled", !.owner = NULL, !.leaseExpired = FALSE,
                        !.hist = @ \cup {"LeaseCancel"} \cup Stale(j)])
     ELSE IF job[j].attempt < MaxAttempts
       THEN SetJob(j, [job[j] EXCEPT !.status = "Enqueued", !.owner = NULL, !.leaseExpired = FALSE,
                        !.longWait = FALSE, !.hist = @ \cup {"Interrupted"}])
       ELSE SetJob(j, [job[j] EXCEPT !.status = "DeadLettered", !.owner = NULL, !.leaseExpired = FALSE,
                        !.hist = @ \cup {"Interrupted", "DeadLettered"}])
  /\ UNCHANGED <<runs, node, queue, maint>>

\* ---------------------------------------------------------------- handler outcomes (actor: Handler)
SetRun(r, f) == runs' = (runs \ {r}) \cup {f}

\* @req REQ-127 REQ-128 REQ-184  handler returns: Succeeded (result stored or dropped for size: not state).
\* @req INV-128  a run whose token is not current cannot write.
SucceedByRun(r) == Current(r)
HandlerReturns(r) ==
  /\ r \in runs
  /\ runs' = runs \ {r}
  /\ IF SucceedByRun(r)
       THEN SetJob(r.job, [job[r.job] EXCEPT !.status = "Succeeded", !.owner = NULL])
       ELSE UNCHANGED job                     \* INV-128 refused, or job no longer Processing (no rule)
  /\ UNCHANGED <<node, queue, maint>>

\* Which requirement decides a throw.  e = "retryable": the retry policy allows another attempt ·
\* "permanent": the policy declines or PermanentJobFailureException · "oce": OperationCanceledException,
\* only thrown after a token was signalled (A-5).  One predicate per requirement, as written.
CR(r)         == job[r.job].cancelReq
ShutOCE(r, e) == e = "oce" /\ r.sSig            \* "an OCE thrown after the job's token was cancelled for shutdown"
R136(r, e) == e = "oce" /\ CR(r)                                          \* REQ-136
R138(r, e) == e = "oce" /\ ~CR(r) /\ r.tSig /\ ~r.graceOver               \* REQ-138 / REQ-186 ("throws OCE within it")
R140(r, e) == ShutOCE(r, e) /\ ~CR(r) /\ ~r.tSig                          \* REQ-140 (run 3: "or it throws OCE and its timeout token was not signalled")
R190(r, e) == e = "retryable" /\ CR(r) /\ job[r.job].attempt < MaxAttempts \* REQ-190 (run 3: "other than OCE or PermanentJobFailureException while
                                                                         \*  the attempt number is below maxAttempts and the retry policy allows another attempt")
\* A-5: an OCE covered by REQ-136 or REQ-138 is not also an ordinary failure (REQ-136 notes).
Gen(r, e)  == ~ShutOCE(r, e) /\ ~(e = "oce" /\ (R136(r, e) \/ R138(r, e)))
R129(r, e) == Gen(r, e) /\ ~CR(r) /\ job[r.job].attempt < MaxAttempts /\ e # "permanent"   \* REQ-129
R131(r, e) == Gen(r, e) /\ (job[r.job].attempt >= MaxAttempts \/ e = "permanent")          \* REQ-131

Rules == {"R129", "R131", "R136", "R138", "R140", "R190"}
Applies(r, e, x) == CASE x = "R129" -> R129(r, e) [] x = "R131" -> R131(r, e) [] x = "R136" -> R136(r, e)
                      [] x = "R138" -> R138(r, e) [] x = "R140" -> R140(r, e) [] x = "R190" -> R190(r, e)
Applicable(r, e) == {x \in Rules : Applies(r, e, x)}
RuleOut(r, x) == CASE x = "R129" -> {"Failed"} [] x = "R131" -> {"DeadLettered"}
                   [] x = "R136" -> {"Cancelled"} [] x = "R190" -> {"Cancelled"} [] x = "R140" -> {"Released"}
                   [] x = "R138" -> IF job[r.job].attempt < MaxAttempts THEN {"Failed", "DeadLettered"}
                                                                       ELSE {"DeadLettered"}

\* @req REQ-129 REQ-131 REQ-136 REQ-138 REQ-140 REQ-186 REQ-190   handler throws e
HandlerThrows(r, e) ==
  /\ r \in runs
  /\ e = "oce" => (r.cSig \/ r.tSig \/ r.sSig)
  /\ runs' = runs \ {r}
  /\ IF Current(r)
       THEN \E x \in Applicable(r, e) : \E o \in RuleOut(r, x) :
              LET j == r.job
                  tags == (IF o \in {"Failed", "DeadLettered"} THEN {o} ELSE {})
                          \cup (IF x = "R138" THEN {"Timeout"} ELSE {})
                          \cup (IF x \in {"R129", "R131"} /\ ShutOCE(r, e) THEN {"ShutdownFailure"} ELSE {})
                          \cup (IF x \in {"R136", "R190"} THEN Stale(j) ELSE {})
              IN IF o = "Released"
                   THEN SetJob(j, [job[j] EXCEPT !.status = "Enqueued", !.owner = NULL, !.attempt = @ - 1,
                                    !.leaseExpired = FALSE, !.longWait = FALSE, !.hist = @ \cup {"Released"}])
                   ELSE SetJob(j, [job[j] EXCEPT !.status = o, !.owner = NULL, !.due = FALSE,
                                    !.hist = @ \cup tags])
       ELSE UNCHANGED job                     \* INV-128 refused, or job no longer Processing
  /\ UNCHANGED <<node, queue, maint>>

\* ---------------------------------------------------------------- timeout
\* @req REQ-137 REQ-189  every job has a timeout; it passes (A-1) and the token is signalled.
SignalTimeout(r) ==
  /\ r \in runs /\ r.mode = "running" /\ Current(r) /\ ~r.tSig
  /\ SetRun(r, [r EXCEPT !.tSig = TRUE])
  /\ UNCHANGED <<job, node, queue, maint>>

\* modeling artefact: TimeoutGracePeriod (REQ-187) passes.
GracePasses(r) ==
  /\ r \in runs /\ r.mode = "running" /\ r.tSig /\ ~r.graceOver
  /\ SetRun(r, [r EXCEPT !.graceOver = TRUE])
  /\ UNCHANGED <<job, node, queue, maint>>

\* @req REQ-138 REQ-186 REQ-190 REQ-191  still running after the grace period: abandon the handler (it keeps
\*        running in the process outside the limit, INV-106 notes, and is recorded, REQ-191): Failed with
\*        retry or DeadLettered, or Cancelled when cancellation was requested (REQ-190).
AbandonOnTimeout(r) ==
  /\ r \in runs /\ r.mode = "running" /\ r.tSig /\ r.graceOver /\ Current(r)
  /\ IF job[r.job].cancelReq
       THEN SetJob(r.job, [job[r.job] EXCEPT !.status = "Cancelled", !.owner = NULL,
                            !.hist = @ \cup {"Abandoned"} \cup Stale(r.job)])
       ELSE \E allow \in BOOLEAN :
         IF job[r.job].attempt < MaxAttempts /\ allow
           THEN SetJob(r.job, [job[r.job] EXCEPT !.status = "Failed", !.owner = NULL, !.due = FALSE,
                                !.hist = @ \cup {"Timeout", "Failed", "Abandoned"}])
           ELSE SetJob(r.job, [job[r.job] EXCEPT !.status = "DeadLettered", !.owner = NULL,
                                !.hist = @ \cup {"Timeout", "DeadLettered", "Abandoned"}])
  /\ SetRun(r, [r EXCEPT !.mode = "abandoned"])
  /\ UNCHANGED <<node, queue, maint>>

\* ---------------------------------------------------------------- cancellation (actor: Application/Operator)
\* @req REQ-134
CancelPending(j) ==
  /\ job[j].status \in {"Scheduled", "Enqueued", "Failed", "Unroutable"}   \* Awaiting: Jobs_Flow.tla
  /\ SetJob(j, [job[j] EXCEPT !.status = "Cancelled"])
  /\ UNCHANGED <<runs, node, queue, maint>>

\* @req REQ-135  record the request and signal the token of the run holding the job.
CancelProcessing(j) ==
  /\ job[j].status = "Processing" /\ ~job[j].cancelReq
  /\ SetJob(j, [job[j] EXCEPT !.cancelReq = TRUE, !.cancelTok = job[j].token])
  /\ runs' = {IF r.job = j /\ r.token = job[j].token THEN [r EXCEPT !.cSig = TRUE] ELSE r : r \in runs}
  /\ UNCHANGED <<node, queue, maint>>

\* ---------------------------------------------------------------- shutdown (hosting Node lifecycle)
\* hosting REQ-27: the host stops a running node.
NodeDrain(n) ==
  /\ node[n].st = "Running"
  /\ node' = [node EXCEPT ![n].st = "Draining"]
  /\ UNCHANGED <<job, runs, queue, maint>>

\* modeling artefact: ShutdownTimeout passes.
ShutdownPasses(n) ==
  /\ node[n].st = "Draining" /\ ~node[n].shutdownPassed
  /\ node' = [node EXCEPT ![n].shutdownPassed = TRUE]
  /\ UNCHANGED <<job, runs, queue, maint>>

\* @req REQ-139
SignalShutdown(r) ==
  /\ r \in runs /\ r.mode = "running" /\ ~r.sSig
  /\ node[r.node].st = "Draining" /\ node[r.node].shutdownPassed
  /\ SetRun(r, [r EXCEPT !.sSig = TRUE])
  /\ UNCHANGED <<job, node, queue, maint>>

\* @req REQ-140 REQ-190 REQ-191  handler still running: release the lease and take back the attempt or, when
\*        cancellation was requested, mark the job Cancelled (REQ-190); the handler is abandoned and recorded
\*        (REQ-191).  The "throws OperationCanceledException" branch of REQ-140 is in HandlerThrows.
\*        Run 4: REQ-140 applies only while the timeout token was not signalled (both branches).  REQ-190's
\*        "its node releases it at shutdown" has no timeout guard of its own and is kept as written (A-19).
ReleaseOnShutdown(r) ==
  /\ r \in runs /\ r.mode = "running" /\ r.sSig /\ Current(r)
  /\ node[r.node].st = "Draining"
  /\ job[r.job].cancelReq \/ ~r.tSig
  /\ IF job[r.job].cancelReq
       THEN SetJob(r.job, [job[r.job] EXCEPT !.status = "Cancelled", !.owner = NULL,
                            !.hist = @ \cup {"Abandoned"} \cup Stale(r.job)])
       ELSE SetJob(r.job, [job[r.job] EXCEPT !.status = "Enqueued", !.owner = NULL, !.attempt = @ - 1,
                     !.leaseExpired = FALSE, !.longWait = FALSE, !.hist = @ \cup {"Released", "Abandoned"}])
  /\ SetRun(r, [r EXCEPT !.mode = "released"])
  /\ UNCHANGED <<node, queue, maint>>

\* hosting REQ-29 (run 4 wording): stop when every in-flight job has finished, or once ShutdownTimeout has
\* passed, every remaining run's token was cancelled and "the lease releases that jobs REQ-140 calls for" were
\* attempted.  Runs REQ-140 does not call to release (timeout signalled, or cancellation requested) do not hold
\* the node.  A current run left behind is tagged DrainLeft (history only) so probes can tell it from a crash.
R140Pending(r) == r.mode = "running" /\ Current(r) /\ ~r.tSig /\ ~job[r.job].cancelReq
NodeStop(n) ==
  /\ node[n].st = "Draining"
  /\ \/ RunsOn(n) = {}
     \/ /\ node[n].shutdownPassed
        /\ \A r \in RunsOn(n) : r.mode = "running" => r.sSig
        /\ \A r \in RunsOn(n) : ~R140Pending(r)
  /\ node' = [node EXCEPT ![n].st = "Stopped", ![n].shutdownPassed = FALSE]
  /\ runs' = runs \ RunsOn(n)
  /\ job' = [j \in Jobs |-> IF \E r \in RunsOn(n) : r.job = j /\ r.mode = "running" /\ Current(r)
                              THEN [job[j] EXCEPT !.hist = @ \cup {"DrainLeft"}] ELSE job[j]]
  /\ UNCHANGED <<queue, maint>>

\* modeling artefact A-3: a process dies; its handlers die with it, its leases will expire.
Crash(n) ==
  /\ node[n].st # "Stopped"
  /\ node' = [node EXCEPT ![n].st = "Stopped", ![n].shutdownPassed = FALSE]
  /\ runs' = runs \ RunsOn(n)
  /\ UNCHANGED <<job, queue, maint>>

\* hosting REQ-12/REQ-18: a node starts, possibly with a handler for the job's name (rolling deploy).
\* @req REQ-125  a running worker node registers a handler -> Unroutable jobs return to Enqueued.
NodeStart(n) ==
  /\ node[n].st = "Stopped"
  /\ \E h \in BOOLEAN :
       /\ node' = [node EXCEPT ![n] = [st |-> "Running", handler |-> h, shutdownPassed |-> FALSE]]
       /\ IF h /\ n \in WorkerNodes
            THEN job' = [j \in Jobs |-> IF job[j].status = "Unroutable"
                                           THEN [job[j] EXCEPT !.status = "Enqueued", !.longWait = FALSE]
                                           ELSE job[j]]
            ELSE UNCHANGED job
  /\ UNCHANGED <<runs, queue, maint>>

\* ---------------------------------------------------------------- requeue / delete / retention
\* @req REQ-141 REQ-142  dead letter -> Enqueued, attempt 0, cancellation request cleared (bulk = per job,
\*                      one atomic step each).
\* @req REQ-143          succeeded / cancelled -> Enqueued, attempt 0, cancellation request cleared, history kept.
\* @req INV-129          any other state is refused (guard).  Unique-key part: Jobs_Unique.tla.
Requeue(j) ==
  /\ job[j].status \in Finished
  /\ SetJob(j, [job[j] EXCEPT !.status = "Enqueued", !.attempt = 0, !.owner = NULL, !.cancelReq = FALSE,
                 !.longWait = FALSE, !.due = FALSE, !.hist = @ \cup {"Requeued"}])
  /\ UNCHANGED <<runs, node, queue, maint>>

\* @req REQ-144  any state but Processing (INV-130 refuses Processing: guard).
Delete(j) ==
  /\ job[j].status \notin {"none", "Processing"}
  /\ SetJob(j, [job[j] EXCEPT !.status = "none"])
  /\ UNCHANGED <<runs, node, queue, maint>>

\* @req REQ-145  retention passed (A-1) -> removed.
Retention(j) ==
  /\ job[j].status \in Finished
  /\ SetJob(j, [job[j] EXCEPT !.status = "none"])
  /\ UNCHANGED <<runs, node, queue, maint>>

\* ---------------------------------------------------------------- queue / maintenance (actor: Operator)
\* @req REQ-160
PauseQueue  == QueueOps /\ queue = "Active" /\ queue' = "Paused" /\ UNCHANGED <<job, runs, node, maint>>
\* @req REQ-161
ResumeQueue == QueueOps /\ queue = "Paused" /\ queue' = "Active" /\ UNCHANGED <<job, runs, node, maint>>
\* @req REQ-162
MaintOn     == QueueOps /\ maint = "Off" /\ maint' = "On" /\ UNCHANGED <<job, runs, node, queue>>
\* @req REQ-163
MaintOff    == QueueOps /\ maint = "On" /\ maint' = "Off" /\ UNCHANGED <<job, runs, node, queue>>

Next ==
  \/ \E j \in Jobs : \/ Enqueue(j) \/ Schedule(j) \/ DuePasses(j) \/ WaitPasses(j) \/ LeaseExpires(j)
                     \/ Promote(j) \/ RetryDue(j) \/ MarkUnroutable(j) \/ CancelPending(j)
                     \/ CancelProcessing(j) \/ Requeue(j) \/ Delete(j) \/ Retention(j)
  \/ \E n \in Nodes, j \in Jobs : Claim(n, j) \/ Recover(n, j)
  \/ \E r \in runs : \/ Renew(r) \/ HandlerReturns(r) \/ SignalTimeout(r) \/ GracePasses(r)
                     \/ AbandonOnTimeout(r) \/ SignalShutdown(r) \/ ReleaseOnShutdown(r)
                     \/ \E e \in {"retryable", "permanent", "oce"} : HandlerThrows(r, e)
  \/ \E n \in Nodes : NodeDrain(n) \/ ShutdownPasses(n) \/ NodeStop(n) \/ Crash(n) \/ NodeStart(n)
  \/ PauseQueue \/ ResumeQueue \/ MaintOn \/ MaintOff

\* Fairness only for actor: system and for the passing of time.
Fairness ==
  /\ \A j \in Jobs : /\ WF_vars(Promote(j)) /\ WF_vars(RetryDue(j)) /\ WF_vars(MarkUnroutable(j))
                     /\ WF_vars(Retention(j)) /\ WF_vars(DuePasses(j)) /\ WF_vars(WaitPasses(j))
                     /\ WF_vars(\E n \in Nodes : Claim(n, j)) /\ WF_vars(\E n \in Nodes : Recover(n, j))
  /\ \A n \in Nodes : WF_vars(ShutdownPasses(n)) /\ WF_vars(NodeStop(n))
  /\ \A j \in Jobs :
       /\ WF_vars(\E r \in runs : r.job = j /\ SignalTimeout(r))
       /\ WF_vars(\E r \in runs : r.job = j /\ GracePasses(r))
       /\ WF_vars(\E r \in runs : r.job = j /\ AbandonOnTimeout(r))
       /\ WF_vars(\E r \in runs : r.job = j /\ SignalShutdown(r))
       /\ WF_vars(\E r \in runs : r.job = j /\ ReleaseOnShutdown(r))
       /\ WF_vars(\E r \in runs : r.job = j /\ Renew(r))

Spec == Init /\ [][Next]_vars /\ Fairness

StateBound == \A j \in Jobs : job[j].token <= MaxToken     \* CONSTRAINT (modeling artefact)

\* ======================================================================== properties
\* @req INV-103  never more than one worker holds an unexpired claim on a job.
Inv_SingleClaim ==
  \A j \in Jobs : Cardinality({r \in runs : r.job = j /\ r.mode = "running" /\ Current(r)
                                            /\ ~job[j].leaseExpired}) <= 1

\* @req INV-106  never claims on more processing jobs at once on a node than its limit (Claims, A-4).
Inv_NodeClaims == \A n \in Nodes : Cardinality(Claims(n)) <= NodeLimit

\* Former reading of INV-106 (run 1, F-5): handlers executing in the process, abandoned ones included.
\* Expected VIOLATED and accepted by the owner (INV-106, REQ-191 notes); kept to show the trace.
Chk_HandlersWithinLimit ==
  \A n \in Nodes : Cardinality({r \in RunsOn(n) : node[n].st # "Stopped"}) <= NodeLimit

\* @req INV-130  a processing job cannot be deleted.
Inv_NoDeleteProcessing == \A j \in Jobs : job[j].status = "Processing" => ~ENABLED Delete(j)

\* @req INV-129  only finished jobs can be requeued.
Inv_RequeueOnlyFinished == \A j \in Jobs : job[j].status \notin Finished => ~ENABLED Requeue(j)

\* @req SCN-103 INV-104  a processing job whose lease has not passed is never recovered.
Scn_HealthyNotRecovered ==
  \A j \in Jobs, n \in Nodes : (job[j].status = "Processing" /\ ~job[j].leaseExpired) => ~ENABLED Recover(n, j)

\* @req SCN-104  a claimed job cannot be claimed again.
Scn_NoSecondClaim == \A j \in Jobs, n \in Nodes : job[j].status = "Processing" => ~ENABLED Claim(n, j)

\* @req SCN-107  a cancelled scheduled job is never promoted.
Scn_CancelledNotPromoted == \A j \in Jobs : job[j].status = "Cancelled" => ~ENABLED Promote(j)

\* @req SCN-110 INV-113  a paused queue is not drained.  @req INV-114  nor during maintenance.
Scn_PausedNotDrained ==
  \A j \in Jobs, n \in Nodes : (queue = "Paused" \/ maint = "On") => ~ENABLED Claim(n, j)

\* @req SCN-117 INV-128  a stale run cannot complete a job.  Run 4: "stale" includes a run whose job is no
\*        longer processing (INV-128's new clause).
Scn_StaleCannotComplete ==
  \A r \in runs : (job[r.job].token # r.token \/ job[r.job].status # "Processing")
                  => ~ENABLED (SucceedByRun(r) /\ HandlerReturns(r))

\* @req INV-128 REQ-140  (run 4) a run that was released at shutdown or abandoned is never current again, so
\*        none of its writes (complete, fail, renew) can change its job, before or after the job is claimed again.
Inv_StaleRunsFenced == \A r \in runs : r.mode \in {"released", "abandoned"} => ~Current(r)

\* @req SCN-120 hosting REQ-20  a process without the worker never claims.
Scn_NoWorkerNoClaim == \A j \in Jobs, n \in Nodes \ WorkerNodes : ~ENABLED Claim(n, j)

\* Same-trigger check (validate warning REQ-129/REQ-131 + REQ-136/REQ-138): a run that may throw
\* OperationCanceledException while both REQ-136 and REQ-138 apply.  Violation = two rules, two outcomes.
Chk_CancelTimeoutOverlap ==
  \A r \in runs : ~(Current(r) /\ R136(r, "oce") /\ R138(r, "oce"))

\* Pairwise same-event checks (each run alone gives its own shortest trace).
Chk_PermanentVsCancel   == \A r \in runs : ~(Current(r) /\ R131(r, "permanent") /\ R190(r, "permanent"))   \* REQ-131 vs REQ-190
Chk_TimeoutVsShutdown   == \A r \in runs : ~(Current(r) /\ (r.cSig \/ r.tSig \/ r.sSig) /\ R138(r, "oce") /\ R140(r, "oce"))   \* REQ-138/186 vs REQ-140

\* Same-event check for every throw: at most one of REQ-129, REQ-131, REQ-136, REQ-138/186, REQ-140 and
\* REQ-190 applies.  Violation = two requirements decide one exception differently.
Chk_SingleRule ==
  \A r \in runs, e \in {"retryable", "permanent", "oce"} :
    (Current(r) /\ (e = "oce" => (r.cSig \/ r.tSig \/ r.sSig))) => Cardinality(Applicable(r, e)) <= 1

\* @req LIV-101  while processing with an expired lease and a worker node running, the job is
\*               eventually returned or dead-lettered (or the condition stops holding, A-6).
Liv_LeaseRecovered ==
  \A j \in Jobs : (job[j].status = "Processing" /\ job[j].leaseExpired /\ WorkerUp)
                  ~> (job[j].status \in {"Enqueued", "DeadLettered"}
                      \/ ~(job[j].status = "Processing" /\ job[j].leaseExpired) \/ ~WorkerUp)

\* ---------------------------------------------------------------- positive scenario traps (expected VIOLATED)
\* @req SCN-100
Scn100_NotReached == ~\E j \in Jobs : job[j].status = "Succeeded" /\ job[j].attempt = 1 /\ job[j].hist = {}
\* @req SCN-101  (maxAttempts = 2 = MaxAttempts)
Scn101_NotReached == ~\E j \in Jobs : job[j].status = "DeadLettered" /\ job[j].attempt = 2
                        /\ job[j].hist = {"Failed", "DeadLettered"}
\* @req SCN-102
Scn102_NotReached == ~\E j \in Jobs : job[j].status = "Succeeded" /\ job[j].attempt = 2
                        /\ job[j].hist = {"Interrupted"}
\* @req SCN-111
Scn111_NotReached == ~\E j \in Jobs : job[j].status = "Succeeded" /\ "Unroutable" \in job[j].hist
                        /\ job[j].hist \cap {"Failed", "DeadLettered"} = {}
\* @req SCN-112  (dead-lettered after MaxAttempts, requeued, claimed: attempt 1)
Scn112_NotReached == ~\E j \in Jobs : job[j].status = "Processing" /\ job[j].attempt = 1
                        /\ {"DeadLettered", "Requeued"} \subseteq job[j].hist
\* @req SCN-115
Scn115_NotReached == ~\E j \in Jobs : job[j].status = "Processing" /\ job[j].attempt = 1
                        /\ "Released" \in job[j].hist
                        /\ \E r \in runs : r.job = j /\ r.mode = "released" /\ r.node # job[j].owner

\* ---------------------------------------------------------------- gap probes (finding evidence; expected VIOLATED)
\* A job whose cancellation was requested is claimed and runs again without anyone requeuing it.
Gap_CancelRequestLost ==
  ~\E j \in Jobs : job[j].cancelReq /\ job[j].status = "Processing" /\ job[j].token > job[j].cancelTok
                   /\ "Requeued" \notin job[j].hist
\* A handler that honours the shutdown token gets a counted, failed attempt.
Gap_CooperativeShutdownCounted == ~\E j \in Jobs : "ShutdownFailure" \in job[j].hist
\* A cancellation requested on an earlier run decides a later run after a requeue (A-16).
Gap_StaleCancelRequest == ~\E j \in Jobs : "StaleCancel" \in job[j].hist

\* @req REQ-191 INV-128 REQ-123  (run 4) REQ-191 records a lease-lost handler when the system "refuses the heartbeat
\*        of a handler that is still running because its lease token is no longer current or its job is no longer
\*        processing".  The record is history only, so it is a predicate, not an action.
LeaseLostRecordable(r) == r.mode = "running" /\ node[r.node].st # "Stopped"
                          /\ (job[r.job].token # r.token \/ job[r.job].status # "Processing")
\* Run 3 probe (F-2): a handler still running on a live node holds no claim (so its node claims another job,
\* REQ-123), its job has left Processing for a finished state without a new lease token, and REQ-191 cannot
\* record it.  Run 4: expected to HOLD (the new trigger is the complement of Current).
Gap_LeaseLostUnrecorded ==
  ~\E r \in runs : /\ r.mode = "running" /\ node[r.node].st # "Stopped" /\ ~Current(r)
                   /\ ~LeaseLostRecordable(r) /\ job[r.job].status \in Finished
                   /\ Claims(r.node) # {}

\* Check (run 3): a handler whose timeout token was signalled and whose node then signals shutdown.  If it is
\* still running, REQ-140 releases it and takes the attempt back; if it throws OperationCanceledException,
\* REQ-138/186 count the attempt.  Violation = a state where both are possible (cooperating costs an attempt).
Chk_TimeoutReleaseSplit ==
  \A r \in runs : ~(Current(r) /\ r.tSig /\ r.sSig /\ ~r.graceOver /\ ~CR(r)
                    /\ ENABLED ReleaseOnShutdown(r) /\ R138(r, "oce"))

\* @req SCN-122  positive: a cancelled job whose lease expires with attempts left ends Cancelled (expected VIOLATED).
Scn122_NotReached == ~\E j \in Jobs : job[j].status = "Cancelled" /\ "LeaseCancel" \in job[j].hist

\* @req SCN-124 REQ-140  (run 4) negative, impossibleAt 3: a run whose timeout token was signalled and whose
\*        token was then cancelled for shutdown is not released with its attempt taken back, whether the handler
\*        is still running (ReleaseOnShutdown) or throws OperationCanceledException (R140).
Scn124_TimedOutNotReleased ==
  \A r \in runs : (Current(r) /\ r.tSig /\ r.sSig /\ ~CR(r)) => (~ENABLED ReleaseOnShutdown(r) /\ ~R140(r, "oce"))
\* SCN-124 steps 1-2 are reachable (expected VIOLATED): shows the property above is not vacuous.
Scn124_StepsNotReached == ~\E r \in runs : Current(r) /\ r.tSig /\ r.sSig /\ ~CR(r) /\ job[r.job].attempt = 1

\* @req SCN-125  (run 4) positive: a lease-lost run of a job cancelled on recovery (REQ-190, no new token) is
\*        still running, its job is Cancelled and REQ-191 can record it (expected VIOLATED).
Scn125_NotReached ==
  ~\E r \in runs : /\ LeaseLostRecordable(r) /\ job[r.job].token = r.token
                   /\ job[r.job].status = "Cancelled" /\ "LeaseCancel" \in job[r.job].hist

\* Probe (run 4): an operator cancels a processing job at its last attempt, the node drains, and hosting REQ-29
\* (run 4 wording) lets it stop without REQ-190's shutdown branch, because REQ-140 does not call for releasing a
\* job whose cancellation was requested.  Lease expiry then dead-letters it (REQ-133).  Expected VIOLATED.
Gap_CancelledDeadLetteredAfterDrain ==
  ~\E j \in Jobs : job[j].status = "DeadLettered" /\ job[j].cancelReq
                   /\ {"DrainLeft", "Interrupted"} \subseteq job[j].hist

\* Probe (run 4): a timed-out run left behind by a draining node (REQ-29) ends with its attempt counted by
\* lease expiry (REQ-132/133), never released.  Expected VIOLATED (reachable): the F-1 path.
Reach_TimedOutLeftCounted ==
  ~\E j \in Jobs : "DrainLeft" \in job[j].hist /\ "Interrupted" \in job[j].hist /\ "Released" \notin job[j].hist
                   /\ job[j].status = "Enqueued" /\ job[j].attempt = 1 /\ ~job[j].cancelReq

\* Check (run 4, hosting REQ-29): a draining node eventually stops.
Liv_DrainEnds == \A n \in Nodes : node[n].st = "Draining" ~> node[n].st = "Stopped"
=============================================================================
