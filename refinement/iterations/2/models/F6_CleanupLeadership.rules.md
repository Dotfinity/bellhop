# F6 Cleanup leadership

Covers: one node at a time runs cleanup under a short lease in the store; a node takes the lease once it has expired, the holder renews it, a run renews the lease before each batch and stops when it can't, and otherwise purges in batches until a batch comes back short. "The holder can renew it" is covered by the renewal step always succeeding for the holder, not by a separate rule.

## Rules

- OneLeaseHolder (always): No two nodes hold an unexpired cleanup lease at the same moment. REQ-039
- TakeOnlyAfterExpiry (each step): A node gets the cleanup lease only when no other node holds it unexpired. REQ-039
- OnlyHolderPurges (always): A node purges a batch only while it holds an unexpired cleanup lease. REQ-040
- OneCleanupRunAtATime (always): At most one node is in the middle of a cleanup run at any moment, as the feature summary "one node at a time runs cleanup" says. REQ-039, REQ-040
- RunEndsOnShortBatch (each step): A cleanup run stops only right after a batch that came back short, or when it can't renew the lease before its next batch. REQ-041 (as changed with D-8)

## Assumptions

- The cleanup lease lasts 2 ticks; the stories give no product value. REQ-039
- An idle node may try to take or renew the lease at any tick; the cleanup interval and when each node's interval comes round are not modelled. REQ-039
- A failed attempt to start a run changes nothing; the node stays idle until it tries again. REQ-039
- A node checks the lease when it starts a run and when it renews it before each batch, never while a batch is under way; the stories are silent on checking during a batch. REQ-040, REQ-041
- A node runs one cleanup run at a time; while its run is in progress it touches the lease only through the renewal before each batch. REQ-040, REQ-041
- The lease is not released when a run ends; it simply expires. REQ-039
- A run has at most 3 batches, the last of which, if reached, is always short; no requirement bounds the number of full batches. REQ-041
- A batch, and the pause between batches, may take any number of ticks within the checked window of 5 ticks. REQ-041
- Taking or renewing the lease is one atomic step in the store, judged by one shared store clock. REQ-039
- Nodes do not crash or stop in this model. REQ-039

## Lifecycle

A node's cleanup run, as the model allows it.

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Running: TakeLease
    Idle --> Running: RenewLease
    Running --> Purging: StartBatch (renewal succeeds)
    Running --> Idle: StopOnFailedRenewal
    Purging --> Running: FinishBatch (full)
    Purging --> Idle: FinishBatch (short)
```
