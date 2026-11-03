# M1-07 In-memory store: nodes, leases, purge, index and statistics

## Context

The remaining store methods: node registry (`TickAsync` step 4 heartbeat, `ShutdownNodeAsync`, `GetNodesAsync`), cleanup leadership (`TryAcquireLeaseAsync`, ADR-1, EXE-10), retention (`PurgeAsync`, STO-7 with D6), the secondary index (`IJobIndex`, STO-11), and `GetStatisticsAsync` for the dashboard and metrics. After this story the in-memory store implements the whole contract and every "Not built yet" placeholder from M1-05 is gone.

Files: extend `InMemoryJobStore`; add `tests/Bellhop.Storage.Conformance/NodeAndLeaseConformanceTests.cs`, `PurgeConformanceTests.cs`, `IndexConformanceTests.cs`, `StatisticsConformanceTests.cs`.

**As a** operator
**I want** nodes, cleanup and indexes handled by the store with the same semantics everywhere
**so that** retention never surprises me and the dashboard can filter without table scans.

## Acceptance criteria

All are conformance tests.

- Given a tick with a `NodeHeartbeat`, when `GetNodesAsync` runs, then the node appears with its host, mode, queues, workers, in-flight count, version, `StartedAt` (first heartbeat) and `HeartbeatAt` (latest).
- Given a node holding 2 leases, when `ShutdownNodeAsync` runs with them, then both jobs are `Enqueued` with history reason `Shutdown` and their attempt restored to the pre-claim value (A-9), and the node row is gone.
- Given `TryAcquireLeaseAsync("cleanup", "n1", 1 min)`, when `n2` tries before expiry, then `n2` gets false. After expiry, `n2` gets true. `n1` renewing its own unexpired lease gets true. 8 concurrent first acquirers yield exactly one true.
- Given terminal jobs older and newer than their retention (Succeeded 7 d by default, D6), when `PurgeAsync` runs with `BatchSize = 500` repeatedly, then only the expired ones are deleted, each call deletes at most 500, the last call returns fewer than 500, and no non-terminal job is ever deleted, however old (RET-3, STO-7).
- Given a `DeadLettered` job 29 days old with 30 days retention, when purge runs, then it is kept.
- Given nodes with heartbeats older than `NodeTimeout`, when purge runs, then they are removed; fresh nodes stay.
- Given `IJobIndex.AddAsync(id, "tag", "tenant:42")` for 120 jobs, when `QueryAsync` pages through, then all 120 come back once each, and `CountAsync` returns 120. `RemoveAsync` removes one pairing only. Deleting or purging a job removes its index entries.
- Given jobs created with tags, when the index is queried by `tag`, then they are found (tags are index entries, A-22).
- Given jobs in several states and queues, when `GetStatisticsAsync` runs, then `ByState` counts every state, `EnqueuedByQueue` counts ready jobs per queue, and `SucceededLastHour` / `FailedLastHour` count transitions in the last hour of store time.

## Tests

The four conformance classes, run against the in-memory store.

## Out of scope

The cleanup loop and node heartbeat timing (M1-13). Tags page (M2).

**Priority:** Must
**Depends on:** M1-05
**Traces to:** STO-7, STO-11, EXE-6 (release part), EXE-10, CON-7, RET-3, BLT-9 (index part); arch §5.3, D6, A-9, A-22

## Notes

Status: not started
