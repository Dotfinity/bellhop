# Requirements: Bellhop M1 (from the stories)

Sources: the acceptance criteria of `stories/m1-core/001` to `027` (cited as `M1-NN ACn`, where n is the criterion's position in the story's Acceptance criteria list). Only the stories were read as requirements. Where a story points to the architecture for detail ("as in arch §7.7"), that text was not used to fill gaps: a gap stays a gap.

Reading rule: each acceptance criterion is one statement. Criteria about the order of events (claims, leases, cancels, recurring fires, routing, cleanup) are grouped into features below. Everything else is listed under Not requirements with the reason.

## F1 Job lifecycle and leases

A job moves through claim, lease, completion, retry, recovery, cancel, requeue and shutdown release, possibly on several nodes at once.

- **REQ-001** An enqueued job is claimed by at most one claimer. A claimed job is `Processing`, with its attempt counted and a lease token no other claim has.
  Source: M1-05 AC3. Status: unchanged.
  Verification (iteration 1): holds.
  Verification (iteration 2): holds.
- **REQ-002** Renewing a lease with the current token extends it; renewing with any other token reports the job as lost.
  Source: M1-05 AC8. Status: unchanged.
  Verification (iteration 1): holds with an issue (D-6).
  Verification (iteration 2): holds.
- **REQ-003** Completing a job with a stale token changes nothing. A node told its lease is lost cancels the handler and completes nothing.
  Source: M1-05 AC9, M1-12 AC8. Status: changed by D-6.
  Verification (iteration 1): holds with an issue (D-6).
  Verification (iteration 2): holds.
  Now: Completing, renewing or releasing a job with a stale token changes nothing, and recovering a job makes its old token stale. Every write a node makes about a job it runs (a result, a renewal, a release, progress or a parameter) is conditional, in the same store operation, on the job still being `Processing` under that node's token. If the condition fails, nothing is written and the node stops the handler. A node told its lease is lost cancels the handler and completes nothing.
  History: 2026-11-04, D-6 clarified: the check is a condition of the write itself, not a separate read before it, which would race with recovery.
  History: 2026-11-03, D-6: recovery now retires the old claim, and a node checks it still holds a job before writing.
- **REQ-004** Completing again with the same token and outcome (a retry after a lost response) reports success and changes nothing.
  Source: M1-05 AC10. Status: unchanged.
  Verification (iteration 1): holds.
  Verification (iteration 2): holds.
- **REQ-005** Completion records the outcome: `Succeeded`, `DeadLettered` and `Cancelled` are final; `Failed` waits for its retry time.
  Source: M1-05 AC11. Status: unchanged.
  Verification (iteration 1): broken (D-6).
  Verification (iteration 2): holds.
- **REQ-006** A job whose cancel was requested, and which then fails (for any reason), ends `Cancelled` and is not retried.
  Source: M1-05 AC12, M1-10 AC10. Status: unchanged.
  Verification (iteration 1): broken (D-5).
  Verification (iteration 2): holds.
- **REQ-007** Every due `Scheduled` or `Failed` job is moved to `Enqueued` by a tick, exactly once, even with ticks running on several nodes.
  Source: M1-05 AC13, AC15. Status: unchanged.
  Verification (iteration 1): unchecked (promotion is one step in the model, so no rule could fail).
  Verification (iteration 2): unchecked (promotion is one step in the model).
- **REQ-008** A `Processing` job whose lease has expired is recovered by a tick: back to `Enqueued` if attempts remain, `DeadLettered` if its attempt equals the maximum, `Cancelled` if a cancel was requested.
  Source: M1-05 AC14, M1-13 AC4. Status: unchanged.
  Verification (iteration 1): broken (D-5, D-6).
  Verification (iteration 2): holds.
- **REQ-009** Cancelling a job that hasn't started cancels it at once. Cancelling a `Processing` job records a request that the running node learns at its next lease renewal, and the job ends `Cancelled` when the handler honours it. Cancelling a finished job changes nothing.
  Source: M1-05 AC17, M1-12 AC7. Status: unchanged.
  Verification (iteration 1): broken (D-5, D-6).
  Verification (iteration 2): holds.
- **REQ-010** Requeue moves a `DeadLettered`, `Failed`, `Cancelled` or `Succeeded` job to `Enqueued` with its attempts reset. In any other state it is refused.
  Source: M1-05 AC18, M1-11 AC10. Status: changed by D-4.
  Verification (iteration 1): holds with an issue (D-4).
  Verification (iteration 2): holds.
  Now: Requeue moves a `DeadLettered`, `Failed`, `Cancelled` or `Succeeded` job to `Enqueued` with its attempts reset. In any other state it is refused. Requeuing a run of a recurring job ignores its overlap policy; when another run of the same recurring job is active, the requeue goes ahead, and Bellhop logs a warning event naming both runs and saying they may run side by side. In M1 the log event is the warning; showing it to the operator in the UI comes with the dashboard's requeue action in M2. `RequeueAsync` keeps returning `bool`.
  History: 2026-11-04, D-4 clarified: the warning is a log event in M1, and appears in the UI in M2.
  History: 2026-11-03, D-4: requeue is a manual action that overrides the overlap policy, with a warning.
- **REQ-011** A job can be deleted unless it is `Processing`.
  Source: M1-05 AC19. Status: unchanged.
  Verification (iteration 1): holds.
  Verification (iteration 2): holds.
- **REQ-012** On graceful shutdown, a node releases the leases of jobs still running: they go back to `Enqueued`, and the attempt is not counted.
  Source: M1-07 AC2, M1-12 AC12. Status: changed by D-5.
  Verification (iteration 1): broken (D-5, D-6).
  Verification (iteration 2): holds.
  Now: On graceful shutdown, a node releases the leases of jobs still running: they go back to `Enqueued`, and the attempt is not counted. A job whose cancel was requested is not released back to the queue; it ends `Cancelled`.
  History: 2026-11-03, D-5: a cancel request wins over a shutdown release.
- **REQ-013** A failure with attempts left makes the job `Failed` with a retry time; a failure on the last attempt, or a permanent failure, dead-letters it.
  Source: M1-11 AC1, AC5. Status: unchanged.
  Verification (iteration 1): broken (D-6).
  Verification (iteration 2): holds.

## F2 Lease heartbeat and self-fencing

A node keeps its leases alive while handlers run, and stops its handlers when it can no longer renew.

- **REQ-014** While a handler runs, the node renews the lease every third of the lease length, and a healthy running job is never recovered by another node.
  Source: M1-12 AC6. Status: unchanged.
  Verification (iteration 1): holds.
  Verification (iteration 2): holds.
- **REQ-015** When renewals fail for longer than the lease length since the last successful renewal, the node cancels every running handler, "so no handler keeps running long after another node may have recovered its job".
  Source: M1-12 AC9. Status: changed by D-7.
  Verification (iteration 1): broken (D-7).
  Verification (iteration 2): holds.
  Now: A node arms a fencing deadline at the time it sent its last successful renewal plus two thirds of the lease, and re-arms it on every successful renewal. When the deadline passes, the node cancels its handlers at once. Two nodes never run the same job at once, provided clock skew plus any pause of the node stays under a third of the lease and the handler stops when cancelled. Outside those limits delivery is at-least-once, and handlers with external side effects must be idempotent.
  History: 2026-11-04, D-1 revised: the no-overlap guarantee states its limits.
  History: 2026-11-04, D-7 revised: a deadline timer instead of a check once per renewal interval, which gave up as late as the lease expiry (zero margin). Re-check in iteration 3.
  History: 2026-11-03, D-7: my pick, delegated by the owner: two thirds of the lease, counted from the send time. (This line first said it "leaves one renewal interval before another node may recover the job". That holds only for a deadline checked continuously, not once per renewal interval; corrected 2026-11-04.)
  History: 2026-11-03, D-1 (no overlap at all) replaced "long" with "no later than the moment another node could recover their jobs".
- **REQ-016** If releasing leases at shutdown fails, the lease expires and the job is recovered.
  Source: M1-12 AC14. Status: unchanged.
  Verification (iteration 1): holds.
  Verification (iteration 2): holds.

## F3 Recurring firing and overlap

Each due recurring definition creates its occurrences once across all nodes, and its overlap policy decides what happens while an earlier occurrence is still active.

- **REQ-017** A definition that is paused or orphaned is never returned as due, and a fire for a definition paused after it was returned creates nothing.
  Source: M1-06 AC9, AC11. Status: unchanged.
  Verification (iteration 1): broken (D-11).
  Verification (iteration 2): holds.
- **REQ-018** When several nodes fire the same due instant, exactly one succeeds and exactly one occurrence exists.
  Source: M1-06 AC10, M1-14 AC10. Status: unchanged.
  Verification (iteration 1): holds.
  Verification (iteration 2): holds.
- **REQ-019** An occurrence counts as active when it is `Scheduled`, `Enqueued`, `Processing`, `Failed` or `Awaiting`.
  Source: M1-06 (Overlap section). Status: changed by D-3.
  Verification (iteration 1): unchecked (used as a definition; see D-3).
  Verification (iteration 2): holds.
  Now: An occurrence counts as active when it is `Scheduled`, `Enqueued`, `Processing`, `Failed`, `Awaiting` or `Unroutable`.
  History: 2026-11-03, D-3: Unroutable added to the active states.
- **REQ-020** `Skip`: while an occurrence is active, a fire creates nothing and records `Skipped`, and the next run time still advances.
  Source: M1-06 AC13, M1-15 AC1, AC9. Status: unchanged.
  Verification (iteration 1): not settled: broke only through my wording error in REQ-025, re-checked next iteration.
  Verification (iteration 2): holds.
- **REQ-021** `Queue`: while an occurrence is active, a fire creates the new occurrence as `Awaiting`. It is promoted only once nothing else is active, and two occurrences never run at the same time.
  Source: M1-06 AC14, AC21, M1-15 AC2, AC3. Status: changed (transcription corrected).
  Verification (iteration 1): broken (D-3, D-4).
  Verification (iteration 2): holds.
  Now: `Queue`: while an occurrence is active, a fire creates the new occurrence as `Awaiting`. Once no occurrence other than `Awaiting` ones is active, the next tick promotes the oldest `Awaiting` occurrence, and two occurrences never run at the same time.
  History: 2026-11-03, after iteration 1. My first wording dropped "the oldest" from M1-06 AC14 and contradicted AC21 (two waiting runs, nothing active, one is promoted). Corrected to the stories' text; no owner decision involved.
- **REQ-022** An `Awaiting` occurrence is never stranded: however its predecessor ends (completion, recovery, cancel or delete), the next tick promotes it.
  Source: M1-06 AC15, M1-15 AC4. Status: unchanged.
  Verification (iteration 1): broken (D-4); a second route came from my wording error in REQ-021.
  Verification (iteration 2): broken only by endless loops you accepted in D-4 and D-12 (see iteration 2 results); not raised.
- **REQ-023** `Allow`: a fire always creates an `Enqueued` occurrence, even while another runs.
  Source: M1-06 AC16, M1-15 AC6. Status: unchanged.
  Verification (iteration 1): unchecked.
  Verification (iteration 2): unchecked.
- **REQ-024** `CancelPrevious`: a fire cancels the active occurrence (at once if not running, by request if running) and creates the new one as `Awaiting`, which waits until the previous one is finished. The two never overlap.
  Source: M1-06 AC17, M1-15 AC7, AC8. Status: unchanged.
  Verification (iteration 1): broken (D-3, D-4).
  Verification (iteration 2): holds.
- **REQ-025** A fire that creates several occurrences (catch-up after downtime) creates them as a sequence: all `Enqueued` under `Allow`; otherwise the first per the policy and the rest `Awaiting`, run one at a time in order.
  Source: M1-06 AC18, M1-15 AC5. Status: changed (transcription corrected).
  Verification (iteration 1): not settled: my wording error, re-checked next iteration.
  Verification (iteration 2): holds.
  Now: When no occurrence is active, a fire that creates several occurrences (catch-up after downtime) creates them as a sequence: all `Enqueued` under `Allow`; otherwise the first `Enqueued` and the rest `Awaiting`, run one at a time in order.
  History: 2026-11-03, after iteration 1. My first wording dropped M1-06 AC18's condition "and no active occurrence". Corrected to the stories' text; no owner decision involved.
- **REQ-026** A manual trigger fires whatever the next run time says, applies the overlap policy, and leaves the next run time unchanged. Concurrent manual triggers under `Skip` create exactly one occurrence.
  Source: M1-06 AC19, AC20, M1-14 AC15, M1-15 AC10. Status: changed by D-11.
  Verification (iteration 1): not settled: my wording error in REQ-025; see also D-11.
  Verification (iteration 2): holds.
  Now: A manual trigger fires whatever the next run time says, applies the overlap policy, and leaves the next run time unchanged. It works on a paused job too; pausing stops only the schedule. Concurrent manual triggers under `Skip` create exactly one occurrence.
  History: 2026-11-03, D-11: manual triggers work on paused jobs.
- **REQ-027** When several ticks race over the same `Awaiting` occurrences, exactly one is promoted.
  Source: M1-06 AC21. Status: unchanged.
  Verification (iteration 1): unchecked (a tick is one step in the model).
  Verification (iteration 2): unchecked (a tick is one step in the model).

## F4 Recurring definitions and reconciliation

Code-defined recurring jobs are upserted at startup, orphaned when they disappear from code, and runtime edits follow their own rules.

- **REQ-028** Concurrent reconciles of the same definitions create one row each, and none fails.
  Source: M1-06 AC1. Status: unchanged.
  Verification (iteration 1): unchecked (one row per name by construction).
  Verification (iteration 2): unchecked (one row per name by construction).
- **REQ-029** A reconcile that changes nothing leaves the next run time alone; a schedule change takes the newly computed next run, with no catch-up for the old schedule.
  Source: M1-06 AC2, M1-14 AC11. Status: changed by D-19.
  Verification (iteration 1): holds.
  Verification (iteration 2): holds with an issue (D-19).
  Now: A reconcile that changes nothing leaves the next run time alone; a schedule change takes the newly computed next run, with no catch-up for the old schedule. A schedule change whose newly computed next run is the same instant as the stored next run leaves the next run unchanged.
  History: 2026-11-04, D-19: an unchanged next run instant is kept, so flipping a schedule and back between runs has no effect.
- **REQ-030** A reconcile orphans the code-defined definitions of the same application that are missing from its code, never deletes them, and restores them with a fresh next run time when they come back.
  Source: M1-06 AC3. Status: changed by D-9.
  Verification (iteration 1): holds with an issue (D-9).
  Verification (iteration 2): holds.
  Now: A reconcile orphans the code-defined definitions of its application that are missing from its code, but only when no live node of that application still defines them; it never deletes them, and restores them with a fresh next run time when they come back. Cleanup applies the same orphaning rule on every run, so a definition that no live node of its application defines is orphaned within the node timeout plus one cleanup interval, even when no node starts. Only a reconcile restores.
  History: 2026-11-04, D-20: cleanup also orphans, as a backstop for nodes that crash during a deploy.
  History: 2026-11-03, D-9: orphaning waits until no live node of the application still defines the job.
- **REQ-031** A runtime edit of a code-defined definition is refused unless it allows runtime override; an allowed override survives later reconciles and restarts.
  Source: M1-06 AC4, AC5, M1-14 AC14, AC16. Status: changed by D-10, D-18.
  Verification (iteration 1): broken (D-10).
  Verification (iteration 2): holds.
  Now: A runtime edit of a code-defined definition is refused unless it allows runtime override; an allowed override survives later reconciles and restarts. At runtime, a code-defined job can otherwise only be paused or resumed: removing it, or creating a job with a name its code defines, is refused. An override is permanent: no runtime action clears it, and later changes to the job's schedule in code don't apply to it. An orphaned definition can be removed.
  History: 2026-11-04, D-18: overrides stay and can't be cleared; orphaned definitions can be removed at runtime.
  History: 2026-11-03, D-10: runtime actions on a code-defined job are limited to pause and resume (overrides kept pending D-18).
- **REQ-032** A paused definition is not due; resuming sets the next run from now, with no catch-up for the paused period.
  Source: M1-06 AC6, M1-14 AC12. Status: changed by D-10.
  Verification (iteration 1): holds.
  Verification (iteration 2): holds.
  Now: A paused definition is not due; resuming sets the next run from now, with no catch-up for the paused period. A reconcile never changes whether a definition is paused.
  History: 2026-11-03, D-10: a node's start never undoes a pause.
- **REQ-033** Removing a definition keeps its existing occurrences.
  Source: M1-06 AC7. Status: changed by D-10, D-18.
  Verification (iteration 1): unchecked.
  Verification (iteration 2): unchecked (occurrences aren't in the F4 model).
  Now: Removing a definition keeps its existing occurrences. Code-defined definitions can't be removed at runtime; orphaned ones can.
  History: 2026-11-04, D-18: removing orphaned definitions confirmed.
  History: 2026-11-03, D-10: removal limited to runtime-defined and orphaned definitions.
- **REQ-034** Reconciliation runs once at startup on worker nodes, before their loops start; client-only nodes don't reconcile.
  Source: M1-14 AC5, M1-13 AC11. Status: changed by D-19.
  Verification (iteration 1): holds with an issue (D-9).
  Verification (iteration 2): holds with an issue (D-19).
  Now: Reconciliation runs once at startup on worker nodes, before their loops start; client-only nodes don't reconcile. During a rolling deploy, a job whose schedule differs between the versions follows whichever version's node started last; it settles once every node runs one version, including after a rollback.
  History: 2026-11-04, D-19: schedule flips during a deploy are accepted and documented.

## F5 Job routing

Nodes only run jobs they have handlers for, and jobs nobody can handle are made visible.

- **REQ-035** A claim never takes a job whose name the claiming node can't handle; such a job stays `Enqueued` with its attempt unchanged.
  Source: M1-05 AC6. Status: unchanged.
  Verification (iteration 1): broken (D-12).
  Verification (iteration 2): holds.
- **REQ-036** Cleanup marks an `Enqueued` job `Unroutable` when it is older than the routing grace period and no live node advertises its name; a job a live node advertises, or a younger job, is left alone.
  Source: M1-07 AC7. Status: changed by D-12.
  Verification (iteration 1): holds.
  Verification (iteration 2): holds.
  Now: Cleanup marks an `Enqueued` job `Unroutable` when it is older than the routing grace period and no live node advertises its name; a job a live node advertises, or a younger job, is left alone. A node is live while its last heartbeat is no older than the node timeout; a node that hasn't ticked for the node timeout is treated as gone, even if it later resumes.
  History: 2026-11-03, D-12: a node silent for the node timeout counts as gone.
  History: 2026-11-03, D-2 (within the node timeout) defined "live node".
- **REQ-037** A tick from a node that can handle an `Unroutable` job's name moves it back to `Enqueued`.
  Source: M1-07 AC8. Status: unchanged.
  Verification (iteration 1): broken (D-12).
  Verification (iteration 2): holds.
- **REQ-038** Cleanup never deletes a job that isn't finished, however old.
  Source: M1-07 AC4. Status: unchanged.
  Verification (iteration 1): holds.
  Verification (iteration 2): holds.

## F6 Cleanup leadership

One node at a time runs cleanup, under a short lease in the store.

- **REQ-039** At most one node holds the cleanup lease; another node can take it only after it expires; the holder can renew it.
  Source: M1-07 AC3. Status: unchanged.
  Verification (iteration 1): holds.
  Verification (iteration 2): holds.
- **REQ-040** Only the node holding the cleanup lease purges.
  Source: M1-13 AC7. Status: changed by D-8.
  Verification (iteration 1): broken (D-8).
  Verification (iteration 2): broken (D-8, still happens).
  Now: A node renews the cleanup lease before each batch, and stops its run when it can't. Only the node holding the cleanup lease purges. Every purge batch is bounded by the store's command timeout, and the cleanup lease is the larger of twice the cleanup interval and twice the store's command timeout, so a batch always ends before its lease can expire.
  History: 2026-11-04, D-8 answered: the batch bound is the store's command timeout, and the lease always covers it.
  History: 2026-11-03, D-8: the lease is renewed before every batch.
- **REQ-041** Cleanup keeps purging in batches until a batch comes back short.
  Source: M1-13 AC8. Status: changed by D-8.
  Verification (iteration 1): holds.
  Verification (iteration 2): holds.
  Now: Cleanup keeps purging in batches until a batch comes back short, or until it can't renew the lease before its next batch.
  History: 2026-11-03, D-8: renewing before each batch means a run can also stop on a failed renewal; I missed this edit when applying D-8 and made it during iteration 2.

## F7 Recurring catch-up after downtime

Which occurrences a due definition creates after missed time.

- **REQ-042** After downtime, `RunOnce` creates one occurrence for the latest missed instant, `Skip` creates none if it is late, and `RunAll` creates the newest few up to its limit; in every case the next run is in the future.
  Source: M1-14 AC6, AC7, AC8. Status: unchanged.
  Verification (iteration 1): unchecked (calendar arithmetic; covered by M1-14's tests).
  Verification (iteration 2): unchecked (calendar arithmetic; covered by M1-14's tests).
- **REQ-043** Only the node whose fire succeeded reports the missed occurrences.
  Source: M1-14 AC9. Status: unchanged.
  Verification (iteration 1): holds.
  Verification (iteration 2): holds.

## Store-wide

Rules every model rests on but no story stated. They come from the review of the models (docs/tla-modelling-review.md, finding 6), not from a story criterion.

- **REQ-044** Every store operation takes effect as one atomic step, as if operations ran one at a time (linearizable): claim, renew, complete, release, cancel, requeue, delete, tick, fire, reconcile, purge and lease take-or-renew. Every store (in-memory, PostgreSQL, and the later ones) must give the same guarantee; the conformance suite checks it.
  Source: review, finding 6. Status: new (2026-11-04).
  Verification: assumed by every model (each operation is one step); not checked by a rule of its own.
- **REQ-045** Reconciles of one application are serialized. A starting node registers its node row, with the job names and recurring job names its code defines, in the same serialized step as its reconcile, and the reconcile judges which nodes are live within that step.
  Source: review, finding 6 (D-9 relies on it). Status: new (2026-11-04).
  Verification: assumed by F4 (a node start and its reconcile are one step); iteration 3 checks it.
  Note: without it, two nodes of different versions starting together each miss the other's uncommitted row, and each orphans the other's jobs. In PostgreSQL, a transaction-scoped advisory lock per application does it, the same pattern migrations use (arch §4.3).

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
