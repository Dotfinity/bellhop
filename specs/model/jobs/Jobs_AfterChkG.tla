---------------------------- MODULE Jobs_AfterChkG ----------------------------
\* Run 8 probes that need history (see Jobs_AfterChk.tla for the question).
\* Spec8 is Jobs' Spec plus one history variable (never read by an action): which runs' TimeoutGracePeriod ended
\* after ShutdownTimeout passed on their node, and which after their node's check.  Fairness is not needed: every
\* property here is a safety property.
EXTENDS Jobs_AfterChk

VARIABLE g8   \* set of <<job, token, "st" | "chk">>
vars8 == <<vars, g8>>
GraceEnds(r) == ~r.graceOver /\ \E r2 \in runs' : r2.node = r.node /\ r2.job = r.job /\ r2.token = r.token /\ r2.graceOver
Spec8 == /\ Init /\ g8 = {}
         /\ [][/\ Next
               /\ g8' = g8 \cup {<<r.job, r.token, "st">> : r \in {r \in runs : GraceEnds(r) /\ node[r.node].shutdownPassed}}
                          \cup {<<r.job, r.token, "chk">> : r \in {r \in runs : GraceEnds(r) /\ r.chk}}]_vars8

\* REQ-190's timeout branch, on the draining node, before it stops, for a grace period that ended after the check
\* (named by both notes).
Reach8_Timeout == [][\A r \in runs : ~(LateRun(r) /\ <<r.job, r.token, "chk">> \in g8' /\ AbandonOnTimeout(r))]_vars

\* REQ-140's notes: "if ShutdownTimeout passes first, lease expiry counts the attempt".  A timed-out run with no
\* cancellation request whose grace period ends after ShutdownTimeout passed but before its node stops is counted
\* by REQ-138/186 (reason Timeout) instead.  Expected VIOLATED (= reachable).
Reach8_TimeoutAfterShutdownTimeout ==
  [][\A r \in runs : ~(/\ InFlight(r) /\ ~CR(r) /\ node[r.node].st = "Draining"
                       /\ <<r.job, r.token, "st">> \in g8' /\ AbandonOnTimeout(r))]_vars
=============================================================================
