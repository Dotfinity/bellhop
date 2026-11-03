# M1-15 Recurring overlap policies end to end

## Context

Overlap was Hangfire's most-cited recurring grievance (H2: `DisableConcurrentExecution` times out and retries) and a TickerQ duplicate-execution source (T2: `SkipIfAlreadyRunning` only works in-process). The store enforces the policy atomically (M1-06). This story proves it end to end with real workers on two nodes, and wires the engine-side reactions: logging and outcome for `Skip`, delivery of the cancel request for `CancelPrevious`, and promotion for `Queue`. Implements the overlap table in arch §7.7 and A-16, and records M-5.

Files: small additions in `src/Bellhop/Engine/Recurring/RecurringFirer.cs` (deliver `FireResult.CancelRequested` to local in-flight jobs at once), plus end-to-end tests.

**As a** developer
**I want** to choose what happens when a recurring job is still running at its next occurrence, enforced across all nodes
**so that** a slow run never stacks up, fails, or retries by surprise.

## Acceptance criteria

Each scenario runs two nodes (two worker loops and two schedulers) sharing one in-memory store with fake time, and a handler that blocks on a gate the test controls. The schedule is every minute.

- **Skip (default).** Given occurrence 1 is still running at the next minute, then no second job is created, the definition's `last_outcome` is `Skipped`, info 1403 is logged once, and no failure or retry appears anywhere (REC-6, M-5). After occurrence 1 finishes, the following minute creates a new occurrence normally.
- **Queue.** Given occurrence 1 is running, when the next minute fires, then occurrence 2 is `Awaiting`. When occurrence 1 finishes, occurrence 2 becomes `Enqueued` and runs, and the two never run at the same time on any node.
- **Allow.** Given occurrence 1 is running, then occurrence 2 starts on the other node while 1 is still running.
- **CancelPrevious.** Given occurrence 1 is running on node A and node B fires the next occurrence, then occurrence 1's token is cancelled (through the heartbeat cancel path on A within one heartbeat interval), and occurrence 1 ends as `Cancelled`. Only then does occurrence 2 move from `Awaiting` to `Enqueued` and run. The two never overlap (A-16).
- **CancelPrevious on the same node.** Given the fire happens on the node running occurrence 1, then cancellation is delivered at once from `FireResult.CancelRequested`, without waiting for a heartbeat.
- **Retrying occurrence.** Given occurrence 1 failed and is `Failed`, awaiting retry, when the next minute fires with `Skip`, then it is skipped (a retrying occurrence is active, arch §7.7).
- **Trigger now.** Given `Skip` and a running occurrence, when `TriggerAsync` is called, then the result's outcome is `Skipped` and no job is created.

## Tests

`RecurringOverlapEndToEndTests`, one test per scenario, deterministic with gates and fake time.

## Out of scope

Dashboard display of occurrences (M1-25). The last-50 occurrence history (M2, BLT-10).

**Priority:** Must
**Depends on:** M1-12, M1-14
**Traces to:** REC-6, SCH-6, CON-7; arch §7.7, A-16, M-5

## Notes

Status: not started
