# M1-06 In-memory store: recurring definitions

## Context

Recurring correctness across nodes is the other half of the most painful grievances (H2, H10, T2, T6: duplicate fires, crashes on concurrent seeding, overlap enforced only in-process). REC-3, REC-6 and REC-7 require the store to make these decisions atomically. This story adds the recurring part of the store contract and its conformance tests, so that the engine (M1-14, M1-15) and PostgreSQL (M1-20) build on fixed semantics.

Methods: `ReconcileRecurringAsync`, `UpsertRecurringAsync`, `RemoveRecurringAsync`, `SetRecurringPausedAsync`, `FireRecurringAsync`, `QueryRecurringAsync`, `TickAsync` step 5 (due definitions), and the `Awaiting` promotion and `last_outcome` update inside `CompleteAsync` (arch §5.3, §7.7 overlap table).

Files: extend `InMemoryJobStore`; add `tests/Bellhop.Storage.Conformance/RecurringConformanceTests.cs`; run it from `Bellhop.Tests`.

**As a** user running several nodes
**I want** recurring definitions and their firing decisions to be atomic in the store
**so that** N nodes produce exactly one occurrence and the overlap policy holds across nodes.

## Acceptance criteria

All are conformance tests.

- Given 5 concurrent `ReconcileRecurringAsync` calls with the same 3 code-defined definitions, when all finish, then exactly 3 rows exist, no call threw, and the results sum to 3 created (REC-3).
- Given an existing code-defined definition, when reconcile runs with an unchanged definition, then it reports `Unchanged` and `NextRunAt` is untouched. Given a changed cron, then `NextRunAt` is recomputed through `ComputeNextRun` (REC-10). Given a changed queue only, `NextRunAt` is untouched.
- Given code-defined definitions A and B with `DefinedBy = "svc1"` and C with `DefinedBy = "svc2"`, when `svc1` reconciles with only A, then B is orphaned (`OrphanedAt` set, not deleted), C is untouched, and the result lists `Orphaned = [B]`. Given `svc1` reconciles again with A and B, then B is restored (A-15).
- Given an orphaned or paused definition whose `NextRunAt` is in the past, when `TickAsync` runs with `IncludeRecurring`, then it is not returned. An active due one is returned, and at most `BatchSize` are returned, ordered by `NextRunAt`.
- Given a code-defined definition without `AllowRuntimeOverride`, when `UpsertRecurringAsync` runs for the same name, then `RecurringDefinitionConflictException` is thrown with: `Recurring job "nightly-cleanup" is defined in code. Change it in code, or mark it AllowRuntimeOverride.` With `AllowRuntimeOverride`, the update succeeds.
- Given a due definition and 8 concurrent `FireRecurringAsync` calls with the same `ExpectedNextRunAt`, when all finish, then exactly one returned `Fired = true`, exactly one occurrence job exists, and `NextRunAt` equals the new value (REC-7).
- Given overlap `Skip` and an active occurrence (in each of Scheduled, Enqueued, Processing, Failed, Awaiting), when a fire runs, then no job is created, the outcome is `Skipped`, `last_outcome = Skipped`, and `NextRunAt` still advances.
- Given overlap `Queue` and an active occurrence, when a fire runs, then a new occurrence is created as `Awaiting`. When the active one completes (any outcome), then the oldest `Awaiting` occurrence becomes `Enqueued` in the same `CompleteAsync` call.
- Given overlap `Allow` and an active occurrence, when a fire runs, then a new `Enqueued` occurrence is created.
- Given overlap `CancelPrevious` and an `Enqueued` previous occurrence, when a fire runs, then the previous is `Cancelled` and the new one is `Awaiting`, then promoted at once because nothing is active any more. Given a `Processing` previous one, then it is cancel-requested (listed in `FireResult.CancelRequested`), and the new one stays `Awaiting` until the previous completes (A-16).
- Given `Manual = true`, when a fire runs with a stale `ExpectedNextRunAt`, then it still fires, applies the overlap policy, and leaves `NextRunAt` unchanged (trigger now, REC-9).
- Given an occurrence that completes, when the definition is read, then `LastRunAt`, `LastOutcome` and `LastJobId` reflect it.
- Given `SetRecurringPausedAsync(name, true)`, then the definition is not due while paused. `RemoveRecurringAsync` deletes the definition but not its existing occurrence jobs.
- Given 230 definitions, when `QueryRecurringAsync` pages with `Limit = 100`, then 100, 100 and 30 are returned, ordered by name.

## Tests

`RecurringConformanceTests`, run against the in-memory store. The concurrent tests use real threads.

## Out of scope

Computing occurrences, misfire decisions and logging (M1-14). Node registry, purge and index (M1-07).

**Priority:** Must
**Depends on:** M1-05
**Traces to:** REC-3, REC-6, REC-7, REC-9, REC-10, STO-8; arch §5.3, §7.7, A-15, A-16, M-5

## Notes

Status: not started
