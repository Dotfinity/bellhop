---------------------------- MODULE RecurringRace ----------------------------
\* Generated from specs/recurring.json (specHash 5a8b9d80683d) — edit the requirements, not this file.
\* @req INV-212  every store write that changes a recurring job's state or nextRunAt, or removes it (a trigger, a
\*              schedule change, a pause, a resume, an orphaning, a restore or a removal) is a compare-and-set on
\*              the state and nextRunAt it read, judges due and missed instants by the database clock at that write,
\*              changes nothing if either value changed since the read, and the writer then reads again and decides
\*              anew.
\* Run 7: each write named in Split is a read (Read) and a later write (Write). Between them every step of Recurring
\* can happen, including the atomic form of the same write (another operator, another node). At most one split
\* write is in flight per job (A-28). What the write compares and when it judges are constants, so that INV-212 as
\* written and the readings it rules out are checked with the same spec:
\*   CasOn = {"st", "nra"}, AtWrite = TRUE    INV-212
\*   CasOn = {"nra"},       AtWrite = TRUE    compare-and-set on nextRunAt only (REQ-216 before run 7; run-6 F-1 opt 1)
\*   CasOn = {"st", "nra"}, AtWrite = FALSE   compare-and-set, but the write lands what its read decided
\*   CasOn = {"st"},        AtWrite = FALSE   compare-and-set on the state only
\*   CasOn = {},            AtWrite = FALSE   unconditional (the run-6 F-1 trace)
\* WriteChecksMaint / WriteChecksDecl = TRUE check options for run-7 findings (the write also re-checks maintenance,
\* or the declared names in the heartbeats); INV-212 as written has both FALSE.
EXTENDS Recurring
CONSTANTS Split, CasOn, AtWrite, WriteChecksMaint, WriteChecksDecl
Kinds    == {"Trigger", "Sched", "Reapply", "Pause", "Resume", "Orphan", "Restore", "Remove"}
SysKinds == {"Trigger", "Reapply", "Orphan", "Restore"}     \* written by the scheduler on some running node
ASSUME Split \subseteq Kinds /\ CasOn \subseteq {"st", "nra"} /\ AtWrite \in BOOLEAN
ASSUME AtWrite => "nra" \in CasOn     \* judging at the write is only defined for a write that kept the nextRunAt it read
ASSUME WriteChecksMaint \in BOOLEAN /\ WriteChecksDecl \in BOOLEAN

VARIABLE rd   \* per name: the split write in flight, between its read and its write. w = which write; st, bf, b =
              \* state, stateBeforeOrphan and behind it read (kept only where the write can use them: with the state in
              \* the CAS a write that lands sees the state it read, and with AtWrite it judges behind at the write);
              \* late = newest instant judged late at the read; d = code definition chosen at the read (REQ-206,
              \* REQ-241); cs / cn = the job's state changed / nextRunAt moved since the read (ghosts for the CAS).
varsR == <<vars, rd>>

RdRec == [w: Kinds \cup {"none"}, st: RjStatus, bf: {"Active", "Paused", "none"},
          b: 0..2, late: BOOLEAN, d: Defs, cs: BOOLEAN, cn: BOOLEAN]
NoRd == [w |-> "none", st |-> "none", bf |-> "none", b |-> 0, late |-> FALSE, d |-> "none",
         cs |-> FALSE, cn |-> FALSE]
TypeInvR == TypeInv /\ rd \in [Names -> RdRec]

InitR == Init /\ rd = [r \in Names |-> NoRd]

\* What each read checks: the guard of the atomic action in Recurring. A schedule change is split only when the
\* schedule changed (otherwise it changes neither value and INV-212 does not apply).
Guard(r, k) ==
  CASE k = "Trigger" -> TriggerGuard(r)                                                  \* @req REQ-216
    [] k = "Sched"   -> UpdateGuard(r)                                                   \* @req REQ-212, REQ-227
    [] k = "Reapply" -> SchedulerRuns /\ Stale(r)                                        \* @req REQ-241
    [] k = "Pause"   -> rj[r].st = "Active"                                              \* @req REQ-214
    [] k = "Resume"  -> rj[r].st = "Paused"                                              \* @req REQ-215
    [] k = "Orphan"  -> OrphanGuard(r)                                                   \* @req REQ-205, REQ-207
    [] k = "Restore" -> rj[r].st = "Orphaned" /\ DeclaringNodes(r) # {}                  \* @req REQ-206
    [] k = "Remove"  -> RemoveGuard(r)                                                   \* @req REQ-213
DefsAt(r) == {CodeDef(node[n].ver) : n \in DeclaringNodes(r)}
Lates(k)   == IF k = "Trigger" /\ ~AtWrite THEN BOOLEAN ELSE {FALSE}
DefsOf(r, k) == IF k \in {"Reapply", "Restore"} THEN DefsAt(r) ELSE {"none"}
KeepSt == "st" \notin CasOn
Snap(r, k, late, d) ==
  [w |-> k, st |-> IF KeepSt THEN rj[r].st ELSE "none",
   bf |-> IF k = "Restore" /\ KeepSt THEN rj[r].before ELSE "none",
   b |-> IF AtWrite THEN 0 ELSE rj[r].behind, late |-> late, d |-> d, cs |-> FALSE, cn |-> FALSE]
\* the state and stateBeforeOrphan the write's read saw (with the state in the CAS, a write that lands sees them still)
ReadSt(r) == IF KeepSt THEN rd[r].st ELSE rj[r].st
ReadBf(r) == IF KeepSt THEN rd[r].bf ELSE rj[r].before

\* @req INV-212  the read.
Read(r, k) ==
  /\ rd[r].w = "none" /\ Guard(r, k)
  /\ \E late \in Lates(k), d \in DefsOf(r, k) : rd' = [rd EXCEPT ![r] = Snap(r, k, late, d)]
  /\ UNCHANGED vars

\* @req INV-212  "after which the writer reads the job again and decides anew": if its guard no longer holds it has
\*              nothing to do and stops; otherwise it is a new read. Written as one step with the lost write: the
\*              lost write changes nothing, so a step in between is the same as a step before it (A-28).
Again(r) ==
  IF Guard(r, rd[r].w)
    THEN \E late \in Lates(rd[r].w), d \in DefsOf(r, rd[r].w) : rd' = [rd EXCEPT ![r] = Snap(r, rd[r].w, late, d)]
    ELSE rd' = [rd EXCEPT ![r] = NoRd]

\* "Missed" as the write judges it (REQ-234, REQ-242): by the database clock at the write, or as the read saw it.
Missed(r) == IF AtWrite THEN HasMissed(r) ELSE ReadSt(r) = "Active" /\ rd[r].b >= 1
\* Option checks (not INV-212 as written): the write also re-checks what its read found outside the job's row.
DeclStill(r) ==
  CASE rd[r].w = "Orphan"  -> ~Declared(r)
    [] rd[r].w = "Restore" -> rd[r].d \in DefsAt(r)
    [] rd[r].w = "Reapply" -> Stale(r) /\ rd[r].d \in DefsAt(r)
    [] OTHER -> TRUE
\* @req INV-212  the compare-and-set loses when the state or nextRunAt it compares changed since the read.
Lost(r) ==
  \/ "st" \in CasOn /\ rd[r].cs
  \/ "nra" \in CasOn /\ rd[r].cn
  \/ WriteChecksMaint /\ rd[r].w = "Trigger" /\ maint
  \/ WriteChecksDecl /\ ~DeclStill(r)

\* @req INV-212, REQ-216, REQ-212, REQ-241, REQ-214, REQ-215, REQ-205, REQ-207, REQ-206, REQ-213, REQ-242
\* The write. Lost: nothing changes, the writer reads again (Again). A job whose row is gone (removed) is not written by an
\* unconditional write either (an UPDATE that finds no row). Otherwise it lands the same ...Write as the atomic action,
\* with what the read decided (the state recorded by an orphaning, the definition a restore or REQ-241 takes) and
\* the missed instants judged as AtWrite says.
Write(r) ==
  LET k == rd[r].w IN
  /\ k # "none"
  /\ IF Lost(r)
       THEN Again(r) /\ UNCHANGED vars
     ELSE IF rj[r].st = "none"
       THEN rd' = [rd EXCEPT ![r] = NoRd] /\ UNCHANGED vars
     ELSE /\ rd' = [rd EXCEPT ![r] = NoRd]
          /\ CASE k = "Trigger" -> \E nl \in (IF AtWrite THEN BOOLEAN ELSE {rd[r].late}) :
                                     TriggerWrite(r, IF AtWrite THEN rj[r].behind ELSE rd[r].b, nl)
               [] k = "Sched"   -> UpdateWrite(r, TRUE, Missed(r))
               [] k = "Reapply" -> ReapplyWrite(r, rd[r].d, TRUE, Missed(r))
               [] k = "Pause"   -> PauseWrite(r, Missed(r))
               [] k = "Resume"  -> ResumeWrite(r)
               [] k = "Orphan"  -> OrphanWrite(r, ReadSt(r), Missed(r))
               [] k = "Restore" -> RestoreWrite(r, ReadBf(r), rd[r].d)
               [] k = "Remove"  -> RemoveWrite(r, Missed(r))

\* Ghosts for the compare-and-set: a step changes the job's state, or moves nextRunAt (behind goes down, the job
\* enters Active, leaves Orphaned or is removed: each computes nextRunAt from now or deletes the row). A schedule
\* change with behind already 0 is not seen (A-27).
StCh(r)  == rj'[r].st # rj[r].st
NraCh(r) == \/ rj'[r].behind < rj[r].behind
            \/ StCh(r) /\ (rj'[r].st \in {"Active", "none"} \/ rj[r].st = "Orphaned")
\* Every step of Recurring. A node that stops may take an in-flight scheduler write with it (it never lands); when
\* no node runs, it does (A-29). With both values in the CAS, either change dooms the write, so both ghosts are set
\* together (fewer states, same futures); cs is kept only where the CAS compares the state.
Full == CasOn = {"st", "nra"}
Atomic ==
  /\ Next
  /\ LET stopped == \E n \in Nodes : node[n].st = "Running" /\ node'[n].st = "Down"
         allDown == \A n \in Nodes : node'[n].st = "Down"
     IN \E drop \in (IF ~stopped THEN {FALSE} ELSE IF allDown THEN {TRUE} ELSE BOOLEAN) :
          rd' = [r \in Names |->
                   IF rd[r].w = "none" THEN rd[r]
                   ELSE IF drop /\ rd[r].w \in SysKinds THEN NoRd
                   ELSE LET cs == rd[r].cs \/ ("st" \in CasOn /\ StCh(r))
                            cn == rd[r].cn \/ NraCh(r)
                        IN [rd[r] EXCEPT !.cs = IF Full THEN cs \/ cn ELSE cs, !.cn = IF Full THEN cs \/ cn ELSE cn]]

NextR == Atomic \/ \E r \in Names : (\E k \in Split : Read(r, k)) \/ Write(r)
SpecR == InitR /\ [][NextR]_varsR
\* The writer's own steps are system steps (the call is in flight), so they are fair; nothing else is assumed.
FairR == \A r \in Names : WF_varsR(Write(r))
SpecRL == SpecR /\ FairR

-----------------------------------------------------------------------------
\* Properties (each one applies to atomic steps too, so a split write that behaves like its atomic action passes)

\* @req INV-212  every write that lands is a step of Recurring: what the write does, the atomic action could have done
\*              in that state. (Every property checked on Recurring with the same constants then holds here.)
Prop_Refines == [][Next]_vars

\* @req REQ-242, REQ-234  run-6 F-1 regression: a record is written only for instants that have passed and that no
\*              trigger has handled.
Prop_RecordOnlyUnhandledInstants == [][\A r \in Names : missRec'[r] # missRec[r] => rj[r].behind >= 1]_vars

NewSched(o) == occ[o].st = "none" /\ occ'[o].st # "none" /\ occ'[o].sched
\* @req INV-201, SCN-217  never an occurrence on schedule for a paused or orphaned job (as a step: the write itself).
Prop_NoScheduledOccurrenceWhilePaused ==
  [][\A o \in OccIds : NewSched(o) => rj'[occ'[o].rj].st \notin {"Paused", "Orphaned"}]_vars

\* A trigger's write lands (it changes the job; a node stopping that drops the write changes the nodes instead).
TriggerLanded(r) == rd[r].w = "Trigger" /\ rd'[r] = NoRd /\ rj'[r] # rj[r] /\ node' = node
\* @req INV-210  while maintenance is on, never an occurrence on schedule and never a scheduled advance of nextRunAt.
Prop_NoTriggerWriteInMaintenance ==
  [][(\A o \in OccIds : NewSched(o) => ~maint) /\ \A r \in Names : TriggerLanded(r) => ~maint]_varsR

\* @req INV-203, REQ-227  a trigger creates an occurrence only for the instant nextRunAt still points at: if nextRunAt
\*              moved since its read, that instant was already triggered (by another node, SCN-200) or dropped by a
\*              schedule change, and running it is a second occurrence for it or a catch-up for the old schedule.
Prop_OneOccurrencePerInstant == [][\A r \in Names : TriggerLanded(r) => ~rd[r].cn]_varsR

\* @req REQ-205  orphaning records the job's current state.
Prop_OrphanRecordsCurrentState ==
  [][\A r \in Names : rj[r].st # "Orphaned" /\ rj'[r].st = "Orphaned" => rj'[r].before = rj[r].st]_vars

\* @req REQ-206  a job leaves Orphaned (other than by removal) only to the state it had before it was orphaned, with the
\*              code definition of a running node that declares it.
Prop_LeaveOrphanedOnlyToStateBefore ==
  [][\A r \in Names : rj[r].st = "Orphaned" /\ rj'[r].st \notin {"Orphaned", "none"} => rj'[r].st = rj[r].before]_vars
Prop_RestoreOnlyDeclared ==
  [][\A r \in Names : rj[r].st = "Orphaned" /\ rj'[r].st \notin {"Orphaned", "none"} =>
        \E n \in RunningNodes : r \in Decl(node[n].ver) /\ rj'[r].hash = CodeDef(node[n].ver)]_vars

\* @req REQ-205, REQ-207, SCN-208, INV-206  a stored code-defined job that is not orphaned is orphaned or removed only
\*              while no running worker node declares it.
Prop_CodeJobLeavesOnlyUndeclared ==
  [][\A r \in Names : rj[r].origin = "code" /\ rj[r].st \in {"Active", "Paused"} /\ rj'[r].st \in {"Orphaned", "none"}
        => ~Declared(r)]_vars

\* @req INV-212  a writer that loses eventually acts or finds nothing to do, unless the job's state or nextRunAt keeps
\*              changing under it for ever (obstruction-free: no stuck writer). Checked with SpecRL.
Bump(r) == rj'[r].st # rj[r].st \/ rj'[r].behind < rj[r].behind
Liv_WriterSettles == \A r \in Names : []<>(rd[r].w = "none") \/ []<><<Bump(r)>>_varsR
\* ... and without the escape, to show what "for ever" takes (expected VIOLATED: a lasso in which another write lands in
\* every window between a read and its write).
Liv_WriterSettlesAlways == \A r \in Names : []<>(rd[r].w = "none")

-----------------------------------------------------------------------------
\* Scenarios

\* @req SCN-216  nightly-export (code-defined, daily 02:00) is active, 02:00 has passed (behind = 1), and an operator's
\*              pause has read it at 02:00:02. The scheduler triggers on time, the occurrence starts, the pause's CAS
\*              loses, the pause reads again and marks it paused. Trap: Paused, the 02:00 occurrence started, no record,
\*              and the pause call finished. It can only be reached with the pause losing: a pause write that wins
\*              while 02:00 is still untriggered records it.
Init_SCN216 ==
  /\ BaseInit([CodeRj("Active") EXCEPT !.behind = 1], AllRunning("v1"))
  /\ rd = [r \in Names |-> IF r = J1 THEN [NoRd EXCEPT !.w = "Pause", !.st = IF KeepSt THEN "Active" ELSE "none",
                                                      !.b = IF AtWrite THEN 0 ELSE 1]
                           ELSE NoRd]
Scn216_NotReached ==
  ~(/\ rj[J1].st = "Paused" /\ rd[J1].w = "none" /\ missRec[J1].n = 0
    /\ \E o \in OfJob(J1) : occ[o].st = "Started" /\ occ[o].sched)
\* Leg (a), the scenario's own path: the pause has lost its CAS and read the job again (still the pause in flight, its
\* ghosts reset, so it read after the trigger), the job is active with 02:00 handled and started, nothing recorded.
\* From here its write marks the job paused and, judged at the write, records nothing (Scn216_NotReached is the end).
Scn216a_NotReached ==
  ~(/\ rd[J1].w = "Pause" /\ ~rd[J1].cs /\ ~rd[J1].cn /\ rj[J1].st = "Active" /\ rj[J1].behind = 0
    /\ missRec[J1].n = 0 /\ \E o \in OfJob(J1) : occ[o].st = "Started" /\ occ[o].sched)

\* @req SCN-217  nightly-export is active, 02:00 has passed, and node A's scheduler has read it as active and due. An
\*              operator pauses it (the pause records 02:00 as dropped); A's compare-and-set on the state and nextRunAt
\*              it read (impossibleAt 2): the trigger never lands on the paused job.
Init_SCN217 ==
  /\ BaseInit([CodeRj("Active") EXCEPT !.behind = 1], AllRunning("v1"))
  /\ rd = [r \in Names |-> IF r = J1 THEN [NoRd EXCEPT !.w = "Trigger", !.st = IF KeepSt THEN "Active" ELSE "none",
                                                      !.b = IF AtWrite THEN 0 ELSE 1]
                           ELSE NoRd]
Scn217_TriggerLosesToPause ==
  [][~(rj[J1].st = "Paused" /\ TriggerLanded(J1))]_varsR
\* step 1 is reachable with the trigger still in flight (vacuity of the above)
Scn217_Step1NotReached == ~(rj[J1].st = "Paused" /\ missRec[J1].how = "Pause" /\ rd[J1].w = "Trigger")

SpecSCN216 == Init_SCN216 /\ [][NextR]_varsR
SpecSCN217 == Init_SCN217 /\ [][NextR]_varsR
=============================================================================
