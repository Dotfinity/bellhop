# Findings: Bellhop dashboard and JSON API

<!-- refiner-findings v1 | module: dashboard | specHash: fec5db365b2d09a0a082a140fa5039bd7bfdf6d50e08ff0c14ac82106910c11e | run: 2026-11-06 (run 3) | previous: model/dashboard/previous.findings.md (run 2) -->

**Run:** 2026-11-06, run 3 · **Requirements file:** `specs/dashboard.json` (specHash `fec5db365b2d`) · **Model:** `model/dashboard/Dashboard.tla`, regenerated for the 4 handoff ids (REQ-300, REQ-301, REQ-334, INV-305), with SCN-300 and SCN-301 re-checked · **TLC:** 24 runs, each check alone with `--stop-at-first --workers 2`; no timeout and no TLC exception. The largest is 40 608 distinct states in 18.9 s
**Result:** 1 finding: 0 contradictions · 1 gap · 0 unprovable · 0 ambiguities · 0 modeling notes. One check is violated on purpose and accepted by the owner (see *Accepted checks*). Run 2's F-1 and F-3 are resolved; F-2 is accepted.

| Run | cfg | Result | Distinct states |
|---|---|---|---|
| access, 14 checks one at a time | `Dashboard.cfg` | `TypeInv`, `Inv_RulesConsistent_Anon`/`_User`/`_Key`, `Inv_UnsafeConfigNeverRuns`, `Inv_AnonServedAfterNotice`, `Inv_AnonViewOnlyOutsideDev`, `Chk_LaunchHasPrincipal` (violated in run 2) and the negative scenarios SCN-303, 304, 306, 307 and 309 **hold**; no deadlock. `Chk_ApiKeyNotBypassed` violated in 4 steps (accepted, see below) | 40 608 per passing check |
| banner | `Dashboard_Banner.cfg` | `TypeInv` holds, no deadlock | 384 |
| rollup (`--no-deadlock`) | `Dashboard_Rollup.cfg` | `TypeInv` holds; the action property `Inv_RollupStartWithLease` (new wording of INV-305) **holds**; `Inv_RollupOneWrite` violated in 6 steps (F-1) | 5 120 (TypeInv, property) · 2 300 (violation) |
| SCN-300 | `Dashboard_SCN300.cfg` | trap violated: reachable ✔ in 2 steps (re-checked: REQ-301 changed) | 6 |
| SCN-301 | `Dashboard_SCN301.cfg` | trap violated: reachable ✔ in 4 steps (re-checked: REQ-300 changed) | 28 |
| SCN-302 | `Dashboard_SCN302.cfg` | trap violated: reachable ✔ | 138 |
| SCN-305 | `Dashboard_SCN305.cfg` | trap violated: reachable ✔ | 269 |
| SCN-308 | `Dashboard_SCN308.cfg` | trap violated by the given state: reachable ✔ (the given already satisfies the *then*, as before) | — |
| SCN-310 | `Dashboard_SCN310.cfg` | trap violated: reachable ✔ in 5 steps | 442 |

Reproduce: from `specs/model/dashboard`, `sh run_all.sh`. It runs `run_tlc.py … --stop-at-first` once per invariant, and once per property (with `TypeInv`), and writes `runs/*.json|md`, which are gitignored.

How to read the access results: the authorization sentences (INV-300, INV-301, INV-302, INV-307, INV-308, REQ-303, REQ-304, REQ-305, and the grants of REQ-300/REQ-342) are rules on the outcome of a single request. In every reachable state, TLC checks that **some** outcome satisfies all of them at once. All three `Inv_RulesConsistent_*` checks still hold, so no request forces a response that breaks a `must`.

## Changes since last run
| Finding | Status |
|---|---|
| F-1 (run 2) gap · Chk_LaunchHasPrincipal | **resolved**: REQ-300 names the anonymous principal `anonymous`. `Chk_LaunchHasPrincipal` holds (`Dashboard.cfg`, 40 608 states). Run 2's 4-step trace now ends with the job stored `by = "anonymous"` (checked with a throw-away trap, 575 states). It also holds in every Production configuration, which confirms REQ-300's note that the name never appears on a launch outside Development |
| F-2 (run 2) ambiguity · Chk_ApiKeyNotBypassed | **accepted, not fixed** (owner decision, option 3). `findings_delta.py` lists it as resolved because it is no longer a numbered finding. The check is still violated, with the same 4-step trace; see *Accepted checks* |
| F-3 (run 2) contradiction · Inv_RollupComputeWithLease | **resolved**: INV-305 now says "start computing … only while the node holds the interval's lease". The old state check is gone with the old wording. Its replacement, the action property `Inv_RollupStartWithLease`, holds (`Dashboard_Rollup.cfg`, 5 120 states, depth 11) even though leases still lapse mid-computation (A-15) |
| F-1 gap · Inv_RollupOneWrite | **new**: run 2's model had an unrecorded guard ("never start an interval that is already written"). INV-305 was regenerated from its sentence without that guard, and the "one write per interval" claim no longer holds |

`findings_delta.py model/dashboard/previous.findings.md dashboard.findings.md` (run-2 numbers in the resolved rows):

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | gap · Chk_LaunchHasPrincipal · REQ-300,REQ-320,REQ-321,REQ-322 |
| F-2 | resolved | ambiguity · Chk_ApiKeyNotBypassed · REQ-300,REQ-301,REQ-305,REQ-342 |
| F-3 | resolved | contradiction · Inv_RollupComputeWithLease · INV-305 |
| F-1 | new | gap · Inv_RollupOneWrite · INV-305 |

3 resolved, 1 new, 0 still open. (Of the 3 resolved rows, F-2 was *accepted*, not fixed.)

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | gap | low | INV-305 | Once the writer's lease lapses, another worker can take the lease for an interval that is already written and write it again |

---

## F-1 · gap · low — An interval that is already written can be computed and written again
<!-- finding: gap | Inv_RollupOneWrite | INV-305 -->

**Requirements involved**
- INV-305 (should): *Where the worker is registered on a node, the system shall start computing each rollup interval, as one of that node's background duties, only while the node holds the interval's lease in the store, and write the interval in one batched write that succeeds only if the node still holds the lease.*
- INV-305's source (BLT-13): *"Rollups are computed by one node under a lease (CON-7) in one batched write per interval."* INV-305's notes say: *"the write is fenced by the lease, so at most one result is written per interval even when a lease expires mid-computation."*

**What happens** (TLC counter-example, `Inv_RollupOneWrite`, 6 steps, `Dashboard_Rollup.cfg`)
1. Worker node n1 takes the lease for interval i1 and starts computing (INV-305).
2. n1 still holds the lease, so its batched write succeeds. Interval i1 is written (INV-305).
3. The lease lapses (A-15: a store lease is time-limited; no sentence says it is released or kept after the write).
4. Worker node n2 finds the lease for i1 free, takes it and starts computing i1. Nothing in INV-305 says a node skips an interval that is already written.
5. n2 holds the lease, so its batched write succeeds too. **Interval i1 has been written twice, by two nodes.**

**Why** The fence keeps one writer at a time: it stops a node whose lease lapsed *mid-computation*. It does not stop a *later* lease holder from redoing an interval that is already finished. Whether the second write is harmful depends on what the write does, and no sentence says. If it replaces the interval's buckets with the same values, it is wasted work. If it adds counts, the insights are doubled for that interval. Run 2's model hid this with an unrecorded guard (`wrote = {}` on taking the lease), which is why the owner's note reads as already guaranteed.

**Options**
1. *(recommended)* **Skip written intervals.** INV-305 starts computing only intervals that have not been written yet. With the fenced write, this keeps one result per interval. Evidence: the same model with that one guard added holds `Inv_RollupOneWrite` (throw-away variant, 2 048 distinct states). Run 2's model did the same, with 1 536 states.
2. **Make the write idempotent.** Say the batched write *replaces* the interval's buckets, so a repeat write cannot double anything, and drop the "one write per interval" claim from the notes. This is cheaper to implement (no "written" marker to check), but it allows wasted recomputation after every lease lapse.
3. **Keep the lease as the "done" marker.** The lease for a written interval is never released and never lapses. This needs an unbounded set of permanent leases, and it changes CON-7's lease semantics in hosting.

**Ready to apply (option 1)**
```json
{ "id": "INV-305", "ears": { "where": "the worker is registered on a node",
    "shall": "start computing each rollup interval that has not been written yet, as one of that node's background duties, only while the node holds the interval's lease in the store, and write the interval in one batched write that succeeds only if the node still holds the lease" },
  "notes": "… Run 3 F-1 (option 1): a later lease holder skips an interval that is already written; with the fenced write this keeps one result per interval." }
```

---

## Accepted checks
These checks are violated, and the owner has accepted the behaviour. They are rerun every time, so a change in their trace shows up.

| Check | cfg | Result | Accepted by |
|---|---|---|---|
| `Chk_ApiKeyNotBypassed` (REQ-300, REQ-301, REQ-305, REQ-342) | `Dashboard.cfg` | violated in 4 steps (582 states), the same trace as run 2: Development, `RequireApiKey()` and no listed scheme. REQ-300 grants anonymous requests operate, the node runs, and a request with no key is served | REQ-305 notes (run 2 F-2, option 3), glossary `authorizationRequirement` and `anonymousPermission`, REQ-301's startup message, TECH-92 |

Did the model show a consequence the notes do not cover? No new one. The violation is reachable only in Development without a listed scheme. In Production, the same mapping either fails the host's start (REQ-301, with the new hint about keys and pages) or grants anonymous requests view only (REQ-342). Both cases are spelled out in REQ-305's notes. One consequence is covered only through INV-301's list of operate actions. In Development with no listed scheme, a keyless caller can **create an API key** (anonymous operate includes "create or revoke an API key"). So INV-307's note *"only interactive users mint keys, so a leaked key cannot create more keys"* is not literally true there: a script holding a leaked key can drop it and mint one anonymously. This is within the accepted decision ("a keyless script in Development therefore has operate"). If the owner wants the INV-307 note to stay accurate, it could add "outside an open Development dashboard". This is not reported as a finding.

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.

| # | Assumption | Affects |
|---|---|---|
| A-1 | Superseded in run 2: the scheme list is now the sentence (REQ-300, REQ-301, REQ-342) | — |
| A-2 | The anonymous grants (REQ-300, REQ-342) happen while starting, before hosting REQ-18 marks the node running. Hosting REQ-18 itself names the dashboard checks REQ-301 and REQ-334. "Fail the host's start" (run 3 wording) is the same transition to StartupFailed as before | REQ-300, REQ-301, REQ-334, REQ-342, hosting REQ-18 |
| A-3 | REQ-300 and REQ-342 (Starting → Starting) fire once per startup; their notice or warning is one flag | REQ-300, REQ-342, SCN-301 |
| A-4 | REQ-303's "accept only …" is also read as "accept": a configured user with the right password, from an address that is not locked out, is authenticated | REQ-303 |
| A-5 | The authorization sentences are rules on each request's outcome (authenticated flag plus 200/401/403/other); any outcome that satisfies all of them is allowed. A request with the level it needs (authenticated, or anonymous with a granted level), not refused by INV-302 or INV-307, is served. Launches and key management happen only on a request that could be served | INV-300…INV-308, REQ-300, REQ-302…REQ-306, REQ-319…REQ-322, REQ-337, REQ-338, REQ-342 |
| A-6 | Policies, roles and claims are abstracted: Olga has operate, Vic has view. Operate includes view (glossary) | REQ-302, REQ-306 |
| A-7 | Interactive users exist only where RequireAuthorization/Role/Claim or basic auth is configured; they are authenticated exactly when their session or password is valid. Anonymous requests are never authenticated: their level is what REQ-300 or REQ-342 granted. API keys authenticate only where RequireApiKey() is enabled. Pages, JSON API and MCP are not told apart; since run 3 this is the owner's decision (glossary `anonymousPermission`) | REQ-305, INV-301 |
| A-8 | One client address and one per-address counter of failed **basic-auth** attempts (the per-user counter adds no interaction with any other rule). The counter saturates at MaxFailedLogins = 2 | REQ-304, REQ-335 |
| A-9 | Superseded in run 2: INV-308 and REQ-305 both name "past its expiresAt" | — |
| A-10 | The lockout window passes at a nondeterministic moment and resets the address counter (no clock; 15 minutes is not judged) | REQ-304, REQ-336 |
| A-11 | Run 3: a key-authenticated launch is attributed to "apiKey", standing for `apikey:<name>` (one key slot). An anonymous launch is attributed to `anonymous` exactly where REQ-300 fired. The model derives the name from `anonPerm = "operate"`, which only REQ-300 sets, in the same step. An anonymous viewer under REQ-342 has no name (NULL), and cannot launch | REQ-300, REQ-305, REQ-320…REQ-322 |
| A-12 | A key's expiresAt passes at a nondeterministic moment unless the key never expires; 90 days is not judged | REQ-305, REQ-339, REQ-340, INV-308 |
| A-13 | A revoked or expired key's slot is freed and then behaves as an unknown key (modeling artefact) | INV-308 |
| A-14 | Worker heartbeats are an alive/lost flag with no clock; NodeLostAfter (hosting REQ-60) is not judged. Nothing in this module claims jobs, so enqueued jobs stay enqueued | REQ-341, SCN-308 |
| A-15 | A rollup lease is time-limited and can lapse at any moment, including while its holder computes and after it has written. A holder whose lease is gone has its write refused and drops the computation. Rollup nodes are worker nodes | INV-305 |
| A-16 | Response codes for refusals that INV-300 and INV-308 don't cover (a lockout, ReadOnly, an anonymous request without the level) are left open | INV-302, REQ-304 |
| A-17 | Hosting's store and schema checks are treated as passed. Bounds: 1 API key slot, 1 job slot, 1 recurring slot, 1 worker node, 2 rollup nodes, 1 rollup interval. The access, banner and rollup parts are checked in separate cfgs | all |
| A-18 | New in run 3. No sentence releases the rollup lease after the write; it lapses (A-15). A node does not start a second computation of an interval while it is still computing one. `Inv_RollupOneWrite` tracks *which nodes* wrote, so it catches a second node's write, not the same node writing twice. Run 2's extra guard "an interval already written is not started" was not from any sentence and is removed (F-1) | INV-305 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-300, REQ-301, REQ-302, REQ-303, REQ-304, REQ-305, REQ-306, REQ-319, REQ-320, REQ-321, REQ-322, REQ-334, REQ-335, REQ-336, REQ-337, REQ-338, REQ-339, REQ-340, REQ-341, REQ-342, INV-300, INV-301, INV-302, INV-305, INV-307, INV-308, INV-309 (holds by construction), SCN-300 … SCN-310 (all 11) | **No state change to explore, checked by inspection:** REQ-307, REQ-308, REQ-309, REQ-310, REQ-311, REQ-312, REQ-313, REQ-315, REQ-316, REQ-317, REQ-323, REQ-325, REQ-327, REQ-328, REQ-329, REQ-330, REQ-331, REQ-333, INV-304, INV-306 · **Strength may:** REQ-318, REQ-324 · **Needs real quantities:** REQ-314 (15 s sampling), REQ-343 (7-day pruning; that it is a worker duty is hosting REQ-40), REQ-332 · **Depends on the jobs state machine, not encoded:** REQ-326 (its wording is settled, run 1 F-11) · **Retired:** INV-303 |

## Next
Decide F-1. It is the only open finding, and it is low (INV-305 is a `should`). The choice is between "skip written intervals" (option 1) and "the write replaces the interval" (option 2). Whichever is chosen, INV-305's note "at most one result is written per interval" should match it. Apply the choice to `specs/dashboard.json` with the `refiner-requirements` skill, then run this skill again.

### Raw trace (F-1, `runs/Dashboard_Rollup__Inv_RollupOneWrite.md`, rollup variables only)
| # | Action | lease | computing | wrote |
|---|---|---|---|---|
| 1 | Initial predicate | NULL | {} | {} |
| 2 | AcquireRollupLease | n1 | {n1} | {} |
| 3 | WriteRollup | n1 | {} | {n1} |
| 4 | RollupLeaseExpires | NULL | {} | {n1} |
| 5 | AcquireRollupLease | n2 | {n2} | {n1} |
| 6 | WriteRollup | n2 | {} | {n1, n2} |
