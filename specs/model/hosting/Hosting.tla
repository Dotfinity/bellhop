---------------------------- MODULE Hosting ----------------------------
\* Generated from specs/hosting.json — edit the requirements, not this file.
\* Every action/property carries an @req comment naming the requirement it encodes.
\* Chk_* definitions are NOT requirements: they are checks derived from a requirement's
\* obvious intent (listed in the findings' assumptions table) so TLC can show where the
\* sentences as written allow something else.
EXTENDS Naturals, FiniteSets

CONSTANTS Nodes,            \* Node instances (entity.bound = 2; 1 in the single-node cfgs)
          Versions,         \* schema versions the store can hold
          ExpectedVals,     \* library versions a (re)started node may run (its expected schema)
          InitSchemaVals,   \* schema version of the shared store at Init
          InitReachVals,    \* store reachable at Init?
          RegVals,          \* @req REQ-52  "none" | "client" | "worker" (worker includes client)
          AutoVals,         \* @req REQ-21  AutoMigrate (default true; both values explored)
          ValidVals,        \* options pass validation?
          ToolVals,         \* @req REQ-14  process runs build-time tooling?
          ConfVals,         \* @req REQ-15  a store is configured?
          DevVals,          \* environment is Development?
          AlertVals,        \* @req REQ-52  alerts registration (independent of client/worker)
          OkVals,           \* @req REQ-12  the other modules' startup checks: "pass", "failNoStore" (one that
                            \* needs no store fails: dashboard REQ-301/REQ-334, recurring REQ-210), "failConnect"
                            \* (a Redis check that is part of connecting fails: redis REQ-502/REQ-505) or
                            \* "failStore" (a stored runtime-defined recurring job has a colliding name: recurring
                            \* REQ-236); A-19
          MaxInFlight,      \* worker concurrency in the model (real value irrelevant)
          HealthyAfterPasses, \* @req REQ-50 (3 in the policy; 2 in the model)
          HealthEnv,        \* TRUE: stalls, thresholds and node-count changes may happen
          NULL

ASSUME HealthyAfterPasses \in Nat \ {0}                     \* @req REQ-50
ASSUME \A e \in ExpectedVals : e >= 1 /\ e \in Versions
ASSUME RegVals \subseteq {"none", "client", "worker"}
ASSUME OkVals \subseteq {"pass", "failNoStore", "failConnect", "failStore"}

NodeStatus == {"none", "Starting", "Running", "Draining", "Stopped", "StartupFailed"}
Final      == {"Stopped", "StartupFailed"}
HealthVal  == {"Healthy", "Degraded", "Unhealthy"}

\* Per-process configuration, fixed for the life of one process.
CfgSet == [reg: RegVals, auto: AutoVals, valid: ValidVals, tool: ToolVals,
           conf: ConfVals, dev: DevVals, exp: ExpectedVals, alerts: AlertVals, ok: OkVals]

NodeRec == [st: NodeStatus,
            validated: BOOLEAN,         \* REQ-12 options validated (store work only after this)
            prechecked: BOOLEAN,        \* REQ-12 the startup checks that need no store have passed
            connected: BOOLEAN,         \* REQ-12 connected to the store (for Redis: EVAL and eviction checks passed)
            storeChecked: BOOLEAN,      \* REQ-12 the startup checks that read stored data have passed
            checkedEmpty: BOOLEAN,      \* history: recurring REQ-236 ran on a store with no Bellhop schema
            notifActive: BOOLEAN,       \* notification checks running on this node (REQ-59)
            otherBad: BOOLEAN,          \* history: wrote to the shared store while another startup check fails
            hostStopped: BOOLEAN,       \* the host has signalled stop
            workerActive: BOOLEAN,      \* worker loop + background duties started (REQ-18, REQ-40)
            inFlight: 0..MaxInFlight,   \* claimed jobs whose timeout token was not signalled
            timedOut: 0..MaxInFlight,   \* claimed jobs whose timeout token was signalled (jobs REQ-137) and whose
                                        \* handler has not settled under jobs REQ-138/REQ-186 (grace period)
            timeoutPassed: BOOLEAN,     \* REQ-28 ShutdownTimeout has passed
            cancelDone: BOOLEAN,        \* REQ-29 remaining tokens cancelled, REQ-140/REQ-190 writes attempted
            released: 0..MaxInFlight,   \* jobs released back to the store at shutdown (jobs REQ-140)
            cancelled: 0..MaxInFlight,  \* jobs marked cancelled at shutdown (jobs REQ-190, shutdown branch)
            stopInGrace: BOOLEAN,       \* history: stopped before ShutdownTimeout with a timed-out handler unsettled
            leftToExpiry: 0..MaxInFlight, \* jobs still held at stop: recovered by lease expiry (jobs REQ-132/133)
            claimedEver: BOOLEAN,
            claimedAfterStop: BOOLEAN,
            reconciled: BOOLEAN,        \* REQ-12 code-defined recurring jobs reconciled
            reconcileBad: BOOLEAN,      \* history: reconciled while the schema was not accepted
            migrateBad: BOOLEAN,        \* history: migrated the shared store with invalid options
            ranUnmigrated: BOOLEAN,     \* history: became Running with AutoMigrate on and an older schema
            memWarnings: 0..2,          \* REQ-16 warnings logged (capped)
            summaryLogged: BOOLEAN,     \* REQ-19
            io: BOOLEAN,                \* REQ-13 any store I/O done
            health: HealthVal,
            passes: 0..HealthyAfterPasses,
            stalled: BOOLEAN,           \* REQ-30 internal error stalls processing
            stallReported: BOOLEAN,
            degradedCond: BOOLEAN]      \* REQ-34 lag / dead-letter growth / failures over threshold

VARIABLES cfg, nd, schema, reachable, lock, fewAlive
vars == <<cfg, nd, schema, reachable, lock, fewAlive>>

\* @req Health.initial = Unhealthy (hosting F-11 resolution): a node is Unhealthy until REQ-58/REQ-35.
Fresh == [st |-> "none", validated |-> FALSE, prechecked |-> FALSE, connected |-> FALSE,
          storeChecked |-> FALSE, checkedEmpty |-> FALSE, notifActive |-> FALSE, otherBad |-> FALSE,
          hostStopped |-> FALSE, workerActive |-> FALSE, inFlight |-> 0, timedOut |-> 0,
          timeoutPassed |-> FALSE, cancelDone |-> FALSE, released |-> 0, cancelled |-> 0, stopInGrace |-> FALSE,
          leftToExpiry |-> 0, claimedEver |-> FALSE, claimedAfterStop |-> FALSE,
          reconciled |-> FALSE, reconcileBad |-> FALSE, migrateBad |-> FALSE, ranUnmigrated |-> FALSE,
          memWarnings |-> 0, summaryLogged |-> FALSE, io |-> FALSE,
          health |-> "Unhealthy", passes |-> 0, stalled |-> FALSE, stallReported |-> FALSE,
          degradedCond |-> FALSE]

TypeInv ==
  /\ cfg \in [Nodes -> CfgSet]
  /\ nd  \in [Nodes -> NodeRec]
  /\ schema \in Versions
  /\ reachable \in BOOLEAN
  /\ lock \in Nodes \cup {NULL}
  /\ fewAlive \in BOOLEAN

Min(a, b) == IF a < b THEN a ELSE b

HasWorker(n) == cfg[n].reg = "worker"                       \* @req REQ-52
\* @req REQ-15  no store configured -> the node's own in-memory store: always reachable, fresh schema.
Reach(n)    == ~cfg[n].conf \/ reachable
Sch(n)      == IF cfg[n].conf THEN schema ELSE cfg[n].exp
\* @req REQ-23, REQ-43  accepted range: expected version or one older.
Accepted(n) == Sch(n) \in {cfg[n].exp, cfg[n].exp - 1}
\* @req REQ-18, REQ-22  "no migration is pending under REQ-22": AutoMigrate on and the store older.
Pending(n)  == cfg[n].conf /\ cfg[n].auto /\ schema < cfg[n].exp
\* @req REQ-12, REQ-23, REQ-43  the schema check passes: neither too old with AutoMigrate off nor too new.
SchemaCheckPasses(n) == ~(~cfg[n].auto /\ Sch(n) + 1 < cfg[n].exp) /\ ~(Sch(n) > cfg[n].exp)
\* @req REQ-18  "all startup checks have passed, including option validation (REQ-9) and the dashboard
\*              checks, and, where the worker is registered, code-defined recurring jobs have been
\*              reconciled (REQ-12)": options validated, both groups of REQ-12 startup checks passed,
\*              and a worker node has reconciled (A-2, A-19).
StartupChecksPassed(n) ==
  /\ nd[n].validated /\ nd[n].prechecked /\ nd[n].connected /\ nd[n].storeChecked
  /\ Accepted(n) /\ ~Pending(n)
  /\ HasWorker(n) => nd[n].reconciled
\* A-19: the process will fail one of the other modules' startup checks. A REQ-236 collision cannot be
\* found where the store had no Bellhop schema when the check ran (recurring REQ-236: none stored), and
\* the in-memory store is not Redis, so it has no Redis connection check to fail.
WillFailOther(n) ==
  /\ cfg[n].ok # "pass"
  /\ ~(cfg[n].ok = "failStore" /\ nd[n].checkedEmpty)
  /\ ~(cfg[n].ok = "failConnect" /\ ~cfg[n].conf)

\* @req REQ-56  a node that leaves Starting for any reason releases the migration lock first.
ReleaseIfHeld(n) == IF lock = n THEN NULL ELSE lock

Init ==
  /\ cfg \in [Nodes -> CfgSet]
  /\ nd = [n \in Nodes |-> Fresh]
  /\ schema \in InitSchemaVals
  /\ reachable \in InitReachVals
  /\ lock = NULL
  /\ fewAlive = FALSE

\* ------------------------------------------------------------------ startup

\* @req REQ-12  When the host starts, start the Bellhop node (no I/O before this: REQ-13).
\* @req REQ-16  Same event ("a node starts"): no store configured and not Development -> the in-memory
\*              warning, logged once, before the node is marked running.
\* @req REQ-57  Build-time tooling builds the host without starting it (assumption): never started.
HostStarts(n) ==
  /\ nd[n].st = "none"
  /\ ~cfg[n].tool
  /\ nd' = [nd EXCEPT ![n].st = "Starting",
                      ![n].memWarnings = IF ~cfg[n].conf /\ ~cfg[n].dev THEN 1 ELSE 0]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req REQ-12  "validate the options, and only then connect to the store": options pass validation.
ValidateOptions(n) ==
  /\ nd[n].st = "Starting"
  /\ cfg[n].valid /\ ~nd[n].validated
  /\ nd' = [nd EXCEPT ![n].validated = TRUE]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req REQ-9  While starting, if an option fails validation, fail the host's start.
ValidationFails(n) ==
  /\ nd[n].st = "Starting"
  /\ ~cfg[n].valid
  /\ nd' = [nd EXCEPT ![n].st = "StartupFailed"]
  /\ lock' = ReleaseIfHeld(n)
  /\ UNCHANGED <<cfg, schema, reachable, fewAlive>>

\* @req REQ-12  "validate the options and run the startup checks that need no store (dashboard REQ-301
\*              and REQ-334, recurring REQ-210)": they pass. Unordered with option validation.
NoStoreChecksPass(n) ==
  /\ nd[n].st = "Starting"
  /\ cfg[n].ok # "failNoStore" /\ ~nd[n].prechecked
  /\ nd' = [nd EXCEPT ![n].prechecked = TRUE]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req REQ-12  Cross-module, abstracted (A-19): one of dashboard REQ-301/REQ-334 or recurring REQ-210
\*              fails the host's start. These need no store, so no store step precedes them.
NoStoreCheckFails(n) ==
  /\ nd[n].st = "Starting"
  /\ cfg[n].ok = "failNoStore"
  /\ nd' = [nd EXCEPT ![n].st = "StartupFailed"]
  /\ lock' = ReleaseIfHeld(n)
  /\ UNCHANGED <<cfg, schema, reachable, fewAlive>>

\* @req REQ-12  "then connect to the store, which for Redis includes its EVAL and eviction-policy checks
\*              (redis REQ-500, REQ-502, REQ-505)": the connection is established and, for Redis, the checks
\*              pass. Only after the options were validated and the checks that need no store passed.
ConnectStore(n) ==
  /\ nd[n].st = "Starting" /\ nd[n].validated /\ nd[n].prechecked
  /\ Reach(n) /\ ~nd[n].connected
  /\ ~(cfg[n].conf /\ cfg[n].ok = "failConnect")
  /\ nd' = [nd EXCEPT ![n].connected = TRUE, ![n].io = TRUE]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req REQ-12  with redis REQ-502/REQ-505 (A-19): a Redis check that is part of connecting fails the host's
\*              start, before the schema check. Only a configured store can be Redis.
ConnectCheckFails(n) ==
  /\ nd[n].st = "Starting" /\ nd[n].validated /\ nd[n].prechecked
  /\ Reach(n) /\ ~nd[n].connected
  /\ cfg[n].conf /\ cfg[n].ok = "failConnect"
  /\ nd' = [nd EXCEPT ![n].st = "StartupFailed", ![n].io = TRUE]
  /\ lock' = ReleaseIfHeld(n)
  /\ UNCHANGED <<cfg, schema, reachable, fewAlive>>

\* @req REQ-12  "check the schema (failing under REQ-23 or REQ-43) and run the startup checks that read stored
\*              data (recurring REQ-236, which reads a store that is not migrated yet), and only then migrate":
\*              the schema check passes and REQ-236 finds no collision. The schema check and REQ-236 are one
\*              step here (A-23).
\* @req recurring REQ-236  judged by name and origin only; none stored where the store has no Bellhop schema.
StoreChecksPass(n) ==
  /\ nd[n].st = "Starting" /\ nd[n].connected
  /\ Reach(n) /\ SchemaCheckPasses(n)
  /\ (cfg[n].ok # "failStore" \/ Sch(n) = 0) /\ ~nd[n].storeChecked
  /\ nd' = [nd EXCEPT ![n].storeChecked = TRUE, ![n].io = TRUE, ![n].checkedEmpty = (Sch(n) = 0)]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req recurring REQ-236  (A-19) a stored runtime-defined recurring job has the name of a code- or
\*              configuration-defined one: fail the host's start, after the schema check and before any
\*              migration or reconciliation. A store with no Bellhop schema stores none, so it cannot fail there.
StoreCheckFails(n) ==
  /\ nd[n].st = "Starting" /\ nd[n].connected
  /\ Reach(n) /\ SchemaCheckPasses(n)
  /\ cfg[n].ok = "failStore" /\ Sch(n) # 0
  /\ nd' = [nd EXCEPT ![n].st = "StartupFailed", ![n].io = TRUE]
  /\ lock' = ReleaseIfHeld(n)
  /\ UNCHANGED <<cfg, schema, reachable, fewAlive>>

\* @req REQ-23  AutoMigrate off and schema more than one version older -> fail the host's start.
SchemaTooOld(n) ==
  /\ nd[n].st = "Starting" /\ nd[n].connected                       \* @req REQ-12 order
  /\ Reach(n)
  /\ ~cfg[n].auto
  /\ Sch(n) + 1 < cfg[n].exp
  /\ nd' = [nd EXCEPT ![n].st = "StartupFailed", ![n].io = TRUE]
  /\ lock' = ReleaseIfHeld(n)
  /\ UNCHANGED <<cfg, schema, reachable, fewAlive>>

\* @req REQ-43  Stored schema newer than expected -> fail the host's start (AutoMigrate on or off).
SchemaTooNew(n) ==
  /\ nd[n].st = "Starting" /\ nd[n].connected                       \* @req REQ-12 order
  /\ Reach(n)
  /\ Sch(n) > cfg[n].exp
  /\ nd' = [nd EXCEPT ![n].st = "StartupFailed", ![n].io = TRUE]
  /\ lock' = ReleaseIfHeld(n)
  /\ UNCHANGED <<cfg, schema, reachable, fewAlive>>

\* @req REQ-22, REQ-42  AutoMigrate on and schema older: only the holder of the store's migration
\*                      lock migrates; the others wait (this action is disabled for them) and re-read.
\* @req REQ-12  only after the options were validated and every startup check has passed.
AcquireMigrationLock(n) ==
  /\ nd[n].st = "Starting" /\ nd[n].validated /\ nd[n].prechecked /\ nd[n].storeChecked
  /\ cfg[n].conf /\ cfg[n].auto /\ reachable
  /\ schema < cfg[n].exp
  /\ lock = NULL
  /\ lock' = n
  /\ nd' = [nd EXCEPT ![n].io = TRUE]
  /\ UNCHANGED <<cfg, schema, reachable, fewAlive>>

\* @req REQ-22  Apply the embedded migrations up to the expected version and log it.
\* @req REQ-24  Re-applying migrations that are already applied leaves the schema unchanged.
\* @req REQ-42  Only the lock holder migrates; the lock is released afterwards.
Migrate(n) ==
  /\ nd[n].st = "Starting"
  /\ lock = n /\ reachable
  /\ schema' = IF schema < cfg[n].exp THEN cfg[n].exp ELSE schema
  /\ lock' = NULL
  /\ nd' = [nd EXCEPT ![n].migrateBad = nd[n].migrateBad \/ ~cfg[n].valid,
                      ![n].otherBad = nd[n].otherBad \/ WillFailOther(n)]
  /\ UNCHANGED <<cfg, reachable, fewAlive>>

\* @req REQ-12  ...and only then [after every startup check], where the worker is registered and the
\*              schema version is accepted with no migration pending, reconcile code-defined recurring jobs.
ReconcileRecurring(n) ==
  /\ nd[n].st = "Starting" /\ nd[n].validated /\ nd[n].prechecked /\ nd[n].storeChecked
  /\ HasWorker(n) /\ Reach(n)
  /\ Accepted(n) /\ ~Pending(n)
  /\ ~nd[n].reconciled
  /\ nd' = [nd EXCEPT ![n].reconciled = TRUE, ![n].io = TRUE,
                      ![n].reconcileBad = ~Accepted(n),
                      ![n].otherBad = nd[n].otherBad \/ WillFailOther(n)]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req REQ-18  Store reachable, schema accepted, no migration pending, startup checks passed and, where
\*              the worker is registered, recurring jobs reconciled -> Running; start the worker and its
\*              background duties where the worker is registered.
\* @req REQ-19  Same event: log the one-screen summary.
\* @req REQ-25  Claims only once the store is reachable (guard Reach).
\* Notification checks start on a node with the alerts registration (integrations INV-411/REQ-438, A-20).
MarkRunning(n) ==
  /\ nd[n].st = "Starting"
  /\ Reach(n)
  /\ StartupChecksPassed(n)
  /\ nd' = [nd EXCEPT ![n].st = "Running", ![n].workerActive = HasWorker(n),
                      ![n].notifActive = cfg[n].alerts,
                      ![n].summaryLogged = TRUE, ![n].io = TRUE,
                      ![n].ranUnmigrated = cfg[n].conf /\ cfg[n].auto /\ schema < cfg[n].exp]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* ------------------------------------------------------------------ running (jobs module, abstracted)

\* jobs module claim, abstracted (A-6). Guard Running encodes REQ-27 "stop claiming";
\* @req REQ-20, REQ-40  only a node whose worker was started claims; REQ-25 store reachable.
Claim(n) ==
  /\ nd[n].st = "Running"
  /\ nd[n].workerActive
  /\ Reach(n)
  /\ nd[n].inFlight + nd[n].timedOut < MaxInFlight
  /\ nd' = [nd EXCEPT ![n].inFlight = @ + 1, ![n].claimedEver = TRUE, ![n].io = TRUE,
                      ![n].claimedAfterStop = @ \/ nd[n].hostStopped]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* Handler returns (jobs module; not obliged — a handler may ignore cancellation).
JobFinishes(n) ==
  /\ nd[n].st \in {"Running", "Draining"}
  /\ nd[n].inFlight > 0
  /\ nd' = [nd EXCEPT ![n].inFlight = @ - 1]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* jobs REQ-137 (abstracted, A-24): a job runs longer than its timeout; its timeout token is signalled.
\* Only before the shutdown cancel: REQ-140 reads the timeout token at the release (A-24).
JobTimesOut(n) ==
  /\ nd[n].st \in {"Running", "Draining"} /\ ~nd[n].cancelDone
  /\ nd[n].inFlight > 0
  /\ nd' = [nd EXCEPT ![n].inFlight = @ - 1, ![n].timedOut = @ + 1]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* jobs REQ-138/REQ-186 (abstracted, A-24): the timed-out handler throws OperationCanceledException within
\* TimeoutGracePeriod, or the grace period ends and it is abandoned; the job is failed or dead-lettered and
\* leaves the node's in-flight set. Not obliged here (no clock).
TimedOutSettles(n) ==
  /\ nd[n].st \in {"Running", "Draining"}
  /\ nd[n].timedOut > 0
  /\ nd' = [nd EXCEPT ![n].timedOut = @ - 1]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* ------------------------------------------------------------------ shutdown

\* Environment: the host signals stop. @req REQ-27  While running -> Draining (stop claiming).
\* @req REQ-55  While starting -> stop retrying, Stopped, without starting the worker or any duty.
\* @req REQ-56  a starting node that leaves Starting releases the migration lock first.
HostStops(n) ==
  /\ nd[n].st \in {"Starting", "Running"}
  /\ ~nd[n].hostStopped
  /\ nd' = [nd EXCEPT ![n].hostStopped = TRUE,
                      ![n].st = IF nd[n].st = "Running" THEN "Draining" ELSE "Stopped"]
  /\ lock' = IF nd[n].st = "Starting" THEN ReleaseIfHeld(n) ELSE lock
  /\ UNCHANGED <<cfg, schema, reachable, fewAlive>>

\* @req REQ-28  ShutdownTimeout passes (no clock: may happen at any moment while draining, A-1).
TimeoutPasses(n) ==
  /\ nd[n].st = "Draining"
  /\ ~nd[n].timeoutPassed
  /\ nd' = [nd EXCEPT ![n].timeoutPassed = TRUE]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req REQ-29  "the remaining jobs' tokens were cancelled and the lease releases and cancellations that jobs
\* REQ-140 and REQ-190 call for at shutdown were attempted" (jobs REQ-139, REQ-140, REQ-190, A-7, A-26).
\* One store write is attempted per job still held. REQ-140 releases a job whose timeout token was not
\* signalled and whose cancellation was not requested. REQ-190's shutdown branch marks cancelled a job whose
\* cancellation was requested, timed out or not: that branch has no timeout guard. A timed-out job whose
\* cancellation was not requested keeps its lease (REQ-140) until jobs REQ-138/REQ-186 settles it.
\* Cancellation requests (jobs REQ-135) are not tracked here, so which held jobs have one is chosen freely
\* (A-26). A write lands only if the store is reachable; a failed one is left to lease expiry (jobs REQ-132,
\* REQ-133, REQ-190), outside this model.
CancelAndRelease(n) ==
  /\ nd[n].st = "Draining"
  /\ nd[n].timeoutPassed /\ ~nd[n].cancelDone
  /\ nd[n].inFlight + nd[n].timedOut > 0
  /\ \E c \in 0..nd[n].inFlight, ct \in 0..nd[n].timedOut :
       nd' = [nd EXCEPT ![n].released = IF Reach(n) THEN @ + (nd[n].inFlight - c) ELSE @,
                        ![n].cancelled = IF Reach(n) THEN @ + c + ct ELSE @,
                        ![n].leftToExpiry = IF Reach(n) THEN @ ELSE @ + nd[n].inFlight + ct,
                        ![n].inFlight = 0, ![n].timedOut = @ - ct, ![n].cancelDone = TRUE]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req REQ-29  While draining, "when every in-flight job has finished, or ShutdownTimeout has passed, the
\* remaining jobs' tokens were cancelled and the [REQ-140, REQ-190] releases and cancellations were attempted"
\* -> Stopped. A timed-out handler that has not settled under jobs REQ-138/REQ-186 is an in-flight job
\* (REQ-29's notes, run 4 F-1).
AllFinished(n) == nd[n].inFlight = 0 /\ nd[n].timedOut = 0
StopNode(n) ==
  /\ nd[n].st = "Draining"
  /\ AllFinished(n) \/ (nd[n].timeoutPassed /\ nd[n].cancelDone)
  /\ nd' = [nd EXCEPT ![n].st = "Stopped", ![n].workerActive = FALSE, ![n].notifActive = FALSE,
                      ![n].stopInGrace = ~nd[n].timeoutPassed /\ nd[n].timedOut > 0,
                      ![n].leftToExpiry = @ + nd[n].timedOut, ![n].timedOut = 0]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* ------------------------------------------------------------------ health

Alive(n) == nd[n].st \in {"Starting", "Running", "Draining"}

UnhealthyCond(n) ==
  \/ nd[n].stalled                               \* REQ-30  internal error stalling processing
  \/ ~Reach(n)                                   \* REQ-31
  \/ ~Accepted(n)                                \* REQ-32
  \/ HasWorker(n) /\ ~nd[n].workerActive         \* REQ-33  worker loop not alive
  \/ HasWorker(n) /\ fewAlive                    \* REQ-44  where the worker is registered (A-8)

\* @req REQ-30, REQ-31, REQ-32, REQ-33, REQ-44, REQ-34, REQ-35, REQ-58  one event "the health check runs"
\* (lint warning). Unhealthy checks first (REQ-30..33, REQ-44: from Healthy/Degraded); else, while
\* Unhealthy, REQ-58 -> Degraded; else Degraded thresholds (REQ-34: from Healthy); else count a pass and,
\* from Degraded after HealthyAfterPasses passes in a row, Healthy (REQ-35). A run in which every check
\* passes counts as a pass, including the REQ-58 run (A-15). Where no requirement covers the current
\* status (e.g. Unhealthy and still failing) the status stays.
HealthCheck(n) ==
  /\ Alive(n)
  /\ LET h == nd[n].health
         p == Min(nd[n].passes + 1, HealthyAfterPasses)
     IN  IF UnhealthyCond(n)
           THEN nd' = [nd EXCEPT ![n].health = IF h \in {"Healthy", "Degraded"} THEN "Unhealthy" ELSE h,
                                 ![n].passes = 0,
                                 ![n].stallReported = nd[n].stalled]
         ELSE IF h = "Unhealthy"
           THEN nd' = [nd EXCEPT ![n].health = "Degraded",
                                 ![n].passes = IF nd[n].degradedCond THEN 0 ELSE p]
         ELSE IF nd[n].degradedCond
           THEN nd' = [nd EXCEPT ![n].health = IF h = "Healthy" THEN "Degraded" ELSE h,
                                 ![n].passes = 0]
         ELSE nd' = [nd EXCEPT ![n].passes = p,
                               ![n].health = IF p >= HealthyAfterPasses /\ h = "Degraded"
                                             THEN "Healthy" ELSE h]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* ------------------------------------------------------------------ environment

StoreGoesDown == reachable /\ reachable' = FALSE /\ UNCHANGED <<cfg, nd, schema, lock, fewAlive>>
StoreComesBack == ~reachable /\ reachable' = TRUE /\ UNCHANGED <<cfg, nd, schema, lock, fewAlive>>

Stall(n) ==
  /\ HealthEnv /\ Alive(n) /\ ~nd[n].stalled
  /\ nd' = [nd EXCEPT ![n].stalled = TRUE, ![n].stallReported = FALSE]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>
Unstall(n) ==
  /\ HealthEnv /\ nd[n].stalled
  /\ nd' = [nd EXCEPT ![n].stalled = FALSE]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>
ToggleDegraded(n) ==
  /\ HealthEnv /\ Alive(n)
  /\ nd' = [nd EXCEPT ![n].degradedCond = ~@]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>
ToggleFewAlive ==
  /\ HealthEnv
  /\ fewAlive' = ~fewAlive
  /\ UNCHANGED <<cfg, nd, schema, reachable, lock>>

\* modeling artefact A-3: a finished process exits and a new one (possibly a newer library version)
\* may start in its place. Process exit closes the store session, which frees a store-native
\* migration lock (TECH-126).
Archive(n) ==
  /\ nd[n].st \in Final
  /\ \E c \in CfgSet : cfg' = [cfg EXCEPT ![n] = c]
  /\ nd' = [nd EXCEPT ![n] = Fresh]
  /\ lock' = IF lock = n THEN NULL ELSE lock
  /\ UNCHANGED <<schema, reachable, fewAlive>>

NodeStep(n) ==
  \/ HostStarts(n) \/ ValidateOptions(n) \/ ValidationFails(n)
  \/ NoStoreChecksPass(n) \/ NoStoreCheckFails(n) \/ ConnectStore(n) \/ ConnectCheckFails(n)
  \/ StoreChecksPass(n) \/ StoreCheckFails(n)
  \/ SchemaTooOld(n) \/ SchemaTooNew(n)
  \/ AcquireMigrationLock(n) \/ Migrate(n) \/ ReconcileRecurring(n)
  \/ MarkRunning(n) \/ Claim(n) \/ JobFinishes(n) \/ JobTimesOut(n) \/ TimedOutSettles(n)
  \/ HostStops(n) \/ TimeoutPasses(n)
  \/ CancelAndRelease(n) \/ StopNode(n) \/ HealthCheck(n)
  \/ Stall(n) \/ Unstall(n) \/ ToggleDegraded(n) \/ Archive(n)

Next ==
  \/ \E n \in Nodes : NodeStep(n)
  \/ StoreGoesDown \/ StoreComesBack \/ ToggleFewAlive

\* System-actor transitions are fair (REQ-30..35, REQ-44, REQ-58). For the diagnostic Chk_DrainEnds the
\* host-side shutdown steps are also treated as obligations of the software (A-9); the store,
\* handlers and the host's own stop signal are not. Since REQ-29 only asks that the release be
\* attempted, the release step no longer needs the store and weak fairness suffices.
Fairness ==
  \A n \in Nodes :
    /\ WF_vars(HealthCheck(n))
    /\ WF_vars(TimeoutPasses(n)) /\ WF_vars(CancelAndRelease(n)) /\ WF_vars(StopNode(n))

Spec == Init /\ [][Next]_vars /\ Fairness

\* ------------------------------------------------------------------ requirements as properties

\* @req REQ-13  Before the host starts: no store connection, no schema check, no reconciliation.
Inv_NoIOBeforeHostStart == \A n \in Nodes : nd[n].st = "none" => ~nd[n].io

\* @req REQ-14  Build-time tooling never starts the scheduler or any worker.
Inv_NoWorkerInBuildTooling ==
  \A n \in Nodes : cfg[n].tool => (~nd[n].workerActive /\ nd[n].inFlight = 0)

\* @req REQ-15  No store configured -> the in-memory store (reachable, fresh schema).
Inv_InMemoryWhenNoStore == \A n \in Nodes : ~cfg[n].conf => (Reach(n) /\ Sch(n) = cfg[n].exp)

\* @req REQ-20  No worker registered -> never claim or execute a job.
Inv_NoJobsWithoutWorker == \A n \in Nodes : ~HasWorker(n) => (~nd[n].claimedEver /\ nd[n].inFlight = 0)

\* @req REQ-40  No worker registered -> no background duty.
Inv_NoDutiesWithoutWorker == \A n \in Nodes : ~HasWorker(n) => ~nd[n].workerActive

\* @req REQ-24  Applying already-applied migrations leaves the schema unchanged.
Prop_MigrationIdempotent ==
  [][\A n \in Nodes : (Migrate(n) /\ schema >= cfg[n].exp) => schema' = schema]_vars

\* @req REQ-42  The schema only changes in a step taken by the holder of the migration lock.
Prop_MigrateOnlyUnderLock ==
  [][schema' # schema => (lock # NULL /\ lock' = NULL)]_vars

\* @req SCN-2 (then)  A node with an invalid option never runs and never claims.
Scn_InvalidOptionNeverClaims ==
  \A n \in Nodes : ~cfg[n].valid => (~nd[n].claimedEver /\ nd[n].st # "Running")

\* @req SCN-3  AutoMigrate off, schema two versions behind: REQ-18 is never enabled (impossibleAt 3).
Scn_SchemaMismatchBlocksRunning ==
  \A n \in Nodes :
    (nd[n].st = "Starting" /\ ~cfg[n].auto /\ Sch(n) + 1 < cfg[n].exp) => ~ENABLED MarkRunning(n)

\* ------------------------------------------------------------------ derived checks (assumptions table)

\* A-5 from REQ-27 / SCN-4: once the host has stopped, the node does not run (and so does not claim).
Chk_NoRunningAfterHostStop == \A n \in Nodes : nd[n].hostStopped => nd[n].st # "Running"
Chk_NoClaimAfterHostStop   == \A n \in Nodes : ~nd[n].claimedAfterStop

\* A-10 from REQ-22: with AutoMigrate on, a node does not start running on a schema older than expected.
Chk_MigrateBeforeRunning == \A n \in Nodes : ~nd[n].ranUnmigrated

\* A-11 from REQ-30: while processing is stalled and it has been reported, the node stays Unhealthy.
Chk_StallStaysUnhealthy ==
  \A n \in Nodes : (Alive(n) /\ nd[n].stalled /\ nd[n].stallReported) => nd[n].health = "Unhealthy"

\* A-4 from REQ-12: recurring jobs are only reconciled into a schema the node accepts.
Chk_ReconcileOnAcceptedSchema == \A n \in Nodes : ~nd[n].reconcileBad

\* A-12 from REQ-9: a node whose options fail validation does not migrate the shared store.
Chk_NoMigrationWithInvalidOptions == \A n \in Nodes : ~nd[n].migrateBad

\* @req REQ-56  While a node holds the store's migration lock, that node is starting (was A-13's check).
Inv_LockHolderStarting == lock # NULL => nd[lock].st = "Starting"
Chk_LockHolderStarting == Inv_LockHolderStarting   \* name kept for traces/Chk_LockHolderStarting*.cfg

\* @req REQ-59  A node without the alerts registration runs no notification check.
Inv_NoNotificationWithoutAlerts == \A n \in Nodes : nd[n].notifActive => cfg[n].alerts

\* @req REQ-58, REQ-35  Recovery from Unhealthy always passes through Degraded (hosting F-8).
Prop_NoUnhealthyToHealthy ==
  [][\A n \in Nodes : nd[n].health = "Unhealthy" => nd'[n].health # "Healthy"]_vars

\* A-21 from REQ-12: a worker node reconciles code-defined recurring jobs before it is marked running.
Chk_ReconciledBeforeRunning ==
  \A n \in Nodes : (nd[n].st = "Running" /\ HasWorker(n)) => nd[n].reconciled

\* A-12 extended (A-19): a node that will fail another module's startup check does not write to the
\* shared store first (migrate or reconcile).
Chk_NoStoreWriteBeforeOtherChecks == \A n \in Nodes : ~nd[n].otherBad

\* A-22 retired: recurring REQ-236 now says what it reads on an unmigrated store (name and origin only;
\* none where there is no Bellhop schema), so run 3's Chk_StoreChecksOnAcceptedSchema is gone.
\* Trap (expected violated): a node started on a new database (no Bellhop schema) migrates and runs.
Chk_NewDatabaseNotRunning == ~(\E n \in Nodes : nd[n].st = "Running" /\ nd[n].checkedEmpty)

\* A-25 from REQ-12 (run 3 F-2): a node whose Redis connection checks fail never checks the schema, reads
\* stored data, migrates or reconciles; it fails the start under REQ-502/REQ-505, not REQ-23/REQ-43.
Chk_ConnectChecksFirst ==
  \A n \in Nodes : (cfg[n].conf /\ cfg[n].ok = "failConnect") =>
                     (~nd[n].connected /\ ~nd[n].storeChecked /\ ~nd[n].reconciled)

\* A-24 from REQ-29 with REQ-28 and jobs REQ-138: a node does not stop before ShutdownTimeout while a
\* timed-out handler has not settled under jobs REQ-138/REQ-186.
Chk_NoStopInGraceBeforeTimeout == \A n \in Nodes : ~nd[n].stopInGrace

\* A-14 from SCN-1 "exactly one warning": the in-memory warning is logged at most once per start.
Chk_OneMemoryWarning == \A n \in Nodes : nd[n].memWarnings <= 1
\* A-14 from SCN-1: a Production node running on the in-memory store has logged the warning.
Chk_MemoryWarningBeforeRunning ==
  \A n \in Nodes : (nd[n].st = "Running" /\ ~cfg[n].conf /\ ~cfg[n].dev) => nd[n].memWarnings >= 1

\* A-9 from REQ-28/REQ-29: a draining node eventually stops.
Chk_DrainEnds == \A n \in Nodes : (nd[n].st = "Draining") ~> (nd[n].st = "Stopped")

\* A-26 from REQ-29 with jobs REQ-190 (trap, expected violated): a node stops after marking a job whose
\* cancellation was requested cancelled at shutdown.
Chk_NoShutdownCancellation == ~(\E n \in Nodes : nd[n].st = "Stopped" /\ nd[n].cancelled > 0)

\* ------------------------------------------------------------------ positive scenarios (trap invariants)

\* @req SCN-1  Production, no store -> Running on the in-memory store with exactly one warning.
Scn1_NotReached == ~(\E n \in Nodes : nd[n].st = "Running" /\ ~cfg[n].conf /\ nd[n].memWarnings = 1)

\* @req SCN-2  Invalid option -> StartupFailed and nothing claimed.
Scn2_NotReached == ~(\E n \in Nodes : nd[n].st = "StartupFailed" /\ ~cfg[n].valid /\ ~nd[n].claimedEver)

\* @req SCN-4  Graceful shutdown: one job finishes, one is cancelled and released; node Stopped.
Init_SCN4 ==
  /\ cfg \in [Nodes -> {c \in CfgSet : c.reg = "worker" /\ c.valid /\ c.conf /\ ~c.tool /\ c.ok = "pass"}]
  /\ schema \in InitSchemaVals /\ \A n \in Nodes : schema = cfg[n].exp
  /\ reachable = TRUE /\ lock = NULL /\ fewAlive = FALSE
  /\ nd = [n \in Nodes |-> [Fresh EXCEPT !.st = "Running", !.validated = TRUE, !.workerActive = TRUE,
                                         !.prechecked = TRUE, !.connected = TRUE, !.storeChecked = TRUE,
                                         !.reconciled = TRUE,
                                         !.inFlight = 2,
                                         !.claimedEver = TRUE, !.io = TRUE, !.summaryLogged = TRUE]]
Spec_SCN4 == Init_SCN4 /\ [][Next]_vars
Scn4_NotReached ==
  ~(\E n \in Nodes : nd[n].st = "Stopped" /\ ~nd[n].claimedAfterStop /\ nd[n].released = 1)

\* @req SCN-5  Library N+1, AutoMigrate off, store on N -> Running on N, no migration.
Scn5_NotReached ==
  ~(\E n \in Nodes : nd[n].st = "Running" /\ ~cfg[n].auto /\ schema + 1 = cfg[n].exp)

\* @req SCN-6  Store down at startup: node Starting, reports Unhealthy, nothing claimed, host up.
Scn6_NotReached ==
  ~(\E n \in Nodes : nd[n].st = "Starting" /\ ~reachable /\ nd[n].health = "Unhealthy"
                     /\ ~nd[n].claimedEver /\ ~nd[n].hostStopped)
=============================================================================
