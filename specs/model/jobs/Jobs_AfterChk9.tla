---------------------------- MODULE Jobs_AfterChk9 ----------------------------
\* Run 9 probes over the unchanged Jobs.tla and Jobs_AfterChk.tla (no action, guard or property is changed).
\* Question: REQ-190's and hosting REQ-29's notes (commit 24b1e08) say that for a cancellation requested after the
\* draining node's check, "the handler's own outcome [decides] until the node stops and lease expiry (REQ-132,
\* REQ-133) after it".  Which lease-expiry rule decides such a job, and can lease expiry decide it before the stop?
\* Both properties are expected VIOLATED (= reachable).  Needs MaxAttempts = 2 (attempts left).
EXTENDS Jobs_AfterChk

\* After the stop: the node stopped with the post-check cancel-requested run in flight (DrainLeftCancel), then a
\* running worker node recovered the expired lease.  The rule that applies is REQ-190's lease branch (Cancelled,
\* LeaseCancel), never REQ-132, whose while needs "its cancellation was not requested".
Reach9_LeaseAfterStop ==
  ~\E j \in Jobs : /\ job[j].status = "Cancelled" /\ {"DrainLeftCancel", "LeaseCancel"} \subseteq job[j].hist
                   /\ job[j].attempt < MaxAttempts

\* Before the stop: the lease expires while the draining node still holds the run (A-2: pause or partition) and
\* another running worker node recovers it.  Chk8_Exits already lists this exit; this shows it is reachable.
Reach9_LeaseBeforeStop == [][\A r \in runs : ~(LateRun(r) /\ \E n \in Nodes : Recover(n, r.job))]_vars
=============================================================================
