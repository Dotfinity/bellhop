---------------------- MODULE IntegrationsNotifications ----------------------
\* Generated from integrations.json (specHash 3b92b190e27a) — FEAT-400 Notifications: cooldowns.
\* Edit the requirements, not this file. Every action/property carries an @req comment.
\* Run 2 (handoff): run 1's Reading constant is gone — INV-409, INV-410 and REQ-433 now say how a new
\* delivery decides between Pending and Suppressed and when cooldowns end. INV-400, INV-407, REQ-401,
\* REQ-403, REQ-404 and REQ-414 changed. Which node creates deliveries (INV-411, REQ-438) is in
\* IntegrationsAlerts.tla; here creation is serialised by that lease (assumption A-11).
EXTENDS Naturals, FiniteSets

CONSTANTS Rules,          \* NotificationRule instances
          Subjects,       \* subjects a rule can fire for (job, job name, node, queue, key ...)
          DeliveryIds,    \* Delivery slots
          MaxAttempts,    \* @req REQ-412  NotificationMaxAttempts (5 in the policy, 2 in the model)
          MaxPerCooldown, \* @req REQ-413  MaxDeliveriesPerCooldown (10 in the policy, 1 in the model)
          NULL

ASSUME MaxAttempts \in Nat \ {0}                          \* @req REQ-412
ASSUME MaxPerCooldown \in Nat \ {0}                       \* @req REQ-413

VARIABLES dlv,      \* Delivery slots
          coolS,    \* per rule and subject: subject cooldown open (INV-400)
          coolR,    \* per rule: rule cooldown open (INV-407, REQ-414)
          sentS,    \* history: counted sends since coolS[r][s] opened (capped at 2)
          sentR,    \* history: counted sends since coolR[r] opened
          madeR,    \* counted Pending deliveries created since coolR[r] opened (INV-409 cap)
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
\* What the trigger watches is abstracted to "the rule fires for subject s" (assumption A-1).
\* @req INV-409  Created suppressed if the subject cooldown is open (dedup, which wins over the cap), or if
\*               MaxDeliveriesPerCooldown deliveries were created pending in the open rule cooldown (cap);
\*               otherwise pending, opening the subject cooldown and, if none is open, the rule cooldown.
RuleFires(r, s) ==
  \E d \in Free :
    LET dedup  == coolS[r][s]
        capHit == coolR[r] /\ madeR[r] >= MaxPerCooldown
        st     == IF dedup \/ capHit THEN "Suppressed" ELSE "Pending"
        why    == IF dedup THEN "dedup" ELSE IF capHit THEN "cap" ELSE ""
    IN /\ dlv' = [dlv EXCEPT ![d] = [Empty EXCEPT !.status = st, !.rule = r, !.subject = s, !.why = why]]
       /\ IF st = "Pending"
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
     IN IF ~Counted(d) THEN UNCHANGED <<sentS, sentR>>
        ELSE /\ sentS' = IF coolS[r][s] THEN [sentS EXCEPT ![r][s] = Min(@ + 1, 2)] ELSE sentS
             /\ sentR' = IF coolR[r] THEN [sentR EXCEPT ![r] = Min(@ + 1, Cap)] ELSE sentR
  /\ UNCHANGED <<coolS, coolR, madeR, capSupp>>

\* @req REQ-408  rejected / unreachable and fewer than NotificationMaxAttempts attempts made: retry
\*               (backoff abstracted: the next attempt may come at any later moment, A-2).
\* @req REQ-415  rejected / unreachable and NotificationMaxAttempts attempts made: mark failed
\*               (the error log and the metric are not state). Same event, complementary guards.
\* @req REQ-433  A counted delivery marked failed closes its rule-and-subject cooldown (not the rule's).
ChannelRejects(d) ==
  /\ dlv[d].status = "Pending"
  /\ LET a    == dlv[d].attempts + 1
         r    == dlv[d].rule
         s    == dlv[d].subject
         fail == a >= MaxAttempts
     IN /\ dlv' = [dlv EXCEPT ![d].attempts = a, ![d].status = IF fail THEN "Failed" ELSE "Pending"]
        /\ IF fail /\ Counted(d)
             THEN /\ coolS' = [coolS EXCEPT ![r][s] = FALSE]
                  /\ sentS' = [sentS EXCEPT ![r][s] = 0]
             ELSE UNCHANGED <<coolS, sentS>>
  /\ UNCHANGED <<coolR, sentR, madeR, capSupp>>

\* @req REQ-409  Operator presses 'send test': a test delivery, outside the cooldown.
SendTest(r) ==
  /\ \E d \in Free : dlv' = [dlv EXCEPT ![d] = [Empty EXCEPT !.status = "Pending", !.rule = r, !.isTest = TRUE]]
  /\ UNCHANGED <<coolS, coolR, sentS, sentR, madeR, capSupp>>

\* @req INV-400  modeling artefact A-3: the subject cooldown elapses (no clock).
\* @req INV-410  ... but not while a counted delivery created in it is pending.
SubjectCooldownEnds(r, s) ==
  /\ coolS[r][s]
  /\ PendingFor(r, s) = {}
  /\ coolS' = [coolS EXCEPT ![r][s] = FALSE]
  /\ sentS' = [sentS EXCEPT ![r][s] = 0]
  /\ UNCHANGED <<dlv, coolR, sentR, madeR, capSupp>>

\* @req REQ-414  When the rule cooldown ends and deliveries were suppressed by the cap during it:
\*               create one digest delivery for the rule. (The end itself is time: A-3.)
\* @req INV-410  The rule cooldown does not end while a counted delivery created in it is pending.
RuleCooldownEnds(r) ==
  /\ coolR[r]
  /\ PendingForRule(r) = {}
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

\* @req INV-400  Never more than one non-test delivery sent for the same rule and subject within one
\*               subject cooldown.
Inv_OneSendPerSubjectCooldown == \A r \in Rules, s \in Subjects : sentS[r][s] <= 1

\* @req INV-407  Never more than MaxDeliveriesPerCooldown non-test, non-digest sends per rule within one
\*               rule cooldown.
Inv_RuleCap == \A r \in Rules : sentR[r] <= MaxPerCooldown

\* Run-1 probe for finding F-3 (kept for the delta): the delivery that opened the subject cooldown failed,
\* a later event in the same cooldown was suppressed as a duplicate, and nothing was or will be sent.
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
