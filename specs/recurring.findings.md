# Findings: Bellhop recurring jobs

<!-- refiner-findings v1 | module: recurring | specHash: 0737c73dad5917b30ea6271c4b79240e557492a905b0d8e31802056e6326afc5 | run: 2026-11-08 (run 9) | previous: specs/model/recurring/previous.findings.md (run 8, specHash 551cdd1a5b91) -->

**Run:** 2026-11-08, run 9 · **Requirements file:** `specs/recurring.json` (specHash `0737c73dad59`) · **Model:** `specs/model/recurring/Recurring.tla` (REQ-206's restore is now fair), plus `RecurringRace.tla` (the same in `SpecRC`) · **TLC:** 2.19. Every check ran alone with `--stop-at-first --workers 4` and finished with no TLC exception and no timeout: 96 cfgs, up to 8,741,112 distinct states, at most 356 s each. See [How to reproduce](#how-to-reproduce).
**Result:** 1 finding: 0 contradictions · 0 gaps · 0 unprovable · 1 ambiguity · 0 modeling notes. Run-8 F-1 is resolved: with REQ-206 the scheduler's (`actor: system`), a declared orphan is restored as written, for a plain rollback (SCN-209) and for the race INV-212's notes describe, also with the sweep, the restore, REQ-241 and the create split. The reconciliation also stops once the running nodes stop changing (no flip-flop between orphaning and restoring). The new finding is not about this run's change: REQ-206's definition update, unchanged since run 1, also discards an operator's runtime edit (AllowRuntimeOverride) when the code it restores is the same code. REQ-204's notes say such an edit survives deploys that leave the code unchanged (F-1).

The model has no clock. It cannot judge anything that depends on real amounts of time: DST, time zones, validity windows, the 60 s misfire threshold as a number, how long REQ-242's record is kept, or how long a read-to-write window or a scheduler pass lasts. See *Coverage*.

## Changes since last run
| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | unprovable · Liv_DeclaredConverges · INV-212,REQ-203,REQ-206,REQ-207 |
| F-1 | new | ambiguity · REQ-206 definition update · REQ-204,REQ-206,REQ-212 |

1 resolved, 1 new, 0 still open

Run-8 F-1 is resolved by its option 1. The new F-1 was found while regenerating REQ-206 for this run: its `shall` has said this since run-1 F-5, and no earlier run checked a runtime edit across an orphaning.

(Table from `findings_delta.py`; the "resolved" row uses run 8's numbers.) What changed in the requirements (handoff `specs/model/recurring/handoff.json`, base 551cdd1a5b91, resolution commit 4c0b4e4):
- **REQ-206**: `actor: system` (was Host), and its trigger is now *"the scheduler finds an orphaned recurring job that a running worker node declares"* (was *"a running worker node declares an orphaned recurring job again"*). The `shall` is unchanged.
- **INV-212**: notes only (no hash change). They now also name the transient listed under *Also checked* in run 8: a REQ-203 scheduler create that lands after the node it took the definition from has stopped is corrected by the next pass.
- Impacted, re-checked: INV-212, SCN-209.

Model changes:
- **`Recurring.tla`.** `Fairness` now includes `WF_vars(Restore(r))` (`@req REQ-206`, actor system). Run 8's reading is kept as the counterfactual `SpecCF_RestoreHost` (fairness without the restore, `FairnessHost`). `SpecRestoreFair` is gone, because it is now `Spec`. New properties: `Liv_ReconcileStops` (the scheduler's reconciliation stops once the nodes stop changing) and its counterpart without the escape clause, `Liv_ReconcileStopsAlways`, and `Liv_Scn209Restored` with specs `SpecSCN209b` / `SpecSCN209bH` (SCN-209 leg b as an obligation). There is a new probe, `ProbeAct_RestoreKeepsRuntimeEdit`, and the F-1 option spec `SpecOpt206` (`RestoreOpt206`, `NextOpt206`). Every other action and property is byte-for-byte unchanged. Regression: every `Recurring` cfg that ran in run 8 gives the same distinct-state count. Fairness does not change which states are reachable.
- **`RecurringRace.tla`.** `FairSched` now includes the restore. Run 8's `FairSched` is `FairSchedHost`, and `SpecRC_CF_RestoreHost` is the counterfactual. `SpecRCF` is gone, because it is now `SpecRC`. Nothing else changed.
- **cfgs.** Renamed so that "as written" and "counterfactual" are clear: `Recurring_Liv_Converge` is now as written (`Spec`, expected to hold; it was expected violated in run 8), and run 8's `…_ConvergeOpt` is gone (it was the same check). `Recurring_Liv_CF_ConvergeHost` is the counterfactual (run-8 F-1's trace). In the race model, `Recurring_Race_LiveConv` is now as written (`SpecRC`), run 8's `…_LiveConvW` is gone, and `Recurring_Race_CF_LiveConvHost` is the counterfactual. `Liv_ReconcileStops` was added to `Liv_Converge`, `Liv_ConvergeDel`, `Race_LiveConv` and `Race_LiveConvDel`. New: `Recurring_Liv_ReconcileFlip`, `Recurring_SCN209L` / `…_SCN209LH` (hand-written, like the other scenario cfgs), `Recurring_Race_OTrigger`, `Recurring_Race_RestoreSchO`, `Recurring_Race_UpdateSchOrph` (new constant set ORPHO: ORPH2 with AllowRuntimeOverride and no occurrence slots), `Recurring_P_RestoreDropsEdit` and `Recurring_F_RestoreKeepsEditOpt` (F-1). `Race_CreateDecl` is now labelled an accepted transient.

How the run-8 finding was re-checked:

| Run-8 finding | Requirement change | Evidence in run 9 |
|---|---|---|
| F-1: nothing obliges REQ-206 to restore a declared orphan | REQ-206 is `actor: system`, triggered by the scheduler | `Liv_DeclaredConverges` holds as written in the atomic model (`Liv_Converge`, 30,854 distinct, both orphan policies) and with the sweep, the restore, REQ-241 and the create split (`Race_LiveConv`, 272,096 distinct, 126 s). SCN-209 is now guaranteed, not only reachable (`SCN209L` passes, 73,000 distinct). With run 8's REQ-206 each fails as before: `Liv_CF_ConvergeHost` (10-state lasso: the run-8 trace, with `weekly-report` orphaned while node A on N declares it), `Race_CF_LiveConvHost` (7 states, ending in stuttering), `SCN209LH` (8-state lasso). |

**INV-212 per write** (every as-written check below also passes every REQ-242 property, INV-201, INV-203, INV-204 in the one-job cfgs, REQ-233, REQ-237, REQ-205's recorded state and REQ-206's return state. The two-node ones add the heartbeat properties that the write does not break. Each counterfactual fails in 5 to 12 states). Unchanged from run 8 except the rows marked *(run 9)*:

| Write | As written | Counterfactual (what fails without that part of INV-212) |
|---|---|---|
| Trigger (REQ-216) | holds, incl. `Prop_Refines` (`Race_Trigger`, `Race_TriggerSch`). *(run 9)* Also with two nodes, three releases and both orphan policies, so the job can be orphaned and restored between the trigger's read and its write (`Race_OTrigger`, 2,548,546 distinct) | *Without maintenance*: `Race_CF_TriggerMaint` (INV-210). *Without the state*: `Race_CF_TriggerNra` (INV-201; SCN-217 the same way, `RSCN217n`). *Without nextRunAt*: `Race_CF_TriggerSt` (INV-203, SCN-200). |
| Pause (REQ-214) | holds (`Race_Pause`, `Race_OPause`) | `Race_CF_Pause`, `Race_CF_PauseAtRead`, `Race_CF_PauseNra` |
| Resume (REQ-215) | holds (`Race_Resume`, `Race_OResume`, `Race_ResumeSch`) | `Race_CF_ResumeNra` |
| Operator definition update (REQ-212, REQ-227) | holds (`Race_Update`, `Race_UpdateSch`, `Race_UpdateSchO`). *(run 9)* Also on a code-defined job with AllowRuntimeOverride that can be orphaned and restored in between, with schedule content (`Race_UpdateSchOrph`, 693,360 distinct, every check incl. `Prop_Refines`) | `Race_CF_Update`, `Race_CF_DefUpdate` |
| REQ-241 update | holds against operator edits, with schedule content (`Race_ReapplySch`); heartbeat transient accepted (`Race_Reapply`, `Race_ReapplyDecl`) | `Race_CF_Reapply`, `Race_CF_DefReapply` |
| Orphan sweep (REQ-205, REQ-207) | holds except the accepted transient (`Race_Orphan`, `Race_OrphDecl`) | `Race_CF_OrphanNra` |
| Restore (REQ-206) | holds except the accepted transient (`Race_Restore`, `Race_RestoreDecl`). *(run 9)* Also against operator edits (AllowRuntimeOverride) and the sweep, with schedule content (`Race_RestoreSchO`, 526,176 distinct, incl. `Inv_NextRunAtFromStoredSchedule`) | `Race_CF_Restore` (a pause lost); `Race_CF_RemoveRestore` (the other direction) |
| Removal (REQ-213) | holds (`Race_Remove`, `Race_ORemove`) | `Race_CF_Remove`, `Race_CF_RemoveRestore` |
| REQ-203 scheduler create (an insert keyed by name) | holds except the accepted transient (`Race_Create`, `Race_CreateDecl`) | — |

**Also checked, not findings** (the questions in the brief):
- *The restore racing other writes* (INV-212 lists "a restore"). A restore reads an orphaned job, and nothing but another restore or an operator's removal (REQ-213) can change an orphan's row: REQ-204 and REQ-241 start from Active or Paused, and so does an operator's edit (REQ-212). So a split restore loses its compare-and-set only to a removal, or to a restore followed by a pause and another orphaning. Both are in `Race_Restore` and `Race_RestoreSchO`. Without the compare-and-set the pause is lost (`Race_CF_Restore`). In the other direction, every write that read the job before it was orphaned and restored loses its compare-and-set, because leaving Orphaned moves nextRunAt: the trigger (`Race_OTrigger`), the pause, the resume, the removal (`Race_OPause`, `Race_OResume`, `Race_ORemove`) and an operator edit (`Race_UpdateSchOrph`). An operator's removal of an orphan that a restore overtakes reads again, finds a code-defined job that is not orphaned, and stops (INV-206). That race is more likely now that the restore always happens, and it is handled. Without the compare-and-set the removal deletes an active code-defined job (`Race_CF_RemoveRestore`).
- *Flip-flop between the sweep and the restore while declarations change.* With a fixed set of running nodes, the sweep needs "no running node declares it" and the restore needs "a running node declares it", so at most one of them applies. A split sweep can still land just after a declaring node started (the accepted transient), and then the restore undoes it. `Liv_ReconcileStops` says the scheduler's reconciliation eventually stops changing the job once the nodes stop changing: no orphaning, deletion, restore, re-creation or definition rewrite, unless an operator keeps removing it. It holds as written in the atomic model (`Liv_Converge`; `Liv_ConvergeDel` for Delete) and with the four heartbeat writes split (`Race_LiveConv`, `Race_LiveConvDel`). While nodes keep changing, the job keeps changing too (`Liv_ReconcileFlip`: `Liv_ReconcileStopsAlways` violated, an 11-state lasso in which a node on v1 and a node on v2 take turns restarting for ever, and each start rewrites the definition, REQ-204). This is what REQ-204's notes accept for a rolling deploy. An orphaning followed by a restore at every redeploy between a release that declares the job and one that does not is the same thing, as REQ-205 and REQ-206 say.
- *SCN-209 (rolled-back removal restores the earlier state).* Both legs are still reachable (`SCN209` 2 states, `SCN209b` 4 states). Leg (b) is now an obligation: from `weekly-report` orphaned and remembering Paused, once the rolled-back release runs for good, the job is eventually Paused again, and in the meantime no occurrence is created on schedule (`SCN209L`, `Liv_Scn209Restored` and `Inv_NoScheduleWhilePaused`, 73,000 distinct). It fails with run 8's REQ-206 (`SCN209LH`). The scenario's step note ("the rolled-back release declares it again") still fits: the scheduler finds the job declared once the rolled-back release runs. In `SCN209LH`'s trace an operator's trigger-now (REQ-226) creates an occurrence for the orphaned job. That is allowed (INV-201's and REQ-226's notes), and SCN-209's "no occurrence" is read as "on schedule".
- *Does REQ-206 now share a trigger with REQ-205, REQ-207 or REQ-241?* `validate` reports only the two run-8 warnings (REQ-205/REQ-207, which are modeled as one action, and REQ-222/223/225/235); REQ-206 is not in either. All four sentences start with "the scheduler finds", but they find different jobs: REQ-206 an orphaned one that a node declares, REQ-205/207 a stored one that no node declares, REQ-241 one that nodes declare with a hash that matches none of them. Read alone, the `when` of REQ-205/207 also fits an orphaned job that no node declares, and REQ-241's fits an orphaned one declared with other code. Their `from: [Active, Paused]` rules both out, and REQ-206 (from Orphaned) takes the code definition anyway, so at most one of them applies to any job (A-15). REQ-203's scheduler branch finds a name that is not stored. Each one is its own action in the model, and their guards do not overlap.
- *Maintenance.* The restore is not a trigger, so INV-210 does not stop it, and INV-210's notes already name REQ-206 among the reconciliation actions that keep their own "from now" rule (A-20).
- *Hosting.* REQ-206 is now a background duty of the scheduler. Hosting REQ-40's list of duties that need the worker names "recurring triggers" and "Unroutable or orphan sweep", but not the recurring reconciliation by name (REQ-203's scheduler branch, REQ-205/207, REQ-206, REQ-241). REQ-241's notes say that the check "runs with the orphan sweep, a worker duty (hosting REQ-40)", and the model assumes all of them need a running worker (A-6). If the owner wants REQ-40's list to be complete, that is an edit in `hosting.json`, not here. It changes no behaviour.

**Not checked, worth a look** (the model cannot see it): as in run 8, REQ-224's start of a waiting occurrence and REQ-237's skipping act on occurrence rows, and INV-212 does not cover them (A-30). A scheduler pass is not timed (no clock), so "corrected at the next pass" and "restored" are checked as "eventually", not within a pass.

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | ambiguity | medium | REQ-206, REQ-204, REQ-212, REQ-241 | REQ-206 always writes the node's code definition when it restores a job, even when that code has the stored hash. So an operator's runtime edit (AllowRuntimeOverride) is lost after an orphaning and a rollback, although REQ-204's notes say such an edit survives deploys that leave the code unchanged. |

---

## F-1 · ambiguity · medium — A restore discards an operator's runtime edit although the code did not change
<!-- finding: ambiguity | REQ-206 definition update | REQ-204,REQ-206,REQ-212 -->

**Requirements involved**
- REQ-206: *When the scheduler finds an orphaned recurring job that a running worker node declares, the system shall return the job to the state it had before it was orphaned, **update the stored definition and definitionHash to match that node's code definition**, and compute nextRunAt from now.* (notes: *"refiner-model 2026-11-06 F-5 (decided 2026-11-06, recommended option): **a job that comes back with changed code** takes the code definition at once."*)
- REQ-204: *When a node with the worker registered starts **and the hash of a code-defined recurring job's code definition differs from the definitionHash** of the stored code-defined job with that name, the system shall update the stored definition and definitionHash to match the code …* (notes: *"code is reapplied only when the code definition itself changed, so **a runtime edit under AllowRuntimeOverride survives restarts and deploys that leave the code unchanged**."*)
- REQ-241: *When the scheduler finds a stored code-defined recurring job that running worker nodes declare **but whose definitionHash matches the code definition of none of them** …* (notes: *"A runtime edit under AllowRuntimeOverride does not change definitionHash, so it survives."*)
- REQ-212: an operator updates a code-defined job marked AllowRuntimeOverride.

**What happens** (TLC, `Recurring.tla`, `Recurring_P_RestoreDropsEdit.cfg`: `ProbeAct_RestoreKeepsRuntimeEdit` violated, 8 states). `nightly-export` is code-defined in release N (and N+1 does not declare it), orphanPolicy Orphan, AllowRuntimeOverride:
1. Node A starts on N, and `nightly-export` is created from N's code, hash h(N) (REQ-203).
2. The operator moves it from 02:00 to 03:00 at runtime (REQ-212). The stored definition is now the edit, and definitionHash is still h(N).
3. A is redeployed on N+1. No running node declares the job, so the sweep orphans it (REQ-205).
4. The deploy is rolled back: node B starts on N.
5. The scheduler finds the orphan declared and restores it (REQ-206): Active again, and **the definition is N's code again, so it runs at 02:00**. The 03:00 edit is gone, although B runs exactly the code whose hash was stored.

Without step 3 the edit survives the same restart and redeploy: REQ-204 and REQ-241 compare hashes, find h(N), and change nothing (`Recurring_P_RuntimeTakenOver` and the REQ-241 cfgs pass with AllowRuntimeOverride). So an operator's override is kept across any deploy except one that orphans the job for a while, and that is exactly the case SCN-209 calls a rolled-back removal.

**Why** Run-1 F-5 was about a job that comes back with *changed* code and keeps the old definition. Its recommended option (mine) wrote the update without the hash condition that REQ-204 has, so it also applies when the code is unchanged. The sentence is clear about what it does. What is unclear is whether it is meant: REQ-206's notes give "comes back with changed code" as the reason, and REQ-204's and REQ-241's notes promise that the edit survives. Severity is medium: the options behave differently, and in the case shown an operator's schedule silently reverts.

**Options**
1. *(recommended)* **Give REQ-206 REQ-204's hash condition.** The restore updates the definition only if the hash of that node's code definition differs from the stored definitionHash. Changed code still takes over at once (run-1 F-5 is kept), and unchanged code keeps a runtime edit, as at a restart. nextRunAt is still computed from now, from whatever definition is then stored.
   - **Checked:** `Recurring_F_RestoreKeepsEditOpt.cfg` (`SpecOpt206`, constant set ORPHO): the probe holds, and so do `Liv_DeclaredConverges`, `Liv_ReconcileStops`, `Liv_DefinitionSettles`, `Prop_StaleOnlyWhenNodeStops` and the six REQ-242 properties (37,800 distinct). Not re-checked in the race model: the restore's write stays an INV-212 compare-and-set, and with this option it writes the same fields or fewer.
2. **Keep the sentence and say it in the notes.** REQ-206's notes would say that a restore always takes the code definition, so a runtime edit is lost when a job was orphaned, even if the code did not change. REQ-204's note would say "survives restarts and deploys that leave the code unchanged, unless the job was orphaned in between". This is cheaper, but the operator gets no signal that the override is gone.
3. **Restore only the state and nextRunAt, and leave the definition to REQ-241** at the next pass, which already compares hashes. This also keeps the edit, but it reopens run-1 F-5's window: for one pass a restored job runs with the old code's schedule. Not recommended.

**Ready to apply (option 1, in `specs/recurring.json`)**
```json
{ "id": "REQ-206", "kind": "transition", "status": "approved",
  "entity": "RecurringJob", "actor": "system", "from": ["Orphaned"], "to": ["Active", "Paused"],
  "ears": {
    "when": "the scheduler finds an orphaned recurring job that a running worker node declares",
    "shall": "return the job to the state it had before it was orphaned, update the stored definition and definitionHash to match that node's code definition if its hash differs from the stored definitionHash, and compute nextRunAt from now" },
  "dependsOn": ["REQ-204"],
  "notes": "<existing notes> refiner-model 2026-11-08 run 9 F-1 (recommended option): the definition is taken only when the code changed, as in REQ-204, so a runtime edit under AllowRuntimeOverride survives a rolled-back removal as it survives a restart. Unconditional, a rollback to the same code reverted the operator's edit." }
```

---

## Accepted (not findings)
- **Run-7 F-2's transients** (INV-212 notes, REQ-207 notes, REQ-203 notes; option 2 chosen). The heartbeats are not in the compare-and-set, so:
  - the orphan sweep can remove or orphan a job that a node which just started declares (`Race_OrphDecl`: `Prop_CodeJobLeavesOnlyUndeclared` violated, 7 states). REQ-203 creates it again at the scheduler's next pass (Delete), or REQ-206 restores it (Orphan). Both are now obligations (`Race_LiveConv`, `Race_LiveConvDel`);
  - a restore can take the code definition of a node that stopped before the write (`Race_RestoreDecl`: `Prop_RestoreOnlyDeclared` violated, 9 states). In this trace no other declaring node runs, so the restored job is active with no node declaring it, and the next pass orphans it again (REQ-205), remembering the state it was restored to. REQ-241 is what heals it when another declaring node on other code still runs. INV-212's notes give only the REQ-241 example, but their general clause, "one that changed before the write is corrected at the scheduler's next pass", covers both, and `Liv_DeclaredConverges` and `Liv_ReconcileStops` hold;
  - REQ-241 can do the same (`Race_ReapplyDecl`: `Prop_StaleOnlyWhenNodeStops` violated, 8 states). The next REQ-241 pass updates it again. It can also rewrite a definition that a just-started node's code already matched (`Race_Reapply`, see run 8). The result is a settled state, and the record is true.
  - *(new in the notes, run 9)* REQ-203's scheduler create can land after the node it took the definition from has stopped (`Race_CreateDecl`: `Prop_CodeJobCreatedOnlyDeclared` violated, 10 states). INV-212's notes now say so: "the next pass orphans, removes or updates it as the declarations then say". Every other check holds with the create split (`Race_Create`).

  These four properties stay in the model as documentation, expected violated.
- **The re-created job loses an operator's pause, and instants while it was not stored are not missed** (REQ-203 notes, REQ-234).
- **Instants that fall due while a job is orphaned are dropped without a record** (REQ-206 notes, run-5 F-1). With the restore now obliged, this window lasts until the next pass after a declaring node runs.
- **A trigger-now while paused or orphaned** creates an occurrence (INV-201 and REQ-226 notes), seen in `SCN209LH`'s trace.
- **Run-5 F-3: a REQ-242 record that says "is waiting" is a snapshot** (REQ-242 notes; `Recurring_P_RecordedWaiterSkipped.cfg`, 6 states, action probe violated as expected).
- **Run-4 F-2's trace, now recorded correctly**: a RunOnce catch-up skipped by the overlap policy (`Recurring_P_CatchUpSkipped.cfg`, 5 states). The record says `Skipped`.
- **REQ-240's notes, scoped to Skip and Queue** (run-4 F-3): two Unroutable jobs of one recurring job under Allow (`Recurring_P_OneUnroutable.cfg`, 6 states). `Note240_OneUnroutableSkipQueue` holds for Skip and Queue.
- **Run-3 probes** (REQ-225 start meeting an Unroutable job; REQ-240 cancelling an Unroutable trigger-now run) and the **REQ-241 window** (`Recurring_P_StaleDefinition2.cfg`), unchanged, still reachable as documented.
- **REQ-238 (info)**: an abandoned or lease-lost handler still runs beside the next job (`Recurring_F_RunningHandlers.cfg`, 7 states).
- **A writer can lose for ever** if another write lands in every window between its read and its write (`Race_LiveStarve`). INV-212 sets no bound on retries, and the model cannot judge how likely this is (no clock).
- **The definition is rewritten back and forth while nodes keep being redeployed** (REQ-204 notes; `Liv_ReconcileFlip`). It stops when they stop (`Liv_ReconcileStops`).

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. A-1 to A-34 are from runs 1 to 8, and changes are marked.
| # | Assumption | Affects |
|---|---|---|
| A-1 | No clock. Each job keeps a count of due instants passed since nextRunAt was set (0, 1, "2 or more"), and time passing is a nondeterministic step. "nextRunAt computed from now" resets the count to 0. | REQ-215, REQ-216, REQ-227, REQ-204, REQ-206, REQ-241, INV-210, REQ-242 |
| A-2 | In `Recurring.tla` each write and the read that decides it are one atomic step, so INV-200, INV-203 and SCN-200 hold by construction there. `RecurringRace.tla` drops this for the writes INV-212 names and for REQ-203's scheduler create, except REQ-204 at node start (A-30). | INV-203, SCN-200, REQ-242, INV-212 |
| A-3 | The newest due instant is late or on time by nondeterministic choice. With two or more instants due, the older ones are always missed, which assumes the schedule interval exceeds MisfireThreshold. | REQ-217–REQ-219, REQ-234, INV-207, REQ-242 |
| A-4 | RunAll(max) is modeled with max = 1, which makes it indistinguishable from RunOnce. So REQ-242's "whether each" is checked for one occurrence. | REQ-219, REQ-242 |
| A-5 | A trigger creates at most one occurrence. | REQ-216–REQ-219 |
| A-6 | *(changed)* Every modeled node has the worker registered. A node declares exactly what its release declares, and "running" means up. What nodes publish in their heartbeat (declared names and each name's definition hash) is known to the scheduler at once; heartbeat expiry and a late first heartbeat are not modeled, but a split heartbeat write reads them before a node starts or stops, which has the same effect. The scheduler (triggers, orphan sweep, REQ-241, REQ-203's scheduler branch and, since run 9, REQ-206's restore) and jobs REQ-125's handler registration need some running worker (hosting REQ-40). For the restore that is implied: a running node that declares the job is a running worker. | REQ-203–REQ-207, REQ-216, REQ-241 |
| A-7 | REQ-224 is a separate system step after the earlier job finishes. | REQ-224 |
| A-8 | At node start, REQ-203 and REQ-204 (and REQ-242's schedule-change record) are applied together for every declared name. The store is keyed by name, so INV-200 and SCN-207 hold by construction. Creating a job, by either branch of REQ-203 or by REQ-208, is an insert that fails if the name exists. | REQ-203, REQ-204, REQ-208, INV-200, INV-211, SCN-207, REQ-242, INV-212 |
| A-9 | Overlap, misfire and orphan policies are fixed per job for a whole run. | REQ-205, REQ-207, REQ-212, REQ-221–REQ-225 |
| A-10 | jobs.Job is reduced to Enqueued / Processing / Failed / Succeeded / DeadLettered / Cancelled / Unroutable plus a "handler still executing" flag (lease lost, jobs REQ-132; abandoned on timeout, jobs REQ-138/REQ-186). jobs REQ-125 (Unroutable → Enqueued) can happen whenever a worker runs. | INV-204, REQ-221–REQ-225, REQ-239, REQ-240 |
| A-11 | Occurrences whose job is final in the jobs module (not Unroutable) free their slot (modeling artefact). | all |
| A-12 | INV-204 is checked as written (`Inv_NoOverlapProcessing`, the Processing state). `Inv_NoOverlapRunning` (any executing handler) is kept only to show the window REQ-238 accepts. | INV-204, REQ-238 |
| A-13 | definitionHash is the hash of the code definition last applied. A runtime edit under AllowRuntimeOverride changes the stored definition but not the hash, so REQ-241 never fires because of a runtime edit. In `Recurring.tla` and in race cfgs with `SchedOn = FALSE` the definition has no schedule content: "the schedule changed" is a nondeterministic choice. The `…Sch` race cfgs give it content (A-32). A runtime edit is one value, "edited" (F-1's probe). | REQ-204, REQ-206, REQ-212, REQ-241, REQ-227 |
| A-14 | Configuration-defined jobs are not modeled (INV-209 and REQ-232 are `may`), so REQ-236 is checked for code-defined names only. | INV-209, REQ-232, REQ-236 |
| A-15 | *(changed)* The same-trigger warnings from `validate` (REQ-222/REQ-223/REQ-225/REQ-235 with REQ-221; REQ-205/REQ-207) are each one action, with complementary and exhaustive guards. REQ-206, REQ-241 and REQ-205/207 also start with "the scheduler finds", but their `from` states and declaration conditions are disjoint, so each is its own action. REQ-242 is an `invariant` with a `when` clause; it is modeled as one more consequence of the trigger, schedule-change, pause, orphan and removal events, not as a state predicate. | REQ-205–REQ-207, REQ-241, REQ-242 |
| A-16 | REQ-236's and REQ-210's "fail the host's start" is abstracted as the node staying down. The hosting module owns the node's states. | REQ-236 |
| A-17 | One switch remains: `RerouteOn` explores jobs REQ-125 only in `MainR`, `F_RerouteOverlap`, `F_RerouteQueue` and SCN-215, so the run-1 fixes and the Unroutable rules are judged separately. The race cfgs have it off. | INV-204, REQ-240 |
| A-18 | REQ-240 is applied to every start: REQ-221, REQ-224 and REQ-225 (Allow and CancelPrevious). "Earlier" means created before, in creation order. Confirmed by the owner (run-3 F-1). | REQ-240, REQ-225 |
| A-19 | REQ-240's start and cancel are one atomic step, so jobs REQ-125 cannot return the job to Enqueued between them. | REQ-240, INV-204 |
| A-20 | *(changed)* REQ-241 is a reconciliation step, not a scheduled trigger, so INV-210 does not stop it during maintenance. Nor does it stop REQ-203's scheduler create or REQ-206's restore (INV-210's notes name REQ-206). | REQ-241, REQ-203, REQ-206, INV-210 |
| A-21 | REQ-242's record is abstracted to, per name, a count of records (0, 1, "2 or more"), how the latest one says the instants were handled (`Started` / `Waiting` / `Skipped` naming the occurrence created in that write, `Misfire`, `Schedule`, `Pause`, `Orphan` or `Removed`), and that occurrence. "First, last and how many" are not modeled. The count is never reset: the model has no retention, and a record outlives a removed or orphaned job, kept per name. At "2 or more" a further record of the same kind is invisible, so the "exactly one record" checks are weak there. | REQ-242 |
| A-22 | `missRec` is written only by `TriggerWrite`, the schedule-change writes, `PauseWrite`, `OrphanWrite` and `RemoveWrite` (atomic or split), and read by no guard or update, so states that differ only in it have the same futures. The five 3-slot Queue cfgs, which check nothing about REQ-242, use `VIEW ViewNoRec`. Every other cfg explores `missRec` in full. | checks in the Queue cfgs |
| A-23 | "Missed" for a trigger is REQ-234's first clause: an instant more than MisfireThreshold late. A trigger with only the newest instant late records a miss; with only an on-time newest instant it records nothing. | REQ-242, REQ-234 |
| A-24 | Schemas are not modeled. The initial store holds no recurring job, which is what REQ-236 says a store without a Bellhop schema holds. | REQ-236 |
| A-25 | REQ-234's second clause: while a job is Active, the count of A-1 is exactly the instants that fell due while it was active (every way into Active resets it), so any step other than a trigger that moves nextRunAt from now, or takes the job out of Active, while the count is at least 1, passes over missed instants (`HasMissed`). | REQ-234, REQ-242 |
| A-26 | In `RecurringRace.tla` a split write is a read, which checks the atomic action's guard and keeps what the write will use, and a later write. The read keeps: for the trigger under read-judging, whether the newest instant is late; for a restore, REQ-241 or a create, the code definition of the node it chose; for an update, the schedule it sets and whether that changes the schedule; and the schedule it read. With INV-212 the write compares the state, nextRunAt, definition and, for a trigger, maintenance, and judges `HasMissed`, the trigger's due count and lateness at the write. An orphaning records the state it read, which is the current one when the state is compared. A write whose row is gone does nothing, even unconditionally (an update that finds no row). A create whose name is stored by then fails and reads again. | INV-212, REQ-203 |
| A-27 | The compare-and-set is modeled by three ghosts per job: the state changed, nextRunAt moved, and the definition changed since the read. nextRunAt "moves" when the due count goes down; when the job enters Active, leaves Orphaned or is removed; or, with schedule content, when it is computed from another schedule. The definition "changes" when its content, hash, origin or schedule changes. Without schedule content, a schedule change while the count is already 0 is not seen, and nor is an edit of a definition that is already "edited". With state, nextRunAt and definition all compared, any ghost dooms the write, so the three are kept as one. | INV-212 |
| A-28 | Each cfg splits one write, except the liveness cfgs, and at most one split write per job is in flight. Every other write, including another copy of the same one, is atomic and can land in between. A lost write and its reread are one step. Two split writers at once are argued, not checked: with INV-212 a write that lands read what it lands on, so it is the same as an atomic step at that moment. | INV-212 |
| A-29 | The scheduler's writes (trigger, orphan sweep, restore, REQ-241, REQ-203's create) run on a node. When a node stops, a write in flight may be lost, and when no node runs it is lost. Operator writes are never lost. | INV-212, liveness |
| A-30 | Not split: REQ-204 at node start (one step for every declared name, A-8; its write is the same as REQ-241's, which is split), REQ-203 at node start and REQ-208 (inserts keyed by name), REQ-226's trigger-now (INV-212's notes), and the occurrence writes of REQ-224 and REQ-237. The skipping of REQ-237 inside a pause, orphaning or removal applies to the occurrences still waiting at the write. | REQ-203, REQ-204, REQ-224, REQ-226, REQ-237 |
| A-31 | *(changed)* For `Liv_WriterSettles` only the writer's own step is weakly fair (an in-flight call is the system's to finish). For `Liv_DeclaredConverges`, `Liv_ReconcileStops` and `Liv_Scn209Restored` the scheduler's `actor: system` steps are weakly fair as well: REQ-203's scheduler branch, the orphan sweep, REQ-241 and, since run 9, REQ-206's restore. Run 8's reading (restore not fair) is kept only as the counterfactual specs `SpecCF_RestoreHost`, `SpecRC_CF_RestoreHost` and `SpecSCN209bH`. | INV-212, REQ-203, REQ-206 |
| A-32 | Schedule content (`SchedOn = TRUE`): two schedules, s1 and s2. Release v1's and v3's code use s1, and release v2's code uses s1 or s2, chosen per behaviour, so that two declaring releases can have the same or different schedules. A runtime job is added with s1, and an operator update sets either. A definition write "changes the schedule" when the schedule it sets differs from the stored one, judged against what its read saw (as written the two agree, because a write that lands saw the stored definition). | REQ-204, REQ-212, REQ-227, REQ-241, INV-212 |
| A-33 | `Liv_DeclaredConverges`: a declared code-defined name is eventually stored, Active or Paused, with the code definition of a declaring node, and stays so. A runtime job with that name counts as settled, because REQ-203 does not apply to it and REQ-236 handles the collision. It is excused if the running nodes keep changing for ever, or an operator keeps removing the job for ever (REQ-213). | REQ-203, REQ-206, REQ-241, INV-212 |
| A-34 | An occurrence belongs to its recurring job by name, so occurrences of a removed job still count for overlap against a job created again with that name. | REQ-221–REQ-225, INV-204 |
| A-35 | *(new)* `Liv_ReconcileStops` looks at what reconciliation changes: whether the job is stored and not orphaned, its origin and its definitionHash. An operator's pause, resume or edit is not reconciliation and is not looked at. It is excused as A-33 is. `Liv_Scn209Restored` reads SCN-209's "rolled back" as "a node on the release that declares the job runs from some point on for ever", and is satisfied if an operator removed the orphan first (REQ-213, not part of the scenario). | REQ-203–REQ-207, REQ-241, SCN-209 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-201–REQ-208, REQ-211–REQ-227, REQ-233–REQ-237, REQ-239–REQ-242, INV-200, INV-201, INV-203, INV-204, INV-206, INV-207, INV-210, INV-211, INV-212, SCN-200–SCN-217 | REQ-200, REQ-228, REQ-229, REQ-230, INV-202, INV-208 (need a real clock: time zones, DST, validity window) · REQ-209, REQ-210 (schedule/time-zone validity not representable) · INV-205 (no exceptions or lock waits in the model) · REQ-231 (bookkeeping, nothing depends on it) · REQ-232, INV-209 (strength `may`) · REQ-238 (`info`; shown by `Inv_NoOverlapRunning`) |

Some modeled items are not judged:
- In `Recurring.tla`, INV-200, INV-203, SCN-200 and SCN-207 hold by construction (A-2, A-8). In `RecurringRace.tla`, INV-203 is checked (`Prop_OneOccurrencePerInstant`), and it holds because nextRunAt is compared: it fails without that (`Race_CF_TriggerSt`).
- INV-212 is checked for one split write at a time (A-28). Schedule content is checked in the `…Sch…` cfgs only (A-32).
- REQ-242's retention needs a clock. Its "first, last and how many" are not modeled (A-21).
- REQ-219 and REQ-242's "whether each" are modeled only with max = 1 (A-4).
- REQ-236 is checked for code-defined names only (A-14).
- REQ-241's settling and REQ-203's and REQ-206's healing are checked as "eventually", not "within a pass". A writer that loses is checked to settle unless interfered with for ever, not within a number of retries.
- The cancel reason Superseded (REQ-240) is not modeled.

## How to reproduce
From `specs/model/recurring`: `sh gen_cfgs.sh` regenerates every cfg except the scenario cfgs (`SCN*`, including the new `SCN209L` / `SCN209LH`, and the six `RSCN*`), and `sh run_all.sh` reruns every check below. Each check is one `run_tlc.py <module> --config <cfg> --stop-at-first` call, where the module is `Recurring.tla`, or `RecurringRace.tla` for the `Race_*` and `RSCN*` cfgs. Scenario, race and `RSCN*` cfgs add `--no-deadlock`. `run_all.sh <name>` runs one check. `TLC_WORKERS` (default 4) and `TLC_TIMEOUT` (default 400 s) set the workers and the per-run limit. A TLC still running after the limit is killed, because `run_tlc.py`'s timeout does not stop it on Windows. The `run*.json`/`run*.md` outputs and `run_all.log` are gitignored.

- TLC 2.19 throws "unexpected exception" when `-continue` has to rebuild many traces, so every check uses `--stop-at-first`. The run that produced this report grepped every output for that message and found none.
- This run used `TLC_WORKERS=4 TLC_TIMEOUT=400`, with another module being model-checked on the same machine, so the times are not comparable with run 8. No check hit the limit; the largest, `Race_UpdateSch`, took 356 s.
- Don't start a second TLC run in this folder while one is running: TLC's `-cleanup` removes the shared `states/` folder, and the other run fails with "when reading the disk". The fourteen largest as-written race checks (`Race_Pause` … `Race_ORemove` in the INV-212 rows below) ran from a scratch copy of this folder, with identical `.tla` and `.cfg` files, at the same time as the rest. The copy was then deleted, and its outputs copied here.
- One run in the main batch (`Main`) failed to parse because `Sequences.tla`, which TLC unpacks into the temp folder, was missing for a moment (the other module's runs share that folder). It was rerun alone and passed, as listed.
- After the batch, a comment in `Recurring.tla` (above `Liv_ReconcileStopsAlways`) and the header comment of `Recurring_Liv_ReconcileFlip.cfg` were reworded, and that check was rerun. Nothing else changed.

| Check | Config | Result |
|---|---|---|
| Main: INV-201, INV-210 (both), REQ-233, SCN-200/202, REQ-237, REQ-239 skip rule, INV-204, REQ-242 (six properties) (1 job, 2 slots, Skip/Queue × RunOnce/Skip) | `Recurring.cfg` | passed, 1,735,656 distinct, 25 s |
| Main with jobs REQ-125 | `Recurring_MainR.cfg` | passed, 1,735,656 distinct, 31 s |
| **REQ-242** under RunOnce, Skip and RunAll, plus the main checks | `Recurring_Misfire.cfg` | passed, 2,886,396 distinct, 51 s |
| Definitions: REQ-211/SCN-205, INV-206/SCN-212, SCN-208, INV-211/SCN-214, REQ-236, REQ-237, REQ-242 at node start, orphaning and removal (2 jobs, 2 nodes, both orphan policies), with REQ-203's scheduler branch | `Recurring_Defs.cfg` | passed, 2,586,248 distinct, 95 s |
| Overlap, all four policies, 2 slots: REQ-233, INV-204, REQ-239 skip rule | `Recurring_OverlapAll.cfg` | passed, 2,395,024 distinct, 22 s |
| Overlap Queue(1), 3 slots: REQ-233, REQ-237, REQ-239 skip rule | `Recurring_OverlapQueue.cfg` | passed, 7,439,116 distinct, 112 s |
| Overlap Queue(2), 3 slots: REQ-233, REQ-239 skip rule | `Recurring_OverlapQueue2.cfg` | passed, 7,191,148 distinct, 104 s |
| Run-1 F-1: INV-204, Queue(1), 3 slots | `Recurring_F_WaitingRace.cfg` | passed, 7,439,116 distinct, 83 s |
| Run-1 F-2: probe + INV-204, Queue(2), 3 slots | `Recurring_P_QueueTwoWaiters.cfg` | passed, 7,191,148 distinct, 93 s |
| Run-1 F-5: probe, one node, 3 releases | `Recurring_P_StaleDefinition.cfg` | passed, 151,500 distinct, 3 s |
| Run-1 F-6: probe | `Recurring_P_RuntimeTakenOver.cfg` | passed, 151,500 distinct, 3 s |
| Run-1 F-7: REQ-239 skip rule | `Recurring_P_UnroutableBlocks.cfg` | passed, 2,395,024 distinct, 21 s |
| Run-2 F-1: INV-204, skip rule and the REQ-240 note (Skip/Queue) with jobs REQ-125 and REQ-240, all four policies | `Recurring_F_RerouteOverlap.cfg` | passed, 2,395,024 distinct, 18 s |
| Run-2 F-1: INV-204, REQ-233, REQ-237, skip rule and the REQ-240 note with jobs REQ-125 and REQ-240, Queue(1), 3 slots | `Recurring_F_RerouteQueue.cfg` | passed, 7,439,116 distinct, 104 s |
| Run-2 F-2: REQ-241 settling (liveness + action property) and REQ-242, two nodes, v1/v2 | `Recurring_Liv_Settles.cfg` | passed, 94,146 distinct, 9 s |
| Run-2 F-2: same, two nodes, three releases, AllowRuntimeOverride | `Recurring_Liv_Settles3.cfg` | passed, 468,546 distinct, 46 s |
| Run-2 F-2 window (probe; REQ-241 closes it one step later) | `Recurring_P_StaleDefinition2.cfg` | probe violated, 4 states, as expected |
| Run-3 F-1: a REQ-225 start can meet an Unroutable job (probe) | `Recurring_P_Req225Unroutable.cfg` | probe violated, 5 states; covered by REQ-240 on purpose |
| Run-3 F-2: a trigger-now Unroutable job superseded by a scheduled start (action probe) | `Recurring_P_TriggerNowSuperseded.cfg` | action probe violated, 6 states; accepted (`run_tlc.py` labels an action-property violation "error") |
| Run-4 F-1 regression: overdue instants dropped by a schedule change are recorded | `Recurring_F_OverdueRecorded.cfg` | passed, 151,500 distinct, 3 s |
| Run-4 F-2: a RunOnce catch-up skipped by the overlap policy (action probe; the record says `Skipped`) | `Recurring_P_CatchUpSkipped.cfg` | action probe violated, 5 states, as expected |
| Run-4 F-3: two Unroutable jobs of one recurring job (probe, all four policies) | `Recurring_P_OneUnroutable.cfg` | probe violated, 6 states (Allow); the notes say so |
| Run-5 F-1 regression: missed instants recorded at a pause or an operator removal | `Recurring_F_OverduePaused.cfg` | passed, 1,735,656 distinct, 20 s |
| Run-5 F-1 regression: ... and at an orphaning or a delete by the orphan sweep | `Recurring_F_OverdueOrphaned.cfg` | passed, 199,146 distinct, 3 s |
| Run-5 F-2 regression: a just-passed instant dropped by a schedule change is recorded | `Recurring_F_PassedInstant.cfg` | passed, 1,735,656 distinct, 14 s |
| Run-5 F-3 (accepted): a record saying "waiting", then REQ-237 skips that occurrence (action probe) | `Recurring_P_RecordedWaiterSkipped.cfg` | action probe violated, 6 states, as expected |
| REQ-238 window (info) | `Recurring_F_RunningHandlers.cfg` | `Inv_NoOverlapRunning` violated, 7 states, as REQ-238 accepts |
| SCN-201, 203, 204, 206, 209 (legs `SCN209`, `SCN209b`), 210, 211, 213, 215 | `Recurring_SCNnnn.cfg` | every trap violated as expected (2–5 states): all reachable |
| **SCN-209 leg (b) as an obligation** (run 9): Paused again once the rolled-back release runs, no occurrence on schedule meanwhile | `Recurring_SCN209L.cfg` | passed, 73,000 distinct, 2 s |
| ... with run 8's REQ-206 (counterfactual) | `Recurring_SCN209LH.cfg` | `Liv_Scn209Restored` violated, 8-state lasso, as expected |
| **Run-8 F-1, as written**: a declared code-defined job is eventually stored, not orphaned, with a declaring node's code; and the reconciliation stops once the nodes stop changing | `Recurring_Liv_Converge.cfg` | passed, 30,854 distinct, 3 s |
| ... with run 8's REQ-206 (counterfactual, the run-8 F-1 trace) | `Recurring_Liv_CF_ConvergeHost.cfg` | `Liv_DeclaredConverges` violated, 10-state lasso, as expected |
| The same with orphanPolicy Delete only | `Recurring_Liv_ConvergeDel.cfg` | passed, 7,742 distinct, 2 s |
| The reconciliation without the escape for nodes that keep changing | `Recurring_Liv_ReconcileFlip.cfg` | `Liv_ReconcileStopsAlways` violated, 11-state lasso, as expected |
| **F-1**: a restore with unchanged code keeps a runtime edit (action probe) | `Recurring_P_RestoreDropsEdit.cfg` | action probe violated, 8 states (the F-1 example) |
| **F-1 option 1** (`SpecOpt206`): probe, `Liv_DeclaredConverges`, `Liv_ReconcileStops`, `Liv_DefinitionSettles`, `Prop_StaleOnlyWhenNodeStops`, REQ-242 | `Recurring_F_RestoreKeepsEditOpt.cfg` | passed, 37,800 distinct, 4 s |
| **INV-212** (`RecurringRace.tla`, 1 job, 2 slots, Skip/Queue × RunOnce/Skip): trigger / pause / resume / operator update / removal split, every check incl. `Prop_Refines` | `Recurring_Race_Trigger.cfg`, `…_Pause`, `…_Resume`, `…_Update`, `…_Remove` | passed: 2,885,304 / 4,349,520 / 4,327,920 / 5,229,816 / 3,482,736 distinct, 120–201 s |
| **INV-212 with schedule content**: operator update / resume / trigger split, every check incl. `Prop_Refines` and `Inv_NextRunAtFromStoredSchedule` | `Recurring_Race_UpdateSch.cfg`, `…_ResumeSch`, `…_TriggerSch` | passed: 8,741,112 / 6,083,568 / 2,891,016 distinct, 101–356 s |
| **INV-212 with schedule content**, two nodes on v1/v2, AllowRuntimeOverride: REQ-241 split against operator edits; an operator edit of a code-defined job split | `Recurring_Race_ReapplySch.cfg`, `…_UpdateSchO` | passed: 3,230,796 / 3,942,204 distinct, 134 / 319 s |
| **INV-212**, two nodes, three releases, both orphan policies: pause / resume / trigger (run 9) / removal split, every check incl. `Prop_Refines` and the heartbeat properties | `Recurring_Race_OPause.cfg`, `…_OResume`, `…_OTrigger`, `…_ORemove` | passed: 3,142,944 / 3,142,944 / 2,548,546 / 3,411,996 distinct, 157–214 s |
| **INV-212 with schedule content**, two nodes, three releases, AllowRuntimeOverride, no occurrence slots (run 9): restore split (every check except `Prop_Refines` and the accepted heartbeat property); operator edit split (every check incl. `Prop_Refines`) | `Recurring_Race_RestoreSchO.cfg`, `…_UpdateSchOrph` | passed: 526,176 / 693,360 distinct, 17 / 45 s |
| **Heartbeat writes split as written** (sweep / restore / REQ-241 / REQ-203's create): every check except `Prop_Refines` and the accepted heartbeat property | `Recurring_Race_Orphan.cfg`, `…_Restore`, `…_Reapply`, `…_Create` | passed: 2,683,800 / 3,366,846 / 6,373,746 / 2,870,046 distinct, 99–223 s |
| **Accepted transients** (INV-212 notes) | `Recurring_Race_OrphDecl.cfg`, `…_RestoreDecl`, `…_ReapplyDecl`, `…_CreateDecl` | violated as expected: 7 / 9 / 8 / 10 states |
| INV-212's reread: a writer that loses acts or finds nothing to do, unless interfered with for ever (liveness) | `Recurring_Race_Live.cfg`, `…_LiveOrph` | passed, 55,692 / 36,750 distinct, 3 s |
| ... without the escape clause (accepted) | `Recurring_Race_LiveStarve.cfg` | `Liv_WriterSettlesAlways` violated (19-state lasso), as expected |
| **Convergence and settling with the four heartbeat writes split, as written** (REQ-206 fair) / orphanPolicy Delete only | `Recurring_Race_LiveConv.cfg`, `…_LiveConvDel` | passed: 272,096 distinct, 126 s / 63,602 distinct, 33 s |
| ... with run 8's REQ-206 (counterfactual) | `Recurring_Race_CF_LiveConvHost.cfg` | `Liv_DeclaredConverges` violated, 7 states ending in stuttering, as expected |
| Counterfactuals, one per part of INV-212 (table *INV-212 per write*) | the other 15 `Recurring_Race_CF_*.cfg` | each violated as expected, 5–12 states |
| **SCN-216**: along its own steps (leg a) and to its end | `Recurring_RSCN216a.cfg`, `…_RSCN216` | trap violated, 4 and 5 states: reachable |
| SCN-216 with the run-6 unconditional pause | `Recurring_RSCN216u.cfg` | passed, 516,664 distinct: impossible, as run-6 F-1 said |
| **SCN-217** (impossibleAt 2) | `Recurring_RSCN217.cfg` | passed, 2,189,264 distinct, 34 s |
| SCN-217 step 1 reachable; SCN-217 with a compare-and-set without the state | `Recurring_RSCN217a.cfg`, `…_RSCN217n` | trap violated, 2 states; `Scn217_TriggerLosesToPause` violated, 3 states |

Deadlock checking is on in every run of `Recurring.tla` except the scenario runs, and none was found. Probes (`Probe_…`, `ProbeAct_…`) and `Note240_…` are modeling aids, not requirements. The `Race_CF_*`, `Liv_CF_*` cfgs, `SCN209LH` and `RSCN216u` / `RSCN217n` check readings that the requirements as written rule out, to show that each part of them does something. The `Race_*Decl` cfgs show the transients that INV-212's notes accept. `F_RestoreKeepsEditOpt` checks F-1's option 1, not the requirements as written.

## Next
Decide F-1. Option 1 adds REQ-204's hash condition to REQ-206's definition update. Option 2 keeps the behaviour and says it in REQ-206's and REQ-204's notes. Nothing else is open: run-8 F-1 is resolved, the restore is obliged in the plain rollback and in the race, and the reconciliation settles once the nodes stop changing. Apply changes with `refiner-requirements`, then run `refiner-model` again.
