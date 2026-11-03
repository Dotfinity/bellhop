# Bellhop — Requirements and Feature Design

| | |
|---|---|
| Status | Draft v0.3 for review (open questions 1 to 5 resolved; see [docs/bellhop-architecture.md](docs/bellhop-architecture.md) §0) |
| Date | 2026-11-03 |
| Scope | A new .NET background-job and scheduling library positioned against Hangfire and TickerQ |
| Evidence | [research.md](research.md): feature inventories, grievances, Redis landscape, plugin ecosystem, sources |
| Keywords | MUST / SHOULD / MAY are used as in RFC 2119 |

Bellhop takes the job, carries it where it needs to go, and tells you when it is done. The design goal is simple: **easy to set up, easy to use, and easy to configure only when you need to**. The evidence behind every requirement (what people love and hate about the incumbents, the Redis landscape, the plugin ecosystem) lives in research.md; this file holds only the outcome.

---

## 1. Purpose and scope

Bellhop is a durable background-job library for .NET 8+ applications. It covers:

- fire-and-forget, delayed, and recurring (cron) jobs
- continuations, chains, and batches
- retries, dead-lettering, cancellation, timeouts
- multi-node execution over a shared database
- a dashboard with live updates and per-job logs
- first-class observability (OpenTelemetry, health checks) and testing support

It is **not** a message bus, a workflow/saga engine, or a distributed actor system (see §7 Non-goals).

---

## 2. Product principles

| # | Principle | Consequence |
|---|---|---|
| P1 | **Three lines to a working system.** | Register, pick a store, map the dashboard. Everything else has a documented default. |
| P2 | **One obvious way to define a job.** | A job is a plain data type with a handler. No expression trees, no magic strings, no generator-only paths. |
| P3 | **Correct under concurrency by construction.** | Every claim, trigger and overlap decision is an atomic store operation. No in-process locks pretend to be distributed. |
| P4 | **Boring storage.** | Narrow async store interface, plain SQL, no EF Core or ASP.NET Core dependency in the core, published conformance tests. |
| P5 | **Secure and explicit by default.** | The dashboard requires host authorization outside Development, serialization never trusts type names, and the app fails fast at startup with an actionable message when misconfigured. |
| P6 | **Nothing is silent.** | Every internal failure logs with an event id. Every job outcome is visible in the dashboard, metrics and traces. |
| P7 | **Testable without statics.** | Everything resolves from DI. Time comes from `TimeProvider`. An in-memory store and an inline execution mode ship in the box. |
| P8 | **Trustworthy versioning and licensing.** | MIT forever, no runtime license checks, strict SemVer, upgrade guide per major, rolling-deploy compatible schema. |
| P9 | **Build in what everyone installs.** | The functionality of the popular Hangfire plugins (logs, auth, tags, throttling, launch forms, recurring management, notifications, HTTP jobs, node metrics) is core, versioned and tested with the host. There is no plugin API; extension is through DI hooks and the JSON API. |

---

## 3. Target developer experience

The five-minute path, which the documentation's first page must match exactly:

```csharp
// Program.cs
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddBellhop(bellhop =>
{
    bellhop.UsePostgres(builder.Configuration.GetConnectionString("Default")!);
    bellhop.AddJobsFromAssemblyContaining<Program>();
});

var app = builder.Build();
app.MapBellhopDashboard("/jobs").RequireAuthorization("Admins");
app.Run();
```

```csharp
// Jobs/SendWelcomeEmail.cs
[JobName("send-welcome-email")]            // stable identity; renaming the class is safe
public sealed record SendWelcomeEmail(Guid UserId) : IJob;

public sealed class SendWelcomeEmailHandler(IEmailSender email) : IJobHandler<SendWelcomeEmail>
{
    public Task HandleAsync(SendWelcomeEmail job, JobContext ctx, CancellationToken ct)
        => email.SendWelcomeAsync(job.UserId, ct);
}
```

```csharp
// Anywhere, via DI
public sealed class RegisterUser(IJobClient jobs)
{
    public async Task RegisterAsync(User user)
    {
        await jobs.EnqueueAsync(new SendWelcomeEmail(user.Id));
        await jobs.ScheduleAsync(new SendFollowUpEmail(user.Id), delay: TimeSpan.FromDays(3));
    }
}
```

```csharp
// A recurring job, declared where it lives
[JobName("nightly-cleanup")]
[Recurring("0 3 * * *", TimeZone = "Europe/Sofia", Overlap = OverlapPolicy.Skip)]
public sealed record NightlyCleanup : IJob;
```

Things the developer did **not** have to do: create a database schema by hand, choose polling intervals, write an authorization filter class, configure a serializer, register a hosted service, or pin package versions.

Why "job = data, handler = behaviour" instead of Hangfire's lambda or TickerQ's attributed method:

- the stored record is a name plus a JSON document, so renames, refactors and rolling deploys cannot break it
- `EnqueueAsync(new SendWelcomeEmail(id))` is fully type-safe with one inferred generic, no magic strings
- the handler is a plain DI-constructed class that is trivial to unit test
- it is the pattern .NET developers already know from MediatR, Wolverine, Brighter and MassTransit

The grievances these choices answer are listed in research.md §1.4 and §1.5.

---

## 4. Functional requirements

### 4.1 Setup and configuration (SET)

| ID | Requirement | Level |
|---|---|---|
| SET-1 | A working single-node setup MUST require only `AddBellhop(...)` with a store and job registration. The dashboard MUST be optional. | MUST |
| SET-2 | If no store is configured, Bellhop MUST use the in-memory store and MUST log a warning at startup in non-Development environments. | MUST |
| SET-3 | All options MUST be bindable from `IConfiguration` (`"Bellhop": { ... }`) and overridable in code. Options MUST be validated at startup (`ValidateOnStart`) with messages that name the option and the fix. | MUST |
| SET-4 | Every option MUST have a documented default that is safe for production on a small deployment without tuning. | MUST |
| SET-5 | Registration MUST NOT perform I/O. Database connectivity, schema checks and job reconciliation happen in the hosted service, after the host starts. Build-time tooling (OpenAPI generation, EF design-time) MUST NOT start the scheduler. | MUST |
| SET-6 | The core package MUST NOT depend on ASP.NET Core or EF Core. Worker services and console hosts are first-class. | MUST |
| SET-7 | A node MUST be configurable as `Both` (default), `ClientOnly` (enqueue only, no workers) or `WorkerOnly`. | MUST |
| SET-8 | On start, Bellhop MUST log a one-screen summary: store and schema version, mode, queues and concurrency, registered job count, recurring jobs with their next run, dashboard path and auth mode. | MUST |
| SET-9 | All first-party packages MUST ship with the same version number and MUST declare exact-version dependencies on each other so that mismatches are impossible rather than diagnosed later. | MUST |
| SET-10 | Job registration MUST support assembly scanning (`AddJobsFromAssemblyContaining<T>()`) and explicit `AddJob<TJob, THandler>()`. Scanning across multiple assemblies MUST work (plugin architectures). | MUST |

### 4.2 Job definition model (JOB)

| ID | Requirement | Level |
|---|---|---|
| JOB-1 | A job is a serializable data type implementing `IJob` (or `IJob<TResult>`). Behaviour lives in `IJobHandler<TJob>` resolved from DI in a scope created per execution. No source generator or reflection-based expression capture is required; a generator MAY be offered later purely for AOT registration. | MUST |
| JOB-2 | Every job has a **stable string name** used in storage. The name comes from `[JobName("...")]` or defaults to the type's simple name. A bundled analyzer MUST warn when a job type has no explicit name (renaming it would orphan stored jobs). | MUST |
| JOB-3 | `[JobName]` MUST support aliases (`Aliases = ["old-name"]`) so that renames are safe. Jobs whose name has no registered handler MUST enter an `Unroutable` state, visible in the dashboard, and MUST NOT be failed or deleted. They resume automatically when a handler appears. | MUST |
| JOB-4 | Payloads MUST be serialized with System.Text.Json as plain contracts: no type names, no polymorphism unless the user opts in with `[JsonDerivedType]`. Unknown properties are ignored and missing properties take defaults, so payloads evolve safely. Users MAY supply `JsonSerializerOptions` or a `JsonSerializerContext` (AOT). | MUST |
| JOB-5 | Handler signature: `Task HandleAsync(TJob job, JobContext ctx, CancellationToken ct)` (and `Task<TResult>` for result jobs). No other shape is supported. | MUST |
| JOB-6 | `JobContext` MUST expose: job id, name, attempt number, max attempts, enqueue time, scheduled time, queue, tags, parent/batch ids, a job-scoped `ILogger`, `ReportProgressAsync(double, string?)`, and the trace context. | MUST |
| JOB-7 | Declarative per-job metadata via attributes on the job type: `[Queue]`, `[Priority]`, `[Retry]`, `[Timeout]`, `[Unique]`, `[Concurrency]`, `[Recurring]`. Attributes are data only; they never execute code. The same metadata MUST be settable fluently in `AddBellhop` for teams that dislike attributes, with fluent configuration winning. | MUST |
| JOB-8 | Jobs MAY return a result (`IJob<TResult>`). Results are stored (size-capped, configurable) and readable via `GetResultAsync<TResult>(jobId)`. | SHOULD |
| JOB-9 | A `[Sensitive]` attribute on payload properties MUST cause the value to be masked in the dashboard, captured logs and traces. | SHOULD |
| JOB-10 | Analyzers MUST flag: a job without a handler, a handler without a registered job, payload types that are not serializable, and invalid cron literals in `[Recurring]`. | SHOULD |

### 4.3 Scheduling API (SCH)

All scheduling goes through `IJobClient` (injectable, mockable). There is no static entry point.

| ID | Requirement | Level |
|---|---|---|
| SCH-1 | `EnqueueAsync(job, options?)` runs as soon as a worker is free. Returns a `JobId`. | MUST |
| SCH-2 | `ScheduleAsync(job, at: DateTimeOffset)` and `ScheduleAsync(job, delay: TimeSpan)` run at a point in time. | MUST |
| SCH-3 | `ContinueWithAsync(parentId, job, when: OnSuccess \| OnFailure \| OnCompletion)` chains a job after another. | MUST |
| SCH-4 | `EnqueueOptions` MUST support: queue, priority, unique key and duplicate policy, tags (key/value), timeout, retry policy override, concurrency key, and an explicit database transaction. | MUST |
| SCH-5 | **Uniqueness.** When `UniqueKey` is set and an active job (Scheduled, Enqueued, Processing, Awaiting) with the same key exists, `EnqueueAsync` MUST return the existing id and report `WasDuplicate = true`. Duplicate policy options: `Ignore` (default), `ReplaceSchedule` (debounce: move the existing scheduled job to the new time), `Error`. Uniqueness MUST be enforced by the store (unique index), not by read-then-write. | MUST |
| SCH-6 | `CancelAsync(id)` MUST cancel a Scheduled/Enqueued job immediately and MUST signal the `CancellationToken` of a Processing job on whichever node runs it (cross-node). `RequeueAsync(id)`, `DeleteAsync(id)`, `GetAsync(id)` MUST exist. | MUST |
| SCH-7 | `WaitForCompletionAsync(id, timeout)` and `GetResultAsync<T>(id)` MUST exist for request/response patterns. | SHOULD |
| SCH-8 | **Transactional enqueue.** When the store shares the application's database, the caller MUST be able to pass its open `DbTransaction` so the job becomes visible only if the business transaction commits. `Bellhop.EntityFrameworkCore` adds `dbContext.EnqueueAsync(job)` that joins the context's current transaction without taking a dependency on EF in the core. Stores that cannot offer this (Redis) report it through the capability set in RED-10. | MUST |
| SCH-9 | Bulk operations (`EnqueueManyAsync`) MUST be atomic and MUST use a single round-trip per batch. | SHOULD |
| SCH-10 | Enqueue from inside a handler MUST propagate the parent id and trace context automatically. | MUST |

### 4.4 Recurring jobs (REC)

| ID | Requirement | Level |
|---|---|---|
| REC-1 | Recurring definitions MAY be declared in code (`[Recurring]` attribute or `bellhop.AddRecurring<TJob>(name, schedule, job?, options?)`) or created at runtime through `IRecurringJobManager` (and the dashboard). | MUST |
| REC-2 | Schedules MUST support 5- and 6-field cron (seconds optional), fixed intervals (`Every(TimeSpan)`), and a readable helper API (`Cron.Daily(hour: 3)`). Invalid expressions MUST fail at startup (code-defined) or at the API call (runtime-defined), never silently. | MUST |
| REC-3 | **Reconciliation.** On startup each node MUST upsert code-defined recurring jobs idempotently by name. Multiple nodes starting simultaneously MUST NOT create duplicates or throw. A code-defined job removed from code MUST be marked `Orphaned` and paused, not deleted (configurable). Dashboard edits to a code-defined job MUST be rejected with a clear message unless the job is marked `AllowRuntimeOverride`. | MUST |
| REC-4 | **Time zones.** Every recurring job has an explicit IANA time zone. The default is UTC and MUST be shown in the dashboard next to every schedule. DST transitions MUST follow the documented rule: a skipped local time runs at the next valid instant once; a repeated local time runs once. | MUST |
| REC-5 | **Misfire policy** per job: `RunOnce` (default: if occurrences were missed, run a single catch-up), `Skip` (jump to the next future occurrence), `RunAll(max)`. Missed-occurrence handling MUST be logged with the reason. | MUST |
| REC-6 | **Overlap policy** per job, enforced by the store across nodes: `Skip` (default: do not start if the previous run is still active; record a `Skipped` occurrence), `Queue` (start after the previous finishes), `Allow`, `CancelPrevious`. No distributed lock timeouts, no exceptions. | MUST |
| REC-7 | Triggering MUST be an atomic compare-and-set on the stored `NextRunAt` so that N nodes produce exactly one occurrence. The store MUST index `NextRunAt` so that 100k definitions (multi-tenant) cost one range query per poll. | MUST |
| REC-8 | Recurring jobs MAY carry a payload (per-tenant instances of the same job type). | MUST |
| REC-9 | `IRecurringJobManager` MUST support: add-or-update, remove, trigger now (optionally with an overridden payload), pause, resume, list, next N occurrences, last outcome. | MUST |
| REC-10 | Changing a schedule MUST recompute `NextRunAt` from now, never from the last execution, and MUST NOT fire a catch-up for the old schedule. | MUST |
| REC-11 | Schedules are an extension point: `ISchedule` (`GetNextOccurrence(after, timeZone)`) with cron and interval as the built-in implementations, so applications can add calendars (business days, holidays) without touching the scheduler. | SHOULD |

### 4.5 Execution engine and reliability (EXE)

| ID | Requirement | Level |
|---|---|---|
| EXE-1 | Workers are async tasks bounded by a concurrency limit, not dedicated blocked threads. The store API is fully asynchronous. Execution scopes support `IAsyncDisposable`. | MUST |
| EXE-2 | **Claiming is atomic.** A job can be claimed by exactly one worker using store-native primitives (`FOR UPDATE SKIP LOCKED`, `READPAST/UPDLOCK`). Claims carry a lease with an expiry. | MUST |
| EXE-3 | A running job's lease MUST be renewed by a heartbeat (default: every third of the lease) without handler cooperation. | MUST |
| EXE-4 | **Recovery.** When a lease expires (node crash, network partition) the job MUST be returned to Enqueued with the attempt counted and reason `Interrupted`, or dead-lettered if attempts are exhausted. Recovery is performed by any live node; there is no single point of failure. The dashboard MUST show interrupted attempts distinctly. | MUST |
| EXE-5 | Delivery semantics are **at-least-once**. The docs MUST state the duplicate window (lease length) and MUST recommend idempotent handlers and `UniqueKey`. | MUST |
| EXE-6 | **Graceful shutdown.** On host stop, workers stop claiming, in-flight jobs get `ShutdownTimeout` (default 30 s) to finish, then their tokens are cancelled, then any still-running jobs have their leases released so another node picks them up immediately. | MUST |
| EXE-7 | **Timeouts.** A per-job timeout cancels the token; a handler that ignores cancellation is abandoned after a grace period and the job is marked `Failed` with reason `Timeout`. | MUST |
| EXE-8 | **Latency.** Any node that enqueues a job wakes its own workers immediately. Stores that support notifications (PostgreSQL `LISTEN/NOTIFY`) MUST use them so other nodes pick up work within ~100 ms. Otherwise adaptive polling applies: tight loop while work is found, backing off to `PollInterval` (default 1 s) when idle. | MUST |
| EXE-9 | Time MUST come from `TimeProvider`. Claims and due-checks MUST use the database clock, and Bellhop MUST warn when node clock skew exceeds a threshold. | MUST |
| EXE-10 | The scheduler that promotes due jobs (Scheduled → Enqueued, recurring triggers) MUST be distributed: every node runs it with atomic claims; no leader election is required for correctness. Cleanup MAY use a short lease to avoid redundant work. | MUST |
| EXE-11 | Job states: `Scheduled`, `Enqueued`, `Processing`, `Succeeded`, `Failed` (will retry), `DeadLettered`, `Cancelled`, `Awaiting` (continuation waiting on a parent), `Unroutable`. Every transition MUST be recorded with timestamp, node and reason. | MUST |

### 4.6 Retries, failures and dead-lettering (RET)

| ID | Requirement | Level |
|---|---|---|
| RET-1 | Default retry policy: 5 attempts, exponential backoff with jitter (roughly 10 s, 1 m, 5 m, 30 m). Configurable globally, per job type and per enqueue. | MUST |
| RET-2 | Policies MAY be typed (`IRetryPolicy` from DI) to decide by exception type, attempt and job. Handlers MAY throw `PermanentJobFailureException` to skip retries. | MUST |
| RET-3 | When attempts are exhausted the job MUST move to `DeadLettered` and be retained (default 30 days). It MUST never be silently deleted. | MUST |
| RET-4 | Every attempt MUST store the exception type, message, stack trace and the node that ran it. | MUST |
| RET-5 | Dead-lettered jobs MUST be requeueable individually and in bulk (by name, queue, tag or time range) from the API and dashboard, with the attempt counter reset. | MUST |
| RET-6 | An `IJobEvents` hook (`OnEnqueued`, `OnStarted`, `OnSucceeded`, `OnFailed`, `OnDeadLettered`, `OnCancelled`, `OnRecurringMissed`) resolved from DI. The built-in notifications (BLT-11) are one consumer; applications may add their own. | MUST |

### 4.7 Queues, priority, concurrency and throttling (CON)

| ID | Requirement | Level |
|---|---|---|
| CON-1 | Named queues. A worker declares an ordered list of queues; order is the documented strict priority (first listed is drained first). Weighted round-robin MAY be chosen instead. Per-queue concurrency limits MUST be supported. | MUST |
| CON-2 | Integer priority within a queue (higher first, default 0, FIFO within the same priority). | MUST |
| CON-3 | **Concurrency keys**, enforced by the store across nodes: `[Concurrency(Key = "tenant:{TenantId}", Max = 1)]` acts as a distributed mutex (Max = 1) or semaphore (Max = N). Jobs blocked by a key wait in the queue; they are never failed for waiting. Keys MAY be templated from payload properties. | MUST |
| CON-4 | Rate limits per key (N executions per fixed or sliding window) with the same store-enforced semantics; limits adjustable at runtime (BLT-7). | MUST |
| CON-5 | Queues and individual recurring jobs MUST be pausable and resumable from the API and dashboard. A global "maintenance" pause MUST exist. | MUST |
| CON-6 | Default node concurrency MUST be documented and sane for I/O-bound jobs (proposal: `max(8, 2 × ProcessorCount)`), with an optional separate limit for jobs tagged `LongRunning`. | MUST |
| CON-7 | All coordination (claims, leases, triggers, overlap, concurrency keys, cleanup leadership) MUST live in the job store. No first-party package may require an external lock service or a distributed-lock library (see Appendix A, ADR-1). | MUST |

### 4.8 Workflows: continuations, chains, batches (WF)

All of these are free.

| ID | Requirement | Level |
|---|---|---|
| WF-1 | Continuations (SCH-3) with `OnSuccess`, `OnFailure`, `OnCompletion`. A continuation whose parent is dead-lettered or cancelled MUST resolve according to its condition and never hang in `Awaiting` forever. | MUST |
| WF-2 | Chains: `jobs.ChainAsync(b => b.Then(new A()).Then(new B()).Then(new C()))`, created atomically in one store transaction. | MUST |
| WF-3 | Batches: a named group of jobs created atomically, with batch-level continuations (`OnBatchSucceeded`, `OnBatchCompleted`) and aggregate state. Batches MAY be extended while open. | MUST |
| WF-4 | Parent/child relationships MUST be visible in the dashboard as a graph with per-node state. | SHOULD |
| WF-5 | Sagas, compensation, human tasks and long-lived workflow state are out of scope (see §7). | — |

### 4.9 Storage (STO)

| ID | Requirement | Level |
|---|---|---|
| STO-1 | A single narrow async interface `IJobStore` (target: under 25 methods) with documented semantics for every method. All first-party stores and any third-party store implement only this. | MUST |
| STO-2 | First-party stores: **PostgreSQL** (reference implementation, notifications supported), **SQL Server**, **SQLite** (single node, dev and small deployments), **Redis and Redis-compatible servers** (§4.9.1, §4.9.2), **In-memory**. SQL stores are implemented with plain ADO.NET; no EF Core, no Dapper. | MUST |
| STO-3 | **Schema management.** The store owns a small schema (target: 6 tables or fewer) in a configurable schema/prefix (default `bellhop`). Migrations are embedded, versioned and idempotent. `AutoMigrate` defaults to true and logs what it did. When false, `BellhopSchema.GetScript(provider, fromVersion)` MUST emit the exact SQL for DBAs, and a version mismatch MUST fail fast at startup with the script path in the message. | MUST |
| STO-4 | The store MUST never require the application to register, expose or migrate a `DbContext`. `Bellhop.EntityFrameworkCore` is optional sugar for transactional enqueue only. | MUST |
| STO-5 | **Rolling deploys.** Schema version N must be readable and writable by library versions N and N+1 so that nodes on two adjacent versions can coexist. | MUST |
| STO-6 | **Idle cost.** An idle node (no work, notifications available) MUST issue at most one lightweight query per `PollInterval` and the dashboard MUST NOT add load when nobody is viewing it. | MUST |
| STO-7 | **Retention and cleanup.** Per-state retention (defaults: Succeeded 7 d, Cancelled 7 d, DeadLettered 30 d, state history and logs follow the job). Cleanup runs in small paced batches (default 500 rows, short sleep between) so it never spikes I/O. Tables MUST be designed so cleanup hits an index, not a scan. | MUST |
| STO-8 | Published **conformance test suite** (`Bellhop.Storage.Conformance`): an xunit package any store author runs to prove correctness, including concurrency tests for claims, uniqueness and recurring triggers. Community stores (MySQL, MongoDB, others) are welcome and MUST pass it to be listed. | MUST |
| STO-9 | Multi-tenancy: the same store MAY be shared by multiple applications using a configurable `Namespace`; jobs of one namespace are invisible to workers of another. | SHOULD |
| STO-10 | Payload size: a soft limit (default 64 KB) with a warning and a hard limit (default 1 MB) with a clear exception; large data belongs in the application's own storage and the payload carries a reference. | MUST |
| STO-11 | Every store implements the secondary index contract `IJobIndex` (`AddAsync(jobId, index, value)`, `RemoveAsync`, `QueryAsync(index, value, page)`, `CountAsync`) and typed per-job parameters (EXT-6); both are in the conformance suite. Tags (BLT-9) and correlation-id search (BLT-4) are built on the index, so no store needs a tags add-on. | MUST |

### 4.9.1 Redis store (RED)

Package `Bellhop.Redis`. A first-party store with the same semantics as the SQL stores, built on StackExchange.Redis. Durability is weaker than a database and the store says so out loud.

| ID | Requirement | Level |
|---|---|---|
| RED-1 | **Client.** Built on StackExchange.Redis (MIT), minimum 3.4.20 (Valkey version detection fix). Accepts a connection string or an existing `IConnectionMultiplexer` from DI, and MUST reuse the application's multiplexer when one is registered rather than opening a second one. | MUST |
| RED-2 | **Command baseline.** The store uses only: strings (`SET NX PX`, `GET`, `DEL`, `INCR/DECR`, `EXPIRE/PTTL`), hashes (`HSET/HGET/HMGET/HGETALL/HINCRBY/HDEL`, whole-hash `EXPIRE` only), lists (`LPUSH/RPUSH/RPOP/LMOVE/LREM/LRANGE/LLEN`), sorted sets (`ZADD/ZREM/ZSCORE/ZCARD/ZRANGEBYSCORE ... LIMIT/ZREMRANGEBYSCORE/ZPOPMIN/ZRANK`), sets (`SADD/SREM/SMEMBERS/SISMEMBER`), `PUBLISH/SUBSCRIBE`, `EVAL/EVALSHA/SCRIPT LOAD`, `MULTI/EXEC` without `EVAL` inside, database 0 only. It MUST NOT depend on modules, `FUNCTION/FCALL`, Streams, keyspace notifications, hash-field TTL (`HEXPIRE`), `CLIENT TRACKING`, `KEYS`, `ZRANGEBYLEX`, `SELECT`, `WAIT`, atomic `MSET`, or any Redis-8-only command. This is what makes §4.9.2 possible. | MUST |
| RED-3 | **Data model.** Job record as a hash (terminal jobs get a whole-hash `EXPIRE`); per-queue ready list; per-queue working list; scheduled sorted set scored by due time; retry sorted set; lease sorted set scored by deadline; index sorted sets per state, queue and job name scored by timestamp; tag index sets; recurring definitions as hashes plus a sorted set scored by `NextRunAt`; node registry sorted set scored by heartbeat; unique keys as `SET NX PX`; concurrency counters as integers maintained inside scripts. Key layout is documented and versioned. | MUST |
| RED-4 | **Atomicity.** Every state transition (enqueue, claim, heartbeat, complete, fail, retry, cancel, recover, recurring trigger, unique check, concurrency admission) is exactly one Lua script. All keys a script touches MUST be declared in `KEYS`; all keys of one namespace share one hash tag so scripts are Cluster-safe; the current time is passed in `ARGV`, never read with `TIME`; scripts are deterministic, short, and written in the Lua 5.1 and 5.4 common subset (no `bit` library, no `cjson`/`cmsgpack`, no `redis.replicate_commands`, no `redis.setresp`, numbers passed as strings). Scripts are loaded once and invoked with `EVALSHA`, with `NOSCRIPT` fallback. | MUST |
| RED-5 | **Claims and leases.** A claim script moves the job from the ready list to the node's working list and adds it to the lease set with a deadline. Heartbeats update the lease score. Recovery (EXE-4) scans the lease set for deadlines in the past and requeues or dead-letters those jobs. Recovery MUST key off the lease deadline, never the original fetch time, so a healthy long-running job is never requeued. | MUST |
| RED-6 | **Wake-ups.** Enqueue publishes on a per-queue channel; worker nodes subscribe and wake immediately, with polling at `PollInterval` as the fallback. Blocking pops (`BLMOVE`) MAY be used where the server supports them but MUST NOT be required, since some hosted REST modes cannot block. | MUST |
| RED-7 | **Durability disclosure.** At startup the store reads `INFO persistence` and `INFO replication` where available and logs: a WARNING when AOF is off (RDB-only means minutes of loss), a NOTICE that replication is asynchronous and a failover can drop acknowledged writes, and the detected server family and version. The health check reports the persistence mode. The docs state the loss windows plainly and name AWS MemoryDB, ElastiCache for Valkey 9 with synchronous durability, and Kvrocks as the options for durability-critical workloads. | MUST |
| RED-8 | **Flush and eviction resilience.** The store writes a generation marker key. If the marker disappears (FLUSHALL, eviction, restore from an old snapshot) the store logs an ERROR event `StoreWasReset`, re-seeds code-defined recurring jobs and the queue registry, and the health check turns degraded until reconciliation completes. Code-defined recurring jobs are reconciled on startup and periodically (default every 5 minutes), so a flush never silently stops them. At startup the store MUST warn when `maxmemory-policy` is anything other than `noeviction`. | MUST |
| RED-9 | **Topologies.** Standalone, primary/replica with Sentinel, and Cluster MUST all be supported, with TLS and ACL users. The store MUST NOT fail closed on a topology it recognises; correctness comes from RED-4, not from refusing to start. Default key tagging is one hash tag per namespace, which keeps cross-queue operations (uniqueness, global indexes, dashboard counts) atomic at the cost of bounding one namespace to one shard. An opt-in `ShardByQueue` mode uses one tag per queue for higher Cluster throughput; in that mode uniqueness scope is per queue and global dashboard views aggregate across queues. The capacity trade-off is documented on the store's first docs page. | MUST |
| RED-10 | **Store capabilities.** `IJobStore` exposes a capability set (free-text payload search, transactional enqueue, push notifications, result storage). The Redis store reports no free-text payload search and no transactional enqueue; the dashboard hides filters a store cannot serve instead of failing. State, queue, name and tag filters are served from the index sets with paging via `ZRANGE ... LIMIT`; `KEYS` and `SCAN` are never used at request time. | MUST |
| RED-11 | **Retention.** Terminal jobs receive a whole-hash `EXPIRE` and sit in time-scored index sets; a janitor trims indexes in paced batches (`ZRANGEBYSCORE` + `ZREM`, default 500 per pass) following STO-7. Hash-field TTL is never used. Stale node registrations are removed by heartbeat age. | MUST |
| RED-12 | **Transactional enqueue (SCH-8) is not available on Redis.** The docs say so on the store's first page and point to the SQL stores or to an outbox relay sample (write the job to the application database, relay to Redis). | MUST |
| RED-13 | **Memory safety.** Captured logs and results are size-capped with TTLs; the default payload hard limit on Redis is 256 KB; the health check reports `used_memory` against `maxmemory`. | SHOULD |
| RED-14 | **Conformance and chaos.** `Bellhop.Redis` MUST pass `Bellhop.Storage.Conformance` against every Tier 1 and Tier 2 server in §4.9.2, including Sentinel and Cluster topologies for Redis and Valkey, and chaos tests that kill the primary mid-job and force a failover. | MUST |
| RED-15 | **Latency goal.** Enqueue-to-start p50 under 20 ms against a local server with pub/sub wake-ups. | SHOULD |
| RED-16 | **Hybrid notifications.** `UseRedisNotifications()` MAY pair a SQL store that lacks push (SQL Server, SQLite) with Redis pub/sub for sub-100 ms wake-ups while keeping SQL durability. Redis is then a signal, never a source of truth: if it is unavailable the SQL store falls back to polling. | MAY |
| RED-17 | **Key prefix and namespaces.** Key prefix is configurable (default `bellhop:`); STO-9 namespaces map to distinct prefixes and tags so several applications can share one server. | MUST |
| RED-18 | **Server detection.** On connect the store issues `HELLO`/`INFO`, identifies the server family (Redis, Valkey, Garnet, Dragonfly, Kvrocks, KeyDB, Redict, unknown), probes `EVAL` with a trivial script, applies family-specific adjustments from §4.9.2, and prints the family in the startup summary. An unknown family is allowed with a warning; a missing `EVAL` is a startup failure with a message naming the server flag to enable it. | MUST |

### 4.9.2 Redis-compatible servers (RDV)

Support tiers. **Tier 1**: run in CI on every commit, officially supported. **Tier 2**: run in CI nightly, supported with the caveats listed. **Tier 3**: expected to work from the baseline in RED-2, community-reported, not in CI.

| ID | Server | Tier | Requirement | Level |
|---|---|---|---|---|
| RDV-1 | **Valkey** 8.1, 9.0, 9.1 (BSD-3, Linux Foundation) | 1 | The reference target alongside Redis, tested standalone, Sentinel and Cluster. Detection MUST use `HELLO` because `INFO` reports `redis_version 7.2.4`. Docs show ElastiCache, MemoryDB and Memorystore connection examples and recommend Valkey as the default open-source choice. A Valkey GLIDE C# client adapter MAY follow once the client is mature; the store keeps the client behind an internal abstraction to allow it. | MUST |
| RDV-2 | **Redis** 7.2 (last BSD) and 8.x (AGPLv3 option) | 1 | Fully supported. Docs explain that running Redis 8 as a network service does not impose AGPL obligations on the application and note that 7.4 to 7.8 carry only non-OSI licenses. No reliance on Redis 8 built-in modules (Query Engine, JSON) or Redis-8-only commands (`XACKDEL`, `HGETDEL`, `MSETEX`). | MUST |
| RDV-3 | **Garnet** 2.1+ (MIT, Microsoft, .NET) | 2 | Lua is opt-in and slow on Garnet, so RED-18 MUST name `--lua` when `EVAL` is unavailable and the docs MUST say throughput is bounded by Garnet's Lua performance. No Streams, keyspace notifications or `CLIENT TRACKING` (irrelevant by RED-2); no `WAIT`; `MSET` is not atomic (never relied on); RESP3 stays off; Cluster is supported, Sentinel is not. The durability warning (RED-7) names `--aof-commit-wait`. Because Garnet is a NuGet package, `Bellhop.Testing` MAY offer an in-process Garnet fixture so the Redis store can be tested without Docker. | MUST (fixture: MAY) |
| RDV-4 | **Dragonfly** 2.0+ (BSL 1.1, not OSI) | 2 | Supported with the license status stated in the docs. Lua is 5.4, which the RED-4 subset already accommodates. Docs give the recommended server flags (`--cluster_mode=emulated --lock_on_hashtags`) and explain that declared keys avoid the global script lock. `EVAL` inside `MULTI` is never used. Snapshot-only persistence triggers the RED-7 warning. Database 0 only. | MUST |
| RDV-5 | **Apache Kvrocks** 2.14+ (Apache-2.0, RocksDB-backed) | 2 | Supported and documented as the self-hosted durable option. `BRPOPLPUSH` is absent (the store uses `LMOVE/BLMOVE` anyway); keyspace notifications absent (irrelevant); `ZRANGEBYLEX` and `SCAN` semantics differ (never used); hash-field TTL is disabled there (never used). Cluster via the Kvrocks controller and Sentinel for primary/replica are both exercised in CI. | MUST |
| RDV-6 | **KeyDB** 6.3 (BSD-3, no release since 2023-10) | 3 | Works from the Redis 6.2 baseline. Docs flag it as unmaintained with unpatched upstream CVEs and do not recommend new deployments. | SHOULD |
| RDV-7 | **Redict** 7.3 (LGPL-3.0, security-only) | 3 | Works from the Redis 7.2 baseline. Docs note the server license has no effect on the client application. | SHOULD |
| RDV-8 | **Hosted services** | 1/2/3 | AWS ElastiCache for Valkey (Tier 1 via Valkey; serverless is cluster mode, so hash tags apply; synchronous durability on Valkey 9 node-based clusters is called out), AWS MemoryDB (Tier 1; the recommended managed option for durability), GCP Memorystore for Valkey (Tier 1), Azure Managed Redis (Tier 2; both "OSS cluster" and "Enterprise" clustering policies MUST work; Azure Cache for Redis is not targeted because it retires 2027 to 2028), Redis Cloud (Tier 2), Dragonfly Cloud (Tier 2), Upstash over TCP (Tier 3; the REST mode is unsupported because it has no blocking or pub/sub commands). | MUST |
| RDV-9 | **Not targeted** | — | Tendis, Pika/PikiwiDB and other region-specific forks are not tested and not documented. Reports are accepted. | — |
| RDV-10 | **CI matrix** | — | Tier 1 and Tier 2 servers run as a Docker matrix in CI (redis:7.2, redis:8, valkey:8.1, valkey:9, a Valkey cluster, a Redis Sentinel set, Garnet, Dragonfly, Kvrocks) against the conformance suite plus the chaos tests in RED-14; KeyDB and Redict run nightly as a smoke test. A compatibility page in the docs is generated from the CI results and shows the last green date per server. | MUST |

### 4.10 Dashboard (DSH)

| ID | Requirement | Level |
|---|---|---|
| DSH-1 | Separate package `Bellhop.Dashboard`. Mounted with `app.MapBellhopDashboard("/path")` using endpoint routing. Returns an endpoint convention builder so `.RequireAuthorization(...)`, `.AllowAnonymous()` and `.RequireHost(...)` work like any other endpoint. | MUST |
| DSH-2 | **Security default.** In `Development` the dashboard allows anonymous access and logs a notice. In every other environment startup MUST fail with an actionable message unless the endpoint has an authorization requirement or `.AllowAnonymous()` was called explicitly. Authenticated-but-unauthorized requests return 403, not 401. | MUST |
| DSH-3 | Two permission levels: **view** and **operate** (retry, cancel, delete, trigger, pause, edit). A `ReadOnly()` switch and separate policies per level MUST be supported. | MUST |
| DSH-4 | Works behind reverse proxies, `UsePathBase`, IIS virtual directories and Azure Front Door out of the box: relative asset URLs, standard forwarded-headers middleware, no absolute paths baked into assets. All assets are embedded; no CDN. | MUST |
| DSH-5 | Pages: overview (live counts, throughput, failures, nodes); jobs list with filters (state, name, queue, tag, time range, free text over payload where the store supports it, see RED-10); job detail (payload, state timeline, attempts with exceptions, captured logs, progress, parent/children graph, trace id); recurring jobs (next runs with time zone, last outcome, trigger/pause/edit); dead letters with bulk requeue; queues (depth, pause/resume); nodes (heartbeat, concurrency, in-flight). | MUST |
| DSH-6 | **Per-job logs.** Log lines written through the job-scoped `ILogger` during execution MAY be captured to the store (opt-in level, size-capped) and shown on the job page. No special `Console` API is needed. | MUST |
| DSH-7 | Live updates via Server-Sent Events with polling fallback. No SignalR dependency. Dashboard endpoints MUST be excluded from the host's API explorer / Swagger. | MUST |
| DSH-8 | Every list is paginated and every query is index-backed; the dashboard MUST never load an entire table. | MUST |
| DSH-9 | A JSON API under the dashboard path (documented with OpenAPI, same auth) backs the UI and is usable by scripts and a CLI. | SHOULD |
| DSH-10 | Dark and light themes, responsive layout, keyboard navigation, no inline scripts (CSP-friendly). | SHOULD |
| DSH-11 | Deep links: `ConfigureDashboard(d => d.AddJobLink<TJob>(job => url))` adds a link per job type into the application (an order, a tenant). | MAY |
| DSH-12 | **Launch a job by hand.** With operate permission, any registered job can be enqueued or scheduled from the dashboard through a form generated from the payload type (JSON schema derived from the record, with validation). Custom editors per payload type MAY be registered in dashboard options. Details in BLT-8. | MUST |
| DSH-13 | Additional built-in pages from §4.15: Launch (BLT-8), Tags (BLT-9), Throttles (BLT-7), Notifications (BLT-11), Insights (BLT-13), node metrics on the Nodes page (BLT-6). All sit behind the same view and operate permissions. | MUST |

### 4.11 Observability (OBS)

| ID | Requirement | Level |
|---|---|---|
| OBS-1 | Built-in `ActivitySource` (`Bellhop`) with spans for enqueue (producer) and execute (consumer), trace context propagated through the job record and linked, named after OpenTelemetry messaging conventions. No separate package needed. | MUST |
| OBS-2 | Built-in `Meter` (`Bellhop`): counters for enqueued, started, succeeded, failed, retried, dead-lettered, interrupted; histograms for execution duration and scheduling lag (actual start minus scheduled time); observable gauges for queue depth per queue and active workers. | MUST |
| OBS-3 | **No swallowed exceptions.** Every internal failure (store errors, scheduler errors, serialization errors, recovery) logs through `ILogger` with a stable `EventId` and the job id where applicable. An error that would stall processing MUST also flip the health check. | MUST |
| OBS-4 | Job-scoped logging: every log line written during a handler carries `{JobId, JobName, Attempt, Queue}` via a logger scope. | MUST |
| OBS-5 | `AddBellhopHealthCheck()`: store reachable, schema version matches, worker loop alive, scheduling lag under a threshold, dead-letter growth under a threshold. | MUST |
| OBS-6 | Events via `IJobEvents` (RET-6) for custom alerting. | SHOULD |

### 4.12 Testing support (TST)

| ID | Requirement | Level |
|---|---|---|
| TST-1 | No static or ambient state anywhere in the library. Two independent Bellhop instances MUST be able to run in one process (multi-storage, multi-test). | MUST |
| TST-2 | `IJobClient` and `IRecurringJobManager` are interfaces with ordinary methods (no extension-method-only API) so standard mocking works. | MUST |
| TST-3 | `Bellhop.Testing` provides: a deterministic in-memory store, integration with `FakeTimeProvider`, a `BellhopTestHarness` with `RunPendingAsync()` / `AdvanceTimeAsync(...)` to drain jobs synchronously, and assertion helpers (`harness.Enqueued<SendWelcomeEmail>().Should().ContainSingle(...)`). | MUST |
| TST-4 | Execution mode `Inline`: `EnqueueAsync` runs the handler immediately on the caller's thread and propagates exceptions. For integration tests and local scripts. | MUST |
| TST-5 | Handlers are plain classes; `JobContext.CreateForTest(...)` builds a context without infrastructure. | MUST |
| TST-6 | A published `Testcontainers`-based integration sample for PostgreSQL and SQL Server. | SHOULD |

### 4.13 Extensibility (EXT)

All extension in Bellhop happens through these DI-registered hooks and the JSON API (DSH-9). There is no plugin manifest or asset pipeline (ADR-3).

| ID | Requirement | Level |
|---|---|---|
| EXT-1 | Execution middleware: `IJobMiddleware` with `InvokeAsync(JobExecutionContext ctx, JobExecutionDelegate next)`, resolved from DI per execution (scoped services work), ordered by registration, filterable per job type. This replaces attribute filters. | MUST |
| EXT-2 | Enqueue middleware: `IEnqueueMiddleware` to stamp tags, tenant ids or correlation data on every job created. | SHOULD |
| EXT-3 | Replaceable serializer (`IJobSerializer`) with System.Text.Json as default. | SHOULD |
| EXT-4 | Replaceable store (STO-1) and retry policy (RET-2). | MUST |
| EXT-5 | Multi-tenant hooks: a middleware sample that restores tenant context from a tag is part of the docs. | SHOULD |
| EXT-6 | Typed per-job parameters: `ctx.Parameters.Set<T>(key, value)` / `Get<T>(key)`, persisted with the job, visible on the job page, available to middleware at enqueue and execution time. Correlation ids, launch principals and HTTP job responses use them. | MUST |

### 4.14 Security (SEC)

| ID | Requirement | Level |
|---|---|---|
| SEC-1 | Dashboard secure by default (DSH-2, DSH-3). | MUST |
| SEC-2 | Deserialization never honours type names from stored data (JOB-4). Handler types are resolved only from the registered job name table. | MUST |
| SEC-3 | Sensitive payload masking (JOB-9). | SHOULD |
| SEC-4 | Minimal dependency surface: core depends only on `Microsoft.Extensions.*` abstractions and the BCL. Dependencies are kept current and the project runs a vulnerability scan in CI. | MUST |
| SEC-5 | Connection strings and secrets never appear in logs, the startup summary or the dashboard. | MUST |
| SEC-6 | Outbound HTTP from HTTP jobs (BLT-12) and notification webhooks (BLT-11): an allowlist of destination hosts (default: none allowed until configured), private-network and loopback targets blocked unless explicitly allowed, redirects limited and never across hosts, credentials only through named `HttpClient` registrations (never in payloads or configuration templates), `[Sensitive]` masking applied to headers in the dashboard and logs. | MUST |

### 4.15 Built-in replacements for the Hangfire plugin ecosystem (BLT)

Bellhop has no plugin system (ADR-3). Instead, the functionality people install as Hangfire plugins ships in the box, versioned and tested with the host. Each row names the plugins it replaces (evidence and download counts in research.md §3) and what "same or better" means. Extension for anything not listed goes through the DI hooks in §4.13 and the JSON API in DSH-9.

| ID | Replaces | Requirement | Level |
|---|---|---|---|
| BLT-1 | Hangfire.Console and forks, Console.Extensions, JobsLogger, Bonura.JobLogs | **Per-job logs and progress.** Every line written to the job-scoped `ILogger` (JOB-6, OBS-4) at or above a configurable level (default Information) is captured to the store with timestamp, level, category and structured properties; capped per job (default 256 KB, then truncated with a marker); retained with the job (STO-7); streamed live to the job page (DSH-7); searchable within the job. `ctx.ReportProgressAsync(fraction, message)` renders a progress bar in lists and on the job page. Capture is an `ILoggerProvider` scoped by job id, so Serilog, NLog and every other provider keep working and no special console API exists. Capture can be disabled per job type or globally. | MUST |
| BLT-2 | Dashboard.BasicAuthorization, Dashboard.Basic.Authentication, Dashboard.Authorization, Soenneker.BasicAuthentication | **Dashboard auth presets.** On top of host policies (DSH-1 to DSH-3), one-line presets on the endpoint builder: `RequireBasicAuth()` with users from configuration as salted PBKDF2 or Argon2 hashes (never plain text; a helper and the CLI produce hashes), constant-time comparison and failed-attempt rate limiting; `RequireApiKey()` for scripts and the CLI against the JSON API; `RequireRole(...)` and `RequireClaim(...)` shortcuts mapped to view and operate. | MUST |
| BLT-3 | Hangfire.Autofac, Ninject, SimpleInjector, Unity, Windsor, StructureMap, Lamar, DryIoc, LightInject | **DI without adapters.** Handlers and middleware resolve from `IServiceProvider` in a scope per execution (JOB-1), so any container with an `IServiceProviderFactory` (Autofac, Lamar, DryIoc) works unchanged. `IAsyncDisposable` services are disposed asynchronously. | MUST |
| BLT-4 | OpenTelemetry.Instrumentation.Hangfire, Hangfire.Correlate, Extensions.ApplicationInsights | **Tracing and correlation.** OBS-1 spans and links are built in. A `CorrelationId` is captured at enqueue from the current `Activity`, or from a configurable accessor or header, and is exposed on `JobContext`, in the logger scope, in the dashboard (with a filter), and propagated to continuations and to jobs enqueued from handlers. Application Insights and other vendors receive data through OpenTelemetry; no bridge package. | MUST |
| BLT-5 | AspNetCore.HealthChecks.Hangfire, Hangfire.Prometheus.NetCore, elmah.io heartbeats | **Health and metrics.** OBS-5 health check with configurable thresholds (failures in a window, dead-letter count, scheduling lag, nodes alive, store reachable). The OBS-2 meter exports to Prometheus through the standard OpenTelemetry exporter, shown as a two-line setup in the docs. Missed-run alerts for recurring jobs come from BLT-11. | MUST |
| BLT-6 | Hangfire.Heartbeat | **Node metrics.** The Nodes page shows, per node, process CPU, working set, GC heap, thread-pool queue length, worker utilisation (busy of max) and in-flight jobs, with a 24-hour history chart from samples kept in the store (interval default 15 s, retention 7 days, one batched write per interval). | MUST |
| BLT-7 | Hangfire.MaximumConcurrentExecutions, Hangfire.Throttling | **Throttling.** CON-3 mutexes and semaphores and CON-4 fixed and sliding window rate limits ship in 1.0, free and store-enforced, with **dynamic limits**: a limit can be changed at runtime from the API or the Throttles page without redeploying. The page shows current holders, waiting counts and recent waits per key. | MUST |
| BLT-8 | Dashboard.Management.v2 and v1, MissionControl, Community.Forms, Community.JobsLauncher | **Launch page.** DSH-12 form generation plus: jobs opt in with `[Launchable(Category = "...", Description = "...")]` or a global "all jobs launchable" switch; fields derive from the payload record and `System.ComponentModel.DataAnnotations` (`[Display]`, `[Required]`, `[Range]`, `[StringLength]`, `[DataType]`) for labels, validation, enum dropdowns, dates with time zone, nullable fields, nested records and collections; "Run now", "Schedule for" and "Make recurring" from the same form; a Recent launches list that records who launched what (principal name stored on the job). | MUST |
| BLT-9 | FaceIT.Hangfire.Tags plus 8 per-storage packages, a2n.Tags | **Tags.** Tags are `key` or `key:value` strings set at enqueue (`EnqueueOptions.Tags`), by attributes on the job type, by enqueue middleware, or from the handler (`ctx.Tags.AddAsync`). The dashboard has a Tags page with counts and click-through, tag filters on every job list, bulk actions by tag (requeue, cancel, delete) and per-tag success and failure counts. Built on the store-agnostic index (STO-11), so every store supports it identically and no per-store package exists. | MUST |
| BLT-10 | Hangfire.RecurringJobAdmin, RecurringJobExtensions, Be.Auto.RecurringJobManager, RecurringDateRange | **Recurring job management.** REC-9 in the dashboard: create and edit runtime-defined recurring jobs with a cron builder that previews the next five occurrences in the chosen time zone; pause, resume, trigger now with an edited payload; a validity window (`ActiveFrom`, `ActiveUntil`); the last 50 occurrences with outcome and duration; per-job misfire and overlap settings. Recurring jobs MAY also be defined in configuration (`Bellhop:RecurringJobs`) with `IOptionsMonitor` hot reload, so a schedule change needs no restart. Code-defined jobs are read-only in the UI unless `AllowRuntimeOverride` (REC-3). | MUST |
| BLT-11 | Hangfire.HttpJob email alerts, TickerQ.Integrations, elmah.io heartbeats | **Notifications.** A rules engine on `IJobEvents` (RET-6) with triggers: job dead-lettered, job failed N times, failure rate above a threshold in a window, recurring job missed or late by more than a tolerance, node lost, queue depth above a threshold, throttle key starved. Channels: generic JSON webhook with a message template, Slack and Microsoft Teams incoming-webhook presets, `ILogger` critical, and SMTP email. Rules live in configuration or code, appear on a Notifications page with a "send test" button, and deliveries are rate-limited and deduplicated per rule and subject within a cooldown. | MUST (SMTP: SHOULD) |
| BLT-12 | Hangfire.HttpJob | **HTTP jobs.** A built-in `HttpRequestJob` payload (method, URL, headers, body, content type, named `HttpClient` for credentials, timeout, accepted status codes, optional success predicate on the body, response capture limit) that can be enqueued, scheduled or made recurring from code, from the launch page and from configuration. The response (status, headers, truncated body) is stored as the job result and shown on the job page. Security rules are in SEC-6. Remote "agents" from HttpJob are out of scope. | MUST |
| BLT-13 | Community.Dashboard.Heatmap, Community.JobsInsights, custom `DashboardMetrics` users | **Insights.** Store-backed rollups (per minute for 24 hours, per hour for 30 days) of enqueued, succeeded, failed and dead-lettered counts and duration percentiles per job name and per queue, driving an overview throughput chart, a 7-day heatmap by hour, per-job-name tables (p50 and p95 duration, failure rate, trend) and a slowest and most-failing jobs list. Rollups are computed by one node under a lease (CON-7) in one batched write per interval. | SHOULD |
| BLT-14 | Hangfire.StackTrace | **Readable failures.** Attempt details show the exception chain with inner exceptions and `AggregateException` flattened, async state-machine frames collapsed, the job's own frames highlighted, and a copy button. The raw stack trace stays available. | SHOULD |
| BLT-15 | Dashboard.Dark, Dashboard.Customize, Dashboard.Resources, themed forks | **Branding and localisation.** Dark, light and system themes (DSH-10); title, logo, favicon and accent colour from options; a display name per job type (`[JobName("...", Display = "...")]`); every UI string in a resource bundle with English built in and other languages added as JSON bundles through options or contributed upstream; dates shown in the browser's time zone with the server zone on hover. | SHOULD |
| BLT-16 | Bonura.PerformContextAccessor, Console.Extensions accessor | **`IJobContextAccessor`.** An `AsyncLocal`-backed accessor so services deep in the call stack can read the current `JobContext` (id, logger, progress, cancellation, tags) without threading parameters. | MUST |
| BLT-17 | Hangfire.Community.Outbox | **Outbox mode.** For stores without transactional enqueue (Redis, RED-12) or when the application database differs from the job database, `Bellhop.EntityFrameworkCore` provides an outbox table in the application's `DbContext` and a relay process (one node under a lease, batched, idempotent by outbox id) that moves rows into the job store. `dbContext.EnqueueAsync` uses the direct transactional path when the store shares the database and the outbox otherwise, chosen by configuration. | SHOULD |
| BLT-18 | Hangfire.MAMQSqlExtension, Soenneker.SkipMissedRuns, Effektor.Idempotent, Extensions.Configuration, Hangfire.DynamicJobs | **Already covered elsewhere.** Multi-app shared store: STO-9. Skip missed runs: REC-5. Idempotency: SCH-5. Options from configuration: SET-3. Jobs by type-name strings (DynamicJobs) are deliberately unsupported (JOB-2); the launch page and HTTP jobs cover the ad hoc need. | — |
| BLT-19 | Nall.Hangfire.Mcp | **MCP server.** A Model Context Protocol server over the dashboard JSON API (list, inspect, requeue, trigger, pause, with the same permissions and API keys from BLT-2) so coding agents and assistants can operate jobs. | MAY (1.x) |

**Not carried over, and why.** PowerShellExecutor: arbitrary script execution is a security liability; HTTP jobs and the launch page cover the need. HttpJob remote agents: a remote-execution product, out of scope. Hangfire.Atoms DAGs: chains and batches (WF-1 to WF-3) cover the common cases; general DAG workflows stay out of scope. MediatR bridge and carbon-aware scheduling: ten-line samples in the docs using execution middleware and `ISchedule` (REC-11).

**What stays extensible without a plugin system.** Execution and enqueue middleware (EXT-1, EXT-2), job events (RET-6), serializer (EXT-3), store (STO-1), retry policy (RET-2), schedule types (REC-11), per-job parameters (EXT-6), job deep links (DSH-11), custom payload editors (DSH-12), and the JSON API (DSH-9) for teams that want their own pages. All of these are registered through DI and need no manifest, no asset pipeline and no compatibility matrix.

---

## 5. Non-functional requirements (NFR)

| ID | Requirement | Level |
|---|---|---|
| NFR-1 | **Targets:** `net8.0` and `net10.0` (both LTS). No .NET Framework. Trimming-safe core; Native AOT supported when a `JsonSerializerContext` is supplied. | MUST (AOT: SHOULD) |
| NFR-2 | **Performance goals** on PostgreSQL, modest hardware, one node: enqueue p50 < 2 ms; schedule-to-start lag p50 < 100 ms with notifications and < `PollInterval` without; ≥ 1,000 no-op jobs/s per node; 1-second cron punctuality ≥ 99%. A public benchmark harness that actually executes jobs on every side ships in the repo. | SHOULD |
| NFR-3 | **Zero-tuning defaults.** A deployment of 3 nodes and 100 jobs/minute MUST run correctly and quietly on defaults. Tunables exist but are documented as "you probably don't need this". | MUST |
| NFR-4 | **Resource footprint:** idle CPU indistinguishable from an idle host; memory proportional to in-flight jobs, not to history. | MUST |
| NFR-5 | **Versioning:** strict SemVer. No breaking change in a minor or patch release, including attribute shapes, option names, table layout and dashboard auth behaviour. Deprecations ship with analyzer warnings one minor before removal. Every major has an upgrade guide and a breaking-change list. Every release has a changelog entry. | MUST |
| NFR-6 | **Documentation:** a getting-started page that matches §3 exactly and can be completed in five minutes; a concepts page for at-least-once, leases, misfire, overlap, time zones; a reference listing every option with its default; a samples repo (web, worker service, multi-tenant, transactional enqueue, tests). Docs are versioned with the code and verified by a doc-snippet compile step in CI. | MUST |
| NFR-7 | **License and governance:** MIT, for all packages, permanently. No runtime license checks, no telemetry, no paid feature tier. Contributions under DCO (no CLA that permits relicensing). Public roadmap and issue triage SLA stated in the README. | MUST |
| NFR-8 | **Compatibility of state across deploys:** rolling deploy between adjacent versions works (STO-5); jobs enqueued by version N run on version N+1. | MUST |
| NFR-9 | **Quality gates:** store conformance suite, concurrency/chaos tests (kill nodes mid-job, clock skew, duplicate starts), and a nightly multi-node soak test in CI. | SHOULD |

---

## 6. Packaging

| Package | Contents |
|---|---|
| `Bellhop` | Abstractions, engine, hosting integration, in-memory store, analyzers, OpenTelemetry instrumentation, health check, throttling, notifications, HTTP jobs, `IJobContextAccessor` |
| `Bellhop.PostgreSql` | PostgreSQL store with `LISTEN/NOTIFY` |
| `Bellhop.SqlServer` | SQL Server store |
| `Bellhop.Sqlite` | SQLite store (single node) |
| `Bellhop.Redis` | Redis / Valkey / Garnet / Dragonfly / Kvrocks store and optional notification transport |
| `Bellhop.Dashboard` | ASP.NET Core dashboard and JSON API, including the Launch, Tags, Throttles, Notifications, Insights and Nodes pages and the auth presets |
| `Bellhop.EntityFrameworkCore` | Transactional enqueue helper for `DbContext` users and the outbox relay (BLT-17) |
| `Bellhop.Testing` | Test harness, fake time integration, assertions, optional in-process Garnet fixture |
| `Bellhop.Storage.Conformance` | Test suite for store authors |
| `Bellhop.Mcp` | MCP server over the JSON API (MAY, 1.x, BLT-19) |
| `Bellhop.Cli` (dotnet tool) | Schema script export, requeue dead letters, inspect jobs (MAY, post-1.0) |

All packages share one version number (SET-9).

---

## 7. Non-goals (v1)

- Message bus, pub/sub, or cross-language job execution
- Sagas, compensation, human-in-the-loop workflows
- Exactly-once execution guarantees (at-least-once plus idempotency tooling instead)
- MongoDB and MySQL stores as first-party (community via STO-8)
- A hosted SaaS control plane
- Vendor-specific notification SDKs; notifications use webhooks (with Slack and Teams presets), SMTP and `ILogger` (BLT-11)
- A plugin API for third-party dashboard pages, job states or claim semantics (ADR-3); extension is through DI hooks (§4.13) and the JSON API (DSH-9)
- Remote execution agents and arbitrary script execution from the dashboard
- Windows-specific features (performance counters, MSMQ)
- Supporting Hangfire's expression-based `Enqueue(() => ...)` API; a migration guide is provided

---

## 8. Phasing

| Milestone | Scope |
|---|---|
| **M1 — Core (preview)** | Middleware, events, parameter and index hooks; job model, `IJobClient`, in-memory and PostgreSQL stores, fire-and-forget, delayed, recurring with misfire and overlap policies, retries and dead letters, leases and recovery, OpenTelemetry, health check, `Bellhop.Testing`, read-only dashboard |
| **M2 — 1.0** | SQL Server, SQLite and Redis stores (Tier 1 servers in CI), continuations/chains/batches, unique keys, concurrency keys, full dashboard with operate actions, built-in features BLT-1 to BLT-12 (captured logs, auth presets, correlation, node metrics, throttling with dynamic limits, launch page, tags, recurring management, notifications, HTTP jobs), EF Core transactional enqueue, analyzers, conformance suite, docs and samples, benchmark harness |
| **M3 — 1.x** | BLT-13 to BLT-19 (insights rollups, readable failures, branding and localisation bundles, outbox mode, SMTP channel, MCP server); Tier 2 Redis-compatible servers in CI; in-process Garnet test fixture; CLI tool; Native AOT verification; community stores listed after passing conformance |

---

## 9. Open questions

1. ~~Confirm the name **Bellhop** and the root namespace.~~ **Resolved 2026-11-03:** Bellhop, root namespace `Bellhop`.
2. ~~PostgreSQL as the reference store first, SQL Server second?~~ **Resolved 2026-11-03:** yes, as proposed.
3. ~~Dashboard front-end stack.~~ **Resolved 2026-11-03:** framework-free, embedded bundle under 300 KB, no runtime CDN.
4. ~~Should `AutoMigrate` default to true in all environments?~~ **Resolved 2026-11-03:** true everywhere, with the script export documented on the first page.
5. ~~Default succeeded-job retention: 24 h versus 7 d.~~ **Resolved 2026-11-03:** 7 days by default, configurable (STO-7 updated).
6. Is a Hangfire migration adapter (`Enqueue(() => ...)` sugar backed by Bellhop) worth shipping as a separate, clearly "legacy" package?
7. Redis store in 1.0 or 1.1? (Proposed: 1.0 for Redis and Valkey, with Garnet, Dragonfly and Kvrocks promoted to Tier 2 in 1.x once the CI matrix is stable.)
8. Should Dragonfly, which is not open source (BSL 1.1), be listed as supported at all, or only as "known to work"? (Proposed: Tier 2 with the license stated, since the derivative list is about protocol compatibility, not endorsement.)
9. Should every registered job be launchable from the dashboard by default, or only those marked `[Launchable]`? (Proposed: opt-in by attribute with a global switch, so a payload with side effects is never one click away by accident.)
10. Which notification channels ship in 1.0? (Proposed: generic webhook plus Slack and Teams presets and `ILogger` in 1.0; SMTP in 1.x.)
11. HTTP jobs in core or in a separate `Bellhop.Http` package? (Proposed: core, because the only dependency is `Microsoft.Extensions.Http`, and SEC-6 keeps it safe by default.)

---

## Appendix A — Design decisions

### ADR-1: Do not build on a distributed-lock library

**Context.** madelson/DistributedLock (MIT, v2.8.3 released 2026-07, 10.8M NuGet downloads) is the de facto .NET library for named mutexes, reader-writer locks and semaphores over SQL Server, PostgreSQL, MySQL, Oracle, Redis (RedLock), Azure Blobs, MongoDB, ZooKeeper and files. The question was whether Bellhop should use it instead of implementing its own coordination.

A held lock in that library is either an open database connection holding an advisory lock or `sp_getapplock` (relational providers), or a TTL key renewed by a background task (Redis: 30 s expiry, extended roughly every 9 s). The Postgres provider has no semaphore. Locks are invisible to anything but the holder.

**Where Bellhop needs coordination, and whether a lock is the right primitive:**

| Need | What Bellhop does | Would a lock fit? |
|---|---|---|
| Claim a job exactly once (EXE-2) | One atomic claim statement (`SKIP LOCKED`, `READPAST`, or a Lua script) | No. The claim *is* the update; a lock around it adds a round-trip and nothing else. |
| Keep ownership of a running job and recover after a crash (EXE-3, EXE-4) | Lease timestamp on the job row, renewed by heartbeat; any node reclaims expired leases | Poorly. A connection-held lock per in-flight job means one open connection per running job, and ownership would be invisible to the dashboard and to recovery. The Redis RedLock variant is closer but is a second key that must stay in sync with the job record. |
| Trigger a recurring job exactly once across nodes (REC-7) | Compare-and-set on `NextRunAt` | No lock needed. |
| Overlap policy for recurring jobs (REC-6) | The claim predicate excludes jobs whose previous occurrence is still active | This is exactly Hangfire's `DisableConcurrentExecution` design, and it is the Hangfire lock-timeout problem documented in research.md (grievance H2): timeouts turn into failures and retries. |
| Concurrency keys: mutex or semaphore across nodes (CON-3) | Admission counter checked inside the claim; blocked jobs simply stay queued | A semaphore acquired by the worker either blocks a worker slot (head-of-line blocking) or hands the job back to the queue (churn). Store-side admission has neither problem. |
| Run cleanup on one node at a time (EXE-10) | A short lease row in the nodes table, about thirty lines of code | Yes, this is the one place it would fit, at the cost of one extra package per store provider. |
| Startup reconciliation (REC-3) | Idempotent upsert by name | No lock needed. |

**Decision.** Bellhop's core and first-party stores do not depend on DistributedLock. Bellhop's primitive is *ownership recorded in the store with an expiry*, not *mutual exclusion held by a live connection*. The two overlap only for cleanup leadership, which is not worth a dependency, and the core must stay free of provider clients such as Npgsql or StackExchange.Redis (SEC-4). The in-memory and SQLite stores also have no advisory-lock equivalent, so the engine would still need its own path.

**Where the library is the right tool, and Bellhop recommends it rather than wrapping it:**

- Handler code that must serialize access to an external resource (a third-party API, a file share). The docs show `IDistributedLockProvider` injected next to `IJobClient`, pointed at the same connection string.
- A documented execution-middleware sample (`[Lock("name")]`, §4.13) for teams that prefer Hangfire's lock model. A sample in the docs, not core.

**Consequence.** Requirement CON-7 is added: all coordination lives in the job store, and no first-party package requires an external lock service.

### ADR-2: Redis store uses sorted sets, lists and Lua scripts, not Streams

**Context.** Redis Streams with consumer groups offer a built-in pending-entries list and `XAUTOCLAIM`, which looks like a ready-made lease mechanism. The alternative is the pattern used by BullMQ and Asynq: lists for ready and working jobs, sorted sets for delayed, retry and lease tracking, and a Lua script per state transition.

**Decision.** Sorted sets, lists, hashes and Lua scripts (RED-2 to RED-5). No Streams.

**Reasons.**

- **Portability.** Streams are missing on Garnet, partial on Dragonfly, young on Kvrocks (consumer-group commands arrived in 2.10 with fixes still landing in 2.16 and 2.17), and unusable over Upstash REST. Sorted sets, lists and `EVAL` exist on every server in research.md §2.
- **Modelling.** Streams do not model delay, priority, uniqueness or per-queue ordering; all of those need sorted sets and scripts anyway, so Streams would be a second mechanism rather than a replacement.
- **Deleting before ack.** Removing a specific pending entry needs `XACKDEL`, which exists only in Redis 8.2 and later.
- **Equivalence.** A lease sorted set scored by deadline gives the same crash recovery as `XAUTOCLAIM`, with the deadline visible to the dashboard and to every node.

**Consequences.** Every transition is one script with declared keys under one hash tag (RED-4). Cluster throughput per namespace is bounded by one shard, with `ShardByQueue` as the escape hatch (RED-9). The Lua subset rule in RED-4 is what keeps Dragonfly (Lua 5.4) and Garnet (opt-in Lua) on the supported list.

### ADR-3: No plugin system; the popular plugin functionality is built in

**Context.** An earlier draft of this document (2026-11-03, same day) proposed a manifest-based plugin system: typed back-end hooks, typed dashboard extension kinds, a declarative no-JavaScript UI schema, an ES-module SDK, error boundaries, namespaced additive registration, a Plugins admin page, a test host and a project template. The research in research.md §3 that motivated it also showed what the Hangfire ecosystem is actually used for.

**Decision.** Taken by the project owner on 2026-11-03: Bellhop ships no plugin API. The functionality of the most-installed Hangfire plugins is built in (§4.15). Extension is limited to DI-level hooks (§4.13) and the JSON API (DSH-9).

**Reasons.**

- **The download data.** The top plugins (dashboard auth with about 25M combined downloads, Console with 28.6M, concurrency limits, tags, recurring-job UIs, launch forms) all fill gaps that belong in core, and several are abandoned. A plugin system would mostly re-create the same gaps for someone else to fill.
- **A plugin API is a public contract.** Hangfire's broke on every markup change and shipped one page of documentation. Supporting abstractions packages, a JavaScript SDK, a declarative renderer, a test host and a template is a large fixed cost before 1.0 and a permanent compatibility matrix afterwards (NFR-5).
- **Built-in features are better features.** They can use internal APIs, ship with the host's tests, are versioned with the host, and appear in one package set with one version number (SET-9). Users get no "which plugin version works with which host version" question.
- **The remaining extension needs are small.** Middleware, events, custom stores, custom schedules and a documented JSON API cover correlation, tenant context, alerting bridges, custom calendars and custom pages without a manifest.

**Consequences.** More scope in core: BLT-1 to BLT-12 in 1.0 and BLT-13 to BLT-19 in 1.x (§8). The JSON API (DSH-9) is the official route for custom UI and becomes a public contract. Third-party dashboard pages inside the Bellhop shell are not possible; teams build them in their own application against the API. The decision can be revisited after 1.0 if demand for third-party pages appears; the earlier design's core ideas (typed contributions registered through DI, declarative data-driven panels, error boundaries, no host markup access) are the starting point if it is.
