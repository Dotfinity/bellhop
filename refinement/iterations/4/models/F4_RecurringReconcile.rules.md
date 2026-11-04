# F4 Recurring definitions and reconciliation

Covers: every node start reconciles its application's code-defined recurring jobs with the store, during a rolling deploy of svc1 (old version defines d1 and d2, new version defines d1 and d3, d1's schedule changes) beside svc2 (defines d4), while people edit, pause, resume and remove jobs at runtime. Either svc1 version may start or restart on either node at any time, and svc2 may restart at any time. A reconcile orphans a job only when no live node of its application still defines it (D-9), and cleanup applies the same rule at any moment (D-20), but only to an application with at least one live node (D-22). A node that stops gracefully stops counting as live at once; a node that crashes leaves a row that keeps counting until its heartbeat ages out. At runtime a code-defined job can only be paused or resumed, plus a schedule override where the job allows it; removing it, or creating a job under a name running code defines, is refused (D-10); an orphaned job can be removed (D-18). REQ-028 ("one row each, none fails") is covered by each reconcile being one atomic step on a store that holds one row per name, not by a separate rule. REQ-033's "keeps its existing occurrences" has no rule: occurrences are not modelled and nothing in this feature deletes them.

## Rules

- NeverDeletedByReconcile (each step): A reconcile never deletes a recurring job. REQ-030
- OtherAppUntouched (each step): A reconcile by one application never orphans or changes another application's recurring jobs. REQ-030
- OverrideSurvives (each step): A recurring job changed at runtime under an allowed override keeps its runtime schedule, and stays overridden, through every reconcile and restart. REQ-031
- NoCatchUpAfterRestoreOrResume (each step): A recurring job that comes back from orphaned, is resumed, or gets a new schedule always gets a next run time in the future, never one left over from the past. REQ-029, REQ-030, REQ-032
- UnchangedReconcileKeepsNextRun (each step): A reconcile that leaves a recurring job's schedule, owner and orphaned mark as they were leaves its next run time alone. REQ-029
- ReconcileKeepsPause (each step): A reconcile never pauses or resumes a recurring job. REQ-032
- CodeOnlyNamesKeepCodeSchedule (always): A recurring job whose name is in a running application's code without allowing runtime override never runs on a schedule set at runtime. REQ-031
- RunningCodeKeepsItsJobs (always): A code-defined recurring job that is in the code of at least one live node of its application is never orphaned. REQ-030
- RemovedJobOrphanedAfterDeploy (eventually): A code-defined recurring job of a running application that no live node of it defines any more is eventually orphaned, unless a node that defines it starts again, even when a node crashed during the deploy. REQ-030 (D-20)
- DownAppKeepsItsJobs (each step): While every node of an application is down, cleanup doesn't orphan that application's recurring jobs, so their catch-up after downtime still happens when it comes back. REQ-030 (D-22), REQ-042

Iteration 2's NewScheduleNotReverted is no longer checked: D-19 accepted that during a rolling deploy a schedule follows the version that started last.

Steps the check assumes keep happening (weak fairness): cleanup's orphaning sweep (D-20).

## Assumptions

- svc2 is one always-running starter outside Nodes (both Nodes run svc1); RestartSvc2 is its restart. REQ-034
- A node start and its reconcile are one atomic store step, so concurrent reconciles never interleave. REQ-028, REQ-034
- Every modelled node is a worker node; client-only nodes never reconcile and are left out. REQ-034
- Only d1 changes schedule between versions (S1 in old, S2 in new); d2, d3 and d4 keep S1. REQ-029
- d1 and d2 allow runtime override, d3 and d4 do not, the same in both versions. REQ-031
- A reconcile never touches an overridden job's schedule, even when the code's schedule changed; it only restores it if orphaned. REQ-029, REQ-031
- A reconcile of a name held by a runtime-created job takes it over: it becomes code-defined with the code's schedule. REQ-030, REQ-031
- A newly created job, by reconcile or at runtime, has a fresh next run. REQ-029
- Pause and resume are allowed on every job; they are not runtime edits in the sense of REQ-031. REQ-031, REQ-032
- Every runtime edit changes the schedule and takes a fresh next run; a runtime edit does not restore an orphaned job. REQ-029, REQ-031
- Time passing makes the next run of a paused or orphaned job stale; firing (F3) keeps an active one current, and downtime catch-up is F7. REQ-029, REQ-032
- No two applications define the same name. REQ-030
- Occurrences are not modelled; nothing here deletes job rows, so REQ-033's occurrence clause has no rule. REQ-033
- One row per name holds by construction (the store is a function of name), so REQ-028 has no separate rule. REQ-028
- A node stopped gracefully stops counting as live at once, since its row is deleted; a crashed node's row keeps advertising its code until its heartbeat ages out, which can happen at any moment. REQ-030, REQ-036
- Cleanup runs the orphaning rule at any moment and keeps doing so, only for an application with at least one live node (D-22); which node holds its lease is F6. REQ-030
- A schedule that differs between versions follows the version that started last (D-19, accepted). No rule checks it, and the next run's instant isn't modelled, so REQ-029's same-instant clause has no rule. REQ-029, REQ-034
- "A name its code defines" means a name in the code of a running node of any application; a name only a not-yet-running version defines can still be created at runtime. REQ-031

## Lifecycle

One recurring job, as the model allows it. Paused and orphaned are marks that combine with the other boxes: a paused job can still be orphaned or restored by a reconcile, and Resume returns it to the box it was in. An overridden job that is orphaned and restored comes back overridden. Only a runtime-created or orphaned job can be removed, so a paused job can be removed only when it is one of those.

```mermaid
stateDiagram-v2
    [*] --> Active
    [*] --> Absent
    Absent --> Active: StartNode / RestartSvc2 (name in that code)
    Absent --> RuntimeDefined: RuntimeEdit (name in no running code)
    RuntimeDefined --> RuntimeDefined: RuntimeEdit
    RuntimeDefined --> Active: StartNode / RestartSvc2 (takes the name over)
    Active --> Active: StartNode (schedule change, fresh next run; an old-version start puts the old schedule back)
    Active --> Overridden: RuntimeEdit (override allowed)
    Overridden --> Overridden: RuntimeEdit / StartNode (code schedule ignored)
    Active --> Orphaned: StartNode / CleanupSweep (name in no live node's code)
    Overridden --> Orphaned: StartNode / CleanupSweep (name in no live node's code)
    Orphaned --> Orphaned: Elapse (next run goes stale) / RuntimeEdit (override allowed)
    Orphaned --> Active: StartNode (restored, fresh next run)
    Orphaned --> Overridden: StartNode (restored, was overridden)
    Active --> Paused: Pause
    Overridden --> Paused: Pause
    Orphaned --> Paused: Pause
    RuntimeDefined --> Paused: Pause
    Paused --> Paused: Elapse / StartNode / RestartSvc2
    Paused --> Active: Resume (fresh next run)
    Orphaned --> Absent: Remove
    RuntimeDefined --> Absent: Remove
    Paused --> Absent: Remove (runtime-created or orphaned only)
```
