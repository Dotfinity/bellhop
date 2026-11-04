# TLA+ review: issues to resolve

Source: [tla-modelling-review.md](tla-modelling-review.md) (finding numbers in brackets). Issues are listed in the order they should be worked: a decision comes before the edits that depend on it.

New owner decisions are recorded in `refinement/decisions.md` (continuing from D-19), and requirement changes in `refinement/requirements.md`, as before. Issue 11 then carries every settled decision into the stories and the architecture in one pass. Issues 12 to 15 are iteration 3 of the models, run after the decisions settle.

Status: open, decided (answer recorded, not yet propagated), done.

| # | Issue | Needs your call | Lands in | Status |
|---|---|---|---|---|
| 1 | Self-fencing has zero margin; REQ-015's history line contradicts results.md [2] | decided 2026-11-04: deadline timer at 2/3 (margin just under 1/3 lease) | decisions D-7, REQ-015 | decided |
| 2 | "No overlap at all" (D-1) is stated as absolute; it holds only within skew and pause limits, and only for handlers that honour cancellation [3] | decided 2026-11-04: bounded no-overlap; `JobContext.LeaseToken` added in M1 | decisions D-1, REQ-015; arch §3.1 via issue 11 | decided |
| 3 | D-6 is worded as check-then-write, and `Renew` and `ShutdownNodeAsync` lack a `state='Processing'` fence [5, 6] | no (wording and fence follow from D-6) | REQ-003, REQ-012 | open |
| 4 | D-4's requeue warning has nowhere to appear in M1 [1, 7] | yes: return value, log event or dashboard | decisions D-4, REQ-010 | open |
| 5 | A crash during a rolling deploy leaves a removed recurring job unorphaned [4] | yes: how orphans are swept | new decision D-20, REQ-030 | open |
| 6 | D-8 still open, and its severity overstates a load issue [8] | yes | decisions D-8, REQ-040 | open |
| 7 | D-19 still open; its option 1 breaks rollbacks [8] | yes | decisions D-19, REQ-029 | open |
| 8 | D-18 still open (runtime overrides, removing orphans) | yes | decisions D-18, REQ-031, REQ-033 | open |
| 9 | Store atomicity is assumed by every model but stated nowhere; D-9's reconcile needs an ordering rule [6] | no (states what the models already assume) | REQ list (new cross-cutting rule), arch §4.4 / §5 | open |
| 10 | The `Queue` policy's `Awaiting` backlog has no cap [9] | yes | new decision D-21 | open |
| 11 | Carry D-3 to D-12 and every decision above into the stories and the architecture; add a "Propagated to" line to each decision [1] | no | stories/m1-core, docs/bellhop-architecture.md, decisions.md | open |
| 12 | F1 and F3 disagree on whether a requeue clears a cancel request; re-run F3 [7] | no | iteration 3 models | open |
| 13 | F3's main config keeps a known-failing rule; `NoOverlap` checks a warning flag the design lacks [7] | no | iteration 3 models | open |
| 14 | Models miss the crash, timer and fence cases: F2 deadline timer and skew, F4 crashed nodes and a convergence rule, the architecture's fences as an input [4, 5] | no | iteration 3 models | open |
| 15 | Liveness gaps: a job leaves `Processing`, cleanup eventually runs; REQ-007 and REQ-027 to be owned by M1-19's tests [9] | no | iteration 3 models, M1-19 | open |
| 16 | No way to re-run the checks; TLC logs ignored by git; a full copy of the models per iteration [10] | yes (repo layout) | refinement/README.md | open |
| 17 | Counterexample traces aren't conformance tests yet [10] | no | M1-05, M1-06, M1-07 criteria | open |
