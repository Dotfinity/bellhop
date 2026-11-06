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
          MaxInFlight,      \* worker concurrency in the model (real value irrelevant)
          HealthyAfterPasses, \* @req REQ-50 (3 in the policy; 2 in the model)
          HealthEnv,        \* TRUE: stalls, thresholds and node-count changes may happen
          NULL

ASSUME HealthyAfterPasses \in Nat \ {0}                     \* @req REQ-50
ASSUME \A e \in ExpectedVals : e >= 1 /\ e \in Versions
ASSUME RegVals \subseteq {"none", "client", "worker"}

NodeStatus == {"none", "Starting", "Running", "Draining", "Stopped", "StartupFailed"}
Final      == {"Stopped", "StartupFailed"}
HealthVal  == {"Healthy", "Degraded", "Unhealthy"}

\* Per-process configuration, fixed for the life of one process.
CfgSet == [reg: RegVals, auto: AutoVals, valid: ValidVals, tool: ToolVals,
           conf: ConfVals, dev: DevVals, exp: ExpectedVals]

NodeRec == [st: NodeStatus,
            hostStopped: BOOLEAN,       \* the host has signalled stop
            workerActive: BOOLEAN,      \* worker loop + background duties started (REQ-18, REQ-40)
            inFlight: 0..MaxInFlight,
            timeoutPassed: BOOLEAN,     \* REQ-28 ShutdownTimeout has passed
            released: 0..MaxInFlight,   \* jobs released back to the store at shutdown (jobs REQ-140)
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

Fresh == [st |-> "none", hostStopped |-> FALSE, workerActive |-> FALSE, inFlight |-> 0,
          timeoutPassed |-> FALSE, released |-> 0, claimedEver |-> FALSE, claimedAfterStop |-> FALSE,
          reconciled |-> FALSE, reconcileBad |-> FALSE, migrateBad |-> FALSE, ranUnmigrated |-> FALSE,
          memWarnings |-> 0, summaryLogged |-> FALSE, io |-> FALSE,
          health |-> "Healthy", passes |-> 0, stalled |-> FALSE, stallReported |-> FALSE,
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
\* "all startup checks have passed" (REQ-18) read as: no condition of REQ-9/REQ-23/REQ-43 holds (A-2).
StartupChecksPassed(n) == cfg[n].valid /\ Accepted(n)

Init ==
  /\ cfg \in [Nodes -> CfgSet]
  /\ nd = [n \in Nodes |-> Fresh]
  /\ schema \in InitSchemaVals
  /\ reachable \in InitReachVals
  /\ lock = NULL
  /\ fewAlive = FALSE

\* ------------------------------------------------------------------ startup

\* @req REQ-12  When the host starts, start the Bellhop node (no I/O before this: REQ-13).
HostStarts(n) ==
  /\ nd[n].st = "none"
  /\ nd' = [nd EXCEPT ![n].st = "Starting"]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req REQ-9  While starting, if an option fails validation, stop the node from starting.
ValidationFails(n) ==
  /\ nd[n].st = "Starting"
  /\ ~cfg[n].valid
  /\ nd' = [nd EXCEPT ![n].st = "StartupFailed"]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req REQ-23  AutoMigrate off and schema more than one version older -> StartupFailed.
SchemaTooOld(n) ==
  /\ nd[n].st = "Starting"
  /\ Reach(n)
  /\ ~cfg[n].auto
  /\ Sch(n) + 1 < cfg[n].exp
  /\ nd' = [nd EXCEPT ![n].st = "StartupFailed", ![n].io = TRUE]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req REQ-43  Stored schema newer than expected -> StartupFailed (AutoMigrate on or off).
SchemaTooNew(n) ==
  /\ nd[n].st = "Starting"
  /\ Reach(n)
  /\ Sch(n) > cfg[n].exp
  /\ nd' = [nd EXCEPT ![n].st = "StartupFailed", ![n].io = TRUE]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req REQ-22, REQ-42  AutoMigrate on and schema older: only the holder of the store's migration
\*                      lock migrates; the others wait (this action is disabled for them) and re-read.
AcquireMigrationLock(n) ==
  /\ nd[n].st = "Starting"
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
  /\ nd' = [nd EXCEPT ![n].migrateBad = nd[n].migrateBad \/ ~cfg[n].valid]
  /\ UNCHANGED <<cfg, reachable, fewAlive>>

\* @req REQ-16  While starting, no store configured and not Development -> warn (in-memory store in use).
WarnInMemoryStore(n) ==
  /\ nd[n].st = "Starting"
  /\ ~cfg[n].conf /\ ~cfg[n].dev
  /\ nd[n].memWarnings < 2
  /\ nd' = [nd EXCEPT ![n].memWarnings = @ + 1]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req REQ-12  ...connect to the store, check the schema and, where the worker is registered,
\*              reconcile code-defined recurring jobs. The sentence orders reconciliation after the
\*              schema *check*, not after the check *passed* or migration (A-4): left nondeterministic.
ReconcileRecurring(n) ==
  /\ nd[n].st = "Starting"
  /\ HasWorker(n) /\ Reach(n)
  /\ ~nd[n].reconciled
  /\ nd' = [nd EXCEPT ![n].reconciled = TRUE, ![n].io = TRUE,
                      ![n].reconcileBad = ~Accepted(n)]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req REQ-18  Store reachable, schema accepted, startup checks passed -> Running; start the worker.
\* @req REQ-19  Same event: log the one-screen summary.
\* @req REQ-25  Claims only once the store is reachable (guard Reach).
MarkRunning(n) ==
  /\ nd[n].st = "Starting"
  /\ Reach(n)
  /\ StartupChecksPassed(n)
  /\ nd' = [nd EXCEPT ![n].st = "Running", ![n].workerActive = HasWorker(n),
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
  /\ nd[n].inFlight < MaxInFlight
  /\ nd' = [nd EXCEPT ![n].inFlight = @ + 1, ![n].claimedEver = TRUE, ![n].io = TRUE,
                      ![n].claimedAfterStop = @ \/ nd[n].hostStopped]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* Handler returns (jobs module; not obliged — a handler may ignore cancellation).
JobFinishes(n) ==
  /\ nd[n].st \in {"Running", "Draining"}
  /\ nd[n].inFlight > 0
  /\ nd' = [nd EXCEPT ![n].inFlight = @ - 1]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* ------------------------------------------------------------------ shutdown

\* Environment: the host signals stop. @req REQ-27  While running -> Draining (stop claiming).
\* While Starting no requirement says anything: the flag is set and the status is unchanged (A-5).
HostStops(n) ==
  /\ nd[n].st \in {"Starting", "Running"}
  /\ ~nd[n].hostStopped
  /\ nd' = [nd EXCEPT ![n].hostStopped = TRUE,
                      ![n].st = IF nd[n].st = "Running" THEN "Draining" ELSE "Starting"]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req REQ-28  ShutdownTimeout passes (no clock: may happen at any moment while draining, A-1).
TimeoutPasses(n) ==
  /\ nd[n].st = "Draining"
  /\ ~nd[n].timeoutPassed
  /\ nd' = [nd EXCEPT ![n].timeoutPassed = TRUE]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* REQ-29's precondition "tokens cancelled and leases released" — done by jobs REQ-140 (A-7).
\* Releasing a lease is a store write, so it needs the store.
CancelAndRelease(n) ==
  /\ nd[n].st = "Draining"
  /\ nd[n].timeoutPassed
  /\ nd[n].inFlight > 0
  /\ Reach(n)
  /\ nd' = [nd EXCEPT ![n].released = @ + nd[n].inFlight, ![n].inFlight = 0]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req REQ-29  Draining, every in-flight job finished (or timed out and released) -> Stopped.
StopNode(n) ==
  /\ nd[n].st = "Draining"
  /\ nd[n].inFlight = 0
  /\ nd' = [nd EXCEPT ![n].st = "Stopped", ![n].workerActive = FALSE]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* ------------------------------------------------------------------ health

Alive(n) == nd[n].st \in {"Starting", "Running", "Draining"}

UnhealthyCond(n) ==
  \/ ~Reach(n)                                   \* REQ-31
  \/ ~Accepted(n)                                \* REQ-32
  \/ HasWorker(n) /\ ~nd[n].workerActive         \* REQ-33  worker loop not alive
  \/ fewAlive                                    \* REQ-44  fewer than MinNodesAlive (A-8)

\* @req REQ-31, REQ-32, REQ-33, REQ-44, REQ-34, REQ-35  one event "the health check runs" (lint warning):
\* Unhealthy checks first; else Degraded thresholds (REQ-34); else count a pass and, after
\* HealthyAfterPasses passes in a row, report Healthy (REQ-35). Where no requirement covers the
\* current status (e.g. Unhealthy and still failing) the status stays.
HealthCheck(n) ==
  /\ Alive(n)
  /\ LET h == nd[n].health
         p == Min(nd[n].passes + 1, HealthyAfterPasses)
     IN  IF UnhealthyCond(n)
           THEN nd' = [nd EXCEPT ![n].health = IF h \in {"Healthy", "Degraded"} THEN "Unhealthy" ELSE h,
                                 ![n].passes = 0]
         ELSE IF nd[n].degradedCond
           THEN nd' = [nd EXCEPT ![n].health = IF h \in {"Healthy", "Unhealthy"} THEN "Degraded" ELSE h,
                                 ![n].passes = 0]
         ELSE nd' = [nd EXCEPT ![n].passes = p,
                               ![n].health = IF p >= HealthyAfterPasses /\ h \in {"Degraded", "Unhealthy"}
                                             THEN "Healthy" ELSE h]
  /\ UNCHANGED <<cfg, schema, reachable, lock, fewAlive>>

\* @req REQ-30  If an internal error stalls processing, report the node Unhealthy.
ReportStall(n) ==
  /\ Alive(n)
  /\ nd[n].stalled
  /\ nd[n].health \in {"Healthy", "Degraded"}
  /\ nd' = [nd EXCEPT ![n].health = "Unhealthy", ![n].stallReported = TRUE]
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
  \/ HostStarts(n) \/ ValidationFails(n) \/ SchemaTooOld(n) \/ SchemaTooNew(n)
  \/ AcquireMigrationLock(n) \/ Migrate(n) \/ WarnInMemoryStore(n) \/ ReconcileRecurring(n)
  \/ MarkRunning(n) \/ Claim(n) \/ JobFinishes(n) \/ HostStops(n) \/ TimeoutPasses(n)
  \/ CancelAndRelease(n) \/ StopNode(n) \/ HealthCheck(n) \/ ReportStall(n)
  \/ Stall(n) \/ Unstall(n) \/ ToggleDegraded(n) \/ Archive(n)

Next ==
  \/ \E n \in Nodes : NodeStep(n)
  \/ StoreGoesDown \/ StoreComesBack \/ ToggleFewAlive

\* System-actor transitions are fair (REQ-30..35, REQ-44). For the diagnostic Chk_DrainEnds the
\* host-side shutdown steps are also treated as obligations of the software (A-9); the store,
\* handlers and the host's own stop signal are not. The release is strongly fair so that a store
\* which keeps coming back is enough; only a store that stays down can block it.
Fairness ==
  \A n \in Nodes :
    /\ WF_vars(HealthCheck(n)) /\ WF_vars(ReportStall(n))
    /\ WF_vars(TimeoutPasses(n)) /\ SF_vars(CancelAndRelease(n)) /\ WF_vars(StopNode(n))

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

\* A-13 from REQ-42: the migration lock is held only by a node that is still starting.
Chk_LockHolderStarting == lock # NULL => nd[lock].st = "Starting"

\* A-14 from SCN-1 "exactly one warning": the in-memory warning is logged at most once per start.
Chk_OneMemoryWarning == \A n \in Nodes : nd[n].memWarnings <= 1
\* A-14 from SCN-1: a Production node running on the in-memory store has logged the warning.
Chk_MemoryWarningBeforeRunning ==
  \A n \in Nodes : (nd[n].st = "Running" /\ ~cfg[n].conf /\ ~cfg[n].dev) => nd[n].memWarnings >= 1

\* A-9 from REQ-28/REQ-29: a draining node eventually stops.
Chk_DrainEnds == \A n \in Nodes : (nd[n].st = "Draining") ~> (nd[n].st = "Stopped")

\* ------------------------------------------------------------------ positive scenarios (trap invariants)

\* @req SCN-1  Production, no store -> Running on the in-memory store with exactly one warning.
Scn1_NotReached == ~(\E n \in Nodes : nd[n].st = "Running" /\ ~cfg[n].conf /\ nd[n].memWarnings = 1)

\* @req SCN-2  Invalid option -> StartupFailed and nothing claimed.
Scn2_NotReached == ~(\E n \in Nodes : nd[n].st = "StartupFailed" /\ ~cfg[n].valid /\ ~nd[n].claimedEver)

\* @req SCN-4  Graceful shutdown: one job finishes, one is cancelled and released; node Stopped.
Init_SCN4 ==
  /\ cfg \in [Nodes -> {c \in CfgSet : c.reg = "worker" /\ c.valid /\ c.conf /\ ~c.tool}]
  /\ schema \in InitSchemaVals /\ \A n \in Nodes : schema = cfg[n].exp
  /\ reachable = TRUE /\ lock = NULL /\ fewAlive = FALSE
  /\ nd = [n \in Nodes |-> [Fresh EXCEPT !.st = "Running", !.workerActive = TRUE, !.inFlight = 2,
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
