# Findings: Bellhop job lifecycle

<!-- refiner-findings v1 | module: jobs | specHash: f8184c68c75cb2291ef7d8a9df9c370b87094a26fb28c0ca4e0070e8f54f2813 | run: 2026-11-06 | previous: specs/model/jobs/previous.findings.md (run 1, specHash 1779db13a8dd) -->

**Run:** 2026-11-06 (run 2, from `specs/model/jobs/handoff.json`) · **Requirements file:** `specs/jobs.json` (specHash `f8184c68c75c`) · **Model:** `model/jobs/Jobs.tla`, `Jobs_Unique.tla`, `Jobs_Throttle.tla`, `Jobs_Flow.tla` · **TLC:** 2.19. Every run completed with `--stop-at-first` and no TLC exception. The largest runs were 3,663,520 distinct states in 71 s (`Jobs_HoldsQ.cfg`), 1,406,536 in 26 s (`Jobs_Flow_Holds.cfg`) and 915,880 states for the LIV-101 liveness check in 92 s (`Jobs_LIV101.cfg`).
**Result:** 7 findings: 3 contradictions · 2 gaps · 2 ambiguities · 0 unprovable · 0 modeling notes. All 13 findings of run 1 are resolved; F-12 and F-13 are now accepted (`accepted-unprovable`).

Only the requirements listed in the handoff were re-modeled; the rest of the model is unchanged. The model is still split into four files so each TLC run stays under 2 minutes:

| File | Covers |
|---|---|
| `Jobs.tla` | execution, leases, recovery, retries, timeouts, shutdown, cancellation (incl. REQ-190, REQ-191), requeue, delete, retention, queue pause, maintenance and routing |
| `Jobs_Unique.tla` | unique keys (FEAT-103) on every creating call, and the unique-key side of single and bulk requeue |
| `Jobs_Throttle.tla` | claim order, concurrency keys, rate limits, queue limits, the LongRunning limit, LIV-100 (FEAT-104) |
| `Jobs_Flow.tla` | continuations, chains and batches (FEAT-106), incl. INV-138 and batch-member retention |

To reproduce, run `sh run_all.sh` from `specs/model/jobs`. It makes one `run_tlc.py … --stop-at-first` call per cfg (wrapped in `timeout 170`). Every trace below can be reproduced with its cfg alone, for example `python run_tlc.py Jobs.tla --config Jobs_CHK3.cfg --stop-at-first`.

## Changes since last run

| Finding | Status |
|---|---|
| F-1 | new |
| F-2 | new |
| F-3 | new |
| F-4 | new |
| F-5 | new |
| F-6 | new |
| F-7 | new |
| F-1 (run 1) | resolved — INV-108/109 are claim-time rules; `Prop_KeyMaxAtClaim`/`Prop_RateAtStart` hold (`Jobs_Throttle_Holds.cfg`, `Jobs_Throttle_HoldsK.cfg`) |
| F-2 (run 1) | resolved — REQ-123 checks the queue and LongRunning limits; `Inv_QueueLimit` and `Inv_LongRunning` hold (`Jobs_Throttle_T2.cfg`, `Jobs_Throttle_T3.cfg`) |
| F-3 (run 1) | resolved — REQ-150/152 cover every creating call; `Inv_UniqueKey` holds for schedule, ReplaceSchedule-on-enqueue and continuations (`Jobs_Unique_U2/U3/U4.cfg`) |
| F-4 (run 1) | resolved — REQ-142 skips held keys; `Inv_UniqueKey` holds with bulk requeue (`Jobs_Unique_U5.cfg`) |
| F-5 (run 1) | resolved — INV-106 counts claims (`Inv_NodeClaims` holds in `Jobs_Holds.cfg`); the former handler reading is still violated and accepted (REQ-191) |
| F-6 (run 1) | resolved — `Chk_CancelTimeoutOverlap` holds (`Jobs_CHK.cfg`, 1,730,312 states) |
| F-7 (run 1) | resolved — `Gap_CancelRequestLost` holds (`Jobs_GAP1.cfg`); new F-6 below is about the request outliving a requeue |
| F-8 (run 1) | resolved — `Gap_CooperativeShutdownCounted` holds (`Jobs_GAP2.cfg`); new F-2 below is a side effect of the fix |
| F-9 (run 1) | resolved — `Gap_DeadLetterRequeueLosesContinuation` holds (`Jobs_Flow_GAP3b.cfg`); SCN-121 is reachable |
| F-10 (run 1) | resolved — `Gap_BatchUpgradeImpossible` holds without explicit deletes (`Jobs_Flow_GAP4.cfg`); new F-5 below is the cost of the fix |
| F-11 (run 1) | resolved — INV-138; `Scn123_MissingParentRejected` holds in all three flow holds runs |
| F-12 (run 1) | resolved — accepted: LIV-100 is tagged `accepted-unprovable` (still fails in `Jobs_Throttle_L1/L2.cfg`, as the owner expects) |
| F-13 (run 1) | resolved — accepted: LIV-102 is `should` and tagged `accepted-unprovable` (still fails in `Jobs_Flow_F1/F3.cfg`, as the owner expects) |

`findings_delta.py`: 13 resolved, 7 new, 0 still open. "(run 1)" marks the previous file's numbering. The run 1 file has a blank line between each heading and its fingerprint comment, which the script does not parse, so the delta was computed on a copy with those blank lines removed (`specs/model/jobs/previous.normalized.md`).

## Summary

| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | contradiction | medium | REQ-131, REQ-190 | A permanent failure after a cancel request is both dead-lettered and cancelled |
| F-2 | contradiction | medium | REQ-138, REQ-186, REQ-140 | An OperationCanceledException after both the timeout and the shutdown signal is both a counted timeout and an uncounted release |
| F-3 | contradiction | medium | REQ-175, REQ-174 | A continuation added to a dead-lettered parent cannot be resolved "at once", so REQ-175 cannot be met |
| F-4 | ambiguity | medium | REQ-135, REQ-141, REQ-142, REQ-143, REQ-190, REQ-136 | A cancel request outlives a requeue, so the next run's first failure cancels the job instead of retrying it |
| F-5 | gap | medium | REQ-145, REQ-179, REQ-180 | Members of a Completed batch are never removed by retention, and nothing ever removes the batch |
| F-6 | gap | low | REQ-143, REQ-173, REQ-174, REQ-175 | Requeuing a cancelled parent does not revive the continuations that were cancelled with it |
| F-7 | ambiguity | low | INV-106, REQ-123, REQ-191, INV-128 | A handler whose lease was lost keeps running outside the limit, and REQ-191 does not record it |

---

## F-1 · contradiction · medium — A permanent failure after a cancel request is both dead-lettered and cancelled
<!-- finding: contradiction | Chk_PermanentVsCancel | REQ-131,REQ-190 -->

**Requirements involved**
- REQ-131: *While a job is processing, when its handler throws an exception, if the exception is not an OperationCanceledException thrown after the job's token was cancelled for shutdown, and the attempt number has reached maxAttempts, the retry policy declines another attempt, or the exception is a PermanentJobFailureException, then the system shall move the job to dead-lettered.*
- REQ-190: *While a job is processing and its cancellation was requested, when … its handler throws an exception other than OperationCanceledException with attempts left, the system shall … mark the job cancelled instead of returning it to enqueued, marking it failed or dead-lettering it for the timeout.*

**What happens** (`Jobs_CHK3.cfg`: `Chk_PermanentVsCancel` violated in 4 states; `Chk_SingleRule` in `Jobs_CHK2.cfg` finds the same state)
1. j1 is enqueued and node A claims it, attempt 1 of 2 (REQ-120, REQ-123).
2. The operator cancels j1; the request is recorded and A's token is signalled (REQ-135).
3. The handler ignores the token and throws a PermanentJobFailureException (or the retry policy declines). **REQ-131 dead-letters j1; REQ-190 marks it Cancelled.** Both apply to the same exception.

**Why.** REQ-190's exception branch says "with attempts left" but not "and the retry policy would retry". REQ-131 has no cancellation guard, and its "policy declines / PermanentJobFailureException" branch applies with attempts left too. The outcomes differ visibly: Dead-lettered fires OnFailure/OnCompletion continuations (REQ-172) and is kept 30 days; Cancelled cancels them (REQ-173) and is kept 7 days. REQ-190's notes already say exhausted attempts still dead-letter "because a dead-lettered job does not run again"; the same holds here. Related to the open question in REQ-190's notes (cancel requested and attempts exhausted), which this run confirms is consistent; this case is the one with attempts left.

**Options**
1. *(recommended)* Dead-letter wins whenever no retry would follow: narrow REQ-190's exception branch to exceptions the retry policy would retry. This matches REQ-190's own rationale (it exists so a cancelled job does not run again).
2. Cancellation wins: add "and its cancellation was not requested, or the attempt number has reached maxAttempts" to REQ-131's `if`. The operator's cancel then shows as Cancelled, at the cost of a third rule shape in the REQ-129/131 pair.

**Ready to apply (option 1)**
```json
{ "id": "REQ-190", "ears": { "while": "a job is processing and its cancellation was requested",
    "when": "its lease expires with attempts left, its node releases it at shutdown, its handler is still running TimeoutGracePeriod after its timeout token was signalled, or its handler throws an exception other than OperationCanceledException that the retry policy would retry with attempts left",
    "shall": "abandon the handler if it is still running and mark the job cancelled instead of returning it to enqueued, marking it failed or dead-lettering it for the timeout" } }
```

---

## F-2 · contradiction · medium — An OperationCanceledException after both the timeout and the shutdown signal is both a counted timeout and an uncounted release
<!-- finding: contradiction | Chk_TimeoutVsShutdown | REQ-138,REQ-140,REQ-186 -->

**Requirements involved**
- REQ-138: *While a job is processing, its timeout token was signalled and its cancellation was not requested, if the handler … throws OperationCanceledException within [TimeoutGracePeriod], and the attempt number is below maxAttempts …, then the system shall … mark the job failed with reason Timeout and set retryAt from the backoff.* (REQ-186: dead-lettered when attempts run out)
- REQ-140: *While the job's node is draining, the job's token was cancelled for shutdown and its cancellation was not requested, if the handler is still running or throws OperationCanceledException, then the system shall release the job's lease and take back the attempt it counted …*

**What happens** (`Jobs_CHK4.cfg`: `Chk_TimeoutVsShutdown` violated in 7 states)
1. Node A claims j1, attempt 1 (REQ-123).
2. j1's timeout passes and its token is signalled (REQ-137).
3. The host stops A; A drains (hosting REQ-27), and ShutdownTimeout passes while j1 is still running, so its token is cancelled for shutdown too (REQ-139).
4. Within the grace period the handler throws OperationCanceledException. **REQ-138 marks j1 Failed with reason Timeout and counts the attempt; REQ-140 releases it and takes the attempt back.**

**Why.** Run 1's F-8 fix added "or throws OperationCanceledException" to REQ-140, which now overlaps REQ-138/186's "throws OperationCanceledException within it". REQ-129/131 exclude the shutdown case, but REQ-138/186 do not, and REQ-140 does not exclude the timeout case. A job that keeps timing out during rolling deploys would, under REQ-140, never use up its attempts.

**Options**
1. *(recommended)* Timeout wins: REQ-140's OCE branch applies only when the timeout token was not signalled. The timeout came first, and counting it keeps maxAttempts meaningful.
2. Shutdown wins: add "and its token was not cancelled for shutdown" to the `while` of REQ-138 and REQ-186. Simpler for operators reading the history (one "Released" entry), but a job that always times out is never dead-lettered while nodes keep restarting.

**Ready to apply (option 1)**
```json
{ "id": "REQ-140", "ears": { "while": "the job's node is draining, the job's token was cancelled for shutdown and its cancellation was not requested",
    "if": "the handler is still running, or it throws OperationCanceledException and its timeout token was not signalled",
    "shall": "release the job's lease and take back the attempt it counted, so another node can claim it immediately and the interrupted run does not count towards maxAttempts" } }
```

---

## F-3 · contradiction · medium — A continuation added to a dead-lettered parent cannot be resolved "at once", so REQ-175 cannot be met
<!-- finding: contradiction | REQ-175 | REQ-174,REQ-175 -->

**Requirements involved**
- REQ-175: *When an application adds a continuation to a parent that has already succeeded, been dead-lettered or been cancelled, the system shall resolve the continuation at once, as if the parent had just finished (REQ-171 to REQ-174), instead of storing it as awaiting.*
- REQ-174 (changed in run 1, F-9): *While a continuation is awaiting, when its parent succeeds, if the condition is OnFailure, then the system shall cancel the continuation with reason ConditionNotMet.*

**What happens** (`Jobs_Flow_GAP5.cfg`: `Gap_LateContinuationAwaits` violated in 5 states)
1. j1 is enqueued, claimed and dead-lettered (REQ-120, REQ-123, REQ-131).
2. The application adds an OnSuccess continuation j2 to j1 (REQ-175). None of REQ-171 to REQ-174 applies to "parent dead-lettered, condition OnSuccess" any more, so **j2 is stored as awaiting, which REQ-175 forbids**.

**Why.** Before F-9, REQ-174 cancelled every non-matching continuation of a finished parent, so REQ-175 always resolved. F-9 deliberately keeps a non-matching continuation of a dead-lettered parent waiting (the parent can be requeued), and REQ-175's "instead of storing it as awaiting" was not updated.

**Options**
1. *(recommended)* Make REQ-175 follow REQ-171 to REQ-174 exactly, including "stays awaiting": an OnSuccess continuation added to a dead-lettered parent waits for a requeue, the same as one added before the parent failed.
2. Reject the call: adding an OnSuccess continuation to a dead-lettered parent is an error (like INV-138). Callers then have to requeue the parent first.

**Ready to apply (option 1)**
```json
{ "id": "REQ-175", "ears": { "when": "an application adds a continuation to a parent that has already succeeded, been dead-lettered or been cancelled",
    "shall": "resolve the continuation as if the parent had just finished (REQ-171 to REQ-174), and store it as awaiting only when none of those rules applies" } }
```

---

## F-4 · ambiguity · medium — A cancel request outlives a requeue, so the next run's first failure cancels the job instead of retrying it
<!-- finding: ambiguity | Job.cancelRequested | REQ-135,REQ-143,REQ-190 -->

**Requirements involved**
- REQ-135: *While a job is processing, when an application or operator cancels it, the system shall record the cancellation request and signal the handler's cancellation token …*
- REQ-143: *When an application or operator requeues a succeeded or cancelled job, the system shall enqueue the same job again with its attempt number reset to zero, keeping its earlier history.* (REQ-141, REQ-142 likewise for dead letters)
- REQ-190: *While a job is processing and its cancellation was requested, when … its handler throws an exception other than OperationCanceledException with attempts left, the system shall … mark the job cancelled …* (and REQ-129, REQ-132, REQ-138, REQ-140, REQ-186 are guarded by "its cancellation was not requested"; REQ-136 marks any OperationCanceledException as a cancel)

**What happens** (`Jobs_GAP5.cfg`: `Gap_StaleCancelRequest` violated in 8 states)
1. j1 is enqueued and node A claims it, attempt 1 (REQ-120, REQ-123).
2. The operator cancels j1; the request is recorded (REQ-135).
3. The handler finishes anyway and j1 is Succeeded (REQ-127, as REQ-136's notes intend).
4. A week later the operator requeues j1 (REQ-143): Enqueued, attempt 0. Nothing clears the recorded request.
5. Node A claims j1 again, attempt 1 (REQ-123).
6. The handler throws an ordinary, retryable exception. Because "its cancellation was requested" is still true, REQ-129 does not apply and **REQ-190 marks j1 Cancelled** instead of retrying it. A timeout OperationCanceledException on this run would likewise be read as a cancel by REQ-136.

**Why.** "Its cancellation was requested" (attribute `cancelRequested`) is set by REQ-135 and read by seven requirements, but no requirement says it belongs to one run or is cleared by a requeue. Requeue keeps "earlier history" (REQ-143), which suggests the flag stays.

**Options**
1. *(recommended)* A requeue clears the request: REQ-141, REQ-142 and REQ-143 enqueue the job "with its attempt number reset to zero and its cancellation request cleared". A requeue is a fresh start by the operator.
2. Scope the request to the attempt: replace "its cancellation was requested" with "its cancellation was requested during the current attempt" in REQ-129, REQ-132, REQ-136, REQ-138, REQ-140, REQ-186 and REQ-190. Same effect, seven edits.
3. Keep it and document that a job cancelled once is treated as cancelled on every later run.

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-141", "ears": { "when": "an operator requeues a dead-lettered job through the API or the dashboard",
      "shall": "enqueue the job again with its attempt number reset to zero and its cancellation request cleared" }, "mentions": ["Job.attempt", "Job.cancelRequested"] },
  { "id": "REQ-143", "ears": { "when": "an application or operator requeues a succeeded or cancelled job",
      "shall": "enqueue the same job again with its attempt number reset to zero and its cancellation request cleared, keeping its earlier history" }, "mentions": ["Job.attempt", "Job.cancelRequested"] }
]
```
REQ-142 needs the same clause ("…in its own atomic step with its attempt number reset to zero and its cancellation request cleared, …"). Keep each item's existing `mentions` entries and add `Job.cancelRequested`.

---

## F-5 · gap · medium — Members of a Completed batch are never removed by retention, and nothing ever removes the batch
<!-- finding: gap | Batch.Completed | REQ-145,REQ-179,REQ-180 -->

**Requirements involved**
- REQ-145 (changed in run 1, F-10): *When a job has been succeeded, cancelled or dead-lettered for longer than that state's retention, if the job is not a member of a batch that is open or completed, then the system shall remove the job …*
- REQ-179: *While a batch is open or completed, when every member job has succeeded, the system shall mark the batch succeeded.*
- REQ-180: *While a batch is open, when every member job is succeeded, dead-lettered, cancelled or deleted and at least one did not succeed, the system shall mark the batch completed.*

**What happens** (concrete example; the model keeps job slots, A-11, so it cannot show storage growth)
1. An application creates batch B with 1,000 members (REQ-177). 999 succeed; one is dead-lettered (REQ-131). B becomes Completed (REQ-180).
2. Nobody requeues the dead letter. B stays Completed for ever: only REQ-179 leaves Completed, and it needs every member to succeed.
3. REQ-145 skips all 1,000 members for ever, including the 999 succeeded ones, whose 7-day retention passed long ago. No requirement removes a batch. Every batch with one unrequeued failure is kept indefinitely, with its payloads, logs and history (INV-119).

**Why.** F-10's fix protects members so a Completed batch can still be upgraded (SCN-119), but gives the protection no end. `Gap_BatchUpgradeImpossible` now holds (`Jobs_Flow_GAP4.cfg`), which confirms the protection works; this is its cost.

**Options**
1. *(recommended)* Give the batch a retention of its own: when every member of a Completed batch has been finished for longer than its own state's retention, remove the batch together with its members, and cancel its awaiting batch-level continuations. Members stay requeueable until then.
2. Keep Completed batches until an operator deletes them, and say so (dashboard list of Completed batches, documentation).
3. Protect only Open batches. This brings back run 1's F-10 trace: a Completed batch can then no longer be upgraded once retention removes a succeeded member.

**Ready to apply (option 1)**
```json
{ "id": "REQ-192", "kind": "transition", "status": "proposed", "strength": "must",
  "entity": "Batch", "actor": "system", "from": ["Completed"],
  "ears": { "while": "a batch is completed",
    "when": "every member job has been succeeded, cancelled or dead-lettered for longer than that state's retention",
    "shall": "remove the batch together with its member jobs, their state history, captured logs and parameters, and cancel the batch's awaiting continuations" },
  "mentions": ["Batch.members", "Job.stateHistory", "Job.capturedLogs", "Job.parameters"],
  "dependsOn": ["REQ-104", "REQ-145", "REQ-180"],
  "rationale": "refiner-model run 2 F-5: REQ-145 exempts members of a completed batch, and nothing else ends that exemption." }
```
`to` is omitted because the batch is removed. If the Batch entity should keep a final state instead, add `"Removed"` to its states.

---

## F-6 · gap · low — Requeuing a cancelled parent does not revive the continuations that were cancelled with it
<!-- finding: gap | ConditionNotMet | REQ-143,REQ-173,REQ-174,REQ-175 -->

**Requirements involved**
- REQ-173: *While a continuation is awaiting, when its parent is cancelled, the system shall cancel the continuation, whatever its condition.* (REQ-175 applies it at once when the parent is already cancelled.)
- REQ-174: *… when its parent succeeds, if the condition is OnFailure, then the system shall cancel the continuation with reason ConditionNotMet.*
- REQ-143: *When an application or operator requeues a succeeded or cancelled job, the system shall enqueue the same job again …*

**What happens** (`Jobs_Flow_GAP3.cfg`: `Gap_ContinuationLostOnRequeue` violated in 12 states)
1. j1 runs and succeeds (REQ-123, REQ-127).
2. The application adds an OnFailure continuation j3 to j1. j1 already succeeded, so j3 is cancelled at once with ConditionNotMet (REQ-175, REQ-174).
3. The application adds an OnSuccess continuation j2 to j3. j3 is already cancelled, so j2 is cancelled at once (REQ-175, REQ-173).
4. The operator requeues j3 (REQ-143 allows requeuing a cancelled job). j3 runs, is dead-lettered, is requeued again and finally succeeds.
5. **j2 stays Cancelled** although its parent j3 has now succeeded.

The same happens in a plain chain when an operator cancels a step by mistake and then requeues it: the later steps were cancelled by REQ-173 and stay cancelled.

**Why.** Run 1's F-9 fix keeps continuations of a *dead-lettered* parent waiting, but a *cancelled* parent still cascades the cancel to its continuations immediately, and REQ-143 lets that parent be requeued. Whether the cascade should be reversible is not stated.

**Options**
1. *(recommended)* Accept and document: a cancel is deliberate and ends the chain below it; requeuing a cancelled job runs that job only. Add this to REQ-143's notes so operators know to re-create the rest of the chain.
2. Make it reversible: when a cancelled parent is requeued, return the continuations that its cancellation cancelled (reason ParentCancelled) to awaiting. This needs a cancellation reason on REQ-173 and a new transition.

**Ready to apply (option 1)**
```json
{ "id": "REQ-143", "notes": "Decided by the owner on 2026-11-06: RequeueAsync(id) accepts any finished state (DeadLettered is REQ-141) and refuses the rest (INV-129). Requeuing a cancelled job runs that job only: continuations cancelled with it (REQ-173, REQ-174, REQ-175) stay cancelled and must be re-created (refiner-model run 2 F-6)." }
```

---

## F-7 · ambiguity · low — A handler whose lease was lost keeps running outside the limit, and REQ-191 does not record it
<!-- finding: ambiguity | REQ-191 | INV-106,INV-128,REQ-123,REQ-191 -->

**Requirements involved**
- INV-106: *The system shall never hold claims on more processing jobs at once on a node than the node's concurrency limit.*
- REQ-123: *… when a running node with the worker registered … has a free worker slot …, the system shall claim the job …*
- REQ-191: *When the system abandons a handler that is still running, after a timeout (REQ-138, REQ-186, REQ-190) or a release at shutdown (REQ-140), the system shall log a warning … and record in that attempt that its handler was abandoned and is still running outside the node's concurrency limit.*
- INV-128: *If a run presents a lease token that is no longer the job's current leaseToken when it renews the lease …, then the system shall refuse the write …*

**What happens** (concrete example; the model counts a slot as taken while any non-abandoned handler runs, A-4, so it uses the stricter reading)
1. Node A (concurrency limit 1) claims j1. A network partition stops A's heartbeats; j1's lease expires and node B returns it to Enqueued and runs it (REQ-132, REQ-123).
2. The partition heals. A's handler for j1 is still running; its next heartbeat is refused (INV-128). A holds no claim any more.
3. If "a free worker slot" means "fewer claims than the limit" (the INV-106 wording since run 1's F-5), A claims j2: **two handlers run on a node with limit 1**, and REQ-191 records nothing, because j1's handler was neither timed out nor released at shutdown.

**Why.** Run 1's F-5 decision moved INV-106 from handlers to claims and made abandoned handlers visible through REQ-191, but "free worker slot" in REQ-123 was not defined, and REQ-191 lists only two of the three ways a node can lose the claim of a running handler.

**Options**
1. *(recommended)* Extend REQ-191 to lease loss: when a run's heartbeat is refused because its token is no longer current while its handler is still running, log and record it the same way. Define "free worker slot" in the glossary as "fewer claims than the concurrency limit".
2. Define "free worker slot" as "fewer handlers executing than the limit, not counting abandoned ones", so a lease-lost handler keeps its slot until it ends. Safer for resources, but a hung handler blocks a slot until its timeout.

**Ready to apply (option 1)**
```json
{ "id": "REQ-191", "ears": { "when": "the system abandons a handler that is still running, after a timeout (REQ-138, REQ-186, REQ-190) or a release at shutdown (REQ-140), or refuses its heartbeat because its lease token is no longer current (INV-128)",
    "shall": "log a warning naming the job, its attempt and the node, and record in that attempt that its handler was abandoned and is still running outside the node's concurrency limit" } }
```
Glossary: `"freeWorkerSlot": "A node has a free worker slot while it holds claims on fewer processing jobs than its concurrency limit (INV-106)."`

---

## Accepted (not reported as findings)

- **LIV-100** (`accepted-unprovable`): strict queue priority and job priority can still starve a job for ever (`Jobs_Throttle_L1.cfg` lasso back to state 5, `Jobs_Throttle_L2.cfg` lasso back to state 3); it holds with one queue and equal priority (`L0`) and with a shared concurrency key (`L3`).
- **LIV-102** (`should`, `accepted-unprovable`): an OnBatchSucceeded continuation of a batch that stays Completed waits for ever (`Jobs_Flow_F1.cfg`, stuttering), and so does a continuation behind an Unroutable parent (`Jobs_Flow_F3.cfg`, lasso back to state 7). It now holds with OnBatchCompleted only (`F2`, 206,624 states) and with job continuations and no people/environment actions (`F4`, 205,289 states): a non-matching continuation of a dead-lettered parent is cancelled once retention removes the parent (REQ-188). A batch whose members are explicitly deleted completes without succeeding (`Jobs_Flow_GAP6.cfg`), which run 1's F-10 decision accepts.
- **INV-106, former reading** (handlers executing, abandoned ones included): still violated (`Jobs_INV106.cfg`, `Chk_HandlersWithinLimit`: a timed-out handler is abandoned, the job is dead-lettered, requeued and claimed again on the same node, so two handlers run under limit 1). The owner accepted this in run 1 (INV-106 and REQ-191 notes).
- **INV-108/109, former reading** (state invariants): still violated after an operator lowers a limit (`Jobs_Throttle.cfg`, 6 states); the requirements now say "admit a claim" / "start", which hold.

## Modeling assumptions

These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.

| # | Assumption | Affects |
|---|---|---|
| A-1 | No clocks. scheduledAt/retryAt passing, UnroutableAfter, the timeout, TimeoutGracePeriod, ShutdownTimeout and retention are each a nondeterministic event that may happen at any time and, because time passes, eventually does (fair). Backoff lengths, retention lengths and window lengths are not judged. | REQ-100, REQ-104, REQ-122, REQ-124, REQ-130, REQ-137, REQ-145, REQ-183, REQ-187, REQ-189, INV-105 |
| A-2 | A lease is a flag. It can expire at any time while processing (crash, partition or pause), and a late heartbeat from the run that holds the current token renews it (REQ-126 has no "not yet expired" guard). | REQ-102, REQ-126, REQ-132, REQ-133, INV-104, LIV-101 |
| A-3 | A crash removes the node's handlers at once; its leases expire later. Draining nodes stop as hosting REQ-29 says. | REQ-132, REQ-139, REQ-140 |
| A-4 | "Free worker slot" (REQ-123) counts handlers executing on the node that were not abandoned or released, including one whose lease was lost. INV-106 counts claims held by the node's live run with the current token. See F-7. | INV-106, REQ-123, F-7 |
| A-5 | OperationCanceledException is thrown only after a token was signalled. REQ-136 and REQ-138/186 take precedence over REQ-129/131 for it (REQ-136 notes). Every other overlap between the throw rules is checked (`Chk_SingleRule`), not resolved. | F-1, F-2 |
| A-6 | "While P, eventually Q" is read as `P ~> (Q \/ ~P)`: the obligation ends when P stops holding, for example when the job is cancelled or deleted. | LIV-100, LIV-101, LIV-102 |
| A-7 | Every run ends eventually (the timeout guarantees it), so a run's outcome is fair in the throttling and flow models. | Jobs_Throttle.tla, Jobs_Flow.tla |
| A-8 | A retried job joins the back of its queue for the "order they were enqueued" rule. | INV-111 |
| A-9 | Rate-limit windows are fixed windows that end nondeterministically; sliding windows are not modeled. | INV-109 |
| A-10 | Continuations are resolved in the same step as their parent's outcome, cancellation, deletion or removal by retention, and a cancellation cascades down a chain in that step (REQ-173 notes). | REQ-171–REQ-175, REQ-188 |
| A-11 | In `Jobs_Flow.tla`, removed job slots are not reused, so parent links stay valid. Deadlock checking is off there (`--no-deadlock`) because the pool runs out. | Jobs_Flow.tla, F-5 |
| A-12 | "Every member job" (REQ-179, REQ-180) ranges over the members created with the batch; an explicitly deleted member counts as finished and not succeeded (REQ-180). | REQ-179, REQ-180 |
| A-13 | Bounds: 1–3 jobs, 2 nodes, 1 queue (2 in the throttling model), MaxAttempts = 2 (1 for the LIV-101 run, `Jobs_HoldsQ.cfg`, `Jobs_Flow_Holds.cfg`, `Jobs_Flow_GAP3/GAP3b/GAP4.cfg`), node limit 1, at most 2 lease tokens per job, Max and N in {1, 2}, one node's LongRunning limit 1. One namespace: the per-queue scope of INV-100 under Redis ShardByQueue is not modeled. | all |
| A-14 | One job name; "a handler for its name or one of its aliases" is a per-node handler flag that can change when a node restarts (rolling deploy). | REQ-101, REQ-123, REQ-124, REQ-125 |
| A-15 | A schedule call for a time that is not in the future (REQ-182) is a call that schedules, so ReplaceSchedule applies to it (REQ-150's "the call does not schedule a job"). | REQ-150, REQ-151, REQ-182 |
| A-16 | No requirement clears `cancelRequested`; the model keeps it across requeues, as the sentences say. See F-4. | F-4 |

## Coverage

| Modeled | Skipped (reason) |
|---|---|
| REQ-100–102, REQ-104, REQ-106–108, REQ-120–145, REQ-147, REQ-150–152, REQ-156, REQ-158, REQ-160–163, REQ-170–177, REQ-179–191, INV-100, INV-103, INV-104, INV-106–115, INV-118, INV-128–130, INV-135, INV-138, LIV-100–102, SCN-100–112, SCN-114, SCN-115, SCN-117–123 | Inline mode: REQ-146, INV-131–134, INV-137 (call-stack semantics) · data, not state: REQ-105, REQ-148, REQ-154, REQ-155, REQ-165–169, INV-116, INV-117, INV-119–127, INV-136 · no effect on state: REQ-103, REQ-109, INV-105 (absorbed by A-1) · transactions: INV-101, REQ-153, SCN-113 · INV-102 (one atomic call) · strength `may`: REQ-157, REQ-159, REQ-164 · SCN-116 (payload size) · REQ-178 (retired) · REQ-191's log line (only the record is state) |

**Scenario results.** Every positive scenario is reachable (trap violated, as expected): SCN-100, 101, 102, 105, 108, 111, 112, 114, 115, 118, 119, and the new SCN-121 (`Jobs_Flow_SCN121.cfg`, 6 steps: chain, step dead-lettered, requeued, succeeds, next step enqueued) and SCN-122 (`Jobs_SCN122.cfg`, 5 steps: claimed, lease expires, cancel recorded, recovery marks it Cancelled). Every negative scenario holds over the complete bounded state space: SCN-103, 104, 107, 110 and 117 (`Jobs_Holds.cfg` 1,730,312 states, `Jobs_HoldsQ.cfg` 3,663,520 states), SCN-120 (`Jobs_SCN120.cfg`), SCN-109 and the new SCN-123 (`Jobs_Flow_Holds.cfg`, `Jobs_Flow_HoldsC.cfg`, `Jobs_Flow_HoldsU.cfg`; people and environment actions are split across them so each fits in 120 s). INV-103, INV-104, INV-106 (claims), INV-113, INV-114, INV-128, INV-129 (state part) and INV-130 also hold in those runs; INV-107, INV-108, INV-109 and INV-112 hold in the throttling holds runs; INV-100 holds in every uniqueness run. LIV-101 holds (`Jobs_LIV101.cfg`, 915,880 distinct states).

**Same-trigger warnings from `validate`.** REQ-127/128/184, REQ-129/131 and REQ-132/133 are modeled as one action each, and REQ-171/174 inside one resolution step; the model found no state where the guards of a pair overlap. All throw rules are now checked together by `Chk_SingleRule`; its only overlaps are F-1 and F-2, which `validate` cannot see because their trigger wordings differ.

**Cross-module.** F-2 involves hosting's draining rules (hosting REQ-27, REQ-29). F-7 involves the node limit (hosting `Node.concurrencyLimit`) and lease loss during partitions. The per-queue INV-100 scope under Redis ShardByQueue (redis INV-500) is in the sentence now but not modeled (A-13). Recurring occurrences that carry unique keys go through REQ-150/152 (every creating call) and are not modeled here.

## Next

Apply the chosen options to `specs/jobs.json` with the `refiner-requirements` skill (it validates and diffs), then run this skill again. Findings whose fingerprint disappears are listed as resolved in the next report.
