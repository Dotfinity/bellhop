# F2 Lease heartbeat and self-fencing

Covers: node n1 runs one job under a 6-tick lease and tries to renew it every 2 ticks (a third of the lease). A renewal can succeed, get a late answer (1 or 2 ticks later), lose its answer, or fail because the store is down. n1 counts from the moment it sent its last renewal that succeeded, and cancels its handler once 4 ticks (two thirds of the lease) have passed without one; its check runs at least once per renewal interval, so the cancel can come up to 2 ticks after that. Node n2 may recover the job once the store's time is past the lease expiry, then run it. n1 may also finish on its own, or shut down with a failed lease release.

## Rules

- NoDoubleRun (always): n2 never runs the job while n1 is still running it and hasn't cancelled. REQ-015
- HealthyNeverRecovered (always): While every renewal has succeeded and its answer came straight back, no other node recovers the job. REQ-014
- CancelledByRecoveryMoment (each step): The clock never moves past a moment at which another node could recover the job (or already has) while n1's handler is still running and not cancelled. REQ-015
- RecoveredAfterFailedRelease (eventually): When n1 shuts down and releasing its lease fails, the job is recovered once the lease runs out. REQ-016

## Assumptions

- Time moves in whole ticks of a sixth of the lease (lease = 6 ticks); the node tries one renewal every 2 ticks (a third of the lease), and two thirds of the lease is 4 ticks. The requirements don't say how "a third" rounds for a lease not divisible by three. REQ-014, REQ-015
- Both nodes' clocks equal the store's clock; clock skew is out of scope (confirmed, D-14). REQ-015
- The node takes the time of a successful renewal as the moment it sent the request, and the store extends the lease from no earlier than that moment (D-7). REQ-015
- The claim at time 0 counts as the first successful renewal: the store's lease expires at 0 + lease length and the node counts from 0. REQ-014, REQ-015
- The node has at most one renewal waiting for an answer; a late answer arrives 1 or 2 ticks after it was sent (at most one renewal interval late, confirmed, D-14), before the next attempt. REQ-014
- The node checks whether to cancel at least once per renewal interval (confirmed, D-14), so it cancels no later than 2 ticks after two thirds of the lease has passed. REQ-015
- A handler stops the moment the node cancels it; a handler that ignores the cancel, or takes time to stop, is out of scope. REQ-015
- A job recovered from n1 has attempts left, so it goes back to Enqueued, and n2 is the node that claims it. REQ-008, REQ-001
- n2 never renews its own lease and nothing recovers the job from n2; one hand-over is modelled (confirmed, D-14). REQ-014
- Only a shutdown whose lease release fails is modelled, and only early enough that the lease can run out before the clock bound (tick 12). REQ-012, REQ-016

## Lifecycle

The job, as the store sees it:

```mermaid
stateDiagram-v2
    [*] --> HeldByN1
    HeldByN1 --> HeldByN1: RenewOk / RenewSlowResponse / RenewResponseLost / RenewStoreDown
    HeldByN1 --> Succeeded: HolderFinishes
    HeldByN1 --> Enqueued: Recover
    Enqueued --> HeldByN2: RecovererStarts
    Succeeded --> [*]
    HeldByN2 --> [*]
```

n1's handler:

```mermaid
stateDiagram-v2
    [*] --> Running
    Running --> Running: RenewOk / RenewSlowResponse / SlowResponseArrives / RenewResponseLost / RenewStoreDown
    Running --> Cancelled: SelfFence
    Running --> Finished: HolderFinishes
    Running --> Stopped: ShutdownReleaseFails
    Cancelled --> [*]
    Finished --> [*]
    Stopped --> [*]
```

RenewToldLost (n1 renews and is told the job is no longer its own) is still in the model but never happens: n1 has always cancelled before the job can be recovered, so no step leaves Running that way, and no step of n1's happens while the job is Enqueued or held by n2.
