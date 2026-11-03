---- MODULE F2_SelfFencingSendTime ----
\* PURPOSE: a node keeps one running job's lease alive and cancels its handler when it can no longer renew, so another node that recovers the job never runs it at the same time.
\* ASSUMPTION: time moves in whole ticks of a third of the lease (lease = 3 ticks) and the node attempts one renewal per tick; the requirements don't say how "a third" rounds for a lease not divisible by three.
\* ASSUMPTION: both nodes' clocks equal the store's clock; skew is out of scope.
\* ASSUMPTION: VARIANT of F2_SelfFencing. The node takes the time of a successful renewal as the moment it sent the request, not the moment the response reached it.
\* ASSUMPTION: the claim at time 0 counts as the first successful renewal: the store's lease expires at 0 + lease length and the node counts from 0.
\* ASSUMPTION: the node has at most one renewal in flight; a late response arrives exactly one tick after it was sent, and the node then makes that tick's attempt.
\* ASSUMPTION: the node checks the self-fencing condition at least once per tick, so it cancels within the first tick in which the condition holds.
\* ASSUMPTION: a job recovered from n1 has attempts left, so it goes back to Enqueued, and n2 is the node that claims it.
\* ASSUMPTION: n2 never renews its own lease and nothing recovers the job from n2; one hand-over is modelled.
\* ASSUMPTION: only a shutdown whose lease release fails is modelled, and only early enough that the lease can expire before the clock bound.
EXTENDS Naturals, Common

CONSTANTS Holder, Recoverer, MaxTime, LeaseLength

ASSUME /\ Holder \in Nodes
       /\ Recoverer \in Nodes
       /\ Holder # Recoverer
       /\ MaxTime \in Nat
       /\ LeaseLength \in Nat \ {0}

VARIABLES now, expiry, jobState, owner, handler, lastOk, pending, attempted, healthy
vars == <<now, expiry, jobState, owner, handler, lastOk, pending, attempted, healthy>>

Times == 0..MaxTime
HandlerStates == {"Idle", "Running", "Cancelled", "Finished", "Stopped"}

TypeOK ==
    /\ now \in Times
    /\ expiry \in 0..(MaxTime + LeaseLength)
    /\ jobState \in {"Processing", "Enqueued", "Succeeded"}
    /\ owner \in Nodes
    /\ handler \in [Nodes -> HandlerStates]
    /\ lastOk \in Times
    /\ pending \in {"none", "sent", "due"}
    /\ attempted \in BOOLEAN
    /\ healthy \in BOOLEAN

Init ==
    /\ now = 0
    /\ expiry = LeaseLength
    /\ jobState = "Processing"
    /\ owner = Holder
    /\ handler = [n \in Nodes |-> IF n = Holder THEN "Running" ELSE "Idle"]
    /\ lastOk = 0
    /\ pending = "none"
    /\ attempted = TRUE
    /\ healthy = TRUE

HolderRuns == handler[Holder] = "Running"
HolderHoldsLease == jobState = "Processing" /\ owner = Holder
Recovered == jobState = "Enqueued" \/ owner = Recoverer
FenceDue == HolderRuns /\ now > lastOk + LeaseLength
CanAttempt == HolderRuns /\ ~attempted /\ pending = "none"

\* REQ-014, REQ-002
RenewOk ==
    /\ CanAttempt
    /\ HolderHoldsLease
    /\ expiry' = now + LeaseLength
    /\ lastOk' = now
    /\ attempted' = TRUE
    /\ UNCHANGED <<now, jobState, owner, handler, pending, healthy>>

\* REQ-014, REQ-002
RenewSlowResponse ==
    /\ CanAttempt
    /\ HolderHoldsLease
    /\ expiry' = now + LeaseLength
    /\ pending' = "sent"
    /\ attempted' = TRUE
    /\ healthy' = FALSE
    /\ UNCHANGED <<now, jobState, owner, handler, lastOk>>

\* REQ-014, REQ-015
SlowResponseArrives ==
    /\ pending = "due"
    /\ lastOk' = now - 1
    /\ pending' = "none"
    /\ UNCHANGED <<now, expiry, jobState, owner, handler, attempted, healthy>>

\* REQ-015, REQ-002
RenewResponseLost ==
    /\ CanAttempt
    /\ HolderHoldsLease
    /\ expiry' = now + LeaseLength
    /\ attempted' = TRUE
    /\ healthy' = FALSE
    /\ UNCHANGED <<now, jobState, owner, handler, lastOk, pending>>

\* REQ-015
RenewStoreDown ==
    /\ CanAttempt
    /\ attempted' = TRUE
    /\ healthy' = FALSE
    /\ UNCHANGED <<now, expiry, jobState, owner, handler, lastOk, pending>>

\* REQ-002, REQ-003
RenewToldLost ==
    /\ CanAttempt
    /\ ~HolderHoldsLease
    /\ handler' = [handler EXCEPT ![Holder] = "Cancelled"]
    /\ attempted' = TRUE
    /\ UNCHANGED <<now, expiry, jobState, owner, lastOk, pending, healthy>>

\* REQ-015
SelfFence ==
    /\ FenceDue
    /\ handler' = [handler EXCEPT ![Holder] = "Cancelled"]
    /\ UNCHANGED <<now, expiry, jobState, owner, lastOk, pending, attempted, healthy>>

\* REQ-003, REQ-005
HolderFinishes ==
    /\ HolderRuns
    /\ handler' = [handler EXCEPT ![Holder] = "Finished"]
    /\ jobState' = IF HolderHoldsLease THEN "Succeeded" ELSE jobState
    /\ UNCHANGED <<now, expiry, owner, lastOk, pending, attempted, healthy>>

\* REQ-012, REQ-016
ShutdownReleaseFails ==
    /\ HolderRuns
    /\ now + LeaseLength + 1 <= MaxTime
    /\ handler' = [handler EXCEPT ![Holder] = "Stopped"]
    /\ healthy' = FALSE
    /\ UNCHANGED <<now, expiry, jobState, owner, lastOk, pending, attempted>>

\* REQ-008, REQ-016
Recover ==
    /\ HolderHoldsLease
    /\ now > expiry
    /\ jobState' = "Enqueued"
    /\ UNCHANGED <<now, expiry, owner, handler, lastOk, pending, attempted, healthy>>

\* REQ-001
RecovererStarts ==
    /\ jobState = "Enqueued"
    /\ jobState' = "Processing"
    /\ owner' = Recoverer
    /\ handler' = [handler EXCEPT ![Recoverer] = "Running"]
    /\ expiry' = now + LeaseLength
    /\ UNCHANGED <<now, lastOk, pending, attempted, healthy>>

\* REQ-014, REQ-015
Tick ==
    /\ now < MaxTime
    /\ HolderRuns => attempted
    /\ ~FenceDue
    /\ now' = now + 1
    /\ attempted' = FALSE
    /\ pending' = IF pending = "sent" THEN "due" ELSE "none"
    /\ UNCHANGED <<expiry, jobState, owner, handler, lastOk, healthy>>

Next ==
    \/ RenewOk
    \/ RenewSlowResponse
    \/ SlowResponseArrives
    \/ RenewResponseLost
    \/ RenewStoreDown
    \/ RenewToldLost
    \/ SelfFence
    \/ HolderFinishes
    \/ ShutdownReleaseFails
    \/ Recover
    \/ RecovererStarts
    \/ Tick

Spec == Init /\ [][Next]_vars /\ WF_vars(Tick) /\ WF_vars(Recover)

\* REQ-015
NoDoubleRun == ~(handler[Holder] = "Running" /\ handler[Recoverer] = "Running")

\* REQ-014
HealthyNeverRecovered == healthy => ~Recovered

\* REQ-015
CancelledByRecoveryMoment ==
    [][Tick => ~(HolderRuns /\ (Recovered \/ (HolderHoldsLease /\ now > expiry)))]_vars

\* REQ-016
RecoveredAfterFailedRelease == (handler[Holder] = "Stopped") ~> Recovered
====
