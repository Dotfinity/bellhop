---------------------- MODULE IntegrationsAlertEvents ----------------------
\* Generated from integrations.json (specHash 7b719d5882c5) — FEAT-400 Notifications, INV-412, INV-413.
\* Edit the requirements, not this file. Every action/property carries an @req comment.
\* INV-412 makes the alerts node find once-only events "from what the job store records" and mark each one
\* in the store write that creates its delivery. INV-413 says where a rule starts: the first time the
\* lease holder evaluates a rule whose name and event settings (trigger, threshold, tolerance; run 5) the
\* store has no record of, every stored event is marked without a delivery.
\* Run 7 (handoff: INV-412 and INV-413 modified, run-6 F-24 option 1 applied): two marks. INV-412 delivers
\* each event that is neither "delivered" for the rule's name nor "before the start" of its name and event
\* settings, and marks it delivered for the name, in a write that succeeds only if it is not yet delivered
\* for that name. INV-413's first evaluation marks the stored events "before the start" of that name and
\* those settings. The two marks are kept apart (start*, del*). Run 7 also adds a rename (a new name,
\* REQ-410) and a trigger edit that widens what the rule watches, and counts deliveries per rule name.
\* This module asks what the store records for each event, what one event is, and how a rule's
\* life (added, removed, re-added, edited, edited back, renamed) moves its start point.
\* The lease is not modeled here: one alerts node holds it throughout and is always able to act
\* (INV-411, REQ-438, handovers and stale writes are in IntegrationsAlerts.tla). Retention (jobs REQ-145)
\* is not modeled; INV-412's notes accept that a removed job is no longer alerted.
\*
\* Readings and counterfactuals, one constant each (the findings name them):
\*   MissRecord : what the store holds about a missed due instant of a recurring job.
\*     "durable"     : @req recurring REQ-242  one record each time nextRunAt moves past missed instants,
\*                     by a trigger (REQ-216) or a schedule change (REQ-227), and (run 6) each time an
\*                     active job with missed instants is paused, orphaned or removed; kept for
\*                     RetentionDeadLettered.
\*     "lastOutcome" : counterfactual "REQ-242 dropped": recurring REQ-231's last outcome only, which
\*                     the next outcome overwrites and a schedule change never writes (run 3's F-17).
\*   RuleStart  : where a rule the store has no record of starts.
\*     "firstSeen"    : @req INV-413  every event the store already records is marked before the start.
\*     "freshCatchUp" : run-4 F-21 option (not chosen): as "firstSeen", except on a store that records no
\*                      rule at all (OtherRuleKnown = FALSE), where nothing is marked.
\*     "storeStart"   : counterfactual "INV-413 dropped": nothing is marked (run 3's F-18 flood).
\*     "sinceNameEval": run 7 F-25 option 2 (not a requirement): as "firstSeen", except that a name the lease
\*                      holder has evaluated before keeps its place: only the events the store recorded at
\*                      the name's last evaluation (Evaluate) are marked, so events between the previous
\*                      version's last evaluation and this version's first are due to this version.
\*   RuleKey    : what INV-413's store record knows a rule by.
\*     "nameAndSettings" : @req INV-413  the rule's name and event settings: here the name (nm), the
\*                         trigger (watch) and a threshold/tolerance version bit (ver).
\*     "nameOnly"        : counterfactual: run 4's wording, the name only (run 4's F-22).
\*                         Records are kept, never replaced (INV-413 notes: "kept ... continues where it
\*                         stopped"), so a rule edited back to earlier settings finds their record again.
\*   MarkScope  : what the "delivered" (INV-412) and "before the start" (INV-413) marks are attached to.
\*     "split"       : @req INV-412 INV-413  (run 7) "delivered" per rule name, "before the start" per name
\*                     and event settings; an event is due for a version if neither mark holds.
\*     "perSettings" : counterfactual: run 6's wording, both marks per name and event settings (run 6's F-24).
\*     "perName"     : counterfactual: run 5's other reading, both marks per rule name (run 5's F-23).
\*   EditKind   : what a developer's edit of the rule changes.
\*     "trigger"  : what it watches (dead-letters <-> missed occurrences), keeping its name.
\*     "widen"    : (run 7) what it watches, keeping its name, so that the two versions watch overlapping
\*                  events (dead-letters <-> dead-letters and missed occurrences).
\*     "settings" : (run 6) a threshold or tolerance, keeping its name: the same events stay watched, but
\*                  INV-413 sees a rule with new event settings (a version bit in the record key).
\*     "rename"   : (run 7) its name only (REQ-410: rules are identified by name; INV-413 notes: a renamed
\*                  rule is a new rule): a name bit in the record key and in the "delivered" key.
\*   MarkKey    : what an INV-412/INV-413 mark is attached to.
\*     "perChange"   : @req INV-412  the recorded state change (one entry of the job's history, jobs INV-116).
\*     "perJob"      : counterfactual: the job (run 3's F-19 reading).
EXTENDS Naturals, FiniteSets

CONSTANTS SameJob,           \* TRUE: dead-letter 2 is the same job as dead-letter 1, requeued in between (jobs REQ-141)
          RuleAtStart,       \* TRUE: the rule is configured from the start; FALSE: it is added later (REQ-410)
          OtherRuleKnown,    \* TRUE: the store already records some other rule (not a new system)
          InitialWatch,      \* which once-only events the rule watches: subset of {"dl", "miss"} (A-19)
          AllowRemove,       \* the rule may be removed from configuration and added back
          AllowEdit,         \* the rule may be edited (EditKind)
          EditKind,
          AllowPause,        \* (run 6) an operator may pause and resume the recurring job (REQ-214, REQ-215)
          RecordedAtStart,   \* (run 6) the store already records the rule as first configured (it has been running)
          MaxChanges,        \* configuration changes in one behaviour
          RuleStart, RuleKey, MarkScope, MarkKey, MissRecord

ASSUME SameJob \in BOOLEAN /\ RuleAtStart \in BOOLEAN /\ OtherRuleKnown \in BOOLEAN
ASSUME InitialWatch \subseteq {"dl", "miss"} /\ AllowRemove \in BOOLEAN /\ AllowEdit \in BOOLEAN
ASSUME MaxChanges \in Nat /\ EditKind \in {"trigger", "widen", "settings", "rename"} /\ AllowPause \in BOOLEAN
ASSUME RecordedAtStart \in BOOLEAN
ASSUME RuleStart \in {"firstSeen", "freshCatchUp", "storeStart", "sinceNameEval"}
ASSUME RuleKey \in {"nameAndSettings", "nameOnly"}
ASSUME MarkScope \in {"split", "perSettings", "perName"}
ASSUME MarkKey \in {"perChange", "perJob"}
ASSUME MissRecord \in {"durable", "lastOutcome"}

DL       == 1..2        \* dead-letter transitions, in the order they happen
Instants == 1..2        \* moves of one recurring job's nextRunAt past a missed instant, in order
JobOf(d) == IF SameJob THEN 1 ELSE d
Outcome  == [k: {"none", "skipped", "succeeded"}, i: 0..2]
Keys     == SUBSET {"dl", "miss", "v2", "n2"}  \* "n2": renamed; "v2": edited threshold/tolerance
NameK(n) == IF n THEN {"n2"} ELSE {}             \* (run 7) the key of the rule's name alone

\* @req INV-413  The key of the store record for the rule as it is now configured (its name n, its trigger
\*               w and, through v, its threshold/tolerance).
RecKey(w, v, n) == NameK(n) \cup (IF RuleKey = "nameOnly" THEN {} ELSE w \cup (IF v THEN {"v2"} ELSE {}))

VARIABLES ruleOn,       \* the rule is loaded by the lease holder (REQ-410)
          known,        \* @req INV-413  the records the store keeps for the rule (set of RecKey values)
          watch,        \* which once-only events the rule watches (its trigger)
          ver,          \* (run 6) the rule's threshold/tolerance has been edited (FALSE: original)
          nm,           \* (run 7) the rule has been renamed (FALSE: original name)
          recActive,    \* (run 6) the recurring job is active (recurring REQ-214, REQ-215)
          changes,      \* configuration changes so far
          dl,           \* number of dead-letters so far; each is in the job's state history (jobs INV-116)
          processed,    \* number of moves of nextRunAt so far (recurring REQ-216, REQ-227)
          lastOutcome,  \* recurring REQ-231: the recurring job's last outcome (one field)
          missRec,      \* @req recurring REQ-242  miss records in the store
          startDL,      \* @req INV-413  "before the start" marks per key: "perChange" dead-letter entries,
          startJob,     \*   "perJob" jobs,
          startMI,      \*   miss records
          delDL,        \* @req INV-412  "delivered" marks per key: "perChange" dead-letter entries,
          delJob,       \*   "perJob" jobs,
          delMI,        \*   miss records
          madeDL, madeMI,          \* history: deliveries created, per rule name (nm), per dead-letter / miss record
          missedI,                 \* history: missed instants recorded (REQ-242) or meant to be
          pausedI,                 \* history: (run 6) instants recorded by a pause, orphaning or removal
          dlOff, miOff,            \* history: events that happened while the rule did not watch them
          dlNew, miNew,            \* history: events that happened while the store had no record of the rule
          evalDL, evalMI, evaluated \* "sinceNameEval" only: per name, what the store recorded at its last evaluation
vars == <<ruleOn, known, watch, ver, nm, recActive, changes, dl, processed, lastOutcome, missRec,
          startDL, startJob, startMI, delDL, delJob, delMI, madeDL, madeMI, missedI, pausedI,
          dlOff, miOff, dlNew, miNew, evalDL, evalMI, evaluated>>
evals == <<evalDL, evalMI, evaluated>>
marks == <<startDL, startJob, startMI, delDL, delJob, delMI, evalDL, evalMI, evaluated>>

TypeInv ==
  /\ ruleOn \in BOOLEAN /\ known \subseteq Keys
  /\ watch \subseteq {"dl", "miss"} /\ ver \in BOOLEAN /\ nm \in BOOLEAN /\ recActive \in BOOLEAN
  /\ changes \in 0..MaxChanges
  /\ dl \in 0..2 /\ processed \in 0..2
  /\ lastOutcome \in Outcome
  /\ missRec \subseteq Instants /\ missedI \subseteq Instants /\ pausedI \subseteq Instants
  /\ startDL \in [Keys -> SUBSET DL] /\ startJob \in [Keys -> SUBSET DL] /\ startMI \in [Keys -> SUBSET Instants]
  /\ delDL \in [Keys -> SUBSET DL] /\ delJob \in [Keys -> SUBSET DL] /\ delMI \in [Keys -> SUBSET Instants]
  /\ madeDL \in [BOOLEAN -> [DL -> 0..2]] /\ madeMI \in [BOOLEAN -> [Instants -> 0..2]]
  /\ dlOff \subseteq DL /\ miOff \subseteq Instants /\ dlNew \subseteq DL /\ miNew \subseteq Instants
  /\ evalDL \in [BOOLEAN -> 0..2] /\ evalMI \in [BOOLEAN -> SUBSET Instants] /\ evaluated \subseteq BOOLEAN

Min(a, b) == IF a < b THEN a ELSE b
Watches(k) == ruleOn /\ k \in watch
CurKey == RecKey(watch, ver, nm)
Known == CurKey \in known
\* Where the marks are written: "before the start" by INV-413's first evaluation, "delivered" by INV-412's
\* delivery write.
StartKy == IF MarkScope = "perName" THEN NameK(nm) ELSE CurKey
DelivKy == IF MarkScope = "perSettings" THEN CurKey ELSE NameK(nm)
\* Deliveries for one event under any rule name.
MadeDL(d) == madeDL[FALSE][d] + madeDL[TRUE][d]
MadeMI(i) == madeMI[FALSE][i] + madeMI[TRUE][i]

Init ==
  /\ ruleOn = RuleAtStart
  /\ known = IF RecordedAtStart THEN {RecKey(InitialWatch, FALSE, FALSE)} ELSE {}
  /\ watch = InitialWatch /\ ver = FALSE /\ nm = FALSE /\ recActive = TRUE
  /\ changes = 0
  /\ dl = 0 /\ processed = 0
  /\ lastOutcome = [k |-> "none", i |-> 0]
  /\ missRec = {} /\ missedI = {} /\ pausedI = {}
  /\ startDL = [k \in Keys |-> {}] /\ startJob = [k \in Keys |-> {}] /\ startMI = [k \in Keys |-> {}]
  /\ delDL = [k \in Keys |-> {}] /\ delJob = [k \in Keys |-> {}] /\ delMI = [k \in Keys |-> {}]
  /\ madeDL = [b \in BOOLEAN |-> [d \in DL |-> 0]] /\ madeMI = [b \in BOOLEAN |-> [i \in Instants |-> 0]]
  /\ dlOff = {} /\ miOff = {} /\ dlNew = {} /\ miNew = {}
  /\ evalDL = [b \in BOOLEAN |-> 0] /\ evalMI = [b \in BOOLEAN |-> {}]
  /\ evaluated = IF RecordedAtStart /\ RuleStart = "sinceNameEval" THEN {FALSE} ELSE {}

\* jobs REQ-131 (and REQ-141 in between when SameJob): a job is dead-lettered; jobs INV-116 records the
\* transition in its state history, so the store holds the event.
DeadLetter ==
  /\ dl < 2
  /\ dl' = dl + 1
  /\ dlOff' = IF Watches("dl") THEN dlOff ELSE dlOff \cup {dl + 1}
  /\ dlNew' = IF Known THEN dlNew ELSE dlNew \cup {dl + 1}
  /\ UNCHANGED <<ruleOn, known, watch, ver, nm, recActive, pausedI, changes, processed, lastOutcome, missRec,
                 marks, madeDL, madeMI, missedI, miOff, miNew>>

\* recurring REQ-216, REQ-217/REQ-218, REQ-231, REQ-242: a trigger of the active job finds a missed instant.
\* nextRunAt moves on in one compare-and-set that, with REQ-242, also writes one miss record; under Skip the
\* last outcome becomes "skipped" (under RunOnce there is not even that, see the run-3 F-17 text).
TriggerMissed ==
  /\ recActive
  /\ processed < 2
  /\ processed' = processed + 1
  /\ lastOutcome' = [k |-> "skipped", i |-> processed + 1]
  /\ missRec' = IF MissRecord = "durable" THEN missRec \cup {processed + 1} ELSE missRec
  /\ missedI' = missedI \cup {processed + 1}
  /\ miOff' = IF Watches("miss") THEN miOff ELSE miOff \cup {processed + 1}
  /\ miNew' = IF Known THEN miNew ELSE miNew \cup {processed + 1}
  /\ UNCHANGED <<ruleOn, known, watch, ver, nm, recActive, pausedI, changes, dl, marks, madeDL,
                 madeMI, dlOff, dlNew>>

\* @req recurring REQ-227 REQ-242  (run 5) The active recurring job's schedule changes while an instant is
\* overdue: nextRunAt is computed from now and moves past it with no catch-up and no occurrence, so REQ-231
\* records no outcome; REQ-242 records the instant as dropped by the schedule change in the same write.
\* Run 6: under recurring REQ-234 the instant is missed however recently it fell due (no clock here).
ScheduleChangeMissed ==
  /\ recActive
  /\ processed < 2
  /\ processed' = processed + 1
  /\ missRec' = IF MissRecord = "durable" THEN missRec \cup {processed + 1} ELSE missRec
  /\ missedI' = missedI \cup {processed + 1}
  /\ miOff' = IF Watches("miss") THEN miOff ELSE miOff \cup {processed + 1}
  /\ miNew' = IF Known THEN miNew ELSE miNew \cup {processed + 1}
  /\ UNCHANGED <<ruleOn, known, watch, ver, nm, recActive, pausedI, changes, dl, lastOutcome, marks,
                 madeDL, madeMI, dlOff, dlNew>>

\* @req recurring REQ-214 REQ-205 REQ-207 REQ-213 REQ-242  (run 6) An operator pauses the active recurring
\* job (or the orphan sweep orphans it, or it is removed) while an instant is overdue and not triggered.
\* The pause does not move nextRunAt and creates no occurrence, so REQ-231 records no outcome; REQ-242
\* records the instant as dropped by the pause in the pause write. A removal is a pause never resumed.
PauseMissed ==
  /\ AllowPause
  /\ recActive
  /\ processed < 2
  /\ recActive' = FALSE
  /\ processed' = processed + 1
  /\ missRec' = IF MissRecord = "durable" THEN missRec \cup {processed + 1} ELSE missRec
  /\ missedI' = missedI \cup {processed + 1}
  /\ pausedI' = pausedI \cup {processed + 1}
  /\ miOff' = IF Watches("miss") THEN miOff ELSE miOff \cup {processed + 1}
  /\ miNew' = IF Known THEN miNew ELSE miNew \cup {processed + 1}
  /\ UNCHANGED <<ruleOn, known, watch, ver, nm, changes, dl, lastOutcome, marks, madeDL, madeMI,
                 dlOff, dlNew>>

\* recurring REQ-215 (REQ-206 for an orphan): resumed, nextRunAt from now; instants that fell due while
\* paused are dropped on purpose and are not missed (REQ-234), so nothing is recorded.
Resume ==
  /\ AllowPause
  /\ ~recActive
  /\ recActive' = TRUE
  /\ UNCHANGED <<ruleOn, known, watch, ver, nm, pausedI, changes, dl, processed, lastOutcome, missRec, marks,
                 madeDL, madeMI, missedI, dlOff, miOff, dlNew, miNew>>

\* recurring REQ-216, INV-207, REQ-231: the trigger is on time; its occurrence runs and succeeds, and the
\* last outcome becomes "succeeded" (creation and finish are one step here).
TriggerRuns ==
  /\ recActive
  /\ processed < 2
  /\ processed' = processed + 1
  /\ lastOutcome' = [k |-> "succeeded", i |-> processed + 1]
  /\ UNCHANGED <<ruleOn, known, watch, ver, nm, recActive, pausedI, changes, dl, missRec, marks,
                 madeDL, madeMI, missedI, dlOff, miOff, dlNew, miNew>>

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
  /\ UNCHANGED <<known, watch, ver, nm, recActive, pausedI, dl, processed, lastOutcome, missRec, marks,
                 madeDL, madeMI, missedI, dlOff, miOff, dlNew, miNew>>

\* REQ-410: the rule is removed (or a node without it holds the lease during a rolling deploy). INV-413
\* notes: its records and marks are kept while no node loads it.
RemoveRule ==
  /\ AllowRemove
  /\ ruleOn
  /\ changes < MaxChanges
  /\ ruleOn' = FALSE
  /\ changes' = changes + 1
  /\ UNCHANGED <<known, watch, ver, nm, recActive, pausedI, dl, processed, lastOutcome, missRec, marks,
                 madeDL, madeMI, missedI, dlOff, miOff, dlNew, miNew>>

\* REQ-410: a developer edits the rule. "trigger": dead-letters <-> missed occurrences. "widen" (run 7):
\* dead-letters <-> dead-letters and missed occurrences. "settings" (run 6): its threshold or tolerance; it
\* watches the same events. "rename" (run 7): its name. A second edit puts the old version back (a
\* rollback, or a rolling deploy that moves the lease from a node with the new version back to one with
\* the old). With RuleKey = "nameAndSettings" the edited rule is a record the store may not have yet
\* (INV-413).
EditRule ==
  /\ AllowEdit
  /\ ruleOn
  /\ changes < MaxChanges
  /\ CASE EditKind = "trigger"  -> /\ watch \in {{"dl"}, {"miss"}}
                                   /\ watch' = IF watch = {"dl"} THEN {"miss"} ELSE {"dl"}
                                   /\ UNCHANGED <<ver, nm>>
       [] EditKind = "widen"    -> /\ watch \in {{"dl"}, {"dl", "miss"}}
                                   /\ watch' = IF watch = {"dl"} THEN {"dl", "miss"} ELSE {"dl"}
                                   /\ UNCHANGED <<ver, nm>>
       [] EditKind = "settings" -> /\ ver' = ~ver
                                   /\ UNCHANGED <<watch, nm>>
       [] EditKind = "rename"   -> /\ nm' = ~nm
                                   /\ UNCHANGED <<watch, ver>>
  /\ changes' = changes + 1
  /\ UNCHANGED <<ruleOn, known, recActive, pausedI, dl, processed, lastOutcome, missRec, marks,
                 madeDL, madeMI, missedI, dlOff, miOff, dlNew, miNew>>

\* @req INV-413  The lease holder evaluates a rule whose name and event settings the store has no record
\*               of: record them and mark every event the store records as before the start of that
\*               name and those event settings, without creating deliveries. (One step here; the write's
\*               lease check and condition across a handover are in IntegrationsAlerts.tla.)
FirstSeen ==
  /\ ruleOn
  /\ ~Known
  /\ known' = known \cup {CurKey}
  /\ IF RuleStart = "sinceNameEval" /\ nm \in evaluated
       THEN /\ startDL' = [startDL EXCEPT ![StartKy] = @ \cup 1..evalDL[nm]]
            /\ startJob' = [startJob EXCEPT ![StartKy] = @ \cup {JobOf(d) : d \in 1..evalDL[nm]}]
            /\ startMI' = [startMI EXCEPT ![StartKy] = @ \cup evalMI[nm]]
       ELSE IF RuleStart \in {"firstSeen", "sinceNameEval"} \/ (RuleStart = "freshCatchUp" /\ OtherRuleKnown)
       THEN /\ startDL' = [startDL EXCEPT ![StartKy] = @ \cup 1..dl]
            /\ startJob' = [startJob EXCEPT ![StartKy] = @ \cup {JobOf(d) : d \in 1..dl}]
            /\ startMI' = [startMI EXCEPT ![StartKy] = @ \cup {i \in Instants : Findable(i)}]
       ELSE UNCHANGED <<startDL, startJob, startMI>>
  /\ UNCHANGED <<ruleOn, watch, ver, nm, recActive, pausedI, changes, dl, processed, lastOutcome, missRec,
                 delDL, delJob, delMI, madeDL, madeMI, missedI, dlOff, miOff, dlNew, miNew, evals>>

\* @req INV-412  Due for the rule as it is now configured: neither delivered for its name nor before the
\*               start of its name and event settings. (Under the counterfactuals both marks share a key.)
DueDL(d) == IF MarkKey = "perChange" THEN d \notin startDL[StartKy] \cup delDL[DelivKy]
            ELSE JobOf(d) \notin startJob[StartKy] \cup delJob[DelivKy]
\* @req INV-412  The write's condition: not yet marked delivered for that name. (Under "perSettings", run 6's
\*               "not yet marked handled for them", which includes the start marks of the same key.)
WriteOK_DL(d) == IF MarkKey = "perChange"
                   THEN d \notin delDL[DelivKy] /\ (MarkScope # "split" => d \notin startDL[StartKy])
                   ELSE JobOf(d) \notin delJob[DelivKy] /\ (MarkScope # "split" => JobOf(d) \notin startJob[StartKy])

\* @req REQ-400  A job is dead-lettered: a delivery for the rule with the job as subject.
\* @req INV-412  The event is found in the store and, being due, gets its delivery and the "delivered" mark
\*               in one write that succeeds only if it is not yet delivered for the rule's name. Find and
\*               write are one step here (the two-step write is in IntegrationsAlerts.tla).
HandleDeadLetter(d) ==
  /\ Watches("dl") /\ Known
  /\ d <= dl
  /\ DueDL(d)
  /\ WriteOK_DL(d)
  /\ delDL' = [delDL EXCEPT ![DelivKy] = @ \cup {d}]
  /\ delJob' = [delJob EXCEPT ![DelivKy] = @ \cup {JobOf(d)}]
  /\ madeDL' = [madeDL EXCEPT ![nm][d] = Min(@ + 1, 2)]
  /\ UNCHANGED <<ruleOn, known, watch, ver, nm, recActive, pausedI, changes, dl, processed, lastOutcome, missRec,
                 startDL, startJob, startMI, delMI, madeMI, missedI, dlOff, miOff, dlNew, miNew, evals>>

\* @req REQ-403  An occurrence is missed: a delivery for the rule with the recurring job as subject.
\* @req INV-412  Found in the store (recurring REQ-242's record), due, delivered and marked in one write.
HandleMissed(i) ==
  /\ Watches("miss") /\ Known
  /\ Findable(i)
  /\ i \notin startMI[StartKy] \cup delMI[DelivKy]    \* due
  /\ i \notin delMI[DelivKy]                          \* the write's condition (implied by "due" in one step)
  /\ delMI' = [delMI EXCEPT ![DelivKy] = @ \cup {i}]
  /\ madeMI' = [madeMI EXCEPT ![nm][i] = Min(@ + 1, 2)]
  /\ UNCHANGED <<ruleOn, known, watch, ver, nm, recActive, pausedI, changes, dl, processed, lastOutcome, missRec,
                 startDL, startJob, startMI, delDL, delJob, madeDL, missedI, dlOff, miOff, dlNew, miNew, evals>>

\* "sinceNameEval" only (F-25 option 2): the lease holder finishes an evaluation of the rule, with nothing
\* left due for it, and the store keeps for the rule's name what it recorded at that point.
Evaluate ==
  /\ RuleStart = "sinceNameEval"
  /\ ruleOn /\ Known
  /\ ~(\E d \in DL : ENABLED HandleDeadLetter(d))
  /\ ~(\E i \in Instants : ENABLED HandleMissed(i))
  /\ <<evalDL[nm], evalMI[nm], nm \in evaluated>> # <<dl, {i \in Instants : Findable(i)}, TRUE>>
  /\ evalDL' = [evalDL EXCEPT ![nm] = dl]
  /\ evalMI' = [evalMI EXCEPT ![nm] = {i \in Instants : Findable(i)}]
  /\ evaluated' = evaluated \cup {nm}
  /\ UNCHANGED <<ruleOn, known, watch, ver, nm, recActive, changes, dl, processed, lastOutcome, missRec,
                 startDL, startJob, startMI, delDL, delJob, delMI, madeDL, madeMI, missedI, pausedI,
                 dlOff, miOff, dlNew, miNew>>

Next ==
  \/ DeadLetter \/ TriggerMissed \/ ScheduleChangeMissed \/ PauseMissed \/ Resume \/ TriggerRuns
  \/ AddRule \/ RemoveRule \/ EditRule \/ FirstSeen \/ Evaluate
  \/ \E d \in DL : HandleDeadLetter(d)
  \/ \E i \in Instants : HandleMissed(i)

\* Rule evaluation is a system duty of the lease holder (INV-411): fair. Events, pauses and configuration
\* changes are not.
Fairness == /\ WF_vars(FirstSeen) /\ WF_vars(Evaluate)
            /\ \A d \in DL : WF_vars(HandleDeadLetter(d))
            /\ \A i \in Instants : WF_vars(HandleMissed(i))
Spec == Init /\ [][Next]_vars /\ Fairness
\* For the remove-and-re-add check only: the removed rule does come back (a rolling deploy finishes).
SpecReadd == Spec /\ WF_vars(AddRule)
\* For the edit-back checks only: the edit is rolled back (or the rolling deploy flaps back) for sure.
SpecEditBack == Spec /\ WF_vars(EditRule)

\* @req INV-412  "neither ... alerts an event again": one event never yields two deliveries for the same
\*               rule name, under whichever of its versions (run 7: the "delivered" mark is per name).
Inv_OneDeliveryPerEvent == \A b \in BOOLEAN : /\ \A d \in DL : madeDL[b][d] <= 1
                                              /\ \A i \in Instants : madeMI[b][i] <= 1

\* (run 7) One event never yields two deliveries under any rule name: a renamed rule and its old name
\* together. A check of one reading, not a requirement (F-26).
Chk_OneDeliveryPerEventAnyName == /\ \A d \in DL : MadeDL(d) <= 1
                                  /\ \A i \in Instants : MadeMI(i) <= 1

\* @req REQ-400 INV-412 INV-413  Every dead-letter is alerted, except one that happened while the store had
\*                               no record of the rule as then configured (its start point, INV-413).
Liv_DeadLetterAlerted == \A d \in DL : (d <= dl /\ d \notin dlNew) ~> (MadeDL(d) >= 1)

\* @req REQ-403 INV-412 INV-413  Every missed instant is alerted, with the same exception, whether a
\*                               trigger, a schedule change or (run 6) a pause, orphaning or removal
\*                               dropped it (recurring REQ-242).
Liv_MissedAlerted == \A i \in Instants : (i \in missedI /\ i \notin miNew) ~> (MadeMI(i) >= 1)

\* (run 6) Vacuity trap, expected to be VIOLATED: an instant recorded by a pause is alerted.
Trap_PausedMissAlerted == ~(\E i \in pausedI : MadeMI(i) >= 1)

\* REQ-400 / REQ-403 "where a rule watches …, when …": no delivery for an event that happened while the
\* rule did not watch it. A check of one reading, not a requirement (run 3 F-18, run 4 F-22, *Accepted*).
Chk_NoAlertForEventBeforeRule == /\ \A d \in DL : MadeDL(d) >= 1 => d \notin dlOff
                                 /\ \A i \in Instants : MadeMI(i) >= 1 => i \notin miOff

\* INV-412 notes, "events that happen … while no alerts node runs at all are alerted when a holder next
\* runs": every event that happens while the rule is configured is alerted, including those before the
\* holder first evaluates it. A check of one reading, not a requirement (run 4 F-21, accepted).
Chk_ConfiguredEventAlerted ==
  /\ \A d \in DL : (d <= dl /\ d \notin dlOff) ~> (MadeDL(d) >= 1)
  /\ \A i \in Instants : (i \in missedI /\ i \notin miOff) ~> (MadeMI(i) >= 1)

\* INV-413 notes, "continues where it stopped and skips nothing", applied to a rule whose settings are
\* edited and then put back: a dead-letter that happened while the rule watched dead-letters and after
\* its record existed is alerted once the rule watches dead-letters again for good (no change left).
\* A check of one reading (run 5).
Chk_WatchedDeadLetterAlertedOnReturn ==
  \A d \in DL : (d <= dl /\ d \notin dlOff /\ d \notin dlNew /\ Watches("dl") /\ changes = MaxChanges)
                  ~> (MadeDL(d) >= 1)

\* (run 7) The same for missed instants, for the widened trigger.
Chk_WatchedMissAlertedOnReturn ==
  \A i \in Instants : (i \in missedI /\ i \notin miOff /\ i \notin miNew /\ Watches("miss")
                       /\ changes = MaxChanges) ~> (MadeMI(i) >= 1)
=============================================================================
