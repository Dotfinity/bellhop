# Findings: Bellhop dashboard and JSON API

<!-- refiner-findings v1 | module: dashboard | specHash: ce16de70435fba1584ec443b26258c24c1db3a6e362d3c79d695efd8fc73cdc3 | run: 2026-11-06 | previous: none -->

**Run:** 2026-11-06 · **Requirements file:** `specs/dashboard.json` (specHash `ce16de70435f`) · **Model:** `model/dashboard/Dashboard.tla` · **TLC:** main run violated 2 invariants (`-continue`), 23 392 distinct states, 15.5 s; 4 reading/part runs and 5 scenario runs, all < 31 s
**Result:** 13 findings: 3 contradictions · 3 gaps · 0 unprovable · 6 ambiguities · 1 modeling note

| Run | cfg | Result | Distinct states |
|---|---|---|---|
| main (access) | `Dashboard.cfg` | `Inv_RulesConsistent_Anon`, `Inv_RulesConsistent_Key` violated; all `Scn_` negatives, `TypeInv`, `Inv_UnsafeConfigNeverRuns`, `Inv_AnonServedAfterNotice` hold; no deadlock | 23 392 |
| reading A-2 | `Dashboard_A2.cfg` | `Inv_UnsafeConfigNeverRuns` violated | 23 524 |
| reading A-9 | `Dashboard_A9.cfg` | `Inv_RulesConsistent_Key` violated (also with no failed logins) | 23 392 |
| banner | `Dashboard_Banner.cfg` | `Inv_BannerHasLastSeen` violated by the initial state | 384 |
| rollup | `Dashboard_Rollup.cfg` (`--no-deadlock`: a written interval is final) | `Inv_RollupOneNode` violated | 1 920 |
| SCN-300 | `Dashboard_SCN300.cfg` | trap violated: reachable ✔ | 8 |
| SCN-301 | `Dashboard_SCN301.cfg` | **trap not violated: scenario impossible** (F-1) | 40 |
| SCN-302 | `Dashboard_SCN302.cfg` | trap violated: reachable ✔ | 23 168 |
| SCN-305 | `Dashboard_SCN305.cfg` | trap violated: reachable ✔ | 23 392 |
| SCN-308 | `Dashboard_SCN308.cfg` | trap violated in the given state: reachable ✔ | 256 |

How to read the access results: the authorization sentences (INV-300, INV-301, INV-302, INV-307, INV-308, REQ-303, REQ-304, REQ-305, REQ-300) are encoded as rules on the outcome of a single request. TLC checks, in every reachable state, whether **some** outcome (authenticated or not; 200/401/403/other) satisfies all of them at once. A violation means that, for that request in that state, every possible response breaks at least one `must`.

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | contradiction | high | REQ-300, INV-301, SCN-301 | Anonymous access in Development cannot be served: INV-301 requires a permission that anonymous requests never have |
| F-2 | contradiction | high | REQ-304, REQ-305, INV-308 | A valid API key from a locked-out address must be both accepted and rejected |
| F-3 | gap | medium | REQ-304, INV-308 | With API keys but no basic auth, failed key attempts are counted but nothing ever locks out |
| F-4 | ambiguity | medium | INV-308, REQ-305, REQ-339 | "Expired" can mean state Expired or "expiresAt has passed"; under the second reading the rules conflict |
| F-5 | ambiguity | medium | REQ-301, REQ-334, REQ-300, hosting REQ-18 | "All startup checks" in hosting REQ-18 does not name the dashboard checks; a production dashboard without auth can start |
| F-10 | ambiguity | medium | REQ-300, REQ-301 | "Authorization requirement" is undefined for RequireBasicAuth() and RequireApiKey() |
| F-8 | ambiguity | medium | REQ-314, INV-305, REQ-332, hosting REQ-40 | Which nodes sample, prune samples and compute rollups is unclear against "no background duty without a worker" |
| F-6 | gap | low | REQ-341 | The no-worker banner must show "when the last worker was seen" even when none ever was |
| F-7 | contradiction | low | INV-305 | A rollup lease that expires mid-computation lets two nodes compute and write the same interval |
| F-9 | gap | low | REQ-322, REQ-323, REQ-320, REQ-305 | Launch attribution: recurring launches store no principal; key-authenticated launches have none defined |
| F-11 | ambiguity | low | REQ-326, jobs REQ-142 | Bulk cancel/delete by tag: which jobs match and what is reported when a job changes state during the action |
| F-12 | ambiguity | low | REQ-320, REQ-321, REQ-322, hosting REQ-51, hosting REQ-52 | Can a dashboard-only node (no client registered) launch, requeue or cancel jobs? |
| F-13 | modeling | low | REQ-341, integrations REQ-411 | `uses` does not list `integrations`, but REQ-341 depends on NodeLostAfter defined there |

---

## F-1 · contradiction · high: Anonymous access in Development cannot be served
<!-- finding: contradiction | Inv_RulesConsistent_Anon | REQ-300,INV-301,SCN-301 -->

**Requirements involved**
- REQ-300: *While a node is starting, if the dashboard is mapped without an authorization requirement and the environment is Development, then the system shall allow anonymous access and log a notice saying so.*
- INV-301: *The system shall serve a dashboard page, JSON API read or MCP read only to a request with view or operate permission, and perform an operate action (…) only for a request with operate permission.*
- REQ-302 / REQ-306: permission levels are granted by the configured policies, roles or claims, and none of them applies to an anonymous request.
- SCN-301 *then*: *Anonymous requests are served and one notice was logged.*

**What happens** (TLC counter-example, `Inv_RulesConsistent_Anon`, 3 states; SCN-301 trap never violated in 40 states)
1. The app runs in Development with `MapBellhopDashboard("/jobs")` and no authorization (SCN-301's given).
2. The node is starting. REQ-300 allows anonymous access and logs the notice.
3. The node is marked running (hosting REQ-18).
4. An anonymous browser opens the overview. REQ-300 says it must be served. INV-301 says a page is served only to a request with view or operate permission, and an anonymous request has neither. **No response satisfies both.** So SCN-301's outcome ("anonymous requests are served") is unreachable.

Related case, found in the static read: **outside Development with `AllowAnonymous()` called**, REQ-301 does not fire, because AllowAnonymous() was called. REQ-300 does not fire either, because the environment is not Development. No requirement grants anonymous access, so the opt-in that TECH-88 and REQ-301's message point to has no defined effect.

**Why:** REQ-300 grants *access* but no *permission level*, while INV-301 is phrased purely in permission levels. Nothing says what level anonymous access carries, or whether anonymous users may run operate actions such as launching jobs or creating API keys.

**Options**
1. *(recommended)* Make anonymous access a permission grant. REQ-300 grants operate in Development, and a new REQ-342 grants view (or operate, the owner decides) when AllowAnonymous() is called outside Development. INV-301 stays as it is and now holds.
2. Exempt anonymous access in INV-301: "…only to a request with view or operate permission or while anonymous access is allowed". This is simpler, but it leaves operate actions undefined for anonymous users, and AllowAnonymous() outside Development still has no requirement.
3. Retire REQ-300 so Development also needs RequireAuthorization() or AllowAnonymous(). The first-run experience gets worse, and F-1's AllowAnonymous() case still needs option 1's REQ-342.

**Ready to apply (option 1)**
```json
{ "id": "REQ-300", "ears": { "while": "a node is starting",
    "if": "the dashboard is mapped without an authorization requirement and the environment is Development",
    "shall": "treat anonymous requests as having operate permission and log a notice saying so" } },
{ "id": "REQ-342", "kind": "transition", "status": "proposed", "strength": "must",
  "entity": "hosting.Node", "actor": "system", "from": ["Starting"], "to": ["Starting"],
  "ears": { "while": "a node is starting",
    "if": "the dashboard is mapped without an authorization requirement, AllowAnonymous() was called and the environment is not Development",
    "shall": "treat anonymous requests as having view permission and log a warning that the dashboard is open to anonymous viewers" },
  "mentions": ["DashboardEndpoint.environment", "DashboardEndpoint.authRequirement", "DashboardEndpoint.allowAnonymous"],
  "notes": "Level for AllowAnonymous() outside Development to be confirmed by the owner (view or operate)." }
```

---

## F-2 · contradiction · high: A valid API key from a locked-out address must be both accepted and rejected
<!-- finding: contradiction | Inv_RulesConsistent_Key | REQ-304,REQ-305,INV-308 -->

**Requirements involved**
- REQ-304: *Where basic authentication is enabled, if a user, or a client address, has failed MaxFailedLogins times within LoginLockoutWindow, then the system shall reject further attempts for that user or from that address until the window has passed, even with the right password.*
- INV-308: *If a request presents an API key that is revoked, expired or unknown, then the system shall respond 401 Unauthorized and count it as a failed login for the client address.*
- REQ-305: *Where RequireApiKey() is enabled, when a script or the CLI calls the JSON API with an active API key, the system shall authenticate it with the scope assigned to that key.*
- Entity `LoginAttempt`: *A basic-auth or API-key credential check.*

**What happens** (TLC counter-example, `Inv_RulesConsistent_Key`, 5 states; MaxFailedLogins = 2 in the model, 5 in the policy)
1. The dashboard has RequireBasicAuth() and RequireApiKey(). The node is running.
2. Someone at the office's shared address mistypes a password or pastes an old key. That counts as one failed login for the address (REQ-304, INV-308).
3. Olga signs in with basic auth and creates key k1 with operate scope for the CI job (REQ-337).
4. A second failure comes from the same address, so the address has reached MaxFailedLogins (REQ-304).
5. The CI script, behind the same NAT address, calls the JSON API with the active key k1. REQ-305 says authenticate it. REQ-304 says reject further attempts from that address. **No response satisfies both.**

The same state can be reached by an attacker deliberately sending MaxFailedLogins junk keys from the CI's address. That is a cheap lockout of every key-authenticated script.

**Why:** REQ-304 counts every credential check per address, including API-key checks through INV-308, and rejects all further attempts. REQ-305 authenticates every active key unconditionally. Neither says which one wins.

**Options**
1. *(recommended)* Make the lockout win: add an `if` to REQ-305. A locked address cannot use keys until the window passes. This is consistent with INV-308 counting key failures; the cost is that a noisy neighbour on a shared address can block CI for 15 minutes.
2. Exempt valid keys: REQ-304 rejects only basic-auth attempts, and API keys are never locked out. Key guessing is then unlimited (see F-3), which is acceptable only if keys are long random secrets (an NFR).
3. Separate counters: key failures lock out key attempts only, and password failures lock out password attempts only. This needs a new requirement for the key counter.

**Ready to apply (option 1)**
```json
{ "id": "REQ-305", "ears": { "where": "RequireApiKey() is enabled",
    "when": "a script or the CLI calls the JSON API with an active API key",
    "if": "the client address is not locked out under REQ-304",
    "shall": "authenticate it with the scope assigned to that key" },
  "dependsOn": ["REQ-304"] }
```

---

## F-3 · gap · medium: Failed API-key attempts are counted but never lock anything out without basic auth
<!-- finding: gap | REQ-304 | REQ-304,INV-308 -->

**Requirements involved**
- INV-308: *…respond 401 Unauthorized and count it as a failed login for the client address.*
- REQ-304: *Where basic authentication is enabled, if … a client address has failed MaxFailedLogins times … then the system shall reject further attempts…*

**What happens** (concrete example; the reachable state appears in the main run with `basicAuth = FALSE`, `apiKeyAuth = TRUE`, `failAddr = 2`)
1. The dashboard uses RequireAuthorization() for browsers and RequireApiKey() for the CLI, with no basic auth.
2. A script on one address tries 10 000 guessed keys. Each gets 401 and is counted against the address (INV-308).
3. The count passes MaxFailedLogins, but REQ-304 applies only "where basic authentication is enabled", so attempt 10 001 is checked like the first. The counting INV-308 requires has no effect.

**Why:** the lockout condition was written for basic auth (owner decision 2026-11-06), and the key-lifecycle decision added key counting without widening the lockout's `where`.

**Options**
1. *(recommended)* Widen REQ-304's `where` to "basic authentication or RequireApiKey() is enabled" (together with F-2 option 1).
2. Keep the lockout for basic auth only, and drop "count it as a failed login" from INV-308. Brute-force resistance then rests on key entropy (state it as an NFR).

**Ready to apply (option 1)**
```json
{ "id": "REQ-304", "ears": { "where": "basic authentication is enabled with RequireBasicAuth() or RequireApiKey() is enabled",
    "if": "a user, or a client address, has failed MaxFailedLogins times within LoginLockoutWindow",
    "shall": "reject further attempts for that user or from that address until the window has passed, even with the right password or an active API key" } }
```

---

## F-4 · ambiguity · medium: "Expired" key: state Expired, or past its expiresAt?
<!-- finding: ambiguity | Inv_RulesConsistent_Key | INV-308,REQ-305,REQ-339 -->

**Requirements involved**
- INV-308: *If a request presents an API key that is revoked, expired or unknown, then the system shall respond 401 Unauthorized…*
- REQ-305: *…when a script or the CLI calls the JSON API with an active API key, the system shall authenticate it…*
- REQ-339: *While an API key is active, when its expiresAt has passed, the system shall mark the key expired.*

**What happens** (TLC counter-example under reading B, `Dashboard_A9.cfg`, `Inv_RulesConsistent_Key`, 4 states, no failed logins involved)
1. RequireApiKey() is enabled and the node is running.
2. Olga creates key k with a 1-day expiry (REQ-337), as in SCN-307's given.
3. k's expiresAt passes. REQ-339 has not run yet, so k is still in state Active.
4. The CLI calls the JSON API with k. REQ-305 says authenticate it, because k is *active*. INV-308 says respond 401, because k is *expired* in the sense of being past its expiresAt. **No response satisfies both.**

Under reading A (expired = state Expired, the main run), the rules agree and SCN-307 holds. In that reading, though, a key keeps working after its expiresAt until REQ-339 gets round to marking it, and no requirement bounds that delay.

**Options**
1. *(recommended)* Decide at request time: REQ-305 authenticates only a key whose expiresAt has not passed, and REQ-339 becomes bookkeeping for the list page. The key stops working at the exact instant it expires, whatever the sweep does.
2. Keep the state reading and add an NFR bounding the lag between expiresAt and REQ-339 (for example ≤ 1 min).

**Ready to apply (option 1)**
```json
{ "id": "REQ-305", "ears": { "where": "RequireApiKey() is enabled",
    "when": "a script or the CLI calls the JSON API with an active API key whose expiresAt has not passed",
    "shall": "authenticate it with the scope assigned to that key" },
  "mentions": ["DashboardRequest.principal", "ApiKey.Active", "ApiKey.scope", "ApiKey.expiresAt"] }
```
(If F-2 option 1 is also applied, keep its `if` clause.)

---

## F-5 · ambiguity · medium: Hosting's "all startup checks" does not name the dashboard checks
<!-- finding: ambiguity | Inv_UnsafeConfigNeverRuns | REQ-300,REQ-301,REQ-334,hosting.REQ-18 -->

**Requirements involved**
- hosting REQ-18: *While a node is starting, when the store is reachable, the stored schema version is accepted (REQ-23, REQ-43) and all startup checks have passed, the system shall mark the node running…* (REQ-19 has the same trigger.)
- REQ-301: *While a node is starting, if the dashboard is mapped without an authorization requirement, AllowAnonymous() was not called and the environment is not Development, then the system shall stop the node from starting…*
- REQ-334: *While a node is starting, if basic authentication is enabled and a configured password is not a supported salted hash, then the system shall stop the node from starting…*

**What happens** (TLC counter-example under reading B, `Dashboard_A2.cfg`, `Inv_UnsafeConfigNeverRuns`, 2 states; also reproduced with SCN-300's given)
1. Production, `MapBellhopDashboard("/jobs")` with no authorization and no AllowAnonymous() (SCN-300's given). The node is starting, so REQ-301 and hosting REQ-18 are both enabled.
2. Hosting REQ-18 fires first (store reachable, schema accepted, and nothing says the dashboard checks are "startup checks"), so the node is marked running. REQ-301 applies only "while a node is starting", so it can no longer fire. **A production dashboard with no authorization is serving.**

Under reading A (main run, `DashChecksInStartup = TRUE`), `Inv_UnsafeConfigNeverRuns` holds and SCN-300 is reachable. The same ordering question decides whether REQ-300's notice is always logged before the node runs.

**Options**
1. *(recommended)* Name the checks in hosting REQ-18 and REQ-19 (same trigger), so the dashboard checks precede "running" by definition.
2. Add a dashboard-side invariant instead: *The system shall never mark a node running while REQ-301 or REQ-334 applies.* This keeps hosting untouched, but "startup checks" stays undefined for other modules.

**Ready to apply (option 1, in `hosting.json`; apply the same `when` to REQ-19)**
```json
{ "id": "REQ-18", "ears": { "while": "a node is starting",
    "when": "the store is reachable, the stored schema version is accepted (REQ-23, REQ-43) and all startup checks have passed, including option validation (REQ-9) and the dashboard checks (dashboard REQ-300, REQ-301, REQ-334)",
    "shall": "mark the node running and, where the worker is registered, start the worker and its background duties" } }
```

---

## F-10 · ambiguity · medium: What counts as "an authorization requirement"?
<!-- finding: ambiguity | authorization requirement | REQ-300,REQ-301 -->

**Requirements involved**
- REQ-300 / REQ-301: *…if the dashboard is mapped without an authorization requirement…*
- REQ-303 (RequireBasicAuth()), REQ-305 (RequireApiKey()), REQ-306 (RequireRole/RequireClaim); TECH-88 (RequireAuthorization on the endpoint builder).

**What happens** (concrete example)
- Development, the app calls only `RequireApiKey()` so the CLI works locally. If RequireApiKey() is *not* an authorization requirement, REQ-300 opens the whole dashboard to anonymous browsers despite the key requirement. If it *is*, browsers have no way in at all.
- Production with only `RequireBasicAuth()`: under one reading REQ-301 stops startup ("no authorization requirement"); under the other it starts normally.

The model used reading A-1 (any of RequireAuthorization/Role/Claim, RequireBasicAuth, RequireApiKey counts). The F-1 and F-5 results hold under that reading.

**Options**
1. *(recommended)* Spell the list out in REQ-300, REQ-301 and REQ-342 (F-1): "mapped without RequireAuthorization, RequireRole, RequireClaim or RequireBasicAuth". Leave RequireApiKey() out, because it authenticates scripts, not browsers.
2. Count every scheme, RequireApiKey() included (the model's reading), and add a glossary entry.

**Ready to apply (option 1)**
```json
{ "id": "REQ-301", "ears": { "while": "a node is starting",
    "if": "the dashboard is mapped without RequireAuthorization, RequireRole, RequireClaim or RequireBasicAuth, AllowAnonymous() was not called and the environment is not Development",
    "shall": "stop the node from starting with a message that says how to add authorization or opt in to anonymous access" } }
```
(Apply the same `if` wording to REQ-300.)

---

## F-8 · ambiguity · medium: Which nodes sample, prune samples and compute rollups?
<!-- finding: ambiguity | node scope of dashboard duties | REQ-314,INV-305,REQ-332,hosting.REQ-40 -->

**Requirements involved**
- REQ-314: *While a node is running, the system shall take a metrics sample every NodeSampleInterval…, write it in one batched store write per interval and keep samples for NodeSampleRetention…*
- INV-305: *The system shall compute each rollup interval on exactly one node, which holds a lease in the store…*
- hosting REQ-40: *While a node has no worker registered, the system shall run no background duty on that node: no … retention cleanup, …*

**What happens** (concrete example; REQ-314 and REQ-332 were not modeled, because they depend on real durations)
1. A web API runs with the client and the dashboard. Its only worker service is stopped (SCN-308's situation).
2. REQ-314 says the web node, which is running, samples every 15 s. Whether that sampling is a "background duty" that hosting REQ-40 forbids on a node without a worker is not stated.
3. Deleting samples older than 7 days is retention cleanup, which hosting REQ-40 forbids on this node. No worker is alive, so nobody prunes.
4. Rollups (INV-305) need "exactly one node". If rollups are a background duty, no node computes them while the workers are down, and the insights page shows a hole exactly when the operator is investigating.

**Options**
1. *(recommended)* Every running node samples **itself**. Sample pruning and rollups are worker background duties, added to hosting REQ-40's list, and the gap during a worker outage is accepted.
2. Every running node may do all three (lease-based, as INV-305 already says). Amend hosting REQ-40 to exempt the dashboard duties.

**Ready to apply (option 1)**
```json
{ "id": "REQ-314", "ears": { "while": "a node is running, whether or not the worker is registered",
    "shall": "take a metrics sample of that node every NodeSampleInterval, 15 s by default, and write it in one batched store write per interval" } },
{ "id": "REQ-343", "kind": "invariant", "status": "proposed", "strength": "must", "entity": "NodeSample",
  "ears": { "where": "the worker is registered on a node", "shall": "delete node samples older than NodeSampleRetention, 7 days by default, as one of that node's background duties" },
  "mentions": ["NodeSample.takenAt", "hosting.Node.hasWorker"] }
```

---

## F-6 · gap · low: The no-worker banner must show a "last seen" time that may not exist
<!-- finding: gap | Inv_BannerHasLastSeen | REQ-341 -->

**Requirements involved**
- REQ-341: *While no node with the worker registered has sent a heartbeat within NodeLostAfter, the system shall show a banner on every dashboard page saying that no worker is running, …, with the time the last worker was seen.*

**What happens** (TLC, `Dashboard_Banner.cfg`, `Inv_BannerHasLastSeen` violated by the initial state)
1. A new deployment has a web API with the client and the dashboard, and the worker service has never been deployed. This is exactly the silent-failure case (P6) the requirement was written for.
2. The banner must be shown, together with "the time the last worker was seen". No worker was ever seen, so there is no such time.

**Options**
1. *(recommended)* Say what to show in that case.
2. Make the time optional: "…and, if a worker was ever seen, the time it was last seen".

**Ready to apply (option 1)**
```json
{ "id": "REQ-341", "ears": { "while": "no node with the worker registered has sent a heartbeat within NodeLostAfter",
    "shall": "show a banner on every dashboard page saying that no worker is running, so enqueued and scheduled jobs will not run, with the time the last worker was seen or, if none was ever seen, that no worker has connected to this store" } }
```

---

## F-7 · contradiction · low: An expired rollup lease lets two nodes compute the same interval
<!-- finding: contradiction | Inv_RollupOneNode | INV-305 -->

**Requirements involved**
- INV-305 (should): *The system shall compute each rollup interval on exactly one node, which holds a lease in the store, and write it in one batched write.*

**What happens** (TLC counter-example, `Dashboard_Rollup.cfg`, `Inv_RollupOneNode`, 4 states)
1. Node n1 takes the rollup lease for interval 10:00–10:01 and starts computing.
2. n1 pauses (a GC pause, or a slow query) longer than the lease, and the lease expires in the store.
3. Node n2 sees no lease, takes it and computes the same interval. **Two nodes are computing the interval.** Nothing says n1 must check that it still holds the lease before its batched write, so both writes land.

**Why:** a lease is time-limited, but the sentence ties "exactly one" to holding the lease without saying the write is fenced by it.

**Options**
1. *(recommended)* Fence the write: a node writes the interval only if it still holds the lease (an atomic compare in the store), so at most one write lands. Duplicate *computation* stays possible and harmless.
2. Make the write idempotent (the second write replaces the first with the same numbers), and weaken "exactly one node" to "at most one stored result".

**Ready to apply (option 1)**
```json
{ "id": "INV-305", "ears": { "shall": "compute each rollup interval on a node that holds the interval's lease in the store, and write it in one batched write that succeeds only if that node still holds the lease" } }
```

---

## F-9 · gap · low: Launch attribution is incomplete
<!-- finding: gap | launch attribution | REQ-322,REQ-323,REQ-320,REQ-305 -->

**Requirements involved**
- REQ-320 / REQ-321: *…store the operator's principal name on it.*
- REQ-322: *When an operator submits a valid launch form with Make recurring and a schedule, the system shall create a runtime-defined recurring job with the form's payload.* (No principal.)
- REQ-323: *The system shall list recent launches with who launched which job and when.*
- REQ-305: key-authenticated requests have a scope, but no principal name is defined.

**What happens** (concrete example; in the model, `LaunchRecurring` stores `by = NULL` and key launches store a placeholder, A-11)
1. Olga submits the launch form with Make recurring. REQ-322 creates the recurring job and stores nothing about Olga, so REQ-323 has no "who" to list.
2. The CI script with an operate-scope key launches SendReport through the JSON API, which INV-301 allows. REQ-320 says to store "the operator's principal name", but a key has no defined principal name (its name? its creator?).

**Options**
1. *(recommended)* REQ-322 also stores the principal name, and REQ-305 defines a key's principal name as "apikey:<name>".
2. Limit REQ-323 to Run now and Schedule for launches, and leave key launches unattributed.

**Ready to apply (option 1)**
```json
{ "id": "REQ-322", "ears": { "when": "an operator submits a valid launch form with Make recurring and a schedule",
    "shall": "create a runtime-defined recurring job with the form's payload and store the operator's principal name on it" } },
{ "id": "REQ-305", "ears": { "where": "RequireApiKey() is enabled",
    "when": "a script or the CLI calls the JSON API with an active API key",
    "shall": "authenticate it with the scope assigned to that key and the principal name \"apikey:\" followed by the key's name" } }
```

---

## F-11 · ambiguity · low: Bulk actions by tag when jobs change state meanwhile
<!-- finding: ambiguity | bulk by tag | REQ-326,jobs.REQ-142 -->

**Requirements involved**
- REQ-326: *When an operator runs a bulk requeue, cancel or delete by tag, the system shall apply the action to every job with that tag for which the action is allowed in its current state.*
- jobs REQ-142 (bulk requeue of dead letters): *…each matching dead-lettered job again in its own atomic step…, and return how many were requeued and how many were skipped because their state changed meanwhile.*

**What happens** (concrete example)
1. Olga cancels by tag `order-42`, which matches 300 jobs.
2. While the action runs, one matching job moves from Enqueued to Processing (so cancel now only signals its token, jobs REQ-135), and a new job tagged `order-42` is enqueued.
3. REQ-326 says "every job with that tag" but does not say at what instant the set is taken, whether each job is its own atomic step, or what Olga is told. Jobs REQ-142 answers all three, but only for requeue of dead letters.

The note on REQ-326 says the allowed states are "open in the jobs module (REQ-143, REQ-144)". Those are now decided, so the note is stale.

**Options**
1. *(recommended)* Mirror jobs REQ-142: match at the start, one atomic step per job, and report how many were applied and how many skipped.
2. Make the whole bulk action one transaction. That is simpler to describe but heavy on large tags, and impossible on Redis across shards.

**Ready to apply (option 1)**
```json
{ "id": "REQ-326", "ears": { "when": "an operator runs a bulk requeue, cancel or delete by tag",
    "shall": "apply the action to each job that has the tag when the action starts, in its own atomic step, where the action is allowed in the job's state at that step, and return how many jobs were changed and how many were skipped" },
  "notes": "Allowed states: jobs REQ-134, REQ-135, REQ-141, REQ-143, REQ-144." }
```

---

## F-12 · ambiguity · low: Can a dashboard-only node launch or change jobs?
<!-- finding: ambiguity | dashboard without client | REQ-320,REQ-321,REQ-322,hosting.REQ-51,hosting.REQ-52 -->

**Requirements involved**
- hosting REQ-51: *The system shall serve the dashboard on a node exactly when the application maps it, whether or not the client or the worker is registered.*
- hosting REQ-52: *…register the client (AddClient), the worker (AddWorker), both or neither, and map the dashboard independently, where registering the worker also makes the client available…*
- REQ-320 to REQ-322: the dashboard enqueues, schedules or creates jobs.

**What happens** (concrete example)
1. An ops portal calls AddBellhop and MapBellhopDashboard but neither AddClient nor AddWorker.
2. Olga, with operate permission, submits Run now. REQ-320 says enqueue the job, but REQ-52 makes the client (the thing that enqueues) available only through AddClient or AddWorker. Whether the dashboard brings its own enqueue path, or the launch page should be disabled, is not stated. The same applies to requeue, cancel and trigger.

**Options**
1. *(recommended)* Mapping the dashboard makes the operate actions available on its own (the dashboard writes through the store). State this as a dashboard invariant.
2. Without the client, the dashboard hides launch and the other operate actions and says why.

**Ready to apply (option 1)**
```json
{ "id": "INV-309", "kind": "invariant", "status": "proposed", "strength": "must", "entity": "DashboardEndpoint",
  "ears": { "shall": "offer and perform launches and other operate actions on a node that maps the dashboard whether or not the client or the worker is registered on that node" },
  "mentions": ["hosting.Node.hasClient", "hosting.Node.hasWorker"] }
```

---

## F-13 · modeling · low: `uses` omits `integrations`
<!-- finding: modeling | uses | REQ-341,integrations.REQ-411 -->

REQ-341 depends on NodeLostAfter, which is defined by integrations REQ-411 (see REQ-341's note). `dashboard.json` lists `"uses": ["hosting", "jobs", "recurring"]`, so impact analysis will not flag REQ-341 when NodeLostAfter changes. The model abstracts NodeLostAfter away (A-14), so this does not change any result above.

**Ready to apply**
```json
{ "uses": ["hosting", "jobs", "recurring", "integrations"] }
```
Alternatively, move NodeLostAfter to hosting, where heartbeats live, and have integrations use it from there.

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.

| # | Assumption | Affects |
|---|---|---|
| A-1 | "An authorization requirement" means any of RequireAuthorization/Role/Claim, RequireBasicAuth or RequireApiKey (see F-10) | REQ-300, REQ-301 |
| A-2 | Main run: hosting REQ-18's "all startup checks" include REQ-301 and REQ-334, and REQ-300 runs first. The other reading is checked in `Dashboard_A2.cfg` (F-5) | REQ-300, REQ-301, REQ-334 |
| A-3 | REQ-300 (Starting → Starting) fires once per startup | REQ-300, SCN-301 |
| A-4 | REQ-303's "accept only …" is also read as "accept": a configured user with the right password, from an address that is not locked out, is authenticated | REQ-303 |
| A-5 | The authorization sentences are rules on each request's outcome (authenticated flag plus 200/401/403/other); any outcome that satisfies all of them is allowed. An authenticated request with the level it needs, not refused by INV-302 or INV-307, is served. Launches and key management happen only on a request that could be served (INV-301 is the shared authorization step, as the notes on REQ-337 and INV-304 state) | INV-300…INV-308, REQ-302…REQ-306, REQ-319…REQ-322, REQ-337, REQ-338 |
| A-6 | Policies, roles and claims are abstracted: Olga has operate, Vic has view. Operate includes view (glossary) | REQ-302, REQ-306 |
| A-7 | Interactive users exist only where RequireAuthorization/Role/Claim or basic auth is configured; they are authenticated exactly when their session or password is valid. Anonymous requests are never authenticated, and API keys authenticate only where RequireApiKey() is enabled | REQ-305, INV-301 |
| A-8 | One client address and one per-address failure counter (the per-user counter adds no interaction with any other rule). The counter saturates at MaxFailedLogins = 2, and rejected attempts during a lockout are not counted again | REQ-304, REQ-335, INV-308 |
| A-9 | Main run: "expired" in INV-308 means state Expired. `Dashboard_A9.cfg` uses "expiresAt has passed" (F-4) | INV-308, SCN-307 |
| A-10 | The lockout window passes at a nondeterministic moment and resets the address counter (no clock; 15 minutes is not judged) | REQ-304, REQ-336 |
| A-11 | A launch authenticated by an API key is attributed to a placeholder principal "apiKey" (F-9) | REQ-320, REQ-321 |
| A-12 | A key's expiresAt passes at a nondeterministic moment unless the key never expires; 90 days is not judged | REQ-339, REQ-340 |
| A-13 | A revoked or expired key's slot is freed and then behaves as an unknown key (modeling artefact) | INV-308 |
| A-14 | Worker heartbeats are an alive/lost flag with no clock. Nothing in this module claims jobs, so enqueued jobs stay enqueued | REQ-341, SCN-308 |
| A-15 | A rollup lease can expire while its holder still computes, and the write may or may not check the lease (the sentence is silent) | INV-305 |
| A-16 | Response codes for refusals that INV-300 and INV-308 don't cover (a lockout, ReadOnly, an unauthenticated request without a key) are left open | INV-302, REQ-304 |
| A-17 | Hosting's store and schema checks are treated as passed. Bounds: 1 API key slot, 1 job slot, 1 recurring slot, 1 worker node, 2 rollup nodes, 1 rollup interval. The access, banner and rollup parts are checked in separate cfgs | all |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-300, REQ-301, REQ-302, REQ-303, REQ-304, REQ-305, REQ-306, REQ-319, REQ-320, REQ-321, REQ-322, REQ-334, REQ-335, REQ-336, REQ-337, REQ-338, REQ-339, REQ-340, REQ-341, INV-300, INV-301, INV-302, INV-305, INV-307, INV-308, SCN-300 … SCN-308 (all 9) | **No state change to explore, checked by inspection:** REQ-307, REQ-308, REQ-309, REQ-310, REQ-311, REQ-312, REQ-313, REQ-315, REQ-316, REQ-317, REQ-323, REQ-325, REQ-327, REQ-328, REQ-329, REQ-330, REQ-331, REQ-333, INV-304, INV-306 · **Strength may:** REQ-318, REQ-324 · **Needs real quantities:** REQ-314 (see F-8), REQ-332 · **Depends on the jobs state machine, not encoded:** REQ-326 (see F-11) · **Retired:** INV-303 |

## Next
Apply the chosen options to `specs/dashboard.json` (and `hosting.json` for F-5, F-8) with the `refiner-requirements` skill, which validates and diffs, then run this skill again. Findings whose fingerprint disappears are listed as resolved in the next report.
