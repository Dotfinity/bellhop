# Findings: Bellhop hosting, configuration, startup, health and shutdown

<!-- refiner-findings v1 | module: hosting | specHash: 40f284cf2fba0ca8fe76266669a0c1be00a7c3040138a5f78e1a04b5d8793fa0 | run: 2026-11-06 | previous: none -->

**Run:** 2026-11-06 · **Requirements file:** `specs/hosting.json` (specHash `40f284cf2fba`) · **Model:** `specs/model/hosting/Hosting.tla`
**TLC:**
- `Hosting.cfg` (1 node, all configurations): safety; 8 checks violated (below), no deadlock. The `-continue` run hit a TLC 2.19 internal exception at 56,395 of 106,368 distinct states, so it is used only for its violations. Each violated check also has its own `--stop-at-first` trace under `traces/`.
- `traces/Holds.cfg` (1 node, every requirement invariant and property reported as holding, `--stop-at-first`): **passed** over the full 106,368 distinct states.
- `Hosting_2N.cfg` (2 nodes, shared store): safety; 3 checks violated. This `-continue` run also stopped early on the TLC exception, at 97,605 distinct states. The full two-node space is larger than 9.7 M distinct states and does not finish in 120 s (`traces/Holds_2N.cfg`).
- `traces/Holds_2N_small.cfg` (2 nodes, valid options only, expected version 3): **passed** over 651,696 distinct states. Two-node runs with invalid options or an expected version of 2 are therefore checked only for the violations listed below, not for "holds".
- `Hosting_Health.cfg`: safety; 1 check violated; 10,056 distinct states.
- liveness `traces/Live.cfg`: violated, stuttering.
- Scenarios SCN-1, SCN-2, SCN-4, SCN-5, SCN-6: reachable (pass). SCN-3 holds.

**Result:** 11 findings — 3 contradictions · 2 gaps · 0 unprovable · 6 ambiguities · 0 modeling notes

Most checks below are named `Chk_…`. These are not requirements: each is the obvious intent of a requirement or scenario, written as a property so that TLC can show where the sentences allow something else. Each one is listed in the assumptions table. The exception is `Inv_NoWorkerInBuildTooling` (REQ-14), which is a requirement. All requirement invariants other than REQ-14 hold: REQ-13, REQ-15, REQ-20, REQ-24, REQ-40, REQ-42 (lock discipline), SCN-2 and SCN-3. They hold over the full one-node space, and for two nodes under the reduced bounds of `traces/Holds_2N_small.cfg`.

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | gap | medium | REQ-27, REQ-18, REQ-25 | A host that stops while Bellhop is still starting gets a running worker that claims jobs |
| F-2 | contradiction | high | REQ-22, REQ-18, REQ-23, REQ-42 | With AutoMigrate on, a node can start running on the older schema without migrating, possibly still holding the migration lock |
| F-3 | contradiction | high | REQ-30, REQ-35 | A stalled node reported Unhealthy turns Healthy again while still stalled |
| F-4 | ambiguity | medium | REQ-12, REQ-9, REQ-22, REQ-23, REQ-42 | Startup step order is unstated: a node that is about to fail migrates or writes to the shared store first |
| F-5 | gap | medium | REQ-29, REQ-28, jobs REQ-140 | A draining node never stops if the store is down when ShutdownTimeout passes |
| F-6 | contradiction | medium | REQ-14, REQ-12, REQ-18 | REQ-14 holds only if build tooling never starts the host, and nothing says so |
| F-7 | ambiguity | low | REQ-16, REQ-53, REQ-54, SCN-1 | "While starting, … log a warning" says neither "once" nor "before running" |
| F-8 | ambiguity | medium | REQ-34, REQ-35 | When recovering from Unhealthy, a node with a backlog reports better (Degraded) than a node without one (Unhealthy) |
| F-9 | ambiguity | medium | REQ-44, REQ-49, REQ-33 | What counts as an "alive node" for MinNodesAlive? |
| F-10 | ambiguity | medium | REQ-9, REQ-23, REQ-43, REQ-51, REQ-52 | "Stop the node from starting": does the host stop, and do the client and dashboard keep working? |
| F-11 | ambiguity | low | Health.initial, REQ-31, REQ-35 | A node reports Healthy before any health check has run |

---

## F-1 · gap · medium — A host that stops while Bellhop is still starting gets a running worker that claims jobs
<!-- finding: gap | Chk_NoClaimAfterHostStop | REQ-27,REQ-18,REQ-25 -->

**Requirements involved**
- REQ-27: *While a node is running, when the host stops, the system shall stop claiming new jobs on that node.*
- REQ-18: *While a node is starting, when the store is reachable, the stored schema version is accepted (REQ-23, REQ-43) and all startup checks have passed, the system shall mark the node running and, where the worker is registered, start the worker and its background duties.*
- REQ-25: *While a node is starting, if the store is unreachable, then the system shall keep retrying the connection with backoff without stopping the host, and claim no job until the store is reachable.*

**What happens** (TLC counter-example, `Chk_NoClaimAfterHostStop`, 5 states, `traces/Chk_NoClaimAfterHostStop.md`)
1. The worker service `worker-1` starts — REQ-12 → Starting. The store is not reachable yet (REQ-25 keeps retrying).
2. The orchestrator stops the pod, so the host signals stop. No requirement covers a host stop while Starting, so the node stays Starting.
3. The store becomes reachable and the checks pass — REQ-18 → **Running; the worker and its background duties start.**
4. The worker claims a job — the host stopped at step 2, so REQ-27's trigger already happened before the node was running, and REQ-27 never fires.

**Why** Node has no transition out of Starting on host stop, and REQ-18 has no "the host has not stopped" condition. REQ-25 makes Starting last as long as a database outage does, so this window is minutes long, not milliseconds. The host's own shutdown timeout will eventually kill the process with the job half-run: the job is recovered by lease expiry (jobs REQ-132) and counts as an attempt.

**Options**
1. *(recommended)* Add a transition: *While a node is starting, when the host stops, stop retrying and mark the node stopped without starting the worker.* This gives Starting a way out and makes REQ-18 unreachable after the stop.
2. Extend REQ-27 to `from: ["Starting", "Running"]` → Draining. This works, but it puts a node that never started any work through draining.
3. Add `"if": "the host has not been asked to stop"` to REQ-18 and REQ-19 only. This blocks the worker, but the node then sits in Starting forever: the gap remains.

**Ready to apply (option 1)**
```json
{ "id": "REQ-55", "kind": "transition", "status": "proposed", "strength": "must",
  "entity": "Node", "actor": "Host", "from": ["Starting"], "to": ["Stopped"],
  "ears": { "while": "a node is starting", "when": "the host stops",
            "shall": "stop retrying the store connection and mark the node stopped without starting the worker or any background duty" },
  "mentions": ["Node.hasWorker", "Store.reachable"], "dependsOn": ["REQ-25", "REQ-27"] }
```

---

## F-2 · contradiction · high — With AutoMigrate on, a node can start running on the older schema without migrating, possibly still holding the migration lock
<!-- finding: contradiction | Chk_MigrateBeforeRunning | REQ-22,REQ-18,REQ-23,REQ-42 -->

**Requirements involved**
- REQ-22: *While a node is starting, if AutoMigrate is on and the stored schema version is older than the expected version, then the system shall apply the embedded migrations up to the expected version and log what it did.*
- REQ-18: *…when the store is reachable, the stored schema version is accepted (REQ-23, REQ-43) and all startup checks have passed, the system shall mark the node running…*
- REQ-23 notes: *a node accepts the schema version it expects or one version older.*
- REQ-42: *…let only the node holding the store's migration lock apply migrations, and have the others wait for the lock and then re-read the schema version.*

**What happens** (TLC counter-example, `Chk_MigrateBeforeRunning`, 3 states, `traces/Chk_MigrateBeforeRunning.md`)
1. The store is on schema 1. `worker-1` runs library version 2 with AutoMigrate on (the default, REQ-21). The host starts it — REQ-12.
2. Schema 1 is "accepted" (it is one version older), so REQ-18 is enabled at the same time as REQ-22. REQ-18 fires: **`worker-1` is Running on schema 1 and no migration ran.** REQ-22 can no longer fire because it only applies while Starting.

The second trace (`traces/Live.md`, states 1–6) is worse. The store is on 2 and the node expects 3. The node takes the migration lock (REQ-42, start of REQ-22), and REQ-18 then fires before the migration runs: **the node is Running and still holds the migration lock** (`Chk_LockHolderStarting`). Another node with AutoMigrate on that needs the migration waits for that lock (REQ-42) for as long as the first node runs.

**Why** "Accepted" (REQ-23/43) was designed for AutoMigrate **off** (rolling deploys). REQ-18 uses it as its only schema condition, so with AutoMigrate on it races REQ-22. No requirement says migration must finish before REQ-18, or that the lock is released when the holder leaves Starting.

**Options**
1. *(recommended)* Add "no migration is pending" to the REQ-18/REQ-19 trigger: with AutoMigrate on, the schema must equal the expected version. REQ-22 then always runs first, and the lock is always released by the migration itself.
2. Define accepted per mode: with AutoMigrate on, accepted means equal to the expected version; with it off, expected or one older. This is the same effect, written in REQ-23's notes plus a new assumption.
3. Keep the race and require that the lock is released when the holder leaves Starting (see F-4, REQ-56). This removes the stuck waiter but still lets a node run unmigrated with AutoMigrate on.

**Ready to apply (option 1)** — REQ-18 and REQ-19 share a trigger, so change both
```json
{ "id": "REQ-18", "ears": { "while": "a node is starting",
    "when": "the store is reachable, the stored schema version is accepted (REQ-23, REQ-43), no migration is pending under REQ-22 and all startup checks have passed",
    "shall": "mark the node running and, where the worker is registered, start the worker and its background duties" },
  "dependsOn": ["REQ-52", "REQ-22"] }
{ "id": "REQ-19", "ears": { "while": "a node is starting",
    "when": "the store is reachable, the stored schema version is accepted (REQ-23, REQ-43), no migration is pending under REQ-22 and all startup checks have passed",
    "shall": "log a one-screen summary with the store and schema version, which of the client, worker and dashboard are registered, queues and concurrency, the registered job count, recurring jobs with their next run, and the dashboard path and auth mode" } }
```

---

## F-3 · contradiction · high — A stalled node reported Unhealthy turns Healthy again while still stalled
<!-- finding: contradiction | Chk_StallStaysUnhealthy | REQ-30,REQ-35 -->

**Requirements involved**
- REQ-30: *If an internal error stalls processing (store error, scheduler error, serialization error or recovery error), then the system shall report the node Unhealthy.*
- REQ-35: *When the health check runs, if every check has passed on the last HealthyAfterPasses runs in a row, then the system shall report the node Healthy.*

**What happens** (TLC counter-example, `Chk_StallStaysUnhealthy`, 6 states, `run_Health.md`; HealthyAfterPasses = 2 in the model, 3 by default)
1. `api-1` starts with the client registered; the store is reachable — REQ-12.
2. The health check runs; every check passes (pass 1).
3. A serialization error stalls processing.
4. REQ-30 → **Unhealthy**.
5. The health check runs. The store is reachable (REQ-31), the schema is accepted (REQ-32), there is no worker loop to check (REQ-33), nodes are alive (REQ-44) and no threshold is exceeded (REQ-34), so every check passes (pass 2). REQ-35 → **Healthy, while processing is still stalled.**

With the default of 3 passes, or if REQ-30 reset the counter, this takes up to three runs instead of one, but the outcome is the same.

**Why** REQ-30 is an event outside the health check ("if an error stalls…"), so its condition is not one of the checks that REQ-35 counts. Nothing keeps the node Unhealthy while the stall lasts.

**Options**
1. *(recommended)* Make the stall a health check: *When the health check runs, if processing is stalled by an internal error…, report the node Unhealthy.* It then joins the REQ-31/32/33/44 event, and REQ-35's "every check has passed" covers it automatically.
2. Add to REQ-35: *"…and processing has not been stalled by an internal error during those runs"*. Same effect, but there are now two places that define "passed".
3. Keep REQ-30 as a momentary signal and downgrade it to `should`, accepting that a persistent stall reads Healthy after HealthyAfterPasses runs.

**Ready to apply (option 1)**
```json
{ "id": "REQ-30", "ears": { "when": "the health check runs",
    "if": "an internal error (store error, scheduler error, serialization error or recovery error) is stalling processing",
    "shall": "report the node Unhealthy" },
  "notes": "Turned into a health check so that REQ-35 cannot report Healthy while the stall lasts (hosting findings F-3)." }
```

---

## F-4 · ambiguity · medium — Startup step order is unstated: a node that is about to fail migrates or writes to the shared store first
<!-- finding: ambiguity | startup-order | REQ-12,REQ-9,REQ-22,REQ-23,REQ-42 -->

**Requirements involved**
- REQ-12: *When the host starts, the system shall start the Bellhop node and only then connect to the store and check the schema, and, where the worker is registered, reconcile code-defined recurring jobs.*
- REQ-9: *While a node is starting, if an option fails validation, then the system shall stop the node from starting…*
- REQ-22 (quoted in F-2) and REQ-42: *…let only the node holding the store's migration lock apply migrations…*

**What happens** (three TLC counter-examples)
- (a) `Chk_NoMigrationWithInvalidOptions` (2 nodes, 4 states, `traces/Chk_NoMigrationWithInvalidOptions_2N.md`): `worker-2` runs library 2 with AutoMigrate on and a negative PollInterval, and the store is on 0. It takes the migration lock (REQ-42) and **migrates the shared store to 2** (REQ-22). Only then does REQ-9 fail it. In a rolling deploy (store on N, a misconfigured N+1 pod), every healthy N node now sees a newer schema and reports Unhealthy (REQ-32), and every N node that restarts fails (REQ-43). One bad pod changes the shared schema without ever running.
- (b) `Chk_ReconcileOnAcceptedSchema` (3 states): `worker-1` has AutoMigrate off and the store is two versions behind. REQ-12 **reconciles recurring definitions into a schema the node is about to reject**, and then REQ-23 fails it.
- (c) `Chk_LockHolderStarting` (2 nodes, 4 states, `traces/Chk_LockHolderStarting_2N.md`): `worker-2` takes the migration lock and then fails REQ-9 **while holding it**. Whether `worker-1` (AutoMigrate on, waiting under REQ-42) ever gets the lock depends on whether the failed process exits (see F-10). The model assumes that exit releases a store-native lock (TECH-126).

**Why** REQ-12 orders "connect → check schema → reconcile", but says nothing about where validation (REQ-9) and migration (REQ-22) sit. It also doesn't say whether "check the schema" means *checked* or *accepted*. REQ-42 doesn't say when the lock is released if the holder fails.

**Options**
1. *(recommended)* Fix the order in REQ-12: validate options → connect → check the schema (failing under REQ-23/43, or migrating under REQ-22) → reconcile only on an accepted, migrated schema. Add REQ-56: the lock is released whenever its holder leaves Starting.
2. Add guards only: REQ-22 `if` "…and the options passed validation"; REQ-12's reconcile "where the schema version is accepted". Then add REQ-56.
3. Keep the order open and record it as acceptable, with a note that a failed node may leave a migrated schema behind. Migrations are additive (TECH-127), so old nodes keep working, but they report Unhealthy.

**Ready to apply (option 1)**
```json
{ "id": "REQ-12", "ears": { "when": "the host starts",
    "shall": "start the Bellhop node, validate the options, and only then connect to the store and check the schema (failing under REQ-23 or REQ-43, or migrating under REQ-22), and, where the worker is registered and the schema version is accepted with no migration pending, reconcile code-defined recurring jobs" },
  "dependsOn": ["REQ-9", "REQ-22", "REQ-23", "REQ-43"] }
{ "id": "REQ-56", "kind": "invariant", "status": "proposed", "strength": "must", "entity": "Store",
  "ears": { "while": "a node holds the store's migration lock", "shall": "keep that node starting; a node that leaves starting for any reason releases the lock first" },
  "mentions": ["Store.schemaVersion"], "dependsOn": ["REQ-42"] }
```

---

## F-5 · gap · medium — A draining node never stops if the store is down when ShutdownTimeout passes
<!-- finding: gap | Chk_DrainEnds | REQ-29,REQ-28 -->

**Requirements involved**
- REQ-28: *The system shall give in-flight jobs ShutdownTimeout to finish after the host stops, 30 seconds by default.*
- REQ-29: *While a node is draining, when every in-flight job has finished, or ShutdownTimeout has passed and the remaining jobs' tokens were cancelled and their leases released, the system shall stop the node.*
- jobs REQ-140: *…release the job's lease and take back the attempt it counted…*

**What happens** (TLC counter-example, `Chk_DrainEnds`, liveness, stuttering, `traces/Live.md`)
1. `worker-1` is Running and claims job j1 — REQ-18.
2. The host stops — REQ-27 → Draining.
3. The database goes down.
4. ShutdownTimeout passes — REQ-28. The j1 handler ignores cancellation.
5. Releasing j1's lease is a store write, and the store is down, so REQ-29's second condition never becomes true. **The node stays Draining.** In practice the host's own shutdown timeout kills the process.

**Why** REQ-29 makes stopping depend on a store write succeeding. REQ-25 decided that a database outage must not take the application down at startup, but there is no matching rule that an outage must not block shutdown. The job itself is safe: if the release never happens, its lease expires and jobs REQ-132 recovers it, but then the attempt is counted.

**Options**
1. *(recommended)* Make the release best-effort in REQ-29: "…ShutdownTimeout has passed, the remaining jobs' tokens were cancelled and a release of their leases was attempted…". Lease expiry (jobs REQ-132) covers the failed release, so the node always stops.
2. Add a second bound ("…or ShutdownTimeout has passed twice") after which the node stops regardless.
3. Keep REQ-29 and document that shutdown during an outage relies on the host's own kill timeout.

**Ready to apply (option 1)**
```json
{ "id": "REQ-29", "ears": { "while": "a node is draining",
    "when": "every in-flight job has finished, or ShutdownTimeout has passed, the remaining jobs' tokens were cancelled and the release of their leases was attempted",
    "shall": "stop the node" },
  "notes": "A release that fails because the store is down is covered by lease expiry (jobs REQ-132); that attempt then counts (hosting findings F-5)." }
```

---

## F-6 · contradiction · medium — REQ-14 holds only if build tooling never starts the host, and nothing says so
<!-- finding: contradiction | Inv_NoWorkerInBuildTooling | REQ-14,REQ-12,REQ-18 -->

**Requirements involved**
- REQ-14: *Where the process runs build-time tooling such as OpenAPI generation or EF Core design-time services, the system shall not start the scheduler or any worker.*
- REQ-12: *When the host starts, the system shall start the Bellhop node…* and REQ-18: *…start the worker and its background duties.*

**What happens** (TLC counter-example, `Inv_NoWorkerInBuildTooling`, 3 states)
1. `dotnet ef` loads the app with the worker registered and the in-memory store. The host starts — REQ-12.
2. REQ-18 → **Running, worker started. REQ-14 is violated.**

**Why** Neither REQ-12 nor REQ-18 has a "not under build tooling" condition, so REQ-14 holds only if build tooling never starts the host. That may be true in practice: the tooling builds the host and stops before it runs. But the requirements don't say it, and the model cannot assume it.

**Options**
1. *(recommended)* Record the fact as an assumption, so that REQ-14 follows from it and the conformance tests check it.
2. Guard REQ-12: `"where": "the process is not running build-time tooling"`. This holds even if a tool does start the host, but needs a way to detect the tooling.
3. Retire REQ-14 as a consequence of option 1 (`info`).

**Ready to apply (option 1)**
```json
{ "id": "REQ-57", "kind": "assumption", "status": "proposed", "strength": "must",
  "ears": { "shall": "assume that build-time tooling (OpenAPI generation, EF Core design-time services) builds the host without starting it" },
  "dependsOn": ["REQ-14"], "notes": "Makes REQ-14 follow from REQ-12 (hosting findings F-6)." }
```

---

## F-7 · ambiguity · low — "While starting, … log a warning" says neither "once" nor "before running"
<!-- finding: ambiguity | Chk_OneMemoryWarning | REQ-16,REQ-53,REQ-54,SCN-1 -->

**Requirements involved**
- REQ-16: *While a node is starting, if no store is configured and the environment is not Development, then the system shall log a warning that the in-memory store is in use.*
- SCN-1 then: *The node is Running on the in-memory store and exactly one warning about it was logged.*

**What happens** (two TLC counter-examples)
- `Chk_OneMemoryWarning` (4 states): HostStarts → warning → **warning again**. Nothing limits it to once.
- `Chk_MemoryWarningBeforeRunning` (3 states): HostStarts → REQ-18 Running → **no warning at all**. REQ-16 only applies while Starting, and nothing makes it happen before REQ-18.

SCN-1 is reachable (it passes), but it is not guaranteed. REQ-53 and REQ-54 have the same sentence shape. (They are log-only, so the model skipped them, but the reading is the same.)

**Options**
1. *(recommended)* Make the warnings event-driven on startup and require them once, before the node runs: `when: "the node starts"`, plus "once, before the node is marked running".
2. Leave the sentences as they are and change SCN-1 to "at least one warning".
3. Move all three into REQ-19's summary, which is logged exactly once, by REQ-18.

**Ready to apply (option 1)** (apply the same `when` and `shall` shape to REQ-53 and REQ-54)
```json
{ "id": "REQ-16", "ears": { "when": "a node starts",
    "if": "no store is configured and the environment is not Development",
    "shall": "log a warning that the in-memory store is in use, once, before the node is marked running" } }
```

---

## F-8 · ambiguity · medium — When recovering from Unhealthy, a node with a backlog reports better (Degraded) than a node without one (Unhealthy)
<!-- finding: ambiguity | health-recovery-order | REQ-34,REQ-35 -->

**Requirements involved**
- REQ-34: *When the health check runs, if no check that reports Unhealthy fails, and scheduling lag exceeds SchedulingLagThreshold, … then the system shall report the node Degraded.* (`from: Healthy, Unhealthy`)
- REQ-35: *When the health check runs, if every check has passed on the last HealthyAfterPasses runs in a row, then the system shall report the node Healthy.*

**What happens** (concrete example from the `HealthCheck` action; the states are reachable in `Hosting_Health.cfg`)
The database is back after an outage, and both nodes are Unhealthy (REQ-31).
- `worker-1` has a backlog over SchedulingLagThreshold. First run: no Unhealthy check fails → REQ-34 → **Degraded**.
- `worker-2` has no backlog. Runs 1 and 2: every check passes, but there are fewer than 3 in a row → **stays Unhealthy**. It becomes Healthy at run 3.

For two health-check intervals, the node in better shape reports the worse status. An orchestrator that takes Unhealthy pods out of readiness drops `worker-2` and keeps `worker-1`.

**Why** REQ-34 lets an Unhealthy node drop straight to Degraded, but there is no "recovering" step for a node that passes everything. The REQ-34 notes show this was meant for "store back, backlog remains", but not for "store back, no backlog".

**Options**
1. *(recommended)* Add a transition: *When the health check runs, while the node is Unhealthy, if no check that reports Unhealthy fails, report the node Degraded.* Then recovery always goes Unhealthy → Degraded → Healthy (after HealthyAfterPasses passes), and REQ-35 only needs `from: ["Degraded"]`.
2. Keep the Unhealthy hold and drop `Unhealthy` from REQ-34's `from`, so backlogged nodes wait too. This is consistent, but slower.
3. Accept the behaviour and say so in REQ-34's notes.

**Ready to apply (option 1)**
```json
{ "id": "REQ-58", "kind": "transition", "status": "proposed", "strength": "must",
  "entity": "Health", "actor": "system", "from": ["Unhealthy"], "to": ["Degraded"],
  "ears": { "when": "the health check runs", "while": "the node is Unhealthy",
            "if": "no check that reports Unhealthy fails", "shall": "report the node Degraded" },
  "dependsOn": ["REQ-34", "REQ-35"] }
{ "id": "REQ-35", "from": ["Degraded"] }
```

---

## F-9 · ambiguity · medium — What counts as an "alive node" for MinNodesAlive?
<!-- finding: ambiguity | nodes-alive | REQ-44,REQ-49 -->

**Requirements involved**
- REQ-44: *When the health check runs, if fewer than MinNodesAlive nodes are alive, then the system shall report the node Unhealthy.*
- REQ-49 notes: *The reporting node is itself alive, so the default never fires.*
- dashboard (the "no worker alive" banner): *While no node with the worker registered has sent a heartbeat within NodeLostAfter…*

**What happens** (concrete example)
`api-1` registers only the client (REQ-52), and `worker-1` is down. Alive nodes could be read two ways:
- Alive = **worker nodes with a recent heartbeat** (the dashboard and jobs modules count it this way). There are 0 alive, 0 < 1, so `api-1` reports **Unhealthy** with the default setting. That contradicts REQ-49's note, and readiness probes take the web API out of rotation because a worker is down. The REQ-25 decision says a database outage must not do exactly that.
- Alive = **any Bellhop process**. Then `api-1` counts itself, the default never fires, and the check can't detect "no worker running".

The model leaves "fewer than MinNodesAlive" as a nondeterministic flag (A-8). It cannot settle this.

**Options**
1. *(recommended)* Define alive as "has the worker registered and sent a heartbeat within NodeLostAfter", the same as the dashboard. Evaluate REQ-44 only where the worker is registered; client-only processes get the dashboard banner instead.
2. Count every process. Fix REQ-49's note, and accept that REQ-44 cannot detect a missing worker.
3. Count workers on every node, and accept that client-only processes go Unhealthy whenever no worker is alive. The docs then advise against mapping Bellhop health to API readiness.

**Ready to apply (option 1)**
```json
{ "id": "REQ-44", "ears": { "where": "the worker is registered", "when": "the health check runs",
    "if": "fewer than MinNodesAlive nodes with the worker registered have sent a heartbeat within NodeLostAfter",
    "shall": "report the node Unhealthy" },
  "mentions": ["Health.nodesAlive", "Node.hasWorker"] }
```

---

## F-10 · ambiguity · medium — "Stop the node from starting": does the host stop, and do the client and dashboard keep working?
<!-- finding: ambiguity | startup-failed-host | REQ-9,REQ-23,REQ-43,REQ-51 -->

**Requirements involved**
- REQ-9 / REQ-23 / REQ-43: *…the system shall stop the node from starting…*
- REQ-43 notes: *a node on N that restarts after an N+1 node migrated fails here; that is acceptable because it is being replaced.*
- REQ-51: *The system shall serve the dashboard on a node exactly when the application maps it…*
- REQ-25 notes: *a database outage must not take the web application down.*

**What happens** (concrete example)
During a rolling deploy, `api-1` (library N; client and dashboard) restarts after `worker-9` (N+1) has migrated the store. REQ-43 → StartupFailed. There are two readings:
- **The host fails to start.** The web API crash-loops until it is replaced, so its HTTP endpoints, not just Bellhop, are down. That is the opposite of the reasoning in REQ-25.
- **The host keeps running without Bellhop.** Does `IJobClient` still enqueue against a schema this node rejected? Is the dashboard still served, as REQ-51's "exactly when mapped" says? And the migration lock from F-4 (c) is only released when the process exits, which with this reading never happens.

The model shows (F-4 c) that StartupFailed can be reached while holding the lock. It cannot choose between the readings.

**Options**
1. *(recommended)* Fail fast: say that StartupFailed fails the host's start (the .NET convention for options validation). Note in REQ-43 that the rolling-deploy case costs a restart of an already-replaced pod.
2. Keep the host up. StartupFailed then disables the client (enqueue throws with the startup message) and the dashboard shows only the failure, and the health check reports Unhealthy. This needs a new invariant for each part, and REQ-51 needs an exception.
3. Keep the host up with the client and dashboard working. Accept writes against a rejected schema (TECH-127 keeps them additive).

**Ready to apply (option 1)** — the same change for REQ-23 and REQ-43
```json
{ "id": "REQ-9", "ears": { "while": "a node is starting", "if": "an option fails validation",
    "shall": "fail the host's start with a message that names the option and the fix" },
  "notes": "StartupFailed fails the host (hosting findings F-10); process exit also releases a held migration lock (TECH-126)." }
```

---

## F-11 · ambiguity · low — A node reports Healthy before any health check has run
<!-- finding: ambiguity | Health.initial | REQ-31,REQ-35 -->

**Requirements involved**
- Entity `Health`: `initial: ["Healthy"]`
- REQ-35: *…if every check has passed on the last HealthyAfterPasses runs in a row, then the system shall report the node Healthy.*

**What happens** (SCN-6 trace, `run_SCN6.md`, state 2)
`worker-1` starts with the database down. Until the first health check runs, the node reports **Healthy**, with 0 passes, the store unreachable and the worker not started. After that first run it is Unhealthy (REQ-31, REQ-33), and it needs HealthyAfterPasses passes to come back. The starting value skips the rule that REQ-35 imposes on every other route to Healthy.

**Options**
1. *(recommended)* Start Unhealthy: `initial: ["Unhealthy"]`. A node becomes Healthy only through REQ-35, so readiness waits HealthyAfterPasses check intervals after startup.
2. Start Degraded, with a recovering meaning (fits F-8 option 1).
3. Keep Healthy and note that the first report is optimistic.

**Ready to apply (option 1)**
```json
{ "name": "Health", "initial": ["Unhealthy"] }
```

---

## Modeling assumptions
Where the sentences were silent, I had to decide. Each decision below shapes the results above; if one is wrong, say so and rerun.
| # | Assumption | Affects |
|---|---|---|
| A-1 | No clocks. ShutdownTimeout passing, backoff, health thresholds and clock skew are nondeterministic events or flags | REQ-25, REQ-28, REQ-29, REQ-34, REQ-46–48 |
| A-2 | "All startup checks have passed" (REQ-18) means none of REQ-9, REQ-23 or REQ-43's conditions holds: options are valid and the schema is accepted | REQ-18, REQ-19, SCN-2 |
| A-3 | A process in a final state exits and may be replaced by a new one, possibly on another library version and with another configuration (modeling artefact `Archive`). Exit frees a store-native migration lock (TECH-126) | all, F-4 c |
| A-4 | REQ-12's reconciliation is ordered after the schema *check*, not after it *passed* or after migration, so the order is left open | REQ-12, F-4 |
| A-5 | The host may signal stop while the node is Starting or Running. In Starting no requirement applies, so the status is unchanged. `Chk_NoRunningAfterHostStop` and `Chk_NoClaimAfterHostStop` come from REQ-27 and SCN-4 | REQ-27, F-1 |
| A-6 | Job claims are abstracted from the jobs module: a claim needs Running, a started worker and a reachable store; 1 in-flight slot (2 in SCN-4). Handlers are not obliged to finish | REQ-20, REQ-25, REQ-27, REQ-29 |
| A-7 | Cancel and release at timeout is jobs REQ-140; releasing a lease is a store write | REQ-29, F-5 |
| A-8 | "Fewer than MinNodesAlive nodes are alive" is a nondeterministic flag; the meaning of "alive" is F-9 | REQ-44, REQ-49 |
| A-9 | `Chk_DrainEnds` treats the host-side shutdown steps as obligations (fair, with the release strongly fair). The store, handlers and the stop signal are not obliged | REQ-28, REQ-29, F-5 |
| A-10 | `Chk_MigrateBeforeRunning`: with AutoMigrate on, a node does not run on a schema older than expected (from REQ-22's "shall apply") | F-2 |
| A-11 | `Chk_StallStaysUnhealthy`: REQ-30's report holds while the stall lasts. REQ-30 does not reset the pass counter | F-3 |
| A-12 | `Chk_NoMigrationWithInvalidOptions` and `Chk_ReconcileOnAcceptedSchema`: a node that will fail startup does not write to the shared store | F-4 |
| A-13 | `Chk_LockHolderStarting`: the migration lock is held only by a node that is still Starting | F-2, F-4 |
| A-14 | SCN-1's "exactly one warning" is read as "at most once" and "before Running" | F-7 |
| A-15 | The health check is one action (lint: same trigger), evaluated in the order Unhealthy checks → Degraded thresholds → count a pass. Where no requirement covers the current status, it stays. HealthyAfterPasses = 2 (3 by default) | REQ-31–35, REQ-44 |
| A-16 | Schema versions are small integers (0–3). Accepted = expected or expected − 1. The in-memory store has the expected schema and is always reachable | REQ-15, REQ-23, REQ-43 |
| A-17 | Registrations are none / client / worker (worker includes client). The dashboard is not modeled | REQ-52, REQ-51 |
| A-18 | Bounds: 1 node for startup, shutdown and health; 2 nodes for the shared store and migration lock | all |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-9, REQ-12, REQ-13, REQ-14, REQ-15, REQ-16, REQ-18, REQ-19, REQ-20, REQ-21, REQ-22, REQ-23, REQ-24, REQ-25, REQ-27, REQ-28, REQ-29, REQ-30, REQ-31, REQ-32, REQ-33, REQ-34, REQ-35, REQ-40, REQ-42, REQ-43, REQ-44, REQ-46…REQ-50 (absorbed into nondeterministic flags), REQ-52, SCN-1…SCN-6 | REQ-1–8, REQ-36–39 (info) · REQ-11, REQ-41 (retired) · REQ-10 (needs lease timing, jobs REQ-102) · REQ-17, REQ-51 (static rules, a model can only restate them) · REQ-26, REQ-45, REQ-53, REQ-54 (log-only, nothing reads the state) |

Lint warnings: REQ-18 and REQ-19 are modeled as one action (`MarkRunning`); REQ-31–35 and REQ-44 as one action (`HealthCheck`). Both are as intended; F-3 proposes moving REQ-30 into the second group.

Files: `model/hosting/Hosting.tla`, `Hosting.cfg` (main), `Hosting_2N.cfg`, `Hosting_Health.cfg`, `Hosting_SCN{1,2,4,5,6}.cfg`, `run*.json/md`; a minimal trace for each violated check is in `model/hosting/traces/` (run with `--config traces/<name>.cfg` from `model/hosting`). Receipt: `hosting.modeled.json`.

## Next
Apply the chosen options to `hosting.json` with the `refiner-requirements` skill (it validates and diffs), then run this skill again. Findings whose fingerprint disappears are listed as resolved in the next report.
