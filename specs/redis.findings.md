# Findings: Bellhop Redis store behaviour

<!-- refiner-findings v1 | module: redis | specHash: fb9a582eac88b10894a48db443960a05d217c328fd46a73780562b87006febf3 | run: 2026-11-08 (run 6) | previous: specs/model/redis/previous.findings.md (run 5, specHash d47dbfbc7797) -->

**Run:** 2026-11-08, run 6 · **Requirements file:** `specs/redis.json` (specHash `fb9a582eac88`) · **Model:** `specs/model/redis/Redis.tla` (42 cfgs from `gen_cfgs.py`) · **TLC:** 2.19. Every check ran alone with `--stop-at-first --workers 2` and a 170 s limit: 95 checks, all with the expected result, no timeouts. One run (SCN-508) hit a transient TLC parse failure ("Module-Table lookup failure") and passed when rerun alone; there was no other TLC exception. Three other modules were being checked on the same machine. The largest space is `Redis_Unique2During.cfg`, with 2,893,397 distinct states in 65.2 s.
**Result:** 1 finding: 0 contradictions · 0 gaps · 0 unprovable · 1 ambiguity · 0 modeling notes. Run 5's only finding is resolved.

This run regenerated the marker writes from `handoff.json` (base 55ee2c4, resolution commit e316e1f):
- REQ-507 now replaces the marker *in the same atomic step as the read that found it*. It has no compare-and-set, and the node always logs StoreWasReset. REQ-528 writes the first marker in the same atomic step as the read that found it missing; "only if none exists yet" is gone because it holds by construction. TECH-130 says the scripts make that write and return whether they did.
- In the model this is A-19, which every run so far assumed: `DetectReset` and `InitMarker` stay one step. The run-5 option switch `OptRetryCAS` and its cfgs (`Redis_HideRaceRetry.cfg`, `Redis_RaceRetry.cfg`) are removed, and so is `Redis_Race.cfg`, which only showed that the split broke no safety invariant. `SplitCAS` stays as a labelled counterfactual for the run-5 wording (`Redis_HideRace.cfg`).
- The impacted ids were re-checked: LIV-501, REQ-523, REQ-526, REQ-530, SCN-500 and SCN-503 to SCN-510. Re-checking REQ-523 raised F-1.

**The change works.** With the read and the write in one step, a flush is hidden only if every node that saw the old marker made no marker read between the flush and the advance, and every run that was live at the flush has lost its lease (`Redis_Hide.cfg`, 119,197 states; `Redis_Hide2.cfg`, two jobs, 1,105,989). Exactly one node reports each reset (`Inv_OneEventPerReset`), and none reports a reset that did not happen (`Inv_NoFalseReset`), on the main run, two flushes, a late first look and rollbacks. The run-5 wording, kept as a counterfactual, still loses the report (`Redis_HideRace.cfg`, 14 steps): n1 reads the missing marker, n2's first marker (REQ-528) lands before n1's compare-and-set, n1 loses and re-seeds silently, and n2's advance (REQ-527) then hides the flush.

**Nothing new from the atomic write itself.** REQ-509's clear and REQ-527's advance are conditional writes on a value the node holds, and neither can overwrite a REQ-507 write: the clear acts only on the value this reconciliation is for, and the advance only on the value the node remembers, which is always older than a REQ-507 value (A-24). Under ShardByQueue the model has no data loss (`Redis_Shard.cfg`), so per-tag markers are still not checked. The TECH-130 open question stands.

## Changes since last run
| Finding | Status |
|---|---|
| F-1 (run 5): REQ-507's compare-and-set can lose to a write that does not report | resolved. REQ-507 and REQ-528 make their write in the same atomic step as the read. `Inv_HiddenOnlyIfPaused` and `Inv_HiddenRunsLeaseLost` pass on `Redis_Hide.cfg` (119,197) and `Redis_Hide2.cfg` (1,105,989); `Inv_OneEventPerReset` and `Inv_NoFalseReset` pass on `Redis.cfg` (348,597), `Redis_Flush2.cfg`, `Redis_LateJoin.cfg` and `Redis_RestoreFR.cfg`. The run-5 wording, kept as the counterfactual `Redis_HideRace.cfg`, still fails in 14 steps. |
| F-1 (this run) | new |

`findings_delta.py` output (fingerprints; the first row uses run 5's number):

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | gap · Inv_HiddenOnlyIfPaused · NFR-31,REQ-507,REQ-527,REQ-528 |
| F-1 | new | ambiguity · Inv_UnackedUntilOperator/Req523Literal · REQ-507,REQ-523 |

1 resolved, 1 new, 0 still open

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | ambiguity | medium | REQ-523, REQ-507 | REQ-523 fires "when this node's compare-and-set in REQ-507 succeeds", but REQ-507 no longer makes a compare-and-set. Read literally, no reset is ever recorded as unacknowledged, and health never shows it |

Decide **F-1**. It is the only finding, and it is one phrase.

---

## F-1 · ambiguity · medium — REQ-523's trigger names a compare-and-set that REQ-507 no longer makes
<!-- finding: ambiguity | Inv_UnackedUntilOperator/Req523Literal | REQ-507,REQ-523 -->

**Requirements involved**
- REQ-523: *When **this node's compare-and-set in REQ-507 succeeds**, the system shall log an ERROR saying that runtime-defined recurring jobs, the maintenance pause, queue pauses, runtime throttle limits and recurring-job pauses may have been lost and are back at their defaults, record the reset as unacknowledged in the store, and remember it until it finds the reset acknowledged.*
- REQ-507 (changed in e316e1f): *… the system shall replace the marker, **in the same atomic step as the read that found it**, with the Redis server's current time as both its value and its last-reset value, flagged as reconciling, log the ERROR event StoreWasReset, and start re-seeding …* There is no compare-and-set left in it.
- REQ-524 (health Degraded while a reset is unacknowledged), REQ-525 (operator acknowledges), REQ-532 (re-write a lost record) and SCN-500 (*"the reset is recorded as unacknowledged and health reports Degraded"*) all depend on REQ-523's record.

**What happens** (TLC, `Redis_Req523Literal.cfg`, `Inv_UnackedUntilOperator`, 9 steps; REQ-523 read literally, so its trigger never occurs)
1. Nodes n1 and n2 connect, are marked running and read the marker (REQ-500, hosting REQ-18).
2. FLUSHALL.
3. n1's next marker read finds it missing. n1 has seen a marker, so REQ-507 applies: n1 replaces the marker in the same step, logs StoreWasReset and starts re-seeding.
4. **No compare-and-set was made, so REQ-523's trigger did not happen.** There is no ERROR about lost runtime state, no unacknowledged record and nothing for n1 to remember. A reset has been detected, no operator has acknowledged it, and the store does not say it is unacknowledged.

From there, REQ-524 never reports Degraded for it, REQ-525 has nothing to acknowledge, and REQ-532 has nothing to re-write. SCN-500's expected outcome ("recorded as unacknowledged", health Degraded) depends on that record.

**Why** e316e1f removed the compare-and-set from REQ-507 and left REQ-523's trigger pointing at it. Run 5 had already modeled REQ-523 as "this node's REQ-507 write succeeded", the only reading that keeps it alive. That is still what the model does, and with it every check of this run passes (`Inv_UnackedUntilOperator` on `Redis.cfg` and `Redis_Flush2.cfg`; SCN-500 is reachable). Read literally, though, REQ-523 has no event. The diff listed REQ-523 as impacted because it mentions REQ-507; its sentence was not part of the change.

**Options**
1. *(recommended)* **Name the event REQ-507 now has:** "When this node replaces the generation marker under REQ-507, …". It says what the model already checks. REQ-507 always succeeds in replacing the marker now, so exactly one node per reset records it (`Inv_OneEventPerReset`). Cost: one phrase.
2. **Fold REQ-523 into REQ-507's shall.** One sentence would carry the replacement, both ERRORs, the record and the memory. REQ-507 is already the longest sentence in the module, and REQ-532 refers to REQ-523's record by id, so this moves more text for no gain.
3. **Leave it, and say so in REQ-523's notes** that "compare-and-set" means the write REQ-507 makes. The semantic sentence would still name a step that no longer exists, and the next reader or modeling run trips over it again.

**Ready to apply (option 1)**
```json
{ "id": "REQ-523", "ears": {
    "when": "this node replaces the generation marker under REQ-507",
    "shall": "log an ERROR saying that runtime-defined recurring jobs, the maintenance pause, queue pauses, runtime throttle limits and recurring-job pauses may have been lost and are back at their defaults, record the reset as unacknowledged in the store, and remember it until it finds the reset acknowledged" },
  "notes": "<existing notes> refiner-model 2026-11-08 run 6 F-1: REQ-507 has no compare-and-set since redis run 5 F-1; its replacement of the marker, atomic with the read that found it, is the event. Exactly one node makes it per reset, so exactly one node records it." }
```

---

## Checked and accepted (not findings)
| Check | Config | Result | Why it is not a finding |
|---|---|---|---|
| A late-join flush hidden while the node that saw the old marker makes no read | `Redis_LivLateJoinAdv.cfg` | `Liv_LossReported` violated (14 steps, ends stuttering) | Run-3 F-3 option 2, documented in REQ-528's notes and NFR-31; run 4 F-1 made "paused" mean "makes no marker read" |
| Rollback to older data (restore, lagging replica) | `Redis_Restore.cfg`, `Redis_RestoreOlder.cfg` | `Inv_NoLostOutcome` (10, 11 steps), `Inv_SingleClaim` (11, 12), `Inv_ConcurrencyKeyMax` (11, 12) violated | Run-2 F-5, option 2 accepted (REQ-507 and REQ-526 notes, NFR-31): a claim after the copy, or a same-marker rollback that is not detected |
| Runtime eviction (the policy changes after startup) | `Redis_Evict.cfg` | `Inv_ConcurrencyKeyMax` (12 steps), `Inv_NoLostOutcome` (11) violated | REQ-531 states that resets caused by eviction are not detected; REQ-505 refuses eviction at startup |
| A lease-lost run beside a newer claim | every cfg | excluded from `Inv_ConcurrencyKeyMax` and `Inv_SingleClaim` (A-18) | The stated rule: a run that did not heartbeat for a whole LeaseDuration has lost its lease, as under jobs REQ-132 |
| Counterfactual: the run-5 wording of REQ-507 (read, then a separate compare-and-set) | `Redis_HideRace.cfg` | `Inv_HiddenOnlyIfPaused` violated (14 steps), as expected | Shows why run 5 F-1 needed the change; not the requirement any more |
| Counterfactual: REQ-523 read literally | `Redis_Req523Literal.cfg` | `Inv_UnackedUntilOperator` violated (9 steps), as expected | The example for F-1 |

## Passed checks
| Check | Config | Distinct states | Meaning |
|---|---|---|---|
| `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_UnackedUntilOperator`, `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Scn_NoClaimWhileFlagged` | `Redis.cfg` (two workers, one flush) | 348,597 each | One report per flush, no false report, and "a detected flush ends every lease", with the write in the read |
| all seven safety invariants | `Redis_Flush2.cfg` (second flush during a reconciliation) | 2,856,201 | Two flushes with the restarted REQ-509 wait |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique2During.cfg` / `Redis_Recurring2During.cfg` | 2,893,397 / 2,177,993 | Unique keys and occurrences across two flushes |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique2.cfg` / `Redis_Recurring2.cfg` (second flush after the first reconciliation) | 1,014,197 / 837,857 | An expired run is not brought back (REQ-522) |
| `Inv_SingleClaim`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost` | `Redis_Flush2Late.cfg` (two flushes, a late first look, one job) | 921,195 | REQ-521 under resetSinceClaim |
| all seven safety invariants | `Redis_LateJoin.cfg` | 907,278 | A late first look (REQ-528's first marker beside a node that saw the old one): one report, no false one |
| `Inv_HiddenOnlyIfPaused`, `Inv_HiddenRunsLeaseLost`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_ConcurrencyKeyMax` | `Redis_Hide.cfg` | 119,197 | **Run-5 F-1 resolved**: a hidden flush needs every node that saw the old marker to make no read |
| `Inv_HiddenOnlyIfPaused`, `Inv_HiddenRunsLeaseLost` | `Redis_Hide2.cfg` (two jobs) | 1,105,989 | The same with a claim beside a running job |
| `Inv_ResetSinceClaimSound`, `Inv_NoFalseReset`, `Inv_ConcurrencyKeyMax` | `Redis_Fresh.cfg` (two workers, new server) | 1,096 | A new server is initialised, not reported (SCN-503) |
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
| SCN-500, 503, 504, 505, 507 and 508 traps violated, as expected | `Redis_SCN5xx.cfg` | 899 / 71 / 10,873 / 808 / 28,150 / 963 | Positive scenarios are reachable in 10, 8, 15, 10, 14 and 12 steps |

Bounded checks:
- `Redis_Flush2.cfg`, the `*2During` cfgs and SCN-509 allow the second flush only while a node is reconciling (`ActC_SecondLossDuringReconcile`).
- `Redis_Unique2.cfg`, `Redis_Recurring2.cfg` and SCN-510 allow it only after the first reconciliation has ended everywhere (`ActC_SecondLossAfterReconcile`).
- `Redis_HideRace.cfg` (counterfactual) keeps the read-to-write window shorter than one LeaseDuration (`ActC_ShortCAS`, A-29).
- `Redis_Flush2Late.cfg` runs with one job, as in runs 4 and 5. `Inv_NoFalseReset` under rollbacks is checked on `Redis_RestoreFR.cfg` (one job, one claim).

## Modeling assumptions
Decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. Changes since run 5 are marked.
| # | Assumption | Affects |
|---|---|---|
| A-1 | "The store is ready" (REQ-500) is one of the startup checks of hosting REQ-18 | REQ-500, REQ-502, REQ-505, SCN-501 |
| A-2 | The marker reads of a worker's claim, heartbeat and completion scripts and of its REQ-509 clear apply REQ-507, REQ-528 and REQ-530 before their own effect (`ReadOK`). Other reads (REQ-527, REQ-510, plain looks) can happen at any time, so REQ-507/528/530 can also run as their own step | REQ-507, REQ-528, REQ-530 |
| A-3 | Re-seeding writes the recurring definitions, the queue registry and the node's registration in one step | REQ-507, REQ-528, REQ-530, LIV-500 |
| A-5 | Only `actor: system` steps are (weakly) fair, including heartbeats (jobs REQ-126), plus the passage of time (`LeaseElapses`). The server becomes unreachable at most once per run, every outage ends, and a dropped node reconnects | all liveness checks |
| A-6 | used_memory above RedisMemoryDegradedShare is a boolean that can change at any time; HealthyAfterPasses = 1 | REQ-519, REQ-520 |
| A-8 | A stopped node's run and memory disappear with it | `Redis_ClientOnly.cfg` |
| A-9 | "Processing at once" in jobs INV-108, and "holds an unexpired claim" in INV-103, mean handlers running under a claim whose lease has not expired | run-3 F-1 |
| A-10 | All model jobs share one concurrency key; with `UniqueKeys` they share one unique key; with `Recurring` they are occurrences of one recurring job with overlap Skip | run-3 F-2 |
| A-12 | A restore or failover rolls the whole server back to an image taken earlier, marker included | accepted rollback rows |
| A-14 | Job ids and lease tokens are fresh | all |
| A-16 | A refused heartbeat or completion (jobs INV-128) does not stop the handler | run-3 F-2 |
| A-17 | Without `LateJoin`, every worker has read the marker before data is lost. With `LateJoin`, at least one has; REQ-528's notes accept that a loss no running node saw goes unreported | late-join cfgs |
| A-18 | **LeaseDuration without a clock.** See below. | every safety result |
| A-19 | *(changed: now the requirement)* REQ-507's and REQ-528's read and write are one atomic step (`DetectReset`, `InitMarker`). `SplitCAS` keeps the run-5 wording only as a counterfactual | REQ-507, REQ-528 |
| A-21 | Only a rollback to an older marker value counts as a detectable loss in `Liv_LossReported`; same-value rollbacks and runtime evictions are documented as undetected (NFR-31, REQ-531) | `Liv_LossReported` |
| A-22 | A node remembers the last value it saw from ordinary reads, claims and its own writes (glossary `lastSeenMarker`). A heartbeat or completion that reads a newer unflagged value is the same as an ordinary read followed by the heartbeat (`Observe`), so it is not modeled separately | REQ-507, REQ-530 |
| A-24 | Marker values and last-reset values from "the Redis server's current time" (REQ-507, REQ-527, REQ-528) are a counter that every new time value increases, flushes and rollbacks included. REQ-528's lowest value is below every such value | REQ-507, REQ-527, REQ-528 |
| A-25 | A node "has finished a value's reconciliation" once REQ-509 found the marker at that value, cleared or already unflagged (REQ-530 notes) | REQ-530, LIV-500 |
| A-26 | A single node can lose its connection (REQ-529) while the others stay connected; its store is connecting until it reconnects, and it neither heartbeats nor completes meanwhile | `Redis_Drop.cfg`, `Redis_LivDrop.cfg` |
| A-27 | "Paused" in NFR-31 and the REQ-528 notes means the node makes no marker read between the flush and the advance (`readInWindow`) | REQ-528, NFR-31 |
| A-28 | A script's read and the node's response to it (REQ-507/528/530) are ordered response-first: the claim, heartbeat or completion takes effect only once no sentence applies. Since run 6 the script makes the REQ-507/528 write itself, which is that response | REQ-526, REQ-522, REQ-521 |
| A-29 | (counterfactual only) With `SplitCAS`, the window between the read and the compare-and-set is shorter than one LeaseDuration (`ActC_ShortCAS`) | `Redis_HideRace.cfg` |
| A-30 | A refused claim attempt (marker missing or flagged) is not modeled as a read. Whether a reconciling node keeps calling its claim script no longer matters for detection: with the write in the read, nothing can land between them | REQ-507 |
| A-31 | *(new)* REQ-523's trigger, "this node's compare-and-set in REQ-507 succeeds", is modeled as this node's REQ-507 replacement of the marker (`DetectReset`), as in run 5. The literal reading is the counterfactual `Req523Literal` (F-1) | REQ-523 |

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
- `python run_all.py [cfg …]` runs each invariant and each property alone with `--stop-at-first`, and enforces a 170 s limit per run. `TLC_WORKERS` sets the worker count (default 4; this run used 2). Results go to `runs/` and `run.md`, which are gitignored. Set `RUN_INDEX=name.json` to write a separate index.
- Never run two batches in the same folder at once: TLC's `-cleanup` deletes the other batch's state directories.
- `python summary.py [filter]` lists finished checks (including older results still in `runs/`). `python trace.py runs/<cfg>__<check>.json [var …]` prints a trace as changed variables per step.

Switches in the model that are not requirements:
- `SplitCAS`: COUNTERFACTUAL, the run-5 wording of REQ-507 (a read and a separate compare-and-set). `TRUE` only in `Redis_HideRace`.
- `Req523Literal`: COUNTERFACTUAL, REQ-523 read literally (F-1). `TRUE` only in `Redis_Req523Literal`.
- `TrackHidden`: keeps the history variables of `Inv_HiddenOnlyIfPaused` and `Inv_HiddenRunsLeaseLost`. `TRUE` only in `Redis_Hide*`.

With all three `FALSE`, `casPending`, `found`, `foundLR` and the history variables stay constant; `Redis.cfg` has 348,597 states, as in run 5.

## Next
Decide F-1: option 1 changes REQ-523's `when` to "this node replaces the generation marker under REQ-507", which is what the model already checks. Apply it to `specs/redis.json` with the `refiner-requirements` skill, then run this skill again.

These questions were already open and are unchanged by this run: one marker per hash tag under ShardByQueue (TECH-130), the StaleNodeAge value (REQ-533), and whether REQ-531 should report Unhealthy instead of an ERROR.
