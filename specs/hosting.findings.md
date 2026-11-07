# Findings: Bellhop hosting, configuration, startup, health and shutdown

<!-- refiner-findings v1 | module: hosting | specHash: c057134bffdae0bdf5a154a82f99c79b9aaac9790fc95089e52b7163d82c0e20 | run: 2026-11-07 (fourth run) | previous: model/hosting/previous.findings.md (git: specs/hosting.findings.md at d42e2c1) -->

**Run:** 2026-11-07, fourth run · **Requirements file:** `specs/hosting.json` (specHash `c057134bffda`) · **Model:** `specs/model/hosting/Hosting.tla`, updated from `model/hosting/handoff.json` (2 modified: REQ-12, REQ-29; impacted: SCN-1, SCN-2, SCN-3, SCN-4, SCN-5, SCN-6)
**TLC:** every check ran on its own with `--stop-at-first --workers 4` (`model/hosting/run_checks.py`). No run threw a TLC exception, and every "holds" below is a completed run. The hard timeout went from 160 s to 600 s: the state space grew by the connect step and timed-out jobs, and five other modules were being checked on the same machine.

| Config | Bounds | Result | Distinct states |
|---|---|---|---|
| `Hosting.cfg` | 1 node, every configuration, jobs may time out | 23 checks and the deadlock run hold, including the new `Chk_ConnectChecksFirst` and `Chk_NoStopInGraceBeforeTimeout`. The new-database trap `Chk_NewDatabaseNotRunning` is reached, as expected | 139,504 (trap: 108,885 at the stop) |
| `Hosting_Live.cfg` | `Hosting.cfg` with every other module's startup check passing | `Chk_DrainEnds` holds | 50,016 |
| `Hosting_Drain.cfg` | *(new)* 1 worker node, 2 job slots, jobs time out before or during the drain; REQ-29 as its sentence reads | `Chk_NoStopInGraceBeforeTimeout` and `Chk_DrainEnds` hold | 270 |
| `Hosting_DrainNotes.cfg` | *(new)* the same, REQ-29 as its notes read | `Chk_NoStopInGraceBeforeTimeout` is violated (F-1). `Chk_DrainEnds` holds | 137 at the stop (294 for `Chk_DrainEnds`) |
| `Hosting_Health.cfg` | 1 node, stalls, thresholds and node-count changes | `Chk_StallStaysUnhealthy`, `Prop_NoUnhealthyToHealthy` and the deadlock run hold | 4,616 |
| `Hosting_2N.cfg` | 2 nodes, shared store, invalid options possible, other modules' checks (now including a failing Redis connect check) pass or fail in either group | 11 checks and the deadlock run hold, including `Chk_NoStoreWriteBeforeOtherChecks`, `Chk_ReconciledBeforeRunning` and `Chk_ConnectChecksFirst` | 2,483,294 |
| `traces/Holds_2N_small.cfg` | 2 nodes, valid options, expected version 3 | 7 checks hold | 119,826 |
| `Hosting_2N_fail.cfg` | 2 nodes, AutoMigrate on, expected version 3 | 6 checks hold, including `Chk_NoStoreWriteBeforeOtherChecks` and `Chk_ConnectChecksFirst` | 182,630 |
| `Hosting_SCN{1,2,4,5,6}.cfg` | scenario | every trap was reached, so all five scenarios pass | 12–188 |

**Result:** 1 finding: 0 contradictions · 0 gaps · 0 unprovable · 1 ambiguity · 0 modeling notes. Both run-3 findings are resolved. The new finding comes from REQ-29's notes, which say something its sentence does not.

## Changes since last run
| Finding | Status |
|---|---|
| F-1 | new. REQ-29's sentence makes a draining node wait for a timed-out handler. Its notes and jobs REQ-140's notes say the node does not wait |
| previous F-1 (ambiguity \| Chk_StoreChecksOnAcceptedSchema) | resolved. Recurring REQ-236 now says what it reads on an unmigrated store: name and origin only, and none where there is no Bellhop schema. The run-3 check, which assumed (A-22) that REQ-236 could read only an accepted schema, is retired with that assumption. On a new database, a node now passes REQ-236, migrates and runs (trap `Chk_NewDatabaseNotRunning` reached, 108,885 states). A REQ-236 collision can no longer be found on a store with no schema. `Chk_NoStoreWriteBeforeOtherChecks` still holds: 1 node (139,504), 2 nodes with failing checks (`Hosting_2N_fail.cfg`, 182,630) and the full two-node space (`Hosting_2N.cfg`, 2,483,294) |
| previous F-2 (ambiguity \| redis-check-order) | resolved. REQ-12 now places the Redis EVAL and eviction checks inside "connect to the store". The model has a connect step that a failing Redis check ends in StartupFailed, before the schema check. `Chk_ConnectChecksFirst` holds: 1 node (139,504), `Hosting_2N_fail.cfg` (182,630) and `Hosting_2N.cfg` (2,483,294). Reading C from run 3 (a node retrying for ever in Connecting) is gone, because REQ-12 now says the failure fails the start |

`findings_delta.py previous.findings.md hosting.findings.md`:

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | ambiguity · Chk_StoreChecksOnAcceptedSchema · REQ-12,REQ-22,recurring:REQ-236 |
| F-2 | resolved | ambiguity · redis-check-order · REQ-12,redis:REQ-500,redis:REQ-502,redis:REQ-505 |
| F-1 | new | ambiguity · Chk_NoStopInGraceBeforeTimeout · REQ-29,jobs:REQ-138,jobs:REQ-140 |

2 resolved, 1 new, 0 still open

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | ambiguity | low | REQ-28, REQ-29, jobs REQ-137, REQ-138, REQ-140, REQ-186 | REQ-29's sentence waits for a timed-out handler; its notes say the drain does not, and that changes how the job ends |

---

## F-1 · ambiguity · low — REQ-29's sentence waits for a timed-out handler; its notes say the drain does not
<!-- finding: ambiguity | Chk_NoStopInGraceBeforeTimeout | REQ-29,jobs:REQ-138,jobs:REQ-140 -->

**Requirements involved**
- REQ-29: *While a node is draining, when every in-flight job has finished, or ShutdownTimeout has passed, the remaining jobs' tokens were cancelled and the lease releases that jobs REQ-140 calls for were attempted, the system shall stop the node.* Its notes add: *"a job whose timeout token was signalled before the shutdown signal is not released (jobs REQ-140), so the node does not wait for it; lease expiry recovers it and its attempt counts (jobs REQ-132, REQ-133)."*
- jobs REQ-137: *While a job is processing, when it has run for longer than its timeout, the system shall signal the handler's cancellation token.*
- jobs REQ-138 (REQ-186 is the same with attempts exhausted): *While a job is processing, its timeout token was signalled and its cancellation was not requested, if the handler is still running TimeoutGracePeriod later or throws OperationCanceledException within it, and … the retry policy allows another attempt, the system shall abandon the handler if it is still running, mark the job failed with reason Timeout and set retryAt from the backoff.*
- jobs REQ-140: *While the job's node is draining, the job's token was cancelled for shutdown, its timeout token was not signalled and its cancellation was not requested, …, release the job's lease and take back the attempt …* Its notes repeat: *"the draining node does not wait for it (hosting REQ-29)"*.
- jobs REQ-132: *While a job is processing …, when its leaseExpiresAt has passed …, if the attempt number is below maxAttempts, … return the job to enqueued with reason Interrupted, keeping the attempt counted.*

**What happens** (TLC counter-example, `Chk_NoStopInGraceBeforeTimeout`, 137 states, `Hosting_DrainNotes.cfg`, which reads REQ-29 the way its notes do; trace in `model/hosting/checks/drainNotes_Chk_NoStopInGraceBeforeTimeout.md`)
`orders-1` runs one job, `send-invoice`, with the default 5-minute timeout. ShutdownTimeout and TimeoutGracePeriod are both 30 s (REQ-28, jobs REQ-187).
1. `orders-1` starts, passes every startup check and is marked running (REQ-12, REQ-18). It claims `send-invoice`.
2. `send-invoice` runs past its timeout, and its timeout token is signalled (jobs REQ-137). Its 30-second grace period starts.
3. One second later, the host stops: the node is Draining (REQ-27).
4. **The node stops at once** (REQ-29 as the notes read it): no other job is in flight, and the timed-out handler is not waited for. `send-invoice` is still Processing with `orders-1`'s lease.
5. Later, the lease expires and another node returns `send-invoice` to enqueued with reason Interrupted, keeping the attempt (jobs REQ-132).

As the sentence reads it (`Hosting_Drain.cfg`), the node waits in step 4. The handler is still an in-flight job until it throws within its grace or is abandoned (REQ-138, REQ-186), so `Chk_NoStopInGraceBeforeTimeout` holds there (270 states). With the defaults, the grace ends 29 s later, before ShutdownTimeout. REQ-138 then marks the job failed with reason Timeout and a backoff, or REQ-186 dead-letters it if the retry policy declines another attempt.

**Why** The jobs run-3 F-1 decision was about REQ-140: a timed-out job is not *released*. The note added to REQ-29 then said more than that, namely that the node does not *wait* for it. The sentence was not changed to match, so it still counts a timed-out handler as in flight. The two readings end the job differently:
- **The sentence** (wait up to ShutdownTimeout): a job that timed out before the stop signal settles under REQ-138 or REQ-186 while the node drains. It is retried after its backoff, or dead-lettered when the retry policy declines. Lease expiry is only needed when the timeout fires during the drain and its grace outlasts ShutdownTimeout.
- **The notes** (do not wait): every job that timed out before the stop signal is left to lease expiry. It waits for LeaseDuration, is recorded as Interrupted instead of Timeout, and REQ-132 returns it to enqueued **without asking the retry policy**. A job whose policy says "don't retry a timeout" runs again.

Neither reading loses a job, and the drain ends under both (`Chk_DrainEnds` holds on both cfgs).

**Options**
1. *(recommended)* Keep the sentence and correct the notes on REQ-29 and jobs REQ-140. A handler whose timeout token was signalled is in flight until REQ-138 or REQ-186 settles it, so the drain waits for it like any other job, up to ShutdownTimeout. With the defaults, a timeout signalled before the stop signal always settles inside the drain. This is annotation only and needs no re-modeling.
2. Make the notes the rule: *"when every in-flight job whose timeout token was not signalled has finished, or …"*. Drains end sooner, but every job that timed out shortly before a deploy goes through lease expiry: it is recorded as Interrupted, waits for LeaseDuration and skips the retry policy.
3. Leave both. Implementers who follow the sentence get option 1. A jobs implementer who reads REQ-140's notes may skip the timed-out handler in the drain count and get option 2.

**Ready to apply (option 1)** (annotation only: replace the last sentence of each `notes`)
```json
{ "id": "REQ-29",
  "notes": "… jobs run 3 F-1: a job whose timeout token was signalled is not released (jobs REQ-140). It stays in flight until jobs REQ-138 or REQ-186 settles it, so the drain waits for it up to ShutdownTimeout like any other job; with the defaults (both 30 s) a timeout signalled before the stop signal settles within the drain. Only a handler still in its grace period when ShutdownTimeout passes is left to lease expiry, and its attempt counts (jobs REQ-132, REQ-133). refiner-model 2026-11-07 run 4 F-1 (recommended option)." }
```
```json
{ "id": "REQ-140",
  "notes": "… A job whose timeout token was signalled before the shutdown signal is a timeout whether the handler cooperates or not (REQ-138, REQ-186). The draining node counts it as in flight until it settles, up to ShutdownTimeout (hosting REQ-29); if ShutdownTimeout passes first, lease expiry counts the attempt (REQ-132, REQ-133). hosting run 4 F-1." }
```

**Also checked (not a finding).** The drain can still end while a timed-out handler runs. That happens under the sentence too, when ShutdownTimeout passes during the handler's grace period: a timeout signalled during the drain, or a grace period longer than what is left of ShutdownTimeout. The job keeps its lease, the stopping process takes the handler with it, and lease expiry returns the job (REQ-132) or dead-letters it (REQ-133), with the attempt counted. Fencing (jobs INV-128) refuses a late result. Nothing is lost, and this is what the jobs run-3 F-1 decision accepted, so it is not reported. The one side effect is the retry-policy skip in REQ-132. That belongs to the jobs module, and it also applies to every crash.

---

## Modeling assumptions
Decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. Changes since the third run are marked.
| # | Assumption | Affects |
|---|---|---|
| A-1 | No clocks. ShutdownTimeout passing, backoff, health thresholds, clock skew, NodeLostAfter, a job's timeout and TimeoutGracePeriod are nondeterministic events or flags | REQ-25, REQ-28, REQ-29, REQ-34, REQ-46–48, REQ-60 |
| A-2 | *(changed)* "All startup checks have passed" (REQ-18) means: options validated (REQ-9), the checks that need no store passed, the store connected with the Redis checks passed, the schema accepted (REQ-23/43) with REQ-236 passed, and no migration pending (REQ-22). "Recurring jobs have been reconciled" is REQ-12's reconcile step, required only on worker nodes | REQ-18, REQ-19, SCN-2 |
| A-3 | A process in a final state exits and may be replaced by a new one, possibly on another library version and with another configuration (modeling artefact `Archive`). Exit frees a store-native migration lock (TECH-126) | all |
| A-5 | The host may signal stop while the node is Starting (REQ-55 → Stopped) or Running (REQ-27 → Draining) | REQ-27, REQ-55 |
| A-6 | *(changed)* Job claims are abstracted from the jobs module: a claim needs Running, a started worker and a reachable store; 1 in-flight slot (2 in SCN-4 and the drain cfgs). Handlers are not obliged to finish. A claimed job may time out (A-24) | REQ-20, REQ-25, REQ-27, REQ-29 |
| A-7 | *(changed)* Cancel and release at timeout is jobs REQ-139/REQ-140. Only jobs whose timeout token was not signalled are released. The release is attempted whatever the store's state; it only lands if the store is reachable | REQ-29 |
| A-8 | "Fewer than MinNodesAlive worker nodes have a heartbeat within NodeLostAfter" is a nondeterministic flag, evaluated only on worker nodes | REQ-44, REQ-49, REQ-60 |
| A-9 | `Chk_DrainEnds` treats the host-side shutdown steps as obligations (weakly fair). The store, handlers, job timeouts and the stop signal are not obliged. It is checked on `Hosting_Live.cfg` (every other module's check passes) and on both drain cfgs | REQ-28, REQ-29 |
| A-10…A-13 | The derived checks from the first run are unchanged | — |
| A-14 | REQ-16's "once, before the node is marked running" is read as one warning logged as part of the node's start event | REQ-16, SCN-1 |
| A-15 | The health check is one action (lint: same trigger), in the order: Unhealthy checks, then REQ-58 from Unhealthy, then REQ-34 from Healthy, then counting a pass. A run in which every check passes counts as a pass, including the REQ-58 run | REQ-30–35, REQ-44, REQ-58 |
| A-16 | Schema versions are small integers (0–3; 0 is a store with no Bellhop schema). Accepted = expected or expected − 1. The in-memory store has the expected schema and is always reachable | REQ-15, REQ-23, REQ-43 |
| A-17 | Registrations are none / client / worker (worker includes client), combined with the alerts registration. The dashboard itself is not modeled; its startup checks are part of A-19 | REQ-52, REQ-51 |
| A-18 | Bounds: 1 node for startup, shutdown and health; 2 nodes for the shared store and migration lock, with the full space checked | all |
| A-19 | *(changed)* The other modules' startup checks are one per-process value: all pass; one that needs no store fails (dashboard REQ-301/334, recurring REQ-210); a Redis check that is part of connecting fails (redis REQ-502/505; only a configured store can be Redis); or a stored runtime-defined recurring job collides (recurring REQ-236). The first group runs alongside option validation, in either order. The Redis checks run inside the connect step, before the schema check. REQ-236 runs after the schema check and before any migration or reconciliation. It cannot fail on a store with no Bellhop schema | REQ-12, REQ-18 |
| A-20 | A node with the alerts registration starts its notification checks when it is marked running (integrations INV-411/REQ-438), and stops them when it stops. REQ-59 therefore holds by construction | REQ-59 |
| A-22 | *(retired)* REQ-236 now says what it reads on an unmigrated store; `Chk_StoreChecksOnAcceptedSchema` is gone | — |
| A-23 | *(new)* The schema check and REQ-236 are one step. Between them, another node can only migrate the schema forward. REQ-236 reads name and origin only, and migrations only add (TECH-127), so a split step would read the same answer | REQ-12, recurring REQ-236 |
| A-24 | *(new)* A claimed job may time out (jobs REQ-137) until the shutdown cancel. A timed-out job settles under jobs REQ-138/REQ-186 (it throws within its grace or is abandoned), which is not obliged here. `TimedOutCounts` selects whether an unsettled timed-out handler counts as an in-flight job for REQ-29 (TRUE, the sentence: `Hosting.cfg` and every other cfg; FALSE, the notes: `Hosting_DrainNotes.cfg`). `Chk_NoStopInGraceBeforeTimeout` says a node does not stop before ShutdownTimeout while such a handler is unsettled | REQ-29, F-1 |
| A-25 | *(new)* `Chk_ConnectChecksFirst`: a node whose Redis connection checks fail never connects, reads stored data or reconciles; it fails the start under REQ-502/505, not REQ-23/43 | REQ-12 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-9, REQ-12–16, REQ-18–25, REQ-27–35, REQ-40, REQ-42–44, REQ-46…REQ-50 (absorbed into nondeterministic flags), REQ-52, REQ-55–60 (REQ-57 as a guard on HostStarts; REQ-60 absorbed, A-8), SCN-1…SCN-6 | REQ-1–8, REQ-36–39 (info) · REQ-11, REQ-41 (retired) · REQ-10 (needs lease timing, jobs REQ-102) · REQ-17, REQ-51 (static rules, a model can only restate them) · REQ-26, REQ-45 (log-only, nothing reads the state) · REQ-53, REQ-54 (log-only, the same "a node starts" event as REQ-16, which is modeled) |

Regenerated this run:
- **REQ-12.** New actions `ConnectStore` and `ConnectCheckFails` (the Redis checks inside the connect step). `StoreChecksPass` and `StoreCheckFails` are now recurring REQ-236 only, cannot fail on schema 0, and record `checkedEmpty`. `SchemaTooOld`, `SchemaTooNew` and the store checks need the connection. `OkVals` gains `"failConnect"`.
- **REQ-29.** New jobs-side actions `JobTimesOut` and `TimedOutSettles`. `CancelAndRelease` releases only jobs that were not timed out and records `cancelDone`. `StopNode` follows both readings through `TimedOutCounts`.

Re-checked: SCN-1 to SCN-6 (SCN-3 is `Scn_SchemaMismatchBlocksRunning`). `Init_SCN4` starts connected. Every cfg gains `TimedOutCounts = TRUE`, and `failConnect` where it listed `failStore`. New cfgs: `Hosting_Drain.cfg` and `Hosting_DrainNotes.cfg`. Nothing else in the model changed.

Lint warnings, all one event each, modeled as one action: REQ-16/53/54 (`HostStarts`), REQ-18/19 (`MarkRunning`), REQ-27/55 (`HostStops`), REQ-30–35/44/58 (`HealthCheck`).

**Reproduce** from `specs/model/hosting`: `python run_checks.py`, or `python run_checks.py <check-name>` for one check (a full name runs only that check; anything else is a substring). It writes one cfg per check to `checks/` and runs `run_tlc.py Hosting.tla --config checks/<name>.cfg --stop-at-first --workers 4`. Receipt: `hosting.modeled.json` (45 items up to date, 7 skipped).

## Next
Decide F-1. It is annotation only, but the jobs implementer reads REQ-140's notes, and the two readings send a timed-out job through different rules: REQ-138 and REQ-186 under the sentence, REQ-132 under the notes. Apply changes with `refiner-requirements`, then run `refiner-model` again.
