# M1-10 Job execution pipeline

## Context

`JobProcessor.ExecuteAsync` runs one attempt of one claimed job: scope, context, middleware, handler, outcome, completion. It is a step function (arch §7), called by the worker loop (M1-12) and directly by the test harness (M1-17). This story covers arch §7.3 steps 1 to 10 for the success, cancel, unroutable and deserialization paths. The failure path calls a retry decision, which this story makes "dead-letter on any exception" through an internal seam. M1-11 replaces that with the real policy.

Files: `src/Bellhop/Engine/` (`JobProcessor`, `JobContextImpl` or the `JobContext` internals, `MiddlewarePipeline`, `JobCancellation` with a reason enum: `Cancelled`, `Timeout`, `Shutdown`, `LeaseLost`), plus `UseMiddleware`.

**As a** developer
**I want** my handler resolved from DI in its own scope, wrapped in my middleware, with a rich context
**so that** handlers are plain classes, cross-cutting concerns are middleware, and failures are recorded.

## Acceptance criteria

- Given a claimed job, when it is executed, then the handler is resolved from a new async DI scope (scoped services are distinct per execution) and the scope is disposed with `DisposeAsync` (EXE-1, BLT-3).
- Given a handler that returns normally, then `CompleteAsync` is called with `Succeeded`, and `IJobEvents.OnStartedAsync` and `OnSucceededAsync` are raised in that order.
- Given a handler that reads `JobContext`, then `Id`, `Name`, `Attempt`, `MaxAttempts`, `EnqueuedAt`, `ScheduledAt`, `Queue`, `Tags`, `ParentId`, `RecurringName` and `Parameters` match the claimed job (JOB-6).
- Given a handler that calls `ctx.ReportProgressAsync(0.3, "step 1")`, then the store holds progress 0.3 and the message. Calls more often than once per second are coalesced, with the last value always written before completion.
- Given a handler that calls `ctx.Parameters.SetAsync("k", 1)`, then the parameter is persisted at once and visible through `GetAsync` (EXT-6).
- Given a handler that logs through `ctx.Logger` or an injected `ILogger<T>`, then the log entries carry a scope with `JobId`, `JobName`, `Attempt` and `Queue` (OBS-4).
- Given a handler that enqueues another job, then the child's `ParentId` is this job's id (SCH-10, end to end with M1-09).
- Given middleware A and B registered in that order, and B registered with `appliesTo: t => t == typeof(X)`, when job X runs, then the order is A → B → handler → B → A. When job Y runs, B is skipped. Middleware resolves scoped services from the execution scope (EXT-1).
- Given middleware that short-circuits (doesn't call `next`), then the handler doesn't run and the job is `Succeeded`.
- Given the job's token is cancelled with reason `Cancelled` and the handler throws any exception (`OperationCanceledException` or another), then the job is completed as `Cancelled`, not retried, and `OnCancelledAsync` is raised. If the handler returns normally despite the request, then it is `Succeeded` (the work was done).
- Given reason `LeaseLost`, then nothing is written. Given `CompleteAsync` returns false for any outcome, then debug-level log 1207 is written and no event is raised.
- Given a payload that fails to deserialize, then the job is completed as `DeadLettered` with reason `DeserializationFailed` and the serializer's message as the error, and error 1203 is logged (arch §4.7).
- Given a handler that throws, then the retry seam is consulted and the job is completed with its decision, with the exception type, message and stack trace in the history (RET-4).
- Given `CompleteAsync` throws twice and then succeeds, then the job is completed once, after the retries in arch §7.3 step 9. Given it throws every time, then error 1208 is logged with the job id and the exception is not rethrown to the caller.
- Given an `IJobEvents` handler that throws, then 1209 is logged with the handler's type, and the job outcome is unchanged.

## Tests

`JobProcessorTests` (with the in-memory store and `FakeTimeProvider`; jobs claimed through the store, then executed), `MiddlewarePipelineTests`, `JobContextTests`, `ProgressCoalescingTests`, `JobEventsInvocationTests`.

## Out of scope

Retry policy, backoff and `PermanentJobFailureException` (M1-11). Claiming, slots, heartbeat, timeouts, shutdown (M1-12). Spans and metrics (M1-16).

**Priority:** Must
**Depends on:** M1-09
**Traces to:** JOB-1, JOB-5, JOB-6, EXE-1, EXT-1, EXT-6, OBS-4, RET-4, RET-6, SCH-10, BLT-3; arch §7.3, §4.7

## Notes

Status: not started
