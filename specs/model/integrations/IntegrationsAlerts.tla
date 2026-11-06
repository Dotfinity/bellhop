------------------------- MODULE IntegrationsAlerts -------------------------
\* Generated from integrations.json (specHash 3b92b190e27a) — FEAT-400 Notifications: who evaluates.
\* Edit the requirements, not this file. Every action/property carries an @req comment.
\* New in run 2: the alerts registration and the notification lease (INV-411, REQ-438), the node-lost and
\* missed-occurrence triggers (REQ-404, REQ-403), SCN-404, SCN-405, and run 1's assumption A-11 (two nodes
\* noticing the same event). Cooldowns are in IntegrationsNotifications.tla; here a "delivery" is counted
\* per event or per lost node, whatever its Pending/Suppressed outcome.
\*
\* EventTracking: edge-triggered rules (REQ-400 "when a job is dead-lettered", REQ-401 Nth failure) fire on
\* an event that happens on some worker node. The alerts node that holds the lease must learn about it,
\* and after a lease handover the new holder must know which events were already handled. No requirement
\* says how (finding F-15). Three readings:
\*   "storeCursor"   : the store records an event as handled in the same write that creates its delivery.
\*   "nodeReplay"    : each node remembers what it handled; a new holder handles every stored event it has
\*                     not handled itself.
\*   "nodeFromNow"   : each node remembers what it handled; a new holder handles only events that happen
\*                     after it took the lease.
EXTENDS Naturals, FiniteSets

CONSTANTS Nodes,          \* processes
          AlertNodes,     \* nodes with the alerts registration (hosting REQ-52, REQ-59)
          WorkerNodes,    \* nodes with the worker registered
          Events,         \* edge-triggered events (a job dead-lettered ...)
          EventTracking,
          MaxCrashes,     \* node crashes in one behaviour (A-10)
          MaxPauses,      \* lease expiries of a running holder, e.g. a long GC pause (A-12)
          NULL

ASSUME AlertNodes \subseteq Nodes /\ WorkerNodes \subseteq Nodes
ASSUME EventTracking \in {"storeCursor", "nodeReplay", "nodeFromNow"}

VARIABLES running,   \* node process is up
          stale,     \* hosting REQ-60: no heartbeat for NodeLostAfter (only after the node stopped)
          lease,     \* @req REQ-438  store-side notification lease holder
          occurred,  \* events that have happened (stored in the jobs module)
          handledS,  \* "storeCursor": events marked handled in the store
          handledN,  \* "node*": per node, events this node handled or chose to skip
          made,      \* history: deliveries created per event (capped)
          lost,      \* history: node-lost deliveries created per lost node (capped)
          crashes, pauses
vars == <<running, stale, lease, occurred, handledS, handledN, made, lost, crashes, pauses>>

TypeInv ==
  /\ running  \in [Nodes -> BOOLEAN]
  /\ stale    \in [Nodes -> BOOLEAN]
  /\ lease    \in Nodes \cup {NULL}
  /\ occurred \subseteq Events
  /\ handledS \subseteq Events
  /\ handledN \in [Nodes -> SUBSET Events]
  /\ made     \in [Events -> 0..2]
  /\ lost     \in [Nodes -> 0..2]
  /\ crashes  \in 0..MaxCrashes
  /\ pauses   \in 0..MaxPauses

Min(a, b) == IF a < b THEN a ELSE b

Init ==
  /\ running  = [n \in Nodes |-> TRUE]
  /\ stale    = [n \in Nodes |-> FALSE]
  /\ lease    = NULL
  /\ occurred = {}
  /\ handledS = {}
  /\ handledN = [n \in Nodes |-> {}]
  /\ made     = [e \in Events |-> 0]
  /\ lost     = [n \in Nodes |-> 0]
  /\ crashes  = 0
  /\ pauses   = 0

\* jobs module (abstracted): an edge event happens, e.g. a job is dead-lettered on a worker node.
EventHappens(e) ==
  /\ e \notin occurred
  /\ \E w \in WorkerNodes : running[w]
  /\ occurred' = occurred \cup {e}
  /\ UNCHANGED <<running, stale, lease, handledS, handledN, made, lost, crashes, pauses>>

\* @req REQ-438  No running alerts node holds an unexpired lease: one running alerts node takes it.
TakeLease(n) ==
  /\ n \in AlertNodes
  /\ running[n]
  /\ lease = NULL
  /\ lease' = n
  /\ handledN' = IF EventTracking = "nodeFromNow" THEN [handledN EXCEPT ![n] = occurred] ELSE handledN
  /\ UNCHANGED <<running, stale, occurred, handledS, made, lost, crashes, pauses>>

\* @req REQ-438  The holder stops renewing (crashed): the lease expires.
LeaseExpires ==
  /\ lease # NULL
  /\ ~running[lease]
  /\ lease' = NULL
  /\ UNCHANGED <<running, stale, occurred, handledS, handledN, made, lost, crashes, pauses>>

\* Environment (A-12): a running holder misses its renewal (pause) and the lease expires under it.
LeasePauses ==
  /\ lease # NULL
  /\ running[lease]
  /\ pauses < MaxPauses
  /\ lease' = NULL
  /\ pauses' = pauses + 1
  /\ UNCHANGED <<running, stale, occurred, handledS, handledN, made, lost, crashes>>

\* @req REQ-400 REQ-401  An edge event becomes a delivery for its rule.
\* @req INV-411  Only on a running alerts node that holds the lease, checked in the same store write.
HandleEvent(n, e) ==
  /\ n \in AlertNodes
  /\ running[n]
  /\ lease = n
  /\ e \in occurred
  /\ IF EventTracking = "storeCursor"
       THEN /\ e \notin handledS
            /\ handledS' = handledS \cup {e}
            /\ UNCHANGED handledN
       ELSE /\ e \notin handledN[n]
            /\ handledN' = [handledN EXCEPT ![n] = @ \cup {e}]
            /\ UNCHANGED handledS
  /\ made' = [made EXCEPT ![e] = Min(@ + 1, 2)]
  /\ UNCHANGED <<running, stale, lease, occurred, lost, crashes, pauses>>

\* @req REQ-404  A node has sent no heartbeat for NodeLostAfter: delivery with the node as subject.
\*               (State-triggered, so any holder sees it; repeats are left to the cooldown, INV-400.)
\* @req INV-411  Only on a running alerts node that holds the lease.
NodeLostAlert(n, x) ==
  /\ n \in AlertNodes
  /\ running[n]
  /\ lease = n
  /\ stale[x]
  /\ lost[x] = 0
  /\ lost' = [lost EXCEPT ![x] = 1]
  /\ UNCHANGED <<running, stale, lease, occurred, handledS, handledN, made, crashes, pauses>>

\* Environment: a node crashes; its memory is lost.
Crash(n) ==
  /\ running[n]
  /\ crashes < MaxCrashes
  /\ running' = [running EXCEPT ![n] = FALSE]
  /\ handledN' = [handledN EXCEPT ![n] = {}]
  /\ crashes' = crashes + 1
  /\ UNCHANGED <<stale, lease, occurred, handledS, made, lost, pauses>>

\* hosting REQ-60 (time abstracted, A-3): a stopped node is reported lost after NodeLostAfter.
GoesStale(n) ==
  /\ ~running[n]
  /\ ~stale[n]
  /\ stale' = [stale EXCEPT ![n] = TRUE]
  /\ UNCHANGED <<running, lease, occurred, handledS, handledN, made, lost, crashes, pauses>>

\* Environment (A-13): a crashed node is restarted by its host. The restarted process is a new instance:
\* it does not inherit the crashed process's lease, which must expire first (LeaseExpires).
Restart(n) ==
  /\ ~running[n]
  /\ lease # n
  /\ running' = [running EXCEPT ![n] = TRUE]
  /\ stale' = [stale EXCEPT ![n] = FALSE]
  /\ UNCHANGED <<lease, occurred, handledS, handledN, made, lost, crashes, pauses>>

Next ==
  \/ \E e \in Events : EventHappens(e)
  \/ LeaseExpires \/ LeasePauses
  \/ \E n \in Nodes : \/ TakeLease(n) \/ Crash(n) \/ GoesStale(n) \/ Restart(n)
                      \/ (\E e \in Events : HandleEvent(n, e))
                      \/ (\E x \in Nodes : NodeLostAlert(n, x))

\* The lease takeover and rule evaluation are system duties (REQ-438, INV-411): fair. Restart is the
\* host's job (A-13) and is fair too, so a crashed alerts node does come back.
Fairness ==
  /\ \A n \in Nodes : WF_vars(TakeLease(n)) /\ WF_vars(\E e \in Events : HandleEvent(n, e))
                      /\ WF_vars(Restart(n))
  /\ WF_vars(LeaseExpires)

Spec == Init /\ [][Next]_vars /\ Fairness

\* Run-1 assumption A-11, now a check: one event never yields two deliveries.
Chk_OneDeliveryPerEvent == \A e \in Events : made[e] <= 1

\* Every event eventually yields a delivery (as long as some alerts node runs; restarts are fair).
Chk_EventAlerted == \A e \in Events : (e \in occurred) ~> (made[e] >= 1)

\* @req SCN-405  (negative, impossibleAt 2) A node without the notification lease creates no delivery.
Scn405_NoLeaseNoDelivery ==
  \A n \in Nodes, e \in Events : lease # n => ~ENABLED HandleEvent(n, e)

\* @req SCN-404  Trap for IntegrationsAlerts_SCN404.cfg (expected to be VIOLATED): a node-lost delivery
\*               for the only worker is created while no worker node runs.
Scn404_NotReached ==
  ~(\E x \in WorkerNodes : lost[x] = 1 /\ \A w \in WorkerNodes : ~running[w])
=============================================================================
