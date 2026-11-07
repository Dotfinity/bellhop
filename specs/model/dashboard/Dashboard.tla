---------------------------- MODULE Dashboard ----------------------------
\* Generated from specs/dashboard.json (specHash fec5db365b2d; run 3 regenerated the handoff ids) — edit the requirements, not this file.
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
          Parts,
          NULL

ASSUME MaxFailedLogins \in Nat \ {0}                \* @req REQ-335
ASSUME Parts \subseteq {"access", "banner", "rollup"}

Principals == {Olga, Vic}
Perm(p)    == IF p = Olga THEN "operate" ELSE "view"   \* REQ-302/REQ-306: policies grant levels; abstracted (A-6)

VARIABLES
  cfg,          \* DashboardEndpoint + startup configuration, fixed after Init
  node,         \* hosting.Node of the dashboard process: Starting | Running | StartupFailed
  anonPerm,     \* REQ-300 / REQ-342 effect: permission of anonymous requests ("none" | "view" | "operate")
  noticeLogged, \* REQ-300 notice / REQ-342 warning logged
  failAddr,     \* LoginAttempt.failedCount for the (single) client address, saturating at MaxFailedLogins
  key,          \* ApiKey
  job,          \* jobs.Job created by launches
  recJob,       \* recurring.RecurringJob created by REQ-322
  errorsShown,  \* REQ-319: validation errors shown
  anonServed,   \* history: the actions anonymous requests have been served for (SCN-301)
  worker,       \* banner part: per worker node "absent" | "alive" | "lost"
  everSeen,     \* banner part: some worker heartbeat was ever recorded (the "last seen" time exists)
  lease,        \* rollup part: holder of the rollup lease for interval i1
  computing,    \* rollup part: nodes computing interval i1
  wrote         \* rollup part: nodes that wrote interval i1

vars == <<cfg, node, anonPerm, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed,
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
JobRec    == [status: {"none", "Enqueued", "Scheduled"}, by: Principals \cup {"apiKey", "anonymous", NULL}]
EmptyJob  == [status |-> "none", by |-> NULL]

TypeInv ==
  /\ cfg \in Cfgs
  /\ node \in {"Starting", "Running", "StartupFailed"}
  /\ anonPerm \in {"none", "view", "operate"}
  /\ noticeLogged \in BOOLEAN /\ errorsShown \in BOOLEAN
  /\ anonServed \subseteq {"read", "operate", "keyMgmt"}
  /\ failAddr \in 0..MaxFailedLogins
  /\ key \in [KeyIds -> KeyRec]
  /\ job \in [JobIds -> JobRec]
  /\ recJob \in [status: {"none", "Active"}, by: Principals \cup {"apiKey", "anonymous", NULL}]
  /\ worker \in [WorkerNodes -> {"absent", "alive", "lost"}]
  /\ everSeen \in BOOLEAN
  /\ lease \in RollupNodes \cup {NULL}
  /\ computing \subseteq RollupNodes /\ wrote \subseteq RollupNodes

-----------------------------------------------------------------------------
\* Startup (part "access")

\* @req REQ-300 REQ-301 REQ-342  The sentences list RequireAuthorization, RequireRole, RequireClaim and
\*               RequireBasicAuth; RequireApiKey() is deliberately not on the list (glossary authorizationRequirement).
HasAuthReq == cfg.authReq \/ cfg.basicAuth
Cond300 == cfg.env = "Development" /\ ~HasAuthReq
Cond301 == ~HasAuthReq /\ ~cfg.allowAnon /\ cfg.env # "Development"
Cond342 == ~HasAuthReq /\ cfg.allowAnon /\ cfg.env # "Development"
Cond334 == cfg.basicAuth /\ ~cfg.pwHashed

\* @req REQ-300  While starting, Development + none of the listed schemes: anonymous requests get operate
\*               permission and the principal name "anonymous"; log a notice. Fires once (A-3). The name is
\*               AnonName below: this action is the only one that sets anonPerm to "operate" (A-11).
AllowAnonymousInDev ==
  /\ "access" \in Parts
  /\ node = "Starting" /\ Cond300 /\ anonPerm = "none"
  /\ anonPerm' = "operate" /\ noticeLogged' = TRUE
  /\ UNCHANGED <<cfg, node, failAddr, key, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* @req REQ-342  While starting, not Development, none of the listed schemes, AllowAnonymous(): anonymous
\*               requests get view permission only; log a warning. Fires once (A-3).
GrantAnonymousView ==
  /\ "access" \in Parts
  /\ node = "Starting" /\ Cond342 /\ anonPerm = "none"
  /\ anonPerm' = "view" /\ noticeLogged' = TRUE
  /\ UNCHANGED <<cfg, node, failAddr, key, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* @req REQ-301  While starting, no auth requirement, no AllowAnonymous(), not Development: fail the host's start
\*               (the node never runs). The message text, including the RequireApiKey() hint, has no state.
FailNoAuthorization ==
  /\ "access" \in Parts
  /\ node = "Starting" /\ Cond301
  /\ node' = "StartupFailed"
  /\ UNCHANGED <<cfg, anonPerm, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* @req REQ-334  While starting, basic auth with a password that is not a supported salted hash: fail the host's start.
FailUnhashedPassword ==
  /\ "access" \in Parts
  /\ node = "Starting" /\ Cond334
  /\ node' = "StartupFailed"
  /\ UNCHANGED <<cfg, anonPerm, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* hosting REQ-18 (context, not this module): mark the node running when "all startup checks have passed,
\* including … the dashboard checks (dashboard REQ-301, REQ-334)". Store/schema checks abstracted as passed.
\* A-2: the anonymous grants (REQ-300, REQ-342) happen while starting, before the node runs.
StartupChecksPassed ==
  /\ ~Cond301 /\ ~Cond334
  /\ Cond300 => anonPerm = "operate"
  /\ Cond342 => anonPerm = "view"
MarkRunning ==
  /\ "access" \in Parts
  /\ node = "Starting" /\ StartupChecksPassed
  /\ node' = "Running"
  /\ UNCHANGED <<cfg, anonPerm, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

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

\* @req INV-308  revoked, expired, past its expiresAt or unknown.
BadKey(r) ==
  /\ IsKey(r)
  /\ \/ KeyOf(r).status \in {"none", "Revoked", "Expired"}
     \/ KeyOf(r).status = "Active" /\ KeyOf(r).expiresPassed
\* @req REQ-304  basic-authentication attempts only (A-8: per-address counter only).
Locked(r) == cfg.basicAuth /\ IsUser(r) /\ failAddr >= MaxFailedLogins

\* Anonymous requests are never authenticated (A-7); their level is what REQ-300 / REQ-342 granted.
Level(r, o) == IF IsAnon(r) THEN anonPerm
               ELSE IF ~o.auth THEN "none"
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
\* @req INV-308  Revoked, expired, past-expiresAt or unknown key: 401 (no longer counted as a failed login).
R_INV308(r, o) == BadKey(r) => (o.code = "401" /\ ~o.auth)
\* @req REQ-304  Basic auth enabled, address over MaxFailedLogins basic-auth failures in the window: reject
\*               further basic-auth attempts, even with the right password. API keys are not affected.
R_REQ304(r, o) == Locked(r) => ~o.auth
\* @req REQ-305  RequireApiKey(): a call with an active key whose expiresAt has not passed is authenticated
\*               with the key's scope (principal name "apikey:<name>", see Launcher).
R_REQ305(r, o) == (cfg.apiKeyAuth /\ IsKey(r) /\ KeyOf(r).status = "Active" /\ ~KeyOf(r).expiresPassed) => o.auth
\* @req REQ-303  Basic auth accepts only configured users with salted PBKDF2 hashes (and, A-4, accepts them
\*               when the password is right and the address is not locked).
R_REQ303(r, o) ==
  /\ (cfg.basicAuth /\ IsUser(r) /\ o.auth) => (r.cred.ok /\ cfg.pwHashed)
  /\ (cfg.basicAuth /\ IsUser(r) /\ r.cred.ok /\ cfg.pwHashed /\ ~Locked(r)) => o.auth
\* @req REQ-302 REQ-306 REQ-300 REQ-342  A-5: a request with the level it needs (authenticated, or anonymous
\*               with a granted level), not refused by INV-302/INV-307, is served.
R_Grant(r, o) ==
  (HasNeed(r, o) /\ ~(cfg.readOnly /\ r.action # "read") /\ ~(IsKey(r) /\ r.action = "keyMgmt"))
    => Served(o)
\* A-7: authentication outside basic auth and API keys is the host's scheme; anonymous is never authenticated;
\*      keys authenticate only where RequireApiKey() is enabled.
R_Host(r, o) ==
  /\ IsAnon(r) => ~o.auth
  /\ (IsUser(r) /\ ~cfg.basicAuth) => (o.auth <=> r.cred.ok)
  /\ (IsKey(r) /\ ~cfg.apiKeyAuth) => ~o.auth

Rules(r, o) ==
  /\ R_INV301(r, o) /\ R_INV302(r, o) /\ R_INV300(r, o) /\ R_INV307(r, o) /\ R_INV308(r, o)
  /\ R_REQ304(r, o) /\ R_REQ305(r, o) /\ R_REQ303(r, o) /\ R_Grant(r, o) /\ R_Host(r, o)

CanServe(r) == \E o \in Outcomes : Rules(r, o) /\ Served(o)
Min(a, b) == IF a < b THEN a ELSE b

\* @req REQ-304  Handle one request with an outcome allowed by all rules; only a wrong basic-auth password
\*               counts as a failed login for the client address (INV-308 no longer counts bad keys).
Respond(r) ==
  /\ "access" \in Parts
  /\ node = "Running"
  /\ \E o \in Outcomes :
       /\ Rules(r, o)
       /\ failAddr' = IF cfg.basicAuth /\ IsUser(r) /\ ~r.cred.ok
                      THEN Min(failAddr + 1, MaxFailedLogins) ELSE failAddr
       /\ anonServed' = IF IsAnon(r) /\ Served(o) THEN anonServed \cup {r.action} ELSE anonServed
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, key, job, recJob, errorsShown, worker, everSeen, lease, computing, wrote>>

\* modeling artefact A-10: "within LoginLockoutWindow" / "until the window has passed" without a clock.
\* @req REQ-336 (15 minutes) is absorbed by this abstraction.
LockoutWindowPasses ==
  /\ "access" \in Parts
  /\ failAddr > 0
  /\ failAddr' = 0
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, key, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

-----------------------------------------------------------------------------
\* Launch (part "access")

\* @req REQ-300  Anonymous requests have the principal name "anonymous" where REQ-300 fired (A-11). REQ-342 gives
\*               anonymous viewers no name, so outside Development an anonymous request has none (NULL).
AnonName == IF anonPerm = "operate" THEN "anonymous" ELSE NULL
\* @req REQ-305 REQ-300  A key-authenticated request's principal name is "apikey:<name>" ("apiKey": one key slot);
\*               an anonymous request's is AnonName.
Launcher(r) == IF IsUser(r) THEN r.cred.p ELSE IF IsKey(r) THEN "apiKey" ELSE AnonName

\* @req REQ-319  Invalid launch form: show validation errors, create nothing.
SubmitInvalidLaunch(r) ==
  /\ "access" \in Parts
  /\ node = "Running" /\ r.action = "operate" /\ CanServe(r)
  /\ errorsShown' = TRUE
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, failAddr, key, job, recJob, anonServed, worker, everSeen, lease, computing, wrote>>

\* @req REQ-320  Valid form, Run now: enqueue the job and store the operator's principal name.
LaunchRunNow(r) ==
  /\ "access" \in Parts
  /\ node = "Running" /\ r.action = "operate" /\ CanServe(r)
  /\ \E j \in JobIds : job[j].status = "none" /\ job' = [job EXCEPT ![j] = [status |-> "Enqueued", by |-> Launcher(r)]]
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, failAddr, key, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* @req REQ-321  Valid form, Schedule for: schedule the job and store the operator's principal name.
LaunchSchedule(r) ==
  /\ "access" \in Parts
  /\ node = "Running" /\ r.action = "operate" /\ CanServe(r)
  /\ \E j \in JobIds : job[j].status = "none" /\ job' = [job EXCEPT ![j] = [status |-> "Scheduled", by |-> Launcher(r)]]
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, failAddr, key, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* @req REQ-322  Valid form, Make recurring: create a runtime-defined recurring job and store the operator's principal name.
LaunchRecurring(r) ==
  /\ "access" \in Parts
  /\ node = "Running" /\ r.action = "operate" /\ CanServe(r)
  /\ recJob.status = "none"
  /\ recJob' = [status |-> "Active", by |-> Launcher(r)]
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, failAddr, key, job, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

-----------------------------------------------------------------------------
\* API keys (part "access")

\* @req REQ-337 REQ-340  Create a key with a scope and an optional expiry (default ApiKeyDefaultExpiry, or never).
CreateKey(r) ==
  /\ "access" \in Parts
  /\ node = "Running" /\ r.action = "keyMgmt" /\ CanServe(r)
  /\ \E k \in KeyIds, s \in {"view", "operate"}, never \in BOOLEAN :
       /\ key[k].status = "none"
       /\ key' = [key EXCEPT ![k] = [status |-> "Active", scope |-> s, neverExpires |-> never, expiresPassed |-> FALSE]]
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, failAddr, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* @req REQ-338  Revoke a key: mark it revoked.
RevokeKey(r) ==
  /\ "access" \in Parts
  /\ node = "Running" /\ r.action = "keyMgmt" /\ CanServe(r)
  /\ \E k \in KeyIds : key[k].status = "Active" /\ key' = [key EXCEPT ![k].status = "Revoked"]
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, failAddr, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* modeling artefact A-12: a key's expiresAt may pass at any moment (no clock); never-expiring keys excluded.
KeyExpiresAtPasses(k) ==
  /\ "access" \in Parts
  /\ key[k].status = "Active" /\ ~key[k].neverExpires /\ ~key[k].expiresPassed
  /\ key' = [key EXCEPT ![k].expiresPassed = TRUE]
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, failAddr, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* @req REQ-339  While active, when expiresAt has passed: mark the key expired. (actor: system → fair)
MarkKeyExpired(k) ==
  /\ "access" \in Parts
  /\ key[k].status = "Active" /\ key[k].expiresPassed
  /\ key' = [key EXCEPT ![k].status = "Expired"]
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, failAddr, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

\* modeling artefact A-13: a revoked or expired key's slot is freed; it is then an "unknown" key.
ArchiveKey(k) ==
  /\ "access" \in Parts
  /\ key[k].status \in {"Revoked", "Expired"}
  /\ key' = [key EXCEPT ![k] = EmptyKey]
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, failAddr, job, recJob, errorsShown, anonServed, worker, everSeen, lease, computing, wrote>>

-----------------------------------------------------------------------------
\* No-worker banner (part "banner")

\* modeling artefact A-14: worker nodes start, heartbeat and go quiet (stop, crash, or NodeLostAfter passes)
\* with no clock; "within NodeLostAfter" is the alive/lost flag.
WorkerHeartbeats(w) ==
  /\ "banner" \in Parts
  /\ worker[w] # "alive"
  /\ worker' = [worker EXCEPT ![w] = "alive"] /\ everSeen' = TRUE
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, lease, computing, wrote>>
WorkerLost(w) ==
  /\ "banner" \in Parts
  /\ worker[w] = "alive"
  /\ worker' = [worker EXCEPT ![w] = "lost"]
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, everSeen, lease, computing, wrote>>

\* @req REQ-341  While no worker node has a heartbeat within NodeLostAfter (hosting REQ-60), the banner is shown,
\*               with the last-seen time, or "no worker has connected" when none was ever seen.
Banner == \A w \in WorkerNodes : worker[w] # "alive"
BannerDetail == IF everSeen THEN "lastSeen" ELSE "neverConnected"

-----------------------------------------------------------------------------
\* Insights rollups (part "rollup") — one interval i1. RollupNodes are nodes with the worker registered
\* (INV-305 "where the worker is registered", hosting REQ-40).

\* @req INV-305  "start computing each rollup interval that has not been written yet … only while the node holds
\*               the interval's lease": a node takes the free lease and starts computing in one step, and only if
\*               no node has written the interval (run 4: the guard wrote = {} is now the sentence, run-3 F-1).
\*               (system → fair) A node does not start a second computation of the interval while it is still
\*               computing one (A-18).
AcquireRollupLease(n) ==
  /\ "rollup" \in Parts
  /\ lease = NULL /\ n \notin computing /\ wrote = {}
  /\ lease' = n /\ computing' = computing \cup {n}
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, worker, everSeen, wrote>>

\* modeling artefact A-15: a lease is time-limited (store lease); it may expire while its holder still works.
RollupLeaseExpires ==
  /\ "rollup" \in Parts
  /\ lease # NULL
  /\ lease' = NULL
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, worker, everSeen, computing, wrote>>

\* @req INV-305  The computing node writes the interval in one batched write that succeeds only if it still
\*               holds the lease (fenced write). No sentence releases the lease after the write; it lapses (A-15).
WriteRollup(n) ==
  /\ "rollup" \in Parts
  /\ n \in computing /\ lease = n
  /\ wrote' = wrote \cup {n} /\ computing' = computing \ {n}
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, worker, everSeen, lease>>

\* @req INV-305  A node whose lease is gone has its write refused and drops the computation.
RollupWriteRefused(n) ==
  /\ "rollup" \in Parts
  /\ n \in computing /\ lease # n
  /\ computing' = computing \ {n}
  /\ UNCHANGED <<cfg, node, anonPerm, noticeLogged, failAddr, key, job, recJob, errorsShown, anonServed, worker, everSeen, lease, wrote>>

-----------------------------------------------------------------------------

\* modeling artefact: StartupFailed is final (hosting.Node); stutter so it is not reported as deadlock.
Final ==
  /\ node = "StartupFailed"
  /\ UNCHANGED vars

Init ==
  /\ cfg \in Cfgs
  /\ node = "Starting" /\ anonPerm = "none" /\ noticeLogged = FALSE
  /\ failAddr = 0
  /\ key = [k \in KeyIds |-> EmptyKey]
  /\ job = [j \in JobIds |-> EmptyJob]
  /\ recJob = [status |-> "none", by |-> NULL]
  /\ errorsShown = FALSE /\ anonServed = {}
  /\ worker = [w \in WorkerNodes |-> "absent"] /\ everSeen = FALSE
  /\ lease = NULL /\ computing = {} /\ wrote = {}

Next ==
  \/ AllowAnonymousInDev \/ GrantAnonymousView \/ FailNoAuthorization \/ FailUnhashedPassword \/ MarkRunning \/ Final
  \/ \E r \in Reqs : Respond(r) \/ SubmitInvalidLaunch(r) \/ LaunchRunNow(r) \/ LaunchSchedule(r)
                     \/ LaunchRecurring(r) \/ CreateKey(r) \/ RevokeKey(r)
  \/ LockoutWindowPasses
  \/ \E k \in KeyIds : KeyExpiresAtPasses(k) \/ MarkKeyExpired(k) \/ ArchiveKey(k)
  \/ \E w \in WorkerNodes : WorkerHeartbeats(w) \/ WorkerLost(w)
  \/ \E n \in RollupNodes : AcquireRollupLease(n) \/ WriteRollup(n) \/ RollupWriteRefused(n)
  \/ RollupLeaseExpires

\* Only system-actor transitions are fair.
Fairness ==
  /\ WF_vars(AllowAnonymousInDev) /\ WF_vars(GrantAnonymousView)
  /\ WF_vars(FailNoAuthorization) /\ WF_vars(FailUnhashedPassword)
  /\ \A k \in KeyIds : WF_vars(MarkKeyExpired(k))
  /\ \A n \in RollupNodes : WF_vars(AcquireRollupLease(n)) /\ WF_vars(WriteRollup(n)) /\ WF_vars(RollupWriteRefused(n))

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

\* @req REQ-300 REQ-342  Anonymous requests are only served after the notice/warning was logged
\*               (SCN-301 "one notice was logged").
Inv_AnonServedAfterNotice == anonServed # {} => noticeLogged

\* @req REQ-342 INV-301  Outside Development, AllowAnonymous() gives anonymous requests view only: they are
\*               never served an operate action.
Inv_AnonViewOnlyOutsideDev == cfg.env # "Development" => anonServed \subseteq {"read"}

\* @req REQ-320 REQ-321 REQ-322  Every launch stores the launching operator's principal name (Chk: the sentences
\*               require a name; it must exist for every principal that can launch). See A-11.
Chk_LaunchHasPrincipal ==
  /\ \A j \in JobIds : job[j].status # "none" => job[j].by # NULL
  /\ recJob.status # "none" => recJob.by # NULL

\* @req REQ-305 REQ-300  Chk (obvious intent of enabling RequireApiKey()): without AllowAnonymous(), a request
\*               without a key is never served on a node that requires API keys. Run 3: expected VIOLATED; the
\*               owner accepted it (REQ-305 notes, glossary authorizationRequirement and anonymousPermission).
Chk_ApiKeyNotBypassed == (cfg.apiKeyAuth /\ ~cfg.allowAnon) => anonServed = {}

\* @req INV-305  "one batched write per interval" (source BLT-13; notes: "at most one result is written per
\*               interval"): no two nodes write the same interval. wrote is a set of nodes, so this catches a
\*               second node's write, not the same node writing twice.
Inv_RollupOneWrite == Cardinality(wrote) <= 1
\* @req INV-305  "start computing each rollup interval that has not been written yet … only while the node holds
\*               the interval's lease": an action property (PROPERTIES), since it constrains the step that starts a
\*               computation, not a state. Run 4: the step also requires that no node has written the interval.
Inv_RollupStartWithLease ==
  [][\A n \in RollupNodes : (n \notin computing /\ n \in computing') => (lease' = n /\ wrote = {})]_vars

\* @req SCN-303  Vic (view only) cannot launch (impossibleAt 1).
Scn_ViewerCannotLaunch ==
  \A r \in Reqs : (IsUser(r) /\ r.cred.p = Vic /\ r.action = "operate") => ~ENABLED LaunchRunNow(r)
\* @req SCN-304  ReadOnly() blocks Olga's launch (impossibleAt 1).
Scn_ReadOnlyBlocksLaunch ==
  cfg.readOnly => \A r \in Reqs : (IsUser(r) /\ r.cred.p = Olga) => ~ENABLED LaunchRunNow(r)
\* @req SCN-306  An API key cannot mint another key (impossibleAt 1).
Scn_KeyCannotMintKey == \A r \in Reqs : IsKey(r) => ~ENABLED CreateKey(r)
\* @req SCN-307  A key whose expiry has passed is rejected on the JSON API, whether or not REQ-339 has
\*               already marked it expired (impossibleAt 2).
Scn_ExpiredKeyRejected ==
  \A r \in Reqs : (IsKey(r) /\ (KeyOf(r).status = "Expired" \/ (KeyOf(r).status = "Active" /\ KeyOf(r).expiresPassed)))
                    => ~CanServe(r)
\* @req SCN-309  Outside Development, an anonymous viewer (AllowAnonymous() only) cannot launch (impossibleAt 2).
Scn_AnonViewerCannotLaunch ==
  (cfg.env # "Development" /\ cfg.allowAnon /\ ~cfg.authReq /\ ~cfg.basicAuth)
    => \A r \in Reqs : IsAnon(r) => ~ENABLED LaunchRunNow(r)

\* Scenario trap invariants (expected to be VIOLATED in their own cfg; the trace is the example run).
\* @req SCN-300
Scn300_NotReached == ~(node = "StartupFailed")
\* @req SCN-301
Scn301_NotReached == ~("operate" \in anonServed /\ noticeLogged)
\* @req SCN-302
Scn302_NotReached == ~(\E j \in JobIds : job[j].status = "Enqueued" /\ job[j].by = Olga)
\* @req SCN-305
Scn305_NotReached == ~(errorsShown /\ \A j \in JobIds : job[j].status = "none" /\ recJob.status = "none")
\* @req SCN-308
Scn308_NotReached == ~(Banner /\ BannerDetail = "lastSeen" /\ \A j \in JobIds : job[j].status = "Enqueued")
\* @req SCN-310  The office address is locked out of basic auth, a correct password from it is rejected, and
\*               the CI request with an active, unexpired operate key k is authenticated and served.
KeyReq(k)  == [cred |-> [kind |-> "key", p |-> NULL, ok |-> FALSE, k |-> k], action |-> "operate"]
OlgaOkReq  == [cred |-> [kind |-> "user", p |-> Olga, ok |-> TRUE, k |-> NULL], action |-> "read"]
Scn310_NotReached ==
  ~(/\ node = "Running" /\ failAddr >= MaxFailedLogins
    /\ \A o \in Outcomes : Rules(OlgaOkReq, o) => ~o.auth
    /\ \E k \in KeyIds : /\ key[k].status = "Active" /\ key[k].scope = "operate" /\ ~key[k].expiresPassed
                         /\ \A o \in Outcomes : Rules(KeyReq(k), o) => o.auth
                         /\ \E o \in Outcomes : Rules(KeyReq(k), o) /\ Served(o))

\* Scenario Init constraints (the "given").
Init300 == Init /\ cfg.env = "Production" /\ ~cfg.authReq /\ ~cfg.allowAnon /\ ~cfg.basicAuth /\ ~cfg.apiKeyAuth
Init301 == Init /\ cfg.env = "Development" /\ ~cfg.authReq /\ ~cfg.basicAuth /\ ~cfg.apiKeyAuth
Init302 == Init /\ ~cfg.readOnly
Init305 == Init
Init310 == Init /\ cfg.basicAuth /\ cfg.apiKeyAuth /\ cfg.pwHashed /\ ~cfg.readOnly
\* SCN-308: the only worker was seen and has gone quiet; jobs are enqueued (and nothing in this module claims them, A-14).
Init308 == /\ cfg \in Cfgs
           /\ node = "Starting" /\ anonPerm = "none" /\ noticeLogged = FALSE
           /\ failAddr = 0
           /\ key = [k \in KeyIds |-> EmptyKey]
           /\ recJob = [status |-> "none", by |-> NULL]
           /\ errorsShown = FALSE /\ anonServed = {}
           /\ lease = NULL /\ computing = {} /\ wrote = {}
           /\ job = [j \in JobIds |-> [status |-> "Enqueued", by |-> NULL]]
           /\ worker = [w \in WorkerNodes |-> "lost"] /\ everSeen = TRUE
Spec300 == Init300 /\ [][Next]_vars
Spec301 == Init301 /\ [][Next]_vars
Spec302 == Init302 /\ [][Next]_vars
Spec305 == Init305 /\ [][Next]_vars
Spec308 == Init308 /\ [][Next]_vars
Spec310 == Init310 /\ [][Next]_vars
=============================================================================
