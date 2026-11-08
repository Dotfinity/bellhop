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
    QUEUE1R) set -- "{j1}" "{o1, o2, o3}" "{a}" '{"v1"}' "{}" "{}" "{}" "{}" 1 '{"Queue"}' '{"RunOnce"}' '{"Orphan"}' TRUE ;;
    ALLOW3) set -- "{j1}" "{o1, o2, o3}" "{a}" '{"v1"}' "{j1}" "{}" "{}" "{}" 1 '{"Allow", "CancelPrevious"}' '{"RunOnce"}' '{"Orphan"}' FALSE ;;
    MISALL) set -- "{j1}" "{o1, o2}" "{a}" '{"v1"}' "{j1}" "{}" "{}" "{}" 1 '{"Skip", "Queue"}' '{"RunOnce", "Skip", "RunAll"}' '{"Orphan"}' FALSE ;;
    SETTLE3) set -- "{j1}" "{o1}" "{a, b}" '{"v1", "v2", "v3"}' "{j1}" "{j1}" "{j1}" "{j1}" 1 '{"Skip"}' '{"RunOnce"}' '{"Orphan"}' FALSE ;;
  esac
  printf 'CONSTANTS\n  Names = %s\n  OccIds = %s\n  Nodes = %s\n  Releases = %s\n  DeclV1 = %s\n  DeclV2 = %s\n  DeclV3 = %s\n  Override = %s\n  MaxQueued = %s\n  OverlapPolicies = %s\n  MisfirePolicies = %s\n  OrphanPolicies = %s\n  RerouteOn = %s\n  NULL = NULL\n' "$@"
}
# cfg <file> <constant set> <comment> <checks...>   (Prop_*, Liv_* and ProbeAct_* go under PROPERTIES)
cfg() {
  f=$1; c=$2; h=$3; shift 3
  { printf '%s %s\nSPECIFICATION Spec\n' '\*' "$h"; consts $c; printf 'INVARIANTS\n'
    for i in "$@"; do case $i in Prop_*|Liv_*|ProbeAct_*) ;; *) printf '  %s\n' $i ;; esac; done
    for i in "$@"; do case $i in Prop_*|Liv_*|ProbeAct_*) printf 'PROPERTIES\n  %s\n' $i ;; esac; done; } > $f
}
H='expected to hold; run with --stop-at-first (TLC 2.19 -continue can crash).'
V='expected VIOLATED; run with --stop-at-first, the trace is the example.'
P='Probe (modeling aid, not a requirement):'
R='regression check for a run-1 finding; expected to hold.'
R2='regression check for a run-2 finding; expected to hold.'
R4='regression check for a run-4 finding; expected to hold.'
REC="Prop_MissRecordOnlyByMove Prop_MissedMoveRecordsOnce Prop_RecordSaysOutcome"
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
cfg Recurring_P_OverduePaused.cfg   MAIN   "Run 5: $P instants missed while active leave with no REQ-242 record when the job is paused; $V" ProbeAct_OverduePausedRecorded
cfg Recurring_P_OverdueOrphaned.cfg PROBE  "Run 5: $P ... or orphaned / deleted by the orphan sweep; $V" ProbeAct_OverdueOrphanedRecorded
cfg Recurring_P_PassedInstantDropped.cfg MAIN "Run 5 (A-25): $P a schedule change drops a passed, not-yet-triggered instant with no occurrence and no record; $V" ProbeAct_PassedInstantRunsOrIsRecorded
cfg Recurring_P_RecordedWaiterSkipped.cfg MAIN "Run 5: $P a REQ-242 record that says the catch-up occurrence is waiting, then REQ-237 skips it; $V" ProbeAct_RecordedWaiterNeverSkipped
# Run 4: the 3-slot Queue cfgs check nothing about REQ-242, so they use VIEW ViewNoRec (A-22) to stay at run-3 size.
for f in Recurring_OverlapQueue.cfg Recurring_OverlapQueue2.cfg Recurring_F_WaitingRace.cfg Recurring_F_RerouteQueue.cfg Recurring_P_QueueTwoWaiters.cfg; do
  printf 'VIEW ViewNoRec
' >> $f
done
