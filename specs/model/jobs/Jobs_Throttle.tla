--------------------------- MODULE Jobs_Throttle ---------------------------
\* Generated from specs/jobs.json — edit the requirements, not this file.
\* Scope: FEAT-104 claim order and throttling: REQ-123 (guards), REQ-156, REQ-158, INV-107, INV-108,
\*        INV-109, INV-110, INV-111, INV-112, LIV-100.  The worker slots are one node's (INV-112 is per node).  One cluster-wide pool of worker slots, one worker
\*        serving the ordered queue list <<q1, q2>> with strict priority (INV-110 default).
\*        Leases, nodes and cancellation are in Jobs.tla.
EXTENDS Naturals, FiniteSets, Sequences

CONSTANTS Jobs,
          InQ2,        \* jobs in queue q2 (the rest are in q1); the worker lists <<q1, q2>>
          HighPri,     \* jobs with priority 1 (the rest have the default 0, REQ-108)
          Keyed,       \* jobs carrying the concurrency key tenant:7
          Rated,       \* jobs carrying the rate-limit key
          Slots,       \* free worker slots across the cluster (REQ-106 / INV-106 abstracted)
          QLimit1,     \* concurrency limit of queue q1 (INV-107); 0 = no limit
          MaxValues,   \* values an operator may set for the key's Max (REQ-158)
          RateValues,  \* values an operator may set for N executions per window (REQ-158)
          Outcomes,    \* run outcomes used: {"Succeeded"} keeps retries (bounded by MaxAttempts, not modeled here) out of lassos
          LongRun,     \* jobs tagged LongRunning
          LRLimit      \* the node's LongRunning limit (INV-112); 0 = none configured

VARIABLES status, order, keyMax, rateN, started
vars == <<status, order, keyMax, rateN, started>>

St == {"none", "Enqueued", "Processing", "Succeeded", "Failed"}

TypeInv ==
  /\ status \in [Jobs -> St]
  /\ order \in Seq(Jobs)
  /\ keyMax \in MaxValues /\ rateN \in RateValues
  /\ started \in Nat

Init ==
  /\ status = [j \in Jobs |-> "none"]
  /\ order = <<>>
  /\ keyMax \in MaxValues /\ rateN \in RateValues
  /\ started = 0

QIdx(j)   == IF j \in InQ2 THEN 2 ELSE 1
Pri(j)    == IF j \in HighPri THEN 1 ELSE 0
Pos(j)    == CHOOSE i \in 1..Len(order) : order[i] = j
Holding   == Cardinality({j \in Jobs : status[j] = "Processing" /\ j \in Keyed})
Busy      == Cardinality({j \in Jobs : status[j] = "Processing"})
InQ1Proc  == Cardinality({j \in Jobs : status[j] = "Processing" /\ QIdx(j) = 1})
LRProc    == Cardinality({j \in Jobs : status[j] = "Processing" /\ j \in LongRun})
Remove(s, j) == SelectSeq(s, LAMBDA x : x # j)

\* @req REQ-123 REQ-156  "an active queue that is below its concurrency limit … its concurrency key and
\*                      rate limit admit it and, for a job tagged LongRunning, the node is below its LongRunning limit"
Admitted(j) == /\ (j \in Keyed => Holding < keyMax)
               /\ (j \in Rated => started < rateN)
               /\ (QIdx(j) = 1 /\ QLimit1 > 0 => InQ1Proc < QLimit1)
               /\ (j \in LongRun /\ LRLimit > 0 => LRProc < LRLimit)
Claimable(j) == status[j] = "Enqueued" /\ Admitted(j)

\* @req INV-110 INV-111  a should be claimed before b: earlier queue in the worker's list; same queue:
\*                       higher priority, then enqueue order.
Before(a, b) == \/ QIdx(a) < QIdx(b)
                \/ QIdx(a) = QIdx(b) /\ (Pri(a) > Pri(b) \/ (Pri(a) = Pri(b) /\ Pos(a) < Pos(b)))

\* @req REQ-123  claim the next admitted job by queue order and priority when a worker slot is free.
\* @req INV-109  every start counts against the window.
Claim(j) ==
  /\ Claimable(j)
  /\ ~\E a \in Jobs : a # j /\ Claimable(a) /\ Before(a, j)
  /\ Busy < Slots
  /\ status' = [status EXCEPT ![j] = "Processing"]
  /\ order' = Remove(order, j)
  /\ started' = IF j \in Rated THEN started + 1 ELSE started
  /\ UNCHANGED <<keyMax, rateN>>

\* @req REQ-120  the application enqueues (again) — not obliged, so not fair.
Enqueue(j) ==
  /\ status[j] = "none"
  /\ status' = [status EXCEPT ![j] = "Enqueued"] /\ order' = Append(order, j)
  /\ UNCHANGED <<keyMax, rateN, started>>

\* REQ-127 / REQ-129 / REQ-138: every run ends (timeout, REQ-137/REQ-189) — A-7: modeled as fair.
Finish(j) ==
  /\ status[j] = "Processing"
  /\ \E o \in Outcomes : status' = [status EXCEPT ![j] = o]
  /\ UNCHANGED <<order, keyMax, rateN, started>>

\* @req REQ-130  retry: back in the queue behind what is there (A-8: a retry is a new enqueue for order).
Retry(j) ==
  /\ status[j] = "Failed"
  /\ status' = [status EXCEPT ![j] = "Enqueued"] /\ order' = Append(order, j)
  /\ UNCHANGED <<keyMax, rateN, started>>

\* @req REQ-145  retention frees the slot (A-1).
Retention(j) ==
  /\ status[j] = "Succeeded"
  /\ status' = [status EXCEPT ![j] = "none"]
  /\ UNCHANGED <<order, keyMax, rateN, started>>

\* modeling artefact: a fixed rate-limit window ends (A-9).
WindowRolls == started > 0 /\ started' = 0 /\ UNCHANGED <<status, order, keyMax, rateN>>

\* @req REQ-158  operator changes Max / N; running jobs untouched, following claims use it.
SetLimits ==
  /\ \E m \in MaxValues, n \in RateValues : (m # keyMax \/ n # rateN) /\ keyMax' = m /\ rateN' = n
  /\ UNCHANGED <<status, order, started>>

Next ==
  \/ \E j \in Jobs : Claim(j) \/ Enqueue(j) \/ Finish(j) \/ Retry(j) \/ Retention(j)
  \/ WindowRolls \/ SetLimits

Fairness ==
  /\ \A j \in Jobs : WF_vars(Claim(j)) /\ WF_vars(Finish(j)) /\ WF_vars(Retry(j)) /\ WF_vars(Retention(j))
  /\ WF_vars(WindowRolls)

Spec == Init /\ [][Next]_vars /\ Fairness

\* @req INV-108  never admit a claim that would make more jobs with the key processing than its Max at the
\*               time of the claim (action property).
Prop_KeyMaxAtClaim ==
  [][\A j \in Keyed : (status[j] # "Processing" /\ status'[j] = "Processing") => Holding' <= keyMax]_vars
\* @req INV-109  never start a job with the key when N have already started in the current window.
Prop_RateAtStart ==
  [][\A j \in Rated : (status[j] # "Processing" /\ status'[j] = "Processing") => started < rateN]_vars
\* @req INV-112  never more LongRunning jobs at once on the node than its limit.
Inv_LongRunning == LRLimit > 0 => LRProc <= LRLimit

\* Former readings of INV-108 / INV-109 (run 1, F-1): state invariants that a lowered limit breaks.
\* Expected VIOLATED after REQ-158 lowers a limit; kept to show that the new wording is what holds.
Chk_KeyMaxState == Holding <= keyMax
Chk_RateState   == started <= rateN
\* @req INV-107  never more processing jobs from q1 than its limit.
Inv_QueueLimit == QLimit1 > 0 => InQ1Proc <= QLimit1

\* @req LIV-100  (should) an enqueued job in an active queue served by a running worker is eventually claimed.
\*               Queue active, maintenance off and a serving worker are constant in this model.
Liv_EventuallyClaimed == \A j \in Jobs : status[j] = "Enqueued" ~> status[j] = "Processing"
=============================================================================
