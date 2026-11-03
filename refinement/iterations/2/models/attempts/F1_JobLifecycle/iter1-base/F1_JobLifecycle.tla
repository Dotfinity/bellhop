---- MODULE F1_JobLifecycle ----
EXTENDS Integers, FiniteSets, Common

\* PURPOSE: how a job moves through claim, lease, completion, retry, recovery,
\* cancel, requeue, delete and shutdown release when two nodes work at once.
\* ASSUMPTION: time is not modelled; a lease may expire at any moment while the job is Processing, and a Failed or Scheduled job may become due at any moment.
\* ASSUMPTION: a job is claimed at most MaxClaims times in total, so lease tokens are bounded.
\* ASSUMPTION: an operator requeues a job at most MaxRequeues times.
\* ASSUMPTION: a job's lease token changes only when the job is claimed again; nothing in the requirements retires it on recovery, release, requeue or completion, and the store checks only the token.
\* ASSUMPTION: a node knows its lease is lost only when a renewal is refused (REQ-002); until then it keeps running the job.
\* ASSUMPTION: a node reports the Cancelled outcome only after a renewal has told it a cancel was requested.
\* ASSUMPTION: a cancel on a Failed job waiting for its retry counts as cancelling a job that has not started, so it is cancelled at once.
\* ASSUMPTION: when an expired lease has a cancel request, recovery cancels the job whatever its attempts.
\* ASSUMPTION: a requeue clears an earlier cancel request; nothing else does.
\* ASSUMPTION: a shutdown release is checked by token like renewal and completion, and the store does not check the job's state; "not counted" means the attempt count goes down by one.
\* ASSUMPTION: a node repeats a completion at most once, after which it has its answer and forgets the job.
\* ASSUMPTION: a deleted job no longer exists, so nothing a node sends for it changes anything.
\* ASSUMPTION: the check runs one job (two jobs exceed the checkable size); jobs do not interact in F1, and a shutdown releases each job the node runs in the same way.

CONSTANTS Jobs, MaxAttempts, MaxClaims, MaxRequeues

VARIABLES state, attempt, token, leaseExpired, cancelReq, requeues,
          recTok, recOut, attemptBefore, held, done, knowsCancel

storeVars == <<state, attempt, token, leaseExpired, cancelReq, requeues,
               recTok, recOut, attemptBefore>>
vars == <<state, attempt, token, leaseExpired, cancelReq, requeues,
          recTok, recOut, attemptBefore, held, done, knowsCancel>>

Outcomes == {"Succeeded", "Cancelled", "Failed", "Permanent"}
Statuses == JobStates \cup {"Deleted"}
RequeueFrom == {"DeadLettered", "Failed", "Cancelled", "Succeeded"}
NotStarted == {"Scheduled", "Enqueued", "Failed"}
Counts == (0 - MaxClaims)..(MaxAttempts + MaxClaims)

TypeOK ==
    /\ state \in [Jobs -> Statuses]
    /\ attempt \in [Jobs -> Counts]
    /\ token \in [Jobs -> 0..MaxClaims]
    /\ leaseExpired \in [Jobs -> BOOLEAN]
    /\ cancelReq \in [Jobs -> BOOLEAN]
    /\ requeues \in [Jobs -> 0..MaxRequeues]
    /\ recTok \in [Jobs -> 0..MaxClaims]
    /\ recOut \in [Jobs -> Outcomes \cup {"None"}]
    /\ attemptBefore \in [Jobs -> Counts]
    /\ held \in [Nodes -> [Jobs -> 0..MaxClaims]]
    /\ done \in [Nodes -> [Jobs -> Outcomes \cup {"None"}]]
    /\ knowsCancel \in [Nodes -> [Jobs -> BOOLEAN]]

Init ==
    /\ state \in [Jobs -> {"Scheduled", "Enqueued"}]
    /\ attempt = [j \in Jobs |-> 0]
    /\ token = [j \in Jobs |-> 0]
    /\ leaseExpired = [j \in Jobs |-> FALSE]
    /\ cancelReq = [j \in Jobs |-> FALSE]
    /\ requeues = [j \in Jobs |-> 0]
    /\ recTok = [j \in Jobs |-> 0]
    /\ recOut = [j \in Jobs |-> "None"]
    /\ attemptBefore = [j \in Jobs |-> 0]
    /\ held = [n \in Nodes |-> [j \in Jobs |-> 0]]
    /\ done = [n \in Nodes |-> [j \in Jobs |-> "None"]]
    /\ knowsCancel = [n \in Nodes |-> [j \in Jobs |-> FALSE]]

Running(n, j) == held[n][j] # 0 /\ done[n][j] = "None"

\* REQ-002, REQ-003
Current(n, j) == held[n][j] = token[j] /\ state[j] # "Deleted"

\* REQ-005, REQ-006, REQ-013
Recorded(j, o) ==
    IF o = "Succeeded" THEN "Succeeded"
    ELSE IF o = "Cancelled" THEN "Cancelled"
    ELSE IF cancelReq[j] THEN "Cancelled"
    ELSE IF o = "Permanent" \/ attempt[j] >= MaxAttempts THEN "DeadLettered"
    ELSE "Failed"

\* REQ-003, REQ-004, REQ-005
StoreComplete(j, t, o) ==
    IF t = token[j] /\ state[j] # "Deleted" /\ ~(recTok[j] = t /\ recOut[j] = o)
      THEN /\ state' = [state EXCEPT ![j] = Recorded(j, o)]
           /\ leaseExpired' = [leaseExpired EXCEPT ![j] = FALSE]
           /\ recTok' = [recTok EXCEPT ![j] = t]
           /\ recOut' = [recOut EXCEPT ![j] = o]
           /\ UNCHANGED <<attempt, token, cancelReq, requeues, attemptBefore>>
      ELSE UNCHANGED storeVars

\* REQ-001
Claim(n, j) ==
    /\ state[j] = "Enqueued"
    /\ token[j] < MaxClaims
    /\ state' = [state EXCEPT ![j] = "Processing"]
    /\ attempt' = [attempt EXCEPT ![j] = @ + 1]
    /\ attemptBefore' = [attemptBefore EXCEPT ![j] = attempt[j]]
    /\ token' = [token EXCEPT ![j] = @ + 1]
    /\ leaseExpired' = [leaseExpired EXCEPT ![j] = FALSE]
    /\ held' = [held EXCEPT ![n][j] = token[j] + 1]
    /\ done' = [done EXCEPT ![n][j] = "None"]
    /\ knowsCancel' = [knowsCancel EXCEPT ![n][j] = FALSE]
    /\ UNCHANGED <<cancelReq, requeues, recTok, recOut>>

\* REQ-002, REQ-003, REQ-009
Renew(n, j) ==
    /\ Running(n, j)
    /\ IF Current(n, j)
         THEN /\ leaseExpired' = [leaseExpired EXCEPT ![j] = FALSE]
              /\ knowsCancel' = [knowsCancel EXCEPT ![n][j] = cancelReq[j]]
              /\ UNCHANGED <<held, done>>
         ELSE /\ held' = [held EXCEPT ![n][j] = 0]
              /\ knowsCancel' = [knowsCancel EXCEPT ![n][j] = FALSE]
              /\ UNCHANGED <<leaseExpired, done>>
    /\ UNCHANGED <<state, attempt, token, cancelReq, requeues, recTok, recOut,
                   attemptBefore>>

\* REQ-008
Expire(j) ==
    /\ state[j] = "Processing"
    /\ ~leaseExpired[j]
    /\ leaseExpired' = [leaseExpired EXCEPT ![j] = TRUE]
    /\ UNCHANGED <<state, attempt, token, cancelReq, requeues, recTok, recOut,
                   attemptBefore, held, done, knowsCancel>>

\* REQ-008
Recover(j) ==
    /\ state[j] = "Processing"
    /\ leaseExpired[j]
    /\ state' = [state EXCEPT ![j] =
                   IF cancelReq[j] THEN "Cancelled"
                   ELSE IF attempt[j] < MaxAttempts THEN "Enqueued"
                   ELSE "DeadLettered"]
    /\ leaseExpired' = [leaseExpired EXCEPT ![j] = FALSE]
    /\ UNCHANGED <<attempt, token, cancelReq, requeues, recTok, recOut,
                   attemptBefore, held, done, knowsCancel>>

\* REQ-003, REQ-005, REQ-006, REQ-009, REQ-013
Complete(n, j, o) ==
    /\ Running(n, j)
    /\ (o = "Cancelled") => knowsCancel[n][j]
    /\ StoreComplete(j, held[n][j], o)
    /\ done' = [done EXCEPT ![n][j] = o]
    /\ UNCHANGED <<held, knowsCancel>>

\* REQ-004
RepeatComplete(n, j) ==
    /\ held[n][j] # 0
    /\ done[n][j] # "None"
    /\ StoreComplete(j, held[n][j], done[n][j])
    /\ held' = [held EXCEPT ![n][j] = 0]
    /\ done' = [done EXCEPT ![n][j] = "None"]
    /\ knowsCancel' = [knowsCancel EXCEPT ![n][j] = FALSE]

\* REQ-009
CancelNow(j) ==
    /\ state[j] \in NotStarted
    /\ state' = [state EXCEPT ![j] = "Cancelled"]
    /\ UNCHANGED <<attempt, token, leaseExpired, cancelReq, requeues, recTok,
                   recOut, attemptBefore, held, done, knowsCancel>>

\* REQ-009
RequestCancel(j) ==
    /\ state[j] = "Processing"
    /\ ~cancelReq[j]
    /\ cancelReq' = [cancelReq EXCEPT ![j] = TRUE]
    /\ UNCHANGED <<state, attempt, token, leaseExpired, requeues, recTok,
                   recOut, attemptBefore, held, done, knowsCancel>>

\* REQ-007
Promote(j) ==
    /\ state[j] \in {"Scheduled", "Failed"}
    /\ state' = [state EXCEPT ![j] = "Enqueued"]
    /\ UNCHANGED <<attempt, token, leaseExpired, cancelReq, requeues, recTok,
                   recOut, attemptBefore, held, done, knowsCancel>>

\* REQ-010
Requeue(j) ==
    /\ state[j] \in RequeueFrom
    /\ requeues[j] < MaxRequeues
    /\ state' = [state EXCEPT ![j] = "Enqueued"]
    /\ attempt' = [attempt EXCEPT ![j] = 0]
    /\ requeues' = [requeues EXCEPT ![j] = @ + 1]
    /\ cancelReq' = [cancelReq EXCEPT ![j] = FALSE]
    /\ UNCHANGED <<token, leaseExpired, recTok, recOut, attemptBefore, held,
                   done, knowsCancel>>

\* REQ-011
Delete(j) ==
    /\ state[j] \notin {"Processing", "Deleted"}
    /\ state' = [state EXCEPT ![j] = "Deleted"]
    /\ UNCHANGED <<attempt, token, leaseExpired, cancelReq, requeues, recTok,
                   recOut, attemptBefore, held, done, knowsCancel>>

\* REQ-012
Releases(n, j) == Running(n, j) /\ Current(n, j)

\* REQ-012
ShutdownRelease(n) ==
    /\ \E j \in Jobs : held[n][j] # 0
    /\ state' = [j \in Jobs |-> IF Releases(n, j) THEN "Enqueued" ELSE state[j]]
    /\ attempt' = [j \in Jobs |-> IF Releases(n, j) THEN attempt[j] - 1 ELSE attempt[j]]
    /\ leaseExpired' = [j \in Jobs |-> IF Releases(n, j) THEN FALSE ELSE leaseExpired[j]]
    /\ held' = [held EXCEPT ![n] = [j \in Jobs |-> 0]]
    /\ done' = [done EXCEPT ![n] = [j \in Jobs |-> "None"]]
    /\ knowsCancel' = [knowsCancel EXCEPT ![n] = [j \in Jobs |-> FALSE]]
    /\ UNCHANGED <<token, cancelReq, requeues, recTok, recOut, attemptBefore>>

Next ==
    \/ \E n \in Nodes, j \in Jobs :
         \/ Claim(n, j)
         \/ Renew(n, j)
         \/ RepeatComplete(n, j)
         \/ \E o \in Outcomes : Complete(n, j, o)
    \/ \E j \in Jobs :
         \/ Expire(j)
         \/ Recover(j)
         \/ CancelNow(j)
         \/ RequestCancel(j)
         \/ Promote(j)
         \/ Requeue(j)
         \/ Delete(j)
    \/ \E n \in Nodes : ShutdownRelease(n)

Spec == Init /\ [][Next]_vars

JobUnchanged(j) ==
    /\ state'[j] = state[j]
    /\ attempt'[j] = attempt[j]
    /\ token'[j] = token[j]
    /\ leaseExpired'[j] = leaseExpired[j]
    /\ cancelReq'[j] = cancelReq[j]

\* REQ-001
SingleLeaseHolder ==
    \A j \in Jobs :
        token[j] # 0 => Cardinality({n \in Nodes : held[n][j] = token[j]}) <= 1

\* REQ-002, REQ-003
StaleTokenChangesNothing ==
    [][\A n \in Nodes, j \in Jobs :
         (/\ held[n][j] # token[j]
          /\ \/ Renew(n, j)
             \/ RepeatComplete(n, j)
             \/ \E o \in Outcomes : Complete(n, j, o))
         => JobUnchanged(j)]_vars

\* REQ-004
RepeatChangesNothing ==
    [][\A n \in Nodes, j \in Jobs : RepeatComplete(n, j) => JobUnchanged(j)]_vars

\* REQ-008, REQ-013
AttemptsWithinMax == \A j \in Jobs : attempt[j] \in 0..MaxAttempts

\* REQ-006
CancelledNeverAwaitsRetry == \A j \in Jobs : ~(cancelReq[j] /\ state[j] = "Failed")

\* REQ-006, REQ-008, REQ-009
CancelRequestHonoured ==
    [][\A j \in Jobs :
         (/\ cancelReq[j]
          /\ state'[j] # state[j]
          /\ state'[j] \in {"Enqueued", "Scheduled", "Failed"})
         => requeues'[j] = requeues[j] + 1]_vars

\* REQ-010
RequeueOnlyFromEndStates ==
    [][\A j \in Jobs :
         requeues'[j] # requeues[j]
         => /\ state[j] \in RequeueFrom
            /\ state'[j] = "Enqueued"
            /\ attempt'[j] = 0]_vars

\* REQ-011
NoDeleteWhileProcessing ==
    [][\A j \in Jobs :
         (state'[j] = "Deleted" /\ state[j] # "Deleted") => state[j] # "Processing"]_vars

\* REQ-012
ReleaseDoesNotCountAttempt ==
    [][\A n \in Nodes :
         ShutdownRelease(n)
         => \A j \in Jobs :
              (state'[j] # state[j] \/ attempt'[j] # attempt[j])
              => attempt'[j] = attemptBefore[j]]_vars

\* REQ-005, REQ-009
FinalStaysFinal ==
    [][\A j \in Jobs :
         state[j] \in FinalStates
         => \/ state'[j] \in {state[j], "Deleted"}
            \/ requeues'[j] = requeues[j] + 1]_vars

====
