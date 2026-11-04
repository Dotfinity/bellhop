# Iteration 4 results: your fix worked

Resolved 1 problem from iteration 3 (D-22), which also settles D-20. Nothing new came up, and no decision is open.

## Resolved

| Decision | What was wrong | What fixed it |
|---|---|---|
| D-22 | With every node of an application down, cleanup on another application's node orphaned its recurring jobs, and they lost their catch-up. | Cleanup orphans only for an application with a live node (REQ-030). |
| D-20 | A crash during a rolling deploy left a removed recurring job active for good. | Cleanup also orphans (iteration 3), now limited by D-22. |

## Each feature

| Feature | Iteration 3 | Iteration 4 |
|---|---|---|
| F1 to F3, F5, F6 | as in iteration 3 | unchanged since iteration 3 |
| F4 Recurring definitions and reconciliation | 9 of 10 held (D-22) | all 10 held |
| F7 Recurring catch-up | not checked | not checked |

The rule that a removed job is eventually orphaned now reads "a job of a running application". An application that is down is left alone on purpose, and a separate rule checks that cleanup doesn't touch it.

## Requirements changed

REQ-030, from your answer to D-22.

## New assumption

- An application retired for good keeps its recurring jobs until someone removes them, as before D-20. This goes to the handoff's known risks.

## Not checked by any rule yet

As in iteration 3: F7 (REQ-042), REQ-007, REQ-023, REQ-027, REQ-028 and REQ-033; REQ-044 and REQ-045 have no rule of their own; REQ-029's same-instant clause.

## What a passed rule means here

As in iteration 3: two nodes and one to four jobs or runs, against the rules in each rules file. It doesn't prove the code, and it can't find a rule nobody wrote.
