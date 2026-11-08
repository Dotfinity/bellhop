# Findings: Bellhop recurring jobs

<!-- refiner-findings v1 | module: recurring | specHash: 90327ae0b99bd7899bd5cffbe24df47baac2158ef875afd8c2048f5388b970d9 | run: 2026-11-08 (run 5) | previous: specs/model/recurring/previous.findings.md (run 4, specHash 5c02192f9862) -->

**Run:** 2026-11-08, run 5 · **Requirements file:** `specs/recurring.json` (specHash `90327ae0b99b`) · **Model:** `specs/model/recurring/Recurring.tla` · **TLC:** 2.19. Every check ran alone with `--stop-at-first` and finished with no TLC exception and no timeout: 37 cfgs, up to 7,439,116 distinct states, at most 148 s each. See [How to reproduce](#how-to-reproduce).
**Result:** 3 findings: 0 contradictions · 1 gap · 0 unprovable · 2 ambiguities · 0 modeling notes. All three run-4 findings are resolved. The reworded REQ-242 holds as written: a schedule change that moves an active job's nextRunAt past missed instants now writes the record, and the record says whether the catch-up occurrence started, is waiting or was skipped. The new findings sit at the edges of the new sentence: a job that stops being active (F-1), an instant that has passed but is not yet "missed" (F-2), and a record that says "is waiting" forever (F-3).

The model has no clock. It cannot judge anything that depends on real amounts of time: DST, time zones, validity windows, the 60 s misfire threshold as a number, or how long REQ-242's record is kept. See *Coverage*.

## Changes since last run
| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | gap · ProbeAct_OverdueLeavesOnlyByTrigger · REQ-204,REQ-227,REQ-241,REQ-242 |
| F-2 | resolved | ambiguity · ProbeAct_CatchUpNeverSkipped · REQ-217,REQ-222,REQ-242 |
| F-3 | resolved | ambiguity · Probe_OneUnroutablePerJob · REQ-225,REQ-240 |
| F-1 | new | gap · ProbeAct_OverduePausedRecorded · REQ-205,REQ-206,REQ-214,REQ-215,REQ-242 |
| F-2 | new | ambiguity · ProbeAct_PassedInstantRunsOrIsRecorded · REQ-227,REQ-234,REQ-242 |
| F-3 | new | ambiguity · ProbeAct_RecordedWaiterNeverSkipped · REQ-223,REQ-237,REQ-242 |

3 resolved, 3 new, 0 still open

(Table from `findings_delta.py`.) What changed in the requirements (handoff `specs/model/recurring/handoff.json`, base fe77203):
- REQ-242's sentence (resolution commit da32b43). It now fires when an active job's nextRunAt is moved past missed instants by a trigger (REQ-216) or by a schedule change (REQ-227). The record says how the instants were handled: the occurrences the misfire policy created and whether each started, is waiting or was skipped by the overlap policy, or that the misfire policy or the schedule change dropped them. "Same compare-and-set" became "same store write". `dependsOn` gained REQ-222 and REQ-227.
- Annotation only (no hash change): REQ-227's notes (dropped instants are recorded), REQ-240's notes (run-4 F-3: "never more than one Unroutable job" is scoped to Skip and Queue), and integrations REQ-403's notes.

Model changes:
- REQ-242 regenerated. `missRec` is now a record per name: the count (as before), how the latest record says the instants were handled (`Started`, `Waiting`, `Skipped` with the occurrence it names, `Misfire` or `Schedule`), and that occurrence (A-21, updated).
- The schedule-change branches of REQ-204 (`NodeStart`), REQ-241 (`ReapplyCode`) and REQ-212/REQ-227 (`OperatorUpdate`) now write the record when the job is Active and missed instants are passed over (A-25, new). Their other behaviour is unchanged.
- The two run-4 REQ-242 properties are replaced by three: `Prop_MissRecordOnlyByMove`, `Prop_MissedMoveRecordsOnce`, `Prop_RecordSaysOutcome`. They run in Main, MainR, Misfire, Defs, both REQ-241 settling cfgs and the new `Recurring_F_OverdueRecorded.cfg`.
- The run-4 F-1 probe (`ProbeAct_OverdueLeavesOnlyByTrigger`, `Recurring_P_OverdueDropped.cfg`) is retired. Its path is now the regression check `Recurring_F_OverdueRecorded.cfg`, which is expected to hold. There are four new probes, one for each new finding plus F-1's orphan path.

Every other action is byte-for-byte as in run 4. Every check was rerun, because the state of every action changed.

How each run-4 finding was re-checked:

| Run-4 finding | Requirement change | Evidence in run 5 |
|---|---|---|
| F-1 a schedule change drops overdue instants with no record | REQ-242's `when` covers schedule changes (REQ-227) of an active job | `Prop_MissedMoveRecordsOnce` holds. It says that every step taking an Active job with missed instants to nextRunAt-from-now, by any action, writes exactly one record. Checked in `Recurring_F_OverdueRecorded.cfg` (run 4's F-1 constants: one node, three releases, REQ-204 and REQ-241; 76,500 distinct states), `Recurring_Defs.cfg` (400,968), `Recurring_Liv_Settles3.cfg` (288,234) and the main cfgs (operator edits, REQ-212). A scratch vacuity check reached a `Schedule` record written by REQ-204 at node start and one written by REQ-241. |
| F-2 a record saying "caught up" for a run Skip dropped | The record says whether each catch-up occurrence started, is waiting or was skipped | The run-4 trace is still reachable (`Recurring_P_CatchUpSkipped.cfg`, 5 states), but the record written in step 4 now says `Skipped` and names the skipped occurrence. `Prop_RecordSaysOutcome` holds in Main, MainR and Misfire (2,153,292 distinct states, all three misfire policies). Scratch vacuity checks reached all five kinds of record. |
| F-3 "never more than one Unroutable job" | REQ-240's notes scoped to Skip and Queue | `Note240_OneUnroutableSkipQueue` holds in `Recurring_F_RerouteOverlap.cfg` (1,736,064) and `Recurring_F_RerouteQueue.cfg` (7,439,116). `Probe_OneUnroutablePerJob` is still reached under Allow in 6 states, which the notes now say. |

**REQ-242 per path** (what the model now does; all three properties pass):

| Path | Job state at the move | Record written |
|---|---|---|
| Trigger, nothing missed (newest on time, no older one passed) | Active | none |
| Trigger, RunOnce / RunAll (max = 1, A-4), something missed | Active | one; `Started`, `Waiting` or `Skipped`, naming the created occurrence |
| Trigger, Skip misfire, something missed | Active | one; `Misfire` (dropped by the misfire policy) |
| Schedule change (REQ-204, REQ-241, REQ-212 → REQ-227), older instants missed | Active | one; `Schedule` |
| Schedule change, only the newest instant passed and not yet triggered | Active | one or none, depending on the reading of "missed" (**F-2**) |
| Schedule change | Paused | none (REQ-242 notes: dropped on purpose) |
| Pause (REQ-214), orphan sweep (REQ-205, REQ-207), operator removal (REQ-213) of a job with missed instants | Active → Paused / Orphaned / removed | none (**F-1**), and every way back to Active is "from now" |
| Resume (REQ-215), restore (REQ-206), trigger-now (REQ-226) | — | none |

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | gap | medium | REQ-242, REQ-214, REQ-215, REQ-205, REQ-206 | Instants missed while a job is active are dropped with no record if the job is paused or orphaned before a trigger runs. Resume and restore then compute nextRunAt from now, and REQ-242 only covers moves of an *active* job. |
| F-2 | ambiguity | medium | REQ-242, REQ-234, REQ-227 | REQ-234 defines "missed" only for a trigger. An instant that has passed but has not been triggered yet, and is then dropped by a schedule change, gets neither an occurrence nor (under one reading) a record. |
| F-3 | ambiguity | low | REQ-242, REQ-223, REQ-237 | The record says the catch-up occurrence "is waiting" and is never updated. When REQ-237 later skips that occurrence, the record still says it is waiting. |

---

## F-1 · gap · medium — Missed instants of a job that is then paused or orphaned leave no record
<!-- finding: gap | ProbeAct_OverduePausedRecorded | REQ-205,REQ-206,REQ-214,REQ-215,REQ-242 -->

**Requirements involved**
- REQ-242: *When an active recurring job's nextRunAt is moved past one or more missed due instants, by a trigger (REQ-216) or by a schedule change (REQ-227), the system shall record in the job store which due instants were missed … and how they were handled …* Notes: *"Paused and orphaned jobs are excluded: their instants are dropped on purpose (REQ-215, REQ-206)."*
- REQ-214: *When an operator pauses a recurring job through the API or the dashboard, the system shall mark the job paused.*
- REQ-215: *When an operator resumes a paused recurring job, the system shall mark the job active and compute nextRunAt from now.* Notes: *"instants missed while paused are dropped … Maintenance is different: instants that fall due during maintenance go through the misfire policy (INV-210)."*
- REQ-205 / REQ-206: the orphan sweep marks a job no running node declares orphaned (REQ-207 deletes it under orphanPolicy Delete). A node that declares it again restores it and computes nextRunAt from now.
- INV-210: *… so that instants missed meanwhile go through the misfire policy when maintenance ends.*
- integrations REQ-403 alerts a missed occurrence from REQ-242's record.

**What happens, by pause** (TLC counter-example, action probe `ProbeAct_OverduePausedRecorded`, `Recurring_P_OverduePaused.cfg`, 5 states). `hourly-invoices` runs hourly, misfire RunOnce:
1. An operator adds `hourly-invoices` (REQ-208). It is active.
2. Every worker node is down (or maintenance is on, INV-210), so no trigger runs. 01:00 passes.
3. 02:00 passes. The 01:00 instant is now more than MisfireThreshold overdue, so it is missed (REQ-234, A-3).
4. The operator pauses `hourly-invoices` (REQ-214). **No record is written: a pause does not move nextRunAt, and REQ-242 fires only on a move.** The count stays 0.

From here the model has no way to write the record. Resume (REQ-215) computes nextRunAt from now, but the job is paused at that move, so REQ-242 does not fire. A schedule change while paused does not fire it either (the sentence says *active*). The 01:00 and 02:00 runs never happen, and integrations REQ-403 never alerts them as missed. If maintenance was the cause, INV-210 promised that those instants would go through the misfire policy.

**What happens, by orphaning** (`ProbeAct_OverdueOrphanedRecorded`, `Recurring_P_OverdueOrphaned.cfg`, 7 states). `nightly-export` is code-defined, daily at 02:00:
1. The node starts on release v1, which declares `nightly-export`. The job is created Active (REQ-203).
2. The node goes down (an outage).
3. 02:00 passes.
4. The next due instant passes too, so at least one instant is missed (REQ-234, A-3).
5. The node comes back on release v3, which no longer declares `nightly-export` (a deploy during the outage).
6. The orphan sweep runs before the trigger. Both are enabled, and the order is up to the scheduler. The sweep marks the job orphaned and remembers Active (REQ-205). **No record is written.**

If the deploy is rolled back, REQ-206 restores the job to Active and computes nextRunAt from now. The job is orphaned at that move, so REQ-242 does not fire. Under orphanPolicy Delete (REQ-207) the definition is removed in step 6 instead. In both cases the missed run leaves no trace. Had the trigger won the race in step 6, RunOnce would have caught it up and recorded it.

**Why** Run-4 F-1 hung the record on the move of an *active* job's nextRunAt, and excluded paused and orphaned jobs because instants that fall due *while* paused or orphaned are dropped on purpose. The instants here fell due while the job was active, and REQ-215's own notes say maintenance-time instants go through the misfire policy. A pause or an orphaning does not move nextRunAt, so REQ-242 does not fire at that step. The later move (REQ-215 or REQ-206) happens while the job is not active, so REQ-242 does not fire then either. Removing an active runtime job with missed instants (REQ-213) is a third path, but there the job is gone. As in run-4 F-1, whether a missed run leaves a trace depends on what the operator or the deploy happened to do next.

**Options**
1. *(recommended)* **Record them when the job stops being active.** Add a second trigger to REQ-242: an active job whose nextRunAt has already passed missed instants is paused, orphaned or removed. The record says the instants were dropped by the pause, orphaning or removal. That write is the pause, orphan or removal write. There is still one record and one consumer, and the "dropped on purpose" rule for instants that fall due while paused or orphaned stays. Together with F-2 option 1, "missed" here means "passed and never triggered".
2. **Accept it.** Say in REQ-242's notes (and REQ-215's and REQ-206's) that instants already missed when a job is paused or orphaned are dropped without a record. Integrations REQ-403 alerts them only through its "has not started" branch, and only if an alerts node evaluated the rule after its tolerance passed and before the pause. No behaviour change.
3. **Trigger before pausing.** Before REQ-214 or REQ-205 takes an overdue active job out of Active, run the trigger (misfire policy and REQ-242 record). A pause would then start a run, which is not what an operator who pauses expects. Not recommended.

**Ready to apply (option 1)**
```json
{ "id": "REQ-242",
  "ears": {
    "when": "an active recurring job's nextRunAt is moved past one or more missed due instants, by a trigger (REQ-216) or by a schedule change (REQ-227), or an active recurring job whose nextRunAt has already passed one or more missed due instants is paused (REQ-214), orphaned (REQ-205) or removed (REQ-207, REQ-213)",
    "shall": "record in the job store which due instants were missed (the first, the last and how many) and how they were handled (the occurrences the misfire policy created for them and whether each started, is waiting or was skipped by the overlap policy, or that the misfire policy, the schedule change, the pause, the orphaning or the removal dropped them), in the same store write that moves nextRunAt or changes the job's state, and keep that record as long as dead-lettered jobs are kept (jobs RetentionDeadLettered)" },
  "dependsOn": ["REQ-216", "REQ-217", "REQ-218", "REQ-219", "REQ-220", "REQ-222", "REQ-227", "REQ-214", "REQ-205", "REQ-207", "REQ-213"],
  "notes": "<existing notes, with 'Paused and orphaned jobs are excluded: their instants are dropped on purpose (REQ-215, REQ-206).' replaced by: 'Instants that fall due while a job is paused or orphaned are dropped on purpose and not recorded (REQ-215, REQ-206); instants already missed when an active job is paused, orphaned or removed are recorded in that write (refiner-model run 5 F-1).'>" }
```

---

## F-2 · ambiguity · medium — Is an instant that has passed but was not yet triggered "missed" at a schedule change?
<!-- finding: ambiguity | ProbeAct_PassedInstantRunsOrIsRecorded | REQ-227,REQ-234,REQ-242 -->

**Requirements involved**
- REQ-234: *The system shall treat a due instant as missed only when the trigger runs more than MisfireThreshold after it, 60 seconds by default (MisfireThreshold).*
- REQ-242: *When an active recurring job's nextRunAt is moved past one or more **missed** due instants, by a trigger (REQ-216) or by a schedule change (REQ-227), …*
- REQ-227: *When a recurring job's schedule changes, the system shall compute nextRunAt from now, never from the last execution, and create no catch-up occurrence for the old schedule.*
- INV-207: *When a recurring job is triggered no more than MisfireThreshold after its due instant, the system shall treat the instant as on time and create its occurrence whatever the misfire policy.* Notes: *"so Skip never drops a run that is only a poll interval late."*

**What happens** (TLC counter-example, action probe `ProbeAct_PassedInstantRunsOrIsRecorded`, `Recurring_P_PassedInstantDropped.cfg`, 4 states). `tenant-sync` is a runtime job, hourly at :00, misfire RunOnce:
1. An operator adds `tenant-sync` (REQ-208). It is active.
2. 10:00:00 passes. The scheduler polls every few seconds and has not triggered it yet.
3. At 10:00:05 the operator changes its schedule to :30 (REQ-212). REQ-227 computes nextRunAt from now. **The 10:00 instant is gone: no occurrence was created for it (REQ-227: no catch-up), and it was not "missed" under REQ-234, because no trigger ran more than MisfireThreshold after it. So, under that reading, REQ-242 writes no record.** The run has silently not happened. The record count stays 0.

The same happens when REQ-204 applies a changed schedule at a node start, or REQ-241 applies one, a few seconds after a due instant. If the scheduler had polled first, INV-207 would have run the instant as on time. If the change had come more than 60 s later, REQ-242 would have recorded it.

**Why** REQ-234 defines "missed" by when *the trigger* runs. Run 4 added a path with no trigger (the schedule change), so for that path the word is undefined. Read literally, an instant less than MisfireThreshold old is not missed, so it is neither run nor recorded. Read as "passed and will never run", it is recorded as dropped by the schedule change. The model explores both (A-25), and `Prop_MissedMoveRecordsOnce` checks only the case where an older instant was certainly missed. The window is short (MisfireThreshold plus the poll interval), but in it a run disappears without trace, which INV-207 and REQ-242 were each written to prevent.

**Options**
1. *(recommended)* **Define "missed" for moves without a trigger.** Amend REQ-234: an instant is also missed when nextRunAt is moved past it without a trigger (a schedule change, or with F-1 option 1 a pause, orphaning or removal), however recently it fell due. Every passed instant that will not run is then recorded, and REQ-227's "no catch-up" is unchanged.
2. **Keep REQ-234, and say so.** Add to REQ-242's notes that an instant less than MisfireThreshold old when a schedule change moves nextRunAt is neither run nor recorded. No behaviour change, but the drop is invisible.
3. **Run it as on time.** Extend INV-207 so that a schedule change first creates the occurrence of an instant still within MisfireThreshold under the old schedule. That makes REQ-227 create something for the old schedule, and it adds an ordering rule to REQ-204, REQ-241 and REQ-212. Not recommended.

**Ready to apply (option 1)**
```json
{ "id": "REQ-234",
  "ears": { "shall": "treat a due instant as missed when the trigger runs more than MisfireThreshold after it, 60 seconds by default (MisfireThreshold), or when nextRunAt is moved past it without a trigger (a schedule change, REQ-227), however recently it fell due" },
  "notes": "<existing notes> refiner-model run 5 F-2: REQ-242 also records instants dropped without a trigger; without this clause an instant less than MisfireThreshold old at a schedule change was neither run nor recorded." }
```
(If F-1 option 1 is taken too, add "or a pause, orphaning or removal (REQ-242)" after "a schedule change, REQ-227".)

---

## F-3 · ambiguity · low — A record saying the catch-up occurrence "is waiting" is never updated
<!-- finding: ambiguity | ProbeAct_RecordedWaiterNeverSkipped | REQ-223,REQ-237,REQ-242 -->

**Requirements involved**
- REQ-242: *… how they were handled (the occurrences the misfire policy created for them and whether each started, **is waiting** or was skipped by the overlap policy …), in the same store write that moves nextRunAt …*
- REQ-223: under overlap Queue, an occurrence created while an earlier one is in the way waits.
- REQ-237: *When a recurring job is paused, orphaned or removed while it has waiting occurrences, the system shall record each waiting occurrence as skipped with reason Paused, Orphaned or Removed.*
- REQ-231: an occurrence's outcome is recorded as the job's *last* outcome, which the next occurrence overwrites.

**What happens** (TLC counter-example, action probe `ProbeAct_RecordedWaiterNeverSkipped`, `Recurring_P_RecordedWaiterSkipped.cfg`, 6 states). `tenant-sync` is code-defined, hourly, misfire RunOnce, overlap Queue(1):
1. A node starts and the job is created (REQ-203).
2. An operator triggers it now, and its job is enqueued (REQ-226, REQ-221).
3. The 10:00 instant passes. The scheduler is more than MisfireThreshold late, so the instant is missed (REQ-234).
4. The trigger runs. RunOnce creates one occurrence for the miss (REQ-217), and it waits behind the operator's job (REQ-223). The same write records the miss: *one occurrence, waiting* (REQ-242).
5. The operator pauses `tenant-sync` (REQ-214). The waiting occurrence is skipped with reason Paused (REQ-237). **The record still says the missed instant's occurrence is waiting. Nothing will run for it.** The skip is visible only as the job's last outcome (REQ-231) until the next occurrence overwrites it.

The record can also go stale the other way: the waiting occurrence later starts (REQ-224), and the record still says waiting.

**Why** REQ-242 writes the record once, in the write that moves nextRunAt. "Is waiting" is the only one of the three outcomes that can still change after that write. Run-4 F-2 chose to record the outcome so that a reader of the record never has to correlate it with an overwritten last outcome. For a waiting occurrence, the reader still has to.

**Options**
1. *(recommended)* **Say what "waiting" means.** Add to REQ-242's notes that the record describes each occurrence as it was in that write, and that it names the occurrence so a reader can look up whether a waiting one later started or was skipped. Annotation only. This assumes that occurrences are kept as long as the record. If they are not, take option 2.
2. **Update the record.** When a waiting occurrence named in a REQ-242 record starts (REQ-224) or is skipped (REQ-237), record that in the record in the same write. The record is then always current, but it gets a second writer, and two more requirements change.

**Ready to apply (option 1)**
```json
{ "id": "REQ-242",
  "notes": "<existing notes> refiner-model run 5 F-3: the record describes each occurrence as it was in the write that moved nextRunAt; a waiting one may later start (REQ-224) or be skipped (REQ-237), which the record does not follow. It names the occurrence so that its later state can be looked up." }
```

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. A-1 to A-24 are from runs 1 to 4; changes are marked.
| # | Assumption | Affects |
|---|---|---|
| A-1 | No clock. Each job keeps a count of due instants passed since nextRunAt was set (0, 1, "2 or more"), and time passing is a nondeterministic step. "nextRunAt computed from now" resets the count to 0. | REQ-215, REQ-216, REQ-227, REQ-204, REQ-206, REQ-241, INV-210, REQ-242 |
| A-2 | REQ-216's compare-and-set is one atomic step, so INV-203 and SCN-200 hold by construction. So does "in the same store write" in REQ-242: the record is written in the step that moves nextRunAt. | INV-203, SCN-200, REQ-242 |
| A-3 | The newest due instant is late or on time by nondeterministic choice. With two or more instants due, the older ones are always missed, which assumes the schedule interval exceeds MisfireThreshold. | REQ-217–REQ-219, REQ-234, INV-207, REQ-242 |
| A-4 | RunAll(max) is modeled with max = 1, which makes it indistinguishable from RunOnce. So REQ-242's "whether each" is checked for one occurrence. | REQ-219, REQ-242 |
| A-5 | A trigger creates at most one occurrence. | REQ-216–REQ-219 |
| A-6 | Every modeled node has the worker registered. A node declares exactly what its release declares, and "running" means up. What nodes publish in their heartbeat (declared names and each name's definition hash) is known to the scheduler at once; heartbeat expiry is not modeled. The scheduler (triggers, orphan sweep, REQ-241) and jobs REQ-125's handler registration need some running worker (hosting REQ-40). | REQ-203–REQ-207, REQ-216, REQ-241 |
| A-7 | REQ-224 is a separate system step after the earlier job finishes. | REQ-224 |
| A-8 | At node start, REQ-203 and REQ-204 (and now REQ-242's schedule-change record) are applied together for every declared name. The store is keyed by name, so INV-200 and SCN-207 hold by construction. | REQ-203, REQ-204, INV-200, SCN-207, REQ-242 |
| A-9 | Overlap, misfire and orphan policies are fixed per job for a whole run. | REQ-205, REQ-207, REQ-212, REQ-221–REQ-225 |
| A-10 | jobs.Job is reduced to Enqueued / Processing / Failed / Succeeded / DeadLettered / Cancelled / Unroutable plus a "handler still executing" flag (lease lost, jobs REQ-132; abandoned on timeout, jobs REQ-138/REQ-186). jobs REQ-125 (Unroutable → Enqueued) can happen whenever a worker runs. | INV-204, REQ-221–REQ-225, REQ-239, REQ-240 |
| A-11 | Occurrences whose job is final in the jobs module (not Unroutable) free their slot (modeling artefact). | all |
| A-12 | INV-204 is checked as written (`Inv_NoOverlapProcessing`, the Processing state). `Inv_NoOverlapRunning` (any executing handler) is kept only to show the window REQ-238 accepts. | INV-204, REQ-238 |
| A-13 | definitionHash is the hash of the code definition last applied. A runtime edit under AllowRuntimeOverride changes the stored definition but not the hash, so REQ-241 never fires because of a runtime edit. | REQ-204, REQ-212, REQ-241 |
| A-14 | Configuration-defined jobs are not modeled (INV-209 and REQ-232 are `may`), so REQ-236 is checked for code-defined names only. | INV-209, REQ-232, REQ-236 |
| A-15 | The same-trigger warnings from `validate` (REQ-222/REQ-223/REQ-225/REQ-235 with REQ-221; REQ-205/REQ-207) are each one action, with complementary and exhaustive guards. REQ-242 is an `invariant` with a `when` clause; it is modeled as one more consequence of the trigger and schedule-change events, not as a state predicate. | REQ-242 |
| A-16 | REQ-236's and REQ-210's "fail the host's start" is abstracted as the node staying down. The hosting module owns the node's states. | REQ-236 |
| A-17 | One switch remains: `RerouteOn` explores jobs REQ-125 only in `MainR`, `F_RerouteOverlap`, `F_RerouteQueue` and SCN-215, so the run-1 fixes and the Unroutable rules are judged separately. | INV-204, REQ-240 |
| A-18 | REQ-240 is applied to every start: REQ-221, REQ-224 and REQ-225 (Allow and CancelPrevious). "Earlier" means created before, in creation order. Confirmed by the owner (run-3 F-1). | REQ-240, REQ-225 |
| A-19 | REQ-240's start and cancel are one atomic step, so jobs REQ-125 cannot return the job to Enqueued between them. | REQ-240, INV-204 |
| A-20 | REQ-241 is a reconciliation step, not a scheduled trigger, so INV-210 does not stop it during maintenance. Whether the schedule changed is a nondeterministic choice, as in REQ-204. | REQ-241, INV-210 |
| A-21 | *(changed)* REQ-242's record is abstracted to, per name, a count of records (0, 1, "2 or more"), how the latest one says the instants were handled (`Started` / `Waiting` / `Skipped` naming the occurrence created in that write, `Misfire`, or `Schedule`), and that occurrence. "First, last and how many" are not modeled. The count is never reset: the model has no retention, and a record outlives a removed or orphaned job. | REQ-242 |
| A-22 | *(changed)* `missRec` is written only by `Trigger` and the schedule-change steps, and read by no guard or update, so states that differ only in it have the same futures. The five 3-slot Queue cfgs, which check nothing about REQ-242, use `VIEW ViewNoRec`. Every other cfg explores `missRec` in full. | checks in the Queue cfgs |
| A-23 | "Missed" for a trigger is REQ-234's: an instant more than MisfireThreshold late. A trigger with only the newest instant late records a miss; with only an on-time newest instant it records nothing. | REQ-242, REQ-234 |
| A-24 | Schemas are not modeled. The initial store holds no recurring job, which is what REQ-236 says a store without a Bellhop schema holds. | REQ-236 |
| A-25 | *(new)* At a schedule change, an active job with two or more instants passed has missed the older ones (A-3) and is always recorded. With only the newest instant passed, whether it counts as missed is a nondeterministic choice, because REQ-234 defines "missed" only for a trigger (F-2). Only an *active* job's schedule change writes a record, as the sentence says. | REQ-242, REQ-204, REQ-212, REQ-241 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-201–REQ-208, REQ-211–REQ-227, REQ-233–REQ-237, REQ-239–REQ-242, INV-200, INV-201, INV-203, INV-204, INV-206, INV-207, INV-210, INV-211, SCN-200–SCN-215 | REQ-200, REQ-228, REQ-229, REQ-230, INV-202, INV-208 (need a real clock: time zones, DST, validity window) · REQ-209, REQ-210 (schedule/time-zone validity not representable) · INV-205 (no exceptions or lock waits in the model) · REQ-231 (bookkeeping, nothing depends on it) · REQ-232, INV-209 (strength `may`) · REQ-238 (`info`; shown by `Inv_NoOverlapRunning`) |

Some modeled items are not judged:
- INV-200, INV-203, SCN-200 and SCN-207 hold by construction (A-2, A-8). So do REQ-242's "one record per move" and "same store write" (A-2). The model checks that nothing else writes a record, that every move past missed instants writes one, and that the record agrees with what that write did.
- REQ-242's retention ("as long as dead-lettered jobs are kept") needs a clock. Its "first, last and how many" are not modeled (A-21).
- REQ-219 and REQ-242's "whether each" are modeled only with max = 1 (A-4).
- REQ-236 is checked for code-defined names only (A-14).
- REQ-241's settling is checked as "eventually", not "within a time".
- The cancel reason Superseded (REQ-240) is not modeled.

## How to reproduce
From `specs/model/recurring`: `sh gen_cfgs.sh` regenerates the non-scenario cfgs, and `sh run_all.sh` reruns every check below. Each check is one `run_tlc.py Recurring.tla --config <cfg> --stop-at-first --workers 4` call; scenario cfgs add `--no-deadlock`. `run_all.sh <name>` runs one check. The `run*.json`/`run*.md` outputs are gitignored.

- TLC 2.19 throws "unexpected exception" when `-continue` has to rebuild many traces, so every check uses `--stop-at-first`. The run that produced this report grepped every output for that message and found none.
- `run_all.sh` wraps each run in `timeout` because `run_tlc.py --timeout` does not stop TLC on Windows. This run used `TLC_TIMEOUT=300` for the five 3-slot Queue cfgs and `TLC_TIMEOUT=200` for the rest. None hit the limit. Four other modules were being model-checked on the same machine at the same time, so the times are not comparable with run 4.
- Don't start a second TLC run in this folder while one is running: TLC's `-cleanup` removes the shared `states/` folder and the other run fails with "when reading the disk".
- The vacuity checks quoted above (each kind of record reachable; a `Schedule` record written by REQ-204 and by REQ-241) were run from a scratch module that extended `Recurring` and was then deleted. They are not part of `run_all.sh`.

| Check | Config | Result |
|---|---|---|
| Main: INV-201, INV-210 (both), REQ-233, SCN-200/202, REQ-237, REQ-239 skip rule, INV-204, REQ-242 (three properties) (1 job, 2 slots, Skip/Queue × RunOnce/Skip) | `Recurring.cfg` | passed, 1,246,728 distinct, 15 s |
| Main with jobs REQ-125 | `Recurring_MainR.cfg` | passed, 1,246,728 distinct, 16 s |
| **REQ-242** under RunOnce, Skip and RunAll, plus the main checks | `Recurring_Misfire.cfg` | passed, 2,153,292 distinct, 23 s |
| Definitions: REQ-211/SCN-205, INV-206/SCN-212, SCN-208, INV-211/SCN-214, REQ-236, REQ-237, REQ-242 at node start (2 jobs, 2 nodes, both orphan policies) | `Recurring_Defs.cfg` | passed, 400,968 distinct, 29 s |
| Overlap, all four policies, 2 slots: REQ-233, INV-204, REQ-239 skip rule | `Recurring_OverlapAll.cfg` | passed, 1,736,064 distinct, 17 s |
| Overlap Queue(1), 3 slots: REQ-233, REQ-237, REQ-239 skip rule | `Recurring_OverlapQueue.cfg` | passed, 7,439,116 distinct, 141 s |
| Overlap Queue(2), 3 slots: REQ-233, REQ-239 skip rule | `Recurring_OverlapQueue2.cfg` | passed, 7,191,148 distinct, 124 s |
| Run-1 F-1: INV-204, Queue(1), 3 slots | `Recurring_F_WaitingRace.cfg` | passed, 7,439,116 distinct, 120 s |
| Run-1 F-2: probe + INV-204, Queue(2), 3 slots | `Recurring_P_QueueTwoWaiters.cfg` | passed, 7,191,148 distinct, 101 s |
| Run-1 F-5: probe, one node, 3 releases | `Recurring_P_StaleDefinition.cfg` | passed, 76,500 distinct, 2 s |
| Run-1 F-6: probe | `Recurring_P_RuntimeTakenOver.cfg` | passed, 76,500 distinct, 2 s |
| Run-1 F-7: REQ-239 skip rule | `Recurring_P_UnroutableBlocks.cfg` | passed, 1,736,064 distinct, 15 s |
| Run-2 F-1: INV-204, skip rule and the REQ-240 note (Skip/Queue) with jobs REQ-125 and REQ-240, all four policies | `Recurring_F_RerouteOverlap.cfg` | passed, 1,736,064 distinct, 16 s |
| Run-2 F-1: INV-204, REQ-233, REQ-237, skip rule and the REQ-240 note with jobs REQ-125 and REQ-240, Queue(1), 3 slots | `Recurring_F_RerouteQueue.cfg` | passed, 7,439,116 distinct, 148 s |
| Run-2 F-2: REQ-241 settling (liveness + action property) and REQ-242, two nodes, v1/v2 | `Recurring_Liv_Settles.cfg` | passed, 57,834 distinct, 6 s |
| Run-2 F-2: same, two nodes, three releases, AllowRuntimeOverride | `Recurring_Liv_Settles3.cfg` | passed, 288,234 distinct, 34 s |
| Run-2 F-2 window (probe; REQ-241 closes it one step later) | `Recurring_P_StaleDefinition2.cfg` | probe violated, 4 states, as expected |
| Run-3 F-1: a REQ-225 start can meet an Unroutable job (probe) | `Recurring_P_Req225Unroutable.cfg` | probe violated, 5 states; covered by REQ-240 on purpose |
| Run-3 F-2: a trigger-now Unroutable job superseded by a scheduled start (action probe) | `Recurring_P_TriggerNowSuperseded.cfg` | action probe violated, 6 states; accepted (`run_tlc.py` labels an action-property violation "error") |
| **Run-4 F-1** regression: overdue instants dropped by a schedule change are recorded (REQ-242's three properties) | `Recurring_F_OverdueRecorded.cfg` | passed, 76,500 distinct, 2 s |
| Run-4 F-2: a RunOnce catch-up skipped by the overlap policy (action probe; the record now says `Skipped`) | `Recurring_P_CatchUpSkipped.cfg` | action probe violated, 5 states, as expected |
| Run-4 F-3: two Unroutable jobs of one recurring job (probe, all four policies) | `Recurring_P_OneUnroutable.cfg` | probe violated, 6 states (Allow); the notes now say so |
| **F-1**: an active job with missed instants paused, no record (action probe) | `Recurring_P_OverduePaused.cfg` | action probe violated, 5 states |
| **F-1**: the same through the orphan sweep (action probe) | `Recurring_P_OverdueOrphaned.cfg` | action probe violated, 7 states |
| **F-2**: a schedule change drops a passed, not-yet-triggered instant with no occurrence and no record (action probe) | `Recurring_P_PassedInstantDropped.cfg` | action probe violated, 4 states |
| **F-3**: a record saying "waiting", then REQ-237 skips that occurrence (action probe) | `Recurring_P_RecordedWaiterSkipped.cfg` | action probe violated, 6 states |
| REQ-238 window (info) | `Recurring_F_RunningHandlers.cfg` | `Inv_NoOverlapRunning` violated, 7 states, as REQ-238 accepts |
| SCN-201, 203, 204, 206, 209 (legs `SCN209`, `SCN209b`), 210, 211, 213, 215 | `Recurring_SCNnnn.cfg` | every trap violated as expected (2–4 states): all reachable |

Deadlock checking is on in every non-scenario run, and none was found. Probes (`Probe_…`, `ProbeAct_…`) and `Note240_…` are modeling aids, not requirements. Each probe asserts that a situation is unreachable; `Note240_OneUnroutableSkipQueue` checks a claim made in REQ-240's notes.

## Next
Apply the chosen options to `specs/recurring.json` with the `refiner-requirements` skill (it validates and diffs), then run `refiner-model` again. F-1 and F-2 both concern which instants REQ-242 records; their recommended options fit together (REQ-234 defines "missed" for moves without a trigger, and REQ-242 gains the pause, orphan and removal paths). F-3 is notes only. If F-1 option 1 is taken, integrations REQ-403 needs no change, because it already reads REQ-242's record. It will then alert instants dropped by a pause too.
