# Findings: Bellhop Redis store behaviour

<!-- refiner-findings v1 | module: redis | specHash: 7bcd94d03e2daf303b36f0c332801df8419a33efeadb775b52a9515abc20bb8b | run: 2026-11-08 (run 9) | previous: specs/model/redis/previous.findings.md (run 8, specHash 7bcd94d03e2d) -->

**Run:** 2026-11-08, run 9 · **Requirements file:** `specs/redis.json` (specHash `7bcd94d03e2d`, unchanged) · **Model:** `specs/model/redis/Redis.tla` (49 cfgs from `gen_cfgs.py`, both byte-identical to run 8, b7e58b5) · **TLC:** 2.19.
Since run 8 only annotation changed (f2bc587). `reqs.py diff` against b7e58b5 reports no changes and the same specHash, so `Redis.tla`, every cfg and every run-8 result stay valid. This run reran only the 8 cfgs that are evidence for the new notes: 25 checks, each alone with `--stop-at-first --workers 4` and a 170 s limit. All 25 have run 8's result, and every passed check has run 8's distinct-state count. Everything else rests on run 8's complete batch (123 checks, all with the expected result), with the model unchanged. It also ran six probes in `$TEMP/redis9_probe` (module `RedisProbe9`, which `EXTENDS Redis` and adds definitions only; see How to reproduce). Another module was being checked in a sibling folder.
**Timeouts:** none. **TLC exceptions:** none.
**Result:** 1 finding: 0 contradictions · 1 gap · 0 unprovable · 0 ambiguities · 0 modeling notes. Run 8's only finding is resolved (documented).

**What was checked.** Each sentence added by f2bc587 is checked against the model and against run 8's evidence (table under *The new notes against the model*):
- REQ-523's run-7 sentence: with a lost reply, both ERROR lines and the node's memory are lost, the record is not, and health stays Degraded until an operator acknowledges, "with one exception (run 8 F-1)". The first part holds. **The "one exception" does not**: an undetected rollback after a lost reply is a second one (F-1).
- REQ-523's run-8 sentence (the exception) and its "not chosen" clause (no node may read between the two flushes) hold. The shortest erasure has no read between the two flushes.
- REQ-532's run-8 sentence holds for everything it warns about. Its "only if" is slightly too strong, but only in the safe direction (next section).
- NFR-31's new late-join clause holds. TECH-130's new open question is static and agrees with run 8's ShardByQueue paragraph.

**The REQ-532 question from the brief.** *"A record written by a script whose reply was lost (REQ-523) has no node that remembers it, so it survives a later flush only if that flush is itself detected and recorded."*
- **A detected later flush never loses it.** Every detection is a REQ-507 replacement, and the record is written in the same atomic step, reply or not (REQ-523, TECH-130). "Detected and recorded" is therefore one condition. `Inv_RecordUntilAck` passes on `Redis_ReplyLost2.cfg` (4,494,908 states; the second flush with its reply lost too). It also passes on probe P3, which adds a late first look to the lost reply (962,678 states). There the second flush is the REQ-528 first marker, and a node that saw an earlier marker finds it older (REQ-507). `Liv_RecordRestored` passes on `Redis_LivReplyLost2.cfg` (199,106). Strictly, what the store holds afterwards is the record the later detection wrote. The model keeps one record (A-34), so this is "the record". With one record per reset, the lost-reply reset's own record would not come back, but the new one keeps health Degraded until an operator acknowledges.
- **An undetected later flush erases it**, as the note says: `Redis_LivReplyLostLateAdv.cfg` (20 states) and probe P4 (14 states, the shortest). The one case the note misses is in the safe direction. If some node still remembers an *earlier* unacknowledged reset, REQ-532 re-writes the record after the undetected flush, and health stays Degraded. Probe P1 shows this (three workers, three flushes, 17 states): n1 detects R0 with its reply, then loses the reply to its own R1 write, then R2 is an unreported late-join flush, and n1 re-writes the record. That is not a finding, because the note promises less than the system does. A more exact wording is optional (Notes to correct).
- **A rollback is not a flush**, and REQ-532's sentence does not claim to cover one. REQ-523's "one exception" does. That is F-1.

## Changes since last run
| Finding | Status |
|---|---|
| F-1 (run 8): a lost reply followed by an unreported late-join flush erases the earlier reset's record | resolved. f2bc587 applied option 1 (documented). REQ-523's notes name the exception, REQ-532's notes say a lost-reply record survives a later flush only if that flush is detected, and NFR-31's late-join clause adds the erased record. The traces are now under *Checked and accepted*: `Redis_LivReplyLostLateAdv.cfg` `Liv_RecordRestored` (rerun: 20 states, run 8: 21, ends stuttering) and the no-read shape (probe P4, 14 states) |
| F-1 (this run) | new |

`findings_delta.py` output (fingerprints; the first row uses run 8's number):

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | gap · Liv_RecordRestored/LostReply · REQ-523,REQ-524,REQ-528,REQ-532 |
| F-1 | new | gap · Trap_Erased/LostReplyRollback · REQ-507,REQ-523,REQ-524,REQ-532 |

1 resolved, 1 new, 0 still open

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | gap | low | REQ-523, REQ-507, REQ-524, REQ-532, NFR-31 | After a lost reply, a rollback to an image from before the flush is not detected and removes the record too, so health returns to Healthy without acknowledgement. REQ-523's note says the late-join flush is the only exception |

Decide **F-1**. It is the only finding, and it is about one note sentence. The rollback itself is a case NFR-31 already accepts, and it also brings back the operator state from before the flush. What is wrong is only the note's count of exceptions.

---

## F-1 · gap · low — After a lost reply, an undetected rollback also erases the record; REQ-523's note names only one exception
<!-- finding: gap | Trap_Erased/LostReplyRollback | REQ-507,REQ-523,REQ-524,REQ-532 -->

**Requirements involved**
- REQ-523's run-7 note, as corrected by f2bc587: *"If the connection drops or the call times out after the script ran, both ERROR log lines (StoreWasReset and this one) and this node's memory are lost but the record is not, and **health stays Degraded (REQ-524) until an operator acknowledges it, with one exception (run 8 F-1)**."*
- REQ-507: a read that finds the marker *"missing, or with a value older than the last value this node saw"* replaces it. Its notes say *"a rollback to a state less than one interval old is not detected"*, and so does NFR-31.
- REQ-532: *While **this node remembers** an unacknowledged store reset, if the store holds no record of that reset, the system shall re-write the record as unacknowledged.*
- REQ-524: *if … a store reset has not been acknowledged, the system shall report the node Degraded.*

**What happens** (probe P2, `Trap_Erased`, 10 states; two workers, one flush, one rollback, one lost reply, no late join)
1. Worker nodes n1 and n2 connect, run, and both read the marker at value 2 (REQ-500, hosting REQ-18).
2. FLUSHALL (reset R1).
3. n1's next marker read finds the marker missing. In one atomic step, its script replaces the marker with value 3, flagged, and records R1 as unacknowledged (REQ-507, REQ-523, TECH-130). n1's connection drops before the reply arrives (REQ-529). n1 logs nothing, does not remember R1, and its last-seen value is still 2 (A-32).
4. Before either node reads the new marker, the server rolls back to an image taken before the flush. That can be a restore, or a failover to a replica that had not received the FLUSHALL yet. The image holds marker 2 and no reset record.

Both nodes last saw 2, so neither finds the marker missing or older (REQ-507), and the rollback is never detected. The store holds no reset record, no node remembers R1 (REQ-532 has no node), and neither ERROR line was logged. The next health check that finds nothing else wrong reports both nodes **Healthy**. No operator acknowledged R1. The trap state is final: no node can detect the rollback any more, and nothing can re-write the record.

A crash of the primary is a common cause of both a lost reply and a failover, so the two arriving together is a realistic case.

**Why** A lost reply leaves the record as the only trace of the reset (run 8 F-1). It also leaves the writer's last-seen value at the old marker. With the reply, n1 would have last seen 3, found the rolled-back 2 older, and reported the rollback, which writes a new record (REQ-507, REQ-523). The baseline proves it: probe P2b, the same bounds without a lost reply, never reaches the trap (1,247,312 states). Run 8 F-1 needed an unreported late-join flush to erase the record. Here any rollback no node can see is enough.

**What this is not.** That the rollback is not detected is accepted: the image holds the marker every node last saw, which is NFR-31's *"a rollback to a state less than one RecurringReconcileInterval old is not detected"* (A-21). The work it undoes is accepted too (REQ-507 notes, run 2 F-5). The rollback also undoes the flush itself. The restored image holds the operator state from before R1, so the REQ-523 ERROR ("may have been lost and are back at their defaults") no longer describes the store. Healthy is therefore arguably the right answer. What no note covers is the sentence in REQ-523's note that names run 8 F-1 as the *only* way health can return to Healthy without an acknowledgement.

**Options**
1. *(recommended)* **Correct REQ-523's note.** Name the second exception, and say why it is benign: the rollback takes the flush back with it. NFR-31 needs no change, because its rollback clause already states that this rollback is not detected. Cost: words only.
2. **Also add it to NFR-31's rollback clause**, for example "…is not detected, including a rollback to just before a flush whose script reply was lost, which removes that flush's record too". Operators get more to read for a case where their data is back to its state before the flush. NFR-31 is in `non-functional-requirements.md`, outside this module.
3. **Have every worker that finds an unacknowledged record remember it** (run 8 F-1 option 2, still not chosen). That closes this case only if some node reads the record between the script and the rollback. In the 10-state trace, no node reads anything in that window. Not checked.

**Ready to apply (option 1)**
```json
{ "id": "REQ-523",
  "notes": "<existing notes, with 'with one exception (run 8 F-1)' changed to 'with two exceptions (run 8 F-1 and run 9 F-1)'> Run 9 F-1 (recommended option): the second exception is a rollback, before any node reads the new marker, to an image from before the flush. Every node last saw the image's marker, so the rollback is not detected (NFR-31), and it removes the record along with the flush it recorded. The image holds the operator state from before the flush, so the ERROR no longer describes the store." }
```

---

## The new notes against the model
| Claim (f2bc587) | Where | Evidence (run 9 unless marked) | Result |
|---|---|---|---|
| A lost reply loses both ERROR lines and the node's memory, but not the record | REQ-523 notes | `Redis_ReplyLost.cfg`: `Inv_EveryResetLogged` violated (9 states, accepted), `Inv_RecordUntilAck` passes (178,576). `Redis_SCN500LostReply.cfg`: the trap is violated in 12 states, with the record alone keeping n1 Degraded | holds |
| Health stays Degraded until an operator acknowledges, "with one exception (run 8 F-1)" | REQ-523 notes | The exception: `Redis_LivReplyLostLateAdv.cfg`, probe P4. A second one: probe P2 | **F-1** |
| The exception: no node remembers, so REQ-532 cannot re-write the record. The unreported late-join flush erases it, and health returns to Healthy | REQ-523 notes | `Redis_LivReplyLostLateAdv.cfg` `Liv_RecordRestored` violated (20 states, ends stuttering), the same shape as run 8 with the node names swapped. P4: 14 states | holds. "Returns to Healthy" has a safe-direction exception (P1) |
| Not chosen: remembering on every read cannot close it, because no node may read between the two flushes | REQ-523 notes | P4, the shortest erasure: between R1's write and R2, n1 is reconnecting after its lost reply and n2 has not looked yet. No marker or record read happens in that window | holds |
| A lost-reply record has no node that remembers it | REQ-532 notes | A-32. Baseline `Redis_LivLateAdv2.cfg`: `Liv_RecordRestored` passes (175,022) when the detector got its reply and remembers | holds |
| ...so it survives a later flush only if that flush is detected and recorded | REQ-532 notes | Detected: `Redis_ReplyLost2.cfg` (4,494,908), P3 (962,678), `Redis_LivReplyLost2.cfg` (199,106). Undetected: `Redis_LivReplyLostLateAdv.cfg`, P4. Undetected but kept: P1 | holds for what it warns about. "Only if" is too strong in the safe direction (P1) |
| A late-join flush also erases the unacknowledged record of an earlier reset whose script reply was lost | NFR-31 | As the two rows above. The base clause: `Redis_LivLateJoinAdv.cfg` `Liv_LossReported` violated (15 states, accepted) | holds |
| Which hash slot REQ-523's record lives in under ShardByQueue | TECH-130 open question | Static. Matches run 8's ShardByQueue paragraph. The model's ShardByQueue switch covers unique keys only | an open question, not checked |

## Notes to correct (annotation only, not edited)
Fixed since run 8 (f2bc587): the TECH-130 open question now says "the REQ-507/REQ-528 marker write" instead of compare-and-set, and REQ-523's run-7 note now names both ERROR lines.

Still outstanding from runs 7 and 8: these notes still describe a compare-and-set that REQ-507 no longer makes.
- REQ-507 notes, F-9: "the compare-and-set makes exactly one node report each reset". The note's own run-5 sentence already corrects it.
- REQ-523 notes, F-9: "only the node that wins the compare-and-set reports the reset". Run 3 F-5: "REQ-528's first write is also a compare-and-set of a reconciling marker".
- REQ-530 notes, F-9 and F-13: "the nodes that lose the compare-and-set in REQ-507". (REQ-527's own compare-and-set is current and correct.)

New this run (optional, safe direction):
- REQ-532 notes, run 8 F-1: "it survives a later flush only if that flush is itself detected and recorded". An exact version would read: "…so after a later flush the store again shows an unacknowledged reset only if that flush is itself detected and recorded, or another node still remembers an earlier unacknowledged reset" (P1). The same applies to REQ-523's "health returns to Healthy", which would read "can return".

## Checked and accepted (not findings)
| Check | Config | Result | Why it is not a finding |
|---|---|---|---|
| A lost reply loses both ERROR lines | `Redis_ReplyLost.cfg` | `Inv_EveryResetLogged` violated (9 states): n1's script replaces the marker and writes the record, the reply is lost, and nothing is logged | REQ-523's run-7 note now says "both ERROR log lines (StoreWasReset and this one) and this node's memory are lost but the record is not". The record is there (`Inv_RecordUntilAck` passes), and health shows the reset |
| *(moved from run 8 F-1)* An unacknowledged record erased by an unreported late-join flush after a lost reply | `Redis_LivReplyLostLateAdv.cfg` | `Liv_RecordRestored` violated (20 states; 21 in run 8; ends stuttering) | REQ-523's run-8 note names this exception, REQ-532's note says the record survives only a detected flush, and NFR-31's late-join clause adds "such a flush also erases the unacknowledged record of an earlier reset whose script reply was lost" |
| *(moved from run 8 F-1)* The same with no read between the two flushes | probe P4 | `Trap_Erased` violated (14 states, the shortest) | As above. It is also the reason REQ-523's note gives for not choosing "every reader remembers" |
| *(new)* An undetected later flush, with a node that remembers an earlier unacknowledged reset | probe P1 | `Trap_P1_UndetectedKeeps` violated (17 states): REQ-532 re-writes the record after the unreported flush | Safe direction: the record is there and health stays Degraded. Only the "only if" wording is affected (Notes to correct) |
| A late-join flush hidden while the node that saw the old marker makes no read | `Redis_LivLateJoinAdv.cfg` | `Liv_LossReported` violated (15 states; ends stuttering) | Run-3 F-3 option 2, documented in REQ-528's notes and NFR-31. Run 4 F-1 made "paused" mean "makes no marker read" |
| Rollback to older data (restore, lagging replica) | `Redis_Restore.cfg`, `Redis_RestoreOlder.cfg` (run 8) | `Inv_NoLostOutcome` (10, 11 steps), `Inv_SingleClaim` (11, 12), `Inv_ConcurrencyKeyMax` (11, 12) violated | Run-2 F-5, option 2 accepted (REQ-507 and REQ-526 notes, NFR-31): a claim after the copy, or a same-marker rollback that is not detected |
| Runtime eviction (the policy changes after startup) | `Redis_Evict.cfg` (run 8) | `Inv_ConcurrencyKeyMax` (12 steps), `Inv_NoLostOutcome` (11) violated | REQ-531 states that resets caused by eviction are not detected; REQ-505 refuses eviction at startup |
| A lease-lost run beside a newer claim | every cfg | excluded from `Inv_ConcurrencyKeyMax` and `Inv_SingleClaim` (A-18) | The stated rule: a run that did not heartbeat for a whole LeaseDuration has lost its lease, as under jobs REQ-132 |
| Counterfactual: the run-5 wording of REQ-507 (read, then a separate compare-and-set) | `Redis_HideRace.cfg` (run 8) | `Inv_HiddenOnlyIfPaused` violated (14 steps), as expected | Shows why run 5 F-1 needed the change; not the requirement any more |
| Counterfactual: the run-7 wording of REQ-523 (record written by the node after the reply) | `Redis_ReplyLostRun7.cfg` (run 8) | `Inv_RecordUntilAck` violated (9 steps), as expected | Shows that the invariant catches run 7 F-1, and that 43b4622 closes it; not the requirement any more |
| An undetected rollback after a lost reply erases the record | probe P2 | `Trap_Erased` violated (10 states) | The example for F-1 (it is a finding, listed here for completeness) |

## Passed checks
Rows marked *(rerun)* were checked again in this run. Every one has run 8's distinct-state count. The other rows are run 8's results, which still hold because the model and the cfgs are unchanged.

| Check | Config | Distinct states | Meaning |
|---|---|---|---|
| `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_UnackedUntilOperator`, `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Inv_RecordUntilAck`, `Scn_NoClaimWhileFlagged` | `Redis.cfg` (two workers, one flush) | 348,597 each | One report per flush, no false report, "a detected flush ends every lease", and the record kept until acknowledged |
| all eight safety invariants | `Redis_Flush2.cfg` (second flush during a reconciliation) | 2,856,201 | Two flushes with the restarted REQ-509 wait; the record is written again after the second |
| all eight safety invariants | `Redis_LateJoin.cfg` | 907,278 | A late first look (REQ-528's first marker beside a node that saw the old one): one report, no false one, record kept |
| `Inv_RecordUntilAck`, `Inv_UnackedUntilOperator`, `Inv_HiddenOnlyIfPaused`, `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim` | `Redis_ReplyLost.cfg` (one job, one flush, one lost reply) *(rerun)* | 178,576 | The lost reply leaves the record, and the flush is not hidden |
| `Inv_RecordUntilAck`, `Inv_UnackedUntilOperator`, `Inv_NoFalseReset`, `Inv_OneEventPerReset` | `Redis_ReplyLost2.cfg` (one job, two flushes, up to two lost replies) *(rerun)* | 4,494,908 | A second flush, with its own reply lost too, is recorded again (REQ-532 note, "detected") |
| `Liv_LossReported`, `Liv_Reseeded`, `Liv_RecordRestored` | `Redis_LivReplyLost.cfg` *(rerun)* | 162,454 | The lost-reply flush counts as detected (A-33), and the pause still ends |
| `Liv_RecordRestored`, `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivReplyLost2.cfg` (no jobs, two flushes, two lost replies) *(rerun)* | 199,106 | A record erased by the second flush comes back through that flush's own detection |
| `Liv_RecordRestored` | `Redis_LivLateAdv2.cfg` (no jobs, two flushes, late join, one advance, no lost reply) *(rerun)* | 175,022 | Baseline: REQ-532 re-writes the record after an unreported late-join flush when a node remembers |
| `Liv_Reseeded` | `Redis_LivLateJoinAdv.cfg` *(rerun)* | 96,724 | The pause always ends, with an advance too |
| SCN-500 with the reply lost: trap violated, as expected | `Redis_SCN500LostReply.cfg` *(rerun)* | 5,275 (explored before the stop) | Reachable in 12 states; health kept Degraded by the record alone |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique2During.cfg` / `Redis_Recurring2During.cfg` | 2,893,397 / 2,177,993 | Unique keys and occurrences across two flushes |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique2.cfg` / `Redis_Recurring2.cfg` (second flush after the first reconciliation) | 1,014,197 / 837,857 | An expired run is not brought back (REQ-522) |
| `Inv_SingleClaim`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost` | `Redis_Flush2Late.cfg` (two flushes, a late first look, one job) | 921,195 | REQ-521 under resetSinceClaim |
| `Inv_HiddenOnlyIfPaused`, `Inv_HiddenRunsLeaseLost`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_ConcurrencyKeyMax` | `Redis_Hide.cfg` | 119,197 | A hidden flush needs every node that saw the old marker to make no read (replies always arrive) |
| `Inv_HiddenOnlyIfPaused`, `Inv_HiddenRunsLeaseLost` | `Redis_Hide2.cfg` (two jobs) | 1,105,989 | The same with a claim beside a running job |
| `Inv_ResetSinceClaimSound`, `Inv_NoFalseReset`, `Inv_ConcurrencyKeyMax` | `Redis_Fresh.cfg` (two workers, new server) | 1,096 | A new server is initialised, not reported (SCN-503) |
| `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Scn_NoClaimWhileFlagged` | `Redis_Outage.cfg` / `Redis_Drop.cfg` | 1,906,584 / 1,475,436 | Outages and single-node drops during the pause |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique.cfg` / `Redis_Recurring.cfg` (one flush) | 310,693 / 265,981 | REQ-534 and the occurrence pause |
| `Inv_UniqueKey` | `Redis_Shard.cfg` | 1,240 | jobs INV-100's per-queue scope matches INV-500 |
| `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_RecordUntilAck` | `Redis_RestoreFR.cfg` | 210,590 | Rollbacks cause no false or double report and do not separate a marker from its record (replies always arrive; with a lost reply see F-1) |
| `Liv_Reseeded`, `Liv_MarkerWritten` (LIV-501), `Liv_LossReported`, `Liv_UnackedRestored` | `Redis_Liveness.cfg` | 33,469 | One flush: re-seeded, marker written, reported, record kept (REQ-532) |
| `Liv_LossReported`, `Liv_UnackedRestored`, `Liv_Reseeded`, `Liv_RecordRestored` | `Redis_LivFlush2.cfg` | 318,426 | Two flushes; a record erased by the second is restored (REQ-532) |
| `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivRestore.cfg` | 392,700 | A rollback to an older marker is eventually reported |
| `Liv_Reseeded` | `Redis_LivOutage.cfg` / `Redis_LivDrop.cfg` (`Liv_LossReported` too) | 6,299 / 141,700 | No stuck pause after a reconnection |
| `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivLateJoin.cfg` | 27,450 | A late first look is reported (no advance) |
| `Liv_Reseeded`, `Scn_ClientNoDetect` (SCN-506) | `Redis_ClientOnly.cfg` | 10,556 | A client-only node never reconciles |
| `Inv_UnreachableIsUnhealthy`, `Inv_UnhealthyOnlyWithCause` | `Redis_Health.cfg` | 47,178 | Health precedence matches hosting |
| `Scn_NoEvalNoReady` (SCN-501) | `Redis_SCN501.cfg` | 56 | A server without EVAL never becomes ready |
| `Scn_NoClearBeforeWait` (SCN-509) / `Scn_NoRevivalAfterExpiry` (SCN-510) | `Redis_SCN509.cfg` / `Redis_SCN510.cfg` | 2,856,201 / 837,857 | Negative scenarios hold; their steps 1–3 are reachable (`Redis_SCN509Reach.cfg` 12 steps, `Redis_SCN510Reach.cfg` 15 steps) |
| SCN-500, 503, 504, 505, 507 and 508 traps violated, as expected | `Redis_SCN5xx.cfg` | 1,014 / 72 / 10,691 / 973 / 27,414 / 1,368 | Positive scenarios are reachable in 10, 8, 15, 10, 14 and 12 steps |

The state counts of violated checks are the states explored before TLC stopped, so they vary from run to run with the parallel search (`Redis_SCN500LostReply.cfg` 5,275 here, 5,222 in run 8; the trace length is 12 in both).

**Probes** (run 9, `$TEMP/redis9_probe`, `--stop-at-first`, 2 or 3 workers; no jobs, `MaxTok = 0`, `LostReply = TRUE` unless stated):
| Probe | Bounds | Check | Result | Used for |
|---|---|---|---|---|
| P1 | three workers, three flushes, late join, one advance, one lost reply that comes after a detection with its reply (`ActC_LostAfterReply`) | `Trap_P1_UndetectedKeeps` | violated, 17 states (2,105,889 explored) | REQ-532 "only if" (safe-direction exception) |
| P2 | two workers, flush and rollback (`LossKinds = {"flush", "restore"}`, `MaxLosses = 2`), one advance, one lost reply | `Trap_Erased` | violated, 10 states | F-1 |
| P2b | P2 without a lost reply (`LostReply = FALSE`, `MaxDrops = 0`) | `Trap_Erased` | passes, 1,247,312 states | F-1 baseline |
| P3 | the constants of `Redis_LivReplyLostLateAdv.cfg` | `Inv_RecordUntilAck` | passes, 962,678 states | REQ-532 "detected" with a late first look |
| P4 | the constants of `Redis_LivReplyLostLateAdv.cfg` | `Trap_Erased` | violated, 14 states (shortest) | the no-read shape of run 8 F-1 |

**F-1's run-8 example, rerun** (`Redis_LivReplyLostLateAdv.cfg`, 20 states, ends stuttering; n1 and n2 swap roles relative to run 8's text): n1 reads the marker at 2, and n2 has not looked yet. FLUSHALL (R1). n1's script replaces the marker with 3 and records R1, and the reply is lost. n1 reconnects and joins 3 silently (REQ-530). A second FLUSHALL (R2) erases the marker and R1's record. n2's first read writes the lowest-value first marker without a record (REQ-528), while n1 makes no marker read. n2 clears the flag after a LeaseDuration and advances the marker to 5 (REQ-509, REQ-527). n1 then reads 5 as an ordinary newer value. No record is left, nobody remembers a reset, and nothing was logged.

**The no-read shape** (P4, 14 states): as above up to the lost reply, but R2 comes while n1 is still reconnecting. No node reads the marker or the record between R1's write and R2.

Bounded checks:
- `Redis_Flush2.cfg`, the `*2During` cfgs and SCN-509 allow the second flush only while a node is reconciling (`ActC_SecondLossDuringReconcile`).
- `Redis_Unique2.cfg`, `Redis_Recurring2.cfg` and SCN-510 allow it only after the first reconciliation has ended everywhere (`ActC_SecondLossAfterReconcile`).
- `Redis_ReplyLost2.cfg` and the three record liveness cfgs put no constraint on when the second flush comes.
- `Redis_HideRace.cfg` (counterfactual) keeps the read-to-write window shorter than one LeaseDuration (`ActC_ShortCAS`, A-29).
- `Redis_Flush2Late.cfg` runs with one job, as in runs 4 to 8. `Inv_NoFalseReset` under rollbacks is checked on `Redis_RestoreFR.cfg` (one job, one claim).
- `Redis_ReplyLost.cfg`, `Redis_ReplyLostRun7.cfg` and `Redis_LivReplyLost.cfg` run with one job and at most one lost reply. `Redis_ReplyLost2.cfg` has one job and up to two lost replies.
- `Redis_LivReplyLost2.cfg`, `Redis_LivReplyLostLateAdv.cfg`, `Redis_LivLateAdv2.cfg` and all six probes run with no jobs (`Jobs = {}`, `MaxTok = 0`). With one job the liveness cfgs time out. The record rules (REQ-523, REQ-524, REQ-525, REQ-532) read no job state, and every marker read that detects a reset can also happen as its own step (A-2).
- P1 orders the lost reply after a detection with its reply (`ActC_LostAfterReply`, A-36), so that the record's re-writer can only be a node remembering an *earlier* reset.

## Modeling assumptions
Decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. Changes since run 8 are marked.
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
| A-12 | A restore or failover rolls the whole server back to an image taken earlier, marker and record included. The first image is the initial store (marker 2, no record), so a rollback can go to before the first flush | accepted rollback rows, `Redis_RestoreFR.cfg`, F-1 |
| A-14 | Job ids and lease tokens are fresh | all |
| A-16 | A refused heartbeat or completion (jobs INV-128) does not stop the handler | run-3 F-2 |
| A-17 | Without `LateJoin`, every worker has read the marker before data is lost. With `LateJoin`, at least one has; REQ-528's notes accept that a loss no running node saw goes unreported | late-join cfgs |
| A-18 | **LeaseDuration without a clock.** See below. | every safety result |
| A-19 | REQ-507's and REQ-528's read and write are one atomic step (`DetectReset`, `InitMarker`), as the sentences say since run 6. `SplitCAS` keeps the run-5 wording only as a counterfactual | REQ-507, REQ-528 |
| A-21 | Only a rollback to an older marker value counts as a detectable loss in `Liv_LossReported`; same-value rollbacks and runtime evictions are documented as undetected (NFR-31, REQ-531). *(run 9)* A rollback is also undetectable when its marker is older than the current one but no node has seen anything newer, as after a lost reply (F-1). `Hidden` covers both | `Liv_LossReported`, F-1 |
| A-22 | A node remembers the last value it saw from ordinary reads, claims and its own writes (glossary `lastSeenMarker`). A heartbeat or completion that reads a newer unflagged value is the same as an ordinary read followed by the heartbeat (`Observe`), so it is not modeled separately | REQ-507, REQ-530 |
| A-24 | Marker values and last-reset values from "the Redis server's current time" (REQ-507, REQ-527, REQ-528) are a counter that every new time value increases, flushes and rollbacks included. REQ-528's lowest value is below every such value | REQ-507, REQ-527, REQ-528 |
| A-25 | A node "has finished a value's reconciliation" once REQ-509 found the marker at that value, cleared or already unflagged (REQ-530 notes) | REQ-530, LIV-500 |
| A-26 | A single node can lose its connection (REQ-529) while the others stay connected; its store is connecting until it reconnects, and it neither heartbeats nor completes meanwhile | `Redis_Drop.cfg`, `Redis_LivDrop.cfg`, `Redis_*ReplyLost*.cfg` |
| A-27 | "Paused" in NFR-31 and the REQ-528 notes means the node makes no marker read between the flush and the advance (`readInWindow`). A node whose store is connecting makes no reads, so it counts as paused | REQ-528, NFR-31 |
| A-28 | A script's read and the node's response to it (REQ-507/528/530) are ordered response-first: the claim, heartbeat or completion takes effect only once no sentence applies. When the reply arrives, the script's REQ-507/528 write and the node's response are one step. With `LostReply`, the write can happen without the response (A-32) | REQ-526, REQ-522, REQ-521, REQ-523 |
| A-29 | (counterfactual only) With `SplitCAS`, the window between the read and the compare-and-set is shorter than one LeaseDuration (`ActC_ShortCAS`) | `Redis_HideRace.cfg` |
| A-30 | A refused claim attempt (marker missing or flagged) is not modeled as a read. Whether a reconciling node keeps calling its claim script does not matter for detection: with the write in the read, nothing can land between them | REQ-507 |
| A-31 | REQ-523's trigger, "this node replaces the generation marker under REQ-507", is `DetectReset` (and its store side in `ReplyLost`). `InitMarker` (REQ-528) and `Learn` (REQ-530) record nothing | REQ-523 |
| A-32 | `LostReply`: a connection drop (REQ-529) can come between the server running the script that makes REQ-507's write and the node receiving its reply. The write stands, unacknowledged record included (REQ-523, TECH-130). The node learns nothing: it logs neither ERROR, remembers nothing, its store is connecting and its last-seen value is unchanged. This is an environment event, not fair, at most `MaxDrops` per run, and it is on only in `Redis_*ReplyLost*.cfg`, `Redis_SCN500LostReply.cfg` and the probes. A client-side timeout has the same effect but is not modeled | F-1 (run 8, resolved), F-1 |
| A-33 | A loss counts as detected (`pendingLoss` ends) once a node's script has replaced the marker under REQ-507, reply or not, because that replacement writes the record. Whether the two ERROR lines were logged is tracked apart from this (`silentReset`, `Inv_EveryResetLogged`) | `Liv_LossReported`, `Inv_HiddenOnlyIfPaused`, `Inv_RecordUntilAck` |
| A-34 | The store holds one reset record (`resetRec`: none, unacknowledged or acknowledged), not one per reset. A later detection overwrites it, and REQ-532's "record of that reset" is that record. An acknowledgement covers every reset recorded before it (`owed` ends). *(run 9)* With one record per reset, a detected later flush writes its own record rather than restoring the lost-reply one. Health and acknowledgement are the same either way (see the REQ-532 question) | REQ-523, REQ-525, REQ-532, `Inv_RecordUntilAck`, `Liv_RecordRestored` |
| A-35 | *(new, found in P1's trace)* `RewriteRecord` (REQ-532) requires the node to be running and the server reachable, but not the node's own connection, so it can fire while that node is reconnecting. That makes a re-write earlier, never adds or removes one: reconnection is fair, and nothing but an acknowledgement or a stop clears the memory. No result above depends on it. P1 holds after the reconnection too, because n1 still remembers R0. Tighten the guard (`rs[n] # "Connecting"`) the next time the model changes | REQ-532, P1 |
| A-36 | *(new, probe only)* `ActC_LostAfterReply`: in P1 the one lost reply comes after a detection with its reply | P1 |

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
- `python run_all.py [cfg …]` runs each invariant and each property alone with `--stop-at-first`, and enforces a 170 s limit per run. `TLC_WORKERS` sets the worker count (default 4; this run used 4). Results go to `runs/` and `run.md`, which are gitignored. Set `RUN_INDEX=name.json` to write a separate index. Cfgs whose name contains `_SCN` followed by a number run as scenarios (`--no-deadlock`, trap as written); the name may continue after the number (`Redis_SCN500LostReply`).
- This run: `python run_all.py Redis_LivReplyLostLateAdv.cfg Redis_LivLateAdv2.cfg Redis_LivReplyLost2.cfg Redis_LivReplyLost.cfg Redis_ReplyLost.cfg Redis_ReplyLost2.cfg Redis_SCN500LostReply.cfg Redis_LivLateJoinAdv.cfg`.
- Never run two batches in the same folder at once: TLC's `-cleanup` deletes the other batch's state directories.
- `python summary.py [filter]` lists finished checks (including older results still in `runs/`). `python trace.py runs/<cfg>__<check>.json [var …]` prints a trace as changed variables per step.

The probes are not kept in the repository. To rerun them, copy `Redis.tla` into an empty folder next to this module:
```tla
---- MODULE RedisProbe9 ----
EXTENDS Redis
NoOneRemembers == \A n \in Nodes : ~remembers[n]
Trap_P1_UndetectedKeeps == ~(Hidden /\ silentReset /\ owed /\ ~everAcked /\ resetRec = "unacked" /\ losses = 3)
ActC_LostAfterReply == (silentReset' /\ ~silentReset) => detections >= 1
Trap_Erased == ~(Hidden /\ owed /\ ~everAcked /\ resetRec # "unacked" /\ NoOneRemembers)
====
```
Use `gen_cfgs.py`'s BASE constants with `Jobs = {}`, `QueueA = {}`, `MaxTok = 0`, `LostReply = TRUE`, then the bounds in the probe table. Run with `run_tlc.py RedisProbe9.tla --config <cfg> --stop-at-first`. `Hidden` is defined in `Redis.tla`: the loss is pending, the marker is present and unflagged, and no worker's last-seen value is newer, so no node can detect the loss any more.

Switches in the model that are not requirements:
- `SplitCAS`: COUNTERFACTUAL, the run-5 wording of REQ-507 (a read and a separate compare-and-set). `TRUE` only in `Redis_HideRace`.
- `LostReply`: ENVIRONMENT, the reply to REQ-507's write is lost with the connection (A-32). `TRUE` only in `Redis_ReplyLost*`, `Redis_LivReplyLost*`, `Redis_SCN500LostReply` and the probes (not P2b).
- `RecordAfterReply`: COUNTERFACTUAL, the run-7 wording of REQ-523 (the record is written by the node after the reply, so a lost reply loses it). `TRUE` only in `Redis_ReplyLostRun7`.
- `TrackHidden`: keeps the history variables of `Inv_HiddenOnlyIfPaused` and `Inv_HiddenRunsLeaseLost`. `TRUE` only in `Redis_Hide*` and `Redis_ReplyLost`.

With all four `FALSE`, `casPending`, `found`, `foundLR`, `silentReset` and the hidden-flush history variables stay constant, and `ReplyLost` is disabled. `Redis.cfg` has 348,597 states, as in runs 5 to 8.

## Next
Decide F-1. Option 1 corrects one sentence of REQ-523's notes and needs no change to NFR-31. Apply it to `specs/redis.json` with the `refiner-requirements` skill, then run this skill again. If you choose option 2, the NFR-31 edit belongs in `non-functional-requirements.md`. The optional REQ-532 wording and the compare-and-set notes (Notes to correct) can go in the same edit. None of them changes behaviour.

These questions were already open and are unchanged by this run: one marker per hash tag under ShardByQueue (TECH-130; it now also asks where the reset record lives), the StaleNodeAge value (REQ-533), and whether REQ-531 should report Unhealthy instead of an ERROR. A-35's guard should be tightened the next time `Redis.tla` changes.
