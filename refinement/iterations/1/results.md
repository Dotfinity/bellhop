# Iteration 1 results: 10 problems found

First iteration, so nothing could be resolved yet. Resolved 0, new 10, still open 15 (the 10 problems plus 5 questions confirming what the checks assumed). D-1 and D-2 were your answers before the run, and both were applied.

## New problems, most severe first

| Decision | Severity | What can go wrong |
|---|---|---|
| D-3 | major | A recurring job can run twice at once when one of its runs is marked Unroutable. |
| D-4 | major | An operator requeue can start an old run of a recurring job next to the current one. |
| D-5 | major | A cancelled job runs again if its node shuts down before the handler stops. |
| D-6 | major | After another node recovers a job, the original node can still finish or release it, overwriting a final result. |
| D-7 | major | Under your D-1 answer, a node stops its handler too late to rule out two nodes running the same job. |
| D-8 | major | A cleanup run can outlive its lease, and two nodes then clean up at once. |
| D-9 | major | During a rolling deploy, recurring jobs switch off and on as nodes restart. No story covers this; the rule came from the modelling. |
| D-10 | minor | A code-defined recurring job can be removed and re-created at runtime with another schedule. |
| D-11 | minor | The stories don't say whether a paused recurring job can be triggered by hand. |
| D-12 | minor | A node that stops ticking for a while can have its jobs marked Unroutable, then moved back. |

D-13 to D-17 ask you to confirm the assumptions each check rests on.

## Each feature's outcome

| Feature | Outcome | Rules held | Rules broken |
|---|---|---|---|
| F1 Job lifecycle and leases | problems found | 6 | 4 (D-5, D-6) |
| F2 Lease heartbeat and self-fencing | problems found | 2 | 2 (D-7) |
| F3 Recurring firing and overlap | problems found | 2 | 5 (D-3, D-4, D-11; two came from my wording, see below) |
| F4 Recurring definitions and reconciliation | problems found | 5 | 2 (D-9, D-10) |
| F5 Job routing | problem found | 4 | 1 (D-12) |
| F6 Cleanup leadership | problems found | 3 | 2 (D-8) |
| F7 Recurring catch-up | not checked | – | – |

In every check, every step the model describes happened at least once, so no rule passed just because something couldn't happen.

## My mistakes, not problems in Bellhop

Two of F3's broken rules came from how I worded the requirements, not from the stories:
- My REQ-025 dropped M1-06 AC18's condition "and no active occurrence".
- My REQ-021 said "once nothing else is active" where the stories say the oldest waiting run is promoted.

Both are corrected in requirements.md, marked as transcription fixes. The two rules that broke because of them (one creating runs under `Skip` while another is active, and two waiting runs blocking each other) aren't raised as problems. They will be checked again in the next iteration.

## Requirements changed

- REQ-015 by your D-1 answer: two nodes never run the same job at once.
- REQ-036 by your D-2 answer: a node is live while its last heartbeat is within the node timeout.
- REQ-021 and REQ-025: transcription fixes, above.

## Not checked by any rule yet

- F7 (REQ-042), which occurrences a catch-up creates: calendar arithmetic, which M1-14's own tests cover better than this check.
- REQ-007 (each due job promoted once) and REQ-027 (racing ticks promote one waiting run): each tick is a single step in the models, so no rule could fail.
- REQ-019 is used as a definition rather than checked by its own rule.
- REQ-023 (`Allow` always creates), REQ-028 (one row per name) and REQ-033 (removing a definition keeps its runs).

## What a passed rule means here

Each check covers its model with two nodes and one to three jobs or runs, against the rules listed in its rules file. It doesn't prove the code, and it can't find a rule nobody wrote. Several held rules restate a guard taken straight from the requirements, so they confirm the model matches the text more than they test the design. The weakest passes:
- the lease rules in F1 and F6, which hold because claiming and taking a lease are single steps in the store;
- REQ-018's one-fire-per-instant, which holds because of the compare-and-set the stories describe.
