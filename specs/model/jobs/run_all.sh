#!/bin/sh
# Reproduces every TLC run for the jobs module, one property set per cfg, stopping at the first violation
# (TLC's -continue mode crashes on large trace sets). Usage: sh run_all.sh   (from specs/model/jobs)
# TLC_WORKERS (default 4) and TLC_TIMEOUT (default 170 s) override the defaults, e.g. when other models run.
# Each run is wrapped in `timeout 170` because run_tlc.py's own --timeout does not stop TLC on Windows;
# if a run is cut off, kill the java process whose command line names the cfg before rerunning.
R="python $HOME/.claude-personal/skills/refiner-model/scripts/run_tlc.py"
run() { m=$1; c=$2; shift 2; rm -f run_$c.json run_$c.md
        timeout ${TLC_TIMEOUT:-170} $R $m.tla --config $c.cfg --workers ${TLC_WORKERS:-4} --stop-at-first --timeout $(( ${TLC_TIMEOUT:-170} - 10 )) "$@" --out run_$c.json --md run_$c.md >/dev/null 2>&1
        python -c "import json;d=json.load(open('run_$c.json'));print('$c',d['status'],d['property'],d['stats'].get('distinctStates'),d['stats'].get('seconds'),'stutter',d.get('stutter'),'back',d.get('backToState'),[e for e in d['errors'] if 'xception' in e][:1])" 2>/dev/null || echo "$c NO RESULT (timeout or crash)"; }
# Jobs.tla: holds runs, same-event checks, probes, former INV-106 reading, liveness
# Jobs.cfg (all at once) and Jobs_LIV101.cfg exceed 170 s since run 3; their checks run split below.
for c in Jobs_Holds Jobs_HoldsQ Jobs_CHK Jobs_CHK2 Jobs_CHK3 Jobs_CHK4 Jobs_CHK5 Jobs_CHK6 Jobs_INV106; do run Jobs $c; done
for c in Jobs_LIV101a Jobs_LIV101b Jobs_LIV29; do run Jobs $c; done
# Jobs_GAP6 (run 3 F-2) holds by construction since run 4 and its two-slot space exceeds 170 s.
for c in Jobs_GAP1 Jobs_GAP2 Jobs_GAP5 Jobs_GAP7 Jobs_GAP8 Jobs_P2 Jobs_P3 Jobs_P4 Jobs_P5 Jobs_SCN100 Jobs_SCN101 Jobs_SCN102 Jobs_SCN111 Jobs_SCN112 Jobs_SCN115 Jobs_SCN120 Jobs_SCN122 Jobs_SCN124 Jobs_SCN124s Jobs_SCN125; do run Jobs $c --no-deadlock; done
# Run 8: probes over the unchanged Jobs.tla for a cancellation requested after the node's check (REQ-190 and
# hosting REQ-29 notes). Reach8_ action properties are expected violated (TLC reports them as errors); Chk8_Exits holds.
for c in Jobs_AfterChk_O Jobs_AfterChk_R Jobs_AfterChk_EC Jobs_AfterChk_ED Jobs_AfterChk_X Jobs_AfterChk_X1; do run Jobs_AfterChk $c --no-deadlock; done
for c in Jobs_AfterChk_T Jobs_AfterChk_ST; do run Jobs_AfterChkG $c --no-deadlock; done   # Spec8: history variable g8
# Run 9: which lease-expiry rule decides a post-check cancellation (REQ-190's lease branch, not REQ-132), and whether
# lease expiry can decide it before the stop. Both Reach9_ properties are expected violated.
for c in Jobs_AfterChk9_LA Jobs_AfterChk9_LB; do run Jobs_AfterChk9 $c --no-deadlock; done
for c in Jobs_Unique Jobs_Unique_U1 Jobs_Unique_U2 Jobs_Unique_U3 Jobs_Unique_U4 Jobs_Unique_U5 Jobs_Unique_SCN105; do run Jobs_Unique $c --no-deadlock; done
for c in Jobs_Throttle Jobs_Throttle_Holds Jobs_Throttle_HoldsK Jobs_Throttle_T0 Jobs_Throttle_T2 Jobs_Throttle_T3 Jobs_Throttle_L0 Jobs_Throttle_L1 Jobs_Throttle_L2 Jobs_Throttle_L3; do run Jobs_Throttle $c; done
for c in Jobs_Flow_Holds Jobs_Flow_HoldsC Jobs_Flow_HoldsU Jobs_Flow_F1 Jobs_Flow_F2 Jobs_Flow_F3 Jobs_Flow_F4 Jobs_Flow_GAP3 Jobs_Flow_GAP3b Jobs_Flow_GAP4 Jobs_Flow_GAP5 Jobs_Flow_GAP6 Jobs_Flow_F5 Jobs_Flow_P1 Jobs_Flow_P1b Jobs_Flow_SCN108 Jobs_Flow_SCN114 Jobs_Flow_SCN118 Jobs_Flow_SCN119 Jobs_Flow_SCN121; do run Jobs_Flow $c --no-deadlock; done
rm -rf states
