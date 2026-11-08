# Findings: Bellhop job lifecycle

<!-- refiner-findings v1 | module: jobs | specHash: d1c4f5af9f87339150943337d04b6b0e155d916eaf43724355ad60b513bb826c | run: 2026-11-08 | previous: specs/model/jobs/previous.findings.md (run 7, specHash d1c4f5af9f87) -->

**Run:** 2026-11-08 (run 8, from `specs/model/jobs/handoff.json`, base ed02be0) · **Requirements file:** `specs/jobs.json` (specHash `d1c4f5af9f87`, unchanged: run 7's fix is notes only) · **Model:** `model/jobs/Jobs.tla`, `Jobs_Unique.tla`, `Jobs_Throttle.tla`, `Jobs_Flow.tla`, plus the new probe modules `Jobs_AfterChk.tla` and `Jobs_AfterChkG.tla` · **TLC:** 2.19. The full batch ran with `TLC_WORKERS=4 TLC_TIMEOUT=400 sh run_all.sh`, every check alone with `--stop-at-first`, while three other modules were being checked on the same machine. No timeouts and no TLC exceptions in the run this report rests on. A first batch hit an error in the new probe module only: the cfgs that use `Spec` failed with "current state is not a legal state", because the history variable `g8` was declared in the same module and `Spec` does not constrain it. The probes were split into `Jobs_AfterChk.tla` (no history) and `Jobs_AfterChkG.tla` (with `g8`), and then the full batch was rerun from the start. The largest runs were 7,433,296 distinct states in 172 s (`Jobs_HoldsQ.cfg`) and 3,555,212 in 41–75 s (`Jobs_Holds.cfg`, the CHK, GAP and `Jobs_AfterChk_X` runs).
**Result:** 1 finding: 0 contradictions · 0 gaps · 1 ambiguity · 0 unprovable · 0 modeling notes. Run 7's F-1 is resolved: its path is now accepted in both notes (see *Accepted*).

The handoff is empty (no semantic change), so no requirement was regenerated. `Jobs.tla`, `Jobs_Unique.tla`, `Jobs_Throttle.tla` and `Jobs_Flow.tla` are byte-for-byte as in run 7, and so are all their cfgs. Run 7's fix (commit d3e5d8e) changed only two notes: jobs REQ-190's and hosting REQ-29's. This run checks those notes against the model, and re-reads the rest of the REQ-140, REQ-190 and REQ-191 notes and hosting REQ-29's notes.

| File | Covers |
|---|---|
| `Jobs.tla` | execution, leases, recovery, retries, timeouts, shutdown, cancellation (REQ-190, REQ-191), requeue, delete, retention, queue pause, maintenance and routing |
| `Jobs_Unique.tla` | unique keys (FEAT-103) on every creating call, and the unique-key side of single and bulk requeue |
| `Jobs_Throttle.tla` | claim order, concurrency keys, rate limits, queue limits, the LongRunning limit, LIV-100 (FEAT-104) |
| `Jobs_Flow.tla` | continuations, chains and batches (FEAT-106), including INV-138, batch-member retention and batch removal (REQ-192) |
| `Jobs_AfterChk.tla`, `Jobs_AfterChkG.tla` | *(new, probes only)* `EXTENDS Jobs`. What can settle a run whose cancellation was requested after its draining node's check, and a timed-out run after ShutdownTimeout. They add no action and change no guard |

What is new:

- **`Jobs_AfterChk.tla`.** `LateRun(r)` is a run that the check left on its timeout path (`chk` is set only by `ShutdownCheckLeaves`, which needs no request), whose cancellation was requested afterwards, and which still holds its job's lease on its draining node. Five action properties, `Reach8_*`, each say that one rule never settles such a run. Each is expected to be violated, which means reachable. `Chk8_Exits` says every step that ends `LateRun(r)` is a handler outcome, a lease-expiry recovery, the node's stop or a crash. It holds. On a scratch copy that drops the normal return from the list, it is violated in 11,770 states, so it is not vacuous. `Reach8_TimeoutAfterShutdownTimeout` checks REQ-140's note.
- `Spec8` (in `Jobs_AfterChkG.tla`) is `Jobs`' `Spec` plus one history variable `g8`, which no action reads. It records whether a run's TimeoutGracePeriod ended after ShutdownTimeout or after the check. Only the two timeout probes (`Jobs_AfterChk_T`, `Jobs_AfterChk_ST`) use it. Without it, a grace period that ended *before* the check would count, because grace passing and the abandonment are two steps in the model.
- `run_all.sh` runs the eight `Jobs_AfterChk_*.cfg` too. TLC reports a violated action property as an error, so `run_all.log` shows `error None` for the six `Reach8_` cfgs (`T`, `O`, `R`, `EC`, `ED`, `ST`). That is the expected result.

To reproduce, run `TLC_WORKERS=4 TLC_TIMEOUT=400 sh run_all.sh` from `specs/model/jobs`.

## Changes since last run

| Finding | Status |
|---|---|
| F-1 (run 7) | resolved. Hosting REQ-29's note now names the node's shutdown check as the boundary, and says a request after it is left to lease expiry unless REQ-190's timeout branch or REQ-136 settles it first. REQ-190's note says the same thing, but with the timeout branch only. `Jobs_GAP8` (`Chk_NoCancelLeftAtStop`) is still violated by the same path, which both notes now describe (10 states this run, 11 in run 7: TLC's multi-worker search does not always return the same shortest trace). Moved to *Accepted* |
| F-1 | new: the two notes list different and incomplete outcomes for a request after the check, and REQ-140's note puts the same kind of boundary at ShutdownTimeout. In each case the handler can still settle the job until the node stops |

`findings_delta.py specs/model/jobs/previous.findings.md specs/jobs.findings.md`:

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | ambiguity · Chk_NoCancelLeftAtStop · REQ-140,REQ-190,hosting.REQ-29 |
| F-1 | new | ambiguity · Chk8_Exits · REQ-136,REQ-140,REQ-190,hosting.REQ-29 |

1 resolved, 1 new, 0 still open. (The "resolved" row uses run 7's number.)

## Summary

| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | ambiguity | low | REQ-190, REQ-140, REQ-136, REQ-127, REQ-131, hosting REQ-29 | REQ-190's note says a request after the check is cancelled by the timeout branch "and otherwise left to lease expiry". Hosting REQ-29's note adds REQ-136. Until the node stops, the handler can also end the job through REQ-136 (left out of REQ-190's note), a normal return (REQ-127, Succeeded) or another exception (REQ-190's exception branch, or REQ-131). REQ-140's note says lease expiry counts the attempt "if ShutdownTimeout passes first", but REQ-138/186 can still count it before the node stops |

---

## F-1 · ambiguity · low — Three notes say lease expiry decides, but until the node stops the handler's own outcome still can
<!-- finding: ambiguity | Chk8_Exits | REQ-190,REQ-140,REQ-136,hosting.REQ-29 -->

**Requirements involved**
- REQ-190 notes (run 7 F-1, new): *"A request made after that check can only find a timed-out handler still in its grace period, because the check released or cancelled every other one; **it is cancelled by the timeout branch if the node is still running when TimeoutGracePeriod ends, and otherwise left to lease expiry**, which dead-letters it at its last attempt (REQ-133)."*
- hosting REQ-29 notes (run 7 F-1, new): *"a request made after that check can only find a timed-out handler still in its grace period. The node does not wait for it, so **unless jobs REQ-190's timeout branch or REQ-136 settles it before the node stops, lease expiry decides** (cancelled with attempts left, dead-lettered at the last attempt), as after a crash."*
- REQ-140 notes (run 3 F-1): *"… the draining node counts it as in flight until it settles, up to ShutdownTimeout (hosting REQ-29); **if ShutdownTimeout passes first, lease expiry counts the attempt** (REQ-132, REQ-133)."*
- REQ-136: *While a job is processing and its cancellation was requested, when its handler throws OperationCanceledException, the system shall mark the job cancelled.* Notes: *"If it returns normally the job is Succeeded (REQ-127) … any other exception takes the normal failure path (REQ-129, REQ-131) … If the handler throws another exception … REQ-190 marks it cancelled …"*
- REQ-127: *While a job is processing, when its handler returns without an exception, the system shall mark the job succeeded.*
- REQ-131: *While a job is processing, when its handler throws an exception, if the exception is not an OperationCanceledException thrown after the job's token was cancelled for shutdown, and the attempt number has reached maxAttempts, the retry policy declines another attempt, or the exception is a PermanentJobFailureException, then the system shall move the job to dead-lettered.*
- REQ-190's exception branch: *"… or its handler throws an exception other than OperationCanceledException or PermanentJobFailureException while the attempt number is below maxAttempts and the retry policy allows another attempt"*, which makes the job Cancelled.

**What happens** (`Jobs_AfterChk_O.cfg`: `Reach8_OCE` is violated, a 10-state trace at MaxAttempts = 1.)
1. j1 is enqueued and node n1 claims it at attempt 1, its last attempt (REQ-120, REQ-123).
2. j1 runs past its timeout, so its timeout token is signalled (REQ-137). TimeoutGracePeriod starts (REQ-187).
3. The host stops n1, so n1 drains (hosting REQ-27). ShutdownTimeout passes.
4. n1 cancels j1's token for shutdown (REQ-139).
5. n1 makes its check and finds the handler still running. The timeout token was signalled, so REQ-140 does not apply. No cancellation was requested, so REQ-190's shutdown branch does not apply either. j1 stays on its timeout path (`ShutdownCheckLeaves`).
6. **An operator cancels j1** (REQ-135). The request is recorded and the handler's token is signalled.
7. **The handler honours the token and throws OperationCanceledException.** REQ-136 marks j1 **Cancelled**. n1 is still draining. The timeout branch did not act, and neither did lease expiry.

REQ-190's note allows only the timeout branch or lease expiry here, so step 7 is the outcome it leaves out. It is also the outcome a cooperating handler gives: REQ-135 signals the token so that the handler throws. Hosting REQ-29's note names REQ-136, so the two notes disagree with each other.

The same prefix (steps 1–6) leads to three more outcomes that neither note names. Each one happens on the draining node before it stops:

| Probe | Trace | After step 6 | Outcome |
|---|---|---|---|
| `Jobs_AfterChk_R` (`Reach8_Return`) | 10 states | the handler returns normally | **Succeeded** (REQ-127; REQ-136's notes: "a normal return still marks it succeeded") |
| `Jobs_AfterChk_ED` (`Reach8_ExcDeadLettered`) | 10 states | the handler throws another exception at its last attempt | **DeadLettered** as a failure (REQ-131), not with reason Interrupted by lease expiry |
| `Jobs_AfterChk_EC` (`Reach8_ExcCancelled`, MaxAttempts = 2) | 11 states | at attempt 1 of 2 the handler throws a retryable exception | **Cancelled** by REQ-190's *exception* branch, not its timeout branch |
| `Jobs_AfterChk_T` (`Reach8_Timeout`, `Spec8`) | 12 states | the grace period ends after the request, and n1 is still draining | **Cancelled** by REQ-190's timeout branch, handler abandoned and recorded (REQ-191). This is the case both notes name |

`Chk8_Exits` holds over 3,555,212 states (MaxAttempts = 2) and 1,858,324 states (MaxAttempts = 1). Nothing else settles such a run. The other ways out are lease expiry recovered by a running worker node (REQ-190's lease branch, REQ-132/133), the node's stop (after which lease expiry decides, `Jobs_GAP8`) and a crash.

REQ-140's note has the same shape for a timed-out job with no request (`Jobs_AfterChk_ST.cfg`, `Spec8`: `Reach8_TimeoutAfterShutdownTimeout` is violated, an 8-state trace at MaxAttempts = 1):
1. j1 is claimed at attempt 1 of 1, and its timeout token is signalled.
2. n1 drains and ShutdownTimeout passes. j1 has not settled, so this is the note's "if ShutdownTimeout passes first".
3. TimeoutGracePeriod ends after ShutdownTimeout, before n1 stops.
4. REQ-186 abandons the handler and moves j1 to **DeadLettered with reason Timeout**. Lease expiry does not count this attempt, REQ-186 does.

**Why.** For a request after the check, the boundary is not the check itself. The check only decides that the node will not wait. Until the node stops, the handler is still running on a live node, so every handler-outcome rule still applies to it. Lease expiry decides only once the node has stopped. REQ-140's note puts the same boundary at ShutdownTimeout, but a draining node still cancels the tokens and makes its check after ShutdownTimeout, so the timeout path can still settle the job in that window. Two smaller points:
- REQ-190's "if the node is still running" names a hosting Node state, `Running`. A draining node has left that state (`Node.states`: Starting, Running, Draining, Stopped, StartupFailed). Read literally, the timeout branch never applies here, but the model shows that it does (`Reach8_Timeout`). Hosting REQ-29's note says "before the node stops", which is the reading the sentences support.
- The window is short in practice: it lasts from ShutdownTimeout, or from the check, until the node's own stop sequence ends. The model has no clocks and cannot judge how short (A-1). The outcomes are still reachable whatever the durations are, and REQ-136 needs no timing at all: the request signals the token, and a cooperating handler throws at once.

No sentence is wrong. The behaviour follows REQ-127, REQ-131, REQ-136 and REQ-190 as written, and REQ-136's own notes already list the handler outcomes. The notes are not normative, so the severity is low. They are, however, what an implementer of the drain reads to learn what to expect, and REQ-190's note says something that is not true.

**Options**
1. *(recommended)* **Correct the three notes.** Put the boundary at the node's stop, and point to the handler-outcome rules instead of listing two of them. No behaviour changes. The fix is in jobs REQ-190 and REQ-140, and in **hosting.json** (REQ-29, another module).
2. **Shorten instead of correcting.** Delete the run-7 sentence from REQ-190's notes and the run-3 clause from REQ-140's notes, and keep only hosting REQ-29's note, corrected as in option 1. There is less to keep in step later, but the jobs module then says nothing about a request after the check.
3. **Accept as is.** REQ-136's notes already give the handler outcomes, so a careful reader can piece it together. REQ-190's note keeps saying something false, and the two notes keep disagreeing.

**Ready to apply (option 1)**

In `specs/jobs.json`, REQ-190 `notes`: replace the last two sentences ("A request made after that check can only find … (REQ-133). Run 7 F-1 spelled this out.") with
```json
{ "id": "REQ-190", "notes": "… A request made after that check can only find a timed-out handler still in its grace period, because the check released or cancelled every other one. The node does not wait for it, but until the node stops the handler's own outcome decides, as for any cancel-requested job: REQ-136 if it throws OperationCanceledException, this requirement's timeout branch if it is still running when TimeoutGracePeriod ends, REQ-127 if it returns normally, and this requirement's exception branch or REQ-131 for any other exception. Once the node has stopped, lease expiry decides, and it dead-letters the job at its last attempt (REQ-133). Run 7 F-1 spelled this out; run 8 F-1 completed the list and put the boundary at the node's stop." }
```
In `specs/jobs.json`, REQ-140 `notes`: replace "if ShutdownTimeout passes first, lease expiry counts the attempt (REQ-132, REQ-133)." with
```json
{ "id": "REQ-140", "notes": "… if the node stops first, lease expiry counts the attempt (REQ-132, REQ-133); between ShutdownTimeout and the node's stop, REQ-138 or REQ-186 can still settle it (run 8 F-1)." }
```
In `specs/hosting.json`, REQ-29 `notes`: replace the last sentence ("jobs run 7 F-1: a request made after that check … as after a crash.") with
```json
{ "id": "REQ-29", "notes": "… jobs run 7 F-1: a request made after that check can only find a timed-out handler still in its grace period. The node does not wait for it. Until the node stops, the handler's own outcome decides (jobs REQ-127, REQ-131, REQ-136, and REQ-190's timeout and exception branches); once the node has stopped, lease expiry decides (cancelled with attempts left, dead-lettered at the last attempt), as after a crash. jobs run 8 F-1 completed this list." }
```

---

## Also checked (not findings)

- **"Can only find a timed-out handler still in its grace period"** (both notes). This holds. `ReleaseOnShutdown` takes every other checked run out of flight (released or cancelled), and only `ShutdownCheckLeaves` sets `chk`, which needs the timeout signal. A draining node claims nothing (REQ-123 needs a running node), so after the check no other run of that node can meet the request. One modeling artefact: grace passing and the abandonment are separate steps (A-1), so the model can also check a run whose grace period has just ended and has not yet been abandoned. In the sentences that is one event (REQ-138/186 "still running TimeoutGracePeriod later"), so it is not reported.
- **"The node does not wait for it"** (hosting REQ-29). This holds. `NodeStop` needs only that every in-flight run was checked (`Jobs_GAP8`, 10 states). `Liv_DrainEnds` holds (`Jobs_LIV29.cfg`).
- **A request before the check ends Cancelled at a graceful stop, "even at its last attempt"** (hosting REQ-29). This holds as in run 7. `Prop_LateCancelNotLeft` holds in both holds cfgs, and `Reach_LateCancelled` is reachable (`Jobs_P4`). The exceptions are the ones REQ-190's notes already accept: an exception at the last attempt before the check (REQ-131), and the lease-expiry race (`Jobs_P5`, `Reach_LateLeaseExpiryFirst`).
- **REQ-140's run-6 F-1 note** ("a cancellation requested before that check makes the job cancelled (REQ-190), not released"). This holds. It is the same check as above.
- **REQ-140's run-3 notes** on the timeout guard covering both branches. This holds: `Scn124_TimedOutNotReleased` (both holds cfgs) and `Chk_TimeoutReleaseSplit` (`Jobs_CHK5`). Only the last clause, "if ShutdownTimeout passes first", is part of F-1.
- **REQ-191's notes** (abandoned and lease-lost handlers are recorded; the node claims again once it holds fewer claims than its limit). This holds: `Prop_AbandonRecorded` and `Inv_NodeClaims` (both holds cfgs). `Gap_LeaseLostUnrecorded` (`Jobs_GAP6`, not run) holds by construction since run 4. In `Reach8_Timeout` the late request's handler is abandoned and tagged `Abandoned`. A run left on its timeout path that dies with its node's stop is not "abandoned" by the system (A-3), as in run 7.
- **Hosting REQ-29's older notes** (best-effort release, a timed-out job counted as in flight up to ShutdownTimeout, "only a handler still in its grace period when ShutdownTimeout passes is left to lease expiry"). These hold. The last one is a necessary condition, and the model agrees: every run left in flight at the stop was checked with its timeout signalled.

## Accepted (not reported as findings)

- **A cancellation after the node's check, on a timed-out handler, left to lease expiry** (run 7 F-1, `Jobs_GAP8.cfg`, `Chk_NoCancelLeftAtStop`, 10 states). Both notes now say this path exists: REQ-190's ("otherwise left to lease expiry, which dead-letters it at its last attempt (REQ-133)") and hosting REQ-29's ("The node does not wait for it … lease expiry decides (… dead-lettered at the last attempt), as after a crash"). Which rules can still settle the job before the node stops is F-1, not this path.
- **Cancellation that arrives after a draining node stopped** (`Jobs_GAP7.cfg`, run 4's probe). Its shortest trace is the GAP8 path with an earlier lease expiry (12 states). The lease-expiry outcome is the one REQ-190's notes accept, and the same as after a crash.
- **LIV-100** (`accepted-unprovable`): strict queue priority and job priority can still starve a job forever (`Jobs_Throttle_L1.cfg` and `Jobs_Throttle_L2.cfg`, lassos). It holds with one queue and equal priority (`L0`) and with a shared concurrency key (`L3`).
- **LIV-102** (`should`, `accepted-unprovable`): a continuation behind an Unroutable parent can still wait forever (`Jobs_Flow_F3.cfg`, lasso). `F1`, `F2`, `F4` and `F5` hold.
- **REQ-143 / run 2 F-6** (accepted in REQ-143's notes): requeuing a cancelled parent does not revive the continuations cancelled with it (`Jobs_Flow_GAP3.cfg`).
- **INV-106, former reading** (handlers executing, abandoned ones included): still violated (`Jobs_INV106.cfg`, `Chk_HandlersWithinLimit`), as the owner accepted in run 1.
- **INV-108/109, former reading** (state invariants): still violated after an operator lowers a limit (`Jobs_Throttle.cfg`, `Chk_KeyMaxState`). The claim-time wording holds (`Jobs_Throttle_Holds.cfg`, `Jobs_Throttle_HoldsK.cfg`).
- **Timed-out job at shutdown, recovered by lease expiry** (REQ-140 and hosting REQ-29 notes): when the node stops before TimeoutGracePeriod ends, the job comes back through REQ-132 with reason Interrupted and no backoff, rather than through REQ-138 with reason Timeout and retryAt. The attempt counts either way (`Jobs_P2.cfg`), and the notes accept it. F-1 asks only that REQ-140's note name the node's stop, not ShutdownTimeout, as the point after which this happens.

## Runs

| cfg | Result | Distinct states | s |
|---|---|---|---|
| `Jobs_Holds` | holds | 3,555,212 | 75 |
| `Jobs_HoldsQ` (MaxAttempts = 1) | holds | 7,433,296 | 172 |
| `Jobs_CHK` / `CHK3` / `CHK4` / `CHK5` | hold | 3,555,212 each | 41–42 |
| `Jobs_CHK2` (`Chk_SingleRule`) | holds | 3,555,212 | 43 |
| `Jobs_CHK6` (`Chk_SingleOutcome`) | holds | 3,555,212 | 43 |
| `Jobs_GAP1` / `GAP2` / `GAP5` | hold | 3,555,212 each | 41–47 |
| `Jobs_GAP6` | not run: holds by construction since run 4; the full two-slot space does not finish in time | – | – |
| `Jobs_GAP7` | violated, accepted path | 34,970 | 2 |
| `Jobs_GAP8` (`Chk_NoCancelLeftAtStop`) | violated, now accepted (run 7 F-1 path, 10 states) | 11,857 | 2 |
| `Jobs_P2` | violated (reachable, accepted path) | 29,566 | 2 |
| `Jobs_P3` (`Reach_ShutdownCancelled`) | violated (reachable, as expected) | 2,872 | 1 |
| `Jobs_P4` (`Reach_LateCancelled`) | violated (reachable, as expected, 9 states) | 3,238 | 1 |
| `Jobs_P5` (`Reach_LateLeaseExpiryFirst`) | violated (reachable, accepted race, 9 states) | 5,245 | 1 |
| `Jobs_INV106` | violated (accepted) | 496 | 1 |
| `Jobs_LIV101a` / `LIV101b` | hold | 87,496 / 664,576 | 6 / 41 |
| `Jobs_LIV29` (`Liv_DrainEnds`, hosting REQ-29) | holds | 87,496 | 11 |
| `Jobs_SCN100/101/102/111/112/115/122/124s/125` | traps violated (reachable, as expected) | 126–9,228 | 1 |
| `Jobs_SCN120` / `Jobs_SCN124` | hold | 1,433,536 / 3,555,212 | 16 / 48 |
| `Jobs_AfterChk_O` / `R` / `ED` (new, MaxAttempts = 1) | violated (reachable: REQ-136, REQ-127, REQ-131; F-1) | 12,370 / 12,348 / 12,287 | 1 |
| `Jobs_AfterChk_EC` (new, MaxAttempts = 2) | violated (reachable: REQ-190's exception branch; F-1) | 17,331 | 2 |
| `Jobs_AfterChk_T` (new, `Spec8`) | violated (reachable: REQ-190's timeout branch, as both notes say) | 26,326 | 2 |
| `Jobs_AfterChk_ST` (new, `Spec8`) | violated (reachable: REQ-186 after ShutdownTimeout; F-1) | 2,958 | 1 |
| `Jobs_AfterChk_X` / `X1` (new, `Chk8_Exits`) | hold | 3,555,212 / 1,858,324 | 46 / 27 |
| `Jobs_Unique`, `U1`–`U5` / `SCN105` (unchanged) | hold / trap violated | 3,220–7,794 / 51 | 1 |
| `Jobs_Throttle_*` (unchanged) | Holds, HoldsK, T0, T2, T3, L0, L3 hold; L1 and L2 (lassos) and `Jobs_Throttle` violated, accepted | ≤ 1,692 | 1 |
| `Jobs_Flow_Holds` / `HoldsC` / `HoldsU` (unchanged) | hold | 1,407,799 / 652,237 / 259,033 | 16 / 9 / 4 |
| `Jobs_Flow_P1b` | holds | 3,936,009 | 42 |
| `Jobs_Flow_F1` / `F2` / `F4` / `F5` | hold | 206,420 / 207,248 / 205,289 / 206,420 | 11–19 |
| `Jobs_Flow_F3` | violated (accepted, LIV-102) | 66,911 | 4 |
| `Jobs_Flow_GAP3b` / `GAP4` | hold | 1,388,164 / 1,396,162 | 9 / 12 |
| `Jobs_Flow_GAP3` / `GAP5` / `GAP6` | violated (accepted / allowed / accepted) | 114,188 / 409 / 3,072 | 1–2 |
| `Jobs_Flow_P1` | violated (the required case since run 4) | 458,984 | 4 |
| `Jobs_Flow_SCN108/114/118/119/121` | traps violated (reachable, as expected) | 182–286,637 | 1–3 |

**Timeouts and exceptions.** No run hit the limit, and the complete rerun had no TLC exception. The one exception is described at the top: it was in the first batch's new probe cfgs, which were fixed before the rerun. `Jobs.cfg` and `Jobs_LIV101.cfg` (all checks at once) still run split, as in runs 3 to 7, and `Jobs_GAP6` is still not run. The distinct-state counts of the unchanged models match run 7 wherever a run explores the whole bounded space. They differ only where TLC stops at the first violation, because the multi-worker search is nondeterministic there.

## Modeling assumptions

These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. None changed in run 8.

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
| A-13 | Bounds: 1–4 jobs, 2 nodes, 1 queue (2 in the throttling model), MaxAttempts = 2 (1 for `Jobs_HoldsQ`, `Jobs_LIV101a/b`, `Jobs_LIV29`, `Jobs_GAP7`, `Jobs_GAP8`, `Jobs_P3`, `Jobs_P4`, `Jobs_P5`, `Jobs_AfterChk_T/O/R/ED/ST/X1`, `Jobs_Flow_Holds`, `Jobs_Flow_GAP3/GAP3b/GAP4`, `Jobs_Flow_P1/P1b`), node limit 1, at most 2 lease tokens per job (1 in `Jobs_LIV101a` and `Jobs_LIV29`), Max and N in {1, 2}, one node's LongRunning limit 1. `Jobs_Flow_P1/P1b` use 4 job slots. One namespace: the per-queue scope of INV-100 under Redis ShardByQueue is not modeled. | all |
| A-14 | One job name; "a handler for its name or one of its aliases" is a per-node handler flag that can change when a node restarts (rolling deploy). | REQ-101, REQ-123, REQ-124, REQ-125 |
| A-15 | A schedule call for a time that is not in the future (REQ-182) is a call that schedules, so ReplaceSchedule applies to it (REQ-150's "the call does not schedule a job"). | REQ-150, REQ-151, REQ-182 |
| A-18 | REQ-191's record and log line are history only. Abandonment is recorded as the tag `Abandoned` in the step that abandons (`AbandonOnTimeout`, both outcomes of the shutdown check in `ReleaseOnShutdown`), and `Prop_AbandonRecorded` checks that. The tag is per job, not per attempt, so the property is checked where a first attempt is abandoned. The lease-lost trigger is the predicate `LeaseLostRecordable`: a running handler on a live node whose token is not current or whose job is not processing. For a job that was deleted or removed, only the log line can be written, because "that attempt" no longer exists. | REQ-191, INV-128 |
| A-19 | Cancelling a token for shutdown (REQ-139) and the node's check are separate steps. Following REQ-190's trigger and REQ-140's notes, the check is made once per in-flight run, before the node stops, and it reads the cancellation request and the timeout signal as they are then. It has three outcomes: release (REQ-140), cancel (REQ-190) or neither (a timed-out run with no request, left on its timeout path). The only remaining assumption is that the check is always made, which only REQ-140's notes say. | REQ-139, REQ-140, REQ-190, hosting REQ-29 |
| A-20 | "The job's node" (REQ-140) and "its draining node" (REQ-190) are the node whose run holds the job's current lease token. A node whose run lost its lease to another node's claim makes no shutdown write for that job. | REQ-140, REQ-190, INV-128 |

## Coverage

| Modeled | Skipped (reason) |
|---|---|
| REQ-100–102, REQ-104, REQ-106–108, REQ-120–145, REQ-147, REQ-150–152, REQ-156, REQ-158, REQ-160–163, REQ-170–177, REQ-179–192, INV-100, INV-103, INV-104, INV-106–115, INV-118, INV-128–130, INV-135, INV-138, LIV-100–102, SCN-100–112, SCN-114, SCN-115, SCN-117–125 | Inline mode: REQ-146, INV-131–134, INV-137 (call-stack semantics) · data, not state: REQ-105, REQ-148, REQ-154, REQ-155, REQ-165–169, INV-116, INV-117, INV-119–127, INV-136 · no effect on state: REQ-103, REQ-109, INV-105 (absorbed by A-1) · transactions: INV-101, REQ-153, SCN-113 · INV-102 (one atomic call) · strength `may`: REQ-157, REQ-159, REQ-164 · SCN-116 (payload size) · REQ-178 (retired) · REQ-191's log line (only the record is state) |

**Scenario results.** Unchanged from run 7. Every positive scenario is reachable (trap violated, as expected): SCN-100, 101, 102, 105, 108, 111, 112, 114, 115, 118, 119, 121, 122 and 125. Every negative scenario holds over the complete bounded state space: SCN-103, 104, 107, 110, 117 and 124 (`Jobs_Holds.cfg`, `Jobs_HoldsQ.cfg`, `Jobs_SCN124.cfg`), SCN-106 (`Jobs_Throttle_Holds/HoldsK.cfg`), SCN-120 (`Jobs_SCN120.cfg`), and SCN-109 and SCN-123 (the flow holds runs). SCN-113 is still skipped.

**Same-trigger warnings from `validate`.** REQ-127/128/184, REQ-129/131 and REQ-132/133 are modeled as one action each, and REQ-171/174 inside one resolution step. REQ-140's still-running branch and REQ-190's shutdown branch are one action by design: two outcomes of one check.

**Cross-module.** Part of F-1's fix is a note in **hosting.json** (REQ-29). The rest is in jobs REQ-190 and REQ-140. None of the three changes behaviour. Under hosting REQ-29 a draining node always stops (`Liv_DrainEnds`, `Jobs_LIV29.cfg`).

## Next

Apply the chosen option (F-1: REQ-190's and REQ-140's notes in `specs/jobs.json`, REQ-29's notes in `specs/hosting.json`) with the `refiner-requirements` skill (it validates and diffs), then run this skill again. Findings whose fingerprint disappears are listed as resolved in the next report.
