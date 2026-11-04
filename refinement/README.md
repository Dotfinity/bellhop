# Refinement of the M1 requirements

This folder holds the M1 requirements restated from the stories, every question and finding about them, and the models that check every possible order of events against them. It was produced with the `refine-requirements` skill, and its layout is that skill's.

## Layout

| Path | What it is |
|---|---|
| `requirements.md` | Features F1 to F7 and requirements REQ-001 to REQ-045, each with its source, current text (`Now:`), history and the outcome of each iteration's check |
| `decisions.md` | Decisions D-1 to D-22: every question and finding, in every status |
| `iterations/<n>/inputs.md` | The requirement text and answers that iteration read |
| `iterations/<n>/models/` | One TLA+ module per feature (`F<n>_<Name>.tla`), its configuration (`.cfg`), its rules in plain words (`.rules.md`), the outcome (`.check.json`) and a trace per broken rule (`.trace-<Rule>.txt`) |
| `iterations/<n>/models/attempts/` | Earlier versions, and mutants: a model with one fix taken out, to show that the fix is what makes its rule hold |
| `iterations/<n>/results.md` | What changed since the previous iteration, written for the requirements' owner |

Each iteration keeps a full copy of the models, so an iteration's outcome can always be reproduced from its own folder. The current iteration is **4**. Its F4 model is new; the other five are carried over unchanged from iteration 3.

## Re-running a check

You need Java 11 or later and `tla2tools.jar` from [TLA+ release v1.7.4](https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar) (it reports itself as TLC 2.19; SHA-256 `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`). From the iteration's `models` folder:

```sh
java -XX:+UseParallelGC -cp /path/to/tla2tools.jar tlc2.TLC \
  -workers auto -deadlock -config F1_JobLifecycle.cfg F1_JobLifecycle.tla
```

- Run it once per module, F1 to F6. `CommonCheck` only checks that the shared constants are valid.
- `-deadlock` is needed: several models bound their clocks, so a run can legitimately end in a state with no next step.
- TLC stops at the first broken rule. To see every broken rule, take the rules out of the `.cfg` one at a time, or use the skill's `check_module.py`, which does that for you and writes the `.check.json`. One limit: when several rules about steps or about what eventually happens are listed together, the script can't always tell which one broke (`status: unfinished`). Running each such rule alone with the command above settles it.
- Times on a 24-core machine: F3 takes about 20 minutes (5.7 million distinct states), F4 about a minute, the rest a few seconds.

The raw TLC logs (`*.tlc.log`) are not committed (`.gitignore` excludes `*.log`). The `.check.json` files and the traces are the committed record: each rule's outcome, the size of each run, and any step that never happened (`neverFired`), which would mean a rule passed only because something couldn't occur.

## Reading an outcome

In `.check.json`, `status` is `ok` (every rule held), `issues` (a rule broke; see its trace and the decision raised from it), or a problem with the model itself (`spec_bug`, `compile_error`, `too_big`, `unfinished`, `tooling`), which is never a finding about Bellhop. A passed check covers the model with two nodes and a few jobs, against the rules written down. It doesn't prove the code, and it can't find a rule nobody wrote: see each iteration's "What a passed rule means here".
