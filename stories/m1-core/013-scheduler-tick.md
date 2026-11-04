# M1-13 Scheduler tick, recovery and cleanup

## Context

The tick is the one periodic query a node makes (STO-6). It promotes due jobs, recovers expired leases on behalf of crashed nodes, reroutes unroutable jobs, heartbeats the node and returns due recurring definitions. Cleanup runs under a short store lease on one node at a time. Together they provide EXE-4 (recovery without a single point of failure), EXE-9 (database clock, skew warning), EXE-10 (distributed scheduler) and STO-7 (paced retention). This answers H3 and H4, Hangfire's stuck jobs and expiration-manager load spikes.

Implements arch §7.4, except firing recurring definitions (M1-14, which plugs into the tick result). Fills in the scheduler shell from M1-08.

Files: `src/Bellhop/Engine/Scheduling/` (`SchedulerLoop` with step function `TickOnceAsync`, `CleanupLoop` with `RunOnceAsync`, `ClockSkewMonitor`).

**As a** operator of several nodes
**I want** every node to share scheduling, recovery and cleanup safely
**so that** crashed nodes' jobs come back on their own, nothing depends on a leader, and cleanup never spikes the database.

## Acceptance criteria

- Given a `Both` node, when it runs, then `TickAsync` is called every `PollInterval`, with the node's routable names and queues, and a heartbeat every `NodeHeartbeatInterval` carrying the application name and the code-defined recurring names (EXE-10, refinement D-9).
- Given a tick that promoted jobs, promoted `Awaiting` occurrences, or reports ready queues, then the worker wake signal is raised (EXE-8). Given `MoreDue = true`, the next tick runs at once.
- Given the store clock 10 s behind the node clock, when a tick runs, then `IStoreClock` reports node time minus about 10 s, and later engine computations (retry times, recurring next runs) use it (EXE-9).
- Given node A claims a job through the store and "crashes" (the lease is never renewed), when node B's scheduler ticks after the lease expires, then the job is `Enqueued` with reason `Interrupted`, the next claim returns it as attempt 2, and info 1301 is logged on B (EXE-4). With attempts exhausted, it is `DeadLettered` with reason `Interrupted`, and B raises `OnDeadLetteredAsync`. With a cancel request pending, it is `Cancelled`, and B raises `OnCancelledAsync` (RET-6). Two "nodes" (two scheduler instances with different node ids) share one in-memory store in this test. The full run-it-again path with workers is covered by M1-17 and the acceptance run.
- Given the node clock 10 s ahead of the store clock (a `FakeTimeProvider` for the node and a separate clock for the store), when a tick runs, then warning 1302 reports the skew, and is not repeated for 10 minutes (EXE-9).
- Given the tick throws, then 1303 is logged, the loop backs off as in arch §7.1, and the health state records the failure (consumed by M1-16).
- Given two nodes running cleanup at the same interval, when both fire, then only the lease holder calls `PurgeAsync` (EXE-10, ADR-1).
- Given `Cleanup.Interval = 10 s` and a store `CommandTimeout` of 30 s, then the cleanup lease requested is 60 s (the larger of twice the interval and twice the command timeout); with the default 5 min interval it is 10 min. The holder renews the lease with `TryAcquireLeaseAsync` before every `PurgeAsync` batch, and stops the run as soon as a renewal returns false (refinement D-8).
- *(refinement, D-8)* Given node A's cleanup run and a fake clock advanced past A's lease between two batches (so node B takes the lease), then A calls no further `PurgeAsync` and B's run is the only one purging.
- Given 1,200 expired succeeded jobs and `BatchSize = 500`, when cleanup runs, then `PurgeAsync` is called 3 times with `PauseBetweenBatches` between calls, and stops after the batch that returned fewer than 500 (STO-7).
- Given configured retention (`Succeeded = 1 h` for the test), when cleanup runs, then the `PurgeRequest` carries the configured per-state values and `UnroutableAfter = 1 min`. The default retention for Succeeded is 7 days (D6).
- Given jobs that cleanup marked `Unroutable`, then warning 1202 is logged once per job name with the count and the text in arch §7.3 (JOB-3).
- Given recurring definitions that cleanup orphaned (no live node of their application defines them any more), then info 1406 is logged with their names (refinement D-20).
- Given `Mode = ClientOnly`, then neither the tick nor cleanup runs (A-14).
- Given the host stops, then the tick and cleanup loops stop within `PollInterval`.

## Tests

`SchedulerTickTests`, `RecoveryAcrossNodesTests`, `ClockSkewTests`, `CleanupLeadershipTests`, `CleanupPacingTests`, using the in-memory store and fake time.

## Out of scope

Firing recurring definitions (M1-14). Reconciliation (M1-14). PostgreSQL tick SQL (M1-19 to M1-21). Health check surface (M1-16).

**Priority:** Must
**Depends on:** M1-07, M1-08
**Traces to:** EXE-4, EXE-9, EXE-10, STO-6, STO-7, CON-7; arch §7.4, D6; refinement D-8, D-9, D-20

## Notes

Status: not started
