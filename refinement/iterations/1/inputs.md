# Iteration 1 inputs

Date: 2026-11-03. Source documents: stories/m1-core/*.md only (see requirements.md for the reading rule).

## Decided answers read by this iteration

- D-1: no overlap at all. REQ-015 now reads: A node cancels its handlers no later than the moment another node could recover their jobs. Two nodes never run the same job at once.
- D-2: within the node timeout. REQ-036 adds: A node is live while its last heartbeat is no older than the node timeout.

## Requirement text

## F1 Job lifecycle and leases

A job moves through claim, lease, completion, retry, recovery, cancel, requeue and shutdown release, possibly on several nodes at once.

- **REQ-001** An enqueued job is claimed by at most one claimer. A claimed job is `Processing`, with its attempt counted and a lease token no other claim has.
  Source: M1-05 AC3. Status: unchanged.
- **REQ-002** Renewing a lease with the current token extends it; renewing with any other token reports the job as lost.
  Source: M1-05 AC8. Status: unchanged.
- **REQ-003** Completing a job with a stale token changes nothing. A node told its lease is lost cancels the handler and completes nothing.
  Source: M1-05 AC9, M1-12 AC8. Status: unchanged.
- **REQ-004** Completing again with the same token and outcome (a retry after a lost response) reports success and changes nothing.
  Source: M1-05 AC10. Status: unchanged.
- **REQ-005** Completion records the outcome: `Succeeded`, `DeadLettered` and `Cancelled` are final; `Failed` waits for its retry time.
  Source: M1-05 AC11. Status: unchanged.
- **REQ-006** A job whose cancel was requested, and which then fails (for any reason), ends `Cancelled` and is not retried.
  Source: M1-05 AC12, M1-10 AC10. Status: unchanged.
- **REQ-007** Every due `Scheduled` or `Failed` job is moved to `Enqueued` by a tick, exactly once, even with ticks running on several nodes.
  Source: M1-05 AC13, AC15. Status: unchanged.
- **REQ-008** A `Processing` job whose lease has expired is recovered by a tick: back to `Enqueued` if attempts remain, `DeadLettered` if its attempt equals the maximum, `Cancelled` if a cancel was requested.
  Source: M1-05 AC14, M1-13 AC4. Status: unchanged.
- **REQ-009** Cancelling a job that hasn't started cancels it at once. Cancelling a `Processing` job records a request that the running node learns at its next lease renewal, and the job ends `Cancelled` when the handler honours it. Cancelling a finished job changes nothing.
  Source: M1-05 AC17, M1-12 AC7. Status: unchanged.
- **REQ-010** Requeue moves a `DeadLettered`, `Failed`, `Cancelled` or `Succeeded` job to `Enqueued` with its attempts reset. In any other state it is refused.
  Source: M1-05 AC18, M1-11 AC10. Status: unchanged.
- **REQ-011** A job can be deleted unless it is `Processing`.
  Source: M1-05 AC19. Status: unchanged.
- **REQ-012** On graceful shutdown, a node releases the leases of jobs still running: they go back to `Enqueued`, and the attempt is not counted.
  Source: M1-07 AC2, M1-12 AC12. Status: unchanged.
- **REQ-013** A failure with attempts left makes the job `Failed` with a retry time; a failure on the last attempt, or a permanent failure, dead-letters it.
  Source: M1-11 AC1, AC5. Status: unchanged.

## F2 Lease heartbeat and self-fencing

A node keeps its leases alive while handlers run, and stops its handlers when it can no longer renew.

- **REQ-014** While a handler runs, the node renews the lease every third of the lease length, and a healthy running job is never recovered by another node.
  Source: M1-12 AC6. Status: unchanged.
- **REQ-015** When renewals fail for longer than the lease length since the last successful renewal, the node cancels every running handler, "so no handler keeps running long after another node may have recovered its job".
  Source: M1-12 AC9. Status: changed by D-1.
  Now: A node cancels its handlers no later than the moment another node could recover their jobs. Two nodes never run the same job at once.
  History: 2026-11-03, D-1 (no overlap at all) replaced "long" with "no later than the moment another node could recover their jobs".
- **REQ-016** If releasing leases at shutdown fails, the lease expires and the job is recovered.
  Source: M1-12 AC14. Status: unchanged.

## F3 Recurring firing and overlap

Each due recurring definition creates its occurrences once across all nodes, and its overlap policy decides what happens while an earlier occurrence is still active.

- **REQ-017** A definition that is paused or orphaned is never returned as due, and a fire for a definition paused after it was returned creates nothing.
  Source: M1-06 AC9, AC11. Status: unchanged.
- **REQ-018** When several nodes fire the same due instant, exactly one succeeds and exactly one occurrence exists.
  Source: M1-06 AC10, M1-14 AC10. Status: unchanged.
- **REQ-019** An occurrence counts as active when it is `Scheduled`, `Enqueued`, `Processing`, `Failed` or `Awaiting`.
  Source: M1-06 (Overlap section). Status: unchanged.
- **REQ-020** `Skip`: while an occurrence is active, a fire creates nothing and records `Skipped`, and the next run time still advances.
  Source: M1-06 AC13, M1-15 AC1, AC9. Status: unchanged.
- **REQ-021** `Queue`: while an occurrence is active, a fire creates the new occurrence as `Awaiting`. It is promoted only once nothing else is active, and two occurrences never run at the same time.
  Source: M1-06 AC14, M1-15 AC2, AC3. Status: unchanged.
- **REQ-022** An `Awaiting` occurrence is never stranded: however its predecessor ends (completion, recovery, cancel or delete), the next tick promotes it.
  Source: M1-06 AC15, M1-15 AC4. Status: unchanged.
- **REQ-023** `Allow`: a fire always creates an `Enqueued` occurrence, even while another runs.
  Source: M1-06 AC16, M1-15 AC6. Status: unchanged.
- **REQ-024** `CancelPrevious`: a fire cancels the active occurrence (at once if not running, by request if running) and creates the new one as `Awaiting`, which waits until the previous one is finished. The two never overlap.
  Source: M1-06 AC17, M1-15 AC7, AC8. Status: unchanged.
- **REQ-025** A fire that creates several occurrences (catch-up after downtime) creates them as a sequence: all `Enqueued` under `Allow`; otherwise the first per the policy and the rest `Awaiting`, run one at a time in order.
  Source: M1-06 AC18, M1-15 AC5. Status: unchanged.
- **REQ-026** A manual trigger fires whatever the next run time says, applies the overlap policy, and leaves the next run time unchanged. Concurrent manual triggers under `Skip` create exactly one occurrence.
  Source: M1-06 AC19, AC20, M1-14 AC15, M1-15 AC10. Status: unchanged.
- **REQ-027** When several ticks race over the same `Awaiting` occurrences, exactly one is promoted.
  Source: M1-06 AC21. Status: unchanged.

## F4 Recurring definitions and reconciliation

Code-defined recurring jobs are upserted at startup, orphaned when they disappear from code, and runtime edits follow their own rules.

- **REQ-028** Concurrent reconciles of the same definitions create one row each, and none fails.
  Source: M1-06 AC1. Status: unchanged.
- **REQ-029** A reconcile that changes nothing leaves the next run time alone; a schedule change takes the newly computed next run, with no catch-up for the old schedule.
  Source: M1-06 AC2, M1-14 AC11. Status: unchanged.
- **REQ-030** A reconcile orphans the code-defined definitions of the same application that are missing from its code, never deletes them, and restores them with a fresh next run time when they come back.
  Source: M1-06 AC3. Status: unchanged.
- **REQ-031** A runtime edit of a code-defined definition is refused unless it allows runtime override; an allowed override survives later reconciles and restarts.
  Source: M1-06 AC4, AC5, M1-14 AC14, AC16. Status: unchanged.
- **REQ-032** A paused definition is not due; resuming sets the next run from now, with no catch-up for the paused period.
  Source: M1-06 AC6, M1-14 AC12. Status: unchanged.
- **REQ-033** Removing a definition keeps its existing occurrences.
  Source: M1-06 AC7. Status: unchanged.
- **REQ-034** Reconciliation runs once at startup on worker nodes, before their loops start; client-only nodes don't reconcile.
  Source: M1-14 AC5, M1-13 AC11. Status: unchanged.

## F5 Job routing

Nodes only run jobs they have handlers for, and jobs nobody can handle are made visible.

- **REQ-035** A claim never takes a job whose name the claiming node can't handle; such a job stays `Enqueued` with its attempt unchanged.
  Source: M1-05 AC6. Status: unchanged.
- **REQ-036** Cleanup marks an `Enqueued` job `Unroutable` when it is older than the routing grace period and no live node advertises its name; a job a live node advertises, or a younger job, is left alone.
  Source: M1-07 AC7. Status: changed by D-2.
  Now adds: A node is live while its last heartbeat is no older than the node timeout.
  History: 2026-11-03, D-2 (within the node timeout) defined "live node".
- **REQ-037** A tick from a node that can handle an `Unroutable` job's name moves it back to `Enqueued`.
  Source: M1-07 AC8. Status: unchanged.
- **REQ-038** Cleanup never deletes a job that isn't finished, however old.
  Source: M1-07 AC4. Status: unchanged.

## F6 Cleanup leadership

One node at a time runs cleanup, under a short lease in the store.

- **REQ-039** At most one node holds the cleanup lease; another node can take it only after it expires; the holder can renew it.
  Source: M1-07 AC3. Status: unchanged.
- **REQ-040** Only the node holding the cleanup lease purges.
  Source: M1-13 AC7. Status: unchanged.
- **REQ-041** Cleanup keeps purging in batches until a batch comes back short.
  Source: M1-13 AC8. Status: unchanged.

## F7 Recurring catch-up after downtime

Which occurrences a due definition creates after missed time.

- **REQ-042** After downtime, `RunOnce` creates one occurrence for the latest missed instant, `Skip` creates none if it is late, and `RunAll` creates the newest few up to its limit; in every case the next run is in the future.
  Source: M1-14 AC6, AC7, AC8. Status: unchanged.
- **REQ-043** Only the node whose fire succeeded reports the missed occurrences.
  Source: M1-14 AC9. Status: unchanged.

