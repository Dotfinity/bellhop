---------------------------- MODULE Recurring ----------------------------
\* Generated from specs/recurring.json (specHash 577c79cef0e7) — edit the requirements, not this file.
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
          OrphanPolicies,   \* @req REQ-205, REQ-207  orphan policy explored ("default" or "delete")
          NULL

ASSUME MaxQueued \in Nat \ {0}                                              \* @req REQ-233
ASSUME OverlapPolicies \subseteq {"Skip", "Queue", "Allow", "CancelPrevious"}  \* @req REQ-201
ASSUME MisfirePolicies \subseteq {"RunOnce", "Skip", "RunAll"}                 \* @req REQ-201
ASSUME OrphanPolicies \subseteq {"default", "delete"}
ASSUME Releases \subseteq {"v1", "v2", "v3"} /\ DeclV1 \cup DeclV2 \cup DeclV3 \subseteq Names

VARIABLES rj,     \* stored recurring definitions, keyed by name
          node,   \* hosting.Node abstraction: Down / Running a release
          occ,    \* occurrences
          job,    \* jobs.Job of each occurrence (same slot)
          order,  \* creation order of live occurrences ("earlier occurrence", "oldest first")
          maint,  \* jobs.Maintenance: global maintenance pause on?
          ov, mf, op  \* per-job overlap / misfire policy and the orphan policy, fixed per behaviour (A-9)
vars == <<rj, node, occ, job, order, maint, ov, mf, op>>

RjStatus  == {"none", "Active", "Paused", "Orphaned"}
Defs      == {"none", "d1", "d2", "d3", "rt", "edited"}  \* definition content; dN = code of release vN
OccStatus == {"none", "Waiting", "Started", "Skipped"}
JobStatus == {"none", "Enqueued", "Processing", "Failed", "Succeeded", "DeadLettered", "Cancelled", "Unroutable"}
Finals    == {"Succeeded", "DeadLettered", "Cancelled"}   \* glossary "unfinished" = not one of these

Decl(v)    == CASE v = "v1" -> DeclV1 [] v = "v2" -> DeclV2 [] OTHER -> DeclV3
CodeDef(v) == CASE v = "v1" -> "d1" [] v = "v2" -> "d2" [] OTHER -> "d3"

\* behind = how many due instants have passed since nextRunAt was last set: 0, 1, or 2 (= "2 or more").
\* This replaces the clock (A-1).
RjRec  == [st: RjStatus, origin: {"code", "runtime", "none"}, before: {"Active", "Paused", "none"},
           hash: Defs, def: Defs, behind: 0..2, miss: {"none", "caughtUp", "dropped"}]
OccRec == [st: OccStatus, rj: Names \cup {NULL}, blk: SUBSET OccIds,
           reason: {"none", "Overlap", "QueueFull"}, sched: BOOLEAN]
JobRec == [st: JobStatus, zombie: BOOLEAN, cancelReq: BOOLEAN]

TypeInv ==
  /\ rj    \in [Names -> RjRec]
  /\ node  \in [Nodes -> [st: {"Down", "Running"}, ver: Releases]]
  /\ occ   \in [OccIds -> OccRec]
  /\ job   \in [OccIds -> JobRec]
  /\ order \in Seq(OccIds) /\ Len(order) <= Cardinality(OccIds)
  /\ maint \in BOOLEAN
  /\ ov \in [Names -> OverlapPolicies] /\ mf \in [Names -> MisfirePolicies] /\ op \in OrphanPolicies

NoRj   == [st |-> "none", origin |-> "none", before |-> "none", hash |-> "none", def |-> "none", behind |-> 0, miss |-> "none"]
NoOcc  == [st |-> "none", rj |-> NULL, blk |-> {}, reason |-> "none", sched |-> FALSE]
NoJob  == [st |-> "none", zombie |-> FALSE, cancelReq |-> FALSE]
EnqJob == [st |-> "Enqueued", zombie |-> FALSE, cancelReq |-> FALSE]

Live          == {o \in OccIds : occ[o].st # "none"}
OfJob(r)      == {o \in Live : occ[o].rj = r}
Finished(o)   == job[o].st \in Finals
Unfinished(o) == occ[o].st = "Started" /\ ~Finished(o)
Blocking(r)   == {o \in OfJob(r) : Unfinished(o)}
WaitingOf(r)  == {o \in OfJob(r) : occ[o].st = "Waiting"}
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
  /\ ov \in [Names -> OverlapPolicies] /\ mf \in [Names -> MisfirePolicies] /\ op \in OrphanPolicies

-----------------------------------------------------------------------------
\* Creating an occurrence and deciding it by the overlap policy: one event, five requirements.
\* @req REQ-221, REQ-222, REQ-223, REQ-225, REQ-235
Decide(o, r, sched) ==
  LET B == Blocking(r)
      mk(st, blk, reason) == [st |-> st, rj |-> r, blk |-> blk, reason |-> reason, sched |-> sched]
  IN /\ order' = Append(order, o)
     /\ IF B = {} THEN                                                   \* @req REQ-221
          /\ occ' = [occ EXCEPT ![o] = mk("Started", {}, "none")]
          /\ job' = [job EXCEPT ![o] = EnqJob]
        ELSE CASE ov[r] = "Skip" ->                                      \* @req REQ-222
                    /\ occ' = [occ EXCEPT ![o] = mk("Skipped", {}, "Overlap")] /\ UNCHANGED job
               [] ov[r] = "Queue" /\ Cardinality(WaitingOf(r)) < MaxQueued ->   \* @req REQ-223
                    /\ occ' = [occ EXCEPT ![o] = mk("Waiting", B, "none")] /\ UNCHANGED job
               [] ov[r] = "Queue" ->                                     \* @req REQ-235
                    /\ occ' = [occ EXCEPT ![o] = mk("Skipped", {}, "QueueFull")] /\ UNCHANGED job
               [] ov[r] = "Allow" ->                                     \* @req REQ-225
                    /\ occ' = [occ EXCEPT ![o] = mk("Started", {}, "none")]
                    /\ job' = [job EXCEPT ![o] = EnqJob]
               [] ov[r] = "CancelPrevious" ->                            \* @req REQ-225 (+ jobs REQ-134/135)
                    /\ occ' = [occ EXCEPT ![o] = mk("Started", {}, "none")]
                    /\ job' = [x \in OccIds |->
                                 IF x = o THEN EnqJob
                                 ELSE IF x \in B
                                   THEN IF job[x].st = "Processing"
                                          THEN [job[x] EXCEPT !.cancelReq = TRUE]
                                          ELSE [job[x] EXCEPT !.st = "Cancelled"]
                                   ELSE job[x]]

\* @req REQ-216  Active, maintenance off, nextRunAt passed: one compare-and-set advances nextRunAt
\*              and creates what the misfire policy calls for.
\* @req REQ-217, REQ-218, REQ-219, INV-207, REQ-234  misfire handling; REQ-220 recorded in .miss.
\* @req INV-201, INV-210  guarded by Active and ~maint.
\* The CAS makes the whole step atomic (A-2); RunAll(max) is abstracted to max = 1 (A-4);
\* at most one occurrence per trigger (A-5).
Trigger(r) ==
  /\ SchedulerRuns
  /\ rj[r].st = "Active" /\ ~maint /\ rj[r].behind >= 1
  /\ \E missed \in (IF rj[r].behind = 2 THEN {TRUE} ELSE BOOLEAN) :   \* lateness > MisfireThreshold? (A-3)
       IF missed /\ mf[r] = "Skip"
         THEN /\ rj' = [rj EXCEPT ![r].behind = 0, ![r].miss = "dropped"]   \* @req REQ-218
              /\ UNCHANGED <<occ, job, order>>
         ELSE /\ rj' = [rj EXCEPT ![r].behind = 0, ![r].miss = IF missed THEN "caughtUp" ELSE "none"]
              /\ \E o \in FreeSlots : Decide(o, r, TRUE)                 \* @req REQ-217, INV-207
  /\ UNCHANGED <<node, maint, ov, mf, op>>

\* @req REQ-226  Trigger now: any stored job (also paused/orphaned), decided by the overlap policy,
\*              nextRunAt unchanged.
TriggerNow(r) ==
  /\ rj[r].st # "none"
  /\ \E o \in FreeSlots : Decide(o, r, FALSE)
  /\ UNCHANGED <<rj, node, maint, ov, mf, op>>

\* @req REQ-224  While an occurrence is waiting, when the earlier occurrence's job succeeds, is
\*              dead-lettered or cancelled: enqueue its job, record it started. Note: oldest first.
\*              "The earlier occurrence" = the one(s) that blocked it when it was created (blk).
\*              Runs as its own step after the job finished (A-7). No guard on the job's state.
StartWaiting(o) ==
  /\ occ[o].st = "Waiting"
  /\ \A b \in occ[o].blk : ~Unfinished(b)
  /\ \A w \in WaitingOf(occ[o].rj) : Pos(w) >= Pos(o)
  /\ occ' = [occ EXCEPT ![o].st = "Started", ![o].blk = {}]
  /\ job' = [job EXCEPT ![o] = EnqJob]
  /\ UNCHANGED <<rj, node, order, maint, ov, mf, op>>

-----------------------------------------------------------------------------
\* Definitions and reconciliation

\* @req REQ-203  node start: create a missing code-defined job (Active, nextRunAt from now).
\* @req REQ-204  node start: code definition changed vs stored definitionHash -> update, keep Active/Paused.
\* Both happen in the one start step for every name the release declares (A-8).
NodeStart(n, v) ==
  /\ node[n].st = "Down" /\ v \in Releases
  /\ node' = [node EXCEPT ![n] = [st |-> "Running", ver |-> v]]
  /\ rj' = [r \in Names |->
              IF r \notin Decl(v) THEN rj[r]
              ELSE IF rj[r].st = "none"
                THEN [NoRj EXCEPT !.st = "Active", !.origin = "code", !.hash = CodeDef(v), !.def = CodeDef(v)]
              ELSE IF rj[r].st \in {"Active", "Paused"} /\ rj[r].hash # CodeDef(v)
                THEN [rj[r] EXCEPT !.hash = CodeDef(v), !.def = CodeDef(v)]
              ELSE rj[r]]
  /\ UNCHANGED <<occ, job, order, maint, ov, mf, op>>

\* modeling artefact: a node stops or crashes (hosting module).
NodeStop(n) ==
  /\ node[n].st = "Running"
  /\ node' = [node EXCEPT ![n].st = "Down"]
  /\ UNCHANGED <<rj, occ, job, order, maint, ov, mf, op>>

\* @req REQ-205  no running worker node declares a stored code-defined job, default policy:
\*              record its state, mark it orphaned (which pauses it).
\* @req REQ-207  same event, policy delete: remove the definition.
Orphan(r) ==
  /\ SchedulerRuns
  /\ rj[r].st \in {"Active", "Paused"} /\ rj[r].origin = "code"
  /\ ~Declared(r)
  /\ rj' = IF op = "default"
             THEN [rj EXCEPT ![r].before = rj[r].st, ![r].st = "Orphaned"]
             ELSE [rj EXCEPT ![r] = NoRj]
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op>>

\* @req REQ-206  a running worker node declares an orphaned job again: back to its earlier state,
\*              nextRunAt from now.
Restore(r) ==
  /\ rj[r].st = "Orphaned" /\ Declared(r)
  /\ rj' = [rj EXCEPT ![r].st = rj[r].before, ![r].before = "none", ![r].behind = 0]
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op>>

\* @req REQ-208  operator adds a runtime job when no definition with its name exists.
OperatorAdd(r) ==
  /\ rj[r].st = "none"
  /\ rj' = [rj EXCEPT ![r] = [NoRj EXCEPT !.st = "Active", !.origin = "runtime", !.def = "rt"]]
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op>>

CanEdit(r) == rj[r].origin = "runtime" \/ (rj[r].origin = "code" /\ r \in Override)

\* @req REQ-212  operator updates a runtime job, or a code job with AllowRuntimeOverride.
\* @req REQ-211  otherwise the edit is rejected (guard CanEdit).
\* @req REQ-227  if the schedule changed: nextRunAt from now, no catch-up.
OperatorUpdate(r) ==
  /\ rj[r].st \in {"Active", "Paused"} /\ CanEdit(r)
  /\ \E scheduleChanged \in BOOLEAN :
       rj' = [rj EXCEPT ![r].def = "edited",
                        ![r].behind = IF scheduleChanged THEN 0 ELSE rj[r].behind]
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op>>

\* @req REQ-213  operator removes a runtime job, or an orphaned one of any origin.
\* @req INV-206  a code job that is not orphaned is refused (guard).
OperatorRemove(r) ==
  /\ (rj[r].st # "none" /\ rj[r].origin = "runtime") \/ rj[r].st = "Orphaned"
  /\ rj' = [rj EXCEPT ![r] = NoRj]
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op>>

\* @req REQ-214
Pause(r) ==
  /\ rj[r].st = "Active"
  /\ rj' = [rj EXCEPT ![r].st = "Paused"]
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op>>

\* @req REQ-215  resume: Active, nextRunAt from now.
Resume(r) ==
  /\ rj[r].st = "Paused"
  /\ rj' = [rj EXCEPT ![r].st = "Active", ![r].behind = 0]
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op>>

\* modeling artefact A-1: a due instant of a stored job passes (no clock).
TimePasses(r) ==
  /\ rj[r].st # "none" /\ rj[r].behind < 2
  /\ rj' = [rj EXCEPT ![r].behind = rj[r].behind + 1]
  /\ UNCHANGED <<node, occ, job, order, maint, ov, mf, op>>

\* jobs REQ-162, REQ-163 (other module): operator toggles maintenance.
ToggleMaintenance ==
  /\ maint' = ~maint
  /\ UNCHANGED <<rj, node, occ, job, order, ov, mf, op>>

-----------------------------------------------------------------------------
\* jobs.Job abstraction (A-10): only what "unfinished" and "processing" need.
JobStep(o, new) == job' = [job EXCEPT ![o] = new] /\ UNCHANGED <<rj, node, occ, order, maint, ov, mf, op>>

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

\* modeling artefact A-11: finished occurrences free their slot (not while a waiting one refers to them).
Archive(o) ==
  /\ \/ occ[o].st = "Skipped"
     \/ occ[o].st = "Started" /\ Finished(o) /\ ~job[o].zombie
  /\ \A w \in OccIds : o \notin occ[w].blk
  /\ occ'   = [occ EXCEPT ![o] = NoOcc]
  /\ job'   = [job EXCEPT ![o] = NoJob]
  /\ order' = SelectSeq(order, LAMBDA x : x # o)
  /\ UNCHANGED <<rj, node, maint, ov, mf, op>>

Next ==
  \/ \E r \in Names : \/ Trigger(r) \/ TriggerNow(r) \/ Orphan(r) \/ Restore(r) \/ OperatorAdd(r)
                      \/ OperatorUpdate(r) \/ OperatorRemove(r) \/ Pause(r) \/ Resume(r) \/ TimePasses(r)
  \/ \E n \in Nodes : NodeStop(n) \/ \E v \in Releases : NodeStart(n, v)
  \/ \E o \in OccIds : \/ StartWaiting(o) \/ Claim(o) \/ Complete(o) \/ RetryDue(o) \/ LeaseLost(o)
                       \/ AbandonOnTimeout(o) \/ ZombieEnds(o) \/ BecomeUnroutable(o) \/ Archive(o)
  \/ ToggleMaintenance

\* Only actor: system transitions are fair.
Fairness == /\ \A r \in Names : WF_vars(Trigger(r)) /\ WF_vars(Orphan(r))
            /\ \A o \in OccIds : WF_vars(StartWaiting(o))

Spec == Init /\ [][Next]_vars /\ Fairness

-----------------------------------------------------------------------------
\* Properties

\* @req INV-201  paused or orphaned: never an occurrence on schedule.  (also SCN-202)
Inv_NoScheduleWhilePaused ==
  \A r \in Names : rj[r].st \in {"Paused", "Orphaned"} => ~ENABLED Trigger(r)

\* @req INV-210  maintenance on: never an occurrence on schedule ...
Inv_NoScheduleInMaintenance == maint => \A r \in Names : ~ENABLED Trigger(r)

\* @req INV-210  ... and nextRunAt unchanged while maintenance is on (behind only grows).
Prop_MaintenanceKeepsNextRunAt ==
  [][maint /\ maint' => \A r \in Names : rj[r].st # "none" /\ rj'[r].st # "none" => rj'[r].behind >= rj[r].behind]_vars

\* @req INV-204  Skip/Queue: never two of its occurrences' jobs processing at the same time on any
\*              nodes — counting every running handler (current run or one abandoned/lease-lost).
Executing(o) == job[o].st = "Processing" \/ job[o].zombie
Inv_NoOverlapRunning ==
  \A r \in Names : ov[r] \in {"Skip", "Queue"} => Cardinality({o \in OfJob(r) : Executing(o)}) <= 1

\* @req INV-204  same, counting only jobs whose stored status is Processing (narrow reading, A-12).
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
  /\ ov \in [Names -> OverlapPolicies] /\ mf \in [Names -> MisfirePolicies] /\ op \in OrphanPolicies
AllRunning(v) == [n \in Nodes |-> [st |-> "Running", ver |-> v]]
O1 == CHOOSE o \in OccIds : TRUE

\* @req SCN-201  Skip: the 10:00 run is processing at 10:01.
Init_SCN201 ==
  /\ rj = [r \in Names |-> IF r = J1 THEN [RuntimeRj("Active") EXCEPT !.behind = 1] ELSE NoRj]
  /\ node = AllRunning("v1")
  /\ occ = [o \in OccIds |-> IF o = O1 THEN [NoOcc EXCEPT !.st = "Started", !.rj = J1, !.sched = TRUE] ELSE NoOcc]
  /\ job = [o \in OccIds |-> IF o = O1 THEN [EnqJob EXCEPT !.st = "Processing"] ELSE NoJob]
  /\ order = <<O1>> /\ maint = FALSE
  /\ ov \in [Names -> OverlapPolicies] /\ mf \in [Names -> MisfirePolicies] /\ op \in OrphanPolicies
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

\* @req SCN-211  Skip misfire; due 03:00:00, first poll 03:00:02 (within MisfireThreshold).
Init_SCN211 == BaseInit([RuntimeRj("Active") EXCEPT !.behind = 1], AllRunning("v1"))
Scn211_NotReached ==
  ~(\E o \in OfJob(J1) : occ[o].st = "Started" /\ occ[o].sched /\ rj[J1].miss = "none" /\ rj[J1].behind = 0)

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

\* F: an unroutable occurrence job blocks the next occurrence.
Probe_UnroutableBlocksNext ==
  ~(\E o, s \in OccIds : job[o].st = "Unroutable" /\ occ[s].st = "Skipped" /\ occ[s].rj = occ[o].rj)

\* F: with Queue(max >= 2), a newer waiting occurrence starts while an older one is still unfinished.
Probe_NewerWaiterStartsBesideOlder ==
  ~(\E w, x \in OccIds : occ[w].st = "Waiting" /\ x \in OfJob(occ[w].rj) /\ Unfinished(x)
      /\ Pos(x) < Pos(w) /\ ENABLED StartWaiting(w))
=============================================================================
