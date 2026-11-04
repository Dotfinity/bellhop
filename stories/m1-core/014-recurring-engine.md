# M1-14 Recurring jobs: reconciliation, firing and manager

## Context

The engine side of recurring jobs: collecting code-defined definitions, reconciling them at startup, computing occurrences and misfires when the tick reports due definitions, and the runtime `IRecurringJobManager`. The store already makes the atomic decisions (M1-06). This story decides *what* to ask it. Implements arch §7.7 (definitions, reconciliation, next occurrence, firing steps 1 to 5, trigger, pause and resume) and REC-1 to REC-5, REC-8 to REC-10. Answers H10 and T6 (catch-up surprises, duplicate seeding).

Files: `src/Bellhop/Engine/Recurring/` (`RecurringRegistry` from `[Recurring]`, `AddRecurring` and `JobBuilder.Recurring`; `RecurringReconciler`; `RecurringFirer`; `MisfireCalculator`; `RecurringJobManager`), and the recurring lines of the startup summary.

**As a** developer
**I want** to declare recurring jobs in code or create them at runtime, and have them fire exactly once per occurrence with explicit misfire rules
**so that** schedules are predictable after downtime, deploys and edits.

## Acceptance criteria

- Given `[Recurring("0 3 * * *", TimeZone = "Europe/Sofia")]` on a job, when the host starts, then a code-defined definition named after the job exists with that schedule and zone, and the startup summary shows its next run in local time with the zone (REC-1, REC-4, SET-8).
- Given `AddRecurring<TenantReport>("report:tenant-42", Schedule.Cron("0 6 * * *"), new TenantReport(42))` and the same for tenant 43, then two definitions exist, each firing its own payload (REC-8).
- Given an invalid cron in `[Recurring]` or an unknown time zone, when the host starts, then startup fails naming the job, the field and the fix (REC-2). Given the same through `IRecurringJobManager.AddOrUpdateAsync`, then `ArgumentException` is thrown at the call.
- Given a recurring name that breaks the name rule, or two code-defined recurring jobs with the same name, then startup fails naming both.
- Given startup on a `Both` node, then reconciliation runs once before the loops start, and info 1401 logs created, updated, unchanged and orphaned counts with the orphaned names (REC-3). The `ReconcileRequest` carries this node's id and heartbeat (application name and code-defined recurring names) and `NodeTimeout`, so the store registers the node and judges which nodes are live in the same step (refinement D-9, REQ-045).
- *(refinement, D-9)* Given two schedulers sharing one store, one on code {A, B} (the old version) and one starting on {A, C} (the new version), then B is not orphaned while the old one's heartbeat is live, and C is not orphaned when the old one restarts. Once the old one stops gracefully, the next start or cleanup run orphans B.
- Given a rolling deploy where both versions define one job with different schedules, then the job follows the version whose node started last, until every node runs one version. This is accepted (refinement D-19) and documented in the getting-started guide (M1-26).
- Given a due definition with `NextRunAt = 03:00`, a tick at 03:00:00.4 and `RunOnce`, then one occurrence job is created with `ScheduledAt` 03:00 and `RecurringName` set, and `NextRunAt` becomes the next day's 03:00.
- Given the node was down from 01:30 to 08:30 with an hourly schedule (`0 * * * *`, so `NextRunAt` was 02:00 and the due occurrences are 02:00 to 08:00, 7 in all), when it comes back, then:
  - `RunOnce` creates one occurrence (for 08:00) and logs 1402 for the 6 not run,
  - `Skip` creates none, because the latest occurrence (08:00) is 30 minutes late, beyond `MisfireThreshold`, and logs 1402 for all 7,
  - `RunAll` with `MisfireMax = 3` creates the newest 3 occurrences (06:00, 07:00, 08:00) as a sequence (the first `Enqueued`, the others `Awaiting` under the default `Skip` overlap, arch §7.7), and logs 1402 for the 4 not run,
  - in every case `NextRunAt` becomes 09:00, and `OnRecurringMissedAsync` is raised once, with the missed instants and the policy (REC-5).
- Given a per-second schedule and a node down for 5 hours (18,000 due occurrences, above the 10,000 enumeration cap), when it comes back with `RunOnce`, then exactly one occurrence is created at the latest second ≤ now, the log says "10,000 or more" missed, and the fire completes in under 100 ms of CPU.
- Given two nodes that both see the same due definition, then 1402 and `OnRecurringMissedAsync` happen only on the node whose fire returned `Fired = true` (arch §7.7 step 5). `OnEnqueuedAsync` is raised for each created `Enqueued` occurrence.
- Given two scheduler instances sharing one store, when both tick a due definition at once, then exactly one occurrence exists, and the losing fire is not logged above debug (REC-7).
- Given `IRecurringJobManager.AddOrUpdateAsync` changes an hourly schedule to daily at 10:00 while `NextRunAt` was 09:00 (overdue), then `NextRunAt` becomes the next 10:00 after now, and no catch-up runs for the old schedule (REC-10).
- Given the manager and a code-defined job that isn't orphaned, when `RemoveAsync` runs, then the store's conflict exception reaches the caller; for a runtime-defined or orphaned job it is removed (refinement D-10, D-18). A runtime override is never cleared by any manager call.
- Given the manager, then `RemoveAsync`, `PauseAsync`, `ResumeAsync` (passing `NextRunAt` recomputed from the estimated store now, so no catch-up for the paused period), `ListAsync` (keyset-paged, with `LastFireOutcome` and `LastJobState`), `GetAsync` and `GetNextOccurrencesAsync(name, 5)` behave as described in arch §3.1 and §7.7 (REC-9).
- Given `IRecurringJobManager` mocked with Moq in a consumer's test, then setups on its methods work directly (TST-2).
- Given a code-defined job with `AllowRuntimeOverride`, when the manager changes its schedule and the host restarts, then the runtime schedule is kept (REC-3, arch §5.3).
- Given `TriggerAsync(name)`, then one occurrence is created now with the stored payload, and `NextRunAt` is unchanged. Given `TriggerAsync(name, payloadOverride)`, then the occurrence uses the override (REC-9).
- Given a manager edit to a code-defined job without `AllowRuntimeOverride`, then the store's conflict exception reaches the caller with the message from M1-06 (REC-3).
- Given a definition stored with a cron that no longer parses (edited by hand), when it is due, then it is paused with `LastFireOutcome = Invalid`, error 1404 names it, and other definitions still fire (arch §4.7).
- Given a fire that throws for one definition, then 1405 is logged with the name, and the remaining due definitions are fired in the same tick.

## Tests

`RecurringRegistrationTests`, `ReconcilerTests`, `MisfireCalculatorTests` (table-driven, including DST days), `RecurringFiringTests` (scheduler with fake time and the in-memory store), `RecurringJobManagerTests`, `RecurringConcurrencyTests` (two schedulers, one store).

## Out of scope

Overlap behaviour end to end, including `CancelPrevious` cancellation delivery (M1-15). Configuration-defined recurring jobs and the dashboard editor (M2, BLT-10).

**Priority:** Must
**Depends on:** M1-04, M1-06, M1-13
**Traces to:** REC-1 to REC-5, REC-7 to REC-10, SET-8, TST-2, RET-6; arch §7.7, A-12, A-13, A-14, A-15; refinement D-9, D-10, D-18, D-19, REQ-045

## Notes

Status: not started
