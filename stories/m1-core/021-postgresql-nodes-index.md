# M1-21 PostgreSQL store: nodes, leases, purge, index and statistics

## Context

Implements the remaining `IJobStore` methods and `IJobIndex` on PostgreSQL, the methods M1-07 covers: heartbeat upsert in the tick, `ShutdownNodeAsync`, `GetNodesAsync`, `TryAcquireLeaseAsync` on `meta`, `PurgeAsync` with `SKIP LOCKED` batches over `jobs_finished`, the index on `job_index`, and `GetStatisticsAsync`. After this story the PostgreSQL store implements the whole contract and no "Not built yet" placeholder remains. Answers H4: cleanup in paced batches that hit an index.

Files: `src/Bellhop.PostgreSql/PostgreSqlJobStore.Nodes.cs`, `.Purge.cs`, `.Index.cs`, `.Statistics.cs` (partial classes) with their SQL; `tests/Bellhop.PostgreSql.Tests/` conformance runners for the four M1-07 classes.

**As a** operator on PostgreSQL
**I want** cleanup, node tracking and filtering to be cheap and index-backed
**so that** the database stays small and quiet without tuning.

## Acceptance criteria

- Given the four conformance classes from M1-07, when they run against PostgreSQL, then every test passes.
- Given 1,000,000 terminal jobs (bulk-loaded with `COPY` in the test) of which 600 are past retention, when `PurgeAsync` runs, then it deletes at most `BatchSize` rows per call, uses `jobs_finished` (verified by `EXPLAIN`), and each call finishes in under 1 s on the test container (STO-7).
- Given purge running on two nodes at once (lease bypassed in the test), then no row is deleted twice and no deadlock occurs (`SKIP LOCKED`).
- Given `GetStatisticsAsync` on 1,000,000 jobs, then it uses index-only or partial-index scans for the per-state counts, or a documented alternative if exact counts are too slow. If exact counting of terminal states is above 200 ms, Notes record the choice: for example, an estimate from `pg_class.reltuples` per partial index, labelled as approximate in the API (`ByStateIsApproximate`), and an amendment to arch §5.2.
- Given `TryAcquireLeaseAsync` from 8 concurrent connections, then exactly one wins.
- Given the index API over 100,000 tagged jobs, then `QueryAsync` and `CountAsync` use the `job_index` primary key.

## Tests

The four conformance runners, plus `PostgreSqlPurgeLoadTests` and `PostgreSqlStatisticsPlanTests`.

## Out of scope

Cleanup scheduling (M1-13). Node metrics history (M2).

**Priority:** Must
**Depends on:** M1-07, M1-19
**Traces to:** STO-7, STO-11, EXE-10, CON-7, DSH-8; arch §4.4, §5.3

## Notes

Status: not started
