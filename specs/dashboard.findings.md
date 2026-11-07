# Findings: Bellhop dashboard and JSON API

<!-- refiner-findings v1 | module: dashboard | specHash: 2d34d3724a1639363f5d1a9b7cbe2877d2b1168b005183072757a6db897e0d6b | run: 2026-11-07 (run 4) | previous: model/dashboard/previous.findings.md (run 3) -->

**Run:** 2026-11-07, run 4 · **Requirements file:** `specs/dashboard.json` (specHash `2d34d3724a16`) · **Model:** `model/dashboard/Dashboard.tla`, regenerated for the one handoff id (INV-305): `AcquireRollupLease` and `Inv_RollupStartWithLease`; nothing else changed and no item was impacted · **TLC:** 24 runs, each check alone with `--stop-at-first --workers 2`; no timeout and no TLC exception. The largest is 40 608 distinct states in 11.7 s
**Result:** no findings: 0 contradictions · 0 gaps · 0 unprovable · 0 ambiguities · 0 modeling notes. One check is violated on purpose and accepted by the owner (see *Accepted checks*). Run 3's F-1 is resolved.

| Run | cfg | Result | Distinct states |
|---|---|---|---|
| access, 14 checks one at a time | `Dashboard.cfg` | `TypeInv`, `Inv_RulesConsistent_Anon`/`_User`/`_Key`, `Inv_UnsafeConfigNeverRuns`, `Inv_AnonServedAfterNotice`, `Inv_AnonViewOnlyOutsideDev`, `Chk_LaunchHasPrincipal` and the negative scenarios SCN-303, 304, 306, 307 and 309 **hold**; no deadlock. `Chk_ApiKeyNotBypassed` violated in 4 steps (accepted, see below) | 40 608 per passing check |
| banner | `Dashboard_Banner.cfg` | `TypeInv` holds, no deadlock | 384 |
| rollup (`--no-deadlock`) | `Dashboard_Rollup.cfg` | `TypeInv` holds; `Inv_RollupOneWrite` **holds** (violated in run 3, F-1); the action property `Inv_RollupStartWithLease`, now with the "not written yet" condition, **holds** | 2 048 each |
| SCN-300 | `Dashboard_SCN300.cfg` | trap violated: reachable ✔ in 2 steps | 6 |
| SCN-301 | `Dashboard_SCN301.cfg` | trap violated: reachable ✔ in 4 steps | 28 |
| SCN-302 | `Dashboard_SCN302.cfg` | trap violated: reachable ✔ | 138 |
| SCN-305 | `Dashboard_SCN305.cfg` | trap violated: reachable ✔ | 269 |
| SCN-308 | `Dashboard_SCN308.cfg` | trap violated by the given state: reachable ✔ (the given already satisfies the *then*, as before) | — |
| SCN-310 | `Dashboard_SCN310.cfg` | trap violated: reachable ✔ in 5 steps (454 states where run 3 reported 442: the count at which parallel BFS stops varies; this cfg checks only the access part, which did not change) | 454 |

Reproduce: from `specs/model/dashboard`, `sh run_all.sh`. It runs `run_tlc.py … --stop-at-first` once per invariant, and once per property (with `TypeInv`), and writes `runs/*.json|md`, which are gitignored.

How to read the access results: the authorization sentences (INV-300, INV-301, INV-302, INV-307, INV-308, REQ-303, REQ-304, REQ-305, and the grants of REQ-300/REQ-342) are rules on the outcome of a single request. In every reachable state, TLC checks that **some** outcome satisfies all of them at once. All three `Inv_RulesConsistent_*` checks still hold, so no request forces a response that breaks a `must`.

## Changes since last run
| Finding | Status |
|---|---|
| F-1 (run 3) gap · Inv_RollupOneWrite | **resolved**: INV-305 now starts computing only an interval "that has not been written yet". `AcquireRollupLease` was regenerated with that condition, and `Inv_RollupOneWrite` holds (`Dashboard_Rollup.cfg`, 2 048 states, depth 6). Run 3's 6-step trace stops at step 4: after n1's write and the lapse of its lease, n2 can no longer start i1. Leases still lapse at any moment (A-15), so the fenced write is still exercised: a node whose lease lapsed mid-computation has its write refused, and a second node may still compute and write an interval that was never written. The state space is the one run 3's throw-away variant predicted (2 048) |

`findings_delta.py model/dashboard/previous.findings.md dashboard.findings.md`:

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | gap · Inv_RollupOneWrite · INV-305 |

1 resolved, 0 new, 0 still open.

## Summary
No findings. INV-305's notes ("skipping it is what makes the result single") now match what the model shows.

---

## Accepted checks
These checks are violated, and the owner has accepted the behaviour. They are rerun every time, so a change in their trace shows up.

| Check | cfg | Result | Accepted by |
|---|---|---|---|
| `Chk_ApiKeyNotBypassed` (REQ-300, REQ-301, REQ-305, REQ-342) | `Dashboard.cfg` | violated in 4 steps (582 states), the same trace as runs 2 and 3: Development, `RequireApiKey()` and no listed scheme. REQ-300 grants anonymous requests operate, the node runs, and a request with no key is served | REQ-305 notes (run 2 F-2, option 3), glossary `authorizationRequirement` and `anonymousPermission`, REQ-301's startup message, TECH-92 |

Did the model show a consequence the notes do not cover? No. Run 3 remarked that INV-307's note ("a leaked key cannot create more keys") was not literally true in an open Development dashboard. The note now says it holds "outside an open Development dashboard", which matches the trace.

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
| A-18 | No sentence releases the rollup lease after the write; it lapses (A-15). A node does not start a second computation of an interval while it is still computing one, and does not take the lease again while computing: a lease that lapsed and was taken again is not the lease the node "still holds". `Inv_RollupOneWrite` tracks *which nodes* wrote, so it catches a second node's write, not the same node writing twice | INV-305 |
| A-19 | New in run 4. "Has not been written yet" is judged at the moment the node starts computing, which in the model is the same step in which it takes the lease. An implementation that decides which interval to compute *before* taking its lease, and does not look again after, reads a stale "not written" and can write a finished interval a second time (run 3's F-1 trace with the read moved before step 4). The sentence already rules this out ("start computing each rollup interval that has not been written yet … only while the node holds the interval's lease"), so it is not a finding; it is the place an implementation is most likely to diverge | INV-305 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-300, REQ-301, REQ-302, REQ-303, REQ-304, REQ-305, REQ-306, REQ-319, REQ-320, REQ-321, REQ-322, REQ-334, REQ-335, REQ-336, REQ-337, REQ-338, REQ-339, REQ-340, REQ-341, REQ-342, INV-300, INV-301, INV-302, INV-305, INV-307, INV-308, INV-309 (holds by construction), SCN-300 … SCN-310 (all 11) | **No state change to explore, checked by inspection:** REQ-307, REQ-308, REQ-309, REQ-310, REQ-311, REQ-312, REQ-313, REQ-315, REQ-316, REQ-317, REQ-323, REQ-325, REQ-327, REQ-328, REQ-329, REQ-330, REQ-331, REQ-333, INV-304, INV-306 · **Strength may:** REQ-318, REQ-324 · **Needs real quantities:** REQ-314 (15 s sampling), REQ-343 (7-day pruning; that it is a worker duty is hosting REQ-40), REQ-332 · **Depends on the jobs state machine, not encoded:** REQ-326 (its wording is settled, run 1 F-11) · **Retired:** INV-303 |

## Next
Nothing to decide in this module. The one accepted check (`Chk_ApiKeyNotBypassed`) is rerun each time and its trace is unchanged. If a reviewer wants to look at one place, it is A-19: where the implementation of INV-305 reads "not written" relative to taking the lease. Rerun this skill when `specs/dashboard.json` or a hosting sentence it relies on (REQ-18, REQ-40) changes.
