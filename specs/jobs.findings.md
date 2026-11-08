# Findings: Bellhop job lifecycle

<!-- refiner-findings v1 | module: jobs | specHash: d1c4f5af9f87339150943337d04b6b0e155d916eaf43724355ad60b513bb826c | run: 2026-11-08 | previous: specs/model/jobs/previous.findings.md (run 9, specHash d1c4f5af9f87) -->

**Run:** 2026-11-08 (run 10, no handoff: commit 7670cb7 changed notes only) · **Requirements file:** `specs/jobs.json` (specHash `d1c4f5af9f87`, unchanged) · **Model:** `model/jobs/Jobs.tla`, `Jobs_Unique.tla`, `Jobs_Throttle.tla`, `Jobs_Flow.tla` and the probe modules `Jobs_AfterChk.tla`, `Jobs_AfterChkG.tla` and `Jobs_AfterChk9.tla`, all byte-for-byte as in run 9 · **TLC:** 2.19. This run reran only the 12 cfgs that are the evidence for the changed notes: `Jobs_GAP7`, `Jobs_GAP8`, the eight `Jobs_AfterChk_*` cfgs and the two `Jobs_AfterChk9_*` cfgs. They ran with `TLC_WORKERS=4 TLC_TIMEOUT=400`, through the same `run` function as `run_all.sh`, each check alone with `--stop-at-first`, while another module was being checked on the same machine. All 12 finished with the expected result, with no timeouts and no TLC exceptions. The largest was `Jobs_AfterChk_X` (3,555,212 distinct states in 39 s).
**Result:** 0 findings: 0 contradictions · 0 gaps · 0 ambiguities · 0 unprovable · 0 modeling notes. Run 9's F-1 is resolved: the notes no longer cite a rule for the post-check case, and every claim they make is borne out by the model and the run-8/run-9 probes (see *Accepted*). Three wording observations are listed under *Also checked*. None of them is a claim the model contradicts.

No requirement was regenerated and no model file or cfg changed. Commit 7670cb7 changed two notes: the last part of jobs REQ-190's, and the matching sentence of hosting REQ-29's. Neither note is in the spec hash, so the hash is unchanged. This run checks those notes against the model and the probes. It also re-reads the rest of the REQ-136, REQ-138, REQ-140, REQ-186, REQ-190 and REQ-191 notes and hosting REQ-29's notes. **Every other result in this report comes from run 9's complete batch** (79 runs, all as expected, commit 1c8423d). It still stands because the models are unchanged and nothing semantic has changed since then.

| File | Covers |
|---|---|
| `Jobs.tla` | execution, leases, recovery, retries, timeouts, shutdown, cancellation (REQ-190, REQ-191), requeue, delete, retention, queue pause, maintenance and routing |
| `Jobs_Unique.tla` | unique keys (FEAT-103) on every creating call, and the unique-key side of single and bulk requeue |
| `Jobs_Throttle.tla` | claim order, concurrency keys, rate limits, queue limits, the LongRunning limit, LIV-100 (FEAT-104) |
| `Jobs_Flow.tla` | continuations, chains and batches (FEAT-106), including INV-138, batch-member retention and batch removal (REQ-192) |
| `Jobs_AfterChk.tla`, `Jobs_AfterChkG.tla` | *(run 8 probes)* `EXTENDS Jobs`. What can settle a run whose cancellation was requested after its draining node's check, and a timed-out run after ShutdownTimeout |
| `Jobs_AfterChk9.tla` | *(run 9 probes)* `EXTENDS Jobs_AfterChk`. Which lease-expiry rule decides a post-check cancellation, after the stop and before it |

Nothing is new in the model. To reproduce this run's subset, run the `Jobs_GAP7`/`Jobs_GAP8` line and the three AfterChk lines of `run_all.sh`. To reproduce everything, run `TLC_WORKERS=4 TLC_TIMEOUT=400 sh run_all.sh` from `specs/model/jobs`.

## Changes since last run

| Finding | Status |
|---|---|
| F-1 (run 9) | resolved. REQ-190's and hosting REQ-29's notes no longer cite "(REQ-132, REQ-133)" for a request made after the check. They say that it "ends as any cancel-requested job that is still processing does, by its handler's outcome or by lease expiry", and that they name no rules on purpose. `Jobs_AfterChk9_LA` (REQ-190's lease branch after the stop) and `LB` (lease expiry before the stop) both fall under "by lease expiry". Moved to *Accepted* |

`findings_delta.py specs/model/jobs/previous.findings.md specs/jobs.findings.md`:

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | ambiguity · Reach9_LeaseAfterStop · REQ-132,REQ-133,REQ-190,hosting.REQ-29 |

1 resolved, 0 new, 0 still open. (The "resolved" row uses run 9's number.)

## Summary

No findings.

---

## Also checked (not findings)

Each claim in the two changed notes, in order:

- **"A request made after that check is not part of the shutdown."** (REQ-190; hosting REQ-29 the same.) This holds. The check is made once per run (`chk`), and a request that arrives after it is not read by `ReleaseOnShutdown`, so REQ-190's shutdown branch never fires for it. `Prop_LateCancelNotLeft` (run 9 batch) holds for a request made before the check.
- **"Only a timed-out handler still in its grace period can be in flight then, because the check released or cancelled every other one"** (REQ-190; hosting REQ-29 the same without the "because"). This holds as in runs 8 and 9. Only `ShutdownCheckLeaves` sets `chk`, it needs the timeout signal, and `ReleaseOnShutdown` takes every other checked run out of flight. A draining node claims nothing (REQ-123 needs a running node). The modeling artefact from run 8, that grace passing and abandonment are two steps (A-1), is unchanged and not reported.
- **"The node does not wait for it"** (both notes). This holds. `NodeStop` needs only that every in-flight run was checked. `Jobs_GAP8` (rerun, 10 states) stops n1 with the cancel-requested run still in flight, and `Liv_DrainEnds` holds (`Jobs_LIV29.cfg`, run 9 batch).
- **"It ends as any cancel-requested job that is still processing does"** (both notes). This holds, and it is now the operative clause. `Chk8_Exits` (rerun, holds at MaxAttempts 2 and 1: `Jobs_AfterChk_X`, `X1`) lists every step that ends such a run. Each one is an action that any cancel-requested processing job can take: abandonment after the grace period (`AbandonOnTimeout`), a throw, a normal return, or lease recovery by a running worker node (`Recover`). Two steps leave the job Processing with no handler, the node's stop and a crash, after which only `Recover` can end it. None of these steps is specific to shutdown. The only ending that the post-check run cannot take is the shutdown check itself, which is the point of the first sentence. Delete is refused for a processing job (INV-130), and a claim needs Enqueued, so there is no other way out.
- **"By its handler's outcome or by lease expiry"** (both notes). This holds, reading "its handler's outcome" as run 9 did. The probes, all rerun and all reachable as expected:
  - REQ-136 (`Jobs_AfterChk_O`, 11 states),
  - REQ-127 (`R`, 10),
  - REQ-190's exception branch (`EC`, 10),
  - REQ-131 (`ED`, 10),
  - REQ-190's timeout branch: the handler is still running TimeoutGracePeriod after its timeout signal, and the grace period ends after the check (`T`, 11 states),
  - lease expiry after the stop with attempts left: REQ-190's lease branch, Cancelled (`Jobs_AfterChk9_LA`, 12 states),
  - lease expiry before the stop with attempts left: REQ-190's lease branch while n1 is still draining (`Jobs_AfterChk9_LB`, 11 states),
  - lease expiry at the last attempt: REQ-133, DeadLettered (`Jobs_GAP7`, 13 states).

  Run 9's extra observation, that lease expiry can also decide *before* the stop, no longer differs from the note, because the note dropped "until the node stops … after it". `T` is counted as "its handler's outcome" here, as in run 9: the handler did not finish within its grace period, and REQ-191's notes call a timeout the attempt's own outcome. It is also the most likely ending for this particular handler. A reader who takes "handler's outcome" to mean only a return or a throw would miss it. The clause before it ("as any cancel-requested job that is still processing does") covers it either way, and no reading changes the outcome, so it is not reported.
- **The `Jobs_GAP7` trace this run.** The multi-worker search found the pre-stop variant: the request comes after the check and before the stop (steps 10–12), then REQ-133 dead-letters j1 at MaxAttempts = 1. Run 9's trace was the after-stop variant. Both are "a request made after that check" and both end by lease expiry, so the note covers either.
- **"These notes deliberately name no rules"** (REQ-190, labelled "Run 7 to run 9 F-1") and **"these notes deliberately name no jobs rules"** (hosting REQ-29). *Observation, not a finding.* Read literally, "these notes" is each requirement's whole `notes` field, and both fields name many rules elsewhere: REQ-190's names REQ-129 to REQ-140, and hosting REQ-29's names jobs REQ-132, REQ-133, REQ-138, REQ-140, REQ-186 and REQ-190. The intended scope, the sentences about a request after the check, is clear from the label and from where the sentence sits. It makes no claim about behaviour, and no reading of it sends a reader to a wrong rule. It could still lead a later editor to strip the run-3 and run-4 citations. If the owner wants it exact: "this part deliberately names no rules" (REQ-190) and "this part deliberately names no jobs rules" (hosting REQ-29, a **hosting.json** edit).
- **Hosting REQ-29's label for that sentence still reads "jobs run 7 and run 8 F-1:".** *Observation, not a finding.* The sentence was rewritten for run 9 F-1 (commit 7670cb7), and REQ-190's matching label was updated to "Run 7 to run 9 F-1". This is provenance only, and the commit records the change. If wanted, change the label to "jobs run 7 to run 9 F-1:" (**hosting.json**).
- **Hosting REQ-29's run-1 sentence** ("a release that fails because the store is down is covered by lease expiry (jobs REQ-132), and that attempt then counts"). *Observation, not a finding.* This sentence has not changed since run 1. It is about a job with no request and no timeout signal, the only kind REQ-140 releases, and for that job REQ-132 is the rule while attempts are left. At the last attempt the rule is REQ-133 (dead-lettered), which "that attempt then counts" implies but does not name. The model cannot judge the failed release itself, because store outages are not modeled (A-3). The same notes field cites "(jobs REQ-132, REQ-133)" in its run-3 sentence. If the owner wants the two citations to match, it is a **hosting.json** edit.
- **REQ-140's notes, rest of** (unchanged since run 9). These hold as in run 9. "If the node stops before REQ-138 or REQ-186 settles it, lease expiry counts the attempt (REQ-132, REQ-133)" is about a timeout with no request, and for that job those are the rules: `Jobs_AfterChk_ST` (rerun, 8 states) shows REQ-186 settling before the stop, and `Jobs_P2` (run 9 batch) shows lease expiry after it. The run-6 sentence and "the lease is released as soon as ShutdownTimeout passes" are read at the check made after the token is cancelled (A-19), as since run 6.
- **Hosting REQ-29's run-3 and run-4 sentences** (unchanged since run 9). These hold as in run 9. Every run left in flight at the stop is a timed-out one that REQ-138/186 has not settled, or REQ-190's timeout branch if a request came later. A request made before the check ends Cancelled at a graceful stop even at the last attempt (`Reach_ShutdownCancelled`, `Jobs_P3`, run 9 batch).
- **REQ-136's notes** (unchanged). These hold. REQ-136 is the only rule for an OCE thrown by a cancel-requested job (`Jobs_CHK2`, `Chk_SingleRule`). Two clauses were re-read word by word this run:
  - "if it ignores the token it stays Processing until its timeout, if it has one": REQ-189 gives every job a timeout, so "if it has one" is always true. This is redundant, not wrong.
  - "If the handler … is released at shutdown, REQ-190 marks it cancelled instead of returning it to enqueued": REQ-140 never releases a cancel-requested job. The check cancels it instead (`ReleaseOnShutdown` branches on the request). The clause reads correctly as "where it would be released, it is cancelled instead", which REQ-190's run-4 note spells out.
- **REQ-138, REQ-186 and REQ-191's notes** (unchanged). These hold as in run 9. Every overlap of the throw rules gives one outcome (`Jobs_CHK6`). An abandonment is recorded in the step that abandons (`Prop_AbandonRecorded`, both holds cfgs), and the lease-lost handler of a job cancelled on recovery is reachable and recorded (`Jobs_SCN125`).

## Accepted (not reported as findings)

- **A cancellation requested after the node's check, ended by lease expiry** (run 9 F-1: `Jobs_AfterChk9_LA` after the stop, `LB` before it; run 7 F-1: `Jobs_GAP8`, `Chk_NoCancelLeftAtStop`). Both notes: "the node does not wait for it, and it ends as any cancel-requested job that is still processing does, … by lease expiry". REQ-190's lease branch applies with attempts left, REQ-133 at the last attempt. The notes no longer name either, so they cannot name the wrong one.
- **The handler's own outcome on a post-check request** (run 8 F-1: `Jobs_AfterChk_O`, `R`, `EC`, `ED`, `T`). Both notes: "by its handler's outcome". REQ-136, REQ-127, REQ-131 and REQ-190's exception and timeout branches are those outcomes.
- **REQ-186 counting a timed-out run after ShutdownTimeout, before the stop** (run 8 F-1: `Jobs_AfterChk_ST`). REQ-140's note puts the boundary at the node's stop ("if the node stops before REQ-138 or REQ-186 settles it"), and so does hosting REQ-29's.
- **A cancellation that arrives after a draining node stopped** (`Jobs_GAP7.cfg`, run 4's probe). It is a request after the check, so both notes cover it: with no handler left, it ends by lease expiry, REQ-133 at MaxAttempts = 1. Hosting REQ-29's earlier "as after a crash" is gone, and the new wording covers this case.
- **LIV-100** (`accepted-unprovable`): strict queue priority and job priority can still starve a job forever (`Jobs_Throttle_L1.cfg` and `Jobs_Throttle_L2.cfg`, lassos). It holds with one queue and equal priority (`L0`) and with a shared concurrency key (`L3`).
- **LIV-102** (`should`, `accepted-unprovable`): a continuation behind an Unroutable parent can still wait forever (`Jobs_Flow_F3.cfg`, lasso). `F1`, `F2`, `F4` and `F5` hold.
- **REQ-143 / run 2 F-6** (accepted in REQ-143's notes): requeuing a cancelled parent does not revive the continuations cancelled with it (`Jobs_Flow_GAP3.cfg`).
- **INV-106, former reading** (handlers executing, abandoned ones included): still violated (`Jobs_INV106.cfg`, `Chk_HandlersWithinLimit`), as the owner accepted in run 1.
- **INV-108/109, former reading** (state invariants): still violated after an operator lowers a limit (`Jobs_Throttle.cfg`, `Chk_KeyMaxState`). The claim-time wording holds (`Jobs_Throttle_Holds.cfg`, `Jobs_Throttle_HoldsK.cfg`).
- **Timed-out job at shutdown, recovered by lease expiry** (REQ-140 and hosting REQ-29 notes): when the node stops before REQ-138/186 settles it, the job comes back through REQ-132 with reason Interrupted and no backoff, rather than through REQ-138 with reason Timeout and retryAt. The attempt counts either way (`Jobs_P2.cfg`), and the notes accept it.
- **A late request whose lease expires before the check** (`Jobs_P5`, `Reach_LateLeaseExpiryFirst`, run 7): dead-lettered at the last attempt by REQ-133 while the draining node still holds the run (accepted race, REQ-190's notes).

## Runs

Rerun this run (the evidence for the changed notes):

| cfg | Result | Distinct states | s |
|---|---|---|---|
| `Jobs_GAP7` | violated, accepted path (13 states; request after the check, REQ-133 after the stop) | 35,872 | 1 |
| `Jobs_GAP8` (`Chk_NoCancelLeftAtStop`) | violated, accepted (10 states) | 12,250 | 1 |
| `Jobs_AfterChk_O` / `R` / `ED` (MaxAttempts = 1) | violated (reachable: REQ-136, REQ-127, REQ-131; accepted) | 11,559 / 12,316 / 12,503 | 1 |
| `Jobs_AfterChk_EC` (MaxAttempts = 2) | violated (reachable: REQ-190's exception branch; accepted) | 17,380 | 1 |
| `Jobs_AfterChk_T` (`Spec8`) | violated (reachable: REQ-190's timeout branch, 11 states; accepted) | 24,466 | 1 |
| `Jobs_AfterChk_ST` (`Spec8`) | violated (reachable: REQ-186 after ShutdownTimeout, before the stop, 8 states; accepted) | 2,855 | 1 |
| `Jobs_AfterChk_X` / `X1` (`Chk8_Exits`) | hold | 3,555,212 / 1,858,324 | 39 / 22 |
| `Jobs_AfterChk9_LA` (`Reach9_LeaseAfterStop`) | violated (reachable: REQ-190's lease branch after the stop, 12 states; accepted) | 60,348 | 1 |
| `Jobs_AfterChk9_LB` (`Reach9_LeaseBeforeStop`) | violated (reachable: lease expiry before the stop, 11 states; accepted) | 30,108 | 1 |

TLC reports a violated action property as an error, so the run log shows `error None` for the `Reach8_` and `Reach9_LeaseBeforeStop` cfgs. That is the expected result. The full-space runs (`X`, `X1`) match run 9's distinct-state counts exactly. The others stop at the first violation, so their counts and trace lengths differ slightly from run 9's, because the multi-worker search is nondeterministic.

Not rerun, unchanged since run 9's complete batch: `Jobs_Holds`, `Jobs_HoldsQ`, `Jobs_CHK`–`CHK6`, `Jobs_GAP1/2/5`, `Jobs_P2`–`P5`, `Jobs_INV106`, `Jobs_LIV101a/b`, `Jobs_LIV29`, every `Jobs_SCN*`, every `Jobs_Unique*`, `Jobs_Throttle*` and `Jobs_Flow*` cfg. Their results and state counts are in run 9's report (`specs/model/jobs/previous.findings.md`, *Runs*). `Jobs.cfg` and `Jobs_LIV101.cfg` (all checks at once) still run split, and `Jobs_GAP6` is still not run (it holds by construction since run 4).

**Timeouts and exceptions.** None in the 12 runs.

## Modeling assumptions

These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. None changed in run 10.

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

**Scenario results.** Unchanged from run 9, which ran them all. Every positive scenario is reachable (trap violated, as expected): SCN-100, 101, 102, 105, 108, 111, 112, 114, 115, 118, 119, 121, 122 and 125. Every negative scenario holds over the complete bounded state space: SCN-103, 104, 107, 110, 117 and 124 (`Jobs_Holds.cfg`, `Jobs_HoldsQ.cfg`, `Jobs_SCN124.cfg`), SCN-106 (`Jobs_Throttle_Holds/HoldsK.cfg`), SCN-120 (`Jobs_SCN120.cfg`), and SCN-109 and SCN-123 (the flow holds runs). SCN-113 is still skipped.

**Same-trigger warnings from `validate`** (0 errors, the same 4 warnings). REQ-127/128/184, REQ-129/131 and REQ-132/133 are modeled as one action each, and REQ-171/174 inside one resolution step. REQ-140's still-running branch and REQ-190's shutdown branch are one action by design: two outcomes of one check. REQ-190's lease branch is the third outcome of the REQ-132/133 action (`Recover`).

**Cross-module.** Nothing needs fixing. All three optional wording edits under *Also checked* touch **hosting.json** (REQ-29's notes: the "these notes" scope, the run label and the run-1 citation). The "these notes" edit also touches jobs REQ-190. None of them changes behaviour. Under hosting REQ-29 a draining node always stops (`Liv_DrainEnds`, `Jobs_LIV29.cfg`, run 9 batch).

## Next

Nothing has to be changed. If the owner wants the optional wording edits under *Also checked*, apply them with the `refiner-requirements` skill. Notes are not in the spec hash, so a notes-only edit needs only the rerun subset above, not the full batch.
