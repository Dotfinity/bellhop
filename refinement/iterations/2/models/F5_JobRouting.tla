---- MODULE F5_JobRouting ----
\* PURPOSE: nodes only claim jobs they have a handler for, cleanup marks jobs
\* nobody live can handle as Unroutable, a handling node's tick brings them
\* back, and cleanup only deletes finished jobs. A node silent for longer than
\* the node timeout counts as gone even while its process still runs (D-12).
\* ASSUMPTION: all jobs share the one name x; Handlers are the nodes with a handler for x, and a node's handlers never change across restarts.
\* ASSUMPTION: a node advertises exactly the names it has handlers for, in every heartbeat.
\* ASSUMPTION: time is counted in whole steps; a heartbeat older than NodeTimeout is shown as NodeTimeout + 1.
\* ASSUMPTION: the routing grace period has no stated relation to the node timeout, so a job turns old at any moment, independently of heartbeats.
\* ASSUMPTION: rerouting does not reset a job's age; the requirements do not say.
\* ASSUMPTION: cleanup runs on a node that is running and live, and marks or purges one job per step, each judged on the store as it is at that moment.
\* ASSUMPTION: retention periods are left out; any finished job may be purged.
\* ASSUMPTION: attempts, leases and recovery of a crashed node's running job are left out (feature F1); a job running on a crashed node stays Processing.
\* ASSUMPTION: a node starting again keeps its old heartbeat age until its first tick.
EXTENDS Naturals, FiniteSets, Common

CONSTANTS
    Jobs,          \* the jobs, all named x
    Handlers,      \* the nodes with a handler for x
    NoNode,        \* claimer of a job nobody has claimed
    NodeTimeout    \* heartbeat age after which a node is no longer live

ASSUME Handlers \subseteq Nodes /\ NoNode \notin Nodes /\ NodeTimeout \in Nat

VARIABLES
    state,     \* job -> status, "Purged" once cleanup deleted it
    claimer,   \* job -> node that claimed it, or NoNode
    old,       \* job -> TRUE once older than the routing grace period
    up,        \* node -> TRUE while the node's process runs
    hb         \* node -> age of its last heartbeat, capped at NodeTimeout + 1

vars == << state, claimer, old, up, hb >>

ModelStates == {"Enqueued", "Unroutable", "Processing", "Succeeded",
                "DeadLettered", "Purged"}
ClaimedStates == {"Processing", "Succeeded", "DeadLettered", "Purged"}
Stale == NodeTimeout + 1

TypeOK ==
    /\ state \in [Jobs -> ModelStates]
    /\ claimer \in [Jobs -> Nodes \cup {NoNode}]
    /\ old \in [Jobs -> BOOLEAN]
    /\ up \in [Nodes -> BOOLEAN]
    /\ hb \in [Nodes -> 0..Stale]

\* REQ-036 (D-2, D-12): a running node whose heartbeat is too old is not live
Live(n) == hb[n] <= NodeTimeout

\* REQ-036
NoLiveAdvertiser == ~\E n \in Handlers : Live(n)

Init ==
    /\ state = [j \in Jobs |-> "Enqueued"]
    /\ claimer = [j \in Jobs |-> NoNode]
    /\ old = [j \in Jobs |-> FALSE]
    /\ up = [n \in Nodes |-> TRUE]
    /\ hb = [n \in Nodes |-> 0]

\* REQ-035
Claim(n, j) ==
    /\ up[n]
    /\ n \in Handlers
    /\ state[j] = "Enqueued"
    /\ state' = [state EXCEPT ![j] = "Processing"]
    /\ claimer' = [claimer EXCEPT ![j] = n]
    /\ UNCHANGED << old, up, hb >>

\* REQ-038 (reaching finished states so purge can happen)
Finish(j, outcome) ==
    /\ state[j] = "Processing"
    /\ up[claimer[j]]
    /\ state' = [state EXCEPT ![j] = outcome]
    /\ UNCHANGED << claimer, old, up, hb >>

\* REQ-036 (D-2): heartbeats age as time passes
TimePasses ==
    /\ hb' = [n \in Nodes |-> IF hb[n] < Stale THEN hb[n] + 1 ELSE Stale]
    /\ UNCHANGED << state, claimer, old, up >>

\* REQ-036
GraceExpires(j) ==
    /\ ~old[j]
    /\ old' = [old EXCEPT ![j] = TRUE]
    /\ UNCHANGED << state, claimer, up, hb >>

\* REQ-036, REQ-037
Tick(n) ==
    /\ up[n]
    /\ hb' = [hb EXCEPT ![n] = 0]
    /\ state' = IF n \in Handlers
                THEN [j \in Jobs |-> IF state[j] = "Unroutable"
                                     THEN "Enqueued" ELSE state[j]]
                ELSE state
    /\ UNCHANGED << claimer, old, up >>

\* REQ-036
Crash(n) ==
    /\ up[n]
    /\ up' = [up EXCEPT ![n] = FALSE]
    /\ UNCHANGED << state, claimer, old, hb >>

\* REQ-036
Start(n) ==
    /\ ~up[n]
    /\ up' = [up EXCEPT ![n] = TRUE]
    /\ UNCHANGED << state, claimer, old, hb >>

\* REQ-036
MarkUnroutable(r, j) ==
    /\ up[r]
    /\ Live(r)
    /\ state[j] = "Enqueued"
    /\ old[j]
    /\ NoLiveAdvertiser
    /\ state' = [state EXCEPT ![j] = "Unroutable"]
    /\ UNCHANGED << claimer, old, up, hb >>

\* REQ-038
Purge(r, j) ==
    /\ up[r]
    /\ Live(r)
    /\ state[j] \in FinalStates
    /\ state' = [state EXCEPT ![j] = "Purged"]
    /\ UNCHANGED << claimer, old, up, hb >>

Next ==
    \/ \E n \in Nodes, j \in Jobs : Claim(n, j)
    \/ \E j \in Jobs, o \in {"Succeeded", "DeadLettered"} : Finish(j, o)
    \/ TimePasses
    \/ \E j \in Jobs : GraceExpires(j)
    \/ \E n \in Nodes : Tick(n) \/ Crash(n) \/ Start(n)
    \/ \E r \in Nodes, j \in Jobs : MarkUnroutable(r, j) \/ Purge(r, j)

\* REQ-035, REQ-037: only a handling node's tick and claim must keep happening
Fairness ==
    \A n \in Handlers :
        /\ WF_vars(Tick(n))
        /\ \A j \in Jobs : WF_vars(Claim(n, j))

Spec == Init /\ [][Next]_vars /\ Fairness

\* REQ-035
NeverClaimedWithoutHandler ==
    \A j \in Jobs : claimer[j] # NoNode => claimer[j] \in Handlers

\* REQ-036
UnroutableOnlyWithoutLiveHandlerStep ==
    \A j \in Jobs :
        (state[j] # "Unroutable" /\ state'[j] = "Unroutable") => NoLiveAdvertiser
UnroutableOnlyWithoutLiveHandler == [][UnroutableOnlyWithoutLiveHandlerStep]_vars

\* REQ-036
YoungJobLeftAloneStep ==
    \A j \in Jobs :
        (state[j] # "Unroutable" /\ state'[j] = "Unroutable") => old[j]
YoungJobLeftAlone == [][YoungJobLeftAloneStep]_vars

\* REQ-038
UnfinishedNeverPurgedStep ==
    \A j \in Jobs :
        (state[j] # "Purged" /\ state'[j] = "Purged") => state[j] \in FinalStates
UnfinishedNeverPurged == [][UnfinishedNeverPurgedStep]_vars

\* REQ-036 (D-12): from some moment on, the node keeps running and ticks often
\* enough that its heartbeat is never older than the node timeout
KeepsRunningAndTicking(n) == <>[](up[n] /\ Live(n))

\* REQ-035, REQ-036 (D-12), REQ-037
HandledEventually ==
    \A n \in Handlers :
        KeepsRunningAndTicking(n) => \A j \in Jobs : <>(state[j] \in ClaimedStates)
====
