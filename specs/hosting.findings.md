# Findings: Bellhop hosting, configuration, startup, health and shutdown

<!-- refiner-findings v1 | module: hosting | specHash: 9cb2ea34d3cbc61533a6cd58982324c3035947bb82b28668ef057f7fb20dd591 | run: 2026-11-06 (third run) | previous: model/hosting/previous.findings.md (git: specs/hosting.findings.md at 9504174) -->

**Run:** 2026-11-06, third run · **Requirements file:** `specs/hosting.json` (specHash `9cb2ea34d3cb`) · **Model:** `specs/model/hosting/Hosting.tla`, updated from `model/hosting/handoff.json` (3 modified: REQ-12, REQ-18, REQ-19; impacted: SCN-1, SCN-2, SCN-3, SCN-5, SCN-6)
**TLC:** every check ran on its own with `--stop-at-first --workers 2` (`model/hosting/run_checks.py`). No run threw a TLC exception, and every "holds" below is a completed run. One run timed out (see `Hosting.cfg` row).

| Config | Bounds | Result | Distinct states |
|---|---|---|---|
| `Hosting.cfg` | 1 node, every configuration | 21 checks and the deadlock run hold. `Chk_StoreChecksOnAcceptedSchema` is violated (F-1). `Chk_DrainEnds` timed out at 160 s here, so it was rerun on `Hosting_Live.cfg` | 85,728 |
| `Hosting_Live.cfg` | *(new)* `Hosting.cfg` with every other module's startup check passing (a node that fails one never drains) | `Chk_DrainEnds` holds | 42,720 |
| `Hosting_Health.cfg` | 1 node, stalls, thresholds and node-count changes | `Chk_StallStaysUnhealthy`, `Prop_NoUnhealthyToHealthy` and the deadlock run hold | 3,512 |
| `Hosting_2N.cfg` | 2 nodes, shared store, invalid options possible, other modules' checks pass or fail in either group | 10 checks and the deadlock run (new) hold, including `Chk_NoStoreWriteBeforeOtherChecks` and `Chk_ReconciledBeforeRunning` | 881,138 |
| `traces/Holds_2N_small.cfg` | 2 nodes, valid options, expected version 3 | 7 checks hold, including `Chk_ReconciledBeforeRunning` | 57,042 |
| `Hosting_2N_fail.cfg` | 2 nodes, AutoMigrate on, expected version 3 | 5 checks hold, including `Chk_NoStoreWriteBeforeOtherChecks` | 49,728 |
| `Hosting_SCN{1,2,4,5,6}.cfg` | scenario | every trap was reached, so all five scenarios pass | 8–116 |

**Result:** 2 findings: 0 contradictions · 0 gaps · 0 unprovable · 2 ambiguities · 0 modeling notes. All 3 previous findings are resolved. Both new findings come from the order that the new REQ-12 sentence sets.

## Changes since last run
| Finding | Status |
|---|---|
| F-1 | new. REQ-12's new order runs the startup checks that read the store before the migration, so recurring REQ-236 reads a schema the node may not be able to read |
| F-2 | new. REQ-12 places redis REQ-502 and REQ-505 after the schema check, but the redis module checks them while connecting |
| previous F-1 (ambiguity \| startup-order) | resolved. REQ-12 now orders every other module's startup check before any store write: `Chk_NoStoreWriteBeforeOtherChecks` holds for 1 node (`Hosting.cfg`, 85,728), 2 nodes with failing checks (`Hosting_2N_fail.cfg`, 49,728) and the full two-node space (`Hosting_2N.cfg`, 881,138). The run-2 counter-examples (migrating before dashboard REQ-301 fails; storing an invalid recurring schedule before REQ-210 fails) are no longer reachable |
| previous F-2 (ambiguity \| Chk_ReconciledBeforeRunning) | resolved. REQ-18 and REQ-19 now wait for reconciliation: `Chk_ReconciledBeforeRunning` holds for 1 node (85,728), `traces/Holds_2N_small.cfg` (57,042), `Hosting_2N_fail.cfg` (49,728) and `Hosting_2N.cfg` (881,138) |
| previous F-3 (ambiguity \| StartupFailed-wording) | resolved by the text. Recurring REQ-210 and REQ-236, dashboard REQ-301 and REQ-334, and redis REQ-502 and REQ-505 all now say "fail the host's start" (checked in each module's JSON; not a TLC result) |

`findings_delta.py previous.findings.md hosting.findings.md`:

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | ambiguity · startup-order · REQ-12,REQ-22,REQ-23,REQ-42,REQ-9 |
| F-2 | resolved | ambiguity · Chk_ReconciledBeforeRunning · REQ-12,REQ-18,REQ-19,recurring:REQ-203,recurring:REQ-204 |
| F-3 | resolved | ambiguity · StartupFailed-wording · dashboard:REQ-301,dashboard:REQ-334,recurring:REQ-210,recurring:REQ-236,redis:REQ-502,redis:REQ-505 |
| F-1 | new | ambiguity · Chk_StoreChecksOnAcceptedSchema · REQ-12,REQ-22,recurring:REQ-236 |
| F-2 | new | ambiguity · redis-check-order · REQ-12,redis:REQ-500,redis:REQ-502,redis:REQ-505 |

3 resolved, 2 new, 0 still open

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | ambiguity | medium | REQ-12, REQ-22, REQ-23, REQ-32, recurring REQ-236 | REQ-236 runs before the migration, so on a new database it reads recurring jobs from tables that do not exist yet |
| F-2 | ambiguity | low | REQ-12, REQ-25, redis REQ-500, REQ-502, REQ-505 (TECH-69) | REQ-12 runs the Redis EVAL and eviction checks after the schema check; the redis module runs them while connecting |

---

## F-1 · ambiguity · medium — REQ-236 runs before the migration, so on a new database it reads recurring jobs from tables that do not exist yet
<!-- finding: ambiguity | Chk_StoreChecksOnAcceptedSchema | REQ-12,REQ-22,recurring:REQ-236 -->

**Requirements involved**
- REQ-12: *When the host starts, the system shall start the Bellhop node, validate the options and run the startup checks that need no store (dashboard REQ-301 and REQ-334, recurring REQ-210), then connect to the store, check the schema (failing under REQ-23 or REQ-43) and run the startup checks that need the store (redis REQ-502 and REQ-505, recurring REQ-236), and only then migrate under REQ-22 and, …, reconcile code-defined recurring jobs.*
- REQ-22: *While a node is starting, if AutoMigrate is on and the stored schema version is older than the expected version, the system shall apply the embedded migrations up to the expected version …*
- REQ-23 and REQ-32: a node accepts only its expected schema version or the one before it.
- recurring REQ-236: *While a node is starting, if a code-defined or configuration-defined recurring job has the name of a stored runtime-defined recurring job, the system shall fail the host's start …*

**What happens** (TLC counter-example, `Chk_StoreChecksOnAcceptedSchema`, 5 states, `Hosting.cfg`; trace in `model/hosting/checks/main_Chk_StoreChecksOnAcceptedSchema.md`)
`orders-1` starts on a new PostgreSQL database (schema version 0, no Bellhop tables). Its library expects schema 2 and AutoMigrate is on, which is the default (REQ-21).
1. The host starts the node (REQ-12).
2. The options pass validation, and the dashboard and recurring REQ-210 checks pass (REQ-12).
3. The node connects. The schema check does not fail, because AutoMigrate is on and the schema is not newer (REQ-23, REQ-43).
4. **The startup checks that need the store run now, before the migration** (REQ-12). Recurring REQ-236 must read the stored runtime-defined recurring jobs from schema 0. The database has no recurring table yet.
5. Only after that may the node migrate to 2 (REQ-22).

TLC's shortest trace uses a node without the worker. The guard does not depend on the registration, so a worker node takes the same steps. The same happens whenever AutoMigrate is on and the store is two or more versions behind: REQ-236 reads a schema this library version does not accept (REQ-23, REQ-32), so nothing says it can read it.

**Why** The run-2 F-1 decision was that a node which will fail a startup check never writes to the shared store. REQ-12 therefore puts every check before the migration. REQ-236 is the one check that reads Bellhop's own data, and before the migration that data may be missing or in an older layout. The sentences do not say what REQ-236 finds then. A literal implementation fails the first start of every new database with a "relation does not exist" error instead of migrating it. Another reasonable implementation treats a missing table as "no runtime jobs". Both readings fit the text.

**Options**
1. *(recommended)* Keep the order and say what REQ-236 reads before the migration. A store with no Bellhop schema yet has no runtime-defined jobs. On an older schema, the check reads only each stored job's name and origin, which every schema version stores. The run-2 decision stands: no write happens before a failing check. This relies on name and origin existing in every schema version since the first one. TECH-127 (additive migrations) keeps existing columns, so that only has to be true of schema 1.
2. Move REQ-236 after the migration and before reconciliation: *"… and only then migrate under REQ-22, run recurring REQ-236 and, where the worker is registered …, reconcile"*. The check always reads a schema the node knows. The cost is that it partly reverses the run-2 decision: a node that fails REQ-236 may have migrated the shared schema first, so the older nodes then report Unhealthy (REQ-32).
3. Split the case: run REQ-236 before the migration when the stored schema is accepted, and after it otherwise. This is precise, but it gives the hardest sentence to implement and test, and the new-database case still migrates before the check.

**Ready to apply (option 1)** (REQ-12 `shall` only; the rest of the item is unchanged)
```json
{ "id": "REQ-12", "ears": { "when": "the host starts",
    "shall": "start the Bellhop node, validate the options and run the startup checks that need no store (dashboard REQ-301 and REQ-334, recurring REQ-210), then connect to the store, check the schema (failing under REQ-23 or REQ-43) and run the startup checks that need the store (redis REQ-502 and REQ-505, recurring REQ-236, which reads stored recurring jobs by name and origin only and finds none in a store that has no Bellhop schema yet), and only then migrate under REQ-22 and, where the worker is registered and the schema version is accepted with no migration pending, reconcile code-defined recurring jobs" },
  "notes": "refiner-model 2026-11-06 run 3 F-1: REQ-236 runs before the migration (run 2 F-1), so it must work on an unmigrated store; name and origin are stored by every schema version (TECH-127)." }
```

---

## F-2 · ambiguity · low — REQ-12 runs the Redis EVAL and eviction checks after the schema check; the redis module runs them while connecting
<!-- finding: ambiguity | redis-check-order | REQ-12,redis:REQ-500,redis:REQ-502,redis:REQ-505 -->

Not modeled. This is a static example: the hosting model has no Redis store, and the redis checks are part of the abstract "needs the store" group (A-19).

**Requirements involved**
- REQ-12 (quoted in F-1): *… then connect to the store, check the schema (failing under REQ-23 or REQ-43) and run the startup checks that need the store (redis REQ-502 and REQ-505, …) …*
- redis REQ-500: *While the store is connecting, when the connection is established and a trivial EVAL script succeeds, the system shall identify the server family …, mark the store ready …* No transition leaves Connecting when EVAL fails.
- redis REQ-502: *While a node using the Redis store is starting, if the server does not support EVAL, the system shall fail the host's start …*
- TECH-69: *The Redis store shall … probe EVAL with a trivial script on connect, repeating detection and the maxmemory-policy check on every reconnection …*
- REQ-25: *While a node is starting, if the store is unreachable, the system shall keep retrying the connection with backoff …*

**Example** A node uses Garnet started without `--lua`, and the store's schema marker is one version newer than the library's.
- Reading A (REQ-12's literal order): connect, then check the schema, so the host's start fails with REQ-43's "library older than the schema" message. REQ-502 is never reached.
- Reading B (redis REQ-500 and TECH-69): the EVAL probe is part of connecting, so REQ-502 fails the start first, with the `--lua` message.
- Reading C: the store never leaves Connecting (REQ-500). If "connect to the store" in REQ-12 means "the store is ready", the node never reaches the schema check or REQ-502. It would keep retrying as if the store were unreachable (REQ-25), and REQ-502's failure would never happen.

All three readings fail before any write, so run 2's goal holds under each. They differ in which error the operator sees, and reading C turns a startup failure into an endless retry.

**Options**
1. *(recommended)* In REQ-12, make the Redis checks part of connecting: *"then connect to the store (failing under redis REQ-502 or REQ-505 while connecting, REQ-500), check the schema (failing under REQ-23 or REQ-43) and run the startup checks that need the stored data (recurring REQ-236)"*. This matches the redis module and TECH-69 and removes reading C.
2. Keep REQ-12 and change TECH-69 and redis REQ-500 so that a failed EVAL probe still marks the connection established and leaves REQ-502 to the later check. Two documents change to follow one sentence.
3. Leave it. Implementers will probably choose reading B because TECH-69 is explicit, but the hosting sentence then says something the code does not do.

**Ready to apply (option 1)** (REQ-12 `shall` only; if F-1 option 1 is also chosen, keep its REQ-236 clause)
```json
{ "id": "REQ-12", "ears": { "when": "the host starts",
    "shall": "start the Bellhop node, validate the options and run the startup checks that need no store (dashboard REQ-301 and REQ-334, recurring REQ-210), then connect to the store (failing under redis REQ-502 or REQ-505 while connecting, redis REQ-500), check the schema (failing under REQ-23 or REQ-43) and run the startup checks that need the stored data (recurring REQ-236), and only then migrate under REQ-22 and, where the worker is registered and the schema version is accepted with no migration pending, reconcile code-defined recurring jobs" } }
```

---

## Modeling assumptions
Decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. Changes since the second run are marked.
| # | Assumption | Affects |
|---|---|---|
| A-1 | No clocks. ShutdownTimeout passing, backoff, health thresholds, clock skew and NodeLostAfter are nondeterministic events or flags | REQ-25, REQ-28, REQ-29, REQ-34, REQ-46–48, REQ-60 |
| A-2 | *(changed)* "All startup checks have passed" (REQ-18) means: options validated (REQ-9), both of REQ-12's groups of other-module checks passed (A-19), schema accepted (REQ-23/43) and no migration pending (REQ-22). "Recurring jobs have been reconciled" is REQ-12's reconcile step, required only on worker nodes | REQ-18, REQ-19, SCN-2 |
| A-3 | A process in a final state exits and may be replaced by a new one, possibly on another library version and with another configuration (modeling artefact `Archive`). Exit frees a store-native migration lock (TECH-126) | all |
| A-5 | The host may signal stop while the node is Starting (REQ-55 → Stopped) or Running (REQ-27 → Draining) | REQ-27, REQ-55 |
| A-6 | Job claims are abstracted from the jobs module: a claim needs Running, a started worker and a reachable store; 1 in-flight slot (2 in SCN-4). Handlers are not obliged to finish | REQ-20, REQ-25, REQ-27, REQ-29 |
| A-7 | Cancel and release at timeout is jobs REQ-140. The release is attempted whatever the store's state; it only lands if the store is reachable | REQ-29 |
| A-8 | "Fewer than MinNodesAlive worker nodes have a heartbeat within NodeLostAfter" is a nondeterministic flag, evaluated only on worker nodes | REQ-44, REQ-49, REQ-60 |
| A-9 | `Chk_DrainEnds` treats the host-side shutdown steps as obligations (weakly fair). The store, handlers and the stop signal are not obliged. *(changed)* It is checked on `Hosting_Live.cfg`, where every other module's check passes; on the full `Hosting.cfg` it timed out | REQ-28, REQ-29 |
| A-10…A-13 | The derived checks from the first run are unchanged | — |
| A-14 | REQ-16's "once, before the node is marked running" is read as one warning logged as part of the node's start event | REQ-16, SCN-1 |
| A-15 | The health check is one action (lint: same trigger), in the order: Unhealthy checks, then REQ-58 from Unhealthy, then REQ-34 from Healthy, then counting a pass. A run in which every check passes counts as a pass, including the REQ-58 run | REQ-30–35, REQ-44, REQ-58 |
| A-16 | Schema versions are small integers (0–3; 0 is a store with no Bellhop schema). Accepted = expected or expected − 1. The in-memory store has the expected schema and is always reachable | REQ-15, REQ-23, REQ-43, F-1 |
| A-17 | Registrations are none / client / worker (worker includes client), combined with the alerts registration. The dashboard itself is not modeled; its startup checks are part of A-19 | REQ-52, REQ-51 |
| A-18 | Bounds: 1 node for startup, shutdown and health; 2 nodes for the shared store and migration lock, with the full space checked (881,138 states) | all |
| A-19 | *(changed)* The other modules' startup checks are one per-process value: all pass, one that needs no store fails (dashboard REQ-301/334, recurring REQ-210), or one that needs the store fails (redis REQ-502/505, recurring REQ-236). The first group runs alongside option validation, in either order. The second runs after the schema check and before any migration or reconciliation, as REQ-12 now says. The in-memory store also runs the second group (it trivially passes in reality) | REQ-12, REQ-18, F-1, F-2 |
| A-20 | A node with the alerts registration starts its notification checks when it is marked running (integrations INV-411/REQ-438), and stops them when it stops. REQ-59 therefore holds by construction | REQ-59 |
| A-21 | *(retired)* REQ-18 now requires reconciliation itself. `Chk_ReconciledBeforeRunning` stays as the check for it (every worker node is assumed to declare code-defined recurring jobs; with none, reconciliation is trivially done) | REQ-18 |
| A-22 | *(new)* `Chk_StoreChecksOnAcceptedSchema`: a check that reads Bellhop's stored data (recurring REQ-236) is assumed to be readable only on a schema the node accepts (REQ-23, REQ-32). F-1 option 1 replaces this assumption with a sentence | F-1 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-9, REQ-12–16, REQ-18–25, REQ-27–35, REQ-40, REQ-42–44, REQ-46…REQ-50 (absorbed into nondeterministic flags), REQ-52, REQ-55–60 (REQ-57 as a guard on HostStarts; REQ-60 absorbed, A-8), SCN-1…SCN-6 | REQ-1–8, REQ-36–39 (info) · REQ-11, REQ-41 (retired) · REQ-10 (needs lease timing, jobs REQ-102) · REQ-17, REQ-51 (static rules, a model can only restate them) · REQ-26, REQ-45 (log-only, nothing reads the state) · REQ-53, REQ-54 (log-only, the same "a node starts" event as REQ-16, which is modeled) |

Regenerated this run: REQ-12 (new actions `NoStoreChecksPass`, `NoStoreCheckFails`, `StoreChecksPass` and `StoreCheckFails`, which replace `OtherCheckFails`; the schema, migration and reconcile steps are guarded by the check groups) and REQ-18/REQ-19 (`MarkRunning` waits for reconciliation on worker nodes). Re-checked: SCN-1, SCN-2, SCN-3 (`Scn_SchemaMismatchBlocksRunning`), SCN-5 and SCN-6. `OkVals` changed from a boolean to three values in every cfg, and `Init_SCN4` starts with both check groups passed and the jobs reconciled. Nothing else in the model changed.

Lint warnings, all one event each, modeled as one action: REQ-16/53/54 (`HostStarts`), REQ-18/19 (`MarkRunning`), REQ-27/55 (`HostStops`), REQ-30–35/44/58 (`HealthCheck`).

**Reproduce** from `specs/model/hosting`: `python run_checks.py`, or `python run_checks.py <check-name>` for one check (a full name runs only that check; anything else is a substring). It writes one cfg per check to `checks/` and runs `run_tlc.py Hosting.tla --config checks/<name>.cfg --stop-at-first --workers 2`. Receipt: `hosting.modeled.json` (45 items up to date, 7 skipped).

## Next
Decide F-1 first. It decides whether the run-2 rule "no store write before a failing check" stays as it is (option 1) or gives way for REQ-236 (option 2). F-2 edits the same REQ-12 sentence, so apply them together. Apply changes with `refiner-requirements`, then run `refiner-model` again.
