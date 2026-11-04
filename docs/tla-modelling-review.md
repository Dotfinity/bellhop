# Review: the TLA+ modelling of Bellhop M1

Date: 2026-11-04. Scope: everything under `refinement/` (requirements, decisions D-1 to D-19, both iterations' models, rules, traces and check results), and how its output reaches `docs/bellhop-architecture.md` and `stories/m1-core/`. There is no code yet, so "implementation" here means how the modelling feeds the documents that code will be built from.

What I did: read every iteration-2 model, rules file and check result, the decision log and the refined requirements; compared them with the architecture and the stories; and re-ran TLC 2.19 on modified copies of F2 and F4 outside the repo to test four claims (Appendix A). Nothing under `refinement/` was changed.

## Summary

1. **The modelling's results haven't reached the documents anyone will build from.** Nine decisions are marked resolved, but they changed only `refinement/requirements.md`. The stories and the architecture still describe the old behaviour that the models showed was broken. This blocks implementation.
2. **Self-fencing (D-1, D-7) passes with zero margin.** With the chosen design, a node gives up at the exact instant its lease runs out. One tick of clock skew or delay breaks `NoDoubleRun` (confirmed). A precise fencing timer gives back a real margin (confirmed).
3. **The D-9 fix has a hole.** If a node crashes during a rolling deploy, a job the new version removed is never orphaned, because the crashed node still counts as live when the last node reconciles (confirmed, 6 steps). The model treats a crashed node as gone immediately, so it couldn't see this.
4. **The models only read the stories, so the findings are off in both directions.** One half of D-6 is already prevented by the architecture's `Complete` fence. The architecture's `Renew` fence, which the models never read, still has the other half.
5. The modelling itself is careful and honest: requirements are traced to source lines, every action fired at least once, fixes were checked by putting the old behaviour back, and each result says what a pass doesn't prove. The weak spots are a few contradictory assumptions between models, thin liveness coverage, and no way to re-run the checks.

## What works well

- **Traceability.** Every action and rule cites the REQ it comes from, every REQ cites the story criterion, and every change carries a dated history line. This makes the gaps below easy to find.
- **Vacuity checks.** `neverFired` in each check result and "every step happened at least once" guard against rules that pass because nothing can happen. F2 reports honestly that `RenewToldLost` never fires.
- **Fixes checked both ways.** Each iteration-2 fix was re-run with the old behaviour put back (`attempts/*/mutants`, `probe/*`), and the problem came back. That is what separates "the fix works" from "the model changed".
- **Honest limits.** Each results file has a "what a passed rule means here" section, transcription errors are owned rather than raised as problems (REQ-021, REQ-025), and the weakest passes are named.
- **Decisions are actionable.** Each decision has a concrete scenario, numbered steps and wording to drop into a requirement. Owners can answer them without reading TLA+.

## Findings

### 1. The decisions haven't reached the stories or the architecture (blocker)

`refinement/requirements.md` is a restatement of the stories. Changing it changes no source document. Grepping the stories and the architecture for each resolved decision:

| Decision | Still says the old thing | Must change |
|---|---|---|
| D-3 Unroutable is active | M1-06 Overlap section: "Active means Scheduled, Enqueued, Processing, Failed or Awaiting"; arch §5.3 `TickAsync` step 4 | M1-06, M1-15, arch §7.7 and §5.3 |
| D-4 requeue warns | M1-05 requeue criterion; nothing can carry the warning (the store's `RequeueAsync` returns `bool`, and M1-24 has no requeue action) | M1-05, M1-09/M1-11, and a decision on where the warning goes (return type, log event, dashboard) |
| D-5 cancel wins over shutdown release | M1-07 `ShutdownNodeAsync` and M1-12 shutdown criteria: released jobs go to `Enqueued`; arch §5.3 `ShutdownNodeAsync` | M1-07, M1-12, arch §5.3, §7.5 |
| D-6 recovery retires the token | arch §4.4 `Renew` is fenced on `(id, lease_token)` only; `ShutdownNodeAsync` has no fence stated | arch §4.4, §5.3; M1-05, M1-07 conformance criteria |
| D-7 fence at 2/3 from send time | M1-12: "throws for longer than `LeaseDuration`"; arch §7.2: "bounds the duplicate window to the lease length" | M1-12, arch §7.2 (see finding 2 first) |
| D-8 renew before each batch | M1-13 cleanup criteria; arch §7.4 | M1-13, arch §7.4 (see finding 7) |
| D-9 orphan only when no live node defines it | M1-06: "`svc1` reconciles with only A, then B is orphaned" | M1-06, M1-14, arch §4.4 reconcile; nodes must also advertise their recurring names, a new heartbeat field (M1-07, M1-21 schema, `TickRequest`) |
| D-10 code-defined: pause and resume only | M1-06 runtime-edit criteria; M1-25 recurring page | M1-06, M1-14, M1-25 |
| D-11 manual trigger works when paused | M1-06, M1-14 | M1-06, M1-14, M1-25 |
| D-12 silent node counts as gone | M1-07 routing criterion | M1-07 (wording only) |

Until this is done, an agent running `deliver-story` on M1-06 or M1-12 will build exactly the behaviour the models rejected. D-9 is a contract change (node heartbeat payload and schema), so it also needs a note in arch §5.

**Recommendation:** make one docs commit per decision, or a single commit if you prefer, that edits the story and the architecture section and cites the D-number. Then add a "Propagated to" line to each decision in `decisions.md`, so the log shows whether a decision has landed, not only whether it was decided.

### 2. Self-fencing passes with zero margin (D-1, D-7)

F2 holds only because of a discrete tie. With the chosen design, the node checks whether to give up once per renewal interval and gives up after two thirds of the lease. In the worst case it gives up at `lastOk + 2/3 + 1/3 = lastOk + lease`, which is the store's expiry instant. Recovery requires `now > expiry` strictly. `results.md` already admits "zero margin", but `requirements.md` REQ-015's history says the opposite: "leaves one renewal interval before another node may recover the job". Those two statements contradict each other, and the owner delegated this decision on the strength of the second.

Re-running F2 (Appendix A, runs 1 to 4):

| Fencing check | Recovery allowed from | `NoDoubleRun` |
|---|---|---|
| once per renewal interval (as decided) | `expiry` (a tick of skew or delay) | **violated**, 11 steps |
| precise timer at 2/3 lease | `expiry` | holds |
| precise timer at 2/3 lease | `expiry - 1` (1/6 lease early) | holds |
| precise timer at 2/3 lease | `expiry - 2` (1/3 lease early) | violated (tie) |

So a deadline timer that fires at exactly `lastSuccessfulSendTime + 2/3 × LeaseDuration` tolerates just under one renewal interval of clock skew plus pause (about 20 s with the default 60 s lease). Checking once per interval tolerates none. Lowering the fraction to one third with a once-per-interval check doesn't work either: the node then gives up at every routine renewal (`HealthyNeverRecovered` breaks, run 3).

**Recommendation:** amend REQ-015 and M1-12 to require a deadline timer (re-armed on each successful renewal, using the send time) rather than a periodic check. State the tolerated skew plus pause budget, and tie the clock-skew warning in M1-13 to that budget. Fix the contradictory history line in REQ-015.

### 3. "No overlap at all" (D-1) can't be guaranteed by leases alone

Even with finding 2 fixed, F2 holds only under assumptions the real system can't promise: clocks agree within the margin, the process is never paused for longer than the margin (GC, VM freeze, thread-pool starvation), and a cancelled handler stops at once. D-7's note and the iteration-2 assumptions already say a handler that ignores cancellation breaks it. F3's `NoOverlap` builds on the same assumption ("D-1 means the old handler has stopped before recovery"), so it inherits the caveat.

**Recommendation:** reword REQ-015 as a bounded guarantee: no overlap while skew plus pause stays within the margin and handlers honour cancellation. Tell handler authors that side effects must still be idempotent. A cheap, useful addition would be to expose the lease token on `JobContext`, so a handler can pass it downstream as a fencing token.

### 4. A crash during a rolling deploy leaves a removed job unorphaned (new)

F4 assumes "a live node is a running node; a stopped node stops counting at once". In Bellhop, liveness is "heartbeat within the node timeout" (D-2, 5 minutes), node ids are unique per process start (arch §4.5), and only a graceful shutdown deletes the node row (`ShutdownNodeAsync`). Reconcile runs only at node start (REQ-034).

I added a crashed node whose row stays live until it ages out (Appendix A, run 5). The rule "once every node runs the new code and no crashed node still counts, the job only the old code defined is orphaned" breaks in 6 steps:

1. n1 stops gracefully and starts on the new version. n2 (old) is live, so `d2` is kept, which is correct.
2. n2 crashes. Its row still counts as live.
3. n2 starts on the new version. The crashed old row still advertises `d2`, so `d2` is kept.
4. The old row ages out. Every node now runs the new version, and nothing will reconcile again until the next start, so `d2` stays active, possibly for weeks.

Then `d2` keeps firing. If its handler was removed too, its runs go `Unroutable`, which since D-3 counts as active and blocks later fires. Without crashes the same model holds (run 6, same 24,408 distinct states as the original, so the variant is faithful).

**Recommendation:** add an orphan sweep that doesn't depend on a node starting. For example, cleanup (already single-leader) orphans code-defined definitions that no live node advertises. Alternatively, re-run the orphan step on every tick of the leader. Add a convergence rule like the one above to F4: rolling deploys are where this design's bugs live (D-9, D-19, this one), and F4 currently has no "eventually settles" rule at all.

### 5. Reading only the stories missed things in both directions

The requirements say: "Where a story points to the architecture ... that text was not used to fill gaps." That tests whether the stories are self-sufficient, which is useful. But the architecture is the contract the stories defer to, so:

- **D-6 is half solved already.** Arch §4.4 fences `Complete` on `state='Processing' AND lease_token=@token`, so the iteration-1 scenario (recover, cancel, stale complete overwrites `Cancelled`) can't happen against the architecture. The story (M1-05) just didn't say so.
- **The other half is real in the architecture.** `Renew` is fenced on `(id, lease_token)` only. After recovery the token is unchanged until the next claim, so a stale node's renewal succeeds on an `Enqueued` job, extends its lease, and tells the node it still holds the job. `ShutdownNodeAsync` states no fence at all (the attempt going to -1 in D-6). The D-6 fix as worded ("checks that it still holds the job") doesn't name these two statements.
- **Some decisions add a contract the architecture lacks**, such as D-9's advertised recurring names, and no model checks the shape it would take.

**Recommendation:** for the next iteration, add the arch §4.4 and §5.3 semantics as a second input, and check each store operation's fence against the model's guard. In particular, `Renew` and `ShutdownNodeAsync` should also require `state='Processing'`.

### 6. Atomic steps in the models are a contract for every store

Several rules hold only because a whole operation is one TLA+ step: claim, tick, fire, reconcile (F4: "a node start and its reconcile are one atomic store step"), and completion including its token check. Iteration 1 already calls out the lease rules in F1 and F6 as the weakest passes for this reason. That matches the PostgreSQL design in arch §4.4. But:

- **REQ-003's new wording invites a race:** "Before a node writes anything about a job ..., it checks that it still holds the job." A separate check followed by a write is a check-then-act race. What the model verifies is a conditional write (the fence is in the `UPDATE ... WHERE`). Reword it that way.
- **D-9 needs an ordering rule the model hides.** The starting node's own row and advertised names must be visible, and other nodes' rows read, inside the reconcile transaction. Otherwise two nodes of different versions starting together each miss the other, and jobs flap.
- **Every future store** (in-memory, SQLite, SQL Server, Redis) has to give the same atomicity. M1-07's conformance suite is where to say so. State it explicitly as "each `IJobStore` method is linearizable", because that is the assumption every model rests on.

### 7. Inconsistencies inside the models

- **Requeue and cancel requests disagree.** F1 assumes "a requeue clears an earlier cancel request", and D-13 confirmed it. F3 assumes "requeue resets the attempt count only; the cancel request stays". In F3, a requeued, previously cancelled run can therefore end `Cancelled` straight away, which shortens the window in which it overlaps another run. I haven't re-run F3 with F1's assumption. It should be re-run, because D-4's accepted overlap is exactly this path.
- **A known-failing rule sits in the main F3 config.** `AwaitingNeverStranded` fails, and is waved through in prose because only the two accepted loops (D-4, D-12) cause it. The variants that remove those loops live in `attempts/`. As it stands, the next run can't tell a new stranding bug from the accepted ones. Bound the loops in the main model (as `MaxRequeues` does in F1), or make the rule conditional, so the main config is green when nothing is new.
- **`NoOverlap` was weakened to match D-4** ("or one of them was warned"). That's correct for the decision, but the `warned` flag is model-only state with no counterpart in the design (see finding 1, D-4). Until the warning exists somewhere, this rule checks something the system doesn't do.
- **F3 copies F1's lifecycle in simplified form** ("from F1"). The requeue drift above is the first sign of what happens with two copies. A short note at the top of F3 listing which F1 rules it assumes, and a check that F1's assumptions match, would keep them aligned.

### 8. Decision options worth revisiting

- **D-8 is rated major but is a load problem.** The decision itself says "Nothing is deleted twice", and arch §4.4's purge uses `FOR UPDATE SKIP LOCKED`, so two purges never touch the same rows or block each other. The cost is one extra concurrent batch. Option 3 (accept it) plus a statement timeout on the batch (which is option 1, enforced by the database) is the cheapest correct answer. Option 2 (the store refuses a batch without the lease) adds a lease-row lock to every purge transaction for little benefit.
- **D-19 option 1 ("the newest version decides") breaks rollbacks.** After rolling back to the old version, the old schedule can never be written again, because old < new. It also needs an ordered application version, which Bellhop doesn't have. Option 2 (accept and document) is the safer choice, possibly with "don't reset `next_run_at` when the newly computed next run is the same instant" to reduce the flip's effect.
- **D-4's warning has no surface in M1** (finding 1). Decide where it appears before the stories are edited.

### 9. What the models can't see

- **Liveness is thin.** F1 has no "a `Processing` job eventually leaves `Processing`", F4 no "settles after a deploy" (finding 4), and F6 no "cleanup eventually runs". The bugs found so far cluster around convergence, so this is where more rules will pay off.
- **Small bounds hide growth.** F3 caps occurrences at 3. Under `Queue`, every fire while a run is active, which now includes `Unroutable` (D-3), adds another `Awaiting` occurrence, and neither the stories nor the architecture caps that backlog. A handler-less hour on a minutely job queues 60 runs. That's a design question, not a model bug, but the models will never raise it.
- **Races inside one tick are unchecked** (REQ-007, REQ-027). They're single steps in the models, and the real risk lives in the multi-CTE tick statement with `SKIP LOCKED` (arch §4.4). That's better covered by M1-19's concurrency tests than by these models. Mark them in M1-19 as the place that requirement is checked, so they don't stay "unchecked" forever.
- **F7 (catch-up) is unchecked by design.** That's reasonable, since it's calendar arithmetic and M1-04/M1-14 cover it.

### 10. Reproducibility and housekeeping

- **There's no way to re-run the checks.** There is no script, no README in `refinement/`, and no record of the TLC version or flags. The raw `*.tlc.log` files are excluded by `.gitignore`'s `*.log`, so the committed evidence is the derived `*.check.json` only. Add a small `refinement/README.md` with one command per model (TLC 2.19, `-deadlock`, the config) and either commit the logs or stop generating them.
- **Each iteration copies the whole model set** (`iterations/1/models`, `iterations/2/models`), plus 4.6 MB of `attempts/`. Git history already keeps the old versions. One `refinement/models/` that changes each iteration, with `iterations/N/` holding only inputs, results and traces, would make "the current model" unambiguous.
- **Traces should become tests.** Each counterexample trace is a ready-made conformance test: a sequence of store calls and the state that must not occur. Turning the D-3, D-5, D-6 and D-9 traces into `Bellhop.Storage.Conformance` cases (M1-05 to M1-07) is the most direct way to make the models matter once code exists. Later, `code-to-tla` can check the code against these same models.

## Recommended next steps, in order

1. Propagate D-3 to D-12 into the stories and the architecture (finding 1), after first settling the wording of D-7 (finding 2), D-1 (finding 3), the conditional-write wording of D-6 (findings 5 and 6), and where D-4's warning goes.
2. Decide the orphan sweep for finding 4, and add the convergence rule to F4.
3. Answer D-8, D-18 and D-19, taking finding 8 into account.
4. Iteration 3: add the architecture's §4.4 and §5.3 as an input, align F1 and F3 on requeue, keep the main configs green when nothing is new, and add the liveness rules from finding 9.
5. Add `refinement/README.md` with re-run commands, and file one conformance-test criterion per counterexample trace in M1-05 to M1-07.

## Appendix A: experiments

All runs used TLC 2.19 (`java -cp tla2tools.jar tlc2.TLC -workers 4 -deadlock`) on copies of the iteration-2 models in a scratch folder. The repository's models were not modified.

F2 (`F2_SelfFencing.cfg` unchanged). "Precise" replaces `FenceOverdue`'s `now >= lastOk + FenceAfter + RenewEvery` with `now >= lastOk + FenceAfter`, which stops time from passing the fencing deadline without the node acting.

| Run | `Recover` guard | `FenceAfter` | Fencing check | Result |
|---|---|---|---|---|
| 1 | `now >= expiry` | `2 * RenewEvery` | periodic | `NoDoubleRun` violated, 11 states: store down from tick 2, recovered at tick 6 = expiry, holder not yet fenced |
| 2 | `now > expiry + 1` | `2 * RenewEvery` | periodic | holds (control: a margin on the store side) |
| 3 | `now >= expiry` | `RenewEvery` | periodic | `HealthyNeverRecovered` violated: the node gives up at a routine renewal |
| 4a | `now >= expiry` | `2 * RenewEvery` | precise | holds |
| 4b | `now >= expiry - 1` | `2 * RenewEvery` | precise | holds |
| 4c | `now >= expiry - 2` | `2 * RenewEvery` | precise | `NoDoubleRun` violated |

F4, crashed node rows (run 5). The changes to `F4_RecurringReconcile.tla`:

- add `VARIABLE ghost` (`[Nodes -> Versions \cup {"none"}]`, initially all `"none"`): the version a crashed process's still-live row advertises;
- `LiveCode` for `svc1` also includes `CodeOf("svc1", ghost[m])` for every `m` with a ghost;
- `StartNode(n, v)` requires `node[n] = "down"`;
- `CrashNode(n)`: a running node goes `"down"` and leaves `ghost[n] = node[n]`; `GhostAgesOut(n)`: the ghost clears, with no reconcile;
- check this invariant:

```tla
RemovedJobOrphanedAfterDeploy ==
    ((\A n \in Nodes : node[n] = "new") /\ (\A n \in Nodes : ghost[n] = "none")
       /\ def["d2"].ex /\ def["d2"].app = "svc1")
    => def["d2"].orph
```

Result: violated in 6 states: `StopNode(n1)`, `StartNode(n1, new)`, `CrashNode(n2)`, `StartNode(n2, new)`, `GhostAgesOut(n2)`. Run 6, the same model without `CrashNode` in `Next`, holds with 24,408 distinct states, identical to the original F4.
