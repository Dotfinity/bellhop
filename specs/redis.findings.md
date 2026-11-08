# Findings: Bellhop Redis store behaviour

<!-- refiner-findings v1 | module: redis | specHash: d47dbfbc7797aeb44bfd847921dd9786bfa985f0bbdeb1f83b9630271a37dd52 | run: 2026-11-08 (run 5) | previous: specs/model/redis/previous.findings.md (run 4, specHash 71445b81e1d2) -->

**Run:** 2026-11-08, run 5 · **Requirements file:** `specs/redis.json` (specHash `d47dbfbc7797`) · **Model:** `specs/model/redis/Redis.tla` (44 cfgs from `gen_cfgs.py`) · **TLC:** 2.19. Every check ran alone with `--stop-at-first --workers 4` and a 170 s limit: 120 checks, all with the expected result, no TLC exceptions and no timeouts. The largest space is `Redis_Unique2During.cfg`, with 2,893,397 distinct states in 34 s.
**Result:** 1 finding: 0 contradictions · 1 gap · 0 unprovable · 0 ambiguities · 0 modeling notes. Both run-4 findings are resolved.

This run regenerated the reset machinery from `handoff.json`:
- REQ-507, REQ-528 and REQ-530 now fire on any read a node makes of the marker, including its claim, heartbeat and completion scripts. In the model, those reads (and, under the same words, REQ-509's clear) apply the three sentences before they use what they read (`ReadOK`).
- Glossary `resetSinceClaim` (not hashed, so re-checked by hand): the marker's last-reset value is compared with the last-reset value read at the claim. A claim now keeps that value (`claimLR`).

The run-4 switches `ReadsDetect` and `OptClaimLastReset` are now the requirements, so they were removed from the model; `Redis_HideReads.cfg`, `Redis_FreshOpt.cfg` and `Redis_LateJoinOpt.cfg` merged into `Redis_Hide.cfg`, `Redis_Fresh.cfg` and `Redis_LateJoin.cfg`. The impacted ids were re-checked: LIV-501, REQ-523, REQ-526, and SCN-500, SCN-503 to SCN-510; REQ-521 and REQ-522 for the glossary change.

**Run 4's two fixes work.** A flush is now hidden only if every node that saw the old marker made no marker read between the flush and the advance, and every run that was live at the flush has lost its lease (`Redis_Hide.cfg`, 119,197 states). On a new server no job counts as "reset since the claim" (`Redis_Fresh.cfg`), and every outcome-keeping check still passes under the new comparison (`Redis_LateJoin.cfg`, `Redis_Flush2Late.cfg`, `Redis_Flush2.cfg`).

**What is left sits under an assumption every run so far has made.** The model has always treated REQ-507's "replace the marker, by compare-and-set against what it found" as one atomic step with the read that found it (A-19). Run 4's fix made that read a script's read, so the node now reads in one round trip and writes in another. This run split the two (`SplitCAS`, a model switch) and found a way to lose the report in between (F-1). It is a narrow timing window, and the model cannot judge how narrow (no clock). But it is a late-join case again: the writes that win the race are REQ-528's first marker and REQ-527's advance of it. Run 4 said the next such case should make us question the lowest-value trick, not add a rule around it; F-1's options do both, and say what each costs.

## Changes since last run
| Finding | Status |
|---|---|
| F-1 (run 4): a flush can be hidden while the node that saw the old marker is working | resolved. With REQ-507/528/530 on every marker read, `Inv_HiddenOnlyIfPaused` and `Inv_HiddenRunsLeaseLost` pass on `Redis_Hide.cfg` (119,197) and `Redis_Hide2.cfg` (1,105,989, two jobs), with `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost` and `Inv_ConcurrencyKeyMax`. `Liv_LossReported` on `Redis_LivLateJoinAdv.cfg` still fails only by a node that makes no read (accepted, NFR-31). |
| F-2 (run 4): on a new server every job counts as "reset since the claim" | resolved. `Inv_ResetSinceClaimSound` and `Inv_NoFalseReset` pass on `Redis_Fresh.cfg` (1,096). Re-checked for REQ-521/REQ-522 under the new comparison: `Inv_NoLostOutcome` and `Inv_NoLostOutcomeLeaseLost` pass on `Redis_LateJoin.cfg` (907,278), `Redis_Flush2Late.cfg` (921,195) and `Redis_Flush2.cfg` (2,856,201); `Inv_UniqueKey`/`Inv_RecurringOverlap` on the two-flush cfgs. |
| F-1 (this run) | new |

`findings_delta.py` output (fingerprints; the first two rows use run 4's numbers):

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | gap · Inv_HiddenOnlyIfPaused · NFR-31,REQ-507,REQ-522,REQ-526,REQ-528 |
| F-2 | resolved | gap · Inv_ResetSinceClaimSound · REQ-521,REQ-528,jobs:REQ-144 |
| F-1 | new | gap · Inv_HiddenOnlyIfPaused · NFR-31,REQ-507,REQ-527,REQ-528 |

2 resolved, 1 new, 0 still open

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | gap | medium | REQ-507, REQ-527, REQ-528, REQ-509, NFR-31 | REQ-507's compare-and-set can lose to REQ-528's first marker or REQ-527's advance. The loser re-seeds silently, as if another node had reported the reset, and the flush can be hidden although that node read it |

Decide **F-1**. It is the only finding, and the choice is a design one: make the read and the write one step (option 1, recommended, closes the window by construction), patch the loser's path (option 2, checked), accept the window in NFR-31 (option 3), or drop the lowest-value trick (option 4, not checked).

---

## F-1 · gap · medium — REQ-507's compare-and-set can lose to a write that does not report
<!-- finding: gap | Inv_HiddenOnlyIfPaused | NFR-31,REQ-507,REQ-527,REQ-528 -->

**Requirements involved**
- REQ-507: *… when any read this node makes of the generation marker, including those of its claim, heartbeat and completion scripts, finds it missing, or with a value older than the last value this node saw … the system shall replace the marker, **by compare-and-set against what it found**, … log the ERROR event StoreWasReset **if its own write succeeded**, and **in either case start re-seeding** …*
- REQ-507 notes (F-9): *"the compare-and-set makes exactly one node report each reset; the others reconcile silently."*
- REQ-528: *… write the first generation marker at the lowest value … only if none exists yet … without logging StoreWasReset …*
- REQ-527: *Every RecurringReconcileInterval a worker advances the unflagged marker to the server's current time by compare-and-set against the value it remembers …* (the last-reset value is left as it is).
- REQ-528 notes and NFR-31: a flush first seen by a newly started worker goes unreported only *"if every worker that saw the previous marker is paused until the marker is next advanced"*; run 4 F-1 made "paused" mean "makes no marker read".
- TECH-130 (run 4): the scripts *"return the generation marker and last-reset value they read, so the node applies redis REQ-507, REQ-528 and REQ-530 to them before using the script's result"* — the read is in the script, the compare-and-set is the node's next command.

**What happens: the loser joins a reconciliation nobody reported** (TLC, `Redis_HideRace.cfg`, `Inv_HiddenOnlyIfPaused`, 14 steps; REQ-507's read and compare-and-set are two steps, and no LeaseDuration ends between them)
1. n1 and n2 start. n1 reads marker T0; n2 has not read it yet.
2. FLUSHALL.
3. **n1's heartbeat (or claim) script reads the marker: missing.** n1 has seen T0, so REQ-507 applies, and n1 sends its compare-and-set "against missing".
4. Before it lands, **n2 reads the marker for the first time, finds it missing and writes the first marker** at the lowest value, flagged (REQ-528). n2 logs no StoreWasReset, by design.
5. n1's compare-and-set fails: the marker is no longer missing. "In either case start re-seeding": n1 re-seeds without logging, as F-9 intends for a node that lost to another node's report. But nobody reported.
6. Both re-seed, LeaseDuration passes, n2 clears the flag (REQ-509) and advances the marker to T2 > T0 (REQ-527) before n1's next marker read.
7. Now no node can find the marker missing or older. **The flush is never reported**, although n1 read it in the window and was not paused. There is no StoreWasReset, no REQ-523 ERROR, no unacknowledged reset and no Degraded health.

A second shape (found by TLC on the same cfg in an intermediate run): n1's first read after a quiet spell finds the lowest-value marker, unflagged, older than T0; **n2's REQ-527 advance lands between n1's read and its compare-and-set**; n1's compare-and-set fails, and T2 is not older than T0, so nothing is left to detect.

Nothing else breaks: `Inv_NoFalseReset`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_ConcurrencyKeyMax` and `Inv_HiddenRunsLeaseLost` pass on `Redis_HideRace.cfg` (176,545 states), and all seven safety invariants pass with `SplitCAS` on the main run (`Redis_Race.cfg`, 626,853). Only the report is lost.

**How narrow is it?** The model has no clock, so it cannot say. Outside the model:
- Shape 1 needs n2's first-marker write to land within one round trip of n1's read, and then n1 to make no marker read until n2's advance, which comes at least one LeaseDuration later. Whether n1 reads in that time depends on something no requirement says: **does a node whose store is reconciling keep calling its claim script** (which refuses, TECH-130, but reads and returns the marker)? If it does, n1 detects within one PollInterval, and shape 1 needs n1 to stall for a lease, which is the pause NFR-31 accepts. If it does not, and n1 has no running job, n1's next read is its own REQ-509 clear, which comes about one round trip after n2's; n2's advance must fall in between.
- Shape 2 needs n2's advance to land within one round trip of n1's read.

**Why** F-9 made the compare-and-set decide who reports, on the assumption that the only competing write is another node's REQ-507, which reports. Two other writes compete for the same marker and do not report: REQ-528's first write and REQ-527's advance, and both act on exactly the lowest-value marker that late-join detection depends on. The model never saw it because A-19 made the read and the write one step; run 4's fix moved the read into scripts, which makes the gap between them concrete.

**Options**
1. *(recommended)* **One step: the script that reads the marker also makes REQ-507's (and REQ-528's) write.** The claim, heartbeat and completion scripts, and any other marker read, receive the node's last-seen value and, when REQ-507 or REQ-528 applies, write the new marker in the same script; they return whether they wrote it. Nothing can land between the read and the write, so the compare-and-set always succeeds or finds another node's report.
   - **Checked:** this is A-19. `Inv_HiddenOnlyIfPaused` and `Inv_HiddenRunsLeaseLost` pass on `Redis_Hide.cfg` and `Redis_Hide2.cfg`, and every other check of this run uses it.
   - Cost: REQ-507's write moves into the scripts TECH-130 already describes (and a small script for reads outside them). No new state, trigger or remembered value.
2. **The loser looks again.** If REQ-507's compare-and-set fails, the node applies REQ-507 to the marker the failed write returns, and if that marker's last-reset value is still the one it found (only a REQ-527 advance moved it, which keeps the last-reset value), it replaces that marker too and reports.
   - **Checked:** with this rule (`OptRetryCAS`), `Inv_HiddenOnlyIfPaused`, `Inv_HiddenRunsLeaseLost`, `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost` and `Inv_ConcurrencyKeyMax` pass on `Redis_HideRaceRetry.cfg` (164,995); the seven safety invariants pass on `Redis_RaceRetry.cfg` (626,853).
   - Cost: a second rule inside REQ-507, and the last-reset test is subtle. A simpler "retry whenever the marker is unflagged" was checked too and is wrong: a node that stalls between its read and its write past another node's whole reconciliation reports the same reset twice (`Inv_OneEventPerReset`, 15 steps).
3. **Accept and say so.** Add to NFR-31 and REQ-528's notes: *"…, or if the compare-and-set of the only worker that read it loses, within one round trip, to another node's first marker or advance."* Also say whether a reconciling node keeps calling its claim script; if it does, shape 1 shrinks to the pause NFR-31 already describes. Cheap and honest, but it adds a third way to hide a flush to a guarantee that already has two exceptions.
4. **Question the lowest-value trick (not checked).** Every late-join finding since run 2 comes from REQ-528 encoding "possibly a flush" as a marker value that REQ-527 later overwrites. The alternative: REQ-528 writes the server's time as the value too, and marks the marker as *initialised without a report*; REQ-527 keeps that mark, as it keeps the last-reset value. REQ-507 then also fires on a marker with that mark whose last-reset value is later than the last value this node saw. An advance cannot erase that evidence, so this would also close the paused-node case NFR-31 accepts. Cost: a new marker attribute, REQ-507/REQ-527/REQ-528/REQ-530 and the glossary rewritten, and a new modeling round. Worth it only if the owner wants the late-join guarantee without exceptions.

**Ready to apply (option 1)**
```json
{ "id": "REQ-507", "ears": { "where": "the worker is registered", "while": "the store is ready or reconciling",
    "when": "any read this node makes of the generation marker, including those of its claim, heartbeat and completion scripts, finds it missing, or with a value older than the last value this node saw, whether or not it is flagged as reconciling",
    "if": "this node has seen a generation marker since it started",
    "shall": "replace the marker, in the same atomic step as the read that found it, with the Redis server's current time as both its value and its last-reset value, flagged as reconciling, log the ERROR event StoreWasReset if its own write succeeded, and in either case start re-seeding the code-defined recurring jobs, the queue registry and this node's registration" } }
```
REQ-528's *"only if none exists yet"* gets the same words: *"…, flagged as reconciling, in the same atomic step as the read that found it missing, only if none exists yet, …"*. TECH-130, append: *"…; the claim, heartbeat and completion scripts, given the node's last-seen marker value, make the redis REQ-507 or REQ-528 write themselves when it applies and return whether they made it, and a node's other marker reads use a script that does the same."* With the write in the read, F-9's note ("the others reconcile silently") becomes true as written: a node's write fails only because another node's REQ-507 or REQ-528 write is already there, and REQ-507 itself then applies to that one.

---

## Checked and accepted (not findings)
| Check | Config | Result | Why it is not a finding |
|---|---|---|---|
| A late-join flush hidden while the node that saw the old marker makes no read | `Redis_LivLateJoinAdv.cfg` | `Liv_LossReported` violated (15 steps, ends stuttering) | Run-3 F-3 option 2, documented in REQ-528's notes and NFR-31; run 4 F-1 made "paused" mean "makes no marker read" |
| Rollback to older data (restore, lagging replica) | `Redis_Restore.cfg`, `Redis_RestoreOlder.cfg` | `Inv_NoLostOutcome` (10, 11 steps), `Inv_SingleClaim` (11, 12), `Inv_ConcurrencyKeyMax` (11, 12) violated | Run-2 F-5, option 2 accepted (REQ-507 and REQ-526 notes, NFR-31): a claim after the copy, or a same-marker rollback that is not detected |
| Runtime eviction (the policy changes after startup) | `Redis_Evict.cfg` | `Inv_ConcurrencyKeyMax` (12 steps), `Inv_NoLostOutcome` (11) violated | REQ-531 states that resets caused by eviction are not detected; REQ-505 refuses eviction at startup |
| A lease-lost run beside a newer claim | every cfg | excluded from `Inv_ConcurrencyKeyMax` and `Inv_SingleClaim` (A-18) | The stated rule: a run that did not heartbeat for a whole LeaseDuration has lost its lease, as under jobs REQ-132 |

## Passed checks
| Check | Config | Distinct states | Meaning |
|---|---|---|---|
| `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_UnackedUntilOperator`, `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Scn_NoClaimWhileFlagged` | `Redis.cfg` (two workers, one flush) | 348,597 each | "A detected flush ends every lease" holds for one flush, with detection on every read (run 4: 531,393; claims and heartbeats now wait for REQ-507/528/530, which removes interleavings) |
| all seven safety invariants | `Redis_Flush2.cfg` (second flush during a reconciliation) | 2,856,201 | Two flushes with the restarted REQ-509 wait |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique2During.cfg` / `Redis_Recurring2During.cfg` | 2,893,397 / 2,177,993 | Unique keys and occurrences across two flushes |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique2.cfg` / `Redis_Recurring2.cfg` (second flush after the first reconciliation) | 1,014,197 / 837,857 | An expired run is not brought back (REQ-522 under the new resetSinceClaim) |
| `Inv_SingleClaim`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost` | `Redis_Flush2Late.cfg` (two flushes, a late first look, one job) | 921,195 | REQ-521 under the new resetSinceClaim |
| all seven safety invariants | `Redis_LateJoin.cfg` | 907,278 | Run-4 F-2 fix keeps run-3 F-3's outcome fix |
| `Inv_HiddenOnlyIfPaused`, `Inv_HiddenRunsLeaseLost`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_ConcurrencyKeyMax` | `Redis_Hide.cfg` | 119,197 | Run-4 F-1 resolved: a hidden flush needs every node that saw the old marker to make no read |
| `Inv_HiddenOnlyIfPaused`, `Inv_HiddenRunsLeaseLost` | `Redis_Hide2.cfg` (two jobs) | 1,105,989 | The same with a claim beside a running job |
| `Inv_ResetSinceClaimSound`, `Inv_NoFalseReset`, `Inv_ConcurrencyKeyMax` | `Redis_Fresh.cfg` (two workers, new server) | 1,096 | Run-4 F-2 resolved; a new server is initialised, not reported (SCN-503) |
| all checks except `Inv_HiddenOnlyIfPaused` | `Redis_HideRace.cfg` (`SplitCAS`) | 176,545 | F-1 loses only the report |
| all seven safety invariants | `Redis_Race.cfg` (`SplitCAS`) | 626,853 | Splitting the read from the write breaks no safety invariant |
| all seven checks | `Redis_HideRaceRetry.cfg` / `Redis_RaceRetry.cfg` (F-1 option 2) | 164,995 / 626,853 | Option 2 closes F-1 without a false or double report |
| `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Scn_NoClaimWhileFlagged` | `Redis_Outage.cfg` / `Redis_Drop.cfg` | 1,906,584 / 1,475,436 | Outages and single-node drops during the pause |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique.cfg` / `Redis_Recurring.cfg` (one flush) | 310,693 / 265,981 | REQ-534 and the occurrence pause |
| `Inv_UniqueKey` | `Redis_Shard.cfg` | 1,240 | jobs INV-100's per-queue scope matches INV-500 |
| `Inv_NoFalseReset`, `Inv_OneEventPerReset` | `Redis_RestoreFR.cfg` | 210,590 | Rollbacks cause no false or double report |
| `Liv_Reseeded`, `Liv_MarkerWritten` (LIV-501), `Liv_LossReported`, `Liv_UnackedRestored` | `Redis_Liveness.cfg` | 33,469 | One flush: re-seeded, marker written, reported, record kept |
| `Liv_LossReported`, `Liv_UnackedRestored`, `Liv_Reseeded` | `Redis_LivFlush2.cfg` | 318,426 | Two flushes; the read guards never stall the pause |
| `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivRestore.cfg` | 392,700 | A rollback to an older marker is eventually reported |
| `Liv_Reseeded` | `Redis_LivOutage.cfg` / `Redis_LivDrop.cfg` (`Liv_LossReported` too) | 6,299 / 141,700 | No stuck pause after a reconnection |
| `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivLateJoin.cfg` | 27,450 | A late first look is reported (no advance) |
| `Liv_Reseeded` | `Redis_LivLateJoinAdv.cfg` | 96,724 | The pause always ends, with an advance too |
| `Liv_Reseeded`, `Scn_ClientNoDetect` (SCN-506) | `Redis_ClientOnly.cfg` | 10,556 | A client-only node never reconciles |
| `Inv_UnreachableIsUnhealthy`, `Inv_UnhealthyOnlyWithCause` | `Redis_Health.cfg` | 47,178 | Health precedence matches hosting |
| `Scn_NoEvalNoReady` (SCN-501) | `Redis_SCN501.cfg` | 56 | A server without EVAL never becomes ready |
| `Scn_NoClearBeforeWait` (SCN-509) / `Scn_NoRevivalAfterExpiry` (SCN-510) | `Redis_SCN509.cfg` / `Redis_SCN510.cfg` | 2,856,201 / 837,857 | Negative scenarios hold; their steps 1–3 are reachable (`Redis_SCN509Reach.cfg` 12 steps, `Redis_SCN510Reach.cfg` 15 steps) |
| SCN-500, 503, 504, 505, 507 and 508 traps violated, as expected | `Redis_SCN5xx.cfg` | 888 / 72 / 10,071 / 966 / 27,791 / 1,336 | Positive scenarios are reachable in 10, 8, 15, 10, 14 and 12 steps |

Bounded checks:
- `Redis_Flush2.cfg`, the `*2During` cfgs and SCN-509 allow the second flush only while a node is reconciling (`ActC_SecondLossDuringReconcile`).
- `Redis_Unique2.cfg`, `Redis_Recurring2.cfg` and SCN-510 allow it only after the first reconciliation has ended everywhere (`ActC_SecondLossAfterReconcile`).
- `Redis_HideRace*.cfg` keep the read-to-write window shorter than one LeaseDuration (`ActC_ShortCAS`, A-29).
- `Redis_Flush2Late.cfg` runs with one job, as in run 4. `Inv_NoFalseReset` under rollbacks is checked on `Redis_RestoreFR.cfg` (one job, one claim).

## Modeling assumptions
Decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.
| # | Assumption | Affects |
|---|---|---|
| A-1 | "The store is ready" (REQ-500) is one of the startup checks of hosting REQ-18 | REQ-500, REQ-502, REQ-505, SCN-501 |
| A-2 | (run 5) The marker reads of a worker's claim, heartbeat and completion scripts and of its REQ-509 clear apply REQ-507, REQ-528 and REQ-530 before their own effect (`ReadOK`). Other reads (REQ-527, REQ-510, plain looks) can happen at any time, so REQ-507/528/530 can also run as their own step | run-4 F-1 |
| A-3 | Re-seeding writes the recurring definitions, the queue registry and the node's registration in one step | REQ-507, REQ-528, REQ-530, LIV-500 |
| A-5 | Only `actor: system` steps are (weakly) fair, including heartbeats (jobs REQ-126), plus the passage of time (`LeaseElapses`). The server becomes unreachable at most once per run, every outage ends, and a dropped node reconnects | all liveness checks |
| A-6 | used_memory above RedisMemoryDegradedShare is a boolean that can change at any time; HealthyAfterPasses = 1 | REQ-519, REQ-520 |
| A-8 | A stopped node's run and memory disappear with it | `Redis_ClientOnly.cfg` |
| A-9 | "Processing at once" in jobs INV-108, and "holds an unexpired claim" in INV-103, mean handlers running under a claim whose lease has not expired | run-3 F-1 |
| A-10 | All model jobs share one concurrency key; with `UniqueKeys` they share one unique key; with `Recurring` they are occurrences of one recurring job with overlap Skip | run-3 F-2 |
| A-12 | A restore or failover rolls the whole server back to an image taken earlier, marker included | accepted rollback rows |
| A-14 | Job ids and lease tokens are fresh | all |
| A-16 | A refused heartbeat or completion (jobs INV-128) does not stop the handler | run-3 F-2 |
| A-17 | Without `LateJoin`, every worker has read the marker before data is lost. With `LateJoin`, at least one has; REQ-528's notes accept that a loss no running node saw goes unreported | F-1 |
| A-18 | **LeaseDuration without a clock.** See below. | every safety result |
| A-19 | REQ-507's read and its compare-and-set are one atomic step; a node that loses reads the winner's flagged value later. **F-1 is what happens without it** (`SplitCAS`), and option 1 makes it a requirement | **F-1** |
| A-21 | Only a rollback to an older marker value counts as a detectable loss in `Liv_LossReported`; same-value rollbacks and runtime evictions are documented as undetected (NFR-31, REQ-531) | `Liv_LossReported` |
| A-22 | A node remembers the last value it saw from ordinary reads, claims and its own writes (glossary `lastSeenMarker`). A heartbeat or completion that reads a newer unflagged value is the same as an ordinary read followed by the heartbeat (`Observe`), so it is not modeled separately | run-4 F-1 |
| A-24 | Marker values and last-reset values from "the Redis server's current time" (REQ-507, REQ-527, REQ-528) are a counter that every new time value increases, flushes and rollbacks included. REQ-528's lowest value is below every such value | F-1 |
| A-25 | A node "has finished a value's reconciliation" once REQ-509 found the marker at that value, cleared or already unflagged (REQ-530 notes) | REQ-530, LIV-500 |
| A-26 | A single node can lose its connection (REQ-529) while the others stay connected; its store is connecting until it reconnects, and it neither heartbeats nor completes meanwhile | `Redis_Drop.cfg`, `Redis_LivDrop.cfg` |
| A-27 | "Paused" in NFR-31 and the REQ-528 notes means the node makes no marker read between the flush and the advance (`readInWindow`) | F-1 |
| A-28 | (new) A script's read and the node's response to it (REQ-507/528/530) are ordered response-first: the claim, heartbeat or completion takes effect only once no sentence applies. The other order (claim lands, then the node detects) is the same as a claim just before the read that detects | REQ-526, REQ-522, REQ-521 |
| A-29 | (new) With `SplitCAS`, the window between REQ-507's read and its compare-and-set is shorter than one LeaseDuration (`ActC_ShortCAS`): no REQ-509 wait ends inside it. A node that stalls longer is the paused node of NFR-31 | F-1 |
| A-30 | (new) A refused claim attempt (marker missing or flagged) is not modeled as a read. Whether a reconciling node keeps calling its claim script is not stated; F-1 discusses both readings | F-1 |

**A-18 in full.** "LeaseDuration has passed since it last started re-seeding" (REQ-509) is an event, `LeaseElapses(n)`, that may happen at any time after n last started re-seeding (REQ-507, REQ-528 or REQ-530). Every run that was live when that re-seeding started, and has not renewed or re-created its record since, has gone a whole LeaseDuration without a successful heartbeat. Such a run is marked lease-lost until it ends. A claim starts a fresh lease.
- REQ-522's "leaseExpiresAt has not passed according to the database clock" is read as "not lease-lost".
- A lease can expire earlier than this, when its last heartbeat was well before the flush. That only removes re-creations, so it cannot add a violation of the invariants checked here.
- A failover to a server whose clock is behind (NFR-31) is not modeled for this test.

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
- `SplitCAS`: REQ-507's read and compare-and-set are two steps (A-19 relaxed). `TRUE` only in `Redis_HideRace*`, `Redis_Race*`.
- `OptRetryCAS`: F-1 option 2. `TRUE` only in `Redis_HideRaceRetry` and `Redis_RaceRetry`.
- `TrackHidden`: keeps the history variables of `Inv_HiddenOnlyIfPaused` and `Inv_HiddenRunsLeaseLost`. `TRUE` only in `Redis_Hide*`.

With all three `FALSE`, `casPending`, `found`, `foundLR` and the history variables stay constant; `Redis.cfg` has 348,597 states (run 4: 531,393; the claim now keeps its last-reset value).

## Next
Decide F-1: option 1 is a sentence in REQ-507 and REQ-528 and a clause in TECH-130, and it is the reading every result of this run already rests on. Apply the change to `specs/redis.json` (and TECH-130) with the `refiner-requirements` skill, then run this skill again.

These questions were already open and are unchanged by this run: one marker per hash tag under ShardByQueue (TECH-130), the StaleNodeAge value (REQ-533), and whether REQ-531 should report Unhealthy instead of an ERROR.
