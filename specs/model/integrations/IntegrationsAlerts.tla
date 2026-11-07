------------------------- MODULE IntegrationsAlerts -------------------------
\* Generated from integrations.json (specHash 138efb1f8daa) — FEAT-400 Notifications: who evaluates.
\* Edit the requirements, not this file. Every action/property carries an @req comment.
\* Run 2: the alerts registration and the notification lease (INV-411, REQ-438), the node-lost and
\* missed-occurrence triggers (REQ-404, REQ-403), SCN-404, SCN-405, and run 1's assumption A-11 (two nodes
\* noticing the same event). Cooldowns are in IntegrationsNotifications.tla; here a "delivery" is counted
\* per event or per lost node, whatever its Pending/Suppressed outcome.
\* Run 3 (handoff): INV-412 added, SCN-406 added. What the job store records for each event, and how a
\* new rule starts, are in IntegrationsAlertEvents.tla.
\* Run 4 (handoff: INV-412 modified, INV-413 added): the rule's store record (INV-413) and the question
\* whether a holder's write may act on what it read before its lease lapsed.
\*   RuleKnownAtStart : TRUE: the store already records the rule; FALSE: it is new and INV-413 applies.
\*   DeliveryWrite : what INV-412's write (delivery + handled mark) checks besides the lease.
\*     "literal"     : as written: INV-411 checks the lease in that write; nothing requires it to re-check
\*                     that the event it read is still unhandled. Read and write are two steps.
\*     "conditional" : F-20 option 1: the write succeeds only if the event is still unhandled (one step).
\*   FirstWrite    : what INV-413's write (rule record + marks) checks.
\*     "literal"     : as written: it creates no delivery, so INV-411's lease check does not cover it, and
\*                     nothing requires it to re-check that the name is still unrecorded. Two steps.
\*     "fencedOnly"  : F-20 option 3: it checks the lease (INV-411 extended to it), nothing else.
\*     "conditional" : F-20 option 1: it succeeds only if the name is still unrecorded (one step).
\*
\* EventTracking: edge-triggered rules (REQ-400 "when a job is dead-lettered", REQ-401 Nth failure, REQ-403
\* missed or late occurrence) fire on an event that happens on some worker node.
\*   "storeCursor"   : @req INV-412  the events are found in the job store and each one is marked handled
\*                     for the rule in the same store write that creates its delivery. This is the
\*                     requirement; IntegrationsAlerts.cfg and IntegrationsAlerts_SCN406.cfg use it.
\* The two node-memory readings of run 2 are no longer readings of the requirements. They stay as
\* counterfactuals ("INV-412 dropped"), to show that INV-412 carries the guarantee:
\*   "nodeReplay"    : each node remembers what it handled; a new holder handles every stored event it has
\*                     not handled itself (IntegrationsAlerts_noInv412Replay.cfg).
\*   "nodeFromNow"   : each node remembers what it handled; a new holder handles only events that happen
\*                     after it took the lease (IntegrationsAlerts_noInv412FromNow.cfg).
EXTENDS Naturals, FiniteSets

CONSTANTS Nodes,          \* processes
          AlertNodes,     \* nodes with the alerts registration (hosting REQ-52, REQ-59)
          WorkerNodes,    \* nodes with the worker registered
          Events,         \* edge-triggered events (a job dead-lettered ...)
          EventTracking,
          MaxCrashes,     \* node crashes in one behaviour (A-10)
          MaxPauses,      \* lease expiries of a running holder, e.g. a long GC pause (A-12)
          RuleKnownAtStart,
          DeliveryWrite,
          FirstWrite,
          NULL

ASSUME AlertNodes \subseteq Nodes /\ WorkerNodes \subseteq Nodes
ASSUME EventTracking \in {"storeCursor", "nodeReplay", "nodeFromNow"}
ASSUME RuleKnownAtStart \in BOOLEAN
ASSUME DeliveryWrite \in {"literal", "conditional"} /\ FirstWrite \in {"literal", "fencedOnly", "conditional"}
ASSUME DeliveryWrite = "literal" => EventTracking = "storeCursor"
SplitDelivery == DeliveryWrite = "literal"
SplitFirst    == FirstWrite # "conditional"

VARIABLES running,   \* node process is up
          stale,     \* hosting REQ-60: no heartbeat for NodeLostAfter (only after the node stopped)
          lease,     \* @req REQ-438  store-side notification lease holder
          occurred,  \* events that have happened (stored in the jobs module)
          handledS,  \* "storeCursor": events marked handled in the store
          handledN,  \* "node*": per node, events this node handled or chose to skip
          made,      \* history: deliveries created per event (capped)
          lost,      \* history: node-lost deliveries created per lost node (capped)
          crashes, pauses,
          known,     \* @req INV-413  the store records the rule's name
          pendEv,    \* split writes: per node, the event it read as unhandled and has not yet written
          pendFirst, \* split writes: per node, it read "no record of the rule" and has not yet written
          newEv      \* history: events that happened while the store had no record of the rule
vars == <<running, stale, lease, occurred, handledS, handledN, made, lost, crashes, pauses,
          known, pendEv, pendFirst, newEv>>

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
  /\ known    \in BOOLEAN
  /\ pendEv   \in [Nodes -> Events \cup {NULL}]
  /\ pendFirst \in [Nodes -> BOOLEAN]
  /\ newEv    \subseteq Events

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
  /\ known    = RuleKnownAtStart
  /\ pendEv   = [n \in Nodes |-> NULL]
  /\ pendFirst = [n \in Nodes |-> FALSE]
  /\ newEv    = {}

\* jobs module (abstracted): an edge event happens, e.g. a job is dead-lettered on a worker node.
EventHappens(e) ==
  /\ e \notin occurred
  /\ \E w \in WorkerNodes : running[w]
  /\ occurred' = occurred \cup {e}
  /\ newEv' = IF known THEN newEv ELSE newEv \cup {e}
  /\ UNCHANGED <<running, stale, lease, handledS, handledN, made, lost, crashes, pauses, known, pendEv, pendFirst>>

\* @req REQ-438  No running alerts node holds an unexpired lease: one running alerts node takes it.
TakeLease(n) ==
  /\ n \in AlertNodes
  /\ running[n]
  /\ lease = NULL
  /\ lease' = n
  /\ handledN' = IF EventTracking = "nodeFromNow" THEN [handledN EXCEPT ![n] = occurred] ELSE handledN
  /\ UNCHANGED <<running, stale, occurred, handledS, made, lost, crashes, pauses, known, pendEv, pendFirst, newEv>>

\* @req REQ-438  The holder stops renewing (crashed): the lease expires.
LeaseExpires ==
  /\ lease # NULL
  /\ ~running[lease]
  /\ lease' = NULL
  /\ UNCHANGED <<running, stale, occurred, handledS, handledN, made, lost, crashes, pauses, known, pendEv, pendFirst, newEv>>

\* Environment (A-12): a running holder misses its renewal (pause) and the lease expires under it.
LeasePauses ==
  /\ lease # NULL
  /\ running[lease]
  /\ pauses < MaxPauses
  /\ lease' = NULL
  /\ pauses' = pauses + 1
  /\ UNCHANGED <<running, stale, occurred, handledS, handledN, made, lost, crashes, known, pendEv, pendFirst, newEv>>

\* @req REQ-400 REQ-401 REQ-403  An edge event becomes a delivery for its rule.
\* @req INV-411  Only on a running alerts node that holds the lease, checked in the same store write.
\* @req INV-412  ("storeCursor") the event is found in the store and marked handled in that same write.
\*               One step: the write re-checks what was read (DeliveryWrite = "conditional", or node memory).
HandleEvent(n, e) ==
  /\ ~SplitDelivery
  /\ n \in AlertNodes
  /\ running[n]
  /\ lease = n
  /\ known
  /\ e \in occurred
  /\ IF EventTracking = "storeCursor"
       THEN /\ e \notin handledS
            /\ handledS' = handledS \cup {e}
            /\ UNCHANGED handledN
       ELSE /\ e \notin handledN[n]
            /\ handledN' = [handledN EXCEPT ![n] = @ \cup {e}]
            /\ UNCHANGED handledS
  /\ made' = [made EXCEPT ![e] = Min(@ + 1, 2)]
  /\ UNCHANGED <<running, stale, lease, occurred, lost, crashes, pauses, known, pendEv, pendFirst, newEv>>

\* @req INV-412  Split write (DeliveryWrite = "literal"), read half: the holder finds an event the store
\*               shows as not handled for the rule.
HandleRead(n, e) ==
  /\ SplitDelivery
  /\ n \in AlertNodes
  /\ running[n]
  /\ lease = n
  /\ known
  /\ e \in occurred
  /\ e \notin handledS
  /\ pendEv[n] = NULL
  /\ pendEv' = [pendEv EXCEPT ![n] = e]
  /\ UNCHANGED <<running, stale, lease, occurred, handledS, handledN, made, lost, crashes, pauses, known, pendFirst, newEv>>

\* @req INV-412  Split write, write half: create the delivery and mark the event handled in one write.
\* @req INV-411  The write checks that this node holds the lease. Nothing requires it to check that the
\*               event is still unhandled.
HandleWrite(n) ==
  /\ SplitDelivery
  /\ running[n]
  /\ lease = n
  /\ pendEv[n] # NULL
  /\ handledS' = handledS \cup {pendEv[n]}
  /\ made' = [made EXCEPT ![pendEv[n]] = Min(@ + 1, 2)]
  /\ pendEv' = [pendEv EXCEPT ![n] = NULL]
  /\ UNCHANGED <<running, stale, lease, occurred, handledN, lost, crashes, pauses, known, pendFirst, newEv>>

\* @req INV-413  ("conditional") The holder evaluates the rule, the store has no record of its name:
\*               record it and mark every stored event handled, without deliveries, in one write that
\*               succeeds only while the name is still unrecorded (and, being one step, under the lease).
FirstSeen(n) ==
  /\ ~SplitFirst
  /\ n \in AlertNodes
  /\ running[n]
  /\ lease = n
  /\ ~known
  /\ known' = TRUE
  /\ handledS' = handledS \cup occurred
  /\ UNCHANGED <<running, stale, lease, occurred, handledN, made, lost, crashes, pauses, pendEv, pendFirst, newEv>>

\* @req INV-413  Split (FirstWrite = "literal" or "fencedOnly"), read half: the holder evaluates the rule and finds no
\*               record of its name.
FirstRead(n) ==
  /\ SplitFirst
  /\ n \in AlertNodes
  /\ running[n]
  /\ lease = n
  /\ ~known
  /\ ~pendFirst[n]
  /\ pendFirst' = [pendFirst EXCEPT ![n] = TRUE]
  /\ UNCHANGED <<running, stale, lease, occurred, handledS, handledN, made, lost, crashes, pauses, known, pendEv, newEv>>

\* @req INV-413  Split, write half: record the name and mark every event the store records at the time of
\*               the write as handled. "literal": INV-411 checks the lease only in writes that create or
\*               update a delivery, so this one checks nothing; "fencedOnly": it checks the lease.
FirstWriteStep(n) ==
  /\ SplitFirst
  /\ running[n]
  /\ pendFirst[n]
  /\ FirstWrite = "fencedOnly" => lease = n
  /\ known' = TRUE
  /\ handledS' = handledS \cup occurred
  /\ pendFirst' = [pendFirst EXCEPT ![n] = FALSE]
  /\ UNCHANGED <<running, stale, lease, occurred, handledN, made, lost, crashes, pauses, pendEv, newEv>>

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
  /\ UNCHANGED <<running, stale, lease, occurred, handledS, handledN, made, crashes, pauses, known, pendEv, pendFirst, newEv>>

\* Environment: a node crashes; its memory is lost.
Crash(n) ==
  /\ running[n]
  /\ crashes < MaxCrashes
  /\ running' = [running EXCEPT ![n] = FALSE]
  /\ handledN' = [handledN EXCEPT ![n] = {}]
  /\ pendEv' = [pendEv EXCEPT ![n] = NULL]
  /\ pendFirst' = [pendFirst EXCEPT ![n] = FALSE]
  /\ crashes' = crashes + 1
  /\ UNCHANGED <<stale, lease, occurred, handledS, made, lost, pauses, known, newEv>>

\* hosting REQ-60 (time abstracted, A-3): a stopped node is reported lost after NodeLostAfter.
GoesStale(n) ==
  /\ ~running[n]
  /\ ~stale[n]
  /\ stale' = [stale EXCEPT ![n] = TRUE]
  /\ UNCHANGED <<running, lease, occurred, handledS, handledN, made, lost, crashes, pauses, known, pendEv, pendFirst, newEv>>

\* Environment (A-13): a crashed node is restarted by its host. The restarted process is a new instance:
\* it does not inherit the crashed process's lease, which must expire first (LeaseExpires).
Restart(n) ==
  /\ ~running[n]
  /\ lease # n
  /\ running' = [running EXCEPT ![n] = TRUE]
  /\ stale' = [stale EXCEPT ![n] = FALSE]
  /\ UNCHANGED <<lease, occurred, handledS, handledN, made, lost, crashes, pauses, known, pendEv, pendFirst, newEv>>

Next ==
  \/ \E e \in Events : EventHappens(e)
  \/ LeaseExpires \/ LeasePauses
  \/ \E n \in Nodes : \/ TakeLease(n) \/ Crash(n) \/ GoesStale(n) \/ Restart(n)
                      \/ (\E e \in Events : HandleEvent(n, e) \/ HandleRead(n, e))
                      \/ HandleWrite(n) \/ FirstSeen(n) \/ FirstRead(n) \/ FirstWriteStep(n)
                      \/ (\E x \in Nodes : NodeLostAlert(n, x))

\* The lease takeover and rule evaluation are system duties (REQ-438, INV-411): fair. Restart is the
\* host's job (A-13) and is fair too, so a crashed alerts node does come back.
Fairness ==
  /\ \A n \in Nodes : WF_vars(TakeLease(n)) /\ WF_vars(\E e \in Events : HandleEvent(n, e))
                      /\ WF_vars(Restart(n))
                      /\ WF_vars(\E e \in Events : HandleRead(n, e)) /\ WF_vars(HandleWrite(n))
                      /\ WF_vars(FirstSeen(n)) /\ WF_vars(FirstRead(n)) /\ WF_vars(FirstWriteStep(n))
  /\ WF_vars(LeaseExpires)

Spec == Init /\ [][Next]_vars /\ Fairness

\* @req INV-412  "neither alerts an event again": one event never yields two deliveries
\*               (also run 1's assumption A-11).
Inv_OneDeliveryPerEvent == \A e \in Events : made[e] <= 1

\* @req INV-412  "nor skips one": every event eventually yields a delivery (as long as some alerts node
\*               runs; restarts are fair). INV-412 notes: events while no node holds the lease are
\*               alerted when a holder next runs.
\* @req INV-413  Events that happened before the store recorded the rule are exempt (its start point).
Liv_EventAlerted == \A e \in Events : (e \in occurred /\ e \notin newEv) ~> (made[e] >= 1)

\* @req SCN-405  (negative, impossibleAt 2) A node without the notification lease creates no delivery.
Scn405_NoLeaseNoDelivery ==
  \A n \in Nodes, e \in Events : lease # n => ~ENABLED HandleEvent(n, e) /\ ~ENABLED HandleWrite(n)

\* @req SCN-404  Trap for IntegrationsAlerts_SCN404.cfg (expected to be VIOLATED): a node-lost delivery
\*               for the only worker is created while no worker node runs.
Scn404_NotReached ==
  ~(\E x \in WorkerNodes : lost[x] = 1 /\ \A w \in WorkerNodes : ~running[w])

\* @req SCN-406  The cfg uses strings for nodes and events ("a1", "e1"), so the given can name them.
\*               Given: a1 created e1's delivery, then paused past LeaseDuration (lease expired, pauses
\*               used up); e2 was dead-lettered while no node held the lease. Reachable in the main spec
\*               (e1 happens, a1 takes the lease, handles e1, pauses, e2 happens), so Inv_OneDeliveryPerEvent
\*               in IntegrationsAlerts.cfg covers "a2 did not alert e1 again" from this state too.
InitSCN406 ==
  /\ running  = [n \in Nodes |-> TRUE]
  /\ stale    = [n \in Nodes |-> FALSE]
  /\ lease    = NULL
  /\ occurred = Events
  /\ handledS = {"e1"}
  /\ handledN = [n \in Nodes |-> {}]
  /\ made     = [e \in Events |-> IF e = "e1" THEN 1 ELSE 0]
  /\ lost     = [n \in Nodes |-> 0]
  /\ crashes  = 0
  /\ pauses   = MaxPauses
  /\ known    = TRUE
  /\ pendEv   = [n \in Nodes |-> NULL]
  /\ pendFirst = [n \in Nodes |-> FALSE]
  /\ newEv    = {}
SpecSCN406 == InitSCN406 /\ [][Next]_vars /\ Fairness

\* @req SCN-406  Trap for IntegrationsAlerts_SCN406.cfg (expected to be VIOLATED): a2 holds the lease and
\*               there is exactly one delivery for e1 and exactly one for e2.
Scn406_NotReached ==
  ~(lease = "a2" /\ \A e \in Events : made[e] = 1)
=============================================================================
