---------------------- MODULE IntegrationsNotifications ----------------------
\* Generated from integrations.json (specHash 1ada134dcb35) — FEAT-400 Notifications.
\* Edit the requirements, not this file. Every action/property carries an @req comment.
\*
\* Reading (constant) selects how a new delivery decides between Pending and Suppressed,
\* because REQ-400..REQ-406 do not say (finding F-1):
\*   "literal"  : the sentences as written: to = {Pending, Suppressed}, no condition given.
\*   "atCreate" : suppressed iff a counted delivery was *created* in the open cooldown;
\*                the cooldown opens when a Pending delivery is created.
\*   "atSend"   : suppressed iff a counted delivery was *sent* in the open cooldown;
\*                the cooldown opens when a delivery is sent.
\*   "atCreateHold" : "atCreate", and a cooldown cannot end while a counted delivery created
\*                in it is still pending (tests option 1 of finding F-2; not a requirement yet).
EXTENDS Naturals, FiniteSets

CONSTANTS Rules,          \* NotificationRule instances
          Subjects,       \* subjects a rule can fire for (job, job name, node, queue, key ...)
          DeliveryIds,    \* Delivery slots
          MaxAttempts,    \* @req REQ-412  NotificationMaxAttempts (5 in the policy, 2 in the model)
          MaxPerCooldown, \* @req REQ-413  MaxDeliveriesPerCooldown (10 in the policy, 1 in the model)
          Reading,
          NULL

ASSUME MaxAttempts \in Nat \ {0}                          \* @req REQ-412
ASSUME MaxPerCooldown \in Nat \ {0}                       \* @req REQ-413
ASSUME Reading \in {"literal", "atCreate", "atSend", "atCreateHold"}

VARIABLES dlv,      \* Delivery slots
          coolS,    \* per rule and subject: cooldown open (INV-400)
          coolR,    \* per rule: cooldown open (INV-407, REQ-414)
          sentS,    \* history: counted sends since coolS[r][s] opened (capped at 2)
          sentR,    \* history: counted sends since coolR[r] opened
          madeR,    \* counted Pending deliveries created since coolR[r] opened ("atCreate" cap)
          capSupp   \* subjects suppressed by the per-rule cap in the open rule cooldown (REQ-414)
vars == <<dlv, coolS, coolR, sentS, sentR, madeR, capSupp>>

DStatus == {"none", "Pending", "Sent", "Suppressed", "Failed"}
Cap     == MaxPerCooldown + 1
DRec    == [status: DStatus, rule: Rules \cup {NULL}, subject: Subjects \cup {NULL},
            isTest: BOOLEAN, isDigest: BOOLEAN, attempts: 0..MaxAttempts, why: {"", "dedup", "cap"}]

TypeInv ==
  /\ dlv     \in [DeliveryIds -> DRec]
  /\ coolS   \in [Rules -> [Subjects -> BOOLEAN]]
  /\ coolR   \in [Rules -> BOOLEAN]
  /\ sentS   \in [Rules -> [Subjects -> 0..2]]
  /\ sentR   \in [Rules -> 0..Cap]
  /\ madeR   \in [Rules -> 0..Cap]
  /\ capSupp \in [Rules -> SUBSET Subjects]

Empty == [status |-> "none", rule |-> NULL, subject |-> NULL, isTest |-> FALSE,
          isDigest |-> FALSE, attempts |-> 0, why |-> ""]
Min(a, b) == IF a < b THEN a ELSE b
Counted(d) == ~dlv[d].isTest /\ ~dlv[d].isDigest          \* the deliveries INV-400 / INV-407 talk about
Free == {d \in DeliveryIds : dlv[d].status = "none"}
PendingFor(r, s) == {d \in DeliveryIds : dlv[d].status = "Pending" /\ Counted(d) /\ dlv[d].rule = r /\ dlv[d].subject = s}
PendingForRule(r) == {d \in DeliveryIds : dlv[d].status = "Pending" /\ Counted(d) /\ dlv[d].rule = r}

Init ==
  /\ dlv     = [d \in DeliveryIds |-> Empty]
  /\ coolS   = [r \in Rules |-> [s \in Subjects |-> FALSE]]
  /\ coolR   = [r \in Rules |-> FALSE]
  /\ sentS   = [r \in Rules |-> [s \in Subjects |-> 0]]
  /\ sentR   = [r \in Rules |-> 0]
  /\ madeR   = [r \in Rules |-> 0]
  /\ capSupp = [r \in Rules |-> {}]

\* @req REQ-400 REQ-401 REQ-402 REQ-403 REQ-404 REQ-405 REQ-406
\* Seven triggers, one shape: "create a delivery for that rule with <subject>" (to: Pending | Suppressed).
\* What the trigger watches (dead-letter, Nth failure, rate, missed occurrence, lost node, depth,
\* starved key) is abstracted to "the rule fires for subject s" (assumption A-1).
RuleFires(r, s) ==
  \E d \in Free :
    LET dedup   == coolS[r][s]
        capHit  == coolR[r] /\ (IF Reading = "atSend" THEN sentR[r] ELSE madeR[r]) >= MaxPerCooldown
        choices == IF Reading = "literal" THEN {"Pending", "Suppressed"}
                   ELSE IF dedup \/ capHit THEN {"Suppressed"} ELSE {"Pending"}
    IN \E st \in choices :
         LET why == IF st = "Pending" THEN "" ELSE IF dedup THEN "dedup" ELSE IF capHit THEN "cap" ELSE ""
         IN /\ dlv' = [dlv EXCEPT ![d] = [Empty EXCEPT !.status = st, !.rule = r, !.subject = s, !.why = why]]
            /\ IF st = "Pending" /\ Reading # "atSend"
                 THEN /\ coolS' = [coolS EXCEPT ![r][s] = TRUE]
                      /\ coolR' = [coolR EXCEPT ![r] = TRUE]
                      /\ madeR' = [madeR EXCEPT ![r] = Min(@ + 1, Cap)]
                 ELSE UNCHANGED <<coolS, coolR, madeR>>
            /\ capSupp' = IF why = "cap" THEN [capSupp EXCEPT ![r] = @ \cup {s}] ELSE capSupp
            /\ UNCHANGED <<sentS, sentR>>

\* @req REQ-407  While pending, when the channel accepts the message: mark the delivery sent.
ChannelAccepts(d) ==
  /\ dlv[d].status = "Pending"
  /\ dlv' = [dlv EXCEPT ![d].status = "Sent", ![d].attempts = @ + 1]
  /\ LET r == dlv[d].rule
         s == dlv[d].subject
     IN IF ~Counted(d) THEN UNCHANGED <<coolS, coolR, sentS, sentR>>
        ELSE IF Reading = "atSend"
          THEN /\ coolS' = [coolS EXCEPT ![r][s] = TRUE]
               /\ sentS' = [sentS EXCEPT ![r][s] = Min(@ + 1, 2)]
               /\ coolR' = [coolR EXCEPT ![r] = TRUE]
               /\ sentR' = [sentR EXCEPT ![r] = Min(@ + 1, Cap)]
          ELSE /\ sentS' = IF coolS[r][s] THEN [sentS EXCEPT ![r][s] = Min(@ + 1, 2)] ELSE sentS
               /\ sentR' = IF coolR[r] THEN [sentR EXCEPT ![r] = Min(@ + 1, Cap)] ELSE sentR
               /\ UNCHANGED <<coolS, coolR>>
  /\ UNCHANGED <<madeR, capSupp>>

\* @req REQ-408  rejected / unreachable and fewer than NotificationMaxAttempts attempts made: retry
\*               (backoff abstracted: the next attempt may come at any later moment, A-2).
\* @req REQ-415  rejected / unreachable and NotificationMaxAttempts attempts made: mark failed
\*               (the error log and the metric are not state). Same event, complementary guards.
ChannelRejects(d) ==
  /\ dlv[d].status = "Pending"
  /\ LET a == dlv[d].attempts + 1
     IN dlv' = [dlv EXCEPT ![d].attempts = a,
                           ![d].status = IF a < MaxAttempts THEN "Pending" ELSE "Failed"]
  /\ UNCHANGED <<coolS, coolR, sentS, sentR, madeR, capSupp>>

\* @req REQ-409  Operator presses 'send test': a test delivery, outside the cooldown.
SendTest(r) ==
  /\ \E d \in Free : dlv' = [dlv EXCEPT ![d] = [Empty EXCEPT !.status = "Pending", !.rule = r, !.isTest = TRUE]]
  /\ UNCHANGED <<coolS, coolR, sentS, sentR, madeR, capSupp>>

\* @req INV-400  modeling artefact A-3: the per-subject cooldown elapses (no clock).
SubjectCooldownEnds(r, s) ==
  /\ coolS[r][s]
  /\ Reading = "atCreateHold" => PendingFor(r, s) = {}
  /\ coolS' = [coolS EXCEPT ![r][s] = FALSE]
  /\ sentS' = [sentS EXCEPT ![r][s] = 0]
  /\ UNCHANGED <<dlv, coolR, sentR, madeR, capSupp>>

\* @req REQ-414  When the rule's cooldown ends and deliveries were suppressed by the cap during it:
\*               create one digest delivery for the rule. (The end itself is time: A-3.)
RuleCooldownEnds(r) ==
  /\ coolR[r]
  /\ Reading = "atCreateHold" => PendingForRule(r) = {}
  /\ coolR'   = [coolR EXCEPT ![r] = FALSE]
  /\ sentR'   = [sentR EXCEPT ![r] = 0]
  /\ madeR'   = [madeR EXCEPT ![r] = 0]
  /\ capSupp' = [capSupp EXCEPT ![r] = {}]
  /\ IF capSupp[r] = {} THEN UNCHANGED dlv
     ELSE \E d \in Free : dlv' = [dlv EXCEPT ![d] = [Empty EXCEPT !.status = "Pending", !.rule = r, !.isDigest = TRUE]]
  /\ UNCHANGED <<coolS, sentS>>

\* modeling artefact A-4: closed deliveries free their slot.
Archive(d) ==
  /\ dlv[d].status \in {"Sent", "Suppressed", "Failed"}
  /\ dlv' = [dlv EXCEPT ![d] = Empty]
  /\ UNCHANGED <<coolS, coolR, sentS, sentR, madeR, capSupp>>

Next ==
  \/ \E r \in Rules, s \in Subjects : RuleFires(r, s) \/ SubjectCooldownEnds(r, s)
  \/ \E r \in Rules : SendTest(r) \/ RuleCooldownEnds(r)
  \/ \E d \in DeliveryIds : ChannelAccepts(d) \/ ChannelRejects(d) \/ Archive(d)

Spec == Init /\ [][Next]_vars

\* @req INV-400  Never more than one non-test delivery sent for the same rule and subject within the cooldown.
Inv_OneSendPerSubjectCooldown == \A r \in Rules, s \in Subjects : sentS[r][s] <= 1

\* @req INV-407  Never more than MaxDeliveriesPerCooldown non-test, non-digest sends per rule within its cooldown.
Inv_RuleCap == \A r \in Rules : sentR[r] <= MaxPerCooldown

\* Probe (not a requirement; supports finding F-3): the delivery that opened the subject cooldown
\* failed, a later event in the same cooldown was suppressed, and nothing was or will be sent.
Probe_FailedThenSilent ==
  ~(\E r \in Rules, s \in Subjects :
      /\ coolS[r][s] /\ sentS[r][s] = 0
      /\ \E d \in DeliveryIds : dlv[d].status = "Failed" /\ Counted(d) /\ dlv[d].rule = r /\ dlv[d].subject = s
      /\ \E d \in DeliveryIds : dlv[d].status = "Suppressed" /\ dlv[d].why = "dedup" /\ dlv[d].rule = r /\ dlv[d].subject = s
      /\ ~\E d \in DeliveryIds : dlv[d].status = "Pending" /\ Counted(d) /\ dlv[d].rule = r /\ dlv[d].subject = s)

\* @req SCN-400  Trap for IntegrationsNotifications_SCN400.cfg (expected to be VIOLATED):
\*               exactly one delivery sent and one suppressed for R / sync-crm.
Scn400_NotReached ==
  ~(\E r \in Rules, s \in Subjects :
      /\ Cardinality({d \in DeliveryIds : dlv[d].status = "Sent" /\ Counted(d) /\ dlv[d].rule = r /\ dlv[d].subject = s}) = 1
      /\ Cardinality({d \in DeliveryIds : dlv[d].status = "Suppressed" /\ dlv[d].rule = r /\ dlv[d].subject = s}) = 1
      /\ \A d \in DeliveryIds : dlv[d].status \in {"none", "Sent", "Suppressed"})
=============================================================================
