# M1-06 In-memory store: recurring definitions

## Context

Recurring correctness across nodes is the other half of the most painful grievances (H2, H10, T2, T6: duplicate fires, crashes on concurrent seeding, overlap enforced only in-process). REC-3, REC-6 and REC-7 require the store to make these decisions atomically. This story adds the recurring part of the store contract and its conformance tests, so that the engine (M1-14, M1-15) and PostgreSQL (M1-20) build on fixed semantics.

Methods: `ReconcileRecurringAsync`, `UpsertRecurringAsync`, `RemoveRecurringAsync`, `SetRecurringPausedAsync`, `FireRecurringAsync`, `QueryRecurringAsync`, and `TickAsync` steps 4 (promote `Awaiting` occurrences, the only place this happens) and 6 (due definitions). See arch §4.4 (lock order), §5.3 and the §7.7 overlap rules.

Files: extend `InMemoryJobStore`; add `tests/Bellhop.Storage.Conformance/RecurringConformanceTests.cs`; run it from `Bellhop.Tests`.

**As a** user running several nodes
**I want** recurring definitions and their firing decisions to be atomic in the store
**so that** N nodes produce exactly one occurrence and the overlap policy holds across nodes, however an occurrence ends.

## Acceptance criteria

All are conformance tests. "Fire" means `FireRecurringAsync`; "tick" means `TickAsync` with `IncludeRecurring`.

### Reconcile and edit

- Given 5 concurrent `ReconcileRecurringAsync` calls with the same 3 code-defined definitions, when all finish, then exactly 3 rows exist, no call threw, and the results sum to 3 created (REC-3).
- Given an existing code-defined definition, when reconcile runs with an unchanged definition, then it reports `Unchanged` and `NextRunAt` is untouched. Given a changed cron, then `NextRunAt` takes the request's value (REC-10). Given a changed queue only, `NextRunAt` is untouched.
- Given code-defined definitions A and B with `DefinedBy = "svc1"` and C with `DefinedBy = "svc2"`, when `svc1` reconciles with only A, then B is orphaned (`OrphanedAt` set, not deleted), C is untouched, and the result lists `Orphaned = [B]`. Given `svc1` reconciles again with A and B, then B is restored, and its `NextRunAt` is the request's value, not the stale stored one (A-15).
- Given a code-defined definition without `AllowRuntimeOverride`, when `UpsertRecurringAsync` runs for the same name, then `RecurringDefinitionConflictException` is thrown with: `Recurring job "nightly-cleanup" is defined in code. Change it in code, or mark it AllowRuntimeOverride.`
- Given `AllowRuntimeOverride`, when a runtime upsert changes the schedule, then the edit is stored with `OverriddenAt` set. When reconcile then runs with the original code definition, the runtime schedule, payload and options are kept (REC-3).
- Given `SetRecurringPausedAsync(name, true, null)`, then the definition is not due while paused. Given resume with `nextRunAt = t`, then `NextRunAt = t`.
- Given `RemoveRecurringAsync`, then the definition is deleted, and its existing occurrence jobs are not.
- Given 230 definitions, when `QueryRecurringAsync` pages with `Limit = 100`, then 100, 100 and 30 are returned, ordered by name. Each item's `LastJobState` is the current state of its `LastJobId` job.

### Due and fire

- Given orphaned or paused definitions whose `NextRunAt` is in the past, when a tick runs, then they are not returned. An active due one is returned, and at most `BatchSize` are returned, ordered by `NextRunAt`.
- Given a due definition and 8 concurrent fires with the same `ExpectedNextRunAt`, when all finish, then exactly one returned `Fired = true`, exactly one occurrence job exists, and `NextRunAt` equals the new value (REC-7).
- Given a definition paused after the tick returned it, when a scheduled fire runs, then it returns `Fired = false` and creates nothing.
- Given a fire, then `LastRunAt`, `LastFireOutcome` and `LastJobId` are set on the definition.

### Overlap

REC-6, arch §7.7. "Active" means Scheduled, Enqueued, Processing, Failed or Awaiting.

- Given `Skip` and an active occurrence in each active state in turn, when a fire runs, then no job is created, `LastFireOutcome = Skipped`, and `NextRunAt` still advances.
- Given `Queue` and an active occurrence, when a fire runs, then the new occurrence is `Awaiting`. While the active one is `Processing` or `Failed` (waiting to retry), ticks don't promote it. Once the active one is terminal, the next tick promotes the oldest `Awaiting` occurrence to `Enqueued` and reports `AwaitingPromoted = 1`.
- Given `Queue` with an `Awaiting` occurrence, when its predecessor ends by **any** path (`CompleteAsync`, lease recovery to `DeadLettered` or `Cancelled`, `CancelAsync`, or `DeleteAsync`), then the next tick promotes it. One test per path proves no occurrence is stranded.
- Given `Allow` and an active occurrence, when a fire runs, then a new `Enqueued` occurrence is created.
- Given `CancelPrevious` and an `Enqueued` previous occurrence, when a fire runs, then the previous one is `Cancelled` and the new one is `Awaiting`, promoted by the next tick. Given a `Processing` previous one, then it is cancel-requested (listed in `FireResult.CancelRequested`), and the new one stays `Awaiting` until the previous one is terminal (A-16).
- Given a fire with 3 occurrences (a `RunAll` sequence) and no active occurrence, then under `Allow` all 3 are `Enqueued`. Under `Skip`, `Queue` and `CancelPrevious`, the first is `Enqueued` and the other two are `Awaiting`. Successive ticks with completions in between run them one at a time, in order.
- Given `Manual = true`, when a fire runs with a stale `ExpectedNextRunAt`, then it still fires, applies the overlap policy, and leaves `NextRunAt` unchanged (trigger now, REC-9).
- Given `Skip`, no active occurrence, and 8 concurrent manual fires, then exactly one occurrence is created; the others report `Skipped`. The definition lock serializes them (P3).
- Given two concurrent ticks and one recurring name with 2 `Awaiting` occurrences and nothing active, then exactly one occurrence is promoted.

## Tests

`RecurringConformanceTests`, run against the in-memory store. The concurrent tests use real threads.

## Out of scope

Computing occurrences, misfire decisions and logging (M1-14). Node registry, purge and index (M1-07).

**Priority:** Must
**Depends on:** M1-05
**Traces to:** REC-3, REC-6, REC-7, REC-9, REC-10, STO-8, P3; arch §4.4, §5.3, §7.7, A-15, A-16, A-25, M-5

## Notes

Status: not started
