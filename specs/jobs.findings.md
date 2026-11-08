# Findings: Bellhop job lifecycle

<!-- refiner-findings v1 | module: jobs | specHash: b7690959c1ee1848a995c4a3001a5ebc1b71e4e741902b6ec0a42867b436a1b6 | run: 2026-11-08 | previous: specs/model/jobs/previous.findings.md (run 4, specHash 7952e5e0ed20) -->

**Run:** 2026-11-08 (run 5, from `specs/model/jobs/handoff.json`, base c62b675) · **Requirements file:** `specs/jobs.json` (specHash `b7690959c1ee`) · **Model:** `model/jobs/Jobs.tla`, `Jobs_Unique.tla`, `Jobs_Throttle.tla`, `Jobs_Flow.tla` · **TLC:** 2.19. Every check ran alone with `--stop-at-first --workers 4` inside `timeout 170`, while four other modules were being checked on the same machine. No TLC exceptions. The largest completed runs were 5,710,480 distinct states in 63 s (`Jobs_HoldsQ.cfg`), 3,936,009 in 51 s (`Jobs_Flow_P1b.cfg`) and 2,765,676 in 24–38 s (`Jobs_Holds.cfg`, the CHK and GAP runs, `Jobs_SCN124.cfg`).
**Result:** 2 findings: 0 contradictions · 0 gaps · 2 ambiguities · 0 unprovable · 0 modeling notes. Run 4's only finding is resolved.

Only the requirement in the handoff was regenerated: REQ-190 (modified: the shutdown branch now reads "its token was cancelled for shutdown (REQ-139) while its handler is still running or it throws OperationCanceledException"). SCN-122 and SCN-125 (impacted) were re-checked. `NodeStop` encodes hosting REQ-29, whose wording changed in the same commit (57e6661: "the lease releases **and cancellations** that jobs REQ-140 **and REQ-190** call for at shutdown"), so it was regenerated too. Everything else in `Jobs.tla` is unchanged, and `Jobs_Unique.tla`, `Jobs_Throttle.tla` and `Jobs_Flow.tla` are unchanged byte-for-byte. None of the three mentions REQ-190 or the drain, but they were re-run anyway.

| File | Covers |
|---|---|
| `Jobs.tla` | execution, leases, recovery, retries, timeouts, shutdown, cancellation (REQ-190, REQ-191), requeue, delete, retention, queue pause, maintenance and routing |
| `Jobs_Unique.tla` | unique keys (FEAT-103) on every creating call, and the unique-key side of single and bulk requeue |
| `Jobs_Throttle.tla` | claim order, concurrency keys, rate limits, queue limits, the LongRunning limit, LIV-100 (FEAT-104) |
| `Jobs_Flow.tla` | continuations, chains and batches (FEAT-106), including INV-138, batch-member retention and batch removal (REQ-192) |

What changed in `Jobs.tla`:

- `R190` gained the shutdown OCE branch: the job's cancellation was requested and it throws OperationCanceledException after its token was cancelled for shutdown.
- `ReleaseOnShutdown`'s cancel branch is now triggered as REQ-190 says: the token was cancelled for shutdown while the handler is still running. It has no timeout guard, because the sentence has none. A-19 from run 4 is withdrawn.
- `NodeStop` (hosting REQ-29) also waits for REQ-190's shutdown cancellations (`R190Pending`). "In flight" is now a running handler that holds its job's current lease, so a job already settled no longer holds the node (A-3).
- New checks: `Chk_NoCancelLeftAtStop` (in both holds runs), `Chk_SingleOutcome` (`Jobs_CHK6.cfg`) and `Reach_ShutdownCancelled` (`Jobs_P3.cfg`).

To reproduce, run `sh run_all.sh` from `specs/model/jobs`.

## Changes since last run

| Finding | Status |
|---|---|
| F-1 (run 4) | resolved: hosting REQ-29 now waits for REQ-190's shutdown cancellation. No draining node ever stops while a cancel-requested run still holds its job's lease (`Chk_NoCancelLeftAtStop` holds in `Jobs_HoldsQ.cfg` at MaxAttempts = 1, the case run 4 reported, and in `Jobs_Holds.cfg` at MaxAttempts = 2). The fixed path is reachable: a job cancelled at its last attempt ends Cancelled at a graceful stop (`Jobs_P3.cfg`, an 8-state trace). Run 4's probe `Gap_CancelledDeadLetteredAfterDrain` (`Jobs_GAP7.cfg`) is still violated, but only by a different, accepted path: the cancellation arrives after the node has stopped (see *Accepted*) |
| F-1 | new: REQ-191 does not name REQ-190's new shutdown trigger |
| F-2 | new: REQ-136 and REQ-190's new shutdown branch both decide an OperationCanceledException thrown at shutdown, with the same outcome |

`findings_delta.py specs/model/jobs/previous.findings.md specs/jobs.findings.md`:

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | ambiguity · Gap_CancelledDeadLetteredAfterDrain · REQ-133,REQ-140,REQ-190,hosting.REQ-29 |
| F-1 | new | ambiguity · Reach_ShutdownCancelled · REQ-140,REQ-190,REQ-191 |
| F-2 | new | ambiguity · Chk_SingleRule · REQ-136,REQ-190 |

1 resolved, 2 new, 0 still open. (The "resolved" row uses run 4's number.)

## Summary

| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | ambiguity | medium | REQ-191, REQ-190, REQ-140 | A handler abandoned by REQ-190's shutdown branch fits neither of REQ-191's triggers, so it may not be recorded, unlike one released by REQ-140 |
| F-2 | ambiguity | low | REQ-136, REQ-190 | REQ-136 and REQ-190 both mark a cancel-requested job Cancelled when it throws OperationCanceledException at shutdown |

---

## F-1 · ambiguity · medium — A handler abandoned by REQ-190's shutdown branch fits neither of REQ-191's triggers
<!-- finding: ambiguity | Reach_ShutdownCancelled | REQ-140,REQ-190,REQ-191 -->

**Requirements involved**
- REQ-190 (changed): *While a job is processing and its cancellation was requested, when … **its token was cancelled for shutdown (REQ-139) while its handler is still running** or it throws OperationCanceledException, … the system shall **abandon the handler if it is still running** and mark the job cancelled …*
- REQ-191: *When the system abandons a handler that is still running, **after a timeout (REQ-138, REQ-186, REQ-190) or a release at shutdown (REQ-140)**, or refuses the heartbeat of a handler that is still running because its lease token is no longer current or its job is no longer processing (INV-128), the system shall log a warning naming the job, its attempt and the node, and record in that attempt that its handler was abandoned or lost its lease and is still running outside the node's concurrency limit.*
- REQ-140: *While the job's node is draining, the job's token was cancelled for shutdown, its timeout token was not signalled and its cancellation was not requested, if the handler is still running or throws OperationCanceledException, then the system shall release the job's lease and take back the attempt it counted …*

**What happens** (`Jobs_P3.cfg`: the trap `Reach_ShutdownCancelled` is violated as expected, an 8-state trace at MaxAttempts = 1)
1. j1 is enqueued and node n1 claims it at attempt 1 (REQ-120, REQ-123).
2. An operator cancels j1. The request is recorded and j1's token is signalled (REQ-135). The handler ignores the signal and keeps running.
3. The host stops n1, so n1 drains (hosting REQ-27). ShutdownTimeout passes and j1's token is cancelled for shutdown (REQ-139). The handler is still running.
4. REQ-190's shutdown branch applies: **n1 abandons the still-running handler** and marks j1 Cancelled. n1 then stops (hosting REQ-29).

At step 4 the handler is abandoned while still running, so REQ-191's first trigger matters. But REQ-191 only lists abandonment "after a timeout (REQ-138, REQ-186, REQ-190)", and no timeout was signalled. Its other trigger, "a release at shutdown (REQ-140)", does not fit either, because REQ-140 excludes a job whose cancellation was requested and nothing is released. Read literally, j1's attempt gets no "abandoned" record and no warning is logged. Compare a job without a cancel request at the same moment: REQ-140 releases it and REQ-191 records it.

**Why.** Until run 4, REQ-190's shutdown trigger read "its node releases it at shutdown", which matched REQ-191's "a release at shutdown" in spirit, and the model recorded it. The run-5 wording names the real event (the shutdown token), and REQ-191 was not updated to match. The model records nothing for this case (the job is tagged `ShutdownCancel`, not `Abandoned`) until this is decided.

**Options**
1. *(recommended)* Name REQ-190's shutdown branch in REQ-191: "… after a timeout (REQ-138, REQ-186, REQ-190), a release at shutdown (REQ-140) or a cancellation at shutdown (REQ-190), …". Every handler abandoned while still running is recorded, so the dashboard shows the same thing whether or not the job was cancel-requested. Cost: one clause.
2. Drop the list of causes from REQ-191's first trigger: "When the system abandons a handler that is still running (REQ-138, REQ-140, REQ-186, REQ-190) …". This has the same effect as option 1 and also covers any future abandonment path, but the record no longer says why the handler was abandoned unless the record's wording says so.
3. Accept it: a handler of a cancelled job abandoned at shutdown is not recorded, because its node is stopping and claims nothing more. Say so in REQ-191's notes. Cost: a cancelled attempt can show no trace that its handler was still running when the node stopped.

**Ready to apply (option 1, in `specs/jobs.json`)**
```json
{ "id": "REQ-191", "ears": {
    "when": "the system abandons a handler that is still running, after a timeout (REQ-138, REQ-186, REQ-190), a release at shutdown (REQ-140) or a cancellation at shutdown (REQ-190), or refuses the heartbeat of a handler that is still running because its lease token is no longer current or its job is no longer processing (INV-128)",
    "shall": "log a warning naming the job, its attempt and the node, and record in that attempt that its handler was abandoned or lost its lease and is still running outside the node's concurrency limit" } }
```
Notes addition: *"refiner-model 2026-11-08 run 5 F-1: REQ-190's shutdown branch abandons a still-running handler without a timeout or a release; it is recorded like the other two."*

---

## F-2 · ambiguity · low — REQ-136 and REQ-190 both decide an OperationCanceledException thrown at shutdown by a cancel-requested job
<!-- finding: ambiguity | Chk_SingleRule | REQ-136,REQ-190 -->

**Requirements involved**
- REQ-136: *While a job is processing and its cancellation was requested, when its handler throws OperationCanceledException, the system shall mark the job cancelled.*
- REQ-190 (changed): *While a job is processing and its cancellation was requested, when … its token was cancelled for shutdown (REQ-139) while its handler is still running **or it throws OperationCanceledException**, … the system shall abandon the handler if it is still running and mark the job cancelled …*
- REQ-190 notes: *"The guards of REQ-129, REQ-132, REQ-138, REQ-140 and REQ-186 exclude a requested cancellation, so exactly one rule applies."*

**What happens** (`Jobs_CHK2.cfg`: `Chk_SingleRule` violated, a 7-state trace)
1. j1 is enqueued and node n1 claims it at attempt 1 (REQ-120, REQ-123).
2. An operator cancels j1 and its token is signalled (REQ-135).
3. The host stops n1. ShutdownTimeout passes and j1's token is cancelled for shutdown (REQ-139).
4. The handler now throws OperationCanceledException. **Both REQ-136 and REQ-190's shutdown branch apply.**

Both mark j1 Cancelled, and the handler is not running, so neither abandons anything. `Chk_SingleOutcome` (`Jobs_CHK6.cfg`) holds: every pair of rules that applies to one throw decides the same outcome. So the two requirements do not contradict each other. Since run 2, `Chk_SingleRule` had held: at most one throw rule applied to any exception. It no longer does.

**Why.** REQ-190's new shutdown branch mirrors REQ-140 ("still running or throws OperationCanceledException"). REQ-140 needs the OCE branch because no other rule releases a cooperating handler. For a cancel-requested job, REQ-136 already marks it cancelled on any OperationCanceledException.

**Options**
1. *(recommended)* Drop the OCE clause from REQ-190's shutdown branch: "… its token was cancelled for shutdown (REQ-139) while its handler is still running, …". REQ-136 still marks the job cancelled when the handler cooperates, and exactly one rule decides each event again. Cost: REQ-190 no longer reads as the mirror image of REQ-140.
2. Accept the overlap and add to REQ-190's notes: *"The OCE clause of the shutdown branch overlaps REQ-136; both mark the job cancelled."* No semantic change. Cost: the "exactly one rule applies" property the notes claim becomes "exactly one outcome applies".
3. Exclude shutdown from REQ-136 ("… throws OperationCanceledException and its token was not cancelled for shutdown …"). This removes the overlap from the other side, but it changes a requirement that has been stable since run 1.

**Ready to apply (option 1, in `specs/jobs.json`)**
```json
{ "id": "REQ-190", "ears": { "while": "a job is processing and its cancellation was requested",
    "when": "its lease expires with attempts left, its token was cancelled for shutdown (REQ-139) while its handler is still running, its handler is still running TimeoutGracePeriod after its timeout token was signalled, or its handler throws an exception other than OperationCanceledException or PermanentJobFailureException while the attempt number is below maxAttempts and the retry policy allows another attempt",
    "shall": "abandon the handler if it is still running and mark the job cancelled instead of returning it to enqueued, marking it failed or dead-lettering it for the timeout" } }
```
Notes addition: *"refiner-model 2026-11-08 run 5 F-2: an OperationCanceledException thrown at shutdown by a cancel-requested job is REQ-136's; this branch covers only a handler that is still running."*

---

## Accepted (not reported as findings)

- **Cancellation that arrives after a draining node stopped** (`Jobs_GAP7.cfg`, run 4's probe, an 11-state trace at MaxAttempts = 1). The trace runs like this. A timed-out job is still in its grace period when ShutdownTimeout passes, so its node stops without waiting for it, as hosting REQ-29's notes accept. An operator cancels it while it is still Processing with no live node. Its lease expires at its last attempt, and REQ-133 dead-letters it, because REQ-190's lease branch requires attempts left. That is the lease-expiry outcome REQ-190's notes accept ("exhausted attempts on … lease expiry still dead-letter"). It is the same as a crash, and REQ-186 would have dead-lettered the job at that attempt anyway.
- **LIV-100** (`accepted-unprovable`): strict queue priority and job priority can still starve a job for ever (`Jobs_Throttle_L1.cfg` and `Jobs_Throttle_L2.cfg`, lassos). It holds with one queue and equal priority (`L0`) and with a shared concurrency key (`L3`).
- **LIV-102** (`should`, `accepted-unprovable`): a continuation behind an Unroutable parent can still wait for ever (`Jobs_Flow_F3.cfg`, lasso). `F1`, `F2`, `F4` and `F5` hold.
- **REQ-143 / run 2 F-6** (accepted in REQ-143's notes): requeuing a cancelled parent does not revive the continuations cancelled with it (`Jobs_Flow_GAP3.cfg`).
- **INV-106, former reading** (handlers executing, abandoned ones included): still violated (`Jobs_INV106.cfg`, `Chk_HandlersWithinLimit`), as the owner accepted in run 1.
- **INV-108/109, former reading** (state invariants): still violated after an operator lowers a limit (`Jobs_Throttle.cfg`, `Chk_KeyMaxState`). The claim-time wording holds (`Jobs_Throttle_Holds.cfg`, `Jobs_Throttle_HoldsK.cfg`).
- **Timed-out job at shutdown, recovered by lease expiry** (REQ-140 and hosting REQ-29 notes): when ShutdownTimeout passes before TimeoutGracePeriod ends, the job comes back through REQ-132 with reason Interrupted and no backoff, rather than through REQ-138 with reason Timeout and retryAt. The attempt counts either way (`Jobs_P2.cfg`), and the notes accept it.

## Runs

| cfg | Result | Distinct states | s |
|---|---|---|---|
| `Jobs_Holds` (now with `Chk_NoCancelLeftAtStop`) | holds | 2,765,676 | 25 |
| `Jobs_HoldsQ` (same addition; MaxAttempts = 1) | holds | 5,710,480 | 63 |
| `Jobs_CHK` / `CHK3` / `CHK4` / `CHK5` | hold | 2,765,676 each | 27–31 |
| `Jobs_CHK2` (`Chk_SingleRule`) | **violated** (F-2; held since run 2) | 1,377 | 1 |
| `Jobs_CHK6` (new, `Chk_SingleOutcome`) | holds | 2,765,676 | 38 |
| `Jobs_GAP1` / `GAP2` / `GAP5` | hold | 2,765,676 each | 27–33 |
| `Jobs_GAP6` | not run: holds by construction since run 4; the full two-slot space does not finish in 170 s | – | – |
| `Jobs_GAP7` | violated, accepted path only: the cancellation arrives after the node stopped (run 4: F-1) | 19,977 | 1 |
| `Jobs_P2` | violated (reachable, accepted path) | 15,449 | 1 |
| `Jobs_P3` (new, `Reach_ShutdownCancelled`) | violated (reachable, as expected; F-1 example) | 3,088 | 1 |
| `Jobs_INV106` | violated (accepted) | 639 | 1 |
| `Jobs_LIV101a` / `LIV101b` | hold | 71,760 / 565,888 | 6 / 36 |
| `Jobs_LIV29` (`Liv_DrainEnds`, hosting REQ-29 run-5 wording) | holds | 71,760 | 10 |
| `Jobs_SCN100/101/102/111/112/115/122/124s/125` | traps violated (reachable, as expected) | 144–10,318 | 1 |
| `Jobs_SCN120` / `Jobs_SCN124` | hold | 1,230,432 / 2,765,676 | 11 / 32 |
| `Jobs_Unique`, `U1`–`U5` / `SCN105` | hold / trap violated | 3,220–7,794 / 56 | 1–2 |
| `Jobs_Throttle_*` (unchanged) | Holds, HoldsK, T0, T2, T3, L0, L3 hold; L1 and L2 (lassos) and `Jobs_Throttle` violated, accepted | ≤ 1,692 | 1 |
| `Jobs_Flow_Holds` / `HoldsC` / `HoldsU` | hold | 1,407,799 / 652,237 / 259,033 | 21 / 10 / 5 |
| `Jobs_Flow_P1b` | holds | 3,936,009 | 51 |
| `Jobs_Flow_F1` / `F2` / `F4` / `F5` | hold | 206,420 / 207,248 / 205,289 / 206,420 | 13–22 |
| `Jobs_Flow_F3` | violated (accepted, LIV-102) | 41,039 | 5 |
| `Jobs_Flow_GAP3b` / `GAP4` | hold | 1,388,164 / 1,396,162 | 11 / 14 |
| `Jobs_Flow_GAP3` / `GAP5` / `GAP6` | violated (accepted / allowed / accepted) | 116,374 / 389 / 3,711 | 1–2 |
| `Jobs_Flow_P1` | violated (the required case since run 4) | 459,012 | 5 |
| `Jobs_Flow_SCN108/114/118/119/121` | traps violated (reachable, as expected) | 194–268,315 | 1–3 |

**Timeouts.** `Jobs.cfg` and `Jobs_LIV101.cfg` still exceed 170 s and run split, as in runs 3 and 4, and `Jobs_GAP6` still does not finish. Every other run finished within the skill's 120 s budget. Distinct-state counts vary by a few percent between runs because TLC's multi-worker exploration is nondeterministic. The traces quoted above are from the runs listed.

## Modeling assumptions

These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.

| # | Assumption | Affects |
|---|---|---|
| A-1 | No clocks. scheduledAt/retryAt passing, UnroutableAfter, the timeout, TimeoutGracePeriod, ShutdownTimeout and retention (including REQ-192's "every stored member past its retention") are each a nondeterministic event that may happen at any time and, because time passes, eventually does (fair). Backoff lengths, retention lengths and window lengths are not judged. | REQ-100, REQ-104, REQ-122, REQ-124, REQ-130, REQ-137, REQ-145, REQ-183, REQ-187, REQ-189, REQ-192, INV-105 |
| A-2 | A lease is a flag. It can expire at any time while processing (crash, partition or pause), and a late heartbeat from the run that holds the current token renews it (REQ-126 has no "not yet expired" guard). | REQ-102, REQ-126, REQ-132, REQ-133, INV-104, LIV-101 |
| A-3 | *(changed in run 5)* A crash removes the node's handlers at once; its leases expire later. A draining node stops as hosting REQ-29's run-5 wording says. "In-flight job" (hosting `Node.inFlightJobs`, not defined) is a running handler that holds its job's current lease. A job settled by REQ-138/186/190, released by REQ-140 or lost to lease expiry is no longer in flight, though its handler may still be running, as hosting REQ-29's notes say ("stays in flight until jobs REQ-138 or REQ-186 settles it"). After ShutdownTimeout the node waits for every release REQ-140 calls for and every cancellation REQ-190 calls for. Every such attempt succeeds, because store outages are not modeled here. A stopped node's handlers stop with it. | REQ-132, REQ-139, REQ-140, REQ-190, hosting REQ-29 |
| A-4 | "Holds claims on processing jobs" (REQ-123, INV-106) counts processing jobs whose current lease token is held by the node's live run. Handlers that were abandoned, released or lost their lease are not counted. | INV-106, REQ-123 |
| A-5 | OperationCanceledException is thrown only after a token was signalled. REQ-136 and REQ-138/186 take precedence over REQ-129/131 for it (REQ-136 notes). Every other overlap between the throw rules is checked, not resolved: `Chk_SingleRule` counts the rules (violated in run 5, F-2) and `Chk_SingleOutcome` compares their outcomes (holds). | REQ-129–140, REQ-186, REQ-190 |
| A-6 | "While P, eventually Q" is read as `P ~> (Q \/ ~P)`: the obligation ends when P stops holding, for example when the job is cancelled or deleted. | LIV-100, LIV-101, LIV-102, REQ-192 |
| A-7 | Every run ends eventually (the timeout guarantees it), so a run's outcome is fair in the throttling and flow models. | Jobs_Throttle.tla, Jobs_Flow.tla |
| A-8 | A retried job joins the back of its queue for the "order they were enqueued" rule. | INV-111 |
| A-9 | Rate-limit windows are fixed windows that end nondeterministically; sliding windows are not modeled. | INV-109 |
| A-10 | Continuations are resolved in the same step as their parent's outcome, cancellation, deletion, removal by retention or batch removal, and a cancellation cascades down a chain in that step (REQ-173 notes). | REQ-171–REQ-175, REQ-188, REQ-192 |
| A-11 | In `Jobs_Flow.tla`, removed job slots and removed batches are not reused, so parent links stay valid. Deadlock checking is off there (`--no-deadlock`) because the pool runs out. | Jobs_Flow.tla |
| A-12 | "Every member job" (REQ-179, REQ-180) ranges over the members created with the batch; an explicitly deleted member counts as finished and not succeeded (REQ-180). REQ-192's "every member job that is still stored" skips deleted and retention-removed members. | REQ-179, REQ-180, REQ-192 |
| A-13 | Bounds: 1–4 jobs, 2 nodes, 1 queue (2 in the throttling model), MaxAttempts = 2 (1 for `Jobs_HoldsQ`, `Jobs_LIV101a/b`, `Jobs_LIV29`, `Jobs_GAP7`, `Jobs_P3`, `Jobs_Flow_Holds`, `Jobs_Flow_GAP3/GAP3b/GAP4`, `Jobs_Flow_P1/P1b`), node limit 1, at most 2 lease tokens per job (1 in `Jobs_LIV101a` and `Jobs_LIV29`), Max and N in {1, 2}, one node's LongRunning limit 1. `Jobs_Flow_P1/P1b` use 4 job slots. One namespace: the per-queue scope of INV-100 under Redis ShardByQueue is not modeled. | all |
| A-14 | One job name; "a handler for its name or one of its aliases" is a per-node handler flag that can change when a node restarts (rolling deploy). | REQ-101, REQ-123, REQ-124, REQ-125 |
| A-15 | A schedule call for a time that is not in the future (REQ-182) is a call that schedules, so ReplaceSchedule applies to it (REQ-150's "the call does not schedule a job"). | REQ-150, REQ-151, REQ-182 |
| A-18 | REQ-191's record and log line are history only. The lease-lost trigger is the predicate `LeaseLostRecordable`: a running handler on a live node whose token is not current or whose job is not processing. For a job that was deleted or removed, only the log line can be written, because "that attempt" no longer exists. REQ-190's shutdown abandonment is not recorded until F-1 is decided (tag `ShutdownCancel`). | REQ-191, INV-128 |

A-19 from run 4 (REQ-190's "its node releases it at shutdown" read as the release REQ-140 would make) is withdrawn: REQ-190 now names its own trigger.

## Coverage

| Modeled | Skipped (reason) |
|---|---|
| REQ-100–102, REQ-104, REQ-106–108, REQ-120–145, REQ-147, REQ-150–152, REQ-156, REQ-158, REQ-160–163, REQ-170–177, REQ-179–192, INV-100, INV-103, INV-104, INV-106–115, INV-118, INV-128–130, INV-135, INV-138, LIV-100–102, SCN-100–112, SCN-114, SCN-115, SCN-117–125 | Inline mode: REQ-146, INV-131–134, INV-137 (call-stack semantics) · data, not state: REQ-105, REQ-148, REQ-154, REQ-155, REQ-165–169, INV-116, INV-117, INV-119–127, INV-136 · no effect on state: REQ-103, REQ-109, INV-105 (absorbed by A-1) · transactions: INV-101, REQ-153, SCN-113 · INV-102 (one atomic call) · strength `may`: REQ-157, REQ-159, REQ-164 · SCN-116 (payload size) · REQ-178 (retired) · REQ-191's log line (only the record is state) |

**Scenario results.** Every positive scenario is reachable (trap violated, as expected): SCN-100, 101, 102, 105, 108, 111, 112, 114, 115, 118, 119, 121, 122 and 125. Every negative scenario holds over the complete bounded state space: SCN-103, 104, 107, 110, 117 and 124 (`Jobs_Holds.cfg`, `Jobs_HoldsQ.cfg`, `Jobs_SCN124.cfg`), SCN-106 (`Jobs_Throttle_Holds/HoldsK.cfg`), SCN-120 (`Jobs_SCN120.cfg`), and SCN-109 and SCN-123 (the flow holds runs). SCN-113 is still skipped. SCN-122 and SCN-125 (impacted) use REQ-190's lease branch, which did not change, and both are still reachable.

**Same-trigger warnings from `validate`.** REQ-127/128/184, REQ-129/131 and REQ-132/133 are modeled as one action each, and REQ-171/174 inside one resolution step. For REQ-136 vs REQ-190, see F-2.

**Cross-module.** Under hosting REQ-29's run-5 wording, a draining node always stops (`Liv_DrainEnds`, `Jobs_LIV29.cfg`), even though it now waits for REQ-190's cancellations. Hosting's own model should treat a cancel-requested job as something the drain waits for. The hosting run checks that. F-1 and F-2 are both fixed in `specs/jobs.json`, with no hosting change.

## Next

Apply the chosen options to `specs/jobs.json` (F-1: REQ-191; F-2: REQ-190) with the `refiner-requirements` skill (it validates and diffs), then run this skill again. Findings whose fingerprint disappears are listed as resolved in the next report.
