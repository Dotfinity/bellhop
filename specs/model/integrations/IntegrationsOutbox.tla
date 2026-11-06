-------------------------- MODULE IntegrationsOutbox --------------------------
\* Generated from integrations.json (specHash 3b92b190e27a) — FEAT-402 Outbox.
\* Edit the requirements, not this file. Every action/property carries an @req comment.
\* Run 2 (handoff): REQ-432 (outboxId is the job id, checked against every stored job), REQ-435 (relay
\* lease takeover), REQ-436 (retention assumption), LIV-400 and SCN-403 changed or added. Run 1's
\* KeyScope and LeaseTakeover switches are now fixed by the requirements.
\*   RetentionAssumption : REQ-436 as a guard — retention never removes a job while the outbox row it was
\*                         created from is still pending. FALSE shows what the assumption protects.
\*   OperatorDelete      : jobs REQ-144 (an operator deletes a job) is possible in the crash window.
EXTENDS Naturals

CONSTANTS Rows,                \* OutboxRow slots (outboxIds)
          Nodes,               \* worker nodes that can run the relay (hosting REQ-40)
          RetentionAssumption,
          OperatorDelete,
          MaxCrashes,          \* relay crashes in one behaviour (assumption A-10)
          MaxPauses,           \* relay lease expiries under a live holder (A-12)
          NULL

ASSUME RetentionAssumption \in BOOLEAN /\ OperatorDelete \in BOOLEAN
ASSUME MaxCrashes \in Nat /\ MaxPauses \in Nat

\* Job abstraction (jobs module): the job's id is the row's outboxId, so one job slot per row.
\* "Active" = Scheduled/Enqueued/Processing/Failed/Awaiting; "Finished" = Succeeded/DeadLettered/
\* Cancelled; "none" = never stored or removed (retention REQ-145 or operator delete REQ-144).
RowStatus == {"none", "uncommitted", "Pending", "rolledBack", "deleted"}
JobStatus == {"none", "Active", "Finished"}

VARIABLES row, job, created, holder, step, crashes, pauses, midCrash
vars == <<row, job, created, holder, step, crashes, pauses, midCrash>>

TypeInv ==
  /\ row      \in [Rows -> RowStatus]
  /\ job      \in [Rows -> JobStatus]       \* job with id = outboxId
  /\ created  \in [Rows -> 0..2]            \* history: jobs ever created from the row (capped)
  /\ holder   \in Nodes \cup {NULL}         \* relay lease
  /\ step     \in [Nodes -> [phase: {"idle", "enqueued"}, row: Rows \cup {NULL}]]
  /\ crashes  \in 0..MaxCrashes
  /\ pauses   \in 0..MaxPauses
  /\ midCrash \in BOOLEAN                   \* history: a relay stopped between enqueue and delete

Init ==
  /\ row      = [o \in Rows |-> "none"]
  /\ job      = [o \in Rows |-> "none"]
  /\ created  = [o \in Rows |-> 0]
  /\ holder   = NULL
  /\ step     = [n \in Nodes |-> [phase |-> "idle", row |-> NULL]]
  /\ crashes  = 0
  /\ pauses   = 0
  /\ midCrash = FALSE

Min(a, b) == IF a < b THEN a ELSE b

\* @req REQ-430  Outbox mode: dbContext.EnqueueAsync writes the job as an outbox row in the
\*               application's DbContext; it commits or rolls back with the application's transaction.
AppWritesRow(o) ==
  /\ row[o] = "none"
  /\ row' = [row EXCEPT ![o] = "uncommitted"]
  /\ UNCHANGED <<job, created, holder, step, crashes, pauses, midCrash>>

\* @req REQ-430  (same transaction, outcome decided by the application)
AppEndsTransaction(o) ==
  /\ row[o] = "uncommitted"
  /\ \E r \in {"Pending", "rolledBack"} : row' = [row EXCEPT ![o] = r]
  /\ UNCHANGED <<job, created, holder, step, crashes, pauses, midCrash>>

\* @req REQ-435  No running worker node holds an unexpired relay lease: one takes it.
AcquireRelayLease(n) ==
  /\ holder = NULL
  /\ holder' = n
  /\ UNCHANGED <<row, job, created, step, crashes, pauses, midCrash>>

\* @req REQ-432  (first half) The lease holder processes its next batch: enqueue the row's job with the
\*               outboxId as its job id, creating nothing if a job with that id is still stored in any state.
RelayEnqueues(n, o) ==
  /\ holder = n
  /\ step[n].phase = "idle"
  /\ row[o] = "Pending"
  /\ IF job[o] # "none"
       THEN UNCHANGED <<job, created>>
       ELSE /\ job' = [job EXCEPT ![o] = "Active"]
            /\ created' = [created EXCEPT ![o] = Min(@ + 1, 2)]
  /\ step' = [step EXCEPT ![n] = [phase |-> "enqueued", row |-> o]]
  /\ UNCHANGED <<row, holder, crashes, pauses, midCrash>>

\* @req REQ-432  (second half) ... and then delete the row. A node that lost the lease under a pause still
\*               finishes its in-memory step (the sentence does not fence the delete; it is idempotent).
RelayDeletes(n) ==
  /\ step[n].phase = "enqueued"
  /\ row' = [row EXCEPT ![step[n].row] = "deleted"]
  /\ step' = [step EXCEPT ![n] = [phase |-> "idle", row |-> NULL]]
  /\ UNCHANGED <<job, created, holder, crashes, pauses, midCrash>>

\* @req INV-406  environment: the relay's node crashes; it loses the lease and its in-memory progress.
RelayCrashes(n) ==
  /\ holder = n
  /\ crashes < MaxCrashes
  /\ holder' = NULL
  /\ step' = [step EXCEPT ![n] = [phase |-> "idle", row |-> NULL]]
  /\ crashes' = crashes + 1
  /\ midCrash' = (midCrash \/ step[n].phase = "enqueued")
  /\ UNCHANGED <<row, job, created, pauses>>

\* Environment (A-12): the holder misses a renewal; its lease expires but it keeps running.
RelayLeasePauses(n) ==
  /\ holder = n
  /\ pauses < MaxPauses
  /\ holder' = NULL
  /\ pauses' = pauses + 1
  /\ midCrash' = (midCrash \/ step[n].phase = "enqueued")
  /\ UNCHANGED <<row, job, created, step, crashes>>

\* jobs module (abstracted): the job runs to an end state.
JobFinishes(o) ==
  /\ job[o] = "Active"
  /\ job' = [job EXCEPT ![o] = "Finished"]
  /\ UNCHANGED <<row, created, holder, step, crashes, pauses, midCrash>>

\* jobs REQ-145 retention cleanup (time abstracted, A-3).
\* @req REQ-436  Retention is much longer than LeaseDuration: it never removes the job while the row it
\*               came from is still pending (a crashed relay is replaced first).
RetentionRemoves(o) ==
  /\ job[o] = "Finished"
  /\ RetentionAssumption => row[o] # "Pending"
  /\ job' = [job EXCEPT ![o] = "none"]
  /\ UNCHANGED <<row, created, holder, step, crashes, pauses, midCrash>>

\* jobs REQ-144: an operator deletes the job (any state) from the dashboard or the API.
OperatorDeletes(o) ==
  /\ OperatorDelete
  /\ job[o] # "none"
  /\ job' = [job EXCEPT ![o] = "none"]
  /\ UNCHANGED <<row, created, holder, step, crashes, pauses, midCrash>>

Next ==
  \/ \E o \in Rows : AppWritesRow(o) \/ AppEndsTransaction(o) \/ JobFinishes(o)
                     \/ RetentionRemoves(o) \/ OperatorDeletes(o)
  \/ \E n \in Nodes : \/ AcquireRelayLease(n) \/ RelayDeletes(n) \/ RelayCrashes(n) \/ RelayLeasePauses(n)
                      \/ \E o \in Rows : RelayEnqueues(n, o)

\* The relay and the lease takeover are system duties: fair (REQ-432, REQ-435).
Fairness ==
  \A n \in Nodes : /\ WF_vars(RelayDeletes(n)) /\ WF_vars(\E o \in Rows : RelayEnqueues(n, o))
                   /\ WF_vars(AcquireRelayLease(n))

Spec == Init /\ [][Next]_vars /\ Fairness

\* @req INV-406  Never more than one job from the same outbox row, even across a relay crash.
Inv_OneJobPerRow == \A o \in Rows : created[o] <= 1

\* @req LIV-400  (should) While a row is pending and a worker node runs: eventually its job is enqueued
\*               and the row deleted.
Liv_RowRelayed == \A o \in Rows : (row[o] = "Pending") ~> (row[o] = "deleted" /\ created[o] >= 1)

\* @req SCN-403  Trap for IntegrationsOutbox_SCN403.cfg (expected to be VIOLATED): the relay stopped
\*               between enqueue and delete, and still exactly one job exists for o1 and o1 is gone.
Scn403_NotReached ==
  ~(\E o \in Rows : midCrash /\ row[o] = "deleted" /\ created[o] = 1)
=============================================================================
