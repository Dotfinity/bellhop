# M1-17 Bellhop.Testing harness and inline mode

## Context

Hangfire's static `JobStorage.Current` makes tests flaky (H11), and TickerQ had no deterministic test clock until 10.5 (T16). This story ships `Bellhop.Testing` (TST-3) and the core `Inline` execution mode (TST-4), both driving the engine's step functions directly (arch §7, §9). It is also the first place where the full path (client → store → claim → processor → retry → tick → recurring) runs as one deterministic unit, so it doubles as the engine's integration test bed.

Files: `src/Bellhop.Testing/` (`BellhopTestHarness`, `HarnessJob`, `HarnessJob<T>`), `ExecutionMode.Inline` handling in `src/Bellhop/Client/JobClient.cs`, and tests in `tests/Bellhop.Testing.Tests/`.

**As a** developer testing my application
**I want** to enqueue, run and time-travel jobs deterministically without a database or background threads
**so that** my tests are fast, reliable and read like the behaviour I care about.

## Acceptance criteria

- Given `BellhopTestHarness.Create(bellhop: b => b.AddJob<SendWelcomeEmail, Handler>())`, when a test calls `harness.Client.EnqueueAsync(new SendWelcomeEmail(id))`, then `harness.Enqueued<SendWelcomeEmail>()` contains one item whose `Payload.UserId == id` and whose state is `Enqueued`. `harness.Enqueued<SendWelcomeEmail>().Should().ContainSingle(j => j.Payload.UserId == id)` works with AwesomeAssertions, and the package doesn't reference AwesomeAssertions (TST-3, A-18).
- Given a pending job, when `RunPendingAsync()` runs, then the handler has run, the job is `Succeeded`, and the method returns 1. Jobs enqueued by that handler also run in the same call, and the count includes them.
- Given a job that enqueues itself forever, when `RunPendingAsync(maxJobs: 100)` runs, then it stops after 100 and throws `InvalidOperationException("RunPendingAsync stopped after 100 jobs; a job may be enqueueing itself in a loop.")`.
- Given a job scheduled for 3 days ahead, when `AdvanceTimeAsync(TimeSpan.FromDays(3))` runs, then it ran exactly once, at fake time ≥ its due time.
- Given a recurring job every hour, when `AdvanceTimeAsync(TimeSpan.FromHours(5))` runs, then exactly 5 occurrences ran, each at its scheduled instant (the harness steps through every due instant, arch §9).
- Given a job that fails twice and then succeeds, when time is advanced past both retry delays, then it is `Succeeded` with attempt 3. With the seeded jitter, the result is identical on every run.
- Given a test that doesn't call the harness, then nothing runs on a background thread (no hosted loops).
- Given the harness with a handler that depends on a service registered through `services`, then the service is injected (DI works as in production).
- Given two harnesses in one test, then they share nothing (TST-1).
- Given `ExecutionMode = Inline` in a normal host, when `EnqueueAsync` is called, then the handler runs before `EnqueueAsync` returns, on the caller's async flow; the job is `Succeeded` in the store, and a handler exception propagates to the caller with the job left `DeadLettered` (retries are disabled in inline mode, TST-4, A-19).
- Given `ExecutionMode = Inline`, when `ScheduleAsync` is called, then the job is stored as `Scheduled` and doesn't run, and no background loops run in that host (A-19).
- Given a handler under test with `JobContext.CreateForTest(...)` and no harness, then it can be called directly (TST-5, shown in a sample test).

## Tests

`BellhopTestHarnessTests`, `AdvanceTimeTests`, `InlineModeTests`, plus `EngineEndToEndTests`, which exercise the whole engine through the harness: enqueue → succeed; fail → retry → dead-letter → requeue → succeed; schedule → promote → run; recurring with misfire after a long `AdvanceTimeAsync`; cancel a scheduled job; and crash recovery with two harness "nodes" on one store, where the second runs the interrupted job.

## Out of scope

Testcontainers sample (TST-6, M2). Assertion helpers that depend on a specific assertion library (A-18).

**Priority:** Must
**Depends on:** M1-11, M1-12, M1-14
**Traces to:** TST-1, TST-3, TST-4, TST-5, P7; arch §9, A-18, A-19

## Notes

Status: not started
