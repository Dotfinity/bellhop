---------------------- MODULE IntegrationsAlertEvents ----------------------
\* Generated from integrations.json (specHash 05969b22d40d) — FEAT-400 Notifications, INV-412, INV-413.
\* Edit the requirements, not this file. Every action/property carries an @req comment.
\* INV-412 makes the alerts node find once-only events "from what the job store records" and mark each one
\* handled for the rule in the store write that creates its delivery. INV-413 says where a rule starts: the
\* first time the lease holder evaluates a rule whose name and event settings (trigger, threshold,
\* tolerance; run 5) the store has no record of, every stored event is marked handled for it without a
\* delivery. This module asks what the store records for each event, what one event is, and how a rule's
\* life (added, removed, re-added, edited, edited back) moves its start point.
\* The lease is not modeled here: one alerts node holds it throughout and is always able to act
\* (INV-411, REQ-438, handovers and stale writes are in IntegrationsAlerts.tla). Retention (jobs REQ-145)
\* is not modeled; INV-412's notes accept that a removed job is no longer alerted.
\*
\* Readings and counterfactuals, one constant each (the findings name them):
\*   MissRecord : what the store holds about a missed due instant of a recurring job.
\*     "durable"     : @req recurring REQ-242  one record each time nextRunAt moves past missed instants,
\*                     by a trigger (REQ-216) or a schedule change (REQ-227), kept for RetentionDeadLettered.
\*     "lastOutcome" : counterfactual "REQ-242 dropped": recurring REQ-231's last outcome only, which
\*                     the next outcome overwrites and a schedule change never writes (run 3's F-17).
\*   RuleStart  : where a rule the store has no record of starts.
\*     "firstSeen"    : @req INV-413  every event the store already records is marked handled.
\*     "freshCatchUp" : run-4 F-21 option (not chosen): as "firstSeen", except on a store that records no
\*                      rule at all (OtherRuleKnown = FALSE), where nothing is marked.
\*     "storeStart"   : counterfactual "INV-413 dropped": nothing is marked (run 3's F-18 flood).
\*   RuleKey    : what INV-413's store record knows a rule by.
\*     "nameAndSettings" : @req INV-413  the rule's name and event settings. In this model the settings
\*                         are the trigger (watch); a threshold or tolerance edit is the same kind of change.
\*     "nameOnly"        : counterfactual: run 4's wording, the name only (run 4's F-22).
\*                         Records are kept, never replaced (INV-413 notes: "kept ... continues where it
\*                         stopped"), so a rule edited back to earlier settings finds their record again.
\*   MarkScope  : what "handled for that rule" (INV-412, INV-413) is attached to, now that a rule is known
\*                by more than its name. The sentences do not say (run 5 finding).
\*     "perName"     : one set of marks per rule name, shared by every version of its settings.
\*     "perSettings" : one set of marks per record (name and event settings).
\*   MarkKey    : what INV-412's handled mark is attached to.
\*     "perChange"   : @req INV-412  the recorded state change (one entry of the job's history, jobs INV-116).
\*     "perJob"      : counterfactual: the job (run 3's F-19 reading).
EXTENDS Naturals, FiniteSets

CONSTANTS SameJob,           \* TRUE: dead-letter 2 is the same job as dead-letter 1, requeued in between (jobs REQ-141)
          RuleAtStart,       \* TRUE: the rule is configured from the start; FALSE: it is added later (REQ-410)
          OtherRuleKnown,    \* TRUE: the store already records some other rule (not a new system)
          InitialWatch,      \* which once-only events the rule watches: subset of {"dl", "miss"} (A-19)
          AllowRemove,       \* the rule may be removed from configuration and added back
          AllowEdit,         \* the rule's trigger may be edited between dead-letters and missed occurrences
          MaxChanges,        \* configuration changes in one behaviour
          RuleStart, RuleKey, MarkScope, MarkKey, MissRecord

ASSUME SameJob \in BOOLEAN /\ RuleAtStart \in BOOLEAN /\ OtherRuleKnown \in BOOLEAN
ASSUME InitialWatch \subseteq {"dl", "miss"} /\ AllowRemove \in BOOLEAN /\ AllowEdit \in BOOLEAN
ASSUME MaxChanges \in Nat
ASSUME RuleStart \in {"firstSeen", "freshCatchUp", "storeStart"}
ASSUME RuleKey \in {"nameAndSettings", "nameOnly"}
ASSUME MarkScope \in {"perName", "perSettings"}
ASSUME MarkKey \in {"perChange", "perJob"}
ASSUME MissRecord \in {"durable", "lastOutcome"}

DL       == 1..2        \* dead-letter transitions, in the order they happen
Instants == 1..2        \* moves of one recurring job's nextRunAt past a missed instant, in order
JobOf(d) == IF SameJob THEN 1 ELSE d
Outcome  == [k: {"none", "skipped", "succeeded"}, i: 0..2]
Keys     == SUBSET {"dl", "miss"}   \* {} stands for "the name only"

\* @req INV-413  The key of the store record for the rule as it is now configured.
RecKey(w)  == IF RuleKey = "nameOnly" THEN {} ELSE w
\* The key its handled marks are kept under.
MarkKy(w)  == IF MarkScope = "perName" THEN {} ELSE RecKey(w)

VARIABLES ruleOn,       \* the rule is loaded by the lease holder (REQ-410)
          known,        \* @req INV-413  the records the store keeps for the rule (set of RecKey values)
          watch,        \* which once-only events the rule watches (its trigger)
          changes,      \* configuration changes so far
          dl,           \* number of dead-letters so far; each is in the job's state history (jobs INV-116)
          processed,    \* number of moves of nextRunAt so far (recurring REQ-216, REQ-227)
          lastOutcome,  \* recurring REQ-231: the recurring job's last outcome (one field)
          missRec,      \* @req recurring REQ-242  miss records in the store
          markDL,       \* INV-412 handled marks, per mark key: "perChange" dead-letter entries
          markJob,      \*   "perJob": jobs
          markMI,       \*   miss records
          madeDL, madeMI,          \* history: deliveries created per dead-letter / per miss record
          missedI,                 \* history: moves of nextRunAt past a missed instant
          dlOff, miOff,            \* history: events that happened while the rule did not watch them
          dlNew, miNew             \* history: events that happened while the store had no record of the rule
vars == <<ruleOn, known, watch, changes, dl, processed, lastOutcome, missRec, markDL, markJob, markMI,
          madeDL, madeMI, missedI, dlOff, miOff, dlNew, miNew>>

TypeInv ==
  /\ ruleOn \in BOOLEAN /\ known \subseteq Keys
  /\ watch \subseteq {"dl", "miss"} /\ changes \in 0..MaxChanges
  /\ dl \in 0..2 /\ processed \in 0..2
  /\ lastOutcome \in Outcome
  /\ missRec \subseteq Instants /\ missedI \subseteq Instants
  /\ markDL \in [Keys -> SUBSET DL] /\ markJob \in [Keys -> SUBSET DL] /\ markMI \in [Keys -> SUBSET Instants]
  /\ madeDL \in [DL -> 0..2] /\ madeMI \in [Instants -> 0..2]
  /\ dlOff \subseteq DL /\ miOff \subseteq Instants /\ dlNew \subseteq DL /\ miNew \subseteq Instants

Min(a, b) == IF a < b THEN a ELSE b
Watches(k) == ruleOn /\ k \in watch
Known == RecKey(watch) \in known

Init ==
  /\ ruleOn = RuleAtStart
  /\ known = {}
  /\ watch = InitialWatch
  /\ changes = 0
  /\ dl = 0 /\ processed = 0
  /\ lastOutcome = [k |-> "none", i |-> 0]
  /\ missRec = {} /\ missedI = {}
  /\ markDL = [k \in Keys |-> {}] /\ markJob = [k \in Keys |-> {}] /\ markMI = [k \in Keys |-> {}]
  /\ madeDL = [d \in DL |-> 0] /\ madeMI = [i \in Instants |-> 0]
  /\ dlOff = {} /\ miOff = {} /\ dlNew = {} /\ miNew = {}

\* jobs REQ-131 (and REQ-141 in between when SameJob): a job is dead-lettered; jobs INV-116 records the
\* transition in its state history, so the store holds the event.
DeadLetter ==
  /\ dl < 2
  /\ dl' = dl + 1
  /\ dlOff' = IF Watches("dl") THEN dlOff ELSE dlOff \cup {dl + 1}
  /\ dlNew' = IF Known THEN dlNew ELSE dlNew \cup {dl + 1}
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
  /\ miNew' = IF Known THEN miNew ELSE miNew \cup {processed + 1}
  /\ UNCHANGED <<ruleOn, known, watch, changes, dl, markDL, markJob, markMI, madeDL, madeMI, dlOff, dlNew>>

\* @req recurring REQ-227 REQ-242  (run 5) The recurring job's schedule changes while an instant is overdue:
\* nextRunAt is computed from now and moves past it with no catch-up and no occurrence, so REQ-231 records
\* no outcome; REQ-242 records the instant as dropped by the schedule change in the same write.
ScheduleChangeMissed ==
  /\ processed < 2
  /\ processed' = processed + 1
  /\ missRec' = IF MissRecord = "durable" THEN missRec \cup {processed + 1} ELSE missRec
  /\ missedI' = missedI \cup {processed + 1}
  /\ miOff' = IF Watches("miss") THEN miOff ELSE miOff \cup {processed + 1}
  /\ miNew' = IF Known THEN miNew ELSE miNew \cup {processed + 1}
  /\ UNCHANGED <<ruleOn, known, watch, changes, dl, lastOutcome, markDL, markJob, markMI, madeDL, madeMI,
                 dlOff, dlNew>>

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
\* store records and marks, if any, are kept (INV-413 notes).
AddRule ==
  /\ ~ruleOn
  /\ changes < MaxChanges
  /\ ruleOn' = TRUE
  /\ changes' = changes + 1
  /\ UNCHANGED <<known, watch, dl, processed, lastOutcome, missRec, markDL, markJob, markMI, madeDL, madeMI,
                 missedI, dlOff, miOff, dlNew, miNew>>

\* REQ-410: the rule is removed (or a node without it holds the lease during a rolling deploy). INV-413
\* notes: its records and handled marks are kept while no node loads it.
RemoveRule ==
  /\ AllowRemove
  /\ ruleOn
  /\ changes < MaxChanges
  /\ ruleOn' = FALSE
  /\ changes' = changes + 1
  /\ UNCHANGED <<known, watch, dl, processed, lastOutcome, missRec, markDL, markJob, markMI, madeDL, madeMI,
                 missedI, dlOff, miOff, dlNew, miNew>>

\* REQ-410: a developer edits the rule's trigger, keeping its name (dead-letters <-> missed occurrences).
\* A second edit puts the old trigger back (a rollback, or a rolling deploy that moves the lease from a
\* node with the new version back to one with the old). With RuleKey = "nameAndSettings" the edited rule
\* is a record the store may not have yet (INV-413).
EditRule ==
  /\ AllowEdit
  /\ ruleOn
  /\ watch \in {{"dl"}, {"miss"}}
  /\ changes < MaxChanges
  /\ watch' = IF watch = {"dl"} THEN {"miss"} ELSE {"dl"}
  /\ changes' = changes + 1
  /\ UNCHANGED <<ruleOn, known, dl, processed, lastOutcome, missRec, markDL, markJob, markMI, madeDL, madeMI,
                 missedI, dlOff, miOff, dlNew, miNew>>

\* @req INV-413  The lease holder evaluates a rule whose name and event settings the store has no record
\*               of: record them and mark every event the store records as handled for that rule, without
\*               creating deliveries. (One step here; the write's lease check and condition across a
\*               handover are in IntegrationsAlerts.tla.)
FirstSeen ==
  /\ ruleOn
  /\ ~Known
  /\ known' = known \cup {RecKey(watch)}
  /\ IF RuleStart = "firstSeen" \/ (RuleStart = "freshCatchUp" /\ OtherRuleKnown)
       THEN /\ markDL' = [markDL EXCEPT ![MarkKy(watch)] = @ \cup 1..dl]
            /\ markJob' = [markJob EXCEPT ![MarkKy(watch)] = @ \cup {JobOf(d) : d \in 1..dl}]
            /\ markMI' = [markMI EXCEPT ![MarkKy(watch)] = @ \cup {i \in Instants : Findable(i)}]
       ELSE UNCHANGED <<markDL, markJob, markMI>>
  /\ UNCHANGED <<ruleOn, watch, changes, dl, processed, lastOutcome, missRec, madeDL, madeMI, missedI,
                 dlOff, miOff, dlNew, miNew>>

Unmarked(d) == IF MarkKey = "perChange" THEN d \notin markDL[MarkKy(watch)]
               ELSE JobOf(d) \notin markJob[MarkKy(watch)]

\* @req REQ-400  A job is dead-lettered: a delivery for the rule with the job as subject.
\* @req INV-412  The event is found in the store and, in one write that succeeds only if it is not yet
\*               marked handled for the rule, gets its delivery and the mark.
HandleDeadLetter(d) ==
  /\ Watches("dl") /\ Known
  /\ d <= dl
  /\ Unmarked(d)
  /\ markDL' = [markDL EXCEPT ![MarkKy(watch)] = @ \cup {d}]
  /\ markJob' = [markJob EXCEPT ![MarkKy(watch)] = @ \cup {JobOf(d)}]
  /\ madeDL' = [madeDL EXCEPT ![d] = Min(@ + 1, 2)]
  /\ UNCHANGED <<ruleOn, known, watch, changes, dl, processed, lastOutcome, missRec, markMI, madeMI, missedI,
                 dlOff, miOff, dlNew, miNew>>

\* @req REQ-403  An occurrence is missed: a delivery for the rule with the recurring job as subject.
\* @req INV-412  Found in the store (recurring REQ-242's record) and marked handled in the same write.
HandleMissed(i) ==
  /\ Watches("miss") /\ Known
  /\ Findable(i)
  /\ i \notin markMI[MarkKy(watch)]
  /\ markMI' = [markMI EXCEPT ![MarkKy(watch)] = @ \cup {i}]
  /\ madeMI' = [madeMI EXCEPT ![i] = Min(@ + 1, 2)]
  /\ UNCHANGED <<ruleOn, known, watch, changes, dl, processed, lastOutcome, missRec, markDL, markJob, madeDL,
                 missedI, dlOff, miOff, dlNew, miNew>>

Next ==
  \/ DeadLetter \/ TriggerMissed \/ ScheduleChangeMissed \/ TriggerRuns
  \/ AddRule \/ RemoveRule \/ EditRule \/ FirstSeen
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
\* For the edit-back check only: the edit is rolled back (or the rolling deploy flaps back) for sure.
SpecEditBack == Spec /\ WF_vars(EditRule)

\* @req INV-412  "neither alerts an event again".
Inv_OneDeliveryPerEvent == /\ \A d \in DL : madeDL[d] <= 1
                           /\ \A i \in Instants : madeMI[i] <= 1

\* @req REQ-400 INV-412 INV-413  Every dead-letter after the rule's start point (INV-413) is alerted.
Liv_DeadLetterAlerted == \A d \in DL : (d <= dl /\ d \notin dlNew) ~> (madeDL[d] >= 1)

\* @req REQ-403 INV-412 INV-413  Every missed instant after the rule's start point is alerted, whether a
\*                               trigger or a schedule change moved nextRunAt past it (recurring REQ-242).
Liv_MissedAlerted == \A i \in Instants : (i \in missedI /\ i \notin miNew) ~> (madeMI[i] >= 1)

\* REQ-400 / REQ-403 "where a rule watches …, when …": no delivery for an event that happened while the
\* rule did not watch it. A check of one reading, not a requirement (run 3 F-18, run 4 F-22, *Accepted*).
Chk_NoAlertForEventBeforeRule == /\ \A d \in DL : madeDL[d] >= 1 => d \notin dlOff
                                 /\ \A i \in Instants : madeMI[i] >= 1 => i \notin miOff

\* INV-412 notes, "events that happen … while no alerts node runs at all are alerted when a holder next
\* runs": every event that happens while the rule is configured is alerted, including those before the
\* holder first evaluates it. A check of one reading, not a requirement (run 4 F-21, accepted).
Chk_ConfiguredEventAlerted ==
  /\ \A d \in DL : (d <= dl /\ d \notin dlOff) ~> (madeDL[d] >= 1)
  /\ \A i \in Instants : (i \in missedI /\ i \notin miOff) ~> (madeMI[i] >= 1)

\* INV-413 notes, "continues where it stopped and skips nothing", applied to a rule whose settings are
\* edited and then put back: a dead-letter that happened while the rule watched dead-letters and after
\* its record existed is alerted once the rule watches dead-letters again for good (no change left).
\* A check of one reading (run 5).
Chk_WatchedDeadLetterAlertedOnReturn ==
  \A d \in DL : (d <= dl /\ d \notin dlOff /\ d \notin dlNew /\ Watches("dl") /\ changes = MaxChanges)
                  ~> (madeDL[d] >= 1)
=============================================================================
