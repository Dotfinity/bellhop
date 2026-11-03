---- MODULE F3V_NoRequeueNoRouting ----
\* PURPOSE: one recurring definition fired by two nodes, its overlap policy deciding what each fire, manual trigger and catch-up creates while earlier occurrences are still active.
\* ASSUMPTION: the overlap policy is fixed for the whole run; Init picks it, so one run covers all four.
\* ASSUMPTION: at most MaxOccs occurrences ever exist and at most NumInstants due instants come round; a fire that would exceed the cap is not taken.
\* ASSUMPTION: a fire for a definition paused after it was returned as due leaves the next run time where it was (REQ-017 does not say).
\* ASSUMPTION: resuming and orphaning are not modelled (F4); once paused the definition stays paused.
\* ASSUMPTION: CancelPrevious cancels every active occurrence, and when none is active it creates the new one as Enqueued.
\* ASSUMPTION: a catch-up fire creates exactly two occurrences (RunAll with a limit of two); the catch-up mode itself (REQ-042) is not modelled.
\* ASSUMPTION: a Skip fire's "Skipped" record is not modelled; no rule reads it.
\* ASSUMPTION: "a job that hasn't started" (REQ-009) is every status that is neither Processing nor final, including Failed and Unroutable.
\* ASSUMPTION: lease recovery checks the cancel request first, then the attempt count (REQ-008 gives no order).
\* ASSUMPTION: a lease may expire at any moment; D-1 means the old handler has stopped before recovery, so recovery never leaves two runs of one occurrence.
\* ASSUMPTION: every node can handle the occurrence's name except at the moment cleanup marks it Unroutable; which node claims is not modelled.
\* ASSUMPTION: requeue resets the attempt count only; the cancel request stays (REQ-010 does not clear it).
\* ASSUMPTION: a deleted occurrence counts as no longer Awaiting for the stranding rule.
\* ASSUMPTION: with a run active, a catch-up fire creates both its occurrences as Awaiting under Queue and CancelPrevious, both Enqueued under Allow, and nothing under Skip; REQ-025 now covers only a fire with nothing active.
\* ASSUMPTION: the warning of REQ-010 is a flag on the requeued run, set when another run was active at the requeue; it stays with that run and its retries until the run is requeued again.
EXTENDS Naturals, FiniteSets, Sequences, Common

CONSTANTS MaxOccs, NumInstants, MaxAttempts

Occs == 1..MaxOccs
Instants == 1..NumInstants
Policies == {"Skip", "Queue", "Allow", "CancelPrevious"}
Statuses == JobStates \cup {"None", "Deleted"}

VARIABLES policy, paused, nextRun, dueRead, status, attempt, cancelReq, winners, reporters, warned
vars == <<policy, paused, nextRun, dueRead, status, attempt, cancelReq, winners, reporters, warned>>

TypeOK ==
    /\ policy \in Policies
    /\ paused \in BOOLEAN
    /\ nextRun \in 1..(NumInstants + 1)
    /\ dueRead \in [Nodes -> 0..NumInstants]
    /\ status \in [Occs -> Statuses]
    /\ attempt \in [Occs -> 0..MaxAttempts]
    /\ cancelReq \in [Occs -> BOOLEAN]
    /\ winners \in [Instants -> SUBSET Nodes]
    /\ reporters \in [Instants -> SUBSET Nodes]
    /\ warned \in [Occs -> BOOLEAN]

Init ==
    /\ policy \in Policies
    /\ paused = FALSE
    /\ nextRun = 1
    /\ dueRead = [n \in Nodes |-> 0]
    /\ status = [o \in Occs |-> "None"]
    /\ attempt = [o \in Occs |-> 0]
    /\ cancelReq = [o \in Occs |-> FALSE]
    /\ winners = [i \in Instants |-> {}]
    /\ reporters = [i \in Instants |-> {}]
    /\ warned = [o \in Occs |-> FALSE]

Created == Cardinality({o \in Occs : status[o] # "None"})
\* REQ-019
AnyActive == \E o \in Occs : status[o] \in ActiveStates
\* REQ-019
OtherActive(o) == \E p \in Occs \ {o} : status[p] \in ActiveStates

\* REQ-020, REQ-021, REQ-023, REQ-024, REQ-025: k occurrences created by one fire. With a run active every one follows the policy (none under Skip); with none active REQ-025's sequence applies.
Fire(k) ==
    LET busy == AnyActive
        firstStatus == IF busy /\ policy # "Allow" THEN "Awaiting" ELSE "Enqueued"
        restStatus == IF policy = "Allow" THEN "Enqueued" ELSE "Awaiting"
        new == IF policy = "Skip" /\ busy THEN << >>
               ELSE << firstStatus >> \o [i \in 1..(k - 1) |-> restStatus]
        cancelling == policy = "CancelPrevious" /\ busy
        base == [o \in Occs |->
                    IF cancelling /\ status[o] \in ActiveStates \ {"Processing"}
                    THEN "Cancelled" ELSE status[o]]
    IN /\ Created + Len(new) <= MaxOccs
       /\ status' = [o \in Occs |->
                        IF o > Created /\ o <= Created + Len(new)
                        THEN new[o - Created] ELSE base[o]]
       /\ cancelReq' = IF cancelling
                       THEN [o \in Occs |-> cancelReq[o] \/ status[o] = "Processing"]
                       ELSE cancelReq

\* REQ-017
ReadDue(n) ==
    /\ ~paused
    /\ nextRun <= NumInstants
    /\ dueRead[n] = 0
    /\ dueRead' = [dueRead EXCEPT ![n] = nextRun]
    /\ UNCHANGED <<policy, paused, nextRun, status, attempt, cancelReq, winners, reporters, warned>>

\* REQ-018, REQ-020, REQ-021, REQ-023, REQ-024: compare-and-set on the next run time.
FireDue(n) ==
    /\ dueRead[n] = nextRun
    /\ ~paused
    /\ Fire(1)
    /\ nextRun' = nextRun + 1
    /\ winners' = [winners EXCEPT ![nextRun] = @ \cup {n}]
    /\ dueRead' = [dueRead EXCEPT ![n] = 0]
    /\ UNCHANGED <<policy, paused, attempt, reporters, warned>>

\* REQ-018, REQ-025, REQ-043, REQ-020, REQ-021, REQ-024: catch-up after downtime, two occurrences at once; with a run active it follows the policy like any fire.
CatchUpFire(n) ==
    /\ dueRead[n] = nextRun
    /\ ~paused
    /\ Fire(2)
    /\ nextRun' = nextRun + 1
    /\ winners' = [winners EXCEPT ![nextRun] = @ \cup {n}]
    /\ reporters' = [reporters EXCEPT ![nextRun] = @ \cup {n}]
    /\ dueRead' = [dueRead EXCEPT ![n] = 0]
    /\ UNCHANGED <<policy, paused, attempt, warned>>

\* REQ-017
FirePausedAfterDue(n) ==
    /\ dueRead[n] = nextRun
    /\ paused
    /\ dueRead' = [dueRead EXCEPT ![n] = 0]
    /\ UNCHANGED <<policy, paused, nextRun, status, attempt, cancelReq, winners, reporters, warned>>

\* REQ-018, REQ-043: the compare-and-set fails because another node already fired the instant.
FireLost(n) ==
    /\ dueRead[n] # 0
    /\ dueRead[n] # nextRun
    /\ dueRead' = [dueRead EXCEPT ![n] = 0]
    /\ UNCHANGED <<policy, paused, nextRun, status, attempt, cancelReq, winners, reporters, warned>>

\* REQ-017, REQ-032
Pause ==
    /\ ~paused
    /\ paused' = TRUE
    /\ UNCHANGED <<policy, nextRun, dueRead, status, attempt, cancelReq, winners, reporters, warned>>

\* REQ-026: works on a paused definition too, since pausing stops only the schedule (D-11).
ManualTrigger ==
    /\ Fire(1)
    /\ UNCHANGED <<policy, paused, nextRun, dueRead, attempt, winners, reporters, warned>>

\* REQ-021, REQ-022, REQ-027: the oldest Awaiting occurrence, once no occurrence other than Awaiting ones is active.
PromoteAwaiting(o) ==
    /\ status[o] = "Awaiting"
    /\ \A p \in Occs : p < o => status[p] # "Awaiting"
    /\ \A p \in Occs \ {o} : status[p] \notin ActiveStates \ {"Awaiting"}
    /\ status' = [status EXCEPT ![o] = "Enqueued"]
    /\ UNCHANGED <<policy, paused, nextRun, dueRead, attempt, cancelReq, winners, reporters, warned>>

\* REQ-001, REQ-035 (from F1/F5)
Claim(o) ==
    /\ status[o] = "Enqueued"
    /\ status' = [status EXCEPT ![o] = "Processing"]
    /\ attempt' = [attempt EXCEPT ![o] = @ + 1]
    /\ UNCHANGED <<policy, paused, nextRun, dueRead, cancelReq, winners, reporters, warned>>

\* REQ-005 (from F1)
CompleteSucceeded(o) ==
    /\ status[o] = "Processing"
    /\ status' = [status EXCEPT ![o] = "Succeeded"]
    /\ UNCHANGED <<policy, paused, nextRun, dueRead, attempt, cancelReq, winners, reporters, warned>>

\* REQ-005, REQ-006, REQ-013 (from F1)
CompleteFailed(o) ==
    /\ status[o] = "Processing"
    /\ status' = [status EXCEPT ![o] =
                    IF cancelReq[o] THEN "Cancelled"
                    ELSE IF attempt[o] < MaxAttempts THEN "Failed" ELSE "DeadLettered"]
    /\ UNCHANGED <<policy, paused, nextRun, dueRead, attempt, cancelReq, winners, reporters, warned>>

\* REQ-006, REQ-013 (from F1): a permanent failure.
CompletePermanent(o) ==
    /\ status[o] = "Processing"
    /\ status' = [status EXCEPT ![o] = IF cancelReq[o] THEN "Cancelled" ELSE "DeadLettered"]
    /\ UNCHANGED <<policy, paused, nextRun, dueRead, attempt, cancelReq, winners, reporters, warned>>

\* REQ-009 (from F1): the handler honours the cancel request.
CompleteCancelled(o) ==
    /\ status[o] = "Processing"
    /\ cancelReq[o]
    /\ status' = [status EXCEPT ![o] = "Cancelled"]
    /\ UNCHANGED <<policy, paused, nextRun, dueRead, attempt, cancelReq, winners, reporters, warned>>

\* REQ-005, REQ-006, REQ-009, REQ-013 (from F1)
Complete(o) ==
    \/ CompleteSucceeded(o)
    \/ CompleteFailed(o)
    \/ CompletePermanent(o)
    \/ CompleteCancelled(o)

\* REQ-007 (from F1)
RetryDue(o) ==
    /\ status[o] = "Failed"
    /\ status' = [status EXCEPT ![o] = "Enqueued"]
    /\ UNCHANGED <<policy, paused, nextRun, dueRead, attempt, cancelReq, winners, reporters, warned>>

\* REQ-008 (from F1)
RecoverLease(o) ==
    /\ status[o] = "Processing"
    /\ status' = [status EXCEPT ![o] =
                    IF cancelReq[o] THEN "Cancelled"
                    ELSE IF attempt[o] < MaxAttempts THEN "Enqueued" ELSE "DeadLettered"]
    /\ UNCHANGED <<policy, paused, nextRun, dueRead, attempt, cancelReq, winners, reporters, warned>>

\* REQ-009 (from F1)
CancelOcc(o) ==
    /\ \/ /\ status[o] \in {"Scheduled", "Enqueued", "Failed", "Awaiting", "Unroutable"}
          /\ status' = [status EXCEPT ![o] = "Cancelled"]
          /\ UNCHANGED cancelReq
       \/ /\ status[o] = "Processing"
          /\ ~cancelReq[o]
          /\ cancelReq' = [cancelReq EXCEPT ![o] = TRUE]
          /\ UNCHANGED status
    /\ UNCHANGED <<policy, paused, nextRun, dueRead, attempt, winners, reporters, warned>>

\* REQ-011 (from F1)
DeleteOcc(o) ==
    /\ status[o] \notin {"None", "Deleted", "Processing"}
    /\ status' = [status EXCEPT ![o] = "Deleted"]
    /\ UNCHANGED <<policy, paused, nextRun, dueRead, attempt, cancelReq, winners, reporters, warned>>

\* REQ-010 (from F1): ignores the overlap policy, and warns the operator when another run is active (D-4).
Requeue(o) ==
    /\ status[o] \in {"DeadLettered", "Failed", "Cancelled", "Succeeded"}
    /\ status' = [status EXCEPT ![o] = "Enqueued"]
    /\ attempt' = [attempt EXCEPT ![o] = 0]
    /\ warned' = [warned EXCEPT ![o] = OtherActive(o)]
    /\ UNCHANGED <<policy, paused, nextRun, dueRead, cancelReq, winners, reporters>>

\* REQ-036 (from F5): no live node advertises the name at that moment.
MarkUnroutable(o) ==
    /\ status[o] = "Enqueued"
    /\ status' = [status EXCEPT ![o] = "Unroutable"]
    /\ UNCHANGED <<policy, paused, nextRun, dueRead, attempt, cancelReq, winners, reporters, warned>>

\* REQ-037 (from F5)
Reroute(o) ==
    /\ status[o] = "Unroutable"
    /\ status' = [status EXCEPT ![o] = "Enqueued"]
    /\ UNCHANGED <<policy, paused, nextRun, dueRead, attempt, cancelReq, winners, reporters, warned>>

Next ==
    \/ \E n \in Nodes :
        \/ ReadDue(n)
        \/ FireDue(n)
        \/ CatchUpFire(n)
        \/ FirePausedAfterDue(n)
        \/ FireLost(n)
    \/ Pause
    \/ ManualTrigger
    \/ \E o \in Occs :
        \/ PromoteAwaiting(o)
        \/ Claim(o)
        \/ Complete(o)
        \/ RetryDue(o)
        \/ RecoverLease(o)
        \/ CancelOcc(o)
        \/ DeleteOcc(o)

\* REQ-022, REQ-007: the tick runs every poll interval and running occurrences end.
Spec == Init /\ [][Next]_vars
        /\ \A o \in Occs : /\ WF_vars(PromoteAwaiting(o))
                           /\ WF_vars(RetryDue(o))
                           /\ WF_vars(Claim(o))
                           /\ WF_vars(Complete(o))

\* REQ-021, REQ-024, REQ-010: the one accepted overlap involves a run requeued with a warning (D-4).
NoOverlap ==
    policy # "Allow" =>
        \A o, p \in Occs :
            (o # p /\ status[o] = "Processing" /\ status[p] = "Processing") => (warned[o] \/ warned[p])

\* REQ-018
OneFirePerInstant == \A i \in Instants : Cardinality(winners[i]) <= 1

\* REQ-020, REQ-026
SkipCreatesNothingWhileActive ==
    [][(policy = "Skip" /\ AnyActive) => Created' = Created]_vars

\* REQ-017, REQ-026: pausing stops the schedule only; a manual trigger still creates (D-11).
PausedNeverFires ==
    [][paused => /\ UNCHANGED <<nextRun, winners, reporters>>
                 /\ (Created' = Created \/ ManualTrigger)]_vars

\* REQ-022
AwaitingNeverStranded ==
    \A o \in Occs :
        status[o] = "Awaiting" ~> status[o] \in FinalStates \cup {"Enqueued", "Deleted"}

\* REQ-043
MissedReportedOnce ==
    \A i \in Instants : Cardinality(reporters[i]) <= 1 /\ reporters[i] \subseteq winners[i]

\* REQ-021, REQ-025, REQ-010: the one accepted exception is a newer run requeued with a warning (D-4).
AwaitingRunsInOrder ==
    policy # "Allow" =>
        \A o, p \in Occs :
            (o < p /\ status[o] = "Awaiting" /\ status[p] \in {"Enqueued", "Processing"}) => warned[p]
====
