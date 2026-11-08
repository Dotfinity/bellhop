# Findings: Bellhop job lifecycle

<!-- refiner-findings v1 | module: jobs | specHash: d1c4f5af9f87339150943337d04b6b0e155d916eaf43724355ad60b513bb826c | run: 2026-11-08 | previous: specs/model/jobs/previous.findings.md (run 8, specHash d1c4f5af9f87) -->

**Run:** 2026-11-08 (run 9, no handoff: commit 24b1e08 changed notes only) · **Requirements file:** `specs/jobs.json` (specHash `d1c4f5af9f87`, unchanged) · **Model:** `model/jobs/Jobs.tla`, `Jobs_Unique.tla`, `Jobs_Throttle.tla`, `Jobs_Flow.tla`, the run-8 probe modules `Jobs_AfterChk.tla` and `Jobs_AfterChkG.tla`, plus the new probe module `Jobs_AfterChk9.tla` · **TLC:** 2.19. The full batch ran with `TLC_WORKERS=4 TLC_TIMEOUT=400 sh run_all.sh`, every check alone with `--stop-at-first`, while two other modules were being checked on the same machine. All 79 runs finished, with no timeouts and no TLC exceptions. The largest runs were 7,433,296 distinct states in 174 s (`Jobs_HoldsQ.cfg`) and 3,555,212 in 40–72 s (`Jobs_Holds.cfg`, the CHK, GAP, `Jobs_SCN124` and `Jobs_AfterChk_X` runs).
**Result:** 1 finding: 0 contradictions · 0 gaps · 1 ambiguity · 0 unprovable · 0 modeling notes. Run 8's F-1 is resolved: the notes now name the node's stop as the boundary and defer to the job's rules, and every run-8 trace is covered by them (see *Accepted*).

No requirement was regenerated. `Jobs.tla`, `Jobs_Unique.tla`, `Jobs_Throttle.tla`, `Jobs_Flow.tla`, `Jobs_AfterChk.tla`, `Jobs_AfterChkG.tla` and all their cfgs are byte-for-byte as in run 8. Commit 24b1e08 changed three notes: jobs REQ-190's last part, one clause of jobs REQ-140's, and two sentences of hosting REQ-29's. This run checks those notes against the model and the run-8 probes. It also re-reads the rest of the REQ-136, REQ-138, REQ-140, REQ-186, REQ-190 and REQ-191 notes and hosting REQ-29's notes.

| File | Covers |
|---|---|
| `Jobs.tla` | execution, leases, recovery, retries, timeouts, shutdown, cancellation (REQ-190, REQ-191), requeue, delete, retention, queue pause, maintenance and routing |
| `Jobs_Unique.tla` | unique keys (FEAT-103) on every creating call, and the unique-key side of single and bulk requeue |
| `Jobs_Throttle.tla` | claim order, concurrency keys, rate limits, queue limits, the LongRunning limit, LIV-100 (FEAT-104) |
| `Jobs_Flow.tla` | continuations, chains and batches (FEAT-106), including INV-138, batch-member retention and batch removal (REQ-192) |
| `Jobs_AfterChk.tla`, `Jobs_AfterChkG.tla` | *(run 8 probes)* `EXTENDS Jobs`. What can settle a run whose cancellation was requested after its draining node's check, and a timed-out run after ShutdownTimeout |
| `Jobs_AfterChk9.tla` | *(new, probes only)* `EXTENDS Jobs_AfterChk`. Which lease-expiry rule decides a post-check cancellation, after the stop and before it. It adds no action and changes no guard |

What is new:

- **`Jobs_AfterChk9.tla`.** Two properties, each expected to be violated (= reachable), both at MaxAttempts = 2 so that the job has attempts left. `Reach9_LeaseAfterStop` (state invariant, `Jobs_AfterChk9_LA.cfg`) says no job left in flight at its node's stop with a post-check request (`DrainLeftCancel`) is later cancelled by lease expiry (`LeaseCancel`) with attempts left. `Reach9_LeaseBeforeStop` (action property, `Jobs_AfterChk9_LB.cfg`) says no running worker node recovers such a run's expired lease while its draining node still holds it.
- `run_all.sh` runs the two new cfgs after the run-8 probes. TLC reports a violated action property as an error, so `run_all.log` shows `error None` for `Jobs_AfterChk9_LB`, as for the six `Reach8_` cfgs. That is the expected result.

To reproduce, run `TLC_WORKERS=4 TLC_TIMEOUT=400 sh run_all.sh` from `specs/model/jobs`.

## Changes since last run

| Finding | Status |
|---|---|
| F-1 (run 8) | resolved. REQ-190's and hosting REQ-29's notes now say the job's ordinary rules decide a request after the check: the handler's own outcome until the node stops, lease expiry after it. REQ-140's note and hosting REQ-29's run-3 sentence put the boundary at the node's stop instead of ShutdownTimeout. Each run-8 probe trace is one of those outcomes, and `Chk8_Exits` still holds. Moved to *Accepted* |
| F-1 | new: the notes' pointer for "lease expiry after it" names REQ-132, which never applies to a job whose cancellation was requested. With attempts left the rule is REQ-190's own lease branch, and the job is Cancelled, not returned to Enqueued |

`findings_delta.py specs/model/jobs/previous.findings.md specs/jobs.findings.md`:

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | ambiguity · Chk8_Exits · REQ-136,REQ-140,REQ-190,hosting.REQ-29 |
| F-1 | new | ambiguity · Reach9_LeaseAfterStop · REQ-132,REQ-133,REQ-190,hosting.REQ-29 |

1 resolved, 1 new, 0 still open. (The "resolved" row uses run 8's number.)

## Summary

| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | ambiguity | low | REQ-190, REQ-132, REQ-133, hosting REQ-29 | For a cancellation requested after the check, REQ-190's and hosting REQ-29's notes say lease expiry decides after the stop and cite "(REQ-132, REQ-133)". REQ-132's while needs "its cancellation was not requested", so it never applies to that job. With attempts left the rule that applies is REQ-190's lease branch (Cancelled), which the note in REQ-190 itself does not name |

---

## F-1 · ambiguity · low — The notes cite REQ-132 for lease expiry of a job whose cancellation was requested
<!-- finding: ambiguity | Reach9_LeaseAfterStop | REQ-190,REQ-132,REQ-133,hosting.REQ-29 -->

**Requirements involved**
- REQ-190 notes (run 8 F-1, new): *"A request made after that check is not part of the shutdown. Only a timed-out handler still in its grace period can be in flight then, because the check released or cancelled every other one; the node does not wait for it, and the job's ordinary rules decide, the handler's own outcome until the node stops and **lease expiry (REQ-132, REQ-133) after it**."*
- hosting REQ-29 notes (run 8 F-1, new): *"… the job's ordinary rules decide, the handler's own outcome until the node stops and **lease expiry (jobs REQ-132, REQ-133) after it**, as after a crash."* Run 7's wording here had said *"(cancelled with attempts left, dead-lettered at the last attempt)"*. That parenthesis is gone.
- REQ-132: *While a job is processing **and its cancellation was not requested**, when its leaseExpiresAt has passed according to the database clock, if the attempt number is below maxAttempts, the system shall let any running worker node return the job to enqueued with reason Interrupted, keeping the attempt counted.* Notes: *"a job whose cancellation was requested is marked cancelled instead (REQ-190)."*
- REQ-190: *While a job is processing and its cancellation was requested, when **its lease expires with attempts left**, … the system shall … mark the job cancelled instead of returning it to enqueued …*
- REQ-133: *While a job is processing, when its leaseExpiresAt has passed …, if the attempt number has reached maxAttempts, the system shall let any running worker node move the job to dead-lettered with reason Interrupted.*

**What happens** (`Jobs_AfterChk9_LA.cfg`: `Reach9_LeaseAfterStop` is violated, a 12-state trace at MaxAttempts = 2.)
1. j1 is enqueued and node n1 claims it at attempt 1 of 2 (REQ-120, REQ-123).
2. j1's lease passes its expiry without a renewal reaching the store (A-2). No node recovers it yet. The order does not matter: the lease would also expire after step 8, once n1's heartbeats stop.
3. j1 runs past its timeout, so its timeout token is signalled (REQ-137). TimeoutGracePeriod starts (REQ-187).
4. The host stops n1, so n1 drains (hosting REQ-27). ShutdownTimeout passes.
5. n1 cancels j1's token for shutdown (REQ-139).
6. n1 makes its check and finds the handler still running with its timeout token signalled and no cancellation requested. Neither REQ-140 nor REQ-190's shutdown branch applies, so j1 stays on its timeout path.
7. **An operator cancels j1** (REQ-135). This is the request "made after that check".
8. n1 stops (hosting REQ-29). The run was checked, so the node does not wait for it. j1 is still Processing, with n1's lease.
9. Node n2, running, recovers the expired lease. The attempt number (1) is below maxAttempts (2) and the cancellation was requested, so **REQ-190's lease branch marks j1 Cancelled**. REQ-132 does not apply: its while needs "its cancellation was not requested".

So the note's pointer is wrong for this case. A reader who follows "(REQ-132, REQ-133)" to REQ-132 reads that the job returns to Enqueued with reason Interrupted and runs again. That is the outcome F-7 (REQ-190's purpose: "a cancelled job does not run again") rules out. REQ-132's own note redirects to REQ-190, so a careful reader gets there in the end. But the note that gives the wrong pointer is REQ-190's, and its own lease branch is the rule that applies. At the last attempt REQ-133 applies and dead-letters j1, which is the run-7 path (`Jobs_GAP8`, MaxAttempts = 1). For a job whose cancellation was not requested, REQ-132 is right, but the sentence is only about a job whose cancellation was requested.

The model follows the sentences. `Recover` is the one lease-expiry action, with the three complementary guards, and it takes REQ-190's branch whenever the request is recorded and attempts are left. So a post-check request never comes back as Interrupted. That follows from the guards themselves, and no property is needed to show it.

**Why.** Commit 24b1e08 replaced the lists of outcomes with a pointer to the rules, so that the notes cannot fall out of step with the rules again. For lease expiry the pointer names the rules for a job *without* a request (REQ-132/133), which is what REQ-140's note and hosting REQ-29's run-3 sentence describe. The job in this sentence always has a request, and lease expiry has three rules with complementary guards: REQ-132 (no request, attempts left), REQ-190's lease branch (request, attempts left) and REQ-133 (last attempt). Only the last two can apply here. No requirement is wrong and behaviour does not change. The notes are not normative, so the severity is low.

**Options**
1. *(recommended)* **Point to the two rules that can apply.** In REQ-190's note, "lease expiry (this requirement's lease branch, or REQ-133 at the last attempt)". In hosting REQ-29's note, "(jobs REQ-190's lease branch, or REQ-133 at the last attempt)". It is still a pointer to rules, not a list of outcomes, so it keeps 24b1e08's intent. The fix is in jobs REQ-190 and in **hosting.json** (REQ-29, another module).
2. **Point to the whole event.** Write "lease expiry (REQ-132, REQ-133, REQ-190)" and let the guards pick. Nothing has to be redone if the guards change later, but the pointer names one rule that cannot apply here.
3. **Accept as is.** REQ-132's notes already redirect to REQ-190. The pointer in REQ-190's own notes stays wrong for the attempts-left case.

**Ready to apply (option 1)**

In `specs/jobs.json`, REQ-190 `notes`: replace "and lease expiry (REQ-132, REQ-133) after it." with
```json
{ "id": "REQ-190", "notes": "… the job's ordinary rules decide, the handler's own outcome until the node stops and lease expiry after it (this requirement's lease branch, or REQ-133 at the last attempt; REQ-132 excludes a requested cancellation). Run 7 and run 8 F-1: … Run 9 F-1: the lease-expiry pointer named REQ-132, which never applies to a cancel-requested job." }
```
In `specs/hosting.json`, REQ-29 `notes`: replace "and lease expiry (jobs REQ-132, REQ-133) after it, as after a crash." with
```json
{ "id": "REQ-29", "notes": "… the job's ordinary rules decide, the handler's own outcome until the node stops and lease expiry (jobs REQ-190's lease branch, or REQ-133 at the last attempt) after it, as after a crash." }
```
Leave REQ-140's note and hosting REQ-29's run-3 sentence ("Only a handler that jobs REQ-138 or REQ-186 has not settled when the node stops is left to lease expiry, and its attempt counts (jobs REQ-132, REQ-133)") as they are. They are about a timed-out job with no request, and for that job REQ-132/133 is right.

---

## Also checked (not findings)

- **"A request made after that check is not part of the shutdown. Only a timed-out handler still in its grace period can be in flight then, because the check released or cancelled every other one"** (REQ-190; hosting REQ-29 the same without the "because"). This holds as in run 8. Only `ShutdownCheckLeaves` sets `chk`, it needs the timeout signal, and `ReleaseOnShutdown` takes every other checked run out of flight. A draining node claims nothing (REQ-123 needs a running node). The run-8 modeling artefact (grace passing and abandonment are two steps, A-1) is unchanged and not reported.
- **"The node does not wait for it"** (both notes). This holds. `NodeStop` needs only that every in-flight run was checked (`Jobs_GAP8`), and `Liv_DrainEnds` holds (`Jobs_LIV29.cfg`).
- **"The handler's own outcome until the node stops"** (both notes). Every run-8 probe trace is such an outcome: REQ-136 (`Jobs_AfterChk_O`), REQ-127 (`R`), REQ-190's exception branch (`EC`), REQ-131 (`ED`) and REQ-190's timeout branch (`T`). `Chk8_Exits` still holds at MaxAttempts 2 and 1 (`X`, `X1`). These are now in *Accepted*.
- **Lease expiry before the node stops** (`Jobs_AfterChk9_LB.cfg`, `Reach9_LeaseBeforeStop` violated, an 11-state trace). It has the same prefix as F-1's steps 1–7. Then n2 recovers the expired lease while n1 is still draining, and REQ-190's lease branch marks j1 Cancelled before n1 stops. Read narrowly, this is neither "the handler's own outcome" nor "lease expiry after it". It is not reported, for three reasons. The operative clause is "the job's ordinary rules decide", and REQ-190's lease branch is one of them. REQ-136's notes count "loses its lease" among the ways a cancel-requested handler's job ends. And losing a lease while the node is alive (REQ-191's notes: "a partition or long pause, then recovery by another node") applies to every running handler, not only in this window; no handler-outcome note in the module repeats it. `Chk8_Exits` has listed this exit since run 8. If the owner wants the gloss exact, F-1's edit could read "the handler's own outcome or a lost lease until the node stops". That is optional.
- **REQ-140's new clause** ("if the node stops before REQ-138 or REQ-186 settles it, lease expiry counts the attempt (REQ-132, REQ-133)"). This holds. `Reach8_TimeoutAfterShutdownTimeout` (`Jobs_AfterChk_ST`, 9 states) is REQ-186 settling the job after ShutdownTimeout and before the stop, which the clause now allows. `Jobs_P2` is the node stopping first, with lease expiry counting the attempt (Interrupted). The citation is right here: the sentence is about a timeout with no request, so REQ-132/133 are the rules. A request after the check moves the job to REQ-190's note (F-1).
- **Hosting REQ-29's run-3 sentence** ("Only a handler that jobs REQ-138 or REQ-186 has not settled when the node stops is left to lease expiry, and its attempt counts"). This holds as a necessary condition. `NodeStop` needs every in-flight run checked, and only a timed-out run is checked and left in flight, so every run left at the stop is a timed-out one that REQ-138/186 (or, with a later request, REQ-190's timeout branch) has not settled. A release that fails because the store is down is the note's earlier best-effort sentence. Store outages are not modeled (A-3).
- **Rest of the REQ-136, REQ-138, REQ-186, REQ-190 and REQ-191 notes** (unchanged since run 8). They hold as in run 8. REQ-136 is the only rule for an OCE of a cancel-requested job (`Jobs_CHK2`, `Chk_SingleRule`). Every overlap of the throw rules gives one outcome (`Jobs_CHK6`). Abandonment is recorded (`Prop_AbandonRecorded`, both holds cfgs), and a request before the check is read by it (`Prop_LateCancelNotLeft`; `Reach_LateCancelled` reachable, `Jobs_P4`). REQ-140's run-6 note and the "lease is released as soon as ShutdownTimeout passes" sentence are read at the check after the token is cancelled (A-19), as since run 6.

## Accepted (not reported as findings)

- **The handler's own outcome on a post-check request, before the node stops** (run 8 F-1: `Jobs_AfterChk_O`, `R`, `EC`, `ED`, `T`). REQ-190's and hosting REQ-29's notes now say "the job's ordinary rules decide, the handler's own outcome until the node stops". REQ-136, REQ-127, REQ-131 and REQ-190's exception and timeout branches are those rules.
- **REQ-186 counting a timed-out run after ShutdownTimeout, before the stop** (run 8 F-1: `Jobs_AfterChk_ST`). REQ-140's note now puts the boundary at the node's stop ("if the node stops before REQ-138 or REQ-186 settles it"), and so does hosting REQ-29's ("a handler that jobs REQ-138 or REQ-186 has not settled when the node stops").
- **A cancellation after the node's check, on a timed-out handler, left to lease expiry** (run 7 F-1, `Jobs_GAP8.cfg`, `Chk_NoCancelLeftAtStop`). Both notes: "the node does not wait for it, and … lease expiry … after it". At MaxAttempts = 1 that is REQ-133, dead-lettered. Which rule decides it with attempts left is F-1.
- **Cancellation that arrives after a draining node stopped** (`Jobs_GAP7.cfg`, run 4's probe). The lease-expiry outcome is the same as after a crash, which hosting REQ-29's note now says in so many words.
- **LIV-100** (`accepted-unprovable`): strict queue priority and job priority can still starve a job forever (`Jobs_Throttle_L1.cfg` and `Jobs_Throttle_L2.cfg`, lassos). It holds with one queue and equal priority (`L0`) and with a shared concurrency key (`L3`).
- **LIV-102** (`should`, `accepted-unprovable`): a continuation behind an Unroutable parent can still wait forever (`Jobs_Flow_F3.cfg`, lasso). `F1`, `F2`, `F4` and `F5` hold.
- **REQ-143 / run 2 F-6** (accepted in REQ-143's notes): requeuing a cancelled parent does not revive the continuations cancelled with it (`Jobs_Flow_GAP3.cfg`).
- **INV-106, former reading** (handlers executing, abandoned ones included): still violated (`Jobs_INV106.cfg`, `Chk_HandlersWithinLimit`), as the owner accepted in run 1.
- **INV-108/109, former reading** (state invariants): still violated after an operator lowers a limit (`Jobs_Throttle.cfg`, `Chk_KeyMaxState`). The claim-time wording holds (`Jobs_Throttle_Holds.cfg`, `Jobs_Throttle_HoldsK.cfg`).
- **Timed-out job at shutdown, recovered by lease expiry** (REQ-140 and hosting REQ-29 notes): when the node stops before REQ-138/186 settles it, the job comes back through REQ-132 with reason Interrupted and no backoff, rather than through REQ-138 with reason Timeout and retryAt. The attempt counts either way (`Jobs_P2.cfg`), and the notes accept it.
- **A late request whose lease expires before the check** (`Jobs_P5`, `Reach_LateLeaseExpiryFirst`, run 7): dead-lettered at the last attempt by REQ-133 while the draining node still holds the run (accepted race, REQ-190's notes).

## Runs

| cfg | Result | Distinct states | s |
|---|---|---|---|
| `Jobs_Holds` | holds | 3,555,212 | 72 |
| `Jobs_HoldsQ` (MaxAttempts = 1) | holds | 7,433,296 | 174 |
| `Jobs_CHK` / `CHK3` / `CHK4` / `CHK5` | hold | 3,555,212 each | 42–43 |
| `Jobs_CHK2` (`Chk_SingleRule`) | holds | 3,555,212 | 44 |
| `Jobs_CHK6` (`Chk_SingleOutcome`) | holds | 3,555,212 | 42 |
| `Jobs_GAP1` / `GAP2` / `GAP5` | hold | 3,555,212 each | 41–42 |
| `Jobs_GAP6` | not run: holds by construction since run 4; the full two-slot space does not finish in time | – | – |
| `Jobs_GAP7` | violated, accepted path | 35,620 | 1 |
| `Jobs_GAP8` (`Chk_NoCancelLeftAtStop`) | violated, accepted (run 7 F-1 path, 10 states) | 13,034 | 1 |
| `Jobs_P2` | violated (reachable, accepted path) | 28,864 | 1 |
| `Jobs_P3` (`Reach_ShutdownCancelled`) | violated (reachable, as expected) | 2,709 | 1 |
| `Jobs_P4` (`Reach_LateCancelled`) | violated (reachable, as expected, 9 states) | 3,464 | 1 |
| `Jobs_P5` (`Reach_LateLeaseExpiryFirst`) | violated (reachable, accepted race, 9 states) | 4,992 | 1 |
| `Jobs_INV106` | violated (accepted) | 580 | 1 |
| `Jobs_LIV101a` / `LIV101b` | hold | 87,496 / 664,576 | 5 / 38 |
| `Jobs_LIV29` (`Liv_DrainEnds`, hosting REQ-29) | holds | 87,496 | 10 |
| `Jobs_SCN100/101/102/111/112/115/122/124s/125` | traps violated (reachable, as expected) | 134–10,447 | 1 |
| `Jobs_SCN120` / `Jobs_SCN124` | hold | 1,433,536 / 3,555,212 | 14 / 40 |
| `Jobs_AfterChk_O` / `R` / `ED` (MaxAttempts = 1) | violated (reachable: REQ-136, REQ-127, REQ-131; accepted) | 11,782 / 12,104 / 12,713 | 1 |
| `Jobs_AfterChk_EC` (MaxAttempts = 2) | violated (reachable: REQ-190's exception branch; accepted) | 17,244 | 1 |
| `Jobs_AfterChk_T` (`Spec8`) | violated (reachable: REQ-190's timeout branch; accepted) | 22,653 | 2 |
| `Jobs_AfterChk_ST` (`Spec8`) | violated (reachable: REQ-186 after ShutdownTimeout, before the stop; accepted) | 2,982 | 1 |
| `Jobs_AfterChk_X` / `X1` (`Chk8_Exits`) | hold | 3,555,212 / 1,858,324 | 43 / 24 |
| `Jobs_AfterChk9_LA` (new, `Reach9_LeaseAfterStop`) | violated (reachable: REQ-190's lease branch after the stop, 12 states; F-1) | 58,197 | 2 |
| `Jobs_AfterChk9_LB` (new, `Reach9_LeaseBeforeStop`) | violated (reachable: lease expiry before the stop, 11 states; not reported) | 31,735 | 2 |
| `Jobs_Unique`, `U1`–`U5` / `SCN105` (unchanged) | hold / trap violated | 3,220–7,794 / 51 | 1 |
| `Jobs_Throttle_*` (unchanged) | Holds, HoldsK, T0, T2, T3, L0, L3 hold; L1 and L2 (lassos) and `Jobs_Throttle` violated, accepted | ≤ 1,692 | 1 |
| `Jobs_Flow_Holds` / `HoldsC` / `HoldsU` (unchanged) | hold | 1,407,799 / 652,237 / 259,033 | 16 / 8 / 4 |
| `Jobs_Flow_P1b` | holds | 3,936,009 | 37 |
| `Jobs_Flow_F1` / `F2` / `F4` / `F5` | hold | 206,420 / 207,248 / 205,289 / 206,420 | 11–18 |
| `Jobs_Flow_F3` | violated (accepted, LIV-102) | 72,998 | 4 |
| `Jobs_Flow_GAP3b` / `GAP4` | hold | 1,388,164 / 1,396,162 | 8 / 11 |
| `Jobs_Flow_GAP3` / `GAP5` / `GAP6` | violated (accepted / allowed / accepted) | 120,358 / 389 / 3,180 | 1 |
| `Jobs_Flow_P1` | violated (the required case since run 4) | 459,606 | 3 |
| `Jobs_Flow_SCN108/114/118/119/121` | traps violated (reachable, as expected) | 182–286,556 | 1–2 |

**Timeouts and exceptions.** No run hit the limit and no run had a TLC exception. `Jobs.cfg` and `Jobs_LIV101.cfg` (all checks at once) still run split, as in runs 3 to 8, and `Jobs_GAP6` is still not run. The distinct-state counts match run 8 wherever a run explores the whole bounded space. They differ only where TLC stops at the first violation, because the multi-worker search is nondeterministic there. For the same reason some run-8 probe traces are one state shorter or longer than in run 8 (`EC` 10, `T` 11, `ST` 9).

## Modeling assumptions

These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. None changed in run 9. A-13's MaxAttempts = 2 list now includes `Jobs_AfterChk9_LA/LB`, which use the default.

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

**Scenario results.** Unchanged from run 8. Every positive scenario is reachable (trap violated, as expected): SCN-100, 101, 102, 105, 108, 111, 112, 114, 115, 118, 119, 121, 122 and 125. Every negative scenario holds over the complete bounded state space: SCN-103, 104, 107, 110, 117 and 124 (`Jobs_Holds.cfg`, `Jobs_HoldsQ.cfg`, `Jobs_SCN124.cfg`), SCN-106 (`Jobs_Throttle_Holds/HoldsK.cfg`), SCN-120 (`Jobs_SCN120.cfg`), and SCN-109 and SCN-123 (the flow holds runs). SCN-113 is still skipped.

**Same-trigger warnings from `validate`.** REQ-127/128/184, REQ-129/131 and REQ-132/133 are modeled as one action each, and REQ-171/174 inside one resolution step. REQ-140's still-running branch and REQ-190's shutdown branch are one action by design: two outcomes of one check. REQ-190's lease branch is the third outcome of the REQ-132/133 action (`Recover`), which is where F-1's trace ends.

**Cross-module.** Half of F-1's fix is a note in **hosting.json** (REQ-29); the other half is in jobs REQ-190. Neither changes behaviour. Under hosting REQ-29 a draining node always stops (`Liv_DrainEnds`, `Jobs_LIV29.cfg`).

## Next

Apply the chosen option (F-1: REQ-190's notes in `specs/jobs.json`, REQ-29's notes in `specs/hosting.json`) with the `refiner-requirements` skill (it validates and diffs), then run this skill again. Findings whose fingerprint disappears are listed as resolved in the next report.
