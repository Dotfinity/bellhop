# Findings: Bellhop job lifecycle

<!-- refiner-findings v1 | module: jobs | specHash: 7952e5e0ed20eafe6c69c66a8d43a614ba7df32a111101f16b6bbab9bcf217ff | run: 2026-11-07 | previous: specs/model/jobs/previous.findings.md (run 3, specHash 4abf0385ed9d) -->

**Run:** 2026-11-07 (run 4, from `specs/model/jobs/handoff.json`, base 9e15c1e) · **Requirements file:** `specs/jobs.json` (specHash `7952e5e0ed20`) · **Model:** `model/jobs/Jobs.tla`, `Jobs_Unique.tla`, `Jobs_Throttle.tla`, `Jobs_Flow.tla` · **TLC:** 2.19, every check run alone with `--stop-at-first --workers 4` inside `timeout 170`, while five other modules were being checked on the same machine. There were no TLC exceptions. The largest completed runs were 5,295,568 distinct states in 67 s (`Jobs_HoldsQ.cfg`), 3,936,009 in 40 s (`Jobs_Flow_P1b.cfg`) and 2,610,356 in 26–31 s (`Jobs_Holds.cfg`, the CHK and GAP runs, `Jobs_SCN124.cfg`).
**Result:** 1 finding: 0 contradictions · 0 gaps · 1 ambiguity · 0 unprovable · 0 modeling notes. All three run-3 findings are resolved.

Only the requirements in the handoff were regenerated: INV-128, REQ-140, REQ-188 and REQ-191 (modified), plus the new scenarios SCN-124 and SCN-125. Two impacted items were re-checked: REQ-190 and SCN-115. `NodeStop` encodes hosting REQ-29, whose run-3 wording changed in the hosting module ("the lease releases that jobs REQ-140 calls for"). It was regenerated as well, because REQ-140's new guard only means something if the node stops without waiting. `Jobs_Unique.tla` and `Jobs_Throttle.tla` are unchanged byte-for-byte and were re-run. The model is still split into four files:

| File | Covers |
|---|---|
| `Jobs.tla` | execution, leases, recovery, retries, timeouts, shutdown, cancellation (REQ-190, REQ-191), requeue, delete, retention, queue pause, maintenance and routing |
| `Jobs_Unique.tla` | unique keys (FEAT-103) on every creating call, and the unique-key side of single and bulk requeue |
| `Jobs_Throttle.tla` | claim order, concurrency keys, rate limits, queue limits, the LongRunning limit, LIV-100 (FEAT-104) |
| `Jobs_Flow.tla` | continuations, chains and batches (FEAT-106), including INV-138, batch-member retention and batch removal (REQ-192) |

To reproduce, run `sh run_all.sh` from `specs/model/jobs`. It makes one `run_tlc.py … --stop-at-first` call per cfg.

## Changes since last run

| Finding | Status |
|---|---|
| F-1 | new: comes from hosting REQ-29's run-3 wording combined with REQ-140 and REQ-190 |
| F-1 (run 3) | resolved: REQ-140's timeout guard now covers both branches. `Chk_TimeoutReleaseSplit` holds (`Jobs_CHK5.cfg`, 2,610,356 states), and so does the new SCN-124 (`Jobs_SCN124.cfg`, 2,610,356 states; its steps 1–2 are reachable in 7 states, `Jobs_SCN124s.cfg`). A timed-out run that a draining node leaves behind is counted by lease expiry (`Jobs_P2.cfg`, a 10-state trace) |
| F-2 (run 3) | resolved: INV-128 and REQ-191 also catch "its job is no longer processing". `Gap_LeaseLostUnrecorded` holds by construction, because the new trigger is exactly "the run is not current". The new SCN-125 is reachable (`Jobs_SCN125.cfg`, a 6-state trace). Released and abandoned runs are never current again (`Inv_StaleRunsFenced`, in `Jobs_Holds.cfg` and `Jobs_HoldsQ.cfg`) |
| F-3 (run 3) | resolved: REQ-188 names both retention paths. The new `Inv_NoAwaitingOnRemoved` holds with four job slots (`Jobs_Flow_P1b.cfg`, 3,936,009 states), as well as in `Jobs_Flow_Holds` (1,407,799), `HoldsC` (652,237) and `HoldsU` (259,033). `Probe_MemberContinuationRemoved` is still reached (`Jobs_Flow_P1.cfg`, a 9-state trace), and that is now the required behaviour |

`findings_delta.py specs/model/jobs/previous.findings.md specs/jobs.findings.md`:

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | ambiguity · Chk_TimeoutReleaseSplit · REQ-138,REQ-140,REQ-186 |
| F-2 | resolved | gap · Gap_LeaseLostUnrecorded · INV-128,REQ-123,REQ-133,REQ-190,REQ-191 |
| F-3 | resolved | ambiguity · Probe_MemberContinuationRemoved · REQ-188,REQ-192 |
| F-1 | new | ambiguity · Gap_CancelledDeadLetteredAfterDrain · REQ-133,REQ-140,REQ-190,hosting.REQ-29 |

3 resolved, 1 new, 0 still open. (The "resolved" rows use run 3's numbers.)

## Summary

| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | ambiguity | medium | hosting REQ-29, REQ-140, REQ-190, REQ-133 | A draining node no longer waits to mark a cancel-requested job cancelled, so at its last attempt lease expiry dead-letters it |

---

## F-1 · ambiguity · medium — A draining node no longer waits to mark a cancel-requested job cancelled, so at its last attempt lease expiry dead-letters it
<!-- finding: ambiguity | Gap_CancelledDeadLetteredAfterDrain | REQ-133,REQ-140,REQ-190,hosting.REQ-29 -->

**Requirements involved**
- hosting REQ-29 (changed in run 3): *While a node is draining, when every in-flight job has finished, or ShutdownTimeout has passed, the remaining jobs' tokens were cancelled and **the lease releases that jobs REQ-140 calls for** were attempted, the system shall stop the node.* Before run 3 it read "… and the release of their leases was attempted", meaning every remaining job.
- REQ-140: *While the job's node is draining, the job's token was cancelled for shutdown, its timeout token was not signalled **and its cancellation was not requested**, if the handler is still running or throws OperationCanceledException, then the system shall release the job's lease and take back the attempt it counted …*
- REQ-190: *While a job is processing and its cancellation was requested, when its lease expires with attempts left, **its node releases it at shutdown**, … the system shall abandon the handler if it is still running and mark the job cancelled …*
- REQ-133: *While a job is processing, when its leaseExpiresAt has passed …, if the attempt number has reached maxAttempts, the system shall let any running worker node move the job to dead-lettered with reason Interrupted.*

**What happens** (`Jobs_GAP7.cfg`: `Gap_CancelledDeadLetteredAfterDrain` violated, a 10-state trace, MaxAttempts = 1; the shortest trace lets the lease expire before the drain, and any order works)
1. j1 is enqueued and node n1 claims it at attempt 1, its last attempt (REQ-120, REQ-123).
2. An operator cancels j1. The request is recorded and j1's token is signalled (REQ-135). The handler ignores the signal and keeps running.
3. The host stops n1. n1 drains (hosting REQ-27), ShutdownTimeout passes and j1's token is cancelled for shutdown (REQ-139).
4. REQ-140 does not call for releasing j1, because its cancellation was requested. So hosting REQ-29's condition already holds, and **n1 stops** without applying REQ-190's "its node releases it at shutdown" branch.
5. j1's lease expires (no node is renewing it) and n2 recovers it. Attempts are used up, so REQ-190's lease branch ("with attempts left") does not apply. **REQ-133 dead-letters j1 with reason Interrupted.**

Under hosting REQ-29's run-2 wording, n1 waited for "the release of their leases", which covered every remaining job. REQ-190's shutdown branch then marked j1 Cancelled before n1 stopped. Now an operator's cancellation ends as a dead letter after a graceful shutdown. A dead letter is kept 30 days (REQ-145) and counts towards dead-letter alerts (integrations).

**Why.** REQ-190's shutdown trigger, "its node releases it at shutdown", refers to the release that REQ-140 describes. But REQ-140 excludes cancel-requested jobs, so nothing ever "releases" such a job. Under the old REQ-29 the model read the trigger as "the release REQ-140 would make, but for the cancel request". The new REQ-29 waits only for the releases REQ-140 calls for, and REQ-140 calls for none here. Both readings of REQ-190's trigger now fit the sentences, and they give different outcomes at the last attempt. With attempts left the outcome is the same either way: REQ-190's lease branch marks the job Cancelled.

**Options**
1. *(recommended)* Make REQ-29 wait for both requirements. In REQ-29, write "the lease releases and cancellations that jobs REQ-140 and REQ-190 call for were attempted". The node still does not wait for a timed-out job that is not cancel-requested, which is what run 3 F-1 needed. A cancel-requested job ends Cancelled whether or not it has attempts left, as it did before run 3. Cost: one clause in hosting REQ-29.
2. Accept it, and treat a graceful shutdown like a crash for a cancel-requested job. Drop "its node releases it at shutdown" from REQ-190, so lease expiry decides the outcome: Cancelled with attempts left, dead-lettered at the last attempt. REQ-190's notes already accept that outcome for lease expiry. Cost: an operator's cancellation can end as a dead letter after an ordinary deploy, and the job stays Processing for up to LeaseDuration after the node has stopped.
3. Cancel at lease expiry even with attempts used up. Extend REQ-190's lease branch to "its lease expires", without "with attempts left", and remove the cancel-requested case from REQ-133. This also covers a crash, but it reopens the run-2 decision recorded in REQ-190's notes ("exhausted attempts on … lease expiry still dead-letter").

**Ready to apply (option 1, in `specs/hosting.json`)**
```json
{ "id": "REQ-29", "ears": { "while": "a node is draining",
    "when": "every in-flight job has finished, or ShutdownTimeout has passed, the remaining jobs' tokens were cancelled and the lease releases and cancellations that jobs REQ-140 and REQ-190 call for were attempted",
    "shall": "stop the node" } }
```
Notes addition for hosting REQ-29: *"jobs run 4 F-1: a job whose cancellation was requested is marked cancelled at shutdown (jobs REQ-190) before the node stops. Without this wait, lease expiry would dead-letter it at its last attempt (jobs REQ-133)."*

---

## Accepted (not reported as findings)

- **LIV-100** (`accepted-unprovable`): strict queue priority and job priority can still starve a job for ever (`Jobs_Throttle_L1.cfg` and `Jobs_Throttle_L2.cfg`, lassos). It holds with one queue and equal priority (`L0`) and with a shared concurrency key (`L3`).
- **LIV-102** (`should`, `accepted-unprovable`): a continuation behind an Unroutable parent can still wait for ever (`Jobs_Flow_F3.cfg`, lasso). `F1`, `F2`, `F4` and `F5` hold.
- **REQ-143 / run 2 F-6** (accepted in REQ-143's notes): requeuing a cancelled parent does not revive the continuations cancelled with it (`Jobs_Flow_GAP3.cfg`).
- **INV-106, former reading** (handlers executing, abandoned ones included): still violated (`Jobs_INV106.cfg`, `Chk_HandlersWithinLimit`), as the owner accepted in run 1.
- **INV-108/109, former reading** (state invariants): still violated after an operator lowers a limit (`Jobs_Throttle.cfg`, `Chk_KeyMaxState`). The claim-time wording holds (`Jobs_Throttle_Holds.cfg`, `Jobs_Throttle_HoldsK.cfg`).
- **Timed-out job at shutdown, recovered by lease expiry** (REQ-140 and hosting REQ-29 notes): when the node stops before TimeoutGracePeriod ends, the job comes back through REQ-132 with reason Interrupted and no backoff, rather than through REQ-138 with reason Timeout and retryAt. The attempt counts either way (`Jobs_P2.cfg`, a 10-state trace), and the notes accept it.

**Annotation note (no semantic change).** INV-128's notes say that "before, a run released at shutdown could still complete its job before another node claimed it". That was never reachable. REQ-127, REQ-129 and REQ-131 all start with "while a job is processing", and a released job is Enqueued, so no requirement applied to the write. The new clause turns that silent no-op into a refused, logged write (INV-128) and a record (REQ-191). The note could say so.

## Runs

| cfg | Result | Distinct states | s |
|---|---|---|---|
| `Jobs_Holds` (now with `Inv_StaleRunsFenced`, `Scn124_TimedOutNotReleased`) | holds | 2,610,356 | 31 |
| `Jobs_HoldsQ` (same additions) | holds | 5,295,568 | 67 |
| `Jobs_CHK` / `CHK2` / `CHK3` / `CHK4` | hold | 2,610,356 each | 26–29 |
| `Jobs_CHK5` | holds (run 3: **violated**, F-1) | 2,610,356 | 26 |
| `Jobs_GAP1` / `GAP2` / `GAP5` | hold | 2,610,356 each | 27 |
| `Jobs_GAP6` | not run: holds by construction since run 4; the full two-slot space does not finish in 170 s (also tried at MaxAttempts = 1, MaxToken = 1) | – | – |
| `Jobs_GAP7` | **violated** (F-1) | 9,836 | 1 |
| `Jobs_P2` | violated (reachable, accepted path) | 15,076 | 1 |
| `Jobs_INV106` | violated (accepted) | 588 | 1 |
| `Jobs_LIV101a` / `LIV101b` | hold | 69,120 / 514,080 | 4 / 31 |
| `Jobs_LIV29` (new, `Liv_DrainEnds`) | holds | 69,120 | 9 |
| `Jobs_SCN100/101/102/111/112/115/122` | traps violated (reachable, as expected) | 136–9,023 | 1 |
| `Jobs_SCN120` | holds | 1,144,320 | 11 |
| `Jobs_SCN124` (new, negative) | holds | 2,610,356 | 27 |
| `Jobs_SCN124s` / `Jobs_SCN125` (new) | traps violated (reachable, as expected) | 1,634 / 513 | 1 |
| `Jobs_Unique`, `U1`–`U5` / `SCN105` | hold / trap violated | 3,220–7,794 / 51 | 1 |
| `Jobs_Throttle_*` | unchanged: Holds, HoldsK, T0, T2, T3, L0, L3 hold; L1 and L2 (lassos) and `Jobs_Throttle` violated, accepted | ≤ 1,692 | 1 |
| `Jobs_Flow_Holds` / `HoldsC` / `HoldsU` (now with `Inv_NoAwaitingOnRemoved`) | hold | 1,407,799 / 652,237 / 259,033 | 17 / 9 / 4 |
| `Jobs_Flow_P1b` (new, four slots) | holds | 3,936,009 | 40 |
| `Jobs_Flow_F1` / `F2` / `F4` / `F5` | hold | 206,420 / 207,248 / 205,289 / 206,420 | 11–19 |
| `Jobs_Flow_F3` | violated (accepted, LIV-102) | 56,644 | 4 |
| `Jobs_Flow_GAP3b` / `GAP4` | hold | 1,388,164 / 1,396,162 | 10 / 13 |
| `Jobs_Flow_GAP3` / `GAP5` / `GAP6` | violated (accepted / allowed / accepted) | 122,263 / 389 / 2,992 | 1–2 |
| `Jobs_Flow_P1` | violated (now the required case) | 425,968 | 4 |
| `Jobs_Flow_SCN108/114/118/119/121` | traps violated (reachable, as expected) | 184–286,529 | 1–3 |

**Timeouts.** `Jobs.cfg` and `Jobs_LIV101.cfg` still exceed 170 s and run split, as in run 3. `Jobs_GAP6` now joins them (see above). Every other run finished within the skill's 120 s budget; the largest, `Jobs_HoldsQ`, took 67 s.

## Modeling assumptions

These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.

| # | Assumption | Affects |
|---|---|---|
| A-1 | No clocks. scheduledAt/retryAt passing, UnroutableAfter, the timeout, TimeoutGracePeriod, ShutdownTimeout and retention (including REQ-192's "every stored member past its retention") are each a nondeterministic event that may happen at any time and, because time passes, eventually does (fair). Backoff lengths, retention lengths and window lengths are not judged. | REQ-100, REQ-104, REQ-122, REQ-124, REQ-130, REQ-137, REQ-145, REQ-183, REQ-187, REQ-189, REQ-192, INV-105 |
| A-2 | A lease is a flag. It can expire at any time while processing (crash, partition or pause), and a late heartbeat from the run that holds the current token renews it (REQ-126 has no "not yet expired" guard). | REQ-102, REQ-126, REQ-132, REQ-133, INV-104, LIV-101 |
| A-3 | *(changed in run 4)* A crash removes the node's handlers at once; its leases expire later. A draining node stops as hosting REQ-29's run-3 wording says. It waits only for runs that REQ-140 calls to release: current, timeout not signalled, cancellation not requested. Every remaining run's token must have been cancelled for shutdown. A stopped node's handlers stop with it. | REQ-132, REQ-139, REQ-140, REQ-190, F-1 |
| A-4 | "Holds claims on processing jobs" (REQ-123, INV-106) counts processing jobs whose current lease token is held by the node's live run. Handlers that were abandoned, released or lost their lease are not counted. | INV-106, REQ-123 |
| A-5 | OperationCanceledException is thrown only after a token was signalled. REQ-136 and REQ-138/186 take precedence over REQ-129/131 for it (REQ-136 notes). Every other overlap between the throw rules is checked (`Chk_SingleRule`, holding), not resolved. | REQ-129–140, REQ-186, REQ-190 |
| A-6 | "While P, eventually Q" is read as `P ~> (Q \/ ~P)`: the obligation ends when P stops holding, for example when the job is cancelled or deleted. | LIV-100, LIV-101, LIV-102, REQ-192 |
| A-7 | Every run ends eventually (the timeout guarantees it), so a run's outcome is fair in the throttling and flow models. | Jobs_Throttle.tla, Jobs_Flow.tla |
| A-8 | A retried job joins the back of its queue for the "order they were enqueued" rule. | INV-111 |
| A-9 | Rate-limit windows are fixed windows that end nondeterministically; sliding windows are not modeled. | INV-109 |
| A-10 | Continuations are resolved in the same step as their parent's outcome, cancellation, deletion, removal by retention or batch removal, and a cancellation cascades down a chain in that step (REQ-173 notes). | REQ-171–REQ-175, REQ-188, REQ-192 |
| A-11 | In `Jobs_Flow.tla`, removed job slots and removed batches are not reused, so parent links stay valid. Deadlock checking is off there (`--no-deadlock`) because the pool runs out. | Jobs_Flow.tla |
| A-12 | "Every member job" (REQ-179, REQ-180) ranges over the members created with the batch; an explicitly deleted member counts as finished and not succeeded (REQ-180). REQ-192's "every member job that is still stored" skips deleted and retention-removed members. | REQ-179, REQ-180, REQ-192 |
| A-13 | Bounds: 1–4 jobs, 2 nodes, 1 queue (2 in the throttling model), MaxAttempts = 2 (1 for `Jobs_HoldsQ`, `Jobs_LIV101a/b`, `Jobs_LIV29`, `Jobs_GAP7`, `Jobs_Flow_Holds`, `Jobs_Flow_GAP3/GAP3b/GAP4`, `Jobs_Flow_P1/P1b`), node limit 1, at most 2 lease tokens per job (1 in `Jobs_LIV101a` and `Jobs_LIV29`), Max and N in {1, 2}, one node's LongRunning limit 1. `Jobs_Flow_P1/P1b` use 4 job slots. One namespace: the per-queue scope of INV-100 under Redis ShardByQueue is not modeled. | all |
| A-14 | One job name; "a handler for its name or one of its aliases" is a per-node handler flag that can change when a node restarts (rolling deploy). | REQ-101, REQ-123, REQ-124, REQ-125 |
| A-15 | A schedule call for a time that is not in the future (REQ-182) is a call that schedules, so ReplaceSchedule applies to it (REQ-150's "the call does not schedule a job"). | REQ-150, REQ-151, REQ-182 |
| A-18 | *(changed in run 4)* REQ-191's record and log line are history only. The lease-lost trigger is the predicate `LeaseLostRecordable`: a running handler on a live node whose token is not current or whose job is not processing. For a job that was deleted or removed, only the log line can be written, because "that attempt" no longer exists. | REQ-191, INV-128 |
| A-19 | *(new)* REQ-190's "its node releases it at shutdown" is the shutdown release REQ-140 would make but for the cancel request. It has no timeout guard of its own, so it may also apply to a timed-out job whose cancellation was requested. Either way that job ends Cancelled (REQ-190's timeout branch). See F-1 for whether the node waits for it. | REQ-190, REQ-140 |

A-17 from run 3 (a member removed with its batch counts as "removed by retention") is withdrawn: REQ-188 now says so.

## Coverage

| Modeled | Skipped (reason) |
|---|---|
| REQ-100–102, REQ-104, REQ-106–108, REQ-120–145, REQ-147, REQ-150–152, REQ-156, REQ-158, REQ-160–163, REQ-170–177, REQ-179–192, INV-100, INV-103, INV-104, INV-106–115, INV-118, INV-128–130, INV-135, INV-138, LIV-100–102, SCN-100–112, SCN-114, SCN-115, SCN-117–125 | Inline mode: REQ-146, INV-131–134, INV-137 (call-stack semantics) · data, not state: REQ-105, REQ-148, REQ-154, REQ-155, REQ-165–169, INV-116, INV-117, INV-119–127, INV-136 · no effect on state: REQ-103, REQ-109, INV-105 (absorbed by A-1) · transactions: INV-101, REQ-153, SCN-113 · INV-102 (one atomic call) · strength `may`: REQ-157, REQ-159, REQ-164 · SCN-116 (payload size) · REQ-178 (retired) · REQ-191's log line (only the record is state) |

**Scenario results.** Every positive scenario is reachable (trap violated, as expected): SCN-100, 101, 102, 105, 108, 111, 112, 114, 115, 118, 119, 121, 122 and the new SCN-125. Every negative scenario holds over the complete bounded state space: SCN-103, 104, 107, 110 and 117 (`Jobs_Holds.cfg`, `Jobs_HoldsQ.cfg`), SCN-106 (`Jobs_Throttle_Holds/HoldsK.cfg`), SCN-120 (`Jobs_SCN120.cfg`), SCN-109 and SCN-123 (the flow holds runs), and the new SCN-124 (`Jobs_SCN124.cfg`, also in both Jobs holds runs). SCN-113 is still skipped.

**Same-trigger warnings from `validate`.** REQ-127/128/184, REQ-129/131 and REQ-132/133 are modeled as one action each, and REQ-171/174 inside one resolution step. `Chk_SingleRule` checks every throw rule together and still holds (`Jobs_CHK2.cfg`).

**Cross-module.** The fix for F-1 goes in hosting REQ-29. `Liv_DrainEnds` holds under REQ-29's run-3 wording (`Jobs_LIV29.cfg`, 69,120 states), so a draining node always stops. Redis REQ-534 and recurring REQ-240, the cancellations owned by other modules, are unchanged and have the same shape as REQ-134. They are not modeled here.

## Next

Apply the chosen options to `specs/hosting.json` (F-1) with the `refiner-requirements` skill (it validates and diffs), then run this skill again. Findings whose fingerprint disappears are listed as resolved in the next report.
