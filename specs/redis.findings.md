# Findings: Bellhop Redis store behaviour

<!-- refiner-findings v1 | module: redis | specHash: 934f2065132c686a816074c2b96c34b1677f1f5894532e71001f6cf167aee2e6 | run: 2026-11-06 (run 2) | previous: specs/model/redis/previous.findings.md (run 1, specHash eb75d09b96bf) -->

**Run:** 2026-11-06, run 2 · **Requirements file:** `specs/redis.json` (specHash `934f2065132c`) · **Model:** `specs/model/redis/Redis.tla` (20 cfgs from `gen_cfgs.py`) · **TLC:** 2.19, every check run alone with `--stop-at-first`, 49 runs, no TLC exceptions, one timeout (below); the main configuration explores 7,494,066 distinct states in about 115 s
**Result:** 6 findings: 4 contradictions · 2 gaps · 0 unprovable · 0 ambiguities · 0 modeling notes. All 14 findings from run 1 are resolved.

This run regenerated the reset machinery from `handoff.json`: the forward-moving, reconciling-flagged generation marker (REQ-507, REQ-527, REQ-528, REQ-530), the claim pause (REQ-526), the re-assertion of a running job's record (REQ-522), the wait before the flag is cleared (REQ-509), the kept reset record (REQ-523, REQ-532), reconnection (REQ-529), and the startup eviction check (REQ-505). It then checked them against the guarantees they protect in other modules: jobs INV-100, INV-103 and INV-108, and recurring INV-204.

The owner's "full protection" design does what it set out to do in the case it was written for. Two workers, FLUSHALL up to twice, every worker has read the marker before the flush, and heartbeats arrive on time: no second job takes the concurrency key, no job runs twice, no outcome is lost, and the reset record survives (7,494,066 states, `Redis.cfg`). The six findings are the edges of that case:
- a node that reads the marker for the first time after the flush;
- work created during the pause;
- an outage during the pause;
- a reconnection before the flag is cleared;
- a rollback before anyone notices;
- two nodes picking marker values independently.

## Changes since last run
| Finding | Status |
|---|---|
| F-1 (run 1) — flush lets a second job take the concurrency key | resolved — `Inv_ConcurrencyKeyMax` passes on `Redis.cfg` (7,494,066 states); SCN-504 is reachable (14 steps) |
| F-2 (run 1) — restores, failovers and evictions go unreported | resolved — `Liv_LossReported` passes on `Redis_LivRestore.cfg` and `Redis_LivFlush2.cfg`; SCN-505 reachable. Evictions are refused at startup (REQ-505); runtime eviction and same-marker rollbacks are documented as undetected (REQ-531, NFR-31). What remains of rollbacks is new F-5 |
| F-3 (run 1) — a new server is reported as a reset | resolved — `Inv_NoFalseReset` passes on `Redis_Fresh.cfg`; SCN-503 reachable (5 steps) |
| F-4 (run 1) — client-only node stuck Reconciling | resolved — `Liv_Reseeded` and `Scn_ClientNoDetect` (SCN-506) pass on `Redis_ClientOnly.cfg` |
| F-5 (run 1) — Degraded and Unhealthy from one check | resolved — `Inv_UnreachableIsUnhealthy` passes on `Redis_Health.cfg` |
| F-6 (run 1) — Unhealthy kept after the store returns | resolved — `Inv_UnhealthyOnlyWithCause` passes on `Redis_Health.cfg` |
| F-7 (run 1) — maintenance pause silently switched off | resolved — REQ-523's ERROR now names it, and the flush is always reported (`Liv_LossReported` passes) |
| F-8 (run 1) — second flush erases the reset record | resolved — `Inv_UnackedUntilOperator` passes on `Redis.cfg` (two flushes); `Liv_UnackedRestored` passes on `Redis_LivFlush2.cfg` |
| F-9 (run 1) — two StoreWasReset events for one flush | resolved — with compare-and-set only the winner logs; `Inv_OneEventPerReset` passes when marker values are globally later (`Redis_OptGlobal.cfg`). The remaining violation has another cause: new F-6 |
| F-10 (run 1) — ShardByQueue vs jobs INV-100 | resolved — jobs INV-100 now names the per-queue scope; `Inv_UniqueKey` passes on `Redis_Shard.cfg` |
| F-11 (run 1) — log/result TTL vs jobs INV-119 | resolved (static) — REQ-514 gives logs and results the job's TTL, renewed on every state change |
| F-12 (run 1) — "becomes ready" after reconnect undefined | resolved — REQ-529 is modeled (Ready/Reconciling → Connecting); REQ-503, REQ-504 and REQ-531 fire on every connection |
| F-13 (run 1) — orphan sweep vs re-seeded jobs | resolved (static) — REQ-507 and REQ-530 re-seed the node's registration with the definitions |
| F-14 (run 1) — stale-node age missing | resolved — REQ-533 sets StaleNodeAge (60 s, already an open question) and REQ-515 is a transition |
| F-1 … F-6 (this run) | new |

`findings_delta.py` output (fingerprints; F-numbers are per run, so the first fourteen rows are run 1's numbers):

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | contradiction · Inv_ConcurrencyKeyMax · REQ-507,REQ-521,REQ-522,jobs:INV-108 |
| F-2 | resolved | gap · Liv_LossReported · REQ-504,REQ-505,REQ-507,REQ-521,REQ-523 |
| F-3 | resolved | gap · Inv_NoFalseReset · REQ-507,REQ-509,REQ-523,REQ-524 |
| F-4 | resolved | contradiction · Liv_Reseeded · LIV-500,REQ-507,REQ-509,hosting:REQ-40 |
| F-5 | resolved | contradiction · Inv_UnreachableIsUnhealthy · REQ-508,REQ-519,REQ-524,hosting:REQ-31 |
| F-6 | resolved | gap · Inv_UnhealthyOnlyWithCause · REQ-508,REQ-519,REQ-524,hosting:REQ-35 |
| F-7 | resolved | gap · Inv_MaintenanceOnlyOperatorOff · REQ-507,REQ-523,jobs:REQ-162,jobs:REQ-163 |
| F-8 | resolved | ambiguity · Inv_UnackedUntilOperator · REQ-507,REQ-509,REQ-523,REQ-524,REQ-525 |
| F-9 | resolved | ambiguity · Inv_OneEventPerReset · REQ-507,REQ-509,REQ-523,SCN-500 |
| F-10 | resolved | contradiction · Inv_UniqueKeyPerNamespace · INV-500,jobs:INV-100 |
| F-11 | resolved | contradiction · REQ-514 · REQ-514,jobs:INV-119,jobs:REQ-104 |
| F-12 | resolved | ambiguity · RedisStore.Ready · REQ-500,REQ-503,REQ-504,REQ-505,REQ-509,REQ-511 |
| F-13 | resolved | gap · RecurringJob.Orphaned · REQ-507,REQ-515,recurring:REQ-205,recurring:REQ-207 |
| F-14 | resolved | ambiguity · REQ-515 · REQ-515 |
| F-1 | new | contradiction · Inv_ConcurrencyKeyMax · REQ-521,REQ-522,REQ-526,REQ-528,jobs:INV-108 |
| F-2 | new | contradiction · REQ-526 · REQ-522,REQ-526,jobs:INV-100,recurring:INV-204 |
| F-3 | new | contradiction · Inv_ConcurrencyKeyMax · REQ-509,REQ-521,REQ-522,REQ-529,jobs:INV-108 |
| F-4 | new | gap · Liv_Reseeded · LIV-500,REQ-509,REQ-526,REQ-529,REQ-530 |
| F-5 | new | contradiction · Inv_SingleClaim · REQ-507,REQ-521,REQ-522,REQ-526,jobs:INV-103,jobs:INV-108 |
| F-6 | new | gap · Inv_NoFalseReset · REQ-507,REQ-527,SCN-500 |

14 resolved, 6 new, 0 still open

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | contradiction | high | REQ-528, REQ-526, REQ-522, REQ-521, jobs INV-108 | A node that reads the marker for the first time after a flush "initialises" the store: claims resume while a running job's hold is gone, and its outcome can be lost |
| F-2 | contradiction | high | REQ-526, REQ-522, jobs INV-100, recurring INV-204 | Only claims pause: a job enqueued or an occurrence created during the pause collides with the run that REQ-522 re-creates moments later |
| F-3 | contradiction | high | REQ-509, REQ-522, REQ-529, REQ-521, jobs INV-108 | An outage can use up the HeartbeatInterval wait, so the flag is cleared before the running job re-asserted its hold |
| F-4 | gap | high | LIV-500, REQ-509, REQ-529, REQ-530, REQ-526 | A worker that reconnects after re-seeding but before clearing the flag never clears it, and REQ-526 then blocks every claim for good |
| F-5 | contradiction | high | REQ-526, REQ-522, REQ-521, REQ-507, jobs INV-103, INV-108 | After a rollback to an older marker, claims continue against the restored image until a node notices, and a stale record is never re-asserted |
| F-6 | gap | medium | REQ-507, REQ-527, SCN-500 | A detecting node picks "a value later than any it has seen", which can be older than what another node saw: that node reports a second, false reset |

Decide **F-1 first**. A node that starts during the detection window is the most ordinary of these situations: a deploy, an autoscaler, or a crash loop. It breaks the Max = 1 guarantee the design was built for, and it can hide the reset altogether. Its fix, and the fixes for F-3, F-4 and F-6, all change the marker: how values are chosen, whether the first write is flagged, and what the marker remembers. Decide those four together. F-2 and F-5 are independent of them.

---

## F-1 · contradiction · high — A node that reads the marker for the first time after a flush "initialises" the store
<!-- finding: contradiction | Inv_ConcurrencyKeyMax | REQ-521,REQ-522,REQ-526,REQ-528,jobs:INV-108 -->

**Requirements involved**
- REQ-528: *Where the worker is registered, while the store is ready, when the generation marker is found missing, if this node has not seen a generation marker since it started, then the system shall write the first generation marker at the lowest value, only if none exists yet, and log at INFO that it initialised the store.*
- REQ-526: *While the generation marker is missing or flagged as reconciling, the system shall claim no job.*
- REQ-522: *If a heartbeat or progress write finds its job's record missing and the store was reset since the claim, then the system shall re-create the job's record as processing …*
- jobs INV-108: *… never admit a claim that would make more jobs with the same concurrency key processing at once … than that key's Max …*

**What happens** (TLC, `Redis_LateJoin.cfg`, `Inv_ConcurrencyKeyMax`, 11 steps; both jobs share concurrency key `tenant:42`, Max = 1)
1. Worker nodes n1 and n2 start. n2 is running but has not read the generation marker yet. A node reads it at some point while ready; no requirement says when.
2. n1 claims j1 and runs it, reading marker value 2 (jobs REQ-123).
3. Someone runs FLUSHALL. The marker, j1's record and the `tenant:42` hold are gone. Claims pause (REQ-526).
4. n2 now reads the marker for the first time and finds it missing. n2 has never seen a marker, so this is REQ-528, not REQ-507: it writes the first marker at the lowest value, **unflagged**, and logs INFO "initialised".
5. The marker is present and unflagged, so the pause ends. j2 with key `tenant:42` is enqueued.
6. n2 claims j2. The store shows no holder of `tenant:42` — **j1 and j2 now run at once under Max = 1**.

n1's next heartbeat finds j1's record missing and the marker (1) older than the value at its claim (2), so REQ-522 re-creates j1 as Processing with its hold. That happens after j2 was admitted; the store then shows two holders.

A second trace (`Inv_NoLostOutcome`, 11 steps) shows the other face. After step 4, n2 advances the marker back to 2 under REQ-527. j1 finishes on n1: its record is missing, but the marker is not missing, not flagged, and not older than at the claim (2 = 2). So REQ-521 does not apply, **the completion is refused and j1 vanishes from history**. The flush is never reported: n1 last saw 2 and finds 2.

**Why** After a flush the store looks exactly like a new server; only nodes' memories tell the two apart. REQ-528 trusts the first node that looks, even when another node is mid-run, and writes the first marker unflagged, so claims resume before anyone who remembers the old marker has checked.

**Options**
1. *(recommended)* **Write the first marker flagged as reconciling.** REQ-528 writes the lowest value, flagged, and the writer then reconciles like any other node (REQ-509 clears the flag after the wait), without recording a reset. Claims stay paused through the wait, every running job re-asserts its hold (a flagged marker is "reset since the claim"), and any node that saw an earlier value finds the lowest value older than its own and reports the reset (REQ-507 must apply to a flagged marker too; see F-6 for how the detecting node picks a value). The cost: a brand-new installation waits one wait period (see F-3) before its first claim.
2. **Only a starting node may initialise.** REQ-528 applies only while the node is *starting*; a running node that finds the marker missing waits for REQ-507 on another node. This is cheaper, but a node that restarts during the window is still "starting", so the trace above remains.
3. **Accept and document** in NFR-31 that a node starting within seconds of a flush can hide it, and that jobs running at that moment may run twice.

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-528", "ears": { "where": "the worker is registered", "while": "the store is ready", "when": "the generation marker is found missing",
      "if": "this node has not seen a generation marker since it started",
      "shall": "write the first generation marker at the lowest value, flagged as reconciling, only if none exists yet, log at INFO that it initialised the store, and reconcile as in REQ-509 without recording a reset" } },
  { "id": "REQ-507", "ears": { "where": "the worker is registered", "while": "the store is ready or reconciling",
      "when": "the generation marker is found missing, or with a value older than the last value this node saw, whether or not it is flagged as reconciling",
      "if": "this node has seen a generation marker since it started",
      "shall": "replace the marker, by compare-and-set against what it found, with a value later than any value ever written, flagged as reconciling, log the ERROR event StoreWasReset if its own write succeeded, and in either case start re-seeding the code-defined recurring jobs, the queue registry and this node's registration" } }
]
```

---

## F-2 · contradiction · high — Only claims pause: work created during the pause collides with the re-created run
<!-- finding: contradiction | REQ-526 | REQ-522,REQ-526,jobs:INV-100,recurring:INV-204 -->

**Requirements involved**
- REQ-526: *While the generation marker is missing or flagged as reconciling, the system shall claim no job.*
- REQ-522: *… re-create the job's record as processing with the run's claiming node, leaseToken, leaseExpiresAt, queue, concurrency key and recurring occurrence, so that queue limits, concurrency keys and recurring overlap count the run again …*
- jobs INV-100: *… never hold two active jobs with the same unique key in the same namespace …*
- recurring INV-204: *Where a recurring job's overlap policy is Skip or Queue, the system shall never have two of its occurrences' jobs in the Processing state at the same time.*

**What happens — unique key** (TLC, `Redis_Unique.cfg`, `Inv_UniqueKey`, 11 steps; j1 and j2 carry unique key `invoice:7`)
1. n2 claims j1 (`invoice:7`) and runs it.
2. FLUSHALL. j1's record and the `invoice:7` lock are gone.
3. The application enqueues j2 with `invoice:7`. Enqueues are not paused, and nothing holds the key, so j2 is enqueued (jobs REQ-150).
4. n2's heartbeat re-creates j1 as Processing (REQ-522). **j1 (Processing) and j2 (Enqueued) are two active jobs with `invoice:7`**: jobs INV-100 is broken. REQ-522 restores the concurrency key, but not the unique key.

**What happens — recurring overlap** (TLC, `Redis_Recurring.cfg`, `Inv_RecurringOverlap`, 15 steps; j1 and j2 are occurrences of `nightly-cleanup`, overlap Skip)
1. n2 runs occurrence j1. FLUSHALL.
2. n1 detects the reset (REQ-507) and re-seeds `nightly-cleanup` (REQ-203 via REQ-507).
3. The scheduler creates the next occurrence j2. Recurring REQ-221 finds no unfinished occurrence, because j1's record is gone.
4. n2's heartbeat re-creates j1 as Processing (REQ-522).
5. n1 clears the flag (REQ-509) and claims j2. **Two occurrences of `nightly-cleanup` are Processing**: recurring INV-204 is broken.

**Why** The pause covers claims only. Anything that decides by looking for an existing job — unique-key enqueue, recurring overlap, chain and batch creation — sees an empty store until the running jobs' next heartbeats re-create them, and it is not paused.

**Options**
1. *(recommended)* **Pause what decides by absence, and re-assert unique keys.** REQ-522 also re-creates the unique-key lock. REQ-526 extends to "create no recurring occurrence", and an enqueue or schedule with a unique key waits until the flag is cleared. "Waits" means retrying for up to the wait period, then failing with a retryable StoreReconciling error. Enqueues without a unique key are unaffected.
2. **Accept and document**: add *"except after a store reset (redis REQ-507)"* to jobs INV-100 and recurring INV-204, as INV-500 does for ShardByQueue, and say so in NFR-31.
3. **De-duplicate after the pause**: when REQ-509 clears the flag, for every unique key or recurring job with two active jobs, cancel the newer one with reason DuplicateAfterReset. The caller was already told the newer job was enqueued, so this is surprising, and it still lets both run if the newer one was claimed first.

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-526", "ears": { "while": "the generation marker is missing or flagged as reconciling",
      "shall": "claim no job, create no recurring occurrence, and hold any enqueue or schedule that carries a unique key until the flag is cleared, failing it with a retryable StoreReconciling error if the flag is still set after LeaseDuration" } },
  { "id": "REQ-522", "ears": { "if": "a heartbeat or progress write finds its job's record missing and the store was reset since the claim",
      "shall": "re-create the job's record as processing with the run's claiming node, leaseToken, leaseExpiresAt, queue, concurrency key, unique key and recurring occurrence, so that queue limits, concurrency keys, unique keys and recurring overlap count the run again, and let the run continue" } }
]
```

---

## F-3 · contradiction · high — An outage can use up the HeartbeatInterval wait before the running job re-asserts its hold
<!-- finding: contradiction | Inv_ConcurrencyKeyMax | REQ-509,REQ-521,REQ-522,REQ-529,jobs:INV-108 -->

**Requirements involved**
- REQ-509: *While the store is reconciling, when this node has re-seeded …, and HeartbeatInterval has passed since the reconciling marker was written, the system shall clear the reconciling flag …*
- REQ-529: *When the connection to the server is lost …, the system shall mark the store connecting and repeat server detection when it reconnects.*
- REQ-522 (quoted in F-2); jobs INV-108 (quoted in F-1).

**What happens** (TLC, `Redis_Outage.cfg`, `Inv_ConcurrencyKeyMax`, 18 steps)
1. n2 runs j1 (key `tenant:42`, Max = 1). FLUSHALL.
2. n1 detects the reset and writes the flagged marker (REQ-507). j2 with `tenant:42` is enqueued.
3. The Redis server is unreachable for a while (failovers often follow the same incidents as restores). Both nodes mark their store connecting (REQ-529). HeartbeatInterval passes during the outage, and no heartbeat can land.
4. The server comes back. n1 reconnects first; n2 is still reconnecting.
5. n1 finds the flagged marker (REQ-530), re-seeds, and — HeartbeatInterval having passed since the marker was written — clears the flag (REQ-509).
6. n1 claims j2. **j1 is still running on n2 without a record or hold**, so two jobs run under Max = 1.

A second trace (`Inv_NoLostOutcome`, 17 steps) follows the same path. n2's run finishes after the flag was cleared. n2 never saw the flag, the marker (3) is newer than at its claim (2), and n2 did not detect or learn of the reset. So REQ-521 does not apply, and **the completion is refused and the job vanishes**.

**Why** REQ-509 waits for a time period, but the guarantee needs an event: every running job's heartbeat landing during the pause. An outage, a GC pause or a slow reconnection on one node makes the two differ. And once the flag is cleared, a node that missed the whole pause has nothing left in the store that tells it a reset happened.

**Options**
1. *(recommended)* **Wait a full lease, measured from the later of the write and this node's reconnection, and keep the last reset in the marker.**
   - REQ-509 waits LeaseDuration instead of HeartbeatInterval, and counts from whichever is later: the reconciling marker's write, or this node's last reconnection.
   - A run that could not heartbeat for a whole lease would have lost its claim without any reset (jobs REQ-132, and the accepted at-least-once case in recurring REQ-238). A double run after that is therefore no worse than an ordinary lease loss.
   - The marker also keeps the value of the last reset it was written for. "Reset since the claim" then includes "the marker's last-reset value is later than the value read at the claim", which covers a node that never saw the flag.
   - The cost: claims pause for about 60 s after a reset instead of 20 s.
2. **Wait for the re-assertions themselves.** Every node that detects or learns of the reset writes the list of its live claims, and the flag clears only when every node registered at the time has reported. This is exact, but registrations are themselves flushed and need re-seeding first (REQ-507), and a dead node blocks the clear until StaleNodeAge.
3. **Accept and document** in NFR-31 that an outage during the pause can let a concurrency key admit one job too many and lose that job's outcome.

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-509", "ears": { "while": "the store is reconciling",
      "when": "this node has re-seeded the code-defined recurring jobs, the queue registry and its registration, and LeaseDuration has passed since the reconciling marker was written and since this node last reconnected",
      "shall": "clear the reconciling flag on the generation marker if it is still set on the value written at detection, keeping that value as the marker's last-reset value, and mark the store ready" },
    "dependsOn": ["REQ-507", "jobs.REQ-102"] }
]
```
Glossary `resetSinceClaim`, append: *"…, or the marker's last-reset value is later than the value read when the job was claimed."*

---

## F-4 · gap · high — A worker that reconnects before clearing the flag never clears it
<!-- finding: gap | Liv_Reseeded | LIV-500,REQ-509,REQ-526,REQ-529,REQ-530 -->

**Requirements involved**
- LIV-500: *While the generation marker is flagged as reconciling and a node with the worker registered is running, the system shall eventually re-seed every code-defined recurring job and clear the reconciling flag.*
- REQ-530: *… when the generation marker is found flagged as reconciling with a value **for which this node has not yet re-seeded**, the system shall start re-seeding …*
- REQ-509 (quoted in F-3); REQ-529 (quoted in F-3); REQ-526 (quoted in F-2).

**What happens** (TLC, `Redis_LivOutage.cfg`, `Liv_Reseeded`, 15 steps, ends stuttering; one worker n1)
1. n1 runs j1. FLUSHALL. j1 finishes; REQ-521 records it.
2. n1 detects the reset (REQ-507), writes flagged value 3, and re-seeds (it has now re-seeded for 3).
3. Before the wait in REQ-509 is over, the server becomes unreachable. n1 marks the store connecting (REQ-529).
4. The server comes back; n1 reconnects and marks the store **ready** (REQ-500).
5. The marker is still flagged with value 3. REQ-530 does not apply (n1 has already re-seeded for 3); REQ-509 does not apply (n1 is not reconciling); REQ-507 does not apply (3 is not older than 3).
6. **Nothing ever clears the flag, so REQ-526 blocks every claim on every node, for good.**

With several workers this happens when every worker has re-seeded for the value before the outage, which is the common case: the wait in REQ-509 is long compared with re-seeding. An outage disconnects all of them at once.

**Why** Reconnecting drops a node out of Reconciling (REQ-529, then REQ-500 marks it ready), and REQ-530 lets a node rejoin only for values it has not re-seeded for. Re-seeding is complete, but the reconciliation is not.

**Options**
1. *(recommended)* **Rejoin any reconciliation not yet finished.** REQ-530 applies to a flagged value *whose reconciliation this node has not finished*, rather than one it has not re-seeded for. Re-seeding is idempotent, so doing it again costs little. Checked: `Liv_Reseeded` passes with this reading (`Redis_OptResume.cfg`, 7,469 states).
2. **Stay reconciling across a reconnection.** REQ-529: a node that reconnects while it was reconciling returns to reconciling, not ready. The effect is the same, but REQ-500 then needs an exception.
3. **Let any worker clear a stale flag**: a flag older than twice the wait is cleared by any worker that finds it. This is a time-out on a liveness bug, and it delays recovery.

**Ready to apply (option 1)**
```json
{ "id": "REQ-530", "ears": { "where": "the worker is registered", "while": "the store is ready",
    "when": "the generation marker is found flagged as reconciling with a value whose reconciliation this node has not finished",
    "shall": "start re-seeding the code-defined recurring jobs, the queue registry and this node's registration, without logging StoreWasReset, and remember the value" } }
```

---

## F-5 · contradiction · high — After a rollback to an older marker, claims continue against the restored image until a node notices
<!-- finding: contradiction | Inv_SingleClaim | REQ-507,REQ-521,REQ-522,REQ-526,jobs:INV-103,jobs:INV-108 -->

**Requirements involved**
- REQ-526 (quoted in F-2): claims pause only while the marker is *missing or flagged*.
- REQ-507: detection when the marker is *older than the last value this node saw*. Only the node checks this, from its own memory.
- REQ-522 (quoted in F-2): re-assert only when the record is *missing*.
- jobs INV-103: *… never let more than one worker hold an unexpired claim on the same job.*

**What happens** (TLC, `Redis_RestoreOlder.cfg`, only rollbacks to an older marker, `Inv_SingleClaim`, 12 steps)
1. A snapshot is taken while j1 is enqueued and the marker is 2.
2. n2 claims j1 and runs it.
3. n1 advances the marker to 3 (REQ-527); n2 has not read it yet.
4. The server is restored from the snapshot, for example by a failover to a lagging replica. The marker is 2 again and j1 is **Enqueued** again.
5. n1, which saw 3, would detect the rollback the next time it checks, but it claims first: the marker is present and unflagged, so REQ-526 does not stop it. The claim script cannot know the marker went backwards; only the node's memory can. **n1 claims j1 while n2 is still running it.**
6. When the rollback is detected, n2's heartbeat finds j1's record *present* but holding n1's lease token. REQ-522 needs a *missing* record, so jobs INV-128 refuses n2's write and n2's run continues.

Two more traces from the same cfg:
- `Inv_ConcurrencyKeyMax`, 12 steps: the restored image predates j1's claim, so `tenant:42` is free and j2 is claimed beside j1.
- `Inv_NoLostOutcome`, 11 steps: n2 completes j1 before anyone notices. The record is missing, but the marker (2) is not older than n2's claim value (2), so REQ-521 does not apply and j1 vanishes.

**Why** Detecting an older marker relies on the memory of the one node that saw the newer value, and that node checks only "at some point". Until then the restored image is live. REQ-522 also only covers the flush case (record missing), not the rollback case (record present but stale).

**Options**
1. *(recommended)* **Let the claim check the node's memory, and re-assert stale records too.**
   - The claiming node passes the last value it saw to the claim script. The script refuses, and the node then detects the reset (REQ-507), when the marker is older (REQ-526: "…or older than the last value the claiming node saw").
   - REQ-522 also applies when the record is present but holds another lease token or another state, and the store was reset since the claim. REQ-521 likewise.
   - What remains: a node that never saw the newer value (n2 above) cannot tell until another node detects. This shrinks to the time until the next claim attempt by any node that did see it.
2. **Treat rollbacks as at-least-once and document it**: in NFR-31, say that after a rollback jobs claimed after the snapshot run again and outcomes in the window can be lost, and that detection reports it afterwards.
3. **Re-check the marker on every write**: every job write passes the node's last-seen value and fails on an older marker. This is exact, but it changes every Lua script (TECH-52 to TECH-87), the same cost that was rejected as run-1 F-2 option 3.

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-526", "ears": { "while": "the generation marker is missing, flagged as reconciling, or older than the last value the claiming node saw",
      "shall": "claim no job, create no recurring occurrence, and hold any enqueue or schedule that carries a unique key until the flag is cleared, failing it with a retryable StoreReconciling error if the flag is still set after LeaseDuration" } },
  { "id": "REQ-522", "ears": { "if": "a heartbeat or progress write finds its job's record missing, or present without its lease token, and the store was reset since the claim",
      "shall": "re-create the job's record as processing with the run's claiming node, leaseToken, leaseExpiresAt, queue, concurrency key, unique key and recurring occurrence, so that queue limits, concurrency keys, unique keys and recurring overlap count the run again, and let the run continue" } }
]
```
(This merges with F-2's snippet for the same two ids.)

---

## F-6 · gap · medium — Two nodes pick marker values independently, so one sees the other's reset as a second one
<!-- finding: gap | Inv_NoFalseReset | REQ-507,REQ-527,SCN-500 -->

**Requirements involved**
- REQ-507: *… replace the marker … with a value **later than any this node has seen** …*
- REQ-527: *… advance the generation marker to a later value by compare-and-set …, and remember the value.*
- SCN-500 (then): *… one ERROR StoreWasReset event …*

**What happens** (TLC, `Redis.cfg`, `Inv_NoFalseReset`, 13 steps; `Inv_OneEventPerReset` fails on the same trace)
1. n1 and n2 both read marker 2. n1 advances it to 3 (REQ-527); n2 has not read 3 yet.
2. FLUSHALL. n1 detects it and writes 4, flagged (later than any value n1 has seen).
3. A second FLUSHALL before n2 looked. n2 detects it and writes **3**: later than any value *n2* has seen (2).
4. n1 reads 3, which is older than the 4 it saw. **n1 reports a third StoreWasReset after two losses**, writes a new flagged value, pauses claims again, and the operator sees a phantom reset.

**Why** "Later than any this node has seen" is local knowledge. After a flush the store holds nothing to compare against, so two nodes can pick values that go backwards relative to each other.

**Options**
1. *(recommended)* **Take marker values from the Redis server clock.** REQ-507 and REQ-527 write the server's current `TIME` (microseconds); REQ-528's lowest value stays the constant 1. The server clock keeps moving across a flush, so every new value is later than any value written before, whoever wrote it. Checked: `Inv_NoFalseReset` and `Inv_OneEventPerReset` pass when values are globally later (`Redis_OptGlobal.cfg`, 4,898,346 states). What remains: a failover to a replica whose clock is behind looks like a rollback. Name that in NFR-31.
2. **Join a flagged marker, never treat it as older**: REQ-507 ignores flagged markers and REQ-530 adopts the flagged value as the node's last-seen value. This conflicts with F-1 option 1, which needs a flagged first marker to be detected as older.
3. **Accept**: back-to-back flushes are rare; say in SCN-500's notes that each detection may log its own event.

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-507", "ears": { "where": "the worker is registered", "while": "the store is ready or reconciling",
      "when": "the generation marker is found missing, or with a value older than the last value this node saw, whether or not it is flagged as reconciling",
      "if": "this node has seen a generation marker since it started",
      "shall": "replace the marker, by compare-and-set against what it found, with the server's current time as its value, flagged as reconciling, log the ERROR event StoreWasReset if its own write succeeded, and in either case start re-seeding the code-defined recurring jobs, the queue registry and this node's registration" } },
  { "id": "REQ-527", "ears": { "where": "the worker is registered", "while": "the store is ready",
      "when": "RecurringReconcileInterval has passed since the generation marker was last advanced",
      "shall": "advance the generation marker to the server's current time by compare-and-set, unless another node already did, and remember the value" } }
]
```
(F-1's REQ-507 snippet says "later than any value ever written"; this option is how to get that.)

---

## Checked and accepted (not findings)
| Check | Config | Result | Why it is not a finding |
|---|---|---|---|
| Runtime eviction (policy changes after startup) | `Redis_Evict.cfg` | `Inv_ConcurrencyKeyMax` violated (12 steps), `Inv_NoLostOutcome` violated (11 steps) | REQ-531 states that resets caused by eviction are not detected; REQ-505 refuses eviction at startup |
| Rollback within one RecurringReconcileInterval (same marker value) | `Redis_Restore.cfg` | `Inv_SingleClaim` (11), `Inv_ConcurrencyKeyMax` (11), `Inv_NoLostOutcome` (10) violated; `Inv_NoFalseReset` passes (8,111,656 states) | NFR-31 states that such a rollback is not detected |
| A-18 off: heartbeats may arrive after HeartbeatInterval with no outage | not run separately | — | covered by F-3: the fix there does not depend on heartbeat timing |

## Passed checks
| Check | Config | Distinct states | Meaning |
|---|---|---|---|
| `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Inv_NoLostOutcome`, `Inv_UnackedUntilOperator` | `Redis.cfg` (two workers, FLUSHALL twice) | 7,494,066 each | The reset design holds jobs INV-103/INV-108 and the reset record when every worker read the marker before the flush and heartbeats are on time |
| `Inv_SingleClaim`, `Scn_NoClaimWhileFlagged` (REQ-526, SCN-504) | `Redis_Outage.cfg` | 2,265,870 | No claim while the marker is missing or flagged, also across an outage |
| `Liv_Reseeded` (LIV-500), `Liv_MarkerWritten` (LIV-501), `Liv_LossReported`, `Liv_UnackedRestored` | `Redis_Liveness.cfg` | 24,919 | One flush: re-seeded, marker written, reported, record kept |
| `Liv_LossReported`, `Liv_UnackedRestored`, `Liv_Reseeded` | `Redis_LivFlush2.cfg` | 671,776 | Two flushes, including one during reconciliation (run-1 F-8) |
| `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivRestore.cfg` | 265,566 | A rollback to an older marker is eventually reported (run-1 F-2) |
| `Liv_Reseeded`, `Scn_ClientNoDetect` (SCN-506) | `Redis_ClientOnly.cfg` | 8,852 | A client-only node never reconciles; LIV-500 holds with the worker wording (run-1 F-4) |
| `Inv_NoFalseReset` | `Redis_Fresh.cfg`, `Redis_LateJoin.cfg` | 80 / 458,031 | A new server, or a late joiner, causes no false reset report (run-1 F-3) |
| `Inv_UnreachableIsUnhealthy`, `Inv_UnhealthyOnlyWithCause` | `Redis_Health.cfg` | 57,006 | Health precedence matches hosting (run-1 F-5, F-6) |
| `Inv_UniqueKey` | `Redis_Shard.cfg` | 1,240 | jobs INV-100's per-queue scope matches INV-500 (run-1 F-10) |
| `Scn_NoEvalNoReady` (SCN-501) | `Redis_SCN501.cfg` | 56 | A server without EVAL never becomes ready |
| SCN-500, SCN-503, SCN-504, SCN-505 traps violated as expected | `Redis_SCN500/503/504/505.cfg` | 493 / 50 / 4,831 / 849 | Positive scenarios are reachable in 9, 5, 14 and 10 steps |
| Option checks | `Redis_OptGlobal.cfg`, `Redis_OptResume.cfg` | 4,898,346 / 7,469 | F-6 option 1 and F-4 option 1 remove their violations |

`Inv_NoFalseReset` on `Redis_RestoreOlder.cfg` timed out at 170 s (the action constraint makes the space larger, not smaller). Its result on `Redis_Restore.cfg` (all rollbacks) passes.

## Modeling assumptions
Decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.
| # | Assumption | Affects |
|---|---|---|
| A-1 | "The store is ready" (REQ-500) is one of the startup checks of hosting REQ-18 | REQ-500, REQ-502, REQ-505, SCN-501 |
| A-2 | A worker reads the marker at any time while its store is ready or reconciling (REQ-507, REQ-528, REQ-530 give no interval) | F-1, F-5, F-6 |
| A-3 | Re-seeding writes the recurring definitions, the queue registry and the node's registration in one step | REQ-507, REQ-530, LIV-500 |
| A-5 | Only `actor: system` steps are (weakly) fair, including heartbeats (jobs REQ-126). The server becomes unreachable at most once per run, and every outage ends | all liveness checks |
| A-6 | used_memory above RedisMemoryDegradedShare is a boolean that can change at any time; HealthyAfterPasses = 1 | REQ-519, REQ-520 |
| A-8 | A stopped node's run and memory disappear with it | `Redis_ClientOnly.cfg` |
| A-9 | "Processing at once" in jobs INV-108, and "holds an unexpired claim" in INV-103, mean handlers actually running under a claim their node believes it holds | F-1, F-3, F-5 |
| A-10 | All model jobs share one concurrency key; with `UniqueKeys` they share one unique key; with `Recurring` they are occurrences of one recurring job with overlap Skip | F-2 |
| A-12 | A restore or failover rolls the whole server back to an image taken earlier, marker included | F-5 |
| A-14 | Job ids and lease tokens are fresh | all |
| A-16 | A refused heartbeat or completion (jobs INV-128) does not stop the handler; no jobs requirement says it does | F-3, F-5 |
| A-17 | In the main cfgs, every worker has read the marker before data is lost; `Redis_LateJoin.cfg` drops this | F-1 |
| A-18 | "HeartbeatInterval has passed since the reconciling marker was written" (REQ-509) is modeled as: every run live at the write has sent a heartbeat since, or an outage intervened. The model has no clock | F-3 |
| A-19 | The compare-and-set in REQ-507 is atomic, so a node that loses it reads the winner's flagged value and follows REQ-530 | REQ-507, REQ-530 |
| A-20 | REQ-527 does not advance a flagged marker | REQ-527 |
| A-21 | Only a rollback to an older marker value counts as a detectable loss in `Liv_LossReported`; same-value rollbacks and runtime evictions are documented as undetected (NFR-31, REQ-531) | `Liv_LossReported` |
| A-22 | A node remembers the last value it saw from ordinary reads, claims, its own writes and learned flagged values (REQ-530: "remember the value") | F-5, F-6 |

(A-4, A-7, A-11, A-13 and A-15 from run 1 no longer apply: the reset record is now explicitly in the store, health guards are now exclusive, "reset since the claim" is defined in the glossary, log-only consequences are listed per action, and REQ-526 forbids claims while the marker is missing or flagged.)

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-500 to REQ-505, REQ-507 to REQ-510, REQ-512, REQ-513, REQ-519 to REQ-533 (REQ-533 absorbed), LIV-500, LIV-501, INV-500, SCN-500, SCN-501, SCN-503 to SCN-506 | REQ-506 (reporting content, no state) · REQ-511 (topology acceptance, a TECH/conformance concern) · REQ-514 (needs real durations; checked statically, run-1 F-11 resolved) · REQ-515 (node registrations by age need a clock; run-1 F-13/F-14 resolved statically) · REQ-516, REQ-517, INV-501, SCN-502 (strength `may`) · REQ-518 (info) |

## How to reproduce
From `specs/model/redis/`:
- `python gen_cfgs.py` writes the cfgs.
- `python run_all.py [cfg …]` runs each invariant and each property alone with `--stop-at-first`, enforces a 170 s limit per run, and stops only that run's TLC process if the limit is hit. Results go to `runs/` and `run.md`, which are gitignored.
- `python trace.py runs/<cfg>__<check>.json` prints a trace as changed variables per step.
- A single check by hand: `python ~/.claude-personal/skills/refiner-model/scripts/run_tlc.py Redis.tla --config Redis_LateJoin.cfg --workers 2 --stop-at-first`.

`OptGlobalValues` and `OptResumeFlag` in the model are option checks for F-6 and F-4. They are `FALSE` in every cfg except `Redis_OptGlobal.cfg` and `Redis_OptResume.cfg`, and they are not requirements.

## Next
Decide F-1, F-3, F-4 and F-6 together, since they share the marker design, then F-2 and F-5. Apply the chosen options to `specs/redis.json` with the `refiner-requirements` skill, then run this skill again.

Already open questions, unchanged by this run: one marker per hash tag under ShardByQueue (TECH-130); the StaleNodeAge value (REQ-533); and whether REQ-531 should report Unhealthy instead of an ERROR. The model shows no new consequence for the first two. For the third, the eviction runs (`Redis_Evict.cfg`) show what an evicting server does to jobs; reporting Unhealthy would make that visible, not prevent it.
