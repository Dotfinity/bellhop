# Findings: Bellhop recurring jobs

<!-- refiner-findings v1 | module: recurring | specHash: 5c02192f98626fb02a908c6263bc6066f651184a484a85d701eb927a5b0b1779 | run: 2026-11-07 (run 4) | previous: specs/model/recurring/previous.findings.md (run 3, specHash 77018f6c8a50) -->

**Run:** 2026-11-07, run 4 · **Requirements file:** `specs/recurring.json` (specHash `5c02192f9862`) · **Model:** `specs/model/recurring/Recurring.tla` · **TLC:** 2.19. Every check ran alone with `--stop-at-first` and finished with no TLC exception and no timeout: 33 cfgs, up to 7,439,116 distinct states, at most 121 s each. See [How to reproduce](#how-to-reproduce).
**Result:** 3 findings: 0 contradictions · 1 gap · 0 unprovable · 2 ambiguities · 0 modeling notes. Both run-3 findings are resolved. The new REQ-242 holds as written: one record per trigger that missed something, written in the same step, under all three misfire policies. The gap is a path that drops missed instants without a trigger.

The model has no clock. It cannot judge anything that depends on real amounts of time: DST, time zones, validity windows, the 60 s misfire threshold as a number, or how long REQ-242's record is kept. See *Coverage*.

## Changes since last run
| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | ambiguity · REQ-240 · REQ-225,REQ-239,REQ-240 |
| F-2 | resolved | gap · REQ-240 · REQ-226,REQ-240 |
| F-1 | new | gap · ProbeAct_OverdueLeavesOnlyByTrigger · REQ-204,REQ-227,REQ-241,REQ-242 |
| F-2 | new | ambiguity · ProbeAct_CatchUpNeverSkipped · REQ-217,REQ-222,REQ-242 |
| F-3 | new | ambiguity · Probe_OneUnroutablePerJob · REQ-225,REQ-240 |

2 resolved, 3 new, 0 still open

(Table from `findings_delta.py`.) What changed in the requirements (handoff `specs/model/recurring/handoff.json`, base 9e15c1e):
- REQ-240 gained REQ-225 in `dependsOn`, and its notes now confirm run-3 F-1 and F-2. The sentence is unchanged.
- REQ-236's `if` clause now says the collision is judged by each stored job's name and origin only, and that a store with no Bellhop schema stores none.
- REQ-242 is new: a missed-instant record, written in the trigger's compare-and-set.
- RecurringJob gained the attribute `missedInstants`, which is why the handoff lists 49 impacted ids.

Model changes:
- REQ-242 is the new variable `missRec`, written only by `Trigger`, with two new properties.
- REQ-236's encoding is unchanged; only its comment was updated (A-24).
- REQ-240's encoding is unchanged, because run 3 already modeled the sentence as written (A-18).
- New checks: one cfg (`Recurring_Misfire.cfg`) and three probes.
- The five 3-slot Queue cfgs use a VIEW without `missRec` (A-22).

Because the state of every action changed, every check was rerun. No other action was rewritten.

How each run-3 finding was re-checked:

| Run-3 finding | Requirement change | Evidence in run 4 |
|---|---|---|
| F-1 REQ-240's sentence covers every start, its metadata only Skip and Queue | REQ-225 added to `dependsOn`; notes: every start supersedes, under every overlap policy | The model already applied the sentence to REQ-221, REQ-224 and REQ-225 starts (A-18), so the decision confirms what was checked. `Recurring_F_RerouteOverlap.cfg` covers all four policies with jobs REQ-125 and passes INV-204, the REQ-239 skip rule and the notes' "one Unroutable job" claim for Skip and Queue: 653,248 distinct states. The run-3 probe (a REQ-225 start meets an earlier Unroutable job) is still reachable in 5 states. That situation is real, and the sentence now covers it on purpose. |
| F-2 a trigger-now run that is Unroutable is cancelled as Superseded | Accepted; REQ-240's notes say so | `ProbeAct_TriggerNowNeverSuperseded` is still violated in 6 states (`Recurring_P_TriggerNowSuperseded.cfg`). That is the accepted behaviour, and the trace matches the notes. |

**REQ-240: duplicates and stranded jobs.**
- *Duplicates:* under Skip and Queue, no two occurrences' jobs of one recurring job are ever Processing at once (INV-204) in any check, including with jobs REQ-125 returning Unroutable jobs. At most one job per recurring job is Unroutable (`Note240_OneUnroutableSkipQueue`, 653,248 and 7,439,116 distinct states). Under Allow and CancelPrevious, two jobs can be Unroutable at once (F-3). Allow permits that overlap.
- *Stranded jobs:* REQ-240 only fires when a later occurrence starts. An Unroutable job of a recurring job that is then paused, orphaned or removed waits for jobs REQ-125 (handler back) or jobs REQ-134 (operator cancel), like any other job. That is by reading, not a TLC check. No recurring rule leaves a job in a state that no requirement can move it out of.

**REQ-242 per misfire policy** (`Recurring_Misfire.cfg`: RunOnce, Skip and RunAll, Skip and Queue overlap, maintenance and outages; 722,628 distinct states; both properties pass):

| Misfire policy | Instants missed at the trigger | Occurrence created | REQ-242 record |
|---|---|---|---|
| any | none (the newest instant on time, no older one passed) | the on-time one (INV-207) | none written (`Prop_MissRecordOnlyByMissedTrigger`) |
| RunOnce | older ones and/or the newest is late | one, for all of them (REQ-217) | exactly one, same step (`Prop_MissedTriggerRecordsOnce`) |
| Skip | the newest is late | none (REQ-218) | exactly one, same step. The record is the only stored trace of the miss. |
| Skip | older ones, the newest is on time | the on-time one | exactly one, same step |
| RunAll (max = 1, A-4) | as RunOnce | as RunOnce | exactly one, same step |

Trigger-now (REQ-226), reconciliation (REQ-204, REQ-206, REQ-241), resume (REQ-215) and operator edits (REQ-227) never write a record. That is what REQ-242 says, but it is how F-1 arises. A RunOnce or RunAll catch-up occurrence can be skipped by the overlap policy in the same write (F-2).

**REQ-236.** The model has never modeled schemas. Its initial store holds no recurring job, which is what the new wording says a store without a Bellhop schema holds. So the first start on a new database is never refused (`Recurring_Defs.cfg`, 44,552 distinct states, `Scn_RuntimeNameBlocksStart` passes). The guard reads only each stored name's origin. The claim that every schema version stores name and origin (TECH-127, "migrations only add") is taken as given (A-24).

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | gap | medium | REQ-242, REQ-204, REQ-227, REQ-241 | A schedule change applied at a node start (or by REQ-241) moves nextRunAt past instants that were already missed; no trigger runs, so REQ-242 writes no record and the miss is never alerted |
| F-2 | ambiguity | low | REQ-242, REQ-217, REQ-222 | "How the misfire policy handled them": a RunOnce catch-up occurrence can be skipped by the overlap policy in the same write, so a record saying "caught up" does not mean a run happened |
| F-3 | ambiguity | low | REQ-240, REQ-225 | REQ-240's notes say a recurring job never holds more than one Unroutable job. Under Allow (and CancelPrevious) it can hold two. |

---

## F-1 · gap · medium — Missed instants dropped by a schedule change leave no REQ-242 record
<!-- finding: gap | ProbeAct_OverdueLeavesOnlyByTrigger | REQ-204,REQ-227,REQ-241,REQ-242 -->

**Requirements involved**
- REQ-242: *When a recurring job is triggered after one or more due instants were missed, the system shall record in the job store which due instants were missed (the first, the last and how many) and how the misfire policy handled them, in the same compare-and-set that advances nextRunAt, …*
- REQ-204: *When a node with the worker registered starts and the hash of a code-defined recurring job's code definition differs from the definitionHash of the stored code-defined job with that name, the system shall update the stored definition and definitionHash to match the code, keeping its paused or active state, and, if the schedule changed, compute nextRunAt from now as in REQ-227.*
- REQ-227: *When a recurring job's schedule changes, the system shall compute nextRunAt from now, never from the last execution, and create no catch-up occurrence for the old schedule.*
- REQ-241 (the scheduler re-applies a running node's code) and REQ-212 (an operator edit) also end in REQ-227.
- integrations REQ-403 reads missed occurrences from REQ-242's record (its notes, and integrations INV-412).

**What happens** (TLC counter-example, action probe `ProbeAct_OverdueLeavesOnlyByTrigger`, `Recurring_P_OverdueDropped.cfg`, 6 states, one node). `nightly-export` is code-defined, runs daily at 02:00 with misfire RunOnce, and the app runs on one node:
1. The node starts on release v1, which declares `nightly-export`. The job is created Active (REQ-203).
2. The 02:00 instant passes. Nothing has triggered it yet.
3. The node is stopped for a deploy at 02:00:30, before its scheduler polls.
4. The deploy stalls, and the next due instant passes too. Now at least one instant is more than MisfireThreshold overdue (REQ-234), so it is missed.
5. The node starts on release v2, whose code moves `nightly-export` to 02:30. REQ-204 rewrites the definition and, because the schedule changed, computes nextRunAt from now (REQ-227). **The overdue instants are gone. No trigger ran, so REQ-242 wrote no record and REQ-220 wrote no log or event.** The record count stays 0. integrations REQ-403 never alerts the miss, because its "missed" branch reads only REQ-242's record. Its "has not started" branch reads the stored nextRunAt, so it catches the miss only if an alerts node was up and the rule's tolerance had passed before step 5. On a one-node app neither is true.

With an unchanged schedule the same outage ends in a trigger that catches up under RunOnce and writes the record. The model shows that run in `Recurring_Misfire.cfg` and SCN-206. So whether a missed run leaves any trace depends on whether the deploy also changed the schedule.

**Why** REQ-242 hangs the record on the trigger. Three other requirements move nextRunAt past overdue instants without a trigger, through REQ-227. REQ-227's "no catch-up" is a deliberate decision. What is missing is the record that runs were missed. INV-210's notes accept that operator and reconciliation actions keep their own "from now" rules, but they do not mention that those rules make a miss invisible to alerts. Paused and orphaned jobs are different: REQ-215's and REQ-206's notes say their instants are dropped on purpose, and nothing is due while a job is paused.

**Options**
1. *(recommended)* **Record the drop as a miss.** Widen REQ-242's trigger to every move of an *active* job's nextRunAt past missed instants: a trigger (REQ-216) or a schedule change (REQ-227). The handling recorded is then "dropped by a schedule change". There is still one record, one sentence and one consumer, and REQ-227's "no catch-up" stays. Cost: an operator's deliberate edit during an outage also produces a miss alert, which is accurate (runs did not happen). Not model-checked as a rule; the probe shows the paths it would cover (REQ-204 here; REQ-241 and REQ-212 are the same step shape).
2. **Accept it.** Say in REQ-227's notes and in integrations REQ-403's notes that instants dropped by a schedule change are not recorded as missed, and are alerted only by the "has not started" branch if its tolerance passed first. No behaviour change. A one-node deploy after an outage then loses a run without a trace.
3. **Trigger before applying the new schedule.** Before REQ-204, REQ-241 or REQ-212 applies a changed schedule to an active job that is overdue, run the trigger under the old schedule (misfire policy, REQ-242 record). This catches the run up instead of dropping it. That reverses REQ-227's "no catch-up" for this case and adds an ordering rule to three requirements. Not recommended.

**Ready to apply (option 1)**
```json
{ "id": "REQ-242",
  "ears": {
    "when": "an active recurring job's nextRunAt is moved past one or more missed due instants, by a trigger (REQ-216) or by a schedule change (REQ-227)",
    "shall": "record in the job store which due instants were missed (the first, the last and how many) and how they were handled (by the misfire policy, or dropped by the schedule change), in the same write that moves nextRunAt, and keep that record as long as dead-lettered jobs are kept (jobs RetentionDeadLettered)" },
  "dependsOn": ["REQ-216", "REQ-217", "REQ-218", "REQ-219", "REQ-220", "REQ-227"],
  "notes": "<existing notes> Run 4 F-1 (recommended option): a schedule change applied at a node start (REQ-204), by the scheduler (REQ-241) or by an operator (REQ-212) drops missed instants without a trigger; they are recorded too, so integrations REQ-403 alerts them. Paused and orphaned jobs are excluded: their instants are dropped on purpose (REQ-215, REQ-206)." }
```

---

## F-2 · ambiguity · low — A record that says "caught up" does not mean a run happened
<!-- finding: ambiguity | ProbeAct_CatchUpNeverSkipped | REQ-217,REQ-222,REQ-242 -->

**Requirements involved**
- REQ-242: *… record … which due instants were missed … and how the misfire policy handled them, in the same compare-and-set that advances nextRunAt …*
- REQ-217: *When a recurring job is triggered after one or more due instants were missed, if the misfire policy is RunOnce, the system shall create a single occurrence for all missed instants and, if the most recent due instant is on time, for that instant too.*
- REQ-222: *When an occurrence is created while an earlier occurrence of the same recurring job is waiting or has an unfinished job, if the overlap policy is Skip, the system shall start nothing and record the occurrence as skipped.*

**What happens** (TLC counter-example, action probe `ProbeAct_CatchUpNeverSkipped`, `Recurring_P_CatchUpSkipped.cfg`, 5 states). `tenant-sync` runs hourly, misfire RunOnce, overlap Skip:
1. A node starts and the job is created (REQ-203).
2. An operator triggers it now; its job is enqueued (REQ-226, REQ-221).
3. The 10:00 instant passes. The scheduler is late by more than MisfireThreshold, so the instant is missed (REQ-234).
4. The trigger runs. RunOnce creates one occurrence for the missed instant (REQ-217), and the same write records the miss (REQ-242: one record, handled by RunOnce). **The occurrence is created while the operator's job is still unfinished, so Skip records it as skipped (REQ-222).** The record says the miss was caught up by one run, but no run happened. REQ-231's last outcome (skipped) is overwritten by the next occurrence.

The alert itself is not affected: integrations REQ-403 alerts on the record either way. What differs is what the record, and an alert or dashboard built on it, says happened.

**Why** "How the misfire policy handled them" can be read as "what the misfire policy decided" (one catch-up occurrence) or "what became of the missed instants" (nothing ran). The two differ whenever the overlap policy skips the catch-up occurrence (Skip, or Queue when full under REQ-235). Both decisions are made in the same write (A-2), so the record could carry either.

**Options**
1. *(recommended)* **Record the outcome too.** The record also names the occurrence the trigger created and whether it started, waited or was skipped (and why). The trigger knows all of this when it writes, so it costs no extra state. Then a reader of the record never has to correlate it with a last outcome that gets overwritten.
2. **Record the misfire decision only, and say so.** Add to REQ-242's notes that the record describes the misfire policy's decision, and that whether the occurrence ran is in its own outcome (REQ-231). This is the cheapest option, but a consumer that wants to say "and nothing ran" cannot find out once the last outcome is overwritten.

**Ready to apply (option 1)**
```json
{ "id": "REQ-242",
  "ears": {
    "when": "a recurring job is triggered after one or more due instants were missed",
    "shall": "record in the job store which due instants were missed (the first, the last and how many), how the misfire policy handled them and what became of the occurrence it created (started, waiting or skipped, with the reason), in the same compare-and-set that advances nextRunAt, and keep that record as long as dead-lettered jobs are kept (jobs RetentionDeadLettered)" } }
```
(If F-1 option 1 is also taken, merge the two: F-1's `when`, plus this finding's "what became of the occurrence it created". The schedule-change case creates none.)

---

## F-3 · ambiguity · low — REQ-240's notes: "never more than one Unroutable job" holds only for Skip and Queue
<!-- finding: ambiguity | Probe_OneUnroutablePerJob | REQ-225,REQ-240 -->

**Requirements involved**
- REQ-240: *When an occurrence of a recurring job starts while an earlier occurrence of the same recurring job has an unroutable job, the system shall cancel that unroutable job with reason Superseded in the same write that starts the new occurrence.* Notes: *"… so a recurring job never holds more than one Unroutable job and only one runs when a handler comes back."*
- REQ-225: under Allow and CancelPrevious, an occurrence created while an earlier job is unfinished starts too.

**What happens** (TLC counter-example, `Probe_OneUnroutablePerJob`, `Recurring_P_OneUnroutable.cfg`, 6 states). `tenant-sync` has overlap Allow:
1. An operator adds `tenant-sync` at runtime (REQ-208).
2. The operator triggers it now; the job is enqueued (REQ-226, REQ-221).
3. The operator triggers it again. The first job is still enqueued, so Allow starts the second one too (REQ-225). Nothing is Unroutable yet, so REQ-240 does nothing.
4. No running worker lists the handler. The first job is marked Unroutable (jobs REQ-124).
5. The second job is marked Unroutable too. **The recurring job holds two Unroutable jobs. When the handler comes back, jobs REQ-125 returns both, and both run.**

The same happens with scheduled occurrences. It also happens under CancelPrevious: an earlier job whose cancellation REQ-225 requested while it was Processing loses its lease, goes back to Enqueued, and becomes Unroutable beside the newer job. That case was checked on a scratch copy, `Recurring_P_OneUnroutable.cfg` with CancelPrevious only and 3 slots, and was reached in 8 states. Under Skip and Queue the claim holds: `Note240_OneUnroutableSkipQueue` passes in `Recurring_F_RerouteOverlap.cfg` (653,248 distinct states) and `Recurring_F_RerouteQueue.cfg` (7,439,116).

**Why** REQ-240 cancels an Unroutable job only when a *later* occurrence starts. Under Allow, two jobs can be started before either becomes Unroutable. The note's reasoning was written for Skip and Queue (run-2 F-1). Run 3 extended the sentence to every policy but kept the note's wording. Behaviour is fine, because Allow permits the overlap. Only the note promises more than the requirements give.

**Options**
1. *(recommended)* **Scope the note.** Change it to "under Skip and Queue a recurring job never holds more than one Unroutable job …; under Allow and CancelPrevious, jobs started side by side can all become Unroutable and all run when the handler comes back, which those policies permit." Annotation only.
2. **Make it true for every policy.** Add a requirement that when a recurring job's occurrence job becomes Unroutable, its earlier Unroutable jobs are cancelled as Superseded. That is new behaviour in the jobs/recurring seam for no correctness gain under Allow. Not recommended.

**Ready to apply (option 1)**
```json
{ "id": "REQ-240",
  "notes": "<existing notes, with 'so a recurring job never holds more than one Unroutable job and only one runs when a handler comes back' replaced by: 'so under Skip and Queue a recurring job never holds more than one Unroutable job and only one runs when a handler comes back (under Allow and CancelPrevious, jobs started side by side can all become Unroutable and all run when it comes back, which those policies permit; refiner-model run 4 F-3)'>" }
```

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. A-1 to A-20 are from runs 1 to 3; changes are marked.
| # | Assumption | Affects |
|---|---|---|
| A-1 | No clock. Each job keeps a count of due instants passed since nextRunAt was set (0, 1, "2 or more"), and time passing is a nondeterministic step. "nextRunAt computed from now" resets the count to 0. | REQ-215, REQ-216, REQ-227, REQ-204, REQ-206, REQ-241, INV-210, REQ-242 |
| A-2 | REQ-216's compare-and-set is one atomic step, so INV-203 and SCN-200 hold by construction. *(run 4)* So does "in the same compare-and-set" in REQ-242: the record is written in the trigger step. | INV-203, SCN-200, REQ-242 |
| A-3 | The newest due instant is late or on time by nondeterministic choice. With two or more instants due, the older ones are always missed, which assumes the schedule interval exceeds MisfireThreshold. | REQ-217–REQ-219, REQ-234, INV-207, REQ-242 |
| A-4 | RunAll(max) is modeled with max = 1, which makes it indistinguishable from RunOnce. | REQ-219 |
| A-5 | A trigger creates at most one occurrence. | REQ-216–REQ-219 |
| A-6 | Every modeled node has the worker registered. A node declares exactly what its release declares, and "running" means up. What nodes publish in their heartbeat (declared names and each name's definition hash) is known to the scheduler at once; heartbeat expiry is not modeled. The scheduler (triggers, orphan sweep, REQ-241) and jobs REQ-125's handler registration need some running worker (hosting REQ-40). | REQ-203–REQ-207, REQ-216, REQ-241 |
| A-7 | REQ-224 is a separate system step after the earlier job finishes. | REQ-224 |
| A-8 | At node start, REQ-203 and REQ-204 are applied together for every declared name. The store is keyed by name, so INV-200 and SCN-207 hold by construction. | REQ-203, REQ-204, INV-200, SCN-207 |
| A-9 | Overlap, misfire and orphan policies are fixed per job for a whole run. | REQ-205, REQ-207, REQ-212, REQ-221–REQ-225 |
| A-10 | jobs.Job is reduced to Enqueued / Processing / Failed / Succeeded / DeadLettered / Cancelled / Unroutable plus a "handler still executing" flag (lease lost, jobs REQ-132; abandoned on timeout, jobs REQ-138/REQ-186). jobs REQ-125 (Unroutable → Enqueued) can happen whenever a worker runs. | INV-204, REQ-221–REQ-225, REQ-239, REQ-240 |
| A-11 | Occurrences whose job is final in the jobs module (not Unroutable) free their slot (modeling artefact). | all |
| A-12 | INV-204 is checked as written (`Inv_NoOverlapProcessing`, the Processing state). `Inv_NoOverlapRunning` (any executing handler) is kept only to show the window REQ-238 accepts. | INV-204, REQ-238 |
| A-13 | definitionHash is the hash of the code definition last applied. A runtime edit under AllowRuntimeOverride changes the stored definition but not the hash, so REQ-241 never fires because of a runtime edit. | REQ-204, REQ-212, REQ-241 |
| A-14 | Configuration-defined jobs are not modeled (INV-209 and REQ-232 are `may`), so REQ-236 is checked for code-defined names only. | INV-209, REQ-232, REQ-236 |
| A-15 | The same-trigger warnings from `validate` (REQ-222/REQ-223/REQ-225/REQ-235 with REQ-221) are each one action, with complementary and exhaustive guards. *(run 4)* REQ-242 is an `invariant` with a `when` clause; it is modeled as one more consequence of the trigger event (REQ-216–REQ-220), not as a state predicate. | REQ-242 |
| A-16 | REQ-236's and REQ-210's "fail the host's start" is abstracted as the node staying down. The hosting module owns the node's states. | REQ-236 |
| A-17 | One switch remains: `RerouteOn` explores jobs REQ-125 only in `MainR`, `F_RerouteOverlap`, `F_RerouteQueue` and SCN-215, so the run-1 fixes and the Unroutable rules are judged separately. | INV-204, REQ-240 |
| A-18 | REQ-240 is applied to every start: REQ-221, REQ-224 and REQ-225 (Allow and CancelPrevious). "Earlier" means created before, in creation order. *(run 4)* Confirmed by the owner (run-3 F-1). | REQ-240, REQ-225 |
| A-19 | REQ-240's start and cancel are one atomic step, so jobs REQ-125 cannot return the job to Enqueued between them. | REQ-240, INV-204 |
| A-20 | REQ-241 is a reconciliation step, not a scheduled trigger, so INV-210 does not stop it during maintenance. Whether the schedule changed is a nondeterministic choice, as in REQ-204. | REQ-241, INV-210 |
| A-21 | *(new)* REQ-242's record is abstracted to a count of records per name (0, 1, "2 or more"). Its content (first, last, how many, how handled) is not modeled beyond the trigger's `miss` field. The count is never reset: the model has no retention, and the sentence keeps the record for RetentionDeadLettered whatever happens to the definition, so a record outlives a removed or orphaned job. | REQ-242 |
| A-22 | *(new)* `missRec` is written only by `Trigger` and read by no guard or update, so states that differ only in it have the same futures. The five 3-slot Queue cfgs, which check nothing about REQ-242, use `VIEW ViewNoRec` to stay at run-3 size. Every other cfg explores `missRec` in full. | checks in the Queue cfgs |
| A-23 | *(new)* "Missed" in REQ-242 is REQ-234's: an instant more than MisfireThreshold late. A trigger with only the newest instant late (count 1) records a miss; with only an on-time newest instant it records nothing. | REQ-242, REQ-234 |
| A-24 | *(new)* Schemas are not modeled. The initial store holds no recurring job, which is what REQ-236 now says a store without a Bellhop schema holds. That every schema version stores name and origin (REQ-236 notes, TECH-127) is taken as given. | REQ-236 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-201–REQ-208, REQ-211–REQ-227, REQ-233–REQ-237, REQ-239–REQ-242, INV-200, INV-201, INV-203, INV-204, INV-206, INV-207, INV-210, INV-211, SCN-200–SCN-215 | REQ-200, REQ-228, REQ-229, REQ-230, INV-202, INV-208 (need a real clock: time zones, DST, validity window) · REQ-209, REQ-210 (schedule/time-zone validity not representable) · INV-205 (no exceptions or lock waits in the model) · REQ-231 (bookkeeping, nothing depends on it) · REQ-232, INV-209 (strength `may`) · REQ-238 (`info`; shown by `Inv_NoOverlapRunning`) |

Some modeled items are not judged:
- INV-200, INV-203, SCN-200 and SCN-207 hold by construction (A-2, A-8). So do REQ-242's "exactly one record per trigger" and "same compare-and-set" (A-2). The model checks that nothing else writes a record and that every missed trigger writes one, under every misfire policy.
- REQ-242's retention ("as long as dead-lettered jobs are kept") needs a clock.
- REQ-219 is modeled only with max = 1 (A-4).
- REQ-236 is checked for code-defined names only (A-14).
- REQ-241's settling is checked as "eventually", not "within a time".
- The cancel reason Superseded (REQ-240) is not modeled.

## How to reproduce
From `specs/model/recurring`: `sh gen_cfgs.sh` regenerates the non-scenario cfgs, and `sh run_all.sh` reruns every check below. Each check is one `run_tlc.py Recurring.tla --config <cfg> --stop-at-first --workers 4` call; scenario cfgs add `--no-deadlock`. `run_all.sh <name>` runs one check. The `run*.json`/`run*.md` outputs are gitignored.

- TLC 2.19 throws "unexpected exception" when `-continue` has to rebuild many traces, so every check uses `--stop-at-first`. The run that produced this report grepped every output for that message and found none.
- `run_all.sh` wraps each run in `timeout` because `run_tlc.py --timeout` does not stop TLC on Windows. This run used `TLC_TIMEOUT=290` for the five 3-slot Queue cfgs and `TLC_TIMEOUT=160` for the rest, the same limits as run 3. None hit the limit. Five other modules were being model-checked on the same machine at the same time, so the times are not comparable with run 3.
- Don't start a second TLC run in this folder while one is running: TLC's `-cleanup` removes the shared `states/` folder and the other run fails with "when reading the disk".

| Check | Config | Result |
|---|---|---|
| Main: INV-201, INV-210 (both), REQ-233, SCN-200/202, REQ-237, REQ-239 skip rule, INV-204, REQ-242 (both properties) (1 job, 2 slots, Skip/Queue × RunOnce/Skip) | `Recurring.cfg` | passed, 482,136 distinct, 5 s |
| Main with jobs REQ-125 | `Recurring_MainR.cfg` | passed, 482,136 distinct, 5 s |
| **REQ-242** under RunOnce, Skip and RunAll, plus the main checks | `Recurring_Misfire.cfg` | passed, 722,628 distinct, 7 s |
| Definitions: REQ-211/SCN-205, INV-206/SCN-212, SCN-208, INV-211/SCN-214, REQ-236, REQ-237 (2 jobs, 2 nodes, both orphan policies) | `Recurring_Defs.cfg` | passed, 44,552 distinct, 2 s |
| Overlap, all four policies, 2 slots: REQ-233, INV-204, REQ-239 skip rule | `Recurring_OverlapAll.cfg` | passed, 653,248 distinct, 5 s |
| Overlap Queue(1), 3 slots: REQ-233, REQ-237, REQ-239 skip rule | `Recurring_OverlapQueue.cfg` | passed, 7,439,116 distinct, 93 s |
| Overlap Queue(2), 3 slots: REQ-233, REQ-239 skip rule | `Recurring_OverlapQueue2.cfg` | passed, 7,191,148 distinct, 97 s |
| Run-1 F-1: INV-204, Queue(1), 3 slots | `Recurring_F_WaitingRace.cfg` | passed, 7,439,116 distinct, 92 s |
| Run-1 F-2: probe + INV-204, Queue(2), 3 slots | `Recurring_P_QueueTwoWaiters.cfg` | passed, 7,191,148 distinct, 94 s |
| Run-1 F-5: probe, one node, 3 releases | `Recurring_P_StaleDefinition.cfg` | passed, 48,900 distinct, 1 s |
| Run-1 F-6: probe | `Recurring_P_RuntimeTakenOver.cfg` | passed, 48,900 distinct, 1 s |
| Run-1 F-7: REQ-239 skip rule | `Recurring_P_UnroutableBlocks.cfg` | passed, 653,248 distinct, 5 s |
| Run-2 F-1: INV-204, skip rule and the REQ-240 note (Skip/Queue) with jobs REQ-125 and REQ-240, all four policies | `Recurring_F_RerouteOverlap.cfg` | passed, 653,248 distinct, 5 s |
| Run-2 F-1: INV-204, REQ-233, REQ-237, skip rule and the REQ-240 note with jobs REQ-125 and REQ-240, Queue(1), 3 slots | `Recurring_F_RerouteQueue.cfg` | passed, 7,439,116 distinct, 121 s |
| Run-2 F-2: REQ-241 settling (liveness + action property), two nodes, v1/v2 | `Recurring_Liv_Settles.cfg` | passed, 36,078 distinct, 3 s |
| Run-2 F-2: same, two nodes, three releases, AllowRuntimeOverride | `Recurring_Liv_Settles3.cfg` | passed, 180,078 distinct, 15 s |
| Run-2 F-2 window (probe; REQ-241 closes it one step later) | `Recurring_P_StaleDefinition2.cfg` | probe violated, 6 states, as expected |
| Run-3 F-1: a REQ-225 start can meet an Unroutable job (probe) | `Recurring_P_Req225Unroutable.cfg` | probe violated, 5 states; now covered by REQ-240 on purpose |
| Run-3 F-2: a trigger-now Unroutable job superseded by a scheduled start (action probe) | `Recurring_P_TriggerNowSuperseded.cfg` | action probe violated, 6 states; accepted (`run_tlc.py` labels an action-property violation "error"; the TLC message is "Action property … is violated") |
| **F-1**: overdue instants leave the schedule without a trigger (action probe) | `Recurring_P_OverdueDropped.cfg` | action probe violated, 6 states |
| **F-2**: a recorded RunOnce catch-up skipped by the overlap policy (action probe) | `Recurring_P_CatchUpSkipped.cfg` | action probe violated, 5 states |
| **F-3**: two Unroutable jobs of one recurring job (probe, all four policies) | `Recurring_P_OneUnroutable.cfg` | probe violated, 6 states (Allow) |
| REQ-238 window (info) | `Recurring_F_RunningHandlers.cfg` | `Inv_NoOverlapRunning` violated, 7 states, as REQ-238 accepts |
| SCN-201, 203, 204, 206, 209 (legs `SCN209`, `SCN209b`), 210, 211, 213, 215 | `Recurring_SCNnnn.cfg` | every trap violated as expected (2–6 states): all reachable |

Deadlock checking is on in every non-scenario run, and none was found. Probes (`Probe_…`, `ProbeAct_…`) and `Note240_…` are modeling aids, not requirements. Each probe asserts that a situation is unreachable; `Note240_OneUnroutableSkipQueue` checks a claim made in REQ-240's notes. The run-3 vacuity check for `Liv_DefinitionSettles` (REQ-241 removed) was not repeated. The only model change since then is `missRec`, which no guard reads.

## Next
Apply the chosen options to `specs/recurring.json` with the `refiner-requirements` skill (it validates and diffs), then run `refiner-model` again. F-1 changes REQ-242's sentence; F-2 changes it too if option 1 is taken (merge the two snippets). F-3 is notes only. If F-1 option 1 is taken, integrations REQ-403 needs no change, because it already reads REQ-242's record.
