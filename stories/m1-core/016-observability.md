# M1-16 Traces, metrics and health check

## Context

Hangfire's OpenTelemetry support is a contrib beta with no enqueue spans (H19), and TickerQ swallowed exceptions (T10). This story adds the built-in `ActivitySource`, `Meter` and health check (OBS-1, OBS-2, OBS-5), and finishes OBS-3 by flipping the health check on errors that stall processing. Implements arch §8.1 to §8.3. Spans wrap the existing client and processor code paths; metrics hook into the client, processor, worker and scheduler.

Files: `src/Bellhop/Diagnostics/` (`BellhopInstrumentation` holding the `ActivitySource` and `Meter`, both per instance from DI; `BellhopHealthState`; `BellhopHealthCheck`; `AddBellhopHealthCheck` on `IHealthChecksBuilder`), with small additions in `JobClient`, `JobProcessor`, `WorkerLoop` and `SchedulerLoop`.

**As a** operator
**I want** traces from enqueue to execution, standard metrics and a meaningful health check out of the box
**so that** I can see what jobs do in my existing tools and get alerted when processing stalls.

## Acceptance criteria

- Given an `ActivityListener` on source `Bellhop` and an ambient `Activity` in the caller, when a job is enqueued and executed, then a producer span `publish default` is a child of the caller's activity, and a consumer span `process default` has the producer as parent and a link to it. Both carry the attributes in arch §8.1 (OBS-1, A-17).
- Given a job enqueued from inside a handler, then its producer span is a child of the running consumer span (SCH-10).
- Given a running handler, then `ctx.TraceContext` equals the consumer span's context (JOB-6).
- Given a recurring occurrence, then its consumer span starts a new trace.
- Given a handler that throws, then the consumer span's status is error, and the exception is recorded as a span event with its type and message.
- Given two Bellhop hosts in one process, then each has its own `ActivitySource` and `Meter` instances, and a `MeterListener` scoped to one host's meter sees only that host's measurements (TST-1).
- Given a `MeterListener`, when jobs are enqueued, succeed, fail and retry, dead-letter and get recovered, then the counters in arch §8.2 increase by the right amounts with `bellhop.queue` and `bellhop.job.name` tags, `bellhop.job.duration` records the handler time, and `bellhop.job.scheduling_lag` records start minus due time (OBS-2).
- Given `bellhop.queue.depth` is observed twice within 15 s, then the store's statistics were read at most once. If it is never observed, the statistics are never read for it.
- Given `AddHealthChecks().AddBellhopHealthCheck()` on a healthy node, then the result is Healthy, with data for store reachability, schema version, last worker loop iteration, scheduling-lag p50 and dead-letter count in the last hour (OBS-5).
- Given the store has failed continuously for longer than `StoreFailureThreshold`, then the check is Unhealthy, with the last error message in its description (OBS-3).
- Given an idle worker node with no work for 10 minutes, then the check stays Healthy (the loop records liveness on its `PollInterval` timeout, arch §7.1). Given the worker loop hung (it has not woken for 3 × `PollInterval` + 30 s, simulated by blocking it), then the check is Unhealthy. On a `ClientOnly` node this check is skipped.
- Given the scheduling-lag p50 over the last minute exceeds `SchedulingLagThreshold`, or the number of jobs this node dead-lettered in the last hour exceeds `DeadLetterGrowthThreshold`, then the check is Degraded, naming which threshold was exceeded.
- Given a health probe, then it makes no store call (it reads `BellhopHealthState`).

## Tests

`TracingTests` (with an `ActivityListener`), `MetricsTests` (with `MeterListener` and `IMeterFactory` from DI), `HealthCheckTests` (each condition, driving `BellhopHealthState` through a fault-injecting store and fake time).

## Out of scope

Correlation ids (M2, BLT-4). Prometheus exporter setup, which is user configuration; M1-26 documents the two lines. Captured logs (M2).

**Priority:** Must
**Depends on:** M1-11, M1-12, M1-13, M1-14
**Traces to:** OBS-1, OBS-2, OBS-3, OBS-5, JOB-6, SCH-10, TST-1; arch §8, A-17

## Notes

Status: not started
