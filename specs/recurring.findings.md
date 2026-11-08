# Findings: Bellhop recurring jobs

<!-- refiner-findings v1 | module: recurring | specHash: 5a8b9d80683d76515031d1f076cd2d97ed5d3d355e5ff295cca716cc3d8f014b | run: 2026-11-08 (run 7) | previous: specs/model/recurring/previous.findings.md (run 6, specHash a564d3a8e001) -->

**Run:** 2026-11-08, run 7 · **Requirements file:** `specs/recurring.json` (specHash `5a8b9d80683d`) · **Model:** `specs/model/recurring/Recurring.tla`, plus `RecurringRace.tla` (rewritten for INV-212) · **TLC:** 2.19. Every check ran alone with `--stop-at-first --workers 4` and finished with no TLC exception and no timeout: 73 cfgs, up to 7,439,116 distinct states, at most 231 s each. See [How to reproduce](#how-to-reproduce).
**Result:** 3 findings: 1 contradiction · 1 gap · 0 unprovable · 1 ambiguity · 0 modeling notes. Run-6 F-1 is resolved: INV-212 holds as written for every write whose read looks only at the job's own row (pause, resume, schedule change, removal), in both orders of every race and through the reread after a lost compare-and-set. Each part of INV-212 is needed: a counterfactual without it fails. The new findings are about what the compare-and-set does not cover. A trigger compares state and nextRunAt but not maintenance, so a trigger in flight when maintenance turns on still creates its occurrence (F-1). The orphan sweep, the restore and REQ-241 decide from which nodes declare the job, so the sweep can delete a code-defined job that a node which just started declares (F-2). A definition write decides whether "the schedule changed" from what it read, so INV-212 may not cover it at all (F-3, not model-checked).

The model has no clock. It cannot judge anything that depends on real amounts of time: DST, time zones, validity windows, the 60 s misfire threshold as a number, how long REQ-242's record is kept, or how long a read-to-write window lasts. See *Coverage*.

## Changes since last run
| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | ambiguity · Prop_RecordOnlyUnhandledInstants · REQ-205,REQ-213,REQ-214,REQ-216,REQ-242 |
| F-1 | new | contradiction · Prop_NoTriggerWriteInMaintenance · INV-210,INV-212,REQ-216 |
| F-2 | new | gap · Prop_CodeJobLeavesOnlyUndeclared · INV-212,REQ-203,REQ-205,REQ-206,REQ-207,REQ-241 |
| F-3 | new | ambiguity · INV-212 scope · INV-212,REQ-204,REQ-212,REQ-227,REQ-241 |

1 resolved, 3 new, 0 still open

(Table from `findings_delta.py`; the "resolved" row uses run 6's number.) What changed in the requirements (handoff `specs/model/recurring/handoff.json`, base a564d3a8e001, resolution commit e09a5c1):
- **INV-212** (new, must): every store write that changes a recurring job's state or nextRunAt, or removes it (a trigger, a schedule change, a pause, a resume, an orphaning, a restore or a removal), is a compare-and-set on the state and nextRunAt it read. It judges due and missed instants by the database clock at that write, changes nothing if either value changed since the read, and the writer then reads the job again and decides anew.
- **REQ-216**: its compare-and-set is now "on its state and nextRunAt (INV-212)"; `dependsOn` gained INV-212.
- **REQ-242**: its write "is a compare-and-set that judges the missed instants by the database clock at that write (INV-212)"; `dependsOn` gained INV-212.
- **SCN-216** (new): a pause that loses to a trigger records no miss. **SCN-217** (new, impossibleAt 2): a trigger that loses to a pause creates no occurrence.
- Impacted, re-checked: SCN-200, SCN-201, SCN-202, SCN-206, SCN-210, SCN-211 and SCN-213 (via REQ-216).
- Read for context, not modeled: TECH-45 now extends the compare-and-set to every such write. Its notes describe a way to judge at the write: compute the missed instants from the database time of the read, and lose if a new instant has fallen due since. A write that loses that way reads again and judges then, so the outcome is the same as judging at the write, which the model does.

Model changes:
- **`Recurring.tla`, regenerated for INV-212, REQ-216 and REQ-242, same behaviour.** Each of the eight writes INV-212 names is now a guard (what its read checks) plus a `…Write` operator (what it lands): `TriggerWrite`, `UpdateWrite`, `ReapplyWrite`, `PauseWrite`, `ResumeWrite`, `OrphanWrite`, `RestoreWrite` and `RemoveWrite`. The atomic actions are the guard and the write, as before (A-2). Regression: every one of the 37 `Recurring` cfgs gives the same distinct-state count as run 6 (for example Main 1,735,656, Defs 2,586,248, OverlapQueue 7,439,116).
- **`RecurringRace.tla`, rewritten.** It extends `Recurring` and keeps every step of it. The run-6 pause-only split and its `CondPause` switch are gone. Any write in the constant `Split` is a `Read` and a later `Write`, with every `Recurring` step possible in between, including the atomic form of the same write (another operator, another node). Two ghosts per job say whether the state changed, or nextRunAt moved, since the read (A-27). Constants choose what the write compares (`CasOn`) and when it judges the missed instants (`AtWrite`), so INV-212 as written and each reading it rules out run on the same spec. A lost write changes nothing and reads again at once (A-28). Two more switches check the options of F-1 and F-2. There are new properties (`Prop_Refines`, `Prop_NoScheduledOccurrenceWhilePaused`, `Prop_NoTriggerWriteInMaintenance`, `Prop_OneOccurrencePerInstant`, `Prop_OrphanRecordsCurrentState`, `Prop_LeaveOrphanedOnlyToStateBefore`, `Prop_RestoreOnlyDeclared`, `Prop_CodeJobLeavesOnlyUndeclared`, `Liv_WriterSettles`) and the scenarios SCN-216 and SCN-217.
- **cfgs.** `Recurring_Race_Pause` (now INV-212's pause) and `…_Race_PauseCAS` (gone) are replaced by 30 `Recurring_Race_*.cfg` and 6 `Recurring_RSCN*.cfg`, all generated by `gen_cfgs.sh` except the scenario cfgs.
- **`Prop_Refines`** (`[][Next]_vars` of `Recurring`) is the strongest check: every step of the split model is a step the atomic model could take. Where it holds, every property already checked on `Recurring` with the same constants holds too, including the ones that use `ENABLED`.

How the run-6 finding was re-checked:

| Run-6 finding | Requirement change | Evidence in run 7 |
|---|---|---|
| F-1: a pause records an instant that a trigger ran in the meantime | INV-212: every such write is a compare-and-set on state and nextRunAt, judged at the write | `Prop_RecordOnlyUnhandledInstants` and all six REQ-242 properties hold with the pause split (`Recurring_Race_Pause.cfg`, 4,349,520 distinct; `…_Race_OPause.cfg`, 3,142,944, with orphaning). The run-6 trace still fails when the write is unconditional (`…_Race_CF_Pause.cfg`, 6 states). SCN-216 is reachable along its own steps (`Recurring_RSCN216a.cfg`, 3 states: the trigger lands, the pause loses and reads again) and to its end (`…_RSCN216.cfg`, 4 states). Unconditional, it is impossible (`…_RSCN216u.cfg` passes, 516,664 distinct). |

**INV-212 per write** (every as-written check below also passes `Prop_Refines`, every REQ-242 property, INV-201, INV-203, REQ-233, REQ-237, REQ-205's recorded state and REQ-206's return state, and INV-204 in the one-job cfgs; the two-node ones add the heartbeat properties. Each counterfactual fails in 5 to 12 states):

| Write | As written | Counterfactual (what fails without that part of INV-212) |
|---|---|---|
| Trigger (REQ-216) | **F-1**: lands after maintenance turns on (`Race_MainMaint`, 6 states). With F-1 option 1 everything holds (`Race_TriggerOpt`, 2,885,304). | *nextRunAt only* (REQ-216 before this run): an operator pauses in between, and the trigger creates an occurrence for the paused job, INV-201 (`Race_CF_TriggerNra`; SCN-217 fails the same way, `RSCN217n`). *State only*: another node triggers the instant in between, and this one creates a second occurrence for it, INV-203 and SCN-200 (`Race_CF_TriggerSt`). |
| Pause (REQ-214) | holds (`Race_Pause`, `Race_OPause`) | *Unconditional*: run-6 F-1 (`Race_CF_Pause`). *Judged at the read*: 02:00 passes between the read and the write, and the pause drops it with no record, REQ-242 (`Race_CF_PauseAtRead`, `Prop_LeaveRecordsMissed`). *nextRunAt only*: the orphan sweep orphans the job in between, and the pause takes it out of Orphaned into Paused, REQ-206 (`Race_CF_PauseNra`). |
| Resume (REQ-215) | holds (`Race_Resume` 4,327,920, `Race_OResume` 3,142,944) | *nextRunAt only*: orphaned in between, and the resume makes a job that no node declares active, REQ-206 (`Race_CF_ResumeNra`). |
| Schedule change by an operator (REQ-212, REQ-227) | holds (`Race_Sched`, 3,482,736) | *Unconditional*: another schedule change records the missed instant in between, and this write records it again, REQ-242 (`Race_CF_Sched`). |
| REQ-241 reapply with a schedule change | **F-2** (its node can stop before the write, `Race_ReapplyDecl`). With F-2 option 1 everything holds (`Race_ReapplyOpt`, 4,130,946). | *Unconditional*: a trigger runs the instant in between, and REQ-241 records it as dropped by the schedule change, REQ-242 (`Race_CF_Reapply`). |
| Orphan sweep (REQ-205, REQ-207) | **F-2** (`Race_OrphDecl`, 7 states). With F-2 option 1 everything holds (`Race_OrphanOpt`, 2,731,146). | *nextRunAt only*: paused in between, and the orphaning records "Active" as the earlier state, so REQ-206 later brings back as active a job the operator paused, REQ-205 (`Race_CF_OrphanNra`). |
| Restore (REQ-206) | **F-2** (`Race_RestoreDecl`). With F-2 option 1 everything holds (`Race_RestoreOpt`, 3,328,446). | *Unconditional*: restored, paused and orphaned again in between, and the write brings the job back active, which loses the pause, REQ-206 (`Race_CF_Restore`, 12 states). |
| Removal (REQ-213) | holds (`Race_Remove` 3,482,736, `Race_ORemove` 3,411,996) | *Unconditional*: a schedule change records the instant in between, and the removal records it again, REQ-242 (`Race_CF_Remove`). Also, the job is removed and a node start re-creates it as code-defined in between, and the removal deletes an active code-defined job, INV-206 (`Race_CF_RemoveRestore`). |

**The reread after a lost compare-and-set** (INV-212's last clause). `Liv_WriterSettles` holds with weak fairness of the writer's own step only (`Race_Live`, pause, resume, schedule change and removal; `Race_LiveOrph`, the scheduler's three writes): a writer that loses always reads again, and then acts or finds nothing to do. The only exception is when the job's state or nextRunAt keeps changing under it for ever. That exception is real in the model (`Race_LiveStarve`: a lasso in which an operator's pause and resume, or a trigger, land in every window), and the model cannot judge it. A window lasts a store round trip, and the next change needs either another operator action or the next due instant. INV-212 sets no bound on retries, and nothing here needs one. INV-212's notes ("a trigger that loses does nothing on its reread") hold, except that if a new instant fell due between the lost write and the reread, the reread triggers that instant, as REQ-216 says it should.

**Impacted, re-checked.** SCN-200: `Scn_SecondCasImpossible` holds in Main, MainR and Misfire, and in the race model `Prop_OneOccurrencePerInstant` holds wherever the trigger is split. Without nextRunAt in the compare-and-set, the second node creates a second occurrence (`Race_CF_TriggerSt`). SCN-202: `Inv_NoScheduleWhilePaused` and `Prop_NoScheduledOccurrenceWhilePaused` hold everywhere they run. SCN-201, SCN-206, SCN-210, SCN-211 and SCN-213 are still reachable (2 to 4 states). SCN-217 holds (`RSCN217`, 2,189,264 distinct), and its step 1 is reachable with the trigger still in flight (`RSCN217a`, 2 states).

**Also checked, not findings:**
- *Two writers in flight at once.* Each cfg splits one write at a time, and everything else stays atomic (A-28). With INV-212 a write that lands read the state and nextRunAt it lands on, so it is the same as an atomic step at that moment. Two split writers then interleave like two atomic ones. The cases where this argument fails, writes that read other data, are F-1 and F-2.
- *Creating a job* (REQ-203, REQ-208) is not in INV-212's list. It is an insert keyed by name (A-8, TECH-44's unique index), which fails if the name exists, so it is already a compare-and-set on "no row".
- *A pause during maintenance* still records the instants that fell due during maintenance as dropped by the pause (run 6, INV-210's notes allow this).

**Not checked, worth a look** (the model cannot see it): REQ-224's start of a waiting occurrence and REQ-237's skipping act on occurrence rows, not on the job's row, so INV-212 does not cover them. The model judges both at their write (A-30). If REQ-224's start read "waiting" and a pause skipped that occurrence before the start's write landed, an unconditional start would run a skipped occurrence of a paused job. REQ-224's `while an occurrence is waiting` requires the start to be conditional on the occurrence still waiting, so it is fine if the implementation does it that way. There is no requirement that is wrong here.

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | contradiction | high | INV-210, REQ-216, INV-212 | INV-212's compare-and-set covers the job's state and nextRunAt, not maintenance. A trigger that read the job before an operator turned maintenance on still lands, creating an occurrence and advancing nextRunAt while maintenance is on. |
| F-2 | gap | medium | REQ-205, REQ-207, REQ-206, REQ-241, REQ-203, INV-212 | The orphan sweep decides from which running nodes declare the job, and the compare-and-set does not cover that. A sweep in flight when a node that declares the job starts still deletes it (orphanPolicy Delete), and nothing re-creates it until the next node start. |
| F-3 | ambiguity | medium | INV-212, REQ-204, REQ-241, REQ-212, REQ-227 | Whether a definition write "changes nextRunAt" depends on whether "the schedule changed" is judged against what it read or against what is stored at the write. Judged against the read, an operator schedule edit in between is overwritten while nextRunAt stays computed from the edit (not model-checked). |

---

## F-1 · contradiction · high — A trigger in flight when maintenance turns on still creates its occurrence
<!-- finding: contradiction | Prop_NoTriggerWriteInMaintenance | INV-210,INV-212,REQ-216 -->

**Requirements involved**
- INV-210: *While the global maintenance pause is on, the system shall **never create an occurrence on schedule and never advance nextRunAt by a scheduled trigger**, so that instants missed meanwhile go through the misfire policy when maintenance ends.*
- REQ-216: ***While a recurring job is active and maintenance is off**, when its nextRunAt has passed according to the database clock, the system shall in one compare-and-set on its state and nextRunAt (INV-212), advance nextRunAt to the next occurrence after now and create the occurrence or occurrences its misfire policy calls for.*
- INV-212: *… a compare-and-set **on the state and nextRunAt it read**, which judges due and missed instants by the database clock at that write and changes nothing if either value changed since the read …*
- jobs REQ-162: *When an operator turns on the global maintenance pause, the system shall mark maintenance on.* jobs INV-114: *While maintenance is on, the system shall never claim any job on any node.*

**What happens** (TLC, `RecurringRace.tla`, `Recurring_Race_MainMaint.cfg`: `Prop_NoTriggerWriteInMaintenance` is violated in 6 states). `nightly-export` is daily at 02:00, misfire policy Skip:
1. A node starts and `nightly-export` is created, active (REQ-203).
2. 02:00:00 passes.
3. At 02:00:01 node A's scheduler reads `nightly-export`: active, maintenance off, nextRunAt passed (REQ-216's read).
4. At 02:00:01 an operator turns on maintenance for a database upgrade (jobs REQ-162).
5. A's compare-and-set lands. The state and nextRunAt are the ones it read, so INV-212's compare-and-set succeeds: nextRunAt moves to tomorrow 02:00, and the 02:00 occurrence is created and started, with its job enqueued. **Maintenance is on, and INV-210 says never.**
6. Jobs INV-114 holds the job until maintenance ends at 05:00. Then it runs, three hours late. Its misfire policy Skip would have dropped the instant had the trigger read the job after maintenance turned on (INV-210, REQ-218), and REQ-242 would have recorded it. Here nothing is recorded.

**Why** REQ-216 has two `while` conditions, the job is active and maintenance is off, and INV-212 makes the write conditional on the first only. The state is in the compare-and-set, and maintenance is a jobs-module flag in another row. So between the read and the write the job's state is protected and maintenance is not. Severity is high by the rule (a reachable state breaks a `must`). The effect is small, though: the result is the same as when the trigger lands one moment *before* maintenance turns on, which is allowed. In both cases the occurrence waits for maintenance to end and then runs, whatever the misfire policy. The atomic model cannot show this (A-2). It appears as soon as the trigger is split, and it is the only thing that fails with the trigger split: with option 1 every check passes, including `Prop_Refines` (`Recurring_Race_TriggerOpt.cfg`, 2,885,304 distinct states).

**Options**
1. *(recommended)* **The trigger's compare-and-set also requires maintenance to be off at the write.** One phrase in REQ-216. A trigger that read before maintenance turned on then loses, reads again, finds maintenance on and does nothing, and the instant goes through the misfire policy when maintenance ends, as INV-210 intends. The store reads the maintenance flag in the same statement or transaction as the compare-and-set. TECH-45 should say the same; that is in `technical-specifications.md`, outside this module.
   - **Checked:** `Recurring_Race_TriggerOpt.cfg`. `Prop_Refines`, `Prop_NoTriggerWriteInMaintenance`, INV-201, INV-203 (`Prop_OneOccurrencePerInstant`), INV-204, REQ-233, REQ-237 and all seven REQ-242 properties hold.
2. **Judge maintenance at the trigger's read and say so.** INV-210's `shall` becomes *"never create an occurrence on schedule, and never advance nextRunAt by a scheduled trigger, from a trigger that read the job while maintenance was on"*, and its notes say that a trigger already past its read when maintenance turns on completes, and its job waits for maintenance to end (jobs INV-114). Nothing changes in the code. It is the same outcome as a trigger that lands just before maintenance turns on.
3. **Make turning maintenance on wait for triggers in flight.** jobs REQ-162 would wait or fence until no trigger that read before it can still land. This is a cross-node protocol for a one-trigger window, and it belongs to the jobs module. Not recommended.

**Ready to apply (option 1, in `specs/recurring.json`)**
```json
{ "id": "REQ-216",
  "ears": {
    "while": "a recurring job is active and maintenance is off",
    "when": "its nextRunAt has passed according to the database clock",
    "shall": "in one compare-and-set on its state and nextRunAt (INV-212) that also requires maintenance to be off at that write, advance nextRunAt to the next occurrence after now and create the occurrence or occurrences its misfire policy calls for" },
  "dependsOn": ["INV-212", "INV-210"],
  "notes": "<existing notes> refiner-model 2026-11-08 run 7 F-1 (recommended option): maintenance is a separate flag that INV-212's compare-and-set does not compare, so a trigger that read the job just before an operator turned maintenance on still created its occurrence and advanced nextRunAt while maintenance was on (INV-210), and the instant skipped the misfire policy. The write now loses, and on its reread the trigger finds maintenance on and does nothing." }
```

---

## F-2 · gap · medium — The orphan sweep can delete a job that a node which has just started declares
<!-- finding: gap | Prop_CodeJobLeavesOnlyUndeclared | INV-212,REQ-203,REQ-205,REQ-206,REQ-207,REQ-241 -->

**Requirements involved**
- REQ-207: *When the scheduler finds a stored code-defined recurring job **that no running worker node declares**, if the job's orphanPolicy is Delete, the system shall remove the definition.* REQ-205 is the same event with orphanPolicy Orphan, and SCN-208 is "rolling deploy does not orphan a job an old node still declares".
- REQ-203: ***When a node with the worker registered starts** and a code-defined recurring job has no stored definition with its name, the system shall create the definition …*
- REQ-206: *When a running worker node declares an orphaned recurring job again, the system shall return the job to the state it had before …, update the stored definition and definitionHash to match **that node's code definition**, and compute nextRunAt from now.*
- REQ-241: *When the scheduler finds a stored code-defined recurring job that running worker nodes declare but whose definitionHash matches the code definition of none of them, the system shall update the stored definition and definitionHash to the code definition **of one of those nodes** …*
- INV-212: *… a compare-and-set on **the state and nextRunAt** it read …*

**What happens** (TLC, `RecurringRace.tla`, `Recurring_Race_OrphDecl.cfg`: `Prop_CodeJobLeavesOnlyUndeclared` is violated in 7 states). `weekly-report` is code-defined, active, orphanPolicy Delete. Release N declares it and N+1 does not:
1. Node A starts on N, and `weekly-report` is created (REQ-203).
2. Node A is redeployed on N+1, and node B is down. Nothing declares `weekly-report` now, and that is correct: release N+1 drops it.
3. A's orphan sweep reads `weekly-report`: active, and no running worker node declares it. Under REQ-207 it decides to remove it.
4. The deploy is rolled back: node B starts on N. `weekly-report` is stored with the same hash, so REQ-203 and REQ-204 do nothing. B now declares it.
5. A's compare-and-set lands. The state and nextRunAt are the ones it read, so it succeeds, and **`weekly-report` is deleted, although running node B declares it.**
6. Nothing creates it again. REQ-203 runs only when a node starts, and REQ-206 and REQ-241 need a stored definition. `weekly-report` does not run until some node restarts.

With orphanPolicy Orphan, the same race orphans the job (TLC, scratch cfg, 7 states), and REQ-206 restores it as soon as it runs, because B declares it. Instants that fall due in between are dropped without a record, which REQ-234 allows for an orphaned job. The restore and REQ-241 have the same shape: each takes the code definition of a node it read, and that node can stop before the write (`Race_RestoreDecl`: `Prop_RestoreOnlyDeclared` violated in 9 states; `Race_ReapplyDecl`: `Prop_StaleOnlyWhenNodeStops` violated in 8 states). Both of those heal themselves, because the next sweep or REQ-241 fixes the definition.

**Why** These three writes decide from the heartbeats (which running nodes declare the job, with which hash, REQ-205's notes), and INV-212 compares only the job's own state and nextRunAt. A node that starts changes neither of them when its code is unchanged. The atomic model hides this, because it reads and writes in one step and sees heartbeats at once (A-2, A-6). The window was there before INV-212: a node's first heartbeat is published some time after its REQ-203 runs. INV-212 does not close it, and the run-6 split, which had the pause only, could not show it. With option 1 every check passes, including `Prop_Refines` (`Race_OrphanOpt` 2,731,146, `Race_RestoreOpt` 3,328,446, `Race_ReapplyOpt` 4,130,946 distinct states).

**Options**
1. *(recommended)* **These writes also re-check the declared names at the write.** The orphan sweep (REQ-205, REQ-207), a restore (REQ-206) and REQ-241 also judge at that write which running worker nodes declare the job, and with which code definition. The write changes nothing if that changed, and the writer reads again. One clause in INV-212. The node heartbeats are in the same store, so the compare-and-set can read them. This closes the race in the model. In practice the window that remains is the delay before a node's declarations are published. To close that too, hosting must have a node publish its declared names before it applies REQ-203 and REQ-204. That belongs to the hosting module.
   - **Checked:** `Recurring_Race_OrphanOpt.cfg`, `…_RestoreOpt.cfg` and `…_ReapplyOpt.cfg` (two nodes, three releases, both orphan policies). `Prop_Refines`, `Prop_CodeJobLeavesOnlyUndeclared`, `Prop_RestoreOnlyDeclared`, `Prop_StaleOnlyWhenNodeStops`, `Prop_OrphanRecordsCurrentState`, `Prop_LeaveOrphanedOnlyToStateBefore` and all seven REQ-242 properties hold.
2. **Heal instead of prevent.** REQ-203 also fires from the scheduler: *"when a running worker node declares a code-defined recurring job that has no stored definition with its name"*. A deleted job that a running node declares then comes back with nextRunAt from now, whatever caused the deletion: this race, a late heartbeat, or an operator removing an orphan that has just been declared again (REQ-213, already reachable in the atomic model). Instants in between are lost without a record. Not model-checked.
3. **Accept and say so.** REQ-207's notes say that a job can be deleted while a node that has just started declares it, and comes back at the next node start. Notes only.

**Ready to apply (option 1, in `specs/recurring.json`)**
```json
{ "id": "INV-212",
  "ears": {
    "shall": "make every store write that changes a recurring job's state or nextRunAt, or removes the job (a trigger, a schedule change, a pause, a resume, an orphaning, a restore or a removal), a compare-and-set on the state and nextRunAt it read, which judges due and missed instants by the database clock at that write and changes nothing if either value changed since the read, and, for an orphaning, a restore or a REQ-241 update, also judges at that write which running worker nodes declare the job and with which code definition and changes nothing if that changed, after which the writer reads the job again and decides anew" },
  "dependsOn": ["REQ-216", "REQ-227", "REQ-214", "REQ-215", "REQ-205", "REQ-206", "REQ-207", "REQ-213", "REQ-242", "REQ-241"],
  "notes": "<existing notes> refiner-model 2026-11-08 run 7 F-2 (recommended option): the orphan sweep, a restore and REQ-241 decide from the heartbeats, which the compare-and-set did not cover. A sweep that read 'no node declares it' during a rollback deleted weekly-report after a node that declares it had started, and nothing re-created it until the next node start. The remaining window, before a starting node's declarations are published, is closed by hosting publishing them before REQ-203 and REQ-204 run." }
```
If you apply F-3's option 1 as well, the two clauses combine; the combined sentence is under F-3.

---

## F-3 · ambiguity · medium — Does INV-212 cover a definition write that "did not change the schedule"?
<!-- finding: ambiguity | INV-212 scope | INV-212,REQ-204,REQ-212,REQ-227,REQ-241 -->

**Requirements involved**
- INV-212: *… every store write **that changes a recurring job's state or nextRunAt** …*
- REQ-241: *… update the stored definition and definitionHash to the code definition of one of those nodes, keeping its paused or active state, and, **if the schedule changed**, compute nextRunAt from now as in REQ-227.* REQ-204 says the same at node start.
- REQ-212: *When an operator updates a runtime-defined recurring job, or a code-defined one marked AllowRuntimeOverride, the system shall store the new definition.* REQ-227: *When a recurring job's schedule changes, the system shall compute nextRunAt from now …*

**What happens** (a concrete example; not model-checked, because the model has no schedule content, A-13). `sync-crm` is code-defined with AllowRuntimeOverride, schedule every 5 minutes. A rolling deploy of release N+1 changes its payload but not its schedule:
1. REQ-241 on node A reads `sync-crm`: the stored definition is release N's, and its schedule is every 5 minutes, the same as N+1's. It decides that the schedule did not change, so its write is a plain definition update. It changes neither state nor nextRunAt, so INV-212 does not apply.
2. An operator changes `sync-crm` to daily at 06:00 (REQ-212). REQ-227 computes nextRunAt from now: tomorrow 06:00. This write is a compare-and-set (INV-212) and succeeds.
3. A's definition update lands unconditionally. The stored schedule is now N+1's, every 5 minutes, but nextRunAt is still tomorrow 06:00.
4. `sync-crm` does not run for about 20 hours (some 240 five-minute runs), and REQ-242 records nothing, because no write moved nextRunAt past those instants. After tomorrow's 06:00 trigger it runs every 5 minutes again.

The reverse order has the same shape. An operator edit that changes only the payload reads the definition, REQ-241 lands with a new schedule and nextRunAt from now, and the operator's write then restores the old schedule beside the new nextRunAt.

**Why** "Changes state or nextRunAt" is a property of the write that the writer judges from its read. INV-212's rationale ("a write that lands after another one changed either value acts on a job that no longer exists in that form") applies here: the definition write acts on a schedule that is no longer stored. But its wording excludes the write. Losing the operator's edit to new code is accepted (REQ-204's notes: last writer wins). A nextRunAt that belongs to neither stored schedule is new.

**Options**
1. *(recommended)* **Widen INV-212 to definition writes.** Every store write that changes a job's state, nextRunAt or definition is a compare-and-set on the state, nextRunAt and definition it read. The schedule-changed test of REQ-204, REQ-212 and REQ-241 then runs against what is stored at the write, because a write that loses reads again. In a store this is one row version. It could be model-checked next run by giving the definition a schedule bit.
2. **Accept and say so.** REQ-241's and REQ-204's notes say that a definition write that read the schedule before a concurrent operator edit can leave nextRunAt computed from the edited schedule until the next trigger. Notes only.
3. **Keep with nextRunAt the schedule it was computed from**, and have every trigger recompute nextRunAt from now when that is not the stored schedule. This closes the gap whatever the write order, but it adds a field and a rule.

**Ready to apply (option 1, in `specs/recurring.json`)**
```json
{ "id": "INV-212",
  "ears": {
    "shall": "make every store write that changes a recurring job's state, nextRunAt or definition, or removes the job (a trigger, a schedule change, a definition update by REQ-204, REQ-212 or REQ-241, a pause, a resume, an orphaning, a restore or a removal), a compare-and-set on the state, nextRunAt and definition it read, which judges due and missed instants by the database clock at that write and changes nothing if any of them changed since the read, after which the writer reads the job again and decides anew" },
  "dependsOn": ["REQ-216", "REQ-227", "REQ-214", "REQ-215", "REQ-205", "REQ-206", "REQ-207", "REQ-213", "REQ-242", "REQ-204", "REQ-212", "REQ-241"],
  "notes": "<existing notes> refiner-model 2026-11-08 run 7 F-3 (recommended option): whether a definition write changes nextRunAt depends on whether the schedule changed, which the writer judged from its read. A REQ-241 update that read an unchanged schedule landed after an operator's schedule edit, stored the code schedule and kept nextRunAt from the edit, so sync-crm did not run for some 20 hours and nothing was recorded." }
```
F-2 and F-3 option 1 together: *"make every store write that changes a recurring job's state, nextRunAt or definition, or removes the job (a trigger, a schedule change, a definition update by REQ-204, REQ-212 or REQ-241, a pause, a resume, an orphaning, a restore or a removal), a compare-and-set on the state, nextRunAt and definition it read, which judges due and missed instants by the database clock at that write and changes nothing if any of them changed since the read, and, for an orphaning, a restore or a REQ-241 update, also judges at that write which running worker nodes declare the job and with which code definition and changes nothing if that changed, after which the writer reads the job again and decides anew"* (`dependsOn` as in F-3 above).

---

## Accepted (not findings)
- **Run-5 F-3: a REQ-242 record that says "is waiting" is a snapshot** (REQ-242 notes). The recorded waiting occurrence can later be skipped (REQ-237) or start (REQ-224) while the record still says waiting (`Recurring_P_RecordedWaiterSkipped.cfg`, 6 states, action probe violated as expected).
- **Run-4 F-2's trace, now recorded correctly**: a RunOnce catch-up skipped by the overlap policy (`Recurring_P_CatchUpSkipped.cfg`, 5 states). The record says `Skipped`.
- **REQ-240's notes, scoped to Skip and Queue** (run-4 F-3): two Unroutable jobs of one recurring job under Allow (`Recurring_P_OneUnroutable.cfg`, 6 states). `Note240_OneUnroutableSkipQueue` holds for Skip and Queue.
- **Run-3 probes** (REQ-225 start meeting an Unroutable job; REQ-240 cancelling an Unroutable trigger-now run) and the **REQ-241 window** (`Recurring_P_StaleDefinition2.cfg`), unchanged, still reachable as documented.
- **REQ-238 (info)**: an abandoned or lease-lost handler still runs beside the next job (`Recurring_F_RunningHandlers.cfg`, 7 states).
- **A writer can lose for ever** if another write lands in every window between its read and its write (`Race_LiveStarve`). INV-212 sets no bound on retries, and the model cannot judge how likely this is (no clock). It is listed here so that nobody reads `Liv_WriterSettles` as "always finishes".

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. A-1 to A-26 are from runs 1 to 6, and changes are marked.
| # | Assumption | Affects |
|---|---|---|
| A-1 | No clock. Each job keeps a count of due instants passed since nextRunAt was set (0, 1, "2 or more"), and time passing is a nondeterministic step. "nextRunAt computed from now" resets the count to 0. | REQ-215, REQ-216, REQ-227, REQ-204, REQ-206, REQ-241, INV-210, REQ-242 |
| A-2 | *(changed)* In `Recurring.tla` each write and the read that decides it are one atomic step, so INV-200, INV-203 and SCN-200 hold by construction there. `RecurringRace.tla` drops this for the eight writes INV-212 names, except REQ-204 at node start (A-30). | INV-203, SCN-200, REQ-242, INV-212 |
| A-3 | The newest due instant is late or on time by nondeterministic choice. With two or more instants due, the older ones are always missed, which assumes the schedule interval exceeds MisfireThreshold. | REQ-217–REQ-219, REQ-234, INV-207, REQ-242 |
| A-4 | RunAll(max) is modeled with max = 1, which makes it indistinguishable from RunOnce. So REQ-242's "whether each" is checked for one occurrence. | REQ-219, REQ-242 |
| A-5 | A trigger creates at most one occurrence. | REQ-216–REQ-219 |
| A-6 | Every modeled node has the worker registered. A node declares exactly what its release declares, and "running" means up. What nodes publish in their heartbeat (declared names and each name's definition hash) is known to the scheduler at once; heartbeat expiry is not modeled. The scheduler (triggers, orphan sweep, REQ-241) and jobs REQ-125's handler registration need some running worker (hosting REQ-40). | REQ-203–REQ-207, REQ-216, REQ-241, F-2 |
| A-7 | REQ-224 is a separate system step after the earlier job finishes. | REQ-224 |
| A-8 | At node start, REQ-203 and REQ-204 (and REQ-242's schedule-change record) are applied together for every declared name. The store is keyed by name, so INV-200 and SCN-207 hold by construction, and creating a job is an insert that fails if the name exists. | REQ-203, REQ-204, INV-200, SCN-207, REQ-242, INV-212 |
| A-9 | Overlap, misfire and orphan policies are fixed per job for a whole run. | REQ-205, REQ-207, REQ-212, REQ-221–REQ-225 |
| A-10 | jobs.Job is reduced to Enqueued / Processing / Failed / Succeeded / DeadLettered / Cancelled / Unroutable plus a "handler still executing" flag (lease lost, jobs REQ-132; abandoned on timeout, jobs REQ-138/REQ-186). jobs REQ-125 (Unroutable → Enqueued) can happen whenever a worker runs. | INV-204, REQ-221–REQ-225, REQ-239, REQ-240 |
| A-11 | Occurrences whose job is final in the jobs module (not Unroutable) free their slot (modeling artefact). | all |
| A-12 | INV-204 is checked as written (`Inv_NoOverlapProcessing`, the Processing state). `Inv_NoOverlapRunning` (any executing handler) is kept only to show the window REQ-238 accepts. | INV-204, REQ-238 |
| A-13 | definitionHash is the hash of the code definition last applied. A runtime edit under AllowRuntimeOverride changes the stored definition but not the hash, so REQ-241 never fires because of a runtime edit. The definition has no schedule content: "the schedule changed" is a nondeterministic choice, so F-3 cannot be checked. | REQ-204, REQ-212, REQ-241, F-3 |
| A-14 | Configuration-defined jobs are not modeled (INV-209 and REQ-232 are `may`), so REQ-236 is checked for code-defined names only. | INV-209, REQ-232, REQ-236 |
| A-15 | The same-trigger warnings from `validate` (REQ-222/REQ-223/REQ-225/REQ-235 with REQ-221; REQ-205/REQ-207) are each one action, with complementary and exhaustive guards. REQ-242 is an `invariant` with a `when` clause; it is modeled as one more consequence of the trigger, schedule-change, pause, orphan and removal events, not as a state predicate. | REQ-242 |
| A-16 | REQ-236's and REQ-210's "fail the host's start" is abstracted as the node staying down. The hosting module owns the node's states. | REQ-236 |
| A-17 | One switch remains: `RerouteOn` explores jobs REQ-125 only in `MainR`, `F_RerouteOverlap`, `F_RerouteQueue` and SCN-215, so the run-1 fixes and the Unroutable rules are judged separately. The race cfgs have it off. | INV-204, REQ-240 |
| A-18 | REQ-240 is applied to every start: REQ-221, REQ-224 and REQ-225 (Allow and CancelPrevious). "Earlier" means created before, in creation order. Confirmed by the owner (run-3 F-1). | REQ-240, REQ-225 |
| A-19 | REQ-240's start and cancel are one atomic step, so jobs REQ-125 cannot return the job to Enqueued between them. | REQ-240, INV-204 |
| A-20 | REQ-241 is a reconciliation step, not a scheduled trigger, so INV-210 does not stop it during maintenance. Whether the schedule changed is a nondeterministic choice, as in REQ-204. | REQ-241, INV-210 |
| A-21 | REQ-242's record is abstracted to, per name, a count of records (0, 1, "2 or more"), how the latest one says the instants were handled (`Started` / `Waiting` / `Skipped` naming the occurrence created in that write, `Misfire`, `Schedule`, `Pause`, `Orphan` or `Removed`), and that occurrence. "First, last and how many" are not modeled. The count is never reset: the model has no retention, and a record outlives a removed or orphaned job, kept per name. At "2 or more" a further record of the same kind is invisible, so the "exactly one record" checks are weak there. | REQ-242 |
| A-22 | `missRec` is written only by `TriggerWrite`, the schedule-change writes, `PauseWrite`, `OrphanWrite` and `RemoveWrite` (atomic or split), and read by no guard or update, so states that differ only in it have the same futures. The five 3-slot Queue cfgs, which check nothing about REQ-242, use `VIEW ViewNoRec`. Every other cfg explores `missRec` in full. | checks in the Queue cfgs |
| A-23 | "Missed" for a trigger is REQ-234's first clause: an instant more than MisfireThreshold late. A trigger with only the newest instant late records a miss; with only an on-time newest instant it records nothing. | REQ-242, REQ-234 |
| A-24 | Schemas are not modeled. The initial store holds no recurring job, which is what REQ-236 says a store without a Bellhop schema holds. | REQ-236 |
| A-25 | REQ-234's second clause: while a job is Active, the count of A-1 is exactly the instants that fell due while it was active (every way into Active resets it), so any step other than a trigger that moves nextRunAt from now, or takes the job out of Active, while the count is at least 1, passes over missed instants (`HasMissed`). | REQ-234, REQ-242 |
| A-26 | *(rewritten)* In `RecurringRace.tla` a split write is a read, which checks the atomic action's guard and keeps what the write will use (for the trigger, under read-judging, whether the newest instant is late; for a restore or REQ-241, the code definition of the node it chose), and a later write. With INV-212 the write compares the state and nextRunAt, and judges `HasMissed`, the trigger's due count and lateness at the write. The read decides only which write it is. An orphaning records the state it read, which is the current one when the state is compared. A write whose row is gone does nothing, even unconditionally (an update that finds no row). | INV-212, F-1, F-2 |
| A-27 | *(new)* The compare-and-set is modeled by two ghosts per job: the state changed, and nextRunAt moved, since the read. nextRunAt "moves" when the due count goes down, or when the job enters Active, leaves Orphaned or is removed (each computes nextRunAt from now or deletes the row). A schedule change while the count is already 0 is not seen as a move. That change leaves a state that no write in the model decides differently on. With both values compared, either ghost dooms the write, so the two are kept as one. | INV-212 |
| A-28 | *(new)* Each cfg splits one write, and at most one split write per job is in flight. Every other write, including another copy of the same one, is atomic and can land in between. A lost write and its reread are one step: the lost write changes nothing, so a step between the two is the same as a step before the lost write. Two split writers at once are argued, not checked (see *Also checked*). | INV-212 |
| A-29 | *(new)* The scheduler's writes (trigger, orphan sweep, restore, REQ-241) run on a node. When a node stops, a write in flight may be lost, and when no node runs it is lost. Operator writes are never lost. Nothing lands after its writer is gone. | INV-212, liveness |
| A-30 | *(new)* Not split: REQ-204 at node start (one step for every declared name, A-8; its write is the same as REQ-241's, which is split), definition writes that change no schedule (not INV-212 writes as worded, F-3), creating a job (A-8), REQ-226's trigger-now (INV-212's notes), and the occurrence writes of REQ-224 and REQ-237. The skipping of REQ-237 inside a pause, orphaning or removal applies to the occurrences still waiting at the write. | REQ-204, REQ-224, REQ-226, REQ-237, F-3 |
| A-31 | *(new)* For `Liv_WriterSettles` only the writer's own step is weakly fair (an in-flight call is the system's to finish); nothing else is assumed fair. | INV-212 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-201–REQ-208, REQ-211–REQ-227, REQ-233–REQ-237, REQ-239–REQ-242, INV-200, INV-201, INV-203, INV-204, INV-206, INV-207, INV-210, INV-211, INV-212, SCN-200–SCN-217 | REQ-200, REQ-228, REQ-229, REQ-230, INV-202, INV-208 (need a real clock: time zones, DST, validity window) · REQ-209, REQ-210 (schedule/time-zone validity not representable) · INV-205 (no exceptions or lock waits in the model) · REQ-231 (bookkeeping, nothing depends on it) · REQ-232, INV-209 (strength `may`) · REQ-238 (`info`; shown by `Inv_NoOverlapRunning`) |

Some modeled items are not judged:
- In `Recurring.tla`, INV-200, INV-203, SCN-200 and SCN-207 hold by construction (A-2, A-8). In `RecurringRace.tla`, INV-203 is checked (`Prop_OneOccurrencePerInstant`), and it holds because nextRunAt is compared: it fails without that (`Race_CF_TriggerSt`).
- INV-212 is checked for one split write at a time (A-28), and for definition writes only where they change the schedule (F-3, A-13).
- REQ-242's retention ("as long as dead-lettered jobs are kept") needs a clock. Its "first, last and how many" are not modeled (A-21).
- REQ-219 and REQ-242's "whether each" are modeled only with max = 1 (A-4).
- REQ-236 is checked for code-defined names only (A-14).
- REQ-241's settling is checked as "eventually", not "within a time". A writer that loses is checked to settle unless interfered with for ever, not within a number of retries.
- The cancel reason Superseded (REQ-240) is not modeled.

## How to reproduce
From `specs/model/recurring`: `sh gen_cfgs.sh` regenerates the non-scenario cfgs, and `sh run_all.sh` reruns every check below. Each check is one `run_tlc.py <module> --config <cfg> --stop-at-first` call, where the module is `Recurring.tla`, or `RecurringRace.tla` for the `Race_*` and `RSCN*` cfgs. Scenario, race and `RSCN*` cfgs add `--no-deadlock`. `run_all.sh <name>` runs one check. `TLC_WORKERS` (default 4) and `TLC_TIMEOUT` (default 400 s) set the workers and the per-run limit. A TLC still running after the limit is killed, because `run_tlc.py`'s timeout does not stop it on Windows. The `run*.json`/`run*.md` outputs and `run_all.log` are gitignored.

- TLC 2.19 throws "unexpected exception" when `-continue` has to rebuild many traces, so every check uses `--stop-at-first`. The run that produced this report grepped every output for that message and found none.
- This run used `TLC_WORKERS=4 TLC_TIMEOUT=400`, with three other modules being model-checked on the same machine, so the times are not comparable with run 6. No final check hit the limit. A first attempt that split five writes in one cfg passed 400 s and was replaced by one cfg per write (A-28).
- Don't start a second TLC run in this folder while one is running: TLC's `-cleanup` removes the shared `states/` folder, and the other run fails with "when reading the disk". The race checks ran from scratch copies of this folder for that reason, with identical `.tla` and `.cfg` files; the copies were then deleted, and their outputs copied here.
- The trace of F-2 under orphanPolicy Orphan came from a scratch copy of `Recurring_Race_OrphDecl.cfg` with `OrphanPolicies = {"Orphan"}` (7 states), then deleted. It is not part of `run_all.sh`.

| Check | Config | Result |
|---|---|---|
| Main: INV-201, INV-210 (both), REQ-233, SCN-200/202, REQ-237, REQ-239 skip rule, INV-204, REQ-242 (six properties) (1 job, 2 slots, Skip/Queue × RunOnce/Skip) | `Recurring.cfg` | passed, 1,735,656 distinct, 25 s |
| Main with jobs REQ-125 | `Recurring_MainR.cfg` | passed, 1,735,656 distinct, 22 s |
| **REQ-242** under RunOnce, Skip and RunAll, plus the main checks | `Recurring_Misfire.cfg` | passed, 2,886,396 distinct, 40 s |
| Definitions: REQ-211/SCN-205, INV-206/SCN-212, SCN-208, INV-211/SCN-214, REQ-236, REQ-237, REQ-242 at node start, orphaning and removal (2 jobs, 2 nodes, both orphan policies) | `Recurring_Defs.cfg` | passed, 2,586,248 distinct, 94 s |
| Overlap, all four policies, 2 slots: REQ-233, INV-204, REQ-239 skip rule | `Recurring_OverlapAll.cfg` | passed, 2,395,024 distinct, 20 s |
| Overlap Queue(1), 3 slots: REQ-233, REQ-237, REQ-239 skip rule | `Recurring_OverlapQueue.cfg` | passed, 7,439,116 distinct, 103 s |
| Overlap Queue(2), 3 slots: REQ-233, REQ-239 skip rule | `Recurring_OverlapQueue2.cfg` | passed, 7,191,148 distinct, 91 s |
| Run-1 F-1: INV-204, Queue(1), 3 slots | `Recurring_F_WaitingRace.cfg` | passed, 7,439,116 distinct, 83 s |
| Run-1 F-2: probe + INV-204, Queue(2), 3 slots | `Recurring_P_QueueTwoWaiters.cfg` | passed, 7,191,148 distinct, 82 s |
| Run-1 F-5: probe, one node, 3 releases | `Recurring_P_StaleDefinition.cfg` | passed, 151,500 distinct, 2 s |
| Run-1 F-6: probe | `Recurring_P_RuntimeTakenOver.cfg` | passed, 151,500 distinct, 2 s |
| Run-1 F-7: REQ-239 skip rule | `Recurring_P_UnroutableBlocks.cfg` | passed, 2,395,024 distinct, 16 s |
| Run-2 F-1: INV-204, skip rule and the REQ-240 note (Skip/Queue) with jobs REQ-125 and REQ-240, all four policies | `Recurring_F_RerouteOverlap.cfg` | passed, 2,395,024 distinct, 19 s |
| Run-2 F-1: INV-204, REQ-233, REQ-237, skip rule and the REQ-240 note with jobs REQ-125 and REQ-240, Queue(1), 3 slots | `Recurring_F_RerouteQueue.cfg` | passed, 7,439,116 distinct, 106 s |
| Run-2 F-2: REQ-241 settling (liveness + action property) and REQ-242, two nodes, v1/v2 | `Recurring_Liv_Settles.cfg` | passed, 94,146 distinct, 8 s |
| Run-2 F-2: same, two nodes, three releases, AllowRuntimeOverride | `Recurring_Liv_Settles3.cfg` | passed, 468,546 distinct, 44 s |
| Run-2 F-2 window (probe; REQ-241 closes it one step later) | `Recurring_P_StaleDefinition2.cfg` | probe violated, 4 states, as expected |
| Run-3 F-1: a REQ-225 start can meet an Unroutable job (probe) | `Recurring_P_Req225Unroutable.cfg` | probe violated, 5 states; covered by REQ-240 on purpose |
| Run-3 F-2: a trigger-now Unroutable job superseded by a scheduled start (action probe) | `Recurring_P_TriggerNowSuperseded.cfg` | action probe violated, 6 states; accepted (`run_tlc.py` labels an action-property violation "error") |
| Run-4 F-1 regression: overdue instants dropped by a schedule change are recorded | `Recurring_F_OverdueRecorded.cfg` | passed, 151,500 distinct, 3 s |
| Run-4 F-2: a RunOnce catch-up skipped by the overlap policy (action probe; the record says `Skipped`) | `Recurring_P_CatchUpSkipped.cfg` | action probe violated, 5 states, as expected |
| Run-4 F-3: two Unroutable jobs of one recurring job (probe, all four policies) | `Recurring_P_OneUnroutable.cfg` | probe violated, 6 states (Allow); the notes say so |
| Run-5 F-1 regression: missed instants recorded at a pause or an operator removal | `Recurring_F_OverduePaused.cfg` | passed, 1,735,656 distinct, 19 s |
| Run-5 F-1 regression: ... and at an orphaning or a delete by the orphan sweep | `Recurring_F_OverdueOrphaned.cfg` | passed, 199,146 distinct, 4 s |
| Run-5 F-2 regression: a just-passed instant dropped by a schedule change is recorded | `Recurring_F_PassedInstant.cfg` | passed, 1,735,656 distinct, 15 s |
| Run-5 F-3 (accepted): a record saying "waiting", then REQ-237 skips that occurrence (action probe) | `Recurring_P_RecordedWaiterSkipped.cfg` | action probe violated, 6 states, as expected |
| REQ-238 window (info) | `Recurring_F_RunningHandlers.cfg` | `Inv_NoOverlapRunning` violated, 7 states, as REQ-238 accepts |
| SCN-201, 203, 204, 206, 209 (legs `SCN209`, `SCN209b`), 210, 211, 213, 215 | `Recurring_SCNnnn.cfg` | every trap violated as expected (2–4 states): all reachable |
| **INV-212** (`RecurringRace.tla`, 1 job, 2 slots, Skip/Queue × RunOnce/Skip): pause / resume / operator schedule change / removal split, every check incl. `Prop_Refines` | `Recurring_Race_Pause.cfg`, `…_Resume`, `…_Sched`, `…_Remove` | passed: 4,349,520 / 4,327,920 / 3,482,736 / 3,482,736 distinct, 110–156 s |
| **INV-212**, two nodes, three releases, both orphan policies: pause / resume / removal split, every check incl. `Prop_Refines` and the heartbeat properties | `Recurring_Race_OPause.cfg`, `…_OResume`, `…_ORemove` | passed: 3,142,944 / 3,142,944 / 3,411,996 distinct, 191–203 s |
| **F-1**: the trigger split as written | `Recurring_Race_MainMaint.cfg` | `Prop_NoTriggerWriteInMaintenance` violated, 6 states |
| **F-1 option 1**: the trigger split, its write also requires maintenance off, every check | `Recurring_Race_TriggerOpt.cfg` | passed, 2,885,304 distinct, 87 s |
| **F-2**: orphan sweep, restore and REQ-241 split as written | `Recurring_Race_OrphDecl.cfg`, `…_RestoreDecl`, `…_ReapplyDecl` | `Prop_CodeJobLeavesOnlyUndeclared` violated, 7 states; `Prop_RestoreOnlyDeclared`, 9; `Prop_StaleOnlyWhenNodeStops`, 8 |
| **F-2 option 1**: orphan sweep / restore / REQ-241 split, their write also re-checks the declared names, every check | `Recurring_Race_OrphanOpt.cfg`, `…_RestoreOpt`, `…_ReapplyOpt` | passed: 2,731,146 / 3,328,446 / 4,130,946 distinct, 154–231 s |
| INV-212's reread: a writer that loses acts or finds nothing to do, unless interfered with for ever (liveness) | `Recurring_Race_Live.cfg`, `…_LiveOrph` | passed, 47,442 / 27,774 distinct, 3 s |
| ... without the escape clause (accepted) | `Recurring_Race_LiveStarve.cfg` | `Liv_WriterSettlesAlways` violated (lasso), as expected |
| Counterfactuals, one per part of INV-212 (table *INV-212 per write*) | `Recurring_Race_CF_*.cfg` (12) | each violated as expected, 5–12 states |
| **SCN-216**: along its own steps (leg a) and to its end | `Recurring_RSCN216a.cfg`, `…_RSCN216` | trap violated, 3 and 4 states: reachable |
| SCN-216 with the run-6 unconditional pause | `Recurring_RSCN216u.cfg` | passed, 516,664 distinct: impossible, as run-6 F-1 said |
| **SCN-217** (impossibleAt 2) | `Recurring_RSCN217.cfg` | passed, 2,189,264 distinct, 44 s |
| SCN-217 step 1 reachable; SCN-217 with a compare-and-set on nextRunAt only | `Recurring_RSCN217a.cfg`, `…_RSCN217n` | trap violated, 2 states; `Scn217_TriggerLosesToPause` violated, 3 states |

Deadlock checking is on in every run of `Recurring.tla` except the scenario runs, and none was found. Probes (`Probe_…`, `ProbeAct_…`) and `Note240_…` are modeling aids, not requirements. Each probe asserts that a situation is unreachable; `Note240_OneUnroutableSkipQueue` checks a claim made in REQ-240's notes. The `Race_CF_*` cfgs and `RSCN216u` / `RSCN217n` check readings that INV-212 rules out, to show that each part of it does something.

## Next
Decide F-1 first. It is the only one where a reachable state breaks a `must` as written, and both cheap options are one phrase: option 1 in REQ-216, or option 2 in INV-210. Then F-2 and F-3, which both change INV-212's sentence. F-2's option 1 also needs a line in the hosting module, and F-1's option 1 a line in TECH-45 (`technical-specifications.md`). Apply changes with `refiner-requirements`, then run `refiner-model` again. F-3's option 1 can be model-checked next run by giving the definition a schedule bit.
