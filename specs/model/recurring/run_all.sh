#!/bin/sh
# Reruns every check of the Recurring model, one cfg per TLC run, the way recurring.findings.md was produced.
# Run from specs/model/recurring:   sh run_all.sh [cfg-suffix ...]   (no argument = all)
# Every run uses --stop-at-first: TLC 2.19 throws an internal exception under -continue and stops early.
# run_tlc.py's --timeout does not stop TLC on Windows, so each run is also wrapped in `timeout`, and a TLC left
# running after that is killed. The largest cfgs need 2-4 minutes; the per-run limit is TLC_TIMEOUT, 400 s by default.
# Race_* and RSCN* cfgs use RecurringRace.tla (run 7, INV-212); the rest use Recurring.tla.
R=${RUN_TLC:-$HOME/.claude-personal/skills/refiner-model/scripts/run_tlc.py}
T=${TLC_TIMEOUT:-400}
ALL="Defs Main MainR Misfire OverlapAll OverlapQueue OverlapQueue2 F_WaitingRace F_RerouteOverlap F_RerouteQueue F_RunningHandlers
     P_QueueTwoWaiters P_StaleDefinition P_StaleDefinition2 P_RuntimeTakenOver P_UnroutableBlocks P_Req225Unroutable P_TriggerNowSuperseded
     P_OneUnroutable F_OverdueRecorded P_CatchUpSkipped F_OverduePaused F_OverdueOrphaned F_PassedInstant P_RecordedWaiterSkipped
     Liv_Settles Liv_Settles3
     SCN201 SCN203 SCN204 SCN206 SCN209 SCN209b SCN210 SCN211 SCN213 SCN215
     Race_Pause Race_Resume Race_Sched Race_Remove Race_TriggerOpt Race_MainMaint
     Race_OPause Race_OResume Race_ORemove Race_OrphanOpt Race_RestoreOpt Race_ReapplyOpt Race_OrphDecl Race_RestoreDecl Race_ReapplyDecl
     Race_Live Race_LiveOrph Race_LiveStarve
     Race_CF_Pause Race_CF_PauseAtRead Race_CF_TriggerNra Race_CF_TriggerSt Race_CF_Sched Race_CF_Remove Race_CF_RemoveRestore
     Race_CF_OrphanNra Race_CF_PauseNra Race_CF_ResumeNra Race_CF_Restore Race_CF_Reapply
     RSCN216 RSCN216a RSCN216u RSCN217 RSCN217n RSCN217a"
for c in ${*:-$ALL}; do
  cfg=Recurring_$c.cfg; [ "$c" = Main ] && cfg=Recurring.cfg
  mod=Recurring.tla; case $c in Race_*|RSCN*) mod=RecurringRace.tla ;; esac
  case $c in SCN*|Race_*|RSCN*) extra=--no-deadlock ;; *) extra= ;; esac
  rm -f "run_$c.json" "run_$c.md"
  timeout $((T + 15)) python "$R" "$mod" --config "$cfg" --stop-at-first --workers ${TLC_WORKERS:-4} --timeout $T $extra --out "run_$c.json" --md "run_$c.md" > /dev/null
  command -v powershell > /dev/null && powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"name='java.exe'\" | Where-Object { \$_.CommandLine -like '*-config $cfg *' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" 2> /dev/null
  if [ -f "run_$c.md" ]; then
    printf '%-24s %s | %s | exceptions: %s\n' "$c" "$(head -1 "run_$c.md" | sed 's/.*: \*\*//; s/\*\*//')" \
      "$(grep -m1 '^States:' "run_$c.md")" "$(grep -c -i 'unexpected exception' "run_$c.md")"
  else
    printf '%-24s TIMEOUT after %s s\n' "$c" $((T + 15))
  fi
done
