# M1-12 Worker loop, heartbeat, timeouts and shutdown

## Context

The worker loop turns claims into running processors with bounded concurrency, keeps leases alive, delivers cross-node cancellation, enforces timeouts, and shuts down gracefully. This addresses Hangfire's sync-over-async workers (H7) and stuck-in-Processing jobs (H3). Implements arch §7.1, §7.2, §7.3 (timeout and abandonment) and §7.5. It fills in the worker shell started by M1-08 and implements the internal `IWorkerWakeSignal` from M1-09.

The loop's iteration is a step function (`ClaimOnceAsync`), so M1-17 can drive it without the hosted loop.

Files: `src/Bellhop/Engine/Workers/` (`WorkerLoop`, `SlotManager`, `LeaseHeartbeat`, `WorkerWakeSignal`, `InFlightRegistry`), `JobTimeoutException`.

**As a** operator
**I want** workers that use async slots, keep their leases alive, honour timeouts and cancellation, and hand work back on shutdown
**so that** jobs run promptly, nothing is stuck after a deploy, and a hung handler can't take a node down.

## Acceptance criteria

- Given `WorkerCount = 4` and 20 jobs that each wait on a gate, when the loop runs, then exactly 4 are `Processing` at once, and no claim ever asks for more than the free slots (`MaxTotal`). Releasing one lets the next start (EXE-1, CON-6).
- Given `Queues = [critical, default]`, `QueueConcurrency = { critical: 1 }` and `WorkerCount = 4`, with many jobs in both queues, then at most 1 `critical` job runs at a time, and the other slots are filled from `default` (CON-1).
- Given a claim that returns as many jobs as requested, then the loop claims again immediately without waiting for `PollInterval` (adaptive polling, EXE-8).
- Given an idle loop, when a job is enqueued on the same node, then it starts without waiting for `PollInterval` (local wake-up, EXE-8). Measured with a real clock: under 50 ms on a dev machine; the test asserts under 500 ms to avoid flakiness.
- Given an idle loop and a tick result listing a queue with ready jobs (simulated), then exactly one claim follows. Given neither a signal nor ready queues, then no claim is issued, so idle cost stays at the tick alone (STO-6), but the loop still records liveness in `BellhopHealthState` every `PollInterval` (arch §7.1).
- Given `LeaseDuration = 30 s` and a job running for 2 minutes of fake time, then `RenewLeasesAsync` was called about every 10 s with that job, and the job was never recovered (EXE-3).
- Given a renew result listing the job in `CancelRequested`, then the handler's token is cancelled, and the job completes as `Cancelled` when the handler honours it (SCH-6, cross-node path).
- Given a renew result listing the job in `Lost`, then its token is cancelled with reason `LeaseLost`, warning 1206 is logged, and nothing is completed.
- Given `RenewLeasesAsync` throws for longer than `LeaseDuration` since the last successful renewal, then every in-flight job's token is cancelled with reason `LeaseLost` and 1206 is logged (self-fencing, arch §7.2), so no handler keeps running long after another node may have recovered its job (EXE-5).
- Given a job with `Timeout = 1 s` whose handler honours cancellation, when 1 s passes, then the job fails with `JobTimeoutException` and goes through the retry policy (EXE-7).
- Given a job with `Timeout = 1 s` whose handler ignores cancellation, when 1 s plus `CancellationGracePeriod` passes, then the slot is freed, the job is completed as a timeout failure, warning 1205 is logged, and a later exception from the abandoned task is logged at debug level, not thrown (A-10).
- Given 3 in-flight jobs, two finishing within `ShutdownTimeout` and one ignoring cancellation, when the host stops, then claiming stops at once, lease heartbeats continue, the two complete normally, the third's token is cancelled with reason `Shutdown`, and after `CancellationGracePeriod` `ShutdownNodeAsync` releases its lease. The job is `Enqueued` with reason `Shutdown` and its attempt is not counted (EXE-6, A-9). Log 1210 lists its id.
- Given default options and a generic host with the default 30 s `HostOptions.ShutdownTimeout`, when the host stops with a job that ignores cancellation, then the lease is released before the host's stop token fires. Given a host stop token that fires early (a 3 s host timeout in the test), then Bellhop skips the remaining wait and releases the leases at once (arch §7.5).
- Given `ShutdownNodeAsync` throws during stop, then 1211 is logged and stop completes (the lease will expire and be recovered).
- Given the store's `ClaimAsync` throws 3 times, then 1201 is logged each time with exponential backoff from `PollInterval` up to 30 s, the loop keeps running, and the backoff resets after a success.
- Given an exception thrown anywhere in an iteration, then the loop does not exit until the host stops (T10: nothing swallowed, nothing dies silently).

## Tests

`WorkerLoopConcurrencyTests`, `QueueOrderAndLimitTests`, `WakeUpTests`, `LeaseHeartbeatTests`, `CancellationTests`, `TimeoutTests`, `GracefulShutdownTests`, `WorkerLoopResilienceTests` (a fault-injecting store wrapper). Fake time where possible; the wake-up latency test uses real time with a generous bound.

## Out of scope

The scheduler tick and recovery (M1-13). PostgreSQL push signals (M1-22, which plugs into the wake signal and cancel path built here). Metrics (M1-16).

**Priority:** Must
**Depends on:** M1-07, M1-11
**Traces to:** EXE-1, EXE-3, EXE-5, EXE-6, EXE-7, EXE-8, SCH-6, CON-1, CON-6, STO-6; arch §7.1, §7.2, §7.3, §7.5, A-8, A-9, A-10

## Notes

Status: not started
