---------------------------- MODULE RecurringRace ----------------------------
\* Generated from specs/recurring.json (specHash 551cdd1a5b91) — edit the requirements, not this file.
\* @req INV-212  every store write that changes a recurring job's state, nextRunAt or definition, or removes it (a
\*              trigger, a schedule change, a definition update by REQ-204, REQ-212 or REQ-241, a pause, a resume, an
\*              orphaning, a restore or a removal) is a compare-and-set on the state, nextRunAt and definition it read,
\*              and for a trigger also on maintenance being off; it judges due and missed instants by the database clock
\*              at that write, changes nothing if any of them changed since the read, and the writer then reads again
\*              and decides anew.
\* Each write named in Split is a read (Read) and a later write (Write). Between them every step of Recurring can
\* happen, including the atomic form of the same write (another operator, another node). At most one split write is in
\* flight per job (A-28). What the write compares and when it judges are constants, so that INV-212 as written and the
\* readings it rules out are checked with the same spec:
\*   CasOn = {"st", "nra", "def", "maint"}, AtWrite = TRUE   INV-212 as written (run 8)
\*   CasOn without "maint"                                   run 7's wording: a trigger does not compare maintenance
\*   CasOn without "def"                                     run 7's wording: a definition write that its read judged
\*                                                           to change no schedule is not an INV-212 write and lands
\*                                                           unconditionally; the others compare state and nextRunAt
\*   CasOn without "st" / without "nra", AtWrite = FALSE, CasOn = {}   the counterfactuals of run 7
\* SchedOn = TRUE gives definitions schedule content (run 8, A-32): each release's code has a schedule, an operator
\* update sets one, and nsch says which schedule the stored nextRunAt was computed from. SchedOn = FALSE keeps the run-7
\* abstraction (A-13: "the schedule changed" is a nondeterministic choice) and leaves sch, nsch and csch constant.
\* The heartbeats (which running nodes declare a job, with which code) are not in the compare-and-set (INV-212 notes,
\* run-7 F-2 option 2): the orphan sweep, a restore, REQ-241 and REQ-203's scheduler create decide from what they read.
EXTENDS Recurring
CONSTANTS Split, CasOn, AtWrite, SchedOn
Kinds    == {"Trigger", "Update", "Reapply", "Pause", "Resume", "Orphan", "Restore", "Remove", "Create"}
SysKinds == {"Trigger", "Reapply", "Orphan", "Restore", "Create"}  \* written by the scheduler on some running node
ASSUME Split \subseteq Kinds /\ CasOn \subseteq {"st", "nra", "def", "maint"} /\ AtWrite \in BOOLEAN /\ SchedOn \in BOOLEAN
ASSUME AtWrite => "nra" \in CasOn     \* judging at the write is only defined for a write that kept the nextRunAt it read

Scheds == IF SchedOn THEN {"s1", "s2"} ELSE {"s1"}
VARIABLES rd,    \* per name: the split write in flight, between its read and its write. w = which write; st, bf, b =
                 \* state, stateBeforeOrphan and behind it read (kept only where the write can use them: with the state in
                 \* the CAS a write that lands sees the state it read, and with AtWrite it judges behind at the write);
                 \* late = newest instant judged late at the read; d = code definition chosen at the read (REQ-206,
                 \* REQ-241, REQ-203); ns = the schedule an operator update sets; sc = the schedule changed, as the read
                 \* judged it; rs = the schedule it read; cs / cn / cd = the job's state changed / nextRunAt moved /
                 \* definition changed since the read (ghosts for the CAS).
          sch,   \* per name: the stored schedule ("none" when not stored, and always when SchedOn = FALSE)
          nsch,  \* per name: the schedule the stored nextRunAt was computed from
          csch   \* per release: the schedule in its code definition, fixed per behaviour (A-32)
schv  == <<sch, nsch, csch>>
varsR == <<vars, rd, schv>>

RdRec == [w: Kinds \cup {"none"}, st: RjStatus, bf: {"Active", "Paused", "none"}, b: 0..2, late: BOOLEAN, d: Defs,
          ns: Scheds \cup {"none"}, sc: BOOLEAN, rs: Scheds \cup {"none"}, cs: BOOLEAN, cn: BOOLEAN, cd: BOOLEAN]
NoRd == [w |-> "none", st |-> "none", bf |-> "none", b |-> 0, late |-> FALSE, d |-> "none",
         ns |-> "none", sc |-> FALSE, rs |-> "none", cs |-> FALSE, cn |-> FALSE, cd |-> FALSE]
TypeInvR == /\ TypeInv /\ rd \in [Names -> RdRec]
            /\ sch \in [Names -> Scheds \cup {"none"}] /\ nsch \in [Names -> Scheds \cup {"none"}]
            /\ csch \in [Releases -> Scheds]

\* Only release v2's schedule varies: one other release is enough to have "same" and "different" schedules (A-32).
CschInit == {f \in [Releases -> Scheds] : \A v \in Releases \ {"v2"} : f[v] = "s1"}
InitS == sch = [r \in Names |-> "none"] /\ nsch = [r \in Names |-> "none"] /\ csch \in CschInit
InitR == Init /\ InitS /\ rd = [r \in Names |-> NoRd]

\* The schedule of a code definition; a runtime job is added with schedule s1 (an update can change it).
SchOf(d) == CASE d = "d1" -> csch["v1"] [] d = "d2" -> csch["v2"] [] d = "d3" -> csch["v3"] [] OTHER -> "s1"

-----------------------------------------------------------------------------
\* Atomic steps with schedule content (SchedOn): every step of Recurring, with what it does to the stored schedule and
\* to the schedule nextRunAt was computed from. A definition write's "the schedule changed" is no longer a free choice:
\* it is whether the new schedule differs from the stored one, and then nextRunAt is computed from now (REQ-227).
SameSch == UNCHANGED <<sch, nsch>>
SetSch(r, s, moved) == sch' = [sch EXCEPT ![r] = s] /\ nsch' = IF moved THEN [nsch EXCEPT ![r] = s] ELSE nsch
ClearSch(r) == sch' = [sch EXCEPT ![r] = "none"] /\ nsch' = [nsch EXCEPT ![r] = "none"]
FromSch(r, s) == UNCHANGED sch /\ nsch' = [nsch EXCEPT ![r] = s]      \* nextRunAt computed with schedule s
\* @req REQ-227, REQ-212, REQ-241  a definition write that sets schedule s: nextRunAt from now iff s is a new schedule.
SchChange(r, s) == LET ch == s # sch[r] IN rj'[r].behind = (IF ch THEN 0 ELSE rj[r].behind) /\ SetSch(r, s, ch)
Reap(r, v) == r \in Decl(v) /\ rj[r].st \in {"Active", "Paused"} /\ rj[r].origin = "code" /\ rj[r].hash # CodeDef(v)
\* @req REQ-203, REQ-204  node start: created jobs take the release's schedule; reapplied ones too, nextRunAt from now if
\*              it is a new schedule.
StartSch(v) ==
  /\ \A r \in Names : Reap(r, v) => rj'[r].behind = IF csch[v] # sch[r] THEN 0 ELSE rj[r].behind
  /\ sch'  = [r \in Names |-> IF r \in Decl(v) /\ (rj[r].st = "none" \/ Reap(r, v)) THEN csch[v] ELSE sch[r]]
  /\ nsch' = [r \in Names |-> IF r \in Decl(v) /\ rj[r].st = "none" THEN csch[v]
                              ELSE IF Reap(r, v) /\ csch[v] # sch[r] THEN csch[v] ELSE nsch[r]]
NextSch ==
  \/ \E r \in Names :
       \/ Trigger(r) /\ FromSch(r, sch[r])                       \* @req REQ-216: the next occurrence of the stored schedule
       \/ TriggerNow(r) /\ SameSch
       \/ Orphan(r) /\ (IF rj'[r].st = "none" THEN ClearSch(r) ELSE SameSch)
       \/ Restore(r) /\ SetSch(r, SchOf(rj'[r].def), TRUE)        \* @req REQ-206
       \/ OperatorAdd(r) /\ SetSch(r, "s1", TRUE)                 \* @req REQ-208
       \/ OperatorUpdate(r) /\ \E s \in Scheds : SchChange(r, s)  \* @req REQ-212, REQ-227
       \/ OperatorRemove(r) /\ ClearSch(r)
       \/ Pause(r) /\ SameSch
       \/ Resume(r) /\ FromSch(r, sch[r])                        \* @req REQ-215
       \/ TimePasses(r) /\ SameSch
       \/ ReapplyCode(r) /\ SchChange(r, SchOf(rj'[r].def))       \* @req REQ-241
       \/ CreateDeclared(r) /\ SetSch(r, SchOf(rj'[r].def), TRUE) \* @req REQ-203
  \/ \E n \in Nodes : \/ NodeStop(n) /\ SameSch
                      \/ \E v \in Releases : NodeStart(n, v) /\ StartSch(v)
  \/ \E o \in OccIds : /\ \/ StartWaiting(o) \/ Claim(o) \/ Complete(o) \/ RetryDue(o) \/ LeaseLost(o)
                          \/ AbandonOnTimeout(o) \/ ZombieEnds(o) \/ BecomeUnroutable(o) \/ Reroute(o) \/ Archive(o)
                       /\ SameSch
  \/ ToggleMaintenance /\ SameSch
NextS == IF SchedOn THEN NextSch /\ UNCHANGED csch ELSE Next /\ UNCHANGED schv

-----------------------------------------------------------------------------
\* What each read checks: the guard of the atomic action in Recurring.
Guard(r, k) ==
  CASE k = "Trigger" -> TriggerGuard(r)                                                  \* @req REQ-216
    [] k = "Update"  -> UpdateGuard(r)                                                   \* @req REQ-212, REQ-227
    [] k = "Reapply" -> SchedulerRuns /\ Stale(r)                                        \* @req REQ-241
    [] k = "Pause"   -> rj[r].st = "Active"                                              \* @req REQ-214
    [] k = "Resume"  -> rj[r].st = "Paused"                                              \* @req REQ-215
    [] k = "Orphan"  -> OrphanGuard(r)                                                   \* @req REQ-205, REQ-207
    [] k = "Restore" -> rj[r].st = "Orphaned" /\ DeclaringNodes(r) # {}                  \* @req REQ-206
    [] k = "Remove"  -> RemoveGuard(r)                                                   \* @req REQ-213
    [] k = "Create"  -> CreateGuard(r)                                                   \* @req REQ-203
DefsAt(r) == {CodeDef(node[n].ver) : n \in DeclaringNodes(r)}
Lates(k)   == IF k = "Trigger" /\ ~AtWrite THEN BOOLEAN ELSE {FALSE}
DefsOf(r, k) == IF k \in {"Reapply", "Restore", "Create"} THEN DefsAt(r) ELSE {"none"}
NewSchs(k) == IF k = "Update" THEN Scheds ELSE {"none"}
\* "the schedule changed" as the read judges it: against the schedule it read (SchedOn), or a free choice (A-13).
ScOf(r, k, d, ns) ==
  IF k \notin {"Update", "Reapply"} THEN {FALSE}
  ELSE IF SchedOn THEN {(IF k = "Update" THEN ns ELSE SchOf(d)) # sch[r]}
  ELSE BOOLEAN
KeepSt == "st" \notin CasOn
Snap(r, k, late, d, ns, sc) ==
  [w |-> k, st |-> IF KeepSt THEN rj[r].st ELSE "none",
   bf |-> IF k = "Restore" /\ KeepSt THEN rj[r].before ELSE "none",
   b |-> IF AtWrite THEN 0 ELSE rj[r].behind, late |-> late, d |-> d, ns |-> ns, sc |-> sc, rs |-> sch[r],
   cs |-> FALSE, cn |-> FALSE, cd |-> FALSE]
NewRead(r, k) ==
  \E late \in Lates(k), d \in DefsOf(r, k), ns \in NewSchs(k) :
    \E sc \in ScOf(r, k, d, ns) : rd' = [rd EXCEPT ![r] = Snap(r, k, late, d, ns, sc)]
\* the state and stateBeforeOrphan the write's read saw (with the state in the CAS, a write that lands sees them still)
ReadSt(r) == IF KeepSt THEN rd[r].st ELSE rj[r].st
ReadBf(r) == IF KeepSt THEN rd[r].bf ELSE rj[r].before

\* @req INV-212  the read.
Read(r, k) ==
  /\ rd[r].w = "none" /\ Guard(r, k)
  /\ NewRead(r, k)
  /\ UNCHANGED <<vars, schv>>

\* @req INV-212  "after which the writer reads the job again and decides anew": if its guard no longer holds it has
\*              nothing to do and stops; otherwise it is a new read. Written as one step with the lost write: the
\*              lost write changes nothing, so a step in between is the same as a step before it (A-28).
Again(r) == IF Guard(r, rd[r].w) THEN NewRead(r, rd[r].w) ELSE rd' = [rd EXCEPT ![r] = NoRd]

\* "Missed" as the write judges it (REQ-234, REQ-242): by the database clock at the write, or as the read saw it.
Missed(r) == IF AtWrite THEN HasMissed(r) ELSE ReadSt(r) = "Active" /\ rd[r].b >= 1
\* Run 7's wording (CasOn without "def"): a definition write that its read judged to change no schedule changes neither
\* state nor nextRunAt, so it is not an INV-212 write and lands unconditionally.
Exempt(r) == "def" \notin CasOn /\ rd[r].w \in {"Update", "Reapply"} /\ ~rd[r].sc
\* @req INV-212  the compare-and-set loses when something it compares changed since the read.
\* @req REQ-203  a create is an insert keyed by name (A-8): it fails when the name is stored by then.
Lost(r) ==
  IF rd[r].w = "Create" THEN rj[r].st # "none"
  ELSE /\ ~Exempt(r)
       /\ \/ "st" \in CasOn /\ rd[r].cs
          \/ "nra" \in CasOn /\ rd[r].cn
          \/ "def" \in CasOn /\ rd[r].cd
          \/ "maint" \in CasOn /\ rd[r].w = "Trigger" /\ maint                          \* @req INV-210, REQ-216

SchW(A) == IF SchedOn THEN A ELSE UNCHANGED <<sch, nsch>>
\* @req INV-212, REQ-216, REQ-212, REQ-241, REQ-214, REQ-215, REQ-205, REQ-207, REQ-206, REQ-213, REQ-203, REQ-242
\* The write. Lost: nothing changes, the writer reads again (Again). A job whose row is gone (removed) is not written by an
\* unconditional write either (an UPDATE that finds no row). Otherwise it lands the same ...Write as the atomic action,
\* with what the read decided (the state recorded by an orphaning, the definition a restore, REQ-241 or a create takes,
\* the schedule an update sets and whether it changed, the schedule a trigger or a resume computes nextRunAt from) and
\* the missed instants judged as AtWrite says.
Write(r) ==
  LET k == rd[r].w IN
  /\ k # "none"
  /\ IF Lost(r)
       THEN Again(r) /\ UNCHANGED <<vars, schv>>
     ELSE IF k # "Create" /\ rj[r].st = "none"
       THEN rd' = [rd EXCEPT ![r] = NoRd] /\ UNCHANGED <<vars, schv>>
     ELSE /\ rd' = [rd EXCEPT ![r] = NoRd]
          /\ UNCHANGED csch
          /\ CASE k = "Trigger" -> /\ \E nl \in (IF AtWrite THEN BOOLEAN ELSE {rd[r].late}) :
                                        TriggerWrite(r, IF AtWrite THEN rj[r].behind ELSE rd[r].b, nl)
                                   /\ SchW(FromSch(r, rd[r].rs))
               [] k = "Update"  -> UpdateWrite(r, rd[r].sc, Missed(r)) /\ SchW(SetSch(r, rd[r].ns, rd[r].sc))
               [] k = "Reapply" -> /\ ReapplyWrite(r, rd[r].d, rd[r].sc, Missed(r))
                                   /\ SchW(SetSch(r, SchOf(rd[r].d), rd[r].sc))
               [] k = "Pause"   -> PauseWrite(r, Missed(r)) /\ SchW(SameSch)
               [] k = "Resume"  -> ResumeWrite(r) /\ SchW(FromSch(r, rd[r].rs))
               [] k = "Orphan"  -> /\ OrphanWrite(r, ReadSt(r), Missed(r))
                                   /\ SchW(IF op[r] = "Delete" THEN ClearSch(r) ELSE SameSch)
               [] k = "Restore" -> RestoreWrite(r, ReadBf(r), rd[r].d) /\ SchW(SetSch(r, SchOf(rd[r].d), TRUE))
               [] k = "Remove"  -> RemoveWrite(r, Missed(r)) /\ SchW(ClearSch(r))
               [] k = "Create"  -> CreateWrite(r, rd[r].d) /\ SchW(SetSch(r, SchOf(rd[r].d), TRUE))

\* Ghosts for the compare-and-set: a step changes the job's state; moves nextRunAt (behind goes down, the job enters
\* Active, leaves Orphaned or is removed, or nextRunAt is computed from another schedule); or changes its definition
\* (content, hash, origin or schedule). Without schedule content a schedule change with behind already 0 is not seen,
\* and nor is an edit of a definition that is already "edited" (A-27).
StCh(r)  == rj'[r].st # rj[r].st
NraCh(r) == \/ rj'[r].behind < rj[r].behind
            \/ StCh(r) /\ (rj'[r].st \in {"Active", "none"} \/ rj[r].st = "Orphaned")
            \/ nsch'[r] # nsch[r]
DefCh(r) == rj'[r].def # rj[r].def \/ rj'[r].hash # rj[r].hash \/ rj'[r].origin # rj[r].origin \/ sch'[r] # sch[r]
\* Every step of Recurring. A node that stops may take an in-flight scheduler write with it (it never lands); when
\* no node runs, it does (A-29). With state, nextRunAt and definition all in the CAS, any change dooms the write, so the
\* ghosts are set together (fewer states, same futures); cs and cd are kept only where the CAS compares them.
Full == {"st", "nra", "def"} \subseteq CasOn
RdUpd ==
  LET stopped == \E n \in Nodes : node[n].st = "Running" /\ node'[n].st = "Down"
      allDown == \A n \in Nodes : node'[n].st = "Down"
  IN \E drop \in (IF ~stopped THEN {FALSE} ELSE IF allDown THEN {TRUE} ELSE BOOLEAN) :
       rd' = [r \in Names |->
                IF rd[r].w = "none" THEN rd[r]
                ELSE IF drop /\ rd[r].w \in SysKinds THEN NoRd
                ELSE LET cs  == rd[r].cs \/ ("st" \in CasOn /\ StCh(r))
                         cn  == rd[r].cn \/ NraCh(r)
                         cd  == rd[r].cd \/ ("def" \in CasOn /\ DefCh(r))
                         any == cs \/ cn \/ cd
                     IN [rd[r] EXCEPT !.cs = IF Full THEN any ELSE cs, !.cn = IF Full THEN any ELSE cn,
                                      !.cd = IF Full THEN any ELSE cd]]
Atomic == NextS /\ RdUpd

NextR == Atomic \/ \E r \in Names : (\E k \in Split : Read(r, k)) \/ Write(r)
SpecR == InitR /\ [][NextR]_varsR
\* The writer's own steps are system steps (the call is in flight), so they are fair; nothing else is assumed.
FairR == \A r \in Names : WF_varsR(Write(r))
SpecRL == SpecR /\ FairR
\* Convergence (run 8): also the scheduler's own steps (actor system): REQ-203's create, the orphan sweep, REQ-241.
FairSched == \A r \in Names : /\ WF_varsR(Atomic /\ CreateDeclared(r)) /\ WF_varsR(Atomic /\ Orphan(r))
                              /\ WF_varsR(Atomic /\ ReapplyCode(r))
SpecRC == SpecRL /\ FairSched
\* Not the requirements as written: REQ-206 (actor Host) also weakly fair, the run-8 finding's option 1.
SpecRCF == SpecRC /\ \A r \in Names : WF_varsR(Atomic /\ Restore(r))

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

\* @req REQ-203  run 8: a code-defined job is created only while a running worker node declares it (judged after the
\*              step, so a node start that creates the jobs it declares counts).
Prop_CodeJobCreatedOnlyDeclared ==
  [][\A r \in Names : rj[r].st = "none" /\ rj'[r].st # "none" /\ rj'[r].origin = "code" =>
        \E n \in Nodes : node'[n].st = "Running" /\ r \in Decl(node'[n].ver)]_vars

\* @req REQ-242  Prop_RecordSaysOutcome for the cfgs that split a write deciding from the heartbeats: the record names the
\*              step that wrote it, where that step may be the split write itself. Such a write is not a step of the atomic
\*              model when a node started or stopped since its read (INV-212 notes accept it), so Prop_RecordSaysOutcome,
\*              which names the atomic actions, would fail on a correct record. Everything else is the same.
Landed(r, k) == rd[r].w = k /\ rd'[r] = NoRd /\ rj'[r] # rj[r] /\ node' = node
Prop_RecordSaysOutcomeR ==
  [][\A r \in Names : missRec'[r] # missRec[r] =>
        CASE missRec'[r].how \in {"Started", "Waiting", "Skipped"} ->
               /\ MissedTrigger(r) /\ mf[r] # "Skip" /\ missRec'[r].occ # NULL
               /\ occ[missRec'[r].occ].st = "none" /\ occ'[missRec'[r].occ].st = missRec'[r].how
               /\ occ'[missRec'[r].occ].rj = r /\ occ'[missRec'[r].occ].sched
          [] missRec'[r].how = "Misfire"  -> MissedTrigger(r) /\ mf[r] = "Skip"
          [] missRec'[r].how = "Schedule" -> (ScheduleChange(r) \/ Landed(r, "Reapply") \/ Landed(r, "Update"))
                                             /\ rj'[r].st = "Active"
          [] missRec'[r].how = "Pause"    -> Pause(r) \/ Landed(r, "Pause")
          [] missRec'[r].how = "Orphan"   -> (Orphan(r) \/ Landed(r, "Orphan")) /\ rj'[r].st = "Orphaned"
          [] missRec'[r].how = "Removed"  -> (Orphan(r) \/ OperatorRemove(r) \/ Landed(r, "Orphan") \/ Landed(r, "Remove"))
                                             /\ rj'[r].st = "none"
          [] OTHER -> FALSE]_varsR

\* @req REQ-227, REQ-204, REQ-212, REQ-241, INV-212  run-7 F-3: the stored nextRunAt is computed from the stored
\*              schedule. A definition write that stores a schedule other than the one nextRunAt came from, without
\*              computing nextRunAt from now, leaves a nextRunAt that belongs to neither (SchedOn only).
Inv_NextRunAtFromStoredSchedule == SchedOn => \A r \in Names : rj[r].st # "none" => nsch[r] = sch[r]

\* @req INV-212  a writer that loses eventually acts or finds nothing to do, unless the job's state, nextRunAt or
\*              definition keeps changing under it for ever (obstruction-free: no stuck writer). Checked with SpecRL.
Bump(r) == \/ rj'[r].st # rj[r].st \/ rj'[r].behind < rj[r].behind
           \/ rj'[r].def # rj[r].def \/ rj'[r].hash # rj[r].hash \/ sch'[r] # sch[r] \/ nsch'[r] # nsch[r]
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
  /\ InitS
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
  /\ InitS
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
