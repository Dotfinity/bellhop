# Findings: Bellhop Redis store behaviour

<!-- refiner-findings v1 | module: redis | specHash: eb75d09b96bf5bac6ef7f375db1cd3b37547c8eacd5eaa979a91b1392532a08b | run: 2026-11-06 | previous: none -->

**Run:** 2026-11-06 · **Requirements file:** `specs/redis.json` (specHash `eb75d09b96bf`) · **Model:** `specs/model/redis/Redis.tla` (+ 12 cfgs) · **TLC:** 2.19, every check run alone with `--stop-at-first`, no TLC exceptions; the main configuration explores 1,046,835 distinct states in about 9 s
**Result:** 14 findings: 5 contradictions · 4 gaps · 0 unprovable · 5 ambiguities

The model covers one Redis server shared by two nodes. It includes the cross-module parts the redis sentences touch: job claims with a concurrency key and a unique key, the maintenance pause, recurring re-seeding, and per-node health. Data loss enters as FLUSHALL, eviction of single keys, or a rollback to an older image (restore from snapshot or failover to a lagging replica). Ten findings come from TLC traces. Four are static (F-10, F-11, F-12, F-13) and are backed by a concrete example from the sentences.

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | contradiction | high | REQ-507, REQ-521, REQ-522, jobs INV-108, INV-107, recurring INV-204 | After a flush, a second job takes a concurrency key while the first run, which REQ-522 lets continue, still holds it |
| F-2 | gap | high | REQ-504, REQ-505, REQ-507, REQ-521, REQ-523, jobs INV-103 | Reset detection only notices a *missing* marker, so a restore, a failover or a partial eviction goes unreported. Jobs then run twice and outcomes are lost |
| F-3 | gap | medium | REQ-507, REQ-509, REQ-523, REQ-524 | A brand-new Redis server is reported as a reset: an ERROR, and Degraded until an operator acknowledges it |
| F-4 | contradiction | medium | LIV-500, REQ-507, REQ-509, hosting REQ-40, REQ-53, recurring REQ-203 | A client-only node detects a reset, can never re-seed, and stays Reconciling and Degraded for ever |
| F-5 | contradiction | medium | REQ-519, REQ-524, REQ-508, hosting REQ-31 | One health-check run can yield both Degraded and Unhealthy. A node whose store is down reports Degraded |
| F-6 | gap | medium | REQ-508, REQ-519, REQ-524, hosting REQ-35 | An Unhealthy node stays Unhealthy after its store comes back while a Degraded-only condition holds |
| F-7 | gap | medium | REQ-507, REQ-523, jobs REQ-162, REQ-163, INV-114 | A flush or restore silently switches off the maintenance pause and other operator settings |
| F-8 | ambiguity | medium | REQ-507, REQ-509, REQ-523, REQ-524, REQ-525 | A second flush during reconciliation erases the unacknowledged-reset record, and nothing detects it |
| F-9 | ambiguity | low | SCN-500, REQ-507, REQ-509, REQ-523 | With two nodes, one flush produces two StoreWasReset events and two new markers, but SCN-500 expects one |
| F-10 | contradiction | medium | INV-500, jobs INV-100 | ShardByQueue lets two active jobs share a unique key in one namespace, which INV-100's sentence forbids |
| F-11 | contradiction | medium | REQ-514, jobs INV-119, REQ-104 | A TTL on captured logs and results can expire them before the job, against INV-119 |
| F-12 | ambiguity | low | REQ-500, REQ-501, REQ-503, REQ-504, REQ-505, REQ-509, REQ-511 | "When the store becomes ready" is undefined after reconciliation and after a reconnect; there is no "connection lost" transition |
| F-13 | gap | low | REQ-507, REQ-515, recurring REQ-205, REQ-206, REQ-207 | After a flush, node registrations are gone, so the orphan sweep can pause or delete the code-defined jobs that were just re-seeded |
| F-14 | ambiguity | low | REQ-515 | The stale-node age is not given, and an event-driven rule is filed as an invariant |

Decide **F-1 first**. It is the only place where a reset breaks a `must` from another module (a distributed mutex) during normal operation. Its fix also changes how REQ-509 and REQ-522 are written, and F-2, F-8 and F-9 depend on that.

---

## F-1 · contradiction · high — After a flush, a second job takes a concurrency key while the first run still holds it
<!-- finding: contradiction | Inv_ConcurrencyKeyMax | REQ-507,REQ-521,REQ-522,jobs:INV-108 -->

**Requirements involved**
- REQ-522: *If a heartbeat or progress write finds its job's record missing because the store's generation changed since the claim, then the system shall ignore the write without error and let the run continue.*
- REQ-521: *When a run completes or fails and its job's record no longer exists because the store's generation changed since the claim, the system shall write a minimal job record …*
- jobs INV-108: *The system shall never let more jobs with the same concurrency key be processing at once, across all nodes, than that key's Max.* The notes say *Max = 1 is a distributed mutex*. INV-107 says *enforced by the store at claim time like concurrency keys*.

**What happens** (TLC, `Redis_Flush.cfg`, `Inv_ConcurrencyKeyMax`, 10 states)
1. Nodes n1 and n2 connect to the ready store and start running (REQ-500, hosting REQ-18).
2. The application enqueues `j1` with concurrency key `tenant:42` (Max = 1).
3. n1 claims `j1`. The store records `j1` as Processing and as the holder of `tenant:42` (jobs REQ-123).
4. Someone runs FLUSHALL. `j1`'s record, the key's holder set and the generation marker are gone.
5. n1's handler keeps running: REQ-522 ignores its heartbeats and lets the run continue.
6. The application enqueues `j2` with the same key `tenant:42`. No active job with that key exists in the store.
7. n2 claims `j2`. The store sees no holder of `tenant:42`. **`j1` on n1 and `j2` on n2 now both run under a Max = 1 key, which violates INV-108.**

The main run reaches the same state with a partial eviction (`EvictJob`) in place of FLUSHALL. The same steps break a queue's concurrency limit (INV-107) and recurring INV-204 (overlap Skip or Queue): their counts live in the same flushed keys.

**Why** Concurrency limits are enforced only from store-side holder sets. A reset erases those sets, and REQ-522 deliberately keeps the old holder running. Nothing re-establishes the old run's hold, and nothing pauses claims until it is re-established. Claims are allowed throughout: before the reset is detected, and while the store is Reconciling.

**Options**
1. *(recommended)* **Re-assert holds and block claims until they are back.** REQ-522: a heartbeat that finds its record missing after a generation change re-creates the record as Processing, with its lease token and concurrency-key hold. A new REQ-526: no job is claimed while the generation marker is missing. REQ-509: the new marker is written only after HeartbeatInterval has passed since detection, so every live run has had one heartbeat to re-assert its hold. This closes the window for FLUSHALL, where the marker disappears with the data. It does not cover partial eviction; see F-2. Cost: claims pause for about one HeartbeatInterval (20 s) after a reset.
2. **Cancel in-flight runs on a reset.** REQ-522 signals the handler's cancellation token instead of letting it continue. Simpler, but the window between the flush and the next heartbeat (up to 20 s, plus TimeoutGracePeriod) stays open, and work that would have finished is cancelled.
3. **Accept and document.** Add *"except after a store reset (redis REQ-507)"* to jobs INV-107 and INV-108 and to recurring INV-204, as INV-500 already does for INV-100, and state the lost mutual exclusion in NFR-31. This is honest, but a Max = 1 key is often used for exactly-one guarantees.

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-522", "ears": { "if": "a heartbeat or progress write finds its job's record missing because the store's generation changed since the claim",
      "shall": "re-create the job's record as processing with the run's claiming node, leaseToken, leaseExpiresAt and concurrency-key hold, and let the run continue" } },
  { "id": "REQ-526", "kind": "invariant", "status": "proposed", "entity": "RedisStore",
    "ears": { "while": "the generation marker is missing", "shall": "claim no job" },
    "mentions": ["RedisStore.generationMarker", "jobs.Job"], "dependsOn": ["REQ-507"],
    "rationale": "F-1: holds erased by a flush must be re-asserted before new holders are admitted (jobs INV-107, INV-108, recurring INV-204)." },
  { "id": "REQ-509", "ears": { "while": "the store is reconciling",
      "when": "the code-defined recurring jobs and the queue registry have been re-seeded and HeartbeatInterval has passed since the reset was detected",
      "shall": "write a new generation marker and mark the store ready" } }
]
```

---

## F-2 · gap · high — Reset detection only notices a missing marker; restores, failovers and partial evictions go unreported
<!-- finding: gap | Liv_LossReported | REQ-504,REQ-505,REQ-507,REQ-521,REQ-523 -->

**Requirements involved**
- REQ-507: *While the store is ready, when the generation marker key is found missing, the system shall log the ERROR event StoreWasReset and start re-seeding …* Its notes say *Causes: FLUSHALL, eviction, restore from an old snapshot.*
- REQ-504: *… replication is asynchronous and a failover can drop acknowledged writes.*
- REQ-505: *… the server may evict job data.*
- REQ-521 notes: *A record missing for any other reason is still refused.*

**What happens**: three TLC traces.

*(a) Restore or failover runs a job twice* (`Redis_Restore.cfg`, `Inv_SingleClaim` = jobs INV-103, 10 states)
1. n1 and n2 run. The application enqueues `j1` (generation marker = 1).
2. A snapshot is taken, or the replica's copy lags at this point.
3. n1 claims `j1`.
4. The server is restored from that snapshot, or fails over to that replica. `j1` is back to Enqueued and the marker is 1 again: **present, so REQ-507 never fires.**
5. n2 claims `j1`. **n1 and n2 now both run `j1` under live claims, which violates INV-103.** No ERROR is logged and health stays Healthy. When n1 completes, fencing (jobs INV-128) refuses its write.

`Liv_LossReported` (`Redis_LivRestore.cfg`, stutters after 15 states) confirms that the rollback is never detected while both nodes keep running.

*(b) Partial eviction loses an outcome* (`Redis.cfg`, `Inv_NoLostOutcome`, 7 states)
1. n1 runs and claims `j1` at generation 1.
2. Under a maxmemory policy other than noeviction (only a warning, REQ-505), Redis evicts `j1`'s record. The marker stays.
3. `j1`'s handler succeeds. The record is missing but the generation did not change, so REQ-521 does not apply, and its notes say the write is refused. **The successful outcome is lost, and no reset is ever reported.**

*(c) A second flush before the new marker loses an outcome* (`Redis_Flush.cfg`, `Inv_NoLostOutcome`, 8 states)
1. FLUSHALL. Before any node checks the marker, the application enqueues `j1` and n1 claims it. The claim reads marker = missing.
2. A second FLUSHALL. n1 completes `j1`: the record is missing and the marker is "missing", as at claim time, so the generation looks unchanged. **The write is refused and the outcome is lost.**

*(d) An evicted recurring definition comes back silently* (`Redis_Liveness.cfg`, `Liv_LossReported`, stutters after 13 states)
1. Eviction removes the stored definition of `nightly-cleanup`. The marker stays.
2. REQ-510's periodic reconciliation re-creates it, so code-defined jobs recover, but **no reset is ever reported**. A runtime-defined recurring job evicted the same way is simply gone (REQ-523 never fires).

**Why** A missing marker proves a reset, but a present marker does not prove there was none. A rollback restores the marker as well. Eviction removes keys one at a time. The generation-change test in REQ-521 and REQ-522 inherits the blind spot.

**Options**
1. *(recommended)* **Detect rollbacks, refuse partial eviction.** The marker carries a value that moves forward: a new value every RecurringReconcileInterval, which every node remembers. A marker *older* than the one a node last saw counts as a reset, like a missing marker. REQ-505 becomes a startup failure unless maxmemory-policy is noeviction, so a partial eviction cannot happen silently. REQ-521's "generation changed" then also covers "marker older than at claim". This detects rollbacks older than one interval. Cost: one write per interval, and a strict refusal on servers that cannot be configured.
2. **Report what cannot be detected.** Keep detection as it is. Fix REQ-507's notes, which currently list restore as a detected cause. Add an `info` item and NFR-31 text saying that restores, failovers and partial evictions are not detected and can duplicate or lose jobs.
3. **Record per-write sequence numbers** on every job write and compare them on heartbeat. Exact, but it adds a write to every Lua script, and the TECH-52 to TECH-87 scripts change.

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-507", "ears": { "while": "the store is ready",
      "when": "the generation marker key is found missing, or its value is older than the value this node last saw",
      "shall": "log the ERROR event StoreWasReset and start re-seeding the code-defined recurring jobs and the queue registry" } },
  { "id": "REQ-527", "kind": "transition", "status": "proposed", "entity": "RedisStore", "actor": "system", "from": ["Ready"], "to": ["Ready"],
    "ears": { "while": "the store is ready", "when": "RecurringReconcileInterval has passed since the generation marker was last advanced",
              "shall": "advance the generation marker to a new, later value and remember it" },
    "mentions": ["RedisStore.generationMarker"], "dependsOn": ["REQ-510"],
    "rationale": "F-2: a restore or failover brings back an older marker; only a marker that moves forward reveals the rollback." },
  { "id": "REQ-505", "ears": { "when": "the store becomes ready", "if": "maxmemory-policy is anything other than noeviction",
      "shall": "stop the node from starting with a message that eviction can silently delete job data and names the setting" } }
]
```

---

## F-3 · gap · medium — A brand-new Redis server is reported as a reset
<!-- finding: gap | Inv_NoFalseReset | REQ-507,REQ-509,REQ-523,REQ-524 -->

**Requirements involved**
- REQ-507 (quoted in F-2). REQ-509 notes: *Writing a new marker is implied.* No requirement writes the *first* marker.
- REQ-523: *When the store detects a reset, the system shall log an ERROR … and record the reset as unacknowledged.* REQ-524: *if a store reset has not been acknowledged, then … report the node Degraded.*

**What happens** (TLC, `Redis_Fresh.cfg`, `Inv_NoFalseReset`, 4 states; no data-loss event at all)
1. First deployment: n1 connects to an empty Redis server, and the store becomes ready (REQ-500).
2. n1 starts running (hosting REQ-18).
3. n1 finds the generation marker missing. **It logs StoreWasReset, logs that runtime-defined recurring jobs may have been lost, and records an unacknowledged reset (REQ-507, REQ-523). From then on it reports Degraded until an operator acknowledges (REQ-524).**

`Redis.cfg` shows the same result when only the marker key is evicted and all data is intact (`Inv_NoFalseReset`, 5 states).

**Why** An empty server and a flushed server look the same, and no requirement initialises the marker.

**Options**
1. *(recommended)* **Initialise on first sight.** When the store becomes ready and finds no marker, a node that has not seen a marker since it started writes the first marker with an INFO log. Only a node that has seen a marker reports a reset. Trade-off: a flush that happens while every node is down is not reported.
2. **Explicit initialisation.** The marker is written by an install step (AutoMigrate or a CLI init, hosting REQ-22). Until then the node fails to start with a message. Precise, but it adds a setup step, unlike the SQL stores.
3. **Keep it, and document** that a new installation shows one reset that someone must acknowledge.

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-528", "kind": "transition", "status": "proposed", "entity": "RedisStore", "actor": "system", "from": ["Ready"], "to": ["Ready"],
    "ears": { "while": "the store is ready", "when": "the generation marker key is found missing",
              "if": "this node has not seen a generation marker since it started",
              "shall": "write the first generation marker and log at INFO that it initialised the store" },
    "mentions": ["RedisStore.generationMarker"],
    "rationale": "F-3: an empty server must not be reported as a reset." },
  { "id": "REQ-507", "ears": { "while": "the store is ready and this node has seen a generation marker since it started",
      "when": "the generation marker key is found missing",
      "shall": "log the ERROR event StoreWasReset and start re-seeding the code-defined recurring jobs and the queue registry" } }
]
```
If you also take F-2 option 1, merge the two `when` clauses for REQ-507.

---

## F-4 · contradiction · medium — A client-only node detects a reset and stays Reconciling for ever
<!-- finding: contradiction | Liv_Reseeded | LIV-500,REQ-507,REQ-509,hosting:REQ-40 -->

**Requirements involved**
- LIV-500: *While the generation marker is missing and a node is running, the system shall eventually re-seed every code-defined recurring job.*
- REQ-507 (any node that is ready) and REQ-509: *… when the code-defined recurring jobs and the queue registry have been re-seeded, … write a new generation marker and mark the store ready.*
- hosting REQ-40: *While a node has no worker registered, the system shall run no background duty … Redis recurring reconciliation …*. hosting REQ-53 and recurring REQ-203: only worker nodes declare, and so create, code-defined recurring jobs.

**What happens** (TLC, `Redis_ClientOnly.cfg`, `Liv_Reseeded`, stuttering after 12 states)
1. Worker node n1 and client-only node n2 (web front end, no AddWorker) both start.
2. The host stops n1 for a deploy (hosting REQ-27/REQ-29). Then someone runs FLUSHALL.
3. n2 finds the marker missing. It logs StoreWasReset and goes to Reconciling (REQ-507). Its health turns Degraded (REQ-508).
4. n2 cannot re-seed: it has no worker and declares no recurring jobs. REQ-509 waits for the re-seed. **n2 stays Reconciling and Degraded, the marker stays missing, and `nightly-cleanup` never comes back while a node is running, which violates LIV-500.**

With two worker nodes that keep running, LIV-500 holds (`Redis_Liveness.cfg`, 10,164 states).

**Why** LIV-500 promises re-seeding whenever *any* node runs, but re-seeding is a worker duty. REQ-507 does not restrict detection to worker nodes, so a client node starts a reconciliation it can never finish.

**Options**
1. *(recommended)* Restrict detection and reconciliation to worker nodes (`where` clause on REQ-507), and require a running *worker* node in LIV-500. A client-only node then never enters Reconciling. This matches hosting REQ-40.
2. Keep detection on every node, but let a client node finish when another node has re-seeded and written the marker (REQ-509 `when` "… or another node has written a new generation marker"). LIV-500 still needs the worker wording.
3. Downgrade LIV-500 to `should` and document that a deployment with no worker running does not recover recurring jobs.

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-507", "ears": { "where": "the worker is registered", "while": "the store is ready",
      "when": "the generation marker key is found missing",
      "shall": "log the ERROR event StoreWasReset and start re-seeding the code-defined recurring jobs and the queue registry" } },
  { "id": "LIV-500", "ears": { "while": "the generation marker is missing and a node with the worker registered is running",
      "shall": "eventually re-seed every code-defined recurring job" }, "mentions": ["RedisStore.generationMarker", "hosting.Node.Running"] }
]
```

---

## F-5 · contradiction · medium — One health check yields both Degraded and Unhealthy
<!-- finding: contradiction | Inv_UnreachableIsUnhealthy | REQ-519,REQ-524,REQ-508,hosting:REQ-31 -->

**Requirements involved**
- hosting REQ-31: *When the health check runs, if the store is unreachable, the system shall report the node Unhealthy.*
- REQ-519: *When the health check runs, if the Redis server's used_memory is above RedisMemoryDegradedShare of its maxmemory, then … report the node Degraded.* REQ-524 (unacknowledged reset) and REQ-508 (reconciling) have the same shape. All of them have `from: Healthy`.
- hosting REQ-34 resolves this for its own checks (*"if no check that reports Unhealthy fails"*). The redis rules do not.

**What happens** (TLC, `Redis_Health.cfg`, `Inv_UnreachableIsUnhealthy`, 4 states)
1. n1 is Healthy. Redis becomes unreachable. used_memory was last above 80 % of maxmemory.
2. The health check runs. REQ-31 says Unhealthy and REQ-519 says Degraded, both from Healthy, on the same trigger. **TLC takes Degraded: a node whose store is down reports Degraded.** An orchestrator that maps Unhealthy to "not ready" keeps routing traffic to it.

An unacknowledged reset (REQ-524) produces the same conflict.

**Why** Several rules fire on one event with different outcomes, and none of them states a precedence. The validator's same-trigger warning (REQ-519 / REQ-524 on hosting.Health) points at the same place.

**Options**
1. *(recommended)* Add REQ-34's guard to REQ-508, REQ-519 and REQ-524: *"if no check that reports Unhealthy fails"*. This is local, and consistent with hosting.
2. Add one hosting invariant: *the health check reports the worst outcome of all its checks*. One rule instead of three guards, but it lives in the hosting module.
3. Leave it, and define precedence in TECH. This is behaviour, so it does not belong there.

**Ready to apply (option 1, with F-6)**: see the combined snippet in F-6.

---

## F-6 · gap · medium — An Unhealthy node stays Unhealthy after its store comes back
<!-- finding: gap | Inv_UnhealthyOnlyWithCause | REQ-508,REQ-519,REQ-524,hosting:REQ-35 -->

**Requirements involved**
- REQ-508, REQ-519, REQ-524: *from: Healthy* → Degraded.
- hosting REQ-35: *… if every check has passed on the last HealthyAfterPasses runs in a row, … report the node Healthy.*
- hosting REQ-34 notes: *From Unhealthy as well, so a node whose store comes back but still has a backlog drops to Degraded instead of staying Unhealthy.*

**What happens** (TLC, `Redis_Health.cfg`, `Inv_UnhealthyOnlyWithCause`, 6 states)
1. Redis becomes unreachable. The health check reports Unhealthy (REQ-31).
2. Redis comes back. used_memory is above 80 %.
3. The health check runs. REQ-35 cannot apply because the memory check fails. REQ-519 applies only from Healthy. **The node stays Unhealthy with its store reachable.** The orchestrator keeps it out of service until memory drops.

An unacknowledged reset gives the same result, and it can last for days, because it ends only when an operator acknowledges. So does a store that is still reconciling.

**Why** The redis Degraded rules were written from Healthy only. hosting REQ-34 was widened to include Unhealthy for exactly this reason.

**Options**
1. *(recommended)* `from: ["Healthy", "Unhealthy"]` on REQ-508, REQ-519 and REQ-524, plus the F-5 guard.
2. Replace the three rules with a single "worst outcome of all checks" rule (F-5 option 2). Recovery from Unhealthy then follows automatically.

**Ready to apply (option 1 for F-5 and F-6)**
```json
[
  { "id": "REQ-519", "from": ["Healthy", "Unhealthy"], "ears": { "when": "the health check runs",
      "if": "no check that reports Unhealthy fails and the Redis server's used_memory is above RedisMemoryDegradedShare of its maxmemory",
      "shall": "report the node Degraded" } },
  { "id": "REQ-524", "from": ["Healthy", "Unhealthy"], "ears": { "when": "the health check runs",
      "if": "no check that reports Unhealthy fails and a store reset has not been acknowledged",
      "shall": "report the node Degraded" } },
  { "id": "REQ-508", "from": ["Healthy", "Unhealthy"], "ears": { "while": "the Redis store is reconciling after a reset",
      "if": "no check that reports Unhealthy fails", "shall": "report the node Degraded" } }
]
```

---

## F-7 · gap · medium — A flush or restore silently switches off the maintenance pause
<!-- finding: gap | Inv_MaintenanceOnlyOperatorOff | REQ-507,REQ-523,jobs:REQ-162,jobs:REQ-163 -->

**Requirements involved**
- jobs REQ-163: *When an operator turns off the global maintenance pause, the system shall mark maintenance off.* No other transition leaves `On`.
- jobs INV-114: *While maintenance is on, the system shall never claim any job on any node.*
- REQ-507 re-seeds only *the code-defined recurring jobs and the queue registry*. REQ-523 reports only the runtime-defined recurring jobs.

**What happens** (TLC, `Redis.cfg` and `Redis_Restore.cfg`, `Inv_MaintenanceOnlyOperatorOff`, 3 states)
1. An operator turns maintenance on for a database migration (jobs REQ-162).
2. FLUSHALL, or a restore from a snapshot taken before step 1. **The maintenance flag is gone, and every worker starts claiming again (jobs REQ-123).** No requirement covers this change. The ERROR from REQ-523 mentions recurring jobs only.

The same applies to other operator state kept in Redis: paused queues, throttle changes made at runtime (jobs REQ-158), and recurring jobs an operator paused. A paused code-defined job is re-seeded as **Active**, because recurring REQ-203 always creates `to: Active`.

**Why** Re-seeding restores what code declares. Operator decisions stored in Redis are lost, and the requirements say nothing about them.

**Options**
1. *(recommended)* **Report it.** Extend REQ-523's ERROR to list what fell back to defaults: maintenance off, queues resumed, runtime throttle limits and recurring pauses dropped. This matches the owner's "report only" decision for runtime-defined jobs.
2. **Fail safe.** On reset detection, turn maintenance on until an operator acknowledges the reset (REQ-525). Nothing runs against a half-restored store, but every flush becomes an outage until someone acts.
3. **Cache operator state on the nodes** and re-apply it while re-seeding. This contradicts the REQ-523 notes (*nodes do not cache runtime definitions*).

**Ready to apply (option 1)**
```json
{ "id": "REQ-523", "ears": { "when": "the store detects a reset",
    "shall": "log an ERROR saying that runtime-defined recurring jobs, the maintenance pause, queue pauses, runtime throttle limits and recurring-job pauses may have been lost and are back at their defaults, and record the reset as unacknowledged" } }
```

---

## F-8 · ambiguity · medium — A second flush during reconciliation erases the unacknowledged-reset record
<!-- finding: ambiguity | Inv_UnackedUntilOperator | REQ-507,REQ-509,REQ-523,REQ-524,REQ-525 -->

**Requirements involved**
- REQ-523: *… record the reset as unacknowledged.* It does not say where. REQ-524 notes: *Lasts beyond reconciliation (REQ-508), until an operator acknowledges the reset (REQ-525).*
- REQ-507 applies only *while the store is ready*. REQ-509 writes the marker only at the end of reconciliation.
- hosting REQ-51 notes: the dashboard and the nodes talk *only through the store*, so the record is in Redis. This is modeling assumption A-4.

**What happens** (TLC, `Redis.cfg`, `Inv_UnackedUntilOperator`, 6 states)
1. n1 runs. FLUSHALL. n1 finds the marker missing, logs StoreWasReset, records the reset as unacknowledged, and starts reconciling (REQ-507, REQ-523).
2. A second FLUSHALL (a script run twice, or a second eviction wave) while n1 is still Reconciling. **The unacknowledged-reset record is gone.** n1 is not Ready, so REQ-507 does not fire again, and the marker was already missing, so nothing changes from n1's point of view.
3. n1 re-seeds and writes the marker (REQ-509). Health returns to Healthy at the next checks (REQ-35). **Nobody acknowledged the reset, and the jobs enqueued between the two flushes are lost without a report.**

`Liv_LossReported` (`Redis_LivFlush2.cfg`, stutters after 16 states) shows the second flush is never detected: n1 finishes reconciling, writes marker 2, and both nodes run on.

If the record is kept on the nodes instead, only the detecting node degrades, and a restart forgets the reset. That is a different, also unintended, behaviour. That is why this is an ambiguity, not a contradiction.

**Options**
1. *(recommended)* **Mark the reset in the store at detection time.** REQ-507 writes a new marker value, flagged as "reconciling", as soon as it detects the reset. A second flush removes it again and is detected again, even during reconciliation. REQ-509 then only clears the flag. Keep the unacknowledged record in the store (state it), and have every node re-assert it while it remembers an unacknowledged reset.
2. **Keep the record in node memory** and have each node re-write it to the store at each health check until the store shows it acknowledged. It survives flushes but not a cluster-wide restart.
3. Say explicitly that the record is in Redis and that a later flush can erase it, and accept the gap.

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-507", "ears": { "while": "the store is ready or reconciling",
      "when": "the generation marker key is found missing",
      "shall": "log the ERROR event StoreWasReset, write a new generation marker flagged as reconciling, and start re-seeding the code-defined recurring jobs and the queue registry" } },
  { "id": "REQ-509", "ears": { "while": "the store is reconciling",
      "when": "the code-defined recurring jobs and the queue registry have been re-seeded",
      "shall": "clear the reconciling flag on the generation marker and mark the store ready" } },
  { "id": "REQ-523", "ears": { "when": "the store detects a reset",
      "shall": "log an ERROR saying that runtime-defined recurring jobs may have been lost and cannot be re-seeded, and record the reset as unacknowledged in the store, re-writing that record whenever it is found missing while this node remembers an unacknowledged reset" } }
]
```

---

## F-9 · ambiguity · low — One flush, two StoreWasReset events and two markers
<!-- finding: ambiguity | Inv_OneEventPerReset | SCN-500,REQ-507,REQ-509,REQ-523 -->

**Requirements involved**
- SCN-500 *then*: *… one ERROR StoreWasReset event and one ERROR about possibly lost runtime-defined recurring jobs were logged …*
- REQ-507 and REQ-509 are per node (*"The Redis store as seen by one node"*).

**What happens** (TLC, `Redis.cfg`, `Inv_OneEventPerReset`, 8 states)
1. n1 and n2 both run. FLUSHALL.
2. n1 finds the marker missing and logs StoreWasReset (REQ-507).
3. n2 finds the marker missing before n1 has written a new one. **It logs StoreWasReset as well: two events for one reset.** Later both write a new marker (REQ-509), so the generation advances twice.

SCN-500 has one node, so it passes as written (`Redis_SCN500.cfg`: reachable in 8 states). The two-node behaviour is what the scenario's "one event" does not say.

**Options**
1. *(recommended)* Detection by compare-and-set: only the node that writes the new (reconciling) marker first logs and records the reset; the others reconcile silently. This fits F-8 option 1.
2. Reword SCN-500 to "one StoreWasReset event per node that detects the reset", and let dashboards de-duplicate.

**Ready to apply (option 1)**
```json
{ "id": "REQ-507", "ears": { "while": "the store is ready or reconciling",
    "when": "the generation marker key is found missing",
    "shall": "write a new generation marker flagged as reconciling only if none exists yet, and, if this node wrote it, log the ERROR event StoreWasReset; in either case start re-seeding the code-defined recurring jobs and the queue registry" } }
```

---

## F-10 · contradiction · medium — ShardByQueue lets two active jobs share a unique key in one namespace
<!-- finding: contradiction | Inv_UniqueKeyPerNamespace | INV-500,jobs:INV-100 -->

**Requirements involved**
- INV-500: *Where ShardByQueue mode is on, the system shall enforce unique keys per queue rather than per namespace.*
- jobs INV-100: *The system shall never hold two active jobs with the same unique key in the same namespace, even when the enqueues arrive concurrently on different nodes.* The exception is only in its notes.

**What happens** (TLC, `Redis.cfg`, `Inv_UniqueKeyPerNamespace`, 3 states)
1. ShardByQueue is on. The application enqueues `j1` in queue `emails` with unique key `invoice-7`.
2. The application enqueues `j2` in queue `pdf` with the same key. INV-500 checks only the `pdf` queue and accepts it. **Two active jobs with key `invoice-7` exist in one namespace, which violates INV-100's sentence.**

**Why** The exception lives in an annotation (`notes`), which the model and the code generator never read.

**Options**
1. *(recommended)* Put the exception into INV-100's sentence.
2. Keep namespace-wide uniqueness under ShardByQueue with a separate lock key per unique key. This needs a second hash slot, so the Lua script is no longer atomic in Cluster mode.
3. Refuse unique keys on jobs in ShardByQueue mode unless the key's scope is declared per queue.

**Ready to apply (option 1, to `jobs.json`)**
```json
{ "id": "INV-100", "ears": { "shall": "never hold two active jobs with the same unique key in the same namespace or, where the Redis ShardByQueue mode is on (redis INV-500), in the same queue, even when the enqueues arrive concurrently on different nodes" } }
```

---

## F-11 · contradiction · medium — A TTL on captured logs and results can outlive INV-119
<!-- finding: contradiction | REQ-514 | REQ-514,jobs:INV-119,jobs:REQ-104 -->

The model cannot judge this, because it depends on durations that are not given. Static example:

**Requirements involved**
- REQ-514 (`should`): *The system shall cap the size of captured logs and job results and give them a TTL.* Notes: *The TTL value is not given. It must not be shorter than the job's own retention, or INV-119 breaks.*
- jobs INV-119: *The system shall keep a job's state history, captured logs and parameters for exactly as long as the job itself.*
- jobs REQ-104: dead-lettered jobs are kept 30 days, succeeded jobs 7 days.

**Example** A job dead-letters on day 0, and its captured logs get a TTL of 7 days, the succeeded-job retention. On day 10 an operator opens the dead letter (kept 30 days) to diagnose it: **the job is there, but its captured logs have expired, which violates INV-119.** A requeue of an old dead letter (jobs INV-129) produces the same result: the job lives on while the earlier run's logs expire.

**Options**
1. *(recommended)* Tie the TTL to the job: *give them the same TTL as the job's record, renewed whenever the job changes state*.
2. No TTL on logs and results; they are deleted together with the job (jobs REQ-145). A TTL is only a safety net, longer than the longest retention.
3. Make INV-119 "at least as long as the job" for Redis and accept orphan logs until their TTL.

**Ready to apply (option 1)**
```json
{ "id": "REQ-514", "ears": { "shall": "cap the size of captured logs and job results and give them the same TTL as their job's record, renewed whenever the job changes state" } }
```

---

## F-12 · ambiguity · low — "When the store becomes ready" after reconciliation and after a reconnect
<!-- finding: ambiguity | RedisStore.Ready | REQ-500,REQ-503,REQ-504,REQ-505,REQ-509,REQ-511 -->

- REQ-503, REQ-504 and REQ-505 fire *when the store becomes ready*. REQ-509 also makes the store ready, so after every reset the durability warnings would be logged again. Is that intended?
- RedisStore has no transition out of Ready on connection loss. After a Sentinel failover (REQ-511) the node keeps the family, version and durability findings of the old primary, and the new primary's AOF or eviction settings are never checked.
- REQ-500 and REQ-501 share a trigger (validator warning). REQ-500 says *apply that family's adjustments* even when the family is unknown (REQ-501). What does "adjustments" mean for an unknown family?

**Recommended**: add a Ready → Connecting transition on connection loss, and say that REQ-500 to REQ-505 run on every (re)connection, not after reconciliation:
```json
[
  { "id": "REQ-529", "kind": "transition", "status": "proposed", "entity": "RedisStore", "actor": "system", "from": ["Ready", "Reconciling"], "to": ["Connecting"],
    "ears": { "when": "the connection to the server is lost or the server's role changes", "shall": "mark the store connecting and repeat server detection when it reconnects" },
    "mentions": ["RedisStore.reachable", "RedisStore.topology"],
    "rationale": "F-12: after a failover the new primary's family, persistence and eviction settings are re-checked." },
  { "id": "REQ-503", "ears": { "when": "the store becomes ready after connecting", "if": "INFO persistence shows that AOF is off, or the server persists by snapshot only",
      "shall": "log a warning that acknowledged jobs can be lost in a crash, naming the server's durability flag where one exists, such as --aof-commit-wait on Garnet" } }
]
```
(REQ-504 and REQ-505 take the same `when` wording.)

---

## F-13 · gap · low — After a flush, the orphan sweep can pause or delete re-seeded recurring jobs
<!-- finding: gap | RecurringJob.Orphaned | REQ-507,REQ-515,recurring:REQ-205,recurring:REQ-207 -->

Not modeled; this is a static example. Node registrations, which hold the recurring names each node declares (recurring REQ-205 notes), are Redis keys, and REQ-515 manages them, so FLUSHALL removes them too. REQ-507 re-seeds the definitions but not the registrations. If the scheduler's orphan sweep runs before the next node heartbeat re-registers the node, it *"finds a stored code-defined recurring job that no running worker node declares"*. With the default policy it orphans and pauses the job (REQ-205), and the job comes back at the next heartbeat (REQ-206). With the delete policy it **removes the just-re-seeded definition** (REQ-207), until the next REQ-510 reconciliation up to 5 minutes later. Occurrences in between are missed.

**Recommended**: add node registrations to what REQ-507 re-seeds (*"… the queue registry and this node's registration"*), or pause the orphan sweep while any node reports the store reconciling.

---

## F-14 · ambiguity · low — The stale-node age is not given
<!-- finding: ambiguity | REQ-515 | REQ-515 -->

REQ-515: *When a node has not sent a heartbeat for longer than the stale-node age, the system shall remove its node registration.* There is no constant for the age, and no `assumption` or glossary entry. It is filed as an `invariant`, but it is event-driven and changes hosting.Node registration state: it is a transition. This matters because jobs REQ-124 (Unroutable) and recurring REQ-205 (Orphaned) count "running worker nodes" from these registrations.

**Recommended**: add an assumption *"default StaleNodeAge to 3 × HeartbeatInterval (StaleNodeAge)"* or whatever the owner prefers, and change REQ-515 to `kind: transition`, with `entity: hosting.Node` and `actor: system`.

---

## Passed checks
| Check | Config | Distinct states | Meaning |
|---|---|---|---|
| `Scn_NoEvalNoReady` (SCN-501) | `Redis.cfg`, `Redis_SCN501.cfg` | 1,046,835 / 188 | A server without EVAL never lets the store become ready; the node fails to start (REQ-502) |
| `Scn_FlushRecovered_NotReached` violated as expected (SCN-500) | `Redis_SCN500.cfg` | 908 | FLUSHALL → StoreWasReset → re-seed → new marker → Ready, Degraded with the reset unacknowledged: reachable in 8 states |
| `Inv_SingleClaim` (jobs INV-103) | `Redis.cfg`, `Redis_Flush.cfg` | 1,046,835 / 607,860 | A flush or eviction alone never lets two workers run the *same* job (only a rollback does, F-2) |
| `Inv_UnackedUntilOperator` | `Redis_Health.cfg` (one flush) | 8,684 | With a single reset the record survives until an operator acknowledges; F-8 needs two |
| `Inv_NoFalseReset` | `Redis_Restore.cfg` | 3,540 |
| `Liv_Reseeded` (LIV-500) | `Redis_Liveness.cfg` (two worker nodes) | 10,164 | With a worker running, every code-defined recurring job is re-seeded after a flush or eviction |
| `Inv_SingleClaim` + `Scn_NoEvalNoReady` together | `Redis.cfg` | 1,046,835 | Same full space as when each runs alone, so the search was complete | Rollbacks never cause a *false* reset (they cause a missed one, F-2) |

## Modeling assumptions
Decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.
| # | Assumption | Affects |
|---|---|---|
| A-1 | "The store is ready" (REQ-500) is one of the startup checks of hosting REQ-18, so a node runs only after its store is ready | REQ-500, REQ-502, SCN-501 |
| A-2 | The marker check (REQ-507) runs on any running node, at any time while its store is ready; no interval is given | REQ-507, F-4, F-9 |
| A-3 | Only worker nodes re-seed (hosting REQ-40, REQ-53; recurring REQ-203). Re-seeding writes the recurring definitions and the queue registry in one step | REQ-507, REQ-509, LIV-500 |
| A-4 | The unacknowledged-reset record is kept in Redis (dashboard and nodes talk only through the store, hosting REQ-51 notes) | REQ-523–REQ-525, F-8 |
| A-5 | Only `actor: system` steps are (weakly) fair. The server becomes unreachable at most once per run (`MaxOutages = 1`), and every outage ends. Without this, a server that flaps or stays down for ever fails every liveness check trivially | LIV-500, Liv_LossReported |
| A-6 | used_memory above RedisMemoryDegradedShare is a boolean that can change at any time. HealthyAfterPasses = 1 | REQ-519, REQ-520, F-5, F-6 |
| A-7 | When several health rules apply to one check, any of their outcomes may result; no precedence is stated | F-5 |
| A-8 | A stopped node's run disappears with it (hosting drain and lease release are in other modules) | F-4 |
| A-9 | "Processing at once" in jobs INV-108 means handlers actually running under a claim their node holds, not just Processing records | F-1 |
| A-10 | All model jobs share one concurrency key (Max = 1) and one unique key. With ShardByQueue, `j1` is in qA and `j2` in qB | F-1, F-10 |
| A-11 | "The store's generation changed since the claim" (REQ-521, REQ-522) means the marker value read at claim time differs from the current one; "missing" counts as a value | F-2(c) |
| A-12 | A restore or failover rolls the whole server back to an image taken earlier, marker included (REQ-504: replication is asynchronous) | F-2(a), F-7 |
| A-13 | Log lines, family and version detection, and the startup summary carry no state; only StoreWasReset events are counted | REQ-500, REQ-501, REQ-503–REQ-505 |
| A-14 | Job ids are fresh, so every id is enqueued at most once | F-1, F-10 |
| A-15 | Claims are allowed while a node's store is reconciling, and before a reset is detected; no requirement forbids them | F-1 |
| A-16 | Heartbeats change no modeled state (lease timing is the jobs module's), so REQ-522 is encoded by the absence of any action that stops a run whose record vanished | REQ-522, F-1 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-500 to REQ-505, REQ-507 to REQ-510, REQ-512, REQ-513, REQ-519 to REQ-525, LIV-500, INV-500, SCN-500, SCN-501 | REQ-506 (reporting content, no state) · REQ-511 (topology acceptance, a TECH/conformance concern) · REQ-514 (needs real durations; static finding F-11) · REQ-515 (age not given; F-14) · REQ-516, REQ-517, INV-501, SCN-502 (strength `may`, not checked) · REQ-518 (info) |

## How to reproduce
From `specs/model/redis/`: `python run_all.py` runs every cfg the way this report was produced. Each invariant runs alone with `--stop-at-first`, each property runs alone, and scenarios run as written. Results go to `runs/` and to `run.md`, which are gitignored. A single check by hand, for example:
`python ~/.claude-personal/skills/refiner-model/scripts/run_tlc.py Redis.tla --config Redis_Fresh.cfg --workers 2 --stop-at-first`

## Next
Apply the chosen options to `specs/redis.json` (and the `jobs.json` / `hosting.json` snippets in F-5, F-6 and F-10) with the `refiner-requirements` skill, which validates and diffs, then run this skill again. Findings whose fingerprint disappears are listed as resolved in the next report.
