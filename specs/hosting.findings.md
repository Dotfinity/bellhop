# Findings: Bellhop hosting, configuration, startup, health and shutdown

<!-- refiner-findings v1 | module: hosting | specHash: 8159591701b2c3c6df7a0962279a88be27a8c81974ce75704522403d07f14f82 | run: 2026-11-06 (second run) | previous: model/hosting/previous.findings.md (git: specs/hosting.findings.md at 0f06870..d16eb21) -->

**Run:** 2026-11-06, second run · **Requirements file:** `specs/hosting.json` (specHash `8159591701b2`) · **Model:** `specs/model/hosting/Hosting.tla`, updated from `model/hosting/handoff.json` (19 modified, 6 added)
**TLC:** every check ran on its own with `--stop-at-first` (`model/hosting/run_checks.py`). No run threw a TLC exception, and every "holds" below is a completed run.

| Config | Bounds | Result | Distinct states |
|---|---|---|---|
| `Hosting.cfg` | 1 node, every configuration | 22 checks and the deadlock run hold. `Chk_ReconciledBeforeRunning` and `Chk_NoStoreWriteBeforeOtherChecks` are violated (F-2, F-1) | 54,440 |
| `Hosting_Health.cfg` | 1 node, stalls, thresholds and node-count changes | `Chk_StallStaysUnhealthy`, `Prop_NoUnhealthyToHealthy` and the deadlock run hold | 4,256 |
| `Hosting_2N.cfg` | 2 nodes, shared store, invalid options possible, other modules' checks pass or fail | 8 checks hold, including REQ-56 and the REQ-42 lock properties | 758,838 |
| `traces/Holds_2N_small.cfg` | 2 nodes, valid options, expected version 3 | 6 checks hold; `Chk_ReconciledBeforeRunning` violated (F-2) | 78,286 |
| `Hosting_2N_fail.cfg` | 2 nodes, AutoMigrate on, expected version 3 | 3 checks hold; `Chk_NoStoreWriteBeforeOtherChecks` violated (F-1) | 32,212 |
| `Hosting_SCN{1,2,4,5,6}.cfg` | scenario | every trap was reached, so all five scenarios pass | 6–75 |

The full two-node space now finishes: 758,838 states, against more than 9.7 M in the first run. Validation now comes before any store work, which removes most interleavings.

**Result:** 3 findings: 0 contradictions · 0 gaps · 0 unprovable · 3 ambiguities · 0 modeling notes. 10 of the 11 previous findings are resolved and 1 is still open in a narrower form.

## Changes since last run
| Finding | Status |
|---|---|
| F-1 | still open (narrowed). Option validation now comes first, but the other modules' startup checks are still unordered |
| F-2 | new |
| F-3 | new |
| previous F-1 (gap \| Chk_NoClaimAfterHostStop) | resolved. REQ-55: `Chk_NoClaimAfterHostStop` and `Chk_NoRunningAfterHostStop` hold over 54,440 states |
| previous F-2 (contradiction \| Chk_MigrateBeforeRunning) | resolved. REQ-18 now requires no migration pending: holds for 1 node (54,440) and 2 nodes (758,838) |
| previous F-3 (contradiction \| Chk_StallStaysUnhealthy) | resolved. REQ-30 is now a health check: holds in `Hosting_Health.cfg` (4,256) |
| previous F-5 (gap \| Chk_DrainEnds) | resolved. REQ-29 makes the release best-effort: `Chk_DrainEnds` holds (54,440) |
| previous F-6 (contradiction \| Inv_NoWorkerInBuildTooling) | resolved. Assumption REQ-57: `Inv_NoWorkerInBuildTooling` holds (54,440) |
| previous F-7 (ambiguity \| Chk_OneMemoryWarning) | resolved. REQ-16 logs once, when the node starts: `Chk_OneMemoryWarning` and `Chk_MemoryWarningBeforeRunning` hold |
| previous F-8 (ambiguity \| health-recovery-order) | resolved. REQ-58: `Prop_NoUnhealthyToHealthy` holds (54,440 and 4,256) |
| previous F-9 (ambiguity \| nodes-alive) | resolved by the text. REQ-44 now says "nodes with the worker registered … within NodeLostAfter", evaluated only where the worker is registered |
| previous F-10 (ambiguity \| startup-failed-host) | resolved for hosting. REQ-9, REQ-23 and REQ-43 now "fail the host's start". The six transitions in other modules are F-3 |
| previous F-11 (ambiguity \| Health.initial) | resolved. Health starts Unhealthy (SCN-6 is reached in 6 states with the node already Unhealthy). The readiness delay is already an open question for the owner |

`findings_delta.py previous.findings.md hosting.findings.md`: 1 still open, 2 new, 10 resolved.

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | ambiguity | medium | REQ-12, REQ-9, REQ-22, REQ-23, REQ-42 (+ dashboard REQ-301/334, recurring REQ-203/210/236, redis REQ-502/505) | A node that will fail another module's startup check can still migrate the shared schema or store recurring definitions first |
| F-2 | ambiguity | medium | REQ-12, REQ-18, REQ-19, recurring REQ-203, REQ-204 | REQ-18 does not wait for REQ-12's reconciliation, so a worker node can run without its code-defined recurring jobs |
| F-3 | ambiguity | low | recurring REQ-210, REQ-236 · dashboard REQ-301, REQ-334 · redis REQ-502, REQ-505 | Six StartupFailed transitions in other modules still say "stop the node from starting", the wording F-10 resolved for hosting |

---

## F-1 · ambiguity · medium — A node that will fail another module's startup check can still migrate the shared schema or store recurring definitions first
<!-- finding: ambiguity | startup-order | REQ-12,REQ-9,REQ-22,REQ-23,REQ-42 -->

Still open from the previous run, in a narrower form. Option validation now comes first: `Chk_NoMigrationWithInvalidOptions` holds over the full two-node space (758,838 states). The other startup checks have no place in the order.

**Requirements involved**
- REQ-12: *When the host starts, the system shall start the Bellhop node, validate the options, and only then connect to the store and check the schema (failing under REQ-23 or REQ-43, or migrating under REQ-22), and, where the worker is registered and the schema version is accepted with no migration pending, reconcile code-defined recurring jobs.*
- REQ-18: *… when the store is reachable, … and all startup checks have passed, including option validation (REQ-9) and the dashboard checks (dashboard REQ-301, REQ-334) …*
- dashboard REQ-301: *While a node is starting, if the dashboard is mapped without RequireAuthorization, … and the environment is not Development, the system shall stop the node from starting …*
- recurring REQ-203: *When a node with the worker registered starts and a code-defined recurring job has no stored definition with its name, the system shall create the definition with its schedule … and nextRunAt computed from now.*
- recurring REQ-210: *While a node is starting, if a code-defined or configuration-defined recurring job has an invalid schedule expression, … the system shall stop the node from starting …*

**What happens** (TLC counter-examples)
- (a) `Chk_NoStoreWriteBeforeOtherChecks`, two nodes, 5 states (`Hosting_2N_fail.cfg`). `worker-2` runs library 3 with AutoMigrate on and valid options, but its dashboard is mapped without authorization in Production. The store is on schema 0.
  1. `worker-2` starts (REQ-12) and its options pass validation (REQ-12, REQ-9).
  2. It takes the migration lock (REQ-42) and **migrates the shared store from 0 to 3** (REQ-22).
  3. Only now does dashboard REQ-301 fail it: StartupFailed.
- (b) `Chk_NoStoreWriteBeforeOtherChecks`, one node, 4 states (`Hosting.cfg`). `worker-1` declares a code-defined recurring job with an invalid cron expression.
  1. It starts and its options pass validation.
  2. It reconciles code-defined recurring jobs (REQ-12, recurring REQ-203): **a definition whose schedule REQ-210 rejects is written to the shared store**, with a nextRunAt computed from a schedule that cannot be parsed.
  3. Recurring REQ-210 then fails the node. The stored definition stays behind for every other worker's scheduler.

**Why** REQ-12 now orders option validation before any store work, but the startup checks owned by other modules have no place in that order. They are dashboard REQ-301 and REQ-334 (no store needed), recurring REQ-210 (no store needed) and REQ-236 (needs the store), and redis REQ-502 and REQ-505 (need the connection). REQ-18 counts them as "all startup checks", so they must pass before the node runs, but nothing says they come before the node writes to the shared store.

**Options**
1. *(recommended)* Extend REQ-12's order. Run every startup check that needs no store together with option validation. After connecting, run the checks that need the store before migrating or reconciling. A failing node then never writes to the shared store.
2. Add one hosting invariant instead: *the system shall never migrate the store or write recurring definitions on a node for which any startup check fails*. Equivalent in effect, but it leaves "when" implicit, and the checks that need the store still have to happen before the writes.
3. Accept the migration case (migrations are additive, TECH-127) and fix only the recurring case: guard recurring REQ-203 and REQ-204 with *"if the definition's schedule and time zone are valid"*. A partial fix: the dashboard-check case still migrates.

**Ready to apply (option 1)**
```json
{ "id": "REQ-12", "ears": { "when": "the host starts",
    "shall": "start the Bellhop node, validate the options and run every startup check that needs no store (dashboard REQ-301 and REQ-334, recurring REQ-210), and only then connect to the store, run the startup checks that need it (REQ-23, REQ-43, redis REQ-502 and REQ-505, recurring REQ-236), migrate under REQ-22, and, where the worker is registered and the schema version is accepted with no migration pending, reconcile code-defined recurring jobs" },
  "notes": "refiner-model 2026-11-06 second run F-1: a node that will fail any startup check never writes to the shared store." }
```

---

## F-2 · ambiguity · medium — REQ-18 does not wait for REQ-12's reconciliation, so a worker node can run without its code-defined recurring jobs
<!-- finding: ambiguity | Chk_ReconciledBeforeRunning | REQ-12,REQ-18,REQ-19,recurring:REQ-203,recurring:REQ-204 -->

**Requirements involved**
- REQ-12 (quoted in F-1): *… where the worker is registered and the schema version is accepted with no migration pending, reconcile code-defined recurring jobs.*
- REQ-18: *While a node is starting, when the store is reachable, the stored schema version is accepted (REQ-23, REQ-43), no migration is pending under REQ-22 and all startup checks have passed, including option validation (REQ-9) and the dashboard checks …, the system shall mark the node running and, where the worker is registered, start the worker and its background duties.*
- recurring REQ-203 and REQ-204: *When a node with the worker registered starts and …, the system shall create / update the definition …*

**What happens** (TLC counter-example, `Chk_ReconciledBeforeRunning`, 4 states, `Hosting.cfg`; also 2 nodes in `traces/Holds_2N_small.cfg`)
1. `worker-1` (worker registered, store reachable, schema on the expected version) starts (REQ-12).
2. Its options pass validation (REQ-12).
3. REQ-18 fires: every condition in its `when` holds. **The node is Running and its worker and scheduler are started, but REQ-12's reconciliation has not run.**
4. Recurring REQ-203 and REQ-204 fire "when a node … starts", and the node is no longer starting. A new code-defined job is never created on this node, and a changed definition keeps its old schedule until the next restart. On SQL stores no other mechanism re-runs reconciliation; Redis has REQ-510's periodic pass.

**Why** REQ-12 lists reconciliation as a step of the start, but REQ-18's trigger lists what it waits for, and reconciliation is not in it. "All startup checks" reads as checks that can fail the start, not as work to finish.

**Options**
1. *(recommended)* Add reconciliation to REQ-18 and REQ-19's shared trigger: *"… and, where the worker is registered, code-defined recurring jobs have been reconciled (REQ-12)"*. The scheduler then always starts on reconciled definitions.
2. Make reconciliation the scheduler's first duty after the node is running: recurring REQ-203 and REQ-204 *"when the scheduler of a node with the worker registered starts"*. The node becomes ready a little earlier, but the scheduler must not trigger before reconciling, which needs its own sentence.
3. Leave it, and note in REQ-12 that reconciliation happens before REQ-18 by construction. This is unverifiable: nothing in the sentences enforces it.

**Ready to apply (option 1)** (REQ-18 and REQ-19 share the trigger; keep them identical)
```json
[
  { "id": "REQ-18", "ears": { "while": "a node is starting",
      "when": "the store is reachable, the stored schema version is accepted (REQ-23, REQ-43), no migration is pending under REQ-22, all startup checks have passed, including option validation (REQ-9) and the dashboard checks (dashboard REQ-301, REQ-334), and, where the worker is registered, code-defined recurring jobs have been reconciled (REQ-12)",
      "shall": "mark the node running and, where the worker is registered, start the worker and its background duties" } },
  { "id": "REQ-19", "ears": { "while": "a node is starting",
      "when": "the store is reachable, the stored schema version is accepted (REQ-23, REQ-43), no migration is pending under REQ-22, all startup checks have passed, including option validation (REQ-9) and the dashboard checks (dashboard REQ-301, REQ-334), and, where the worker is registered, code-defined recurring jobs have been reconciled (REQ-12)",
      "shall": "log a one-screen summary with the store and schema version, which of the client, worker, alerts and dashboard are registered, queues and concurrency, the registered job count, recurring jobs with their next run, and the dashboard path and auth mode" } }
]
```

---

## F-3 · ambiguity · low — Six StartupFailed transitions in other modules still say "stop the node from starting", the wording F-10 resolved for hosting
<!-- finding: ambiguity | StartupFailed-wording | recurring:REQ-210,recurring:REQ-236,dashboard:REQ-301,dashboard:REQ-334,redis:REQ-502,redis:REQ-505 -->

Not modeled; this is a static example, with each transition abstracted as `OtherCheckFails` (A-19).

**Requirements involved**
- hosting REQ-9, REQ-23 and REQ-43 now say *"… the system shall fail the host's start with a message …"* (owner's decision on the previous F-10).
- recurring REQ-210 and REQ-236, dashboard REQ-301 and REQ-334, and redis REQ-502 and REQ-505 all move `hosting.Node` from Starting to StartupFailed with *"… the system shall stop the node from starting with a message …"*.

**Example** A Redis server's maxmemory-policy is `allkeys-lru` (redis REQ-505), or a production dashboard has no authorization (dashboard REQ-301). Hosting's rule says a startup failure fails the host's start. These sentences only say the node does not start, which is the reading the previous F-10 found ambiguous: the host and its HTTP endpoints could stay up with Bellhop disabled. An implementer reading the redis or dashboard module alone cannot tell which applies.

**Options**
1. *(recommended)* Use hosting's wording in all six: *"fail the host's start with a message …"*. Each module is edited, with no change in meaning given the F-10 decision.
2. Leave the six sentences and add a hosting invariant: *"Whenever a node enters StartupFailed, for any reason, the system shall fail the host's start."* One rule, but it lives far from the six sentences that trigger it.

**Ready to apply (option 1)** (`shall` only; the rest of each item is unchanged)
```json
[
  { "id": "recurring:REQ-210", "ears": { "shall": "fail the host's start with a message that names the job and the problem" } },
  { "id": "recurring:REQ-236", "ears": { "shall": "fail the host's start with a message that names the job and says it is already defined at runtime" } },
  { "id": "dashboard:REQ-301", "ears": { "shall": "fail the host's start with a message that says how to add authorization or opt in to anonymous access" } },
  { "id": "dashboard:REQ-334", "ears": { "shall": "fail the host's start with a message that names the user and shows how to produce the hash" } },
  { "id": "redis:REQ-502", "ears": { "shall": "fail the host's start with a message that names the server flag that enables scripting" } },
  { "id": "redis:REQ-505", "ears": { "shall": "fail the host's start with a message that eviction can silently delete job data …" } }
]
```
(The `module:` prefix only shows which file each item lives in. The redis REQ-505 message is shortened here; keep the module's full text.)

---

## Modeling assumptions
Decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. Changes since the first run are marked.
| # | Assumption | Affects |
|---|---|---|
| A-1 | No clocks. ShutdownTimeout passing, backoff, health thresholds, clock skew and NodeLostAfter are nondeterministic events or flags | REQ-25, REQ-28, REQ-29, REQ-34, REQ-46–48, REQ-60 |
| A-2 | *(changed)* "All startup checks have passed" (REQ-18) means: options validated (REQ-9), schema accepted (REQ-23/43), no migration pending (REQ-22), and every other module's startup check passes (A-19) | REQ-18, REQ-19, SCN-2 |
| A-3 | A process in a final state exits and may be replaced by a new one, possibly on another library version and with another configuration (modeling artefact `Archive`). Exit frees a store-native migration lock (TECH-126) | all |
| A-4 | *(retired)* REQ-12 now orders reconciliation after an accepted schema with no migration pending | — |
| A-5 | *(changed)* The host may signal stop while the node is Starting (REQ-55 → Stopped) or Running (REQ-27 → Draining) | REQ-27, REQ-55 |
| A-6 | Job claims are abstracted from the jobs module: a claim needs Running, a started worker and a reachable store; 1 in-flight slot (2 in SCN-4). Handlers are not obliged to finish | REQ-20, REQ-25, REQ-27, REQ-29 |
| A-7 | *(changed)* Cancel and release at timeout is jobs REQ-140. The release is attempted whatever the store's state; it only lands if the store is reachable, and a failed release is left to lease expiry (jobs REQ-132, outside the model) | REQ-29 |
| A-8 | "Fewer than MinNodesAlive worker nodes have a heartbeat within NodeLostAfter" is a nondeterministic flag, evaluated only on worker nodes | REQ-44, REQ-49, REQ-60 |
| A-9 | `Chk_DrainEnds` treats the host-side shutdown steps as obligations (weakly fair). The store, handlers and the stop signal are not obliged | REQ-28, REQ-29 |
| A-10…A-13 | The derived checks from the first run are unchanged. `Chk_LockHolderStarting` is now the requirement invariant `Inv_LockHolderStarting` (REQ-56) | — |
| A-14 | *(changed)* REQ-16's "once, before the node is marked running" is read as one warning logged as part of the node's start event | REQ-16, SCN-1 |
| A-15 | *(changed)* The health check is one action (lint: same trigger), evaluated in the order: Unhealthy checks (REQ-30–33, REQ-44), then REQ-58 from Unhealthy, then REQ-34 from Healthy, then counting a pass (REQ-35 from Degraded). A run in which every check passes counts as a pass, including the REQ-58 run. Under that reading a node is Healthy after HealthyAfterPasses runs from the first clean check; if the REQ-58 run should not count, it is one run later | REQ-30–35, REQ-44, REQ-58 |
| A-16 | Schema versions are small integers (0–3). Accepted = expected or expected − 1. The in-memory store has the expected schema and is always reachable | REQ-15, REQ-23, REQ-43 |
| A-17 | *(changed)* Registrations are none / client / worker (worker includes client), combined with the alerts registration. The dashboard itself is not modeled; its startup checks are part of A-19 | REQ-52, REQ-51 |
| A-18 | *(changed)* Bounds: 1 node for startup, shutdown and health; 2 nodes for the shared store and migration lock, with the full space now checked (758,838 states) | all |
| A-19 | *(new)* The other modules' startup checks (dashboard REQ-301/334, recurring REQ-210/236, redis REQ-502/505) are one per-process flag `ok`. When it is false, a starting node may go to StartupFailed at any moment, since no requirement orders these checks | REQ-18, F-1, F-3 |
| A-20 | *(new)* A node with the alerts registration starts its notification checks when it is marked running (integrations INV-411/REQ-438), and stops them when it stops. REQ-59 therefore holds by construction | REQ-59 |
| A-21 | *(new)* `Chk_ReconciledBeforeRunning`: a worker node does not run before REQ-12's reconciliation (every worker node is assumed to declare code-defined recurring jobs) | F-2 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-9, REQ-12–16, REQ-18–25, REQ-27–35, REQ-40, REQ-42–44, REQ-46…REQ-50 (absorbed into nondeterministic flags), REQ-52, REQ-55–60 (REQ-57 as a guard on HostStarts; REQ-60 absorbed, A-8), SCN-1…SCN-6 | REQ-1–8, REQ-36–39 (info) · REQ-11, REQ-41 (retired) · REQ-10 (needs lease timing, jobs REQ-102) · REQ-17, REQ-51 (static rules, a model can only restate them) · REQ-26, REQ-45 (log-only, nothing reads the state) · REQ-53, REQ-54 (log-only, the same "a node starts" event as REQ-16, which is modeled) |

Lint warnings, all one event each, modeled as one action: REQ-16/53/54 (`HostStarts`), REQ-18/19 (`MarkRunning`), REQ-27/55 (`HostStops`), REQ-30–35/44/58 (`HealthCheck`).

**Reproduce** from `specs/model/hosting`: `python run_checks.py`, or `python run_checks.py <name-substring>` for some checks. It writes one cfg per check to `checks/` and runs `run_tlc.py Hosting.tla --config checks/<name>.cfg --stop-at-first --workers 2`. Receipt: `hosting.modeled.json` (45 items up to date, 7 skipped).

## Next
Decide F-1 and F-2 together: both are about REQ-12's order, and their snippets touch REQ-12, REQ-18 and REQ-19. F-3 edits three other modules. Apply them with `refiner-requirements`, then run `refiner-model` again.
