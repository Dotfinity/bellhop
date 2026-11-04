# Iteration 3 results: fixes worked, and 1 new problem came up

Resolved 3 problems from earlier iterations (D-7, D-8, D-19), and settled the questions D-18 and D-21. D-1, D-4 and D-6, which were revised or clarified after the review, held again. 1 new problem came up (D-22). It comes from D-20's cleanup sweep, so D-20 stays decided until D-22 is settled. Every answer this time was yours, except D-6's clarified wording, which only restates what the model already checked.

## New

- **D-22 (major, from the modelling): when every node of an application is down, cleanup orphans all its recurring jobs, and they lose their catch-up.** This needs a store shared by several applications. When the application comes back, its jobs are restored with a fresh next run, so a `RunOnce` or `RunAll` catch-up for the downtime never happens. The suggested fix, sweeping only applications that have a live node, was checked: with it, every rule in F4 holds, including the crash case D-20 was for.

## Resolved

| Decision | What was wrong | What fixed it |
|---|---|---|
| D-7 | A node gave up at the very moment its lease ran out, so any clock skew allowed two runs at once. | A fencing deadline at two thirds of the lease (REQ-015). It holds with skew plus pause of a sixth of the lease, and still with a third (the limit); it breaks beyond. The old once-per-interval check breaks with a sixth. |
| D-8 | One slow cleanup batch could outlive its lease, and two nodes purged at once. | Each batch is bounded by the store's command timeout, and the lease always covers it (REQ-040). Without the bound, both cleanup rules break again. |
| D-19 | A restarting old node put back the old schedule during a rolling deploy. | Accepted and documented (REQ-034), so it is no longer a rule. |

Questions settled: D-18 (overrides stay and are permanent; orphans can be removed) and D-21 (`Queue` unchanged). Neither needed a model change.

## Each feature, before and after

| Feature | Iteration 2 | Iteration 3 |
|---|---|---|
| F1 Job lifecycle and leases | all 10 held | all 11 held (new: a job that starts running always stops) |
| F2 Lease heartbeat and self-fencing | all 4 held, with no margin | all 4 held with skew and pause of a sixth of the lease |
| F3 Recurring firing and overlap | 6 of 7 held; the seventh only through accepted loops | all 7 held, with those loops bounded |
| F4 Recurring definitions and reconciliation | 1 rule broken (D-19) | 9 of 10 held; 1 new rule broken (D-22) |
| F5 Job routing | all 5 held | unchanged since iteration 2 |
| F6 Cleanup leadership | 2 rules broken (D-8) | all 6 held (new: cleanup never stops for good) |
| F7 Recurring catch-up | not checked | not checked |

Each fix was also checked the other way round, in `models/attempts/`:
- F2 with the old once-per-interval check breaks the no-double-run rule.
- F4 without the cleanup sweep never orphans a removed job.
- F6 without the batch bound breaks both cleanup rules.
- F4 with two nodes' reconciles not serialized orphans a job a running node defines. That is why REQ-045 is needed.

## Changes to the models, not to Bellhop

- F3 now clears a cancel request on requeue, as F1 and the architecture do. Iteration 2's F3 kept it, which disagreed with F1. Nothing broke either way.
- F3 bounds the two loops accepted in D-4 and D-12 (one requeue, one Unroutable mark), and assumes a node with the handler comes back. Its waiting-runs rule now holds outright instead of being waved through.
- F4 now models a crashed node whose row still counts as live until its heartbeat ages out. Iteration 2 treated a crashed node as gone at once, which hid the problem D-20 fixed.

## Requirements changed since iteration 2

REQ-003, REQ-010, REQ-015, REQ-029, REQ-030, REQ-031, REQ-033, REQ-034 and REQ-040, from your answers. REQ-044 and REQ-045 are new, from the review.

## New assumptions this iteration

They go to the handoff's known risks unless you confirm or correct them:
- Clock skew plus a node's pause delays its give-up by at most a sixth of the lease in the main check; a third is the limit.
- A handler eventually finishes, if only through its timeout.
- A node with a job's handler eventually comes back.
- An operator requeues at most once, and cleanup marks a run Unroutable at most once, in the checked runs.
- A cleanup batch and the pause after it end before the lease runs out. The pause is at most 10 s, the batch at most the 30 s command timeout, and the lease at least 60 s.
- A crashed node's row can age out at any moment; cleanup keeps running.

## Not checked by any rule yet

F7 (REQ-042), REQ-007, REQ-023, REQ-027, REQ-028 and REQ-033, for the reasons given in iteration 1. REQ-044 and REQ-045 have no rule of their own; every model assumes REQ-044, and F4 assumes REQ-045 (above). REQ-029's clause about keeping the next run when the instant is unchanged has no rule, because the next run's instant isn't modelled.

## What a passed rule means here

Each check covers two nodes and one to four jobs or runs, against the rules in its rules file. It doesn't prove the code, and it can't find a rule nobody wrote. In F2, the step where a node is told at renewal that its job was taken over never happens, because a node always gives up first. In F6, a run stopping because it couldn't renew never happens, because with batches bounded a run never loses its lease. No rule depends on either step.
