# Findings: Bellhop recurring jobs

<!-- refiner-findings v1 | module: recurring | specHash: a564d3a8e0016830d6db134c4eff9f68e704abf92c5d5a94fd299dbe0b69a6ba | run: 2026-11-08 (run 6) | previous: specs/model/recurring/previous.findings.md (run 5, specHash 90327ae0b99b) -->

**Run:** 2026-11-08, run 6 · **Requirements file:** `specs/recurring.json` (specHash `a564d3a8e001`) · **Model:** `specs/model/recurring/Recurring.tla`, plus `RecurringRace.tla` (new, for F-1) · **TLC:** 2.19. Every check ran alone with `--stop-at-first --workers 2` and finished with no TLC exception and no timeout: 39 cfgs, up to 9,357,168 distinct states, at most 233 s each. See [How to reproduce](#how-to-reproduce).
**Result:** 1 finding: 0 contradictions · 0 gaps · 0 unprovable · 1 ambiguity · 0 modeling notes. All three run-5 findings are resolved: F-1 and F-2 by the new sentences, which hold as written, and F-3 by REQ-242's notes. The new finding is about concurrency, not wording. The pause, orphan and removal writes now decide a record from what they read, and nothing says those writes are conditional, so a trigger that lands in between can make a pause record an instant that ran on time.

The model has no clock. It cannot judge anything that depends on real amounts of time: DST, time zones, validity windows, the 60 s misfire threshold as a number, or how long REQ-242's record is kept. See *Coverage*.

## Changes since last run
| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | gap · ProbeAct_OverduePausedRecorded · REQ-205,REQ-206,REQ-214,REQ-215,REQ-242 |
| F-2 | resolved | ambiguity · ProbeAct_PassedInstantRunsOrIsRecorded · REQ-227,REQ-234,REQ-242 |
| F-3 | resolved | ambiguity · ProbeAct_RecordedWaiterNeverSkipped · REQ-223,REQ-237,REQ-242 |
| F-1 | new | ambiguity · Prop_RecordOnlyUnhandledInstants · REQ-205,REQ-213,REQ-214,REQ-216,REQ-242 |

3 resolved, 1 new, 0 still open

(Table from `findings_delta.py`; the "resolved" rows use run 5's numbers.) What changed in the requirements (handoff `specs/model/recurring/handoff.json`, base 55ee2c4, resolution commit 47a87f4):
- **REQ-234** (assumption): an instant is missed when the trigger runs more than MisfireThreshold after it, *or*, for an instant that fell due while the job was active, when no trigger ran for it before nextRunAt was moved past it or the job stopped being active, however recently it fell due.
- **REQ-242**: it also fires when an active job is paused (REQ-214), orphaned (REQ-205) or removed (REQ-207, REQ-213) while it has missed instants. The record then says the pause, orphaning or removal dropped them, in the write that does so. `dependsOn` gained REQ-234, REQ-214, REQ-205, REQ-207 and REQ-213, and `mentions` gained Paused and Orphaned.
- Impacted, re-checked: REQ-217 and INV-207.
- Annotation only (no hash change): notes of REQ-206, REQ-215 and REQ-227, and integrations REQ-403. The glossary entry MisfireThreshold, which is not hashed, now says the same as REQ-234. It is used only by REQ-234's sentence, and checked here by hand: they agree.

Model changes:
- **REQ-234 and REQ-242 regenerated.** `HasMissed(r)` is "active with at least one instant passed since nextRunAt was set" (A-25, rewritten). Every way into Active resets that count, so it counts exactly the instants that fell due while the job was active. The schedule-change steps record whenever `HasMissed` holds, and the nondeterministic `late` choice of run 5 is gone. `Pause`, `Orphan` (both policies) and `OperatorRemove` now write the record (`Pause`, `Orphan`, `Removed`) in the same step. They had left `missRec` unchanged.
- **Properties.** `Prop_MissRecordOnlyByMove`, `Prop_MissedMoveRecordsOnce` and `Prop_RecordSaysOutcome` now cover the new paths. `Prop_NoInstantRecordedTwice` is new. The run-5 F-1 and F-2 probes are now regression checks that must hold: `Prop_LeaveRecordsMissed` (was `ProbeAct_OverduePausedRecorded` and `ProbeAct_OverdueOrphanedRecorded`) and `Prop_PassedInstantRunsOrIsRecorded` (was `ProbeAct_…`). All six run in Main, MainR, Misfire, Defs, both REQ-241 settling cfgs and the run-4 and run-5 regression cfgs.
- **cfgs.** `Recurring_P_OverduePaused`, `…_P_OverdueOrphaned` and `…_P_PassedInstantDropped` became `Recurring_F_OverduePaused`, `…_F_OverdueOrphaned` (now with both orphan policies, constant set `PROBEOD`) and `…_F_PassedInstant`. `Recurring_P_RecordedWaiterSkipped` stays as documentation of the accepted run-5 F-3.
- **New `RecurringRace.tla`.** It extends `Recurring`, keeps every behaviour, and adds a pause split into its read and its write (F-1). There are two cfgs: `Recurring_Race_Pause` (the write is unconditional) and `…_Race_PauseCAS` (F-1 option 1).

Every other action is byte-for-byte as in run 5. Every check was rerun.

How each run-5 finding was re-checked:

| Run-5 finding | Requirement change | Evidence in run 6 |
|---|---|---|
| F-1: instants missed while active, then paused or orphaned, leave no record | REQ-242 also fires on pause, orphaning and removal of an active job with missed instants | `Prop_LeaveRecordsMissed` holds on `Recurring_F_OverduePaused.cfg` (the run-5 pause trace, plus operator removal; 1,735,656 distinct), `…_F_OverdueOrphaned.cfg` (the run-5 outage-then-deploy trace, both orphan policies; 199,146) and `Recurring_Defs.cfg` (2 jobs, 2 nodes; 2,586,248). Vacuity: a `Pause`, `Orphan` and `Removed` record (by REQ-213 and by REQ-207) are each reachable in 4 to 6 steps. |
| F-2: an instant passed but not yet triggered, dropped by a schedule change with no record | REQ-234 makes it missed; REQ-242 records it | `Prop_PassedInstantRunsOrIsRecorded` holds on `Recurring_F_PassedInstant.cfg` (1,735,656) and every main cfg. Vacuity: the exact run-5 shape (only the newest instant passed, then an operator schedule change) is reachable, and so is a pause with only the newest instant passed. Both now record. |
| F-3: a record saying "is waiting" goes stale | REQ-242's notes: the record is a snapshot of its write | The run-5 trace is still reachable (`Recurring_P_RecordedWaiterSkipped.cfg`, 6 states), as the notes now accept. Listed under *Accepted*. |

**REQ-242 per path** (what the model now does; every REQ-242 property passes):

| Path | Job state at the step | Record written |
|---|---|---|
| Trigger, nothing missed (newest on time, no older one passed) | Active | none |
| Trigger, RunOnce / RunAll (max = 1, A-4), something missed | Active | one; `Started`, `Waiting` or `Skipped`, naming the created occurrence |
| Trigger, Skip misfire, something missed | Active | one; `Misfire` |
| Schedule change (REQ-204, REQ-241, REQ-212 → REQ-227), at least one instant passed, however recently | Active | one; `Schedule` |
| Pause (REQ-214), at least one instant passed | Active → Paused | one; `Pause` |
| Orphan sweep (REQ-205 / REQ-207), at least one instant passed | Active → Orphaned / removed | one; `Orphan` / `Removed` |
| Operator removal (REQ-213), at least one instant passed | Active → removed | one; `Removed` |
| Any step on a paused or orphaned job; resume (REQ-215), restore (REQ-206), trigger-now (REQ-226) | — | none |

**Impacted, re-checked.** INV-207: SCN-211 is still reachable (an on-time newest instant creates its occurrence under Skip). `Prop_RecordSaysOutcome` passes under all three misfire policies (`Recurring_Misfire.cfg`, 2,886,396 distinct), so an on-time instant is never recorded as missed by a trigger. REQ-217: SCN-206 is still reachable (one catch-up occurrence, started), and the `Started`/`Waiting`/`Skipped` records are each reachable.

**Also checked, not findings:**
- *A pause and a trigger, both atomic, never record the same instant twice.* `Prop_NoInstantRecordedTwice` holds everywhere it runs. A record step leaves the job with nextRunAt from now or not active, and every way back into Active computes nextRunAt from now. Splitting the pause is F-1.
- *A pause during maintenance* records the instants that fell due during maintenance as dropped by the pause (reachable in 5 steps), instead of sending them through the misfire policy when maintenance ends. INV-210's notes allow this: "Operator and reconciliation actions during maintenance (REQ-206, REQ-215, REQ-227) keep their own 'from now' rules." The instants are now recorded, where before run 6 they were dropped with no trace.
- *A removed job's record* outlives the job (REQ-242 keeps it as long as dead-lettered jobs are kept). The model keeps it per name, so a job re-added under the same name continues the same count (A-21). Nothing reads the count, so this is not judged.

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | ambiguity | medium | REQ-242, REQ-214, REQ-205, REQ-213, REQ-216 | The pause, orphan and removal writes now decide a record from what they read, and nothing says they are conditional. A trigger that lands between the read and the write runs the instant, and the pause still records it as dropped, so integrations REQ-403 alerts a miss that did not happen. |

---

## F-1 · ambiguity · medium — A pause can record an instant that a trigger ran in the meantime
<!-- finding: ambiguity | Prop_RecordOnlyUnhandledInstants | REQ-205,REQ-213,REQ-214,REQ-216,REQ-242 -->

**Requirements involved**
- REQ-242: *When an active recurring job's nextRunAt is moved past one or more missed due instants, …, or an active recurring job is paused (REQ-214), orphaned (REQ-205) or removed (REQ-207, REQ-213) while it has missed due instants, the system shall record … how they were handled (… or that … the pause, the orphaning or the removal dropped them), **in the same store write** that moves nextRunAt or pauses, orphans or removes the job …*
- REQ-234: *… or, for an instant that fell due while the recurring job was active, when no trigger ran for it before nextRunAt was moved past it or the job stopped being active, however recently it fell due.*
- REQ-214: *When an operator pauses a recurring job through the API or the dashboard, the system shall mark the job paused.*
- REQ-216: *While a recurring job is active and maintenance is off, when its nextRunAt has passed according to the database clock, the system shall **in one compare-and-set on nextRunAt**, advance nextRunAt … and create the occurrence or occurrences its misfire policy calls for.*
- INV-207: *When a recurring job is triggered no more than MisfireThreshold after its due instant, the system shall treat the instant as on time and create its occurrence whatever the misfire policy.*
- integrations REQ-403 alerts a missed occurrence from REQ-242's record.

**What happens** (TLC, `RecurringRace.tla`, `Recurring_Race_Pause.cfg`: `Prop_RecordOnlyUnhandledInstants` is violated in 6 states; the trigger shape below came from a scratch trap on the same spec, also 6 states). `nightly-export` is code-defined, daily at 02:00, with a running worker:
1. The node starts and `nightly-export` is created, active (REQ-203).
2. 02:00:00 passes. The scheduler polls every few seconds and has not triggered it yet.
3. At 02:00:02 an operator pauses `nightly-export` from the dashboard. The pause call reads the job: active, and the 02:00 instant has passed with no trigger, so under REQ-234 the pause will drop it, and REQ-242 says to record it.
4. Before the pause's write lands, the scheduler triggers the job. It is 2 s late, so it is on time (INV-207). REQ-216's compare-and-set on nextRunAt succeeds and creates the 02:00 occurrence, which starts. Nothing was missed, so no record is written.
5. The pause write lands: the job is paused, and **the record it decided in step 3 says the 02:00 instant was dropped by the pause.** But the 02:00 run is running.
6. Integrations REQ-403 reads the record and alerts that `nightly-export` missed its 02:00 run.

TLC's shortest trace has an operator schedule edit in step 4 instead of the trigger. The pause then records an instant that the edit's own record (`Schedule`) already covers, so the instant is recorded twice, and so alerted twice (integrations INV-412: each record is its own event). An orphan sweep or an operator removal that races a trigger has the same shape, because each also decides the record from its read. The split was modeled for the pause only.

**Why** Before run 6, a pause only set the job's state, and REQ-216's compare-and-set already settled any race over nextRunAt. Run 6 made the pause, orphan and removal writes depend on nextRunAt as well (which instants are missed), but only "in the same store write" says how they are written. That makes them atomic with respect to themselves, not conditional on what they read. The main model writes each of them as one atomic step with their read (A-2), so it cannot see this. `RecurringRace.tla` splits the pause into its read and its write, and the gap appears at once.

**Options**
1. *(recommended)* **Make the record-writing write a compare-and-set on nextRunAt, like REQ-216's.** The pause, orphan and removal write judges the missed instants by the database clock at the write, and changes nothing if nextRunAt moved since it was read; the caller reads again. One phrase in REQ-242, and the same pattern every recurring write that touches nextRunAt already uses (TECH-45).
   - **Checked:** with this (`Recurring_Race_PauseCAS.cfg`, 9,357,168 distinct states), `Prop_RecordOnlyUnhandledInstants`, `Prop_MissRecordOnlyByMove`, `Prop_MissedMoveRecordsOnce`, `Prop_NoInstantRecordedTwice`, `Prop_LeaveRecordsMissed`, `Prop_PassedInstantRunsOrIsRecorded` and INV-201 hold. (`Prop_RecordSaysOutcome` names the atomic `Pause` action, so it does not apply to the split steps.)
   - *Not checked, worth deciding with it:* the reverse order, where a trigger reads the job as active, the pause lands, and the trigger's compare-and-set then succeeds because a pause does not move nextRunAt. That would create an occurrence for a paused job (INV-201) and record the instant a second time. REQ-216's guard and its compare-and-set are one step in this model (A-2). If the store's compare-and-set compares nextRunAt only, as REQ-216 and TECH-45 say, nothing stops it. Making REQ-216's compare-and-set "on nextRunAt and the job's state" closes it. It is a second phrase, and it is not model-checked.
2. **Accept and say so.** Add to REQ-242's notes that a pause, orphaning or removal that races a trigger or a schedule change can record an instant that was run or already recorded, so integrations REQ-403 can alert a miss that did not happen, or alert one twice. The subject cooldown (integrations INV-400) merges repeats for the same job within a cooldown, but not a false first alert. Notes only.
3. **Say it in TECH-45 only.** Extend "Every store shall trigger recurring jobs with an atomic compare-and-set on the stored NextRunAt" to pausing, orphaning and removing a job. Behaviour is unchanged from option 1, but the rule lives in the mechanism, so the logic file stays silent and the next modeling run keeps A-2 as an assumption instead of a requirement.

**Ready to apply (option 1, in `specs/recurring.json`)**
```json
{ "id": "REQ-242",
  "ears": {
    "shall": "record in the job store which due instants were missed (the first, the last and how many) and how they were handled (the occurrences the misfire policy created for them and whether each started, is waiting or was skipped by the overlap policy, or that the misfire policy, the schedule change, the pause, the orphaning or the removal dropped them), in the same store write that moves nextRunAt or pauses, orphans or removes the job, which is a compare-and-set on nextRunAt like REQ-216's, judges the missed instants by the database clock and changes nothing if nextRunAt moved since it was read, and keep that record as long as dead-lettered jobs are kept (jobs RetentionDeadLettered)" },
  "dependsOn": ["REQ-216", "REQ-217", "REQ-218", "REQ-219", "REQ-220", "REQ-222", "REQ-227", "REQ-234", "REQ-214", "REQ-205", "REQ-207", "REQ-213"],
  "notes": "<existing notes> refiner-model run 6 F-1 (recommended option): the pause, orphan and removal writes decide the record from what they read, so they are conditional on it. Unconditional, a trigger landing between the read and the write ran the instant on time and the pause still recorded it as dropped, and integrations REQ-403 alerted a miss that did not happen." }
```
Optional, not model-checked (the reverse order above): REQ-216's `shall` becomes *"in one compare-and-set on nextRunAt and the job's state, advance nextRunAt …"*, and TECH-45 says the same.

---

## Accepted (not findings)
- **Run-5 F-3: a REQ-242 record that says "is waiting" is a snapshot** (REQ-242 notes). The recorded waiting occurrence can later be skipped (REQ-237) or start (REQ-224) while the record still says waiting (`Recurring_P_RecordedWaiterSkipped.cfg`, 6 states, action probe violated as expected).
- **Run-4 F-2's trace, now recorded correctly**: a RunOnce catch-up skipped by the overlap policy (`Recurring_P_CatchUpSkipped.cfg`, 5 states). The record says `Skipped`.
- **REQ-240's notes, scoped to Skip and Queue** (run-4 F-3): two Unroutable jobs of one recurring job under Allow (`Recurring_P_OneUnroutable.cfg`, 6 states). `Note240_OneUnroutableSkipQueue` holds for Skip and Queue.
- **Run-3 probes** (REQ-225 start meeting an Unroutable job; REQ-240 cancelling an Unroutable trigger-now run) and the **REQ-241 window** (`Recurring_P_StaleDefinition2.cfg`), unchanged, still reachable as documented.
- **REQ-238 (info)**: an abandoned or lease-lost handler still runs beside the next job (`Recurring_F_RunningHandlers.cfg`, 7 states).

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. A-1 to A-24 are from runs 1 to 5, and changes are marked.
| # | Assumption | Affects |
|---|---|---|
| A-1 | No clock. Each job keeps a count of due instants passed since nextRunAt was set (0, 1, "2 or more"), and time passing is a nondeterministic step. "nextRunAt computed from now" resets the count to 0. | REQ-215, REQ-216, REQ-227, REQ-204, REQ-206, REQ-241, INV-210, REQ-242 |
| A-2 | *(changed)* REQ-216's compare-and-set is one atomic step with its guard, so INV-203 and SCN-200 hold by construction. So is "in the same store write" in REQ-242, including the pause, orphan and removal writes and the read that decides them. `RecurringRace.tla` drops this for the pause (F-1). | INV-203, SCN-200, REQ-242, F-1 |
| A-3 | The newest due instant is late or on time by nondeterministic choice. With two or more instants due, the older ones are always missed, which assumes the schedule interval exceeds MisfireThreshold. | REQ-217–REQ-219, REQ-234, INV-207, REQ-242 |
| A-4 | RunAll(max) is modeled with max = 1, which makes it indistinguishable from RunOnce. So REQ-242's "whether each" is checked for one occurrence. | REQ-219, REQ-242 |
| A-5 | A trigger creates at most one occurrence. | REQ-216–REQ-219 |
| A-6 | Every modeled node has the worker registered. A node declares exactly what its release declares, and "running" means up. What nodes publish in their heartbeat (declared names and each name's definition hash) is known to the scheduler at once; heartbeat expiry is not modeled. The scheduler (triggers, orphan sweep, REQ-241) and jobs REQ-125's handler registration need some running worker (hosting REQ-40). | REQ-203–REQ-207, REQ-216, REQ-241 |
| A-7 | REQ-224 is a separate system step after the earlier job finishes. | REQ-224 |
| A-8 | At node start, REQ-203 and REQ-204 (and REQ-242's schedule-change record) are applied together for every declared name. The store is keyed by name, so INV-200 and SCN-207 hold by construction. | REQ-203, REQ-204, INV-200, SCN-207, REQ-242 |
| A-9 | Overlap, misfire and orphan policies are fixed per job for a whole run. | REQ-205, REQ-207, REQ-212, REQ-221–REQ-225 |
| A-10 | jobs.Job is reduced to Enqueued / Processing / Failed / Succeeded / DeadLettered / Cancelled / Unroutable plus a "handler still executing" flag (lease lost, jobs REQ-132; abandoned on timeout, jobs REQ-138/REQ-186). jobs REQ-125 (Unroutable → Enqueued) can happen whenever a worker runs. | INV-204, REQ-221–REQ-225, REQ-239, REQ-240 |
| A-11 | Occurrences whose job is final in the jobs module (not Unroutable) free their slot (modeling artefact). | all |
| A-12 | INV-204 is checked as written (`Inv_NoOverlapProcessing`, the Processing state). `Inv_NoOverlapRunning` (any executing handler) is kept only to show the window REQ-238 accepts. | INV-204, REQ-238 |
| A-13 | definitionHash is the hash of the code definition last applied. A runtime edit under AllowRuntimeOverride changes the stored definition but not the hash, so REQ-241 never fires because of a runtime edit. | REQ-204, REQ-212, REQ-241 |
| A-14 | Configuration-defined jobs are not modeled (INV-209 and REQ-232 are `may`), so REQ-236 is checked for code-defined names only. | INV-209, REQ-232, REQ-236 |
| A-15 | The same-trigger warnings from `validate` (REQ-222/REQ-223/REQ-225/REQ-235 with REQ-221; REQ-205/REQ-207) are each one action, with complementary and exhaustive guards. REQ-242 is an `invariant` with a `when` clause; it is modeled as one more consequence of the trigger, schedule-change, pause, orphan and removal events, not as a state predicate. | REQ-242 |
| A-16 | REQ-236's and REQ-210's "fail the host's start" is abstracted as the node staying down. The hosting module owns the node's states. | REQ-236 |
| A-17 | One switch remains: `RerouteOn` explores jobs REQ-125 only in `MainR`, `F_RerouteOverlap`, `F_RerouteQueue` and SCN-215, so the run-1 fixes and the Unroutable rules are judged separately. | INV-204, REQ-240 |
| A-18 | REQ-240 is applied to every start: REQ-221, REQ-224 and REQ-225 (Allow and CancelPrevious). "Earlier" means created before, in creation order. Confirmed by the owner (run-3 F-1). | REQ-240, REQ-225 |
| A-19 | REQ-240's start and cancel are one atomic step, so jobs REQ-125 cannot return the job to Enqueued between them. | REQ-240, INV-204 |
| A-20 | REQ-241 is a reconciliation step, not a scheduled trigger, so INV-210 does not stop it during maintenance. Whether the schedule changed is a nondeterministic choice, as in REQ-204. | REQ-241, INV-210 |
| A-21 | *(changed)* REQ-242's record is abstracted to, per name, a count of records (0, 1, "2 or more"), how the latest one says the instants were handled (`Started` / `Waiting` / `Skipped` naming the occurrence created in that write, `Misfire`, `Schedule`, `Pause`, `Orphan` or `Removed`), and that occurrence. "First, last and how many" are not modeled. The count is never reset: the model has no retention, and a record outlives a removed or orphaned job, kept per name. At "2 or more" a further record of the same kind is invisible, so the "exactly one record" checks are weak there. | REQ-242 |
| A-22 | *(changed)* `missRec` is written only by `Trigger`, the schedule-change steps, `Pause`, `Orphan` and `OperatorRemove`, and read by no guard or update, so states that differ only in it have the same futures. The five 3-slot Queue cfgs, which check nothing about REQ-242, use `VIEW ViewNoRec`. Every other cfg explores `missRec` in full. | checks in the Queue cfgs |
| A-23 | "Missed" for a trigger is REQ-234's first clause: an instant more than MisfireThreshold late. A trigger with only the newest instant late records a miss; with only an on-time newest instant it records nothing. | REQ-242, REQ-234 |
| A-24 | Schemas are not modeled. The initial store holds no recurring job, which is what REQ-236 says a store without a Bellhop schema holds. | REQ-236 |
| A-25 | *(rewritten)* REQ-234's second clause: while a job is Active, the count of A-1 is exactly the instants that fell due while it was active (every way into Active resets it), so any step other than a trigger that moves nextRunAt from now, or takes the job out of Active, while the count is at least 1, passes over missed instants (`HasMissed`). Run 5's nondeterministic choice for a just-passed instant is gone. | REQ-234, REQ-242 |
| A-26 | *(new)* In `RecurringRace.tla` the pause is a read and a later write. The read decides whether the job has missed instants. Unconditional, the write lands that decision whatever happened since. With `CondPause` (F-1 option 1), the write changes nothing if nextRunAt moved since the read (a trigger or a schedule change), and otherwise judges the missed instants at the write (the database clock). The orphan sweep and operator removal are not split; they have the same shape. The atomic `Pause` stays in the spec, so every behaviour of `Recurring` is included. | F-1 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-201–REQ-208, REQ-211–REQ-227, REQ-233–REQ-237, REQ-239–REQ-242, INV-200, INV-201, INV-203, INV-204, INV-206, INV-207, INV-210, INV-211, SCN-200–SCN-215 | REQ-200, REQ-228, REQ-229, REQ-230, INV-202, INV-208 (need a real clock: time zones, DST, validity window) · REQ-209, REQ-210 (schedule/time-zone validity not representable) · INV-205 (no exceptions or lock waits in the model) · REQ-231 (bookkeeping, nothing depends on it) · REQ-232, INV-209 (strength `may`) · REQ-238 (`info`; shown by `Inv_NoOverlapRunning`) |

Some modeled items are not judged:
- INV-200, INV-203, SCN-200 and SCN-207 hold by construction (A-2, A-8). So do REQ-242's "one record per write" and "same store write" (A-2). The model checks that nothing else writes a record, that every step past missed instants writes one, that no instant is recorded twice, and that the record agrees with what that write did.
- REQ-242's retention ("as long as dead-lettered jobs are kept") needs a clock. Its "first, last and how many" are not modeled (A-21).
- REQ-219 and REQ-242's "whether each" are modeled only with max = 1 (A-4).
- REQ-236 is checked for code-defined names only (A-14).
- REQ-241's settling is checked as "eventually", not "within a time".
- The cancel reason Superseded (REQ-240) is not modeled.

## How to reproduce
From `specs/model/recurring`: `sh gen_cfgs.sh` regenerates the non-scenario cfgs, and `sh run_all.sh` reruns every check below. Each check is one `run_tlc.py <module> --config <cfg> --stop-at-first` call, where the module is `Recurring.tla`, or `RecurringRace.tla` for the `Race_*` cfgs. Scenario and race cfgs add `--no-deadlock`. `run_all.sh <name>` runs one check. `TLC_WORKERS` (default 4) and `TLC_TIMEOUT` (default 300 s) set the workers and the per-run limit. The `run*.json`/`run*.md` outputs are gitignored.

- TLC 2.19 throws "unexpected exception" when `-continue` has to rebuild many traces, so every check uses `--stop-at-first`. The run that produced this report grepped every output for that message and found none.
- This run used `TLC_WORKERS=2 TLC_TIMEOUT=540`, because three other modules were being model-checked on the same machine. None hit the limit, and the times are not comparable with run 5.
- Don't start a second TLC run in this folder while one is running: TLC's `-cleanup` removes the shared `states/` folder, and the other run fails with "when reading the disk". The vacuity checks and the first race runs ran from scratch copies for that reason.
- The vacuity checks quoted above (each of the nine record kinds reachable; a pause and a schedule change with only the newest instant passed; removal of an active job by REQ-213 and by REQ-207; a `Schedule` record by REQ-204 and by REQ-241, the latter with two nodes on three releases; a pause during maintenance) and the trigger-shaped F-1 trace ran from scratch modules that extended `Recurring` / `RecurringRace` and were then deleted. They are not part of `run_all.sh`.

| Check | Config | Result |
|---|---|---|
| Main: INV-201, INV-210 (both), REQ-233, SCN-200/202, REQ-237, REQ-239 skip rule, INV-204, REQ-242 (six properties) (1 job, 2 slots, Skip/Queue × RunOnce/Skip) | `Recurring.cfg` | passed, 1,735,656 distinct, 43 s |
| Main with jobs REQ-125 | `Recurring_MainR.cfg` | passed, 1,735,656 distinct, 46 s |
| **REQ-242** under RunOnce, Skip and RunAll, plus the main checks | `Recurring_Misfire.cfg` | passed, 2,886,396 distinct, 74 s |
| Definitions: REQ-211/SCN-205, INV-206/SCN-212, SCN-208, INV-211/SCN-214, REQ-236, REQ-237, REQ-242 at node start, orphaning and removal (2 jobs, 2 nodes, both orphan policies) | `Recurring_Defs.cfg` | passed, 2,586,248 distinct, 182 s |
| Overlap, all four policies, 2 slots: REQ-233, INV-204, REQ-239 skip rule | `Recurring_OverlapAll.cfg` | passed, 2,395,024 distinct, 35 s |
| Overlap Queue(1), 3 slots: REQ-233, REQ-237, REQ-239 skip rule | `Recurring_OverlapQueue.cfg` | passed, 7,439,116 distinct, 182 s |
| Overlap Queue(2), 3 slots: REQ-233, REQ-239 skip rule | `Recurring_OverlapQueue2.cfg` | passed, 7,191,148 distinct, 141 s |
| Run-1 F-1: INV-204, Queue(1), 3 slots | `Recurring_F_WaitingRace.cfg` | passed, 7,439,116 distinct, 126 s |
| Run-1 F-2: probe + INV-204, Queue(2), 3 slots | `Recurring_P_QueueTwoWaiters.cfg` | passed, 7,191,148 distinct, 137 s |
| Run-1 F-5: probe, one node, 3 releases | `Recurring_P_StaleDefinition.cfg` | passed, 151,500 distinct, 2 s |
| Run-1 F-6: probe | `Recurring_P_RuntimeTakenOver.cfg` | passed, 151,500 distinct, 3 s |
| Run-1 F-7: REQ-239 skip rule | `Recurring_P_UnroutableBlocks.cfg` | passed, 2,395,024 distinct, 29 s |
| Run-2 F-1: INV-204, skip rule and the REQ-240 note (Skip/Queue) with jobs REQ-125 and REQ-240, all four policies | `Recurring_F_RerouteOverlap.cfg` | passed, 2,395,024 distinct, 27 s |
| Run-2 F-1: INV-204, REQ-233, REQ-237, skip rule and the REQ-240 note with jobs REQ-125 and REQ-240, Queue(1), 3 slots | `Recurring_F_RerouteQueue.cfg` | passed, 7,439,116 distinct, 157 s |
| Run-2 F-2: REQ-241 settling (liveness + action property) and REQ-242, two nodes, v1/v2 | `Recurring_Liv_Settles.cfg` | passed, 94,146 distinct, 10 s |
| Run-2 F-2: same, two nodes, three releases, AllowRuntimeOverride | `Recurring_Liv_Settles3.cfg` | passed, 468,546 distinct, 55 s |
| Run-2 F-2 window (probe; REQ-241 closes it one step later) | `Recurring_P_StaleDefinition2.cfg` | probe violated, 5 states, as expected |
| Run-3 F-1: a REQ-225 start can meet an Unroutable job (probe) | `Recurring_P_Req225Unroutable.cfg` | probe violated, 5 states; covered by REQ-240 on purpose |
| Run-3 F-2: a trigger-now Unroutable job superseded by a scheduled start (action probe) | `Recurring_P_TriggerNowSuperseded.cfg` | action probe violated, 6 states; accepted (`run_tlc.py` labels an action-property violation "error") |
| Run-4 F-1 regression: overdue instants dropped by a schedule change are recorded | `Recurring_F_OverdueRecorded.cfg` | passed, 151,500 distinct, 4 s |
| Run-4 F-2: a RunOnce catch-up skipped by the overlap policy (action probe; the record says `Skipped`) | `Recurring_P_CatchUpSkipped.cfg` | action probe violated, 5 states, as expected |
| Run-4 F-3: two Unroutable jobs of one recurring job (probe, all four policies) | `Recurring_P_OneUnroutable.cfg` | probe violated, 6 states (Allow); the notes say so |
| **Run-5 F-1** regression: missed instants recorded at a pause or an operator removal | `Recurring_F_OverduePaused.cfg` | passed, 1,735,656 distinct, 35 s |
| **Run-5 F-1** regression: ... and at an orphaning or a delete by the orphan sweep | `Recurring_F_OverdueOrphaned.cfg` | passed, 199,146 distinct, 5 s |
| **Run-5 F-2** regression: a just-passed instant dropped by a schedule change is recorded | `Recurring_F_PassedInstant.cfg` | passed, 1,735,656 distinct, 25 s |
| Run-5 F-3 (accepted): a record saying "waiting", then REQ-237 skips that occurrence (action probe) | `Recurring_P_RecordedWaiterSkipped.cfg` | action probe violated, 6 states, as expected |
| **F-1**: pause split into read and write, unconditional | `Recurring_Race_Pause.cfg` (`RecurringRace.tla`) | `Prop_RecordOnlyUnhandledInstants` violated, 6 states |
| **F-1 option 1**: the pause write is a compare-and-set on nextRunAt | `Recurring_Race_PauseCAS.cfg` (`RecurringRace.tla`) | passed, 9,357,168 distinct, 233 s |
| REQ-238 window (info) | `Recurring_F_RunningHandlers.cfg` | `Inv_NoOverlapRunning` violated, 7 states, as REQ-238 accepts |
| SCN-201, 203, 204, 206, 209 (legs `SCN209`, `SCN209b`), 210, 211, 213, 215 | `Recurring_SCNnnn.cfg` | every trap violated as expected (2–6 states): all reachable |

Deadlock checking is on in every non-scenario, non-race run, and none was found. Probes (`Probe_…`, `ProbeAct_…`) and `Note240_…` are modeling aids, not requirements. Each probe asserts that a situation is unreachable; `Note240_OneUnroutableSkipQueue` checks a claim made in REQ-240's notes.

## Next
Decide F-1 and apply it to `specs/recurring.json` with the `refiner-requirements` skill (it validates and diffs), then run `refiner-model` again. Option 1 is one phrase in REQ-242. The optional REQ-216 phrase is worth deciding at the same time, because it closes the reverse order of the same race; it is not model-checked yet. Integrations REQ-403 needs no change either way.
