----------------------------- MODULE Redis -----------------------------
\* Generated from specs/redis.json (specHash eb75d09b96bf) - edit the requirements, not this file.
\* Every action/property carries an @req comment naming the requirement it encodes.
\* Entities of other modules (hosting.Node, hosting.Health, jobs.Job, jobs.Maintenance,
\* recurring.RecurringJob) are abstracted to the few fields the redis requirements touch;
\* each abstraction is listed in specs/redis.findings.md (Modeling assumptions).
EXTENDS Naturals, FiniteSets

CONSTANTS Nodes,         \* hosting.Node instances (bound 2)
          WorkerNodes,   \* nodes with AddWorker (hosting REQ-20, REQ-40)
          Jobs,          \* jobs.Job ids; every id is enqueued at most once (fresh GUIDs)
          QueueA,        \* jobs in queue qA; the rest are in qB (for INV-500 / INV-100)
          KeyMax,        \* jobs INV-108: Max of the one concurrency key all model jobs share
          ShardByQueue,  \* @req INV-500 option
          FreshStore,    \* TRUE: first start against an empty server (no marker yet)
          LossKinds,     \* subset of {"flush", "evict", "restore"} enabled in this run
          MaxLosses,     \* at most this many data-loss events (environment bound)
          AllowStop,     \* hosts may stop nodes (hosting REQ-27/29, abstracted)
          CheckHealth,   \* model switch: include health-check runs (keeps non-health runs small)
          MemToggle,     \* model switch: let used_memory cross the REQ-519 threshold
          MaxOutages,    \* at most this many times the server becomes unreachable (A-5)
          NULL

\* @req REQ-512  capability set: no transactional enqueue; push notifications and result storage.
\*               No action in this model reads it (absorbed).
\* @req REQ-513  payload hard limit 256 KB - absorbed: payload sizes are not modeled.
\* @req REQ-520  RedisMemoryDegradedShare = 80% - absorbed into the boolean memHigh (A-6).
ASSUME /\ WorkerNodes \subseteq Nodes /\ QueueA \subseteq Jobs
       /\ KeyMax \in Nat \ {0}
       /\ LossKinds \subseteq {"flush", "evict", "restore"}
       /\ MaxLosses \in Nat
       /\ ShardByQueue \in BOOLEAN /\ FreshStore \in BOOLEAN /\ AllowStop \in BOOLEAN
       /\ CheckHealth \in BOOLEAN /\ MemToggle \in BOOLEAN /\ MaxOutages \in Nat

VARIABLES
  \* per node
  node,        \* hosting.Node status
  rs,          \* RedisStore status as seen by this node
  health,      \* hosting.Health status
  chk,         \* what the last health check on this node saw: "none" | "reachable" | "unreachable"
  run,         \* job whose handler runs on this node, or NULL
  claimGen,    \* generation marker value read when that job was claimed
  \* the Redis server (shared by all nodes)
  marker,      \* generation marker: 0 = missing
  nextGen,     \* last generation value ever written
  codeRec,     \* code-defined recurring job (nightly-cleanup) is stored
  registry,    \* queue registry is stored
  unacked,     \* "store reset not acknowledged" record (A-4: kept in the store)
  maint,       \* jobs.Maintenance flag (stored)
  jobRec,      \* job records: [st, owner]
  snap,        \* a snapshot / replica image a restore or failover can roll back to
  \* environment
  evalOK,      \* server supports EVAL
  reachable,   \* server reachable
  memHigh,     \* used_memory above RedisMemoryDegradedShare of maxmemory
  \* history (observation only - no action is guarded by these)
  created, maintIntent, pendingLoss, falseReset, lostOutcome, detections, losses, everAcked,
  outages      \* environment counter: times the server became unreachable

nodeVars  == <<node, rs, health, chk, run, claimGen>>
storeVars == <<marker, nextGen, codeRec, registry, unacked, maint, jobRec, snap>>
envVars   == <<evalOK, reachable, memHigh, outages>>
histVars  == <<created, maintIntent, pendingLoss, falseReset, lostOutcome, detections, losses, everAcked>>
vars      == <<nodeVars, storeVars, envVars, histVars>>

NodeStatus  == {"Starting", "Running", "Stopped", "StartupFailed"}
StoreStatus == {"Connecting", "Ready", "Reconciling"}
HealthSt    == {"Healthy", "Degraded", "Unhealthy"}
JobSt       == {"none", "enqueued", "processing", "done", "recreated"}
ActiveSt    == {"enqueued", "processing"}            \* jobs REQ-107 (the subset modeled)
MaxGen      == 1 + Cardinality(Nodes) * (MaxLosses + 2)
Gens        == 0..MaxGen
JobRec      == [st: JobSt, owner: Nodes \cup {NULL}]
NoJob       == [st |-> "none", owner |-> NULL]
Data        == [codeRec: BOOLEAN, registry: BOOLEAN, unacked: BOOLEAN, maint: BOOLEAN,
                jobRec: [Jobs -> JobRec]]

TypeInv ==
  /\ node     \in [Nodes -> NodeStatus]
  /\ rs       \in [Nodes -> StoreStatus]
  /\ health   \in [Nodes -> HealthSt]
  /\ chk      \in [Nodes -> {"none", "reachable", "unreachable"}]
  /\ run      \in [Nodes -> Jobs \cup {NULL}]
  /\ claimGen \in [Nodes -> Gens]
  /\ marker \in Gens /\ nextGen \in Gens
  /\ codeRec \in BOOLEAN /\ registry \in BOOLEAN /\ unacked \in BOOLEAN /\ maint \in BOOLEAN
  /\ jobRec \in [Jobs -> JobRec]
  /\ snap \in [marker: Gens, data: Data]
  /\ evalOK \in BOOLEAN /\ reachable \in BOOLEAN /\ memHigh \in BOOLEAN /\ outages \in 0..MaxOutages
  /\ created \in [Jobs -> BOOLEAN] /\ maintIntent \in BOOLEAN
  /\ pendingLoss \in BOOLEAN /\ falseReset \in BOOLEAN /\ lostOutcome \in BOOLEAN
  /\ detections \in Nat /\ losses \in 0..MaxLosses /\ everAcked \in BOOLEAN

DataNow == [codeRec |-> codeRec, registry |-> registry, unacked |-> unacked,
            maint |-> maint, jobRec |-> jobRec]

Init ==
  /\ node = [n \in Nodes |-> "Starting"]
  /\ rs = [n \in Nodes |-> "Connecting"]
  /\ health = [n \in Nodes |-> "Healthy"]
  /\ chk = [n \in Nodes |-> "none"]
  /\ run = [n \in Nodes |-> NULL]
  /\ claimGen = [n \in Nodes |-> 0]
  \* an established store carries generation 1 and its seeded data; a fresh one has nothing
  /\ marker = IF FreshStore THEN 0 ELSE 1
  /\ nextGen = marker
  /\ codeRec = ~FreshStore
  /\ registry = ~FreshStore
  /\ unacked = FALSE
  /\ maint = FALSE
  /\ jobRec = [j \in Jobs |-> NoJob]
  /\ snap = [marker |-> marker, data |-> [codeRec |-> codeRec, registry |-> registry,
             unacked |-> FALSE, maint |-> FALSE, jobRec |-> [j \in Jobs |-> NoJob]]]
  /\ evalOK \in BOOLEAN
  /\ reachable = TRUE
  /\ memHigh = FALSE
  /\ outages = 0
  /\ created = [j \in Jobs |-> FALSE]
  /\ maintIntent = FALSE
  /\ pendingLoss = FALSE /\ falseReset = FALSE /\ lostOutcome = FALSE
  /\ detections = 0 /\ losses = 0 /\ everAcked = FALSE

Up(n) == node[n] \in {"Starting", "Running"}

---------------------------------------------------------------------------
\* Startup

\* @req REQ-500 REQ-501  Same event: connection established and a trivial EVAL succeeds -> store
\*   ready; family/version detected (REQ-500) or, if unrecognised, a warning (REQ-501). Family,
\*   version and log lines carry no state here. REQ-503, REQ-504, REQ-505 are log-only
\*   consequences of "the store becomes ready" and are absorbed into this action and FinishReconcile.
Connect(n) ==
  /\ node[n] = "Starting" /\ rs[n] = "Connecting"
  /\ reachable /\ evalOK
  /\ rs' = [rs EXCEPT ![n] = "Ready"]
  /\ UNCHANGED <<node, health, chk, run, claimGen, storeVars, envVars, histVars>>

\* @req REQ-502  A server without EVAL stops the node from starting.
StartupNoEval(n) ==
  /\ node[n] = "Starting" /\ rs[n] = "Connecting"
  /\ reachable /\ ~evalOK
  /\ node' = [node EXCEPT ![n] = "StartupFailed"]
  /\ UNCHANGED <<rs, health, chk, run, claimGen, storeVars, envVars, histVars>>

\* context: hosting REQ-18 - node runs once its startup checks passed; A-1: "store ready" is one of them.
NodeRuns(n) ==
  /\ node[n] = "Starting" /\ rs[n] = "Ready"
  /\ node' = [node EXCEPT ![n] = "Running"]
  /\ UNCHANGED <<rs, health, chk, run, claimGen, storeVars, envVars, histVars>>

\* context: hosting REQ-27/REQ-29 abstracted - the host stops a node (human/host actor, not fair).
\* The handler's outcome is dropped with it (A-8).
NodeStops(n) ==
  /\ AllowStop /\ node[n] = "Running"
  /\ node' = [node EXCEPT ![n] = "Stopped"]
  /\ run' = [run EXCEPT ![n] = NULL]
  /\ UNCHANGED <<rs, health, chk, claimGen, storeVars, envVars, histVars>>

---------------------------------------------------------------------------
\* Flush / eviction / restore resilience

\* @req REQ-507 REQ-523  While ready, marker found missing -> StoreWasReset ERROR, ERROR about
\*   runtime-defined recurring jobs, reset recorded as unacknowledged, start re-seeding.
\*   A-2: the marker check runs on any running node (REQ-507 names no worker restriction).
DetectReset(n) ==
  /\ node[n] = "Running" /\ rs[n] = "Ready" /\ reachable
  /\ marker = 0
  /\ rs' = [rs EXCEPT ![n] = "Reconciling"]
  /\ unacked' = TRUE
  /\ detections' = detections + 1
  /\ falseReset' = (falseReset \/ ~pendingLoss)
  /\ pendingLoss' = FALSE
  /\ UNCHANGED <<node, health, chk, run, claimGen, marker, nextGen, codeRec, registry, maint,
                 jobRec, snap, envVars, created, maintIntent, lostOutcome, losses, everAcked>>

\* @req REQ-507  "re-seeding the code-defined recurring jobs and the queue registry".
\*   Context recurring REQ-203 / hosting REQ-40, REQ-53: only a node with the worker registered
\*   declares (and so can re-seed) code-defined recurring jobs and queues (A-3).
Reseed(n) ==
  /\ node[n] = "Running" /\ rs[n] = "Reconciling" /\ reachable
  /\ n \in WorkerNodes
  /\ ~(codeRec /\ registry)
  /\ codeRec' = TRUE /\ registry' = TRUE
  /\ UNCHANGED <<nodeVars, marker, nextGen, unacked, maint, jobRec, snap, envVars, histVars>>

\* @req REQ-509  While reconciling, when re-seeded -> write a new generation marker, store ready.
FinishReconcile(n) ==
  /\ node[n] = "Running" /\ rs[n] = "Reconciling" /\ reachable
  /\ codeRec /\ registry
  /\ nextGen' = nextGen + 1
  /\ marker' = nextGen + 1
  /\ rs' = [rs EXCEPT ![n] = "Ready"]
  /\ UNCHANGED <<node, health, chk, run, claimGen, codeRec, registry, unacked, maint, jobRec,
                 snap, envVars, histVars>>

\* @req REQ-510  While ready, every RecurringReconcileInterval: reconcile code-defined recurring
\*   jobs again (recurring REQ-203 recreates a missing one). Worker duty (hosting REQ-40).
PeriodicReconcile(n) ==
  /\ node[n] = "Running" /\ rs[n] = "Ready" /\ reachable
  /\ n \in WorkerNodes
  /\ ~codeRec
  /\ codeRec' = TRUE
  /\ UNCHANGED <<nodeVars, marker, nextGen, registry, unacked, maint, jobRec, snap, envVars, histVars>>

\* @req REQ-525  Operator acknowledges the reset on the dashboard (human actor: not fair).
Acknowledge ==
  /\ unacked /\ reachable
  /\ unacked' = FALSE /\ everAcked' = TRUE
  /\ UNCHANGED <<nodeVars, marker, nextGen, codeRec, registry, maint, jobRec, snap, envVars,
                 created, maintIntent, pendingLoss, falseReset, lostOutcome, detections, losses>>

\* environment: FLUSHALL (REQ-507 notes: cause 1). Everything in the server is gone.
Flush ==
  /\ "flush" \in LossKinds /\ losses < MaxLosses /\ reachable
  /\ marker' = 0 /\ codeRec' = FALSE /\ registry' = FALSE /\ unacked' = FALSE /\ maint' = FALSE
  /\ jobRec' = [j \in Jobs |-> NoJob]
  /\ pendingLoss' = TRUE /\ losses' = losses + 1
  /\ UNCHANGED <<nodeVars, nextGen, snap, envVars, created, maintIntent, falseReset, lostOutcome, detections, everAcked>>

\* environment: eviction (REQ-505 notes: possible unless maxmemory-policy is noeviction).
\* Evicts one key: the marker alone, or one job record, or the recurring definition.
EvictMarker ==
  /\ "evict" \in LossKinds /\ losses < MaxLosses /\ reachable /\ marker # 0
  /\ marker' = 0 /\ losses' = losses + 1
  /\ UNCHANGED <<nodeVars, nextGen, codeRec, registry, unacked, maint, jobRec, snap, envVars,
                 created, maintIntent, pendingLoss, falseReset, lostOutcome, detections, everAcked>>

EvictJob(j) ==
  /\ "evict" \in LossKinds /\ losses < MaxLosses /\ reachable /\ jobRec[j].st # "none"
  /\ jobRec' = [jobRec EXCEPT ![j] = NoJob]
  /\ pendingLoss' = TRUE /\ losses' = losses + 1
  /\ UNCHANGED <<nodeVars, marker, nextGen, codeRec, registry, unacked, maint, snap, envVars,
                 created, maintIntent, falseReset, lostOutcome, detections, everAcked>>

EvictRecurring ==
  /\ "evict" \in LossKinds /\ losses < MaxLosses /\ reachable /\ codeRec
  /\ codeRec' = FALSE
  /\ pendingLoss' = TRUE /\ losses' = losses + 1
  /\ UNCHANGED <<nodeVars, marker, nextGen, registry, unacked, maint, jobRec, snap, envVars,
                 created, maintIntent, falseReset, lostOutcome, detections, everAcked>>

\* environment: an RDB/AOF snapshot is taken, or a replica lags behind (REQ-504: replication is async).
TakeSnapshot ==
  /\ "restore" \in LossKinds /\ reachable /\ marker # 0
  /\ snap' = [marker |-> marker, data |-> DataNow]
  /\ snap # snap'
  /\ UNCHANGED <<nodeVars, marker, nextGen, codeRec, registry, unacked, maint, jobRec, envVars, histVars>>

\* environment: restore from an old snapshot (REQ-507 notes: cause 3) or failover to a lagging
\* replica (REQ-504). The server rolls back to the image, marker included.
Restore ==
  /\ "restore" \in LossKinds /\ losses < MaxLosses /\ reachable
  /\ snap.data # DataNow
  /\ marker' = snap.marker
  /\ codeRec' = snap.data.codeRec /\ registry' = snap.data.registry
  /\ unacked' = snap.data.unacked /\ maint' = snap.data.maint /\ jobRec' = snap.data.jobRec
  /\ pendingLoss' = TRUE /\ losses' = losses + 1
  /\ UNCHANGED <<nodeVars, nextGen, snap, envVars, created, maintIntent, falseReset, lostOutcome, detections, everAcked>>

---------------------------------------------------------------------------
\* Jobs, as far as the reset rules touch them (context from the jobs module)

\* context: jobs REQ-182 / INV-100 / REQ-150 (Ignore) with the scope of @req INV-500.
JobQueue(j) == IF j \in QueueA THEN "qA" ELSE "qB"
SameScope(j, k) == IF ShardByQueue THEN JobQueue(j) = JobQueue(k) ELSE TRUE
Enqueue(j) ==
  /\ ~created[j] /\ reachable
  /\ ~\E k \in Jobs : jobRec[k].st \in ActiveSt /\ SameScope(j, k)
  /\ jobRec' = [jobRec EXCEPT ![j] = [st |-> "enqueued", owner |-> NULL]]
  /\ created' = [created EXCEPT ![j] = TRUE]
  /\ UNCHANGED <<nodeVars, marker, nextGen, codeRec, registry, unacked, maint, snap, envVars,
                 maintIntent, pendingLoss, falseReset, lostOutcome, detections, losses, everAcked>>

\* context: jobs REQ-123 - claim, with the concurrency key enforced by the store (INV-108 notes)
\* and the maintenance pause (INV-114). Claims are not restricted while reconciling (silent).
Holders == {j \in Jobs : jobRec[j].st = "processing"}
Claim(n, j) ==
  /\ node[n] = "Running" /\ n \in WorkerNodes /\ rs[n] # "Connecting" /\ reachable
  /\ run[n] = NULL /\ ~maint
  /\ jobRec[j].st = "enqueued"
  /\ Cardinality(Holders) < KeyMax
  /\ jobRec' = [jobRec EXCEPT ![j] = [st |-> "processing", owner |-> n]]
  /\ run' = [run EXCEPT ![n] = j]
  /\ claimGen' = [claimGen EXCEPT ![n] = marker]
  /\ UNCHANGED <<node, rs, health, chk, marker, nextGen, codeRec, registry, unacked, maint, snap,
                 envVars, histVars>>

\* @req REQ-522  A heartbeat/progress write that finds the record missing after a generation
\*   change is ignored and the run continues. Heartbeats change no modeled state, so REQ-522 is
\*   encoded by the absence of any action that stops a run whose record vanished.
\* @req REQ-521  Completion (handler actor - not fair):
\*   record still ours                         -> done (jobs REQ-127)
\*   record missing, generation changed        -> minimal record "recreated" + warning (REQ-521)
\*   record missing, generation NOT changed    -> refused (REQ-521 notes: "still refused")
\*   record present but not our claim          -> refused (jobs INV-128 fencing)
Complete(n) ==
  /\ run[n] # NULL /\ reachable
  /\ LET j == run[n] IN
       /\ jobRec' = [jobRec EXCEPT ![j] =
            CASE jobRec[j].st = "processing" /\ jobRec[j].owner = n -> [st |-> "done", owner |-> n]
              [] jobRec[j].st = "none" /\ marker # claimGen[n]      -> [st |-> "recreated", owner |-> n]
              [] OTHER                                              -> jobRec[j]]
       /\ lostOutcome' = (lostOutcome \/ (jobRec[j].st = "none" /\ marker = claimGen[n]))
  /\ run' = [run EXCEPT ![n] = NULL]
  /\ UNCHANGED <<node, rs, health, chk, claimGen, marker, nextGen, codeRec, registry, unacked,
                 maint, snap, envVars, created, maintIntent, pendingLoss, falseReset, detections, losses, everAcked>>

\* context: jobs REQ-162 / REQ-163 - operator turns maintenance on / off.
MaintOn  == /\ reachable /\ ~maint /\ maint' = TRUE  /\ maintIntent' = TRUE
            /\ UNCHANGED <<nodeVars, marker, nextGen, codeRec, registry, unacked, jobRec, snap, envVars,
                           created, pendingLoss, falseReset, lostOutcome, detections, losses, everAcked>>
MaintOff == /\ reachable /\ maint /\ maint' = FALSE /\ maintIntent' = FALSE
            /\ UNCHANGED <<nodeVars, marker, nextGen, codeRec, registry, unacked, jobRec, snap, envVars,
                           created, pendingLoss, falseReset, lostOutcome, detections, losses, everAcked>>

---------------------------------------------------------------------------
\* Health (hosting.Health per node)

AllPass(n) == reachable /\ rs[n] # "Reconciling" /\ ~memHigh /\ ~unacked
\* One health-check run. Every rule whose guard holds is a possible outcome (A-7: no rule
\* says which wins when two disagree). HealthyAfterPasses abstracted to 1 (A-6).
Outcomes(n) ==
  LET h == health[n]
      r31  == IF ~reachable /\ h \in {"Healthy", "Degraded"} THEN {"Unhealthy"} ELSE {}   \* hosting REQ-31
      r508 == IF rs[n] = "Reconciling" /\ h = "Healthy" THEN {"Degraded"} ELSE {}         \* @req REQ-508
      r519 == IF memHigh /\ h = "Healthy" THEN {"Degraded"} ELSE {}                      \* @req REQ-519
      r524 == IF unacked /\ h = "Healthy" THEN {"Degraded"} ELSE {}                      \* @req REQ-524
      r35  == IF AllPass(n) /\ h \in {"Degraded", "Unhealthy"} THEN {"Healthy"} ELSE {}   \* hosting REQ-35
      all  == r31 \cup r508 \cup r519 \cup r524 \cup r35
  IN IF all = {} THEN {h} ELSE all

\* @req REQ-508 REQ-519 REQ-524  (with hosting REQ-31, REQ-35 for context)
HealthCheck(n) ==
  /\ CheckHealth /\ Up(n)
  /\ \E h \in Outcomes(n) : health' = [health EXCEPT ![n] = h]
  /\ chk' = [chk EXCEPT ![n] = IF reachable THEN "reachable" ELSE "unreachable"]
  /\ UNCHANGED <<node, rs, run, claimGen, storeVars, envVars, histVars>>

\* environment: the server goes away / comes back; memory crosses the threshold.
Disconnect == /\ reachable /\ outages < MaxOutages
              /\ reachable' = FALSE /\ outages' = outages + 1
              /\ UNCHANGED <<nodeVars, storeVars, evalOK, memHigh, histVars>>
Reconnect  == /\ ~reachable /\ reachable' = TRUE
              /\ UNCHANGED <<nodeVars, storeVars, evalOK, memHigh, outages, histVars>>
MemChange  == /\ MemToggle /\ memHigh' = ~memHigh
              /\ UNCHANGED <<nodeVars, storeVars, evalOK, reachable, outages, histVars>>

---------------------------------------------------------------------------
SystemStep(n) ==
  \/ Connect(n) \/ StartupNoEval(n) \/ NodeRuns(n)
  \/ DetectReset(n) \/ Reseed(n) \/ FinishReconcile(n) \/ PeriodicReconcile(n)
  \/ HealthCheck(n)

Next ==
  \/ \E n \in Nodes : SystemStep(n) \/ NodeStops(n) \/ Complete(n)
  \/ \E n \in Nodes, j \in Jobs : Claim(n, j)
  \/ \E j \in Jobs : Enqueue(j) \/ EvictJob(j)
  \/ Acknowledge \/ MaintOn \/ MaintOff
  \/ Flush \/ EvictMarker \/ EvictRecurring \/ TakeSnapshot \/ Restore
  \/ Disconnect \/ Reconnect \/ MemChange

\* Only actor: system transitions are fair. A-5: the server becomes unreachable at most
\* MaxOutages times and every outage ends (Reconnect is fair); otherwise every liveness property
\* fails trivially on a server that flaps or stays down for ever.
Fairness ==
  /\ \A n \in Nodes : /\ WF_vars(Connect(n)) /\ WF_vars(StartupNoEval(n)) /\ WF_vars(NodeRuns(n))
                      /\ WF_vars(DetectReset(n)) /\ WF_vars(Reseed(n))
                      /\ WF_vars(FinishReconcile(n)) /\ WF_vars(PeriodicReconcile(n))
                      /\ WF_vars(HealthCheck(n))
  /\ WF_vars(Reconnect)

Spec == Init /\ [][Next]_vars /\ Fairness

---------------------------------------------------------------------------
\* Properties

RunningNode == \E n \in Nodes : node[n] = "Running"

\* @req LIV-500  While the marker is missing and a node is running, eventually every code-defined
\*   recurring job is re-seeded. "While" read as: unless the condition stops holding.
Liv_Reseeded ==
  (marker = 0 /\ ~codeRec /\ RunningNode) ~> (codeRec \/ ~RunningNode)

\* @req REQ-507 REQ-523  (purpose, REQ-507 notes: "Causes: FLUSHALL, eviction, restore from an old
\*   snapshot") Every data-loss event is eventually detected and reported, while a node runs.
Liv_LossReported ==
  (pendingLoss /\ RunningNode) ~> (~pendingLoss \/ ~RunningNode)

\* @req REQ-507  A reset is reported only when data was actually lost.
Inv_NoFalseReset == ~falseReset

\* @req SCN-500  "one ERROR StoreWasReset event" per reset.
Inv_OneEventPerReset == detections <= losses

\* @req REQ-521  (notes: "so the outcome is not lost from history") a finished run's outcome
\*   always reaches the store.
Inv_NoLostOutcome == ~lostOutcome

\* @req REQ-523 REQ-524 REQ-525  Once a reset has been detected, it stays recorded as
\*   unacknowledged until an operator acknowledges it (REQ-524 notes: "Lasts beyond
\*   reconciliation ... until an operator acknowledges the reset").
Inv_UnackedUntilOperator == (detections >= 1 /\ ~everAcked) => unacked

\* context jobs INV-108  Never more running holders of a concurrency key than its Max
\*   ("processing" read as: a handler runs under a claim its node still holds, A-9).
Inv_ConcurrencyKeyMax == Cardinality({n \in Nodes : run[n] # NULL}) <= KeyMax

\* context jobs INV-103  Never two workers running the same job under a live claim.
Inv_SingleClaim == \A j \in Jobs : Cardinality({n \in Nodes : run[n] = j}) <= 1

\* context jobs INV-100  Never two active jobs with the same unique key in one namespace
\*   (all model jobs share one unique key and one namespace).
Inv_UniqueKeyPerNamespace ==
  \A j, k \in Jobs : (j # k /\ jobRec[j].st \in ActiveSt) => jobRec[k].st \notin ActiveSt

\* context jobs REQ-162/REQ-163  Maintenance goes off only when an operator turns it off.
Inv_MaintenanceOnlyOperatorOff == maintIntent => maint

\* context hosting REQ-31  A health check that found the store unreachable reports Unhealthy.
Inv_UnreachableIsUnhealthy == \A n \in Nodes : chk[n] = "unreachable" => health[n] = "Unhealthy"

\* context hosting REQ-30..REQ-35, REQ-44  Unhealthy only while an Unhealthy check fails: in this
\*   model the only such check is the store being unreachable (REQ-31).
Inv_UnhealthyOnlyWithCause == \A n \in Nodes : chk[n] = "reachable" => health[n] # "Unhealthy"

\* @req SCN-501  A server without EVAL never lets the store become ready (impossibleAt: 2).
Scn_NoEvalNoReady == \A n \in Nodes : ~evalOK => ~ENABLED Connect(n)

\* @req SCN-500  Positive scenario: trap for Redis_SCN500.cfg (expected to be VIOLATED).
\*   After a FLUSHALL: nightly-cleanup exists again, a new marker is written, the store is ready,
\*   one StoreWasReset was logged, and health is Degraded with the reset unacknowledged.
Scn_FlushRecovered_NotReached ==
  ~(\E n \in Nodes :
      /\ losses = 1 /\ codeRec /\ marker > 1 /\ rs[n] = "Ready"
      /\ detections = 1 /\ unacked /\ health[n] = "Degraded")

=============================================================================
