# M1-05 In-memory store: job lifecycle and conformance suite

## Context

The in-memory store is the default store (SET-2), the store behind `Bellhop.Testing` (TST-3) and the fixture the dashboard is built on. The conformance suite (STO-8) is the executable definition of the store contract. Writing the two together means the suite's first implementation is the simplest one, and PostgreSQL (M1-19) is then measured against the same tests.

This story covers the job lifecycle part of `IJobStore` (arch §5.3): `Capabilities`, `InitializeAsync`, `CreateJobsAsync`, `ClaimAsync`, `RenewLeasesAsync`, `CompleteAsync`, `UpdateProgressAsync`, `SetParameterAsync`, `CancelAsync`, `RequeueAsync`, `DeleteAsync`, `GetJobAsync`, `QueryJobsAsync`, and `TickAsync` steps 1 (promote), 2 (recover) and 7 (ready queues, `StoreNow`, `MoreDue`). Tick steps 3 to 6 and the remaining methods are M1-06 and M1-07; until then they throw `NotImplementedException("Not built yet: <method> (M1-0x)")`.

Files:

- `src/Bellhop/Storage/InMemory/InMemoryJobStore.cs` (internal), with time from the injected `TimeProvider` and one lock (arch §4.1), plus `UseInMemoryStore()` on `BellhopBuilder`. It also has the internal `GetNextDueAt()` used by the test harness (arch §9).
- `tests/Bellhop.Storage.Conformance/`:
  - `JobStoreFixture` (abstract), with `CreateStoreAsync(namespace, nodeName)` and a `StoreClock` with `AdvanceAsync(TimeSpan)`. The in-memory implementation advances a `FakeTimeProvider`. A database implementation shifts every persisted timestamp back by the same amount, which is test-only code in the store's test project, never on `IJobStore`. This lets conformance tests cover leases, retention and node timeouts of minutes or days without waiting.
  - `JobLifecycleConformanceTests` (abstract xUnit v3 class).
- `tests/Bellhop.Tests/Storage/InMemoryJobLifecycleConformance.cs`, which runs the suite.

**As a** store author (and the Bellhop team)
**I want** an executable specification of the job lifecycle and a reference in-memory implementation
**so that** every store behaves identically and the engine can be built and tested without a database.

## Acceptance criteria

All of these are conformance tests (they run against every store), unless marked *in-memory only*. Every method is linearizable: concurrent calls behave as if they ran one at a time (arch §5, REQ-044). Criteria marked *(refinement)* replay a sequence the refinement models found breaking a rule (refinement/decisions.md); each must fail if its decision is reverted.

- Given 3 jobs created in one `CreateJobsAsync` call where the third has a duplicate id, when the call runs, then it throws `DuplicateJobIdException` and none of the three exists.
- Given a `Scheduled` job with `Delay = 10 min`, when it is read back, then `DueAt` equals the store clock at insert plus 10 minutes (EXE-9).
- Given 1,000 enqueued jobs and 8 concurrent claimers each claiming batches of 10 in a loop until empty, when all finish, then every job was claimed exactly once, and each claimed job is `Processing` with attempt 1 and a distinct lease token (EXE-2).
- Given jobs in queues `critical` and `default`, with `Queues = [critical: 3, default: 3]` and `MaxTotal = 4`, when a claim runs, then it returns 4 jobs: 3 from `critical` first, then 1 from `default`. Within a queue, higher priority comes first, then FIFO by `enqueued_at` (CON-1, CON-2).
- Given `QueueSlots` with `critical` omitted, when a claim runs, then no `critical` job is claimed.
- Given an enqueued job named `x` and `RoutableNames` without `x`, when a claim runs, then the job is not claimed and stays `Enqueued` with its attempt unchanged (JOB-3, A-26).
- Given `OnlyId` set to an `Enqueued` job that is not first in FIFO order, then exactly that job is claimed. Given `OnlyId` of a job in another state, then nothing is claimed.
- Given a claimed job, when `RenewLeasesAsync` runs with its token, then the lease expiry moves forward. Given a wrong token, then the id is in `Lost`.
- *(refinement, D-6)* Given a claimed job whose lease expired and was recovered by a tick (now `Enqueued`, its token unchanged), when `RenewLeasesAsync` runs with the old token, then the id is in `Lost` and the job's lease fields are unchanged.
- Given a claimed job, when `CompleteAsync` runs with a stale token (the job was recovered and re-claimed), then it returns false and the job's state and history are unchanged (fencing).
- *(refinement, D-6)* Given a claimed job whose lease expired, recovered by a tick and then cancelled (`Cancelled`) before any re-claim, when `CompleteAsync` runs with the old token and `Succeeded`, then it returns false and the job stays `Cancelled`. Every write a node makes about a job is conditional on `state = 'Processing'` and its token (arch §4.4).
- Given a completed job, when `CompleteAsync` is called again with the same token and outcome (a retry after a lost response), then it returns true and writes nothing more (idempotent, arch §4.4).
- Given each outcome (`Succeeded`, `Failed` with `RetryAt`, `DeadLettered`, `Cancelled`), when `CompleteAsync` runs, then the state, `finished_at` (terminal only), `due_at` (Failed only), cleared lease owner and expiry, and a history entry with node, reason and error are recorded (EXE-11, RET-4).
- Given a `Processing` job with a cancel request, when `CompleteAsync` runs with `Failed`, then the job is `Cancelled`, not scheduled for a retry.
- Given a `Failed` job due at T and a `Scheduled` job due at T, when the store clock passes T and `TickAsync` runs, then both are `Enqueued` and `Promoted = 2`.
- Given a `Processing` job whose lease has expired, when `TickAsync` runs, then it is `Enqueued` with history reason `Interrupted` if attempts remain, `DeadLettered` with reason `Interrupted` if `attempt == max_attempts`, or `Cancelled` if a cancel was requested. It is listed in `Recovered` with its new state (EXE-4).
- Given two concurrent `TickAsync` calls over 500 due jobs, when both finish, then every job was promoted exactly once (`Promoted` sums to 500).
- Given 1,500 due jobs, when one tick runs, then it promotes at most the fixed batch (1,000) and reports `MoreDue = true`.
- Given jobs in each state, when `CancelAsync` runs, then results and states follow arch §5.3 (`Cancelled` / `CancellationRequested` with `cancel_requested_at` set and reported by the next `RenewLeasesAsync` / `AlreadyFinished` / `NotFound`).
- Given a `DeadLettered` job with attempt 5, when `RequeueAsync` runs, then it is `Enqueued` with attempt 0, a cleared cancel request and a history entry, and the result has `Requeued = true` and `ActiveSibling = null` (RET-5). The same holds for `Failed`, `Cancelled` and `Succeeded`. Given `Scheduled`, `Enqueued`, `Processing`, `Awaiting` or `Unroutable`, it returns `Requeued = false` and changes nothing. `ActiveSibling` for recurring occurrences is M1-06.
- Given a non-Processing job with tags, when `DeleteAsync` runs, then the job, its history and its index entries are gone. Given a `Processing` job, it returns false.
- Given `UpdateProgressAsync` with the current lease, when the job is read, then progress and message are stored; with a stale lease, including one whose job was recovered but not yet re-claimed (D-6), nothing changes.
- Given `SetParameterAsync` with the current lease token, then the parameter is stored; with a stale token, it returns false and nothing changes; without a token, it is stored on any non-terminal job (EXT-6, STO-11).
- Given 120 jobs, when `QueryJobsAsync` pages through with `Limit = 50` filtered by state, name, queue, tag, time range, then the pages hold 50, 50 and 20 with no duplicates or gaps, ordered newest first, and the last `NextCursor` is null (DSH-8).
- Given `TickAsync` with `Queues = [a, b]` and a ready job only in `b`, then `QueuesWithReadyJobs = [b]`. Given a job in `a` promoted by that same tick, then `a` is listed too.
- *In-memory only:* given a `FakeTimeProvider`, when time is advanced, then the store's "now" follows it, and two store instances never share state (TST-1).

## Tests

The conformance class above, run by `InMemoryJobLifecycleConformance`. Concurrency tests use real threads (`Task.Run`) even in memory, to prove the lock.

## Out of scope

Recurring storage and `Awaiting` promotion (M1-06). Nodes, leader leases, purge, Unroutable marking and rerouting, the index API and statistics (M1-07). PostgreSQL (M1-19). Push notifications (the in-memory store has none; local workers are woken by the client and the scheduler, M1-09 and M1-13).

**Priority:** Must
**Depends on:** M1-02
**Traces to:** STO-1, STO-2 (in-memory), STO-8, STO-11 (parameters), EXE-2, EXE-4, EXE-9, EXE-11, CON-1, CON-2, JOB-3, RET-4, RET-5, SCH-6, EXT-6, DSH-8; arch §4.1, §4.4, §5; refinement D-6, REQ-044

## Notes

Status: not started
