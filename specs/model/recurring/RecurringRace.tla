---------------------------- MODULE RecurringRace ----------------------------
\* Run 6 (F-1): the pause write (REQ-214, REQ-242) split into the read that decides the record and the write
\* that lands it, to ask whether a trigger (REQ-216) landing in between makes the pause record an instant the
\* trigger already handled. Modeling aid, not a requirement: REQ-242 does not say whether that write is
\* conditional on what it read. CondPause = TRUE checks F-1 option 1 (the write is a compare-and-set on
\* nextRunAt, like REQ-216's, judged by the database clock at the write, and changes nothing if nextRunAt
\* moved since the read; the operator's call reads again). Prop_RecordSaysOutcome names the atomic Pause
\* action, so it is not checked here; every other REQ-242 property of Recurring is. The atomic Pause of Recurring stays in Next, so every Recurring behaviour is still here.
EXTENDS Recurring
CONSTANT CondPause
ASSUME CondPause \in BOOLEAN
VARIABLES pend,   \* per name: "none", or what an in-flight pause read: "missed" or "nothing"
          moved   \* per name: nextRunAt moved since that read
varsR == <<vars, pend, moved>>

InitR == Init /\ pend = [r \in Names |-> "none"] /\ moved = [r \in Names |-> FALSE]

\* @req REQ-214, REQ-242  the operator's pause call reads the job: active, with or without missed instants.
PauseRead(r) ==
  /\ rj[r].st = "Active" /\ pend[r] = "none"
  /\ pend' = [pend EXCEPT ![r] = IF HasMissed(r) THEN "missed" ELSE "nothing"]
  /\ moved' = [moved EXCEPT ![r] = FALSE]
  /\ UNCHANGED vars

\* @req REQ-214, REQ-237, REQ-242  ... and writes: paused, waiting occurrences skipped, and the record its read
\*              decided. With CondPause, a write whose nextRunAt moved since the read changes nothing.
PauseWrite(r) ==
  /\ pend[r] # "none" /\ rj[r].st = "Active"
  /\ pend' = [pend EXCEPT ![r] = "none"]
  /\ IF CondPause /\ moved[r]
       THEN UNCHANGED <<vars, moved>>
       ELSE /\ rj' = [rj EXCEPT ![r].st = "Paused"]
            /\ SkipWaiting(r, "Paused")
            \* unconditional: the record is what the read decided; CondPause: the compare-and-set held, so
            \* nextRunAt is the one read, and "missed" is judged by the database clock at the write (as REQ-216)
            /\ missRec' = IF CondPause THEN LeaveRec(r, "Pause")
                          ELSE IF pend[r] = "missed" THEN Recorded(r, "Pause", NULL) ELSE missRec
            /\ UNCHANGED <<node, job, order, maint, ov, mf, op, moved>>

\* Every step of Recurring; a step that moves an active job's nextRunAt (behind goes down: a trigger or a schedule
\* change) while a pause read is in flight marks it moved.
NextR ==
  \/ /\ Next /\ UNCHANGED pend
     /\ moved' = [r \in Names |-> moved[r] \/ (pend[r] # "none" /\ rj'[r].behind < rj[r].behind)]
  \/ \E r \in Names : PauseRead(r) \/ PauseWrite(r)

SpecR == InitR /\ [][NextR]_varsR

\* @req REQ-242, REQ-234  a record is written only for instants that have passed and that no trigger has handled
\*              (in Recurring this holds by construction: every record step needs behind >= 1).
Prop_RecordOnlyUnhandledInstants ==
  [][\A r \in Names : missRec'[r] # missRec[r] => rj[r].behind >= 1]_varsR
\* @req INV-201  unchanged by the split (the trigger's guard is still atomic, A-2).
Inv_NoScheduleWhilePausedR == Inv_NoScheduleWhilePaused
=============================================================================
