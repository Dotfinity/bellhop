# Findings: Bellhop hosting, configuration, startup, health and shutdown

<!-- refiner-findings v1 | module: hosting | specHash: 7f4e4a93844cc1ac516e5620fd90d04074fe29e04012535eff1a772cbd3bf463 | run: 2026-11-08 (fifth run) | previous: model/hosting/previous.findings.md (git: specs/hosting.findings.md at 846cc29) -->

**Run:** 2026-11-08, fifth run · **Requirements file:** `specs/hosting.json` (specHash `7f4e4a93844c`) · **Model:** `specs/model/hosting/Hosting.tla`, updated from `model/hosting/handoff.json` (1 modified: REQ-29; impacted: SCN-4)
**TLC:** every check ran on its own with `--stop-at-first --workers 4` (`model/hosting/run_checks.py`, hard timeout 600 s). No run threw a TLC exception, and every "holds" below is a completed run. Four other modules were being checked on the same machine.

| Config | Bounds | Result | Distinct states |
|---|---|---|---|
| `Hosting.cfg` | 1 node, every configuration, jobs may time out | 23 checks and the deadlock run hold, including `Chk_NoStopInGraceBeforeTimeout`. The new-database trap `Chk_NewDatabaseNotRunning` is reached, as expected | 141,520 (trap: 108,881 at the stop) |
| `Hosting_Live.cfg` | `Hosting.cfg` with every other module's startup check passing | `Chk_DrainEnds` holds | 51,168 |
| `Hosting_Drain.cfg` | 1 worker node, 2 job slots, jobs time out before or during the drain, held jobs may have a cancellation request | `Chk_NoStopInGraceBeforeTimeout` and `Chk_DrainEnds` hold. The new trap `Chk_NoShutdownCancellation` is reached: a node marks a job cancelled at shutdown and stops, as expected | 318 (trap: 192 at the stop) |
| `Hosting_DrainNotes.cfg` | *(retired)* REQ-29 as its run-4 notes read; the notes now match the sentence | — | — |
| `Hosting_Health.cfg` | 1 node, stalls, thresholds and node-count changes | `Chk_StallStaysUnhealthy`, `Prop_NoUnhealthyToHealthy` and the deadlock run hold | 4,824 |
| `Hosting_2N.cfg` | 2 nodes, shared store, invalid options possible, other modules' checks pass or fail in either group | 11 checks and the deadlock run hold | 2,709,110 |
| `traces/Holds_2N_small.cfg` | 2 nodes, valid options, expected version 3 | 7 checks hold | 137,898 |
| `Hosting_2N_fail.cfg` | 2 nodes, AutoMigrate on, expected version 3 | 6 checks hold | 203,870 |
| `Hosting_SCN{1,2,4,5,6}.cfg` | scenario | every trap was reached, so all five scenarios pass (SCN-4: 145 states) | 12–190 |

**Result:** 0 findings: 0 contradictions · 0 gaps · 0 unprovable · 0 ambiguities · 0 modeling notes. The run-4 finding is resolved, and the REQ-29 change raised nothing new.

## Changes since last run
| Finding | Status |
|---|---|
| previous F-1 (ambiguity \| Chk_NoStopInGraceBeforeTimeout) | resolved. REQ-29's notes (and jobs REQ-140's) now say what its sentence says: a handler whose timeout token was signalled stays in flight until jobs REQ-138 or REQ-186 settles it, and the drain waits for it up to ShutdownTimeout. The notes' reading has no source any more, so the `TimedOutCounts` switch and `Hosting_DrainNotes.cfg` are retired. `Chk_NoStopInGraceBeforeTimeout` holds on `Hosting.cfg` (141,520 states) and `Hosting_Drain.cfg` (318) |

`findings_delta.py previous.findings.md hosting.findings.md`:

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | ambiguity · Chk_NoStopInGraceBeforeTimeout · REQ-29,jobs:REQ-138,jobs:REQ-140 |

1 resolved, 0 new, 0 still open

## What the REQ-29 change does in the model
REQ-29 now reads: *While a node is draining, when every in-flight job has finished, or ShutdownTimeout has passed, the remaining jobs' tokens were cancelled and the lease releases and cancellations that jobs REQ-140 and REQ-190 call for at shutdown were attempted, the system shall stop the node.*

The shutdown-cancel step (`CancelAndRelease`) now attempts one store write per job the node still holds:
- a job whose timeout token was not signalled and whose cancellation was not requested is released (jobs REQ-140);
- a job whose cancellation was requested is marked cancelled (jobs REQ-190, shutdown branch). That branch has no timeout guard, so a timed-out job with a cancellation request is marked cancelled as well, and the node does not wait for its grace period;
- a timed-out job without a cancellation request keeps its lease. The node waits for it until REQ-138 or REQ-186 settles it, or until it stops after ShutdownTimeout and lease expiry recovers the job.

A write lands only if the store is reachable. A failed one is left to lease expiry, so a store outage still never blocks the stop. `Chk_DrainEnds` holds on `Hosting_Live.cfg` and `Hosting_Drain.cfg`.

Example (`Chk_NoShutdownCancellation` trap, `Hosting_Drain.cfg`, 192 states; trace in `model/hosting/checks/drain_trap_Chk_NoShutdownCancellation.md`):
1. `orders-1` starts, passes every startup check and is marked running (REQ-12, REQ-18). It claims `send-invoice` and `sync-stock`.
2. An operator requests cancellation of `sync-stock` (jobs REQ-135); its handler ignores the token.
3. The host stops: the node is Draining (REQ-27). ShutdownTimeout passes (REQ-28).
4. Both tokens are cancelled. `send-invoice` is released with its attempt taken back (jobs REQ-140); `sync-stock` is marked Cancelled (jobs REQ-190).
5. The node stops (REQ-29). Neither job is left to lease expiry, so `sync-stock` cannot be dead-lettered at its last attempt, which was jobs run 4 F-1.

**Also checked (not a finding).** A cancellation requested *after* the shutdown cancel, for a timed-out job the node still holds, finds REQ-190's shutdown trigger already past. The node stops after ShutdownTimeout; lease expiry then marks the job cancelled (REQ-190, attempts left) or dead-letters it at its last attempt (REQ-133). REQ-190's notes accept exactly that for lease expiry ("exhausted attempts on … lease expiry still dead-letter"), so it is not reported. Cancellation requests belong to the jobs module, which does not model the hosting drain.

---

## Modeling assumptions
Decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. Changes since the fourth run are marked.
| # | Assumption | Affects |
|---|---|---|
| A-1 | No clocks. ShutdownTimeout passing, backoff, health thresholds, clock skew, NodeLostAfter, a job's timeout and TimeoutGracePeriod are nondeterministic events or flags | REQ-25, REQ-28, REQ-29, REQ-34, REQ-46–48, REQ-60 |
| A-2 | "All startup checks have passed" (REQ-18) means: options validated (REQ-9), the checks that need no store passed, the store connected with the Redis checks passed, the schema accepted (REQ-23/43) with REQ-236 passed, and no migration pending (REQ-22). "Recurring jobs have been reconciled" is REQ-12's reconcile step, required only on worker nodes | REQ-18, REQ-19, SCN-2 |
| A-3 | A process in a final state exits and may be replaced by a new one, possibly on another library version and with another configuration (modeling artefact `Archive`). Exit frees a store-native migration lock (TECH-126) | all |
| A-5 | The host may signal stop while the node is Starting (REQ-55 → Stopped) or Running (REQ-27 → Draining) | REQ-27, REQ-55 |
| A-6 | Job claims are abstracted from the jobs module: a claim needs Running, a started worker and a reachable store; 1 in-flight slot (2 in SCN-4 and the drain cfg). Handlers are not obliged to finish. A claimed job may time out (A-24) | REQ-20, REQ-25, REQ-27, REQ-29 |
| A-7 | *(changed)* Cancel and release at ShutdownTimeout is jobs REQ-139, REQ-140 and REQ-190. Jobs whose timeout token was not signalled and whose cancellation was not requested are released; jobs whose cancellation was requested are marked cancelled, timed out or not. Each write is attempted whatever the store's state, and lands only if the store is reachable | REQ-29 |
| A-8 | "Fewer than MinNodesAlive worker nodes have a heartbeat within NodeLostAfter" is a nondeterministic flag, evaluated only on worker nodes | REQ-44, REQ-49, REQ-60 |
| A-9 | `Chk_DrainEnds` treats the host-side shutdown steps as obligations (weakly fair). The store, handlers, job timeouts and the stop signal are not obliged. It is checked on `Hosting_Live.cfg` (every other module's check passes) and on `Hosting_Drain.cfg` | REQ-28, REQ-29 |
| A-10…A-13 | The derived checks from the first run are unchanged | — |
| A-14 | REQ-16's "once, before the node is marked running" is read as one warning logged as part of the node's start event | REQ-16, SCN-1 |
| A-15 | The health check is one action (lint: same trigger), in the order: Unhealthy checks, then REQ-58 from Unhealthy, then REQ-34 from Healthy, then counting a pass. A run in which every check passes counts as a pass, including the REQ-58 run | REQ-30–35, REQ-44, REQ-58 |
| A-16 | Schema versions are small integers (0–3; 0 is a store with no Bellhop schema). Accepted = expected or expected − 1. The in-memory store has the expected schema and is always reachable | REQ-15, REQ-23, REQ-43 |
| A-17 | Registrations are none / client / worker (worker includes client), combined with the alerts registration. The dashboard itself is not modeled; its startup checks are part of A-19 | REQ-52, REQ-51 |
| A-18 | Bounds: 1 node for startup, shutdown and health; 2 nodes for the shared store and migration lock, with the full space checked | all |
| A-19 | The other modules' startup checks are one per-process value: all pass; one that needs no store fails (dashboard REQ-301/334, recurring REQ-210); a Redis check that is part of connecting fails (redis REQ-502/505; only a configured store can be Redis); or a stored runtime-defined recurring job collides (recurring REQ-236). The first group runs alongside option validation, in either order. The Redis checks run inside the connect step, before the schema check. REQ-236 runs after the schema check and before any migration or reconciliation. It cannot fail on a store with no Bellhop schema | REQ-12, REQ-18 |
| A-20 | A node with the alerts registration starts its notification checks when it is marked running (integrations INV-411/REQ-438), and stops them when it stops. REQ-59 therefore holds by construction | REQ-59 |
| A-23 | The schema check and REQ-236 are one step. Between them, another node can only migrate the schema forward. REQ-236 reads name and origin only, and migrations only add (TECH-127), so a split step would read the same answer | REQ-12, recurring REQ-236 |
| A-24 | *(changed)* A claimed job may time out (jobs REQ-137) until the shutdown cancel. A timed-out job settles under jobs REQ-138/REQ-186 (it throws within its grace or is abandoned), which is not obliged here. An unsettled timed-out handler is an in-flight job for REQ-29 (its sentence and, since run 4, its notes); the `TimedOutCounts` switch is retired. `Chk_NoStopInGraceBeforeTimeout` says a node does not stop before ShutdownTimeout while such a handler is unsettled | REQ-29 |
| A-25 | `Chk_ConnectChecksFirst`: a node whose Redis connection checks fail never connects, reads stored data or reconciles; it fails the start under REQ-502/505, not REQ-23/43 | REQ-12 |
| A-26 | *(new)* Cancellation requests (jobs REQ-135) are not tracked. At the shutdown cancel, which held jobs have one is chosen freely, timed-out jobs included. `Chk_NoShutdownCancellation` is a trap: it is expected to be violated, showing that a node can mark a job cancelled at shutdown and then stop | REQ-29, jobs REQ-190 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-9, REQ-12–16, REQ-18–25, REQ-27–35, REQ-40, REQ-42–44, REQ-46…REQ-50 (absorbed into nondeterministic flags), REQ-52, REQ-55–60 (REQ-57 as a guard on HostStarts; REQ-60 absorbed, A-8), SCN-1…SCN-6 | REQ-1–8, REQ-36–39 (info) · REQ-11, REQ-41 (retired) · REQ-10 (needs lease timing, jobs REQ-102) · REQ-17, REQ-51 (static rules, a model can only restate them) · REQ-26, REQ-45 (log-only, nothing reads the state) · REQ-53, REQ-54 (log-only, the same "a node starts" event as REQ-16, which is modeled) |

Regenerated this run:
- **REQ-29.** `CancelAndRelease` attempts a REQ-140 release or a REQ-190 cancellation for every held job (A-7, A-26) and records the new `cancelled` count. `AllFinished` counts an unsettled timed-out handler as in flight, with no switch. The constant `TimedOutCounts` is removed from the module and every cfg. New trap `Chk_NoShutdownCancellation`.

Re-checked: SCN-4 (its trap is still reached: one job finishes and the other is released, `released = 1`), and every other check. `Hosting_DrainNotes.cfg` and its two checks are removed. Nothing else in the model changed.

Lint warnings, all one event each, modeled as one action: REQ-16/53/54 (`HostStarts`), REQ-18/19 (`MarkRunning`), REQ-27/55 (`HostStops`), REQ-30–35/44/58 (`HealthCheck`).

**Reproduce** from `specs/model/hosting`: `python run_checks.py`, or `python run_checks.py <check-name>` for one check (a full name runs only that check; anything else is a substring). It writes one cfg per check to `checks/` and runs `run_tlc.py Hosting.tla --config checks/<name>.cfg --stop-at-first --workers 4`. Receipt: `hosting.modeled.json` (45 items up to date, 21 skipped).

## Next
Nothing to decide in hosting. This run's report is the assumptions table: A-26 is new, and A-7 and A-24 changed. If any of them is wrong, apply changes with `refiner-requirements`, then run `refiner-model` again.
