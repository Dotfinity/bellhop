# Findings: Bellhop job lifecycle

<!-- refiner-findings v1 | module: jobs | specHash: 0d2b4b8050debb3b456a934b4d9c36f0895b2b30d4f086e4abcc9b65cca6fb5d | run: 2026-11-08 | previous: specs/model/jobs/previous.findings.md (run 5, specHash b7690959c1ee) -->

**Run:** 2026-11-08 (run 6, from `specs/model/jobs/handoff.json`, base 55ee2c4) · **Requirements file:** `specs/jobs.json` (specHash `0d2b4b8050de`) · **Model:** `model/jobs/Jobs.tla`, `Jobs_Unique.tla`, `Jobs_Throttle.tla`, `Jobs_Flow.tla` · **TLC:** 2.19. Every check ran alone with `--stop-at-first --workers 2` inside `timeout 400`, while three other modules were being checked on the same machine. No TLC exceptions and no timeouts. The largest completed runs were 5,535,056 distinct states in 152 s (`Jobs_HoldsQ.cfg`), 3,936,009 in 55 s (`Jobs_Flow_P1b.cfg`) and 2,701,996 in 39–66 s (`Jobs_Holds.cfg`, the CHK and GAP runs, `Jobs_SCN124.cfg`).
**Result:** 1 finding: 0 contradictions · 0 gaps · 1 ambiguity · 0 unprovable · 0 modeling notes. Both run-5 findings are resolved.

Only the requirements in the handoff were regenerated: REQ-190 (modified: the shutdown branch lost its "or it throws OperationCanceledException" clause) and REQ-191 (modified: it fires when the system abandons a still-running handler "for whatever reason", and REQ-138, REQ-140, REQ-186 and REQ-190 are in `dependsOn`). SCN-122 and SCN-125 (impacted) were re-checked. `Jobs_Unique.tla`, `Jobs_Throttle.tla` and `Jobs_Flow.tla` are unchanged byte-for-byte, and none of them mentions REQ-190 or REQ-191. They were re-run anyway.

| File | Covers |
|---|---|
| `Jobs.tla` | execution, leases, recovery, retries, timeouts, shutdown, cancellation (REQ-190, REQ-191), requeue, delete, retention, queue pause, maintenance and routing |
| `Jobs_Unique.tla` | unique keys (FEAT-103) on every creating call, and the unique-key side of single and bulk requeue |
| `Jobs_Throttle.tla` | claim order, concurrency keys, rate limits, queue limits, the LongRunning limit, LIV-100 (FEAT-104) |
| `Jobs_Flow.tla` | continuations, chains and batches (FEAT-106), including INV-138, batch-member retention and batch removal (REQ-192) |

What changed in `Jobs.tla`:

- `R190` is now REQ-190's exception branch only. An OperationCanceledException thrown by a cancel-requested job is decided by `R136` alone, at shutdown too.
- `ReleaseOnShutdown`'s cancel branch (REQ-190's shutdown branch) records the abandoned handler (tag `Abandoned`, REQ-191) and leaves the run in mode `abandoned`. `ShutdownCancel` stays as the cause tag, like `Timeout` and `Released`. Run 5's A-18 caveat is withdrawn.
- New action property `Prop_AbandonRecorded` (REQ-191): every step in which the system stops holding a still-running handler (abandoned after a timeout, or released or cancelled at shutdown) records it. It runs in both holds cfgs. On a scratch copy with run 5's behaviour, it fails in 7 steps (the shutdown cancellation with no record), so it is not vacuous.
- New probe `ProbeAct_CancelAfterShutdownSignal` (`Jobs_P4.cfg`) for F-1.
- `run_all.sh`: `TLC_WORKERS` and `TLC_TIMEOUT` override the defaults (4 workers, 170 s). This run used 2 and 400.

To reproduce, run `TLC_WORKERS=2 TLC_TIMEOUT=400 sh run_all.sh` from `specs/model/jobs`.

## Changes since last run

| Finding | Status |
|---|---|
| F-1 (run 5) | resolved. REQ-191 now covers REQ-190's shutdown cancellation. `Prop_AbandonRecorded` holds in `Jobs_Holds.cfg` (MaxAttempts = 2) and `Jobs_HoldsQ.cfg` (MaxAttempts = 1, the case run 5 reported). The path is still reachable, now with the record: `Reach_ShutdownCancelled` (`Jobs_P3.cfg`) is violated as expected, in 7 steps |
| F-2 (run 5) | resolved. `Chk_SingleRule` (`Jobs_CHK2.cfg`) holds again (2,701,996 states): at most one rule decides each throw. `Chk_SingleOutcome` (`Jobs_CHK6.cfg`) still holds |
| F-1 | new: an operator's cancellation can arrive between REQ-139's shutdown token and the node's shutdown write, where neither REQ-140 nor REQ-190 applies as written |

`findings_delta.py specs/model/jobs/previous.findings.md specs/jobs.findings.md`:

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | ambiguity · Reach_ShutdownCancelled · REQ-140,REQ-190,REQ-191 |
| F-2 | resolved | ambiguity · Chk_SingleRule · REQ-136,REQ-190 |
| F-1 | new | ambiguity · ProbeAct_CancelAfterShutdownSignal · REQ-140,REQ-190,hosting.REQ-29 |

2 resolved, 1 new, 0 still open. (The "resolved" rows use run 5's numbers.)

## Summary

| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | ambiguity | low | REQ-190, REQ-140, REQ-139, hosting REQ-29 | A cancellation requested after the node cancelled the token for shutdown, but before its shutdown write, fits neither REQ-140 (its state guard fails) nor REQ-190 (its event came first). Read literally, the job is left to lease expiry and is dead-lettered at its last attempt |

---

## F-1 · ambiguity · low — A cancellation between the shutdown token and the shutdown write fits neither REQ-140 nor REQ-190
<!-- finding: ambiguity | ProbeAct_CancelAfterShutdownSignal | REQ-140,REQ-190,hosting.REQ-29 -->

**Requirements involved**
- REQ-139: *While the job's node is draining, when ShutdownTimeout has passed and the job is still running, the system shall signal the handler's cancellation token.*
- REQ-140: *While the job's node is draining, the job's token was cancelled for shutdown, its timeout token was not signalled **and its cancellation was not requested**, if the handler is still running or throws OperationCanceledException, then the system shall release the job's lease and take back the attempt it counted …*
- REQ-190: ***While** a job is processing and its cancellation was requested, **when** its lease expires with attempts left, **its token was cancelled for shutdown (REQ-139) while its handler is still running**, … the system shall abandon the handler if it is still running and mark the job cancelled …*
- REQ-135: *While a job is processing, when an application or operator cancels it, the system shall record the cancellation request and signal the handler's cancellation token …*
- hosting REQ-29: the node stops once ShutdownTimeout has passed, the tokens were cancelled and *"the lease releases and cancellations that jobs REQ-140 and REQ-190 call for at shutdown were attempted"*.

**What happens** (`Jobs_P4.cfg`: the action probe `ProbeAct_CancelAfterShutdownSignal` is violated as expected, a 7-state trace (6 steps) at MaxAttempts = 1)
1. j1 is enqueued and node n1 claims it at attempt 1 (REQ-120, REQ-123).
2. The host stops n1, so n1 drains (hosting REQ-27). ShutdownTimeout passes.
3. n1 cancels j1's token for shutdown (REQ-139). The handler is still running and n1 has not yet made its shutdown write for j1.
4. **An operator cancels j1** (REQ-135). The request is recorded.

At step 4 REQ-140 no longer applies: its `while` requires that j1's cancellation was not requested. REQ-190's shutdown branch does not apply either. Its `when` is the event "its token was cancelled for shutdown while its handler is still running", and that event happened at step 3, before REQ-190's `while` held. So read literally, neither sentence calls for a write for j1, and hosting REQ-29 lets n1 stop without one. j1's lease then expires, and at its last attempt REQ-133 dead-letters it. With attempts left, REQ-190's lease branch marks it cancelled. This is the outcome run-4 F-1 removed for a request made before the shutdown token.

The model does not take that path. It decides between REQ-140 and REQ-190 when n1 makes the shutdown write, reading the cancellation request as it is then (A-19), so j1 ends Cancelled. Every result above uses that reading.

**Why.** REQ-140 is written as a state (`while` + `if`), so it is judged whenever its conditions hold. REQ-190's shutdown branch is written as an event inside a `while`. Run 5 gave it its own event, the token cancelled for shutdown, and run 6 removed the exception clause. Both changes were correct, but they leave the moment between the event and the write that acts on it undefined. The window is short: the time between cancelling tokens and the shutdown write, while the node is already past ShutdownTimeout. A request made after the write is the case REQ-190's notes and hosting run 5 already accept ("exhausted attempts on … lease expiry still dead-letter").

**Options**
1. *(recommended)* **Make the node's check the trigger.** REQ-190's shutdown branch becomes "its draining node finds its handler still running after cancelling its token for shutdown (REQ-139)". The node's check is the moment REQ-140's `if the handler is still running` is judged too, so REQ-140 and REQ-190 become the two outcomes of one check, and the cancellation request is read when the check is made. One clause, and it is the reading the model already checks. Re-model REQ-190.
2. **Notes only.** Say in REQ-190's notes (and REQ-140's) that the shutdown branch is judged when the node makes its shutdown write, so a request that arrives between the shutdown token and that write is a cancellation. No semantic change, but the sentence on its own still reads as an event.
3. **Accept it.** A request in that window is left to lease expiry, like a request after the write. Say so in REQ-190's notes and in hosting REQ-29's notes. The cost is that a request made while the node is still holding the job, before it stops, can still be dead-lettered at the last attempt.

**Ready to apply (option 1, in `specs/jobs.json`)**
```json
{ "id": "REQ-190", "ears": { "while": "a job is processing and its cancellation was requested",
    "when": "its lease expires with attempts left, its draining node finds its handler still running after cancelling its token for shutdown (REQ-139), its handler is still running TimeoutGracePeriod after its timeout token was signalled, or its handler throws an exception other than OperationCanceledException or PermanentJobFailureException while the attempt number is below maxAttempts and the retry policy allows another attempt",
    "shall": "abandon the handler if it is still running and mark the job cancelled instead of returning it to enqueued, marking it failed or dead-lettering it for the timeout" } }
```
Notes addition: *"refiner-model 2026-11-08 run 6 F-1: the shutdown branch is the node's check that also judges REQ-140, so a cancellation requested after the token was cancelled for shutdown but before that check is a cancellation, not left to lease expiry."*

---

## Also checked (not findings)

- **REQ-191 and REQ-190's lease branch.** REQ-190 also "abandons the handler if it is still running" when the lease expires. The recovering node cannot reach a handler on another node, so the record is made when that node's heartbeat is refused (REQ-191's second trigger, `LeaseLostRecordable`), as SCN-125 shows (`Jobs_SCN125.cfg`, reachable). Both triggers would write the same record ("abandoned or lost its lease"), so this is not reported.
- **An OperationCanceledException at shutdown by a cancel-requested job** is now REQ-136's alone, and ends Cancelled as before (`Chk_SingleRule`, `Chk_SingleOutcome` hold). The draining node does not wait for anything more: a handler that threw is no longer in flight.

## Accepted (not reported as findings)

- **Cancellation that arrives after a draining node stopped** (`Jobs_GAP7.cfg`, run 4's probe, an 11-state trace at MaxAttempts = 1). A timed-out job is still in its grace period when ShutdownTimeout passes, so its node stops without waiting for it, as hosting REQ-29's notes accept. An operator cancels it while it is still Processing with no live node. Its lease expires at its last attempt, and REQ-133 dead-letters it, because REQ-190's lease branch requires attempts left. That is the lease-expiry outcome REQ-190's notes accept, and it is the same as after a crash.
- **LIV-100** (`accepted-unprovable`): strict queue priority and job priority can still starve a job forever (`Jobs_Throttle_L1.cfg` and `Jobs_Throttle_L2.cfg`, lassos). It holds with one queue and equal priority (`L0`) and with a shared concurrency key (`L3`).
- **LIV-102** (`should`, `accepted-unprovable`): a continuation behind an Unroutable parent can still wait forever (`Jobs_Flow_F3.cfg`, lasso). `F1`, `F2`, `F4` and `F5` hold.
- **REQ-143 / run 2 F-6** (accepted in REQ-143's notes): requeuing a cancelled parent does not revive the continuations cancelled with it (`Jobs_Flow_GAP3.cfg`).
- **INV-106, former reading** (handlers executing, abandoned ones included): still violated (`Jobs_INV106.cfg`, `Chk_HandlersWithinLimit`), as the owner accepted in run 1.
- **INV-108/109, former reading** (state invariants): still violated after an operator lowers a limit (`Jobs_Throttle.cfg`, `Chk_KeyMaxState`). The claim-time wording holds (`Jobs_Throttle_Holds.cfg`, `Jobs_Throttle_HoldsK.cfg`).
- **Timed-out job at shutdown, recovered by lease expiry** (REQ-140 and hosting REQ-29 notes): when ShutdownTimeout passes before TimeoutGracePeriod ends, the job comes back through REQ-132 with reason Interrupted and no backoff, rather than through REQ-138 with reason Timeout and retryAt. The attempt counts either way (`Jobs_P2.cfg`), and the notes accept it.

## Runs

| cfg | Result | Distinct states | s |
|---|---|---|---|
| `Jobs_Holds` (now with `Prop_AbandonRecorded`) | holds | 2,701,996 | 65 |
| `Jobs_HoldsQ` (same addition; MaxAttempts = 1) | holds | 5,535,056 | 152 |
| `Jobs_CHK` / `CHK3` / `CHK4` / `CHK5` | hold | 2,701,996 each | 47–50 |
| `Jobs_CHK2` (`Chk_SingleRule`) | **holds** (run 5: violated, F-2) | 2,701,996 | 51 |
| `Jobs_CHK6` (`Chk_SingleOutcome`) | holds | 2,701,996 | 42 |
| `Jobs_GAP1` / `GAP2` / `GAP5` | hold | 2,701,996 each | 39–40 |
| `Jobs_GAP6` | not run: holds by construction since run 4; the full two-slot space does not finish in time | – | – |
| `Jobs_GAP7` | violated, accepted path only: the cancellation arrives after the node stopped | 17,142 | 1 |
| `Jobs_P2` | violated (reachable, accepted path) | 12,914 | 1 |
| `Jobs_P3` (`Reach_ShutdownCancelled`, now with the record) | violated (reachable, as expected) | 2,551 | 1 |
| `Jobs_P4` (new, `ProbeAct_CancelAfterShutdownSignal`) | violated (reachable, as expected; F-1 example) | 1,359 | 1 |
| `Jobs_INV106` | violated (accepted) | 481 | 1 |
| `Jobs_LIV101a` / `LIV101b` | hold | 71,296 / 550,816 | 6 / 36 |
| `Jobs_LIV29` (`Liv_DrainEnds`, hosting REQ-29) | holds | 71,296 | 9 |
| `Jobs_SCN100/101/102/111/112/115/122/124s/125` | traps violated (reachable, as expected) | 73–10,204 | 1 |
| `Jobs_SCN120` / `Jobs_SCN124` | hold | 1,206,848 / 2,701,996 | 15 / 39 |
| `Jobs_Unique`, `U1`–`U5` / `SCN105` | hold / trap violated | 3,220–7,794 / 42 | 1 |
| `Jobs_Throttle_*` (unchanged) | Holds, HoldsK, T0, T2, T3, L0, L3 hold; L1 and L2 (lassos) and `Jobs_Throttle` violated, accepted | ≤ 1,692 | 1 |
| `Jobs_Flow_Holds` / `HoldsC` / `HoldsU` | hold | 1,407,799 / 652,237 / 259,033 | 21 / 10 / 4 |
| `Jobs_Flow_P1b` | holds | 3,936,009 | 55 |
| `Jobs_Flow_F1` / `F2` / `F4` / `F5` | hold | 206,420 / 207,248 / 205,289 / 206,420 | 11–22 |
| `Jobs_Flow_F3` | violated (accepted, LIV-102) | 46,793 | 4 |
| `Jobs_Flow_GAP3b` / `GAP4` | hold | 1,388,164 / 1,396,162 | 12 / 15 |
| `Jobs_Flow_GAP3` / `GAP5` / `GAP6` | violated (accepted / allowed / accepted) | 110,405 / 303 / 2,222 | 1–2 |
| `Jobs_Flow_P1` | violated (the required case since run 4) | 356,280 | 4 |
| `Jobs_Flow_SCN108/114/118/119/121` | traps violated (reachable, as expected) | 152–211,181 | 1–2 |

**Timeouts.** `Jobs.cfg` and `Jobs_LIV101.cfg` (all checks at once) still run split, as in runs 3 to 5, and `Jobs_GAP6` is still not run. No other run hit the limit. Distinct-state counts in `Jobs.tla` differ slightly from run 5 because a run cancelled at shutdown now has mode `abandoned`. The unchanged models differ only where TLC's multi-worker exploration is nondeterministic (`Jobs_Flow_F3`, `GAP3`, `P1`, the scenario traps).

## Modeling assumptions

These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.

| # | Assumption | Affects |
|---|---|---|
| A-1 | No clocks. scheduledAt/retryAt passing, UnroutableAfter, the timeout, TimeoutGracePeriod, ShutdownTimeout and retention (including REQ-192's "every stored member past its retention") are each a nondeterministic event that may happen at any time and, because time passes, eventually does (fair). Backoff lengths, retention lengths and window lengths are not judged. | REQ-100, REQ-104, REQ-122, REQ-124, REQ-130, REQ-137, REQ-145, REQ-183, REQ-187, REQ-189, REQ-192, INV-105 |
| A-2 | A lease is a flag. It can expire at any time while processing (crash, partition or pause), and a late heartbeat from the run that holds the current token renews it (REQ-126 has no "not yet expired" guard). | REQ-102, REQ-126, REQ-132, REQ-133, INV-104, LIV-101 |
| A-3 | A crash removes the node's handlers at once; its leases expire later. A draining node stops as hosting REQ-29's run-5 wording says. "In-flight job" (hosting `Node.inFlightJobs`, not defined) is a running handler that holds its job's current lease. A job settled by REQ-138/186/190, released by REQ-140 or lost to lease expiry is no longer in flight, though its handler may still be running, as hosting REQ-29's notes say. After ShutdownTimeout the node waits for every release REQ-140 calls for and every cancellation REQ-190 calls for. Every such attempt succeeds, because store outages are not modeled here. A stopped node's handlers stop with it. | REQ-132, REQ-139, REQ-140, REQ-190, hosting REQ-29 |
| A-4 | "Holds claims on processing jobs" (REQ-123, INV-106) counts processing jobs whose current lease token is held by the node's live run. Handlers that were abandoned, released or lost their lease are not counted. | INV-106, REQ-123 |
| A-5 | OperationCanceledException is thrown only after a token was signalled. REQ-136 and REQ-138/186 take precedence over REQ-129/131 for it (REQ-136 notes). Every other overlap between the throw rules is checked, not resolved: `Chk_SingleRule` counts the rules (holds again in run 6) and `Chk_SingleOutcome` compares their outcomes (holds). | REQ-129–140, REQ-186, REQ-190 |
| A-6 | "While P, eventually Q" is read as `P ~> (Q \/ ~P)`: the obligation ends when P stops holding, for example when the job is cancelled or deleted. | LIV-100, LIV-101, LIV-102, REQ-192 |
| A-7 | Every run ends eventually (the timeout guarantees it), so a run's outcome is fair in the throttling and flow models. | Jobs_Throttle.tla, Jobs_Flow.tla |
| A-8 | A retried job joins the back of its queue for the "order they were enqueued" rule. | INV-111 |
| A-9 | Rate-limit windows are fixed windows that end nondeterministically; sliding windows are not modeled. | INV-109 |
| A-10 | Continuations are resolved in the same step as their parent's outcome, cancellation, deletion, removal by retention or batch removal, and a cancellation cascades down a chain in that step (REQ-173 notes). | REQ-171–REQ-175, REQ-188, REQ-192 |
| A-11 | In `Jobs_Flow.tla`, removed job slots and removed batches are not reused, so parent links stay valid. Deadlock checking is off there (`--no-deadlock`) because the pool runs out. | Jobs_Flow.tla |
| A-12 | "Every member job" (REQ-179, REQ-180) ranges over the members created with the batch; an explicitly deleted member counts as finished and not succeeded (REQ-180). REQ-192's "every member job that is still stored" skips deleted and retention-removed members. | REQ-179, REQ-180, REQ-192 |
| A-13 | Bounds: 1–4 jobs, 2 nodes, 1 queue (2 in the throttling model), MaxAttempts = 2 (1 for `Jobs_HoldsQ`, `Jobs_LIV101a/b`, `Jobs_LIV29`, `Jobs_GAP7`, `Jobs_P3`, `Jobs_P4`, `Jobs_Flow_Holds`, `Jobs_Flow_GAP3/GAP3b/GAP4`, `Jobs_Flow_P1/P1b`), node limit 1, at most 2 lease tokens per job (1 in `Jobs_LIV101a` and `Jobs_LIV29`), Max and N in {1, 2}, one node's LongRunning limit 1. `Jobs_Flow_P1/P1b` use 4 job slots. One namespace: the per-queue scope of INV-100 under Redis ShardByQueue is not modeled. | all |
| A-14 | One job name; "a handler for its name or one of its aliases" is a per-node handler flag that can change when a node restarts (rolling deploy). | REQ-101, REQ-123, REQ-124, REQ-125 |
| A-15 | A schedule call for a time that is not in the future (REQ-182) is a call that schedules, so ReplaceSchedule applies to it (REQ-150's "the call does not schedule a job"). | REQ-150, REQ-151, REQ-182 |
| A-18 | *(changed in run 6)* REQ-191's record and log line are history only. Abandonment is recorded as the tag `Abandoned` in the step that abandons (`AbandonOnTimeout`, both branches of `ReleaseOnShutdown`), and `Prop_AbandonRecorded` checks that. The tag is per job, not per attempt, so the property is checked where a first attempt is abandoned. The lease-lost trigger is the predicate `LeaseLostRecordable`: a running handler on a live node whose token is not current or whose job is not processing. For a job that was deleted or removed, only the log line can be written, because "that attempt" no longer exists. | REQ-191, INV-128 |
| A-19 | *(new)* Cancelling a token for shutdown (REQ-139) and the shutdown write that releases (REQ-140) or cancels (REQ-190) the job are separate steps. The write reads the cancellation request as it is when the write is made, so a request between the two makes it a cancellation. Read literally, neither sentence applies in that case (F-1). | REQ-139, REQ-140, REQ-190, hosting REQ-29 |

## Coverage

| Modeled | Skipped (reason) |
|---|---|
| REQ-100–102, REQ-104, REQ-106–108, REQ-120–145, REQ-147, REQ-150–152, REQ-156, REQ-158, REQ-160–163, REQ-170–177, REQ-179–192, INV-100, INV-103, INV-104, INV-106–115, INV-118, INV-128–130, INV-135, INV-138, LIV-100–102, SCN-100–112, SCN-114, SCN-115, SCN-117–125 | Inline mode: REQ-146, INV-131–134, INV-137 (call-stack semantics) · data, not state: REQ-105, REQ-148, REQ-154, REQ-155, REQ-165–169, INV-116, INV-117, INV-119–127, INV-136 · no effect on state: REQ-103, REQ-109, INV-105 (absorbed by A-1) · transactions: INV-101, REQ-153, SCN-113 · INV-102 (one atomic call) · strength `may`: REQ-157, REQ-159, REQ-164 · SCN-116 (payload size) · REQ-178 (retired) · REQ-191's log line (only the record is state) |

**Scenario results.** Every positive scenario is reachable (trap violated, as expected): SCN-100, 101, 102, 105, 108, 111, 112, 114, 115, 118, 119, 121, 122 and 125. Every negative scenario holds over the complete bounded state space: SCN-103, 104, 107, 110, 117 and 124 (`Jobs_Holds.cfg`, `Jobs_HoldsQ.cfg`, `Jobs_SCN124.cfg`), SCN-106 (`Jobs_Throttle_Holds/HoldsK.cfg`), SCN-120 (`Jobs_SCN120.cfg`), and SCN-109 and SCN-123 (the flow holds runs). SCN-113 is still skipped. SCN-122 and SCN-125 (impacted) use REQ-190's lease branch and REQ-191's lease-lost trigger, which did not change, and both are still reachable.

**Same-trigger warnings from `validate`.** REQ-127/128/184, REQ-129/131 and REQ-132/133 are modeled as one action each, and REQ-171/174 inside one resolution step. REQ-136 and REQ-190 no longer share a trigger.

**Cross-module.** Under hosting REQ-29, a draining node always stops (`Liv_DrainEnds`, `Jobs_LIV29.cfg`). F-1 touches hosting REQ-29 only through which writes it waits for. Option 1 needs no hosting change, because REQ-29 already waits for "the cancellations that jobs REQ-190 calls for at shutdown".

## Next

Apply the chosen option to `specs/jobs.json` (F-1: REQ-190) with the `refiner-requirements` skill (it validates and diffs), then run this skill again. Findings whose fingerprint disappears are listed as resolved in the next report.
