#!/bin/sh
# Reruns every dashboard check the way dashboard.findings.md reports it. Run from specs/model/dashboard.
# Each invariant runs alone with --stop-at-first: TLC 2.19 crashes under -continue once it rebuilds many
# traces. `timeout 170` is needed because run_tlc.py's own --timeout does not stop TLC on Windows.
# Results go to runs/<name>.json and .md (gitignored); the generated one-check cfgs are removed afterwards.
RUN="python ${RUN_TLC:-$HOME/.claude-personal/skills/refiner-model/scripts/run_tlc.py}"
mkdir -p runs

run() {  # run <name> [extra run_tlc args]: runs/<name>.cfg, then removes it
  name=$1; shift
  timeout 170 $RUN Dashboard.tla --config "runs/$name.cfg" --stop-at-first --workers 2 \
    --out "runs/$name.json" --md "runs/$name.md" "$@" > /dev/null
  rm -f "runs/$name.cfg"
  printf '%-58s %s\n' "$name" "$(head -1 "runs/$name.md" | sed 's/.*\*\*\(.*\)\*\*.*/\1/')"
}

one() {  # one <cfg> <invariant> [extra run_tlc args]
  cfg=$1; inv=$2; shift 2
  name="$(basename "$cfg" .cfg)__$inv"
  sed '/^INVARIANTS/,$d' "$cfg" > "runs/$name.cfg"
  printf 'INVARIANTS\n  %s\n' "$inv" >> "runs/$name.cfg"
  run "$name" "$@"
}

prop() {  # prop <cfg> <property> [extra run_tlc args]: the (action) property alone, with TypeInv
  cfg=$1; p=$2; shift 2
  name="$(basename "$cfg" .cfg)__$p"
  sed '/^INVARIANTS/,$d' "$cfg" > "runs/$name.cfg"
  printf 'INVARIANTS\n  TypeInv\nPROPERTIES\n  %s\n' "$p" >> "runs/$name.cfg"
  run "$name" "$@"
}

invs()  { sed -n '/^INVARIANTS/,$p' "$1" | sed '/^PROPERTIES/,$d' | tail -n +2 | tr -d ' '; }
props() { sed -n '/^PROPERTIES/,$p' "$1" | tail -n +2 | tr -d ' '; }

for inv in $(invs Dashboard.cfg); do one Dashboard.cfg "$inv"; done
one Dashboard_Banner.cfg TypeInv
for inv in $(invs Dashboard_Rollup.cfg); do one Dashboard_Rollup.cfg "$inv" --no-deadlock; done
for p in $(props Dashboard_Rollup.cfg); do prop Dashboard_Rollup.cfg "$p" --no-deadlock; done
for c in Dashboard_SCN*.cfg; do one "$c" "$(invs "$c")" --no-deadlock; done

grep -l -i "unexpected exception" runs/*.md 2>/dev/null && echo "WARNING: a run above hit a TLC exception; its result is not trustworthy"
exit 0
