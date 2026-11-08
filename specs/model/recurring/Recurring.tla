---------------------------- MODULE Recurring ----------------------------
\* Generated from specs/recurring.json (specHash 0737c73dad59) — edit the requirements, not this file.
\* Run 7 (INV-212): every write that changes a job's state or nextRunAt, or removes it, is written here as a guard
\* (what its read checks) and a ...Write operator (what it lands). This module keeps each as one atomic step (A-2);
\* RecurringRace.tla splits them into a read and a write and checks INV-212's compare-and-set.
\* Run 8: REQ-203 also fires from the scheduler (CreateDeclared, fair); INV-212 also covers definition writes and,
\* for a trigger, maintenance (both only visible in RecurringRace.tla).
\* Run 9: REQ-206's restore is the scheduler's too (actor system), so Restore is weakly fair in Spec. SpecCF_RestoreHost
\* is run 8's reading (REQ-206 not fair), kept as a counterfactual.
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
\*              misfire policy ("Misfire"), a schedule change ("Schedule"), a pause ("Pause"), an orphaning
\*              ("Orphan") or a removal ("Removed", REQ-207 or REQ-213) dropped the instants.
MissHow == {"none", "Started", "Waiting", "Skipped", "Misfire", "Schedule", "Pause", "Orphan", "Removed"}
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

\* @req REQ-216  Active, maintenance off, nextRunAt passed: one compare-and-set as INV-212 describes (state, nextRunAt,
\*              definition, and maintenance off at the write) advances nextRunAt and creates what the misfire policy
\*              calls for.
\* @req REQ-217, REQ-218, REQ-219, INV-207, REQ-234  misfire handling; REQ-220 recorded in .miss.
\* @req REQ-242  when one or more instants were missed, the same CAS writes one missed-instant record:
\*              how the instants were handled (the created occurrence's start / wait / overlap skip, or
\*              dropped by the misfire policy) and which occurrence; first/last/how many abstracted (A-21).
\* @req INV-201, INV-210  guarded by Active and ~maint.
\* Here the read and the CAS are one atomic step (A-2; RecurringRace.tla splits them); RunAll(max) is abstracted
\* to max = 1 (A-4); at most one occurrence per trigger (A-5).
NewRec(r, how, o) == [n |-> IF missRec[r].n < 2 THEN missRec[r].n + 1 ELSE 2, how |-> how, occ |-> o]  \* @req REQ-242
Recorded(r, how, o) == [missRec EXCEPT ![r] = NewRec(r, how, o)]                                         \* @req REQ-242
\* The write of a trigger that found b due instants (b >= 1) and judged the newest late or not.
\* The most recent due instant is judged on its own (INV-207); with b = 2 at least one
\* older instant was passed over and is missed (A-3).
TriggerWrite(r, b, newestLate) ==
  /\ LET olderMissed == b = 2
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
TriggerGuard(r) == SchedulerRuns /\ rj[r].st = "Active" /\ ~maint /\ rj[r].behind >= 1
Trigger(r) ==
  /\ TriggerGuard(r)
  /\ \E newestLate \in BOOLEAN : TriggerWrite(r, rj[r].behind, newestLate)   \* newest later than MisfireThreshold?

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

\* @req REQ-234  an instant that fell due while the job was active and that no trigger reached before nextRunAt
\*              was moved past it or the job stopped being active is missed, however recently it fell due.
\*              While Active, behind counts exactly those instants (every way into Active resets it), so an
\*              active job with behind >= 1 has missed instants at any write other than a trigger (A-25).
HasMissed(r) == rj[r].st = "Active" /\ rj[r].behind >= 1
\* @req REQ-242  a schedule change (REQ-227, applied by REQ-204, REQ-241 or REQ-212) that moves an *active*
\*              job's nextRunAt past missed instants writes a record "dropped by the schedule change" in the
\*              same write.
SchedRec(r, changed) ==                                                        \* @req REQ-242
  IF changed /\ HasMissed(r) THEN NewRec(r, "Schedule", NULL) ELSE missRec[r]
\* @req REQ-242  an active job paused (REQ-214), orphaned (REQ-205) or removed (REQ-207, REQ-213) while it has
\*              missed instants: the record says the pause / orphaning / removal dropped them, in the same write
\*              (PauseWrite, OrphanWrite, RemoveWrite below, called with missed = HasMissed(r)).

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
  /\ \E schedChanged \in [Names -> BOOLEAN] :
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
          /\ missRec' = [r \in Names |-> IF reapply(r) THEN SchedRec(r, schedChanged[r])   \* @req REQ-242
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
\* (the write: before = the state it records, missed = whether it judged missed instants, REQ-242)
OrphanWrite(r, before, missed) ==
  /\ IF op[r] = "Orphan"
       THEN rj' = [rj EXCEPT ![r].before = before, ![r].st = "Orphaned"] /\ SkipWaiting(r, "Orphaned")
            /\ missRec' = IF missed THEN Recorded(r, "Orphan", NULL) ELSE missRec      \* @req REQ-242
       ELSE rj' = [rj EXCEPT ![r] = NoRj] /\ SkipWaiting(r, "Removed")
            /\ missRec' = IF missed THEN Recorded(r, "Removed", NULL) ELSE missRec     \* @req REQ-242
  /\ UNCHANGED <<node, job, order, maint, ov, mf, op>>
OrphanGuard(r) == SchedulerRuns /\ rj[r].st \in {"Active", "Paused"} /\ rj[r].origin = "code" /\ ~Declared(r)
Orphan(r) == OrphanGuard(r) /\ OrphanWrite(r, rj[r].st, HasMissed(r))

\* @req REQ-206  the scheduler finds an orphaned job that a running worker node declares: back to its earlier state,
\*              definition and definitionHash from that node's code, nextRunAt from now. (run 9: actor system, fair. A
\*              declaring running node is a running worker, so the scheduler runs; A-6.)
RestoreWrite(r, st, d) ==
  /\ rj' = [rj EXCEPT ![r].st = st, ![r].before = "none", ![r].behind = 0, ![r].hash = d, ![r].def = d]
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op, missRec>>
Restore(r) ==
  /\ rj[r].st = "Orphaned"
  /\ \E n \in RunningNodes :
       /\ r \in Decl(node[n].ver)
       /\ RestoreWrite(r, rj[r].before, CodeDef(node[n].ver))

\* @req REQ-241  the scheduler finds a stored code-defined job (Active or Paused) that running worker
\*              nodes declare but whose definitionHash matches the code of none of them: take the code
\*              definition of one of them, keep Active/Paused; if the schedule changed (nondeterministic,
\*              as in REQ-204), nextRunAt from now (REQ-227). Nodes publish name + hash (A-6: instantly).
DeclaringNodes(r) == {n \in RunningNodes : r \in Decl(node[n].ver)}
Stale(r) ==
  /\ rj[r].st \in {"Active", "Paused"} /\ rj[r].origin = "code"
  /\ DeclaringNodes(r) # {}
  /\ \A n \in DeclaringNodes(r) : rj[r].hash # CodeDef(node[n].ver)
\* (the write: d = the code definition taken, sc = schedule changed, missed as judged, REQ-242)
ReapplyWrite(r, d, sc, missed) ==
  /\ rj' = [rj EXCEPT ![r].hash = d, ![r].def = d, ![r].behind = IF sc THEN 0 ELSE rj[r].behind]
  /\ missRec' = [missRec EXCEPT ![r] = IF sc /\ missed THEN NewRec(r, "Schedule", NULL) ELSE missRec[r]]  \* @req REQ-242
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op>>
ReapplyCode(r) ==
  /\ SchedulerRuns
  /\ Stale(r)
  /\ \E n \in DeclaringNodes(r), schedChanged \in BOOLEAN :
       ReapplyWrite(r, CodeDef(node[n].ver), schedChanged, HasMissed(r))

\* @req REQ-203  the scheduler finds a code-defined job that a running worker node declares and that has no stored
\*              definition with its name: create it from the code definition of a node that declares it, Active,
\*              nextRunAt from now. (The node-start branch of the same sentence is in NodeStart.) An insert keyed by
\*              name, so it fails if the name is stored by then (A-8).
CreateGuard(r) == SchedulerRuns /\ rj[r].st = "none" /\ Declared(r)
CreateWrite(r, d) ==
  /\ rj' = [rj EXCEPT ![r] = [NoRj EXCEPT !.st = "Active", !.origin = "code", !.hash = d, !.def = d]]
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op, missRec>>
CreateDeclared(r) == CreateGuard(r) /\ \E n \in DeclaringNodes(r) : CreateWrite(r, CodeDef(node[n].ver))

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
UpdateWrite(r, sc, missed) ==
  /\ rj' = [rj EXCEPT ![r].def = "edited", ![r].behind = IF sc THEN 0 ELSE rj[r].behind]
  /\ missRec' = [missRec EXCEPT ![r] = IF sc /\ missed THEN NewRec(r, "Schedule", NULL) ELSE missRec[r]]  \* @req REQ-242
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op>>
UpdateGuard(r) == rj[r].st \in {"Active", "Paused"} /\ CanEdit(r)
OperatorUpdate(r) ==
  /\ UpdateGuard(r)
  /\ \E scheduleChanged \in BOOLEAN : UpdateWrite(r, scheduleChanged, HasMissed(r))

\* @req REQ-213  operator removes a runtime job, or an orphaned one of any origin.
\* @req INV-206  a code job that is not orphaned is refused (guard).
\* @req REQ-237  waiting occurrences skipped with reason Removed.
\* @req REQ-242  an active job removed with missed instants: recorded as dropped by the removal, same write.
RemoveWrite(r, missed) ==
  /\ rj' = [rj EXCEPT ![r] = NoRj]
  /\ SkipWaiting(r, "Removed")
  /\ missRec' = IF missed THEN Recorded(r, "Removed", NULL) ELSE missRec
  /\ UNCHANGED <<node, job, order, maint, ov, mf, op>>
RemoveGuard(r) == (rj[r].st # "none" /\ rj[r].origin = "runtime") \/ rj[r].st = "Orphaned"
OperatorRemove(r) == RemoveGuard(r) /\ RemoveWrite(r, HasMissed(r))

\* @req REQ-214
\* @req REQ-237  waiting occurrences skipped with reason Paused.
\* @req REQ-242  instants already missed are recorded as dropped by the pause, in the pause write.
PauseWrite(r, missed) ==
  /\ rj' = [rj EXCEPT ![r].st = "Paused"]
  /\ SkipWaiting(r, "Paused")
  /\ missRec' = IF missed THEN Recorded(r, "Pause", NULL) ELSE missRec
  /\ UNCHANGED <<node, job, order, maint, ov, mf, op>>
Pause(r) == rj[r].st = "Active" /\ PauseWrite(r, HasMissed(r))

\* @req REQ-215  resume: Active, nextRunAt from now.
ResumeWrite(r) ==
  /\ rj' = [rj EXCEPT ![r].st = "Active", ![r].behind = 0]
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op, missRec>>
Resume(r) == rj[r].st = "Paused" /\ ResumeWrite(r)

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
                      \/ ReapplyCode(r) \/ CreateDeclared(r)
  \/ \E n \in Nodes : NodeStop(n) \/ \E v \in Releases : NodeStart(n, v)
  \/ \E o \in OccIds : \/ StartWaiting(o) \/ Claim(o) \/ Complete(o) \/ RetryDue(o) \/ LeaseLost(o)
                       \/ AbandonOnTimeout(o) \/ ZombieEnds(o) \/ BecomeUnroutable(o) \/ Reroute(o)
                       \/ Archive(o)
  \/ ToggleMaintenance

\* Only actor: system transitions are fair.
FairnessHost == /\ \A r \in Names : WF_vars(Trigger(r)) /\ WF_vars(Orphan(r)) /\ WF_vars(ReapplyCode(r))
                                    /\ WF_vars(CreateDeclared(r))                 \* @req REQ-203 (actor system, run 8)
                /\ \A o \in OccIds : WF_vars(StartWaiting(o))
Fairness == FairnessHost /\ \A r \in Names : WF_vars(Restore(r))                   \* @req REQ-206 (actor system, run 9)

Spec == Init /\ [][Next]_vars /\ Fairness
\* Not the requirements as written: run 8's REQ-206 (actor Host), whose restore is not fair. Counterfactual only.
SpecCF_RestoreHost == Init /\ [][Next]_vars /\ FairnessHost

\* A-22: missRec is written only by Trigger, the schedule-change steps and Pause / Orphan / OperatorRemove (REQ-242) and read by no guard or
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

\* @req REQ-203, REQ-206, REQ-241, INV-212 (notes)  run 8: stored definitions converge to what running nodes declare. A
\*              code-defined name that a running worker node declares is eventually stored, not orphaned, with the
\*              code definition of a declaring node, and stays so, unless the running nodes keep changing for ever or
\*              an operator keeps removing the job for ever (REQ-213, each removal undoes the healing). A runtime job
\*              with that name counts as settled: REQ-203 does not apply to it, and REQ-236 refuses the next start of a
\*              node that declares it (A-33).
Settled(r) == \/ rj[r].origin = "runtime"
              \/ /\ rj[r].st \in {"Active", "Paused"} /\ rj[r].origin = "code"
                 /\ \E n \in DeclaringNodes(r) : rj[r].hash = CodeDef(node[n].ver)
NodesChange == node' # node
Liv_DeclaredConverges ==
  \A r \in Names : <>[](Declared(r) => Settled(r)) \/ []<><<NodesChange>>_vars \/ []<><<OperatorRemove(r)>>_vars

\* @req REQ-205, REQ-206, REQ-207, REQ-203, REQ-241  run 9: the scheduler's reconciliation stops once the running nodes
\*              stop changing: no flip-flop between orphaning or deleting a job and restoring or re-creating it, and no
\*              definition rewritten back and forth, unless an operator keeps removing the job for ever. ReconView is what
\*              those steps change (an operator's pause or resume is not reconciliation and is not looked at).
ReconView(r) == <<rj[r].st \in {"Orphaned", "none"}, rj[r].origin, rj[r].hash>>
Liv_ReconcileStops ==
  \A r \in Names : ~[]<><<ReconView(r)' # ReconView(r)>>_vars \/ []<><<NodesChange>>_vars \/ []<><<OperatorRemove(r)>>_vars
\* ... and without the escape for nodes that keep changing (expected VIOLATED: nodes that keep being redeployed change the
\* stored job each time, by REQ-204 rewriting the definition, as its notes accept for a rolling deploy, or by orphaning and
\* restoring it, as REQ-205 and REQ-206 say).
Liv_ReconcileStopsAlways ==
  \A r \in Names : ~[]<><<ReconView(r)' # ReconView(r)>>_vars \/ []<><<OperatorRemove(r)>>_vars

\* A step that moves nextRunAt by a schedule change (REQ-227 via REQ-204, REQ-241 or REQ-212).
ScheduleChange(r) == OperatorUpdate(r) \/ ReapplyCode(r) \/ \E n \in Nodes, v \in Releases : NodeStart(n, v)
MissedTrigger(r) == Trigger(r) /\ rj'[r].miss # "none"
\* @req REQ-234  a step other than a trigger that passes over an active job's missed instants: it moves nextRunAt
\*              from now while the job stays active (a schedule change), or it takes the job out of Active (a
\*              pause, an orphaning, or a removal by REQ-207 or REQ-213).
PassesOver(r) == HasMissed(r) /\ ~Trigger(r) /\ (rj'[r].st # "Active" \/ rj'[r].behind = 0)
RecordedAs(r, how) == missRec'[r].n = (IF missRec[r].n < 2 THEN missRec[r].n + 1 ELSE 2) /\ missRec'[r].how = how

\* @req REQ-242  a missed-instant record is written only when an active job's nextRunAt is moved past missed
\*              instants or the job stops being active while it has some: by a trigger that missed at least
\*              one, or by a step that passes over them (never by trigger-now, resume, restore, a trigger with
\*              nothing missed, or any step on a paused or orphaned job) ...
Prop_MissRecordOnlyByMove ==
  [][\A r \in Names : missRec'[r] # missRec[r] => MissedTrigger(r) \/ PassesOver(r)]_vars

\* @req REQ-242  ... and every such step writes exactly one record, in the same step, whatever the misfire
\*              policy (run-4 F-1, run-5 F-1 and F-2).
Prop_MissedMoveRecordsOnce ==
  [][\A r \in Names : (MissedTrigger(r) \/ PassesOver(r))
        => missRec'[r].n = (IF missRec[r].n < 2 THEN missRec[r].n + 1 ELSE 2) /\ missRec'[r].how # "none"]_vars

\* @req REQ-242, REQ-234  no due instant is recorded twice: a step that writes a record leaves the job either
\*              with nextRunAt from now or out of Active, and every way back into Active computes nextRunAt from
\*              now (REQ-215, REQ-206), so a later record never covers an instant an earlier one did.
Prop_NoInstantRecordedTwice ==
  [][\A r \in Names : missRec'[r] # missRec[r] => rj'[r].behind = 0 \/ rj'[r].st # "Active"]_vars

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
          [] missRec'[r].how = "Schedule" -> ScheduleChange(r) /\ rj'[r].st = "Active"
          [] missRec'[r].how = "Pause"    -> Pause(r)
          [] missRec'[r].how = "Orphan"   -> Orphan(r) /\ rj'[r].st = "Orphaned"
          [] missRec'[r].how = "Removed"  -> (Orphan(r) \/ OperatorRemove(r)) /\ rj'[r].st = "none"
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
\* Run 9 (REQ-206 actor system): SCN-209 leg (b) is now an obligation, not only reachable. From the orphaned state that
\* remembers Paused, once the rolled-back release runs for good (it declares weekly-report), weekly-report eventually
\* leaves Orphaned, Paused (the restore takes stateBeforeOrphan), unless an operator removed it first (REQ-213, not part
\* of the scenario). "No occurrence was created meanwhile" is Inv_NoScheduleWhilePaused in the same cfg. Leg (a), the
\* orphaning, is the orphan sweep, fair since run 1. SpecSCN209bH is the counterfactual with run 8's REQ-206 (not fair).
SpecSCN209b  == Init_SCN209b /\ [][Next]_vars /\ Fairness
SpecSCN209bH == Init_SCN209b /\ [][Next]_vars /\ FairnessHost
Liv_Scn209Restored == <>[]Declared(J1) => <>(rj[J1].st \in {"Paused", "none"})

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

\* Run 9 (probe, action): a restore by a node whose code definition has the stored definitionHash (the code did not change)
\* keeps an operator's runtime edit (AllowRuntimeOverride), as REQ-204 and REQ-241 do. Expected VIOLATED as written:
\* REQ-206 updates the stored definition to the node's code whatever the hash.
ProbeAct_RestoreKeepsRuntimeEdit ==
  [][\A r \in Names : rj[r].st = "Orphaned" /\ rj[r].def = "edited" /\ rj'[r].st \in {"Active", "Paused"}
        /\ rj'[r].hash = rj[r].hash => rj'[r].def = "edited"]_vars

\* Not the requirements as written: the run-9 finding's option 1, REQ-206 updates the definition only if the hash of
\* that node's code definition differs from the stored definitionHash (as REQ-204). The only step from Orphaned to
\* Active or Paused is Restore, so NextOpt206 is Next with Restore replaced by RestoreOpt206.
RestoreOpt206(r) ==
  /\ rj[r].st = "Orphaned"
  /\ \E n \in RunningNodes :
       /\ r \in Decl(node[n].ver)
       /\ LET d == CodeDef(node[n].ver) IN
            /\ rj' = [rj EXCEPT ![r].st = rj[r].before, ![r].before = "none", ![r].behind = 0, ![r].hash = d,
                                ![r].def = IF rj[r].hash = d THEN rj[r].def ELSE d]
            /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op, missRec>>
NextOpt206 == \/ Next /\ ~\E r \in Names : rj[r].st = "Orphaned" /\ rj'[r].st \in {"Active", "Paused"}
              \/ \E r \in Names : RestoreOpt206(r)
SpecOpt206 == Init /\ [][NextOpt206]_vars /\ FairnessHost /\ \A r \in Names : WF_vars(RestoreOpt206(r))

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

\* @req REQ-242  run-5 F-1 regression (was ProbeAct_OverduePausedRecorded / ProbeAct_OverdueOrphanedRecorded): an
\*              active job with missed instants that is paused, orphaned or removed (REQ-207 or REQ-213) is
\*              recorded in that step, as dropped by that step.
Prop_LeaveRecordsMissed ==
  [][\A r \in Names : HasMissed(r) /\ rj'[r].st # "Active" =>
        RecordedAs(r, CASE rj'[r].st = "Paused" -> "Pause" [] rj'[r].st = "Orphaned" -> "Orphan" [] OTHER -> "Removed")]_vars

\* @req REQ-234, REQ-242  run-5 F-2 regression (was ProbeAct_PassedInstantRunsOrIsRecorded): a due instant of an
\*              active job that has passed, however recently, leaves the schedule only by a trigger or with a
\*              record "dropped by the schedule change".
Prop_PassedInstantRunsOrIsRecorded ==
  [][\A r \in Names : HasMissed(r) /\ rj'[r].st = "Active" /\ rj'[r].behind = 0 /\ ~Trigger(r)
        => RecordedAs(r, "Schedule")]_vars

\* Run 5 F-3 (resolved by REQ-242's notes, kept as documentation): a record that says the catch-up occurrence
\* "is waiting" is a snapshot. Reachable = the recorded waiting occurrence is later skipped (REQ-237) while the
\* record still says waiting, which the notes accept.
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
