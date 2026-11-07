#!/bin/sh
# Reruns every check of the Recurring model, one cfg per TLC run, the way recurring.findings.md was produced.
# Run from specs/model/recurring:   sh run_all.sh [cfg-suffix ...]   (no argument = all)
# Every run uses --stop-at-first: TLC 2.19 throws an internal exception under -continue and stops early.
# run_tlc.py's --timeout does not stop TLC on Windows, so each run is also wrapped in `timeout`. The 3-slot
# Queue cfgs (7M+ distinct states) need 2-4 minutes, so the per-run limit is TLC_TIMEOUT, 300 s by default.
R=${RUN_TLC:-$HOME/.claude-personal/skills/refiner-model/scripts/run_tlc.py}
T=${TLC_TIMEOUT:-300}
ALL="Defs Main MainR Misfire OverlapAll OverlapQueue OverlapQueue2 F_WaitingRace F_RerouteOverlap F_RerouteQueue F_RunningHandlers
     P_QueueTwoWaiters P_StaleDefinition P_StaleDefinition2 P_RuntimeTakenOver P_UnroutableBlocks P_Req225Unroutable P_TriggerNowSuperseded
     P_OneUnroutable P_OverdueDropped P_CatchUpSkipped
     Liv_Settles Liv_Settles3
     SCN201 SCN203 SCN204 SCN206 SCN209 SCN209b SCN210 SCN211 SCN213 SCN215"
for c in ${*:-$ALL}; do
  cfg=Recurring_$c.cfg; [ "$c" = Main ] && cfg=Recurring.cfg
  case $c in SCN*) extra=--no-deadlock ;; *) extra= ;; esac
  timeout $((T + 10)) python "$R" Recurring.tla --config "$cfg" --stop-at-first --workers 4 --timeout $T $extra --out "run_$c.json" --md "run_$c.md" > /dev/null
  printf '%-20s %s | %s | exceptions: %s\n' "$c" "$(head -1 "run_$c.md" | sed 's/.*: \*\*//; s/\*\*//')" \
    "$(grep -m1 '^States:' "run_$c.md")" "$(grep -c -i 'unexpected exception' "run_$c.md")"
done
