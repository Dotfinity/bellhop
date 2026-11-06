---------------------------- MODULE Dashboard ----------------------------
\* Generated from specs/dashboard.json (specHash ce16de70435f) — edit the requirements, not this file.
\* Every action/property carries an @req comment naming the requirement it encodes.
\* Assumptions A-n refer to the table in specs/dashboard.findings.md.
\*
\* The module has three independent parts, switched on per cfg with the constant Parts so that
\* their state spaces are not multiplied together:
\*   "access"  startup auth checks, request authorization, API keys, launch     (Dashboard.cfg)
\*   "banner"  the no-worker banner                                            (Dashboard_Banner.cfg)
\*   "rollup"  the insights rollup lease                                       (Dashboard_Rollup.cfg)
EXTENDS Naturals, FiniteSets

CONSTANTS Olga, Vic,             \* interactive principals: Olga has operate, Vic has view only (A-6)
          KeyIds,                \* ApiKey slots (an unused slot is an "unknown" key)
          JobIds,                \* jobs.Job slots for launches
          WorkerNodes,           \* hosting.Node instances with the worker registered (banner part)
          RollupNodes,           \* nodes that may compute a rollup interval (rollup part)
          MaxFailedLogins,       \* @req REQ-335  (5 in the policy; 2 in the model)
          DashChecksInStartup,   \* A-2: hosting REQ-18 "all startup checks" includes REQ-300/301/334
          ExpiredMeansTime,      \* A-9: INV-308 "expired" = expiresAt passed (TRUE) or state Expired (FALSE)
          Parts,
          NULL

ASSUME MaxFailedLogins \in Nat \ {0}                \* @req REQ-335
ASSUME DashChecksInStartup \in BOOLEAN /\ ExpiredMeansTime \in BOOLEAN
ASSUME Parts \subseteq {"access", "banner", "rollup"}

Principals == {Olga, Vic}
Perm(p)    == IF p = Olga THEN "operate" ELSE "view"   \* REQ-302/REQ-306: policies grant levels; abstracted (A-6)

VARIABLES
  cfg,          \* DashboardEndpoint + startup configuration, fixed after Init
  node,         \* hosting.Node of the dashboard process: Starting | Running | StartupFailed
  anonAllowed,  \* REQ-300 effect: anonymous access allowed
  noticeLogged, \* REQ-300 effect: notice logged
  failAddr,     \* LoginAttempt.failedCount for the (single) client address, saturating at MaxFailedLogins
  key,          \* ApiKey
  job,          \* jobs.Job created by launches
  recJob,       \* recurring.RecurringJob created by REQ-322
  errorsShown,  \* REQ-319: validation errors shown
  anonServed,   \* history: an anonymous request has been served (SCN-301)
  worker,       \* banner part: per worker node "absent" | "alive" | "lost"
  everSeen,     \* banner part: some worker heartbeat was ever recorded (the "last seen" time exists)
  lease,        \* rollup part: holder of the rollup lease for interval i1
  computing,    \* rollup part: nodes computing interval i1
  wrote         \* rollup part: nodes that wrote interval i1

vars == <<cfg, node, anonAllowed, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed,
          worker, everSeen, lease, computing, wrote>>

Cfgs == [env: {"Development", "Production"},
         authReq: BOOLEAN,      \* RequireAuthorization / RequireRole / RequireClaim
         allowAnon: BOOLEAN,    \* AllowAnonymous() called
         basicAuth: BOOLEAN,    \* RequireBasicAuth()
         pwHashed: BOOLEAN,     \* every configured password is a salted PBKDF2 hash
         apiKeyAuth: BOOLEAN,   \* RequireApiKey()
         readOnly: BOOLEAN]     \* ReadOnly()

KeyStatus == {"none", "Active", "Revoked", "Expired"}
KeyRec    == [status: KeyStatus, scope: {"view", "operate"}, neverExpires: BOOLEAN, expiresPassed: BOOLEAN]
EmptyKey  == [status |-> "none", scope |-> "view", neverExpires |-> FALSE, expiresPassed |-> FALSE]
JobRec    == [status: {"none", "Enqueued", "Scheduled"}, by: Principals \cup {"apiKey", NULL}]
EmptyJob  == [status |-> "none", by |-> NULL]

TypeInv ==
  /\ cfg \in Cfgs
  /\ node \in {"Starting", "Running", "StartupFailed"}
  /\ anonAllowed \in BOOLEAN /\ noticeLogged \in BOOLEAN /\ errorsShown \in BOOLEAN /\ anonServed \in BOOLEAN
  /\ failAddr \in 0..MaxFailedLogins
  /\ key \in [KeyIds -> KeyRec]
  /\ job \in [JobIds -> JobRec]
  /\ recJob \in [status: {"none", "Active"}, by: Principals \cup {"apiKey", NULL}]
  /\ worker \in [WorkerNodes -> {"absent", "alive", "lost"}]
  /\ everSeen \in BOOLEAN
  /\ lease \in RollupNodes \cup {NULL}
  /\ computing \subseteq RollupNodes /\ wrote \subseteq RollupNodes

-----------------------------------------------------------------------------
\* Startup (part "access")

\* A-1: "an authorization requirement" = any of RequireAuthorization/Role/Claim, RequireBasicAuth, RequireApiKey.
HasAuthReq == cfg.authReq \/ cfg.basicAuth \/ cfg.apiKeyAuth
Cond300 == cfg.env = "Development" /\ ~HasAuthReq
Cond301 == ~HasAuthReq /\ ~cfg.allowAnon /\ cfg.env # "Development"
Cond334 == cfg.basicAuth /\ ~cfg.pwHashed

\* @req REQ-300  While starting, Development + no auth requirement: allow anonymous access and log a notice.
\*               Fires once (A-3).
AllowAnonymousInDev ==
  /\ "access" \in Parts
  /\ node = "Starting" /\ Cond300 /\ ~anonAllowed
  /\ anonAllowed' = TRUE /\ noticeLogged' = TRUE
  /\ UNCHANGED <<cfg, node, failAddr, key, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* @req REQ-301  While starting, no auth requirement, no AllowAnonymous(), not Development: stop the node.
FailNoAuthorization ==
  /\ "access" \in Parts
  /\ node = "Starting" /\ Cond301
  /\ node' = "StartupFailed"
  /\ UNCHANGED <<cfg, anonAllowed, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* @req REQ-334  While starting, basic auth with a password that is not a supported salted hash: stop the node.
FailUnhashedPassword ==
  /\ "access" \in Parts
  /\ node = "Starting" /\ Cond334
  /\ node' = "StartupFailed"
  /\ UNCHANGED <<cfg, anonAllowed, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* hosting REQ-18 (context, not this module): mark the node running when "all startup checks have passed".
\* Store/schema checks abstracted as passed. Whether the dashboard checks count is A-2 (DashChecksInStartup).
StartupChecksPassed == DashChecksInStartup => (~Cond301 /\ ~Cond334 /\ (Cond300 => anonAllowed))
MarkRunning ==
  /\ "access" \in Parts
  /\ node = "Starting" /\ StartupChecksPassed
  /\ node' = "Running"
  /\ UNCHANGED <<cfg, anonAllowed, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

-----------------------------------------------------------------------------
\* Requests (part "access"). The authorization sentences are encoded as rules that constrain the
\* outcome of one request; a request is handled with ANY outcome that satisfies every rule (A-5).
\* Inv_RulesConsistent_* asks TLC whether such an outcome always exists.

Creds ==
  {[kind |-> "anon", p |-> NULL, ok |-> FALSE, k |-> NULL]}
  \cup {[kind |-> "user", p |-> p, ok |-> b, k |-> NULL] : p \in Principals, b \in BOOLEAN}   \* ok = right password / valid session
  \cup {[kind |-> "key", p |-> NULL, ok |-> FALSE, k |-> k] : k \in KeyIds}                 \* slot "none" = unknown key
Actions  == {"read", "operate", "keyMgmt"}   \* keyMgmt = create or revoke an API key (an operate action, INV-301)
\* Interactive user credentials exist only where some interactive scheme is configured (A-7).
Reqs == {r \in [cred: Creds, action: Actions] :
           r.cred.kind = "user" => (cfg.authReq \/ cfg.basicAuth)}
Outcomes == [auth: BOOLEAN, code: {"200", "401", "403", "other"}]

IsAnon(r) == r.cred.kind = "anon"
IsUser(r) == r.cred.kind = "user"
IsKey(r)  == r.cred.kind = "key"
KeyOf(r)  == key[r.cred.k]
Served(o) == o.code = "200"

BadKey(r) ==
  /\ IsKey(r)
  /\ \/ KeyOf(r).status \in {"none", "Revoked", "Expired"}
     \/ ExpiredMeansTime /\ KeyOf(r).status = "Active" /\ KeyOf(r).expiresPassed
Locked(r) == cfg.basicAuth /\ (IsUser(r) \/ IsKey(r)) /\ failAddr >= MaxFailedLogins   \* A-8 (per-address only)

Level(r, o) == IF ~o.auth THEN "none"
               ELSE IF IsUser(r) THEN Perm(r.cred.p)
               ELSE IF IsKey(r) THEN KeyOf(r).scope
               ELSE "none"
Need(a) == IF a = "read" THEN {"view", "operate"} ELSE {"operate"}   \* glossary: operate includes view
HasNeed(r, o) == Level(r, o) \in Need(r.action)

\* @req INV-301  Serve reads only with view or operate; perform operate actions only with operate.
R_INV301(r, o) == Served(o) => HasNeed(r, o)
\* @req INV-302  ReadOnly(): refuse every operate action.
R_INV302(r, o) == (cfg.readOnly /\ r.action # "read") => ~Served(o)
\* @req INV-300  Authenticated but lacking the permission: 403, not 401.
R_INV300(r, o) == (o.auth /\ ~HasNeed(r, o)) => o.code = "403"
\* @req INV-307  Request authenticated by an API key that creates/revokes a key: 403, change nothing.
R_INV307(r, o) == (o.auth /\ IsKey(r) /\ r.action = "keyMgmt") => o.code = "403"
\* @req INV-308  Revoked, expired or unknown key: 401 (and counted, see Respond).
R_INV308(r, o) == BadKey(r) => (o.code = "401" /\ ~o.auth)
\* @req REQ-304  Basic auth enabled, address over MaxFailedLogins in the window: reject the attempt, even with
\*               the right credential. "Attempts" include API-key checks (LoginAttempt description).
R_REQ304(r, o) == Locked(r) => ~o.auth
\* @req REQ-305  RequireApiKey(): a call with an active key is authenticated with the key's scope.
R_REQ305(r, o) == (cfg.apiKeyAuth /\ IsKey(r) /\ KeyOf(r).status = "Active") => o.auth
\* @req REQ-303  Basic auth accepts only configured users with salted PBKDF2 hashes (and, A-4, accepts them
\*               when the password is right and the address is not locked).
R_REQ303(r, o) ==
  /\ (cfg.basicAuth /\ IsUser(r) /\ o.auth) => (r.cred.ok /\ cfg.pwHashed)
  /\ (cfg.basicAuth /\ IsUser(r) /\ r.cred.ok /\ cfg.pwHashed /\ ~Locked(r)) => o.auth
\* @req REQ-302 REQ-306  A-5: an authenticated request with the level it needs, not refused by
\*               INV-302/INV-307, is served (permission levels are granted by their policies).
R_Grant(r, o) ==
  (o.auth /\ HasNeed(r, o) /\ ~(cfg.readOnly /\ r.action # "read") /\ ~(IsKey(r) /\ r.action = "keyMgmt"))
    => Served(o)
\* @req REQ-300  Anonymous access allowed: anonymous requests are served.
R_REQ300(r, o) == (anonAllowed /\ IsAnon(r)) => Served(o)
\* A-7: authentication outside basic auth and API keys is the host's scheme; anonymous is never authenticated;
\*      keys authenticate only where RequireApiKey() is enabled.
R_Host(r, o) ==
  /\ IsAnon(r) => ~o.auth
  /\ (IsUser(r) /\ ~cfg.basicAuth) => (o.auth <=> r.cred.ok)
  /\ (IsKey(r) /\ ~cfg.apiKeyAuth) => ~o.auth

Rules(r, o) ==
  /\ R_INV301(r, o) /\ R_INV302(r, o) /\ R_INV300(r, o) /\ R_INV307(r, o) /\ R_INV308(r, o)
  /\ R_REQ304(r, o) /\ R_REQ305(r, o) /\ R_REQ303(r, o) /\ R_Grant(r, o) /\ R_REQ300(r, o) /\ R_Host(r, o)

CanServe(r) == \E o \in Outcomes : Rules(r, o) /\ Served(o)
Min(a, b) == IF a < b THEN a ELSE b

\* @req INV-308 REQ-304  Handle one request with an outcome allowed by all rules; a bad key or a wrong
\*               basic-auth password counts as a failed login for the client address.
Respond(r) ==
  /\ "access" \in Parts
  /\ node = "Running"
  /\ \E o \in Outcomes :
       /\ Rules(r, o)
       /\ failAddr' = IF BadKey(r) \/ (cfg.basicAuth /\ IsUser(r) /\ ~r.cred.ok)
                      THEN Min(failAddr + 1, MaxFailedLogins) ELSE failAddr
       /\ anonServed' = (anonServed \/ (IsAnon(r) /\ Served(o)))
  /\ UNCHANGED <<cfg, node, anonAllowed, noticeLogged, key, job, recJob, errorsShown, worker, everSeen, lease, computing, wrote>>

\* modeling artefact A-10: "within LoginLockoutWindow" / "until the window has passed" without a clock.
\* @req REQ-336 (15 minutes) is absorbed by this abstraction.
LockoutWindowPasses ==
  /\ "access" \in Parts
  /\ failAddr > 0
  /\ failAddr' = 0
  /\ UNCHANGED <<cfg, node, anonAllowed, noticeLogged, key, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

-----------------------------------------------------------------------------
\* Launch (part "access")

Launcher(r) == IF IsUser(r) THEN r.cred.p ELSE "apiKey"   \* A-11: principal name of a key-authenticated launch

\* @req REQ-319  Invalid launch form: show validation errors, create nothing.
SubmitInvalidLaunch(r) ==
  /\ "access" \in Parts
  /\ node = "Running" /\ r.action = "operate" /\ CanServe(r)
  /\ errorsShown' = TRUE
  /\ UNCHANGED <<cfg, node, anonAllowed, noticeLogged, failAddr, key, job, recJob, anonServed, worker, everSeen, lease, computing, wrote>>

\* @req REQ-320  Valid form, Run now: enqueue the job and store the operator's principal name.
LaunchRunNow(r) ==
  /\ "access" \in Parts
  /\ node = "Running" /\ r.action = "operate" /\ CanServe(r)
  /\ \E j \in JobIds : job[j].status = "none" /\ job' = [job EXCEPT ![j] = [status |-> "Enqueued", by |-> Launcher(r)]]
  /\ UNCHANGED <<cfg, node, anonAllowed, noticeLogged, failAddr, key, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* @req REQ-321  Valid form, Schedule for: schedule the job and store the operator's principal name.
LaunchSchedule(r) ==
  /\ "access" \in Parts
  /\ node = "Running" /\ r.action = "operate" /\ CanServe(r)
  /\ \E j \in JobIds : job[j].status = "none" /\ job' = [job EXCEPT ![j] = [status |-> "Scheduled", by |-> Launcher(r)]]
  /\ UNCHANGED <<cfg, node, anonAllowed, noticeLogged, failAddr, key, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* @req REQ-322  Valid form, Make recurring: create a runtime-defined recurring job (the sentence stores no principal).
LaunchRecurring(r) ==
  /\ "access" \in Parts
  /\ node = "Running" /\ r.action = "operate" /\ CanServe(r)
  /\ recJob.status = "none"
  /\ recJob' = [status |-> "Active", by |-> NULL]
  /\ UNCHANGED <<cfg, node, anonAllowed, noticeLogged, failAddr, key, job, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

-----------------------------------------------------------------------------
\* API keys (part "access")

\* @req REQ-337 REQ-340  Create a key with a scope and an optional expiry (default ApiKeyDefaultExpiry, or never).
CreateKey(r) ==
  /\ "access" \in Parts
  /\ node = "Running" /\ r.action = "keyMgmt" /\ CanServe(r)
  /\ \E k \in KeyIds, s \in {"view", "operate"}, never \in BOOLEAN :
       /\ key[k].status = "none"
       /\ key' = [key EXCEPT ![k] = [status |-> "Active", scope |-> s, neverExpires |-> never, expiresPassed |-> FALSE]]
  /\ UNCHANGED <<cfg, node, anonAllowed, noticeLogged, failAddr, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* @req REQ-338  Revoke a key: mark it revoked.
RevokeKey(r) ==
  /\ "access" \in Parts
  /\ node = "Running" /\ r.action = "keyMgmt" /\ CanServe(r)
  /\ \E k \in KeyIds : key[k].status = "Active" /\ key' = [key EXCEPT ![k].status = "Revoked"]
  /\ UNCHANGED <<cfg, node, anonAllowed, noticeLogged, failAddr, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* modeling artefact A-12: a key's expiresAt may pass at any moment (no clock); never-expiring keys excluded.
KeyExpiresAtPasses(k) ==
  /\ "access" \in Parts
  /\ key[k].status = "Active" /\ ~key[k].neverExpires /\ ~key[k].expiresPassed
  /\ key' = [key EXCEPT ![k].expiresPassed = TRUE]
  /\ UNCHANGED <<cfg, node, anonAllowed, noticeLogged, failAddr, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* @req REQ-339  While active, when expiresAt has passed: mark the key expired. (actor: system → fair)
MarkKeyExpired(k) ==
  /\ "access" \in Parts
  /\ key[k].status = "Active" /\ key[k].expiresPassed
  /\ key' = [key EXCEPT ![k].status = "Expired"]
  /\ UNCHANGED <<cfg, node, anonAllowed, noticeLogged, failAddr, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* modeling artefact A-13: a revoked or expired key's slot is freed; it is then an "unknown" key.
ArchiveKey(k) ==
  /\ "access" \in Parts
  /\ key[k].status \in {"Revoked", "Expired"}
  /\ key' = [key EXCEPT ![k] = EmptyKey]
  /\ UNCHANGED <<cfg, node, anonAllowed, noticeLogged, failAddr, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

-----------------------------------------------------------------------------
\* No-worker banner (part "banner")

\* modeling artefact A-14: worker nodes start, heartbeat and go quiet (stop, crash, or NodeLostAfter passes)
\* with no clock; "within NodeLostAfter" is the alive/lost flag.
WorkerHeartbeats(w) ==
  /\ "banner" \in Parts
  /\ worker[w] # "alive"
  /\ worker' = [worker EXCEPT ![w] = "alive"] /\ everSeen' = TRUE
  /\ UNCHANGED <<cfg, node, anonAllowed, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, lease, computing, wrote>>
WorkerLost(w) ==
  /\ "banner" \in Parts
  /\ worker[w] = "alive"
  /\ worker' = [worker EXCEPT ![w] = "lost"]
  /\ UNCHANGED <<cfg, node, anonAllowed, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, everSeen, lease, computing, wrote>>

\* @req REQ-341  While no worker node has a heartbeat within NodeLostAfter, the banner is shown.
Banner == \A w \in WorkerNodes : worker[w] # "alive"

-----------------------------------------------------------------------------
\* Insights rollups (part "rollup") — one interval i1

\* @req INV-305  A node computes the interval while holding the lease in the store. (actor: system → fair)
AcquireRollupLease(n) ==
  /\ "rollup" \in Parts
  /\ lease = NULL /\ wrote = {} /\ n \notin computing
  /\ lease' = n /\ computing' = computing \cup {n}
  /\ UNCHANGED <<cfg, node, anonAllowed, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, worker, everSeen, wrote>>

\* modeling artefact A-15: a lease is time-limited (store lease); it may expire while its holder still works.
RollupLeaseExpires ==
  /\ "rollup" \in Parts
  /\ lease # NULL
  /\ lease' = NULL
  /\ UNCHANGED <<cfg, node, anonAllowed, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, worker, everSeen, computing, wrote>>

\* @req INV-305  The computing node writes the interval in one batched write (the sentence does not say the
\*               write checks the lease is still held, so both readings are allowed).
WriteRollup(n) ==
  /\ "rollup" \in Parts
  /\ n \in computing
  /\ wrote' = wrote \cup {n} /\ computing' = computing \ {n}
  /\ lease' = IF lease = n THEN NULL ELSE lease
  /\ UNCHANGED <<cfg, node, anonAllowed, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, worker, everSeen>>

-----------------------------------------------------------------------------

\* modeling artefact: StartupFailed is final (hosting.Node); stutter so it is not reported as deadlock.
Final ==
  /\ node = "StartupFailed"
  /\ UNCHANGED vars

Init ==
  /\ cfg \in Cfgs
  /\ node = "Starting" /\ anonAllowed = FALSE /\ noticeLogged = FALSE
  /\ failAddr = 0
  /\ key = [k \in KeyIds |-> EmptyKey]
  /\ job = [j \in JobIds |-> EmptyJob]
  /\ recJob = [status |-> "none", by |-> NULL]
  /\ errorsShown = FALSE /\ anonServed = FALSE
  /\ worker = [w \in WorkerNodes |-> "absent"] /\ everSeen = FALSE
  /\ lease = NULL /\ computing = {} /\ wrote = {}

Next ==
  \/ AllowAnonymousInDev \/ FailNoAuthorization \/ FailUnhashedPassword \/ MarkRunning \/ Final
  \/ \E r \in Reqs : Respond(r) \/ SubmitInvalidLaunch(r) \/ LaunchRunNow(r) \/ LaunchSchedule(r)
                     \/ LaunchRecurring(r) \/ CreateKey(r) \/ RevokeKey(r)
  \/ LockoutWindowPasses
  \/ \E k \in KeyIds : KeyExpiresAtPasses(k) \/ MarkKeyExpired(k) \/ ArchiveKey(k)
  \/ \E w \in WorkerNodes : WorkerHeartbeats(w) \/ WorkerLost(w)
  \/ \E n \in RollupNodes : AcquireRollupLease(n) \/ WriteRollup(n)
  \/ RollupLeaseExpires

\* Only system-actor transitions are fair.
Fairness ==
  /\ WF_vars(AllowAnonymousInDev) /\ WF_vars(FailNoAuthorization) /\ WF_vars(FailUnhashedPassword)
  /\ \A k \in KeyIds : WF_vars(MarkKeyExpired(k))
  /\ \A n \in RollupNodes : WF_vars(AcquireRollupLease(n)) /\ WF_vars(WriteRollup(n))

Spec == Init /\ [][Next]_vars /\ Fairness

-----------------------------------------------------------------------------
\* Properties

\* @req INV-300 INV-301 INV-302 INV-307 INV-308 REQ-303 REQ-304 REQ-305 REQ-300  For every request a running
\* node can receive, some outcome satisfies every authorization rule at once. Split by credential kind so each
\* conflict gets its own counter-example.
Consistent(kind) == node = "Running" =>
  \A r \in Reqs : r.cred.kind = kind => \E o \in Outcomes : Rules(r, o)
Inv_RulesConsistent_Anon == Consistent("anon")
Inv_RulesConsistent_User == Consistent("user")
Inv_RulesConsistent_Key  == Consistent("key")

\* @req REQ-301 REQ-334  A node whose dashboard configuration must stop startup never runs.
Inv_UnsafeConfigNeverRuns == node = "Running" => (~Cond301 /\ ~Cond334)

\* @req REQ-300  Anonymous requests are only served after the notice was logged (SCN-301 "one notice was logged").
Inv_AnonServedAfterNotice == anonServed => noticeLogged

\* @req REQ-341  The banner shows "the time the last worker was seen": that time must exist whenever it is shown.
Inv_BannerHasLastSeen == Banner => everSeen

\* @req INV-305  Each rollup interval is computed on exactly one node (should).
Inv_RollupOneNode == Cardinality(computing \cup wrote) <= 1

\* @req SCN-303  Vic (view only) cannot launch (impossibleAt 1).
Scn_ViewerCannotLaunch ==
  \A r \in Reqs : (IsUser(r) /\ r.cred.p = Vic /\ r.action = "operate") => ~ENABLED LaunchRunNow(r)
\* @req SCN-304  ReadOnly() blocks Olga's launch (impossibleAt 1).
Scn_ReadOnlyBlocksLaunch ==
  cfg.readOnly => \A r \in Reqs : (IsUser(r) /\ r.cred.p = Olga) => ~ENABLED LaunchRunNow(r)
\* @req SCN-306  An API key cannot mint another key (impossibleAt 1).
Scn_KeyCannotMintKey == \A r \in Reqs : IsKey(r) => ~ENABLED CreateKey(r)
\* @req SCN-307  An expired key is rejected on the JSON API (impossibleAt 2).
Scn_ExpiredKeyRejected ==
  \A r \in Reqs : (IsKey(r) /\ KeyOf(r).status = "Expired") => ~CanServe(r)

\* Scenario trap invariants (expected to be VIOLATED in their own cfg; the trace is the example run).
\* @req SCN-300
Scn300_NotReached == ~(node = "StartupFailed")
\* @req SCN-301
Scn301_NotReached == ~(anonServed /\ noticeLogged)
\* @req SCN-302
Scn302_NotReached == ~(\E j \in JobIds : job[j].status = "Enqueued" /\ job[j].by = Olga)
\* @req SCN-305
Scn305_NotReached == ~(errorsShown /\ \A j \in JobIds : job[j].status = "none" /\ recJob.status = "none")
\* @req SCN-308
Scn308_NotReached == ~(Banner /\ everSeen /\ \A j \in JobIds : job[j].status = "Enqueued")

\* Scenario Init constraints (the "given").
Init300 == Init /\ cfg.env = "Production" /\ ~cfg.authReq /\ ~cfg.allowAnon /\ ~cfg.basicAuth /\ ~cfg.apiKeyAuth
Init301 == Init /\ cfg.env = "Development" /\ ~cfg.authReq /\ ~cfg.basicAuth /\ ~cfg.apiKeyAuth
Init302 == Init /\ ~cfg.readOnly
Init305 == Init
\* SCN-308: the only worker was seen and has gone quiet; jobs are enqueued (and nothing in this module claims them, A-14).
Init308 == /\ cfg \in Cfgs
           /\ node = "Starting" /\ anonAllowed = FALSE /\ noticeLogged = FALSE
           /\ failAddr = 0
           /\ key = [k \in KeyIds |-> EmptyKey]
           /\ recJob = [status |-> "none", by |-> NULL]
           /\ errorsShown = FALSE /\ anonServed = FALSE
           /\ lease = NULL /\ computing = {} /\ wrote = {}
           /\ job = [j \in JobIds |-> [status |-> "Enqueued", by |-> NULL]]
           /\ worker = [w \in WorkerNodes |-> "lost"] /\ everSeen = TRUE
Spec300 == Init300 /\ [][Next]_vars
Spec301 == Init301 /\ [][Next]_vars
Spec302 == Init302 /\ [][Next]_vars
Spec305 == Init305 /\ [][Next]_vars
Spec308 == Init308 /\ [][Next]_vars
=============================================================================
