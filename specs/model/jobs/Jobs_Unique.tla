---------------------------- MODULE Jobs_Unique ----------------------------
\* Generated from specs/jobs.json — edit the requirements, not this file.
\* Scope: FEAT-103 uniqueness (REQ-107, REQ-150, REQ-151, REQ-152, INV-100, INV-135, SCN-105)
\*        and the unique-key side of requeue (REQ-141, REQ-142, REQ-143, INV-129).
\* Execution is abstracted to one step per outcome; leases, nodes and timeouts are in Jobs.tla.
EXTENDS Naturals, FiniteSets

CONSTANTS Jobs,       \* Job slots (entity.bound = 3)
          Kinds,      \* creation calls the run may use: subset of {"enqueue","schedule","schedulePast","continue"}
          Policies,   \* duplicate policies the run may use: subset of {"Ignore","Error","ReplaceSchedule"}
          BulkOn      \* whether the bulk requeue (REQ-142) is used in this run

VARIABLES job, lastCall
vars == <<job, lastCall>>

Status == {"none", "Scheduled", "Enqueued", "Processing", "Succeeded", "Failed", "DeadLettered",
           "Cancelled", "Awaiting", "Unroutable"}
\* @req REQ-107  active states for uniqueness
ActiveSt == {"Scheduled", "Enqueued", "Processing", "Awaiting", "Failed", "Unroutable"}
Finished == {"Succeeded", "Cancelled", "DeadLettered"}
CallResult == {"none", "created", "duplicate", "rejected", "replaced", "unchanged"}

TypeInv ==
  /\ job \in [Jobs -> [status: Status, keyed: BOOLEAN]]
  /\ lastCall \in CallResult

Init == job = [j \in Jobs |-> [status |-> "none", keyed |-> FALSE]] /\ lastCall = "none"

KeyHeld(j) == \E e \in Jobs : e # j /\ job[e].keyed /\ job[e].status \in ActiveSt
Holder == {e \in Jobs : job[e].keyed /\ job[e].status \in ActiveSt}
Set(j, st) == job' = [job EXCEPT ![j].status = st]

Target(kind) == CASE kind = "enqueue"      -> "Enqueued"     \* REQ-120
                  [] kind = "schedule"     -> "Scheduled"    \* REQ-121
                  [] kind = "schedulePast" -> "Enqueued"     \* REQ-182
                  [] kind = "continue"     -> "Awaiting"     \* REQ-170

\* One creation call.  The duplicate rules are applied exactly where their sentences apply; a
\* combination no sentence covers falls through to the plain creation requirement (REQ-120/121/170/182).
\* @req REQ-120 REQ-121 REQ-170 REQ-182 REQ-150 REQ-151 REQ-152 INV-135
Create(j, kind, keyed, pol) ==
  /\ job[j].status = "none"
  /\ IF keyed /\ Holder # {}
       THEN CASE kind = "enqueue" /\ pol = "Ignore"
                   -> job' = job /\ lastCall' = "duplicate"                         \* REQ-150
              [] kind = "enqueue" /\ pol = "Error"
                   -> job' = job /\ lastCall' = "rejected"                          \* REQ-152
              [] kind \in {"schedule", "schedulePast"} /\ pol = "ReplaceSchedule"
                   /\ \E e \in Holder : job[e].status = "Scheduled"
                   -> job' = job /\ lastCall' = "replaced"                          \* REQ-151
              [] kind \in {"schedule", "schedulePast"} /\ pol = "ReplaceSchedule"
                   -> job' = job /\ lastCall' = "unchanged"                         \* INV-135
              [] OTHER
                   -> job' = [job EXCEPT ![j] = [status |-> Target(kind), keyed |-> TRUE]]
                      /\ lastCall' = "created"                                      \* no duplicate rule applies
       ELSE job' = [job EXCEPT ![j] = [status |-> Target(kind), keyed |-> keyed]] /\ lastCall' = "created"

\* Abstract lifecycle (system / handler / environment); details in Jobs.tla and Jobs_Flow.tla.
Promote(j)    == job[j].status = "Scheduled" /\ Set(j, "Enqueued")                       \* REQ-122
Claim(j)      == job[j].status = "Enqueued" /\ Set(j, "Processing")                      \* REQ-123
Outcome(j)    == job[j].status = "Processing"
                 /\ \E st \in {"Succeeded", "Failed", "DeadLettered", "Cancelled", "Enqueued"} : Set(j, st)
                 \* REQ-127 REQ-129 REQ-131 REQ-136 REQ-132/REQ-140 (back to Enqueued)
Retry(j)      == job[j].status = "Failed" /\ Set(j, "Enqueued")                          \* REQ-130
Unroutable(j) == job[j].status = "Enqueued" /\ Set(j, "Unroutable")                      \* REQ-124
Routable(j)   == job[j].status = "Unroutable" /\ Set(j, "Enqueued")                      \* REQ-125
Release(j)    == job[j].status = "Awaiting" /\ \E st \in {"Enqueued", "Cancelled"} : Set(j, st)  \* REQ-171..174
Cancel(j)     == job[j].status \in {"Scheduled", "Enqueued", "Awaiting", "Failed", "Unroutable"}
                 /\ Set(j, "Cancelled")                                                  \* REQ-134
Remove(j)     == job[j].status \in Finished /\ job' = [job EXCEPT ![j] = [status |-> "none", keyed |-> FALSE]]
                 \* REQ-144 REQ-145

\* @req REQ-141 REQ-143 INV-129  single requeue: finished job, unique key not held by another active job.
Requeue(j) ==
  /\ job[j].status \in Finished
  /\ ~(job[j].keyed /\ KeyHeld(j))
  /\ Set(j, "Enqueued")

\* @req REQ-142  bulk requeue: each matching dead letter in its own atomic step; skipped only when
\*               "their state changed meanwhile".
BulkRequeueOne(j) ==
  /\ BulkOn
  /\ job[j].status = "DeadLettered"
  /\ Set(j, "Enqueued")

Next ==
  \/ \E j \in Jobs, k \in Kinds, key \in BOOLEAN, p \in Policies : Create(j, k, key, p)
  \/ \E j \in Jobs :
       /\ \/ Promote(j) \/ Claim(j) \/ Outcome(j) \/ Retry(j) \/ Unroutable(j) \/ Routable(j)
          \/ Release(j) \/ Cancel(j) \/ Remove(j) \/ Requeue(j) \/ BulkRequeueOne(j)
       /\ UNCHANGED lastCall

Spec == Init /\ [][Next]_vars

\* @req INV-100  never two active jobs with the same unique key.
Inv_UniqueKey == Cardinality(Holder) <= 1

\* @req SCN-105  positive: the second enqueue returns the existing id with WasDuplicate (trap, expected VIOLATED).
Scn105_NotReached == ~(lastCall = "duplicate" /\ Cardinality(Holder) = 1)
=============================================================================
