---------------------------- MODULE Recurring ----------------------------
\* Generated from specs/recurring.json (specHash 90327ae0b99b) — edit the requirements, not this file.
\* Every action/property carries an @req comment naming the requirement it encodes.
\* Entities of other modules (jobs.Job, jobs.Maintenance, hosting.Node) are abstracted to the
\* minimum the recurring requirements talk about; each abstraction is an assumption (A-n) in
\* specs/recurring.findings.md.
EXTENDS Naturals, FiniteSets, Sequences

CONSTANTS Names,            \* RecurringJob instances, keyed by name (entity.bound = 2)
          OccIds,           \* Occurrence slots
          Nodes,            \* hosting.Node instances, all with the worker registered (A-6)
          Releases,         \* code releases a node can run: subset of {"v1", "v2", "v3"}
          DeclV1, DeclV2, DeclV3,  \* names declared in code by release v1 / v2 / v3
          Override,         \* code-defined names marked AllowRuntimeOverride
          MaxQueued,        \* @req REQ-233  MaxQueuedOccurrences (1 by default)
          OverlapPolicies,  \* @req REQ-201  policies explored (default Skip)
          MisfirePolicies,  \* @req REQ-201  policies explored (default RunOnce)
          OrphanPolicies,   \* @req REQ-205, REQ-207  per-job orphanPolicy values explored ("Orphan" or "Delete")
          RerouteOn,        \* explore jobs REQ-125 (Unroutable -> Enqueued)? lets checks separate findings
          NULL

ASSUME MaxQueued \in Nat \ {0}                                              \* @req REQ-233
ASSUME OverlapPolicies \subseteq {"Skip", "Queue", "Allow", "CancelPrevious"}  \* @req REQ-201
ASSUME MisfirePolicies \subseteq {"RunOnce", "Skip", "RunAll"}                 \* @req REQ-201
ASSUME OrphanPolicies \subseteq {"Orphan", "Delete"}
ASSUME RerouteOn \in BOOLEAN
ASSUME Releases \subseteq {"v1", "v2", "v3"} /\ DeclV1 \cup DeclV2 \cup DeclV3 \subseteq Names

VARIABLES rj,     \* stored recurring definitions, keyed by name
          node,   \* hosting.Node abstraction: Down / Running a release
          occ,    \* occurrences
          job,    \* jobs.Job of each occurrence (same slot)
          order,  \* creation order of live occurrences ("earlier occurrence", "oldest first")
          maint,  \* jobs.Maintenance: global maintenance pause on?
          ov, mf, op, \* per-job overlap / misfire / orphan policy, fixed per behaviour (A-9)
          missRec     \* @req REQ-242  missed-instant record kept in the job store, per name: how many records (0, 1,
                      \*              2 = "2 or more"), how the latest one says the instants were handled, and the
                      \*              occurrence it names (A-21)
vars == <<rj, node, occ, job, order, maint, ov, mf, op, missRec>>

RjStatus  == {"none", "Active", "Paused", "Orphaned"}
Defs      == {"none", "d1", "d2", "d3", "rt", "edited"}  \* definition content; dN = code of release vN
OccStatus == {"none", "Waiting", "Started", "Skipped"}
JobStatus == {"none", "Enqueued", "Processing", "Failed", "Succeeded", "DeadLettered", "Cancelled", "Unroutable"}
Finals    == {"Succeeded", "DeadLettered", "Cancelled"}   \* final in the jobs module (an occurrence slot may be archived)
\* @req REQ-239  for overlap decisions a job is finished when Succeeded, DeadLettered, Cancelled or Unroutable.
DoneForOverlap == Finals \cup {"Unroutable"}

Decl(v)    == CASE v = "v1" -> DeclV1 [] v = "v2" -> DeclV2 [] OTHER -> DeclV3
CodeDef(v) == CASE v = "v1" -> "d1" [] v = "v2" -> "d2" [] OTHER -> "d3"

\* behind = how many due instants have passed since nextRunAt was last set: 0, 1, or 2 (= "2 or more").
\* This replaces the clock (A-1).
RjRec  == [st: RjStatus, origin: {"code", "runtime", "none"}, before: {"Active", "Paused", "none"},
           hash: Defs, def: Defs, behind: 0..2, miss: {"none", "caughtUp", "dropped"}]
OccRec == [st: OccStatus, rj: Names \cup {NULL}, blk: SUBSET OccIds,
           reason: {"none", "Overlap", "QueueFull", "Paused", "Orphaned", "Removed"}, sched: BOOLEAN]
JobRec == [st: JobStatus, zombie: BOOLEAN, cancelReq: BOOLEAN]
\* @req REQ-242  how: the created occurrence started / is waiting / was skipped by the overlap policy, or the
\*              misfire policy ("Misfire") or a schedule change ("Schedule") dropped the instants.
MissHow == {"none", "Started", "Waiting", "Skipped", "Misfire", "Schedule"}
MissRec == [n: 0..2, how: MissHow, occ: OccIds \cup {NULL}]

TypeInv ==
  /\ rj    \in [Names -> RjRec]
  /\ node  \in [Nodes -> [st: {"Down", "Running"}, ver: Releases]]
  /\ occ   \in [OccIds -> OccRec]
  /\ job   \in [OccIds -> JobRec]
  /\ order \in Seq(OccIds) /\ Len(order) <= Cardinality(OccIds)
  /\ maint \in BOOLEAN
  /\ ov \in [Names -> OverlapPolicies] /\ mf \in [Names -> MisfirePolicies] /\ op \in [Names -> OrphanPolicies]
  /\ missRec \in [Names -> MissRec]

NoRj   == [st |-> "none", origin |-> "none", before |-> "none", hash |-> "none", def |-> "none", behind |-> 0, miss |-> "none"]
NoOcc  == [st |-> "none", rj |-> NULL, blk |-> {}, reason |-> "none", sched |-> FALSE]
NoJob  == [st |-> "none", zombie |-> FALSE, cancelReq |-> FALSE]
EnqJob == [st |-> "Enqueued", zombie |-> FALSE, cancelReq |-> FALSE]
NoMiss == [n |-> 0, how |-> "none", occ |-> NULL]

Live          == {o \in OccIds : occ[o].st # "none"}
OfJob(r)      == {o \in Live : occ[o].rj = r}
Finished(o)   == job[o].st \in Finals
Unfinished(o) == occ[o].st = "Started" /\ job[o].st \notin DoneForOverlap     \* @req REQ-239
Blocking(r)   == {o \in OfJob(r) : Unfinished(o)}
WaitingOf(r)  == {o \in OfJob(r) : occ[o].st = "Waiting"}
InTheWay(r)   == Blocking(r) \cup WaitingOf(r)   \* "an earlier occurrence ... is waiting or has an unfinished job"
FreeSlots     == {o \in OccIds : occ[o].st = "none"}
Pos(o)        == CHOOSE i \in 1..Len(order) : order[i] = o
RunningNodes  == {n \in Nodes : node[n].st = "Running"}
Declared(r)   == \E n \in RunningNodes : r \in Decl(node[n].ver)
SchedulerRuns == RunningNodes # {}        \* hosting REQ-40: background duties run on worker nodes only

Init ==
  /\ rj    = [r \in Names  |-> NoRj]
  /\ node  = [n \in Nodes  |-> [st |-> "Down", ver |-> CHOOSE v \in Releases : TRUE]]
  /\ occ   = [o \in OccIds |-> NoOcc]
  /\ job   = [o \in OccIds |-> NoJob]
  /\ order = <<>>
  /\ maint = FALSE
  /\ ov \in [Names -> OverlapPolicies] /\ mf \in [Names -> MisfirePolicies] /\ op \in [Names -> OrphanPolicies]
  /\ missRec = [r \in Names |-> NoMiss]

-----------------------------------------------------------------------------
\* Creating an occurrence and deciding it by the overlap policy: one event, five requirements.
\* @req REQ-221, REQ-222, REQ-223, REQ-225, REQ-235
\* "In the way" = an earlier occurrence that is waiting or has an unfinished job (REQ-239).
\* Every live occurrence is earlier than the one being created (it is appended to order).
\* @req REQ-240  an occurrence starts while an earlier occurrence of the same recurring job has an
\*              Unroutable job: that job is cancelled (reason Superseded, not modeled) in the same write.
\* Applied to every start (REQ-221, REQ-224 and REQ-225): the sentence says "an occurrence ... starts"
\* (A-18). E = the earlier occurrences of the same recurring job.
Superseded(x, E) == x \in E /\ job[x].st = "Unroutable"
StartJob(o, E) ==
  job' = [x \in OccIds |-> IF x = o THEN EnqJob
                           ELSE IF Superseded(x, E) THEN [job[x] EXCEPT !.st = "Cancelled"]
                           ELSE job[x]]
Decide(o, r, sched) ==
  LET B == InTheWay(r)
      mk(st, blk, reason) == [st |-> st, rj |-> r, blk |-> blk, reason |-> reason, sched |-> sched]
  IN /\ order' = Append(order, o)
     /\ IF B = {} THEN                                                   \* @req REQ-221
          /\ occ' = [occ EXCEPT ![o] = mk("Started", {}, "none")]
          /\ StartJob(o, OfJob(r))                                     \* @req REQ-240
        ELSE CASE ov[r] = "Skip" ->                                      \* @req REQ-222
                    /\ occ' = [occ EXCEPT ![o] = mk("Skipped", {}, "Overlap")] /\ UNCHANGED job
               [] ov[r] = "Queue" /\ Cardinality(WaitingOf(r)) < MaxQueued ->   \* @req REQ-223
                    \* blk stays {}: REQ-224 now reads the creation order, not who blocked it (smaller state space)
                    /\ occ' = [occ EXCEPT ![o] = mk("Waiting", {}, "none")] /\ UNCHANGED job
               [] ov[r] = "Queue" ->                                     \* @req REQ-235
                    /\ occ' = [occ EXCEPT ![o] = mk("Skipped", {}, "QueueFull")] /\ UNCHANGED job
               [] ov[r] = "Allow" ->                                     \* @req REQ-225
                    /\ occ' = [occ EXCEPT ![o] = mk("Started", {}, "none")]
                    /\ StartJob(o, OfJob(r))                            \* @req REQ-240 (A-18)
               [] ov[r] = "CancelPrevious" ->                            \* @req REQ-225 (+ jobs REQ-134/135)
                    /\ occ' = [occ EXCEPT ![o] = mk("Started", {}, "none")]
                    /\ job' = [x \in OccIds |->
                                 IF x = o THEN EnqJob
                                 ELSE IF x \in B
                                   THEN IF job[x].st = "Processing"
                                          THEN [job[x] EXCEPT !.cancelReq = TRUE]
                                          ELSE [job[x] EXCEPT !.st = "Cancelled"]
                                 ELSE IF Superseded(x, OfJob(r))                \* @req REQ-240 (A-18)
                                   THEN [job[x] EXCEPT !.st = "Cancelled"]
                                 ELSE job[x]]

\* @req REQ-216  Active, maintenance off, nextRunAt passed: one compare-and-set advances nextRunAt
\*              and creates what the misfire policy calls for.
\* @req REQ-217, REQ-218, REQ-219, INV-207, REQ-234  misfire handling; REQ-220 recorded in .miss.
\* @req REQ-242  when one or more instants were missed, the same CAS writes one missed-instant record:
\*              how the instants were handled (the created occurrence's start / wait / overlap skip, or
\*              dropped by the misfire policy) and which occurrence; first/last/how many abstracted (A-21).
\* @req INV-201, INV-210  guarded by Active and ~maint.
\* The CAS makes the whole step atomic (A-2); RunAll(max) is abstracted to max = 1 (A-4);
\* at most one occurrence per trigger (A-5).
NewRec(r, how, o) == [n |-> IF missRec[r].n < 2 THEN missRec[r].n + 1 ELSE 2, how |-> how, occ |-> o]  \* @req REQ-242
Recorded(r, how, o) == [missRec EXCEPT ![r] = NewRec(r, how, o)]                                         \* @req REQ-242
Trigger(r) ==
  /\ SchedulerRuns
  /\ rj[r].st = "Active" /\ ~maint /\ rj[r].behind >= 1
  \* The most recent due instant is judged on its own (INV-207); with behind = 2 at least one
  \* older instant was passed over and is missed (A-3).
  /\ \E newestLate \in BOOLEAN :                      \* newest instant later than MisfireThreshold?
       LET olderMissed == rj[r].behind = 2
           missed      == olderMissed \/ newestLate
       IN IF mf[r] = "Skip" /\ newestLate
            THEN /\ rj' = [rj EXCEPT ![r].behind = 0, ![r].miss = "dropped"]   \* @req REQ-218
                 /\ missRec' = Recorded(r, "Misfire", NULL)                   \* @req REQ-242
                 /\ UNCHANGED <<occ, job, order>>
            ELSE /\ rj' = [rj EXCEPT ![r].behind = 0,
                                     ![r].miss = IF ~missed THEN "none"
                                                 ELSE IF mf[r] = "Skip" THEN "dropped"  \* @req REQ-218: older ones dropped, on-time newest created
                                                 ELSE "caughtUp"]                       \* @req REQ-217, REQ-219 (max = 1, A-4)
                 /\ \E o \in FreeSlots :
                      /\ Decide(o, r, TRUE)                                    \* @req REQ-217, INV-207
                      /\ missRec' = IF ~missed THEN missRec                      \* @req REQ-242
                                    ELSE IF mf[r] = "Skip" THEN Recorded(r, "Misfire", NULL)
                                    ELSE Recorded(r, occ'[o].st, o)               \* Started / Waiting / Skipped
  /\ UNCHANGED <<node, maint, ov, mf, op>>

\* @req REQ-226  Trigger now: any stored job (also paused/orphaned), decided by the overlap policy,
\*              nextRunAt unchanged.
TriggerNow(r) ==
  /\ rj[r].st # "none"
  /\ \E o \in FreeSlots : Decide(o, r, FALSE)
  /\ UNCHANGED <<rj, node, maint, ov, mf, op, missRec>>

\* @req REQ-224  While an occurrence is waiting, when no earlier occurrence of the same recurring job
\*              is waiting or has an unfinished job (REQ-239): enqueue its job, record it started.
\*              Runs as its own step after the earlier job finished (A-7).
\* @req REQ-240  earlier Unroutable jobs of the same recurring job are cancelled in the same step.
StartWaiting(o) ==
  /\ occ[o].st = "Waiting"
  /\ \A x \in InTheWay(occ[o].rj) : Pos(x) >= Pos(o)
  /\ occ' = [occ EXCEPT ![o].st = "Started", ![o].blk = {}]
  /\ StartJob(o, {x \in OfJob(occ[o].rj) : Pos(x) < Pos(o)})
  /\ UNCHANGED <<rj, node, order, maint, ov, mf, op, missRec>>

-----------------------------------------------------------------------------
\* Definitions and reconciliation

\* @req REQ-242  a schedule change (REQ-227, applied by REQ-204, REQ-241 or REQ-212) that moves an *active*
\*              job's nextRunAt past missed instants writes a record "dropped by the schedule change" in the
\*              same write. behind = 2: the older instants are missed (A-3). behind = 1: REQ-234 defines
\*              "missed" only for a trigger, so whether an instant passed but not yet triggered counts as
\*              missed at a schedule change is a nondeterministic choice (A-25).
SchedDropsMissed(r, late) == rj[r].st = "Active" /\ (rj[r].behind = 2 \/ (rj[r].behind = 1 /\ late))
SchedRec(r, changed, late) ==                                                  \* @req REQ-242
  IF changed /\ SchedDropsMissed(r, late) THEN NewRec(r, "Schedule", NULL) ELSE missRec[r]

\* @req REQ-203  node start: create a missing code-defined job (Active, nextRunAt from now).
\* @req REQ-204  node start: a stored *code-defined* job whose code definition changed vs its
\*              definitionHash -> update, keep Active/Paused; if the schedule changed (nondeterministic,
\*              the content is abstract), nextRunAt from now (REQ-227).
\* @req REQ-236  guard: a node whose release declares the name of a stored runtime-defined job does
\*              not start (it goes to StartupFailed, abstracted as staying Down, A-16). Judged by the
\*              stored name and origin only; a store with no Bellhop schema stores none (Init: every name
\*              "none"), so the first start on a new database is never refused.
\* REQ-203 and REQ-204 happen in the one start step for every name the release declares (A-8).
NodeStart(n, v) ==
  /\ node[n].st = "Down" /\ v \in Releases
  /\ \A r \in Decl(v) : rj[r].origin # "runtime"                       \* @req REQ-236
  /\ node' = [node EXCEPT ![n] = [st |-> "Running", ver |-> v]]
  /\ \E schedChanged \in [Names -> BOOLEAN], late \in [Names -> BOOLEAN] :
       LET reapply(r) == r \in Decl(v) /\ rj[r].st \in {"Active", "Paused"} /\ rj[r].origin = "code"
                         /\ rj[r].hash # CodeDef(v)
       IN /\ rj' = [r \in Names |->
                IF r \notin Decl(v) THEN rj[r]
                ELSE IF rj[r].st = "none"
                  THEN [NoRj EXCEPT !.st = "Active", !.origin = "code", !.hash = CodeDef(v), !.def = CodeDef(v)]
                ELSE IF reapply(r)
                  THEN [rj[r] EXCEPT !.hash = CodeDef(v), !.def = CodeDef(v),
                                     !.behind = IF schedChanged[r] THEN 0 ELSE rj[r].behind]
                ELSE rj[r]]
          /\ missRec' = [r \in Names |-> IF reapply(r) THEN SchedRec(r, schedChanged[r], late[r])   \* @req REQ-242
                                                       ELSE missRec[r]]
  /\ UNCHANGED <<occ, job, order, maint, ov, mf, op>>

\* modeling artefact: a node stops or crashes (hosting module).
NodeStop(n) ==
  /\ node[n].st = "Running"
  /\ node' = [node EXCEPT ![n].st = "Down"]
  /\ UNCHANGED <<rj, occ, job, order, maint, ov, mf, op, missRec>>

\* @req REQ-237  pausing, orphaning or removing a job records its waiting occurrences as skipped
\*              with reason Paused / Orphaned / Removed, in the same step (one event).
SkipWaiting(r, why) ==
  occ' = [o \in OccIds |-> IF o \in WaitingOf(r)
                             THEN [occ[o] EXCEPT !.st = "Skipped", !.reason = why, !.blk = {}]
                             ELSE occ[o]]

\* @req REQ-205  no running worker node declares a stored code-defined job, orphanPolicy Orphan:
\*              record its state, mark it orphaned (which pauses it).
\* @req REQ-207  same event, orphanPolicy Delete: remove the definition.
\* @req REQ-237  its waiting occurrences are skipped (Orphaned / Removed).
Orphan(r) ==
  /\ SchedulerRuns
  /\ rj[r].st \in {"Active", "Paused"} /\ rj[r].origin = "code"
  /\ ~Declared(r)
  /\ IF op[r] = "Orphan"
       THEN rj' = [rj EXCEPT ![r].before = rj[r].st, ![r].st = "Orphaned"] /\ SkipWaiting(r, "Orphaned")
       ELSE rj' = [rj EXCEPT ![r] = NoRj] /\ SkipWaiting(r, "Removed")
  /\ UNCHANGED <<node, job, order, maint, ov, mf, op, missRec>>

\* @req REQ-206  a running worker node declares an orphaned job again: back to its earlier state,
\*              definition and definitionHash from that node's code, nextRunAt from now.
Restore(r) ==
  /\ rj[r].st = "Orphaned"
  /\ \E n \in RunningNodes :
       /\ r \in Decl(node[n].ver)
       /\ rj' = [rj EXCEPT ![r].st = rj[r].before, ![r].before = "none", ![r].behind = 0,
                           ![r].hash = CodeDef(node[n].ver), ![r].def = CodeDef(node[n].ver)]
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op, missRec>>

\* @req REQ-241  the scheduler finds a stored code-defined job (Active or Paused) that running worker
\*              nodes declare but whose definitionHash matches the code of none of them: take the code
\*              definition of one of them, keep Active/Paused; if the schedule changed (nondeterministic,
\*              as in REQ-204), nextRunAt from now (REQ-227). Nodes publish name + hash (A-6: instantly).
DeclaringNodes(r) == {n \in RunningNodes : r \in Decl(node[n].ver)}
Stale(r) ==
  /\ rj[r].st \in {"Active", "Paused"} /\ rj[r].origin = "code"
  /\ DeclaringNodes(r) # {}
  /\ \A n \in DeclaringNodes(r) : rj[r].hash # CodeDef(node[n].ver)
ReapplyCode(r) ==
  /\ SchedulerRuns
  /\ Stale(r)
  /\ \E n \in DeclaringNodes(r), schedChanged \in BOOLEAN, late \in BOOLEAN :
       /\ rj' = [rj EXCEPT ![r].hash = CodeDef(node[n].ver), ![r].def = CodeDef(node[n].ver),
                           ![r].behind = IF schedChanged THEN 0 ELSE rj[r].behind]
       /\ missRec' = [missRec EXCEPT ![r] = SchedRec(r, schedChanged, late)]   \* @req REQ-242
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op>>

\* @req REQ-208  operator adds a runtime job when no definition with its name exists.
\* @req INV-211  a name that is already stored is rejected (guard), whatever its origin.
OperatorAdd(r) ==
  /\ rj[r].st = "none"
  /\ rj' = [rj EXCEPT ![r] = [NoRj EXCEPT !.st = "Active", !.origin = "runtime", !.def = "rt"]]
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op, missRec>>

CanEdit(r) == rj[r].origin = "runtime" \/ (rj[r].origin = "code" /\ r \in Override)

\* @req REQ-212  operator updates a runtime job, or a code job with AllowRuntimeOverride.
\* @req REQ-211  otherwise the edit is rejected (guard CanEdit).
\* @req REQ-227  if the schedule changed: nextRunAt from now, no catch-up.
OperatorUpdate(r) ==
  /\ rj[r].st \in {"Active", "Paused"} /\ CanEdit(r)
  /\ \E scheduleChanged \in BOOLEAN, late \in BOOLEAN :
       /\ rj' = [rj EXCEPT ![r].def = "edited",
                           ![r].behind = IF scheduleChanged THEN 0 ELSE rj[r].behind]
       /\ missRec' = [missRec EXCEPT ![r] = SchedRec(r, scheduleChanged, late)]   \* @req REQ-242
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op>>

\* @req REQ-213  operator removes a runtime job, or an orphaned one of any origin.
\* @req INV-206  a code job that is not orphaned is refused (guard).
\* @req REQ-237  waiting occurrences skipped with reason Removed.
OperatorRemove(r) ==
  /\ (rj[r].st # "none" /\ rj[r].origin = "runtime") \/ rj[r].st = "Orphaned"
  /\ rj' = [rj EXCEPT ![r] = NoRj]
  /\ SkipWaiting(r, "Removed")
  /\ UNCHANGED <<node, job, order, maint, ov, mf, op, missRec>>

\* @req REQ-214
\* @req REQ-237  waiting occurrences skipped with reason Paused.
Pause(r) ==
  /\ rj[r].st = "Active"
  /\ rj' = [rj EXCEPT ![r].st = "Paused"]
  /\ SkipWaiting(r, "Paused")
  /\ UNCHANGED <<node, job, order, maint, ov, mf, op, missRec>>

\* @req REQ-215  resume: Active, nextRunAt from now.
Resume(r) ==
  /\ rj[r].st = "Paused"
  /\ rj' = [rj EXCEPT ![r].st = "Active", ![r].behind = 0]
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op, missRec>>

\* modeling artefact A-1: a due instant of a stored job passes (no clock).
TimePasses(r) ==
  /\ rj[r].st # "none" /\ rj[r].behind < 2
  /\ rj' = [rj EXCEPT ![r].behind = rj[r].behind + 1]
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op, missRec>>

\* jobs REQ-162, REQ-163 (other module): operator toggles maintenance.
ToggleMaintenance ==
  /\ maint' = ~maint
  /\ UNCHANGED <<rj, node, occ, job, order, ov, mf, op, missRec>>

-----------------------------------------------------------------------------
\* jobs.Job abstraction (A-10): only what "unfinished" and "processing" need.
JobStep(o, new) == job' = [job EXCEPT ![o] = new] /\ UNCHANGED <<rj, node, occ, order, maint, ov, mf, op, missRec>>

\* jobs REQ-123, INV-114: claim needs a running worker and maintenance off.
Claim(o)    == /\ job[o].st = "Enqueued" /\ ~maint /\ SchedulerRuns
               /\ JobStep(o, [job[o] EXCEPT !.st = "Processing"])
\* jobs REQ-127, REQ-129, REQ-131, REQ-136: handler returns / throws / honours cancellation.
Complete(o) == /\ job[o].st = "Processing"
               /\ \E s \in {"Succeeded", "Failed", "DeadLettered"} \cup (IF job[o].cancelReq THEN {"Cancelled"} ELSE {}) :
                    JobStep(o, [job[o] EXCEPT !.st = s])
\* jobs REQ-130
RetryDue(o) == /\ job[o].st = "Failed" /\ JobStep(o, [job[o] EXCEPT !.st = "Enqueued"])
\* jobs REQ-132 (at-least-once window, jobs REQ-10): lease expires while the handler still runs.
LeaseLost(o) == /\ job[o].st = "Processing" /\ ~job[o].zombie
                /\ JobStep(o, [job[o] EXCEPT !.st = "Enqueued", !.zombie = TRUE])
\* jobs REQ-138, REQ-186: timeout, handler abandoned while still running.
AbandonOnTimeout(o) == /\ job[o].st = "Processing" /\ ~job[o].zombie
                       /\ \E s \in {"Failed", "DeadLettered"} : JobStep(o, [job[o] EXCEPT !.st = s, !.zombie = TRUE])
\* the abandoned / lease-lost handler finally returns (its write is refused, jobs INV-128).
ZombieEnds(o) == /\ job[o].zombie /\ JobStep(o, [job[o] EXCEPT !.zombie = FALSE])
\* jobs REQ-124: no running worker lists a handler for it.
BecomeUnroutable(o) == /\ job[o].st = "Enqueued" /\ JobStep(o, [job[o] EXCEPT !.st = "Unroutable"])
\* jobs REQ-125: a running worker node registers a handler for it -> back to Enqueued. Unroutable is not
\* final in the jobs module, so an Unroutable occurrence job is never archived (A-11).
Reroute(o) == /\ RerouteOn /\ job[o].st = "Unroutable" /\ SchedulerRuns
              /\ JobStep(o, [job[o] EXCEPT !.st = "Enqueued"])

\* modeling artefact A-11: finished occurrences free their slot (not while a waiting one refers to them).
Archive(o) ==
  /\ \/ occ[o].st = "Skipped"
     \/ occ[o].st = "Started" /\ Finished(o) /\ ~job[o].zombie
  /\ \A w \in OccIds : o \notin occ[w].blk
  /\ occ'   = [occ EXCEPT ![o] = NoOcc]
  /\ job'   = [job EXCEPT ![o] = NoJob]
  /\ order' = SelectSeq(order, LAMBDA x : x # o)
  /\ UNCHANGED <<rj, node, maint, ov, mf, op, missRec>>

Next ==
  \/ \E r \in Names : \/ Trigger(r) \/ TriggerNow(r) \/ Orphan(r) \/ Restore(r) \/ OperatorAdd(r)
                      \/ OperatorUpdate(r) \/ OperatorRemove(r) \/ Pause(r) \/ Resume(r) \/ TimePasses(r)
                      \/ ReapplyCode(r)
  \/ \E n \in Nodes : NodeStop(n) \/ \E v \in Releases : NodeStart(n, v)
  \/ \E o \in OccIds : \/ StartWaiting(o) \/ Claim(o) \/ Complete(o) \/ RetryDue(o) \/ LeaseLost(o)
                       \/ AbandonOnTimeout(o) \/ ZombieEnds(o) \/ BecomeUnroutable(o) \/ Reroute(o)
                       \/ Archive(o)
  \/ ToggleMaintenance

\* Only actor: system transitions are fair.
Fairness == /\ \A r \in Names : WF_vars(Trigger(r)) /\ WF_vars(Orphan(r)) /\ WF_vars(ReapplyCode(r))
            /\ \A o \in OccIds : WF_vars(StartWaiting(o))

Spec == Init /\ [][Next]_vars /\ Fairness

\* A-22: missRec is written only by Trigger and the schedule-change steps (REQ-242) and read by no guard or
\* other update, so states that differ only in missRec have the same futures. Checks that do not mention missRec may use this VIEW (the 3-slot Queue cfgs).
ViewNoRec == <<rj, node, occ, job, order, maint, ov, mf, op>>

-----------------------------------------------------------------------------
\* Properties

\* @req INV-201  paused or orphaned: never an occurrence on schedule.  (also SCN-202)
Inv_NoScheduleWhilePaused ==
  \A r \in Names : rj[r].st \in {"Paused", "Orphaned"} => ~ENABLED Trigger(r)

\* @req INV-210  maintenance on: never an occurrence on schedule ...
Inv_NoScheduleInMaintenance == maint => \A r \in Names : ~ENABLED Trigger(r)

\* @req INV-210  ... and no scheduled trigger advances nextRunAt while maintenance is on. Operator and
\*              reconciliation actions (REQ-204, REQ-206, REQ-215, REQ-227) keep their own "from now" rules.
Prop_NoScheduledAdvanceInMaintenance ==
  [][maint => \A r \in Names : ~Trigger(r)]_vars

\* Not a requirement: REQ-238 (info) accepts that an abandoned or lease-lost handler can still run beside
\* the next occurrence's job. Kept to show the accepted window is real (expected VIOLATED).
Executing(o) == job[o].st = "Processing" \/ job[o].zombie
Inv_NoOverlapRunning ==
  \A r \in Names : ov[r] \in {"Skip", "Queue"} => Cardinality({o \in OfJob(r) : Executing(o)}) <= 1

\* @req INV-204  Skip/Queue: never two of its occurrences' jobs in the Processing state at the same time.
Inv_NoOverlapProcessing ==
  \A r \in Names : ov[r] \in {"Skip", "Queue"} => Cardinality({o \in OfJob(r) : job[o].st = "Processing"}) <= 1

\* @req REQ-233  never more than MaxQueuedOccurrences waiting.
Inv_MaxQueued == \A r \in Names : Cardinality(WaitingOf(r)) <= MaxQueued

\* @req REQ-211, SCN-205  a code job without AllowRuntimeOverride cannot be edited.
Scn_CodeJobNotEditable ==
  \A r \in Names : rj[r].origin = "code" /\ r \notin Override => ~ENABLED OperatorUpdate(r)

\* @req INV-206, SCN-212  a code job that is not orphaned cannot be removed.
Scn_CodeJobNotRemovable ==
  \A r \in Names : rj[r].origin = "code" /\ rj[r].st # "Orphaned" => ~ENABLED OperatorRemove(r)

\* @req SCN-208  never orphan a job some running node still declares.
Scn_NoOrphanWhileDeclared == \A r \in Names : Declared(r) => ~ENABLED Orphan(r)

\* @req SCN-200, INV-203  once the CAS advanced nextRunAt past now, the old instant cannot fire again.
Scn_SecondCasImpossible == \A r \in Names : rj[r].st # "none" /\ rj[r].behind = 0 => ~ENABLED Trigger(r)

\* @req INV-211, SCN-214  a name that is already stored cannot be added again (impossibleAt: 1).
Scn_StoredNameCannotBeAdded == \A r \in Names : rj[r].st # "none" => ~ENABLED OperatorAdd(r)

\* @req REQ-236  a release that declares the name of a stored runtime-defined job never starts.
Scn_RuntimeNameBlocksStart ==
  \A n \in Nodes, v \in Releases : (\E r \in Decl(v) : rj[r].origin = "runtime") => ~ENABLED NodeStart(n, v)

\* @req REQ-237  pausing, orphaning or removing a job leaves none of its occurrences waiting.
Prop_PauseOrphanRemoveSkipsWaiting ==
  [][\A r \in Names : rj[r].st # rj'[r].st /\ rj'[r].st \in {"Paused", "Orphaned", "none"}
        => \A o \in OccIds : ~(occ'[o].rj = r /\ occ'[o].st = "Waiting")]_vars

\* @req REQ-239, REQ-222, REQ-235  an occurrence is skipped for overlap only while an earlier one of the
\*              same job is waiting or has an unfinished job (an Unroutable job is not in the way).
Prop_SkipOnlyWhenInTheWay ==
  [][\A o \in OccIds : occ[o].st = "none" /\ occ'[o].st = "Skipped" /\ occ'[o].reason \in {"Overlap", "QueueFull"}
        => \E x \in OccIds \ {o} : occ[x].rj = occ'[o].rj
                                   /\ (occ[x].st = "Waiting" \/ (occ[x].st = "Started" /\ job[x].st \notin DoneForOverlap))]_vars

\* @req REQ-241  settling (the REQ-241 / REQ-204 notes): a stored code definition that matches no running
\*              declaring node eventually matches one again, under weak fairness of the scheduler.
Liv_DefinitionSettles == \A r \in Names : Stale(r) ~> ~Stale(r)

\* @req REQ-241  ... and once it matches, only a node stopping can make it stale again, so it stays settled
\*              once the set of running nodes stops changing.
Prop_StaleOnlyWhenNodeStops ==
  [][\A r \in Names : ~Stale(r) /\ Stale(r)' => \E n \in Nodes : node[n].st = "Running" /\ node'[n].st = "Down"]_vars

\* A step that moves nextRunAt by a schedule change (REQ-227 via REQ-204, REQ-241 or REQ-212).
ScheduleChange(r) == OperatorUpdate(r) \/ ReapplyCode(r) \/ \E n \in Nodes, v \in Releases : NodeStart(n, v)
MissedTrigger(r) == Trigger(r) /\ rj'[r].miss # "none"

\* @req REQ-242  a missed-instant record is written only when an active job's nextRunAt is moved past
\*              missed instants: by a trigger that missed at least one, or by a schedule change (never by
\*              trigger-now, resume, restore, pause, orphaning, or a trigger with nothing missed) ...
Prop_MissRecordOnlyByMove ==
  [][\A r \in Names : missRec'[r] # missRec[r] =>
        \/ MissedTrigger(r)
        \/ rj[r].st = "Active" /\ rj[r].behind >= 1 /\ rj'[r].behind = 0 /\ ScheduleChange(r)]_vars

\* @req REQ-242  ... and every such move writes exactly one record, in the same step, whatever the misfire
\*              policy: every trigger that missed something, and every step that takes an active job with
\*              missed instants (behind = 2, A-3) to nextRunAt-from-now while it stays active (run-4 F-1).
Prop_MissedMoveRecordsOnce ==
  [][\A r \in Names :
        (\/ MissedTrigger(r)
         \/ rj[r].st = "Active" /\ rj[r].behind = 2 /\ rj'[r].st = "Active" /\ rj'[r].behind = 0)
        => missRec'[r].n = (IF missRec[r].n < 2 THEN missRec[r].n + 1 ELSE 2) /\ missRec'[r].how # "none"]_vars

\* @req REQ-242  the record says how the instants were handled: a RunOnce / RunAll catch-up names the
\*              occurrence created in that step and whether it started, is waiting or was skipped by the
\*              overlap policy (run-4 F-2); Skip names the misfire policy; a schedule change names itself.
Prop_RecordSaysOutcome ==
  [][\A r \in Names : missRec'[r] # missRec[r] =>
        CASE missRec'[r].how \in {"Started", "Waiting", "Skipped"} ->
               /\ MissedTrigger(r) /\ mf[r] # "Skip" /\ missRec'[r].occ # NULL
               /\ occ[missRec'[r].occ].st = "none" /\ occ'[missRec'[r].occ].st = missRec'[r].how
               /\ occ'[missRec'[r].occ].rj = r /\ occ'[missRec'[r].occ].sched
          [] missRec'[r].how = "Misfire"  -> MissedTrigger(r) /\ mf[r] = "Skip"
          [] missRec'[r].how = "Schedule" -> ScheduleChange(r)
          [] OTHER -> FALSE]_vars

\* Not a requirement: REQ-240's notes say "a recurring job never holds more than one Unroutable job". Checked
\* for Skip and Queue, where the notes' reasoning applies (expected to hold) ...
Note240_OneUnroutableSkipQueue ==
  \A r \in Names : ov[r] \in {"Skip", "Queue"} => Cardinality({o \in OfJob(r) : job[o].st = "Unroutable"}) <= 1

-----------------------------------------------------------------------------
\* Positive scenarios: given state as Init, trap invariant expected to be VIOLATED.
J1 == CHOOSE r \in Names : TRUE
CodeRj(st)    == [NoRj EXCEPT !.st = st, !.origin = "code", !.hash = "d1", !.def = "d1"]
RuntimeRj(st) == [NoRj EXCEPT !.st = st, !.origin = "runtime", !.def = "rt"]
BaseInit(r1, nd) ==
  /\ rj = [r \in Names |-> IF r = J1 THEN r1 ELSE NoRj]
  /\ node = nd
  /\ occ = [o \in OccIds |-> NoOcc] /\ job = [o \in OccIds |-> NoJob] /\ order = <<>>
  /\ maint = FALSE
  /\ ov \in [Names -> OverlapPolicies] /\ mf \in [Names -> MisfirePolicies] /\ op \in [Names -> OrphanPolicies]
  /\ missRec = [r \in Names |-> NoMiss]
AllRunning(v) == [n \in Nodes |-> [st |-> "Running", ver |-> v]]
O1 == CHOOSE o \in OccIds : TRUE

\* @req SCN-201  Skip: the 10:00 run is processing at 10:01.
Init_SCN201 ==
  /\ rj = [r \in Names |-> IF r = J1 THEN [RuntimeRj("Active") EXCEPT !.behind = 1] ELSE NoRj]
  /\ node = AllRunning("v1")
  /\ occ = [o \in OccIds |-> IF o = O1 THEN [NoOcc EXCEPT !.st = "Started", !.rj = J1, !.sched = TRUE] ELSE NoOcc]
  /\ job = [o \in OccIds |-> IF o = O1 THEN [EnqJob EXCEPT !.st = "Processing"] ELSE NoJob]
  /\ order = <<O1>> /\ maint = FALSE
  /\ ov \in [Names -> OverlapPolicies] /\ mf \in [Names -> MisfirePolicies] /\ op \in [Names -> OrphanPolicies]
  /\ missRec = [r \in Names |-> NoMiss]
Scn201_NotReached ==
  ~(\E o \in OfJob(J1) : occ[o].st = "Skipped" /\ occ[o].reason = "Overlap"
      /\ job[O1].st = "Processing" /\ {x \in OfJob(J1) : job[x].st # "none"} = {O1})

\* @req SCN-203  schedule change at 09:30 (nothing due), no catch-up.
Init_SCN203 == BaseInit(RuntimeRj("Active"), AllRunning("v1"))
Scn203_NotReached == ~(rj[J1].def = "edited" /\ rj[J1].behind = 0 /\ Live = {})

\* @req SCN-204  weekly-report code-defined, active; the new release no longer declares it.
Init_SCN204 == BaseInit(CodeRj("Active"), AllRunning("v2"))
Scn204_NotReached == ~(rj[J1].st = "Orphaned" /\ Live = {})

\* @req SCN-206  hourly, RunOnce, all nodes down 01:30–05:10 (several instants missed).
Init_SCN206 == BaseInit([RuntimeRj("Active") EXCEPT !.behind = 2], [n \in Nodes |-> [st |-> "Down", ver |-> "v1"]])
Scn206_NotReached ==
  ~(/\ Cardinality(OfJob(J1)) = 1 /\ \E o \in OfJob(J1) : occ[o].st = "Started" /\ occ[o].sched
    /\ rj[J1].miss = "caughtUp" /\ rj[J1].behind = 0)

\* @req SCN-209  weekly-report paused; a release that drops it is on every node, then rolled back.
\* Checked in two legs (a state trap cannot see history): (a) given -> orphaned, remembering Paused;
\* (b) from that orphaned state, the rolled-back release brings it back Paused (only REQ-206 leaves Orphaned).
Init_SCN209 == BaseInit(CodeRj("Paused"), AllRunning("v2"))
Scn209a_NotReached == ~(rj[J1].st = "Orphaned" /\ rj[J1].before = "Paused" /\ Live = {})
Init_SCN209b == BaseInit([CodeRj("Orphaned") EXCEPT !.before = "Paused"], AllRunning("v2"))
Scn209b_NotReached ==
  ~(rj[J1].st = "Paused" /\ rj[J1].before = "none" /\ Live = {} /\ \E n \in RunningNodes : node[n].ver = "v1")

\* @req SCN-210  Queue(max 1): the 10:00 run is processing at 10:02 (10:01 and 10:02 on schedule).
Init_SCN210 == Init_SCN201
Scn210_NotReached ==
  ~(/\ Cardinality(WaitingOf(J1)) = 1 /\ \A w \in WaitingOf(J1) : occ[w].sched
    /\ \E o \in OfJob(J1) : occ[o].st = "Skipped" /\ occ[o].reason = "QueueFull" /\ occ[o].sched
    /\ {x \in OfJob(J1) : job[x].st = "Processing"} = {O1})

\* @req SCN-213  Queue(max 1): the 10:00 job succeeded at 10:01:50, the 10:01 occurrence is still waiting
\*              when the 10:02 trigger runs (given state as Init). 10:02 must be skipped QueueFull and
\*              10:01 must be the only occurrence processing.
O2 == CHOOSE o \in OccIds \ {O1} : TRUE
Init_SCN213 ==
  /\ rj = [r \in Names |-> IF r = J1 THEN [RuntimeRj("Active") EXCEPT !.behind = 1] ELSE NoRj]
  /\ node = AllRunning("v1")
  /\ occ = [o \in OccIds |-> IF o = O1 THEN [NoOcc EXCEPT !.st = "Started", !.rj = J1, !.sched = TRUE]
                             ELSE IF o = O2 THEN [NoOcc EXCEPT !.st = "Waiting", !.rj = J1, !.blk = {O1}, !.sched = TRUE]
                             ELSE NoOcc]
  /\ job = [o \in OccIds |-> IF o = O1 THEN [EnqJob EXCEPT !.st = "Succeeded"] ELSE NoJob]
  /\ order = <<O1, O2>> /\ maint = FALSE
  /\ ov \in [Names -> OverlapPolicies] /\ mf \in [Names -> MisfirePolicies] /\ op \in [Names -> OrphanPolicies]
  /\ missRec = [r \in Names |-> NoMiss]
Scn213_NotReached ==
  ~(/\ occ[O2].st = "Started" /\ job[O2].st = "Processing"
    /\ \E s \in OfJob(J1) : s \notin {O1, O2} /\ occ[s].st = "Skipped" /\ occ[s].reason = "QueueFull" /\ occ[s].sched
    /\ {x \in OfJob(J1) : job[x].st = "Processing"} = {O2})

\* @req SCN-211  Skip misfire; due 03:00:00, first poll 03:00:02 (within MisfireThreshold).
Init_SCN211 == BaseInit([RuntimeRj("Active") EXCEPT !.behind = 1], AllRunning("v1"))
Scn211_NotReached ==
  ~(\E o \in OfJob(J1) : occ[o].st = "Started" /\ occ[o].sched /\ rj[J1].miss = "none" /\ rj[J1].behind = 0)

\* @req SCN-215  sync-crm, overlap Skip; the 10:00 occurrence's job is Unroutable. The 10:06 occurrence
\*              starts (REQ-221, REQ-239) and the 10:00 job is cancelled in the same write (REQ-240).
Init_SCN215 ==
  /\ rj = [r \in Names |-> IF r = J1 THEN [RuntimeRj("Active") EXCEPT !.behind = 1] ELSE NoRj]
  /\ node = AllRunning("v1")
  /\ occ = [o \in OccIds |-> IF o = O1 THEN [NoOcc EXCEPT !.st = "Started", !.rj = J1, !.sched = TRUE] ELSE NoOcc]
  /\ job = [o \in OccIds |-> IF o = O1 THEN [EnqJob EXCEPT !.st = "Unroutable"] ELSE NoJob]
  /\ order = <<O1>> /\ maint = FALSE
  /\ ov \in [Names -> OverlapPolicies] /\ mf \in [Names -> MisfirePolicies] /\ op \in [Names -> OrphanPolicies]
  /\ missRec = [r \in Names |-> NoMiss]
Scn215_NotReached ==
  ~(/\ job[O1].st = "Cancelled"
    /\ \E o \in OfJob(J1) : o # O1 /\ occ[o].st = "Started" /\ occ[o].sched /\ job[o].st = "Enqueued"
    /\ \A x \in OfJob(J1) : job[x].st # "Unroutable")

-----------------------------------------------------------------------------
\* Reachability probes (modeling aids, NOT requirements): each is expected to be violated, and
\* its trace is the example for a finding. Run with the Recurring_P_*.cfg files.

\* F: an orphaned job restored by a newer release keeps the stale stored definition.
Probe_StaleDefinitionAfterRestore ==
  ~(\E r \in Names : rj[r].st \in {"Active", "Paused"} /\ rj[r].origin = "code" /\ RunningNodes # {}
      /\ \A n \in RunningNodes : r \in Decl(node[n].ver) /\ rj[r].hash # CodeDef(node[n].ver))

\* F: a runtime job whose name later appears in code is rewritten by code but stays "runtime".
Probe_RuntimeJobTakenOverByCode ==
  ~(\E r \in Names : rj[r].origin = "runtime" /\ rj[r].hash \in {"d1", "d2", "d3"})

\* F (run 1, F-7): an unroutable occurrence job blocks the next occurrence. Under REQ-239 an occurrence
\* skipped while the earlier job was still Enqueued (before it became Unroutable) also satisfies this
\* state predicate, so the run-2 check of F-7 is Prop_SkipOnlyWhenInTheWay; the probe is kept for history.
Probe_UnroutableBlocksNext ==
  ~(\E o, s \in OccIds : job[o].st = "Unroutable" /\ occ[s].st = "Skipped" /\ occ[s].rj = occ[o].rj)

\* Run 3 (A-18): under Allow or CancelPrevious, a REQ-225 start can meet an earlier Unroutable job (another
\* earlier job unfinished, a slot free for the next occurrence), so whether REQ-240 also covers REQ-225 starts
\* changes behaviour. Reachable = the question is real.
Probe_Req225StartMeetsUnroutable ==
  ~(\E r \in Names, x, y \in OccIds :
      ov[r] \in {"Allow", "CancelPrevious"} /\ x \in OfJob(r) /\ y \in OfJob(r)
      /\ job[x].st = "Unroutable" /\ Unfinished(y) /\ FreeSlots # {})

\* Run 3: a trigger-now occurrence (REQ-226, possibly with an overridden payload) whose job is Unroutable is
\* cancelled by REQ-240 when a scheduled occurrence starts. Action probe, so it goes under PROPERTIES.
ProbeAct_TriggerNowNeverSuperseded ==
  [][\A x \in OccIds :
       ~(/\ occ[x].st = "Started" /\ ~occ[x].sched /\ job[x].st = "Unroutable" /\ job'[x].st = "Cancelled"
         /\ \E o \in OccIds : occ[o].st # "Started" /\ occ'[o].st = "Started" /\ occ'[o].sched)]_vars

\* Run 4: ... and for every policy (probe; reachable = the notes overstate it under Allow / CancelPrevious).
Probe_OneUnroutablePerJob ==
  \A r \in Names : Cardinality({o \in OfJob(r) : job[o].st = "Unroutable"}) <= 1

\* Run 5: instants missed while a job is active (behind = 2, A-3) leave with a REQ-242 record whenever the job
\* stops being active. REQ-242 covers only moves of an *active* job's nextRunAt; a pause (REQ-214) or orphaning
\* (REQ-205/REQ-207) keeps or deletes nextRunAt, and every way back to Active is "from now" (REQ-215, REQ-206)
\* while the job is not active. Reachable = instants missed while active are dropped with no record.
ProbeAct_OverduePausedRecorded ==
  [][\A r \in Names : rj[r].st = "Active" /\ rj[r].behind = 2 /\ rj'[r].st = "Paused"
        => missRec'[r] # missRec[r]]_vars
\* ... the same through the orphan sweep (REQ-205 orphans, REQ-207 deletes), for the outage-then-deploy story.
\* (An operator removing an active runtime job, REQ-213, is a third path; the job is gone, so it is not probed.)
ProbeAct_OverdueOrphanedRecorded ==
  [][\A r \in Names : rj[r].st = "Active" /\ rj[r].behind = 2 /\ Orphan(r)
        => missRec'[r] # missRec[r]]_vars

\* Run 5 (A-25): a due instant of an active job that has passed but was not yet triggered leaves the schedule
\* only by running or by being recorded. Reachable = a schedule change drops an instant within
\* MisfireThreshold with neither an occurrence nor a record.
ProbeAct_PassedInstantRunsOrIsRecorded ==
  [][\A r \in Names : rj[r].st = "Active" /\ rj[r].behind >= 1 /\ rj'[r].st = "Active" /\ rj'[r].behind = 0
        /\ ~Trigger(r) => missRec'[r] # missRec[r]]_vars

\* Run 5: a record that says the catch-up occurrence "is waiting" stays true. Reachable = the recorded waiting
\* occurrence is later skipped (REQ-237) while the record still says waiting.
ProbeAct_RecordedWaiterNeverSkipped ==
  [][\A r \in Names : missRec[r].how = "Waiting" /\ missRec[r].occ # NULL
        => ~(occ[missRec[r].occ].st = "Waiting" /\ occ'[missRec[r].occ].st = "Skipped")]_vars

\* Run 4: the occurrence a RunOnce / RunAll catch-up creates (REQ-217, REQ-219) is never skipped by the overlap
\* policy, so a record that says "caught up" (REQ-242) means a run happened. Reachable = it can be skipped.
ProbeAct_CatchUpNeverSkipped ==
  [][\A r \in Names : (Trigger(r) /\ rj'[r].miss = "caughtUp")
        => \A o \in OccIds : occ[o].st = "none" /\ occ'[o].st # "none" => occ'[o].st # "Skipped"]_vars

\* F: with Queue(max >= 2), a newer waiting occurrence starts while an older one is still unfinished.
Probe_NewerWaiterStartsBesideOlder ==
  ~(\E w, x \in OccIds : occ[w].st = "Waiting" /\ x \in OfJob(occ[w].rj) /\ Unfinished(x)
      /\ Pos(x) < Pos(w) /\ ENABLED StartWaiting(w))
=============================================================================
