#!/bin/sh
# Regenerates the non-scenario cfgs of the Recurring model. Run from specs/model/recurring.
# Constant sets: MAIN (1 job, triggering/misfire/maintenance), DEFS (2 jobs, reconciliation),
# QUEUE1/QUEUE2 (Queue policy, 3 slots), ALL (all overlap policies, 2 slots), PROBE (3 releases).
consts() {
  case $1 in
    MAIN)   set -- "{j1}" "{o1, o2}" "{a}" '{"v1"}' "{j1}" "{}" "{}" "{}" 1 '{"Skip", "Queue"}' '{"RunOnce", "Skip"}' '{"default"}' ;;
    DEFS)   set -- "{j1, j2}" "{}" "{a, b}" '{"v1", "v2"}' "{j1, j2}" "{j1}" "{}" "{j1}" 1 '{"Skip"}' '{"RunOnce"}' '{"default", "delete"}' ;;
    QUEUE1) set -- "{j1}" "{o1, o2, o3}" "{a}" '{"v1"}' "{}" "{}" "{}" "{}" 1 '{"Queue"}' '{"RunOnce"}' '{"default"}' ;;
    QUEUE2) set -- "{j1}" "{o1, o2, o3}" "{a}" '{"v1"}' "{}" "{}" "{}" "{}" 2 '{"Queue"}' '{"RunOnce"}' '{"default"}' ;;
    ALL)    set -- "{j1}" "{o1, o2}" "{a}" '{"v1"}' "{j1}" "{}" "{}" "{}" 1 '{"Skip", "Queue", "Allow", "CancelPrevious"}' '{"RunOnce"}' '{"default"}' ;;
    PROBE)  set -- "{j1}" "{o1}" "{a}" '{"v1", "v2", "v3"}' "{j1}" "{j1}" "{}" "{}" 1 '{"Skip"}' '{"RunOnce"}' '{"default"}' ;;
  esac
  printf 'CONSTANTS\n  Names = %s\n  OccIds = %s\n  Nodes = %s\n  Releases = %s\n  DeclV1 = %s\n  DeclV2 = %s\n  DeclV3 = %s\n  Override = %s\n  MaxQueued = %s\n  OverlapPolicies = %s\n  MisfirePolicies = %s\n  OrphanPolicies = %s\n  NULL = NULL\n' "$@"
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
cfg Recurring.cfg               MAIN   "Main run: triggering, misfire, maintenance, overlap with 2 slots; $H" TypeInv Inv_NoScheduleWhilePaused Inv_NoScheduleInMaintenance Inv_NoOverlapProcessing Inv_MaxQueued Scn_SecondCasImpossible
cfg Recurring_Defs.cfg          DEFS   "Definitions and reconciliation, no occurrence slots; $H" TypeInv Scn_CodeJobNotEditable Scn_CodeJobNotRemovable Scn_NoOrphanWhileDeclared
cfg Recurring_OverlapQueue.cfg  QUEUE1 "Overlap Queue(1), 3 slots; $H" TypeInv Inv_MaxQueued
cfg Recurring_OverlapQueue2.cfg QUEUE2 "Overlap Queue(2), 3 slots; $H" TypeInv Inv_MaxQueued
cfg Recurring_OverlapAll.cfg    ALL    "Overlap, all four policies, 2 slots; $H" TypeInv Inv_MaxQueued Inv_NoOverlapProcessing
cfg Recurring_F_Maintenance.cfg     MAIN   "F-4: INV-210 vs REQ-227/REQ-215/REQ-206; $V" Prop_MaintenanceKeepsNextRunAt
cfg Recurring_F_RunningHandlers.cfg MAIN   "F-3: INV-204 counting every running handler; $V" Inv_NoOverlapRunning
cfg Recurring_F_WaitingRace.cfg     QUEUE1 "F-1: INV-204 (status Processing), Queue(1) race; $V" Inv_NoOverlapProcessing
cfg Recurring_P_QueueTwoWaiters.cfg QUEUE2 "F-2: $P Queue(2) lets a newer waiting occurrence start beside an older unfinished one; $V" Probe_NewerWaiterStartsBesideOlder
cfg Recurring_P_StaleDefinition.cfg PROBE  "F-5: $P restored orphan keeps a stale definition; $V" Probe_StaleDefinitionAfterRestore
cfg Recurring_P_RuntimeTakenOver.cfg PROBE "F-6: $P runtime job rewritten by code; $V" Probe_RuntimeJobTakenOverByCode
cfg Recurring_P_UnroutableBlocks.cfg ALL   "F-7: $P unroutable occurrence job blocks the next one; $V" Probe_UnroutableBlocksNext
