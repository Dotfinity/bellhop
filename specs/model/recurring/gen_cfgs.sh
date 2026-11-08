#!/bin/sh
# Regenerates the non-scenario cfgs of the Recurring model. Run from specs/model/recurring.
# Constant sets: MAIN (1 job, triggering/misfire/maintenance), DEFS (2 jobs, reconciliation),
# QUEUE1/QUEUE2 (Queue policy, 3 slots), ALL (all overlap policies, 2 slots), PROBE (3 releases),
# PROBE2/SETTLE3 (two nodes on 2 or 3 releases, for REQ-241), ALLOW3 (Allow/CancelPrevious, 3 slots).
# The last value is RerouteOn: jobs REQ-125 (Unroutable -> Enqueued) is explored only in the *R sets,
# so that the run-1 overlap fixes and the Unroutable rules (REQ-239, REQ-240) are checked separately.
# Run 3: REQ-240 is a requirement now, so the run-2 FixCancelUnroutable switch is gone.
# Run 4: MISALL is MAIN with all three misfire policies, for REQ-242's missed-instant record.
# Run 5: REQ-242 also records schedule changes, so its three properties (REC) run in Defs and the REQ-241 cfgs too.
# Run 6: REQ-242 also records pauses, orphanings and removals, and REQ-234 makes every passed-over instant missed; the
# run-5 F-1/F-2 probes are now the regression checks in REC, and PROBEOD is PROBE with both orphan policies.
# Run 8: SPEC chooses the specification of a Recurring cfg (default Spec); DEFR, LIVE3 and LIVE3D are new sets (see below).
consts() {
  case $1 in
    MAIN)   set -- "{j1}" "{o1, o2}" "{a}" '{"v1"}' "{j1}" "{}" "{}" "{}" 1 '{"Skip", "Queue"}' '{"RunOnce", "Skip"}' '{"Orphan"}' FALSE ;;
    DEFS)   set -- "{j1, j2}" "{}" "{a, b}" '{"v1", "v2"}' "{j1, j2}" "{j1}" "{}" "{j1}" 1 '{"Skip"}' '{"RunOnce"}' '{"Orphan", "Delete"}' FALSE ;;
    QUEUE1) set -- "{j1}" "{o1, o2, o3}" "{a}" '{"v1"}' "{}" "{}" "{}" "{}" 1 '{"Queue"}' '{"RunOnce"}' '{"Orphan"}' FALSE ;;
    QUEUE2) set -- "{j1}" "{o1, o2, o3}" "{a}" '{"v1"}' "{}" "{}" "{}" "{}" 2 '{"Queue"}' '{"RunOnce"}' '{"Orphan"}' FALSE ;;
    MAINR)  set -- "{j1}" "{o1, o2}" "{a}" '{"v1"}' "{j1}" "{}" "{}" "{}" 1 '{"Skip", "Queue"}' '{"RunOnce", "Skip"}' '{"Orphan"}' TRUE ;;
    ALL)    set -- "{j1}" "{o1, o2}" "{a}" '{"v1"}' "{j1}" "{}" "{}" "{}" 1 '{"Skip", "Queue", "Allow", "CancelPrevious"}' '{"RunOnce"}' '{"Orphan"}' FALSE ;;
    ALLR)   set -- "{j1}" "{o1, o2}" "{a}" '{"v1"}' "{j1}" "{}" "{}" "{}" 1 '{"Skip", "Queue", "Allow", "CancelPrevious"}' '{"RunOnce"}' '{"Orphan"}' TRUE ;;
    PROBE2) set -- "{j1}" "{o1}" "{a, b}" '{"v1", "v2"}' "{j1}" "{j1}" "{}" "{}" 1 '{"Skip"}' '{"RunOnce"}' '{"Orphan"}' FALSE ;;
    PROBE)  set -- "{j1}" "{o1}" "{a}" '{"v1", "v2", "v3"}' "{j1}" "{j1}" "{}" "{}" 1 '{"Skip"}' '{"RunOnce"}' '{"Orphan"}' FALSE ;;
    PROBEOD) set -- "{j1}" "{o1}" "{a}" '{"v1", "v2", "v3"}' "{j1}" "{j1}" "{}" "{}" 1 '{"Skip"}' '{"RunOnce"}' '{"Orphan", "Delete"}' FALSE ;;
    QUEUE1R) set -- "{j1}" "{o1, o2, o3}" "{a}" '{"v1"}' "{}" "{}" "{}" "{}" 1 '{"Queue"}' '{"RunOnce"}' '{"Orphan"}' TRUE ;;
    ALLOW3) set -- "{j1}" "{o1, o2, o3}" "{a}" '{"v1"}' "{j1}" "{}" "{}" "{}" 1 '{"Allow", "CancelPrevious"}' '{"RunOnce"}' '{"Orphan"}' FALSE ;;
    MISALL) set -- "{j1}" "{o1, o2}" "{a}" '{"v1"}' "{j1}" "{}" "{}" "{}" 1 '{"Skip", "Queue"}' '{"RunOnce", "Skip", "RunAll"}' '{"Orphan"}' FALSE ;;
    ORPH2)  set -- "{j1}" "{o1}" "{a, b}" '{"v1", "v2", "v3"}' "{j1}" "{j1}" "{}" "{}" 1 '{"Skip"}' '{"RunOnce"}' '{"Orphan", "Delete"}' FALSE ;;
    LIVE)   set -- "{j1}" "{o1}" "{a}" '{"v1"}' "{j1}" "{}" "{}" "{}" 1 '{"Skip"}' '{"RunOnce"}' '{"Orphan"}' FALSE ;;
    LIVE2)  set -- "{j1}" "{}" "{a, b}" '{"v1", "v3"}' "{j1}" "{}" "{}" "{}" 1 '{"Skip"}' '{"RunOnce"}' '{"Orphan", "Delete"}' FALSE ;;
    DEFR)   set -- "{j1}" "{o1}" "{a, b}" '{"v1", "v2"}' "{j1}" "{j1}" "{}" "{j1}" 1 '{"Skip"}' '{"RunOnce"}' '{"Orphan"}' FALSE ;;
    LIVE3)  set -- "{j1}" "{}" "{a, b}" '{"v1", "v2", "v3"}' "{j1}" "{j1}" "{}" "{}" 1 '{"Skip"}' '{"RunOnce"}' '{"Orphan", "Delete"}' FALSE ;;
    LIVE3D) set -- "{j1}" "{}" "{a, b}" '{"v1", "v2", "v3"}' "{j1}" "{j1}" "{}" "{}" 1 '{"Skip"}' '{"RunOnce"}' '{"Delete"}' FALSE ;;
    SETTLE3) set -- "{j1}" "{o1}" "{a, b}" '{"v1", "v2", "v3"}' "{j1}" "{j1}" "{j1}" "{j1}" 1 '{"Skip"}' '{"RunOnce"}' '{"Orphan"}' FALSE ;;
  esac
  printf 'CONSTANTS\n  Names = %s\n  OccIds = %s\n  Nodes = %s\n  Releases = %s\n  DeclV1 = %s\n  DeclV2 = %s\n  DeclV3 = %s\n  Override = %s\n  MaxQueued = %s\n  OverlapPolicies = %s\n  MisfirePolicies = %s\n  OrphanPolicies = %s\n  RerouteOn = %s\n  NULL = NULL\n' "$@"
}
# cfg <file> <constant set> <comment> <checks...>   (Prop_*, Liv_* and ProbeAct_* go under PROPERTIES)
cfg() {
  f=$1; c=$2; h=$3; shift 3
  { printf '%s %s\nSPECIFICATION %s\n' '\*' "$h" ${SPEC:-Spec}; consts $c; printf 'INVARIANTS\n'
    for i in "$@"; do case $i in Prop_*|Liv_*|ProbeAct_*) ;; *) printf '  %s\n' $i ;; esac; done
    for i in "$@"; do case $i in Prop_*|Liv_*|ProbeAct_*) printf 'PROPERTIES\n  %s\n' $i ;; esac; done; } > $f
}
H='expected to hold; run with --stop-at-first (TLC 2.19 -continue can crash).'
V='expected VIOLATED; run with --stop-at-first, the trace is the example.'
P='Probe (modeling aid, not a requirement):'
R='regression check for a run-1 finding; expected to hold.'
R2='regression check for a run-2 finding; expected to hold.'
R4='regression check for a run-4 finding; expected to hold.'
R5='regression check for a run-5 finding; expected to hold.'
REC="Prop_MissRecordOnlyByMove Prop_MissedMoveRecordsOnce Prop_RecordSaysOutcome Prop_NoInstantRecordedTwice Prop_LeaveRecordsMissed Prop_PassedInstantRunsOrIsRecorded"
MAINCHK="TypeInv Inv_NoScheduleWhilePaused Inv_NoScheduleInMaintenance Inv_MaxQueued Scn_SecondCasImpossible Prop_NoScheduledAdvanceInMaintenance Prop_PauseOrphanRemoveSkipsWaiting Prop_SkipOnlyWhenInTheWay $REC"
cfg Recurring.cfg               MAIN   "Main run: triggering, misfire, maintenance, overlap with 2 slots; $H" $MAINCHK Inv_NoOverlapProcessing
cfg Recurring_MainR.cfg         MAINR  "Main run with jobs REQ-125 explored (REQ-240 makes INV-204 checkable here too); $H" $MAINCHK Inv_NoOverlapProcessing
cfg Recurring_Misfire.cfg       MISALL "REQ-242 missed-instant record under all three misfire policies, plus the main checks; $H" $MAINCHK Inv_NoOverlapProcessing
cfg Recurring_Defs.cfg          DEFS   "Definitions and reconciliation, no occurrence slots; $H" TypeInv Scn_CodeJobNotEditable Scn_CodeJobNotRemovable Scn_NoOrphanWhileDeclared Scn_StoredNameCannotBeAdded Scn_RuntimeNameBlocksStart Prop_PauseOrphanRemoveSkipsWaiting $REC
cfg Recurring_OverlapQueue.cfg  QUEUE1 "Overlap Queue(1), 3 slots; $H" TypeInv Inv_MaxQueued Prop_PauseOrphanRemoveSkipsWaiting Prop_SkipOnlyWhenInTheWay
cfg Recurring_OverlapQueue2.cfg QUEUE2 "Overlap Queue(2), 3 slots; $H" TypeInv Inv_MaxQueued Prop_SkipOnlyWhenInTheWay
cfg Recurring_OverlapAll.cfg    ALL    "Overlap, all four policies, 2 slots; $H" TypeInv Inv_MaxQueued Inv_NoOverlapProcessing Prop_SkipOnlyWhenInTheWay
cfg Recurring_F_RunningHandlers.cfg MAIN   "REQ-238 (info, run-1 F-3): an abandoned or lease-lost handler still runs beside the next job; $V" Inv_NoOverlapRunning
cfg Recurring_F_WaitingRace.cfg     QUEUE1 "Run-1 F-1, INV-204 Queue(1) race; $R" Inv_NoOverlapProcessing
cfg Recurring_F_RerouteOverlap.cfg  ALLR   "Run-2 F-1: INV-204 and the REQ-239 skip rule with jobs REQ-125 and REQ-240, all four policies; $R2" Inv_NoOverlapProcessing Prop_SkipOnlyWhenInTheWay Note240_OneUnroutableSkipQueue
cfg Recurring_F_RerouteQueue.cfg    QUEUE1R "Run-2 F-1: INV-204, REQ-233, REQ-237 and the REQ-239 skip rule with jobs REQ-125 and REQ-240, Queue(1), 3 slots; $R2" TypeInv Inv_MaxQueued Inv_NoOverlapProcessing Prop_PauseOrphanRemoveSkipsWaiting Prop_SkipOnlyWhenInTheWay Note240_OneUnroutableSkipQueue
cfg Recurring_P_QueueTwoWaiters.cfg QUEUE2 "Run-1 F-2: $P Queue(2) newer waiting occurrence beside an older unfinished one; $R" Probe_NewerWaiterStartsBesideOlder Inv_NoOverlapProcessing
cfg Recurring_P_StaleDefinition.cfg PROBE  "Run-1 F-5: $P restored orphan keeps a stale definition; $R" Probe_StaleDefinitionAfterRestore
cfg Recurring_P_RuntimeTakenOver.cfg PROBE "Run-1 F-6: $P runtime job rewritten by code; $R" Probe_RuntimeJobTakenOverByCode
cfg Recurring_P_UnroutableBlocks.cfg ALL   "Run-1 F-7: an unroutable job never blocks the next occurrence; $R" Prop_SkipOnlyWhenInTheWay
cfg Recurring_P_StaleDefinition2.cfg PROBE2 "Run-2 F-2 window: $P two nodes on releases v1/v2: stored code definition stale for every running node. REQ-241 closes it one step later, so the moment is still reachable; $V" Probe_StaleDefinitionAfterRestore
cfg Recurring_Liv_Settles.cfg       PROBE2 "Run-2 F-2: REQ-241 settling under weak fairness of the scheduler, two nodes on v1/v2; $R2" TypeInv Prop_StaleOnlyWhenNodeStops Liv_DefinitionSettles $REC
cfg Recurring_Liv_Settles3.cfg      SETTLE3 "Run-2 F-2: REQ-241 settling, two nodes on three releases, runtime override allowed; $R2" TypeInv Prop_StaleOnlyWhenNodeStops Liv_DefinitionSettles $REC
cfg Recurring_P_Req225Unroutable.cfg ALLOW3 "Run 3 (A-18): $P a REQ-225 start (Allow/CancelPrevious) can meet an earlier Unroutable job; $V" Probe_Req225StartMeetsUnroutable
cfg Recurring_P_TriggerNowSuperseded.cfg MAIN "Run 3: $P REQ-240 cancels an Unroutable trigger-now run when a scheduled occurrence starts; $V" ProbeAct_TriggerNowNeverSuperseded
cfg Recurring_P_OneUnroutable.cfg   ALL    "Run 4: $P REQ-240's notes say a recurring job never holds two Unroutable jobs; all four policies; $V" Probe_OneUnroutablePerJob
cfg Recurring_F_OverdueRecorded.cfg PROBE  "Run-4 F-1: overdue instants of an active job dropped by a schedule change (REQ-204, REQ-241, REQ-212) are recorded by REQ-242; $R4" TypeInv $REC
cfg Recurring_P_CatchUpSkipped.cfg  MAIN   "Run 4: $P a RunOnce catch-up occurrence recorded by REQ-242 is skipped by the overlap policy (run 5: the record now says Skipped, Prop_RecordSaysOutcome); $V" ProbeAct_CatchUpNeverSkipped
cfg Recurring_F_OverduePaused.cfg   MAIN    "Run-5 F-1: instants missed while active are recorded when the job is paused or removed (REQ-214, REQ-213); $R5" TypeInv $REC
cfg Recurring_F_OverdueOrphaned.cfg PROBEOD "Run-5 F-1: ... or orphaned or deleted by the orphan sweep (REQ-205, REQ-207), outage-then-deploy; $R5" TypeInv $REC
cfg Recurring_F_PassedInstant.cfg   MAIN    "Run-5 F-2: a passed, not-yet-triggered instant passed over by a schedule change is recorded (REQ-234); $R5" TypeInv Prop_PassedInstantRunsOrIsRecorded Prop_MissRecordOnlyByMove
cfg Recurring_P_RecordedWaiterSkipped.cfg MAIN "Run-5 F-3 (accepted in REQ-242's notes): $P a REQ-242 record that says the catch-up occurrence is waiting, then REQ-237 skips it; $V" ProbeAct_RecordedWaiterNeverSkipped
# Run 8 (REQ-203 also from the scheduler): convergence of the stored definitions to what running nodes declare, in the
# atomic model. LIVE3 is two nodes on three releases (v1 and v2 declare j1, v3 does not), no occurrence slots.
SPEC=Spec; cfg Recurring_Liv_Converge.cfg    LIVE3 "Run 8: a declared code-defined job is eventually stored, not orphaned, with a declaring node's code (fairness as written: REQ-206's actor is Host, not fair); $V" Liv_DeclaredConverges
SPEC=SpecRestoreFair; cfg Recurring_Liv_ConvergeOpt.cfg LIVE3 "Run 8 finding option 1: the same with REQ-206 weakly fair (actor system); $H" Liv_DeclaredConverges
SPEC=Spec
cfg Recurring_Liv_ConvergeDel.cfg LIVE3D "Run 8: the same with orphanPolicy Delete only: REQ-203's scheduler branch re-creates, fairness as written; $H" Liv_DeclaredConverges
# Run 7/8 (INV-212): RecurringRace.tla splits every write named in Split into a read and a write (SpecR). The
# constants say what the write compares (CasOn), when it judges (AtWrite) and whether definitions have schedule content
# (SchedOn); INV-212 as written (run 8) is CasOn = {"st", "nra", "def", "maint"}, AtWrite = TRUE.
# ORPH2 is PROBEOD with two nodes, so a node can start (and declare the job) while another node's sweep is in flight.
# DEFR is two nodes on v1/v2, both declaring j1 with AllowRuntimeOverride: an operator edit can race REQ-241.
# LIVE, LIVE2 and LIVE3 are the smallest sets, for the liveness checks.
race() {
  f=$1; c=$2; split=$3; cas=$4; atw=$5; sch=$6; h=$7; shift 7
  spec=SpecR; for i in "$@"; do case $i in Liv_WriterSettles*) spec=SpecRL ;; Liv_DeclaredConverges) spec=$RSPEC ;; esac; done
  { printf '%s %s\nSPECIFICATION %s\n' '\*' "$h" $spec; consts $c
    printf '  Split = %s\n  CasOn = %s\n  AtWrite = %s\n  SchedOn = %s\nINVARIANTS\n' "$split" "$cas" $atw $sch
    for i in "$@"; do case $i in Prop_*|Liv_*|Scn217_*) ;; *) printf '  %s\n' $i ;; esac; done
    printf 'PROPERTIES\n'; for i in "$@"; do case $i in Prop_*|Liv_*|Scn217_*) printf '  %s\n' $i ;; esac; done; } > $f
}
FULL='{"st", "nra", "def", "maint"}'; NOMAINT='{"st", "nra", "def"}'; NODEF='{"st", "nra", "maint"}'
NOST='{"nra", "def", "maint"}'; NONRA='{"st", "def", "maint"}'; NONE='{}'
RREC="Prop_RecordOnlyUnhandledInstants $REC"
RST="Prop_NoScheduledOccurrenceWhilePaused Prop_OneOccurrencePerInstant Prop_OrphanRecordsCurrentState Prop_LeaveOrphanedOnlyToStateBefore"
RBASE="TypeInvR Inv_NoScheduleWhilePaused Inv_MaxQueued Prop_PauseOrphanRemoveSkipsWaiting Prop_NoTriggerWriteInMaintenance $RREC $RST"
RH="INV-212 as written; $H"
CF='counterfactual (not INV-212 as written): expected VIOLATED; run with --stop-at-first, the trace shows that part of INV-212 is needed.'
AC='accepted transient (INV-212 and REQ-207 notes): expected VIOLATED; run with --stop-at-first.'
# INV-212 as written, one split write per cfg (A-28), each with every check including Prop_Refines. The four writes that
# also decide from the heartbeats (orphan sweep, restore, REQ-241, REQ-203's create) are not steps of Recurring when a
# node started or stopped since their read, which INV-212's notes accept, so they run without Prop_Refines, with the race
# form of Prop_RecordSaysOutcome, and without the heartbeat properties that the accepted transient breaks (those run on
# their own as Race_*Decl): Orphan - CodeJobLeavesOnlyUndeclared; Restore and Reapply - RestoreOnlyDeclared or
# StaleOnlyWhenNodeStops; Create - CodeJobCreatedOnlyDeclared and StaleOnlyWhenNodeStops.
RALL="$RBASE Prop_Refines"
RDECL="Prop_RestoreOnlyDeclared Prop_CodeJobLeavesOnlyUndeclared Prop_StaleOnlyWhenNodeStops Prop_CodeJobCreatedOnlyDeclared"
# For the heartbeat writes, Prop_RecordSaysOutcome (which names the atomic actions) is replaced by its race form, which
# also accepts the split write itself as the step that wrote the record.
RBASEH=$(echo "$RBASE" | sed 's/Prop_RecordSaysOutcome/Prop_RecordSaysOutcomeR/')
race Recurring_Race_Pause.cfg      MAIN  '{"Pause"}'   "$FULL" TRUE FALSE "Run 8: pause split, 1 job, 2 slots; $RH" $RALL Inv_NoOverlapProcessing
race Recurring_Race_Resume.cfg     MAIN  '{"Resume"}'  "$FULL" TRUE FALSE "Run 8: resume split, 1 job, 2 slots; $RH" $RALL Inv_NoOverlapProcessing
race Recurring_Race_Update.cfg     MAIN  '{"Update"}'  "$FULL" TRUE FALSE "Run 8: operator definition update split (schedule changed or not), 1 job, 2 slots; $RH" $RALL Inv_NoOverlapProcessing
race Recurring_Race_Remove.cfg     MAIN  '{"Remove"}'  "$FULL" TRUE FALSE "Run 8: operator removal split, 1 job, 2 slots; $RH" $RALL Inv_NoOverlapProcessing
race Recurring_Race_Trigger.cfg    MAIN  '{"Trigger"}' "$FULL" TRUE FALSE "Run 8: trigger split, its write also requires maintenance off (run-7 F-1); $RH" $RALL Inv_NoOverlapProcessing
race Recurring_Race_UpdateSch.cfg  MAIN  '{"Update"}'  "$FULL" TRUE TRUE "Run 8: operator update split, definitions with schedule content (run-7 F-3); $RH" $RALL Inv_NextRunAtFromStoredSchedule
race Recurring_Race_ResumeSch.cfg  MAIN  '{"Resume"}'  "$FULL" TRUE TRUE "Run 8: resume split, definitions with schedule content; $RH" $RALL Inv_NextRunAtFromStoredSchedule
race Recurring_Race_TriggerSch.cfg MAIN  '{"Trigger"}' "$FULL" TRUE TRUE "Run 8: trigger split, definitions with schedule content; $RH" $RALL Inv_NextRunAtFromStoredSchedule
race Recurring_Race_ReapplySch.cfg DEFR  '{"Reapply"}' "$FULL" TRUE TRUE "Run 8: REQ-241 split racing operator edits (AllowRuntimeOverride), schedule content (run-7 F-3); heartbeats not compared (accepted); $RH" $RBASEH Prop_RestoreOnlyDeclared Prop_CodeJobLeavesOnlyUndeclared Prop_CodeJobCreatedOnlyDeclared Inv_NextRunAtFromStoredSchedule
race Recurring_Race_UpdateSchO.cfg DEFR  '{"Update"}'  "$FULL" TRUE TRUE "Run 8: operator edit of a code-defined job split, racing REQ-241 and node starts, schedule content; $RH" $RALL $RDECL Inv_NextRunAtFromStoredSchedule
race Recurring_Race_OPause.cfg     ORPH2 '{"Pause"}'   "$FULL" TRUE FALSE "Run 8: pause split, two nodes, three releases, both orphan policies; $RH" $RALL $RDECL
race Recurring_Race_OResume.cfg    ORPH2 '{"Resume"}'  "$FULL" TRUE FALSE "Run 8: resume split, two nodes, three releases, both orphan policies; $RH" $RALL $RDECL
race Recurring_Race_ORemove.cfg    ORPH2 '{"Remove"}'  "$FULL" TRUE FALSE "Run 8: removal (of an orphan, REQ-213) split, two nodes, three releases; $RH" $RALL $RDECL
race Recurring_Race_Orphan.cfg     ORPH2 '{"Orphan"}'  "$FULL" TRUE FALSE "Run 8: orphan sweep split; heartbeats not compared (accepted); every other check; $RH" $RBASEH Prop_RestoreOnlyDeclared Prop_StaleOnlyWhenNodeStops Prop_CodeJobCreatedOnlyDeclared
race Recurring_Race_Restore.cfg    ORPH2 '{"Restore"}' "$FULL" TRUE FALSE "Run 8: restore split; heartbeats not compared (accepted); every other check; $RH" $RBASEH Prop_CodeJobLeavesOnlyUndeclared Prop_CodeJobCreatedOnlyDeclared
race Recurring_Race_Reapply.cfg    ORPH2 '{"Reapply"}' "$FULL" TRUE FALSE "Run 8: REQ-241 split; heartbeats not compared (accepted); every other check; $RH" $RBASEH Prop_RestoreOnlyDeclared Prop_CodeJobLeavesOnlyUndeclared Prop_CodeJobCreatedOnlyDeclared
race Recurring_Race_Create.cfg     ORPH2 '{"Create"}'  "$FULL" TRUE FALSE "Run 8: REQ-203's scheduler create split; heartbeats not compared; every other check; $RH" $RBASEH Prop_RestoreOnlyDeclared Prop_CodeJobLeavesOnlyUndeclared
race Recurring_Race_OrphDecl.cfg   ORPH2 '{"Orphan"}'  "$FULL" TRUE FALSE "Run-7 F-2: the sweep lands after a node that declares the job started; $AC" Prop_CodeJobLeavesOnlyUndeclared
race Recurring_Race_RestoreDecl.cfg ORPH2 '{"Restore"}' "$FULL" TRUE FALSE "Run-7 F-2: a restore lands after its node stopped; $AC" Prop_RestoreOnlyDeclared
race Recurring_Race_ReapplyDecl.cfg ORPH2 '{"Reapply"}' "$FULL" TRUE FALSE "Run-7 F-2: REQ-241 lands after its node stopped; $AC" Prop_StaleOnlyWhenNodeStops
race Recurring_Race_CreateDecl.cfg ORPH2 '{"Create"}'  "$FULL" TRUE FALSE "Run 8: REQ-203's scheduler create lands after the declaring node stopped (same kind of transient); expected VIOLATED; run with --stop-at-first." Prop_CodeJobCreatedOnlyDeclared
race Recurring_Race_Live.cfg       LIVE  '{"Pause", "Resume", "Update", "Remove"}' "$FULL" TRUE FALSE "Run 8: a writer that loses its CAS eventually acts or finds nothing to do (weak fairness of the writer only); $RH" TypeInvR Liv_WriterSettles
race Recurring_Race_LiveStarve.cfg LIVE  '{"Pause"}' "$FULL" TRUE FALSE "Run 8: ... without the escape clause; $V" Liv_WriterSettlesAlways
race Recurring_Race_LiveOrph.cfg   LIVE2 '{"Orphan", "Restore", "Reapply", "Create"}' "$FULL" TRUE FALSE "Run 8: the same for the scheduler's writes, two nodes; $RH" TypeInvR Liv_WriterSettles
RSPEC=SpecRCF
race Recurring_Race_LiveConv.cfg   LIVE3 '{"Orphan", "Restore", "Reapply", "Create"}' "$FULL" TRUE FALSE "Run 8 finding option 1 (REQ-206 fair): the accepted transients heal, the stored definition converges; $H" TypeInvR Liv_DeclaredConverges
RSPEC=SpecRC
race Recurring_Race_LiveConvDel.cfg LIVE3D '{"Orphan", "Restore", "Reapply", "Create"}' "$FULL" TRUE FALSE "Run 8: orphanPolicy Delete only, fairness as written: a sweep that deletes a declared job is healed by REQ-203; $H" TypeInvR Liv_DeclaredConverges
race Recurring_Race_LiveConvW.cfg  LIVE3 '{"Orphan", "Restore", "Reapply", "Create"}' "$FULL" TRUE FALSE "Run 8: the same with fairness as written (REQ-206 not fair); $V" TypeInvR Liv_DeclaredConverges
# Counterfactuals: one per part of INV-212, each expected to fail.
race Recurring_Race_CF_Pause.cfg         MAIN  '{"Pause"}'   "$NONE" FALSE FALSE "Run-6 F-1 trace: the pause write unconditional, decided at the read; $CF" Prop_RecordOnlyUnhandledInstants
race Recurring_Race_CF_PauseAtRead.cfg   MAIN  '{"Pause"}'   "$FULL" FALSE FALSE "Compare-and-set, but missed instants judged at the read (drops 'by the database clock at that write'); $CF" Prop_LeaveRecordsMissed
race Recurring_Race_CF_TriggerNra.cfg    MAIN  '{"Trigger"}' "$NOST"  TRUE FALSE "Trigger CAS without the state (REQ-216 before run 7): the reverse order of run-6 F-1; $CF" Prop_NoScheduledOccurrenceWhilePaused
race Recurring_Race_CF_TriggerSt.cfg     MAIN  '{"Trigger"}' "$NONRA" FALSE FALSE "Trigger CAS without nextRunAt: two nodes trigger one instant; $CF" Prop_OneOccurrencePerInstant
race Recurring_Race_CF_TriggerMaint.cfg  MAIN  '{"Trigger"}' "$NOMAINT" TRUE FALSE "Trigger CAS without maintenance (run-7 wording, run-7 F-1 trace); $CF" Prop_NoTriggerWriteInMaintenance
race Recurring_Race_CF_Update.cfg        MAIN  '{"Update"}'  "$NONE" FALSE FALSE "Schedule change unconditional: a pause in between, and the instant the pause recorded is recorded again; $CF" Prop_MissRecordOnlyByMove
race Recurring_Race_CF_Remove.cfg        MAIN  '{"Remove"}'  "$NONE" FALSE FALSE "Removal unconditional: a trigger in between, and the removal records the instant it ran; $CF" Prop_RecordOnlyUnhandledInstants
race Recurring_Race_CF_RemoveRestore.cfg ORPH2 '{"Remove"}'  "$NONE" FALSE FALSE "Removal unconditional: removal of an orphan that was restored in between (INV-206); $CF" Prop_CodeJobLeavesOnlyUndeclared
race Recurring_Race_CF_OrphanNra.cfg     ORPH2 '{"Orphan"}'  "$NOST" TRUE FALSE "Orphan sweep CAS without the state: a pause in between, and the orphaning records the wrong earlier state; $CF" Prop_OrphanRecordsCurrentState
race Recurring_Race_CF_PauseNra.cfg      ORPH2 '{"Pause"}'   "$NOST" TRUE FALSE "Pause CAS without the state: an orphaning in between, and the pause takes the job out of Orphaned; $CF" Prop_LeaveOrphanedOnlyToStateBefore
race Recurring_Race_CF_ResumeNra.cfg     ORPH2 '{"Resume"}'  "$NOST" TRUE FALSE "Resume CAS without the state: an orphaning in between, and the resume makes an orphaned job active; $CF" Prop_LeaveOrphanedOnlyToStateBefore
race Recurring_Race_CF_Restore.cfg       ORPH2 '{"Restore"}' "$NONE" FALSE FALSE "Restore unconditional; $CF" Prop_LeaveOrphanedOnlyToStateBefore
race Recurring_Race_CF_Reapply.cfg       ORPH2 '{"Reapply"}' "$NONE" FALSE FALSE "REQ-241 write unconditional: a pause in between, and the instant the pause recorded is recorded again; $CF" Prop_MissRecordOnlyByMove
race Recurring_Race_CF_DefReapply.cfg    DEFR  '{"Reapply"}' "$NODEF" TRUE TRUE "Run-7 F-3 trace: REQ-241 that read an unchanged schedule lands after an operator's schedule edit (CAS without the definition); $CF" Inv_NextRunAtFromStoredSchedule
race Recurring_Race_CF_DefUpdate.cfg     MAIN  '{"Update"}'  "$NODEF" TRUE TRUE "Run-7 F-3, reverse: an edit that changes no schedule lands after another edit changed it (CAS without the definition); $CF" Inv_NextRunAtFromStoredSchedule
# Run 4: the 3-slot Queue cfgs check nothing about REQ-242, so they use VIEW ViewNoRec (A-22) to stay at run-3 size.
for f in Recurring_OverlapQueue.cfg Recurring_OverlapQueue2.cfg Recurring_F_WaitingRace.cfg Recurring_F_RerouteQueue.cfg Recurring_P_QueueTwoWaiters.cfg; do
  printf 'VIEW ViewNoRec
' >> $f
done
