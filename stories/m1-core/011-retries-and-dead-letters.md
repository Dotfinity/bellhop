# M1-11 Retries and dead letters

## Context

Replaces M1-10's "dead-letter on any exception" seam with the retry model in arch §7.6: default exponential backoff with jitter, typed `IRetryPolicy` from DI (global or per job), `PermanentJobFailureException`, dead-lettering when attempts are exhausted, and `max_attempts` stored per job so that crash recovery (M1-13) can decide without the handler's code.

Files: `src/Bellhop/Engine/Retries/` (`DefaultRetryPolicy`, `RetryPolicyResolver`), the `UseRetryPolicy` and `WithRetryPolicy` registrations, and the `max_attempts` resolution in the client (M1-09 code path, so the client stores the right value).

**As a** developer
**I want** failed jobs retried with sensible backoff and then dead-lettered, with control by job, by exception and per call
**so that** transient failures heal on their own and permanent ones stop quickly and stay visible.

## Acceptance criteria

- Given no retry configuration, when a job fails on attempts 1 to 4, then it is `Failed` with `due_at` about 10 s, 1 min, 5 min and 30 min after each failure (±20%, computed from the estimated store clock, arch §7.4), and attempt 5 failing dead-letters it with reason `AttemptsExhausted` (RET-1, RET-3).
- Given a seeded jitter source, when the delays are computed, then they are deterministic, and over 1,000 samples every delay is within ±20% of its base. Given 16 workers failing jobs concurrently, then the jitter source never throws or returns a constant (it is locked, arch §7.6).
- Given `Retry.Delays = [1 s]` and `MaxAttempts = 4`, then the delays are 1 s, 1 s, 1 s (the last repeats).
- Given `[Retry(2)]` on the job type, fluent `WithRetry(new(3))`, and `EnqueueOptions.Retry = new(6)`, then the stored `max_attempts` is 6. Without the enqueue option it is 3, and without fluent it is 2 (arch §7.6 precedence).
- Given a handler that throws `PermanentJobFailureException`, then the job is dead-lettered on that attempt with the exception recorded, whatever attempts remain (RET-2).
- Given a global `UseRetryPolicy<MyPolicy>()` where `MyPolicy` dead-letters `ArgumentException` and retries others after 1 s, then those decisions apply. `MyPolicy` is resolved from the execution scope, so it can take scoped dependencies (RET-2).
- Given `ConfigureJob<X>().WithRetryPolicy<XPolicy>()` and a global policy, then X uses `XPolicy` and other jobs use the global one.
- Given a policy that throws, then the job is dead-lettered with reason `RetryPolicyFailed`, and error 1204 names the policy type.
- Given each failure, then `IJobEvents.OnFailedAsync` is raised with `WillRetry` and `RetryAt`. On dead-lettering, `OnDeadLetteredAsync` is raised as well (RET-6).
- Given a dead-lettered job, when `IJobClient.RequeueAsync` runs, then it runs again with attempt 1 and the full `max_attempts` budget (RET-5).
- Given a `Failed` job whose `due_at` has passed, when the store tick promotes it (store behaviour from M1-05, driven directly in this test), then it is claimed and executed as the next attempt.

## Tests

`DefaultRetryPolicyTests` (delays, jitter bounds, repetition), `RetryPrecedenceTests`, `RetryPolicyResolutionTests`, `DeadLetterTests`. All use the processor from M1-10 with the in-memory store and `FakeTimeProvider`.

## Out of scope

Bulk requeue (M2). Timeouts as failures (M1-12 raises `JobTimeoutException` into this path). Interrupted attempts from crashes (M1-13, decided in the store).

**Priority:** Must
**Depends on:** M1-10
**Traces to:** RET-1 to RET-6, EXT-4 (retry policy); arch §7.6

## Notes

Status: not started
