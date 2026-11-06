#!/bin/sh
# Reproduces every TLC run for the jobs module, one property set per cfg, stopping at the first violation
# (TLC's -continue mode crashes on large trace sets). Usage: sh run_all.sh   (from specs/model/jobs)
# Each run is wrapped in `timeout 170` because run_tlc.py's own --timeout does not stop TLC on Windows;
# if a run is cut off, kill the java process whose command line names the cfg before rerunning.
R="python $HOME/.claude-personal/skills/refiner-model/scripts/run_tlc.py"
run() { m=$1; c=$2; shift 2; rm -f run_$c.json run_$c.md
        timeout 170 $R $m.tla --config $c.cfg --workers 2 --stop-at-first --timeout 160 "$@" --out run_$c.json --md run_$c.md >/dev/null 2>&1
        python -c "import json;d=json.load(open('run_$c.json'));print('$c',d['status'],d['property'],d['stats'].get('distinctStates'),d['stats'].get('seconds'),'stutter',d.get('stutter'),'back',d.get('backToState'),[e for e in d['errors'] if 'xception' in e][:1])" 2>/dev/null || echo "$c NO RESULT (timeout or crash)"; }
# Jobs.tla: holds runs, same-event checks, probes, former INV-106 reading, liveness
for c in Jobs Jobs_Holds Jobs_HoldsQ Jobs_CHK Jobs_CHK2 Jobs_CHK3 Jobs_CHK4 Jobs_INV106; do run Jobs $c; done
run Jobs Jobs_LIV101
for c in Jobs_GAP1 Jobs_GAP2 Jobs_GAP5 Jobs_SCN100 Jobs_SCN101 Jobs_SCN102 Jobs_SCN111 Jobs_SCN112 Jobs_SCN115 Jobs_SCN120 Jobs_SCN122; do run Jobs $c --no-deadlock; done
for c in Jobs_Unique Jobs_Unique_U1 Jobs_Unique_U2 Jobs_Unique_U3 Jobs_Unique_U4 Jobs_Unique_U5 Jobs_Unique_SCN105; do run Jobs_Unique $c --no-deadlock; done
for c in Jobs_Throttle Jobs_Throttle_Holds Jobs_Throttle_HoldsK Jobs_Throttle_T0 Jobs_Throttle_T2 Jobs_Throttle_T3 Jobs_Throttle_L0 Jobs_Throttle_L1 Jobs_Throttle_L2 Jobs_Throttle_L3; do run Jobs_Throttle $c; done
for c in Jobs_Flow_Holds Jobs_Flow_HoldsC Jobs_Flow_HoldsU Jobs_Flow_F1 Jobs_Flow_F2 Jobs_Flow_F3 Jobs_Flow_F4 Jobs_Flow_GAP3 Jobs_Flow_GAP3b Jobs_Flow_GAP4 Jobs_Flow_GAP5 Jobs_Flow_GAP6 Jobs_Flow_SCN108 Jobs_Flow_SCN114 Jobs_Flow_SCN118 Jobs_Flow_SCN119 Jobs_Flow_SCN121; do run Jobs_Flow $c --no-deadlock; done
rm -rf states
