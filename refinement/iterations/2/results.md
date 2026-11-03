# Iteration 2 results: fixes worked, and 1 new problem came up

Resolved 9 problems from iteration 1. 1 problem still happens after your change, 1 new problem came up, and 1 question from your answers is still open. D-7's fix was my pick, at your request; the other fixes were your own answers.

## Resolved

| Decision | What was wrong | What fixed it |
|---|---|---|
| D-3 | A recurring job could run twice when one run was marked Unroutable. | Unroutable now counts as active (REQ-019). |
| D-4 | An operator requeue could run an old run beside the current one. | Accepted with a warning (REQ-010). It now happens only for a requeue the operator was warned about. |
| D-5 | A cancelled job could run again after its node shut down. | A cancel request wins over the shutdown release (REQ-012). |
| D-6 | After recovery, the original node could still finish or release the job. | Recovery retires the old claim, and a node checks before it writes (REQ-003). |
| D-7 | A node gave up on its lease too late to rule out two nodes running the same job. | It now counts from the send time and gives up at two thirds of the lease (REQ-015). |
| D-9 | A rolling deploy switched recurring jobs off while old nodes still ran them. | A job is orphaned only when no live node still defines it (REQ-030). |
| D-10 | A code-defined job could be removed and re-created at runtime. | At runtime it can only be paused or resumed (REQ-031 to REQ-033). |
| D-11 | Nobody had said whether a paused job could be triggered by hand. | It can (REQ-026). |
| D-12 | A node that stopped ticking could have its jobs marked Unroutable again and again. | Accepted: a node silent for the node timeout counts as gone (REQ-036). |

Each fix was also checked the other way round: with the change removed, the old problem came back. So the fixes, not changes to the models, are what made these rules hold.

## Still happens

- **D-8 (major): a cleanup batch can outlive its lease.** Renewing before each batch helps, but one slow batch can still run past the lease, and another node then starts purging alongside it. There are new options on D-8: bound the batch, have the store refuse a batch from a node without the lease, or accept it.

## New

- **D-19 (major, from the modelling): during a rolling deploy, a restarting old node puts back the old schedule.** This applies to a job both versions define with different schedules. The schedule flips with each restart until every node runs the new version, and each flip resets its next run time.

## Still open

- **D-18 (minor):** whether runtime overrides of code-defined jobs stay, and whether orphaned jobs can be removed. This iteration assumed yes to both.

## Each feature, before and after

| Feature | Iteration 1 | Iteration 2 |
|---|---|---|
| F1 Job lifecycle and leases | 4 rules broken | all 10 held |
| F2 Lease heartbeat and self-fencing | 2 rules broken | all 4 held |
| F3 Recurring firing and overlap | 5 rules broken | 6 of 7 held; the seventh breaks only through loops you accepted (below) |
| F4 Recurring definitions and reconciliation | 2 rules broken | the 2 fixed; 1 new rule broken (D-19) |
| F5 Job routing | 1 rule broken | all 5 held |
| F6 Cleanup leadership | 2 rules broken | still 2 broken (D-8); a third rule held once REQ-041 matched D-8 |
| F7 Recurring catch-up | not checked | not checked |

## Not raised, and why

- **F3: a run waiting its turn can wait forever, but only if the run ahead of it never finishes.** That needs one of two endless loops:
  - an operator cancelling and requeuing the same run forever, with a warning each time (accepted in D-4);
  - the run ahead bouncing between Unroutable and the queue because its handler node keeps going silent (accepted in D-12).

  With neither loop, every waiting run is promoted.
- **F4: a rolled-back deploy leaves the new version's jobs firing.** If the deploy is rolled back and no new-version node restarts, a job only the new version defined stays active until an old-version node starts. Its runs would be marked Unroutable (no node can run them), which the routing rules already make visible.

## Requirements changed this time

REQ-003, REQ-010, REQ-012, REQ-015, REQ-019, REQ-026, REQ-030 to REQ-033, REQ-036, REQ-040 and REQ-041, all from your answers. REQ-041 was an edit your D-8 answer implied; I missed it when applying the answers and made it during this iteration.

## New assumptions this iteration

They go to the handoff's known risks unless you confirm or correct them:
- A job cancelled at shutdown instead of being released (D-5) doesn't count that attempt.
- A cancelled handler stops at once. A handler that ignores cancellation can still run beside the next node, whatever the lease timing.
- In the worst case, a node gives up at the very moment its lease runs out: zero margin when it checks only once per renewal interval. Clock differences between nodes would eat into it.
- With a run active, a catch-up fire creates nothing under `Skip`, both runs waiting under `Queue` and `CancelPrevious`, and both queued under `Allow`.
- For orphaning, a live node means a running one; heartbeats weren't modelled in F4.
- "A name its code defines" means the code of a node that is running now. A name only a not-yet-started version defines can still be created at runtime, and the first node to define it takes it over.

## Not checked by any rule yet

F7 (REQ-042), REQ-007, REQ-023, REQ-027, REQ-028 and REQ-033, for the reasons given in iteration 1.

## What a passed rule means here

Each check covers two nodes and one to three jobs or runs, against the rules in its rules file. It doesn't prove the code, and it can't find a rule nobody wrote. In F2, one step never happens: a node being told at renewal that its job was taken over. That's because a node now always gives up first. No rule depends on that step.
