# Findings: Bellhop Redis store behaviour

<!-- refiner-findings v1 | module: redis | specHash: 7bcd94d03e2daf303b36f0c332801df8419a33efeadb775b52a9515abc20bb8b | run: 2026-11-08 (run 10) | previous: specs/model/redis/previous.findings.md (run 9, specHash 7bcd94d03e2d) -->

**Run:** 2026-11-08, run 10 · **Requirements file:** `specs/redis.json` (specHash `7bcd94d03e2d`, unchanged) · **Model:** `specs/model/redis/Redis.tla` (49 cfgs from `gen_cfgs.py`, both byte-identical to runs 8 and 9) · **TLC:** 2.19.
Since run 9 only annotation changed: 8344b8b (REQ-523, REQ-532 and NFR-31 name the class of undetected losses that take the reset record with them) and 9748d95 (the stale compare-and-set notes in REQ-507, REQ-523 and REQ-530). `reqs.py diff` against 15c063a reports no changes and the same specHash, so `Redis.tla`, every cfg and every run-8 result stay valid. This run reran only the 11 cfgs that are evidence for the changed notes: 40 checks, each alone with `--stop-at-first --workers 4` and a 170 s limit. All 40 have their earlier result (run 8, and run 9 for the cfgs it reran), and every passed check has run 8's distinct-state count. Everything else rests on run 8's complete batch (123 checks, all with the expected result), with the model unchanged. It also ran ten probes in `$TEMP/redis10_probe` (module `RedisProbe10`, which `EXTENDS Redis`; see How to reproduce): run 9's five, rerun, and five new ones. P5 adds one action the model does not have, eviction of the reset record (A-37). Another module was being checked in a sibling folder.
**Timeouts:** no cfg. One probe, P6c (P6 with a third loss), was stopped after 300 s unfinished; it is a bound beyond P6, which passes, and no conclusion rests on it. **TLC exceptions:** none.
**Result:** 0 findings: 0 contradictions · 0 gaps · 0 unprovable · 0 ambiguities · 0 modeling notes. Run 9's only finding is resolved (documented).

**What was checked.** Each sentence changed by 8344b8b and 9748d95 is checked against the model, run 8's batch and run 9's probes (table under *The new notes against the model*):
- REQ-523: health stays Degraded until an operator acknowledges, "unless the store loses it in a way no node detects". A loss no node detects takes the record with it, a node that remembers writes it back, and after a lost reply nobody remembers, so health returns to Healthy. **Holds.** Every erasing trace (P2, P4, P5, `Redis_LivReplyLostLateAdv.cfg`) is a loss no node detects, and every detected loss leaves the record (P3, P6, `Redis_ReplyLost2.cfg`). Two over-statements remain, both in the safe direction (Notes to correct).
- REQ-532: the lost-reply record cannot be restored by this sentence; a detected later reset is recorded in turn; an undetected later loss removes it "unless some node still remembers an earlier unacknowledged reset". **Holds**, including the new "unless" (P1). This is run 9's optional wording, now applied.
- NFR-31: "either of these undetected losses also removes the unacknowledged record of an earlier reset whose script reply was lost". **Holds** for both losses (P4 and P2). The statement does not say these are the only ones.
- The reworded F-9, F-13 and F-5 notes (9748d95) **hold**. No sentence in the module still describes a compare-and-set that REQ-507 makes. The remaining mentions are history and say so.

**The question from the brief: is "a loss no node detects" exactly NFR-31's undetected losses?**
- **In `Redis.tla`, yes.** The record leaves `"unacked"` in only three actions: `Flush`, `Restore` and `Acknowledge`. `EvictJob` removes job records only. A flush is undetected only as the late-join flush (it needs REQ-528's first marker, so `LateJoin`; any node that saw a marker finds the store's marker missing or older). A rollback removes the record only when its image is older than the record, and is undetected only when no node saw anything newer than the image's marker. After a lost reply that is the image from before the flush (P2). Without a lost reply the writer saw the new marker and detects it (P2b passes). These are exactly NFR-31's late-join flush and undetected rollback. One caveat: the model has no clock, so it cannot check that such a rollback is "less than one RecurringReconcileInterval old". The image holds the marker every node last saw, which is the same test as NFR-31's base clause (A-21).
- **Outside the model, runtime eviction also does it.** Under an `allkeys-*` policy (REQ-531: the policy changes after startup), the server can evict the reset record's key. That is a loss of store data no node detects. REQ-531 already says "resets caused by eviction are not detected". Probe P5 adds this action (A-37). After a lost reply it reaches the erased state in 11 states, and health then returns to Healthy (P5L, a lasso). With the detector's reply, REQ-532 writes the record back (P5b passes). Eviction of the marker key is different: the next read finds it missing and REQ-507 reports it.
- **Do the notes still hold?** Yes. REQ-523 states a class ("a later loss of store data that no node detects as a reset") and says it does not count the cases, so eviction is inside it. REQ-532's "a later loss that no node detects (NFR-31)" is true of eviction too. Only its pointer is incomplete, because REQ-531 is the place where eviction is documented. NFR-31 names two losses and does not claim there are no others. It does not mention runtime eviction at all. Runtime eviction already gets its own ERROR (REQ-531), and the store refuses to start on such a server (REQ-505). These are optional wording points (Notes to correct), not findings.
- **Nothing else erases it in the model.** Stops (A-8), reconnections, outages and advances leave `resetRec` unchanged. A rollback to an image taken after the record was written brings the record back with it. Under ShardByQueue the record's hash slot is TECH-130's open question. A failover of only that slot's shard would be another loss no node detects. The class wording covers it too, and the model's ShardByQueue switch covers unique keys only.

## Changes since last run
| Finding | Status |
|---|---|
| F-1 (run 9): after a lost reply, an undetected rollback also erases the record; REQ-523's note named only one exception | resolved. 8344b8b applied option 1 and part of option 2. REQ-523's notes now name the class (a loss no node detects) instead of counting exceptions, REQ-532's notes say the same, and NFR-31's clause covers both undetected losses. The traces are now under *Checked and accepted*: probe P2 (rerun: 10 states, as in run 9) and its baseline P2b (passes, 1,247,312, as in run 9) |

`findings_delta.py` output (fingerprints; the row uses run 9's number):

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | gap · Trap_Erased/LostReplyRollback · REQ-507,REQ-523,REQ-524,REQ-532 |

1 resolved, 0 new, 0 still open

## Summary
No findings. Nothing needs a decision. Notes to correct lists five optional wording points, none of which the model contradicts.

---

## The new notes against the model
| Claim (8344b8b, 9748d95) | Where | Evidence (run 10 unless marked) | Result |
|---|---|---|---|
| A lost reply loses both ERROR lines and the node's memory, but not the record | REQ-523 notes (unchanged) | `Redis_ReplyLost.cfg`: `Inv_EveryResetLogged` violated (9 states, accepted), `Inv_RecordUntilAck` passes (178,576). `Redis_SCN500LostReply.cfg`: trap violated in 12 states, with the record alone keeping n1 Degraded | holds |
| Health stays Degraded until acknowledged, "unless the store loses it in a way no node detects" | REQ-523 notes | Erased only by undetected losses: P2 (rollback, 10 states), P4 (late-join flush, 14), `Redis_LivReplyLostLateAdv.cfg` (17), P5 (eviction, 11). A detected loss leaves the record: `Redis_ReplyLost2.cfg` (4,494,908), P3 (962,678), P6 (flush and rollbacks, 6,658,581) | holds |
| A later loss no node detects as a reset (late-join flush, undetected rollback, NFR-31) takes the record with it | REQ-523 notes | As above. Eviction is a third case (P5), inside the class. A rollback to an image taken after the record, and job-record eviction, do not take it | holds; "takes" is too strong in the safe direction (Notes to correct) |
| A node that remembers the reset writes it back (REQ-532) | REQ-523 notes | `Redis_LivLateAdv2.cfg` `Liv_RecordRestored` (175,022), `Redis_LivFlush2.cfg` (318,426), P5b (eviction, 31,595) | holds |
| After a lost reply no node remembers it, and health then returns to Healthy | REQ-523 notes | P2, P4, P5L (lasso), `Redis_LivReplyLostLateAdv.cfg`. P1: a node that remembers an earlier reset re-writes the record and health stays Degraded | holds; P1 is a safe-direction exception REQ-532's note names and REQ-523's does not |
| A lost-reply record has no node that remembers it, so REQ-532 cannot restore it | REQ-532 notes | A-32. P2, P4 and P5 end with no node remembering | holds |
| A later reset that is detected is recorded in turn (REQ-523) | REQ-532 notes | `Redis_ReplyLost2.cfg` `Inv_RecordUntilAck` (4,494,908), `Redis_LivReplyLost2.cfg` `Liv_RecordRestored` (199,106), P3 (late first look, 962,678), P6 (a flush and up to two rollbacks, 6,658,581). `Inv_RecordUntilAck` holds vacuously while a loss stays undetected, so it checks exactly "detected, then recorded" | holds |
| A later loss no node detects (NFR-31) removes it unless some node still remembers an earlier unacknowledged reset | REQ-532 notes | Removes: P2, P4, P5. Unless: P1 (17 states; 2,129,386 explored) | holds; "(NFR-31)" leaves out REQ-531's eviction (Notes to correct) |
| Either undetected loss (the late-join flush, a rollback within one RecurringReconcileInterval) also removes the record of an earlier lost-reply reset | NFR-31 statement and notes | Late-join flush: P4, `Redis_LivReplyLostLateAdv.cfg`. Rollback: P2. The age bound cannot be checked without a clock (A-21) | holds; a rollback removes it only if its image predates the record (Notes to correct) |
| F-9: exactly one node reports each reset and the others reconcile silently; it follows from the atomic write | REQ-507 notes | `Redis.cfg` `Inv_OneEventPerReset` (348,597), A-19, A-31. With a lost reply no node logs the report (`Redis_ReplyLost.cfg` `Inv_EveryResetLogged`), which REQ-523's notes accept | holds; "exactly one" is at most one (Notes to correct) |
| F-9: only the node that makes REQ-507's replacement reports the reset | REQ-523 notes | A-31: `DetectReset` and the store side of `ReplyLost` only. `Inv_OneEventPerReset` on `Redis.cfg` | holds |
| Run 3 F-5: REQ-528's first write also writes a reconciling marker and must not report a reset (SCN-503) | REQ-523 notes | `InitMarker` writes a flagged marker and no record. `Redis_Fresh.cfg` `Inv_NoFalseReset` (1,096), `Redis_SCN503.cfg` trap (8 steps) | holds |
| F-9 and F-13: the nodes other than the one that replaced the marker under REQ-507 reconcile silently | REQ-530 notes | `Learn` (A-31: records and logs nothing). After a lost reply the writer joins here too (A-32), which the sentence does not exclude | holds |

## Notes to correct (annotation only, not edited)
Fixed since run 9: the four stale compare-and-set notes (REQ-507 F-9, REQ-523 F-9 and run 3 F-5, REQ-530 F-9/F-13) now describe what holds today, and run 9's optional REQ-532 wording ("unless some node still remembers an earlier unacknowledged reset") is applied.

Optional, all in the safe direction or pointers only. The model contradicts none of them:
- REQ-523 notes: "after a lost reply no node remembers it, and health then returns to Healthy". A node that remembers an *earlier* unacknowledged reset still re-writes the record (P1), as REQ-532's note now says. Exact: "…health then returns to Healthy unless some node still remembers an earlier unacknowledged reset (REQ-532)". This is run 9's "returns" → "can return" point, still open.
- REQ-523 notes: "a later loss of store data that no node detects as a reset … takes the record with it". Exact: "can take". A rollback to an image taken after the record was written brings the record back, and the eviction of a job record leaves it.
- REQ-532 notes: "a later loss that no node detects (NFR-31)". Runtime eviction of the record key under REQ-531 is such a loss too (P5). Exact: "(NFR-31, REQ-531)".
- NFR-31: "either of these undetected losses also removes the unacknowledged record". The rollback removes it only when the image is from before the record, as in P2. Exact: "can also remove". NFR-31 does not mention runtime eviction; REQ-531's ERROR is where operators learn of it.
- REQ-507 notes, F-9: "exactly one node reports each reset". With a lost reply no node logs it (accepted in REQ-523's notes), and the late-join flush is reported by none (accepted in NFR-31). Exact: "at most one node reports each reset, and exactly one when the detecting script's reply arrives".

## Checked and accepted (not findings)
| Check | Config | Result | Why it is not a finding |
|---|---|---|---|
| *(moved from run 9 F-1)* An undetected rollback after a lost reply erases the record | probe P2 | `Trap_Erased` violated (10 states, as in run 9) | REQ-523's notes now name the class ("unless the store loses it in a way no node detects", "an undetected rollback, NFR-31"), and NFR-31's clause says either undetected loss removes the record. P2b (no lost reply) never reaches the trap (1,247,312) |
| *(new)* Runtime eviction of the reset record after a lost reply | probe P5, P5L | `Trap_EvictErased` violated (11 states); `Liv_RecordRestored` violated (P5L, lasso, 170,044 explored) | Inside REQ-523's class wording. REQ-531 states that eviction is not detected, and REQ-505 refuses to start on such a server. P5b: with a node that remembers, REQ-532 re-writes the record. The action is a probe extension (A-37) |
| A lost reply loses both ERROR lines | `Redis_ReplyLost.cfg` | `Inv_EveryResetLogged` violated (9 states) | REQ-523's run-7 note. The record is there (`Inv_RecordUntilAck` passes), and health shows the reset |
| *(from run 8 F-1)* An unacknowledged record erased by an unreported late-join flush after a lost reply | `Redis_LivReplyLostLateAdv.cfg` | `Liv_RecordRestored` violated (17 states this run, 20 in run 9; ends stuttering. Same shape: n2's lost-reply write, a second FLUSHALL while n2 reconnects, n1's first marker, the wait and the advance to 5) | REQ-523's and REQ-532's notes and NFR-31's late-join clause |
| *(from run 8 F-1)* The same with no read between the two flushes | probe P4 | `Trap_Erased` violated (14 states, the shortest) | As above. It is also the reason REQ-523's note gives for not choosing "every reader remembers" |
| An undetected later flush, with a node that remembers an earlier unacknowledged reset | probe P1 | `Trap_P1_UndetectedKeeps` violated (17 states): REQ-532 re-writes the record after the unreported flush | Safe direction. REQ-532's note now says so |
| A late-join flush hidden while the node that saw the old marker makes no read | `Redis_LivLateJoinAdv.cfg` (run 9) | `Liv_LossReported` violated (15 states; ends stuttering) | Run-3 F-3 option 2, documented in REQ-528's notes and NFR-31 |
| Rollback to older data (restore, lagging replica) | `Redis_Restore.cfg`, `Redis_RestoreOlder.cfg` (run 8) | `Inv_NoLostOutcome` (10, 11 steps), `Inv_SingleClaim` (11, 12), `Inv_ConcurrencyKeyMax` (11, 12) violated | Run-2 F-5, option 2 accepted (REQ-507 and REQ-526 notes, NFR-31) |
| Runtime eviction of job records (the policy changes after startup) | `Redis_Evict.cfg` (run 8) | `Inv_ConcurrencyKeyMax` (12 steps), `Inv_NoLostOutcome` (11) violated | REQ-531 states that resets caused by eviction are not detected; REQ-505 refuses eviction at startup |
| A lease-lost run beside a newer claim | every cfg | excluded from `Inv_ConcurrencyKeyMax` and `Inv_SingleClaim` (A-18) | The stated rule: a run that did not heartbeat for a whole LeaseDuration has lost its lease, as under jobs REQ-132 |
| Counterfactual: the run-5 wording of REQ-507 (read, then a separate compare-and-set) | `Redis_HideRace.cfg` (run 8) | `Inv_HiddenOnlyIfPaused` violated (14 steps), as expected | Shows why run 5 F-1 needed the change; not the requirement any more |
| Counterfactual: the run-7 wording of REQ-523 (record written by the node after the reply) | `Redis_ReplyLostRun7.cfg` (run 8) | `Inv_RecordUntilAck` violated (9 steps), as expected | Shows that the invariant catches run 7 F-1; not the requirement any more |

## Passed checks
Rows marked *(rerun)* were checked again in this run. Every one has run 8's distinct-state count. The other rows are run 8's results, which still hold because the model and the cfgs are unchanged.

| Check | Config | Distinct states | Meaning |
|---|---|---|---|
| `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_UnackedUntilOperator`, `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Inv_RecordUntilAck`, `Scn_NoClaimWhileFlagged` | `Redis.cfg` (two workers, one flush) *(rerun)* | 348,597 each | One report per flush, no false report, "a detected flush ends every lease", and the record kept until acknowledged |
| all eight safety invariants | `Redis_Flush2.cfg` (second flush during a reconciliation) | 2,856,201 | Two flushes with the restarted REQ-509 wait; the record is written again after the second |
| all eight safety invariants | `Redis_LateJoin.cfg` | 907,278 | A late first look (REQ-528's first marker beside a node that saw the old one): one report, no false one, record kept |
| `Inv_RecordUntilAck`, `Inv_UnackedUntilOperator`, `Inv_HiddenOnlyIfPaused`, `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim` | `Redis_ReplyLost.cfg` (one job, one flush, one lost reply) *(rerun)* | 178,576 | The lost reply leaves the record, and the flush is not hidden |
| `Inv_RecordUntilAck`, `Inv_UnackedUntilOperator`, `Inv_NoFalseReset`, `Inv_OneEventPerReset` | `Redis_ReplyLost2.cfg` (one job, two flushes, up to two lost replies) *(rerun)* | 4,494,908 | A detected second flush, with its own reply lost too, is recorded in turn (REQ-532 note) |
| `Liv_LossReported`, `Liv_Reseeded`, `Liv_RecordRestored` | `Redis_LivReplyLost.cfg` | 162,454 | The lost-reply flush counts as detected (A-33), and the pause still ends |
| `Liv_RecordRestored`, `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivReplyLost2.cfg` (no jobs, two flushes, two lost replies) *(rerun)* | 199,106 | A record erased by the second flush comes back through that flush's own detection |
| `Liv_RecordRestored` | `Redis_LivLateAdv2.cfg` (no jobs, two flushes, late join, one advance, no lost reply) *(rerun)* | 175,022 | REQ-532 re-writes the record after an unreported late-join flush when a node remembers |
| `Liv_LossReported`, `Liv_UnackedRestored`, `Liv_Reseeded`, `Liv_RecordRestored` | `Redis_LivFlush2.cfg` *(rerun)* | 318,426 | Two flushes; a record erased by the second is restored (REQ-532) |
| `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_RecordUntilAck` | `Redis_RestoreFR.cfg` *(rerun)* | 210,590 | Rollbacks cause no false or double report and do not separate a marker from its record (replies always arrive; with a lost reply see P2 and P6) |
| `Inv_ResetSinceClaimSound`, `Inv_NoFalseReset`, `Inv_ConcurrencyKeyMax` | `Redis_Fresh.cfg` (two workers, new server) *(rerun)* | 1,096 | A new server is initialised, not reported (SCN-503; REQ-523's reworded run 3 F-5 note) |
| SCN-500 with the reply lost: trap violated, as expected | `Redis_SCN500LostReply.cfg` *(rerun)* | 5,228 (explored before the stop) | Reachable in 12 states; health kept Degraded by the record alone |
| SCN-503 trap violated, as expected | `Redis_SCN503.cfg` *(rerun)* | 72 | Reachable in 8 steps |
| `Liv_Reseeded` | `Redis_LivLateJoinAdv.cfg` (run 9) | 96,724 | The pause always ends, with an advance too |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique2During.cfg` / `Redis_Recurring2During.cfg` | 2,893,397 / 2,177,993 | Unique keys and occurrences across two flushes |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique2.cfg` / `Redis_Recurring2.cfg` (second flush after the first reconciliation) | 1,014,197 / 837,857 | An expired run is not brought back (REQ-522) |
| `Inv_SingleClaim`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost` | `Redis_Flush2Late.cfg` (two flushes, a late first look, one job) | 921,195 | REQ-521 under resetSinceClaim |
| `Inv_HiddenOnlyIfPaused`, `Inv_HiddenRunsLeaseLost`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_ConcurrencyKeyMax` | `Redis_Hide.cfg` | 119,197 | A hidden flush needs every node that saw the old marker to make no read (replies always arrive) |
| `Inv_HiddenOnlyIfPaused`, `Inv_HiddenRunsLeaseLost` | `Redis_Hide2.cfg` (two jobs) | 1,105,989 | The same with a claim beside a running job |
| `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Scn_NoClaimWhileFlagged` | `Redis_Outage.cfg` / `Redis_Drop.cfg` | 1,906,584 / 1,475,436 | Outages and single-node drops during the pause |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique.cfg` / `Redis_Recurring.cfg` (one flush) | 310,693 / 265,981 | REQ-534 and the occurrence pause |
| `Inv_UniqueKey` | `Redis_Shard.cfg` | 1,240 | jobs INV-100's per-queue scope matches INV-500 |
| `Liv_Reseeded`, `Liv_MarkerWritten` (LIV-501), `Liv_LossReported`, `Liv_UnackedRestored` | `Redis_Liveness.cfg` | 33,469 | One flush: re-seeded, marker written, reported, record kept (REQ-532) |
| `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivRestore.cfg` | 392,700 | A rollback to an older marker is eventually reported |
| `Liv_Reseeded` | `Redis_LivOutage.cfg` / `Redis_LivDrop.cfg` (`Liv_LossReported` too) | 6,299 / 141,700 | No stuck pause after a reconnection |
| `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivLateJoin.cfg` | 27,450 | A late first look is reported (no advance) |
| `Liv_Reseeded`, `Scn_ClientNoDetect` (SCN-506) | `Redis_ClientOnly.cfg` | 10,556 | A client-only node never reconciles |
| `Inv_UnreachableIsUnhealthy`, `Inv_UnhealthyOnlyWithCause` | `Redis_Health.cfg` | 47,178 | Health precedence matches hosting |
| `Scn_NoEvalNoReady` (SCN-501) | `Redis_SCN501.cfg` | 56 | A server without EVAL never becomes ready |
| `Scn_NoClearBeforeWait` (SCN-509) / `Scn_NoRevivalAfterExpiry` (SCN-510) | `Redis_SCN509.cfg` / `Redis_SCN510.cfg` | 2,856,201 / 837,857 | Negative scenarios hold; their steps 1–3 are reachable (`Redis_SCN509Reach.cfg` 12 steps, `Redis_SCN510Reach.cfg` 15 steps) |
| SCN-500, 504, 505, 507 and 508 traps violated, as expected | `Redis_SCN5xx.cfg` | 1,014 / 10,691 / 973 / 27,414 / 1,368 | Positive scenarios are reachable in 10, 15, 10, 14 and 12 steps |

The state counts of violated checks are the states explored before TLC stopped, so they vary from run to run with the parallel search (P1: 2,129,386 here, 2,105,889 in run 9, trace length 17 in both; `Redis_SCN500LostReply.cfg` 5,228 here, 5,275 in run 9, 12 states in both). Liveness counter-examples can also differ in length: `Redis_LivReplyLostLateAdv.cfg` gave 17 states here and 20 in run 9, with the same shape.

**Probes** (run 10, `$TEMP/redis10_probe`, `--stop-at-first`, 4 workers; no jobs, `MaxTok = 0`, `LostReply = TRUE` unless stated). P1 to P4 and P2b are run 9's, rerun unchanged:
| Probe | Bounds | Check | Result | Used for |
|---|---|---|---|---|
| P1 | three workers, three flushes, late join, one advance, one lost reply that comes after a detection with its reply (`ActC_LostAfterReply`) | `Trap_P1_UndetectedKeeps` | violated, 17 states (2,129,386 explored) | REQ-532 "unless some node still remembers" |
| P2 | two workers, flush and rollback (`LossKinds = {"flush", "restore"}`, `MaxLosses = 2`), one advance, one lost reply | `Trap_Erased` | violated, 10 states | undetected rollback (REQ-523, REQ-532, NFR-31); run 9 F-1, now accepted |
| P2b | P2 without a lost reply (`LostReply = FALSE`, `MaxDrops = 0`) | `Trap_Erased` | passes, 1,247,312 states | baseline: with the reply, the rollback is detected |
| P3 | the constants of `Redis_LivReplyLostLateAdv.cfg` | `Inv_RecordUntilAck` | passes, 962,678 states | "a later reset that is detected is recorded in turn", with a late first look |
| P4 | the constants of `Redis_LivReplyLostLateAdv.cfg` | `Trap_Erased` | violated, 14 states (shortest) | the late-join flush; the no-read shape |
| P5 *(new)* | P2's two workers, `LossKinds = {"flush", "evict"}`, `PolicyChange = TRUE`, `MaxLosses = 2`, no advance, one lost reply; `Spec10` adds `EvictRecord` (A-37) | `Trap_EvictErased` | violated, 11 states | runtime eviction is inside REQ-523's class |
| P5L *(new)* | P5 | `Liv_RecordRestored` | violated, lasso back to state 20 (170,044 explored) | after the eviction nothing writes the record back |
| P5b *(new)* | P5 without a lost reply (`LostReply = FALSE`, `MaxDrops = 0`) | `Liv_RecordRestored` | passes, 31,595 states | REQ-532 re-writes an evicted record when a node remembers |
| P6 *(new)* | P2's constants | `Inv_RecordUntilAck` | passes, 6,658,581 states | a detected later loss after a lost reply, flush or rollback, is recorded in turn |
| P6c *(new)* | P6 with `MaxLosses = 3` | `Inv_RecordUntilAck` | timeout: stopped after 300 s, not finished. An extra bound beyond P6; no result rests on it | the same with one more loss |

**P5, the eviction example** (11 states): n1 and n2 run and both read the marker at 2. The maxmemory-policy changes to an evicting one (a failover to a differently configured replica, or CONFIG SET; REQ-531 logs its ERROR at the next connection). FLUSHALL (R1). n1's script replaces the marker with 3 and records R1, and the reply is lost (A-32). The server then evicts the reset record's key. The marker is still 3 and flagged, so n2, and n1 after reconnecting, join it silently (REQ-530), finish the wait and clear the flag (REQ-509). Nobody remembers R1, no loss is pending, no node can find the record missing, and neither ERROR line was logged. Health returns to Healthy without an acknowledgement (P5L ends in a lasso through the operator's maintenance toggles).

The P2, P4 and P1 traces are run 9's, with the same lengths. P2: both nodes read 2, FLUSHALL, n1's script writes 3 and the record and loses its reply, and the server rolls back to the image from before the flush. P4: n1 reads 2 and n2 has not looked yet, FLUSHALL, n1's lost-reply write, a second FLUSHALL while n1 reconnects, n2's first marker, the wait and the advance to 5. P1: n1 detects R1 with its reply and remembers it, a second flush is detected by n1 with its reply lost, a third flush erases the record, n1 re-writes it from its memory of R1 (REQ-532), and the third flush is then hidden by n2's first marker and the advance.

Bounded checks:
- `Redis_Flush2.cfg`, the `*2During` cfgs and SCN-509 allow the second flush only while a node is reconciling (`ActC_SecondLossDuringReconcile`).
- `Redis_Unique2.cfg`, `Redis_Recurring2.cfg` and SCN-510 allow it only after the first reconciliation has ended everywhere (`ActC_SecondLossAfterReconcile`).
- `Redis_ReplyLost2.cfg` and the three record liveness cfgs put no constraint on when the second flush comes.
- `Redis_HideRace.cfg` (counterfactual) keeps the read-to-write window shorter than one LeaseDuration (`ActC_ShortCAS`, A-29).
- `Redis_Flush2Late.cfg` runs with one job, as in runs 4 to 9. `Inv_NoFalseReset` under rollbacks is checked on `Redis_RestoreFR.cfg` (one job, one claim).
- `Redis_ReplyLost.cfg`, `Redis_ReplyLostRun7.cfg` and `Redis_LivReplyLost.cfg` run with one job and at most one lost reply. `Redis_ReplyLost2.cfg` has one job and up to two lost replies.
- `Redis_LivReplyLost2.cfg`, `Redis_LivReplyLostLateAdv.cfg`, `Redis_LivLateAdv2.cfg` and all probes run with no jobs (`Jobs = {}`, `MaxTok = 0`). With one job the liveness cfgs time out. The record rules (REQ-523, REQ-524, REQ-525, REQ-532) read no job state, and every marker read that detects a reset can also happen as its own step (A-2).
- P1 orders the lost reply after a detection with its reply (`ActC_LostAfterReply`, A-36). P5 has no advance (`MaxAdvances = 0`).

## Modeling assumptions
Decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. Changes since run 9 are marked.
| # | Assumption | Affects |
|---|---|---|
| A-1 | "The store is ready" (REQ-500) is one of the startup checks of hosting REQ-18 | REQ-500, REQ-502, REQ-505, SCN-501 |
| A-2 | The marker reads of a worker's claim, heartbeat and completion scripts and of its REQ-509 clear apply REQ-507, REQ-528 and REQ-530 before their own effect (`ReadOK`). Other reads (REQ-527, REQ-510, plain looks) can happen at any time, so REQ-507/528/530 can also run as their own step | REQ-507, REQ-528, REQ-530 |
| A-3 | Re-seeding writes the recurring definitions, the queue registry and the node's registration in one step | REQ-507, REQ-528, REQ-530, LIV-500 |
| A-5 | Only `actor: system` steps are (weakly) fair, including heartbeats (jobs REQ-126), plus the passage of time (`LeaseElapses`). The server becomes unreachable at most once per run, every outage ends, and a dropped node reconnects | all liveness checks |
| A-6 | used_memory above RedisMemoryDegradedShare is a boolean that can change at any time; HealthyAfterPasses = 1 | REQ-519, REQ-520 |
| A-8 | A stopped node's run and memory disappear with it, and a stopped node does not start again (so P1 needs a third worker for its late first look) | `Redis_ClientOnly.cfg`, P1 |
| A-9 | "Processing at once" in jobs INV-108, and "holds an unexpired claim" in INV-103, mean handlers running under a claim whose lease has not expired | run-3 F-1 |
| A-10 | All model jobs share one concurrency key; with `UniqueKeys` they share one unique key; with `Recurring` they are occurrences of one recurring job with overlap Skip | run-3 F-2 |
| A-12 | A restore or failover rolls the whole server back to an image taken earlier, marker and record included. The first image is the initial store (marker 2, no record), so a rollback can go to before the first flush | accepted rollback rows, `Redis_RestoreFR.cfg`, P2, P6 |
| A-14 | Job ids and lease tokens are fresh | all |
| A-16 | A refused heartbeat or completion (jobs INV-128) does not stop the handler | run-3 F-2 |
| A-17 | Without `LateJoin`, every worker has read the marker before data is lost. With `LateJoin`, at least one has; REQ-528's notes accept that a loss no running node saw goes unreported | late-join cfgs |
| A-18 | **LeaseDuration without a clock.** See below. | every safety result |
| A-19 | REQ-507's and REQ-528's read and write are one atomic step (`DetectReset`, `InitMarker`), as the sentences say since run 6. `SplitCAS` keeps the run-5 wording only as a counterfactual | REQ-507, REQ-528 |
| A-21 | Only a rollback to an older marker value counts as a detectable loss in `Liv_LossReported`; same-value rollbacks and runtime evictions are documented as undetected (NFR-31, REQ-531). A rollback is also undetectable when its marker is older than the current one but no node has seen anything newer, as after a lost reply (P2). `Hidden` covers both. *(run 10)* Without a clock the model cannot check NFR-31's "less than one RecurringReconcileInterval old" for either kind | `Liv_LossReported`, P2, NFR-31 |
| A-22 | A node remembers the last value it saw from ordinary reads, claims and its own writes (glossary `lastSeenMarker`). A heartbeat or completion that reads a newer unflagged value is the same as an ordinary read followed by the heartbeat (`Observe`), so it is not modeled separately | REQ-507, REQ-530 |
| A-24 | Marker values and last-reset values from "the Redis server's current time" (REQ-507, REQ-527, REQ-528) are a counter that every new time value increases, flushes and rollbacks included. REQ-528's lowest value is below every such value | REQ-507, REQ-527, REQ-528 |
| A-25 | A node "has finished a value's reconciliation" once REQ-509 found the marker at that value, cleared or already unflagged (REQ-530 notes) | REQ-530, LIV-500 |
| A-26 | A single node can lose its connection (REQ-529) while the others stay connected; its store is connecting until it reconnects, and it neither heartbeats nor completes meanwhile | `Redis_Drop.cfg`, `Redis_LivDrop.cfg`, `Redis_*ReplyLost*.cfg` |
| A-27 | "Paused" in NFR-31 and the REQ-528 notes means the node makes no marker read between the flush and the advance (`readInWindow`). A node whose store is connecting makes no reads, so it counts as paused | REQ-528, NFR-31 |
| A-28 | A script's read and the node's response to it (REQ-507/528/530) are ordered response-first: the claim, heartbeat or completion takes effect only once no sentence applies. When the reply arrives, the script's REQ-507/528 write and the node's response are one step. With `LostReply`, the write can happen without the response (A-32) | REQ-526, REQ-522, REQ-521, REQ-523 |
| A-29 | (counterfactual only) With `SplitCAS`, the window between the read and the compare-and-set is shorter than one LeaseDuration (`ActC_ShortCAS`) | `Redis_HideRace.cfg` |
| A-30 | A refused claim attempt (marker missing or flagged) is not modeled as a read. Whether a reconciling node keeps calling its claim script does not matter for detection: with the write in the read, nothing can land between them | REQ-507 |
| A-31 | REQ-523's trigger, "this node replaces the generation marker under REQ-507", is `DetectReset` (and its store side in `ReplyLost`). `InitMarker` (REQ-528) and `Learn` (REQ-530) record nothing | REQ-523, REQ-530 |
| A-32 | `LostReply`: a connection drop (REQ-529) can come between the server running the script that makes REQ-507's write and the node receiving its reply. The write stands, unacknowledged record included (REQ-523, TECH-130). The node learns nothing: it logs neither ERROR, remembers nothing, its store is connecting and its last-seen value is unchanged. This is an environment event, not fair, at most `MaxDrops` per run, and it is on only in `Redis_*ReplyLost*.cfg`, `Redis_SCN500LostReply.cfg` and the probes (not P2b, P5b). A client-side timeout has the same effect but is not modeled | REQ-523, REQ-532, probes |
| A-33 | A loss counts as detected (`pendingLoss` ends) once a node's script has replaced the marker under REQ-507, reply or not, because that replacement writes the record. Whether the two ERROR lines were logged is tracked apart from this (`silentReset`, `Inv_EveryResetLogged`) | `Liv_LossReported`, `Inv_HiddenOnlyIfPaused`, `Inv_RecordUntilAck` |
| A-34 | The store holds one reset record (`resetRec`: none, unacknowledged or acknowledged), not one per reset. A later detection overwrites it, and REQ-532's "record of that reset" is that record. An acknowledgement covers every reset recorded before it (`owed` ends). With one record per reset, a detected later loss writes its own record rather than restoring the lost-reply one, and in P1 REQ-532 re-writes the earlier reset's record. Health and acknowledgement are the same either way | REQ-523, REQ-525, REQ-532, `Inv_RecordUntilAck`, `Liv_RecordRestored` |
| A-35 | `RewriteRecord` (REQ-532) requires the node to be running and the server reachable, but not the node's own connection, so it can fire while that node is reconnecting. That makes a re-write earlier, never adds or removes one. No result above depends on it. Tighten the guard (`rs[n] # "Connecting"`) the next time the model changes | REQ-532, P1 |
| A-36 | (probe only) `ActC_LostAfterReply`: in P1 the one lost reply comes after a detection with its reply | P1 |
| A-37 | *(new, probe only)* `Redis.tla`'s eviction (`EvictJob`) removes job records only, never the marker or the reset record. P5 adds `EvictRecord` in `RedisProbe10` (`Spec10`): on an evicting server, the record's key is removed, which is not a pending (detectable) loss (REQ-531). Eviction of the marker key is not added: the next read finds it missing, which REQ-507 reports | REQ-531, REQ-523, REQ-532, P5 |

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
- `python run_all.py [cfg …]` runs each invariant and each property alone with `--stop-at-first`, and enforces a 170 s limit per run. `TLC_WORKERS` sets the worker count (default 4; this run used 4). Results go to `runs/` and `run.md`, which are gitignored. Set `RUN_INDEX=name.json` to write a separate index (this run: `run10.json`). Cfgs whose name contains `_SCN` followed by a number run as scenarios (`--no-deadlock`, trap as written); the name may continue after the number (`Redis_SCN500LostReply`).
- This run: `python run_all.py Redis_ReplyLost.cfg Redis_ReplyLost2.cfg Redis_LivReplyLost2.cfg Redis_LivReplyLostLateAdv.cfg Redis_LivLateAdv2.cfg Redis_LivFlush2.cfg Redis_RestoreFR.cfg Redis_SCN500LostReply.cfg Redis.cfg Redis_Fresh.cfg Redis_SCN503.cfg`.
- Never run two batches in the same folder at once: TLC's `-cleanup` deletes the other batch's state directories.
- `python summary.py [filter]` lists finished checks (including older results still in `runs/`). `python trace.py runs/<cfg>__<check>.json [var …]` prints a trace as changed variables per step.

The probes are not kept in the repository. To rerun them, copy `Redis.tla` into an empty folder next to this module:
```tla
---- MODULE RedisProbe10 ----
EXTENDS Redis
NoOneRemembers == \A n \in Nodes : ~remembers[n]
Trap_P1_UndetectedKeeps == ~(Hidden /\ silentReset /\ owed /\ ~everAcked /\ resetRec = "unacked" /\ losses = 3)
ActC_LostAfterReply == (silentReset' /\ ~silentReset) => detections >= 1
Trap_Erased == ~(Hidden /\ owed /\ ~everAcked /\ resetRec # "unacked" /\ NoOneRemembers)
\* P5 only: eviction of the reset record key (A-37), not a pending loss
EvictRecord ==
  /\ "evict" \in LossKinds /\ evicting /\ LossAllowed /\ resetRec # "none"
  /\ resetRec' = "none" /\ losses' = losses + 1
  /\ UNCHANGED <<xVars, nodeVars, marker, flagged, lastReset, codeRec, registry, maint, jobRec, snap, envVars,
                 created, maintIntent, pendingLoss, falseReset, lostOutcome, lostOutcomeLL, detections,
                 everAcked, inits, owed, silentReset>>
Next10 == Next \/ EvictRecord
Spec10 == Init /\ [][Next10]_vars /\ Fairness
Trap_EvictErased == ~(~pendingLoss /\ owed /\ ~everAcked /\ resetRec # "unacked" /\ NoOneRemembers)
====
```
Use `gen_cfgs.py`'s BASE constants with `Jobs = {}`, `QueueA = {}`, `MaxTok = 0`, `LostReply = TRUE`, then the bounds in the probe table. P1 to P4 and P6 use `SPECIFICATION Spec`, P5, P5L and P5b `SPECIFICATION Spec10`. Run with `run_tlc.py RedisProbe10.tla --config <cfg> --stop-at-first`. `Hidden` is defined in `Redis.tla`: the loss is pending, the marker is present and unflagged, and no worker's last-seen value is newer, so no node can detect the loss any more.

Switches in the model that are not requirements:
- `SplitCAS`: COUNTERFACTUAL, the run-5 wording of REQ-507 (a read and a separate compare-and-set). `TRUE` only in `Redis_HideRace`.
- `LostReply`: ENVIRONMENT, the reply to REQ-507's write is lost with the connection (A-32). `TRUE` only in `Redis_ReplyLost*`, `Redis_LivReplyLost*`, `Redis_SCN500LostReply` and the probes (not P2b, P5b).
- `RecordAfterReply`: COUNTERFACTUAL, the run-7 wording of REQ-523 (the record is written by the node after the reply, so a lost reply loses it). `TRUE` only in `Redis_ReplyLostRun7`.
- `TrackHidden`: keeps the history variables of `Inv_HiddenOnlyIfPaused` and `Inv_HiddenRunsLeaseLost`. `TRUE` only in `Redis_Hide*` and `Redis_ReplyLost`.

With all four `FALSE`, `casPending`, `found`, `foundLR`, `silentReset` and the hidden-flush history variables stay constant, and `ReplyLost` is disabled. `Redis.cfg` has 348,597 states, as in runs 5 to 9.

## Next
No finding needs a decision. If you want the notes exact, the five optional wording points under *Notes to correct* can go into one annotation edit of `specs/redis.json` (REQ-507, REQ-523, REQ-532) and `non-functional-requirements.md` (NFR-31) with the `refiner-requirements` skill. None of them changes behaviour or needs a rerun of the model.

These questions were already open and are unchanged by this run: one marker per hash tag under ShardByQueue (TECH-130, including where the reset record lives; a failover of only that shard would be another loss no node detects), the StaleNodeAge value (REQ-533), and whether REQ-531 should report Unhealthy instead of an ERROR. A-35's guard should be tightened the next time `Redis.tla` changes.
