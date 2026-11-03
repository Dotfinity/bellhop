# M1-09 Job client

## Context

`IJobClient` is the only way to create work (requirements.md §4.3, "no static entry point"). This story implements it on top of the registry (M1-03), the store (M1-05) and hosting (M1-08): enqueue, schedule, cancel, requeue, delete, get, enqueue middleware (EXT-2), tags and parameters at enqueue (SCH-4, EXT-6), payload limits (STO-10), and parent-id propagation from inside a handler (SCH-10). Trace propagation is added in M1-16, which wraps the same code path.

Implements arch §6.4.

Files: `src/Bellhop/Client/` (`JobClient`, `EnqueuePipeline`, internal `AmbientJobExecution`, an `AsyncLocal` holder owned by the Bellhop instance and never static, used by M1-10), plus `UseEnqueueMiddleware`. Also an internal `IWorkerWakeSignal` interface with a no-op default, which M1-12 implements.

**As a** developer
**I want** a type-safe, mockable client to enqueue, schedule and manage jobs
**so that** creating background work is one line and is easy to test.

## Acceptance criteria

- Given `EnqueueAsync(new SendWelcomeEmail(id))`, when it returns, then the store holds an `Enqueued` job with the registered name, the serialized payload, queue/priority/retry/timeout from the merged metadata (arch §6.1), and the returned `JobId` (SCH-1).
- Given `ScheduleAsync(job, delay: TimeSpan.FromDays(3))`, then the job is `Scheduled` with `Delay` passed to the store (resolved on the store clock). Given `ScheduleAsync(job, at: t)` with t in the past, then the job is `Scheduled` with `DueAt = t` and becomes due at the next tick (SCH-2).
- Given `EnqueueOptions { Queue = "bulk", Priority = 5, Tags = ["tenant:42"], Timeout = 2 min, Retry = new(3), Parameters = { ["source"] = "signup" } }`, when the job is read back, then each value is stored. Options win over fluent and attribute metadata (SCH-4).
- Given a queue name or tag that breaks the rules in arch §3.2, when enqueue runs, then `ArgumentException` names the value and the rule. Given a null job, `ArgumentNullException`.
- Given an unregistered job type, when enqueue runs, then `InvalidOperationException` says: `Job type App.Foo is not registered. Add it with AddJob<App.Foo, YourHandler>() or AddJobsFromAssemblyContaining<...>() in AddBellhop.`
- Given two `IEnqueueMiddleware` registrations, when enqueue runs, then they run in registration order, can add tags, set parameters and change queue and priority, and the stored job reflects their changes (EXT-2).
- Given enqueue middleware that throws, when enqueue runs, then the exception reaches the caller and no job is stored.
- Given a payload over the soft limit, then the job is stored and warning 1101 logs the job name and size. Over the hard limit, `JobPayloadTooLargeException` reaches the caller and nothing is stored (STO-10).
- Given the store throws on insert, when enqueue runs, then the store's exception reaches the caller unchanged, and error 1102 is logged with the job name (A-2).
- Given an ambient job execution (simulated through `AmbientJobExecution` in this story; real in M1-10), when a job is enqueued, then its `ParentId` is the running job's id (SCH-10).
- Given `CancelAsync`, `RequeueAsync`, `DeleteAsync` and `GetAsync`, when called for jobs in various states, then they return what the store reports (arch §5.3), and `GetAsync` maps `JobDetails` to `JobInfo` with history (SCH-6).
- Given a successful enqueue, then `IJobEvents.OnEnqueuedAsync` is called for each registered `IJobEvents`. An event handler that throws is logged (1209) and does not fail the enqueue.
- Given a successful enqueue of an `Enqueued` job, then the local wake signal is raised once.
- Given `IJobClient`, when it is mocked with Moq in a consumer's unit test, then setups on `EnqueueAsync<T>` work directly (TST-2). Shown in a test in `Bellhop.Tests`.

## Tests

`JobClientEnqueueTests`, `JobClientScheduleTests`, `EnqueueMiddlewareTests`, `JobClientManagementTests`, `ParentPropagationTests`, `JobClientMockabilityTests`. All run against the in-memory store with a `FakeTimeProvider`.

## Out of scope

Execution (M1-10). Tracing spans and metrics (M1-16). Inline mode (M1-17). Uniqueness, transactions, batch enqueue (M2).

**Priority:** Must
**Depends on:** M1-08
**Traces to:** SCH-1, SCH-2, SCH-4, SCH-6, SCH-10, EXT-2, EXT-6, STO-10, TST-2, RET-6; arch §6.4, A-2

## Notes

Status: not started
