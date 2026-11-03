---- MODULE F2_SelfFencing ----
\* PURPOSE: a node keeps one running job's lease alive and cancels its handler when it can no longer renew, so another node that recovers the job never runs it at the same time.
\* ASSUMPTION: time moves in whole ticks of a sixth of the lease (lease = 6 ticks), the node attempts one renewal every 2 ticks (a third of the lease) and two thirds of the lease is 4 ticks; the requirements don't say how "a third" rounds for a lease not divisible by three.
\* ASSUMPTION: both nodes' clocks equal the store's clock; skew is out of scope.
\* ASSUMPTION: the node takes the time of a successful renewal as the moment it sent the request, and the store extends the lease from no earlier than that moment (D-7).
\* ASSUMPTION: the claim at time 0 counts as the first successful renewal: the store's lease expires at 0 + lease length and the node counts from 0.
\* ASSUMPTION: the node has at most one renewal in flight; a late answer arrives 1 or 2 ticks after it was sent (at most one renewal interval late), before the next attempt.
\* ASSUMPTION: the node checks the self-fencing condition at least once per renewal interval, so it cancels no later than 2 ticks after two thirds of the lease has passed.
\* ASSUMPTION: a handler stops the moment the node cancels it; a handler that ignores the cancel is out of scope.
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
       /\ LeaseLength % 3 = 0

\* REQ-014
RenewEvery == LeaseLength \div 3

\* REQ-015
FenceAfter == LeaseLength

VARIABLES now, expiry, jobState, owner, handler, lastOk, pending, sentAt, attempted, healthy
vars == <<now, expiry, jobState, owner, handler, lastOk, pending, sentAt, attempted, healthy>>

Times == 0..MaxTime
HandlerStates == {"Idle", "Running", "Cancelled", "Finished", "Stopped"}

TypeOK ==
    /\ now \in Times
    /\ expiry \in 0..(MaxTime + LeaseLength)
    /\ jobState \in {"Processing", "Enqueued", "Succeeded"}
    /\ owner \in Nodes
    /\ handler \in [Nodes -> HandlerStates]
    /\ lastOk \in Times
    /\ pending \in {"none", "sent"}
    /\ sentAt \in Times
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
    /\ sentAt = 0
    /\ attempted = TRUE
    /\ healthy = TRUE

HolderRuns == handler[Holder] = "Running"
HolderHoldsLease == jobState = "Processing" /\ owner = Holder
Recovered == jobState = "Enqueued" \/ owner = Recoverer
\* lastOk is the send time of the last renewal the node knows succeeded (D-7).
FenceDue == HolderRuns /\ now >= lastOk + FenceAfter
\* The latest moment the node's periodic check can still be catching up on FenceDue.
FenceOverdue == HolderRuns /\ now >= lastOk + FenceAfter + RenewEvery
CanAttempt == HolderRuns /\ ~attempted /\ pending = "none"

\* REQ-014, REQ-002
RenewOk ==
    /\ CanAttempt
    /\ HolderHoldsLease
    /\ expiry' = now + LeaseLength
    /\ lastOk' = now
    /\ attempted' = TRUE
    /\ UNCHANGED <<now, jobState, owner, handler, pending, sentAt, healthy>>

\* REQ-014, REQ-002
RenewSlowResponse ==
    /\ CanAttempt
    /\ HolderHoldsLease
    /\ expiry' = now + LeaseLength
    /\ pending' = "sent"
    /\ sentAt' = now
    /\ attempted' = TRUE
    /\ healthy' = FALSE
    /\ UNCHANGED <<now, jobState, owner, handler, lastOk>>

\* REQ-014, REQ-015
SlowResponseArrives ==
    /\ HolderRuns
    /\ pending = "sent"
    /\ now > sentAt
    /\ lastOk' = sentAt
    /\ pending' = "none"
    /\ UNCHANGED <<now, expiry, jobState, owner, handler, sentAt, attempted, healthy>>

\* REQ-015, REQ-002
RenewResponseLost ==
    /\ CanAttempt
    /\ HolderHoldsLease
    /\ expiry' = now + LeaseLength
    /\ attempted' = TRUE
    /\ healthy' = FALSE
    /\ UNCHANGED <<now, jobState, owner, handler, lastOk, pending, sentAt>>

\* REQ-015
RenewStoreDown ==
    /\ CanAttempt
    /\ attempted' = TRUE
    /\ healthy' = FALSE
    /\ UNCHANGED <<now, expiry, jobState, owner, handler, lastOk, pending, sentAt>>

\* REQ-002, REQ-003
RenewToldLost ==
    /\ CanAttempt
    /\ ~HolderHoldsLease
    /\ handler' = [handler EXCEPT ![Holder] = "Cancelled"]
    /\ attempted' = TRUE
    /\ UNCHANGED <<now, expiry, jobState, owner, lastOk, pending, sentAt, healthy>>

\* REQ-015
SelfFence ==
    /\ FenceDue
    /\ handler' = [handler EXCEPT ![Holder] = "Cancelled"]
    /\ UNCHANGED <<now, expiry, jobState, owner, lastOk, pending, sentAt, attempted, healthy>>

\* REQ-003, REQ-005
HolderFinishes ==
    /\ HolderRuns
    /\ handler' = [handler EXCEPT ![Holder] = "Finished"]
    /\ jobState' = IF HolderHoldsLease THEN "Succeeded" ELSE jobState
    /\ UNCHANGED <<now, expiry, owner, lastOk, pending, sentAt, attempted, healthy>>

\* REQ-012, REQ-016
ShutdownReleaseFails ==
    /\ HolderRuns
    /\ now + LeaseLength + 1 <= MaxTime
    /\ handler' = [handler EXCEPT ![Holder] = "Stopped"]
    /\ healthy' = FALSE
    /\ UNCHANGED <<now, expiry, jobState, owner, lastOk, pending, sentAt, attempted>>

\* REQ-008, REQ-016
Recover ==
    /\ HolderHoldsLease
    /\ now > expiry
    /\ jobState' = "Enqueued"
    /\ UNCHANGED <<now, expiry, owner, handler, lastOk, pending, sentAt, attempted, healthy>>

\* REQ-001
RecovererStarts ==
    /\ jobState = "Enqueued"
    /\ jobState' = "Processing"
    /\ owner' = Recoverer
    /\ handler' = [handler EXCEPT ![Recoverer] = "Running"]
    /\ expiry' = now + LeaseLength
    /\ UNCHANGED <<now, lastOk, pending, sentAt, attempted, healthy>>

\* A renewal falls due every RenewEvery ticks; a late answer still unread when its
\* interval ends is dropped, which is the same as a lost answer.
\* REQ-014, REQ-015
Tick ==
    /\ now < MaxTime
    /\ HolderRuns => attempted
    /\ ~FenceOverdue
    /\ now' = now + 1
    /\ attempted' = IF (now + 1) % RenewEvery = 0 THEN FALSE ELSE attempted
    /\ pending' = IF pending = "sent" /\ now + 1 > sentAt + RenewEvery THEN "none" ELSE pending
    /\ UNCHANGED <<expiry, jobState, owner, handler, lastOk, sentAt, healthy>>

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
