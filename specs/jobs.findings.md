# Findings: Bellhop job lifecycle

<!-- refiner-findings v1 | module: jobs | specHash: d1c4f5af9f87339150943337d04b6b0e155d916eaf43724355ad60b513bb826c | run: 2026-11-08 | previous: specs/model/jobs/previous.findings.md (run 6, specHash 0d2b4b8050de) -->

**Run:** 2026-11-08 (run 7, from `specs/model/jobs/handoff.json`, base 319dd72) · **Requirements file:** `specs/jobs.json` (specHash `d1c4f5af9f87`) · **Model:** `model/jobs/Jobs.tla`, `Jobs_Unique.tla`, `Jobs_Throttle.tla`, `Jobs_Flow.tla` · **TLC:** 2.19. Every check ran alone with `--stop-at-first --workers 4` inside `timeout 400`, while three other modules were being checked on the same machine. No timeouts. One TLC exception, in the first batch only: the three liveness cfgs stopped at once on "the identifier late is either undefined" (fairness used the subscript `vars`, which now holds the new history variable). After the fix (fairness subscript `jvars`, below) all three were rerun and hold. The largest completed runs were 7,433,296 distinct states in 140 s (`Jobs_HoldsQ.cfg`) and 3,555,212 in 37–50 s (`Jobs_Holds.cfg`, the CHK and GAP runs).
**Result:** 1 finding: 0 contradictions · 0 gaps · 1 ambiguity · 0 unprovable · 0 modeling notes. Run 6's F-1 is resolved.

Only the requirement in the handoff was regenerated: REQ-190 (modified: the shutdown branch is now "its draining node finds its handler still running after cancelling its token for shutdown (REQ-139)"). REQ-191, SCN-122 and SCN-125 (impacted) were re-checked. `Jobs_Unique.tla`, `Jobs_Throttle.tla` and `Jobs_Flow.tla` are unchanged byte-for-byte, and none of them mentions REQ-190. They were re-run anyway, because they are cheap.

| File | Covers |
|---|---|
| `Jobs.tla` | execution, leases, recovery, retries, timeouts, shutdown, cancellation (REQ-190, REQ-191), requeue, delete, retention, queue pause, maintenance and routing |
| `Jobs_Unique.tla` | unique keys (FEAT-103) on every creating call, and the unique-key side of single and bulk requeue |
| `Jobs_Throttle.tla` | claim order, concurrency keys, rate limits, queue limits, the LongRunning limit, LIV-100 (FEAT-104) |
| `Jobs_Flow.tla` | continuations, chains and batches (FEAT-106), including INV-138, batch-member retention and batch removal (REQ-192) |

What changed in `Jobs.tla`:

- **The node's check is now an event of its own.** Each run gets a flag `chk`. `ReleaseOnShutdown` (REQ-140's still-running branch and REQ-190's shutdown branch) is the check, made once, and it reads the cancellation request and the timeout signal as they are when it is made. The new action `ShutdownCheckLeaves` is the third outcome of the same check: the handler is still running, its timeout token was signalled and no cancellation was requested, so neither sentence applies and the run stays on its timeout path. Before run 7 the model had no check at all: it re-read the request whenever the run was still in flight, so a request that came after that moment was still cancelled at shutdown.
- `NodeStop` (hosting REQ-29) now waits until every in-flight run was checked, instead of using run 6's `R140Pending` and `R190Pending`. Both are removed.
- New history variable `late`: jobs whose cancellation was requested after their token was cancelled for shutdown and before the node's check, which is run 6's F-1 window. `Next` sets it and no action reads it. Fairness now uses the subscript `jvars`, which leaves `late` out.
- `ProbeAct_CancelAfterShutdownSignal` is replaced by two regression checks for run 6's F-1. `Prop_LateCancelNotLeft` (in both holds cfgs) says a draining node never stops while a late-requested run is still in flight. `Reach_LateCancelled` (`Jobs_P4.cfg`) says the late request ends Cancelled at the check, with the handler abandoned and recorded. On a scratch copy with run 6's literal reading (the shutdown event came before the request, so neither sentence calls for a write), `Prop_LateCancelNotLeft` is violated in 9 states, so it is not vacuous.
- New probe `Reach_LateLeaseExpiryFirst` (`Jobs_P5.cfg`) for the lease-expiry race. `Chk_NoCancelLeftAtStop` moved out of the holds cfgs into its own cfg, `Jobs_GAP8.cfg`, because a request after the check now violates it. That is F-1's example. The check itself was not weakened.
- `Claim` creates its run with `chk |-> FALSE`. This edit is mechanical: it changes no guard.
- `run_all.sh` runs `Jobs_GAP8` and `Jobs_P5` too. run_tlc's own `--timeout` is now `TLC_TIMEOUT - 10` instead of a fixed 160 s.

To reproduce, run `TLC_WORKERS=4 TLC_TIMEOUT=400 sh run_all.sh` from `specs/model/jobs`.

## Changes since last run

| Finding | Status |
|---|---|
| F-1 (run 6) | resolved. With REQ-190's new trigger, a cancellation that arrives between the shutdown token and the node's check is read by that check. `Prop_LateCancelNotLeft` holds in `Jobs_Holds.cfg` (MaxAttempts = 2) and `Jobs_HoldsQ.cfg` (MaxAttempts = 1). `Reach_LateCancelled` (`Jobs_P4.cfg`) is violated as expected: at its last attempt j1 ends Cancelled, with its handler abandoned and recorded (8 states) |
| F-1 | new: hosting REQ-29's note promises that a cancel-requested job ends Cancelled at a graceful stop. A request after the node's check, on a timed-out handler, is left to lease expiry, as REQ-190's new note accepts |

`findings_delta.py specs/model/jobs/previous.findings.md specs/jobs.findings.md`:

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | ambiguity · ProbeAct_CancelAfterShutdownSignal · REQ-140,REQ-190,hosting.REQ-29 |
| F-1 | new | ambiguity · Chk_NoCancelLeftAtStop · REQ-140,REQ-190,hosting.REQ-29 |

1 resolved, 1 new, 0 still open. (The "resolved" row uses run 6's number.)

## Summary

| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | ambiguity | low | REQ-190, REQ-140, REQ-138, REQ-133, hosting REQ-29 | Hosting REQ-29's note says a cancel-requested job "ends Cancelled at a graceful stop, even at its last attempt". A request that arrives after the node's check, while a timed-out handler is still in its grace period, lets the node stop without a cancellation. Lease expiry then dead-letters the job at its last attempt, as REQ-190's new note accepts |

---

## F-1 · ambiguity · low — A cancellation after the node's check is left to lease expiry, but hosting REQ-29's note promises Cancelled
<!-- finding: ambiguity | Chk_NoCancelLeftAtStop | REQ-190,REQ-140,hosting.REQ-29 -->

**Requirements involved**
- REQ-190: *While a job is processing and its cancellation was requested, when … **its draining node finds its handler still running after cancelling its token for shutdown (REQ-139)**, its handler is still running TimeoutGracePeriod after its timeout token was signalled, … the system shall abandon the handler if it is still running and mark the job cancelled …* Notes (run 6 F-1): *"… A request made after that check is still left to lease expiry, as above."*
- REQ-140: *While the job's node is draining, the job's token was cancelled for shutdown, **its timeout token was not signalled** and its cancellation was not requested, if the handler is still running or throws OperationCanceledException, then the system shall release the job's lease …* Notes: *"this sentence and REQ-190's shutdown branch are judged at the same check, made by the draining node after it cancels the token."*
- hosting REQ-29: *While a node is draining, when every in-flight job has finished, or ShutdownTimeout has passed, the remaining jobs' tokens were cancelled and the lease releases and cancellations that jobs REQ-140 and REQ-190 call for at shutdown were attempted, the system shall stop the node.* Notes: *"jobs run 4 F-1: the node also waits for the cancellations jobs REQ-190 makes at shutdown, **so a job whose cancellation was requested ends Cancelled at a graceful stop, even at its last attempt**; without the wait, lease expiry dead-lettered it (jobs REQ-133)."*
- REQ-133: *While a job is processing, when its leaseExpiresAt has passed …, if the attempt number has reached maxAttempts, the system shall let any running worker node move the job to dead-lettered with reason Interrupted.*

**What happens** (`Jobs_GAP8.cfg`: `Chk_NoCancelLeftAtStop` is violated, an 11-state trace at MaxAttempts = 1. `Jobs_GAP7.cfg`, `Gap_CancelledDeadLetteredAfterDrain`, reaches the dead letter of step 8 by the same path in 12 states, with the lease expiring earlier and the node names swapped.)
1. j1 is enqueued and node n2 claims it at attempt 1, its last attempt (REQ-120, REQ-123).
2. j1 runs past its timeout, so its token is signalled (REQ-137). TimeoutGracePeriod starts (REQ-187).
3. The host stops n2, so n2 drains (hosting REQ-27). ShutdownTimeout passes before the grace period ends.
4. n2 cancels j1's token for shutdown (REQ-139).
5. n2 makes its check and finds the handler still running. The timeout token was signalled, so REQ-140 does not apply. No cancellation was requested, so REQ-190 does not apply either. j1 stays on its timeout path.
6. **An operator cancels j1** (REQ-135). The request is recorded and the token is signalled.
7. hosting REQ-29 lets n2 stop. ShutdownTimeout has passed, every token was cancelled, and the check called for no release or cancellation. j1 is still Processing with its cancellation requested (`DrainLeftCancel`).
8. j1's lease expires and n1 recovers it. REQ-190's lease branch needs attempts left, so REQ-133 moves j1 to **DeadLettered** with reason Interrupted.

Steps 1–8 follow the sentences, and REQ-190's new note says so: "a request made after that check is still left to lease expiry". The note on hosting REQ-29 says the opposite: it promises Cancelled at a graceful stop, even at the last attempt. A reader who trusts the note there would expect step 8 to be impossible.

A request after the check can only meet this one case. REQ-140 releases every other still-running handler at the check, and REQ-190 cancels it, so only a timed-out handler still in its grace period stays in flight after the check. Two races decide whether this case ends Cancelled. If the grace period ends before n2 stops, REQ-190's timeout branch cancels j1. If the handler throws OperationCanceledException first, REQ-136 cancels it. Otherwise the node stops and lease expiry dead-letters it, as above. Run 6's GAP7 path (a request after the node stopped) is still possible. It is no longer the shortest trace.

**Why.** Run 6 F-1 option 1 made the check the trigger, and REQ-190's note accepts what that leaves behind. hosting REQ-29's note was written in run 4, when the model and the note both treated "cancellation requested before the node stops" as the boundary. The boundary is now the check, so the note promises more than the sentences give. The note is not normative, so the severity is low. It is the only text that tells an implementer of the drain what to expect.

**Options**
1. *(recommended)* **Correct the notes.** Change hosting REQ-29's note to name the check as the boundary, and make REQ-190's "as above" say what it means. No behaviour changes. The fix is in **hosting.json** (another module) and in jobs REQ-190's notes.
2. **Wait for late requests too.** Make the drain wait, after ShutdownTimeout, for a handler whose cancellation is requested before the node stops. For example, change hosting REQ-29's trigger to "… and the lease releases and cancellations that jobs REQ-140 and REQ-190 call for at shutdown, **and the cancellation of any in-flight job whose cancellation is requested before the node stops**, were attempted". A job would then end Cancelled whenever the request arrives while its node is alive. The cost is a second shutdown check in REQ-190 (another branch, so another re-model), and a drain that can be held after ShutdownTimeout by any operator request.
3. **Accept it silently.** Change nothing. The jobs side already says it, but the hosting note stays wrong.

**Ready to apply (option 1)**

In `specs/hosting.json`, REQ-29 `notes`: replace the last sentence ("jobs run 4 F-1 (recommended option): the node also waits … (jobs REQ-133).") with
```json
{ "id": "REQ-29", "notes": "… jobs run 4 F-1 (recommended option): the node also waits for the cancellations jobs REQ-190 makes at shutdown, so a job whose cancellation was requested before the node's shutdown check (jobs REQ-140, REQ-190) ends Cancelled at a graceful stop, even at its last attempt; without the wait, lease expiry dead-lettered it (jobs REQ-133). jobs run 7 F-1: a request made after that check can only find a timed-out handler still in its grace period; the node does not wait for it, so unless REQ-190's timeout branch or REQ-136 settles it before the node stops, lease expiry decides (cancelled with attempts left, dead-lettered at the last attempt), as after a crash." }
```
In `specs/jobs.json`, REQ-190 `notes`: replace the final sentence "A request made after that check is still left to lease expiry, as above." with
```json
{ "id": "REQ-190", "notes": "… A request made after that check can only find a timed-out handler still in its grace period (the check released or cancelled every other one); it is cancelled by the timeout branch if the node is still running when TimeoutGracePeriod ends, and otherwise left to lease expiry, which dead-letters it at its last attempt (REQ-133) — refiner-model run 7 F-1." }
```

---

## Also checked (not findings)

These are the cases in the window between the shutdown token (REQ-139) and the node's check that the new wording had to cover. None of them leaves a hole.

- **The handler throws OperationCanceledException in the window.** The run ends there, so the check never finds it. The job goes to REQ-136 (Cancelled) if its cancellation was requested, to REQ-138/186 (timeout, counted) if its timeout token was signalled, and to REQ-140's exception branch (released) otherwise. `Chk_SingleRule` (`Jobs_CHK2.cfg`) and `Chk_SingleOutcome` (`Jobs_CHK6.cfg`) hold over 3,555,212 states: at most one rule decides each throw.
- **The handler throws another exception in the window.** REQ-129 or REQ-131 apply as usual. A cancel-requested job goes to REQ-190's exception branch (Cancelled) with attempts left, and to REQ-131 (dead-lettered) at its last attempt. REQ-190's notes accept that ("a cancel request stops the next attempt, it does not rewrite how this attempt ended"). Both checks above cover it.
- **The timeout token is signalled in the window.** REQ-140's "its timeout token was not signalled" is read at the check, so the job is not released whichever signal came first. REQ-140's note speaks only of a timeout "before the shutdown signal", but the sentence decides. REQ-190's shutdown branch has no timeout guard, so a cancel-requested job ends Cancelled either way. `Scn124_TimedOutNotReleased` (both holds cfgs) and `Chk_TimeoutReleaseSplit` (`Jobs_CHK5.cfg`) hold for both orders of the two signals. The not-released job then follows the accepted timeout path below (`Jobs_P2.cfg`, reachable).
- **The lease expires in the window.** If no node has recovered the job yet, the check is made as usual. If a running worker node recovers it first, the job leaves Processing, the draining node's run is no longer current and the check does nothing. The handler is then lease-lost and recorded through REQ-191's heartbeat trigger. A late request at the last attempt can therefore be dead-lettered while its draining node still holds the run (`Jobs_P5.cfg`, `Reach_LateLeaseExpiryFirst`, 9 states: the lease expires, n1 drains, its token is cancelled, an operator cancels, and n2 recovers j1 under REQ-133 before n1's check). This is the lease-expiry race REQ-190's notes accept, and the same as a crash. Both writes are guarded by the lease, so only one of them lands.
- **"Its draining node" for a run that lost its lease.** If another node recovers and claims the job again, the old node is no longer "its node" (A-20). Neither REQ-140 nor REQ-190 lets it release or cancel the job under another node's lease. INV-128 lists renew, progress, complete and fail, not the shutdown write, so this protection comes from "its", not from fencing.
- **hosting REQ-29 still lets the drain end.** `Liv_DrainEnds` (`Jobs_LIV29.cfg`) holds (87,496 states). The check is a system step with weak fairness, so every in-flight run is checked and then released, cancelled or left on its timeout path. `Jobs_LIV101a`/`LIV101b` (LIV-101) hold too.
- **REQ-191.** `Prop_AbandonRecorded` holds in both holds cfgs: the shutdown cancellation at the check records the abandoned handler. A run that the check leaves on its timeout path is not abandoned (its mode stays `running`), so nothing is recorded until its timeout or its node's stop settles it.
- **SCN-122 and SCN-125** (impacted) use REQ-190's lease branch, which did not change. Both traps are still reachable (`Jobs_SCN122.cfg`, `Jobs_SCN125.cfg`).
- **Who makes the check.** No sentence says on its own that the draining node checks every handler after cancelling its token. REQ-140's notes say it does ("made by the draining node after it cancels the token"), and REQ-190's trigger presupposes it. The model makes the check for every in-flight run before the node stops (A-19). If the owner wants that in a sentence rather than a note, REQ-139's `shall` could end "… and then check whether the handler is still running (REQ-140, REQ-190)". Not reported, because REQ-140's still-running branch already cannot be met without that check.

## Accepted (not reported as findings)

- **Cancellation that arrives after a draining node stopped** (`Jobs_GAP7.cfg`, run 4's probe). Its shortest trace is now F-1's path, a request after the check (12 states). The path of run 4 to run 6 (a request after the node stopped, with no live node) is still possible. The lease-expiry outcome is the one REQ-190's notes accept, and the same as after a crash.
- **LIV-100** (`accepted-unprovable`): strict queue priority and job priority can still starve a job forever (`Jobs_Throttle_L1.cfg` and `Jobs_Throttle_L2.cfg`, lassos). It holds with one queue and equal priority (`L0`) and with a shared concurrency key (`L3`).
- **LIV-102** (`should`, `accepted-unprovable`): a continuation behind an Unroutable parent can still wait forever (`Jobs_Flow_F3.cfg`, lasso). `F1`, `F2`, `F4` and `F5` hold.
- **REQ-143 / run 2 F-6** (accepted in REQ-143's notes): requeuing a cancelled parent does not revive the continuations cancelled with it (`Jobs_Flow_GAP3.cfg`).
- **INV-106, former reading** (handlers executing, abandoned ones included): still violated (`Jobs_INV106.cfg`, `Chk_HandlersWithinLimit`), as the owner accepted in run 1.
- **INV-108/109, former reading** (state invariants): still violated after an operator lowers a limit (`Jobs_Throttle.cfg`, `Chk_KeyMaxState`). The claim-time wording holds (`Jobs_Throttle_Holds.cfg`, `Jobs_Throttle_HoldsK.cfg`).
- **Timed-out job at shutdown, recovered by lease expiry** (REQ-140 and hosting REQ-29 notes): when ShutdownTimeout passes before TimeoutGracePeriod ends, the job comes back through REQ-132 with reason Interrupted and no backoff, rather than through REQ-138 with reason Timeout and retryAt. The attempt counts either way (`Jobs_P2.cfg`), and the notes accept it.

## Runs

| cfg | Result | Distinct states | s |
|---|---|---|---|
| `Jobs_Holds` (now with `Prop_LateCancelNotLeft`; `Chk_NoCancelLeftAtStop` moved to GAP8) | holds | 3,555,212 | 50 |
| `Jobs_HoldsQ` (same changes; MaxAttempts = 1) | holds | 7,433,296 | 140 |
| `Jobs_CHK` / `CHK3` / `CHK4` / `CHK5` | hold | 3,555,212 each | 37–40 |
| `Jobs_CHK2` (`Chk_SingleRule`) | holds | 3,555,212 | 40 |
| `Jobs_CHK6` (`Chk_SingleOutcome`) | holds | 3,555,212 | 39 |
| `Jobs_GAP1` / `GAP2` / `GAP5` | hold | 3,555,212 each | 41–42 |
| `Jobs_GAP6` | not run: holds by construction since run 4; the full two-slot space does not finish in time | – | – |
| `Jobs_GAP7` | violated, accepted path (shortest trace is now F-1's) | 33,317 | 2 |
| `Jobs_GAP8` (new, `Chk_NoCancelLeftAtStop`) | violated (F-1 example, 11 states) | 13,249 | 1 |
| `Jobs_P2` | violated (reachable, accepted path) | 28,654 | 1 |
| `Jobs_P3` (`Reach_ShutdownCancelled`) | violated (reachable, as expected) | 2,754 | 1 |
| `Jobs_P4` (now `Reach_LateCancelled`, run-6 F-1 regression) | violated (reachable, as expected, 8 states) | 3,184 | 1 |
| `Jobs_P5` (new, `Reach_LateLeaseExpiryFirst`) | violated (reachable, accepted race, 9 states) | 5,418 | 1 |
| `Jobs_INV106` | violated (accepted) | 497 | 1 |
| `Jobs_LIV101a` / `LIV101b` | hold (rerun after the fairness fix) | 87,496 / 664,576 | 6 / 40 |
| `Jobs_LIV29` (`Liv_DrainEnds`, hosting REQ-29) | holds (rerun after the fairness fix) | 87,496 | 11 |
| `Jobs_SCN100/101/102/111/112/115/122/124s/125` | traps violated (reachable, as expected) | 148–9,099 | 1 |
| `Jobs_SCN120` / `Jobs_SCN124` | hold | 1,433,536 / 3,555,212 | 14 / 37 |
| `Jobs_Unique`, `U1`–`U5` / `SCN105` (unchanged) | hold / trap violated | 3,220–7,794 / 51 | 1 |
| `Jobs_Throttle_*` (unchanged) | Holds, HoldsK, T0, T2, T3, L0, L3 hold; L1 and L2 (lassos) and `Jobs_Throttle` violated, accepted | ≤ 1,692 | 1 |
| `Jobs_Flow_Holds` / `HoldsC` / `HoldsU` (unchanged) | hold | 1,407,799 / 652,237 / 259,033 | 14 / 8 / 4 |
| `Jobs_Flow_P1b` | holds | 3,936,009 | 36 |
| `Jobs_Flow_F1` / `F2` / `F4` / `F5` | hold | 206,420 / 207,248 / 205,289 / 206,420 | 10–16 |
| `Jobs_Flow_F3` | violated (accepted, LIV-102) | 70,639 | 4 |
| `Jobs_Flow_GAP3b` / `GAP4` | hold | 1,388,164 / 1,396,162 | 8 / 11 |
| `Jobs_Flow_GAP3` / `GAP5` / `GAP6` | violated (accepted / allowed / accepted) | 116,826 / 380 / 3,082 | 1–2 |
| `Jobs_Flow_P1` | violated (the required case since run 4) | 459,207 | 4 |
| `Jobs_Flow_SCN108/114/118/119/121` | traps violated (reachable, as expected) | 194–262,899 | 1–2 |

The safety runs in `Jobs.tla` ran before the fairness-subscript fix. The fix touches only `Fairness`, which safety checking does not use.

**Timeouts and exceptions.** `Jobs.cfg` and `Jobs_LIV101.cfg` (all checks at once) still run split, as in runs 3 to 6, and `Jobs_GAP6` is still not run. No run hit the limit. The only exception was the fairness subscript in the first batch (see the top of this report). It was fixed before the liveness runs that count. Distinct-state counts in `Jobs.tla` are higher than in run 6 (3,555,212 vs 2,701,996 at MaxAttempts = 2), because of the `chk` flag and the `late` history variable. The unchanged models differ from run 6 only where TLC's multi-worker exploration is nondeterministic (`Jobs_Flow_F3`, `GAP3`, `P1`, the scenario traps).

## Modeling assumptions

These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.

| # | Assumption | Affects |
|---|---|---|
| A-1 | No clocks. scheduledAt/retryAt passing, UnroutableAfter, the timeout, TimeoutGracePeriod, ShutdownTimeout and retention (including REQ-192's "every stored member past its retention") are each a nondeterministic event that may happen at any time and, because time passes, eventually does (fair). Backoff lengths, retention lengths and window lengths are not judged. | REQ-100, REQ-104, REQ-122, REQ-124, REQ-130, REQ-137, REQ-145, REQ-183, REQ-187, REQ-189, REQ-192, INV-105 |
| A-2 | A lease is a flag. It can expire at any time while processing (crash, partition or pause), and a late heartbeat from the run that holds the current token renews it (REQ-126 has no "not yet expired" guard). | REQ-102, REQ-126, REQ-132, REQ-133, INV-104, LIV-101 |
| A-3 | A crash removes the node's handlers at once; its leases expire later. A draining node stops as hosting REQ-29's run-5 wording says. "In-flight job" (hosting `Node.inFlightJobs`, not defined) is a running handler that holds its job's current lease. A job settled by REQ-138/186/190, released by REQ-140 or lost to lease expiry is no longer in flight, though its handler may still be running, as hosting REQ-29's notes say. After ShutdownTimeout the node waits for its check of every in-flight run (A-19) and for the release or cancellation that check calls for. Every such attempt succeeds, because store outages are not modeled here. A stopped node's handlers stop with it. | REQ-132, REQ-139, REQ-140, REQ-190, hosting REQ-29 |
| A-4 | "Holds claims on processing jobs" (REQ-123, INV-106) counts processing jobs whose current lease token is held by the node's live run. Handlers that were abandoned, released or lost their lease are not counted. | INV-106, REQ-123 |
| A-5 | OperationCanceledException is thrown only after a token was signalled. REQ-136 and REQ-138/186 take precedence over REQ-129/131 for it (REQ-136 notes). Every other overlap between the throw rules is checked, not resolved: `Chk_SingleRule` counts the rules (holds) and `Chk_SingleOutcome` compares their outcomes (holds). | REQ-129–140, REQ-186, REQ-190 |
| A-6 | "While P, eventually Q" is read as `P ~> (Q \/ ~P)`: the obligation ends when P stops holding, for example when the job is cancelled or deleted. | LIV-100, LIV-101, LIV-102, REQ-192 |
| A-7 | Every run ends eventually (the timeout guarantees it), so a run's outcome is fair in the throttling and flow models. | Jobs_Throttle.tla, Jobs_Flow.tla |
| A-8 | A retried job joins the back of its queue for the "order they were enqueued" rule. | INV-111 |
| A-9 | Rate-limit windows are fixed windows that end nondeterministically; sliding windows are not modeled. | INV-109 |
| A-10 | Continuations are resolved in the same step as their parent's outcome, cancellation, deletion, removal by retention or batch removal, and a cancellation cascades down a chain in that step (REQ-173 notes). | REQ-171–REQ-175, REQ-188, REQ-192 |
| A-11 | In `Jobs_Flow.tla`, removed job slots and removed batches are not reused, so parent links stay valid. Deadlock checking is off there (`--no-deadlock`) because the pool runs out. | Jobs_Flow.tla |
| A-12 | "Every member job" (REQ-179, REQ-180) ranges over the members created with the batch; an explicitly deleted member counts as finished and not succeeded (REQ-180). REQ-192's "every member job that is still stored" skips deleted and retention-removed members. | REQ-179, REQ-180, REQ-192 |
| A-13 | Bounds: 1–4 jobs, 2 nodes, 1 queue (2 in the throttling model), MaxAttempts = 2 (1 for `Jobs_HoldsQ`, `Jobs_LIV101a/b`, `Jobs_LIV29`, `Jobs_GAP7`, `Jobs_GAP8`, `Jobs_P3`, `Jobs_P4`, `Jobs_P5`, `Jobs_Flow_Holds`, `Jobs_Flow_GAP3/GAP3b/GAP4`, `Jobs_Flow_P1/P1b`), node limit 1, at most 2 lease tokens per job (1 in `Jobs_LIV101a` and `Jobs_LIV29`), Max and N in {1, 2}, one node's LongRunning limit 1. `Jobs_Flow_P1/P1b` use 4 job slots. One namespace: the per-queue scope of INV-100 under Redis ShardByQueue is not modeled. | all |
| A-14 | One job name; "a handler for its name or one of its aliases" is a per-node handler flag that can change when a node restarts (rolling deploy). | REQ-101, REQ-123, REQ-124, REQ-125 |
| A-15 | A schedule call for a time that is not in the future (REQ-182) is a call that schedules, so ReplaceSchedule applies to it (REQ-150's "the call does not schedule a job"). | REQ-150, REQ-151, REQ-182 |
| A-18 | REQ-191's record and log line are history only. Abandonment is recorded as the tag `Abandoned` in the step that abandons (`AbandonOnTimeout`, both outcomes of the shutdown check in `ReleaseOnShutdown`), and `Prop_AbandonRecorded` checks that. The tag is per job, not per attempt, so the property is checked where a first attempt is abandoned. The lease-lost trigger is the predicate `LeaseLostRecordable`: a running handler on a live node whose token is not current or whose job is not processing. For a job that was deleted or removed, only the log line can be written, because "that attempt" no longer exists. | REQ-191, INV-128 |
| A-19 | *(changed in run 7: it is now the requirement)* Cancelling a token for shutdown (REQ-139) and the node's check are separate steps. Following REQ-190's new trigger and REQ-140's notes, the check is made once per in-flight run, before the node stops, and it reads the cancellation request and the timeout signal as they are then. It has three outcomes: release (REQ-140), cancel (REQ-190) or neither (a timed-out run with no request, left on its timeout path). The only remaining assumption is that the check is always made, which only REQ-140's notes say ("Also checked"). | REQ-139, REQ-140, REQ-190, hosting REQ-29 |
| A-20 | *(new)* "The job's node" (REQ-140) and "its draining node" (REQ-190) are the node whose run holds the job's current lease token. A node whose run lost its lease to another node's claim makes no shutdown write for that job. | REQ-140, REQ-190, INV-128 |

## Coverage

| Modeled | Skipped (reason) |
|---|---|
| REQ-100–102, REQ-104, REQ-106–108, REQ-120–145, REQ-147, REQ-150–152, REQ-156, REQ-158, REQ-160–163, REQ-170–177, REQ-179–192, INV-100, INV-103, INV-104, INV-106–115, INV-118, INV-128–130, INV-135, INV-138, LIV-100–102, SCN-100–112, SCN-114, SCN-115, SCN-117–125 | Inline mode: REQ-146, INV-131–134, INV-137 (call-stack semantics) · data, not state: REQ-105, REQ-148, REQ-154, REQ-155, REQ-165–169, INV-116, INV-117, INV-119–127, INV-136 · no effect on state: REQ-103, REQ-109, INV-105 (absorbed by A-1) · transactions: INV-101, REQ-153, SCN-113 · INV-102 (one atomic call) · strength `may`: REQ-157, REQ-159, REQ-164 · SCN-116 (payload size) · REQ-178 (retired) · REQ-191's log line (only the record is state) |

**Scenario results.** Every positive scenario is reachable (trap violated, as expected): SCN-100, 101, 102, 105, 108, 111, 112, 114, 115, 118, 119, 121, 122 and 125. Every negative scenario holds over the complete bounded state space: SCN-103, 104, 107, 110, 117 and 124 (`Jobs_Holds.cfg`, `Jobs_HoldsQ.cfg`, `Jobs_SCN124.cfg`), SCN-106 (`Jobs_Throttle_Holds/HoldsK.cfg`), SCN-120 (`Jobs_SCN120.cfg`), and SCN-109 and SCN-123 (the flow holds runs). SCN-113 is still skipped.

**Same-trigger warnings from `validate`.** REQ-127/128/184, REQ-129/131 and REQ-132/133 are modeled as one action each, and REQ-171/174 inside one resolution step. REQ-140's still-running branch and REQ-190's shutdown branch are now one action by design: two outcomes of one check.

**Cross-module.** F-1's fix is a note in **hosting.json** (REQ-29), plus a note in jobs REQ-190. Neither changes behaviour. Under hosting REQ-29 a draining node always stops (`Liv_DrainEnds`, `Jobs_LIV29.cfg`). REQ-29's sentence needed no change for run 6's F-1, as the owner expected.

## Next

Apply the chosen option (F-1: REQ-190's notes in `specs/jobs.json`, REQ-29's notes in `specs/hosting.json`) with the `refiner-requirements` skill (it validates and diffs), then run this skill again. Findings whose fingerprint disappears are listed as resolved in the next report.
