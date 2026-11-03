# Decisions: Bellhop M1 (from the stories)

## D-1 · How long may a handler keep running after its job could have been picked up by another node?

Status: decided (2026-11-03): option 1, no overlap at all. REQ-015 changed. Severity: major. Source: analysis. Raised: before the first run.
Features: F2. Requirements: REQ-015.

M1-12 AC9 says self-fencing exists "so no handler keeps running long after another node may have recovered its job". "Long" has no measure, so the check can't tell an acceptable overlap from a bug. Two nodes running the same job at once is what at-least-once delivery allows, but only for a bounded time.

Options:
1. **No overlap at all.** A handler must be cancelled before another node can recover its job. REQ-015 becomes: "A node cancels its handlers no later than the moment another node could recover their jobs."
2. **Overlap up to one renewal interval.** The old handler may run on for at most a third of the lease length after the job was recovered elsewhere. REQ-015 becomes: "…cancels every running handler, at the latest one renewal interval after another node could have recovered its job."

## D-2 · When does a node count as live for routing?

Status: decided (2026-11-03): option 1, within the node timeout. REQ-036 changed. Severity: major. Source: analysis. Raised: before the first run.
Features: F5. Requirements: REQ-036.

M1-07 AC7 marks jobs `Unroutable` when "no live node" advertises their name, but no story says what makes a node live. If a node that can handle the job counts as dead while it is still running (say, between two heartbeats), its jobs are marked `Unroutable` and then moved back on its next tick, over and over.

Options:
1. **Live means its last heartbeat is within the node timeout** (5 minutes by default, the value cleanup already uses to remove nodes). REQ-036 gains: "A node is live while its last heartbeat is no older than the node timeout."
2. **Live means its last heartbeat is within three heartbeat intervals** (45 seconds by default, the dashboard's "stale" threshold). REQ-036 gains: "A node is live while its last heartbeat is no older than three heartbeat intervals."

## D-3 · A recurring job can run twice at once when one of its runs is marked Unroutable

Status: open. Severity: major. Source: verification. Raised: iteration 1.
Features: F3, F5. Requirements: REQ-019, REQ-020, REQ-021, REQ-024, REQ-036, REQ-037.
Rule: NoOverlap.

REQ-019's list of active states leaves out `Unroutable`, so `Skip`, `Queue` and `CancelPrevious` all treat a run that is waiting for a handler as if it had finished. When a node with the handler comes back, REQ-037 puts that run back in the queue next to the newer one. It needs no operator action: only a minute in which no live node advertises the job's name, for example during a deploy.

How it happens (policy `Skip`, every minute):
1. 03:00's run is created and queued.
2. No node that can handle the job is live for a while, so cleanup marks 03:00's run Unroutable.
3. 03:01 fires. Nothing counts as active, so `Skip` creates 03:01's run.
4. A node with the handler starts and moves 03:00's run back to the queue.
5. Both runs are picked up and run at the same time.

Suggested edit to REQ-019. Old: "An occurrence counts as active when it is `Scheduled`, `Enqueued`, `Processing`, `Failed` or `Awaiting`." New: "An occurrence counts as active when it is `Scheduled`, `Enqueued`, `Processing`, `Failed`, `Awaiting` or `Unroutable`."

## D-4 · An operator requeue can start an old run of a recurring job next to the current one

Status: open. Severity: major. Source: verification. Raised: iteration 1.
Features: F3, F1. Requirements: REQ-010, REQ-020, REQ-021, REQ-024.
Rule: NoOverlap (also AwaitingRunsInOrder and AwaitingNeverStranded).

REQ-010 lets an operator requeue any finished job, and nothing says a run of a recurring job is different. So under every policy except `Allow`, a requeued old run can run beside the current one, and under `Queue` it jumps ahead of runs waiting their turn. Cancelling and requeuing over and over can also keep a waiting run waiting indefinitely.

How it happens (policy `Skip`):
1. A catch-up fire creates 02:00's run (queued) and 03:00's run (waiting).
2. 02:00's run starts.
3. Someone cancels 03:00's run, so it ends Cancelled.
4. An operator requeues 03:00's run, which REQ-010 allows from Cancelled.
5. It starts while 02:00's run is still running.

Options:
1. **Refuse while another run is active.** Add to REQ-010: "A run of a recurring job can't be requeued while another run of the same recurring job is active."
2. **Requeue follows the overlap policy.** Add to REQ-010: "A requeued run of a recurring job goes through its overlap policy like a new run: refused under `Skip`, `Awaiting` under `Queue` and `CancelPrevious`, queued under `Allow`."
3. **Requeue overrides the policy on purpose.** Add to REQ-010: "Requeuing a run of a recurring job ignores its overlap policy; the operator accepts that it may run beside another run."

## D-5 · A cancelled job runs again if its node shuts down before the handler stops

Status: open. Severity: major. Source: verification. Raised: iteration 1.
Features: F1. Requirements: REQ-006, REQ-008, REQ-009, REQ-012.
Rule: CancelRequestHonoured.

REQ-009 says a running job whose cancel was requested ends Cancelled. REQ-012 says a job still running at shutdown goes back to the queue. Neither says which wins, so a job someone asked to stop comes back and runs from the start on another node. If the job sends emails or charges a card, the cancelled action happens anyway.

How it happens:
1. Node 1 picks up the job and starts it.
2. Someone cancels it. It is running, so a cancel request is recorded (REQ-009).
3. Node 1 shuts down before the handler stops, and releases the job (REQ-012).
4. The job is back in the queue, and the next node runs it again.

Options:
1. **A released job with a cancel request ends Cancelled.** Add to REQ-012: "A job whose cancel was requested is not released back to the queue; it ends `Cancelled`."
2. **The cancel request survives the release.** Add to REQ-012: "A released job keeps its cancel request, and the next node to pick it up ends it `Cancelled` without running it."

## D-6 · After another node recovers a job, the original node can still finish or release it

Status: open. Severity: major. Source: verification. Raised: iteration 1.
Features: F1. Requirements: REQ-002, REQ-003, REQ-005, REQ-008, REQ-012.
Rules: FinalStaysFinal, AttemptsWithinMax, ReleaseDoesNotCountAttempt.

The stories make a completion with a stale token change nothing (REQ-003), but a token only goes stale when the job is picked up again. Between recovery and the next pickup, the original node's token still works. In that window it can overwrite a final result, or push the attempt count below zero.

How it happens:
1. Node 1 picks up the job.
2. Its lease runs out because it is slow or cut off, and a tick puts the job back in the queue (REQ-008).
3. Someone cancels the queued job, and it ends Cancelled at once (REQ-009).
4. Node 1 finishes and reports success with its old token. The token is still current, so the store records Succeeded, and the final Cancelled is overwritten.

The same window lets node 1 release the job at shutdown after an operator requeued it with attempts reset to 0, which takes the count to -1.

Suggested edit to REQ-003. Old: "Completing a job with a stale token changes nothing. A node told its lease is lost cancels the handler and completes nothing." New: "Completing, renewing or releasing a job with a stale token changes nothing, and recovering a job makes its old token stale. A node told its lease is lost cancels the handler and completes nothing."

## D-7 · A node stops its handler too late to rule out two nodes running the same job

Status: open. Severity: major. Source: verification. Raised: iteration 1.
Features: F2. Requirements: REQ-015.
Rules: NoDoubleRun, CancelledByRecoveryMoment.

Your answer to D-1 says two nodes never run the same job at once. As written, REQ-015 makes a node stop its handler when renewals have failed "for longer than the lease length". That is the same moment another node may recover the job, so nothing makes the stop come first. And if the node counts from when a slow renewal's reply arrives, rather than when it sent the renewal, it gives up later still, by up to a third of the lease (20 seconds with the default 60-second lease).

How it happens (lease 60 s, renewals every 20 s):
1. At 0 s the node renews. The store records it, but the reply is slow and arrives at 20 s, which the node counts as its last success.
2. From then on the store can't be reached and every renewal fails.
3. At 60 s the lease runs out in the store, and another node takes the job and starts it.
4. The first node gives up only at 80 s, 60 s after the reply it counted from. For about 20 seconds both run.

Even counting from when it sent the renewal, the node gives up exactly when the lease runs out, so the two still tie.

This keeps your D-1 answer and needs a margin. Answer with a fraction of the lease, in: "A node counts from when it sent its last successful renewal, and cancels its handlers once ___ of the lease has passed without a successful renewal." Sensible values are between one third and two thirds: one third leaves a whole renewal interval of margin, two thirds makes nodes give up less often in a short outage.

Note: a handler that ignores cancellation keeps running after the node gives up (M1-12 AC11 frees its slot after a grace period). For those handlers, the node alone can't rule out two runs at once.

## D-8 · A cleanup run can outlive its lease, and two nodes then clean up at once

Status: open. Severity: major. Source: verification. Raised: iteration 1.
Features: F6. Requirements: REQ-039, REQ-040, REQ-041.
Rules: OnlyHolderPurges, OneCleanupRunAtATime.

A node checks the cleanup lease only when it starts a run, and a run keeps going until a batch comes back short (REQ-041). After downtime the backlog can be large, so a run can last longer than the lease. Another node then takes the expired lease (REQ-039) and starts its own run. Both purge at once, which doubles the database load cleanup was meant to keep low. Nothing is deleted twice.

How it happens:
1. Node 1 takes the cleanup lease and starts purging a large backlog.
2. Its run is still going when the lease runs out.
3. Node 2's cleanup interval comes round; the lease has expired, so node 2 takes it and starts its own run.
4. Both nodes purge batches at the same time.

Options:
1. **Renew before each batch.** REQ-040 becomes: "A node renews the cleanup lease before each batch, and stops its run when it can't."
2. **Only starting is guarded.** REQ-040 becomes: "Only the node holding the cleanup lease starts a cleanup run; a run already going may finish after the lease expires."

## D-9 · During a rolling deploy, recurring jobs switch off and on as nodes restart

Status: open. Severity: major. Source: modeling. Raised: iteration 1.
Features: F4. Requirements: REQ-030, REQ-034.
Rule: RunningCodeKeepsItsJobs.

No story says what happens to recurring jobs while two versions of the same service run side by side. As written, each node start decides by itself which jobs are orphaned. The first node on the new version orphans jobs the old version still defines, so they stop firing while old nodes are still running. If an old-version node then restarts (a crash or a scale-up), it orphans the jobs the new version added and puts back the old schedules. Each restart flips them again until the deploy finishes.

How it happens:
1. Both nodes run the old version, which defines `nightly-report` and `weekly-digest`.
2. Node 1 restarts on the new version, which drops `weekly-digest` and adds `hourly-sync`. Its start orphans `weekly-digest` and creates `hourly-sync`.
3. Node 2, still on the old version, crashes and restarts. Its start restores `weekly-digest` and orphans `hourly-sync`.
4. `hourly-sync` stops firing until a new-version node restarts.

Options:
1. **Orphan only when no live node still defines the job.** Add to REQ-030: "A definition is orphaned only when no live node of its application still defines it in code." Nodes would need to report which recurring jobs their code defines.
2. **The newest version decides.** Add to REQ-030: "A node only orphans or changes definitions if its version is at least as new as the version that last reconciled them."
3. **Accept and document it.** Add to REQ-034: "During a rolling deploy, recurring jobs added or removed by the new version may switch on and off as nodes of either version start; this settles once every node runs the new version."

## D-10 · A code-defined recurring job can be removed and re-created at runtime with a different schedule

Status: open. Severity: minor. Source: verification. Raised: iteration 1.
Features: F4. Requirements: REQ-031, REQ-033.
Rule: CodeOnlyNamesKeepCodeSchedule.

REQ-031 refuses runtime edits of a code-defined job, but REQ-033 allows removing any job, and nothing stops someone creating a new one with the same name afterwards. That gets round the refusal until the service restarts, when the code's version silently replaces it.

Options:
1. **Refuse it.** Add to REQ-031: "Removing a code-defined job, or creating one with a name code defines, is refused at runtime unless it allows runtime override."
2. **Allow it.** Add to REQ-033: "A code-defined job removed at runtime comes back from code at the next start of its service."

## D-11 · Can a paused recurring job be triggered by hand?

Status: open. Severity: minor. Source: verification. Raised: iteration 1.
Features: F3. Requirements: REQ-017, REQ-026.
Rule: PausedNeverFires.

REQ-017 says a paused job is never due, and REQ-026 says a manual trigger fires "whatever the next run time says". Neither says whether a manual trigger works on a paused job.

Options:
1. **Allowed.** Add to REQ-026: "A manual trigger works on a paused job too; pausing stops only the schedule."
2. **Refused.** Add to REQ-026: "A manual trigger on a paused job is refused."

## D-12 · A busy node that stops ticking for a while can have its jobs marked Unroutable

Status: open. Severity: minor. Source: verification. Raised: iteration 1.
Features: F5. Requirements: REQ-035, REQ-036, REQ-037.
Rule: HandledEventually.

With your D-2 answer, a node counts as live while its last heartbeat is within the node timeout. A node that is running but hasn't ticked for longer than that (a long pause, or the store refusing its ticks) counts as gone, so cleanup on another node marks its jobs Unroutable and logs a warning. When it ticks again it moves them back. If that keeps happening before it picks them up, the jobs bounce between the two states. They aren't lost, but they wait, and the warning is a false alarm.

How it happens:
1. Node 1 can run the job; the job is queued and older than the routing grace period.
2. Node 1 doesn't tick for longer than the node timeout.
3. Node 2 runs cleanup. No live node advertises the job's name, so the job is marked Unroutable.
4. Node 1 ticks and moves it back to the queue, then pauses again before taking it.

Options:
1. **Accept it.** Add to REQ-036: "A node that hasn't ticked for the node timeout is treated as gone, even if it later resumes."
2. **Give it more time.** Add to REQ-036: "A job is marked Unroutable only when no node has advertised its name for twice the node timeout."

## D-13 · Confirm what the job lifecycle check assumed (F1)

Status: open. Severity: minor. Source: verification. Raised: iteration 1.
Features: F1. Requirements: REQ-001 to REQ-013.

The F1 check passed some rules only under these assumptions, which the stories don't settle. Suggested answer: confirm them as written.
- A lease can run out at any moment; time isn't measured.
- A node learns its lease is lost, or that a cancel was requested, only when it next renews.
- Cancelling a run waiting for its retry counts as "hasn't started", so it is cancelled at once.
- When a lease runs out and a cancel was requested, recovery cancels the job whatever attempts are left.
- Requeue clears the cancel request.
- One job was checked; jobs don't affect each other's lifecycle.

## D-14 · Confirm what the self-fencing check assumed (F2)

Status: open. Severity: minor. Source: verification. Raised: iteration 1.
Features: F2. Requirements: REQ-014 to REQ-016.

Suggested answer: confirm them as written.
- Node clocks match the store's clock; clock differences weren't checked.
- A slow renewal reply arrives at most one renewal interval late.
- A node checks whether to give up at least once per renewal interval.
- Only one handover between two nodes was checked.

## D-15 · Confirm what the recurring overlap check assumed (F3)

Status: open. Severity: minor. Source: verification. Raised: iteration 1.
Features: F3. Requirements: REQ-017 to REQ-027, REQ-043.

Suggested answer: confirm them as written.
- `CancelPrevious` cancels every active run, and creates the new run queued when none is active.
- A fire for a job paused after it was found due leaves its next run time unchanged.
- At most three runs and two due instants were checked, and a catch-up creates two runs.
- Each claim and each tick happens as one step, so races inside a single tick (REQ-027) and between concurrent manual triggers (REQ-026) weren't checked.

## D-16 · Confirm what the reconciliation check assumed (F4)

Status: open. Severity: minor. Source: verification. Raised: iteration 1.
Features: F4. Requirements: REQ-028 to REQ-034.

Suggested answer: confirm them as written, and say whether an override can ever be cleared.
- A runtime override wins over every later reconcile, so a deploy never changes an overridden job's schedule, and no story says how to clear an override.
- A reconcile never changes whether a job is paused.
- If a job created at runtime has a name that code defines, the next reconcile takes it over with the code's schedule.
- No two applications define the same job name. No story covers what happens if they do.

## D-17 · Confirm what the routing and cleanup checks assumed (F5, F6)

Status: open. Severity: minor. Source: verification. Raised: iteration 1.
Features: F5, F6. Requirements: REQ-035 to REQ-041.

Suggested answer: confirm them as written, and give the cleanup lease length if you know it.
- A node advertises exactly the job names it has handlers for, in every heartbeat.
- Moving a job back from Unroutable doesn't reset its age.
- The cleanup lease length isn't in the stories; the check used a lease shorter than a long run.
- A node's cleanup lease isn't released when its run ends; it just runs out.
