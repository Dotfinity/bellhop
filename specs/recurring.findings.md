# Findings: Bellhop recurring jobs

<!-- refiner-findings v1 | module: recurring | specHash: 77018f6c8a5075edb339db2f3441e69eca2ac5114a1f29b88506a909a89ec473 | run: 2026-11-06 (run 3) | previous: specs/model/recurring/previous.findings.md (run 2, specHash bc55236159f4) -->

**Run:** 2026-11-06, run 3 · **Requirements file:** `specs/recurring.json` (specHash `77018f6c8a50`) · **Model:** `specs/model/recurring/Recurring.tla` · **TLC:** 2.19; every check ran alone with `--stop-at-first` and finished with no TLC exception and no timeout (29 cfgs, up to 7,439,116 distinct states, ≤ 231 s each); see [How to reproduce](#how-to-reproduce)
**Result:** 2 findings: 0 contradictions · 1 gap · 0 unprovable · 1 ambiguity · 0 modeling notes. Both run-2 findings are resolved. REQ-241's settling claim is checked as a liveness property and holds.

The model has no clock. Anything that depends on real amounts of time (DST, time zones, validity windows, the 60 s misfire threshold as a number) is outside what it can judge; see *Coverage*.

## Changes since last run
| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | contradiction · INV-204 · REQ-221,REQ-224,REQ-239,jobs.REQ-124,jobs.REQ-125 |
| F-2 | resolved | gap · REQ-204 · REQ-204,REQ-206 |
| F-1 | new | ambiguity · REQ-240 · REQ-225,REQ-239,REQ-240 |
| F-2 | new | gap · REQ-240 · REQ-226,REQ-240 |

2 resolved, 2 new, 0 still open

(Table from `findings_delta.py`.) What changed in the requirements (handoff `specs/model/recurring/handoff.json`, base bb8be99): REQ-240 and REQ-241 are new, SCN-215 is new, and REQ-210 and REQ-236 now say "fail the host's start" instead of "stop the node from starting". The handoff lists no impacted ids. The model change is: REQ-240 replaces the run-2 switch `FixCancelUnroutable` (now gone from the model and every cfg), REQ-241 is a new weakly fair scheduler action `ReapplyCode`, SCN-215 has its own cfg, and REQ-236 keeps its encoding (A-16 already read StartupFailed as "the node does not start"). Because a new action changes every state space, every check was rerun.

How each run-2 finding was re-checked:

| Run-2 finding | Requirement change | Evidence in run 3 |
|---|---|---|
| F-1 Unroutable job comes back beside the next occurrence | REQ-240 cancels an earlier occurrence's Unroutable job in the write that starts a new occurrence | The run-2 trace config `Recurring_F_RerouteOverlap.cfg` (all four overlap policies, jobs REQ-125 on) now **passes** `Inv_NoOverlapProcessing` (INV-204) and `Prop_SkipOnlyWhenInTheWay`: 262,576 distinct states. New `Recurring_F_RerouteQueue.cfg` (Queue(1), 3 slots, jobs REQ-125 on) passes INV-204, REQ-233, REQ-237 and the skip rule over 7,439,116 distinct states. `Recurring_MainR.cfg` now also checks INV-204 with jobs REQ-125 and passes: 194,712 distinct states. SCN-215 is reachable in 2 states with jobs REQ-125 on. |
| F-2 stored definition stale after a rollback | REQ-241 re-applies a running node's code when the stored hash matches none of the running nodes that declare the job | `Liv_DefinitionSettles` (*a stale stored definition eventually matches a running declaring node again*, weak fairness on REQ-241 only) and `Prop_StaleOnlyWhenNodeStops` (*once it matches, only a node stopping makes it stale again*) **pass** with two nodes on v1/v2 (`Recurring_Liv_Settles.cfg`, 14,478 distinct states) and with two nodes on three releases and AllowRuntimeOverride (`Recurring_Liv_Settles3.cfg`, 72,078 distinct states). Together they say the definition settles as soon as the set of running nodes stops changing. The check is not vacuous: in a scratch copy of the model with REQ-241 removed from `Next` and from the fairness condition, `Liv_DefinitionSettles` fails with a lasso (back to state 9) in the same config. The run-2 probe `Probe_StaleDefinitionAfterRestore` is still violated in 5 states (`Recurring_P_StaleDefinition2.cfg`), as expected: REQ-241 closes the window one scheduler step later. |

**Settling: what the model can and cannot say.** It can say that under weak fairness of the scheduler's REQ-241 step, and with nodes publishing their declarations instantly (A-6), the stored definition always comes back to a running release, also after a rollback or a late restart of an old node. It cannot say *how soon*: the scheduler's polling interval and heartbeat expiry are amounts of time. One consequence of REQ-241 that the model shows but that is not a finding: whenever every node of the new release is down at once while old nodes still run (for example the first v2 node restarting early in a deploy), REQ-241 writes the old definition back and REQ-204 writes the new one again when the node returns. That is what REQ-241 says (the stored definition follows the running nodes), and with a changed schedule nextRunAt is recomputed from now twice (REQ-227). REQ-241's note, "there is no back-and-forth during a deploy", holds only while at least one new-release node stays up; consider rewording it when you next edit REQ-241.

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | ambiguity | medium | REQ-240, REQ-225, REQ-239 | REQ-240's sentence covers every start, but its dependsOn and notes cover only Skip and Queue starts; under Allow the two readings differ |
| F-2 | gap | low | REQ-240, REQ-226 | An operator's "trigger now" run (perhaps with an overridden payload) whose job is Unroutable is cancelled as Superseded by the next scheduled occurrence |

---

## F-1 · ambiguity · medium — REQ-240 says "an occurrence starts"; its dependsOn and notes cover only Skip and Queue starts
<!-- finding: ambiguity | REQ-240 | REQ-240,REQ-225,REQ-239 -->

**Requirements involved**
- REQ-240: *When an occurrence of a recurring job starts while an earlier occurrence of the same recurring job has an unroutable job, the system shall cancel that unroutable job with reason Superseded in the same write that starts the new occurrence.* `dependsOn`: REQ-221, REQ-224, REQ-239. Notes: *"The newer occurrence replaces the stale one, which is what Skip and Queue intend."*
- REQ-225: *When an occurrence is created while an earlier occurrence of the same recurring job is waiting or has an unfinished job, if the overlap policy is Allow or CancelPrevious, the system shall enqueue a job for the new occurrence and record it as started, and under CancelPrevious also request cancellation of the earlier occurrence's job.*
- REQ-239: an Unroutable job is not "unfinished" for overlap, so REQ-225's "earlier occurrence's job" never includes it.

**What happens** (TLC counter-example, probe `Probe_Req225StartMeetsUnroutable`, `Recurring_P_Req225Unroutable.cfg`, Allow and CancelPrevious with 3 slots, 5 states). `tenant-sync` runs every minute with overlap Allow:
1. `tenant-sync` is stored and active (REQ-208).
2. The 10:00 occurrence starts and its job is enqueued (REQ-221).
3. The 10:01 occurrence is created while the 10:00 job is still enqueued. Allow starts it too (REQ-225).
4. No running worker lists the `TenantSync` handler. The 10:00 job has waited UnroutableAfter and is marked Unroutable (jobs REQ-124). The 10:01 job is still Enqueued because it has waited less. **This is the state the probe reports.**
5. The 10:02 occurrence is created. The 10:01 job is unfinished, so REQ-225 starts it, not REQ-221.
   - Read REQ-240 as written: the 10:00 job is cancelled with reason Superseded.
   - Read it as its dependsOn says (REQ-221 and REQ-224 starts only): the 10:00 job stays Unroutable. When `TenantSync` comes back, jobs REQ-125 returns it to Enqueued and it runs beside the newer jobs. Allow permits that.

With the dependsOn reading, the outcome for the 10:00 job depends on something unrelated: if the 10:01 job had finished before 10:02, the 10:02 occurrence would start under REQ-221 and the 10:00 job *would* be cancelled.

**Why** The sentence says "an occurrence ... starts", and REQ-225 records occurrences as started. But REQ-240 was written for run-2 F-1, which was about INV-204 (Skip and Queue only), and its metadata still reflects that. Skip and Queue never start through REQ-225, so INV-204 holds under both readings. Only Allow and CancelPrevious behave differently. The model uses the sentence as written (A-18).

**Options**
1. *(recommended)* **Confirm the sentence as written.** Add REQ-225 to dependsOn and say in the notes that every start supersedes, under every overlap policy. A recurring job then never has more than one Unroutable job under any policy, and the outcome no longer depends on whether another earlier job happened to be unfinished. This is what the model checks now; no other requirement changes. Cost: under Allow, a stale run that Allow would have let overlap is lost.
2. **Limit REQ-240 to Skip and Queue.** Add `"where": "the recurring job's overlap policy is Skip or Queue"`. Under Allow and CancelPrevious, a stale Unroutable job runs when its handler comes back, beside newer runs. That is consistent with Allow, but under CancelPrevious it is odd, because that policy exists to cancel earlier runs. INV-204 is unaffected (it covers Skip and Queue only).
3. **Limit REQ-240 to REQ-221 and REQ-224 starts**, as dependsOn suggests. Not recommended: as the example shows, the outcome then depends on whether an unrelated earlier job is still unfinished.

**Ready to apply (option 1)**
```json
{ "id": "REQ-240", "dependsOn": ["REQ-221", "REQ-224", "REQ-225", "REQ-239"],
  "notes": "refiner-model 2026-11-06 run 2 F-1 (recommended option; checked by the model over 262,576 states with all four overlap policies). The newer occurrence replaces the stale one, which is what Skip and Queue intend, so a recurring job never holds more than one Unroutable job and only one runs when a handler comes back. Cost: the stale occurrence's run is lost; the cancel reason says why. jobs REQ-134 already allows cancelling an Unroutable job, so the jobs module needs no change. Run 3 F-1: applies to every start under every overlap policy, including Allow and CancelPrevious starts under REQ-225." }
```
(Only `dependsOn` and the last sentence of `notes` change; the ears sentence stays.)

---

## F-2 · gap · low — An Unroutable "trigger now" run is cancelled as Superseded by the next scheduled occurrence
<!-- finding: gap | REQ-240 | REQ-240,REQ-226 -->

**Requirements involved**
- REQ-226: *When an operator triggers a recurring job now, optionally with an overridden payload, the system shall create an occurrence immediately, using the overridden payload if one was given, decide it by the overlap policy like a scheduled occurrence, and leave nextRunAt unchanged.*
- REQ-240 (quoted under F-1). Notes: *"Cost: the stale occurrence's run is lost; the cancel reason says why."*

**What happens** (TLC counter-example, action probe `ProbeAct_TriggerNowNeverSuperseded`, `Recurring_P_TriggerNowSuperseded.cfg`, 6 states, overlap Skip). `nightly-export` runs at 02:00 with overlap Skip, one export per tenant chosen by payload:
1. A worker node starts on a release that declares `nightly-export`, and the job is created (REQ-203).
2. An operator triggers `nightly-export` now with the payload overridden to tenant 42. The occurrence starts and its job is enqueued (REQ-226, REQ-221).
3. The 02:00 instant passes.
4. No running worker lists the `NightlyExport` handler, for example because a deploy dropped it. After UnroutableAfter the operator's job is marked Unroutable (jobs REQ-124).
5. The scheduler fires the 02:00 occurrence. The Unroutable job does not count as unfinished (REQ-239), so the occurrence starts (REQ-221). **In the same write the operator's tenant-42 job is cancelled with reason Superseded (REQ-240).** When the handler comes back, only the 02:00 run with the default payload runs. The tenant-42 export the operator asked for never happens, and nobody is told except by the cancel reason.

**Why** REQ-240 treats every earlier occurrence as interchangeable with the newer one. For scheduled occurrences that is true: same payload, same work. A "trigger now" occurrence may carry an overridden payload (REQ-226), so a later scheduled occurrence does not do the work it asked for. REQ-240's notes accept that a stale run is lost, but they do not mention the explicit operator run, which is the case where losing it surprises someone.

**Options**
1. *(recommended)* **Accept it and say so.** Add to REQ-240's notes that an Unroutable trigger-now occurrence is superseded like any other, and that the operator sees reason Superseded and triggers again once the handler is back. No behaviour change, and INV-204 stays as checked.
2. **Exempt overridden-payload occurrences from REQ-240 and keep their Unroutable job in the way.** Add an exception to REQ-239: an occurrence with an overridden payload whose job is Unroutable counts as unfinished. The operator's run is kept. But the recurring job's scheduled runs are skipped (Skip) or queued (Queue) until someone deals with the Unroutable job, which brings back the run-1 F-7 blockage for this case. Not model-checked; payloads are not modeled.
3. **Exempt them from REQ-240 only.** Not viable: the exempt job comes back beside the newer one when the handler reappears, which is exactly run-2 F-1 (INV-204 violated).

**Ready to apply (option 1)**
```json
{ "id": "REQ-240",
  "notes": "<existing notes> Run 3 F-2: an earlier trigger-now occurrence (REQ-226), even one with an overridden payload, is superseded like a scheduled one; the operator sees reason Superseded and triggers it again once the handler is back." }
```

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. A-1–A-17 are from runs 1 and 2 (changes marked).
| # | Assumption | Affects |
|---|---|---|
| A-1 | No clock. Each job keeps a count of due instants passed since nextRunAt was set (0, 1, "2 or more"), and time passing is a nondeterministic step. "nextRunAt computed from now" resets the count to 0. | REQ-215, REQ-216, REQ-227, REQ-204, REQ-206, REQ-241, INV-210 |
| A-2 | REQ-216's compare-and-set is one atomic step, so INV-203 and SCN-200 hold by construction. | INV-203, SCN-200 |
| A-3 | The newest due instant is late or on time by nondeterministic choice. With two or more instants due, the older ones are always missed, which assumes the schedule interval exceeds MisfireThreshold. | REQ-217–REQ-219, REQ-234, INV-207 |
| A-4 | RunAll(max) is modeled with max = 1, which makes it indistinguishable from RunOnce. | REQ-219 |
| A-5 | A trigger creates at most one occurrence. | REQ-216–REQ-219 |
| A-6 | Every modeled node has the worker registered. A node declares exactly what its release declares, and "running" means up. *(run 3)* What nodes publish in their heartbeat (declared names, and now each name's definition hash for REQ-241) is known to the scheduler at once; heartbeat expiry is not modeled. The scheduler (triggers, orphan sweep, REQ-241) and jobs REQ-125's handler registration need some running worker (hosting REQ-40). | REQ-203–REQ-207, REQ-216, REQ-241 |
| A-7 | REQ-224 is a separate system step after the earlier job finishes. | REQ-224 |
| A-8 | At node start, REQ-203 and REQ-204 are applied together for every declared name. The store is keyed by name, so INV-200 and SCN-207 hold by construction. | REQ-203, REQ-204, INV-200, SCN-207 |
| A-9 | Overlap, misfire and orphan policies are fixed per job for a whole run. | REQ-205, REQ-207, REQ-212, REQ-221–REQ-225 |
| A-10 | jobs.Job is reduced to Enqueued / Processing / Failed / Succeeded / DeadLettered / Cancelled / Unroutable plus a "handler still executing" flag (lease lost, jobs REQ-132; abandoned on timeout, jobs REQ-138/REQ-186). jobs REQ-125 (Unroutable → Enqueued) can happen whenever a worker runs. | INV-204, REQ-221–REQ-225, REQ-239, REQ-240 |
| A-11 | Occurrences whose job is final in the jobs module (not Unroutable) free their slot (modeling artefact). | all |
| A-12 | INV-204 is checked as written (`Inv_NoOverlapProcessing`, the Processing state). `Inv_NoOverlapRunning` (any executing handler) is kept only to show the window REQ-238 accepts. | INV-204, REQ-238 |
| A-13 | definitionHash is the hash of the code definition last applied. A runtime edit under AllowRuntimeOverride changes the stored definition but not the hash. *(run 3)* So REQ-241 never fires because of a runtime edit, and it overwrites one only when no running node's code matches the stored hash, as REQ-204 does at a node start. | REQ-204, REQ-212, REQ-241 |
| A-14 | Configuration-defined jobs are not modeled (INV-209 and REQ-232 are `may`), so REQ-236 is checked for code-defined names only. | INV-209, REQ-232, REQ-236 |
| A-15 | The same-trigger warnings from `validate` (REQ-205/REQ-207; REQ-222/REQ-223/REQ-225/REQ-235 with REQ-221) are each one action, with complementary and exhaustive guards. | — |
| A-16 | REQ-236's and REQ-210's "fail the host's start" (run 3 wording; was "stop the node from starting") is abstracted as the node staying down. The hosting module owns the node's states. | REQ-236 |
| A-17 | *(run 3)* One switch remains: `RerouteOn` explores jobs REQ-125 only in `MainR`, `F_RerouteOverlap`, `F_RerouteQueue` and SCN-215, so the run-1 fixes and the Unroutable rules are judged separately. The run-2 switch `FixCancelUnroutable` is gone: REQ-240 is a requirement and is always on. | INV-204, REQ-240 |
| A-18 | *(new)* REQ-240 is applied to every start: REQ-221, REQ-224 and REQ-225 (Allow and CancelPrevious). "Earlier" means created before, in creation order. See F-1. | REQ-240, REQ-225 |
| A-19 | *(new)* REQ-240's start and cancel are one atomic step, so jobs REQ-125 cannot return the job to Enqueued between them. The model cannot judge an implementation that reads the job's state and writes later; REQ-240's "in the same write" is what rules that out. | REQ-240, INV-204 |
| A-20 | *(new)* REQ-241 is a reconciliation step, not a scheduled trigger, so INV-210 does not stop it during maintenance (as for REQ-204 and REQ-206 in INV-210's notes). Whether the schedule changed is a nondeterministic choice, as in REQ-204. | REQ-241, INV-210 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-201–REQ-208, REQ-211–REQ-227, REQ-233–REQ-237, REQ-239–REQ-241, INV-200, INV-201, INV-203, INV-204, INV-206, INV-207, INV-210, INV-211, SCN-200–SCN-215 | REQ-200, REQ-228, REQ-229, REQ-230, INV-202, INV-208 (need a real clock: time zones, DST, validity window) · REQ-209, REQ-210 (schedule/time-zone validity not representable; REQ-210's rewording changes nothing here) · INV-205 (no exceptions or lock waits in the model) · REQ-231 (bookkeeping, nothing depends on it) · REQ-232, INV-209 (strength `may`) · REQ-238 (`info`; shown by `Inv_NoOverlapRunning`) |

Not judged although modeled: INV-200, INV-203, SCN-200 and SCN-207 hold by construction (A-2, A-8). REQ-219 is modeled only with max = 1 (A-4). REQ-236 is checked for code-defined names only (A-14). REQ-241's settling is checked as "eventually", not "within a time" (A-6). The cancel reason Superseded (REQ-240) is not modeled.

## How to reproduce
From `specs/model/recurring`: `sh gen_cfgs.sh` regenerates the non-scenario cfgs, and `sh run_all.sh` reruns every check below. Each check is one `run_tlc.py Recurring.tla --config <cfg> --stop-at-first --workers 2` call; scenario cfgs add `--no-deadlock`. `run_all.sh <name>` runs one check. The `run*.json`/`run*.md` outputs are gitignored.

- TLC 2.19 throws "unexpected exception" when `-continue` has to rebuild many traces, so every check uses `--stop-at-first`. The run that produced this report grepped every output for that message and found none.
- `run_all.sh` wraps each run in `timeout` because `run_tlc.py --timeout` does not stop TLC on Windows. This run used `TLC_TIMEOUT=290` (so `timeout 300`) for the five three-slot Queue cfgs and `TLC_TIMEOUT=160` (`timeout 170`) for the rest. None hit the limit.
- Don't start a second TLC run in this folder while one is running: TLC's `-cleanup` removes the shared `states/` folder and the other run fails with "when reading the disk".

| Check | Config | Result |
|---|---|---|
| Main: INV-201, INV-210 (both), REQ-233, SCN-200/202, REQ-237, REQ-239 skip rule, INV-204 (1 job, 2 slots, Skip/Queue × RunOnce/Skip) | `Recurring.cfg` | passed, 194,712 distinct, 6 s |
| Main with jobs REQ-125, now including INV-204 | `Recurring_MainR.cfg` | passed, 194,712 distinct, 6 s |
| Definitions: REQ-211/SCN-205, INV-206/SCN-212, SCN-208, INV-211/SCN-214, REQ-236, REQ-237 (2 jobs, 2 nodes, both orphan policies) | `Recurring_Defs.cfg` | passed, 44,552 distinct, 3 s |
| Overlap, all four policies, 2 slots: REQ-233, INV-204, REQ-239 skip rule | `Recurring_OverlapAll.cfg` | passed, 262,576 distinct, 7 s |
| Overlap Queue(1), 3 slots: REQ-233, REQ-237, REQ-239 skip rule | `Recurring_OverlapQueue.cfg` | passed, 7,439,116 distinct, 211 s |
| Overlap Queue(2), 3 slots: REQ-233, REQ-239 skip rule | `Recurring_OverlapQueue2.cfg` | passed, 7,191,148 distinct, 203 s |
| Run-1 F-1: INV-204, Queue(1), 3 slots | `Recurring_F_WaitingRace.cfg` | passed, 7,439,116 distinct, 171 s |
| Run-1 F-2: probe + INV-204, Queue(2), 3 slots | `Recurring_P_QueueTwoWaiters.cfg` | passed, 7,191,148 distinct, 177 s |
| Run-1 F-5: probe, one node, 3 releases | `Recurring_P_StaleDefinition.cfg` | passed, 19,500 distinct, 2 s |
| Run-1 F-6: probe | `Recurring_P_RuntimeTakenOver.cfg` | passed, 19,500 distinct, 2 s |
| Run-1 F-7: REQ-239 skip rule | `Recurring_P_UnroutableBlocks.cfg` | passed, 262,576 distinct, 6 s |
| **Run-2 F-1**: INV-204 + skip rule with jobs REQ-125 and REQ-240, all four policies | `Recurring_F_RerouteOverlap.cfg` | passed, 262,576 distinct, 6 s |
| **Run-2 F-1**: INV-204, REQ-233, REQ-237, skip rule with jobs REQ-125 and REQ-240, Queue(1), 3 slots | `Recurring_F_RerouteQueue.cfg` | passed, 7,439,116 distinct, 231 s |
| **Run-2 F-2**: REQ-241 settling (liveness + action property), two nodes, v1/v2 | `Recurring_Liv_Settles.cfg` | passed, 14,478 distinct, 4 s |
| **Run-2 F-2**: same, two nodes, three releases, AllowRuntimeOverride | `Recurring_Liv_Settles3.cfg` | passed, 72,078 distinct, 13 s |
| Run-2 F-2 window (probe; REQ-241 closes it one step later) | `Recurring_P_StaleDefinition2.cfg` | probe violated, 5 states, as expected |
| **F-1**: a REQ-225 start can meet an Unroutable job (probe) | `Recurring_P_Req225Unroutable.cfg` | probe violated, 5 states |
| **F-2**: a trigger-now Unroutable job superseded by a scheduled start (action probe) | `Recurring_P_TriggerNowSuperseded.cfg` | action probe violated, 6 states (`run_tlc.py` labels an action-property violation "error"; the TLC message is "Action property … is violated") |
| REQ-238 window (info) | `Recurring_F_RunningHandlers.cfg` | `Inv_NoOverlapRunning` violated, 7 states, as REQ-238 accepts |
| SCN-201, 203, 204, 206, 209 (legs `SCN209`, `SCN209b`), 210, 211, 213, 215 | `Recurring_SCNnnn.cfg` | every trap violated as expected (2–6 states): all reachable |

Deadlock checking is on in every non-scenario run, and none was found. Probes (`Probe_…`, `ProbeAct_…`) are modeling aids, not requirements: each asserts that a situation is unreachable. The vacuity check for `Liv_DefinitionSettles` (REQ-241 removed) ran on a scratch copy outside the repository and is not part of `run_all.sh`.

## Next
Apply the chosen options to `specs/recurring.json` with the `refiner-requirements` skill (it validates and diffs), then run `refiner-model` again. Both findings are notes-and-metadata changes if you take the recommended options; neither changes a sentence.
