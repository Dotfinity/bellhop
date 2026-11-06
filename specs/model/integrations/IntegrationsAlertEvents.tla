---------------------- MODULE IntegrationsAlertEvents ----------------------
\* Generated from integrations.json (specHash 8d15657c8cd5) — FEAT-400 Notifications, INV-412.
\* Edit the requirements, not this file. Every action/property carries an @req comment.
\* New in run 3. INV-412 makes the alerts node find once-only events "from what the job store records"
\* and mark each one handled for the rule in the store write that creates its delivery. This module asks
\* what the store records for each event, what one event is, and where a newly configured rule starts.
\* The lease is not modeled here: one alerts node holds it throughout and is always able to act
\* (INV-411, REQ-438 and handovers are in IntegrationsAlerts.tla). Retention (jobs REQ-145) is not
\* modeled; INV-412's notes accept that a removed job is no longer alerted.
\*
\* Readings the sentences leave open, one constant each (the findings name them):
\*   MissRecord : what the store holds about a missed due instant of a recurring job with misfire Skip.
\*     "lastOutcome" : recurring REQ-231's last outcome, the only stored trace a requirement gives; the
\*                     next outcome overwrites it. REQ-220's log line and recurring-missed event are not
\*                     in the store (jobs REQ-169 raises the event in memory on the triggering node).
\*     "durable"     : every missed instant is recorded in the store (an option, not a requirement).
\*   RuleStart  : what a rule configured after events happened treats as not yet handled.
\*     "storeStart"  : every once-only event the store still holds (no handled mark exists for the rule).
\*     "ruleAdded"   : only events after the rule was configured (its marks start at the store's present).
\*   MarkKey    : what INV-412's handled mark is attached to.
\*     "perChange"   : the recorded state change (one entry of the job's state history, jobs INV-116).
\*     "perJob"      : the job (the subject).
EXTENDS Naturals, FiniteSets

CONSTANTS SameJob,      \* TRUE: dead-letter 2 is the same job as dead-letter 1, requeued in between (jobs REQ-141)
          RuleAtStart,  \* TRUE: the rule is configured from the start; FALSE: it is added later (REQ-410)
          RuleStart,
          MarkKey,
          MissRecord

ASSUME SameJob \in BOOLEAN /\ RuleAtStart \in BOOLEAN
ASSUME RuleStart \in {"storeStart", "ruleAdded"}
ASSUME MarkKey \in {"perChange", "perJob"}
ASSUME MissRecord \in {"lastOutcome", "durable"}

DL       == 1..2        \* dead-letter transitions, in the order they happen
Instants == 1..2        \* due instants of one recurring job, in order
JobOf(d) == IF SameJob THEN 1 ELSE d
Outcome  == [k: {"none", "skipped", "succeeded"}, i: 0..2]

VARIABLES ruleOn,       \* the rule is configured (REQ-410)
          dl,           \* number of dead-letters so far; each is in the job's state history (jobs INV-116)
          processed,    \* number of due instants the trigger has handled (recurring REQ-216)
          lastOutcome,  \* recurring REQ-231: the recurring job's last outcome (one field)
          missRec,      \* "durable": missed instants recorded in the store
          markDL,       \* INV-412 handled marks for the rule: "perChange" dead-letter entries
          markJob,      \*   "perJob": jobs
          markMI,       \*   missed instants
          madeDL, madeMI,          \* history: deliveries created per dead-letter / per missed instant
          missedI,                 \* history: instants that were missed
          dlBefore, miBefore       \* history: events that happened while the rule was not configured
vars == <<ruleOn, dl, processed, lastOutcome, missRec, markDL, markJob, markMI, madeDL, madeMI,
          missedI, dlBefore, miBefore>>

TypeInv ==
  /\ ruleOn \in BOOLEAN
  /\ dl \in 0..2 /\ processed \in 0..2
  /\ lastOutcome \in Outcome
  /\ missRec \subseteq Instants /\ missedI \subseteq Instants
  /\ markDL \subseteq DL /\ markJob \subseteq DL /\ markMI \subseteq Instants
  /\ madeDL \in [DL -> 0..2] /\ madeMI \in [Instants -> 0..2]
  /\ dlBefore \subseteq DL /\ miBefore \subseteq Instants

Min(a, b) == IF a < b THEN a ELSE b

Init ==
  /\ ruleOn = RuleAtStart
  /\ dl = 0 /\ processed = 0
  /\ lastOutcome = [k |-> "none", i |-> 0]
  /\ missRec = {} /\ missedI = {}
  /\ markDL = {} /\ markJob = {} /\ markMI = {}
  /\ madeDL = [d \in DL |-> 0] /\ madeMI = [i \in Instants |-> 0]
  /\ dlBefore = {} /\ miBefore = {}

\* jobs REQ-131 (and REQ-141 in between when SameJob): a job is dead-lettered; jobs INV-116 records the
\* transition in its state history, so the store holds the event.
DeadLetter ==
  /\ dl < 2
  /\ dl' = dl + 1
  /\ dlBefore' = IF ruleOn THEN dlBefore ELSE dlBefore \cup {dl + 1}
  /\ UNCHANGED <<ruleOn, processed, lastOutcome, missRec, markDL, markJob, markMI, madeDL, madeMI,
                 missedI, miBefore>>

\* recurring REQ-218 (misfire Skip), REQ-231, REQ-220: the next due instant was missed; no occurrence is
\* created, nextRunAt moves on, the last outcome becomes "skipped", the miss is logged and raised in
\* memory. Only "durable" adds a store record of the instant itself.
TriggerMissed ==
  /\ processed < 2
  /\ processed' = processed + 1
  /\ lastOutcome' = [k |-> "skipped", i |-> processed + 1]
  /\ missRec' = IF MissRecord = "durable" THEN missRec \cup {processed + 1} ELSE missRec
  /\ missedI' = missedI \cup {processed + 1}
  /\ miBefore' = IF ruleOn THEN miBefore ELSE miBefore \cup {processed + 1}
  /\ UNCHANGED <<ruleOn, dl, markDL, markJob, markMI, madeDL, madeMI, dlBefore>>

\* recurring REQ-216, INV-207, REQ-231: the next due instant is on time; its occurrence runs and succeeds, and the
\* last outcome becomes "succeeded" (creation and finish are one step here).
TriggerRuns ==
  /\ processed < 2
  /\ processed' = processed + 1
  /\ lastOutcome' = [k |-> "succeeded", i |-> processed + 1]
  /\ UNCHANGED <<ruleOn, dl, missRec, markDL, markJob, markMI, madeDL, madeMI, missedI, dlBefore, miBefore>>

\* Where the store shows a missed instant to the alerts node.
Findable(i) ==
  IF MissRecord = "durable" THEN i \in missRec
  ELSE lastOutcome = [k |-> "skipped", i |-> i]

\* REQ-410: the rule is added to configuration or code (an operator or developer act, not fair).
AddRule ==
  /\ ~ruleOn
  /\ ruleOn' = TRUE
  /\ IF RuleStart = "ruleAdded"
       THEN /\ markDL' = 1..dl
            /\ markJob' = {JobOf(d) : d \in 1..dl}
            /\ markMI' = {i \in Instants : Findable(i)}
       ELSE UNCHANGED <<markDL, markJob, markMI>>
  /\ UNCHANGED <<dl, processed, lastOutcome, missRec, madeDL, madeMI, missedI, dlBefore, miBefore>>

Unmarked(d) == IF MarkKey = "perChange" THEN d \notin markDL ELSE JobOf(d) \notin markJob

\* @req REQ-400  A job is dead-lettered: a delivery for the rule with the job as subject.
\* @req INV-412  The event is found in the store and marked handled in the write that creates the delivery.
HandleDeadLetter(d) ==
  /\ ruleOn
  /\ d <= dl
  /\ Unmarked(d)
  /\ markDL' = markDL \cup {d}
  /\ markJob' = markJob \cup {JobOf(d)}
  /\ madeDL' = [madeDL EXCEPT ![d] = Min(@ + 1, 2)]
  /\ UNCHANGED <<ruleOn, dl, processed, lastOutcome, missRec, markMI, madeMI, missedI, dlBefore, miBefore>>

\* @req REQ-403  An occurrence is missed: a delivery for the rule with the recurring job as subject.
\* @req INV-412  Found in the store and marked handled in the same write.
HandleMissed(i) ==
  /\ ruleOn
  /\ Findable(i)
  /\ i \notin markMI
  /\ markMI' = markMI \cup {i}
  /\ madeMI' = [madeMI EXCEPT ![i] = Min(@ + 1, 2)]
  /\ UNCHANGED <<ruleOn, dl, processed, lastOutcome, missRec, markDL, markJob, madeDL, missedI, dlBefore, miBefore>>

Next ==
  \/ DeadLetter \/ TriggerMissed \/ TriggerRuns \/ AddRule
  \/ \E d \in DL : HandleDeadLetter(d)
  \/ \E i \in Instants : HandleMissed(i)

\* Rule evaluation is a system duty of the lease holder (INV-411): fair. Events and AddRule are not.
Spec == Init /\ [][Next]_vars /\ \A d \in DL : WF_vars(HandleDeadLetter(d))
                              /\ \A i \in Instants : WF_vars(HandleMissed(i))

\* @req INV-412  "neither alerts an event again".
Inv_OneDeliveryPerEvent == /\ \A d \in DL : madeDL[d] <= 1
                           /\ \A i \in Instants : madeMI[i] <= 1

\* @req REQ-400 INV-412  Every dead-letter that happens while the rule is configured is alerted.
Liv_DeadLetterAlerted == \A d \in DL : (d <= dl /\ d \notin dlBefore) ~> (madeDL[d] >= 1)

\* @req REQ-403 INV-412  Every missed instant that happens while the rule is configured is alerted.
Liv_MissedAlerted == \A i \in Instants : (i \in missedI /\ i \notin miBefore) ~> (madeMI[i] >= 1)

\* REQ-400 / REQ-403 "where a rule watches …, when …": no delivery for an event that happened before
\* the rule existed. A check of one reading, not a requirement (finding F-18).
Chk_NoAlertForEventBeforeRule == /\ \A d \in DL : madeDL[d] >= 1 => d \notin dlBefore
                                 /\ \A i \in Instants : madeMI[i] >= 1 => i \notin miBefore
=============================================================================
