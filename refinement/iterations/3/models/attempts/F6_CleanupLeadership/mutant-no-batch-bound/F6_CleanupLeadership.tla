---- MODULE F6_CleanupLeadership ----
\* PURPOSE: nodes take turns running cleanup under one short lease in the store;
\*          a run renews the lease before each batch, stops when it can't, and
\*          otherwise purges in batches until a batch comes back short.
\* ASSUMPTION: the cleanup lease lasts LeaseLength ticks (2); the stories give no product value.
\* ASSUMPTION: an idle node may try to take or renew the lease at any tick; the cleanup interval and when each node's interval comes round are not modelled.
\* ASSUMPTION: a failed attempt to start a run changes nothing; the node stays idle until it tries again.
\* ASSUMPTION: a node checks the lease when it starts a run and when it renews it before each batch, never while a batch is under way.
\* ASSUMPTION: a node runs one cleanup run at a time; while its run is in progress it touches the lease only through the renewal before each batch.
\* ASSUMPTION: the lease is not released when a run ends; it simply expires.
\* ASSUMPTION: a run has at most MaxBatches (3) batches, the last of which, if reached, is always short; no requirement bounds the number of full batches.
\* ASSUMPTION: a batch is bounded by the store's command timeout and the lease is at least twice that (D-8); with the pause between batches (at most 10 s), a batch and the pause after it end before the lease runs out, modelled as at most one of the lease's two ticks.
\* ASSUMPTION: an idle node keeps trying to take or renew the lease, and a run keeps going, so cleanup never stops for good.
\* ASSUMPTION: taking or renewing the lease is one atomic step in the store, judged by one shared store clock.
\* ASSUMPTION: nodes do not crash or stop in this model.
EXTENDS Naturals, FiniteSets, Common

CONSTANTS LeaseLength, MaxClock, MaxBatches

VARIABLES clock, leaseUntil, phase, batchesDone, lastBatch

vars == <<clock, leaseUntil, phase, batchesDone, lastBatch>>

Phases == {"Idle", "Running", "Purging"}
BatchResults == {"None", "Full", "Short"}

TypeOK ==
    /\ clock \in 0..MaxClock
    /\ leaseUntil \in [Nodes -> 0..(MaxClock + LeaseLength)]
    /\ phase \in [Nodes -> Phases]
    /\ batchesDone \in [Nodes -> 0..MaxBatches]
    /\ lastBatch \in [Nodes -> BatchResults]

\* REQ-039
Holds(n) == clock < leaseUntil[n]

Init ==
    /\ clock = 0
    /\ leaseUntil = [n \in Nodes |-> 0]
    /\ phase = [n \in Nodes |-> "Idle"]
    /\ batchesDone = [n \in Nodes |-> 0]
    /\ lastBatch = [n \in Nodes |-> "None"]

\* REQ-039, REQ-040
StartRun(n) ==
    /\ phase' = [phase EXCEPT ![n] = "Running"]
    /\ batchesDone' = [batchesDone EXCEPT ![n] = 0]
    /\ lastBatch' = [lastBatch EXCEPT ![n] = "None"]

\* REQ-039
TakeLease(n) ==
    /\ phase[n] = "Idle"
    /\ ~Holds(n)
    /\ \A m \in Nodes \ {n} : ~Holds(m)
    /\ leaseUntil' = [m \in Nodes |-> IF m = n THEN clock + LeaseLength ELSE 0]
    /\ StartRun(n)
    /\ UNCHANGED clock

\* REQ-039
RenewLease(n) ==
    /\ phase[n] = "Idle"
    /\ Holds(n)
    /\ leaseUntil' = [leaseUntil EXCEPT ![n] = clock + LeaseLength]
    /\ StartRun(n)
    /\ UNCHANGED clock

\* The renewal before a batch is one store step: it succeeds while the node
\* still holds the lease, or when no node holds it unexpired.
\* REQ-039, REQ-040
CanRenew(n) == Holds(n) \/ \A m \in Nodes \ {n} : ~Holds(m)

\* REQ-039, REQ-040, REQ-041
StartBatch(n) ==
    /\ phase[n] = "Running"
    /\ CanRenew(n)
    /\ leaseUntil' = [m \in Nodes |-> IF m = n THEN clock + LeaseLength ELSE 0]
    /\ phase' = [phase EXCEPT ![n] = "Purging"]
    /\ UNCHANGED <<clock, batchesDone, lastBatch>>

\* REQ-040
StopOnFailedRenewal(n) ==
    /\ phase[n] = "Running"
    /\ ~CanRenew(n)
    /\ phase' = [phase EXCEPT ![n] = "Idle"]
    /\ UNCHANGED <<clock, leaseUntil, batchesDone, lastBatch>>

\* REQ-041
FinishBatch(n) ==
    /\ phase[n] = "Purging"
    /\ \E short \in (IF batchesDone[n] + 1 = MaxBatches THEN {TRUE} ELSE BOOLEAN) :
        /\ batchesDone' = [batchesDone EXCEPT ![n] = @ + 1]
        /\ lastBatch' = [lastBatch EXCEPT ![n] = IF short THEN "Short" ELSE "Full"]
        /\ phase' = [phase EXCEPT ![n] = IF short THEN "Idle" ELSE "Running"]
    /\ UNCHANGED <<clock, leaseUntil>>

\* REQ-039, REQ-040 (D-8)
Tick ==
    /\ clock < MaxClock
    /\ clock' = clock + 1
    /\ UNCHANGED <<leaseUntil, phase, batchesDone, lastBatch>>

Next ==
    \/ \E n \in Nodes : TakeLease(n)
    \/ \E n \in Nodes : RenewLease(n)
    \/ \E n \in Nodes : StartBatch(n)
    \/ \E n \in Nodes : StopOnFailedRenewal(n)
    \/ \E n \in Nodes : FinishBatch(n)
    \/ Tick

\* REQ-039, REQ-041: cleanup comes round again and a run keeps going.
Fairness ==
    /\ WF_vars(\E n \in Nodes : TakeLease(n) \/ RenewLease(n))
    /\ \A n \in Nodes : WF_vars(StartBatch(n) \/ StopOnFailedRenewal(n) \/ FinishBatch(n))

Spec == Init /\ [][Next]_vars /\ Fairness

\* REQ-039
OneLeaseHolder == \A a, b \in Nodes : (Holds(a) /\ Holds(b)) => a = b

\* REQ-039
TakeOnlyAfterExpiry ==
    [][\A n \in Nodes :
        (~Holds(n) /\ clock' < leaseUntil'[n]) => \A m \in Nodes \ {n} : ~Holds(m)]_vars

\* REQ-040
OnlyHolderPurges == \A n \in Nodes : phase[n] = "Purging" => Holds(n)

\* REQ-039, REQ-040
OneCleanupRunAtATime ==
    \A a, b \in Nodes : (phase[a] # "Idle" /\ phase[b] # "Idle") => a = b

\* REQ-039
CleanupKeepsRunning == []<>(\E n \in Nodes : phase[n] # "Idle")

\* REQ-041
RunEndsOnShortBatch ==
    [][\A n \in Nodes :
        (phase[n] # "Idle" /\ phase'[n] = "Idle") =>
            (lastBatch'[n] = "Short" \/ ~CanRenew(n))]_vars
====
