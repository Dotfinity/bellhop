# M1-05 In-memory store: job lifecycle and conformance suite

## Context

The in-memory store is the default store (SET-2), the store behind `Bellhop.Testing` (TST-3) and the fixture the dashboard is built on. The conformance suite (STO-8) is the executable definition of the store contract. Writing the two together means the suite's first implementation is the simplest one, and PostgreSQL (M1-19) is then measured against the same tests.

This story covers the job lifecycle part of `IJobStore` (arch §5.3): `Capabilities`, `InitializeAsync`, `CreateJobsAsync`, `ClaimAsync`, `RenewLeasesAsync`, `CompleteAsync` (except `Awaiting` promotion, M1-06), `UpdateProgressAsync`, `SetParameterAsync`, `CancelAsync`, `RequeueAsync`, `DeleteAsync`, `GetJobAsync`, `QueryJobsAsync`, and `TickAsync` steps 1 (promote), 2 (recover), 3 (reroute) and 6 (ready queues and `StoreNow`). Tick steps 4 and 5, and the remaining methods, are M1-06 and M1-07; until then they throw `NotImplementedException("Not built yet: <method> (M1-0x)")`.

Files:

- `src/Bellhop/Storage/InMemory/InMemoryJobStore.cs` (internal), with time from the injected `TimeProvider` and one lock (arch §4.1), plus `UseInMemoryStore()` on `BellhopBuilder`.
- `tests/Bellhop.Storage.Conformance/`: `JobStoreFixture` (abstract: `CreateStoreAsync(TimeProvider?)` and a `StoreClock` abstraction so tests can advance time on the in-memory store and wait or use the database clock on real stores), and `JobLifecycleConformanceTests` (abstract xUnit v3 class).
- `tests/Bellhop.Tests/Storage/InMemoryJobLifecycleConformance.cs`, which runs the suite.

**As a** store author (and the Bellhop team)
**I want** an executable specification of the job lifecycle and a reference in-memory implementation
**so that** every store behaves identically and the engine can be built and tested without a database.

## Acceptance criteria

All of these are conformance tests (they run against every store), unless marked *in-memory only*.

- Given 3 jobs created in one `CreateJobsAsync` call where the third has a duplicate id, when the call runs, then it throws `DuplicateJobIdException` and none of the three exists.
- Given a `Scheduled` job with `Delay = 10 min`, when it is read back, then `DueAt` equals the store clock at insert plus 10 minutes (EXE-9).
- Given 1,000 enqueued jobs and 8 concurrent claimers each claiming batches of 10 in a loop until empty, when all finish, then every job was claimed exactly once, and each claimed job is `Processing` with attempt 1 and a distinct lease token (EXE-2).
- Given jobs in queues `critical` and `default`, with `Queues = [critical, default]`, when a claim asks for 3 slots per queue, then all `critical` jobs come before any `default` job. Within a queue, higher priority comes first, then FIFO by `enqueued_at` (CON-1, CON-2).
- Given `QueueSlots` with `critical` omitted, when a claim runs, then no `critical` job is claimed.
- Given an enqueued job named `x` and `RoutableNames` without `x`, when a claim runs, then the job is returned with `Unroutable = true`, its state is `Unroutable`, and its attempt is unchanged (JOB-3). Given a later tick whose `RoutableNames` contains `x`, then it is `Enqueued` again (`Rerouted = 1`).
- Given a claimed job, when `RenewLeasesAsync` runs with its token, then the lease expiry moves forward. Given a wrong token, then the id is in `Lost`.
- Given a claimed job, when `CompleteAsync` runs with a stale token (the job was recovered and re-claimed), then it returns false and the job's state and history are unchanged (fencing).
- Given each outcome (`Succeeded`, `Failed` with `RetryAt`, `DeadLettered`, `Cancelled`), when `CompleteAsync` runs, then the state, `finished_at` (terminal only), `due_at` (Failed only), cleared lease, and a history entry with node, reason and error are recorded (EXE-11, RET-4).
- Given a `Failed` job due at T and a `Scheduled` job due at T, when the store clock passes T and `TickAsync` runs, then both are `Enqueued` and `Promoted = 2`.
- Given a `Processing` job whose lease has expired, when `TickAsync` runs, then it is `Enqueued` with history reason `Interrupted` if attempts remain, or `DeadLettered` with reason `Interrupted` if `attempt == max_attempts`, and it is listed in `Recovered` (EXE-4).
- Given two concurrent `TickAsync` calls over 500 due jobs, when both finish, then every job was promoted exactly once (`Promoted` sums to 500).
- Given jobs in each state, when `CancelAsync` runs, then results and states follow arch §5.3 (`Cancelled` / `CancellationRequested` with `cancel_requested_at` set and reported by the next `RenewLeasesAsync` / `AlreadyFinished` / `NotFound`).
- Given a `DeadLettered` job with attempt 5, when `RequeueAsync` runs, then it is `Enqueued` with attempt 0 and a history entry (RET-5). Given a `Processing` job, it returns false.
- Given a non-Processing job with tags, when `DeleteAsync` runs, then the job, its history and its index entries are gone. Given a `Processing` job, it returns false.
- Given `UpdateProgressAsync` with the current lease, when the job is read, then progress and message are stored; with a stale lease, nothing changes.
- Given 120 jobs, when `QueryJobsAsync` pages through with `Limit = 50` filtered by state, name, queue, tag, time range, then the pages hold 50, 50 and 20 with no duplicates or gaps, ordered newest first, and the last `NextCursor` is null (DSH-8).
- Given `TickAsync` with `Queues = [a, b]` and a ready job only in `b`, then `QueuesWithReadyJobs = [b]`.
- *In-memory only:* given a `FakeTimeProvider`, when time is advanced, then the store's "now" follows it, and two store instances never share state (TST-1).

## Tests

The conformance class above, run by `InMemoryJobLifecycleConformance`. Concurrency tests use real threads (`Task.Run`) even in memory, to prove the lock.

## Out of scope

Recurring storage and `Awaiting` promotion (M1-06). Nodes, leader leases, purge, index API and statistics (M1-07). PostgreSQL (M1-19). Push notifications (the in-memory store wakes local workers through the engine's wake signal, M1-12, not through `IJobStoreNotifications`).

**Priority:** Must
**Depends on:** M1-02
**Traces to:** STO-1, STO-2 (in-memory), STO-8, EXE-2, EXE-4, EXE-9, EXE-11, CON-1, CON-2, JOB-3, RET-4, RET-5, SCH-6, DSH-8; arch §4.1, §5

## Notes

Status: not started
