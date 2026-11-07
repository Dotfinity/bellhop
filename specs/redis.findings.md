# Findings: Bellhop Redis store behaviour

<!-- refiner-findings v1 | module: redis | specHash: 71445b81e1d2faf606f7a46616926dfa060ff616a82c5c3d73234fe14c73a604 | run: 2026-11-07 (run 4) | previous: specs/model/redis/previous.findings.md (run 3, specHash 214a6f8075bb) -->

**Run:** 2026-11-07, run 4 · **Requirements file:** `specs/redis.json` (specHash `71445b81e1d2`) · **Model:** `specs/model/redis/Redis.tla` (42 cfgs from `gen_cfgs.py`) · **TLC:** 2.19. Every check ran alone with `--stop-at-first --workers 4` and a 170 s limit: 97 checks, with no TLC exceptions and no timeouts in the final set. One timeout was bounded; see *Passed checks*. The largest space is `Redis_Unique2During.cfg`, with 4,344,839 distinct states in 56 s.
**Result:** 2 findings: 0 contradictions · 2 gaps · 0 unprovable · 0 ambiguities · 0 modeling notes. All 5 run-3 findings are resolved. F-3 is resolved as decided (option 2), and this run checked what option 2 leaves open.

This run regenerated the reset machinery from `handoff.json`:
- REQ-509: the wait restarts each time the node starts re-seeding.
- REQ-522: only an unexpired lease is re-created.
- REQ-528: the first marker carries the server's time as its last-reset value.
- REQ-530: a node does not rejoin an older flagged value.
- REQ-523: wording only.
- New scenarios SCN-509 and SCN-510.

The run-3 switches `RestartWaitOnDetect`, `OptLeaseCheck` and `Prio507` are now the requirements, so they were removed from the model. The impacted ids were re-checked: LIV-501, REQ-526, REQ-532, REQ-534, and SCN-500, SCN-503, SCN-504, SCN-507 and SCN-508.

**The run-3 fixes hold together.** The F-1 fix (restart the wait) and the F-2 fix (lease test) were checked in one model, on every two-flush shape:
- second flush during a reconciliation: every safety invariant passes on `Redis_Flush2.cfg` (4,271,229 states);
- the same with unique keys (`Inv_UniqueKey`, `Redis_Unique2During.cfg`, 4,344,839) and with recurring occurrences (`Inv_RecurringOverlap`, `Redis_Recurring2During.cfg`, 3,226,799);
- second flush after the first reconciliation ended: `Redis_Unique2.cfg` (1,720,733) and `Redis_Recurring2.cfg` (1,398,965);
- two flushes and a late first look, one job: `Inv_SingleClaim`, `Inv_NoLostOutcome` and `Inv_NoLostOutcomeLeaseLost` pass on `Redis_Flush2Late.cfg` (1,513,533).

A Max = 1 key never admits a second job beside a live run, no job runs twice under a live lease, and no outcome is lost.

**F-3 option 2 fixes the lost outcome.** `Inv_NoLostOutcomeLeaseLost` passes on `Redis_LateJoin.cfg` (1,516,194), where it failed in run 3.

**The flush can still be hidden, and not only from a paused node (F-1).** REQ-528's notes and NFR-31 say a late-join flush goes unreported only if every node that saw the old marker is paused until the next advance, and that such a node's runs have lost their lease. Under the model's reading of "found" (A-2), both statements fail. The node that saw the old marker keeps claiming and heartbeating under the flushed marker and never runs REQ-507. Once the marker is advanced, nobody can detect the flush any more. If every marker read a worker already makes counts as "finding" the marker, both statements hold (`Redis_HideReads.cfg`, 127,279 states). F-2 is a smaller side effect of the same REQ-528 change: on a new server, a job counts as "reset since the claim" although no reset happened.

**The pattern, stated plainly.** Both new findings come from the same place: REQ-528's lowest-value first marker, and run 3's last-reset value on it. This is the fourth run in a row whose reset findings sit where two mechanisms meet. This time, though, neither finding needs a new mechanism:
- F-1 is fixed by saying *when* a node looks at the marker. That removes the "at some time" freedom that every late-join case since run 2 has relied on.
- F-2 is fixed by comparing like with like: a last-reset value against a last-reset value.

Both are one-clause changes, and both are model-checked. If run 5 finds another late-join case, question the lowest-value trick itself, not add another rule around it.

## Changes since last run
| Finding | Status |
|---|---|
| F-1 (run 3): a second flush caught by a reconciling node does not restart its wait | resolved. `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Inv_NoLostOutcome` and `Inv_NoLostOutcomeLeaseLost` pass on `Redis_Flush2.cfg` (4,271,229 states). SCN-509 holds (`Scn_NoClearBeforeWait`, 4,271,229), and its steps 1–3 are reachable (12 steps). |
| F-2 (run 3): a later flush brings back a run whose lease already expired | resolved. `Inv_UniqueKey` passes on `Redis_Unique2.cfg` (1,720,733) and `Inv_RecurringOverlap` on `Redis_Recurring2.cfg` (1,398,965), and both pass on the second-flush-during-reconciliation variants (above). SCN-510 holds (`Scn_NoRevivalAfterExpiry`, 1,398,965), and its steps 1–3 are reachable (15 steps). |
| F-3 (run 3): a flush only a late node saw is hidden by the next advance | resolved as decided (option 2). The lost outcome is fixed: `Inv_NoLostOutcomeLeaseLost` passes on `Redis_LateJoin.cfg` (1,516,194). The hidden flush remains, as accepted, but not only for the paused node the acceptance describes: see new F-1. |
| F-4 (run 3): REQ-507 and REQ-530 both apply to the lowest-value first marker | resolved. `Liv_LossReported` passes on `Redis_LivLateJoin.cfg` (42,552) without a precedence switch, and SCN-507 is reachable (14 steps). |
| F-5 (run 3): REQ-523's trigger also matches REQ-528's first write | resolved (wording). `Inv_NoFalseReset` passes on `Redis_Fresh.cfg` (1,096), and SCN-503 is reachable (8 steps). |
| F-1, F-2 (this run) | new |

`findings_delta.py` output (fingerprints; the first five rows use run 3's numbers):

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | contradiction · Inv_ConcurrencyKeyMax · REQ-507,REQ-509,REQ-522,REQ-526,jobs:INV-108 |
| F-2 | resolved | contradiction · Inv_RecurringOverlap · REQ-509,REQ-522,REQ-534,jobs:INV-100,recurring:INV-204 |
| F-3 | resolved | gap · Inv_NoLostOutcomeLeaseLost · REQ-507,REQ-521,REQ-527,REQ-528 |
| F-4 | resolved | ambiguity · Liv_LossReported · REQ-507,REQ-530,SCN-507 |
| F-5 | resolved | ambiguity · REQ-523 · REQ-523,REQ-528,SCN-503 |
| F-1 | new | gap · Inv_HiddenOnlyIfPaused · NFR-31,REQ-507,REQ-522,REQ-526,REQ-528 |
| F-2 | new | gap · Inv_ResetSinceClaimSound · REQ-521,REQ-528,jobs:REQ-144 |

5 resolved, 2 new, 0 still open

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | gap | high | REQ-507, REQ-522, REQ-526, REQ-528, NFR-31 | No requirement says when a node checks the marker for REQ-507. A node that saw the old marker can claim and heartbeat under the flushed marker without detecting it. The next advance then hides the flush with no node paused, and that node's run keeps its lease |
| F-2 | gap | low | REQ-521, REQ-528, glossary resetSinceClaim, jobs REQ-144 | REQ-528's last-reset time is later than the first marker's own value, so every job claimed under that marker counts as "reset since the claim" for its whole run, and REQ-521 can re-create a record an operator deleted |

Decide **F-1 first**. It breaks the guarantee that F-3 option 2 was accepted on. The flush goes unreported while the node that saw the old marker is working normally. A lost maintenance pause, lost queue pauses and lost throttle limits are then never reported. The recommended fix adds no state and no trigger: it says that the marker reads a worker already makes are the ones REQ-507 looks at. It is model-checked. F-2 is small and independent.

---

## F-1 · gap · high — A flush can be hidden while the node that saw the old marker is working
<!-- finding: gap | Inv_HiddenOnlyIfPaused | REQ-507,REQ-522,REQ-526,REQ-528,NFR-31 -->

**Requirements involved**
- REQ-507: *Where the worker is registered, while the store is ready or reconciling, **when the generation marker is found** missing, or with a value older than the last value this node saw, whether or not it is flagged as reconciling, if this node has seen a generation marker since it started, the system shall replace the marker … flagged as reconciling, log the ERROR event StoreWasReset …*
- REQ-528: *… when the generation marker is found missing, if this node has not seen a generation marker since it started, then the system shall write the first generation marker at the lowest value, with the Redis server's current time as its last-reset value, flagged as reconciling …*
- REQ-528 notes: *"The flush itself is reported only if a node that saw the earlier marker reads this one before REQ-527 advances it; **a node paused for that whole time** (more than one LeaseDuration, **so its runs are lease-lost anyway**) does not report it, and NFR-31 says so."*
- NFR-31: *"… that a flush first seen by a newly started worker is not reported **if every worker that saw the previous marker is paused until the marker is next advanced** …"*
- REQ-522 (heartbeat, *while the marker is missing or flagged*) and REQ-526 with TECH-130 (the claim script checks the marker): both read the marker. Neither says what happens when the value read is older than the one the node saw.

**What happens: a claim under the flushed marker** (TLC, `Redis_Hide.cfg`, `Inv_HiddenOnlyIfPaused`, 14 steps)
1. n1 and n2 start. n1 reads marker T0; n2 has not read it yet.
2. FLUSHALL. j1 is enqueued.
3. n2 reads first. It finds the marker missing and has never seen one, so it writes the lowest value, flagged, with last-reset time T1 (REQ-528).
4. n2 re-seeds. LeaseDuration passes, and n2 clears the flag (REQ-509).
5. **n1 claims j1.** The claim script reads the marker: it is present and not flagged, so REQ-526 allows the claim. Its value is the lowest one, older than T0, but nothing in the claim path runs REQ-507.
6. n2 advances the marker to T2 > T0 (REQ-527). **Now no node can find the marker missing or older, so the flush is never reported.** There is no StoreWasReset event, no REQ-523 ERROR, no unacknowledged reset and no Degraded health.

n1 was never paused. It read the old marker, read the new one at step 5, and claimed a job against it.

**What happens: a run keeps its lease** (TLC, `Redis_Hide.cfg`, `Inv_HiddenRunsLeaseLost`, 14 steps)
1. n1 claims j1 at marker T0. FLUSHALL; j1's record is gone.
2. n2 writes the lowest-value first marker, flagged (REQ-528).
3. **j1's heartbeat on n1 re-creates its record** (REQ-522): the marker is flagged, the record is missing, the last-reset value T1 is later than T0, and the lease has not expired. n1 reads the flagged marker here, and its value is older than T0, but REQ-507 does not run.
4. n2 re-seeds, the wait passes, the flag is cleared, and n2 advances the marker. The flush is hidden, and **j1 never lost its lease**, contrary to the REQ-528 notes.

**Why** REQ-507 says *when the marker is found*, but no requirement says when a node looks at it. The model (A-2) lets a node run REQ-507 at any time, independently of the claim, heartbeat and completion reads it already makes. So "every worker that saw the previous marker is paused" is not the only way to miss the window: a node can be busy and still never take the REQ-507 look. Before REQ-528's lowest-value marker, this did not matter. A missing or older marker stayed missing or older until somebody looked. The lowest value is the first marker condition that a later write, REQ-527's advance, erases.

**Options**
1. *(recommended)* **REQ-507 and REQ-530 look at every marker read a worker makes.** The claim, heartbeat and completion scripts already read the marker (TECH-130, REQ-522, REQ-521). Make them return it, and have the node apply REQ-507 or REQ-530 to what they found before it uses the result.
   - A worker polls for claims every PollInterval and heartbeats every HeartbeatInterval, so a worker that is not paused looks at the marker well within the REQ-509 wait of one LeaseDuration.
   - A worker that makes no read for that long has also missed every heartbeat, so its runs have lost their lease. That is exactly the case NFR-31 describes.
   - **Checked:** with this reading (`ReadsDetect`), `Inv_HiddenOnlyIfPaused`, `Inv_HiddenRunsLeaseLost`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost` and `Inv_ConcurrencyKeyMax` all pass on `Redis_HideReads.cfg` (127,279 states).
   - It adds no state, no trigger and no second remembered value. It pins down an event REQ-507 already names.
2. **A minimum check rate.** REQ-507 adds "at least once every HeartbeatInterval" to the look. This is equivalent for nodes with runs, but it adds a timer, and a node could still claim between two looks (step 5 above). Not separately checked.
3. **Accept and re-word.** NFR-31 and the REQ-528 notes drop "paused": *"a flush first seen by a newly started worker may go unreported if no worker that saw the previous marker checks it before it is advanced"*. That is honest, but the guarantee becomes "may go unreported", which is weak for a loss that silently clears a maintenance pause.

**Ready to apply (option 1)**
```json
{ "id": "REQ-507", "ears": { "where": "the worker is registered", "while": "the store is ready or reconciling",
    "when": "the generation marker is found, by any read this node makes of it including its claim, heartbeat and completion scripts, missing, or with a value older than the last value this node saw, whether or not it is flagged as reconciling",
    "if": "this node has seen a generation marker since it started",
    "shall": "replace the marker, by compare-and-set against what it found, with the Redis server's current time as both its value and its last-reset value, flagged as reconciling, log the ERROR event StoreWasReset if its own write succeeded, and in either case start re-seeding the code-defined recurring jobs, the queue registry and this node's registration" } }
```
Also add to TECH-130: *"the claim, heartbeat and completion scripts return the generation marker they read, so the node applies redis REQ-507 and REQ-530 to it before using the script's result."* REQ-528's notes and NFR-31 can stay as they are; with this change they become true.

---

## F-2 · gap · low — On a new server, every job claimed before the first advance counts as "reset since the claim"
<!-- finding: gap | Inv_ResetSinceClaimSound | REQ-521,REQ-528,jobs:REQ-144 -->

**Requirements involved**
- REQ-528 (run 4): *"… write the first generation marker at the lowest value, with the Redis server's current time as its last-reset value …"*
- Glossary `resetSinceClaim`: *"… or the marker's last-reset value is later than **the value read when the job was claimed** …"*
- REQ-521: *When a run completes or fails, its job's record no longer exists and the store was reset since the claim, the system shall write a minimal job record … marked as recreated after a store reset, and log a warning.* Its notes add: *"A record missing for any other reason is still refused."*
- jobs REQ-144: *When an application or operator deletes a job, the system shall remove the job with its history …* (from Enqueued, Failed and the other non-running states).

**What happens** (TLC, `Redis_Fresh.cfg`, `Inv_ResetSinceClaimSound`, 9 steps; a new server with no data loss at all)
1. n1 starts on an empty server and writes the first marker: the lowest value, flagged, with last-reset time T1 (REQ-528).
2. n1 re-seeds, LeaseDuration passes, and n1 clears the flag (REQ-509).
3. n1 claims j1. The value read at the claim is the lowest value.
4. **The marker's last-reset value T1 is later than the value read at the claim, so j1 counts as "reset since the claim"**, though nothing was ever lost. This stays true for j1's whole run, because REQ-527's advance leaves the last-reset value as it is.

The consequence, outside the model:
- j1's handler stalls past its lease, and jobs REQ-132 recovers the job.
- An operator then deletes it (jobs REQ-144).
- When the stale handler finishes, the record is missing and "reset since the claim" holds, so REQ-521 writes a minimal record "recreated after a store reset", with a warning.

**A deleted job comes back, and the log reports a reset that never happened.** Without REQ-528's last-reset value, the completion would be refused (jobs INV-128), as REQ-521's notes promise.

**Why** The glossary compares a *last-reset time* with a *marker value*. That works for REQ-507's markers, where both are the same time. REQ-528's first marker deliberately has a value (the lowest) that is older than its last-reset time, so the comparison is true for every claim made under it.

**Options**
1. *(recommended)* **Compare last-reset with last-reset.** The glossary clause becomes *"the marker's last-reset value is later than the last-reset value read when the job was claimed"*. The claim script already reads the marker (TECH-130), so it returns the last-reset value along with the value. **Checked:** with this change (`OptClaimLastReset`), `Inv_ResetSinceClaimSound` and `Inv_NoFalseReset` pass on `Redis_FreshOpt.cfg` (1,096 states). Run-3 F-3's lost outcome stays fixed: `Inv_NoLostOutcome` and `Inv_NoLostOutcomeLeaseLost` pass on `Redis_LateJoinOpt.cfg` (1,516,194).
2. **Accept and note it** in REQ-521: *"a job claimed before the first advance on a new server counts as reset since the claim; if it is deleted while a stale run still holds it, that run's completion re-creates it."* This is rare: it needs a stale run, a recovery and a delete, for a job claimed within one RecurringReconcileInterval of a new store's first clear. But the note would contradict "A record missing for any other reason is still refused".

**Ready to apply (option 1)**: glossary `resetSinceClaim`
```json
"resetSinceClaim": "The store was reset since a job was claimed: the generation marker is missing, flagged as reconciling, or older than the value read when the job was claimed, or the marker's last-reset value is later than the last-reset value read when the job was claimed, or this node has detected or learned of a reset since the claim (REQ-507, REQ-530). Used by REQ-521 and REQ-522 as 'the store was reset since the claim'."
```
The run's claim must then keep the last-reset value it read, next to the marker value it already keeps.

---

## Checked and accepted (not findings)
| Check | Config | Result | Why it is not a finding |
|---|---|---|---|
| A late-join flush hidden while the node that saw the old marker is paused | `Redis_LivLateJoinAdv.cfg` | `Liv_LossReported` violated (14 steps, ends stuttering) | Run-3 F-3 option 2, documented in REQ-528's notes and NFR-31. In this trace, n2 makes no marker read between the flush and the advance, and its run goes a whole lease without a heartbeat. With F-1 option 1, this is the only way left (`Redis_HideReads.cfg`). |
| Rollback to older data (restore, lagging replica) | `Redis_Restore.cfg`, `Redis_RestoreOlder.cfg` | `Inv_NoLostOutcome` (10, 11 steps), `Inv_SingleClaim` (11, 12), `Inv_ConcurrencyKeyMax` (11, 12) violated | Run-2 F-5, option 2 accepted (REQ-507 and REQ-526 notes, NFR-31). The traces have the same shape as in run 3: a claim after the copy, or a same-marker rollback that is not detected. |
| Runtime eviction (the policy changes after startup) | `Redis_Evict.cfg` | `Inv_ConcurrencyKeyMax` (12 steps), `Inv_NoLostOutcome` (11) violated | REQ-531 states that resets caused by eviction are not detected; REQ-505 refuses eviction at startup |
| A lease-lost run beside a newer claim | every cfg | excluded from `Inv_ConcurrencyKeyMax` and `Inv_SingleClaim` (A-18) | The stated rule: a run that did not heartbeat for a whole LeaseDuration has lost its lease, as under jobs REQ-132 |

## Passed checks
| Check | Config | Distinct states | Meaning |
|---|---|---|---|
| `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_UnackedUntilOperator`, `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Scn_NoClaimWhileFlagged` | `Redis.cfg` (two workers, one flush) | 531,393 each (same as run 3) | "A detected flush ends every lease" holds for one flush |
| all seven safety invariants | `Redis_Flush2.cfg` (second flush during a reconciliation) | 4,271,229 | Run-3 F-1 resolved: the restarted wait keeps Max = 1 |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique2During.cfg` / `Redis_Recurring2During.cfg` | 4,344,839 / 3,226,799 | Run-3 F-1 and F-2 fixes together, with unique keys or occurrences |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique2.cfg` / `Redis_Recurring2.cfg` (second flush after the first reconciliation) | 1,720,733 / 1,398,965 | Run-3 F-2 resolved: an expired run is not brought back |
| `Inv_SingleClaim`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost` | `Redis_Flush2Late.cfg` (two flushes, a late first look, one job) | 1,513,533 | Run-3 F-1 to F-3 fixes together |
| all seven safety invariants | `Redis_LateJoin.cfg` | 1,516,194 | Run-3 F-3 option 2: the lost outcome is fixed |
| `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost` | `Redis_LateJoinOpt.cfg` (F-2 option 1) | 1,516,194 | The F-2 fix keeps run-3 F-3's outcome fix |
| `Inv_HiddenOnlyIfPaused`, `Inv_HiddenRunsLeaseLost`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_ConcurrencyKeyMax` | `Redis_HideReads.cfg` (F-1 option 1) | 127,279 | A hidden flush then needs every node that saw the old marker to be silent for the whole window, and its runs to have lost their lease |
| `Inv_ResetSinceClaimSound`, `Inv_NoFalseReset` | `Redis_FreshOpt.cfg` (F-2 option 1) | 1,096 | No phantom "reset since the claim" on a new server |
| `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Scn_NoClaimWhileFlagged` | `Redis_Outage.cfg` / `Redis_Drop.cfg` | 2,732,328 / 2,166,996 | Outages and single-node drops during the pause |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique.cfg` / `Redis_Recurring.cfg` (one flush) | 471,673 / 393,373 | REQ-534 and the occurrence pause |
| `Inv_UniqueKey` | `Redis_Shard.cfg` | 1,240 | jobs INV-100's per-queue scope matches INV-500 |
| `Inv_NoFalseReset`, `Inv_OneEventPerReset` | `Redis_RestoreFR.cfg` | 260,176 | Rollbacks cause no false or double report |
| `Inv_NoFalseReset`, `Inv_ConcurrencyKeyMax` | `Redis_Fresh.cfg` (two workers, new server) | 1,096 | A new server is initialised, not reported (SCN-503) |
| `Liv_Reseeded`, `Liv_MarkerWritten`, `Liv_LossReported`, `Liv_UnackedRestored` | `Redis_Liveness.cfg` | 49,135 | One flush: re-seeded, marker written, reported, record kept |
| `Liv_LossReported`, `Liv_UnackedRestored`, `Liv_Reseeded` | `Redis_LivFlush2.cfg` | 460,956 | Two flushes; restarting the wait never stalls the pause |
| `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivRestore.cfg` | 591,276 | A rollback to an older marker is eventually reported |
| `Liv_Reseeded` | `Redis_LivOutage.cfg` / `Redis_LivDrop.cfg` (`Liv_LossReported` too) | 8,612 / 200,752 | No stuck pause after a reconnection |
| `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivLateJoin.cfg` | 42,552 | Run-3 F-4 resolved: a late first look is reported (no advance) |
| `Liv_Reseeded` | `Redis_LivLateJoinAdv.cfg` | 148,822 | The pause always ends, with an advance too |
| `Liv_Reseeded`, `Scn_ClientNoDetect` (SCN-506) | `Redis_ClientOnly.cfg` | 14,420 | A client-only node never reconciles |
| `Inv_UnreachableIsUnhealthy`, `Inv_UnhealthyOnlyWithCause` | `Redis_Health.cfg` | 64,386 | Health precedence matches hosting |
| `Scn_NoEvalNoReady` (SCN-501) | `Redis_SCN501.cfg` | 56 | A server without EVAL never becomes ready |
| `Scn_NoClearBeforeWait` (SCN-509) / `Scn_NoRevivalAfterExpiry` (SCN-510) | `Redis_SCN509.cfg` / `Redis_SCN510.cfg` | 4,271,229 / 1,398,965 | Negative scenarios hold; their steps 1–3 are reachable (`Redis_SCN509Reach.cfg` 12 steps, `Redis_SCN510Reach.cfg` 15 steps) |
| SCN-500, 503, 504, 505, 507 and 508 traps violated, as expected | `Redis_SCN5xx.cfg` | 1,013 / 72 / 13,246 / 1,018 / 37,911 / 1,217 | Positive scenarios are reachable in 10, 8, 15, 10, 14 and 12 steps |

Bounded checks:
- `Redis_Flush2.cfg`, the `*2During` cfgs and SCN-509 allow the second flush only while a node is reconciling (`ActC_SecondLossDuringReconcile`).
- `Redis_Unique2.cfg`, `Redis_Recurring2.cfg` and SCN-510 allow it only after the first reconciliation has ended everywhere (`ActC_SecondLossAfterReconcile`).
- `Redis_Flush2Late.cfg` with two jobs timed out at 170 s on `Inv_ConcurrencyKeyMax` and `Inv_SingleClaim`, so it runs with one job. `Inv_ConcurrencyKeyMax` across two flushes is covered by `Redis_Flush2.cfg`, and with a late first look by `Redis_LateJoin.cfg`.
- `Inv_NoFalseReset` under rollbacks is checked on `Redis_RestoreFR.cfg` (one job, one claim), as in run 3.

## Modeling assumptions
Decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.
| # | Assumption | Affects |
|---|---|---|
| A-1 | "The store is ready" (REQ-500) is one of the startup checks of hosting REQ-18 | REQ-500, REQ-502, REQ-505, SCN-501 |
| A-2 | A worker runs REQ-507, REQ-528 and REQ-530 as its own step, at any time while its store is ready or reconciling, independently of the marker reads its claim, heartbeat and completion make (no requirement gives a check interval). `ReadsDetect` is the alternative reading: those reads apply REQ-507 first | **F-1** |
| A-3 | Re-seeding writes the recurring definitions, the queue registry and the node's registration in one step | REQ-507, REQ-528, REQ-530, LIV-500 |
| A-5 | Only `actor: system` steps are (weakly) fair, including heartbeats (jobs REQ-126), plus the passage of time (`LeaseElapses`). The server becomes unreachable at most once per run, every outage ends, and a dropped node reconnects | all liveness checks |
| A-6 | used_memory above RedisMemoryDegradedShare is a boolean that can change at any time; HealthyAfterPasses = 1 | REQ-519, REQ-520 |
| A-8 | A stopped node's run and memory disappear with it | `Redis_ClientOnly.cfg` |
| A-9 | "Processing at once" in jobs INV-108, and "holds an unexpired claim" in INV-103, mean handlers running under a claim whose lease has not expired | run-3 F-1 |
| A-10 | All model jobs share one concurrency key; with `UniqueKeys` they share one unique key; with `Recurring` they are occurrences of one recurring job with overlap Skip | run-3 F-2 |
| A-12 | A restore or failover rolls the whole server back to an image taken earlier, marker included | accepted rollback rows |
| A-14 | Job ids and lease tokens are fresh | all |
| A-16 | A refused heartbeat or completion (jobs INV-128) does not stop the handler | run-3 F-2 |
| A-17 | Without `LateJoin`, every worker has read the marker before data is lost. With `LateJoin`, at least one has; REQ-528's notes accept that a loss no running node saw goes unreported | F-1, F-2 |
| A-18 | **LeaseDuration without a clock.** See below. | run-3 F-1, F-2 and every safety result |
| A-19 | The compare-and-set in REQ-507 is atomic; a node that loses it reads the winner's flagged value later | REQ-507, REQ-530 |
| A-21 | Only a rollback to an older marker value counts as a detectable loss in `Liv_LossReported`; same-value rollbacks and runtime evictions are documented as undetected (NFR-31, REQ-531) | `Liv_LossReported` |
| A-22 | A node remembers the last value it saw from ordinary reads, claims and its own writes (glossary `lastSeenMarker`) | F-1 |
| A-24 | Marker values and last-reset values from "the Redis server's current time" (REQ-507, REQ-527, REQ-528) are a counter that every new time value increases, flushes and rollbacks included. REQ-528's lowest value is below every such value | F-1, F-2 |
| A-25 | A node "has finished a value's reconciliation" once REQ-509 found the marker at that value, cleared or already unflagged (REQ-530 notes) | REQ-530, LIV-500 |
| A-26 | A single node can lose its connection (REQ-529) while the others stay connected; its store is connecting until it reconnects, and it neither heartbeats nor completes meanwhile | `Redis_Drop.cfg`, `Redis_LivDrop.cfg` |
| A-27 | "Paused" in NFR-31 and the REQ-528 notes means the node makes no marker read (claim, heartbeat, completion) between the flush and the advance (`readInWindow` in `Inv_HiddenOnlyIfPaused`) | F-1 |

**A-18 in full.** "LeaseDuration has passed since it last started re-seeding" (REQ-509) is an event, `LeaseElapses(n)`, that may happen at any time after n last started re-seeding (REQ-507, REQ-528 or REQ-530). Every run that was live when that re-seeding started, and has not renewed or re-created its record since, has gone a whole LeaseDuration without a successful heartbeat. Such a run is marked lease-lost until it ends. A claim starts a fresh lease.
- REQ-522's "leaseExpiresAt has not passed according to the database clock" is read as "not lease-lost".
- A lease can expire earlier than this, when its last heartbeat was well before the flush. That only removes re-creations, so it cannot add a violation of the invariants checked here.
- A failover to a server whose clock is behind (NFR-31) is not modeled for this test.

A-23 (run 3: the first marker has no last-reset value) is gone: REQ-528 now gives one.

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-500 to REQ-505, REQ-507 to REQ-510, REQ-512, REQ-513, REQ-519 to REQ-534 (REQ-533 absorbed), LIV-500, LIV-501, INV-500, SCN-500, SCN-501, SCN-503 to SCN-510 | REQ-506 (reporting content, no state) · REQ-511 (topology acceptance, a TECH/conformance concern) · REQ-514 (needs real durations; checked statically, run-1 F-11 resolved) · REQ-515 (node registrations by age need a clock) · REQ-516, REQ-517, INV-501, SCN-502 (strength `may`) · REQ-518 (info) |

## How to reproduce
From `specs/model/redis/`:
- `python gen_cfgs.py` writes the cfgs and removes the ones it no longer writes.
- `python run_all.py [cfg …]` runs each invariant and each property alone with `--stop-at-first --workers 4`, and enforces a 170 s limit per run. Results go to `runs/` and `run.md`, which are gitignored. Set `RUN_INDEX=name.json` to write a separate index.
- Never run two batches in the same folder at once: TLC's `-cleanup` deletes the other batch's state directories. Run the second batch from a copy of the folder.
- `python summary.py [filter]` lists finished checks. `python trace.py runs/<cfg>__<check>.json [var …]` prints a trace as changed variables per step.

Switches in the model that are not requirements:
- `ReadsDetect`: F-1 option 1. `TRUE` only in `Redis_HideReads`.
- `OptClaimLastReset`: F-2 option 1. `TRUE` only in `Redis_FreshOpt` and `Redis_LateJoinOpt`.
- `TrackHidden`: keeps the history variables of `Inv_HiddenOnlyIfPaused` and `Inv_HiddenRunsLeaseLost`. `TRUE` only in `Redis_Hide*`.

With all three `FALSE`, the run-4 variables stay constant; `Redis.cfg` has the same 531,393 states as in run 3.

## Next
Decide F-1. It is the last way found to hide a flush that the documentation does not describe, and its fix is checked. F-2 is a one-clause glossary fix. Apply the changes to `specs/redis.json` (and TECH-130) with the `refiner-requirements` skill, then run this skill again.

These questions were already open and are unchanged by this run: one marker per hash tag under ShardByQueue (TECH-130), the StaleNodeAge value (REQ-533), and whether REQ-531 should report Unhealthy instead of an ERROR.
