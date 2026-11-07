----------------------------- MODULE Jobs_Flow -----------------------------
\* Generated from specs/jobs.json — edit the requirements, not this file.
\* Scope: FEAT-106 continuations, chains and batches: REQ-170..REQ-177, REQ-179..REQ-181, REQ-188, REQ-192,
\*        LIV-102, SCN-108, SCN-109, SCN-114, SCN-118, SCN-119; plus the parent-side effects of
\*        REQ-134 (cancel Awaiting), REQ-141/REQ-143 (requeue), REQ-144 (delete), REQ-145 (retention).
\* Execution is abstracted to claim -> outcome; leases and nodes are in Jobs.tla.
EXTENDS Naturals, FiniteSets

CONSTANTS Jobs, Batches,
          MaxAttempts,  \* @req REQ-100 (2 in the model)
          EnvActs,      \* environment/people actions allowed in this run, subset of
                        \* {"unroutable", "cancel", "requeue", "delete"}
          BatchConds,   \* batch-level continuation conditions used: subset of {"OnBatchSucceeded", "OnBatchCompleted"}
          NULL

VARIABLES job, batch
vars == <<job, batch>>

Status == {"none", "Enqueued", "Processing", "Succeeded", "Failed", "DeadLettered", "Cancelled",
           "Awaiting", "Unroutable", "removed"}
Finished == {"Succeeded", "DeadLettered", "Cancelled"}
Pending  == {"Enqueued", "Processing", "Failed", "Awaiting", "Unroutable"}
JobConds == {"OnSuccess", "OnFailure", "OnCompletion"}
Conds    == {"-"} \cup JobConds \cup {"OnBatchSucceeded", "OnBatchCompleted"}

JobRec == [status: Status, attempt: 0..MaxAttempts, parent: Jobs \cup {NULL}, cond: Conds,
           member: Batches \cup {NULL}, cbatch: Batches \cup {NULL},
           fires: 0..3,                \* times released to Enqueued as a continuation (history)
           released: {"no", "enq", "cancel"},
           late: BOOLEAN,              \* added by REQ-175 to a parent that had already finished (history)
           hs: SUBSET Finished]        \* outcomes ever reached (history)

TypeInv ==
  /\ job \in [Jobs -> JobRec]
  /\ batch \in [Batches -> [status: {"none", "Open", "Succeeded", "Completed", "removed"}, wasCompleted: BOOLEAN]]

Empty == [status |-> "none", attempt |-> 0, parent |-> NULL, cond |-> "-", member |-> NULL,
          cbatch |-> NULL, fires |-> 0, released |-> "no", late |-> FALSE, hs |-> {}]
Init == job = [j \in Jobs |-> Empty] /\ batch = [b \in Batches |-> [status |-> "none", wasCompleted |-> FALSE]]

\* Awaiting continuations below a set of jobs (transitively).
RECURSIVE Close(_)
Close(S) == LET N == S \cup {c \in Jobs : job[c].status = "Awaiting" /\ job[c].parent \in S}
            IN IF N = S THEN S ELSE Close(N)

Matches(cond, outcome) ==
  \/ outcome = "Succeeded"    /\ cond \in {"OnSuccess", "OnCompletion"}     \* REQ-171
  \/ outcome = "DeadLettered" /\ cond \in {"OnFailure", "OnCompletion"}     \* REQ-172

\* A-10: continuations are resolved in the same step as the parent's event (REQ-171..174, REQ-173
\* cascade, REQ-188); the cascade repeats down a chain (REQ-173 notes).
\* outcome \in {"Succeeded", "DeadLettered", "Cancelled", "deleted"}  ("deleted" = REQ-144 or retention)
\* Run 2: REQ-174 cancels only on success with OnFailure; a non-matching continuation of a dead-lettered
\* parent stays Awaiting (the parent can be requeued).
Resolved(f, p, outcome) ==
  LET direct == {c \in Jobs : f[c].status = "Awaiting" /\ f[c].parent = p}
      enq    == IF outcome \in {"Succeeded", "DeadLettered"}
                  THEN {c \in direct : Matches(f[c].cond, outcome)} ELSE {}
      cancel == IF outcome = "DeadLettered" THEN {} ELSE Close(direct \ enq)
  IN [c \in Jobs |-> IF c \in enq THEN [f[c] EXCEPT !.status = "Enqueued", !.fires = @ + 1, !.released = "enq"]
                     ELSE IF c \in cancel THEN [f[c] EXCEPT !.status = "Cancelled", !.released = "cancel",
                                                             !.hs = @ \cup {"Cancelled"}]
                     ELSE f[c]]

\* A job reaches outcome o; its continuations resolve in the same step.
Reach(j, o, extra) ==
  LET f == [job EXCEPT ![j] = [@ EXCEPT !.status = o, !.hs = @ \cup {o}]]
  IN job' = Resolved(f, j, o)

\* ---------------------------------------------------------------- creation (actor: Application)
\* @req REQ-120
Enqueue(j) ==
  /\ job[j].status = "none"
  /\ job' = [job EXCEPT ![j] = [Empty EXCEPT !.status = "Enqueued"]]
  /\ UNCHANGED batch

\* @req REQ-170  parent not finished -> Awaiting.
\* @req REQ-175  parent finished -> resolve as if the parent had just finished (REQ-171..174); stored as
\*               awaiting only when none of those rules applies (run 3).
\* @req INV-138  a parent id that does not exist (never created, deleted or removed) is rejected: guard.
AddContinuation(c, p, cond) ==
  /\ job[c].status = "none" /\ p # c
  /\ job[p].status \in Pending \cup Finished
  /\ IF job[p].status \in Pending
       THEN job' = [job EXCEPT ![c] = [Empty EXCEPT !.status = "Awaiting", !.parent = p, !.cond = cond]]
       ELSE LET aw == [job EXCEPT ![c] = [Empty EXCEPT !.status = "Awaiting", !.parent = p, !.cond = cond,
                                                       !.late = TRUE]]
            IN job' = Resolved(aw, p, job[p].status)
  /\ UNCHANGED batch

\* @req REQ-176  chain a -> b: a Enqueued, b OnSuccess continuation of a, one transaction.
CreateChain(a, b) ==
  /\ a # b /\ job[a].status = "none" /\ job[b].status = "none"
  /\ job' = [job EXCEPT ![a] = [Empty EXCEPT !.status = "Enqueued"],
                        ![b] = [Empty EXCEPT !.status = "Awaiting", !.parent = a, !.cond = "OnSuccess"]]
  /\ UNCHANGED batch

\* @req REQ-177  batch with members m1, m2 and a batch-level continuation c, one transaction (REQ-178 retired).
CreateBatch(bt, m1, m2, c, cond) ==
  /\ batch[bt].status = "none"
  /\ Cardinality({m1, m2, c}) = 3
  /\ \A x \in {m1, m2, c} : job[x].status = "none"
  /\ job' = [job EXCEPT ![m1] = [Empty EXCEPT !.status = "Enqueued", !.member = bt],
                        ![m2] = [Empty EXCEPT !.status = "Enqueued", !.member = bt],
                        ![c]  = [Empty EXCEPT !.status = "Awaiting", !.cbatch = bt, !.cond = cond]]
  /\ batch' = [batch EXCEPT ![bt].status = "Open"]

\* ---------------------------------------------------------------- execution (abstract)
\* @req REQ-123
Claim(j) == /\ job[j].status = "Enqueued" /\ job[j].attempt < MaxAttempts
            /\ job' = [job EXCEPT ![j].status = "Processing", ![j].attempt = @ + 1]
            /\ UNCHANGED batch

\* @req REQ-127 REQ-129 REQ-131 REQ-136  handler outcome (actor: Handler — not fair).
HandlerOutcome(j) ==
  /\ job[j].status = "Processing"
  /\ \/ Reach(j, "Succeeded", 0)
     \/ job[j].attempt < MaxAttempts /\ job' = [job EXCEPT ![j].status = "Failed"]
     \/ Reach(j, "DeadLettered", 0)
     \/ "cancel" \in EnvActs /\ Reach(j, "Cancelled", 0)
  /\ UNCHANGED batch

\* @req REQ-137 REQ-138 REQ-186  every run ends by its timeout at the latest (system — fair).
TimeoutOutcome(j) ==
  /\ job[j].status = "Processing"
  /\ IF job[j].attempt < MaxAttempts THEN job' = [job EXCEPT ![j].status = "Failed"]
                                     ELSE Reach(j, "DeadLettered", 0)
  /\ UNCHANGED batch

\* @req REQ-130
RetryDue(j) == job[j].status = "Failed" /\ job' = [job EXCEPT ![j].status = "Enqueued"] /\ UNCHANGED batch

\* @req REQ-124 / REQ-125  no live node has the handler / one registers (environment).
GoUnroutable(j) == "unroutable" \in EnvActs /\ job[j].status = "Enqueued"
                   /\ job' = [job EXCEPT ![j].status = "Unroutable"] /\ UNCHANGED batch
BackRoutable(j) == job[j].status = "Unroutable"
                   /\ job' = [job EXCEPT ![j].status = "Enqueued"] /\ UNCHANGED batch

\* ---------------------------------------------------------------- people
\* @req REQ-134 REQ-173  cancel a pending job (incl. Awaiting); continuations below it are cancelled.
Cancel(j) == "cancel" \in EnvActs /\ job[j].status \in {"Enqueued", "Failed", "Awaiting", "Unroutable"}
             /\ Reach(j, "Cancelled", 0) /\ UNCHANGED batch

\* @req REQ-141 REQ-143  requeue a finished job, attempt 0 (history kept).
Requeue(j) == "requeue" \in EnvActs /\ job[j].status \in Finished
              /\ job' = [job EXCEPT ![j].status = "Enqueued", ![j].attempt = 0] /\ UNCHANGED batch

\* @req REQ-144 REQ-188  delete (not Processing); awaiting continuations of it are cancelled.
Delete(j) == "delete" \in EnvActs /\ job[j].status \notin {"none", "removed", "Processing"}
             /\ LET f == [job EXCEPT ![j].status = "removed"] IN job' = Resolved(f, j, "deleted")
             /\ UNCHANGED batch

\* @req REQ-145 REQ-188  retention removes finished jobs (system, time A-1) except members of an open or
\*                      completed batch; awaiting continuations of a removed parent are cancelled (REQ-188).
\*                      Slots are not reused (A-11).
Retention(j) == /\ job[j].status \in Finished
                /\ ~(job[j].member # NULL /\ batch[job[j].member].status \in {"Open", "Completed"})
                /\ LET f == [job EXCEPT ![j].status = "removed"] IN job' = Resolved(f, j, "deleted")
                /\ UNCHANGED batch

\* ---------------------------------------------------------------- batches (system)
Members(bt) == {j \in Jobs : job[j].member = bt}
\* A-12: "every member job" ranges over the members created with the batch.  Run 2 (REQ-180): a deleted
\*       member counts as finished and not succeeded; retention no longer removes members of an open or
\*       completed batch (REQ-145).
AllSucceeded(bt) == \A m \in Members(bt) : job[m].status = "Succeeded"
AllFinished(bt)  == \A m \in Members(bt) : job[m].status \in Finished \cup {"removed"}

\* @req REQ-181  batch-level continuations released in the same step as the batch transition.
ReleaseBatchConts(bt, succeeded) ==
  [c \in Jobs |-> IF job[c].status = "Awaiting" /\ job[c].cbatch = bt
                     /\ (job[c].cond = "OnBatchCompleted" \/ (succeeded /\ job[c].cond = "OnBatchSucceeded"))
                    THEN [job[c] EXCEPT !.status = "Enqueued", !.fires = @ + 1, !.released = "enq"]
                    ELSE job[c]]

\* @req REQ-179  Open or Completed -> Succeeded when every member succeeded.
BatchSucceeds(bt) ==
  /\ batch[bt].status \in {"Open", "Completed"} /\ AllSucceeded(bt)
  /\ batch' = [batch EXCEPT ![bt].status = "Succeeded"]
  /\ job' = ReleaseBatchConts(bt, TRUE)

\* @req REQ-180  Open -> Completed when every member is succeeded, dead-lettered, cancelled or deleted and
\*               one did not succeed.
BatchCompletes(bt) ==
  /\ batch[bt].status = "Open" /\ AllFinished(bt) /\ ~AllSucceeded(bt)
  /\ batch' = [batch EXCEPT ![bt].status = "Completed", ![bt].wasCompleted = TRUE]
  /\ job' = ReleaseBatchConts(bt, FALSE)

\* @req REQ-192 REQ-188  (run 3) a Completed or Succeeded batch is removed with its stored members once every
\*        stored member is past its own state's retention (A-1: a fair nondeterministic event, guarded only
\*        by every stored member being finished).  Awaiting batch-level continuations are cancelled (REQ-188).
\*        Run 4: REQ-188 now names both retention paths ("removed by retention (REQ-145, REQ-192)"), so
\*        awaiting job-level continuations of a removed member are cancelled too.  Slots are not reused (A-11).
StoredMembers(bt) == {m \in Members(bt) : job[m].status # "removed"}
BatchRemoved(bt) ==
  /\ batch[bt].status \in {"Completed", "Succeeded"}
  /\ \A m \in StoredMembers(bt) : job[m].status \in Finished
  /\ batch' = [batch EXCEPT ![bt].status = "removed"]
  /\ LET RM == StoredMembers(bt)
         f0 == [c \in Jobs |-> IF c \in RM THEN [job[c] EXCEPT !.status = "removed"]
                               ELSE IF job[c].status = "Awaiting" /\ job[c].cbatch = bt
                                 THEN [job[c] EXCEPT !.status = "Cancelled", !.released = "cancel",
                                                     !.hs = @ \cup {"Cancelled"}]
                               ELSE job[c]]
         cascade == Close({c \in Jobs : f0[c].status = "Awaiting" /\ f0[c].parent \in RM}
                          \cup {c \in Jobs : job[c].status = "Awaiting" /\ job[c].cbatch = bt})
     IN job' = [c \in Jobs |-> IF c \in cascade /\ f0[c].status = "Awaiting"
                                 THEN [f0[c] EXCEPT !.status = "Cancelled", !.released = "cancel",
                                                    !.hs = @ \cup {"Cancelled"}]
                                 ELSE f0[c]]

Next ==
  \/ \E j \in Jobs : \/ Enqueue(j) \/ Claim(j) \/ HandlerOutcome(j) \/ TimeoutOutcome(j) \/ RetryDue(j)
                     \/ GoUnroutable(j) \/ BackRoutable(j) \/ Cancel(j) \/ Requeue(j) \/ Delete(j)
                     \/ Retention(j)
  \/ \E c, p \in Jobs, cond \in JobConds : AddContinuation(c, p, cond)
  \/ \E a, b \in Jobs : CreateChain(a, b)
  \/ \E bt \in Batches, m1, m2, c \in Jobs, cond \in BatchConds : CreateBatch(bt, m1, m2, c, cond)
  \/ \E bt \in Batches : BatchSucceeds(bt) \/ BatchCompletes(bt) \/ BatchRemoved(bt)

\* Fair: system actions.  BackRoutable is environment (a node with the handler starts) — not fair.
Fairness ==
  /\ \A j \in Jobs : WF_vars(Claim(j)) /\ WF_vars(TimeoutOutcome(j)) /\ WF_vars(RetryDue(j))
                     /\ WF_vars(Retention(j))
  /\ \A bt \in Batches : WF_vars(BatchSucceeds(bt)) /\ WF_vars(BatchCompletes(bt)) /\ WF_vars(BatchRemoved(bt))

Spec == Init /\ [][Next]_vars /\ Fairness

\* ======================================================================== properties
\* @req LIV-102  an awaiting continuation is eventually enqueued or cancelled (A-6 reading).
Liv_ContinuationResolved == \A c \in Jobs : job[c].status = "Awaiting" ~> job[c].status # "Awaiting"

\* @req SCN-109  an OnSuccess continuation is never released by a parent that never succeeded.
Scn109_OnSuccessNotAfterDeadLetter ==
  \A c \in Jobs : (job[c].cond = "OnSuccess" /\ job[c].released = "enq" /\ job[c].parent # NULL)
                  => "Succeeded" \in job[job[c].parent].hs
\* @req SCN-114 SCN-119 (REQ-179 notes)  a continuation fires at most once.
Scn_FireOnce == \A c \in Jobs : job[c].fires <= 1

\* positive scenario traps (expected VIOLATED)
\* @req SCN-108
Scn108_NotReached == ~\E c \in Jobs : job[c].cond = "OnFailure" /\ job[c].status = "Enqueued"
                         /\ job[job[c].parent].status = "DeadLettered"
\* @req SCN-114
Scn114_NotReached == ~\E c \in Jobs, bt \in Batches : job[c].cbatch = bt /\ job[c].cond = "OnBatchSucceeded"
                         /\ job[c].status = "Enqueued" /\ job[c].fires = 1 /\ batch[bt].status = "Succeeded"
                         /\ ~batch[bt].wasCompleted
\* @req SCN-118
Scn118_NotReached == ~\E c \in Jobs : job[c].cond = "OnCompletion" /\ job[c].status = "Cancelled"
                         /\ job[c].fires = 0 /\ job[job[c].parent].status = "Cancelled"
\* @req SCN-119
Scn119_NotReached == ~\E c \in Jobs, bt \in Batches : job[c].cbatch = bt /\ job[c].cond = "OnBatchSucceeded"
                         /\ job[c].status = "Enqueued" /\ job[c].fires = 1 /\ batch[bt].status = "Succeeded"
                         /\ batch[bt].wasCompleted

\* @req SCN-121  positive: requeuing a dead-lettered chain step revives the chain (expected VIOLATED).
Scn121_NotReached == ~\E c \in Jobs : job[c].cond = "OnSuccess" /\ job[c].status = "Enqueued" /\ job[c].parent # NULL
                         /\ job[job[c].parent].status = "Succeeded" /\ "DeadLettered" \in job[job[c].parent].hs
\* @req SCN-123 INV-138  negative: no continuation can be added to a parent that does not exist.
Scn123_MissingParentRejected ==
  \A c, p \in Jobs, cond \in JobConds : job[p].status \in {"none", "removed"} => ~ENABLED AddContinuation(c, p, cond)

\* Run 2 probe: a continuation added to a finished parent is stored as awaiting.  Run 3: REQ-175 now allows
\* this when none of REQ-171..174 applies, so a violation is the allowed case, not a finding.
Gap_LateContinuationAwaits == ~\E c \in Jobs : job[c].late /\ job[c].status = "Awaiting"

\* @req REQ-175 REQ-171 REQ-172 REQ-173 REQ-174  (run 3) a continuation whose parent has finished is awaiting
\*        only when none of REQ-171..174 applies: the parent is dead-lettered and the condition is OnSuccess.
Inv_AwaitingOnlyWhenNoRule ==
  \A c \in Jobs : (job[c].status = "Awaiting" /\ job[c].parent # NULL /\ job[job[c].parent].status \in Finished)
                  => (job[job[c].parent].status = "DeadLettered" /\ ~Matches(job[c].cond, "DeadLettered"))

\* @req REQ-192  (run 3) a Completed batch whose members nobody requeues is eventually removed (A-6 reading).
Liv_CompletedBatchRemoved ==
  \A bt \in Batches : batch[bt].status = "Completed" ~> batch[bt].status \in {"Succeeded", "removed"}

\* Probe (run 3): a job-level continuation of a batch member is cancelled because REQ-192 removed its parent
\* with the batch.  Run 4: required by REQ-188; expected VIOLATED (the required case is reachable).
\* @req REQ-188  (run 4) no continuation is left awaiting a parent or batch that no longer exists.
Inv_NoAwaitingOnRemoved ==
  \A c \in Jobs : job[c].status = "Awaiting" =>
                  /\ (job[c].parent # NULL => job[job[c].parent].status # "removed")
                  /\ (job[c].cbatch # NULL => batch[job[c].cbatch].status # "removed")

Probe_MemberContinuationRemoved ==
  ~\E c \in Jobs : /\ job[c].parent # NULL /\ job[c].status = "Cancelled" /\ job[c].released = "cancel"
                   /\ job[job[c].parent].status = "removed" /\ job[job[c].parent].member # NULL
                   /\ batch[job[job[c].parent].member].status = "removed"
                   /\ job[c].cond = "OnSuccess" /\ "Succeeded" \notin job[job[c].parent].hs
                   /\ "Cancelled" \notin job[job[c].parent].hs

\* gap probes (finding evidence; expected VIOLATED)
\* An OnSuccess continuation stays cancelled although its parent was requeued and then succeeded.
\* (run 1 F-9: VIOLATED; run 2: expected to PASS)
Gap_ContinuationLostOnRequeue ==
  ~\E c \in Jobs : job[c].cond = "OnSuccess" /\ job[c].status = "Cancelled" /\ job[c].parent # NULL
                   /\ job[job[c].parent].status = "Succeeded" /\ "DeadLettered" \in job[job[c].parent].hs
\* F-9 path only: the parent was dead-lettered (never cancelled), requeued and succeeded (run 2: expected to PASS).
Gap_DeadLetterRequeueLosesContinuation ==
  ~\E c \in Jobs : job[c].cond = "OnSuccess" /\ job[c].status = "Cancelled" /\ job[c].parent # NULL
                   /\ job[job[c].parent].status = "Succeeded" /\ "DeadLettered" \in job[job[c].parent].hs
                   /\ "Cancelled" \notin job[job[c].parent].hs
\* A Completed batch lost a member to retention while an OnBatchSucceeded continuation still waits.
\* (run 1 F-10: VIOLATED; run 2: expected to PASS when only requeue is used, i.e. no explicit delete)
Gap_BatchUpgradeImpossible ==
  ~\E c \in Jobs, bt \in Batches : job[c].cbatch = bt /\ job[c].status = "Awaiting"
                   /\ batch[bt].status = "Completed" /\ \E m \in Members(bt) : job[m].status = "removed"
=============================================================================
