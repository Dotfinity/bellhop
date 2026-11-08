# Findings: Bellhop Redis store behaviour

<!-- refiner-findings v1 | module: redis | specHash: 7bcd94d03e2daf303b36f0c332801df8419a33efeadb775b52a9515abc20bb8b | run: 2026-11-08 (run 8) | previous: specs/model/redis/previous.findings.md (run 7, specHash ea2b1eed07d1) -->

**Run:** 2026-11-08, run 8 · **Requirements file:** `specs/redis.json` (specHash `7bcd94d03e2d`) · **Model:** `specs/model/redis/Redis.tla` (49 cfgs from `gen_cfgs.py`) · **TLC:** 2.19. Every check ran alone with `--stop-at-first --workers 4` and a 170 s limit: 123 checks, all with the expected result, no TLC exceptions. Three other modules were being checked on the same machine. The largest space is `Redis_ReplyLost2.cfg`, with 4,494,908 distinct states in 53.7 s. The longest check is `Redis_LivReplyLostLateAdv.cfg` (`Liv_RecordRestored`, 74.1 s).
**Timeouts:** four new liveness checks timed out at their first bounds (one job, MaxTok 2): `Redis_LivReplyLost2.cfg` (three checks) and `Redis_LivLateAdv2.cfg`. They still timed out with MaxTok 1. These checks are about the reset record, and no job or claim takes part in that, so the three record cfgs now run with no jobs (`Jobs = {}`, `MaxTok = 0`). Then all of them finish (see Bounded checks). No final check timed out.
**Result:** 1 finding: 0 contradictions · 1 gap · 0 unprovable · 0 ambiguities · 0 modeling notes. Run 7's only finding is resolved.

This run regenerated REQ-523 from `handoff.json` (base ed02be0, resolution commit 43b4622):
- REQ-523 now records the reset as unacknowledged "in the same atomic step as that replacement", and TECH-130 makes the script write the record together with the marker. In the model the record moves into the store side of `ReplyLost` (A-32). `DetectReset` already wrote it in the same step. The ERROR lines and the node's memory still depend on the reply.
- The new invariant proposed by run 7 is `Inv_RecordUntilAck`: every replacement under REQ-507, lost reply included, leaves an unacknowledged record until an operator acknowledges it, except between a further loss and its detection. It passes on every cfg it runs on, `Redis_ReplyLost.cfg` and `Redis_ReplyLost2.cfg` (two flushes, two lost replies) included. A counterfactual with the run-7 wording (`RecordAfterReply`) violates it in 9 steps, so the check does catch run 7's F-1.
- The impacted ids were re-checked. SCN-500 is reachable in 10 steps (`Redis_SCN500.cfg`), and in 12 steps with the reply lost (`Redis_SCN500LostReply.cfg`, no ERROR logged, health kept Degraded by the record alone). REQ-532: `Liv_UnackedRestored` and the new `Liv_RecordRestored` pass on `Redis_Liveness.cfg` and `Redis_LivFlush2.cfg`. `Liv_RecordRestored` also passes on `Redis_LivReplyLost.cfg`, `Redis_LivReplyLost2.cfg` and `Redis_LivLateAdv2.cfg`. It fails on `Redis_LivReplyLostLateAdv.cfg`, which is F-1.
- With every switch off, each check that passed has exactly the same number of distinct states as in run 7 (`Redis.cfg` 348,597). The new history variable `owed` adds no states there.

**The second-flush question from the brief.** With a lost reply no node remembers the reset, so REQ-532 cannot re-write its record. Whether a second flush leaves the record intact therefore depends on that flush being detected and recorded in its own right:
- The second flush is detected and recorded when a node that saw a marker reads it. `Inv_RecordUntilAck` passes on `Redis_ReplyLost2.cfg` (4,494,908 states), including a second flush whose reply is also lost. `Liv_RecordRestored` passes on `Redis_LivReplyLost2.cfg` (199,106).
- The second flush is also recorded when the next read after the first lost reply happens on a node that never saw a marker. `Redis_LateJoin.cfg` and the late-join liveness cfgs cover this: REQ-528's first marker is found older by the node that saw the old one (REQ-507).
- The record is lost when the second flush is the unreported late-join flush that NFR-31 accepts. That is F-1. Without a lost reply, the same flush leaves the earlier record intact, because the node that remembers it re-writes it (`Redis_LivLateAdv2.cfg`, 175,022, passes).

## Changes since last run
| Finding | Status |
|---|---|
| F-1 (run 7): a lost reply to REQ-507's write leaves the flush unreported and unrecorded | resolved. 43b4622 applied option 1. `Inv_RecordUntilAck` passes on `Redis_ReplyLost.cfg` (178,576) and `Redis_ReplyLost2.cfg` (4,494,908). `Inv_HiddenOnlyIfPaused` passes on `Redis_ReplyLost.cfg`, and `Liv_LossReported` passes on `Redis_LivReplyLost.cfg` (162,454). The two ERROR lines are still lost with the reply, as REQ-523's notes accept (Accepted table). |
| F-1 (this run) | new |

`findings_delta.py` output (fingerprints; the first row uses run 7's number):

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | gap · Inv_HiddenOnlyIfPaused/LostReply · REQ-507,REQ-523,REQ-529,REQ-530 |
| F-1 | new | gap · Liv_RecordRestored/LostReply · REQ-523,REQ-524,REQ-528,REQ-532 |

1 resolved, 1 new, 0 still open

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | gap | medium | REQ-523, REQ-524, REQ-532, REQ-528, NFR-31 | A reset whose reply was lost is remembered by no node. If the next flush is the unreported late-join flush NFR-31 accepts, it also erases that reset's record, and health goes back to Healthy with no acknowledgement |

Decide **F-1**. It is the only finding. It happens only inside a window that is already accepted (NFR-31), but it contradicts a claim REQ-523's run-7 note now makes: "health stays Degraded (REQ-524) until an operator acknowledges it".

---

## F-1 · gap · medium — A lost reply followed by an unreported flush erases the earlier reset's record
<!-- finding: gap | Liv_RecordRestored/LostReply | REQ-523,REQ-524,REQ-528,REQ-532 -->

**Requirements involved**
- REQ-523: *When this node replaces the generation marker under REQ-507, the system shall record the reset as unacknowledged in the store in the same atomic step as that replacement, log an ERROR …, and **remember the reset until it finds it acknowledged**.* Its run-7 note: *"If the connection drops or the call times out after the script ran, the ERROR and this node's memory are lost but the record is not, and **health stays Degraded (REQ-524) until an operator acknowledges it**."*
- REQ-532: *While **this node remembers** an unacknowledged store reset, if the store holds no record of that reset, the system shall re-write the record as unacknowledged.* Its note: *"The record does not survive a flush while every node that remembers it is down."*
- REQ-524: *When the health check runs, if no check that reports Unhealthy fails and **a store reset has not been acknowledged**, the system shall report the node Degraded.*
- REQ-528 and NFR-31: *"a flush first seen by a newly started worker is not reported if every worker that saw the previous marker is paused until the marker is next advanced"*.

**What happens** (TLC, `Redis_LivReplyLostLateAdv.cfg`, `Liv_RecordRestored`, 21 steps, ends stuttering)
1. Worker nodes n1 and n2 connect and run. n2 reads the marker at value 2 (REQ-500, hosting REQ-18). n1 has not read it yet.
2. FLUSHALL (reset R1).
3. n2's next marker read finds the marker missing. In one atomic step, its script replaces the marker with value 3, flagged, and **records R1 as unacknowledged** (REQ-507, REQ-523, TECH-130). Then n2's connection drops before the reply arrives (REQ-529). n2 logs nothing and does not remember R1. This is run 7's case, and the record now survives it.
4. n2 reconnects, finds the flagged value 3, which is newer than the 2 it saw, and joins it silently (REQ-530).
5. A second FLUSHALL (reset R2) erases the marker and **R1's record**. Nobody remembers R1, so REQ-532 has no node to re-write the record.
6. n1 reads for the first time and finds the marker missing. It has never seen a marker, so it writes the first marker at the lowest value, flagged, without recording a reset (REQ-528). Meanwhile n2 makes no marker read: it is paused in the sense of NFR-31.
7. n1 re-seeds, a LeaseDuration passes, n1 clears the flag (REQ-509) and advances the marker to 5 (REQ-527). n2 then reads 5, unflagged and newer than its 3. That is an ordinary read.

From then on the store holds no reset record. No node remembers one, and no node logged either reset. The next health check that finds nothing else wrong reports n1 and n2 **Healthy** (hosting REQ-35). No operator has acknowledged R1, and REQ-524's condition "a store reset has not been acknowledged" is still true for R1. R2 being unreported is what NFR-31 accepts. R1 was recorded, and its record is now gone as well.

The same check with one job (MaxTok 1, 74 s) found a shorter shape (16 steps) before this run settled on its bounds. There the second flush comes while n2 is still connecting after its lost reply, so **no node reads the marker or the record at all** between R1's write and R2.

**Why** Before 43b4622, every record in the store had a node that remembered it: the node that wrote it, through REQ-532's re-write. A record written by a script whose reply was lost has no such node, and REQ-532's "while this node remembers" never applies to it. That makes the record only as durable as the store it lives in. A later flush removes it, and the record comes back only if that flush is itself detected. In the case NFR-31 accepts, it is not.

The comparison check shows the difference. `Redis_LivLateAdv2.cfg` has the same two flushes, the same late joiner and advance, and no lost reply. There `Liv_RecordRestored` passes (175,022 states): the node that detected R1 remembers it and re-writes the record after R2 (REQ-532).

**What this is not.** R2 going unreported is accepted (run 3 F-3, NFR-31). Losing the log lines and the node's memory with the reply is accepted too (REQ-523 notes). REQ-532's note covers the case where every node that remembers the record is down, which is not this case: here both nodes are up and none of them remembers. What no note accepts is the consequence of the two together: an unacknowledged reset that was recorded goes back to Healthy with no acknowledgement. REQ-523's note says that cannot happen.

**Options**
1. *(recommended)* **Document it.** Correct REQ-523's note and add the case to NFR-31's late-join sentence. This is consistent with run 3 F-3, where the owner chose to document the unreported late-join flush rather than detect it later. The extra loss happens only inside that window, and only when the reply to the earlier reset was also lost. Cost: words only. NFR-31 is in `non-functional-requirements.md`, outside this module, so that edit belongs there.
2. **Let every worker that finds an unacknowledged record remember it.** The scripts already return the marker (TECH-130). They would also return whether the store holds an unacknowledged record, and REQ-523's "remember" clause would read "…and every worker that finds the reset recorded as unacknowledged remembers it until it finds it acknowledged". REQ-532 then re-writes the record from any of those nodes. This closes the 21-step trace above, because n2 read the flagged marker at step 4. It does not close the 16-step shape, where no node reads anything between the two flushes. It also makes REQ-532's own note ("while every node that remembers it is down") much rarer. Cost: a clause in REQ-523, a return value in TECH-130 (outside this module), and more nodes that may re-write the record. Not checked by this run.
3. **Both**: option 2 for the common shape, option 1 for what is left.

**Ready to apply (option 1)**
```json
{ "id": "REQ-523",
  "notes": "<existing notes> Run 8 F-1 (recommended option): 'health stays Degraded until an operator acknowledges it' has one exception. A reset whose reply was lost is remembered by no node, so REQ-532 cannot re-write its record. If the next flush is the unreported late-join flush of NFR-31, that flush erases the record too, and health returns to Healthy without an acknowledgement. Not chosen: having every worker that finds an unacknowledged record remember it (run 8 F-1 option 2), which narrows the window but cannot close it." }
```
```json
{ "id": "REQ-532",
  "notes": "<existing notes> Run 8 F-1: a record written by a script whose reply was lost (REQ-523) has no node that remembers it, so it survives a later flush only if that flush is itself detected and recorded." }
```
NFR-31 (outside this module) would then read "…that a flush first seen by a newly started worker is not reported if every worker that saw the previous marker is paused until the marker is next advanced, although the outcomes of their runs are still recorded, **and that such a flush also erases the unacknowledged record of an earlier reset whose script reply was lost**; …".

---

## Static read: REQ-523's atomic record against the other sentences
| Sentence | Effect of the change | Result |
|---|---|---|
| REQ-507 / TECH-130 | The script that replaces the marker also writes the record, and TECH-130 says so ("together with redis REQ-523's unacknowledged reset record for a REQ-507 write"). The two texts agree | none |
| REQ-528 | Still "without … recording the reset as unacknowledged". Its first marker is not a REQ-507 write, so the script writes no record. `Redis_Fresh.cfg` (`Inv_NoFalseReset`, 1,096) and the SCN-503 trap (8 steps, `resetRec = "none"`) confirm it | none |
| REQ-530 | Writes nothing, so it writes no record. A node that joins a value whose write lost its reply gains no memory of the reset | the root of F-1 |
| REQ-524 / REQ-525 | Health and acknowledgement read and write the stored record. With the record in the script, health is Degraded after a lost reply (`Redis_SCN500LostReply.cfg`, 12 steps) and an operator can acknowledge it | none |
| REQ-532 | Applies only to a node that remembers. After a lost reply, none does | F-1 |
| Rollbacks (REQ-507 notes) | Every image that holds a marker written by REQ-507 now also holds its record, so a rollback to that marker cannot bring back a marker without its record. `Inv_RecordUntilAck` passes on `Redis_RestoreFR.cfg` (210,590) | none |

**ShardByQueue (adds to an open question, not a new finding).** A Redis script can make "the same atomic step" only within one hash slot. Under ShardByQueue every hash tag carries its own marker copy (TECH-130's open question in `technical-specifications.md`). The record must therefore sit in the slot of the marker copy the script replaces: one record per hash tag, or a second write outside the atomic step. The owner's open question on one marker per hash tag now covers the record too. That edit belongs in `technical-specifications.md`, outside this module.

## Stale notes (annotation only, not edited)
Run 7's list stands: REQ-507 notes F-9, REQ-523 notes F-9 and run 3 F-5, REQ-530 notes F-9 and F-13, and the TECH-130 open question still describe a compare-and-set that REQ-507 no longer makes. One addition:
- **REQ-523 notes**, run 7 F-1: "the ERROR and this node's memory are lost". With a lost reply, *both* ERROR lines are lost: REQ-507's StoreWasReset event and REQ-523's own ERROR. The commit message (43b4622) says "the log lines". The next edit can say "the StoreWasReset event, the ERROR and this node's memory".

## Checked and accepted (not findings)
| Check | Config | Result | Why it is not a finding |
|---|---|---|---|
| A lost reply loses both ERROR lines | `Redis_ReplyLost.cfg` | `Inv_EveryResetLogged` violated (9 steps): n1's script replaces the marker and writes the record, the reply is lost, and nothing is logged | REQ-523's run-7 note: "If the connection drops or the call times out after the script ran, the ERROR and this node's memory are lost but the record is not". The record is there (`Inv_RecordUntilAck` passes), and health shows the reset |
| A late-join flush hidden while the node that saw the old marker makes no read | `Redis_LivLateJoinAdv.cfg` | `Liv_LossReported` violated (15 steps; 16 in run 7; ends stuttering) | Run-3 F-3 option 2, documented in REQ-528's notes and NFR-31. Run 4 F-1 made "paused" mean "makes no marker read". The trace length varies with the parallel search |
| Rollback to older data (restore, lagging replica) | `Redis_Restore.cfg`, `Redis_RestoreOlder.cfg` | `Inv_NoLostOutcome` (10, 11 steps), `Inv_SingleClaim` (11, 12), `Inv_ConcurrencyKeyMax` (11, 12) violated | Run-2 F-5, option 2 accepted (REQ-507 and REQ-526 notes, NFR-31): a claim after the copy, or a same-marker rollback that is not detected |
| Runtime eviction (the policy changes after startup) | `Redis_Evict.cfg` | `Inv_ConcurrencyKeyMax` (12 steps), `Inv_NoLostOutcome` (11) violated | REQ-531 states that resets caused by eviction are not detected; REQ-505 refuses eviction at startup |
| A lease-lost run beside a newer claim | every cfg | excluded from `Inv_ConcurrencyKeyMax` and `Inv_SingleClaim` (A-18) | The stated rule: a run that did not heartbeat for a whole LeaseDuration has lost its lease, as under jobs REQ-132 |
| Counterfactual: the run-5 wording of REQ-507 (read, then a separate compare-and-set) | `Redis_HideRace.cfg` | `Inv_HiddenOnlyIfPaused` violated (14 steps), as expected | Shows why run 5 F-1 needed the change; not the requirement any more |
| Counterfactual: the run-7 wording of REQ-523 (record written by the node after the reply) | `Redis_ReplyLostRun7.cfg` | `Inv_RecordUntilAck` violated (9 steps), as expected | *(new)* Shows that the new invariant catches run 7 F-1, and that 43b4622 closes it; not the requirement any more |
| An unacknowledged record erased by an unreported late-join flush after a lost reply | `Redis_LivReplyLostLateAdv.cfg` | `Liv_RecordRestored` violated (21 steps) | The example for F-1 (it is a finding, listed here for completeness) |

## Passed checks
| Check | Config | Distinct states | Meaning |
|---|---|---|---|
| `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_UnackedUntilOperator`, `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Inv_RecordUntilAck`, `Scn_NoClaimWhileFlagged` | `Redis.cfg` (two workers, one flush) | 348,597 each | One report per flush, no false report, "a detected flush ends every lease", and the record kept until acknowledged |
| all eight safety invariants | `Redis_Flush2.cfg` (second flush during a reconciliation) | 2,856,201 | Two flushes with the restarted REQ-509 wait; the record is written again after the second |
| all eight safety invariants | `Redis_LateJoin.cfg` | 907,278 | A late first look (REQ-528's first marker beside a node that saw the old one): one report, no false one, record kept |
| `Inv_RecordUntilAck`, `Inv_UnackedUntilOperator`, `Inv_HiddenOnlyIfPaused`, `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim` | `Redis_ReplyLost.cfg` (one job, one flush, one lost reply) | 178,576 | *(changed)* **Run 7 F-1 is resolved**: the lost reply leaves the record, and the flush is no longer hidden. Run 7 had 160,546 states; the record the script now writes makes the difference |
| `Inv_RecordUntilAck`, `Inv_UnackedUntilOperator`, `Inv_NoFalseReset`, `Inv_OneEventPerReset` | `Redis_ReplyLost2.cfg` (one job, two flushes, up to two lost replies) | 4,494,908 | *(new)* A second flush, with its own reply lost too, is recorded again |
| `Liv_LossReported`, `Liv_Reseeded`, `Liv_RecordRestored` | `Redis_LivReplyLost.cfg` | 162,454 | *(changed)* The lost-reply flush now counts as detected (A-33), and the pause still ends |
| `Liv_RecordRestored`, `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivReplyLost2.cfg` (no jobs, two flushes, two lost replies) | 199,106 | *(new)* A record erased by the second flush comes back through that flush's own detection |
| `Liv_RecordRestored` | `Redis_LivLateAdv2.cfg` (no jobs, two flushes, late join, one advance, no lost reply) | 175,022 | *(new)* Baseline for F-1: REQ-532 re-writes the record after an unreported late-join flush |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique2During.cfg` / `Redis_Recurring2During.cfg` | 2,893,397 / 2,177,993 | Unique keys and occurrences across two flushes |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique2.cfg` / `Redis_Recurring2.cfg` (second flush after the first reconciliation) | 1,014,197 / 837,857 | An expired run is not brought back (REQ-522) |
| `Inv_SingleClaim`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost` | `Redis_Flush2Late.cfg` (two flushes, a late first look, one job) | 921,195 | REQ-521 under resetSinceClaim |
| `Inv_HiddenOnlyIfPaused`, `Inv_HiddenRunsLeaseLost`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_ConcurrencyKeyMax` | `Redis_Hide.cfg` | 119,197 | A hidden flush needs every node that saw the old marker to make no read (replies always arrive) |
| `Inv_HiddenOnlyIfPaused`, `Inv_HiddenRunsLeaseLost` | `Redis_Hide2.cfg` (two jobs) | 1,105,989 | The same with a claim beside a running job |
| `Inv_ResetSinceClaimSound`, `Inv_NoFalseReset`, `Inv_ConcurrencyKeyMax` | `Redis_Fresh.cfg` (two workers, new server) | 1,096 | A new server is initialised, not reported (SCN-503) |
| `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Scn_NoClaimWhileFlagged` | `Redis_Outage.cfg` / `Redis_Drop.cfg` | 1,906,584 / 1,475,436 | Outages and single-node drops during the pause |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique.cfg` / `Redis_Recurring.cfg` (one flush) | 310,693 / 265,981 | REQ-534 and the occurrence pause |
| `Inv_UniqueKey` | `Redis_Shard.cfg` | 1,240 | jobs INV-100's per-queue scope matches INV-500 |
| `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_RecordUntilAck` | `Redis_RestoreFR.cfg` | 210,590 | Rollbacks cause no false or double report and do not separate a marker from its record |
| `Liv_Reseeded`, `Liv_MarkerWritten` (LIV-501), `Liv_LossReported`, `Liv_UnackedRestored` | `Redis_Liveness.cfg` | 33,469 | One flush: re-seeded, marker written, reported, record kept (REQ-532) |
| `Liv_LossReported`, `Liv_UnackedRestored`, `Liv_Reseeded`, `Liv_RecordRestored` | `Redis_LivFlush2.cfg` | 318,426 | Two flushes; a record erased by the second is restored (REQ-532) |
| `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivRestore.cfg` | 392,700 | A rollback to an older marker is eventually reported |
| `Liv_Reseeded` | `Redis_LivOutage.cfg` / `Redis_LivDrop.cfg` (`Liv_LossReported` too) | 6,299 / 141,700 | No stuck pause after a reconnection |
| `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivLateJoin.cfg` | 27,450 | A late first look is reported (no advance) |
| `Liv_Reseeded` | `Redis_LivLateJoinAdv.cfg` | 96,724 | The pause always ends, with an advance too |
| `Liv_Reseeded`, `Scn_ClientNoDetect` (SCN-506) | `Redis_ClientOnly.cfg` | 10,556 | A client-only node never reconciles |
| `Inv_UnreachableIsUnhealthy`, `Inv_UnhealthyOnlyWithCause` | `Redis_Health.cfg` | 47,178 | Health precedence matches hosting |
| `Scn_NoEvalNoReady` (SCN-501) | `Redis_SCN501.cfg` | 56 | A server without EVAL never becomes ready |
| `Scn_NoClearBeforeWait` (SCN-509) / `Scn_NoRevivalAfterExpiry` (SCN-510) | `Redis_SCN509.cfg` / `Redis_SCN510.cfg` | 2,856,201 / 837,857 | Negative scenarios hold; their steps 1–3 are reachable (`Redis_SCN509Reach.cfg` 12 steps, `Redis_SCN510Reach.cfg` 15 steps) |
| SCN-500, 503, 504, 505, 507 and 508 traps violated, as expected | `Redis_SCN5xx.cfg` | 1,014 / 72 / 10,691 / 973 / 27,414 / 1,368 | Positive scenarios are reachable in 10, 8, 15, 10, 14 and 12 steps |
| SCN-500 with the reply lost: trap violated, as expected | `Redis_SCN500LostReply.cfg` | 5,222 | *(new)* Reachable in 12 steps (below) |

The state counts of violated checks are the states explored before TLC stopped, so they vary from run to run with the worker count. Every check that passed and existed in run 7 has the same count as in run 7, except the two lost-reply cfgs, which changed with the requirement.

**SCN-500 example** (10 steps): n1 connects and runs, and a health check moves it from Unhealthy to Degraded (hosting REQ-58). n1 reads the marker, FLUSHALL. n1's read finds the marker missing. In the same atomic step it replaces the marker, flagged, and records the reset as unacknowledged (REQ-507, REQ-523). With the reply in hand, n1 logs StoreWasReset and the REQ-523 ERROR and remembers the reset. n1 re-seeds, a LeaseDuration passes, and the flag is cleared (REQ-509). The store is Ready, and the next health check can only keep n1 Degraded (REQ-524), because the reset is unacknowledged.

**SCN-500 with the reply lost** (12 steps): as above up to the flush. Then n1's script replaces the marker and writes the record, and the reply is lost with the connection (REQ-529). n1 reconnects, finds the flagged value newer than the one it saw and joins it silently (REQ-530), re-seeds, and clears the flag after a LeaseDuration (REQ-509). Every clause of SCN-500's `then` holds except the two ERROR lines, which were not logged (accepted, REQ-523 notes). The next health check still keeps n1 Degraded (REQ-524) on the record alone.

Bounded checks:
- `Redis_Flush2.cfg`, the `*2During` cfgs and SCN-509 allow the second flush only while a node is reconciling (`ActC_SecondLossDuringReconcile`).
- `Redis_Unique2.cfg`, `Redis_Recurring2.cfg` and SCN-510 allow it only after the first reconciliation has ended everywhere (`ActC_SecondLossAfterReconcile`).
- `Redis_ReplyLost2.cfg` and the three new record liveness cfgs put no constraint on when the second flush comes.
- `Redis_HideRace.cfg` (counterfactual) keeps the read-to-write window shorter than one LeaseDuration (`ActC_ShortCAS`, A-29).
- `Redis_Flush2Late.cfg` runs with one job, as in runs 4 to 7. `Inv_NoFalseReset` under rollbacks is checked on `Redis_RestoreFR.cfg` (one job, one claim).
- `Redis_ReplyLost.cfg`, `Redis_ReplyLostRun7.cfg` and `Redis_LivReplyLost.cfg` run with one job and at most one lost reply. `Redis_ReplyLost2.cfg` has one job and up to two lost replies.
- `Redis_LivReplyLost2.cfg`, `Redis_LivReplyLostLateAdv.cfg` and `Redis_LivLateAdv2.cfg` run with no jobs (`Jobs = {}`, `MaxTok = 0`). With one job they time out. The record rules (REQ-523, REQ-524, REQ-525, REQ-532) read no job state, and every marker read that detects a reset can also happen as its own step (A-2).

## Modeling assumptions
Decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. Changes since run 7 are marked.
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
| A-12 | A restore or failover rolls the whole server back to an image taken earlier, marker and record included | accepted rollback rows, `Redis_RestoreFR.cfg` |
| A-14 | Job ids and lease tokens are fresh | all |
| A-16 | A refused heartbeat or completion (jobs INV-128) does not stop the handler | run-3 F-2 |
| A-17 | Without `LateJoin`, every worker has read the marker before data is lost. With `LateJoin`, at least one has; REQ-528's notes accept that a loss no running node saw goes unreported | late-join cfgs |
| A-18 | **LeaseDuration without a clock.** See below. | every safety result |
| A-19 | REQ-507's and REQ-528's read and write are one atomic step (`DetectReset`, `InitMarker`), as the sentences say since run 6. `SplitCAS` keeps the run-5 wording only as a counterfactual | REQ-507, REQ-528 |
| A-21 | Only a rollback to an older marker value counts as a detectable loss in `Liv_LossReported`; same-value rollbacks and runtime evictions are documented as undetected (NFR-31, REQ-531) | `Liv_LossReported` |
| A-22 | A node remembers the last value it saw from ordinary reads, claims and its own writes (glossary `lastSeenMarker`). A heartbeat or completion that reads a newer unflagged value is the same as an ordinary read followed by the heartbeat (`Observe`), so it is not modeled separately | REQ-507, REQ-530 |
| A-24 | Marker values and last-reset values from "the Redis server's current time" (REQ-507, REQ-527, REQ-528) are a counter that every new time value increases, flushes and rollbacks included. REQ-528's lowest value is below every such value | REQ-507, REQ-527, REQ-528 |
| A-25 | A node "has finished a value's reconciliation" once REQ-509 found the marker at that value, cleared or already unflagged (REQ-530 notes) | REQ-530, LIV-500 |
| A-26 | A single node can lose its connection (REQ-529) while the others stay connected; its store is connecting until it reconnects, and it neither heartbeats nor completes meanwhile | `Redis_Drop.cfg`, `Redis_LivDrop.cfg`, `Redis_*ReplyLost*.cfg` |
| A-27 | "Paused" in NFR-31 and the REQ-528 notes means the node makes no marker read between the flush and the advance (`readInWindow`). A node whose store is connecting makes no reads, so it counts as paused | REQ-528, NFR-31, F-1 |
| A-28 | A script's read and the node's response to it (REQ-507/528/530) are ordered response-first: the claim, heartbeat or completion takes effect only once no sentence applies. When the reply arrives, the script's REQ-507/528 write and the node's response are one step. With `LostReply`, the write can happen without the response (A-32) | REQ-526, REQ-522, REQ-521, REQ-523 |
| A-29 | (counterfactual only) With `SplitCAS`, the window between the read and the compare-and-set is shorter than one LeaseDuration (`ActC_ShortCAS`) | `Redis_HideRace.cfg` |
| A-30 | A refused claim attempt (marker missing or flagged) is not modeled as a read. Whether a reconciling node keeps calling its claim script does not matter for detection: with the write in the read, nothing can land between them | REQ-507 |
| A-31 | REQ-523's trigger, "this node replaces the generation marker under REQ-507", is `DetectReset` (and its store side in `ReplyLost`). `InitMarker` (REQ-528) and `Learn` (REQ-530) record nothing | REQ-523 |
| A-32 | *(changed)* `LostReply`: a connection drop (REQ-529) can come between the server running the script that makes REQ-507's write and the node receiving its reply. The write stands, **and since run 8 it includes the unacknowledged record** (REQ-523, TECH-130). The node learns nothing: it logs neither ERROR, remembers nothing, its store is connecting and its last-seen value is unchanged. This is an environment event, not fair, at most `MaxDrops` per run, and it is on only in `Redis_*ReplyLost*.cfg` and `Redis_SCN500LostReply.cfg`. A client-side timeout has the same effect but is not modeled | F-1 (run 7, resolved), F-1 |
| A-33 | *(new)* A loss counts as detected (`pendingLoss` ends) once a node's script has replaced the marker under REQ-507, reply or not, because that replacement now writes the record. Whether the two ERROR lines were logged is tracked apart from this (`silentReset`, `Inv_EveryResetLogged`) | `Liv_LossReported`, `Inv_HiddenOnlyIfPaused`, `Inv_RecordUntilAck` |
| A-34 | *(new)* The store holds one reset record (`resetRec`: none, unacknowledged or acknowledged), not one per reset. A later detection overwrites it, and REQ-532's "record of that reset" is that record. An acknowledgement covers every reset recorded before it (`owed` ends) | REQ-523, REQ-525, REQ-532, `Inv_RecordUntilAck`, `Liv_RecordRestored` |

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
- `python run_all.py [cfg …]` runs each invariant and each property alone with `--stop-at-first`, and enforces a 170 s limit per run. `TLC_WORKERS` sets the worker count (default 4; this run used 4). Results go to `runs/` and `run.md`, which are gitignored. Set `RUN_INDEX=name.json` to write a separate index. Cfgs whose name contains `_SCN` followed by a number run as scenarios (`--no-deadlock`, trap as written); since run 8 the name may continue after the number (`Redis_SCN500LostReply`).
- Never run two batches in the same folder at once: TLC's `-cleanup` deletes the other batch's state directories.
- `python summary.py [filter]` lists finished checks (including older results still in `runs/`). `python trace.py runs/<cfg>__<check>.json [var …]` prints a trace as changed variables per step.

Switches in the model that are not requirements:
- `SplitCAS`: COUNTERFACTUAL, the run-5 wording of REQ-507 (a read and a separate compare-and-set). `TRUE` only in `Redis_HideRace`.
- `LostReply`: ENVIRONMENT, the reply to REQ-507's write is lost with the connection (A-32). `TRUE` only in `Redis_ReplyLost*`, `Redis_LivReplyLost*` and `Redis_SCN500LostReply`.
- `RecordAfterReply`: COUNTERFACTUAL, the run-7 wording of REQ-523 (the record is written by the node after the reply, so a lost reply loses it). `TRUE` only in `Redis_ReplyLostRun7`.
- `TrackHidden`: keeps the history variables of `Inv_HiddenOnlyIfPaused` and `Inv_HiddenRunsLeaseLost`. `TRUE` only in `Redis_Hide*` and `Redis_ReplyLost`.

With all four `FALSE`, `casPending`, `found`, `foundLR`, `silentReset` and the hidden-flush history variables stay constant, and `ReplyLost` is disabled. `Redis.cfg` has 348,597 states, as in runs 5 to 7.

## Next
Decide F-1. Option 1 corrects REQ-523's note and adds a note to REQ-532. Its NFR-31 counterpart is in `non-functional-requirements.md`, outside this module. Apply it to `specs/redis.json` with the `refiner-requirements` skill, then run this skill again. If you choose option 2 instead, the next run will check it with `Redis_LivReplyLostLateAdv.cfg`. The 16-step shape described under F-1 will still be open, so option 1's note would still be needed.

These questions were already open and are unchanged by this run, except as noted: one marker per hash tag under ShardByQueue (TECH-130; it now covers where the reset record lives too), the StaleNodeAge value (REQ-533), and whether REQ-531 should report Unhealthy instead of an ERROR.
