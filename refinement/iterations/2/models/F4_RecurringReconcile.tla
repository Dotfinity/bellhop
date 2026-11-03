---- MODULE F4_RecurringReconcile ----
\* PURPOSE: code-defined recurring jobs are reconciled at every node start during a
\* rolling deploy of svc1 (old code d1,d2; new code d1,d3) beside svc2 (d4), while
\* people edit, pause, resume and remove definitions at runtime.
\* ASSUMPTION: svc2 is one always-running starter outside Nodes (both Nodes run svc1); RestartSvc2 is its restart.
\* ASSUMPTION: a node start and its reconcile are one atomic store step, so concurrent reconciles never interleave.
\* ASSUMPTION: every modelled node is a worker node; client-only nodes never reconcile and are left out.
\* ASSUMPTION: only d1 changes schedule between versions (S1 in old, S2 in new); d2, d3, d4 keep S1.
\* ASSUMPTION: d1 and d2 allow runtime override, d3 and d4 do not, the same in both versions.
\* ASSUMPTION: a reconcile never touches an overridden definition's schedule, even when the code's schedule changed; it only restores it if orphaned.
\* ASSUMPTION: a reconcile of a name held by a runtime-created definition takes it over: it becomes code-defined with the code's schedule.
\* ASSUMPTION: a newly created definition, by reconcile or at runtime, has a fresh next run.
\* ASSUMPTION: pause and resume are allowed on every definition; they are not runtime edits in the sense of REQ-031.
\* ASSUMPTION: every runtime edit changes the schedule and takes a fresh next run; a runtime edit does not restore an orphaned definition.
\* ASSUMPTION: time passing makes the next run of a paused or orphaned definition stale; firing (F3) keeps an active one current, and downtime catch-up is F7.
\* ASSUMPTION: no two applications define the same name.
\* ASSUMPTION: occurrences are not modelled; nothing here deletes job rows, so REQ-033's occurrence clause has no rule.
\* ASSUMPTION: one row per name holds by construction (the store is a function of name), so REQ-028 has no separate rule.
\* ASSUMPTION: a live node is a running node (heartbeats are not modelled here); a stopped node stops counting at once.
\* ASSUMPTION: "a name its code defines" means a name in the code of a running node of any application; a name only a not-yet-running version defines can still be created at runtime.
\* ASSUMPTION: D-18 (open): runtime overrides of a definition that allows runtime override stay as REQ-031 says.
\* ASSUMPTION: D-18 (open): an orphaned definition can be removed at runtime.
EXTENDS Common, FiniteSets

Apps == {"svc1", "svc2"}
Versions == {"old", "new"}
Defs == {"d1", "d2", "d3", "d4"}
Scheds == {"S1", "S2", "Rt"}            \* "Rt": a schedule set at runtime
Owners == Apps \cup {"rt"}              \* "rt": created at runtime, not code-defined
NodeStates == Versions \cup {"down"}

CodeOf(a, v) ==
    IF a = "svc2" THEN {"d4"}
    ELSE IF v = "old" THEN {"d1", "d2"} ELSE {"d1", "d3"}

\* REQ-030
LiveCode(a, nd) ==
    IF a = "svc2" THEN CodeOf("svc2", "old")
    ELSE UNION {CodeOf("svc1", nd[m]) : m \in {k \in Nodes : nd[k] # "down"}}

\* REQ-029
CodeSched(d, v) == IF d = "d1" /\ v = "new" THEN "S2" ELSE "S1"

\* REQ-031
OverrideAllowed == {"d1", "d2"}

Rows == [ex : BOOLEAN, app : Owners, orph : BOOLEAN, ovr : BOOLEAN,
         paused : BOOLEAN, sched : Scheds, next : {"fresh", "stale"}]

Absent == [ex |-> FALSE, app |-> "rt", orph |-> FALSE, ovr |-> FALSE,
           paused |-> FALSE, sched |-> "Rt", next |-> "fresh"]

CodeRow(a, d, v) == [ex |-> TRUE, app |-> a, orph |-> FALSE, ovr |-> FALSE,
                     paused |-> FALSE, sched |-> CodeSched(d, v), next |-> "fresh"]

\* lastReconciler names the application whose reconcile made the last step, or "none".
VARIABLES def, node, lastReconciler
vars == <<def, node, lastReconciler>>

TypeOK ==
    /\ def \in [Defs -> Rows]
    /\ node \in [Nodes -> NodeStates]
    /\ lastReconciler \in Apps \cup {"none"}

Init ==
    /\ def = [d \in Defs |-> IF d = "d3" THEN Absent
                             ELSE IF d = "d4" THEN CodeRow("svc2", d, "old")
                             ELSE CodeRow("svc1", d, "old")]
    /\ node = [n \in Nodes |-> "old"]
    /\ lastReconciler = "none"

\* live: the names the running nodes of application a define after this start.
\* REQ-029, REQ-030, REQ-031, REQ-032
Reconciled(r, d, a, v, live) ==
    IF d \in CodeOf(a, v)
    THEN IF ~r.ex THEN CodeRow(a, d, v)
         ELSE IF r.ovr
              THEN [r EXCEPT !.orph = FALSE,
                             !.next = IF r.orph THEN "fresh" ELSE r.next]
              ELSE [r EXCEPT !.app = a, !.orph = FALSE, !.sched = CodeSched(d, v),
                             !.next = IF r.orph \/ r.sched # CodeSched(d, v)
                                      THEN "fresh" ELSE r.next]
    ELSE IF r.ex /\ r.app = a /\ d \notin live THEN [r EXCEPT !.orph = TRUE] ELSE r

\* REQ-028, REQ-030
Reconcile(a, v, live) == def' = [d \in Defs |-> Reconciled(def[d], d, a, v, live)]

\* REQ-034, REQ-028, REQ-030
StartNode(n, v) ==
    /\ node' = [node EXCEPT ![n] = v]
    /\ Reconcile("svc1", v, LiveCode("svc1", [node EXCEPT ![n] = v]))
    /\ lastReconciler' = "svc1"

\* REQ-034
StopNode(n) ==
    /\ node[n] # "down"
    /\ node' = [node EXCEPT ![n] = "down"]
    /\ lastReconciler' = "none"
    /\ UNCHANGED def

\* REQ-034, REQ-028
RestartSvc2 ==
    /\ Reconcile("svc2", "old", LiveCode("svc2", node))
    /\ lastReconciler' = "svc2"
    /\ UNCHANGED node

InRunningCode(a, d) == d \in LiveCode(a, node)

\* REQ-031, REQ-029
RuntimeEdit(d) ==
    /\ \/ ~def[d].ex /\ ~\E a \in Apps : InRunningCode(a, d)
       \/ def[d].ex /\ (def[d].app = "rt" \/ d \in OverrideAllowed)
    /\ def' = [def EXCEPT ![d] =
                 IF ~def[d].ex THEN [Absent EXCEPT !.ex = TRUE]
                 ELSE [def[d] EXCEPT !.sched = "Rt", !.next = "fresh",
                                     !.ovr = (def[d].app # "rt")]]
    /\ lastReconciler' = "none"
    /\ UNCHANGED node

\* REQ-031, REQ-032
Pause(d) ==
    /\ def[d].ex /\ ~def[d].paused
    /\ def' = [def EXCEPT ![d].paused = TRUE]
    /\ lastReconciler' = "none"
    /\ UNCHANGED node

\* REQ-031, REQ-032
Resume(d) ==
    /\ def[d].ex /\ def[d].paused
    /\ def' = [def EXCEPT ![d].paused = FALSE, ![d].next = "fresh"]
    /\ lastReconciler' = "none"
    /\ UNCHANGED node

\* REQ-031, REQ-033
Remove(d) ==
    /\ def[d].ex /\ (def[d].app = "rt" \/ def[d].orph)
    /\ def' = [def EXCEPT ![d] = Absent]
    /\ lastReconciler' = "none"
    /\ UNCHANGED node

\* REQ-030, REQ-032
Elapse(d) ==
    /\ def[d].ex /\ (def[d].paused \/ def[d].orph) /\ def[d].next = "fresh"
    /\ def' = [def EXCEPT ![d].next = "stale"]
    /\ lastReconciler' = "none"
    /\ UNCHANGED node

Next ==
    \/ \E n \in Nodes, v \in Versions : StartNode(n, v)
    \/ \E n \in Nodes : StopNode(n)
    \/ RestartSvc2
    \/ \E d \in Defs : RuntimeEdit(d)
    \/ \E d \in Defs : Pause(d)
    \/ \E d \in Defs : Resume(d)
    \/ \E d \in Defs : Remove(d)
    \/ \E d \in Defs : Elapse(d)

Spec == Init /\ [][Next]_vars

\* REQ-030
NeverDeletedByReconcile ==
    [][lastReconciler' # "none" => \A d \in Defs : def[d].ex => def'[d].ex]_vars

\* REQ-030
OtherAppUntouched ==
    [][\A a \in Apps : lastReconciler' = a =>
         \A d \in Defs : (def[d].ex /\ def[d].app \in Apps \ {a}) => def'[d] = def[d]]_vars

\* REQ-031
OverrideSurvives ==
    [][lastReconciler' # "none" =>
         \A d \in Defs : (def[d].ex /\ def[d].ovr) =>
                           (def'[d].ovr /\ def'[d].sched = def[d].sched)]_vars

\* REQ-029, REQ-030, REQ-032
NoCatchUpAfterRestoreOrResume ==
    [][\A d \in Defs :
         (def[d].ex /\ def'[d].ex /\
            ((def[d].orph /\ ~def'[d].orph)
             \/ (def[d].paused /\ ~def'[d].paused)
             \/ def[d].sched # def'[d].sched))
         => def'[d].next = "fresh"]_vars

\* REQ-029
UnchangedReconcileKeepsNextRun ==
    [][lastReconciler' # "none" =>
         \A d \in Defs : (def[d].ex /\ def[d].app = def'[d].app
                          /\ def[d].orph = def'[d].orph
                          /\ def[d].sched = def'[d].sched)
                         => def'[d].next = def[d].next]_vars

\* REQ-032
ReconcileKeepsPause ==
    [][lastReconciler' # "none" =>
         \A d \in Defs : def[d].ex => def'[d].paused = def[d].paused]_vars

\* REQ-031
CodeOnlyNamesKeepCodeSchedule ==
    \A d \in Defs \ OverrideAllowed :
        (def[d].ex /\ \E a \in Apps : InRunningCode(a, d)) => def[d].sched # "Rt"

\* REQ-030
RunningCodeKeepsItsJobs ==
    \A d \in Defs :
        (def[d].ex /\ def[d].app \in Apps /\ InRunningCode(def[d].app, d)) => ~def[d].orph

\* S2 is only ever written by a new-version reconcile, and a new-version reconcile
\* always keeps it, so this checks old-version reconciles.
\* MODELING
NewScheduleNotReverted ==
    [][(lastReconciler' = "svc1" /\ def["d1"].sched = "S2"
        /\ \E m \in Nodes : node'[m] = "new")
       => def'["d1"].sched = "S2"]_vars
====
