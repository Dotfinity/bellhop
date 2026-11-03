# M1-21 PostgreSQL store: nodes, leases, purge, index and statistics

## Context

Implements the remaining `IJobStore` methods and `IJobIndex` on PostgreSQL, the methods M1-07 covers: heartbeat upsert in the tick, `ShutdownNodeAsync`, `GetNodesAsync`, `TryAcquireLeaseAsync` on `meta`, `PurgeAsync` with `SKIP LOCKED` batches over `jobs_finished`, the index on `job_index`, and `GetStatisticsAsync`. After this story the PostgreSQL store implements the whole contract and no "Not built yet" placeholder remains. Answers H4: cleanup in paced batches that hit an index.

Files: `src/Bellhop.PostgreSql/PostgreSqlJobStore.Nodes.cs`, `.Purge.cs`, `.Index.cs`, `.Statistics.cs` (partial classes) with their SQL; `tests/Bellhop.PostgreSql.Tests/` conformance runners for the five M1-07 classes.

**As a** operator on PostgreSQL
**I want** cleanup, node tracking and filtering to be cheap and index-backed
**so that** the database stays small and quiet without tuning.

## Acceptance criteria

- Given the five conformance classes from M1-07 (including namespace isolation and Unroutable marking), when they run against PostgreSQL, then every test passes (STO-9, JOB-3).
- Given 1,000,000 terminal jobs (bulk-loaded with `COPY` in the test) of which 600 are past retention, when `PurgeAsync` runs, then it deletes at most `BatchSize` rows per call, uses `jobs_finished` (verified by `EXPLAIN`), and each call finishes in under 1 s on the test container (STO-7).
- Given purge running on two nodes at once (lease bypassed in the test), then no row is deleted twice and no deadlock occurs (`SKIP LOCKED`).
- Given `GetStatisticsAsync` on 1,000,000 jobs, then non-terminal counts and `ByQueue` are exact and come from the partial indexes, last-hour counts use `jobs_finished`, and the whole call takes under 200 ms. Terminal totals are exact if that fits the budget; otherwise they are estimates and `TerminalCountsApproximate = true` (arch §5.2). Notes record which, with the measured time.
- Given `TryAcquireLeaseAsync` from 8 concurrent connections, then exactly one wins.
- Given the index API over 100,000 tagged jobs, then `QueryAsync` and `CountAsync` use the `job_index` primary key.

## Tests

The five conformance runners, plus `PostgreSqlPurgeLoadTests` and `PostgreSqlStatisticsPlanTests`.

## Out of scope

Cleanup scheduling (M1-13). Node metrics history (M2).

**Priority:** Must
**Depends on:** M1-07, M1-19
**Traces to:** STO-7, STO-9, STO-11, EXE-10, CON-7, JOB-3, DSH-8; arch §4.4, §5.2, §5.3, A-26

## Notes

Status: not started
