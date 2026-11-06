-------------------------- MODULE IntegrationsOutbox --------------------------
\* Generated from integrations.json (specHash 1ada134dcb35) — FEAT-402 Outbox.
\* Edit the requirements, not this file. Every action/property carries an @req comment.
\*
\* KeyScope: what "keyed by the row's outboxId so a repeated relay creates no second job" (REQ-432)
\* compares against — the requirement does not say (finding F-11):
\*   "activeUniqueKey" : a jobs-module unique key, held only while the job is active (jobs REQ-107, REQ-150)
\*   "anyStoredJob"    : any job still in the store with that key, finished or not, until retention removes it
\* LeaseTakeover: whether a worker node is obliged to take a free relay lease (no requirement says so, F-12).
EXTENDS Naturals

CONSTANTS Rows,         \* OutboxRow slots (outboxIds)
          Nodes,        \* worker nodes that can run the relay (hosting REQ-40)
          JobIds,       \* job-store slots
          KeyScope,
          LeaseTakeover,
          MaxCrashes,   \* relay crashes in one behaviour (assumption A-10)
          NULL

ASSUME KeyScope \in {"activeUniqueKey", "anyStoredJob"}
ASSUME LeaseTakeover \in BOOLEAN
ASSUME MaxCrashes \in Nat

\* Job abstraction (jobs module): "Active" stands for Scheduled/Enqueued/Processing/Failed/Awaiting;
\* "Finished" for Succeeded/DeadLettered/Cancelled; "Removed" = deleted by retention cleanup (jobs REQ-145).
RowStatus == {"none", "uncommitted", "Pending", "rolledBack", "deleted"}
JobStatus == {"none", "Active", "Finished", "Removed"}

VARIABLES row, job, created, holder, step, crashes, midCrash
vars == <<row, job, created, holder, step, crashes, midCrash>>

TypeInv ==
  /\ row      \in [Rows -> RowStatus]
  /\ job      \in [JobIds -> [status: JobStatus, key: Rows \cup {NULL}]]
  /\ created  \in [Rows -> 0..2]           \* history: jobs ever created from the row (capped)
  /\ holder   \in Nodes \cup {NULL}        \* relay lease
  /\ step     \in [Nodes -> [phase: {"idle", "enqueued"}, row: Rows \cup {NULL}]]
  /\ crashes  \in 0..MaxCrashes
  /\ midCrash \in BOOLEAN                  \* history: a relay crashed between enqueue and delete

Init ==
  /\ row      = [o \in Rows |-> "none"]
  /\ job      = [j \in JobIds |-> [status |-> "none", key |-> NULL]]
  /\ created  = [o \in Rows |-> 0]
  /\ holder   = NULL
  /\ step     = [n \in Nodes |-> [phase |-> "idle", row |-> NULL]]
  /\ crashes  = 0
  /\ midCrash = FALSE

Min(a, b) == IF a < b THEN a ELSE b

\* @req REQ-430  Outbox mode: dbContext.EnqueueAsync writes the job as an outbox row in the
\*               application's DbContext; it commits or rolls back with the application's transaction.
AppWritesRow(o) ==
  /\ row[o] = "none"
  /\ row' = [row EXCEPT ![o] = "uncommitted"]
  /\ UNCHANGED <<job, created, holder, step, crashes, midCrash>>

\* @req REQ-430  (same transaction, outcome decided by the application)
AppEndsTransaction(o) ==
  /\ row[o] = "uncommitted"
  /\ \E r \in {"Pending", "rolledBack"} : row' = [row EXCEPT ![o] = r]
  /\ UNCHANGED <<job, created, holder, step, crashes, midCrash>>

\* Not in the requirements (assumption A-9, finding F-12): a worker node takes the free relay lease.
AcquireRelayLease(n) ==
  /\ holder = NULL
  /\ holder' = n
  /\ UNCHANGED <<row, job, created, step, crashes, midCrash>>

KeyTaken(o) ==
  \E j \in JobIds : /\ job[j].key = o
                    /\ IF KeyScope = "activeUniqueKey" THEN job[j].status = "Active"
                                                       ELSE job[j].status \in {"Active", "Finished"}

\* @req REQ-432  (first half) The lease holder processes its next batch: enqueue the row's job keyed by
\*               outboxId, so a repeated relay creates no second job.
RelayEnqueues(n, o) ==
  /\ holder = n
  /\ step[n].phase = "idle"
  /\ row[o] = "Pending"
  /\ IF KeyTaken(o)
       THEN UNCHANGED <<job, created>>
       ELSE \E j \in JobIds :
              /\ job[j].status = "none"
              /\ job' = [job EXCEPT ![j] = [status |-> "Active", key |-> o]]
              /\ created' = [created EXCEPT ![o] = Min(@ + 1, 2)]
  /\ step' = [step EXCEPT ![n] = [phase |-> "enqueued", row |-> o]]
  /\ UNCHANGED <<row, holder, crashes, midCrash>>

\* @req REQ-432  (second half) ... and then delete the row.
RelayDeletes(n) ==
  /\ holder = n
  /\ step[n].phase = "enqueued"
  /\ row' = [row EXCEPT ![step[n].row] = "deleted"]
  /\ step' = [step EXCEPT ![n] = [phase |-> "idle", row |-> NULL]]
  /\ UNCHANGED <<job, created, holder, crashes, midCrash>>

\* @req INV-406  environment: the relay's node crashes (between the two steps or anywhere else);
\*               it loses the lease and its in-memory progress.
RelayCrashes(n) ==
  /\ holder = n
  /\ crashes < MaxCrashes
  /\ holder' = NULL
  /\ step' = [step EXCEPT ![n] = [phase |-> "idle", row |-> NULL]]
  /\ crashes' = crashes + 1
  /\ midCrash' = (midCrash \/ step[n].phase = "enqueued")
  /\ UNCHANGED <<row, job, created>>

\* jobs module (abstracted): the job runs to an end state; later retention cleanup removes it.
JobFinishes(j) ==
  /\ job[j].status = "Active"
  /\ job' = [job EXCEPT ![j].status = "Finished"]
  /\ UNCHANGED <<row, created, holder, step, crashes, midCrash>>

\* jobs REQ-145 retention cleanup (time abstracted, A-3).
RetentionRemoves(j) ==
  /\ job[j].status = "Finished"
  /\ job' = [job EXCEPT ![j].status = "Removed"]
  /\ UNCHANGED <<row, created, holder, step, crashes, midCrash>>

Next ==
  \/ \E o \in Rows : AppWritesRow(o) \/ AppEndsTransaction(o)
  \/ \E n \in Nodes : AcquireRelayLease(n) \/ RelayDeletes(n) \/ RelayCrashes(n) \/ \E o \in Rows : RelayEnqueues(n, o)
  \/ \E j \in JobIds : JobFinishes(j) \/ RetentionRemoves(j)

\* The relay is a system duty: fair. Lease takeover is fair only under assumption A-9 (LeaseTakeover).
Fairness ==
  /\ \A n \in Nodes : WF_vars(RelayDeletes(n)) /\ WF_vars(\E o \in Rows : RelayEnqueues(n, o))
  /\ LeaseTakeover => \A n \in Nodes : WF_vars(AcquireRelayLease(n))

Spec == Init /\ [][Next]_vars /\ Fairness

\* @req INV-406  Never more than one job from the same outbox row, even across a relay crash.
Inv_OneJobPerRow == \A o \in Rows : created[o] <= 1

\* @req LIV-400  (should) While a row is pending and a node can run the relay: eventually its job is
\*               enqueued and the row deleted.
Liv_RowRelayed == \A o \in Rows : (row[o] = "Pending") ~> (row[o] = "deleted" /\ created[o] >= 1)

\* @req SCN-403  Trap for IntegrationsOutbox_SCN403.cfg (expected to be VIOLATED): the relay crashed
\*               between enqueue and delete, and still exactly one job exists for o1 and o1 is gone.
Scn403_NotReached ==
  ~(\E o \in Rows : midCrash /\ row[o] = "deleted" /\ created[o] = 1)
=============================================================================
