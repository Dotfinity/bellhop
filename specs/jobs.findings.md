# Findings: Bellhop job lifecycle

<!-- refiner-findings v1 | module: jobs | specHash: 4abf0385ed9d57dbe10175d4662566bd5b731aa55990f78ae44f32898b6bbe60 | run: 2026-11-06 | previous: specs/model/jobs/previous.findings.md (run 2, specHash f8184c68c75c) -->

**Run:** 2026-11-06 (run 3, from `specs/model/jobs/handoff.json`, base bb8be99) · **Requirements file:** `specs/jobs.json` (specHash `4abf0385ed9d`) · **Model:** `model/jobs/Jobs.tla`, `Jobs_Unique.tla`, `Jobs_Throttle.tla`, `Jobs_Flow.tla` · **TLC:** 2.19, every check run alone with `--stop-at-first --workers 2` inside `timeout 170`. No TLC exception. Two cfgs exceeded 170 s and were split (see *Runs*). The largest completed runs were 5,168,496 distinct states in 147 s (`Jobs_HoldsQ.cfg`), 2,461,940 in 55–65 s (`Jobs_Holds.cfg`, the CHK and GAP runs) and 1,407,799 in 33 s (`Jobs_Flow_Holds.cfg`).
**Result:** 3 findings: 0 contradictions · 1 gap · 2 ambiguities · 0 unprovable · 0 modeling notes. All 7 findings of run 2 are resolved (F-6 by acceptance).

Only the requirements in the handoff were re-modeled: REQ-123, REQ-140, REQ-141, REQ-142, REQ-143, REQ-175, REQ-188, REQ-190, REQ-191 (modified) and REQ-192 (added). `Jobs_Unique.tla` and `Jobs_Throttle.tla` are unchanged byte-for-byte. Their REQ-123 guard already counted processing jobs, and requeue there does not involve the cancellation request. They were re-run for the impacted scenarios. The model is still split into four files:

| File | Covers |
|---|---|
| `Jobs.tla` | execution, leases, recovery, retries, timeouts, shutdown, cancellation (REQ-190, REQ-191), requeue, delete, retention, queue pause, maintenance and routing |
| `Jobs_Unique.tla` | unique keys (FEAT-103) on every creating call, and the unique-key side of single and bulk requeue |
| `Jobs_Throttle.tla` | claim order, concurrency keys, rate limits, queue limits, the LongRunning limit, LIV-100 (FEAT-104) |
| `Jobs_Flow.tla` | continuations, chains and batches (FEAT-106), including INV-138, batch-member retention and the new batch removal (REQ-192) |

To reproduce, run `sh run_all.sh` from `specs/model/jobs`. It makes one `run_tlc.py … --stop-at-first` call per cfg.

## Changes since last run

| Finding | Status |
|---|---|
| F-1 | new |
| F-2 | new: what is left of run 2 F-7 after the fix |
| F-3 | new: comes from the new REQ-192 |
| F-1 (run 2) | resolved: REQ-190 now takes only retryable failures. `Chk_PermanentVsCancel` holds (`Jobs_CHK3.cfg`, 2,461,940 states) and so does `Chk_SingleRule` (`Jobs_CHK2.cfg`, 2,461,940 states) |
| F-2 (run 2) | resolved: REQ-140's OCE branch excludes a signalled timeout. `Chk_TimeoutVsShutdown` holds (`Jobs_CHK4.cfg`, 2,461,940 states). New F-1 below is the half of the case this did not cover |
| F-3 (run 2) | resolved: REQ-175 now allows Awaiting. The new `Inv_AwaitingOnlyWhenNoRule` holds in `Jobs_Flow_Holds.cfg` (1,407,799 states), `Jobs_Flow_HoldsC.cfg` (652,237) and `Jobs_Flow_HoldsU.cfg` (259,033). `Gap_LateContinuationAwaits` is still reached (`Jobs_Flow_GAP5.cfg`, 5 states), and that is now the allowed case |
| F-4 (run 2) | resolved: requeues clear the request. `Gap_StaleCancelRequest` holds (`Jobs_GAP5.cfg`, 2,461,940 states) |
| F-5 (run 2) | resolved: REQ-192 and REQ-188. The new `Liv_CompletedBatchRemoved` holds (`Jobs_Flow_F5.cfg`, 206,420 states). LIV-102 with OnBatchSucceeded now holds too (`Jobs_Flow_F1.cfg`, 206,420 states; it failed in run 2). `Gap_BatchUpgradeImpossible` still holds (`Jobs_Flow_GAP4.cfg`, 1,396,162 states). New F-3 below is a wording gap in REQ-188 |
| F-6 (run 2) | resolved: accepted in REQ-143's notes. The trace is unchanged (`Jobs_Flow_GAP3.cfg`, `Gap_ContinuationLostOnRequeue` violated in 12 states) and is listed under *Accepted* |
| F-7 (run 2) | resolved: REQ-123 counts claims. `Inv_NodeClaims` holds with the new claim guard (`Jobs_Holds.cfg` 2,461,940 states, `Jobs_HoldsQ.cfg` 5,168,496 states), and REQ-191 records lease-lost handlers. New F-2 below is one way of losing a lease that the new trigger misses |

`findings_delta.py specs/model/jobs/previous.findings.md specs/jobs.findings.md`:

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | contradiction · Chk_PermanentVsCancel · REQ-131,REQ-190 |
| F-2 | resolved | contradiction · Chk_TimeoutVsShutdown · REQ-138,REQ-140,REQ-186 |
| F-3 | resolved | contradiction · REQ-175 · REQ-174,REQ-175 |
| F-4 | resolved | ambiguity · Job.cancelRequested · REQ-135,REQ-143,REQ-190 |
| F-5 | resolved | gap · Batch.Completed · REQ-145,REQ-179,REQ-180 |
| F-6 | resolved | gap · ConditionNotMet · REQ-143,REQ-173,REQ-174,REQ-175 |
| F-7 | resolved | ambiguity · REQ-191 · INV-106,INV-128,REQ-123,REQ-191 |
| F-1 | new | ambiguity · Chk_TimeoutReleaseSplit · REQ-138,REQ-140,REQ-186 |
| F-2 | new | gap · Gap_LeaseLostUnrecorded · INV-128,REQ-123,REQ-133,REQ-190,REQ-191 |
| F-3 | new | ambiguity · Probe_MemberContinuationRemoved · REQ-188,REQ-192 |

7 resolved, 3 new, 0 still open. (The "resolved" rows use run 2's numbers.)

## Summary

| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | ambiguity | medium | REQ-138, REQ-140, REQ-186 | A timed-out handler that ignores the shutdown signal gets its attempt back; one that throws OperationCanceledException does not |
| F-2 | gap | low | REQ-191, INV-128, REQ-133, REQ-190, REQ-123 | A lease-lost handler whose job was dead-lettered or cancelled on recovery is never recorded, while its node claims again |
| F-3 | ambiguity | low | REQ-188, REQ-192 | REQ-188 does not say whether a member removed with its batch (REQ-192) counts as "removed by retention" for its own continuations |

---

## F-1 · ambiguity · medium — A timed-out handler that ignores the shutdown signal gets its attempt back; one that throws OperationCanceledException does not
<!-- finding: ambiguity | Chk_TimeoutReleaseSplit | REQ-138,REQ-140,REQ-186 -->

**Requirements involved**
- REQ-140 (changed in run 2 F-2): *While the job's node is draining, the job's token was cancelled for shutdown and its cancellation was not requested, if the handler is still running, or it throws OperationCanceledException and its timeout token was not signalled, then the system shall release the job's lease and take back the attempt it counted …*
- REQ-138: *While a job is processing, its timeout token was signalled and its cancellation was not requested, if the handler is still running TimeoutGracePeriod later or throws OperationCanceledException within it, and the attempt number is below maxAttempts …, then the system shall … mark the job failed with reason Timeout and set retryAt from the backoff.* REQ-186 dead-letters it with reason Timeout when attempts run out.

**What happens** (`Jobs_CHK5.cfg`: `Chk_TimeoutReleaseSplit` violated in 7 states)
1. j1 is enqueued and node n1 claims it, attempt 1 (REQ-120, REQ-123).
2. j1's timeout passes and its timeout token is signalled (REQ-137). The grace period starts.
3. The host stops n1 and n1 drains (hosting REQ-27). ShutdownTimeout passes before the grace period ends, so j1's token is also cancelled for shutdown (REQ-139).
4. Now the outcome depends on the handler:
   - If it **ignores both tokens and is still running**, REQ-140's first branch applies (it has no timeout guard). The lease is released and **the attempt is taken back**: j1 is Enqueued at attempt 0.
   - If it **cooperates and throws OperationCanceledException**, REQ-140's second branch is excluded (the timeout token was signalled) and REQ-138 applies. j1 is Failed with reason Timeout and **the attempt counts**.

A handler that hangs until it times out on every run, on a cluster that keeps restarting nodes (rolling deploys), is released without counting every time and never reaches maxAttempts. That is the outcome run 2 F-2 set out to prevent ("a job that keeps timing out during rolling deploys still uses up its attempts", REQ-140 notes). REQ-140's own notes from run 1 F-8 also say "cooperating never costs an attempt". Here cooperating is exactly what costs the attempt.

**Why.** The F-2 fix put the timeout guard on the OCE branch only. The "still running" branch kept its old reading, so the two branches of one requirement now disagree about a timed-out job.

**Options**
1. *(recommended)* Put the timeout guard on all of REQ-140: it applies only while the timeout token has not been signalled. A timed-out handler at shutdown is then handled by REQ-138/186 when its grace period ends (abandoned, attempt counted). If the process stops first (hosting REQ-29), lease expiry handles it (REQ-132/133), and that attempt counts too. Cost: hosting REQ-29 stops the node once "the release of their leases was attempted". This job gets no release, so the node may wait up to TimeoutGracePeriod (30 s) longer before it stops. Add a line to REQ-29's notes.
2. Release it but keep the attempt: REQ-140 shall "… take back the attempt it counted unless its timeout token was signalled". The node stops at once. But a job released at maxAttempts would then be claimed with an attempt number above maxAttempts, so REQ-140 would also need a dead-letter branch (a second rule shape in REQ-140).
3. Keep it as written and document that a timeout followed by shutdown is free for a handler that ignores its tokens. F-2's rationale then holds only for cooperating handlers.

**Ready to apply (option 1)**
```json
{ "id": "REQ-140", "ears": { "while": "the job's node is draining, the job's token was cancelled for shutdown, its timeout token was not signalled and its cancellation was not requested",
    "if": "the handler is still running or throws OperationCanceledException",
    "shall": "release the job's lease and take back the attempt it counted, so another node can claim it immediately and the interrupted run does not count towards maxAttempts" } }
```
Notes addition for REQ-140: *"refiner-model run 3 F-1: a job whose timeout token was signalled before the shutdown signal is a timeout whether the handler cooperates or not (REQ-138, REQ-186); if the process stops first, lease expiry counts the attempt (REQ-132, REQ-133)."*

---

## F-2 · gap · low — A lease-lost handler whose job was dead-lettered or cancelled on recovery is never recorded, while its node claims again
<!-- finding: gap | Gap_LeaseLostUnrecorded | INV-128,REQ-123,REQ-133,REQ-190,REQ-191 -->

**Requirements involved**
- REQ-191 (changed in run 2 F-7): *When the system abandons a handler that is still running, after a timeout (REQ-138, REQ-186, REQ-190) or a release at shutdown (REQ-140), or refuses the heartbeat of a handler that is still running because its lease token is no longer current (INV-128), the system shall log a warning … and record in that attempt that its handler was abandoned or lost its lease and is still running outside the node's concurrency limit.*
- INV-128: *If a run presents a lease token that is no longer the job's current leaseToken when it renews the lease, reports progress, completes or fails, then the system shall refuse the write …*
- REQ-123 (changed in run 2 F-7): *… when a running node … holds claims on fewer processing jobs than its concurrency limit …, the system shall claim the job …, issue a new leaseToken …*
- REQ-133 / REQ-190: lease expiry with attempts used up moves the job to dead-lettered; with a cancellation requested and attempts left, it is marked cancelled.

**What happens** (`Jobs_GAP6.cfg`: `Gap_LeaseLostUnrecorded` violated in 8 states; two job slots)
1. j1 and j2 are enqueued. Node n1 (limit 1) claims j1 with lease token 1 (REQ-120, REQ-123).
2. A partition stops n1's heartbeats and j1's lease expires (A-2). Meanwhile the operator cancels j1, and the request is recorded (REQ-135).
3. A running worker node recovers j1. Its cancellation was requested and it has attempts left, so **REQ-190 marks it Cancelled**. No new lease token is issued, so token 1 is still j1's current leaseToken.
4. n1's handler for j1 is still running, but n1 holds no claim any more (j1 is not processing). n1 claims j2 (REQ-123). Two handlers now run on a node with limit 1.
5. n1's next heartbeat for j1 presents token 1, which **is** still the job's current leaseToken. INV-128 does not refuse it (REQ-126 does not renew it either, because j1 is not processing). So REQ-191's lease-lost trigger never fires and nothing is recorded. This lasts until someone requeues j1 and it is claimed with a new token.

The same happens with REQ-133 (lease expiry with attempts used up: Dead-lettered, kept 30 days, often never requeued) and after an explicit delete. REQ-190's lease branch says it "abandons the handler if it is still running", but REQ-191's abandonment trigger lists REQ-190 only "after a timeout". The trace above shows the case where the job returns to Enqueued (REQ-132) is recorded later, when the job is claimed again with a new token.

**Why.** REQ-191 detects a lost lease by the token changing, and only a new claim changes the token. Two recovery outcomes, Dead-lettered (REQ-133) and Cancelled (REQ-190), end the job without a new claim.

**Options**
1. *(recommended)* Detect "no longer processing under this token" as well as "different token". Extend INV-128 and REQ-191 with "or the job is no longer processing". Nothing else changes, and the stale run's late writes are refused and logged however the job left processing.
2. Clear the lease token whenever a job leaves Processing (a new invariant: *"The system shall hold a leaseToken on a job only while the job is processing."*). The existing INV-128 and REQ-191 wording then covers every case. Cost: a new contract on the stored token, which the dashboard and the Redis store may read.
3. Accept: record only token changes, and note that handlers whose job was dead-lettered or cancelled on lease expiry are not recorded.

**Ready to apply (option 1)**
```json
[
  { "id": "INV-128", "ears": { "if": "a run presents a lease token that is no longer the job's current leaseToken, or the job is no longer processing, when it renews the lease, reports progress, completes or fails",
      "shall": "refuse the write, leave the job unchanged and log a stale-completion warning" } },
  { "id": "REQ-191", "ears": { "when": "the system abandons a handler that is still running, after a timeout (REQ-138, REQ-186, REQ-190) or a release at shutdown (REQ-140), or refuses the heartbeat of a handler that is still running because its lease token is no longer current or its job is no longer processing (INV-128)",
      "shall": "log a warning naming the job, its attempt and the node, and record in that attempt that its handler was abandoned or lost its lease and is still running outside the node's concurrency limit" } }
]
```

---

## F-3 · ambiguity · low — REQ-188 does not say whether a member removed with its batch (REQ-192) counts as "removed by retention" for its own continuations
<!-- finding: ambiguity | Probe_MemberContinuationRemoved | REQ-188,REQ-192 -->

**Requirements involved**
- REQ-192 (new): *While a batch is completed or succeeded, when every member job that is still stored has been succeeded, cancelled or dead-lettered for longer than that state's retention, the system shall remove the batch together with those member jobs …*
- REQ-188 (changed): *While a continuation is awaiting, when its parent is deleted or removed by retention, or, for a batch-level continuation, its batch is removed (REQ-192), the system shall cancel the continuation.*

**What happens** (`Jobs_Flow_P1.cfg`: `Probe_MemberContinuationRemoved` violated in 9 states; the model applies the reading in A-17)
1. An application creates batch b1 with members j2 and j3 and an OnBatchCompleted continuation j1 (REQ-177).
2. j2 succeeds and j3 is dead-lettered (REQ-123, REQ-127, REQ-131).
3. The application adds an OnSuccess continuation j4 to j3. j3 is dead-lettered and the condition does not match, so j4 is stored as awaiting (REQ-175, REQ-174).
4. b1 becomes Completed and j1 is enqueued (REQ-180, REQ-181).
5. Both members pass their retention. **REQ-192 removes b1 with j2 and j3.** In the model, j4 is cancelled because its parent was "removed by retention" (REQ-188).

If REQ-192's removal is *not* "removed by retention" (it is a separate requirement, and REQ-188 names REQ-192 only for batch-level continuations), then j4 waits for ever for a parent that no longer exists. That is the hang REQ-188 exists to prevent (LIV-102).

**Why.** REQ-188 now names two removal paths, "removed by retention" and "its batch is removed (REQ-192)", and ties the second to batch-level continuations only. A job-level continuation of a member falls between the two.

**Options**
1. *(recommended)* Name both retention paths in REQ-188: "removed by retention (REQ-145, REQ-192)". The model already behaves this way.
2. Put it in REQ-192: "… and cancel the awaiting continuations of the batch and of those member jobs". REQ-188 then no longer needs its batch clause.

**Ready to apply (option 1)**
```json
{ "id": "REQ-188", "ears": { "while": "a continuation is awaiting",
    "when": "its parent is deleted or removed by retention (REQ-145, REQ-192), or, for a batch-level continuation, its batch is removed (REQ-192)",
    "shall": "cancel the continuation" } }
```

---

## Accepted (not reported as findings)

- **LIV-100** (`accepted-unprovable`): strict queue priority and job priority can still starve a job for ever (`Jobs_Throttle_L1.cfg` and `Jobs_Throttle_L2.cfg`, each a lasso back to state 4). It holds with one queue and equal priority (`L0`) and with a shared concurrency key (`L3`).
- **LIV-102** (`should`, `accepted-unprovable`): a continuation behind an Unroutable parent can still wait for ever (`Jobs_Flow_F3.cfg`, lasso back to state 6: the parent goes Unroutable and back, repeatedly). **New in run 3:** the other half of the acceptance is gone. With REQ-192 and REQ-188, an OnBatchSucceeded continuation of a batch that stays Completed is cancelled when the batch is removed, so `Jobs_Flow_F1.cfg` now holds (206,420 states). `F2` and `F4` still hold. The owner may want to narrow the acceptance note to the Unroutable case.
- **REQ-143 / run 2 F-6** (accepted in REQ-143's notes): requeuing a cancelled parent does not revive the continuations cancelled with it (`Jobs_Flow_GAP3.cfg`, 12 states).
- **INV-106, former reading** (handlers executing, abandoned ones included): still violated (`Jobs_INV106.cfg`, `Chk_HandlersWithinLimit`, 483 states), as the owner accepted in run 1.
- **INV-108/109, former reading** (state invariants): still violated after an operator lowers a limit (`Jobs_Throttle.cfg`, `Chk_KeyMaxState`, 6 states). The claim-time wording holds (`Jobs_Throttle_Holds.cfg`, `Jobs_Throttle_HoldsK.cfg`).

## Runs

| cfg | Result | Distinct states | s |
|---|---|---|---|
| `Jobs_Holds` | holds | 2,461,940 | 65 |
| `Jobs_HoldsQ` | holds | 5,168,496 | 147 |
| `Jobs_CHK` / `CHK2` / `CHK3` / `CHK4` | hold | 2,461,940 each | 56–62 |
| `Jobs_CHK5` | **violated** (F-1) | 1,548 | 1 |
| `Jobs_GAP1` / `GAP2` / `GAP5` | hold | 2,461,940 each | 53–55 |
| `Jobs_GAP6` | **violated** (F-2) | 10,359 | 2 |
| `Jobs_INV106` | violated (accepted) | 483 | 1 |
| `Jobs_LIV101a` / `LIV101b` | hold | 66,160 / 476,896 | 8 / 55 |
| `Jobs_SCN100/101/102/111/112/115/122` | traps violated (reachable, as expected) | 70–8,939 | 1–2 |
| `Jobs_SCN120` | holds | 1,019,680 | 18 |
| `Jobs_Unique`, `U1`–`U5` / `SCN105` | hold / trap violated | 3,220–7,794 / 42 | 1–2 |
| `Jobs_Throttle_*` | as in run 2 (Holds, HoldsK, T0, T2, T3, L0, L3 hold; L1, L2 and `Jobs_Throttle` violated, accepted) | ≤ 1,692 | 1 |
| `Jobs_Flow_Holds` / `HoldsC` / `HoldsU` | hold | 1,407,799 / 652,237 / 259,033 | 33 / 19 / 7 |
| `Jobs_Flow_F1` / `F2` / `F4` / `F5` | hold | 206,420 / 207,248 / 205,289 / 206,420 | 17–35 |
| `Jobs_Flow_F3` | violated (accepted, LIV-102) | 28,686 | 4 |
| `Jobs_Flow_GAP3b` / `GAP4` | hold | 1,388,164 / 1,396,162 | 19 / 24 |
| `Jobs_Flow_GAP3` / `GAP5` / `GAP6` | violated (accepted / allowed / accepted) | 120,681 / 287 / 2,483 | 1–2 |
| `Jobs_Flow_P1` | **violated** (F-3 example) | 356,437 | 6 |
| `Jobs_Flow_SCN108/114/118/119/121` | traps violated (reachable, as expected) | 133–214,297 | 1–4 |

**Timeouts.** `Jobs.cfg` (every Jobs.tla check at once, with queue operations and MaxAttempts = 2) and `Jobs_LIV101.cfg` both ran past 170 s and were stopped. The space grew about 40 % because REQ-123 now lets a node with a lease-lost handler claim again. Each check in `Jobs.cfg` runs in a split cfg (`Jobs_Holds`, `Jobs_HoldsQ`, `Jobs_CHK`, `Jobs_CHK2`, `Jobs_LIV101a/b`). Neither split cfg is in `run_all.sh`. LIV-101 is split into `LIV101a` (both nodes are workers, first claim of each job, MaxToken = 1) and `LIV101b` (only n1 is a worker, re-claims allowed, MaxToken = 2). Two combinations are no longer checked together: queue operations with MaxAttempts = 2 (run 2 never reached it either, because `Jobs.cfg` stopped at its first violation), and LIV-101 with two worker nodes and re-claims. `Jobs_HoldsQ` takes 147 s, over the skill's 120 s budget but inside the 170 s cap.

## Modeling assumptions

These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.

| # | Assumption | Affects |
|---|---|---|
| A-1 | No clocks. scheduledAt/retryAt passing, UnroutableAfter, the timeout, TimeoutGracePeriod, ShutdownTimeout and retention (including REQ-192's "every stored member past its retention") are each a nondeterministic event that may happen at any time and, because time passes, eventually does (fair). Backoff lengths, retention lengths and window lengths are not judged. | REQ-100, REQ-104, REQ-122, REQ-124, REQ-130, REQ-137, REQ-145, REQ-183, REQ-187, REQ-189, REQ-192, INV-105 |
| A-2 | A lease is a flag. It can expire at any time while processing (crash, partition or pause), and a late heartbeat from the run that holds the current token renews it (REQ-126 has no "not yet expired" guard). | REQ-102, REQ-126, REQ-132, REQ-133, INV-104, LIV-101 |
| A-3 | A crash removes the node's handlers at once; its leases expire later. Draining nodes stop as hosting REQ-29 says. | REQ-132, REQ-139, REQ-140 |
| A-4 | *(changed in run 3)* "Holds claims on processing jobs" (REQ-123, INV-106) counts processing jobs whose current lease token is held by the node's live run. A node that crashed and restarted therefore holds no claim on its old jobs, even though their leaseOwner still names it until recovery. Handlers that were abandoned, released or lost their lease are not counted. | INV-106, REQ-123, F-2 |
| A-5 | OperationCanceledException is thrown only after a token was signalled. REQ-136 and REQ-138/186 take precedence over REQ-129/131 for it (REQ-136 notes). Every other overlap between the throw rules is checked (`Chk_SingleRule`, now holding), not resolved. | REQ-129–140, REQ-186, REQ-190 |
| A-6 | "While P, eventually Q" is read as `P ~> (Q \/ ~P)`: the obligation ends when P stops holding, for example when the job is cancelled or deleted. | LIV-100, LIV-101, LIV-102, REQ-192 |
| A-7 | Every run ends eventually (the timeout guarantees it), so a run's outcome is fair in the throttling and flow models. | Jobs_Throttle.tla, Jobs_Flow.tla |
| A-8 | A retried job joins the back of its queue for the "order they were enqueued" rule. | INV-111 |
| A-9 | Rate-limit windows are fixed windows that end nondeterministically; sliding windows are not modeled. | INV-109 |
| A-10 | Continuations are resolved in the same step as their parent's outcome, cancellation, deletion, removal by retention or batch removal, and a cancellation cascades down a chain in that step (REQ-173 notes). | REQ-171–REQ-175, REQ-188, REQ-192 |
| A-11 | In `Jobs_Flow.tla`, removed job slots and removed batches are not reused, so parent links stay valid. Deadlock checking is off there (`--no-deadlock`) because the pool runs out. | Jobs_Flow.tla |
| A-12 | "Every member job" (REQ-179, REQ-180) ranges over the members created with the batch; an explicitly deleted member counts as finished and not succeeded (REQ-180). REQ-192's "every member job that is still stored" skips deleted and retention-removed members. | REQ-179, REQ-180, REQ-192 |
| A-13 | Bounds: 1–4 jobs, 2 nodes, 1 queue (2 in the throttling model), MaxAttempts = 2 (1 for `Jobs_HoldsQ`, `Jobs_LIV101a/b`, `Jobs_Flow_Holds`, `Jobs_Flow_GAP3/GAP3b/GAP4`, `Jobs_Flow_P1`), node limit 1, at most 2 lease tokens per job (1 in `Jobs_LIV101a`), Max and N in {1, 2}, one node's LongRunning limit 1. `Jobs_GAP6` uses 2 job slots and `Jobs_Flow_P1` 4. One namespace: the per-queue scope of INV-100 under Redis ShardByQueue is not modeled. | all |
| A-14 | One job name; "a handler for its name or one of its aliases" is a per-node handler flag that can change when a node restarts (rolling deploy). | REQ-101, REQ-123, REQ-124, REQ-125 |
| A-15 | A schedule call for a time that is not in the future (REQ-182) is a call that schedules, so ReplaceSchedule applies to it (REQ-150's "the call does not schedule a job"). | REQ-150, REQ-151, REQ-182 |
| A-17 | *(new)* A member removed with its batch by REQ-192 counts as "removed by retention" for REQ-188, so its awaiting job-level continuations are cancelled. See F-3. | REQ-188, REQ-192 |
| A-18 | *(new)* REQ-191's record and log line are history only. The lease-lost trigger is the predicate `LeaseLostRecordable` (a running handler on a live node whose token differs from the job's current one), not an action. | REQ-191, F-2 |

A-16 from run 2 (no requirement clears `cancelRequested`) is withdrawn: REQ-141, REQ-142 and REQ-143 now clear it.

## Coverage

| Modeled | Skipped (reason) |
|---|---|
| REQ-100–102, REQ-104, REQ-106–108, REQ-120–145, REQ-147, REQ-150–152, REQ-156, REQ-158, REQ-160–163, REQ-170–177, REQ-179–192, INV-100, INV-103, INV-104, INV-106–115, INV-118, INV-128–130, INV-135, INV-138, LIV-100–102, SCN-100–112, SCN-114, SCN-115, SCN-117–123 | Inline mode: REQ-146, INV-131–134, INV-137 (call-stack semantics) · data, not state: REQ-105, REQ-148, REQ-154, REQ-155, REQ-165–169, INV-116, INV-117, INV-119–127, INV-136 · no effect on state: REQ-103, REQ-109, INV-105 (absorbed by A-1) · transactions: INV-101, REQ-153, SCN-113 · INV-102 (one atomic call) · strength `may`: REQ-157, REQ-159, REQ-164 · SCN-116 (payload size) · REQ-178 (retired) · REQ-191's log line (only the record is state) |

**Scenario results (impacted ids re-checked).** Every positive scenario is reachable (trap violated, as expected): SCN-100, 101, 102, 105, 108, 111, 112, 114, 115, 118, 119, 121 and 122. Every negative scenario holds over the complete bounded state space: SCN-103, 104, 107, 110 and 117 (`Jobs_Holds.cfg`, `Jobs_HoldsQ.cfg`), SCN-106 (`Jobs_Throttle_Holds/HoldsK.cfg`), SCN-120 (`Jobs_SCN120.cfg`), and SCN-109 and SCN-123 (the three flow holds runs). INV-128 (`Scn_StaleCannotComplete`) and INV-138 (`Scn123_MissingParentRejected`) hold. SCN-113 is still skipped.

**Same-trigger warnings from `validate`.** REQ-127/128/184, REQ-129/131 and REQ-132/133 are modeled as one action each, and REQ-171/174 inside one resolution step. `Chk_SingleRule` checks every throw rule together and now holds (`Jobs_CHK2.cfg`), so the two overlaps from run 2 are gone. F-1 is not a same-event overlap: the two outcomes come from different handler behaviours.

**Cross-module.** F-1 touches hosting REQ-29 (when a draining node stops). F-2 touches the node limit (hosting `Node.concurrencyLimit`). Two cancellations owned by other modules, redis REQ-534 (cancels a pending job with a duplicate unique key after a store reset) and recurring REQ-240 (cancels an Unroutable occurrence job), act on Scheduled, Enqueued, Awaiting or Unroutable jobs only. That is the same shape as REQ-134 (`CancelPending`, `Cancel` in the flow model, with the REQ-173 cascade), so no jobs check changes. They are not modeled here.

## Next

Apply the chosen options to `specs/jobs.json` with the `refiner-requirements` skill (it validates and diffs), then run this skill again. Findings whose fingerprint disappears are listed as resolved in the next report.
