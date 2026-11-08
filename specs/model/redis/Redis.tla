----------------------------- MODULE Redis -----------------------------
\* Generated from specs/redis.json - edit the requirements, not this file.
\* Run 7 (2026-11-08): regenerated from handoff.json (change: REQ-523's trigger is now "this node
\* replaces the generation marker under REQ-507", which DetectReset already encoded as A-31). The
\* run-6 counterfactual Req523Literal (the old wording, which never fired) is removed. Impacted ids
\* re-checked: REQ-532, SCN-500. New environment switch LostReply: the reply of a script that made the
\* REQ-507 write is lost with the connection (REQ-529), so the node does not learn it made it.
\* Switches that are not requirements: TrackHidden (history variables), SplitCAS (COUNTERFACTUAL: the
\* run-5 wording, a read followed by a separate compare-and-set) and LostReply (environment). With all
\* FALSE the extra variables (xVars) stay constant, except claimLR (a requirement since run 5).
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
          UniqueKeys,    \* all model jobs share one unique key (jobs INV-100) - or none
          Recurring,     \* model jobs are occurrences of one recurring job with overlap Skip (recurring INV-204)
          ShardByQueue,  \* @req INV-500 option
          FreshStore,    \* TRUE: first start against an empty server (no marker yet)
          LossKinds,     \* subset of {"flush", "evict", "restore"} enabled in this run
          MaxLosses,     \* at most this many data-loss events (environment bound)
          PolicyChange,  \* the server's maxmemory-policy may change to evicting while nodes run (failover, CONFIG SET)
          LateJoin,      \* a node may read the marker for the first time after a data loss (A-17)
          SplitCAS,      \* COUNTERFACTUAL (run-5 wording, not a requirement): REQ-507's read and a separate
                         \*   compare-and-set are two steps (FALSE = run 6: one atomic step)
          LostReply,     \* environment (run 7): a script that made the REQ-507 write loses its reply with the
                         \*   connection (REQ-529); the write stands, the node never learns it made it
          TrackHidden,   \* model switch: keep the history variables of Inv_HiddenOnlyIfPaused (xVars)
          MaxAdvances,   \* REQ-527 advances in one run (environment bound)
          MaxTok,        \* lease tokens issued in one run (fresh GUIDs, bounded)
          AllowStop,     \* hosts may stop nodes (hosting REQ-27/29, abstracted)
          CheckHealth,   \* model switch: include health-check runs (keeps non-health runs small)
          MemToggle,     \* model switch: let used_memory cross the REQ-519 threshold
          MaxOutages,    \* at most this many times the server becomes unreachable for every node (A-5)
          MaxDrops,      \* at most this many times one node loses its connection (REQ-529, per node)
          NULL

\* @req REQ-512  capability set: no transactional enqueue; push notifications and result storage.
\*               No action in this model reads it (absorbed).
\* @req REQ-513  payload hard limit 256 KB - absorbed: payload sizes are not modeled.
\* @req REQ-520  RedisMemoryDegradedShare = 80% - absorbed into the boolean memHigh (A-6).
\* @req REQ-533  StaleNodeAge = 60 s - absorbed: node registrations are not modeled (REQ-515 skipped).
ASSUME /\ WorkerNodes \subseteq Nodes /\ QueueA \subseteq Jobs
       /\ KeyMax \in Nat \ {0}
       /\ LossKinds \subseteq {"flush", "evict", "restore"}
       /\ MaxLosses \in Nat /\ MaxAdvances \in Nat /\ MaxTok \in Nat
       /\ ShardByQueue \in BOOLEAN /\ FreshStore \in BOOLEAN /\ AllowStop \in BOOLEAN
       /\ UniqueKeys \in BOOLEAN /\ Recurring \in BOOLEAN /\ PolicyChange \in BOOLEAN
       /\ LateJoin \in BOOLEAN /\ SplitCAS \in BOOLEAN /\ LostReply \in BOOLEAN /\ TrackHidden \in BOOLEAN
       /\ CheckHealth \in BOOLEAN /\ MemToggle \in BOOLEAN /\ MaxOutages \in Nat /\ MaxDrops \in Nat

VARIABLES
  \* per node
  node,        \* hosting.Node status
  rs,          \* RedisStore status as seen by this node
  health,      \* hosting.Health status
  chk,         \* what the last health check on this node saw: "none" | "reachable" | "unreachable"
  run,         \* job whose handler runs on this node, or NULL
  claimGen,    \* generation marker value read when that job was claimed
  claimTok,    \* lease token issued at that claim (jobs REQ-123)
  learned,     \* this node detected or learned of a reset since its claim (glossary resetSinceClaim)
  lastSeen,    \* RedisStore.lastSeenMarker: last marker value this node saw since it started (0 = none)
  reseeded,    \* marker value for which this node has re-seeded (0 = none)
  resetVal,    \* marker value this node's reconciliation is for (written at detection, or learned)
  done,        \* marker value whose reconciliation this node has finished (REQ-530 notes; 0 = none)
  remembers,   \* RedisStore.rememberedReset: node remembers an unacknowledged reset (REQ-523, REQ-532)
  waitDone,    \* A-18: LeaseDuration has passed since this node's store became reconciling (REQ-509)
  hbPending,   \* A-18: runs (by node) live when this node's store became reconciling that have not
               \*   renewed or re-created their record since
  leaseLost,   \* A-18: this node's run went a whole LeaseDuration without a successful heartbeat, so its
               \*   lease has expired as it would without any reset (jobs REQ-102, REQ-132)
  \* the Redis server (shared by all nodes)
  marker,      \* generation marker value: 0 = missing
  flagged,     \* the marker's reconciling flag (RedisStore.markerReconciling)
  lastReset,   \* the marker's last-reset value (RedisStore.markerLastReset; 0 = none)
  codeRec,     \* code-defined recurring job (nightly-cleanup) is stored
  registry,    \* queue registry (and node registrations) are stored
  resetRec,    \* reset record in the store: "none" | "unacked" | "acked"
  maint,       \* jobs.Maintenance flag (stored)
  jobRec,      \* job records: [st, owner, tok]
  snap,        \* a snapshot / replica image a restore or failover can roll back to
  \* environment
  evalOK,      \* server supports EVAL
  evicting,    \* server's maxmemory-policy is not noeviction
  reachable,   \* server reachable
  memHigh,     \* used_memory above RedisMemoryDegradedShare of maxmemory
  outages,     \* times the server became unreachable
  drops,       \* times a single node lost its connection
  tokens,      \* lease tokens issued so far
  advances,    \* REQ-527 advances so far
  clock,       \* the Redis server clock as marker values see it: the latest value ever written (REQ-507, REQ-527)
  \* history (observation only - no action is guarded by these)
  created, maintIntent, pendingLoss, falseReset, lostOutcome, lostOutcomeLL, detections, losses,
  everAcked, inits,
  \* run 4/5 extras (xVars): constant unless TrackHidden / SplitCAS is on, except claimLR
  claimLR,      \* last-reset value read when this node's job was claimed (glossary resetSinceClaim, run 5)
  sawAtLoss,    \* history: this node had seen a marker when the last FLUSHALL happened (TrackHidden)
  readInWindow, \* history: this node read the marker (claim, heartbeat, completion) since that flush (TrackHidden)
  runAtLoss,    \* history: this node's current run was already running at that flush (TrackHidden)
  casPending,   \* SplitCAS: this node read a marker that meets REQ-507's condition and has not yet made
  found,        \*   its compare-and-set against the value it read (found)
  foundLR       \*   and the last-reset value it read with it

nodeVars  == <<node, rs, health, chk, run, claimGen, claimTok, learned, lastSeen, reseeded, resetVal,
               done, remembers, waitDone, hbPending, leaseLost>>
storeVars == <<marker, flagged, lastReset, codeRec, registry, resetRec, maint, jobRec, snap>>
envVars   == <<evalOK, evicting, reachable, memHigh, outages, drops, tokens, advances, clock>>
histVars  == <<created, maintIntent, pendingLoss, falseReset, lostOutcome, lostOutcomeLL, detections,
               losses, everAcked, inits>>
xVars     == <<claimLR, sawAtLoss, readInWindow, runAtLoss, casPending, found, foundLR>>
vars      == <<nodeVars, storeVars, envVars, histVars, xVars>>

NodeStatus  == {"Starting", "Running", "Stopped", "StartupFailed"}
StoreStatus == {"Connecting", "Ready", "Reconciling"}
HealthSt    == {"Healthy", "Degraded", "Unhealthy"}
JobSt       == {"none", "enqueued", "processing", "done", "recreated", "cancelled"}
ActiveSt    == {"enqueued", "processing"}            \* jobs REQ-107 (the subset modeled)
InitGen     == 2                                     \* an established store; 1 is "the lowest value" (REQ-528)
MaxGen      == InitGen + MaxAdvances + 3 * MaxLosses + 3  \* run 4: REQ-528's last-reset value takes a clock value too
Gens        == 0..MaxGen
JobRec      == [st: JobSt, owner: Nodes \cup {NULL}, tok: 0..MaxTok]
NoJob       == [st |-> "none", owner |-> NULL, tok |-> 0]
Data        == [marker: Gens, flagged: BOOLEAN, lastReset: Gens, codeRec: BOOLEAN, registry: BOOLEAN,
                resetRec: {"none", "unacked", "acked"}, maint: BOOLEAN, jobRec: [Jobs -> JobRec]]

TypeInv ==
  /\ node      \in [Nodes -> NodeStatus]
  /\ rs        \in [Nodes -> StoreStatus]
  /\ health    \in [Nodes -> HealthSt]
  /\ chk       \in [Nodes -> {"none", "reachable", "unreachable"}]
  /\ run       \in [Nodes -> Jobs \cup {NULL}]
  /\ claimGen  \in [Nodes -> Gens]
  /\ claimTok  \in [Nodes -> 0..MaxTok]
  /\ learned   \in [Nodes -> BOOLEAN]
  /\ lastSeen  \in [Nodes -> Gens]
  /\ reseeded  \in [Nodes -> Gens]
  /\ resetVal  \in [Nodes -> Gens]
  /\ done      \in [Nodes -> Gens]
  /\ remembers \in [Nodes -> BOOLEAN]
  /\ waitDone  \in [Nodes -> BOOLEAN]
  /\ hbPending \in [Nodes -> SUBSET Nodes]
  /\ leaseLost \in [Nodes -> BOOLEAN]
  /\ marker \in Gens /\ flagged \in BOOLEAN /\ lastReset \in Gens
  /\ codeRec \in BOOLEAN /\ registry \in BOOLEAN /\ maint \in BOOLEAN
  /\ resetRec \in {"none", "unacked", "acked"}
  /\ jobRec \in [Jobs -> JobRec]
  /\ snap \in Data
  /\ evalOK \in BOOLEAN /\ evicting \in BOOLEAN /\ reachable \in BOOLEAN /\ memHigh \in BOOLEAN
  /\ outages \in 0..MaxOutages /\ drops \in 0..MaxDrops /\ tokens \in 0..MaxTok
  /\ advances \in 0..MaxAdvances /\ clock \in Gens
  /\ created \in [Jobs -> BOOLEAN] /\ maintIntent \in BOOLEAN
  /\ pendingLoss \in BOOLEAN /\ falseReset \in BOOLEAN /\ lostOutcome \in BOOLEAN /\ lostOutcomeLL \in BOOLEAN
  /\ detections \in Nat /\ losses \in 0..MaxLosses /\ everAcked \in BOOLEAN /\ inits \in Nat
  /\ claimLR \in [Nodes -> Gens]
  /\ sawAtLoss \in [Nodes -> BOOLEAN] /\ readInWindow \in [Nodes -> BOOLEAN] /\ runAtLoss \in [Nodes -> BOOLEAN]
  /\ casPending \in [Nodes -> BOOLEAN] /\ found \in [Nodes -> Gens] /\ foundLR \in [Nodes -> Gens]

DataNow == [marker |-> marker, flagged |-> flagged, lastReset |-> lastReset, codeRec |-> codeRec,
            registry |-> registry, resetRec |-> resetRec, maint |-> maint, jobRec |-> jobRec]

Init ==
  /\ node = [n \in Nodes |-> "Starting"]
  /\ rs = [n \in Nodes |-> "Connecting"]
  /\ health = [n \in Nodes |-> "Unhealthy"]          \* hosting Health.initial (hosting F-11)
  /\ chk = [n \in Nodes |-> "none"]
  /\ run = [n \in Nodes |-> NULL]
  /\ claimGen = [n \in Nodes |-> 0]
  /\ claimTok = [n \in Nodes |-> 0]
  /\ learned = [n \in Nodes |-> FALSE]
  /\ lastSeen = [n \in Nodes |-> 0]
  /\ reseeded = [n \in Nodes |-> 0]
  /\ resetVal = [n \in Nodes |-> 0]
  /\ done = [n \in Nodes |-> 0]
  /\ remembers = [n \in Nodes |-> FALSE]
  /\ waitDone = [n \in Nodes |-> FALSE]
  /\ hbPending = [n \in Nodes |-> {}]
  /\ leaseLost = [n \in Nodes |-> FALSE]
  \* an established store carries a marker and its seeded data; a fresh one has nothing
  /\ marker = IF FreshStore THEN 0 ELSE InitGen
  /\ flagged = FALSE
  /\ lastReset = 0
  /\ codeRec = ~FreshStore
  /\ registry = ~FreshStore
  /\ resetRec = "none"
  /\ maint = FALSE
  /\ jobRec = [j \in Jobs |-> NoJob]
  /\ snap = [marker |-> marker, flagged |-> FALSE, lastReset |-> 0, codeRec |-> codeRec, registry |-> registry,
             resetRec |-> "none", maint |-> FALSE, jobRec |-> [j \in Jobs |-> NoJob]]
  /\ evalOK \in BOOLEAN
  /\ evicting \in BOOLEAN
  /\ reachable = TRUE
  /\ memHigh = FALSE
  /\ outages = 0 /\ drops = 0 /\ tokens = 0 /\ advances = 0
  /\ clock = InitGen
  /\ created = [j \in Jobs |-> FALSE]
  /\ maintIntent = FALSE
  /\ pendingLoss = FALSE /\ falseReset = FALSE /\ lostOutcome = FALSE /\ lostOutcomeLL = FALSE
  /\ detections = 0 /\ losses = 0 /\ everAcked = FALSE /\ inits = 0
  /\ claimLR = [n \in Nodes |-> 0]
  /\ sawAtLoss = [n \in Nodes |-> FALSE] /\ readInWindow = [n \in Nodes |-> FALSE]
  /\ runAtLoss = [n \in Nodes |-> FALSE]
  /\ casPending = [n \in Nodes |-> FALSE] /\ found = [n \in Nodes |-> 0] /\ foundLR = [n \in Nodes |-> 0]

Up(n) == node[n] \in {"Starting", "Running"}
Max2(a, b) == IF a > b THEN a ELSE b
Runs == {m \in Nodes : run[m] # NULL}
\* the run on node n no longer needs a heartbeat in anyone's REQ-509 wait
Renewed(n) == [m \in Nodes |-> hbPending[m] \ {n}]

---------------------------------------------------------------------------
\* Startup and (re)connection

\* @req REQ-500 REQ-501 REQ-503 REQ-504 REQ-531  Same event: connection established and a trivial
\*   EVAL succeeds -> store ready; family/version detected (REQ-500) or a warning (REQ-501); the
\*   durability notes (REQ-503, REQ-504) and, for a running node, the eviction ERROR (REQ-531) are
\*   log-only consequences. Also the reconnection half of @req REQ-529 (detection repeats).
\* @req REQ-505  A starting node never becomes ready on an evicting server (StartupEviction).
Connect(n) ==
  /\ Up(n) /\ rs[n] = "Connecting"
  /\ reachable /\ evalOK
  /\ node[n] = "Starting" => ~evicting
  /\ rs' = [rs EXCEPT ![n] = "Ready"]
  /\ UNCHANGED <<xVars, node, health, chk, run, claimGen, claimTok, learned, lastSeen, reseeded, resetVal,
                 done, remembers, waitDone, hbPending, leaseLost, storeVars, envVars, histVars>>

\* @req REQ-502  A server without EVAL fails the host's start.
StartupNoEval(n) ==
  /\ node[n] = "Starting" /\ rs[n] = "Connecting"
  /\ reachable /\ ~evalOK
  /\ node' = [node EXCEPT ![n] = "StartupFailed"]
  /\ UNCHANGED <<xVars, rs, health, chk, run, claimGen, claimTok, learned, lastSeen, reseeded, resetVal,
                 done, remembers, waitDone, hbPending, leaseLost, storeVars, envVars, histVars>>

\* @req REQ-505  maxmemory-policy other than noeviction fails the host's start.
StartupEviction(n) ==
  /\ node[n] = "Starting" /\ rs[n] = "Connecting"
  /\ reachable /\ evalOK /\ evicting
  /\ node' = [node EXCEPT ![n] = "StartupFailed"]
  /\ UNCHANGED <<xVars, rs, health, chk, run, claimGen, claimTok, learned, lastSeen, reseeded, resetVal,
                 done, remembers, waitDone, hbPending, leaseLost, storeVars, envVars, histVars>>

\* context: hosting REQ-18 - node runs once its startup checks passed; A-1: "store ready" is one of them.
NodeRuns(n) ==
  /\ node[n] = "Starting" /\ rs[n] = "Ready"
  /\ node' = [node EXCEPT ![n] = "Running"]
  /\ UNCHANGED <<xVars, rs, health, chk, run, claimGen, claimTok, learned, lastSeen, reseeded, resetVal,
                 done, remembers, waitDone, hbPending, leaseLost, storeVars, envVars, histVars>>

\* context: hosting REQ-27/REQ-29 abstracted - the host stops a node (human/host actor, not fair).
\* The handler's outcome and the node's memory go with it (A-8).
NodeStops(n) ==
  /\ AllowStop /\ node[n] = "Running"
  /\ node' = [node EXCEPT ![n] = "Stopped"]
  /\ run' = [run EXCEPT ![n] = NULL]
  /\ remembers' = [remembers EXCEPT ![n] = FALSE]
  /\ hbPending' = [m \in Nodes |-> IF m = n THEN {} ELSE hbPending[m] \ {n}]
  /\ waitDone' = [waitDone EXCEPT ![n] = FALSE]
  /\ leaseLost' = [leaseLost EXCEPT ![n] = FALSE]
  /\ runAtLoss' = [runAtLoss EXCEPT ![n] = FALSE]
  /\ UNCHANGED <<claimLR, sawAtLoss, readInWindow, casPending, found, foundLR, rs, health, chk, claimGen, claimTok, learned, lastSeen,
                 reseeded, resetVal, done, storeVars, envVars, histVars>>

---------------------------------------------------------------------------
\* Generation marker and reset handling (worker nodes only: REQ-507, REQ-527, REQ-528, REQ-530)

Checking(n) == n \in WorkerNodes /\ node[n] = "Running" /\ reachable

\* A flush is hidden for good: no node can detect it any more (the marker is present, unflagged and
\* not older than any value a node saw) although no node detected it.
Hidden ==
  /\ pendingLoss /\ marker # 0 /\ ~flagged /\ \A n \in Nodes : ~casPending[n]
  /\ \A n \in WorkerNodes : ~(marker < lastSeen[n])

\* TrackHidden: n read the marker after the last flush and before it became hidden.
MarkRead(n) == IF TrackHidden /\ pendingLoss /\ ~Hidden
                 THEN readInWindow' = [readInWindow EXCEPT ![n] = TRUE]
                 ELSE UNCHANGED readInWindow

\* A node's store becomes reconciling: the REQ-509 wait starts, and every run live now must renew
\* or re-create its record within it, or it has gone a whole LeaseDuration without a heartbeat (A-18).
StartWait(n) ==
  /\ waitDone' = [waitDone EXCEPT ![n] = FALSE]
  /\ hbPending' = [hbPending EXCEPT ![n] = Runs]

\* A worker reads an ordinary (unflagged) marker that moved forward: it remembers the value
\* (glossary generationMarker: "Every node remembers the last value it saw"). A-2: at any time.
Observe(n) ==
  /\ Checking(n) /\ rs[n] \in {"Ready", "Reconciling"}
  /\ marker # 0 /\ ~flagged /\ marker > lastSeen[n]
  /\ lastSeen' = [lastSeen EXCEPT ![n] = marker]
  /\ UNCHANGED <<xVars, node, rs, health, chk, run, claimGen, claimTok, learned, reseeded, resetVal, done,
                 remembers, waitDone, hbPending, leaseLost, storeVars, envVars, histVars>>

\* @req REQ-507 REQ-523  Marker missing, or older than the last value this node saw (flagged or not),
\*   on a worker that has seen a marker since it started -> in the same atomic step as the read that
\*   found it (run 6), replace it with the server's current time as value and last-reset value, flagged;
\*   log StoreWasReset (REQ-507) and the ERROR + unacknowledged record (REQ-523), remember it, and start
\*   re-seeding. Another node's later read finds the new flagged value and joins through REQ-530.
\*   @req REQ-509 (run 4): a detection starts re-seeding, so the LeaseDuration wait (re)starts here,
\*   from Ready and from Reconciling alike ("since it last started re-seeding").
\*   @req REQ-523 (run 7): "When this node replaces the generation marker under REQ-507" is this action.
\*   REQ-528's first marker (InitMarker) and REQ-530's join (Learn) are other actions and record nothing.
\*   @req REQ-507 (run 5): "when any read this node makes of the generation marker, including those of its
\*   claim, heartbeat and completion scripts, finds it ...": the reads of Claim, Heartbeat and Complete
\*   apply this action first (ReadOK below); other reads (REQ-527, REQ-510, plain looks) still happen at
\*   any time (A-2).
\*   COUNTERFACTUAL SplitCAS (run-5 wording): the read (DetectRead) and a compare-and-set against what it
\*   found are two steps; a lost compare-and-set re-seeds without reporting (DetectLose).
DetectCond(n) ==
  /\ Checking(n) /\ rs[n] \in {"Ready", "Reconciling"}
  /\ lastSeen[n] # 0
  /\ marker = 0 \/ marker < lastSeen[n]
  /\ clock + 1 <= MaxGen
DetectRead(n) ==
  /\ SplitCAS /\ DetectCond(n) /\ ~casPending[n]
  /\ casPending' = [casPending EXCEPT ![n] = TRUE]
  /\ found' = [found EXCEPT ![n] = marker]
  /\ foundLR' = [foundLR EXCEPT ![n] = lastReset]
  /\ MarkRead(n)
  /\ UNCHANGED <<claimLR, sawAtLoss, runAtLoss, nodeVars, storeVars, envVars, histVars>>
DetectReset(n) ==
  /\ IF SplitCAS
       THEN /\ casPending[n] /\ Checking(n) /\ rs[n] \in {"Ready", "Reconciling"} /\ clock + 1 <= MaxGen
            /\ marker = found[n]
       ELSE DetectCond(n)
  /\ casPending' = [casPending EXCEPT ![n] = FALSE]
  /\ LET v == clock + 1 IN
       /\ marker' = v /\ flagged' = TRUE /\ lastReset' = v /\ clock' = v
       /\ lastSeen' = [lastSeen EXCEPT ![n] = v]
       /\ resetVal' = [resetVal EXCEPT ![n] = v]
  /\ rs' = [rs EXCEPT ![n] = "Reconciling"]
  /\ StartWait(n)
  /\ resetRec' = "unacked"
  /\ remembers' = [remembers EXCEPT ![n] = TRUE]
  /\ learned' = [learned EXCEPT ![n] = (run[n] # NULL) \/ learned[n]]
  /\ detections' = detections + 1
  /\ falseReset' = (falseReset \/ ~pendingLoss)
  /\ pendingLoss' = FALSE
  /\ UNCHANGED <<claimLR, sawAtLoss, readInWindow, runAtLoss, found, foundLR, node, health, chk, run, claimGen,
                 claimTok, reseeded, done, leaseLost, codeRec,
                 registry, maint, jobRec, snap, evalOK, evicting, reachable, memHigh, outages, drops,
                 tokens, advances, created, maintIntent, lostOutcome, lostOutcomeLL, losses, everAcked, inits>>

\* environment LostReply (run 7, @req REQ-507 REQ-523 REQ-529, TECH-130): the script makes REQ-507's
\*   write in the same atomic step as its read, then the connection drops before its reply arrives
\*   ("the connection to the server is lost", REQ-529). The store side of DetectReset happens; the
\*   node side does not: it does not learn that it replaced the marker, logs nothing, records
\*   nothing, remembers nothing and does not move lastSeen. Its store is connecting, as in
\*   DropConnection. Not fair (environment).
ReplyLost(n) ==
  /\ LostReply /\ ~SplitCAS /\ DetectCond(n) /\ drops < MaxDrops
  /\ LET v == clock + 1 IN
       /\ marker' = v /\ flagged' = TRUE /\ lastReset' = v /\ clock' = v
  /\ MarkRead(n)
  /\ rs' = [rs EXCEPT ![n] = "Connecting"]
  /\ drops' = drops + 1
  /\ waitDone' = [waitDone EXCEPT ![n] = FALSE]
  /\ hbPending' = [hbPending EXCEPT ![n] = {}]
  /\ UNCHANGED <<claimLR, sawAtLoss, runAtLoss, casPending, found, foundLR, node, health, chk, run, claimGen,
                 claimTok, learned, lastSeen, reseeded, resetVal, done, remembers, leaseLost, codeRec, registry,
                 resetRec, maint, jobRec, snap, evalOK, evicting, reachable, memHigh, outages, tokens,
                 advances, histVars>>

\* @req REQ-528  Marker missing on a worker that has not seen one since it started -> write the
\*   first marker at the lowest value, with the server's current time as its last-reset value
\*   (run 4), flagged, in the same atomic step as the read that found it missing (run 6); INFO; start re-seeding without logging StoreWasReset
\*   or recording the reset as unacknowledged (resetRec and detections are untouched).
\*   A-17: without LateJoin a node's first marker read happens before any data loss.
\*   Run 5: also triggered by the reads of Claim, Heartbeat and Complete (ReadOK).
InitCond(n) ==
  /\ Checking(n) /\ rs[n] = "Ready"
  /\ marker = 0 /\ lastSeen[n] = 0
  /\ clock + 1 <= MaxGen
InitMarker(n) ==
  /\ InitCond(n)
  /\ marker' = 1 /\ flagged' = TRUE /\ lastReset' = clock + 1 /\ clock' = clock + 1
  /\ lastSeen' = [lastSeen EXCEPT ![n] = 1]
  /\ resetVal' = [resetVal EXCEPT ![n] = 1]
  /\ rs' = [rs EXCEPT ![n] = "Reconciling"]
  /\ StartWait(n)
  /\ inits' = inits + 1
  /\ UNCHANGED <<xVars, node, health, chk, run, claimGen, claimTok, learned, reseeded, done, remembers,
                 leaseLost, codeRec, registry, resetRec, maint, jobRec, snap, evalOK, evicting, reachable,
                 memHigh, outages, drops, tokens, advances,
                 created, maintIntent, pendingLoss, falseReset, lostOutcome, lostOutcomeLL, detections,
                 losses, everAcked>>

\* @req REQ-530  Marker flagged with a value whose reconciliation this node has not finished, if that
\*   value is not older than the last value this node saw (run 4) -> re-seed without logging
\*   StoreWasReset, and remember the value. Re-seeding starts, so the REQ-509 wait starts.
\*   Run 5: also triggered by the reads of Claim, Heartbeat and Complete (ReadOK).
LearnCond(n) ==
  /\ Checking(n) /\ rs[n] = "Ready"
  /\ marker # 0 /\ flagged /\ marker # done[n]
  /\ ~(marker < lastSeen[n])
Learn(n) ==
  /\ LearnCond(n)
  /\ rs' = [rs EXCEPT ![n] = "Reconciling"]
  /\ resetVal' = [resetVal EXCEPT ![n] = marker]
  /\ lastSeen' = [lastSeen EXCEPT ![n] = marker]
  /\ learned' = [learned EXCEPT ![n] = (run[n] # NULL) \/ learned[n]]
  /\ StartWait(n)
  /\ UNCHANGED <<xVars, node, health, chk, run, claimGen, claimTok, reseeded, done, remembers, leaseLost,
                 storeVars, envVars, histVars>>

\* COUNTERFACTUAL SplitCAS (run-5 wording of REQ-507): the compare-and-set against what the node found
\*   fails because the marker changed since its read. "in either case start re-seeding": the node
\*   reconciles the value it now finds, without StoreWasReset ("if its own write succeeded").
DetectLose(n) ==
  /\ SplitCAS /\ casPending[n] /\ marker # found[n]
  /\ Checking(n) /\ rs[n] \in {"Ready", "Reconciling"}
  /\ casPending' = [casPending EXCEPT ![n] = FALSE]
  /\ rs' = [rs EXCEPT ![n] = "Reconciling"]
  /\ resetVal' = [resetVal EXCEPT ![n] = marker]
  /\ lastSeen' = [lastSeen EXCEPT ![n] = Max2(lastSeen[n], marker)]
  /\ learned' = [learned EXCEPT ![n] = (run[n] # NULL) \/ learned[n]]
  /\ StartWait(n)
  /\ UNCHANGED <<claimLR, sawAtLoss, readInWindow, runAtLoss, found, foundLR, node, health, chk, run, claimGen,
                 claimTok, reseeded, done, remembers, leaseLost, storeVars, envVars, histVars>>

\* @req REQ-507 REQ-528 REQ-530 (run 5): a worker's claim, heartbeat and completion scripts read the
\*   marker and return it (TECH-130); if a condition of these sentences holds at that read, the node
\*   applies it before using the script's result. Run 6 (TECH-130): the script makes the REQ-507 or
\*   REQ-528 write itself. Modeled as: the read happens only once none holds (DetectReset, InitMarker and
\*   Learn are fair, and the script's own write is that step), and, in the counterfactual, not between a
\*   SplitCAS read and its compare-and-set (A-28).
ReadOK(n) == ~DetectCond(n) /\ ~InitCond(n) /\ ~LearnCond(n) /\ ~casPending[n]

\* @req REQ-507 REQ-528 REQ-530 (shall: "start re-seeding the code-defined recurring jobs, the queue
\*   registry and this node's registration"). A-3: one step; recurring REQ-203 recreates the definitions.
Reseed(n) ==
  /\ Checking(n) /\ rs[n] = "Reconciling"
  /\ reseeded[n] # resetVal[n]
  /\ codeRec' = TRUE /\ registry' = TRUE
  /\ reseeded' = [reseeded EXCEPT ![n] = resetVal[n]]
  /\ UNCHANGED <<xVars, node, rs, health, chk, run, claimGen, claimTok, learned, lastSeen, resetVal, done,
                 remembers, waitDone, hbPending, leaseLost, marker, flagged, lastReset, resetRec, maint,
                 jobRec, snap, envVars, histVars>>

\* Time: LeaseDuration passes since node n's store became reconciling (A-18). Every run that was
\* live when the wait started and has not renewed or re-created its record since has now gone a
\* whole LeaseDuration without a successful heartbeat: its lease has expired (jobs REQ-102, REQ-132).
LeaseElapses(n) ==
  /\ rs[n] = "Reconciling" /\ ~waitDone[n]
  /\ waitDone' = [waitDone EXCEPT ![n] = TRUE]
  /\ leaseLost' = [m \in Nodes |-> leaseLost[m] \/ (m \in hbPending[n] /\ run[m] # NULL)]
  /\ hbPending' = [hbPending EXCEPT ![n] = {}]
  /\ UNCHANGED <<xVars, node, rs, health, chk, run, claimGen, claimTok, learned, lastSeen, reseeded, resetVal,
                 done, remembers, storeVars, envVars, histVars>>

\* @req REQ-509  While reconciling, re-seeded for the value, and LeaseDuration has passed since this
\*   node last started re-seeding (StartWait in DetectReset, InitMarker, Learn) -> clear the flag if it is still set on the value this
\*   reconciliation is for; store ready. The node has finished the value if it cleared the flag or
\*   found the marker no longer flagged with it (REQ-530 notes).
\*   Run 5: the clear reads the marker, so REQ-507 applies to it first ("any read this node makes").
FinishReconcile(n) ==
  /\ Checking(n) /\ rs[n] = "Reconciling"
  /\ ReadOK(n)
  /\ reseeded[n] = resetVal[n]
  /\ waitDone[n]
  /\ flagged' = IF flagged /\ marker = resetVal[n] THEN FALSE ELSE flagged
  /\ done' = [done EXCEPT ![n] = IF marker = resetVal[n] THEN resetVal[n] ELSE done[n]]
  /\ rs' = [rs EXCEPT ![n] = "Ready"]
  /\ waitDone' = [waitDone EXCEPT ![n] = FALSE]
  /\ hbPending' = [hbPending EXCEPT ![n] = {}]
  /\ UNCHANGED <<xVars, node, health, chk, run, claimGen, claimTok, learned, lastSeen, reseeded, resetVal,
                 remembers, leaseLost, marker, lastReset, codeRec, registry, resetRec, maint, jobRec,
                 snap, envVars, histVars>>

\* @req REQ-527  Every RecurringReconcileInterval a worker advances the unflagged marker to the
\*   server's current time by compare-and-set against the value it remembers, unless another node
\*   already did; the last-reset value is left as it is.
Advance(n) ==
  /\ Checking(n) /\ rs[n] = "Ready"
  /\ advances < MaxAdvances
  /\ marker # 0 /\ ~flagged /\ marker = lastSeen[n] /\ clock + 1 <= MaxGen
  /\ marker' = clock + 1 /\ clock' = clock + 1
  /\ lastSeen' = [lastSeen EXCEPT ![n] = clock + 1]
  /\ advances' = advances + 1
  /\ UNCHANGED <<xVars, node, rs, health, chk, run, claimGen, claimTok, learned, reseeded, resetVal, done,
                 remembers, waitDone, hbPending, leaseLost, flagged, lastReset, codeRec, registry,
                 resetRec, maint, jobRec, snap, evalOK, evicting, reachable, memHigh, outages, drops,
                 tokens, histVars>>

\* @req REQ-510  While ready, every RecurringReconcileInterval: reconcile code-defined recurring
\*   jobs again (recurring REQ-203 recreates a missing one). Worker duty (hosting REQ-40).
PeriodicReconcile(n) ==
  /\ Checking(n) /\ rs[n] = "Ready"
  /\ ~codeRec
  /\ codeRec' = TRUE
  /\ UNCHANGED <<xVars, nodeVars, marker, flagged, lastReset, registry, resetRec, maint, jobRec, snap, envVars, histVars>>

\* @req REQ-532  A node that remembers an unacknowledged reset re-writes a missing record.
RewriteRecord(n) ==
  /\ node[n] = "Running" /\ reachable /\ remembers[n]
  /\ resetRec = "none"
  /\ resetRec' = "unacked"
  /\ UNCHANGED <<xVars, nodeVars, marker, flagged, lastReset, codeRec, registry, maint, jobRec, snap, envVars, histVars>>

\* @req REQ-523  "...remember it until it finds the reset acknowledged".
ForgetReset(n) ==
  /\ node[n] = "Running" /\ reachable /\ remembers[n]
  /\ resetRec = "acked"
  /\ remembers' = [remembers EXCEPT ![n] = FALSE]
  /\ UNCHANGED <<xVars, node, rs, health, chk, run, claimGen, claimTok, learned, lastSeen, reseeded,
                 resetVal, done, waitDone, hbPending, leaseLost, storeVars, envVars, histVars>>

\* @req REQ-525  Operator acknowledges the reset on the dashboard (human actor: not fair).
Acknowledge ==
  /\ resetRec = "unacked" /\ reachable
  /\ resetRec' = "acked" /\ everAcked' = TRUE
  /\ UNCHANGED <<xVars, nodeVars, marker, flagged, lastReset, codeRec, registry, maint, jobRec, snap, envVars,
                 created, maintIntent, pendingLoss, falseReset, lostOutcome, lostOutcomeLL, detections,
                 losses, inits>>

---------------------------------------------------------------------------
\* Environment: data loss

\* A-17: without LateJoin every worker has read the marker before data is lost; with LateJoin at
\* least one has (a loss no running node saw is documented as unreported, REQ-528 notes).
LossAllowed == /\ losses < MaxLosses /\ reachable
               /\ IF LateJoin THEN \E n \in WorkerNodes : lastSeen[n] # 0
                              ELSE \A n \in WorkerNodes : lastSeen[n] # 0

\* FLUSHALL (REQ-507 notes: cause 1). Everything in the server is gone; its clock keeps running.
Flush ==
  /\ "flush" \in LossKinds /\ LossAllowed
  /\ marker' = 0 /\ flagged' = FALSE /\ lastReset' = 0 /\ codeRec' = FALSE /\ registry' = FALSE
  /\ resetRec' = "none" /\ maint' = FALSE
  /\ jobRec' = [j \in Jobs |-> NoJob]
  /\ pendingLoss' = TRUE /\ losses' = losses + 1
  /\ IF TrackHidden
       THEN /\ sawAtLoss' = [n \in Nodes |-> lastSeen[n] # 0]
            /\ readInWindow' = [n \in Nodes |-> FALSE]
            /\ runAtLoss' = [n \in Nodes |-> run[n] # NULL]
       ELSE UNCHANGED <<sawAtLoss, readInWindow, runAtLoss>>
  /\ UNCHANGED <<claimLR, casPending, found, foundLR, nodeVars, snap, envVars, created, maintIntent, falseReset, lostOutcome, lostOutcomeLL,
                 detections, everAcked, inits>>

\* The policy changes to evicting while nodes run (failover to a differently configured replica,
\* CONFIG SET). REQ-531 logs an ERROR at the next connection; nothing else changes.
PolicyFlip ==
  /\ PolicyChange /\ ~evicting
  /\ evicting' = TRUE
  /\ UNCHANGED <<xVars, nodeVars, storeVars, evalOK, reachable, memHigh, outages, drops, tokens, advances,
                 clock, histVars>>

\* Eviction of one key, possible only on an evicting server (REQ-505, REQ-531).
\* Not marked as a pending (detectable) loss: REQ-531 states such resets are not detected.
EvictJob(j) ==
  /\ "evict" \in LossKinds /\ evicting /\ LossAllowed /\ jobRec[j].st # "none"
  /\ jobRec' = [jobRec EXCEPT ![j] = NoJob]
  /\ losses' = losses + 1
  /\ UNCHANGED <<xVars, nodeVars, marker, flagged, lastReset, codeRec, registry, resetRec, maint, snap, envVars,
                 created, maintIntent, pendingLoss, falseReset, lostOutcome, lostOutcomeLL, detections,
                 everAcked, inits>>

\* An RDB/AOF snapshot is taken, or a replica lags behind (REQ-504: replication is async).
TakeSnapshot ==
  /\ "restore" \in LossKinds /\ reachable /\ marker # 0
  /\ snap' = DataNow
  /\ snap # snap'
  /\ UNCHANGED <<xVars, nodeVars, marker, flagged, lastReset, codeRec, registry, resetRec, maint, jobRec, envVars, histVars>>

\* Restore from an old snapshot or failover to a lagging replica: the server rolls back to the
\* image, marker included (A-12). A-21: only a rollback to an older marker value is a detectable
\* loss; a rollback within one RecurringReconcileInterval (same marker) is documented as undetected
\* (NFR-31) and not counted as pending.
Restore ==
  /\ "restore" \in LossKinds /\ LossAllowed
  /\ snap # DataNow
  /\ marker' = snap.marker /\ flagged' = snap.flagged /\ lastReset' = snap.lastReset
  /\ codeRec' = snap.codeRec /\ registry' = snap.registry
  /\ resetRec' = snap.resetRec /\ maint' = snap.maint /\ jobRec' = snap.jobRec
  /\ pendingLoss' = (pendingLoss \/ snap.marker < marker)
  /\ losses' = losses + 1
  /\ UNCHANGED <<xVars, nodeVars, snap, envVars, created, maintIntent, falseReset, lostOutcome, lostOutcomeLL,
                 detections, everAcked, inits>>

\* Action constraint for Redis_RestoreOlder.cfg: only rollbacks to an older marker value (the
\* detectable kind; same-marker rollbacks are documented as undetected, NFR-31).
ActC_OlderRollbackOnly == (losses' > losses) => snap.marker < marker

\* Action constraints that bound the two-loss cfgs to one shape of second loss each (scope, not
\* requirements): during a reconciliation (Redis_Flush2*.cfg), or after the first reconciliation has
\* ended everywhere (Redis_Unique2.cfg, Redis_Recurring2.cfg).
\* SplitCAS (counterfactual) scope: the window between a node's read and its compare-and-set is shorter than one
\* LeaseDuration (no REQ-509 wait ends inside it). Without it, a node that reads and then stalls for
\* a whole lease is the paused node NFR-31 already describes.
ActC_ShortCAS == (\E n \in Nodes : casPending[n]) => \A m \in Nodes : waitDone'[m] => waitDone[m]
ActC_SecondLossDuringReconcile == (losses' > losses /\ losses >= 1) => \E n \in Nodes : rs[n] = "Reconciling"
ActC_SecondLossAfterReconcile ==
  (losses' > losses /\ losses >= 1) => (marker # 0 /\ ~flagged /\ \A n \in Nodes : rs[n] # "Reconciling")

---------------------------------------------------------------------------
\* Jobs, as far as the reset rules touch them (context from the jobs and recurring modules)

\* context: jobs REQ-182 / INV-100 / REQ-150 (Ignore) with the scope of @req INV-500; with
\* Recurring, the overlap Skip check of recurring REQ-221 (no earlier unfinished occurrence), the
\* definition must exist, and @req REQ-526: no recurring occurrence while the marker is missing or
\* flagged. Plain enqueues are not held during the pause (REQ-526 notes).
JobQueue(j) == IF j \in QueueA THEN "qA" ELSE "qB"
SameScope(j, k) == IF ShardByQueue THEN JobQueue(j) = JobQueue(k) ELSE TRUE
Enqueue(j) ==
  /\ ~created[j] /\ reachable
  /\ UniqueKeys => ~\E k \in Jobs : jobRec[k].st \in ActiveSt /\ SameScope(j, k)
  /\ Recurring => (codeRec /\ marker # 0 /\ ~flagged /\ ~\E k \in Jobs : jobRec[k].st \in ActiveSt)
  /\ jobRec' = [jobRec EXCEPT ![j] = [st |-> "enqueued", owner |-> NULL, tok |-> 0]]
  /\ created' = [created EXCEPT ![j] = TRUE]
  /\ UNCHANGED <<xVars, nodeVars, marker, flagged, lastReset, codeRec, registry, resetRec, maint, snap, envVars,
                 maintIntent, pendingLoss, falseReset, lostOutcome, lostOutcomeLL, detections, losses,
                 everAcked, inits>>

\* context: jobs REQ-123 - claim with the concurrency key counted by the store (INV-108 notes) and
\* the maintenance pause (INV-114); @req REQ-526: no claim while the marker is missing or flagged.
\* The claim script reads the marker (TECH-130), so the node also remembers a newer value. A claim
\* starts a fresh lease.
Holders == {j \in Jobs : jobRec[j].st = "processing"}

Claim(n, j) ==
  /\ node[n] = "Running" /\ n \in WorkerNodes /\ rs[n] # "Connecting" /\ reachable
  /\ run[n] = NULL /\ ~maint
  /\ jobRec[j].st = "enqueued"
  /\ Cardinality(Holders) < KeyMax
  /\ marker # 0 /\ ~flagged
  /\ tokens < MaxTok
  /\ ReadOK(n)
  /\ jobRec' = [jobRec EXCEPT ![j] = [st |-> "processing", owner |-> n, tok |-> tokens + 1]]
  /\ tokens' = tokens + 1
  /\ run' = [run EXCEPT ![n] = j]
  /\ claimGen' = [claimGen EXCEPT ![n] = marker]
  /\ claimTok' = [claimTok EXCEPT ![n] = tokens + 1]
  /\ learned' = [learned EXCEPT ![n] = FALSE]
  /\ leaseLost' = [leaseLost EXCEPT ![n] = FALSE]
  /\ lastSeen' = [lastSeen EXCEPT ![n] = Max2(lastSeen[n], marker)]
  /\ claimLR' = [claimLR EXCEPT ![n] = lastReset]
  /\ MarkRead(n)
  /\ runAtLoss' = [runAtLoss EXCEPT ![n] = FALSE]
  /\ UNCHANGED <<sawAtLoss, casPending, found, foundLR, node, rs, health, chk, reseeded, resetVal, done, remembers, waitDone, hbPending,
                 marker, flagged, lastReset, codeRec, registry, resetRec, maint, snap, evalOK, evicting,
                 reachable, memHigh, outages, drops, advances, clock, histVars>>

\* glossary resetSinceClaim (run 5): marker missing, flagged, or older than at claim, or its last-reset
\* value later than the last-reset value read at the claim, or this node detected or learned of a
\* reset since the claim. Used by @req REQ-521 REQ-522.
ResetSinceClaim(n) ==
  \/ marker = 0 \/ flagged \/ marker < claimGen[n] \/ learned[n]
  \/ lastReset > claimLR[n]

OwnRecord(n) ==
  LET r == jobRec[run[n]] IN r.st = "processing" /\ r.owner = n /\ r.tok = claimTok[n]

\* context jobs REQ-126 (heartbeat; system actor):
\*   - record intact -> lease renewed (modeled only while some REQ-509 wait still needs it);
\*   - @req REQ-522: while the marker is missing or flagged, a heartbeat that finds the record missing,
\*     the store reset since the claim and the run's lease not expired (run 4; A-18: not leaseLost)
\*     re-creates it as processing with the claim's node, token, queue, concurrency key, unique key
\*     and occurrence;
\*   - @req REQ-534: in the same write, another job holding the unique key in a state REQ-534 lists
\*     (Scheduled, Enqueued, Awaiting, Unroutable; the model has Enqueued) is cancelled with
\*     reason DuplicateAfterReset;
\*   - anything else is refused (jobs INV-128) and the run continues (A-16).
\* A successful renewal or re-creation counts for the REQ-509 wait. A run whose lease has already
\* expired stays leaseLost until it ends (A-18).
Heartbeat(n) ==
  /\ node[n] = "Running" /\ run[n] # NULL /\ reachable /\ rs[n] # "Connecting"
  /\ ReadOK(n)
  /\ LET j == run[n] IN
       \/ /\ jobRec[j].st = "none" /\ (marker = 0 \/ flagged) /\ ResetSinceClaim(n)
          /\ ~leaseLost[n]
          /\ jobRec' = [k \in Jobs |->
               IF k = j THEN [st |-> "processing", owner |-> n, tok |-> claimTok[n]]
               ELSE IF UniqueKeys /\ SameScope(j, k) /\ jobRec[k].st = "enqueued"
                    THEN [jobRec[k] EXCEPT !.st = "cancelled"]
                    ELSE jobRec[k]]
       \/ /\ OwnRecord(n) /\ \E m \in Nodes : n \in hbPending[m]
          /\ UNCHANGED jobRec
  /\ hbPending' = Renewed(n)
  /\ MarkRead(n)
  /\ UNCHANGED <<claimLR, sawAtLoss, runAtLoss, casPending, found, foundLR, node, rs, health, chk, run, claimGen, claimTok, learned, lastSeen, reseeded,
                 resetVal, done, remembers, waitDone, leaseLost, marker, flagged, lastReset, codeRec, registry,
                 resetRec, maint, snap, envVars, histVars>>

\* @req REQ-521  Completion (handler actor - not fair):
\*   record still ours                          -> done (jobs REQ-127)
\*   record missing, store reset since claim    -> minimal record "recreated" + warning (REQ-521)
\*   anything else                              -> refused (jobs INV-128); if the record is missing
\*                                                 the job is gone from history (lostOutcome; for a
\*                                                 run whose lease had expired: lostOutcomeLL)
Complete(n) ==
  /\ run[n] # NULL /\ reachable /\ rs[n] # "Connecting"
  /\ ReadOK(n)
  /\ LET j == run[n]
         gone == jobRec[j].st = "none" /\ ~ResetSinceClaim(n) IN
       /\ jobRec' = [jobRec EXCEPT ![j] =
            CASE OwnRecord(n)                                -> [st |-> "done", owner |-> n, tok |-> claimTok[n]]
              [] jobRec[j].st = "none" /\ ResetSinceClaim(n) -> [st |-> "recreated", owner |-> n, tok |-> claimTok[n]]
              [] OTHER                                       -> jobRec[j]]
       /\ lostOutcome' = (lostOutcome \/ (gone /\ ~leaseLost[n]))
       /\ lostOutcomeLL' = (lostOutcomeLL \/ (gone /\ leaseLost[n]))
  /\ run' = [run EXCEPT ![n] = NULL]
  /\ hbPending' = Renewed(n)
  /\ leaseLost' = [leaseLost EXCEPT ![n] = FALSE]
  /\ MarkRead(n)
  /\ runAtLoss' = [runAtLoss EXCEPT ![n] = FALSE]
  /\ UNCHANGED <<claimLR, sawAtLoss, casPending, found, foundLR, node, rs, health, chk, claimGen, claimTok, learned, lastSeen, reseeded, resetVal, done,
                 remembers, waitDone, marker, flagged, lastReset, codeRec, registry, resetRec, maint, snap,
                 envVars, created, maintIntent, pendingLoss, falseReset, detections, losses, everAcked, inits>>

\* context: jobs REQ-162 / REQ-163 - operator turns maintenance on / off.
MaintOn  == /\ reachable /\ ~maint /\ maint' = TRUE  /\ maintIntent' = TRUE
            /\ UNCHANGED <<xVars, nodeVars, marker, flagged, lastReset, codeRec, registry, resetRec, jobRec, snap,
                           envVars, created, pendingLoss, falseReset, lostOutcome, lostOutcomeLL,
                           detections, losses, everAcked, inits>>
MaintOff == /\ reachable /\ maint /\ maint' = FALSE /\ maintIntent' = FALSE
            /\ UNCHANGED <<xVars, nodeVars, marker, flagged, lastReset, codeRec, registry, resetRec, jobRec, snap,
                           envVars, created, pendingLoss, falseReset, lostOutcome, lostOutcomeLL,
                           detections, losses, everAcked, inits>>

---------------------------------------------------------------------------
\* Health (hosting.Health per node)

AllPass(n) == reachable /\ rs[n] # "Reconciling" /\ ~memHigh /\ resetRec # "unacked"
\* One health-check run. Each rule's guard as written; HealthyAfterPasses abstracted to 1 (A-6).
Outcomes(n) ==
  LET h == health[n]
      r31  == IF ~reachable /\ h \in {"Healthy", "Degraded"} THEN {"Unhealthy"} ELSE {}            \* hosting REQ-31
      r58  == IF reachable /\ h = "Unhealthy" THEN {"Degraded"} ELSE {}                            \* hosting REQ-58
      r508 == IF reachable /\ rs[n] = "Reconciling" /\ h \in {"Healthy", "Unhealthy"} THEN {"Degraded"} ELSE {}  \* @req REQ-508
      r519 == IF reachable /\ memHigh /\ h \in {"Healthy", "Unhealthy"} THEN {"Degraded"} ELSE {}             \* @req REQ-519
      r524 == IF reachable /\ resetRec = "unacked" /\ h \in {"Healthy", "Unhealthy"} THEN {"Degraded"} ELSE {} \* @req REQ-524
      r35  == IF AllPass(n) /\ h = "Degraded" THEN {"Healthy"} ELSE {}                             \* hosting REQ-35
      all  == r31 \cup r58 \cup r508 \cup r519 \cup r524 \cup r35
  IN IF all = {} THEN {h} ELSE all

\* @req REQ-508 REQ-519 REQ-524  (with hosting REQ-31, REQ-35, REQ-58 for context)
HealthCheck(n) ==
  /\ CheckHealth /\ Up(n)
  /\ \E h \in Outcomes(n) : health' = [health EXCEPT ![n] = h]
  /\ chk' = [chk EXCEPT ![n] = IF reachable THEN "reachable" ELSE "unreachable"]
  /\ UNCHANGED <<xVars, node, rs, run, claimGen, claimTok, learned, lastSeen, reseeded, resetVal, done,
                 remembers, waitDone, hbPending, leaseLost, storeVars, envVars, histVars>>

\* environment: the server goes away (@req REQ-529: every connected node marks its store
\* connecting) / comes back; memory crosses the threshold.
Disconnect == /\ reachable /\ outages < MaxOutages
              /\ reachable' = FALSE /\ outages' = outages + 1
              /\ rs' = [n \in Nodes |-> "Connecting"]
              /\ waitDone' = [n \in Nodes |-> FALSE]
              /\ hbPending' = [n \in Nodes |-> {}]
              /\ UNCHANGED <<xVars, node, health, chk, run, claimGen, claimTok, learned, lastSeen, reseeded,
                             resetVal, done, remembers, leaseLost, storeVars, evalOK, evicting, memHigh,
                             drops, tokens, advances, clock, histVars>>
Reconnect  == /\ ~reachable /\ reachable' = TRUE
              /\ UNCHANGED <<xVars, nodeVars, storeVars, evalOK, evicting, memHigh, outages, drops, tokens,
                             advances, clock, histVars>>
\* @req REQ-529  One node loses its connection (or sees the server's role change): its store is
\*   connecting until Connect(n) succeeds again; a reconciliation it was in is left (REQ-530 resumes it).
DropConnection(n) ==
  /\ node[n] = "Running" /\ rs[n] \in {"Ready", "Reconciling"} /\ drops < MaxDrops
  /\ rs' = [rs EXCEPT ![n] = "Connecting"]
  /\ drops' = drops + 1
  /\ waitDone' = [waitDone EXCEPT ![n] = FALSE]
  /\ hbPending' = [hbPending EXCEPT ![n] = {}]
  /\ UNCHANGED <<xVars, node, health, chk, run, claimGen, claimTok, learned, lastSeen, reseeded, resetVal,
                 done, remembers, leaseLost, storeVars, evalOK, evicting, reachable, memHigh, outages,
                 tokens, advances, clock, histVars>>
MemChange  == /\ MemToggle /\ memHigh' = ~memHigh
              /\ UNCHANGED <<xVars, nodeVars, storeVars, evalOK, evicting, reachable, outages, drops, tokens,
                             advances, clock, histVars>>

---------------------------------------------------------------------------
SystemStep(n) ==
  \/ Connect(n) \/ StartupNoEval(n) \/ StartupEviction(n) \/ NodeRuns(n)
  \/ Observe(n) \/ DetectRead(n) \/ DetectReset(n) \/ DetectLose(n) \/ InitMarker(n) \/ Learn(n) \/ Reseed(n) \/ FinishReconcile(n)
  \/ Advance(n) \/ PeriodicReconcile(n) \/ RewriteRecord(n) \/ ForgetReset(n)
  \/ HealthCheck(n) \/ Heartbeat(n)

Next ==
  \/ \E n \in Nodes : SystemStep(n) \/ NodeStops(n) \/ Complete(n) \/ LeaseElapses(n) \/ DropConnection(n)
                     \/ ReplyLost(n)
  \/ \E n \in Nodes, j \in Jobs : Claim(n, j)
  \/ \E j \in Jobs : Enqueue(j) \/ EvictJob(j)
  \/ Acknowledge \/ MaintOn \/ MaintOff
  \/ Flush \/ PolicyFlip \/ TakeSnapshot \/ Restore
  \/ Disconnect \/ Reconnect \/ MemChange

\* Only actor: system transitions are fair, plus the passage of time (LeaseElapses). A-5: the
\* server becomes unreachable at most MaxOutages times and every outage ends (Reconnect is fair).
Fairness ==
  /\ \A n \in Nodes : /\ WF_vars(Connect(n)) /\ WF_vars(StartupNoEval(n)) /\ WF_vars(StartupEviction(n))
                      /\ WF_vars(NodeRuns(n)) /\ WF_vars(Observe(n)) /\ WF_vars(DetectReset(n))
                      /\ WF_vars(DetectRead(n)) /\ WF_vars(DetectLose(n))
                      /\ WF_vars(InitMarker(n)) /\ WF_vars(Learn(n)) /\ WF_vars(Reseed(n))
                      /\ WF_vars(FinishReconcile(n)) /\ WF_vars(PeriodicReconcile(n))
                      /\ WF_vars(RewriteRecord(n)) /\ WF_vars(ForgetReset(n))
                      /\ WF_vars(HealthCheck(n)) /\ WF_vars(Heartbeat(n)) /\ WF_vars(LeaseElapses(n))
  /\ WF_vars(Reconnect)

Spec == Init /\ [][Next]_vars /\ Fairness

---------------------------------------------------------------------------
\* Properties

RunningWorker == \E n \in WorkerNodes : node[n] = "Running"

\* @req LIV-500  While the marker is flagged and a worker runs, eventually every code-defined
\*   recurring job is re-seeded and the flag cleared. "While" read as: unless the condition stops.
Liv_Reseeded ==
  (flagged /\ RunningWorker) ~> ((codeRec /\ ~flagged) \/ ~RunningWorker)

\* @req LIV-501  While the marker is missing and a worker runs, eventually a marker is written.
Liv_MarkerWritten ==
  (marker = 0 /\ RunningWorker) ~> (marker # 0 \/ ~RunningWorker)

\* @req REQ-507 REQ-523  (purpose) Every detectable data-loss event is eventually detected and
\*   reported while a worker runs (A-21: evictions and same-marker rollbacks are not "detectable").
Liv_LossReported ==
  (pendingLoss /\ RunningWorker) ~> (~pendingLoss \/ ~RunningWorker)

\* @req REQ-523 REQ-532  A detected reset that has not been acknowledged is eventually recorded
\*   again whenever a flush or rollback erased the record.
Liv_UnackedRestored ==
  (detections >= 1 /\ ~everAcked /\ resetRec # "unacked" /\ RunningWorker)
    ~> (resetRec = "unacked" \/ everAcked \/ ~RunningWorker)

\* @req REQ-507  A reset is reported only when data was actually lost.
Inv_NoFalseReset == ~falseReset

\* @req SCN-500  "one ERROR StoreWasReset event" per reset.
Inv_OneEventPerReset == detections <= losses

\* @req REQ-521  (notes: "so the outcome is not lost from history") a finished run's job never
\*   disappears from history - for a run that kept its lease.
Inv_NoLostOutcome == ~lostOutcome

\* @req REQ-521  (notes, run 2 F-3: "also covers a run on a node that missed the whole
\*   reconciliation ... so its outcome is recorded rather than lost") - for a run whose lease expired.
Inv_NoLostOutcomeLeaseLost == ~lostOutcomeLL

\* @req REQ-523 REQ-524 REQ-525  Once a reset has been detected, it stays recorded as unacknowledged
\*   until an operator acknowledges it, except between a further loss and its repair (REQ-532).
Inv_UnackedUntilOperator == (detections >= 1 /\ ~everAcked /\ ~pendingLoss) => resetRec = "unacked"

\* context jobs INV-108  Never more handlers running under one concurrency key than its Max
\*   (A-9: handlers running under a claim their node still holds). A run whose lease expired is
\*   the ordinary at-least-once case (jobs REQ-132, recurring REQ-238) and is not counted (A-18).
Inv_ConcurrencyKeyMax == Cardinality({n \in Nodes : run[n] # NULL /\ ~leaseLost[n]}) <= KeyMax

\* context jobs INV-103  Never two workers running the same job under unexpired leases.
Inv_SingleClaim == \A j \in Jobs : Cardinality({n \in Nodes : run[n] = j /\ ~leaseLost[n]}) <= 1

\* context jobs INV-100 (as amended by redis F-10: per queue where ShardByQueue is on)  Never two
\*   active jobs with the same unique key in one scope (all model jobs share one unique key).
Inv_UniqueKey ==
  UniqueKeys => \A j, k \in Jobs : (j # k /\ jobRec[j].st \in ActiveSt /\ jobRec[k].st \in ActiveSt) => ~SameScope(j, k)

\* context recurring INV-204 (as amended by recurring F-3: the store's Processing state)  Never two
\*   occurrences' jobs Processing at once.
Inv_RecurringOverlap == Recurring => Cardinality(Holders) <= 1

\* context jobs REQ-162/REQ-163  Maintenance goes off only when an operator turns it off.
Inv_MaintenanceOnlyOperatorOff == maintIntent => maint

\* context hosting REQ-31  A health check that found the store unreachable reports Unhealthy.
Inv_UnreachableIsUnhealthy == \A n \in Nodes : chk[n] = "unreachable" => health[n] = "Unhealthy"

\* context hosting REQ-30..REQ-35, REQ-44, REQ-58  Unhealthy only while an Unhealthy check fails.
Inv_UnhealthyOnlyWithCause == \A n \in Nodes : chk[n] = "reachable" => health[n] # "Unhealthy"

\* @req REQ-526 (SCN-504 then: "no job was claimed while the marker was missing or flagged").
Scn_NoClaimWhileFlagged == (marker = 0 \/ flagged) => \A n \in Nodes, j \in Jobs : ~ENABLED Claim(n, j)

\* @req SCN-501  A server without EVAL never lets the store become ready (impossibleAt: 2).
Scn_NoEvalNoReady == \A n \in Nodes : ~evalOK => ~ENABLED Connect(n)

\* @req SCN-506  A client-only node does not start a reconciliation (impossibleAt: 1).
Scn_ClientNoDetect == \A n \in Nodes \ WorkerNodes : ~ENABLED DetectReset(n) /\ ~ENABLED Learn(n)

\* @req SCN-500  Positive scenario: trap for Redis_SCN500.cfg (expected to be VIOLATED).
\*   Run 7: "health stays Degraded until an operator acknowledges the reset" also needs the next
\*   health check to keep it Degraded (Outcomes = {"Degraded"}); before, the trace could end on a
\*   Degraded set by hosting REQ-58 before the flush and never checked again.
Scn_FlushRecovered_NotReached ==
  ~(\E n \in Nodes :
      /\ losses = 1 /\ codeRec /\ marker # 0 /\ ~flagged /\ rs[n] = "Ready"
      /\ detections = 1 /\ resetRec = "unacked" /\ health[n] = "Degraded"
      /\ Outcomes(n) = {"Degraded"})

\* @req SCN-503  Positive scenario (Redis_SCN503.cfg): a new server is initialised (flagged first
\*   marker, then cleared), no reset is reported or recorded, and claims are allowed.
Scn_FreshInitialised_NotReached ==
  ~(/\ marker # 0 /\ ~flagged /\ inits >= 1 /\ detections = 0 /\ resetRec = "none"
    /\ \E n \in Nodes, j \in Jobs : ENABLED Claim(n, j))

\* @req SCN-504  Positive scenario (Redis_SCN504.cfg): j1 keeps its hold across a flush, j2 waits.
\*   claimGen = InitGen: j1 was claimed before the flush (the cfg has no advance).
Scn_HoldKept_NotReached ==
  ~(\E n \in Nodes, j, k \in Jobs :
      /\ j # k /\ losses = 1 /\ detections = 1 /\ marker # 0 /\ ~flagged
      /\ run[n] = j /\ claimGen[n] = InitGen /\ jobRec[j].st = "processing" /\ jobRec[j].owner = n
      /\ jobRec[k].st = "enqueued" /\ \A m \in Nodes : run[m] # k)

\* @req SCN-505  Positive scenario (Redis_SCN505.cfg): a rollback to an older marker is detected.
Scn_RestoreDetected_NotReached ==
  ~(\E n \in Nodes : losses = 1 /\ detections = 1 /\ flagged /\ rs[n] = "Reconciling" /\ marker > snap.marker)

\* @req SCN-507  Positive scenario (Redis_SCN507.cfg): a node that first looks after the flush writes
\*   the flagged lowest value (REQ-528), the node that saw the old marker reports the reset (REQ-507),
\*   j1 re-asserts its hold (REQ-522) and the flag is cleared (REQ-509). claimGen = InitGen: j1 was
\*   claimed before the flush (the cfg has no advance).
Scn_LateLookPaused_NotReached ==
  ~(\E n \in Nodes, j \in Jobs :
      /\ inits >= 1 /\ losses = 1 /\ detections = 1 /\ marker # 0 /\ ~flagged
      /\ run[n] = j /\ claimGen[n] = InitGen /\ jobRec[j].st = "processing" /\ jobRec[j].owner = n
      /\ ~leaseLost[n])

\* @req SCN-508  Positive scenario (Redis_SCN508.cfg): a unique-key duplicate enqueued during the
\*   pause is cancelled in the write that re-creates the running job's record (REQ-522, REQ-534).
Scn_DuplicateCancelled_NotReached ==
  ~(\E n \in Nodes, j, k \in Jobs :
      /\ losses = 1 /\ detections = 1 /\ run[n] = j
      /\ jobRec[j].st = "processing" /\ jobRec[j].owner = n /\ jobRec[k].st = "cancelled")

\* ---- run 4 ----------------------------------------------------------------

\* @req REQ-528 REQ-507 (REQ-528 notes, NFR-31: "a flush first seen by a newly started worker is not
\*   reported if every worker that saw the previous marker is paused until the marker is next
\*   advanced") - a hidden flush means every node that saw the old marker made no marker read
\*   (claim, heartbeat, completion) since the flush. Needs TrackHidden.
Inv_HiddenOnlyIfPaused == Hidden => \A n \in WorkerNodes : sawAtLoss[n] => ~readInWindow[n]

\* @req REQ-528 (notes: "a node paused for that whole time ... its runs are lease-lost anyway") -
\*   a run that was live at the hidden flush has lost its lease. Needs TrackHidden.
Inv_HiddenRunsLeaseLost == Hidden => \A n \in Nodes : runAtLoss[n] => leaseLost[n]

\* glossary resetSinceClaim ("The store was reset since a job was claimed"): with no data loss at
\*   all, no run counts as reset since its claim (REQ-521 notes: "A record missing for any other
\*   reason is still refused").
Inv_ResetSinceClaimSound == losses = 0 => \A n \in Nodes : run[n] # NULL => ~ResetSinceClaim(n)

\* @req SCN-509 (negative, impossibleAt 4): a flag set by a detection on a node that was already
\*   reconciling is not cleared before LeaseDuration has passed since that detection.
Scn_NoClearBeforeWait == \A n \in Nodes : (rs[n] = "Reconciling" /\ ~waitDone[n]) => ~ENABLED FinishReconcile(n)

\* SCN-509 steps 1-3 are reachable: n1 reconciles a second detection, the run on n2 kept its lease,
\*   and n1 has not re-seeded for the new value (trap, expected VIOLATED).
Scn509_Prefix_NotReached ==
  ~(\E n, m \in Nodes :
      /\ n # m /\ detections = 2 /\ losses = 2 /\ rs[n] = "Reconciling" /\ flagged /\ marker = resetVal[n]
      /\ reseeded[n] # resetVal[n] /\ run[m] # NULL /\ ~leaseLost[m])

\* @req SCN-510 (negative, impossibleAt 4): a run whose lease expired does not re-create its record
\*   at a later flush.
Scn_NoRevivalAfterExpiry ==
  \A n \in Nodes : (leaseLost[n] /\ run[n] # NULL /\ jobRec[run[n]].st = "none") => ~ENABLED Heartbeat(n)

\* SCN-510 steps 1-3 are reachable: a lease-lost run, its record gone, a second detection, flag set.
Scn510_Prefix_NotReached ==
  ~(\E n \in Nodes :
      /\ losses = 2 /\ detections = 2 /\ flagged /\ leaseLost[n] /\ run[n] # NULL
      /\ jobRec[run[n]].st = "none")

=============================================================================
