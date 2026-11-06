# Findings: Bellhop dashboard and JSON API

<!-- refiner-findings v1 | module: dashboard | specHash: 2349c84071280d2c93d2689dc9e62fe9528ecccf662fb5e15e1e91e6d46a2d36 | run: 2026-11-06 (run 2) | previous: git 744d843 specs/dashboard.findings.md -->

**Run:** 2026-11-06, run 2 · **Requirements file:** `specs/dashboard.json` (specHash `2349c8407128`) · **Model:** `model/dashboard/Dashboard.tla`, regenerated for the 16 handoff ids · **TLC:** 24 runs, every invariant alone with `--stop-at-first`, none hit a TLC exception; the largest is 40 608 distinct states in 12.5 s
**Result:** 3 findings: 1 contradiction · 1 gap · 0 unprovable · 1 ambiguity · 0 modeling notes. All 13 findings of run 1 are resolved.

| Run | cfg | Result | Distinct states |
|---|---|---|---|
| access, 14 checks one at a time | `Dashboard.cfg` | `TypeInv`, `Inv_RulesConsistent_Anon`/`_User`/`_Key`, `Inv_UnsafeConfigNeverRuns`, `Inv_AnonServedAfterNotice`, `Inv_AnonViewOnlyOutsideDev`, and the negative scenarios SCN-303, 304, 306, 307 and 309 **hold**; no deadlock. `Chk_LaunchHasPrincipal` (F-1) and `Chk_ApiKeyNotBypassed` (F-2) violated in 4 steps | 40 608 per passing check |
| banner | `Dashboard_Banner.cfg` | `TypeInv` holds, no deadlock | 384 |
| rollup (`--no-deadlock`: a written interval is final) | `Dashboard_Rollup.cfg` | `Inv_RollupOneWrite` **holds**; `Inv_RollupComputeWithLease` violated in 3 steps (F-3) | 1 536 |
| SCN-300 | `Dashboard_SCN300.cfg` | trap violated: reachable ✔ | 6 |
| SCN-301 | `Dashboard_SCN301.cfg` | trap violated: reachable ✔ (impossible in run 1) | 27 |
| SCN-302 | `Dashboard_SCN302.cfg` | trap violated: reachable ✔ | 138 |
| SCN-305 | `Dashboard_SCN305.cfg` | trap violated: reachable ✔ | 269 |
| SCN-308 | `Dashboard_SCN308.cfg` | trap violated by the given state: reachable ✔ (the given already satisfies the *then*, as in run 1) | — |
| SCN-310 | `Dashboard_SCN310.cfg` | trap violated: reachable ✔ in 5 steps | 454 |

Reproduce: from `specs/model/dashboard`, `sh run_all.sh` (it runs `run_tlc.py … --stop-at-first` once per invariant and writes `runs/*.json|md`, which are gitignored).

How to read the access results: the authorization sentences (INV-300, INV-301, INV-302, INV-307, INV-308, REQ-303, REQ-304, REQ-305, and the grants of REQ-300/REQ-342) are rules on the outcome of a single request. In every reachable state, TLC checks that **some** outcome satisfies all of them at once. All three `Inv_RulesConsistent_*` checks now hold, so no request forces a response that breaks a `must`.

## Changes since last run
| Finding | Status |
|---|---|
| F-1 (run 1) contradiction · Inv_RulesConsistent_Anon | **resolved**: REQ-300 now grants anonymous requests operate permission. `Inv_RulesConsistent_Anon` holds (40 608 states) and SCN-301 is reachable in 4 steps |
| F-2 (run 1) contradiction · Inv_RulesConsistent_Key | **resolved**: the lockout (REQ-304) covers basic-auth attempts only. `Inv_RulesConsistent_Key` holds, and SCN-310 shows a valid key working from a locked-out address |
| F-3 (run 1) gap · REQ-304 | **resolved**: failed key attempts are no longer counted (INV-308), so no counter is left without a lockout. Brute-force resistance moves to NFR-62, whose threshold is an open question there |
| F-4 (run 1) ambiguity · Inv_RulesConsistent_Key (expiry) | **resolved**: INV-308 and REQ-305 both name "past its expiresAt". The A-9 reading cfg is gone; `Scn_ExpiredKeyRejected` holds for a key whose expiry has passed, whether or not REQ-339 has marked it yet |
| F-5 (run 1) ambiguity · Inv_UnsafeConfigNeverRuns | **resolved**: hosting REQ-18/19 name REQ-301 and REQ-334. The A-2 reading cfg is gone; `Inv_UnsafeConfigNeverRuns` holds |
| F-6 (run 1) gap · Inv_BannerHasLastSeen | **resolved**: REQ-341 says what to show when no worker was ever seen (`BannerDetail`); SCN-308 is still reachable |
| F-7 (run 1) contradiction · Inv_RollupOneNode | **resolved**: INV-305's write is fenced. `Inv_RollupOneWrite` holds (1 536 states). The wording has a residue, see F-3 below |
| F-8 (run 1) ambiguity · node scope of dashboard duties | **resolved** by the text: every node samples itself (REQ-314), while pruning (REQ-343) and rollups (INV-305) are worker duties listed in hosting REQ-40 |
| F-9 (run 1) gap · launch attribution | **resolved** for named principals: REQ-322 stores the principal, and REQ-305 defines `apikey:<name>`. An anonymous launcher has none, see F-1 below |
| F-10 (run 1) ambiguity · authorization requirement | **resolved**: REQ-300, REQ-301 and REQ-342 list the schemes. One consequence is F-2 below |
| F-11 (run 1) ambiguity · bulk by tag | **resolved** by the text: REQ-326 matches at the start, takes one atomic step per job and reports counts. Still not encoded (jobs state machine) |
| F-12 (run 1) ambiguity · dashboard without client | **resolved**: INV-309. It holds by construction, since no action in the model depends on client registration |
| F-13 (run 1) modeling · uses | **resolved** differently: NodeLostAfter moved to hosting REQ-60, which dashboard already `uses` |
| F-1 gap · Chk_LaunchHasPrincipal | new |
| F-2 ambiguity · Chk_ApiKeyNotBypassed | new |
| F-3 contradiction · Inv_RollupComputeWithLease | new |

`findings_delta.py model/dashboard/previous.findings.md dashboard.findings.md` (run-1 numbers in the resolved rows):

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | contradiction · Inv_RulesConsistent_Anon · INV-301,REQ-300,SCN-301 |
| F-2 | resolved | contradiction · Inv_RulesConsistent_Key · INV-308,REQ-304,REQ-305 |
| F-3 | resolved | gap · REQ-304 · INV-308,REQ-304 |
| F-4 | resolved | ambiguity · Inv_RulesConsistent_Key · INV-308,REQ-305,REQ-339 |
| F-5 | resolved | ambiguity · Inv_UnsafeConfigNeverRuns · REQ-300,REQ-301,REQ-334,hosting.REQ-18 |
| F-6 | resolved | gap · Inv_BannerHasLastSeen · REQ-341 |
| F-7 | resolved | contradiction · Inv_RollupOneNode · INV-305 |
| F-8 | resolved | ambiguity · node scope of dashboard duties · INV-305,REQ-314,REQ-332,hosting.REQ-40 |
| F-9 | resolved | gap · launch attribution · REQ-305,REQ-320,REQ-322,REQ-323 |
| F-10 | resolved | ambiguity · authorization requirement · REQ-300,REQ-301 |
| F-11 | resolved | ambiguity · bulk by tag · REQ-326,jobs.REQ-142 |
| F-12 | resolved | ambiguity · dashboard without client · REQ-320,REQ-321,REQ-322,hosting.REQ-51,hosting.REQ-52 |
| F-13 | resolved | modeling · uses · REQ-341,integrations.REQ-411 |
| F-1 | new | gap · Chk_LaunchHasPrincipal · REQ-300,REQ-320,REQ-321,REQ-322 |
| F-2 | new | ambiguity · Chk_ApiKeyNotBypassed · REQ-300,REQ-301,REQ-305,REQ-342 |
| F-3 | new | contradiction · Inv_RollupComputeWithLease · INV-305 |

13 resolved, 3 new, 0 still open.

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-2 | ambiguity | medium | REQ-300, REQ-301, REQ-342, REQ-305 | RequireApiKey() is not an authorization requirement, so in Development keyless scripts get operate, and in production a keys-only dashboard cannot start without opening the pages |
| F-1 | gap | medium | REQ-300, REQ-320, REQ-321, REQ-322 | An anonymous operator in Development can launch, but has no principal name to store |
| F-3 | contradiction | low | INV-305 | "Compute only while holding the lease" cannot hold once a lease expires mid-computation |

---

## F-2 · ambiguity · medium — RequireApiKey() does not protect the JSON API on its own
<!-- finding: ambiguity | Chk_ApiKeyNotBypassed | REQ-300,REQ-301,REQ-305,REQ-342 -->

**Requirements involved**
- REQ-300: *While a node is starting, if the dashboard is mapped without RequireAuthorization, RequireRole, RequireClaim or RequireBasicAuth and the environment is Development, then the system shall treat anonymous requests as having operate permission and log a notice saying so.*
- REQ-301: *… without RequireAuthorization, RequireRole, RequireClaim or RequireBasicAuth, AllowAnonymous() was not called and the environment is not Development, then the system shall stop the node from starting …*
- REQ-305: *Where RequireApiKey() is enabled, when a script or the CLI calls the JSON API with an active API key whose expiresAt has not passed, the system shall authenticate it …*
- glossary `authorizationRequirement`: RequireApiKey() is deliberately not on the list, because it authenticates scripts, not browsers.

**What happens** (TLC counter-example, `Chk_ApiKeyNotBypassed`, 4 steps, `Dashboard.cfg`)
1. A developer maps `MapBellhopDashboard("/jobs").RequireApiKey()` in Development, to try out the CI script's key. No other scheme, no AllowAnonymous().
2. The node starts. RequireApiKey() is not on REQ-300's list, so REQ-300 fires: anonymous requests have **operate** permission and a notice is logged.
3. The node runs (hosting REQ-18).
4. A script calls an operate endpoint of the JSON API **without any key**. It has operate permission (REQ-300) and is served (INV-301, A-5). It can also create a new API key, because INV-307 refuses only key-authenticated key creation.

The same rule has a production consequence (concrete example from the sentences, no trace): `MapBellhopDashboard("/jobs").RequireApiKey()` in Production, meant as "the JSON API only, for our scripts", meets REQ-301's condition and **the node fails to start**. The only ways out are an interactive scheme, or AllowAnonymous(), and the latter gives anonymous requests view permission (REQ-342) on the pages *and* on the JSON API reads.

**Why** The scheme list now decides who may use the browser pages, but REQ-300 and REQ-342 grant anonymous requests a permission level for everything INV-301 covers: pages, JSON API and MCP. RequireApiKey() adds a way in, but nothing says it closes the JSON API to keyless callers.

**Options**
1. *(recommended)* **Where RequireApiKey() is enabled, the JSON API and MCP require a key.** Add one invariant: keyless JSON API or MCP requests get 401, whatever REQ-300 or REQ-342 grant. The anonymous grants then apply to the browser pages only. The production keys-only case still needs AllowAnonymous() or an interactive scheme for the pages, but no longer exposes the API.
2. **Count RequireApiKey() as an authorization requirement for the JSON API only.** REQ-301 then stops startup only when the *pages* have no scheme. This is the same effect as option 1, split over REQ-300, REQ-301 and REQ-342, and the sentences become harder to read.
3. **Accept and document** that RequireApiKey() adds key authentication but never restricts keyless access that REQ-300 or REQ-342 grant.

**Ready to apply (option 1)**
```json
{ "id": "INV-310", "kind": "invariant", "status": "approved", "strength": "must", "entity": "DashboardRequest",
  "ears": { "where": "RequireApiKey() is enabled", "if": "a JSON API or MCP request presents no API key",
    "shall": "respond 401 Unauthorized, whatever permission REQ-300 or REQ-342 grant anonymous requests" },
  "dependsOn": ["REQ-300", "REQ-342", "REQ-305"],
  "notes": "refiner-model 2026-11-06 run 2 F-2 (option 1): the anonymous grants apply to the browser pages; scripts must present a key once RequireApiKey() is on." }
```

---

## F-1 · gap · medium — An anonymous launch has no principal name to store
<!-- finding: gap | Chk_LaunchHasPrincipal | REQ-300,REQ-320,REQ-321,REQ-322 -->

**Requirements involved**
- REQ-300 (quoted in F-2): anonymous requests have **operate** permission in Development.
- REQ-320: *When an operator submits a valid launch form with Run now, the system shall enqueue the job with the form's payload and store the operator's principal name on it.* REQ-321 and REQ-322 say the same for Schedule for and Make recurring.
- REQ-305 defines a key's principal name (`apikey:<name>`). No sentence defines one for an anonymous request.

**What happens** (TLC counter-example, `Chk_LaunchHasPrincipal`, 4 steps, `Dashboard.cfg`)
1. Development, the dashboard mapped with no scheme. The node starts, and REQ-300 grants anonymous requests operate and logs the notice.
2. The node runs (hosting REQ-18).
3. An anonymous browser submits a valid launch form with Run now. It has operate permission, so REQ-320 enqueues the job.
4. **The job has no principal name** (`by = NULL`): REQ-320 requires one, and the anonymous operator has none. REQ-323's recent-launches list cannot say who launched it.

**Why** Run 1's F-1 fix made anonymous requests operators in Development, but the attribution rules (run 1 F-9) were written for authenticated principals.

**Options**
1. *(recommended)* **Name the anonymous principal.** REQ-300 gives anonymous requests the principal name `anonymous`, so every launch has a name and REQ-323 lists it.
2. **Store the client address instead** for anonymous launches. More useful for tracing who did it, but it adds a personal-data field to the launch record.
3. **Allow anonymous operators everything except launching.** This contradicts INV-301's single operate permission.

**Ready to apply (option 1)**
```json
{ "id": "REQ-300", "ears": { "while": "a node is starting",
    "if": "the dashboard is mapped without RequireAuthorization, RequireRole, RequireClaim or RequireBasicAuth and the environment is Development",
    "shall": "treat anonymous requests as having operate permission and the principal name \"anonymous\", and log a notice saying so" } }
```

---

## F-3 · contradiction · low — "Compute only while holding the lease" cannot hold once a lease expires
<!-- finding: contradiction | Inv_RollupComputeWithLease | INV-305 -->

**Requirements involved**
- INV-305 (should): *Where the worker is registered on a node, the system shall compute each rollup interval, as one of that node's background duties, **only while the node holds the interval's lease** in the store, and write the interval in one batched write that succeeds only if the node still holds the lease.*

**What happens** (TLC counter-example, `Inv_RollupComputeWithLease`, 3 steps, `Dashboard_Rollup.cfg`)
1. Worker node n1 takes the lease for interval i1 and starts computing (INV-305).
2. **The lease expires while n1 is still computing** (A-15: a store lease is time-limited, and a slow query or a GC pause can outlast it). n1 is now computing without holding the lease, which the sentence forbids.
3. (In longer traces, n1's write is then refused, and n2 takes the lease and writes the interval. `Inv_RollupOneWrite` holds, so the stored result is never doubled.)

**Why** Run 1's F-7 option 1 said *"duplicate computation stays possible and harmless"*. The fenced write does that. But the applied sentence also says "compute only while holding", which no node can guarantee, because it does not know the lease expired until it next talks to the store.

**Options**
1. *(recommended)* Reword to what the fence guarantees: **"start computing each rollup interval only while holding its lease"**, and keep the fenced write.
2. Require the node to renew the lease during the computation and stop when renewal fails. This narrows the window but cannot close it, and adds a renewal loop.

**Ready to apply (option 1)**
```json
{ "id": "INV-305", "ears": { "where": "the worker is registered on a node",
    "shall": "start computing each rollup interval, as one of that node's background duties, only while the node holds the interval's lease in the store, and write the interval in one batched write that succeeds only if the node still holds the lease" } }
```

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.

| # | Assumption | Affects |
|---|---|---|
| A-1 | Superseded in run 2: the scheme list is now the sentence (REQ-300, REQ-301, REQ-342) | — |
| A-2 | The anonymous grants (REQ-300, REQ-342) happen while starting, before hosting REQ-18 marks the node running. The dashboard *checks* REQ-301 and REQ-334 are now named by hosting REQ-18 itself | REQ-300, REQ-342, hosting REQ-18 |
| A-3 | REQ-300 and REQ-342 (Starting → Starting) fire once per startup; their notice or warning is one flag | REQ-300, REQ-342, SCN-301 |
| A-4 | REQ-303's "accept only …" is also read as "accept": a configured user with the right password, from an address that is not locked out, is authenticated | REQ-303 |
| A-5 | The authorization sentences are rules on each request's outcome (authenticated flag plus 200/401/403/other); any outcome that satisfies all of them is allowed. A request with the level it needs (authenticated, or anonymous with a granted level), not refused by INV-302 or INV-307, is served. Launches and key management happen only on a request that could be served | INV-300…INV-308, REQ-300, REQ-302…REQ-306, REQ-319…REQ-322, REQ-337, REQ-338, REQ-342 |
| A-6 | Policies, roles and claims are abstracted: Olga has operate, Vic has view. Operate includes view (glossary) | REQ-302, REQ-306 |
| A-7 | Interactive users exist only where RequireAuthorization/Role/Claim or basic auth is configured; they are authenticated exactly when their session or password is valid. Anonymous requests are never authenticated: their level is what REQ-300 or REQ-342 granted. API keys authenticate only where RequireApiKey() is enabled. Pages, JSON API and MCP are not told apart (see F-2) | REQ-305, INV-301 |
| A-8 | One client address and one per-address counter of failed **basic-auth** attempts (the per-user counter adds no interaction with any other rule). The counter saturates at MaxFailedLogins = 2 | REQ-304, REQ-335 |
| A-9 | Superseded in run 2: INV-308 and REQ-305 both name "past its expiresAt" | — |
| A-10 | The lockout window passes at a nondeterministic moment and resets the address counter (no clock; 15 minutes is not judged) | REQ-304, REQ-336 |
| A-11 | A key-authenticated launch is attributed to "apiKey", standing for `apikey:<name>` (one key slot). An anonymous launch gets no name (NULL), because no sentence defines one (F-1) | REQ-305, REQ-320…REQ-322 |
| A-12 | A key's expiresAt passes at a nondeterministic moment unless the key never expires; 90 days is not judged | REQ-305, REQ-339, REQ-340, INV-308 |
| A-13 | A revoked or expired key's slot is freed and then behaves as an unknown key (modeling artefact) | INV-308 |
| A-14 | Worker heartbeats are an alive/lost flag with no clock; NodeLostAfter (hosting REQ-60) is not judged. Nothing in this module claims jobs, so enqueued jobs stay enqueued | REQ-341, SCN-308 |
| A-15 | A rollup lease can expire while its holder still computes; the holder's write is then refused (fenced write) and it drops the computation. Rollup nodes are worker nodes | INV-305 |
| A-16 | Response codes for refusals that INV-300 and INV-308 don't cover (a lockout, ReadOnly, an anonymous request without the level) are left open | INV-302, REQ-304 |
| A-17 | Hosting's store and schema checks are treated as passed. Bounds: 1 API key slot, 1 job slot, 1 recurring slot, 1 worker node, 2 rollup nodes, 1 rollup interval. The access, banner and rollup parts are checked in separate cfgs | all |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-300, REQ-301, REQ-302, REQ-303, REQ-304, REQ-305, REQ-306, REQ-319, REQ-320, REQ-321, REQ-322, REQ-334, REQ-335, REQ-336, REQ-337, REQ-338, REQ-339, REQ-340, REQ-341, REQ-342, INV-300, INV-301, INV-302, INV-305, INV-307, INV-308, INV-309 (holds by construction), SCN-300 … SCN-310 (all 11) | **No state change to explore, checked by inspection:** REQ-307, REQ-308, REQ-309, REQ-310, REQ-311, REQ-312, REQ-313, REQ-315, REQ-316, REQ-317, REQ-323, REQ-325, REQ-327, REQ-328, REQ-329, REQ-330, REQ-331, REQ-333, INV-304, INV-306 · **Strength may:** REQ-318, REQ-324 · **Needs real quantities:** REQ-314 (15 s sampling), REQ-343 (7-day pruning; that it is a worker duty is hosting REQ-40), REQ-332 · **Depends on the jobs state machine, not encoded:** REQ-326 (its wording is settled, run 1 F-11) · **Retired:** INV-303 |

## Next
Decide F-2 first: it determines what the JSON API looks like in every deployment that uses API keys, and F-1's fix (the anonymous principal name) only matters on the pages if F-2 option 1 is taken. Apply the choices to `specs/dashboard.json` with the `refiner-requirements` skill, then run this skill again.
