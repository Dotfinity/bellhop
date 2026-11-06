# Findings: Bellhop job lifecycle

<!-- refiner-findings v1 | module: jobs | specHash: 1779db13a8ddd6fd161d15e3590919eca421f2346c34b014f1777e30a30f8dee | run: 2026-11-06 | previous: none -->

**Run:** 2026-11-06 · **Requirements file:** `specs/jobs.json` (specHash `1779db13a8dd`) · **Model:** `model/jobs/Jobs.tla`, `Jobs_Unique.tla`, `Jobs_Throttle.tla`, `Jobs_Flow.tla` · **TLC:** 2.19. Every run completed with `--stop-at-first` and no TLC exception. The largest runs were 5,805,923 distinct states in 81 s (`Jobs_Flow_Holds.cfg`) and 876,368 states for the LIV-101 liveness check in 70 s (`Jobs_LIV101.cfg`).
**Result:** 13 findings: 5 contradictions · 1 ambiguity · 5 gaps · 2 unprovable · 0 modeling notes

The model is split into four files so each TLC run stays under 2 minutes:

| File | Covers |
|---|---|
| `Jobs.tla` | execution, leases, recovery, retries, timeouts, shutdown, cancellation, requeue, delete, retention, queue pause, maintenance and routing (FEAT-101, 102, 105, 107 in part, 108, and INV-113/114 from FEAT-104) |
| `Jobs_Unique.tla` | unique keys (FEAT-103) and the unique-key side of requeue |
| `Jobs_Throttle.tla` | claim order, concurrency keys, rate limits, queue limits, LIV-100 (FEAT-104) |
| `Jobs_Flow.tla` | continuations, chains and batches (FEAT-106) |

To reproduce, run `sh run_all.sh` from `specs/model/jobs`. It makes one `run_tlc.py … --stop-at-first` call per cfg. The traces below can be reproduced with that cfg alone, for example `python run_tlc.py Jobs_Throttle.tla --config Jobs_Throttle.cfg --stop-at-first`.

## Summary

| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | contradiction | high | INV-108, INV-109, REQ-158 | Lowering a key's Max or rate limit leaves more holders and starts than the invariants allow |
| F-2 | contradiction | high | INV-107, INV-112, REQ-123 | The claim rule never checks the queue limit or the LongRunning limit |
| F-3 | contradiction | high | INV-100, REQ-150, REQ-151, REQ-152, REQ-121, REQ-120, REQ-170 | Three ways to create a job with a key that is already held are covered by no duplicate rule |
| F-4 | contradiction | high | INV-100, INV-129, REQ-142 | Bulk requeue of dead letters can create a second active job with the same key |
| F-5 | contradiction | high | INV-106, REQ-138, REQ-186, REQ-123 | An abandoned handler frees its slot but keeps running, so the node runs more jobs than its limit |
| F-6 | ambiguity | medium | REQ-136, REQ-138, REQ-186 | A cancelled job that hits its timeout and throws OperationCanceledException is both Cancelled and Failed |
| F-7 | gap | medium | REQ-135, REQ-132, REQ-138, REQ-140, REQ-129 | A cancellation request is lost when the job leaves Processing some other way, and the job runs again |
| F-8 | gap | medium | REQ-139, REQ-140, REQ-129, REQ-131 | A handler that honours the shutdown token loses an attempt; one that ignores it does not |
| F-9 | gap | medium | REQ-174, REQ-176, REQ-141, REQ-143 | Requeuing a dead-lettered chain step never revives the rest of the chain |
| F-10 | gap | medium | REQ-179, REQ-180, REQ-181, REQ-144, REQ-145, LIV-102 | A batch with a removed member never completes or succeeds, so its continuation waits for ever |
| F-11 | gap | medium | REQ-170, REQ-175, REQ-188 | A continuation added to a parent that no longer exists is not covered |
| F-12 | unprovable | low | LIV-100, INV-110, INV-111 | Strict queue priority and job priority can starve a job for ever (expected by the owner) |
| F-13 | unprovable | low | LIV-102, REQ-124, REQ-181 | A continuation waits for ever behind an Unroutable parent or a Completed batch (expected by the owner) |

---

## F-1 · contradiction · high — Lowering a key's Max or rate limit leaves more holders and starts than the invariants allow

<!-- finding: contradiction | INV-108,INV-109 | REQ-158 -->

**Requirements involved**
- INV-108: *The system shall never let more jobs with the same concurrency key be processing at once, across all nodes, than that key's Max.*
- INV-109: *Where a rate limit of N executions per fixed or sliding window is set for a key, the system shall never start more than N jobs with that key in any window…*
- REQ-158: *When an operator changes a concurrency key's Max or a rate limit…, the system shall apply the new limit to every following claim on every node…, and leave jobs already running untouched.*

**What happens** (`Jobs_Throttle.cfg`: `Inv_KeyMax` violated in 6 states; `Inv_RateLimit` is violated by the same trace)
1. The key tenant:7 has Max = 2 and a rate limit of 2 per window. The app enqueues j1 with that key (REQ-120).
2. A worker claims j1: 1 holder, 1 start in this window (REQ-123).
3. The app enqueues j2 with the same key, and a worker claims it: 2 holders, 2 starts (REQ-123).
4. The operator lowers Max to 1 and the rate limit to 1 per window (REQ-158). j1 and j2 keep running, as REQ-158 requires. **Two jobs are now processing with Max = 1 (INV-108 violated), and the window holds 2 starts with N = 1 (INV-109 violated).**

**Why.** The REQ-158 notes describe the intended behaviour: when Max drops below the current number of holders, they keep running. INV-108 and INV-109 are written as state invariants, and the state they forbid is exactly the one REQ-158 creates. With limits that never change (`Jobs_Throttle_T0.cfg`), both invariants hold.

**Options**
1. *(recommended)* Make INV-108 and INV-109 rules about claims: "never **admit a claim** that would make more than Max jobs with the key processing" and "never **start** a job that would exceed N in the window". This matches REQ-156 and the REQ-158 notes.
2. Keep the invariants as they are and change REQ-158: when a limit is lowered, cancel the newest holders above the new Max. This is disruptive and costs work in progress.
3. Keep the invariants and forbid lowering Max below the current holders: REQ-158 gets an `if` that rejects the change. Operators can no longer throttle an incident immediately.

**Ready to apply (option 1)**
```json
[
  { "id": "INV-108", "ears": { "shall": "never admit a claim that would make more jobs with the same concurrency key processing at once, across all nodes, than that key's Max at the time of the claim" } },
  { "id": "INV-109", "ears": { "where": "a rate limit of N executions per fixed or sliding window is set for a key",
      "shall": "never start a job with that key when N jobs with that key have already started in the current window, across all nodes, counting every start including retries and recovery restarts" } }
]
```

---

## F-2 · contradiction · high — The claim rule never checks the queue limit or the LongRunning limit

<!-- finding: contradiction | INV-107 | REQ-123 -->

**Requirements involved**
- INV-107: *Where a queue has a concurrency limit, the system shall never run more jobs from that queue at once, across all nodes, than its limit.*
- INV-112: *Where a separate LongRunning limit is configured, the system shall never run more jobs tagged LongRunning at once on a node than that limit.*
- REQ-123: *While a job is enqueued in an active queue, the maintenance pause is off and its concurrency key and rate limit admit it, when a running node … has a free worker slot and the job is the next one by queue order and priority, the system shall claim the job…*

**What happens** (`Jobs_Throttle_T2.cfg`: `Inv_QueueLimit` violated in 5 states)
1. Queue reports has a concurrency limit of 1, and two worker slots are free.
2. The app enqueues j1 in reports, and a worker claims it (REQ-120, REQ-123).
3. The app enqueues j2 in reports. A slot is free, the key and rate limit admit it, and it is next in order, so REQ-123 claims it. **Two jobs from reports are running; INV-107 is violated.**

**Why.** REQ-123 lists every condition for a claim, but a queue below its limit is not one of them. The INV-107 notes say the limit is "enforced by the store at claim time", but that rule exists only in the notes. INV-112 has the same shape: REQ-123 has no LongRunning guard. INV-112 was not modeled separately.

**Options**
1. *(recommended)* Add both limits to REQ-123's `while`.
2. Write a separate claim-guard requirement per limit. REQ-123 stays short, but the claim conditions are then spread over three items.

**Ready to apply (option 1)**
```json
{ "id": "REQ-123", "ears": {
    "while": "a job is enqueued in an active queue that is below its concurrency limit, the maintenance pause is off, its concurrency key and rate limit admit it and, for a job tagged LongRunning, the node is below its LongRunning limit",
    "when": "a running node with the worker registered and a handler for the job's name or one of its aliases has a free worker slot and the job is the next one by queue order and priority",
    "shall": "claim the job for that worker, record the claiming node, issue a new leaseToken, increment the attempt number and set leaseExpiresAt to the database time plus LeaseDuration" },
  "mentions": ["Job.leaseOwner", "Job.leaseToken", "Job.leaseExpiresAt", "Job.attempt", "Job.name", "Queue.Active", "Queue.concurrencyLimit", "Job.longRunning", "Maintenance.Off", "Throttle.holders", "hosting.Node.Running", "hosting.Node.hasWorker"] }
```

---

## F-3 · contradiction · high — Three ways to create a job with a key that is already held are covered by no duplicate rule

<!-- finding: contradiction | INV-100 | REQ-120,REQ-121,REQ-150,REQ-151,REQ-152,REQ-170 -->

**Requirements involved**
- INV-100: *The system shall never hold two active jobs with the same unique key in the same namespace, even when the enqueues arrive concurrently on different nodes.*
- REQ-150 / REQ-152: *When an application **enqueues** a job with a unique key while an active job with the same key exists, if the duplicate policy is Ignore / Error, …*
- REQ-151 / INV-135: *When an application **schedules** a job with a unique key … if the duplicate policy is ReplaceSchedule …*
- REQ-121: *When an application schedules a job …, the system shall store the job as scheduled…* · REQ-170: *When an application adds a continuation …, the system shall store the continuation as awaiting…*

**What happens.** `Inv_UniqueKey` is violated in each isolation run. Plain enqueue with Ignore or Error holds (`Jobs_Unique_U1.cfg`).
- *Schedule with Ignore or Error* (`Jobs_Unique_U2.cfg`, 4 states):
  1. The app enqueues j2 with UniqueKey = order-42 (REQ-120).
  2. The app schedules j3 for tomorrow with UniqueKey = order-42 and policy Ignore. REQ-150 and REQ-152 cover only *enqueues*, and REQ-151 and INV-135 cover only ReplaceSchedule, so no duplicate rule applies. REQ-121 stores j3. **Two active jobs have the key order-42.**
- *Enqueue with ReplaceSchedule* (`Jobs_Unique_U3.cfg`, 3 states): the app enqueues twice with UniqueKey = order-42 and policy ReplaceSchedule. No rule covers enqueue with that policy, so REQ-120 stores both.
- *Continuation with a unique key* (`Jobs_Unique_U4.cfg`, 3 states): j1 is active with order-42, and the app adds continuation j2 with order-42. REQ-170 stores it as Awaiting, which counts as an active state (REQ-107). The same applies to chains (REQ-176) and batches (REQ-177). It applies to recurring occurrences too, if they can carry unique keys.

**Why.** The duplicate rules are written per call (enqueue or schedule) and per policy, but INV-100 applies to every active job, whatever call created it. The combinations nobody wrote fall through to the plain creation requirements.

**Options**
1. *(recommended)* Make the Ignore and Error rules apply to every call that creates a job (enqueue, schedule, continuation, chain, batch). For a call that cannot replace a schedule, ReplaceSchedule behaves like Ignore, as INV-135 already says for a non-scheduled holder.
2. Allow unique keys only on enqueue and schedule, and reject them on continuations, chains and batches. Each policy then still needs an enqueue and a schedule rule.
3. Forbid the uncovered combinations at the call: reject ReplaceSchedule on enqueue, and reject Ignore or Error on schedule. Users will find this surprising.

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-150", "ears": { "when": "an application enqueues, schedules or otherwise creates a job (including a continuation, a chain step or a batch member) with a unique key while an active job with the same key exists",
      "if": "the duplicate policy is Ignore, or the policy is ReplaceSchedule and the call does not schedule a job",
      "shall": "create no job and return the existing job's id with WasDuplicate set to true" } },
  { "id": "REQ-152", "ears": { "when": "an application enqueues, schedules or otherwise creates a job (including a continuation, a chain step or a batch member) with a unique key while an active job with the same key exists",
      "if": "the duplicate policy is Error",
      "shall": "reject the call with an error and create no job" } }
]
```

---

## F-4 · contradiction · high — Bulk requeue of dead letters can create a second active job with the same key

<!-- finding: contradiction | INV-100 | INV-129,REQ-142 -->

**Requirements involved**
- INV-129: *If an application or operator requeues a job that is not succeeded, dead-lettered or cancelled, **or whose unique key is held by another active job**, then the system shall refuse the request…*
- REQ-142: *When an operator requeues dead-lettered jobs in bulk…, the system shall enqueue each matching dead-lettered job again in its own atomic step…, and return how many were requeued and how many were skipped **because their state changed meanwhile**.*

**What happens** (`Jobs_Unique_U5.cfg`: `Inv_UniqueKey` violated in 7 states)
1. The app enqueues j2 with UniqueKey = order-42. A worker claims it, and it is dead-lettered (REQ-120, REQ-123, REQ-131).
2. The key is free again because DeadLettered is not an active state (REQ-107). The app enqueues j3 with order-42 (REQ-120).
3. The operator bulk-requeues dead letters by name (REQ-142). j2 is still DeadLettered, so it is requeued. **j2 and j3 are both active with order-42.**

**Why.** Single requeues (REQ-141, REQ-143) are guarded by INV-129. REQ-142 names only one reason to skip a job, "state changed meanwhile", so it does not clearly fall under INV-129.

**Options**
1. *(recommended)* Make REQ-142 skip jobs whose key is held and report them in a separate count.
2. Make INV-129 explicitly cover bulk requeue and leave REQ-142's sentence alone. The result counts then do not say why a job was skipped.

**Ready to apply (option 1)**
```json
{ "id": "REQ-142", "ears": { "when": "an operator requeues dead-lettered jobs in bulk by name, queue, tag or time range",
    "shall": "enqueue each matching dead-lettered job again in its own atomic step with its attempt number reset to zero, skip any job whose unique key is held by another active job, and return how many were requeued, how many were skipped because their state changed meanwhile and how many were skipped because their unique key is held" },
  "dependsOn": ["INV-100", "INV-129"] }
```

---

## F-5 · contradiction · high — An abandoned handler frees its slot but keeps running, so the node runs more jobs than its limit

<!-- finding: contradiction | INV-106 | REQ-123,REQ-138,REQ-186 -->

**Requirements involved**
- INV-106: *The system shall never run more jobs at once on a node than the node's concurrency limit.*
- REQ-186 / REQ-138: *…if the handler is still running TimeoutGracePeriod later…, then the system shall abandon the handler if it is still running and move the job to dead-lettered / mark the job failed…* Notes: *"An abandoned handler keeps running in the process."*
- REQ-123: *…when a running node … has a free worker slot…*

**What happens** (`Jobs_INV106.cfg`: `Inv_NodeConcurrency` violated in 8 states; node B has a concurrency limit of 1)
1. The app enqueues j1, and node B claims it with token 1 (REQ-120, REQ-123).
2. j1 runs past its timeout. Its token is signalled (REQ-137), and the grace period passes with the handler still running.
3. The handler is abandoned and keeps running on B. The retry policy declines, so j1 is dead-lettered (REQ-186).
4. The operator requeues j1 (REQ-141).
5. B claims j1 again with token 2. REQ-123 sees a free slot, because the abandoned handler no longer holds one. **B now runs two handlers with a limit of 1; INV-106 is violated.** The retry path gives the same result (REQ-138 → Failed → REQ-130 → claim).

**Why.** "Run" in INV-106 has two readings. If an abandoned handler counts, REQ-123's "free worker slot" has to count it too, and a handler that never returns then leaks a slot for ever. If it does not count, INV-106 is violated as soon as one handler is abandoned. Modeling assumption A-4 takes the first reading for INV-106 and the second for REQ-123.

**Options**
1. *(recommended)* Say that INV-106 counts jobs the node holds a claim for, not handlers still executing, and record that abandoned handlers run outside the limit. This is the cheapest fix and makes the runaway handler visible.
2. Count abandoned handlers against the slot until they return: add a rule that the slot is freed only when the handler ends. A node can then end up with no slots left.
3. Count them against the slot up to a cap, for example AbandonedHandlerLimit, and report the node Degraded above it (hosting REQ-34).

**Ready to apply (option 1)**
```json
{ "id": "INV-106", "ears": { "shall": "never hold claims on more processing jobs at once on a node than the node's concurrency limit" },
  "notes": "A handler abandoned after its timeout (REQ-138, REQ-186) or released at shutdown (REQ-140) keeps running in the process but no longer holds a claim; it does not count against the limit." }
```

---

## F-6 · ambiguity · medium — A cancelled job that hits its timeout and throws OperationCanceledException is both Cancelled and Failed

<!-- finding: ambiguity | Chk_CancelTimeoutOverlap | REQ-136,REQ-138,REQ-186 -->

**Requirements involved**
- REQ-136: *While a job is processing and its cancellation was requested, when its handler throws OperationCanceledException, the system shall mark the job cancelled.*
- REQ-138: *While a job is processing and its timeout token was signalled, if the handler … throws OperationCanceledException within it, and the attempt number is below maxAttempts …, then the system shall … mark the job failed with reason Timeout and set retryAt…* (REQ-186: dead-lettered when attempts run out)

**What happens** (`Jobs_CHK.cfg`: `Chk_CancelTimeoutOverlap` violated in 5 states)
1. Node A claims j1 (REQ-123).
2. The operator cancels j1. The request is recorded and A's token is signalled (REQ-135).
3. j1's timeout passes, and the token is signalled for the timeout (REQ-137).
4. Within the grace period the handler throws OperationCanceledException. **REQ-136 marks j1 Cancelled; REQ-138 marks it Failed and retries it.** Both sentences apply to the same event.

**Why.** Both rules react to the same exception on the same token, and neither excludes the other. The REQ-136 notes settle the overlap with REQ-129 but not with REQ-138 or REQ-186.

**Options**
1. *(recommended)* Cancellation wins: add "and its cancellation was not requested" to the `while` of REQ-138 and REQ-186. A job the user cancelled is never retried.
2. Timeout wins: add "and its timeout token was not signalled" to REQ-136. The user's cancel is then lost (see F-7).

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-138", "ears": { "while": "a job is processing, its timeout token was signalled and its cancellation was not requested",
      "if": "the handler is still running TimeoutGracePeriod later or throws OperationCanceledException within it, and the attempt number is below maxAttempts and the retry policy allows another attempt",
      "shall": "abandon the handler if it is still running, mark the job failed with reason Timeout and set retryAt from the backoff" } },
  { "id": "REQ-186", "ears": { "while": "a job is processing, its timeout token was signalled and its cancellation was not requested",
      "if": "the handler is still running TimeoutGracePeriod later or throws OperationCanceledException within it, and the attempt number has reached maxAttempts or the retry policy declines another attempt",
      "shall": "abandon the handler if it is still running and move the job to dead-lettered with reason Timeout" } }
]
```
With option 1, a cancelled job whose handler ignores the token until the grace period ends is covered by neither rule. Fix that as part of F-7.

---

## F-7 · gap · medium — A cancellation request is lost when the job leaves Processing some other way, and the job runs again

<!-- finding: gap | Job.cancelRequested | REQ-129,REQ-132,REQ-135,REQ-138,REQ-140 -->

**Requirements involved**
- REQ-135: *While a job is processing, when an application or operator cancels it, the system shall record the cancellation request and signal the handler's cancellation token on whichever node runs the job.*
- REQ-132: *…when its leaseExpiresAt has passed…, then the system shall let any running worker node return the job to enqueued with reason Interrupted…* The same gap exists in REQ-138 (timeout → Failed → retry), REQ-140 (shutdown → Enqueued) and REQ-129 (another exception → Failed → retry).

**What happens** (`Jobs_GAP1.cfg`: the probe `Gap_CancelRequestLost` is violated in 7 states)
1. Node A claims j1 with token 1 (REQ-123).
2. A is cut off from the store and its lease expires.
3. The operator cancels j1. The request is recorded, and A's token is signalled, but A cannot write anything (REQ-135, INV-128).
4. Node B recovers j1 and returns it to Enqueued as Interrupted (REQ-132).
5. B claims j1 for attempt 2 with token 2 (REQ-123). **j1 runs again although it was cancelled.** B's token is never signalled because REQ-135 fires only once, when the cancel arrives, and no requirement ever marks j1 Cancelled.

**Why.** `cancelRequested` is recorded, but nothing reads it when the job leaves Processing without throwing OperationCanceledException. REQ-136 is the only consumer.

**Options**
1. *(recommended)* Add one transition: while a job's cancellation is requested, whenever it would return to Enqueued or Failed (REQ-129, REQ-132, REQ-138, REQ-140), mark it Cancelled instead.
2. Carry the request forward instead: at claim, signal the token at once if cancellation was requested (an extra clause in REQ-123's `shall`). The job is still claimed and started once more.
3. Accept the behaviour and document that a cancel is best-effort while the job is processing.

**Ready to apply (option 1)**
```json
{ "id": "REQ-190", "kind": "transition", "status": "proposed", "strength": "must",
  "entity": "Job", "actor": "system", "from": ["Processing"], "to": ["Cancelled"],
  "ears": { "while": "a job is processing and its cancellation was requested",
    "when": "the job would be returned to enqueued or marked failed (lease expiry, shutdown release, timeout or a handler exception)",
    "shall": "mark the job cancelled instead" },
  "mentions": ["Job.cancelRequested"], "dependsOn": ["REQ-129", "REQ-132", "REQ-135", "REQ-138", "REQ-140"] }
```
The guards of REQ-129, REQ-132, REQ-138 and REQ-140 then need "and its cancellation was not requested". Otherwise this would be a same-trigger contradiction.

---

## F-8 · gap · medium — A handler that honours the shutdown token loses an attempt; one that ignores it does not

<!-- finding: gap | REQ-140 | REQ-129,REQ-131,REQ-139,REQ-140 -->

**Requirements involved**
- REQ-139: *While the job's node is draining, when ShutdownTimeout has passed and the job is still running, the system shall signal the handler's cancellation token.*
- REQ-140: *…and the job's token was cancelled for shutdown, **if the handler is still running**, then the system shall release the job's lease and take back the attempt it counted…*
- REQ-129 / REQ-131: *…when its handler throws an exception…, mark the job failed and set retryAt… / move the job to dead-lettered.*

**What happens** (`Jobs_GAP2.cfg`: the probe `Gap_CooperativeShutdownCounted` is violated in 7 states)
1. Node B claims j1 for attempt 1 (REQ-123).
2. B's host stops, and B starts draining (hosting REQ-27). ShutdownTimeout passes, and j1's token is signalled (REQ-139).
3. The handler does what it should: it throws OperationCanceledException. No cancellation was requested and no timeout passed, so REQ-136 and REQ-138 do not apply. **REQ-129 marks j1 Failed with the attempt counted, and it waits for its backoff.** On its last attempt, REQ-131 dead-letters it.
4. A handler that *ignored* the token would instead have been released at once with the attempt taken back (REQ-140).

**Why.** REQ-140 exists so that "shutdown is not the job's fault" (its notes), but it covers only the uncooperative handler. The cooperative case falls through to the generic failure rules.

**Options**
1. *(recommended)* Extend REQ-140's `if` to "the handler is still running or throws OperationCanceledException".
2. Add a separate rule for OperationCanceledException after a shutdown signal that returns the job to Enqueued without counting the attempt. The effect is the same, in two requirements.

**Ready to apply (option 1)**
```json
{ "id": "REQ-140", "ears": { "while": "the job's node is draining and the job's token was cancelled for shutdown",
    "if": "the handler is still running or throws OperationCanceledException",
    "shall": "release the job's lease and take back the attempt it counted, so another node can claim it immediately and the interrupted run does not count towards maxAttempts" } }
```
REQ-129 and REQ-131 then need "and the token was not cancelled for shutdown" to stay complementary.

---

## F-9 · gap · medium — Requeuing a dead-lettered chain step never revives the rest of the chain

<!-- finding: gap | ConditionNotMet | REQ-141,REQ-143,REQ-174,REQ-176 -->

**Requirements involved**
- REQ-176: *…store the first job as enqueued and each later job as an OnSuccess continuation of the one before it…* (notes: *"a dead-lettered step cancels the rest of the chain"*)
- REQ-174: *…when its parent succeeds or is dead-lettered, if the parent's outcome does not match the continuation's condition, then the system shall cancel the continuation with reason ConditionNotMet.*
- REQ-141: *When an operator requeues a dead-lettered job…, the system shall enqueue the job again…*

**What happens** (`Jobs_Flow_GAP3.cfg`: the probe `Gap_ContinuationLostOnRequeue` is violated in 7 states)
1. The app creates the chain *import → report*. import is Enqueued, and report is an OnSuccess continuation of import (REQ-176).
2. import is claimed and dead-lettered. report is cancelled with ConditionNotMet (REQ-174).
3. The operator fixes the bug and requeues import (REQ-141). import runs and succeeds (REQ-123, REQ-127).
4. **report stays Cancelled, and the chain never finishes.** The operator has to find and requeue each later step by hand.

**Why.** Batches were given an explicit "upgrade after requeue" rule (REQ-179, SCN-119). Job continuations were not, so the two mechanisms behave differently after the same operator action.

**Options**
1. *(recommended)* Keep a mismatched continuation Awaiting while its parent can still be requeued (DeadLettered), and cancel it only when the parent is cancelled, deleted or removed. This mirrors REQ-181 and its notes. LIV-102 then also waits on dead letters, so it becomes `should` for that case.
2. Add a rule: when a dead-lettered parent is requeued, return its ConditionNotMet continuations to Awaiting.
3. Keep today's behaviour and add a note that requeuing one step does not revive the chain, plus a dashboard action to requeue the whole chain.

**Ready to apply (option 2)** (option 1 changes LIV-102's strength, so option 2 is the smaller edit)
```json
{ "id": "REQ-191", "kind": "transition", "status": "proposed", "strength": "must",
  "entity": "Job", "actor": "system", "from": ["Cancelled"], "to": ["Awaiting"],
  "ears": { "while": "a continuation is cancelled with reason ConditionNotMet",
    "when": "its dead-lettered parent is requeued",
    "shall": "store the continuation as awaiting again, with its parentId and condition" },
  "mentions": ["Job.parentId", "Job.continuationCondition"], "dependsOn": ["REQ-141", "REQ-142", "REQ-174"] }
```

---

## F-10 · gap · medium — A batch with a removed member never completes or succeeds, so its continuation waits for ever

<!-- finding: gap | LIV-102 | REQ-144,REQ-145,REQ-179,REQ-180,REQ-181 -->

**Requirements involved**
- REQ-180: *While a batch is open, when every member job is succeeded, dead-lettered or cancelled and at least one did not succeed, the system shall mark the batch completed.*
- REQ-179: *While a batch is open or completed, when every member job has succeeded, the system shall mark the batch succeeded.*
- REQ-145: *When a job has been succeeded, cancelled or dead-lettered for longer than that state's retention, the system shall remove the job…* · REQ-144 (delete) · LIV-102: *While a continuation is awaiting, the system shall eventually enqueue or cancel it.*

**What happens**
- *A batch that never completes* (`Jobs_Flow_F2.cfg`: `Liv_ContinuationResolved` violated, the trace ends in stuttering):
  1. The app creates batch b1 with members j2 and j3 and an OnBatchCompleted continuation j1 (REQ-177).
  2. j2 is dead-lettered (REQ-131). j3 is still retrying or waiting, for example Unroutable or scheduled far ahead.
  3. j2's 30-day retention passes, and it is removed (REQ-145).
  4. j3 is dead-lettered. "Every member job is succeeded, dead-lettered or cancelled" can no longer be true, because j2 no longer exists. **b1 stays Open, and j1 waits for ever.** The main run (`Jobs_Flow.cfg`) finds the same result with an operator Delete of a member (REQ-144).
- *A completed batch that can no longer be upgraded* (`Jobs_Flow_GAP4.cfg`: the probe is violated in 8 states): j2 succeeds and j3 is dead-lettered, so b1 is Completed (REQ-180). After 7 days j2 is removed (RetentionSucceeded, REQ-104). On day 8 the operator requeues j3, still within its 30-day retention, and it succeeds. **REQ-179 can never fire, so the OnBatchSucceeded continuation never runs**, although SCN-119 describes exactly this operator action.

**Why.** "Every member job" has two readings: the members created with the batch, or the members that still exist. Assumption A-12 takes the first. Under the second reading the batch can succeed with a dead-lettered member removed, which is worse. Either way, retention and delete do not know about batches.

**Options**
1. *(recommended)* Keep batch members as long as their batch is not Succeeded: give REQ-145 an `if` that skips them. A member deleted explicitly (REQ-144) counts as not succeeded for REQ-180.
2. Count a removed member as "finished, not succeeded" in REQ-180, and when a Completed batch loses a member, cancel its OnBatchSucceeded continuations with reason ConditionNotMet. LIV-102 then holds, but SCN-119 only works within RetentionSucceeded.
3. Give the batch its own retention and remove the batch with its members as one unit.

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-145", "ears": { "when": "a job has been succeeded, cancelled or dead-lettered for longer than that state's retention",
      "if": "the job is not a member of a batch that is open or completed",
      "shall": "remove the job together with its state history, captured logs and parameters, in batches of at most CleanupBatchSize" },
    "mentions": ["Batch.members"] },
  { "id": "REQ-180", "ears": { "while": "a batch is open",
      "when": "every member job is succeeded, dead-lettered, cancelled or deleted and at least one did not succeed",
      "shall": "mark the batch completed" } }
]
```

---

## F-11 · gap · medium — A continuation added to a parent that no longer exists is not covered

<!-- finding: gap | Job.parentId | REQ-170,REQ-175,REQ-188 -->

**Requirements involved**
- REQ-170: *When an application adds a continuation to a parent job…, the system shall store the continuation as awaiting…*
- REQ-175: *When an application adds a continuation to a parent that has already succeeded, been dead-lettered or been cancelled, the system shall resolve the continuation at once…*
- REQ-188: *While a continuation is awaiting, when its parent is deleted, the system shall cancel the continuation.*

**What happens** (concrete example; not modeled, see the Coverage note)
1. j1 succeeds on Monday (REQ-127). After RetentionSucceeded (7 days) it is removed (REQ-145).
2. On Wednesday of the following week, the app calls ContinueWith(j1, OnSuccess) with the id it kept.
3. REQ-175 does not apply, because j1 no longer exists, so it is not in a finished state. If REQ-170 stores the continuation as Awaiting, REQ-188 can never fire, since the delete event is in the past. **The continuation waits for ever, violating LIV-102.** The same happens with a parent the operator deleted (REQ-144).

**Why.** REQ-175 was added for parents that had already finished, but a parent that is already gone falls between REQ-170, REQ-175 and REQ-188.

**Options**
1. *(recommended)* Reject the call with an error that names the missing parent, and store nothing.
2. Resolve it as cancelled at once, with reason ParentNotFound. The call succeeds silently, and the caller cannot tell success from loss.

**Ready to apply (option 1)**
```json
{ "id": "INV-138", "kind": "invariant", "status": "proposed", "strength": "must", "entity": "Job",
  "ears": { "if": "an application adds a continuation to a parent job id that does not exist",
    "shall": "reject the call with an error that names the parent id, and store nothing" },
  "mentions": ["Job.parentId"], "dependsOn": ["REQ-170", "REQ-175"] }
```

---

## F-12 · unprovable · low — Strict queue priority and job priority can starve a job for ever (expected by the owner)

<!-- finding: unprovable | LIV-100 | INV-110,INV-111 -->

**Requirements involved**
- LIV-100 (should): *While a job is enqueued in an active queue, maintenance is off and at least one running worker node serves its queue, the system shall eventually claim the job.*
- INV-110: *…claim from the first queue in the worker's ordered list before any later queue, as long as the first has a claimable job.* · INV-111: *…by highest priority first and, for equal priority, in the order they were enqueued.*

**What happens** (`Jobs_Throttle_L1.cfg`: lasso back to state 4 · `Jobs_Throttle_L2.cfg`: lasso back to state 3)
1. A worker with one slot serves the ordered list ⟨critical, reports⟩. The app enqueues j1 in critical and j2 in reports.
2. j1 is claimed and succeeds (REQ-123, REQ-127). The app enqueues another critical job before the worker looks again (REQ-120).
3. That job is claimed first (INV-110), and the loop repeats. **j2 is never claimed.** L2 has the same loop with a priority-1 stream inside one queue (INV-111).

With one queue, equal priority, or a shared concurrency key, LIV-100 holds (`Jobs_Throttle_L0.cfg`, `Jobs_Throttle_L3.cfg`). FIFO order within a queue prevents starvation there.

**Why.** This is the starvation that the LIV-100 and INV-110 notes say the model should report. It is a consequence of strict priority, not a slip.

**Options**
1. *(recommended)* Accept the behaviour: add `"tags": ["accepted-unprovable"]` to LIV-100 and a note that weighted round-robin (REQ-159) is the remedy.
2. Add ageing: a job that has waited longer than a threshold is claimed before higher-priority work.
3. Make weighted round-robin the default instead of strict priority.

**Ready to apply (option 1)**
```json
{ "id": "LIV-100", "tags": ["accepted-unprovable"],
  "notes": "Fails by design under strict queue priority (INV-110) and job priority (INV-111) when higher-ranked work arrives continuously; weighted round-robin (REQ-159) avoids it. Holds for one queue with equal priorities. Confirmed by the model 2026-11-06 (F-12)." }
```

---

## F-13 · unprovable · low — A continuation waits for ever behind an Unroutable parent or a Completed batch (expected by the owner)

<!-- finding: unprovable | LIV-102 | REQ-124,REQ-181 -->

**Requirements involved**
- LIV-102: *While a continuation is awaiting, the system shall eventually enqueue or cancel it.* Its notes say: *"Expected to fail as written when the parent stays Unroutable or Failed for ever, and for an OnBatchSucceeded continuation of a batch that stays Completed."*

**What happens** (`Jobs_Flow_F3.cfg`: lasso back to state 6)
1. The app creates the chain j3 → j1 and adds a second continuation j2 to j3 (REQ-176, REQ-170).
2. j3 fails and is retried (REQ-129, REQ-130).
3. No live node has j3's handler, so j3 becomes Unroutable (REQ-124). A node with the handler starts, and j3 is enqueued again (REQ-125). The node goes away again, and the loop repeats. **j1 and j2 never leave Awaiting.** The Completed-batch case is in the REQ-181 notes. The model does not need it to break LIV-102, because F-10 already does.

With no Unroutable parents and no batches, LIV-102 holds (`Jobs_Flow_F4.cfg`). Failed parents always resolve, because MaxAttempts bounds the retries.

**Options**
1. *(recommended)* Accept the behaviour: add `"tags": ["accepted-unprovable"]` to LIV-102 and keep the operator cancel (REQ-134) as the way out.
2. Make the system responsible: cancel continuations whose parent has been Unroutable for longer than a new UnroutableContinuationTimeout.

**Ready to apply (option 1)**
```json
{ "id": "LIV-102", "tags": ["accepted-unprovable"] }
```

---

## Modeling assumptions

These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.

| # | Assumption | Affects |
|---|---|---|
| A-1 | No clocks. scheduledAt/retryAt passing, UnroutableAfter, the timeout, TimeoutGracePeriod, ShutdownTimeout and retention are each a nondeterministic event that may happen at any time and, because time passes, eventually does (fair). Backoff lengths, retention lengths and window lengths are not judged. | REQ-100, REQ-104, REQ-122, REQ-124, REQ-130, REQ-137, REQ-145, REQ-183, REQ-187, REQ-189, INV-105 |
| A-2 | A lease is a flag. It can expire at any time while processing (crash, partition or pause), and a late heartbeat from the run that holds the current token renews it (REQ-126 has no "not yet expired" guard). | REQ-102, REQ-126, REQ-132, REQ-133, INV-104, LIV-101 |
| A-3 | A crash removes the node's handlers at once; its leases expire later. Draining nodes stop as hosting REQ-29 says. | REQ-132, REQ-139, REQ-140 |
| A-4 | "Free worker slot" (REQ-123) counts handlers that hold a claim. INV-106 counts every handler executing in the node's process, including abandoned and released ones. | F-5 |
| A-5 | OperationCanceledException is thrown only after the token was signalled. REQ-136 and REQ-138/186 take precedence over REQ-129/131 for it (REQ-136 notes). The overlap between REQ-136 and REQ-138 is checked, not resolved. | F-6, F-8 |
| A-6 | "While P, eventually Q" is read as `P ~> (Q \/ ~P)`: the obligation ends when P stops holding, for example when the job is cancelled or deleted. | LIV-100, LIV-101, LIV-102 |
| A-7 | Every run ends eventually (the timeout guarantees it), so a run's outcome is fair in the throttling and flow models. | Jobs_Throttle.tla, Jobs_Flow.tla |
| A-8 | A retried job joins the back of its queue for the "order they were enqueued" rule. | INV-111 |
| A-9 | Rate-limit windows are fixed windows that end nondeterministically; sliding windows are not modeled. | INV-109 |
| A-10 | Continuations are resolved in the same step as their parent's outcome, cancellation or deletion, and a cancellation cascades down a chain in that step (REQ-173 notes). | REQ-171–REQ-175, REQ-188 |
| A-11 | In `Jobs_Flow.tla`, removed job slots are not reused, so parent links stay valid. Deadlock checking is off there (`--no-deadlock`) because the pool runs out. | Jobs_Flow.tla |
| A-12 | "Every member job" (REQ-179, REQ-180) ranges over the members created with the batch; a removed member is neither succeeded nor finished. | F-10 |
| A-13 | Bounds: 1–3 jobs, 2 nodes, 1 queue (2 in the throttling model), MaxAttempts = 2 (1 for the LIV-101 run), node limit 1, at most 2 lease tokens per job, Max and N in {1, 2}. Queue pause and maintenance run in `Jobs_HoldsQ.cfg` with MaxAttempts = 1, and the flow holds check is split by people/environment actions, so each run stays under 120 s. | all |
| A-14 | One job name; "a handler for its name or one of its aliases" is a per-node handler flag that can change when a node restarts (rolling deploy). | REQ-101, REQ-123, REQ-124, REQ-125 |

## Coverage

| Modeled | Skipped (reason) |
|---|---|
| REQ-100–102, REQ-104, REQ-106–108, REQ-120–145, REQ-147, REQ-150–152, REQ-156, REQ-158, REQ-160–163, REQ-170–177, REQ-179–189, INV-100, INV-103, INV-104, INV-106–111, INV-113–115, INV-118, INV-128–130, INV-135, LIV-100–102, SCN-100–105, SCN-107–112, SCN-114, SCN-115, SCN-117–120 | Inline mode: REQ-146, INV-131–134, INV-137 (call-stack semantics) · data, not state: REQ-105, REQ-148, REQ-154, REQ-155, REQ-165–169, INV-116, INV-117, INV-119–127, INV-136 · no effect on state: REQ-103, REQ-109, INV-105 (absorbed by A-1) · transactions: INV-101, REQ-153, SCN-113 · INV-102 (one atomic call) · INV-112 (same shape as INV-107, see F-2) · strength `may`: REQ-157, REQ-159, REQ-164 · SCN-106 (not encoded separately; the Max guard is checked by Inv_KeyMax) · SCN-116 (payload size) · REQ-178 (retired) · F-11 is a static finding: the model only lets a continuation attach to an existing parent |

**Scenario results.** Every positive scenario is reachable: its trap is violated, as expected. That covers SCN-100, 101, 102, 105, 108, 111, 112, 114, 115, 118 and 119. Every negative scenario holds over the complete bounded state space: SCN-103, 104, 107, 110 and 117 (`Jobs_Holds.cfg`, `Jobs_HoldsQ.cfg`), SCN-120 (`Jobs_SCN120.cfg`) and SCN-109 (`Jobs_Flow_Holds.cfg`, `Jobs_Flow_HoldsC.cfg` and `Jobs_Flow_HoldsU.cfg`; the people and environment actions are split across them, because all of them together do not fit in 120 s). INV-103, INV-104, INV-113, INV-114, INV-128, INV-129 (state part) and INV-130 also hold in those runs. LIV-101 holds (`Jobs_LIV101.cfg`, 876,368 distinct states).

**Same-trigger warnings from `validate`.** REQ-127, REQ-128 and REQ-184 are modeled as one action, and so are REQ-129 and REQ-131, and REQ-132 and REQ-133. In each pair the guards are complementary, and the model found no state where both apply. The overlap the model did find is between REQ-136 and REQ-138 (F-6), which `validate` cannot see because their trigger wordings differ.

**Cross-module.** F-5 involves hosting's node concurrency limit (`hosting.Node.concurrencyLimit`), and F-8 involves the hosting draining rules (hosting REQ-27, REQ-29). F-3 affects the recurring module if occurrences can carry unique keys. The INV-100 scope per queue under Redis ShardByQueue (redis INV-500) was not modeled.

## Next

Apply the chosen options to `specs/jobs.json` with the `refiner-requirements` skill (it validates and diffs), then run this skill again. Findings whose fingerprint disappears are listed as resolved in the next report.
