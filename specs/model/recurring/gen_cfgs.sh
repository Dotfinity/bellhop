#!/bin/sh
# Regenerates the non-scenario cfgs of the Recurring model. Run from specs/model/recurring.
# Constant sets: MAIN (1 job, triggering/misfire/maintenance), DEFS (2 jobs, reconciliation),
# QUEUE1/QUEUE2 (Queue policy, 3 slots), ALL (all overlap policies, 2 slots), PROBE (3 releases).
# The last value is RerouteOn: jobs REQ-125 (Unroutable -> Enqueued) is explored only in ALLR and MAINR,
# so that the run-1 overlap fixes and the run-2 Unroutable finding are checked separately. The value after
# it, FixCancelUnroutable, switches on the CANDIDATE FIX for run-2 F-1 (only ALLRF); it is not a requirement.
consts() {
  case $1 in
    MAIN)   set -- "{j1}" "{o1, o2}" "{a}" '{"v1"}' "{j1}" "{}" "{}" "{}" 1 '{"Skip", "Queue"}' '{"RunOnce", "Skip"}' '{"Orphan"}' FALSE FALSE ;;
    DEFS)   set -- "{j1, j2}" "{}" "{a, b}" '{"v1", "v2"}' "{j1, j2}" "{j1}" "{}" "{j1}" 1 '{"Skip"}' '{"RunOnce"}' '{"Orphan", "Delete"}' FALSE FALSE ;;
    QUEUE1) set -- "{j1}" "{o1, o2, o3}" "{a}" '{"v1"}' "{}" "{}" "{}" "{}" 1 '{"Queue"}' '{"RunOnce"}' '{"Orphan"}' FALSE FALSE ;;
    QUEUE2) set -- "{j1}" "{o1, o2, o3}" "{a}" '{"v1"}' "{}" "{}" "{}" "{}" 2 '{"Queue"}' '{"RunOnce"}' '{"Orphan"}' FALSE FALSE ;;
    MAINR)  set -- "{j1}" "{o1, o2}" "{a}" '{"v1"}' "{j1}" "{}" "{}" "{}" 1 '{"Skip", "Queue"}' '{"RunOnce", "Skip"}' '{"Orphan"}' TRUE FALSE ;;
    ALL)    set -- "{j1}" "{o1, o2}" "{a}" '{"v1"}' "{j1}" "{}" "{}" "{}" 1 '{"Skip", "Queue", "Allow", "CancelPrevious"}' '{"RunOnce"}' '{"Orphan"}' FALSE FALSE ;;
    ALLR)   set -- "{j1}" "{o1, o2}" "{a}" '{"v1"}' "{j1}" "{}" "{}" "{}" 1 '{"Skip", "Queue", "Allow", "CancelPrevious"}' '{"RunOnce"}' '{"Orphan"}' TRUE FALSE ;;
    ALLRF)  set -- "{j1}" "{o1, o2}" "{a}" '{"v1"}' "{j1}" "{}" "{}" "{}" 1 '{"Skip", "Queue", "Allow", "CancelPrevious"}' '{"RunOnce"}' '{"Orphan"}' TRUE TRUE ;;
    PROBE2) set -- "{j1}" "{o1}" "{a, b}" '{"v1", "v2"}' "{j1}" "{j1}" "{}" "{}" 1 '{"Skip"}' '{"RunOnce"}' '{"Orphan"}' FALSE FALSE ;;
    PROBE)  set -- "{j1}" "{o1}" "{a}" '{"v1", "v2", "v3"}' "{j1}" "{j1}" "{}" "{}" 1 '{"Skip"}' '{"RunOnce"}' '{"Orphan"}' FALSE FALSE ;;
  esac
  printf 'CONSTANTS\n  Names = %s\n  OccIds = %s\n  Nodes = %s\n  Releases = %s\n  DeclV1 = %s\n  DeclV2 = %s\n  DeclV3 = %s\n  Override = %s\n  MaxQueued = %s\n  OverlapPolicies = %s\n  MisfirePolicies = %s\n  OrphanPolicies = %s\n  RerouteOn = %s\n  FixCancelUnroutable = %s\n  NULL = NULL\n' "$@"
}
# cfg <file> <constant set> <comment> <checks...>   (Prop_* go under PROPERTIES)
cfg() {
  f=$1; c=$2; h=$3; shift 3
  { printf '%s %s\nSPECIFICATION Spec\n' '\*' "$h"; consts $c; printf 'INVARIANTS\n'
    for i in "$@"; do case $i in Prop_*) ;; *) printf '  %s\n' $i ;; esac; done
    for i in "$@"; do case $i in Prop_*) printf 'PROPERTIES\n  %s\n' $i ;; esac; done; } > $f
}
H='expected to hold; run with --stop-at-first (TLC 2.19 -continue can crash).'
V='expected VIOLATED; run with --stop-at-first, the trace is the example.'
P='Probe (modeling aid, not a requirement):'
R='regression check for a run-1 finding; expected to hold.'
MAINCHK="TypeInv Inv_NoScheduleWhilePaused Inv_NoScheduleInMaintenance Inv_MaxQueued Scn_SecondCasImpossible Prop_NoScheduledAdvanceInMaintenance Prop_PauseOrphanRemoveSkipsWaiting Prop_SkipOnlyWhenInTheWay"
cfg Recurring.cfg               MAIN   "Main run: triggering, misfire, maintenance, overlap with 2 slots; $H" $MAINCHK Inv_NoOverlapProcessing
cfg Recurring_MainR.cfg         MAINR  "Main run with jobs REQ-125 explored, every check except INV-204 (see F_RerouteOverlap); $H" $MAINCHK
cfg Recurring_Defs.cfg          DEFS   "Definitions and reconciliation, no occurrence slots; $H" TypeInv Scn_CodeJobNotEditable Scn_CodeJobNotRemovable Scn_NoOrphanWhileDeclared Scn_StoredNameCannotBeAdded Scn_RuntimeNameBlocksStart Prop_PauseOrphanRemoveSkipsWaiting
cfg Recurring_OverlapQueue.cfg  QUEUE1 "Overlap Queue(1), 3 slots; $H" TypeInv Inv_MaxQueued Prop_PauseOrphanRemoveSkipsWaiting Prop_SkipOnlyWhenInTheWay
cfg Recurring_OverlapQueue2.cfg QUEUE2 "Overlap Queue(2), 3 slots; $H" TypeInv Inv_MaxQueued Prop_SkipOnlyWhenInTheWay
cfg Recurring_OverlapAll.cfg    ALL    "Overlap, all four policies, 2 slots; $H" TypeInv Inv_MaxQueued Inv_NoOverlapProcessing Prop_SkipOnlyWhenInTheWay
cfg Recurring_F_RunningHandlers.cfg MAIN   "REQ-238 (info, run-1 F-3): an abandoned or lease-lost handler still runs beside the next job; $V" Inv_NoOverlapRunning
cfg Recurring_F_WaitingRace.cfg     QUEUE1 "Run-1 F-1, INV-204 Queue(1) race; $R" Inv_NoOverlapProcessing
cfg Recurring_F_RerouteOverlap.cfg  ALLR   "INV-204 with jobs REQ-125 explored (REQ-239 counts Unroutable as finished); $V" Inv_NoOverlapProcessing
cfg Recurring_P_QueueTwoWaiters.cfg QUEUE2 "Run-1 F-2: $P Queue(2) newer waiting occurrence beside an older unfinished one; $R" Probe_NewerWaiterStartsBesideOlder Inv_NoOverlapProcessing
cfg Recurring_P_StaleDefinition.cfg PROBE  "Run-1 F-5: $P restored orphan keeps a stale definition; $R" Probe_StaleDefinitionAfterRestore
cfg Recurring_P_RuntimeTakenOver.cfg PROBE "Run-1 F-6: $P runtime job rewritten by code; $R" Probe_RuntimeJobTakenOverByCode
cfg Recurring_P_UnroutableBlocks.cfg ALL   "Run-1 F-7: an unroutable job never blocks the next occurrence; $R" Prop_SkipOnlyWhenInTheWay
cfg Recurring_F_RerouteOverlapFix.cfg ALLRF "Candidate fix for run-2 F-1 (cancel earlier Unroutable jobs when an occurrence starts): INV-204 with jobs REQ-125; $H" Inv_NoOverlapProcessing Prop_SkipOnlyWhenInTheWay
cfg Recurring_P_StaleDefinition2.cfg PROBE2 "Run-2: $P two nodes on releases v1/v2 (rolling deploy): stored code definition stale for every running node; $V" Probe_StaleDefinitionAfterRestore
