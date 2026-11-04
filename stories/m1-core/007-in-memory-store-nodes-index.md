# M1-07 In-memory store: nodes, leases, purge, routing, index, statistics and namespaces

## Context

The remaining store methods:

- the node registry: `TickAsync` step 5 (heartbeat with routable names), `ShutdownNodeAsync` and `GetNodesAsync`
- cleanup leadership: `TryAcquireLeaseAsync` (ADR-1, EXE-10)
- retention and cluster-wide routing: `PurgeAsync` (STO-7 with D6), including marking jobs `Unroutable` (A-26), plus `TickAsync` step 3 (rerouting)
- the secondary index: `IJobIndex` (STO-11)
- `GetStatisticsAsync` for the dashboard and metrics
- namespace isolation (STO-9) across every method

After this story the in-memory store implements the whole contract and every "Not built yet" placeholder from M1-05 is gone.

Files: extend `InMemoryJobStore` (one instance can serve several namespaces over shared state, so the isolation tests mean something); add `tests/Bellhop.Storage.Conformance/` classes `NodeAndLeaseConformanceTests`, `PurgeAndRoutingConformanceTests`, `IndexConformanceTests`, `StatisticsConformanceTests` and `NamespaceIsolationConformanceTests`.

**As a** operator
**I want** nodes, cleanup, routing and indexes handled by the store with the same semantics everywhere
**so that** retention never surprises me, jobs without a handler are visible, and the dashboard can filter without table scans.

## Acceptance criteria

All are conformance tests. Criteria marked *(refinement)* replay a sequence the refinement models found breaking a rule (refinement/decisions.md); each must fail if its decision is reverted.

- Given a tick with a `NodeHeartbeat`, when `GetNodesAsync` runs, then the node appears with its host, mode, queues, workers, in-flight count, version, routable names, application, recurring names (D-9), `StartedAt` (first heartbeat) and `HeartbeatAt` (latest).
- Given a node holding 2 leases, when `ShutdownNodeAsync` runs with them, then both jobs are `Enqueued` with history reason `Shutdown` and their attempt restored to the pre-claim value (A-9), and the node row is gone.
- *(refinement, D-5)* Given a node holding a lease on a job whose cancel was requested, when `ShutdownNodeAsync` runs with it, then the job is `Cancelled`, not `Enqueued`, with its attempt restored, and no other node can claim it.
- *(refinement, D-6)* Given a lease whose job was recovered by a tick and then requeued with attempt 0, when `ShutdownNodeAsync` runs with the old lease, then the job is unchanged (attempt still 0, never -1): a release is conditional on `state = 'Processing'` and the token.
- Given `TryAcquireLeaseAsync("cleanup", "n1", 1 min)`, when `n2` tries before expiry, then `n2` gets false. After expiry, `n2` gets true. `n1` renewing its own unexpired lease gets true. 8 concurrent first acquirers yield exactly one true.
- Given terminal jobs older and newer than their retention (Succeeded 7 d by default, D6), when `PurgeAsync` runs with `BatchSize = 500` repeatedly, then only the expired ones are deleted, each call deletes at most 500, the last call returns fewer than 500, and no non-terminal job is ever deleted, however old (RET-3, STO-7).
- Given a `DeadLettered` job 29 days old with 30 days retention, when purge runs, then it is kept.
- Given nodes with heartbeats older than `NodeTimeout`, when purge runs, then they are removed; fresh nodes stay.
- Given an `Enqueued` job named `x`, older than `UnroutableAfter`, and no live node whose routable names include `x`, when purge runs, then the job is `Unroutable` with a history entry (JOB-3). Given a live node that advertises `x`, then it is left `Enqueued`. Given a younger job, it is left alone. A node is live while its last heartbeat is no older than `NodeTimeout`; a node that hasn't ticked for that long counts as gone, even if it later resumes (D-2, D-12).
- Given an `Unroutable` job named `x`, when a tick runs with `RoutableNames` containing `x`, then it is `Enqueued` again and `Rerouted = 1`. A tick without `x` leaves it alone.
- *(refinement, D-20)* Given code-defined recurring definitions A and B of `svc1`, and live `svc1` nodes that all advertise only A (a crashed old-version node's heartbeat has aged out after the last reconcile), when `PurgeAsync` runs, then B is orphaned and A is not. Given one live `svc1` node still advertising B, then B is left alone.
- *(refinement, D-22)* Given code-defined recurring definitions of `svc1` and no live `svc1` node at all (every node down for longer than `NodeTimeout`), when `PurgeAsync` runs from a `svc2` node sharing the store, then none of them is orphaned, so their catch-up still happens when `svc1` comes back.
- Given `IJobIndex.AddAsync(id, "tag", "tenant:42")` for 120 jobs, when `QueryAsync` pages through, then all 120 come back once each, newest first, and `CountAsync` returns 120. `RemoveAsync` removes one pairing only. Deleting or purging a job removes its index entries.
- Given jobs created with tags, when the index is queried by `tag`, then they are found (tags are index entries, A-22).
- Given jobs in several states and queues, when `GetStatisticsAsync` runs, then non-terminal counts in `ByState` are exact; `ByQueue` gives enqueued, processing and scheduled (including `Failed` waiting to retry) per queue, for every queue that has such jobs; `SucceededLastHour` and `DeadLetteredLastHour` count jobs finished in the last hour of store time. The in-memory store reports exact terminal counts (`TerminalCountsApproximate = false`).
- Given two stores (or one store with two namespaces) sharing the same underlying state with namespaces `a` and `b`, when jobs, recurring definitions, nodes and index entries are created in `a`, then from `b` claims, ticks (promotion, recovery, due recurring, awaiting promotion), purge, queries, statistics, node lists and index queries see none of them (STO-9).

## Tests

The five conformance classes, run against the in-memory store.

## Out of scope

The cleanup loop and node heartbeat timing (M1-13). Tags page (M2).

**Priority:** Must
**Depends on:** M1-05
**Traces to:** STO-7, STO-9, STO-11, EXE-6 (release part), EXE-10, CON-7, RET-3, JOB-3, BLT-9 (index part); arch §5.3, D6, A-9, A-22, A-26; refinement D-2, D-5, D-6, D-9, D-12, D-20, D-22

## Notes

Status: not started
