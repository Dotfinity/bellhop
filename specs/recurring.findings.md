# Findings: Bellhop recurring jobs

<!-- refiner-findings v1 | module: recurring | specHash: bc55236159f462fed18c1d62632276c66ae81b412d1ff99889134318e25ce2cf | run: 2026-11-06 (run 2) | previous: specs/model/recurring/previous.findings.md (run 1, specHash 577c79cef0e7) -->

**Run:** 2026-11-06, run 2 · **Requirements file:** `specs/recurring.json` (specHash `bc55236159f4`) · **Model:** `specs/model/recurring/Recurring.tla` · **TLC:** 2.19; every check ran alone with `--stop-at-first` and completed with no TLC exception (24 cfgs, up to 7,356,508 distinct states, ≤ 157 s each); see [How to reproduce](#how-to-reproduce)
**Result:** 2 findings — 1 contradiction · 1 gap · 0 unprovable · 0 ambiguities · 0 modeling notes. All 11 run-1 findings are resolved.

The model has no clock. Anything that depends on real amounts of time (DST, time zones, validity windows, the 60 s misfire threshold as a number) is outside what it can judge; see *Coverage*.

## Changes since last run
| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | contradiction · INV-204 · REQ-221,REQ-223,REQ-224 |
| F-2 | resolved | contradiction · INV-204 · REQ-223,REQ-224,REQ-233 |
| F-3 | resolved | contradiction · INV-204 · REQ-221,jobs.REQ-132,jobs.REQ-138,jobs.REQ-186 |
| F-4 | resolved | contradiction · INV-210 · REQ-206,REQ-215,REQ-227 |
| F-5 | resolved | gap · RecurringJob.definitionHash · REQ-204,REQ-206 |
| F-6 | resolved | gap · RecurringJob.origin · REQ-203,REQ-204,REQ-208,REQ-213 |
| F-7 | resolved | gap · Occurrence.job · REQ-221,REQ-222,REQ-235,jobs.REQ-124 |
| F-8 | resolved | ambiguity · Occurrence.Waiting · REQ-205,REQ-207,REQ-213,REQ-214,REQ-224 |
| F-9 | resolved | ambiguity · REQ-217 · INV-207,REQ-217,REQ-218 |
| F-10 | resolved | ambiguity · REQ-227 · REQ-204,REQ-227 |
| F-11 | resolved | ambiguity · RecurringJob.orphanPolicy · REQ-205,REQ-207 |
| F-1 | new | contradiction · INV-204 · REQ-221,REQ-224,REQ-239,jobs.REQ-124,jobs.REQ-125 |
| F-2 | new | gap · REQ-204 · REQ-204,REQ-206 |

11 resolved, 2 new, 0 still open

(Table from `findings_delta.py`.) How each run-1 finding was re-checked against the changed requirements:

| Run-1 finding | Requirement change | Evidence in run 2 |
|---|---|---|
| F-1 Queue(1) waiting race | REQ-221–REQ-225, REQ-235: a waiting occurrence is "in the way" | The run-1 trace config `Recurring_F_WaitingRace.cfg` (`Inv_NoOverlapProcessing`, 3 slots) now **passes**: 7,356,508 distinct states. SCN-213 (the regression scenario) is reachable in 5 states. |
| F-2 Queue(≥ 2) releases every waiter | REQ-224: start only when nothing earlier is waiting or unfinished | `Recurring_P_QueueTwoWaiters.cfg` (the run-1 probe plus `Inv_NoOverlapProcessing`, Queue(2), 3 slots) now **passes**: 7,108,540 distinct states. |
| F-3 abandoned handler overlaps | INV-204 now counts the Processing *state*; REQ-238 (`info`) accepts the handler overlap | `Inv_NoOverlapProcessing` passes in every config without jobs REQ-125 (see F-1 below for the one with it). `Inv_NoOverlapRunning`, kept to show the accepted window, is still violated in 7 states as REQ-238 says. |
| F-4 maintenance vs nextRunAt | INV-210 narrowed to the scheduler | `Inv_NoScheduleInMaintenance` and `Prop_NoScheduledAdvanceInMaintenance` pass (`Recurring.cfg`, `Recurring_MainR.cfg`). The run-1 property encoded the broad reading, which is no longer required; its config was removed. |
| F-5 restored orphan keeps old definition | REQ-206 applies the declaring node's code | `Recurring_P_StaleDefinition.cfg` (one node, three releases) now **passes**: 19,500 distinct states. With two nodes a related gap remains (F-2 below). |
| F-6 runtime and code job merge | INV-211, REQ-236, REQ-204 limited to code origin | `Recurring_P_RuntimeTakenOver.cfg` now **passes** (19,500 states). `Scn_StoredNameCannotBeAdded` (INV-211, SCN-214) and `Scn_RuntimeNameBlocksStart` (REQ-236) pass in `Recurring_Defs.cfg` (44,552 states). |
| F-7 unroutable job blocks for good | REQ-239 counts Unroutable as finished | `Prop_SkipOnlyWhenInTheWay` passes in `Recurring_P_UnroutableBlocks.cfg` (261,424 states). The change opens a new contradiction (F-1 below). |
| F-8 waiting occurrences after pause/orphan/removal | REQ-237 | `Prop_PauseOrphanRemoveSkipsWaiting` passes in Main, MainR, Defs and the Queue(1) config. |
| F-9 misfire count | REQ-217–REQ-219 judge the newest instant on its own | Modeled as written; SCN-206 (RunOnce catch-up) and SCN-211 (Skip, on time) are reachable. Nothing left to choose. |
| F-10 schedule change with new code | REQ-204 recomputes nextRunAt from now | Modeled (nondeterministic "schedule changed" at node start); no check fails. |
| F-11 orphan policy undefined | per-job `orphanPolicy` attribute | Modeled as a per-job constant; `Recurring_Defs.cfg` explores both values for two jobs. |

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | contradiction | high | INV-204, REQ-239, REQ-221, REQ-224, jobs REQ-124, jobs REQ-125 | An Unroutable occurrence job counts as finished, the next occurrence starts, then the old job comes back and both run |
| F-2 | gap | medium | REQ-204, REQ-206 | After a rollback, or an old node restarting late in a deploy, the stored definition belongs to a release no running node runs, and nothing fixes it |

---

## F-1 · contradiction · high — An Unroutable occurrence job counts as finished, the next occurrence starts, then the old job comes back and both run
<!-- finding: contradiction | INV-204 | REQ-239,REQ-221,REQ-224,jobs.REQ-124,jobs.REQ-125 -->

**Requirements involved**
- INV-204: *Where a recurring job's overlap policy is Skip or Queue, the system shall never have two of its occurrences' jobs in the Processing state at the same time.*
- REQ-239: *The system shall treat an occurrence's job as unfinished for overlap decisions while it is not Succeeded, DeadLettered, Cancelled or Unroutable.*
- REQ-221: *When an occurrence is created and no earlier occurrence of the same recurring job is waiting or has an unfinished job, the system shall enqueue a job with the recurring job's payload and record the occurrence as started.* (REQ-224 is the same for a waiting occurrence.)
- jobs REQ-125: *While a job is unroutable, when a running worker node registers a handler for its name or one of its aliases, the system shall return the job to enqueued.*

**What happens** (TLC counter-example, `Inv_NoOverlapProcessing`, `Recurring_F_RerouteOverlap.cfg`, 8 states). `sync-crm` runs every minute with overlap Skip:
1. A worker node starts and creates the code-defined job (REQ-203).
2. The 10:00 occurrence starts and its job is enqueued (REQ-216, REQ-221).
3. No running worker lists a handler for `SyncCrm`, for example because a deploy dropped it. After UnroutableAfter the 10:00 job is marked Unroutable (jobs REQ-124).
4. The 10:06 occurrence is created. The 10:00 job is Unroutable, which counts as finished (REQ-239), so nothing is in the way and the 10:06 occurrence starts with an enqueued job (REQ-221).
5. A worker node with the `SyncCrm` handler starts. The 10:00 job goes back to Enqueued (jobs REQ-125).
6. The 10:00 job is claimed and is Processing (jobs REQ-123).
7. The 10:06 job is claimed on another worker and is Processing too. **Two of `sync-crm`'s occurrences' jobs are Processing; INV-204 is violated.**

(Step 2 uses "trigger now" (REQ-226) in the TLC trace; a scheduled trigger gives the same result.)

**Why** REQ-239 treats Unroutable as final for overlap, which fixed run-1 F-7. But Unroutable is not final in the jobs module: REQ-125 brings the job back as soon as a handler appears, and that is exactly when the newer occurrence's job becomes runnable too.

**Options**
1. *(recommended)* **Supersede the stale job.** When an occurrence starts (REQ-221 or REQ-224) while an earlier occurrence of the same recurring job has an Unroutable job, cancel that job in the same write. jobs REQ-134 already allows cancelling an Unroutable job. The newer occurrence replaces the stale one, which is what Skip and Queue intend. Checked: with this rule (`Recurring_F_RerouteOverlapFix.cfg`, all four overlap policies, REQ-125 on), `Inv_NoOverlapProcessing` and `Prop_SkipOnlyWhenInTheWay` **pass** over 262,576 distinct states. Cost: the stale occurrence's run is lost; it is recorded as cancelled.
2. **Undo the Unroutable part of REQ-239** and report the block instead (run-1 F-7 option 2): an Unroutable job is in the way again, and a recurring job blocked by one is reported on the dashboard and in health. INV-204 then holds, but the recurring job stops until someone acts.
3. **Change jobs REQ-125** so that an occurrence job is cancelled instead of returned to Enqueued when a later occurrence of its recurring job has started. This puts recurring knowledge into the jobs module.

**Ready to apply (option 1)**
```json
{ "id": "REQ-240", "kind": "transition", "status": "approved", "strength": "must",
  "entity": "jobs.Job", "actor": "system", "from": ["Unroutable"], "to": ["Cancelled"],
  "ears": { "when": "an occurrence of a recurring job is started while an earlier occurrence of the same recurring job has an unroutable job",
            "shall": "cancel the earlier occurrence's unroutable job in the same write that starts the new occurrence" },
  "mentions": ["Occurrence.job", "jobs.Job.Unroutable", "jobs.Job.Cancelled"],
  "dependsOn": ["REQ-239", "REQ-221", "REQ-224"],
  "notes": "refiner-model 2026-11-06 run 2 F-1: without this, jobs REQ-125 returns the Unroutable job to Enqueued when a handler appears, beside the newer occurrence's job (INV-204). jobs REQ-134 already allows cancelling an Unroutable job." }
```
Add REQ-240 to the feature that holds REQ-221–REQ-225.

---

## F-2 · gap · medium — After a rollback, or an old node restarting late in a deploy, the stored definition belongs to a release no running node runs
<!-- finding: gap | REQ-204 | REQ-204,REQ-206 -->

**Requirements involved**
- REQ-204: *When a node with the worker registered starts and the hash of a code-defined recurring job's code definition differs from the definitionHash of the stored code-defined job with that name, the system shall update the stored definition and definitionHash to match the code, …*
- REQ-204 notes: *"During a rolling deploy, nodes on N and N+1 may rewrite a changed definition back and forth; the last writer wins and it settles when the deploy ends."*
- REQ-206: *When a running worker node declares an orphaned recurring job again, the system shall … update the stored definition and definitionHash to match that node's code definition …*

**What happens** (TLC counter-example, probe `Probe_StaleDefinitionAfterRestore`, `Recurring_P_StaleDefinition2.cfg`, 4 states). `weekly-report` is code-defined. Release v1 and release v2 declare it with different schedules:
1. Node a starts on v1 and creates the job with v1's definition (REQ-203).
2. Node b starts on v2 and rewrites the stored definition to v2's (REQ-204).
3. The v2 deploy is rolled back: node b stops. **Only v1 runs, but the stored definition, schedule included, is v2's.** Nothing in the requirements rewrites it until some node starts again.

The forward case is the same: an old v1 node that restarts after the last v2 node started (a crash during the deploy) writes v1's definition back. When the v1 nodes are then stopped, no node starts, and the stored definition stays v1 while only v2 runs. So the note's "it settles when the deploy ends" holds only if the last node to start runs the new release. REQ-206 has the same root: with nodes on two releases, "that node's code definition" is whichever one restores the job.

**Why** The stored definition is reconciled only at node start (REQ-204) and on restore (REQ-206), so it reflects the last node to start, not the nodes that are running.

**Options**
1. *(recommended)* **Reconcile while running.** Add a scheduler rule: when the scheduler finds a stored code-defined job whose definitionHash matches the code of *no* running worker node that declares it, update it to the code of one such node, with REQ-204's rules. While the hash matches any running node's code nothing changes, so there is no back-and-forth during a deploy, and the definition settles as soon as the running nodes agree. Not model-checked: settling is an "eventually" property and the model has no liveness requirement for it. The state probe is violated for a moment by design.
2. **Document it.** After a rollback, or after an old node restarted during a deploy, restart one node of the intended release. Correct the REQ-204 note.
3. **Let only a newer definition overwrite an older one** (needs a definition version). The back-and-forth stops, but a rollback then never restores the old schedule.

**Ready to apply (option 1)**
```json
{ "id": "REQ-241", "kind": "transition", "status": "approved", "strength": "must",
  "entity": "RecurringJob", "actor": "system", "from": ["Active", "Paused"], "to": ["Active", "Paused"],
  "ears": { "when": "the scheduler finds a stored code-defined recurring job whose definitionHash matches the code definition of no running worker node that declares it",
            "shall": "update the stored definition and definitionHash to the code definition of one such node, keeping its paused or active state, and, if the schedule changed, compute nextRunAt from now as in REQ-227" },
  "mentions": ["RecurringJob.definitionHash", "RecurringJob.origin", "RecurringJob.nextRunAt", "hosting.Node.Running"],
  "dependsOn": ["REQ-204", "REQ-227"],
  "notes": "refiner-model 2026-11-06 run 2 F-2: REQ-204 runs only at node start, so after a rollback or a late restart of an old node the stored definition can belong to a release no running node runs." }
```
And correct the REQ-204 note ("it settles when the deploy ends") to point at REQ-241.

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. A-1–A-15 are from run 1 (changes marked).
| # | Assumption | Affects |
|---|---|---|
| A-1 | No clock. Each job keeps a count of due instants passed since nextRunAt was set (0, 1, "2 or more"), and time passing is a nondeterministic step. "nextRunAt computed from now" resets the count to 0. | REQ-215, REQ-216, REQ-227, REQ-204, REQ-206, INV-210 |
| A-2 | REQ-216's compare-and-set is one atomic step, so INV-203 and SCN-200 hold by construction. | INV-203, SCN-200 |
| A-3 | *(run 2)* The newest due instant is late or on time by nondeterministic choice. With two or more instants due, the older ones are always missed, which assumes the schedule interval exceeds MisfireThreshold. | REQ-217–REQ-219, REQ-234, INV-207 |
| A-4 | RunAll(max) is modeled with max = 1, which makes it indistinguishable from RunOnce. | REQ-219 |
| A-5 | A trigger creates at most one occurrence. | REQ-216–REQ-219 |
| A-6 | Every modeled node has the worker registered. A node declares exactly what its release declares, and "running" means up. The scheduler (triggers, orphan sweep) and jobs REQ-125's handler registration need some running worker (hosting REQ-40). | REQ-203–REQ-207, REQ-216 |
| A-7 | REQ-224 is a separate system step after the earlier job finishes. | REQ-224 |
| A-8 | At node start, REQ-203 and REQ-204 are applied together for every declared name. The store is keyed by name, so INV-200 and SCN-207 hold by construction. | REQ-203, REQ-204, INV-200, SCN-207 |
| A-9 | *(run 2)* Overlap, misfire and orphan policies are fixed per job for a whole run (orphanPolicy is now a per-job attribute). | REQ-205, REQ-207, REQ-212, REQ-221–REQ-225 |
| A-10 | jobs.Job is reduced to Enqueued / Processing / Failed / Succeeded / DeadLettered / Cancelled / Unroutable plus a "handler still executing" flag (lease lost, jobs REQ-132; abandoned on timeout, jobs REQ-138/REQ-186). *(run 2)* jobs REQ-125 (Unroutable → Enqueued) is added; handlers are abstract, so it can happen whenever a worker runs. | INV-204, REQ-221–REQ-225, REQ-239 |
| A-11 | *(run 2)* Occurrences whose job is final in the jobs module (not Unroutable) free their slot (modeling artefact). | all |
| A-12 | *(run 2)* INV-204 is checked as written (`Inv_NoOverlapProcessing`, the Processing state). `Inv_NoOverlapRunning` (any executing handler) is kept only to show the window REQ-238 accepts. | INV-204, REQ-238 |
| A-13 | definitionHash is the hash of the code definition last applied. A runtime edit under AllowRuntimeOverride changes the stored definition but not the hash. | REQ-204, REQ-212 |
| A-14 | Configuration-defined jobs are not modeled (INV-209 and REQ-232 are `may`). *(run 2)* So REQ-236 is checked for code-defined names only. | INV-209, REQ-232, REQ-236 |
| A-15 | The same-trigger warnings from `validate` (REQ-205/REQ-207; REQ-222/REQ-223/REQ-225/REQ-235 with REQ-221) are each one action, with complementary and exhaustive guards. | — |
| A-16 | *(new)* REQ-236's StartupFailed is abstracted as the node staying down. The hosting module owns the node's states. | REQ-236 |
| A-17 | *(new)* Two switches separate the checks: `RerouteOn` explores jobs REQ-125 only in `MainR`, `F_RerouteOverlap` and `F_RerouteOverlapFix`, so the run-1 fixes and F-1 are judged separately. `FixCancelUnroutable` turns on F-1's candidate fix (option 1) only in `F_RerouteOverlapFix`; it is not a requirement. | INV-204, F-1 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-201–REQ-208, REQ-211–REQ-227, REQ-233–REQ-237, REQ-239, INV-200, INV-201, INV-203, INV-204, INV-206, INV-207, INV-210, INV-211, SCN-200–SCN-214 | REQ-200, REQ-228, REQ-229, REQ-230, INV-202, INV-208 (need a real clock: time zones, DST, validity window) · REQ-209, REQ-210 (schedule/time-zone validity not representable) · INV-205 (no exceptions or lock waits in the model) · REQ-231 (bookkeeping, nothing depends on it) · REQ-232, INV-209 (strength `may`) · REQ-238 (`info`; shown by `Inv_NoOverlapRunning`) |

Not judged although modeled: INV-200, INV-203, SCN-200 and SCN-207 hold by construction (A-2, A-8). REQ-219 is modeled only with max = 1 (A-4). REQ-236 is checked for code-defined names only (A-14).

## How to reproduce
From `specs/model/recurring`: `sh gen_cfgs.sh` regenerates the non-scenario cfgs, and `sh run_all.sh` reruns every check below. Each check is one `run_tlc.py Recurring.tla --config <cfg> --stop-at-first --workers 2` call; scenario cfgs add `--no-deadlock`. `run_all.sh <name>` runs one check. The `run*.json`/`run*.md` outputs are gitignored.

- TLC 2.19 throws "unexpected exception" when `-continue` has to rebuild many traces, so every check uses `--stop-at-first`; the run that produced this report grepped every output for that message and found none.
- The three-slot Queue cfgs (about 7 M distinct states) take 2–3 minutes with other TLC runs on the machine, longer than `run_tlc.py`'s 120 s default. `run_all.sh` therefore uses a 300 s limit (`TLC_TIMEOUT`), and wraps each run in `timeout`, because `run_tlc.py --timeout` does not stop TLC on Windows.
- Don't start a second TLC run in this folder while one is running: TLC's `-cleanup` removes the shared `states/` folder and the other run fails with "when reading the disk".

| Check | Config | Result |
|---|---|---|
| Main: INV-201, INV-210 (both), REQ-233, SCN-200/202, REQ-237, REQ-239 skip rule, INV-204 — 1 job, 2 slots, Skip/Queue × RunOnce/Skip | `Recurring.cfg` | passed, 193,176 distinct, 3 s |
| Main with jobs REQ-125, every check except INV-204 | `Recurring_MainR.cfg` | passed, 303,768 distinct, 6 s |
| Definitions: REQ-211/SCN-205, INV-206/SCN-212, SCN-208, INV-211/SCN-214, REQ-236, REQ-237 — 2 jobs, 2 nodes, both orphan policies | `Recurring_Defs.cfg` | passed, 44,552 distinct, 2 s |
| Overlap, all four policies, 2 slots: REQ-233, INV-204, REQ-239 skip rule | `Recurring_OverlapAll.cfg` | passed, 261,424 distinct, 4 s |
| Overlap Queue(1), 3 slots: REQ-233, REQ-237, REQ-239 skip rule | `Recurring_OverlapQueue.cfg` | passed, 7,356,508 distinct, 156 s |
| Overlap Queue(2), 3 slots: REQ-233, REQ-239 skip rule | `Recurring_OverlapQueue2.cfg` | passed, 7,108,540 distinct, 138 s |
| Run-1 F-1: INV-204, Queue(1), 3 slots | `Recurring_F_WaitingRace.cfg` | passed, 7,356,508 distinct, 125 s |
| Run-1 F-2: probe + INV-204, Queue(2), 3 slots | `Recurring_P_QueueTwoWaiters.cfg` | passed, 7,108,540 distinct, 123 s |
| Run-1 F-5: probe, one node, 3 releases | `Recurring_P_StaleDefinition.cfg` | passed, 19,500 distinct, 1 s |
| Run-1 F-6: probe | `Recurring_P_RuntimeTakenOver.cfg` | passed, 19,500 distinct, 1 s |
| Run-1 F-7: REQ-239 skip rule | `Recurring_P_UnroutableBlocks.cfg` | passed, 261,424 distinct, 4 s |
| **F-1**: INV-204 with jobs REQ-125 | `Recurring_F_RerouteOverlap.cfg` | `Inv_NoOverlapProcessing` violated, 8 states |
| F-1 option 1 (candidate fix) | `Recurring_F_RerouteOverlapFix.cfg` | passed, 262,576 distinct, 4 s |
| **F-2**: probe, two nodes on v1/v2 | `Recurring_P_StaleDefinition2.cfg` | probe violated, 4 states |
| REQ-238 window (info) | `Recurring_F_RunningHandlers.cfg` | `Inv_NoOverlapRunning` violated, 7 states, as REQ-238 accepts |
| SCN-201, 203, 204, 206, 209 (legs `SCN209`, `SCN209b`), 210, 211, 213 | `Recurring_SCNnnn.cfg` | every trap violated as expected (2–6 states): all reachable |

Deadlock checking is on in every non-scenario run, and none was found. Probes (`Probe_…`) are modeling aids, not requirements: each asserts that a situation is unreachable.

## Next
Apply the chosen options to `specs/recurring.json` with the `refiner-requirements` skill (it validates and diffs), then run `refiner-model` again. F-1 also touches the jobs module's view of Unroutable; option 1 needs no jobs change.
