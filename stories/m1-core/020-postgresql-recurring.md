# M1-20 PostgreSQL store: recurring definitions

## Context

Implements the recurring part of `IJobStore` on PostgreSQL, the methods M1-06 covers: reconcile with `INSERT … ON CONFLICT`, compare-and-set firing with overlap decided in the same transaction, `Awaiting` promotion in `CompleteAsync`, and due definitions in the tick (arch §4.4). It is done when `RecurringConformanceTests` passes unchanged against PostgreSQL. This is where T6 (duplicate cron rows on multi-instance startup) and T2 (duplicate fires) are proven impossible on the reference store.

Files: `src/Bellhop.PostgreSql/PostgreSqlJobStore.Recurring.cs` (partial class) and its SQL; `tests/Bellhop.PostgreSql.Tests/PostgreSqlRecurringConformance.cs`.

**As a** user running several nodes on PostgreSQL
**I want** recurring definitions to be reconciled and fired atomically in the database
**so that** each occurrence happens exactly once and overlap rules hold across nodes.

## Acceptance criteria

- Given `RecurringConformanceTests` (M1-06), when it runs against PostgreSQL, then every test passes, including 5 concurrent reconciles and 8 concurrent fires (REC-3, REC-6, REC-7).
- Given 100,000 recurring definitions of which 10 are due, when the tick's recurring sub-select is explained, then it uses `recurring_due` and reads only the due rows (REC-7: "one range query per poll").
- Given concurrent reconciles, then no unique-violation exception escapes (ON CONFLICT handles it) and no deadlock occurs over 50 repetitions. Rows are upserted in name order, so lock order is consistent.
- Given a fire whose overlap check and insert run while another node completes the active occurrence, then the outcome is consistent: either the fire sees the occurrence as active (and skips, queues or cancels) or it doesn't (and enqueues). It never leaves an `Awaiting` occurrence with no active predecessor. Proven by a stress test of 200 iterations racing `CompleteAsync` against `FireRecurringAsync` with `Queue` policy, then asserting that no `Awaiting` job remains once all active ones finish.
- Given `CompleteAsync` of an occurrence, when the next `Awaiting` occurrence is promoted, then the promotion and the completion commit together (one transaction).

## Tests

`PostgreSqlRecurringConformance`, `PostgreSqlRecurringPlanTests`, `PostgreSqlRecurringRaceTests`.

## Out of scope

Engine-side firing (M1-14) and end-to-end overlap (M1-15), which run on the in-memory store. The acceptance run (M1-27) exercises them on PostgreSQL.

**Priority:** Must
**Depends on:** M1-06, M1-19
**Traces to:** REC-3, REC-6, REC-7, REC-9, REC-10, STO-8; arch §4.4, §5.3, §7.7

## Notes

Status: not started
