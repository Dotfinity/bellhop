# Decisions: Bellhop M1 (from the stories)

## D-1 · How long may a handler keep running after its job could have been picked up by another node?

Status: decided (2026-11-04, revised): no overlap within stated limits, and the lease token exposed to handlers. REQ-015 changed. Was: resolved (iteration 2), from decided (2026-11-03): option 1, no overlap at all. Severity: major. Source: analysis. Raised: before the first run.
Features: F2. Requirements: REQ-015.

M1-12 AC9 says self-fencing exists "so no handler keeps running long after another node may have recovered its job". "Long" has no measure, so the check can't tell an acceptable overlap from a bug. Two nodes running the same job at once is what at-least-once delivery allows, but only for a bounded time.

Options:
1. **No overlap at all.** A handler must be cancelled before another node can recover its job. REQ-015 becomes: "A node cancels its handlers no later than the moment another node could recover their jobs."
2. **Overlap up to one renewal interval.** The old handler may run on for at most a third of the lease length after the job was recovered elsewhere. REQ-015 becomes: "…cancels every running handler, at the latest one renewal interval after another node could have recovered its job."

### Revised after review (2026-11-04)

"No overlap at all" can't be an absolute guarantee with leases. F2 holds only while clocks agree within the margin, the node is never paused for longer than the margin (GC, a VM freeze), and a cancelled handler stops. D-7 already notes that a handler ignoring cancellation breaks it. The architecture's failure table separately promises only at-least-once. See docs/tla-modelling-review.md, finding 3.

Answer: no overlap stays the design goal, with its limits stated. The last sentence of REQ-015 becomes: "Two nodes never run the same job at once, provided clock skew plus any pause of the node stays under a third of the lease and the handler stops when cancelled. Outside those limits delivery is at-least-once, and handlers with external side effects must be idempotent."

Also decided: `JobContext` gains `Guid LeaseToken { get; }`, the claim's lease token, which is fresh per claim. It is documented as a fencing token a handler can pass to its own downstream writes. `JobContext.CreateForTest` takes an optional token. It lands in arch §3.1 and the stories that build `JobContext` (issue 11).

## D-2 · When does a node count as live for routing?

Status: resolved (iteration 2; every rule this answer touched held). Was: decided (2026-11-03): option 1, within the node timeout. REQ-036 changed. Severity: major. Source: analysis. Raised: before the first run.
Features: F5. Requirements: REQ-036.

M1-07 AC7 marks jobs `Unroutable` when "no live node" advertises their name, but no story says what makes a node live. If a node that can handle the job counts as dead while it is still running (say, between two heartbeats), its jobs are marked `Unroutable` and then moved back on its next tick, over and over.

Options:
1. **Live means its last heartbeat is within the node timeout** (5 minutes by default, the value cleanup already uses to remove nodes). REQ-036 gains: "A node is live while its last heartbeat is no older than the node timeout."
2. **Live means its last heartbeat is within three heartbeat intervals** (45 seconds by default, the dashboard's "stale" threshold). REQ-036 gains: "A node is live while its last heartbeat is no older than three heartbeat intervals."

## D-3 · A recurring job can run twice at once when one of its runs is marked Unroutable

Status: resolved (iteration 2; every rule this answer touched held). Was: decided (2026-11-03): the suggested edit. REQ-019 changed. Severity: major. Source: verification. Raised: iteration 1.
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

Status: resolved (iteration 2; every rule this answer touched held). Was: decided (2026-11-03), owner's own words: "a warning should be shown to the user, otherwise if it's a manual operation, that's fine, we assume the user knows what they're doing". Read as: requeue ignores the overlap policy and warns when another run is active. REQ-010 changed. Severity: major. Source: verification. Raised: iteration 1.
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

Status: resolved (iteration 2; every rule this answer touched held). Was: decided (2026-11-03): option 1. REQ-012 changed. Severity: major. Source: verification. Raised: iteration 1.
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

Status: resolved (iteration 2; every rule this answer touched held). Was: decided (2026-11-03), owner's own words: "upon start of the original node, it should check if another node has picked up its jobs before continuing". Read as: recovery makes the old claim dead, and a node checks it still holds a job before writing anything about it. REQ-003 changed. Severity: major. Source: verification. Raised: iteration 1.
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

Status: decided (2026-11-04, revised): a fencing deadline timer at two thirds of the lease. REQ-015 changed again; to be re-checked in iteration 3. Was: resolved (iteration 2), with a check once per renewal interval, which held only with zero margin. Before that: decided (2026-11-03), delegated ("pick the best decision from reliability and consistency stand point"). Assumed the answer: two thirds of the lease, counted from when the renewal was sent. Severity: major. Source: verification. Raised: iteration 1.
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

### Revised after review (2026-11-04)

The iteration-2 answer held only with zero margin. A node that checks once per renewal interval and gives up at two thirds of the lease can, in the worst case, give up at 2/3 + 1/3 = the whole lease, which is the instant the store's lease expires. It held only because recovery needs the store's time to be strictly past the expiry. Re-running F2 with recovery allowed at the expiry instant (any clock skew or delay above zero) breaks NoDoubleRun in 11 steps. REQ-015's history line ("leaves one renewal interval before another node may recover the job") was wrong for a periodic check. It is corrected below. See docs/tla-modelling-review.md, finding 2 and Appendix A.

Two options were checked against F2:
1. **Deadline timer at two thirds.** Holds with recovery up to 1/6 of the lease early; ties at 1/3 early. Margin just under a third of the lease (20 s at the default 60 s).
2. **Periodic check, giving up at half the lease.** Holds with recovery at the expiry instant; fails at 1/6 early. Margin just under a sixth of the lease (10 s).

Answer: option 1. REQ-015 becomes: "A node arms a fencing deadline at the time it sent its last successful renewal plus two thirds of the lease, and re-arms it on every successful renewal. When the deadline passes, the node cancels its handlers at once. Two nodes never run the same job at once while clock skew plus any pause of the node stays under a third of the lease."

## D-8 · A cleanup run can outlive its lease, and two nodes then clean up at once

Status: open. Still happens after your change in iteration 2 (you chose option 1 on 2026-11-03; REQ-040 and REQ-041 changed). Severity: major. Source: verification. Raised: iteration 1.
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

### Still happens after your change (iteration 2)

Renewing before each batch closes most of the gap, but not a batch that itself takes longer than the lease. The stories set no limit on how long one batch may take, so a node can still be purging when its lease runs out, and another node can take the lease and start purging too.

How it happens now:
1. Node 1 takes the cleanup lease, renews it before its first batch, and starts purging.
2. That one batch is slow (a large table, a busy database), and the lease runs out while it is still going.
3. Node 2's cleanup interval comes round. The lease has expired, so node 2 takes it and starts its own batch.
4. Both nodes purge at the same time until node 1's batch finishes; node 1 then fails to renew and stops.

Options now:
1. **Bound the batch.** Add to REQ-040: "A purge batch is abandoned if it hasn't finished within half the cleanup lease."
2. **Make the store refuse it.** Add to REQ-040: "Each purge batch is written in one store transaction that first checks the node still holds the cleanup lease; a batch from a node that doesn't is rolled back."
3. **Accept it.** Add to REQ-040: "A batch already running when the lease runs out may finish; at most one batch per node can overlap like this."

## D-9 · During a rolling deploy, recurring jobs switch off and on as nodes restart

Status: resolved (iteration 2; every rule this answer touched held). Was: decided (2026-11-03): option 1. REQ-030 changed. Severity: major. Source: modeling. Raised: iteration 1.
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

Status: resolved (iteration 2; every rule this answer touched held). Was: decided (2026-11-03), owner's own words: "make it so runtime we can only disable/pause a job, then at start/restart of a node, it doesn't override the disabled job's state as disabled". Read as: at runtime a code-defined job can only be paused or resumed, and a reconcile never changes whether a job is paused. REQ-031, REQ-032 and REQ-033 changed. Follow-up question D-18. Severity: minor. Source: verification. Raised: iteration 1.
Features: F4. Requirements: REQ-031, REQ-033.
Rule: CodeOnlyNamesKeepCodeSchedule.

REQ-031 refuses runtime edits of a code-defined job, but REQ-033 allows removing any job, and nothing stops someone creating a new one with the same name afterwards. That gets round the refusal until the service restarts, when the code's version silently replaces it.

Options:
1. **Refuse it.** Add to REQ-031: "Removing a code-defined job, or creating one with a name code defines, is refused at runtime unless it allows runtime override."
2. **Allow it.** Add to REQ-033: "A code-defined job removed at runtime comes back from code at the next start of its service."

## D-11 · Can a paused recurring job be triggered by hand?

Status: resolved (iteration 2; every rule this answer touched held). Was: decided (2026-11-03): option 1. REQ-026 changed. Severity: minor. Source: verification. Raised: iteration 1.
Features: F3. Requirements: REQ-017, REQ-026.
Rule: PausedNeverFires.

REQ-017 says a paused job is never due, and REQ-026 says a manual trigger fires "whatever the next run time says". Neither says whether a manual trigger works on a paused job.

Options:
1. **Allowed.** Add to REQ-026: "A manual trigger works on a paused job too; pausing stops only the schedule."
2. **Refused.** Add to REQ-026: "A manual trigger on a paused job is refused."

## D-12 · A busy node that stops ticking for a while can have its jobs marked Unroutable

Status: resolved (iteration 2; every rule this answer touched held). Was: decided (2026-11-03): option 1. REQ-036 changed. Severity: minor. Source: verification. Raised: iteration 1.
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

Status: resolved (iteration 2; every rule this answer touched held). Was: decided (2026-11-03): assumptions confirmed as written. Severity: minor. Source: verification. Raised: iteration 1.
Features: F1. Requirements: REQ-001 to REQ-013.

The F1 check passed some rules only under these assumptions, which the stories don't settle. Suggested answer: confirm them as written.
- A lease can run out at any moment; time isn't measured.
- A node learns its lease is lost, or that a cancel was requested, only when it next renews.
- Cancelling a run waiting for its retry counts as "hasn't started", so it is cancelled at once.
- When a lease runs out and a cancel was requested, recovery cancels the job whatever attempts are left.
- Requeue clears the cancel request.
- One job was checked; jobs don't affect each other's lifecycle.

## D-14 · Confirm what the self-fencing check assumed (F2)

Status: resolved (iteration 2; every rule this answer touched held). Was: decided (2026-11-03): assumptions confirmed as written. Severity: minor. Source: verification. Raised: iteration 1.
Features: F2. Requirements: REQ-014 to REQ-016.

Suggested answer: confirm them as written.
- Node clocks match the store's clock; clock differences weren't checked.
- A slow renewal reply arrives at most one renewal interval late.
- A node checks whether to give up at least once per renewal interval.
- Only one handover between two nodes was checked.

## D-15 · Confirm what the recurring overlap check assumed (F3)

Status: resolved (iteration 2; every rule this answer touched held). Was: decided (2026-11-03): assumptions confirmed as written. Severity: minor. Source: verification. Raised: iteration 1.
Features: F3. Requirements: REQ-017 to REQ-027, REQ-043.

Suggested answer: confirm them as written.
- `CancelPrevious` cancels every active run, and creates the new run queued when none is active.
- A fire for a job paused after it was found due leaves its next run time unchanged.
- At most three runs and two due instants were checked, and a catch-up creates two runs.
- Each claim and each tick happens as one step, so races inside a single tick (REQ-027) and between concurrent manual triggers (REQ-026) weren't checked.

## D-16 · Confirm what the reconciliation check assumed (F4)

Status: resolved (iteration 2; every rule this answer touched held). Was: decided (2026-11-03): assumptions confirmed as written. Whether an override can be cleared was not answered; it stays an assumption that it can't. Severity: minor. Source: verification. Raised: iteration 1.
Features: F4. Requirements: REQ-028 to REQ-034.

Suggested answer: confirm them as written, and say whether an override can ever be cleared.
- A runtime override wins over every later reconcile, so a deploy never changes an overridden job's schedule, and no story says how to clear an override.
- A reconcile never changes whether a job is paused.
- If a job created at runtime has a name that code defines, the next reconcile takes it over with the code's schedule.
- No two applications define the same job name. No story covers what happens if they do.

## D-17 · Confirm what the routing and cleanup checks assumed (F5, F6)

Status: resolved (iteration 2; every rule this answer touched held). Was: decided (2026-11-03): assumptions confirmed as written. No cleanup lease length was given; it stays an assumption. Severity: minor. Source: verification. Raised: iteration 1.
Features: F5, F6. Requirements: REQ-035 to REQ-041.

Suggested answer: confirm them as written, and give the cleanup lease length if you know it.
- A node advertises exactly the job names it has handlers for, in every heartbeat.
- Moving a job back from Unroutable doesn't reset its age.
- The cleanup lease length isn't in the stories; the check used a lease shorter than a long run.
- A node's cleanup lease isn't released when its run ends; it just runs out.

## D-18 · What can be done at runtime with a code-defined job's override, and with an orphaned job?

Status: open. Severity: minor. Source: analysis. Raised: after iteration 1, from the answer to D-10.
Features: F4. Requirements: REQ-031, REQ-033.

Your answer to D-10 limits runtime actions on a code-defined job to pausing and resuming. Two things it doesn't settle:

1. REQ-031 also lets a code-defined job marked "allow runtime override" have its schedule edited at runtime. Does that stay?
2. An orphaned job is code-defined but no longer in any code. Reconcile never deletes it (REQ-030), so if it can't be removed at runtime either, orphans pile up forever.

Until you answer, iteration 2 assumes: overrides stay as REQ-031 says, and an orphaned job can be removed at runtime.

Options:
1. **Keep both.** Overrides stay; orphaned jobs can be removed at runtime.
2. **Pause only, but orphans can go.** Drop runtime overrides: a code-defined job's schedule changes only in code. Orphaned jobs can be removed at runtime.
3. **Pause only, everywhere.** Drop runtime overrides, and orphaned jobs stay until code defines them again or someone deletes them from the database.

## D-19 · During a rolling deploy, a restarting old node puts back the old schedule of a job both versions define

Status: open. Severity: major. Source: modeling. Raised: iteration 2.
Features: F4. Requirements: REQ-029, REQ-034.
Rule: NewScheduleNotReverted.

Your D-9 answer stops jobs being orphaned while any running node still defines them. It doesn't say what happens to a job both versions define with different schedules. As written, each node start writes its own version's schedule, so while the deploy is under way the schedule flips with every restart, and each flip resets the job's next run time, which can skip or bring forward a run.

How it happens:
1. Both nodes run the old version, where `nightly-report` runs at 03:00.
2. Node 2 restarts on the new version, where `nightly-report` runs at 02:00. Its start changes the schedule to 02:00.
3. Node 1, still on the old version, crashes and restarts. Its start changes the schedule back to 03:00, with node 2 still running the new version.
4. Each further restart of either version flips it again, until every node runs the new version.

Options:
1. **The newest version decides.** Add to REQ-029: "A reconcile changes a definition's schedule only if its version is at least as new as the version that last set it."
2. **Accept and document it.** Add to REQ-034: "During a rolling deploy, a job whose schedule differs between the versions follows whichever version's node started last; this settles once every node runs the new version."
