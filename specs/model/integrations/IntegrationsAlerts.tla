------------------------- MODULE IntegrationsAlerts -------------------------
\* Generated from integrations.json (specHash dce58296443f) — FEAT-400 Notifications: who evaluates.
\* Edit the requirements, not this file. Every action/property carries an @req comment.
\* Run 2: the alerts registration and the notification lease (INV-411, REQ-438), the node-lost and
\* missed-occurrence triggers (REQ-404, REQ-403), SCN-404, SCN-405, and run 1's assumption A-11 (two nodes
\* noticing the same event). Cooldowns are in IntegrationsNotifications.tla; here a "delivery" is counted
\* per event or per lost node, whatever its Pending/Suppressed outcome.
\* Run 3 (handoff): INV-412 added, SCN-406 added. What the job store records for each event, and how a
\* new rule starts, are in IntegrationsAlertEvents.tla.
\* Run 4 (handoff: INV-412 modified, INV-413 added): the rule's store record (INV-413) and the question
\* whether a holder's write may act on what it read before its lease lapsed.
\* Run 5 (handoff: INV-412 and INV-413 modified, run-4 F-20 option 1 applied): both writes are now
\* conditional on what was read. Every store write of INV-412/INV-413 is two steps: a read that decides it,
\* and a later write that checks the lease and its condition at the time it lands and fails (changing
\* nothing) if either no longer holds. A node that paused keeps its pending write and may land it after it
\* took the lease back.
\* Run 6 (handoff: INV-412 and INV-413 modified, run-5 F-23 option 1 applied): handled marks belong to the
\* rule's name and event settings. This module had one rule with fixed settings, so its marks were that
\* version's marks and no action changed; rule versions are in IntegrationsAlertEvents.tla.
\* Run 7 (handoff: INV-412 and INV-413 modified, run-6 F-24 option 1 applied): two marks. INV-412's read
\* takes an event that is neither "delivered" for the rule's name (deliveredS) nor "before the start" of the
\* version (startS); its write succeeds only if the event is not yet delivered for the name. INV-413's
\* write marks the stored events "before the start" of the version. Run 7 also lets the two alerts nodes
\* run different versions of the rule (same name, other threshold or tolerance, so the same events): a
\* rolling deploy, in which the lease moves between versions across a pause or a crash.
\* Run 8 (handoff: INV-412 modified, run-7 F-25/F-26 option 1 applied; INV-413 impacted, notes only): "skips
\* one after its start (INV-413)". Liv_EventAlerted now says that: an event after the start of the version
\* the lease holder runs for good is delivered. The start of each version is a history variable (vStart),
\* set by the first INV-413 write that records the version, so a later write that marks more events (the
\* unchecked and lease-only counterfactuals) does not move it. Run 7's property is Chk_EventAlertedAcrossVersions.
\*   NewVersionNodes  : the alerts nodes that run the edited version "B"; the others run "A". {} = one version.
\*   RuleKnownAtStart : TRUE: the store already records version "A"; FALSE: it is new and INV-413 applies.
\*                      Version "B" is never recorded at the start.
\*   MarkScope     : what the marks are kept for.
\*     "split"       : @req INV-412 INV-413  "delivered" per rule name, "before the start" per version.
\*     "perSettings" : counterfactual: run 6's wording, both per version (run 6's F-24).
\*   DeliveryWrite : what INV-412's write (delivery + handled mark) checks.
\*     "conditional" : @req INV-412 INV-411  the lease, and that the event is still not marked handled.
\*     "leaseOnly"   : counterfactual: run 4's wording, the lease only (run 4's F-20).
\*   FirstWrite    : what INV-413's write (rule record + marks) checks.
\*     "conditional" : @req INV-413  the lease, and that the store still has no record of the rule.
\*     "fencedOnly"  : counterfactual: the lease only (run 4's F-20 option 3).
\*     "unchecked"   : counterfactual: run 4's wording, nothing (run 4's F-20).
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
          NewVersionNodes,
          MarkScope,
          DeliveryWrite,
          FirstWrite,
          NULL

ASSUME AlertNodes \subseteq Nodes /\ WorkerNodes \subseteq Nodes /\ NewVersionNodes \subseteq AlertNodes
ASSUME EventTracking \in {"storeCursor", "nodeReplay", "nodeFromNow"}
ASSUME RuleKnownAtStart \in BOOLEAN /\ MarkScope \in {"split", "perSettings"}
ASSUME DeliveryWrite \in {"conditional", "leaseOnly"} /\ FirstWrite \in {"conditional", "fencedOnly", "unchecked"}
\* INV-412's read and write are about the store; the node-memory counterfactuals keep one step.
SplitDelivery == EventTracking = "storeCursor"

Versions == {"A", "B"}
\* (run 7) The version of the rule a node runs, and the key of the "delivered" mark it reads and writes.
Ver(n) == IF n \in NewVersionNodes THEN "B" ELSE "A"
DKeys  == Versions \cup {"name"}
DK(n)  == IF MarkScope = "split" THEN "name" ELSE Ver(n)

VARIABLES running,   \* node process is up
          stale,     \* hosting REQ-60: no heartbeat for NodeLostAfter (only after the node stopped)
          lease,     \* @req REQ-438  store-side notification lease holder
          occurred,  \* events that have happened (stored in the jobs module)
          deliveredS,\* @req INV-412  "storeCursor": events marked delivered, per DKeys
          startS,    \* @req INV-413  events marked before the start, per version
          handledN,  \* "node*": per node, events this node handled or chose to skip
          made,      \* history: deliveries created per event (capped); one rule name
          lost,      \* history: node-lost deliveries created per lost node (capped)
          crashes, pauses,
          known,     \* @req INV-413  the versions of the rule (name and event settings) the store records
          pendEv,    \* per node, the event it read as due and has not yet written (INV-412)
          pendFirst, \* per node, it read "no record of the rule" and has not yet written (INV-413)
          newEv,     \* history: events that happened while the store had no record of a version some
                     \* alerts node runs
          vStart     \* history: (run 8) per version, the events before its start (INV-413)
vars == <<running, stale, lease, occurred, deliveredS, startS, handledN, made, lost, crashes, pauses,
          known, pendEv, pendFirst, newEv, vStart>>

TypeInv ==
  /\ running  \in [Nodes -> BOOLEAN]
  /\ stale    \in [Nodes -> BOOLEAN]
  /\ lease    \in Nodes \cup {NULL}
  /\ occurred \subseteq Events
  /\ deliveredS \in [DKeys -> SUBSET Events]
  /\ startS   \in [Versions -> SUBSET Events]
  /\ handledN \in [Nodes -> SUBSET Events]
  /\ made     \in [Events -> 0..2]
  /\ lost     \in [Nodes -> 0..2]
  /\ crashes  \in 0..MaxCrashes
  /\ pauses   \in 0..MaxPauses
  /\ known    \subseteq Versions
  /\ pendEv   \in [Nodes -> Events \cup {NULL}]
  /\ pendFirst \in [Nodes -> BOOLEAN]
  /\ newEv    \subseteq Events
  /\ vStart   \in [Versions -> SUBSET Events]

Min(a, b) == IF a < b THEN a ELSE b
AllKnown == \A n \in AlertNodes : Ver(n) \in known

Init ==
  /\ running  = [n \in Nodes |-> TRUE]
  /\ stale    = [n \in Nodes |-> FALSE]
  /\ lease    = NULL
  /\ occurred = {}
  /\ deliveredS = [k \in DKeys |-> {}]
  /\ startS   = [v \in Versions |-> {}]
  /\ handledN = [n \in Nodes |-> {}]
  /\ made     = [e \in Events |-> 0]
  /\ lost     = [n \in Nodes |-> 0]
  /\ crashes  = 0
  /\ pauses   = 0
  /\ known    = IF RuleKnownAtStart THEN {"A"} ELSE {}
  /\ pendEv   = [n \in Nodes |-> NULL]
  /\ pendFirst = [n \in Nodes |-> FALSE]
  /\ newEv    = {}
  /\ vStart   = [v \in Versions |-> {}]

\* jobs module (abstracted): an edge event happens, e.g. a job is dead-lettered on a worker node.
EventHappens(e) ==
  /\ e \notin occurred
  /\ \E w \in WorkerNodes : running[w]
  /\ occurred' = occurred \cup {e}
  /\ newEv' = IF AllKnown THEN newEv ELSE newEv \cup {e}
  /\ UNCHANGED <<running, stale, lease, deliveredS, startS, handledN, made, lost, crashes, pauses, known, pendEv, pendFirst, vStart>>

\* @req REQ-438  No running alerts node holds an unexpired lease: one running alerts node takes it.
TakeLease(n) ==
  /\ n \in AlertNodes
  /\ running[n]
  /\ lease = NULL
  /\ lease' = n
  /\ handledN' = IF EventTracking = "nodeFromNow" THEN [handledN EXCEPT ![n] = occurred] ELSE handledN
  /\ UNCHANGED <<running, stale, occurred, deliveredS, startS, made, lost, crashes, pauses, known, pendEv, pendFirst, newEv, vStart>>

\* @req REQ-438  The holder stops renewing (crashed): the lease expires.
LeaseExpires ==
  /\ lease # NULL
  /\ ~running[lease]
  /\ lease' = NULL
  /\ UNCHANGED <<running, stale, occurred, deliveredS, startS, handledN, made, lost, crashes, pauses, known, pendEv, pendFirst, newEv, vStart>>

\* Environment (A-12): a running holder misses its renewal (pause) and the lease expires under it.
LeasePauses ==
  /\ lease # NULL
  /\ running[lease]
  /\ pauses < MaxPauses
  /\ lease' = NULL
  /\ pauses' = pauses + 1
  /\ UNCHANGED <<running, stale, occurred, deliveredS, startS, handledN, made, lost, crashes, known, pendEv, pendFirst, newEv, vStart>>

\* Counterfactuals "INV-412 dropped" (EventTracking = "nodeReplay" / "nodeFromNow"): an edge event
\* (REQ-400, REQ-401, REQ-403) becomes a delivery when the lease holder's own memory has not handled it.
\* @req INV-411  Only on a running alerts node that holds the lease (one step).
HandleEvent(n, e) ==
  /\ ~SplitDelivery
  /\ n \in AlertNodes
  /\ running[n]
  /\ lease = n
  /\ Ver(n) \in known
  /\ e \in occurred
  /\ e \notin handledN[n]
  /\ handledN' = [handledN EXCEPT ![n] = @ \cup {e}]
  /\ UNCHANGED <<deliveredS, startS>>
  /\ made' = [made EXCEPT ![e] = Min(@ + 1, 2)]
  /\ UNCHANGED <<running, stale, lease, occurred, lost, crashes, pauses, known, pendEv, pendFirst, newEv, vStart>>

\* @req REQ-400 REQ-401 REQ-403  An edge event becomes a delivery for its rule.
\* @req INV-412  Read: the holder finds an event the job store shows as neither delivered for the rule's
\*               name nor before the start of the version it runs (a version the store records, INV-412
\*               notes: "for rules the store already records").
HandleRead(n, e) ==
  /\ SplitDelivery
  /\ n \in AlertNodes
  /\ running[n]
  /\ lease = n
  /\ Ver(n) \in known
  /\ e \in occurred
  /\ e \notin deliveredS[DK(n)] \cup startS[Ver(n)]
  /\ pendEv[n] = NULL
  /\ pendEv' = [pendEv EXCEPT ![n] = e]
  /\ UNCHANGED <<running, stale, lease, occurred, deliveredS, startS, handledN, made, lost, crashes, pauses, known, pendFirst, newEv, vStart>>

\* @req INV-412  The write's condition: "not yet marked delivered for that name" (run 7). Under run 6's
\*               wording ("perSettings"), "not yet marked handled for them", i.e. neither mark of the version.
NotMarked(n) == IF MarkScope = "split" THEN pendEv[n] \notin deliveredS[DK(n)]
                ELSE pendEv[n] \notin deliveredS[DK(n)] \cup startS[Ver(n)]
DeliveryOK(n) == /\ lease = n
                 /\ DeliveryWrite = "conditional" => NotMarked(n)

\* @req INV-412  Write: create the delivery and mark the event delivered for the rule's name in one write
\*               that succeeds only if the event is not yet marked delivered for that name ("conditional").
\* @req INV-411  The same write checks that this node holds the lease.
HandleWrite(n) ==
  /\ SplitDelivery
  /\ running[n]
  /\ pendEv[n] # NULL
  /\ DeliveryOK(n)
  /\ deliveredS' = [deliveredS EXCEPT ![DK(n)] = @ \cup {pendEv[n]}]
  /\ made' = [made EXCEPT ![pendEv[n]] = Min(@ + 1, 2)]
  /\ pendEv' = [pendEv EXCEPT ![n] = NULL]
  /\ UNCHANGED <<running, stale, lease, occurred, startS, handledN, lost, crashes, pauses, known, pendFirst, newEv, vStart>>

\* @req INV-412 INV-411  The write lands but its check fails (the lease moved on, or the event was marked
\*                       delivered since the read): nothing changes and the next evaluation reads again.
HandleWriteFails(n) ==
  /\ SplitDelivery
  /\ running[n]
  /\ pendEv[n] # NULL
  /\ ~DeliveryOK(n)
  /\ pendEv' = [pendEv EXCEPT ![n] = NULL]
  /\ UNCHANGED <<running, stale, lease, occurred, deliveredS, startS, handledN, made, lost, crashes, pauses, known, pendFirst, newEv, vStart>>

\* @req INV-413  Read: the holder evaluates the rule and finds no record of its name and event settings
\*               (the version it runs) in the store.
FirstRead(n) ==
  /\ n \in AlertNodes
  /\ running[n]
  /\ lease = n
  /\ Ver(n) \notin known
  /\ ~pendFirst[n]
  /\ pendFirst' = [pendFirst EXCEPT ![n] = TRUE]
  /\ UNCHANGED <<running, stale, lease, occurred, deliveredS, startS, handledN, made, lost, crashes, pauses, known, pendEv, newEv, vStart>>

FirstOK(n) == /\ FirstWrite \in {"conditional", "fencedOnly"} => lease = n
              /\ FirstWrite = "conditional" => Ver(n) \notin known

\* @req INV-413  Write: record the version and mark every event the store records at the time of the write
\*               as before the start of that version, without deliveries, in one write that checks the lease and succeeds only if the
\*               store still has no record of the rule ("conditional").
FirstWriteStep(n) ==
  /\ running[n]
  /\ pendFirst[n]
  /\ FirstOK(n)
  /\ known' = known \cup {Ver(n)}
  /\ startS' = [startS EXCEPT ![Ver(n)] = @ \cup occurred]
  /\ vStart' = IF Ver(n) \in known THEN vStart ELSE [vStart EXCEPT ![Ver(n)] = occurred]
  /\ pendFirst' = [pendFirst EXCEPT ![n] = FALSE]
  /\ UNCHANGED <<running, stale, lease, occurred, deliveredS, handledN, made, lost, crashes, pauses, pendEv, newEv>>

\* @req INV-413  The write lands but its check fails (the lease moved on, or another holder recorded the
\*               rule since the read): nothing changes.
FirstWriteFails(n) ==
  /\ running[n]
  /\ pendFirst[n]
  /\ ~FirstOK(n)
  /\ pendFirst' = [pendFirst EXCEPT ![n] = FALSE]
  /\ UNCHANGED <<running, stale, lease, occurred, deliveredS, startS, handledN, made, lost, crashes, pauses, known, pendEv, newEv, vStart>>

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
  /\ UNCHANGED <<running, stale, lease, occurred, deliveredS, startS, handledN, made, crashes, pauses, known, pendEv, pendFirst, newEv, vStart>>

\* Environment: a node crashes; its memory is lost.
Crash(n) ==
  /\ running[n]
  /\ crashes < MaxCrashes
  /\ running' = [running EXCEPT ![n] = FALSE]
  /\ handledN' = [handledN EXCEPT ![n] = {}]
  /\ pendEv' = [pendEv EXCEPT ![n] = NULL]
  /\ pendFirst' = [pendFirst EXCEPT ![n] = FALSE]
  /\ crashes' = crashes + 1
  /\ UNCHANGED <<stale, lease, occurred, deliveredS, startS, made, lost, pauses, known, newEv, vStart>>

\* hosting REQ-60 (time abstracted, A-3): a stopped node is reported lost after NodeLostAfter.
GoesStale(n) ==
  /\ ~running[n]
  /\ ~stale[n]
  /\ stale' = [stale EXCEPT ![n] = TRUE]
  /\ UNCHANGED <<running, lease, occurred, deliveredS, startS, handledN, made, lost, crashes, pauses, known, pendEv, pendFirst, newEv, vStart>>

\* Environment (A-13): a crashed node is restarted by its host. The restarted process is a new instance:
\* it does not inherit the crashed process's lease, which must expire first (LeaseExpires).
Restart(n) ==
  /\ ~running[n]
  /\ lease # n
  /\ running' = [running EXCEPT ![n] = TRUE]
  /\ stale' = [stale EXCEPT ![n] = FALSE]
  /\ UNCHANGED <<lease, occurred, deliveredS, startS, handledN, made, lost, crashes, pauses, known, pendEv, pendFirst, newEv, vStart>>

Next ==
  \/ \E e \in Events : EventHappens(e)
  \/ LeaseExpires \/ LeasePauses
  \/ \E n \in Nodes : \/ TakeLease(n) \/ Crash(n) \/ GoesStale(n) \/ Restart(n)
                      \/ (\E e \in Events : HandleEvent(n, e) \/ HandleRead(n, e))
                      \/ HandleWrite(n) \/ HandleWriteFails(n) \/ FirstRead(n) \/ FirstWriteStep(n)
                      \/ FirstWriteFails(n)
                      \/ (\E x \in Nodes : NodeLostAlert(n, x))

\* The lease takeover and rule evaluation are system duties (REQ-438, INV-411): fair. Restart is the
\* host's job (A-13) and is fair too, so a crashed alerts node does come back.
Fairness ==
  /\ \A n \in Nodes : WF_vars(TakeLease(n)) /\ WF_vars(\E e \in Events : HandleEvent(n, e))
                      /\ WF_vars(Restart(n))
                      /\ WF_vars(\E e \in Events : HandleRead(n, e)) /\ WF_vars(HandleWrite(n))
                      /\ WF_vars(HandleWriteFails(n))
                      /\ WF_vars(FirstRead(n)) /\ WF_vars(FirstWriteStep(n)) /\ WF_vars(FirstWriteFails(n))
  /\ WF_vars(LeaseExpires)

Spec == Init /\ [][Next]_vars /\ Fairness

\* @req INV-412  "neither alerts an event again": one event never yields two deliveries
\*               (also run 1's assumption A-11).
Inv_OneDeliveryPerEvent == \A e \in Events : made[e] <= 1

\* @req INV-412  "neither a node that takes over the notification lease nor a version of the rule that
\*               takes over from another ... skips one after its start (INV-413)" (run 8): an event after
\*               the start of version v is delivered once the lease stays with a node that runs v (restarts
\*               and the lease takeover are fair, so it does stay with some node). INV-412 notes: events
\*               while no node holds the lease are alerted when a holder next runs.
HolderRuns(v) == lease \in AlertNodes /\ running[lease] /\ Ver(lease) = v /\ v \in known
Liv_EventAlerted == \A v \in Versions, e \in Events :
                      <>[](HolderRuns(v) /\ e \in occurred /\ e \notin vStart[v]) => <>(made[e] >= 1)

\* Run 7's liveness, kept as a check of a wider reading, not a requirement: every event is alerted except
\* one that happened while the store had no record of a version some alerts node runs.
Chk_EventAlertedAcrossVersions == \A e \in Events : (e \in occurred /\ e \notin newEv) ~> (made[e] >= 1)

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
  /\ deliveredS = [k \in DKeys |-> IF k = DK("a1") THEN {"e1"} ELSE {}]
  /\ startS   = [v \in Versions |-> {}]
  /\ handledN = [n \in Nodes |-> {}]
  /\ made     = [e \in Events |-> IF e = "e1" THEN 1 ELSE 0]
  /\ lost     = [n \in Nodes |-> 0]
  /\ crashes  = 0
  /\ pauses   = MaxPauses
  /\ known    = {"A"}
  /\ pendEv   = [n \in Nodes |-> NULL]
  /\ pendFirst = [n \in Nodes |-> FALSE]
  /\ newEv    = {}
  /\ vStart   = [v \in Versions |-> {}]
SpecSCN406 == InitSCN406 /\ [][Next]_vars /\ Fairness

\* @req SCN-406  Trap for IntegrationsAlerts_SCN406.cfg (expected to be VIOLATED): a2 holds the lease and
\*               there is exactly one delivery for e1 and exactly one for e2.
Scn406_NotReached ==
  ~(lease = "a2" /\ \A e \in Events : made[e] = 1)
=============================================================================
