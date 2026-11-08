---------------------------- MODULE Jobs_AfterChk ----------------------------
\* Run 8 probes over the unchanged Jobs.tla (no action, guard or property of Jobs.tla is changed or added to).
\* Question: once a draining node's check (REQ-140, REQ-190) has left a timed-out run in flight and a
\* cancellation is then requested, which rules can settle that run before the node stops?  REQ-190's notes
\* name the timeout branch and lease expiry; hosting REQ-29's notes name REQ-190's timeout branch, REQ-136 and
\* lease expiry.  Each Reach8_ property is expected VIOLATED (= reachable); Chk8_Exits is expected to hold.
\* The two timeout probes need a history variable and are in Jobs_AfterChkG.tla.
EXTENDS Jobs

\* A run the check left on its timeout path (chk is set only by ShutdownCheckLeaves, which needs no request),
\* whose cancellation was requested afterwards, still holding its job's lease on its draining node.
LateRun(r) == r.chk /\ CR(r) /\ InFlight(r) /\ node[r.node].st = "Draining"

\* The same run is still in that situation after the step (a step may rewrite the run record, e.g. GracePasses).
StillLate(r) == \E r2 \in runs' : /\ r2.node = r.node /\ r2.job = r.job /\ r2.token = r.token
                                  /\ r2.chk /\ r2.mode = "running"
                                  /\ job'[r.job].status = "Processing" /\ job'[r.job].token = r.token
                                  /\ job'[r.job].cancelReq /\ node'[r.node].st = "Draining"

\* REQ-136: the handler honours the token that REQ-135 signalled (named by hosting REQ-29's note only).
Reach8_OCE == [][\A r \in runs : ~(LateRun(r) /\ HandlerThrows(r, "oce") /\ job'[r.job].status = "Cancelled")]_vars
\* REQ-127: the handler returns normally (named by neither note; REQ-136's notes: "a normal return still marks it
\* succeeded").
Reach8_Return == [][\A r \in runs : ~(LateRun(r) /\ HandlerReturns(r) /\ job'[r.job].status = "Succeeded")]_vars
\* REQ-190's exception branch with attempts left (named by neither note).  Needs MaxAttempts = 2.
Reach8_ExcCancelled ==
  [][\A r \in runs : ~(LateRun(r) /\ HandlerThrows(r, "retryable") /\ job'[r.job].status = "Cancelled")]_vars
\* REQ-131 at the last attempt or for a permanent failure: dead-lettered as a failure, not by lease expiry
\* (named by neither note).
Reach8_ExcDeadLettered ==
  [][\A r \in runs : ~(LateRun(r) /\ \E e \in {"retryable", "permanent"} : HandlerThrows(r, e)
                       /\ job'[r.job].status = "DeadLettered")]_vars

\* Every step that ends LateRun(r) is one of these: a handler outcome (abandonment after the grace period,
\* a throw, a normal return), lease expiry recovered by a running worker node (REQ-190's lease branch, REQ-132/133), the node's stop (hosting REQ-29) or a crash.
Chk8_Exits ==
  [][\A r \in runs : (LateRun(r) /\ ~StillLate(r)) =>
        \/ AbandonOnTimeout(r)
        \/ \E e \in {"retryable", "permanent", "oce"} : HandlerThrows(r, e)
        \/ HandlerReturns(r)
        \/ \E n \in Nodes : Recover(n, r.job)
        \/ NodeStop(r.node)
        \/ Crash(r.node)]_vars

=============================================================================
