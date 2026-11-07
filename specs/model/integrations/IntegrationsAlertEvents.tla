---------------------- MODULE IntegrationsAlertEvents ----------------------
\* Generated from integrations.json (specHash 138efb1f8daa) — FEAT-400 Notifications, INV-412, INV-413.
\* Edit the requirements, not this file. Every action/property carries an @req comment.
\* INV-412 makes the alerts node find once-only events "from what the job store records" and mark each one
\* handled for the rule in the store write that creates its delivery. INV-413 (run 4) says where a rule
\* starts: the first time the lease holder evaluates a name the store has no record of, every stored event
\* is marked handled for it without a delivery. This module asks what the store records for each event,
\* what one event is, and how a rule's life (added, removed, re-added, edited) moves its start point.
\* The lease is not modeled here: one alerts node holds it throughout and is always able to act
\* (INV-411, REQ-438, handovers and stale writes are in IntegrationsAlerts.tla). Retention (jobs REQ-145)
\* is not modeled; INV-412's notes accept that a removed job is no longer alerted.
\*
\* Readings and counterfactuals, one constant each (the findings name them):
\*   MissRecord : what the store holds about a missed due instant of a recurring job.
\*     "durable"     : @req recurring REQ-242  one record per trigger, kept for RetentionDeadLettered.
\*     "lastOutcome" : counterfactual "REQ-242 dropped": recurring REQ-231's last outcome only, which
\*                     the next outcome overwrites (run 3's F-17).
\*   RuleStart  : where a rule whose name the store has no record of starts.
\*     "firstSeen"    : @req INV-413  every event the store already records is marked handled.
\*     "freshCatchUp" : F-21 option: as "firstSeen", except on a store that records no rule name at all
\*                      (OtherRuleKnown = FALSE), where nothing is marked.
\*     "storeStart"   : counterfactual "INV-413 dropped": nothing is marked (run 3's F-18 flood).
\*   RuleKey    : what INV-413 knows a rule by.
\*     "name"           : @req INV-413  the rule's name only.
\*     "nameAndTrigger" : F-22 option: name plus the settings that decide which changes are its events.
\*   MarkKey    : what INV-412's handled mark is attached to.
\*     "perChange"   : @req INV-412  the recorded state change (one entry of the job's history, jobs INV-116).
\*     "perJob"      : counterfactual: the job (run 3's F-19 reading).
EXTENDS Naturals, FiniteSets

CONSTANTS SameJob,           \* TRUE: dead-letter 2 is the same job as dead-letter 1, requeued in between (jobs REQ-141)
          RuleAtStart,       \* TRUE: the rule is configured from the start; FALSE: it is added later (REQ-410)
          OtherRuleKnown,    \* TRUE: the store already records some other rule's name (not a new system)
          InitialWatch,      \* which once-only events the rule watches: subset of {"dl", "miss"} (A-19)
          AllowRemove,       \* the rule may be removed from configuration and added back
          AllowEdit,         \* the rule's trigger may be edited from dead-letters to missed occurrences
          MaxChanges,        \* configuration changes in one behaviour
          RuleStart, RuleKey, MarkKey, MissRecord

ASSUME SameJob \in BOOLEAN /\ RuleAtStart \in BOOLEAN /\ OtherRuleKnown \in BOOLEAN
ASSUME InitialWatch \subseteq {"dl", "miss"} /\ AllowRemove \in BOOLEAN /\ AllowEdit \in BOOLEAN
ASSUME MaxChanges \in Nat
ASSUME RuleStart \in {"firstSeen", "freshCatchUp", "storeStart"}
ASSUME RuleKey \in {"name", "nameAndTrigger"}
ASSUME MarkKey \in {"perChange", "perJob"}
ASSUME MissRecord \in {"durable", "lastOutcome"}

DL       == 1..2        \* dead-letter transitions, in the order they happen
Instants == 1..2        \* triggers of one recurring job that each find a missed instant, in order
JobOf(d) == IF SameJob THEN 1 ELSE d
Outcome  == [k: {"none", "skipped", "succeeded"}, i: 0..2]

VARIABLES ruleOn,       \* the rule is loaded by the lease holder (REQ-410)
          known,        \* @req INV-413  the store records the rule (by RuleKey)
          watch,        \* which once-only events the rule watches (its trigger)
          changes,      \* configuration changes so far
          dl,           \* number of dead-letters so far; each is in the job's state history (jobs INV-116)
          processed,    \* number of triggers so far (recurring REQ-216)
          lastOutcome,  \* recurring REQ-231: the recurring job's last outcome (one field)
          missRec,      \* @req recurring REQ-242  miss records in the store
          markDL,       \* INV-412 handled marks for the rule: "perChange" dead-letter entries
          markJob,      \*   "perJob": jobs
          markMI,       \*   miss records
          madeDL, madeMI,          \* history: deliveries created per dead-letter / per miss record
          missedI,                 \* history: triggers that found a missed instant
          dlOff, miOff,            \* history: events that happened while the rule did not watch them
          dlNew, miNew             \* history: events that happened while the store had no record of the rule
vars == <<ruleOn, known, watch, changes, dl, processed, lastOutcome, missRec, markDL, markJob, markMI,
          madeDL, madeMI, missedI, dlOff, miOff, dlNew, miNew>>

TypeInv ==
  /\ ruleOn \in BOOLEAN /\ known \in BOOLEAN
  /\ watch \subseteq {"dl", "miss"} /\ changes \in 0..MaxChanges
  /\ dl \in 0..2 /\ processed \in 0..2
  /\ lastOutcome \in Outcome
  /\ missRec \subseteq Instants /\ missedI \subseteq Instants
  /\ markDL \subseteq DL /\ markJob \subseteq DL /\ markMI \subseteq Instants
  /\ madeDL \in [DL -> 0..2] /\ madeMI \in [Instants -> 0..2]
  /\ dlOff \subseteq DL /\ miOff \subseteq Instants /\ dlNew \subseteq DL /\ miNew \subseteq Instants

Min(a, b) == IF a < b THEN a ELSE b
Watches(k) == ruleOn /\ k \in watch

Init ==
  /\ ruleOn = RuleAtStart
  /\ known = FALSE
  /\ watch = InitialWatch
  /\ changes = 0
  /\ dl = 0 /\ processed = 0
  /\ lastOutcome = [k |-> "none", i |-> 0]
  /\ missRec = {} /\ missedI = {}
  /\ markDL = {} /\ markJob = {} /\ markMI = {}
  /\ madeDL = [d \in DL |-> 0] /\ madeMI = [i \in Instants |-> 0]
  /\ dlOff = {} /\ miOff = {} /\ dlNew = {} /\ miNew = {}

\* jobs REQ-131 (and REQ-141 in between when SameJob): a job is dead-lettered; jobs INV-116 records the
\* transition in its state history, so the store holds the event.
DeadLetter ==
  /\ dl < 2
  /\ dl' = dl + 1
  /\ dlOff' = IF Watches("dl") THEN dlOff ELSE dlOff \cup {dl + 1}
  /\ dlNew' = IF known THEN dlNew ELSE dlNew \cup {dl + 1}
  /\ UNCHANGED <<ruleOn, known, watch, changes, processed, lastOutcome, missRec, markDL, markJob, markMI,
                 madeDL, madeMI, missedI, miOff, miNew>>

\* recurring REQ-216, REQ-217/REQ-218, REQ-231, REQ-242: a trigger finds a missed instant. nextRunAt moves on
\* in one compare-and-set that, with REQ-242, also writes one miss record; under Skip the last outcome
\* becomes "skipped" (under RunOnce there is not even that, see the run-3 F-17 text).
TriggerMissed ==
  /\ processed < 2
  /\ processed' = processed + 1
  /\ lastOutcome' = [k |-> "skipped", i |-> processed + 1]
  /\ missRec' = IF MissRecord = "durable" THEN missRec \cup {processed + 1} ELSE missRec
  /\ missedI' = missedI \cup {processed + 1}
  /\ miOff' = IF Watches("miss") THEN miOff ELSE miOff \cup {processed + 1}
  /\ miNew' = IF known THEN miNew ELSE miNew \cup {processed + 1}
  /\ UNCHANGED <<ruleOn, known, watch, changes, dl, markDL, markJob, markMI, madeDL, madeMI, dlOff, dlNew>>

\* recurring REQ-216, INV-207, REQ-231: the trigger is on time; its occurrence runs and succeeds, and the
\* last outcome becomes "succeeded" (creation and finish are one step here).
TriggerRuns ==
  /\ processed < 2
  /\ processed' = processed + 1
  /\ lastOutcome' = [k |-> "succeeded", i |-> processed + 1]
  /\ UNCHANGED <<ruleOn, known, watch, changes, dl, missRec, markDL, markJob, markMI, madeDL, madeMI,
                 missedI, dlOff, miOff, dlNew, miNew>>

\* Where the store shows a missed instant to the alerts node.
Findable(i) ==
  IF MissRecord = "durable" THEN i \in missRec
  ELSE lastOutcome = [k |-> "skipped", i |-> i]

\* REQ-410: the rule is added to configuration or code (an operator or developer act, not fair). Its
\* store record and marks, if any, are kept by name (INV-413 notes).
AddRule ==
  /\ ~ruleOn
  /\ changes < MaxChanges
  /\ ruleOn' = TRUE
  /\ changes' = changes + 1
  /\ UNCHANGED <<known, watch, dl, processed, lastOutcome, missRec, markDL, markJob, markMI, madeDL, madeMI,
                 missedI, dlOff, miOff, dlNew, miNew>>

\* REQ-410: the rule is removed (or a node without it holds the lease during a rolling deploy). INV-413
\* notes: its record and handled marks are kept by name while no node loads it.
RemoveRule ==
  /\ AllowRemove
  /\ ruleOn
  /\ changes < MaxChanges
  /\ ruleOn' = FALSE
  /\ changes' = changes + 1
  /\ UNCHANGED <<known, watch, dl, processed, lastOutcome, missRec, markDL, markJob, markMI, madeDL, madeMI,
                 missedI, dlOff, miOff, dlNew, miNew>>

\* REQ-410: a developer edits the rule's trigger, keeping its name (dead-letters -> missed occurrences).
\* With RuleKey = "nameAndTrigger" the edited rule is a key the store has no record of.
EditRule ==
  /\ AllowEdit
  /\ ruleOn
  /\ watch = {"dl"}
  /\ changes < MaxChanges
  /\ watch' = {"miss"}
  /\ changes' = changes + 1
  /\ known' = IF RuleKey = "name" THEN known ELSE FALSE
  /\ UNCHANGED <<ruleOn, dl, processed, lastOutcome, missRec, markDL, markJob, markMI, madeDL, madeMI,
                 missedI, dlOff, miOff, dlNew, miNew>>

\* @req INV-413  The lease holder evaluates a rule the store has no record of: record it and mark every
\*               event the store already records as handled for it, without creating deliveries.
\*               (One step here; whether the write may act on a stale read is in IntegrationsAlerts.tla.)
FirstSeen ==
  /\ ruleOn
  /\ ~known
  /\ known' = TRUE
  /\ IF RuleStart = "firstSeen" \/ (RuleStart = "freshCatchUp" /\ OtherRuleKnown)
       THEN /\ markDL' = markDL \cup 1..dl
            /\ markJob' = markJob \cup {JobOf(d) : d \in 1..dl}
            /\ markMI' = markMI \cup {i \in Instants : Findable(i)}
       ELSE UNCHANGED <<markDL, markJob, markMI>>
  /\ UNCHANGED <<ruleOn, watch, changes, dl, processed, lastOutcome, missRec, madeDL, madeMI, missedI,
                 dlOff, miOff, dlNew, miNew>>

Unmarked(d) == IF MarkKey = "perChange" THEN d \notin markDL ELSE JobOf(d) \notin markJob

\* @req REQ-400  A job is dead-lettered: a delivery for the rule with the job as subject.
\* @req INV-412  The event is found in the store and marked handled in the write that creates the delivery.
HandleDeadLetter(d) ==
  /\ Watches("dl") /\ known
  /\ d <= dl
  /\ Unmarked(d)
  /\ markDL' = markDL \cup {d}
  /\ markJob' = markJob \cup {JobOf(d)}
  /\ madeDL' = [madeDL EXCEPT ![d] = Min(@ + 1, 2)]
  /\ UNCHANGED <<ruleOn, known, watch, changes, dl, processed, lastOutcome, missRec, markMI, madeMI, missedI,
                 dlOff, miOff, dlNew, miNew>>

\* @req REQ-403  An occurrence is missed: a delivery for the rule with the recurring job as subject.
\* @req INV-412  Found in the store (recurring REQ-242's record) and marked handled in the same write.
HandleMissed(i) ==
  /\ Watches("miss") /\ known
  /\ Findable(i)
  /\ i \notin markMI
  /\ markMI' = markMI \cup {i}
  /\ madeMI' = [madeMI EXCEPT ![i] = Min(@ + 1, 2)]
  /\ UNCHANGED <<ruleOn, known, watch, changes, dl, processed, lastOutcome, missRec, markDL, markJob, madeDL,
                 missedI, dlOff, miOff, dlNew, miNew>>

Next ==
  \/ DeadLetter \/ TriggerMissed \/ TriggerRuns \/ AddRule \/ RemoveRule \/ EditRule \/ FirstSeen
  \/ \E d \in DL : HandleDeadLetter(d)
  \/ \E i \in Instants : HandleMissed(i)

\* Rule evaluation is a system duty of the lease holder (INV-411): fair. Events and configuration
\* changes are not.
Fairness == /\ WF_vars(FirstSeen)
            /\ \A d \in DL : WF_vars(HandleDeadLetter(d))
            /\ \A i \in Instants : WF_vars(HandleMissed(i))
Spec == Init /\ [][Next]_vars /\ Fairness
\* For the remove-and-re-add check only: the removed rule does come back (a rolling deploy finishes).
SpecReadd == Spec /\ WF_vars(AddRule)

\* @req INV-412  "neither alerts an event again".
Inv_OneDeliveryPerEvent == /\ \A d \in DL : madeDL[d] <= 1
                           /\ \A i \in Instants : madeMI[i] <= 1

\* @req REQ-400 INV-412 INV-413  Every dead-letter after the rule's start point (INV-413) is alerted.
Liv_DeadLetterAlerted == \A d \in DL : (d <= dl /\ d \notin dlNew) ~> (madeDL[d] >= 1)

\* @req REQ-403 INV-412 INV-413  Every missed instant after the rule's start point is alerted.
Liv_MissedAlerted == \A i \in Instants : (i \in missedI /\ i \notin miNew) ~> (madeMI[i] >= 1)

\* REQ-400 / REQ-403 "where a rule watches …, when …": no delivery for an event that happened while the
\* rule did not watch it. A check of one reading, not a requirement (F-18 in run 3, F-22 and *Accepted*).
Chk_NoAlertForEventBeforeRule == /\ \A d \in DL : madeDL[d] >= 1 => d \notin dlOff
                                 /\ \A i \in Instants : madeMI[i] >= 1 => i \notin miOff

\* INV-412 notes, "events that happen … while no alerts node runs at all are alerted when a holder next
\* runs": every event that happens while the rule is configured is alerted, including those before the
\* holder first evaluates it. A check of one reading, not a requirement (F-21).
Chk_ConfiguredEventAlerted ==
  /\ \A d \in DL : (d <= dl /\ d \notin dlOff) ~> (madeDL[d] >= 1)
  /\ \A i \in Instants : (i \in missedI /\ i \notin miOff) ~> (madeMI[i] >= 1)
=============================================================================
