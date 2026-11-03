# M1-19 PostgreSQL store: job lifecycle

## Context

Implements the job lifecycle part of `IJobStore` on PostgreSQL, exactly the methods M1-05 covers, using the statements described in arch §4.4: `FOR UPDATE SKIP LOCKED` claims, fenced completion, and a single-statement tick for promote, recover, reroute, ready flags and `now()`. It is done when `JobLifecycleConformanceTests` passes unchanged against PostgreSQL. Where the tracks meet: the same conformance class passes on both stores.

Files: `src/Bellhop.PostgreSql/PostgreSqlJobStore.cs` (methods as in M1-05), `src/Bellhop.PostgreSql/Sql/` (SQL as embedded or `const` strings with the schema substituted once at construction from the validated identifier), and `tests/Bellhop.PostgreSql.Tests/PostgreSqlJobLifecycleConformance.cs`. The conformance fixture's `StoreClock` for PostgreSQL advances time by waiting or by writing timestamps relative to `now()` (choose and record in Notes). Tests must not rely on wall-clock sleeps of more than a few seconds.

**As a** user on PostgreSQL
**I want** the job lifecycle to be atomic and index-backed in the database
**so that** many nodes can claim, complete and recover jobs correctly under load.

## Acceptance criteria

- Given `JobLifecycleConformanceTests` (M1-05), when it runs against PostgreSQL, then every test passes, including the 8-claimer and concurrent-tick tests (EXE-2, EXE-4, STO-8).
- Given a claim, when its SQL runs, then it is one statement (one round-trip), and the history insert happens in the same statement or transaction.
- Given an idle database (no jobs), when `EXPLAIN` is run on the tick statement, then every sub-select uses a partial index (`jobs_due`, `jobs_lease`, `jobs_unroutable`, `jobs_ready`) and none uses a sequential scan on `jobs` once the table holds 100,000 terminal rows (STO-6, STO-7). Asserted by a test that parses `EXPLAIN (FORMAT JSON)`.
- Given the tick, when it runs, then it is one round-trip (STO-6). Counted with an Npgsql command interceptor or logging in the test.
- Given `CreateJobsAsync` with 3 jobs, then they, their history and their index rows are inserted in one transaction. A duplicate id raises `DuplicateJobIdException` (mapped from SQLSTATE 23505 on the primary key) and nothing is written.
- Given `QueryJobsAsync` over 100,000 jobs with each filter in turn, when `EXPLAIN` runs on the generated SQL, then it uses `jobs_state`, `jobs_name` or `job_index`, and the keyset cursor (not `OFFSET`) (DSH-8).
- Given a transient error (the container is paused for 2 s during a claim), then the store raises Npgsql's exception without wrapping away its detail. The engine's backoff is tested elsewhere; this test only checks the store doesn't hang past `CommandTimeout`.
- Given a payload with `\u0000` (not valid in `jsonb`), then `CreateJobsAsync` fails with a clear `JobSerializationException`-style message naming the job, not a raw Npgsql error. Or the serializer rejects it first; record which in Notes.

## Tests

`PostgreSqlJobLifecycleConformance`, `PostgreSqlQueryPlanTests`, `PostgreSqlRoundTripTests`, `PostgreSqlErrorMappingTests`.

## Out of scope

Recurring (M1-20). Nodes, leases, purge, index and statistics (M1-21). Notifications (M1-22).

**Priority:** Must
**Depends on:** M1-05, M1-18
**Traces to:** STO-1, STO-2, STO-6, STO-8, EXE-2, EXE-4, EXE-9, DSH-8; arch §4.4, §5.3

## Notes

Status: not started
