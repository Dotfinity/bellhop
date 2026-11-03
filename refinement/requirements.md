# Requirements: Bellhop M1 (from the stories)

Sources: the acceptance criteria of `stories/m1-core/001` to `027` (cited as `M1-NN ACn`, where n is the criterion's position in the story's Acceptance criteria list). Only the stories were read as requirements. Where a story points to the architecture for detail ("as in arch §7.7"), that text was not used to fill gaps: a gap stays a gap.

Reading rule: each acceptance criterion is one statement. Criteria about the order of events (claims, leases, cancels, recurring fires, routing, cleanup) are grouped into features below. Everything else is listed under Not requirements with the reason.

## F1 Job lifecycle and leases

A job moves through claim, lease, completion, retry, recovery, cancel, requeue and shutdown release, possibly on several nodes at once.

- **REQ-001** An enqueued job is claimed by at most one claimer. A claimed job is `Processing`, with its attempt counted and a lease token no other claim has.
  Source: M1-05 AC3. Status: unchanged.
  Verification (iteration 1): holds.
- **REQ-002** Renewing a lease with the current token extends it; renewing with any other token reports the job as lost.
  Source: M1-05 AC8. Status: unchanged.
  Verification (iteration 1): holds with an issue (D-6).
- **REQ-003** Completing a job with a stale token changes nothing. A node told its lease is lost cancels the handler and completes nothing.
  Source: M1-05 AC9, M1-12 AC8. Status: unchanged.
  Verification (iteration 1): holds with an issue (D-6).
- **REQ-004** Completing again with the same token and outcome (a retry after a lost response) reports success and changes nothing.
  Source: M1-05 AC10. Status: unchanged.
  Verification (iteration 1): holds.
- **REQ-005** Completion records the outcome: `Succeeded`, `DeadLettered` and `Cancelled` are final; `Failed` waits for its retry time.
  Source: M1-05 AC11. Status: unchanged.
  Verification (iteration 1): broken (D-6).
- **REQ-006** A job whose cancel was requested, and which then fails (for any reason), ends `Cancelled` and is not retried.
  Source: M1-05 AC12, M1-10 AC10. Status: unchanged.
  Verification (iteration 1): broken (D-5).
- **REQ-007** Every due `Scheduled` or `Failed` job is moved to `Enqueued` by a tick, exactly once, even with ticks running on several nodes.
  Source: M1-05 AC13, AC15. Status: unchanged.
  Verification (iteration 1): unchecked (promotion is one step in the model, so no rule could fail).
- **REQ-008** A `Processing` job whose lease has expired is recovered by a tick: back to `Enqueued` if attempts remain, `DeadLettered` if its attempt equals the maximum, `Cancelled` if a cancel was requested.
  Source: M1-05 AC14, M1-13 AC4. Status: unchanged.
  Verification (iteration 1): broken (D-5, D-6).
- **REQ-009** Cancelling a job that hasn't started cancels it at once. Cancelling a `Processing` job records a request that the running node learns at its next lease renewal, and the job ends `Cancelled` when the handler honours it. Cancelling a finished job changes nothing.
  Source: M1-05 AC17, M1-12 AC7. Status: unchanged.
  Verification (iteration 1): broken (D-5, D-6).
- **REQ-010** Requeue moves a `DeadLettered`, `Failed`, `Cancelled` or `Succeeded` job to `Enqueued` with its attempts reset. In any other state it is refused.
  Source: M1-05 AC18, M1-11 AC10. Status: unchanged.
  Verification (iteration 1): holds with an issue (D-4).
- **REQ-011** A job can be deleted unless it is `Processing`.
  Source: M1-05 AC19. Status: unchanged.
  Verification (iteration 1): holds.
- **REQ-012** On graceful shutdown, a node releases the leases of jobs still running: they go back to `Enqueued`, and the attempt is not counted.
  Source: M1-07 AC2, M1-12 AC12. Status: unchanged.
  Verification (iteration 1): broken (D-5, D-6).
- **REQ-013** A failure with attempts left makes the job `Failed` with a retry time; a failure on the last attempt, or a permanent failure, dead-letters it.
  Source: M1-11 AC1, AC5. Status: unchanged.
  Verification (iteration 1): broken (D-6).

## F2 Lease heartbeat and self-fencing

A node keeps its leases alive while handlers run, and stops its handlers when it can no longer renew.

- **REQ-014** While a handler runs, the node renews the lease every third of the lease length, and a healthy running job is never recovered by another node.
  Source: M1-12 AC6. Status: unchanged.
  Verification (iteration 1): holds.
- **REQ-015** When renewals fail for longer than the lease length since the last successful renewal, the node cancels every running handler, "so no handler keeps running long after another node may have recovered its job".
  Source: M1-12 AC9. Status: changed by D-1.
  Verification (iteration 1): broken (D-7).
  Now: A node cancels its handlers no later than the moment another node could recover their jobs. Two nodes never run the same job at once.
  History: 2026-11-03, D-1 (no overlap at all) replaced "long" with "no later than the moment another node could recover their jobs".
- **REQ-016** If releasing leases at shutdown fails, the lease expires and the job is recovered.
  Source: M1-12 AC14. Status: unchanged.
  Verification (iteration 1): holds.

## F3 Recurring firing and overlap

Each due recurring definition creates its occurrences once across all nodes, and its overlap policy decides what happens while an earlier occurrence is still active.

- **REQ-017** A definition that is paused or orphaned is never returned as due, and a fire for a definition paused after it was returned creates nothing.
  Source: M1-06 AC9, AC11. Status: unchanged.
  Verification (iteration 1): broken (D-11).
- **REQ-018** When several nodes fire the same due instant, exactly one succeeds and exactly one occurrence exists.
  Source: M1-06 AC10, M1-14 AC10. Status: unchanged.
  Verification (iteration 1): holds.
- **REQ-019** An occurrence counts as active when it is `Scheduled`, `Enqueued`, `Processing`, `Failed` or `Awaiting`.
  Source: M1-06 (Overlap section). Status: unchanged.
  Verification (iteration 1): unchecked (used as a definition; see D-3).
- **REQ-020** `Skip`: while an occurrence is active, a fire creates nothing and records `Skipped`, and the next run time still advances.
  Source: M1-06 AC13, M1-15 AC1, AC9. Status: unchanged.
  Verification (iteration 1): not settled: broke only through my wording error in REQ-025, re-checked next iteration.
- **REQ-021** `Queue`: while an occurrence is active, a fire creates the new occurrence as `Awaiting`. It is promoted only once nothing else is active, and two occurrences never run at the same time.
  Source: M1-06 AC14, AC21, M1-15 AC2, AC3. Status: changed (transcription corrected).
  Verification (iteration 1): broken (D-3, D-4).
  Now: `Queue`: while an occurrence is active, a fire creates the new occurrence as `Awaiting`. Once no occurrence other than `Awaiting` ones is active, the next tick promotes the oldest `Awaiting` occurrence, and two occurrences never run at the same time.
  History: 2026-11-03, after iteration 1. My first wording dropped "the oldest" from M1-06 AC14 and contradicted AC21 (two waiting runs, nothing active, one is promoted). Corrected to the stories' text; no owner decision involved.
- **REQ-022** An `Awaiting` occurrence is never stranded: however its predecessor ends (completion, recovery, cancel or delete), the next tick promotes it.
  Source: M1-06 AC15, M1-15 AC4. Status: unchanged.
  Verification (iteration 1): broken (D-4); a second route came from my wording error in REQ-021.
- **REQ-023** `Allow`: a fire always creates an `Enqueued` occurrence, even while another runs.
  Source: M1-06 AC16, M1-15 AC6. Status: unchanged.
  Verification (iteration 1): unchecked.
- **REQ-024** `CancelPrevious`: a fire cancels the active occurrence (at once if not running, by request if running) and creates the new one as `Awaiting`, which waits until the previous one is finished. The two never overlap.
  Source: M1-06 AC17, M1-15 AC7, AC8. Status: unchanged.
  Verification (iteration 1): broken (D-3, D-4).
- **REQ-025** A fire that creates several occurrences (catch-up after downtime) creates them as a sequence: all `Enqueued` under `Allow`; otherwise the first per the policy and the rest `Awaiting`, run one at a time in order.
  Source: M1-06 AC18, M1-15 AC5. Status: changed (transcription corrected).
  Verification (iteration 1): not settled: my wording error, re-checked next iteration.
  Now: When no occurrence is active, a fire that creates several occurrences (catch-up after downtime) creates them as a sequence: all `Enqueued` under `Allow`; otherwise the first `Enqueued` and the rest `Awaiting`, run one at a time in order.
  History: 2026-11-03, after iteration 1. My first wording dropped M1-06 AC18's condition "and no active occurrence". Corrected to the stories' text; no owner decision involved.
- **REQ-026** A manual trigger fires whatever the next run time says, applies the overlap policy, and leaves the next run time unchanged. Concurrent manual triggers under `Skip` create exactly one occurrence.
  Source: M1-06 AC19, AC20, M1-14 AC15, M1-15 AC10. Status: unchanged.
  Verification (iteration 1): not settled: my wording error in REQ-025; see also D-11.
- **REQ-027** When several ticks race over the same `Awaiting` occurrences, exactly one is promoted.
  Source: M1-06 AC21. Status: unchanged.
  Verification (iteration 1): unchecked (a tick is one step in the model).

## F4 Recurring definitions and reconciliation

Code-defined recurring jobs are upserted at startup, orphaned when they disappear from code, and runtime edits follow their own rules.

- **REQ-028** Concurrent reconciles of the same definitions create one row each, and none fails.
  Source: M1-06 AC1. Status: unchanged.
  Verification (iteration 1): unchecked (one row per name by construction).
- **REQ-029** A reconcile that changes nothing leaves the next run time alone; a schedule change takes the newly computed next run, with no catch-up for the old schedule.
  Source: M1-06 AC2, M1-14 AC11. Status: unchanged.
  Verification (iteration 1): holds.
- **REQ-030** A reconcile orphans the code-defined definitions of the same application that are missing from its code, never deletes them, and restores them with a fresh next run time when they come back.
  Source: M1-06 AC3. Status: unchanged.
  Verification (iteration 1): holds with an issue (D-9).
- **REQ-031** A runtime edit of a code-defined definition is refused unless it allows runtime override; an allowed override survives later reconciles and restarts.
  Source: M1-06 AC4, AC5, M1-14 AC14, AC16. Status: unchanged.
  Verification (iteration 1): broken (D-10).
- **REQ-032** A paused definition is not due; resuming sets the next run from now, with no catch-up for the paused period.
  Source: M1-06 AC6, M1-14 AC12. Status: unchanged.
  Verification (iteration 1): holds.
- **REQ-033** Removing a definition keeps its existing occurrences.
  Source: M1-06 AC7. Status: unchanged.
  Verification (iteration 1): unchecked.
- **REQ-034** Reconciliation runs once at startup on worker nodes, before their loops start; client-only nodes don't reconcile.
  Source: M1-14 AC5, M1-13 AC11. Status: unchanged.
  Verification (iteration 1): holds with an issue (D-9).

## F5 Job routing

Nodes only run jobs they have handlers for, and jobs nobody can handle are made visible.

- **REQ-035** A claim never takes a job whose name the claiming node can't handle; such a job stays `Enqueued` with its attempt unchanged.
  Source: M1-05 AC6. Status: unchanged.
  Verification (iteration 1): broken (D-12).
- **REQ-036** Cleanup marks an `Enqueued` job `Unroutable` when it is older than the routing grace period and no live node advertises its name; a job a live node advertises, or a younger job, is left alone.
  Source: M1-07 AC7. Status: changed by D-2.
  Verification (iteration 1): holds.
  Now adds: A node is live while its last heartbeat is no older than the node timeout.
  History: 2026-11-03, D-2 (within the node timeout) defined "live node".
- **REQ-037** A tick from a node that can handle an `Unroutable` job's name moves it back to `Enqueued`.
  Source: M1-07 AC8. Status: unchanged.
  Verification (iteration 1): broken (D-12).
- **REQ-038** Cleanup never deletes a job that isn't finished, however old.
  Source: M1-07 AC4. Status: unchanged.
  Verification (iteration 1): holds.

## F6 Cleanup leadership

One node at a time runs cleanup, under a short lease in the store.

- **REQ-039** At most one node holds the cleanup lease; another node can take it only after it expires; the holder can renew it.
  Source: M1-07 AC3. Status: unchanged.
  Verification (iteration 1): holds.
- **REQ-040** Only the node holding the cleanup lease purges.
  Source: M1-13 AC7. Status: unchanged.
  Verification (iteration 1): broken (D-8).
- **REQ-041** Cleanup keeps purging in batches until a batch comes back short.
  Source: M1-13 AC8. Status: unchanged.
  Verification (iteration 1): holds.

## F7 Recurring catch-up after downtime

Which occurrences a due definition creates after missed time.

- **REQ-042** After downtime, `RunOnce` creates one occurrence for the latest missed instant, `Skip` creates none if it is late, and `RunAll` creates the newest few up to its limit; in every case the next run is in the future.
  Source: M1-14 AC6, AC7, AC8. Status: unchanged.
  Verification (iteration 1): unchecked (calendar arithmetic; covered by M1-14's tests).
- **REQ-043** Only the node whose fire succeeded reports the missed occurrences.
  Source: M1-14 AC9. Status: unchanged.
  Verification (iteration 1): holds.

## Not requirements

Statements that can't be checked as an order of events. They are left to each story's own tests.

- M1-01 (all criteria): build, packaging, lint and CI setup. Non-functional.
- M1-02 (all): the shape of public types, id format and member counts. Data contract, not behaviour over time.
- M1-03 (all): registration and name validation at startup, serialization and payload masking. Pure data mapping and startup validation.
- M1-04 (all): cron parsing and next-occurrence arithmetic, including the DST rules. Calendar arithmetic; covered by M1-04's table-driven tests.
- M1-05 AC1, AC2, AC4, AC5, AC7, AC16, AC20 to AC24: insert atomicity, time arithmetic, queue ordering, batch sizes, progress and parameter writes, paging, in-memory clock. Data handling and ordering within one call.
- M1-07 AC1, AC5, AC6, AC9 to AC12: node listing, retention arithmetic, index paging, statistics, namespace isolation. Data handling. (Namespace isolation is a real rule, but every call is filtered by namespace, so the order of events can't break it.)
- M1-08, M1-09 (all): options, startup, logging and the client API. Configuration and API behaviour within one call.
- M1-10 (all except AC10, used in REQ-006): DI scopes, middleware order, context fields, events. Within one execution.
- M1-11 AC2 to AC4, AC6 to AC9, AC11: backoff delays, policy resolution and events. Arithmetic and configuration.
- M1-12 AC1 to AC5, AC10, AC11, AC13, AC15, AC16: slot counts, wake-up latency, timeouts and backoff timings. Performance and timing values.
- M1-13 AC1 to AC3, AC5, AC6, AC9, AC10, AC12: tick cadence, clock skew warning, logging. Timing and observability.
- M1-14 AC1 to AC4, AC13, AC17, AC18: registration, validation, mockability, error isolation. Startup validation and API shape.
- M1-16 (all): traces, metrics and health check. Observability.
- M1-17 (all): the test harness. Developer tooling.
- M1-18 to M1-22: the same store rules as F1 to F6 on PostgreSQL, plus query plans, timings and notification latency. Performance and technology; the rules themselves are F1 to F6.
- M1-23 to M1-25 (all): dashboard security, layout and pages. UI and security practice.
- M1-26, M1-27 (all): sample app, documentation and a recorded acceptance run.
- Every story's Context, Tests and Out of scope sections: background and notes to the builder.
