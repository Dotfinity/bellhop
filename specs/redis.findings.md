# Findings: Bellhop Redis store behaviour

<!-- refiner-findings v1 | module: redis | specHash: ea2b1eed07d1d2f91c3186134a26d94364d3a3d09b50c21722f1bbd714c3e4d1 | run: 2026-11-08 (run 7) | previous: specs/model/redis/previous.findings.md (run 6, specHash fb9a582eac88) -->

**Run:** 2026-11-08, run 7 · **Requirements file:** `specs/redis.json` (specHash `ea2b1eed07d1`) · **Model:** `specs/model/redis/Redis.tla` (43 cfgs from `gen_cfgs.py`) · **TLC:** 2.19. Every check ran alone with `--stop-at-first --workers 4` and a 170 s limit: 103 checks, all with the expected result, no timeouts and no TLC exceptions. The longest check took 44.6 s (`Redis_LivRestore.cfg`, `Liv_Reseeded`). Three other modules were being checked on the same machine. The largest space is `Redis_Unique2During.cfg`, with 2,893,397 distinct states in 33.1 s. After the batch, the SCN-500 trap was made stricter (see below) and `Redis_SCN500.cfg` was rerun alone.
**Result:** 1 finding: 0 contradictions · 1 gap · 0 unprovable · 0 ambiguities · 0 modeling notes. Run 6's only finding is resolved.

This run regenerated REQ-523 from `handoff.json` (base 319dd72, resolution commit e2b4708):
- REQ-523 now fires "when this node replaces the generation marker under REQ-507". The model already did this (`DetectReset`, A-31), so A-31 is now the requirement. The run-6 counterfactual `Req523Literal` and `Redis_Req523Literal.cfg` are removed: they modeled a wording that no longer exists.
- The impacted ids were re-checked. REQ-532: `Liv_UnackedRestored` passes on `Redis_Liveness.cfg` and `Redis_LivFlush2.cfg`. SCN-500 is reachable in 10 steps. REQ-523: `Inv_UnackedUntilOperator` passes on `Redis.cfg`, `Redis_Flush2.cfg` and `Redis_LateJoin.cfg`, and `Inv_OneEventPerReset` passes on those cfgs and on `Redis_RestoreFR.cfg`.
- With every switch off, each check that passed has exactly the same number of distinct states as in run 6 (`Redis.cfg` 348,597). Removing `Req523Literal` changed nothing else.

**SCN-500's trap is stricter.** Its `then` ends with "health stays Degraded until an operator acknowledges the reset". The trap only asked for health = Degraded at the end, so the shortest trace (in run 6 too) reached it with a Degraded state left by hosting REQ-58 before the flush, and no health check ran after the reset. The trap now also requires the next health check to keep the node Degraded. With no memory pressure and the store Ready, only the unacknowledged reset can do that (REQ-524). It is still reached in 10 steps (943 states). This change makes the check harder to pass, not easier.

**The new trigger was checked statically against REQ-528 and REQ-530** (section below). It cannot match either of them. Re-reading REQ-523 as a store-side event did raise one new question, which is F-1. A `LostReply` environment switch (one new action, `ReplyLost`) found it: the script makes REQ-507's write, and then the connection drops before the reply reaches the node.

## Changes since last run
| Finding | Status |
|---|---|
| F-1 (run 6): REQ-523's trigger names a compare-and-set REQ-507 no longer makes | resolved. e2b4708 applied option 1. REQ-523 is modeled by `DetectReset` (A-31 is the requirement). `Inv_UnackedUntilOperator` passes on `Redis.cfg` (348,597), `Redis_Flush2.cfg` (2,856,201) and `Redis_LateJoin.cfg` (907,278), `Liv_UnackedRestored` passes, and SCN-500 is reachable. The counterfactual is retired. |
| F-1 (this run) | new |

`findings_delta.py` output (fingerprints; the first row uses run 6's number):

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | ambiguity · Inv_UnackedUntilOperator/Req523Literal · REQ-507,REQ-523 |
| F-1 | new | gap · Inv_HiddenOnlyIfPaused/LostReply · REQ-507,REQ-523,REQ-529,REQ-530 |

1 resolved, 1 new, 0 still open

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | gap | high | REQ-523, REQ-507, REQ-529, REQ-530 | If the connection drops after the script made REQ-507's write but before its reply arrives, no node reports the flush or records it as unacknowledged, and every node, the writer included, joins the new marker silently |

Decide **F-1**. It is the only finding. It was not caused by e2b4708, but the new wording makes it visible: REQ-523 is now triggered by a write in the store that the node learns about only from a reply.

---

## F-1 · gap · high — A lost reply to REQ-507's write leaves the flush unreported and unrecorded
<!-- finding: gap | Inv_HiddenOnlyIfPaused/LostReply | REQ-507,REQ-523,REQ-529,REQ-530 -->

**Requirements involved**
- REQ-523: *When **this node replaces the generation marker under REQ-507**, the system shall log an ERROR saying that runtime-defined recurring jobs, the maintenance pause, queue pauses, runtime throttle limits and recurring-job pauses may have been lost and are back at their defaults, record the reset as unacknowledged in the store, and remember it until it finds the reset acknowledged.*
- REQ-507: *… the system shall replace the marker, **in the same atomic step as the read that found it**, with the Redis server's current time as both its value and its last-reset value, flagged as reconciling, log the ERROR event StoreWasReset, and start re-seeding …*
- TECH-130 (technical specifications): the claim, heartbeat and completion scripts *"make the redis REQ-507 or REQ-528 marker write themselves when it applies, and return the generation marker and last-reset value they read and **whether they wrote it**, so the node logs and re-seeds under redis REQ-507, REQ-528 and REQ-530 before using the script's result"*.
- REQ-529: *When the connection to the server is lost or the server's role changes, the system shall mark the store connecting and repeat server detection when it reconnects.*
- REQ-530: *When any read this node makes of the generation marker … finds it flagged as reconciling with a value whose reconciliation this node has not finished, if that value is not older than the last value this node saw, the system shall start re-seeding … without logging StoreWasReset, and remember the value.*

**What happens** (TLC, `Redis_ReplyLost.cfg`, `Inv_HiddenOnlyIfPaused`, 13 steps)
1. Worker nodes n1 and n2 connect, are marked running and read the generation marker at value 2 (REQ-500, hosting REQ-18).
2. Someone runs FLUSHALL.
3. n1's next marker read, for example its claim script, finds the marker missing. n1 has seen a marker, so REQ-507 applies. The script replaces the marker in the same atomic step with value 3, flagged as reconciling (TECH-130). **Before the reply reaches n1, n1's connection drops** (REQ-529), and n1 marks its store connecting. The marker is replaced, so REQ-523's trigger has happened. n1 never learns that it made the write: it logs no StoreWasReset and no REQ-523 ERROR, writes no unacknowledged record, remembers nothing, and its last-seen value stays at 2.
4. n2 reads the marker and finds it flagged at 3. The value is not older than the 2 that n2 saw, so REQ-530 applies and n2 re-seeds without logging StoreWasReset.
5. n2 finishes re-seeding, a LeaseDuration passes, and REQ-509 clears the flag. The store is Ready and claims resume.
6. When n1 reconnects, it reads value 3, unflagged and newer than the 2 it saw. That is an ordinary read, and no sentence applies.

**The flush is now hidden for good**, although n1 read the marker after the flush and was not paused. No node ever logs StoreWasReset or the REQ-523 ERROR, the store holds no unacknowledged record, and health is never Degraded for the reset (REQ-524). The runtime-defined recurring jobs, the maintenance pause, queue pauses, throttle limits and recurring-job pauses are back at their defaults, and nobody is told.

The liveness check shows the same thing from the other side (`Redis_LivReplyLost.cfg`, `Liv_LossReported`, 16 steps, ends stuttering). This time n2's reply is lost. n2 reconnects, finds its *own* flagged marker newer than anything it saw, and joins it silently through REQ-530 (step 12), so even the node that made the write re-seeds without reporting.

**Why** REQ-523's trigger is a write in the store, but everything it requires (the ERROR, the record and the memory) is done by the node after the script's reply comes back. REQ-507's "log the ERROR event StoreWasReset" works the same way. When the reply is lost, the trigger has happened and none of the response has. Nothing later lets anyone tell that the write was a detection:
- the new marker is newer than every value any node saw, so REQ-507 applies to nobody;
- it is flagged and not older, so REQ-530 makes every node, the writer included, join it silently.

Run 6's A-28 ("the script makes the REQ-507/528 write itself, which is that response") treated the write and the node's response as one step. This run splits them when the connection drops. The same thing happens if the client times out after the server ran the script and the connection stays up: the node's next read finds a newer flagged value. That case is not traced, because the model has no client timeout, but it leaves the store and the node in the same state.

The gap was not introduced by e2b4708. With run 5's separate compare-and-set, losing that command's reply had the same effect. It shows up now because REQ-523's trigger names the replacement itself.

The rest of the model is unaffected. With `LostReply` on, `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_ConcurrencyKeyMax` and `Inv_SingleClaim` pass (`Redis_ReplyLost.cfg`, 160,546 states), and `Liv_Reseeded` passes (`Redis_LivReplyLost.cfg`, 152,077). The lost reply hides the report. It breaks no claim, lease or outcome rule.

**Options**
1. *(recommended)* **Make the record part of the atomic write.** The script that makes REQ-507's replacement also writes the unacknowledged reset record in the same atomic step. Health (REQ-524) and the dashboard then see the reset however the reply, or the node, fares. Only the two ERROR log lines and this node's memory of the reset (REQ-532's re-write) still depend on the reply. A later flush that erases the record is itself a reset and is recorded again. Cost: one clause in REQ-523, and TECH-130 has to name the record among the script's writes. TECH-130 is in `technical-specifications.md`, outside this module, so that edit belongs there. The next run would check a new invariant: every replacement under REQ-507 leaves an unacknowledged record until an operator acknowledges it, lost reply included.
2. **Let the writer recognise its own write.** The REQ-507 script stores the writing node's id with the marker. REQ-530 gets an exception: a node that finds a flagged marker it wrote itself, and does not remember writing, applies REQ-523 instead of joining silently. This also restores the logs and the memory after a reconnect. It does not help when the node stops or crashes before it reconnects. Cost: a new marker field and a branch in REQ-530, the sentence that carries the most guards already. It can be added on top of option 1.
3. **Accept it and document it in NFR-31**: "a flush is not reported if the node whose script replaced the marker loses the reply". This is the cheapest. It goes against the owner's full-protection decision (REQ-507, REQ-509 notes): operator state falls back to its defaults silently and health never shows it.

**Ready to apply (option 1)**
```json
{ "id": "REQ-523", "ears": {
    "when": "this node replaces the generation marker under REQ-507",
    "shall": "record the reset as unacknowledged in the store in the same atomic step as that replacement, log an ERROR saying that runtime-defined recurring jobs, the maintenance pause, queue pauses, runtime throttle limits and recurring-job pauses may have been lost and are back at their defaults, and remember the reset until it finds it acknowledged" },
  "notes": "<existing notes> refiner-model 2026-11-08 run 7 F-1 (recommended option): the record is written by the same script as REQ-507's replacement (TECH-130), so it does not depend on the script's reply. If the connection drops or the call times out after the script ran, the ERROR and this node's memory are lost, but the record is not, and health stays Degraded (REQ-524) until an operator acknowledges it. Before, a lost reply left no trace: every node, the writer included, joined the new marker silently through REQ-530." }
```
TECH-130 (outside this module) would then read "…make the redis REQ-507 or REQ-528 marker write themselves when it applies, **together with redis REQ-523's unacknowledged reset record for a REQ-507 write**, and return …".

---

## Static read: REQ-523's new trigger against REQ-528 and REQ-530
"This node replaces the generation marker under REQ-507" matches only `DetectReset`. Checked sentence by sentence:

| Sentence | Does it replace the marker under REQ-507? | Why not, from the sentences |
|---|---|---|
| REQ-528 (first marker, SCN-503) | No | Its shall says "write the first generation marker", in its own sentence, not under REQ-507. Its `if` ("has not seen a generation marker since it started") is the negation of REQ-507's `if` ("has seen …"), so one read cannot satisfy both. Its shall also says outright "without logging StoreWasReset or recording the reset as unacknowledged". `Redis_Fresh.cfg` (`Inv_NoFalseReset`, 1,096 states) and the SCN-503 trap (reached in 9 steps with `resetRec = "none"`, `detections = 0`) confirm that no record is written. |
| REQ-530 (silent joiners) | No | It writes nothing to the marker: it starts re-seeding and remembers the value. Its trigger (flagged, value not older than the last seen) cannot hold together with REQ-507's (missing, or older than the last seen). `Inv_OneEventPerReset` passes on every cfg where several nodes join a reset. |
| REQ-527 (advance) | No | Its own sentence and verb ("advance … by compare-and-set"), on an unflagged marker, while Ready. |
| REQ-509 (clear the flag) | No | It clears the flag on the value it reconciles. That is not a replacement, and the sentence is not REQ-507. The only conceivable stretch is reading "under REQ-507" as "during a reconciliation that REQ-507 started". The clear never names REQ-507 as its cause, so this is not a finding. |

"Replaces" also covers the missing-marker case: REQ-507 itself says "replace the marker" when it finds it missing, and the glossary (`generationMarker`) says the same ("replaces it … when it detects a reset (REQ-507)"). The only way the trigger can happen without its response is F-1.

## Stale notes (annotation only, not edited)
These notes still describe REQ-507 as a compare-and-set. None of them changes the meaning of a semantic field, and each is corrected by a later note in the same text or by REQ-507 itself. They are listed so that the next edit can tidy them:
- **REQ-507 notes**, F-9: "the compare-and-set makes exactly one node report each reset". A later note in the same text says "F-9's 'exactly one node reports each reset' now follows from that, with no compare-and-set".
- **REQ-523 notes**, F-9: "only the node that wins the compare-and-set reports the reset"; run 3 F-5: "REQ-528's first write is also a compare-and-set of a reconciling marker". The run-6 note corrects the first. The second is stale too: since e316e1f, REQ-528's write is atomic with its read, and the point it makes (REQ-528 must not report) still holds.
- **REQ-530 notes**, F-9 and F-13: "the nodes that lose the compare-and-set in REQ-507 … reconcile silently". No node loses it any more. The run-5 note at the end of the same text says so.
- Outside this module: the TECH-130 open question in `technical-specifications.md` says "compare-and-set and advancing are then not atomic across the whole namespace". REQ-507 no longer makes a compare-and-set; "the REQ-507/REQ-528 write and REQ-527's advance" would be accurate.

REQ-527's "by compare-and-set" is REQ-527's own advance and is correct.

## Checked and accepted (not findings)
| Check | Config | Result | Why it is not a finding |
|---|---|---|---|
| A late-join flush hidden while the node that saw the old marker makes no read | `Redis_LivLateJoinAdv.cfg` | `Liv_LossReported` violated (16 steps this run, 14 in run 6; ends stuttering) | Run-3 F-3 option 2, documented in REQ-528's notes and NFR-31. Run 4 F-1 made "paused" mean "makes no marker read". The longer trace comes from the parallel search (4 workers instead of 2) and shows the same behaviour. |
| Rollback to older data (restore, lagging replica) | `Redis_Restore.cfg`, `Redis_RestoreOlder.cfg` | `Inv_NoLostOutcome` (10, 11 steps), `Inv_SingleClaim` (11, 12), `Inv_ConcurrencyKeyMax` (11, 12) violated | Run-2 F-5, option 2 accepted (REQ-507 and REQ-526 notes, NFR-31): a claim after the copy, or a same-marker rollback that is not detected |
| Runtime eviction (the policy changes after startup) | `Redis_Evict.cfg` | `Inv_ConcurrencyKeyMax` (12 steps), `Inv_NoLostOutcome` (11) violated | REQ-531 states that resets caused by eviction are not detected; REQ-505 refuses eviction at startup |
| A lease-lost run beside a newer claim | every cfg | excluded from `Inv_ConcurrencyKeyMax` and `Inv_SingleClaim` (A-18) | The stated rule: a run that did not heartbeat for a whole LeaseDuration has lost its lease, as under jobs REQ-132 |
| Counterfactual: the run-5 wording of REQ-507 (read, then a separate compare-and-set) | `Redis_HideRace.cfg` | `Inv_HiddenOnlyIfPaused` violated (14 steps), as expected | Shows why run 5 F-1 needed the change; not the requirement any more |
| A lost reply to REQ-507's write | `Redis_ReplyLost.cfg`, `Redis_LivReplyLost.cfg` | `Inv_HiddenOnlyIfPaused` (13 steps), `Liv_LossReported` (16 steps) violated | The example for F-1 |

## Passed checks
| Check | Config | Distinct states | Meaning |
|---|---|---|---|
| `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_UnackedUntilOperator`, `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Scn_NoClaimWhileFlagged` | `Redis.cfg` (two workers, one flush) | 348,597 each | One report per flush, no false report, and "a detected flush ends every lease". **REQ-523 under its new trigger** |
| all seven safety invariants | `Redis_Flush2.cfg` (second flush during a reconciliation) | 2,856,201 | Two flushes with the restarted REQ-509 wait; the unacknowledged record is written again after the second |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique2During.cfg` / `Redis_Recurring2During.cfg` | 2,893,397 / 2,177,993 | Unique keys and occurrences across two flushes |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique2.cfg` / `Redis_Recurring2.cfg` (second flush after the first reconciliation) | 1,014,197 / 837,857 | An expired run is not brought back (REQ-522) |
| `Inv_SingleClaim`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost` | `Redis_Flush2Late.cfg` (two flushes, a late first look, one job) | 921,195 | REQ-521 under resetSinceClaim |
| all seven safety invariants | `Redis_LateJoin.cfg` | 907,278 | A late first look (REQ-528's first marker beside a node that saw the old one): one report, no false one |
| `Inv_HiddenOnlyIfPaused`, `Inv_HiddenRunsLeaseLost`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_ConcurrencyKeyMax` | `Redis_Hide.cfg` | 119,197 | A hidden flush needs every node that saw the old marker to make no read (replies always arrive) |
| `Inv_HiddenOnlyIfPaused`, `Inv_HiddenRunsLeaseLost` | `Redis_Hide2.cfg` (two jobs) | 1,105,989 | The same with a claim beside a running job |
| `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim` | `Redis_ReplyLost.cfg` (one job, one flush, one lost reply) | 160,546 | *(new)* A lost reply breaks no claim, lease or outcome rule (F-1 is about the report only) |
| `Liv_Reseeded` | `Redis_LivReplyLost.cfg` | 152,077 | *(new)* The pause still ends after a lost reply |
| `Inv_ResetSinceClaimSound`, `Inv_NoFalseReset`, `Inv_ConcurrencyKeyMax` | `Redis_Fresh.cfg` (two workers, new server) | 1,096 | A new server is initialised, not reported (SCN-503) |
| `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Scn_NoClaimWhileFlagged` | `Redis_Outage.cfg` / `Redis_Drop.cfg` | 1,906,584 / 1,475,436 | Outages and single-node drops during the pause |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique.cfg` / `Redis_Recurring.cfg` (one flush) | 310,693 / 265,981 | REQ-534 and the occurrence pause |
| `Inv_UniqueKey` | `Redis_Shard.cfg` | 1,240 | jobs INV-100's per-queue scope matches INV-500 |
| `Inv_NoFalseReset`, `Inv_OneEventPerReset` | `Redis_RestoreFR.cfg` | 210,590 | Rollbacks cause no false or double report |
| `Liv_Reseeded`, `Liv_MarkerWritten` (LIV-501), `Liv_LossReported`, `Liv_UnackedRestored` | `Redis_Liveness.cfg` | 33,469 | One flush: re-seeded, marker written, reported, record kept (REQ-532) |
| `Liv_LossReported`, `Liv_UnackedRestored`, `Liv_Reseeded` | `Redis_LivFlush2.cfg` | 318,426 | Two flushes; a record erased by the second is restored (REQ-532) |
| `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivRestore.cfg` | 392,700 | A rollback to an older marker is eventually reported |
| `Liv_Reseeded` | `Redis_LivOutage.cfg` / `Redis_LivDrop.cfg` (`Liv_LossReported` too) | 6,299 / 141,700 | No stuck pause after a reconnection |
| `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivLateJoin.cfg` | 27,450 | A late first look is reported (no advance) |
| `Liv_Reseeded` | `Redis_LivLateJoinAdv.cfg` | 96,724 | The pause always ends, with an advance too |
| `Liv_Reseeded`, `Scn_ClientNoDetect` (SCN-506) | `Redis_ClientOnly.cfg` | 10,556 | A client-only node never reconciles |
| `Inv_UnreachableIsUnhealthy`, `Inv_UnhealthyOnlyWithCause` | `Redis_Health.cfg` | 47,178 | Health precedence matches hosting |
| `Scn_NoEvalNoReady` (SCN-501) | `Redis_SCN501.cfg` | 56 | A server without EVAL never becomes ready |
| `Scn_NoClearBeforeWait` (SCN-509) / `Scn_NoRevivalAfterExpiry` (SCN-510) | `Redis_SCN509.cfg` / `Redis_SCN510.cfg` | 2,856,201 / 837,857 | Negative scenarios hold; their steps 1–3 are reachable (`Redis_SCN509Reach.cfg` 12 steps, `Redis_SCN510Reach.cfg` 15 steps) |
| SCN-500 (stricter trap), 503, 504, 505, 507 and 508 traps violated, as expected | `Redis_SCN5xx.cfg` | 943 / 72 / 9,918 / 968 / 25,227 / 1,244 | Positive scenarios are reachable in 10, 9, 15, 10, 14 and 12 steps |

The state counts of violated checks are the states explored before TLC stopped, so they vary from run to run with the worker count. Every check that passed has the same count as in run 6.

**SCN-500 example** (10 steps): n1 connects and runs, and a health check moves it from Unhealthy to Degraded (hosting REQ-58). n1 reads the marker, FLUSHALL. n1's read finds the marker missing and replaces it, flagged (REQ-507). The same step logs StoreWasReset and the REQ-523 ERROR, records the reset as unacknowledged and remembers it (REQ-523). n1 re-seeds, a LeaseDuration passes, and the flag is cleared (REQ-509). The store is Ready, and the next health check can only keep n1 Degraded (REQ-524), because the reset is unacknowledged.

Bounded checks:
- `Redis_Flush2.cfg`, the `*2During` cfgs and SCN-509 allow the second flush only while a node is reconciling (`ActC_SecondLossDuringReconcile`).
- `Redis_Unique2.cfg`, `Redis_Recurring2.cfg` and SCN-510 allow it only after the first reconciliation has ended everywhere (`ActC_SecondLossAfterReconcile`).
- `Redis_HideRace.cfg` (counterfactual) keeps the read-to-write window shorter than one LeaseDuration (`ActC_ShortCAS`, A-29).
- `Redis_Flush2Late.cfg` runs with one job, as in runs 4 to 6. `Inv_NoFalseReset` under rollbacks is checked on `Redis_RestoreFR.cfg` (one job, one claim).
- `Redis_ReplyLost.cfg` and `Redis_LivReplyLost.cfg` run with one job and at most one lost reply (`MaxDrops = 1`).

## Modeling assumptions
Decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. Changes since run 6 are marked.
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
| A-19 | REQ-507's and REQ-528's read and write are one atomic step (`DetectReset`, `InitMarker`), as the sentences say since run 6. `SplitCAS` keeps the run-5 wording only as a counterfactual | REQ-507, REQ-528 |
| A-21 | Only a rollback to an older marker value counts as a detectable loss in `Liv_LossReported`; same-value rollbacks and runtime evictions are documented as undetected (NFR-31, REQ-531) | `Liv_LossReported` |
| A-22 | A node remembers the last value it saw from ordinary reads, claims and its own writes (glossary `lastSeenMarker`). A heartbeat or completion that reads a newer unflagged value is the same as an ordinary read followed by the heartbeat (`Observe`), so it is not modeled separately | REQ-507, REQ-530 |
| A-24 | Marker values and last-reset values from "the Redis server's current time" (REQ-507, REQ-527, REQ-528) are a counter that every new time value increases, flushes and rollbacks included. REQ-528's lowest value is below every such value | REQ-507, REQ-527, REQ-528 |
| A-25 | A node "has finished a value's reconciliation" once REQ-509 found the marker at that value, cleared or already unflagged (REQ-530 notes) | REQ-530, LIV-500 |
| A-26 | A single node can lose its connection (REQ-529) while the others stay connected; its store is connecting until it reconnects, and it neither heartbeats nor completes meanwhile | `Redis_Drop.cfg`, `Redis_LivDrop.cfg`, `Redis_*ReplyLost.cfg` |
| A-27 | "Paused" in NFR-31 and the REQ-528 notes means the node makes no marker read between the flush and the advance (`readInWindow`) | REQ-528, NFR-31 |
| A-28 | *(changed)* A script's read and the node's response to it (REQ-507/528/530) are ordered response-first: the claim, heartbeat or completion takes effect only once no sentence applies. When the reply arrives, the script's REQ-507/528 write and the node's response are one step. With `LostReply`, the write can happen without the response (A-32) | REQ-526, REQ-522, REQ-521, REQ-523 |
| A-29 | (counterfactual only) With `SplitCAS`, the window between the read and the compare-and-set is shorter than one LeaseDuration (`ActC_ShortCAS`) | `Redis_HideRace.cfg` |
| A-30 | A refused claim attempt (marker missing or flagged) is not modeled as a read. Whether a reconciling node keeps calling its claim script does not matter for detection: with the write in the read, nothing can land between them | REQ-507 |
| A-31 | *(changed: now the requirement)* REQ-523's trigger, "this node replaces the generation marker under REQ-507", is `DetectReset`. `InitMarker` (REQ-528) and `Learn` (REQ-530) record nothing | REQ-523 |
| A-32 | *(new)* `LostReply`: a connection drop (REQ-529) can come between the server running the script that makes REQ-507's write and the node receiving its reply. The write stands; the node learns nothing, its store is connecting, and its last-seen value is unchanged. This is an environment event, not fair, at most `MaxDrops` per run, and it is on only in `Redis_*ReplyLost.cfg`. A client-side timeout has the same effect but is not modeled | F-1 |

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
- `python run_all.py [cfg …]` runs each invariant and each property alone with `--stop-at-first`, and enforces a 170 s limit per run. `TLC_WORKERS` sets the worker count (default 4; this run used 4). Results go to `runs/` and `run.md`, which are gitignored. Set `RUN_INDEX=name.json` to write a separate index.
- Never run two batches in the same folder at once: TLC's `-cleanup` deletes the other batch's state directories.
- `python summary.py [filter]` lists finished checks (including older results still in `runs/`). `python trace.py runs/<cfg>__<check>.json [var …]` prints a trace as changed variables per step.

Switches in the model that are not requirements:
- `SplitCAS`: COUNTERFACTUAL, the run-5 wording of REQ-507 (a read and a separate compare-and-set). `TRUE` only in `Redis_HideRace`.
- `LostReply`: ENVIRONMENT, the reply to REQ-507's write is lost with the connection (A-32, F-1). `TRUE` only in `Redis_ReplyLost` and `Redis_LivReplyLost`.
- `TrackHidden`: keeps the history variables of `Inv_HiddenOnlyIfPaused` and `Inv_HiddenRunsLeaseLost`. `TRUE` only in `Redis_Hide*` and `Redis_ReplyLost`.

With all three `FALSE`, `casPending`, `found`, `foundLR` and the history variables stay constant and `ReplyLost` is disabled. `Redis.cfg` has 348,597 states, as in runs 5 and 6.

## Next
Decide F-1. Option 1 adds "in the same atomic step as that replacement" to REQ-523's record. Its TECH-130 counterpart is in `technical-specifications.md`, outside this module. Apply it to `specs/redis.json` with the `refiner-requirements` skill, then run this skill again. The next run will check that a lost reply still leaves an unacknowledged record.

These questions were already open and are unchanged by this run: one marker per hash tag under ShardByQueue (TECH-130), the StaleNodeAge value (REQ-533), and whether REQ-531 should report Unhealthy instead of an ERROR.
