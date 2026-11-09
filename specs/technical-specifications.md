# Technical specifications — Bellhop

Format: refiner-tech/1

## TECH-1 — Target frameworks

- **Area:** runtime
- **Statement:** Every Bellhop package shall target .NET 8 and .NET 10 (both LTS).
- **Version:** net8.0, net10.0
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-1 — "Targets: net8.0 and net10.0 (both LTS)."

## TECH-2 — No .NET Framework

- **Area:** runtime
- **Statement:** No Bellhop package shall target .NET Framework.
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-1 — "No .NET Framework."

## TECH-3 — Trimming-safe core

- **Area:** runtime
- **Statement:** The core package shall be safe for IL trimming.
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-1 — "Trimming-safe core"

## TECH-4 — Native AOT

- **Area:** runtime
- **Statement:** The core package shall support Native AOT when the application supplies a JsonSerializerContext.
- **Applies to:** system, TECH-6
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §5 NFR-1 — "Native AOT supported when a JsonSerializerContext is supplied." ; requirements.md §8 — "Native AOT verification" (M3)
- **Notes:** A source generator MAY later be offered purely for AOT registration (JOB-1).

## TECH-5 — Payload serializer

- **Area:** library
- **Statement:** The core package shall use System.Text.Json as the default payload serializer, storing plain contracts without type names.
- **Applies to:** jobs, INV-120, INV-121
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.2 JOB-4 — "Payloads MUST be serialized with System.Text.Json as plain contracts: no type names"

## TECH-6 — Serializer options and polymorphism

- **Area:** library
- **Statement:** The core package shall serialize polymorphic payloads only when the user opts in with [JsonDerivedType], and shall accept user-supplied JsonSerializerOptions or a JsonSerializerContext.
- **Applies to:** TECH-5
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.2 JOB-4 — "no polymorphism unless the user opts in with [JsonDerivedType] ... Users MAY supply JsonSerializerOptions or a JsonSerializerContext (AOT)."

## TECH-7 — Replaceable serializer

- **Area:** library
- **Statement:** The core package shall use an IJobSerializer abstraction so the System.Text.Json default can be replaced.
- **Applies to:** TECH-5
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.13 EXT-3

## TECH-8 — Core dependency surface

- **Area:** library
- **Statement:** The core package shall depend only on the BCL and Microsoft.Extensions.* abstractions.
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.14 SEC-4 — "core depends only on Microsoft.Extensions.* abstractions and the BCL"
- **Rationale:** Keeps provider clients such as Npgsql or StackExchange.Redis out of the core (ADR-1).

## TECH-9 — No ASP.NET Core or EF Core in core

- **Area:** framework
- **Statement:** The core package shall not depend on ASP.NET Core or Entity Framework Core.
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.1 SET-6; §2 P4 — "no EF Core or ASP.NET Core dependency in the core"

## TECH-10 — Options binding

- **Area:** library
- **Statement:** The core package shall bind options from Microsoft.Extensions.Configuration under the "Bellhop" section and validate them with ValidateOnStart.
- **Applies to:** REQ-9, REQ-17
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.1 SET-3

## TECH-11 — Hosted service registration

- **Area:** framework
- **Statement:** AddBellhop shall register the Bellhop hosted service with Microsoft.Extensions.Hosting, and AddWorker its worker loop and background duties, so the developer never registers a hosted service by hand.
- **Applies to:** REQ-12, REQ-18, REQ-52, NFR-1
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §3 — "Things the developer did not have to do: ... register a hosted service"; §4.1 SET-5

## TECH-12 — Time source

- **Area:** library
- **Statement:** The core package shall take all time from System.TimeProvider.
- **Applies to:** system, INV-105
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.5 EXE-9 — "Time MUST come from TimeProvider."; §2 P7

## TECH-13 — Dependency injection containers

- **Area:** framework
- **Statement:** The core package shall resolve handlers and middleware from IServiceProvider so that any container with an IServiceProviderFactory works without an adapter.
- **Applies to:** INV-122
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-3 — "any container with an IServiceProviderFactory (Autofac, Lamar, DryIoc) works unchanged"

## TECH-14 — Job definition contract

- **Area:** other
- **Statement:** The core package shall define a job as a serializable type implementing IJob or IJob<TResult> and its behaviour as a class implementing IJobHandler<TJob>, with no source generator or expression capture required.
- **Applies to:** jobs, REQ-3
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.2 JOB-1; §2 P2 — "A job is a plain data type with a handler. No expression trees, no magic strings, no generator-only paths."

## TECH-15 — Handler signature

- **Area:** other
- **Statement:** The core package shall support exactly one handler shape, Task HandleAsync(TJob job, JobContext ctx, CancellationToken ct), and Task<TResult> for result jobs.
- **Applies to:** TECH-14
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.2 JOB-5 — "No other shape is supported."

## TECH-16 — JobContext members

- **Area:** other
- **Statement:** JobContext shall expose the job id, name, attempt number, max attempts, enqueue time, scheduled time, queue, tags, parent and batch ids, correlation id, parameters, a job-scoped ILogger, ReportProgressAsync(double, string?) and the trace context.
- **Applies to:** TECH-15, REQ-166, REQ-168
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.2 JOB-6; §4.15 BLT-4; §4.13 EXT-6

## TECH-17 — Job metadata attributes

- **Area:** other
- **Statement:** The core package shall provide the data-only attributes [Queue], [Priority], [Retry], [Timeout], [Unique], [Concurrency] and [Recurring], each also settable fluently in AddBellhop.
- **Applies to:** INV-123
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.2 JOB-7 — "Attributes are data only; they never execute code."

## TECH-18 — JobName attribute

- **Area:** other
- **Statement:** The core package shall provide [JobName("...")] with Aliases and Display properties.
- **Applies to:** REQ-101, REQ-331
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.2 JOB-2, JOB-3; §4.15 BLT-15

## TECH-19 — IJobClient

- **Area:** other
- **Statement:** The core package shall expose all scheduling through an injectable IJobClient interface with ordinary methods (EnqueueAsync, EnqueueManyAsync, ScheduleAsync with at or delay, ContinueWithAsync, ChainAsync, CreateBatchAsync(name, jobs, continuations), CancelAsync, RequeueAsync, RequeueDeadLetteredAsync(filter), DeleteAsync, GetAsync, WaitForCompletionAsync, GetResultAsync<T>) and no static entry point.
- **Applies to:** jobs
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.3 intro — "All scheduling goes through IJobClient (injectable, mockable). There is no static entry point."; §4.3 SCH-1 to SCH-3, SCH-6, SCH-7, SCH-9; §4.8 WF-2; §4.12 TST-2
- **Notes:** Decided by the owner on 2026-11-06: CreateBatchAsync (WF-3, jobs REQ-177) and RequeueDeadLetteredAsync for bulk requeue by name, queue, tag or time range (RET-5, jobs REQ-142) live on IJobClient; the source named neither. Batches cannot be extended (jobs REQ-178 retired), so there is no AddToBatch.

## TECH-20 — EnqueueOptions

- **Area:** other
- **Statement:** EnqueueOptions shall carry queue, priority, unique key and duplicate policy, key/value tags, timeout, retry policy override, concurrency key and an explicit database transaction.
- **Applies to:** TECH-19, REQ-150, INV-101
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.3 SCH-4

## TECH-21 — IRecurringJobManager

- **Area:** other
- **Statement:** The core package shall expose an IRecurringJobManager interface with ordinary methods for add-or-update, remove, trigger now with an optional payload, pause, resume, list, next N occurrences and last outcome.
- **Applies to:** recurring
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.4 REC-9; §4.12 TST-2

## TECH-22 — Job registration API

- **Area:** other
- **Statement:** AddBellhop shall offer AddJobsFromAssemblyContaining<T>(), working across several assemblies, AddJob<TJob, THandler>() and AddRecurring<TJob>(name, schedule, job?, options?).
- **Applies to:** jobs, recurring
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.1 SET-10 — "Scanning across multiple assemblies MUST work (plugin architectures)."; §4.4 REC-1

## TECH-23 — Schedule syntax

- **Area:** protocol
- **Statement:** The recurring scheduler shall accept 5- and 6-field cron expressions (seconds optional), fixed intervals with Every(TimeSpan), and readable helpers such as Cron.Daily(hour: 3).
- **Applies to:** recurring, REQ-209, REQ-210
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.4 REC-2

## TECH-24 — Time zone identifiers

- **Area:** protocol
- **Statement:** The recurring scheduler shall identify time zones by IANA time zone id.
- **Applies to:** REQ-200
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.4 REC-4 — "Every recurring job has an explicit IANA time zone."

## TECH-25 — ISchedule extension point

- **Area:** other
- **Statement:** The core package shall define ISchedule with GetNextOccurrence(after, timeZone), with cron and interval as built-in implementations, so applications can add calendars.
- **Applies to:** recurring
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.4 REC-11

## TECH-26 — Retry policy contract

- **Area:** other
- **Statement:** The core package shall define a replaceable IRetryPolicy resolved from DI and a PermanentJobFailureException that skips retries.
- **Applies to:** REQ-129, REQ-131
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.6 RET-2; §4.13 EXT-4

## TECH-27 — IJobEvents

- **Area:** other
- **Statement:** The core package shall define IJobEvents with OnEnqueued, OnStarted, OnSucceeded, OnFailed, OnDeadLettered, OnCancelled and OnRecurringMissed, resolved from DI.
- **Applies to:** REQ-169
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.6 RET-6; §4.11 OBS-6

## TECH-28 — Execution middleware

- **Area:** other
- **Statement:** The core package shall define IJobMiddleware with InvokeAsync(JobExecutionContext ctx, JobExecutionDelegate next), resolved from DI per execution, run in registration order and filterable per job type, replacing attribute filters.
- **Applies to:** INV-122
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.13 EXT-1

## TECH-29 — Enqueue middleware

- **Area:** other
- **Statement:** The core package shall define IEnqueueMiddleware so applications can stamp tags, tenant ids or correlation data on every job created.
- **Applies to:** REQ-167
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.13 EXT-2

## TECH-30 — Typed per-job parameters

- **Area:** other
- **Statement:** The core package shall provide ctx.Parameters.Set<T>(key, value) and Get<T>(key), persisted with the job and available to middleware at enqueue and execution time.
- **Applies to:** REQ-309, REQ-320
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.13 EXT-6; §4.9 STO-11
- **Notes:** Correlation ids, launch principals and HTTP job responses are stored through parameters.

## TECH-31 — IJobStore

- **Area:** other
- **Statement:** Every store shall implement only the single asynchronous IJobStore interface, which documents the semantics of each of its methods.
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-1 — "target: under 25 methods"; §4.13 EXT-4; §2 P4
- **Notes:** The under-25-methods figure is a design target, not a hard limit.

## TECH-32 — IJobIndex

- **Area:** other
- **Statement:** Every store shall implement the secondary index contract IJobIndex (AddAsync(jobId, index, value), RemoveAsync, QueryAsync(index, value, page), CountAsync), on which tags and correlation-id search are built.
- **Applies to:** REQ-167, REQ-308
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-11; §4.15 BLT-9

## TECH-33 — Store capability set

- **Area:** other
- **Statement:** IJobStore shall expose a capability set covering transactional enqueue, push notifications and result storage.
- **Applies to:** REQ-153, REQ-512
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-10
- **Notes:** Free-text payload search was removed from the set by owner decision on 2026-11-06 as overkill; tag filters cover lookups by business key.

## TECH-34 — IJobContextAccessor

- **Area:** library
- **Statement:** The core package shall provide an AsyncLocal-backed IJobContextAccessor that exposes the current JobContext.
- **Applies to:** TECH-16
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-16

## TECH-35 — Asynchronous execution model

- **Area:** runtime
- **Statement:** The engine shall run workers as async tasks bounded by a concurrency limit, not dedicated blocked threads, over a fully asynchronous store API, with execution scopes that support IAsyncDisposable.
- **Applies to:** INV-106, INV-122
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.5 EXE-1

## TECH-36 — SQL data access

- **Area:** library
- **Statement:** The SQL stores shall use plain ADO.NET, without EF Core or Dapper.
- **Applies to:** TECH-37, TECH-40, TECH-42
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-2

## TECH-37 — PostgreSQL store

- **Area:** datastore
- **Statement:** The Bellhop.PostgreSql package shall use PostgreSQL as the reference store implementation.
- **Version:** the three most recent major versions at each Bellhop release
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-2; §6; §8 (M1); §9 Q2 — "PostgreSQL as the reference store first, SQL Server second? (Proposed: yes, because SKIP LOCKED + LISTEN/NOTIFY give the best reliability and latency story; SQL Server follows in M2.)"
- **Notes:** Decided by the owner on 2026-11-06: the last three major versions. §9 Q2 confirmed: PostgreSQL is the reference store in M1 and SQL Server follows in M2.

## TECH-38 — PostgreSQL notifications

- **Area:** protocol
- **Statement:** The PostgreSQL store shall use LISTEN/NOTIFY to wake other nodes when work arrives.
- **Applies to:** TECH-37, NFR-6
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.5 EXE-8 — "Stores that support notifications (PostgreSQL LISTEN/NOTIFY) MUST use them"

## TECH-39 — PostgreSQL claims

- **Area:** datastore
- **Statement:** The PostgreSQL store shall claim jobs with FOR UPDATE SKIP LOCKED.
- **Applies to:** INV-103
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.5 EXE-2

## TECH-40 — SQL Server store

- **Area:** datastore
- **Statement:** The Bellhop.SqlServer package shall use Microsoft SQL Server as a job store.
- **Version:** the three most recent major versions at each Bellhop release
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-2; §6; §8 (M2)
- **Notes:** Decided by the owner on 2026-11-06: the last three major versions. Azure SQL Database and Azure SQL Managed Instance are supported too and join the CI matrix (Managed Instance nightly).

## TECH-41 — SQL Server claims

- **Area:** datastore
- **Statement:** The SQL Server store shall claim jobs with READPAST and UPDLOCK hints.
- **Applies to:** INV-103
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.5 EXE-2

## TECH-42 — SQLite store

- **Area:** datastore
- **Statement:** The Bellhop.Sqlite package shall use SQLite as a single-node job store for development and small deployments.
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-2; §6; §8 (M2)
- **Notes:** Decided by the owner on 2026-11-06: pointing two nodes at one SQLite file is unsupported and undefined; the docs say so and the store does not check for it.

## TECH-43 — In-memory store

- **Area:** datastore
- **Statement:** The core package shall include a deterministic in-memory job store.
- **Applies to:** REQ-15, TECH-102
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-2; §4.1 SET-2; §4.12 TST-3; §6

## TECH-44 — Unique keys by index

- **Area:** datastore
- **Statement:** The SQL stores shall enforce unique keys with a unique index rather than a read-then-write check.
- **Applies to:** INV-100
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.3 SCH-5 — "Uniqueness MUST be enforced by the store (unique index), not by read-then-write."
- **Notes:** The Redis store uses SET NX PX for the same purpose (TECH-56).

## TECH-45 — Recurring trigger storage

- **Area:** datastore
- **Statement:** Every store shall make each write that changes a recurring job's state, NextRunAt or definition, or removes the job, one atomic compare-and-set on the stored state, NextRunAt and definition, for example on a row version, that for a trigger also requires the maintenance pause to be off, and keep NextRunAt indexed.
- **Applies to:** REQ-216, INV-203, INV-212, NFR-14
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.4 REC-7
- **Notes:** Recurring run 6 F-1 extended this from triggering to every such write (INV-212). To judge missed instants at the write rather than at the read, a write can compute them from the database time of its read and also require that the database clock has not yet reached the first due instant after that time; if it has, the write changes nothing and the caller reads again. Recurring run 7 F-1 and F-3: the definition and, for a trigger, the maintenance flag are part of the condition (INV-212).

## TECH-46 — Embedded migrations

- **Area:** datastore
- **Statement:** Each SQL store shall own a small schema in a configurable schema or prefix, "bellhop" by default, created and upgraded by embedded, versioned, idempotent migrations.
- **Applies to:** REQ-22, REQ-24
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-3 — "target: 6 tables or fewer"
- **Notes:** Six tables is a design target.

## TECH-47 — Schema script export

- **Area:** tooling
- **Statement:** The SQL stores shall provide BellhopSchema.GetScript(provider, fromVersion), which emits the exact SQL for DBAs.
- **Applies to:** REQ-23
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-3

## TECH-48 — No DbContext required

- **Area:** framework
- **Statement:** No store shall require the application to register, expose or migrate an Entity Framework Core DbContext.
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-4

## TECH-49 — EF Core package

- **Area:** framework
- **Statement:** The optional Bellhop.EntityFrameworkCore package shall use Entity Framework Core to provide dbContext.EnqueueAsync(job) and the outbox table and relay.
- **Applies to:** REQ-430, REQ-431, REQ-432, INV-101
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.3 SCH-8; §4.9 STO-4; §4.15 BLT-17; §6
- **Notes:** The outbox part is SHOULD and M3 (BLT-17); transactional enqueue is MUST and M2.

## TECH-50 — Package versioning

- **Area:** tooling
- **Statement:** All first-party NuGet packages shall ship with the same version number and declare exact-version dependencies on each other.
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.1 SET-9 — "so that mismatches are impossible rather than diagnosed later"; §6

## TECH-51 — No external lock service

- **Area:** library
- **Statement:** No first-party package shall require an external lock service or a distributed-lock library such as DistributedLock; all coordination shall live in the job store.
- **Applies to:** system, REQ-37
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.7 CON-7; Appendix A ADR-1
- **Notes:** Handler code may still use DistributedLock for its own resources; the docs show how (NFR-29).

## TECH-52 — Redis client

- **Area:** library
- **Statement:** The Redis store shall use StackExchange.Redis as its client.
- **Version:** >= 3.4.20
- **Applies to:** TECH-70
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-1 — "minimum 3.4.20 (Valkey version detection fix)"

## TECH-53 — Shared multiplexer

- **Area:** library
- **Statement:** The Redis store shall accept a connection string or an IConnectionMultiplexer, and shall reuse the application's multiplexer from DI when one is registered rather than opening a second one.
- **Applies to:** TECH-52
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-1

## TECH-54 — Redis command baseline

- **Area:** protocol
- **Statement:** The Redis store shall use only strings (SET NX PX, GET, DEL, INCR/DECR, EXPIRE/PTTL), hashes (HSET/HGET/HMGET/HGETALL/HINCRBY/HDEL, whole-hash EXPIRE), lists (LPUSH/RPUSH/RPOP/LMOVE/LREM/LRANGE/LLEN), sorted sets (ZADD/ZREM/ZSCORE/ZCARD/ZRANGEBYSCORE ... LIMIT/ZREMRANGEBYSCORE/ZPOPMIN/ZRANK), sets (SADD/SREM/SMEMBERS/SISMEMBER), PUBLISH/SUBSCRIBE, EVAL/EVALSHA/SCRIPT LOAD and MULTI/EXEC without EVAL inside, on database 0 only.
- **Applies to:** TECH-70, REQ-38
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-2
- **Rationale:** This baseline is what keeps every server in TECH-71 to TECH-86 usable.

## TECH-55 — Redis features never used

- **Area:** protocol
- **Statement:** The Redis store shall not depend on modules, FUNCTION/FCALL, Streams, keyspace notifications, hash-field TTL (HEXPIRE), CLIENT TRACKING, KEYS, ZRANGEBYLEX, SELECT, WAIT, atomic MSET or any Redis-8-only command.
- **Applies to:** TECH-70, REQ-38
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-2; Appendix A ADR-2

## TECH-56 — Redis data model

- **Area:** datastore
- **Statement:** The Redis store shall keep each job as a hash, per-queue ready and working lists, scheduled, retry and lease sorted sets scored by time, index sorted sets per state, queue and name, tag index sets, recurring definitions as hashes with a sorted set scored by NextRunAt, a node registry sorted set scored by heartbeat, unique keys as SET NX PX and concurrency counters as integers maintained inside scripts, in a documented and versioned key layout, plus a generation marker with a forward-only value taken from the server clock, a reconciling flag and the last-reset value in every hash tag the claim scripts use, and an unacknowledged-reset record.
- **Applies to:** TECH-70, REQ-507, REQ-526, REQ-527, REQ-532
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-3

## TECH-57 — One script per transition

- **Area:** datastore
- **Statement:** The Redis store shall perform every state transition (enqueue, claim, heartbeat, complete, fail, retry, cancel, recover, recurring trigger, unique check, concurrency admission) as exactly one Lua script.
- **Applies to:** TECH-70, REQ-511
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-4

## TECH-58 — Declared keys and hash tags

- **Area:** datastore
- **Statement:** Every Redis script shall declare all the keys it touches in KEYS, and all keys of one namespace shall share one hash tag so scripts are Cluster-safe.
- **Applies to:** TECH-57, TECH-64
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-4, RED-9
- **Notes:** Declared keys also avoid Dragonfly's global script lock (RDV-4).

## TECH-59 — Script time from the caller

- **Area:** datastore
- **Statement:** Redis scripts shall receive the current time in ARGV, taken from a TIME call to the same server once per store call, never read TIME inside a script or use a node's clock, and shall be deterministic and short.
- **Applies to:** TECH-57
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-4
- **Notes:** Decided by the owner on 2026-11-06: the client reads the server clock with TIME and passes it in, so scripts stay deterministic and claims and due checks use the Redis clock as INV-105 requires. The extra round trip can be pipelined with the script call.

## TECH-60 — Lua subset

- **Area:** language
- **Statement:** Redis scripts shall be written in the common subset of Lua 5.1 and 5.4, without the bit library, cjson, cmsgpack, redis.replicate_commands or redis.setresp, and with numbers passed as strings.
- **Version:** Lua 5.1 and 5.4 common subset
- **Applies to:** TECH-57
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-4
- **Rationale:** Keeps Dragonfly (Lua 5.4) and Garnet (opt-in Lua) supported (ADR-2).

## TECH-61 — Script loading

- **Area:** datastore
- **Statement:** The Redis store shall load each script once and invoke it with EVALSHA, falling back on NOSCRIPT.
- **Applies to:** TECH-57
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-4

## TECH-62 — Redis claims and leases

- **Area:** datastore
- **Statement:** The Redis claim script shall move a job from the ready list to the node's working list and add it to the lease sorted set with its deadline; heartbeats update that score and recovery scans the set for deadlines in the past.
- **Applies to:** REQ-123, REQ-132, INV-104
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-5

## TECH-63 — Redis wake-ups

- **Area:** protocol
- **Statement:** The Redis store shall publish on a per-queue pub/sub channel at enqueue and have workers subscribe, with polling at PollInterval as the fallback; blocking pops (BLMOVE) may be used but shall not be required.
- **Applies to:** TECH-70, REQ-103
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-6 — "since some hosted REST modes cannot block"

## TECH-64 — Redis topologies

- **Area:** platform
- **Statement:** The Redis store shall support standalone servers, primary/replica with Sentinel and Cluster, with TLS and ACL users.
- **Applies to:** REQ-511
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-9
- **Notes:** The default tagging bounds one namespace to one shard; the trade-off is documented (NFR-33).

## TECH-65 — ShardByQueue mode

- **Area:** datastore
- **Statement:** The Redis store shall offer an opt-in ShardByQueue mode that uses one hash tag per queue for higher Cluster throughput.
- **Applies to:** INV-500, INV-306
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-9

## TECH-66 — Redis dashboard queries

- **Area:** datastore
- **Statement:** The Redis store shall serve state, queue, name and tag filters from its index sets with paging via ZRANGE ... LIMIT, and shall never use KEYS or SCAN at request time.
- **Applies to:** REQ-308, NFR-16
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-10

## TECH-67 — Redis retention mechanism

- **Area:** datastore
- **Statement:** The Redis store shall give terminal jobs a whole-hash EXPIRE and trim time-scored index sets with a janitor using ZRANGEBYSCORE and ZREM, 500 entries per pass by default, never using hash-field TTL, and shall give captured logs and results the same EXPIRE as their job hash, re-applied on every state change.
- **Applies to:** REQ-145, REQ-109, REQ-514
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-11

## TECH-68 — Redis key prefix

- **Area:** datastore
- **Statement:** The Redis store shall prefix its keys with a configurable prefix, "bellhop:" by default, mapping each namespace to a distinct prefix and hash tag.
- **Applies to:** INV-125
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-17

## TECH-69 — Redis server detection

- **Area:** protocol
- **Statement:** The Redis store shall identify the server family with HELLO and INFO and probe EVAL with a trivial script on connect, repeating detection and the maxmemory-policy check on every reconnection, including a Sentinel role change.
- **Applies to:** REQ-500, REQ-502, REQ-505, REQ-529, REQ-531
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-18; §4.9.2 RDV-1

## TECH-70 — Redis store package

- **Area:** datastore
- **Statement:** The Bellhop.Redis package shall use Redis and Redis-compatible servers as a job store with the same semantics as the SQL stores.
- **Applies to:** redis
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-2; §4.9.1 intro — "Durability is weaker than a database and the store says so out loud."; §6; §8 (M2)
- **Notes:** Decided by the owner on 2026-11-06 (§9 Q7): the Redis store ships in 1.0 (M2) with the Tier 1 servers.

## TECH-71 — Valkey

- **Area:** datastore
- **Statement:** The Redis store shall support Valkey as a Tier 1 server, tested standalone, with Sentinel and as a Cluster.
- **Version:** 8.1, 9.0, 9.1
- **Applies to:** TECH-70
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-1
- **Notes:** Valkey's INFO reports redis_version 7.2.4, so detection uses HELLO (TECH-69). The docs recommend Valkey as the default open-source choice (NFR-34).

## TECH-72 — Valkey GLIDE adapter

- **Area:** library
- **Statement:** The Redis store shall support the Valkey GLIDE C# client through its internal client abstraction once that client is mature.
- **Applies to:** TECH-52
- **Strength:** may
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-1

## TECH-73 — Redis

- **Area:** datastore
- **Statement:** The Redis store shall support Redis as a Tier 1 server without relying on Redis 8 built-in modules or Redis-8-only commands such as XACKDEL, HGETDEL or MSETEX.
- **Version:** 7.2 and 8.x
- **Applies to:** TECH-70
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-2

## TECH-74 — Garnet

- **Area:** datastore
- **Statement:** The Redis store shall support Microsoft Garnet as a Tier 2 server, with Cluster supported and Sentinel not supported, RESP3 off and no reliance on WAIT or atomic MSET.
- **Version:** >= 2.1
- **Applies to:** TECH-70, REQ-502, REQ-503
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-3
- **Notes:** Lua is opt-in and slow on Garnet, so throughput is bounded by its Lua performance (documented in NFR-34).

## TECH-75 — In-process Garnet fixture

- **Area:** tooling
- **Statement:** Bellhop.Testing shall use Garnet's NuGet package to offer an in-process server fixture so the Redis store can be tested without Docker.
- **Applies to:** TECH-102, TECH-74
- **Strength:** may
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-3; §6; §8 (M3)

## TECH-76 — Dragonfly

- **Area:** datastore
- **Statement:** The Redis store shall support Dragonfly as a Tier 2 server on database 0 only, never using EVAL inside MULTI.
- **Version:** >= 2.0
- **Applies to:** TECH-70, REQ-503
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-4; §9 Q8
- **Notes:** Dragonfly is BSL 1.1, not OSI; the docs state the licence and the recommended flags --cluster_mode=emulated --lock_on_hashtags (NFR-34). Decided by the owner on 2026-11-06 (§9 Q8): listed as supported at Tier 2.

## TECH-77 — Apache Kvrocks

- **Area:** datastore
- **Statement:** The Redis store shall support Apache Kvrocks as a Tier 2 server, with Cluster through the Kvrocks controller and Sentinel for primary/replica both exercised in CI.
- **Version:** >= 2.14
- **Applies to:** TECH-70
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-5
- **Notes:** BRPOPLPUSH, keyspace notifications and hash-field TTL are absent, and ZRANGEBYLEX and SCAN semantics differ; none of them is used (TECH-55). Documented as the self-hosted durable option.

## TECH-78 — KeyDB

- **Area:** datastore
- **Statement:** The Redis store shall work on KeyDB as a Tier 3 server from the Redis 6.2 baseline.
- **Version:** 6.3
- **Applies to:** TECH-70
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-6
- **Notes:** Unmaintained since 2023-10 with unpatched upstream CVEs; not recommended for new deployments (NFR-34).

## TECH-79 — Redict

- **Area:** datastore
- **Statement:** The Redis store shall work on Redict as a Tier 3 server from the Redis 7.2 baseline.
- **Version:** 7.3
- **Applies to:** TECH-70
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-7

## TECH-80 — AWS ElastiCache for Valkey

- **Area:** service
- **Statement:** The Redis store shall support AWS ElastiCache for Valkey as a Tier 1 hosted service, including serverless, which runs in cluster mode.
- **Applies to:** TECH-70, TECH-71
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-8
- **Notes:** Synchronous durability on Valkey 9 node-based clusters is called out in the docs (NFR-31).

## TECH-81 — AWS MemoryDB

- **Area:** service
- **Statement:** The Redis store shall support AWS MemoryDB as a Tier 1 hosted service.
- **Applies to:** TECH-70
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-8 — "the recommended managed option for durability"

## TECH-82 — GCP Memorystore for Valkey

- **Area:** service
- **Statement:** The Redis store shall support Google Cloud Memorystore for Valkey as a Tier 1 hosted service.
- **Applies to:** TECH-70
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-8

## TECH-83 — Azure Managed Redis

- **Area:** service
- **Statement:** The Redis store shall support Azure Managed Redis as a Tier 2 hosted service under both the "OSS cluster" and "Enterprise" clustering policies.
- **Applies to:** TECH-70
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-8
- **Notes:** Azure Cache for Redis is not targeted because it retires in 2027 to 2028.

## TECH-84 — Redis Cloud

- **Area:** service
- **Statement:** The Redis store shall support Redis Cloud as a Tier 2 hosted service.
- **Applies to:** TECH-70
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-8

## TECH-85 — Dragonfly Cloud

- **Area:** service
- **Statement:** The Redis store shall support Dragonfly Cloud as a Tier 2 hosted service.
- **Applies to:** TECH-70, TECH-76
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-8

## TECH-86 — Upstash

- **Area:** service
- **Statement:** The Redis store shall support Upstash over TCP as a Tier 3 hosted service and shall not support its REST mode.
- **Applies to:** TECH-70
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-8 — "the REST mode is unsupported because it has no blocking or pub/sub commands"

## TECH-87 — Redis CI matrix

- **Area:** tooling
- **Statement:** CI shall run the conformance suite and the chaos tests against a Docker matrix of redis:7.2, redis:8, valkey:8.1, valkey:9, a Valkey cluster, a Redis Sentinel set, Garnet, Dragonfly and Kvrocks, with KeyDB and Redict as a nightly smoke test.
- **Applies to:** NFR-35, NFR-58
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-10; §4.9.2 tier definitions — "Tier 1: run in CI on every commit ... Tier 2: run in CI nightly"
- **Notes:** Tier 2 servers join CI in M3 (§8).

## TECH-88 — Dashboard package

- **Area:** framework
- **Statement:** The Bellhop.Dashboard package shall use ASP.NET Core endpoint routing, mounted with app.MapBellhopDashboard("/path"), which returns an endpoint convention builder so RequireAuthorization, AllowAnonymous and RequireHost work as on any endpoint.
- **Applies to:** dashboard
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.10 DSH-1; §4.1 SET-1 — "The dashboard MUST be optional."; §6

## TECH-89 — Live updates transport

- **Area:** protocol
- **Statement:** The dashboard shall use Server-Sent Events for live updates and shall not depend on SignalR.
- **Applies to:** REQ-315
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.10 DSH-7

## TECH-90 — API explorer exclusion

- **Area:** framework
- **Statement:** The dashboard shall exclude its endpoints from the host's ASP.NET Core API explorer and Swagger documents.
- **Applies to:** TECH-88
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.10 DSH-7

## TECH-91 — Embedded assets

- **Area:** framework
- **Statement:** The dashboard shall embed all its assets, reference them with relative URLs and load nothing from a CDN.
- **Applies to:** NFR-47
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.10 DSH-4

## TECH-92 — Dashboard JSON API

- **Area:** protocol
- **Statement:** The dashboard shall back its UI with a JSON API under the dashboard path, documented with OpenAPI.
- **Applies to:** INV-301, TECH-121, TECH-122
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.10 DSH-9
- **Notes:** ADR-3 makes this API the official route for custom UI and therefore a public contract covered by NFR-20.

## TECH-93 — Dashboard front-end stack

- **Area:** framework
- **Statement:** The dashboard front end shall be built with React, shadcn/ui components and Magic UI, and shall load nothing from a CDN at runtime.
- **Applies to:** TECH-88
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §9 Q3 — "Proposed: whichever keeps the embedded bundle under ~300 KB and needs no runtime CDN."
- **Notes:** Decided by the owner on 2026-11-06: React with shadcn/ui and Magic UI; the ~300 KB budget is dropped (NFR-60 retired). Both component sets use Tailwind CSS and are copied into the repository rather than referenced as packages. Only the MIT-licensed free Magic UI components may be used, never Magic UI Pro, to keep NFR-40 (no paid tier). Animations must respect prefers-reduced-motion (NFR-50). The "no runtime CDN" part of §9 Q3 still holds.

## TECH-94 — Basic-auth password hashing

- **Area:** library
- **Statement:** RequireBasicAuth() shall verify passwords against salted PBKDF2-HMAC-SHA256 hashes with at least 600,000 iterations, computed with the BCL's Rfc2898DeriveBytes.Pbkdf2, which a helper and the CLI generate.
- **Applies to:** REQ-303, NFR-43
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-2
- **Notes:** Decided by the owner on 2026-11-06: PBKDF2 only, so the dashboard takes no third-party dependency; Argon2 is not offered. 600,000 iterations follows the OWASP recommendation for PBKDF2-HMAC-SHA256.

## TECH-95 — Launch form generation

- **Area:** library
- **Statement:** The launch page shall derive its form fields, labels and validation from the payload record and System.ComponentModel.DataAnnotations ([Display], [Required], [Range], [StringLength], [DataType]) through a JSON schema, covering enums, dates with time zone, nullable fields, nested records and collections.
- **Applies to:** REQ-319, INV-304
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.10 DSH-12; §4.15 BLT-8

## TECH-96 — Launchable attribute

- **Area:** other
- **Statement:** The core package shall provide [Launchable(Category = "...", Description = "...")] and a global "all jobs launchable" switch.
- **Applies to:** INV-304
- **Strength:** must
- **Status:** retired
- **Source:** requirements.md §4.15 BLT-8
- **Notes:** Retired on 2026-11-06 by owner decision: every registered job type is launchable (INV-304, DSH-12), so no opt-in attribute or switch is needed and the Launch page lists jobs by name.

## TECH-97 — Tracing

- **Area:** library
- **Statement:** The core package shall emit traces through a built-in ActivitySource named "Bellhop" whose spans follow the OpenTelemetry messaging semantic conventions.
- **Applies to:** NFR-54
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.11 OBS-1 — "No separate package needed."; §4.15 BLT-4 — "Application Insights and other vendors receive data through OpenTelemetry; no bridge package."

## TECH-98 — Metrics

- **Area:** library
- **Statement:** The core package shall emit metrics through a built-in Meter named "Bellhop".
- **Applies to:** NFR-55
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.11 OBS-2

## TECH-99 — Prometheus export

- **Area:** library
- **Statement:** Bellhop metrics shall reach Prometheus through the standard OpenTelemetry Prometheus exporter, with no Bellhop-specific exporter package.
- **Applies to:** TECH-98, NFR-36
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-5

## TECH-100 — Log capture provider

- **Area:** library
- **Statement:** Job log capture shall be an ILoggerProvider scoped by job id, so Serilog, NLog and every other logging provider keep working and no special console API exists.
- **Applies to:** REQ-165
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-1; §4.10 DSH-6 — "No special Console API is needed."

## TECH-101 — Health check

- **Area:** library
- **Statement:** The core package shall provide AddBellhopHealthCheck() on Microsoft.Extensions.Diagnostics.HealthChecks.
- **Applies to:** REQ-30, REQ-31, REQ-32, REQ-33, REQ-34
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.11 OBS-5

## TECH-102 — Testing package

- **Area:** tooling
- **Statement:** The Bellhop.Testing package shall provide a BellhopTestHarness with RunPendingAsync() and AdvanceTimeAsync(...) that drains jobs synchronously over the deterministic in-memory store, plus assertion helpers such as harness.Enqueued<T>().Should().ContainSingle(...).
- **Applies to:** NFR-53
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.12 TST-3; §6; §8 (M1)

## TECH-103 — Fake time

- **Area:** library
- **Statement:** Bellhop.Testing shall integrate with FakeTimeProvider.
- **Applies to:** TECH-102, TECH-12
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.12 TST-3

## TECH-104 — Test context factory

- **Area:** other
- **Statement:** The core package shall provide JobContext.CreateForTest(...) to build a context without infrastructure.
- **Applies to:** TECH-16
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.12 TST-5

## TECH-105 — Store conformance suite

- **Area:** tooling
- **Statement:** The Bellhop.Storage.Conformance package shall use xUnit to give store authors a test suite that proves correctness, including concurrency tests for claims, uniqueness and recurring triggers, and tests for IJobIndex and typed parameters.
- **Applies to:** TECH-31, TECH-32, NFR-59
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-8, STO-11; §6

## TECH-106 — Testcontainers sample

- **Area:** tooling
- **Statement:** The project shall publish an integration test sample for PostgreSQL and SQL Server using Testcontainers.
- **Applies to:** TECH-37, TECH-40
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.12 TST-6

## TECH-107 — Analyzer: missing job name

- **Area:** tooling
- **Statement:** The core package shall ship a Roslyn analyzer that warns when a job type has no explicit [JobName].
- **Applies to:** REQ-101
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.2 JOB-2 — "renaming it would orphan stored jobs"; §8 (M2)

## TECH-108 — Analyzer: job without handler

- **Area:** tooling
- **Statement:** The core package shall ship a Roslyn analyzer that flags a job type with no handler.
- **Applies to:** REQ-124
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.2 JOB-10

## TECH-109 — Analyzer: handler without job

- **Area:** tooling
- **Statement:** The core package shall ship a Roslyn analyzer that flags a handler whose job type is not registered.
- **Applies to:** TECH-22
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.2 JOB-10

## TECH-110 — Analyzer: unserializable payload

- **Area:** tooling
- **Statement:** The core package shall ship a Roslyn analyzer that flags payload types that System.Text.Json cannot serialize.
- **Applies to:** TECH-5
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.2 JOB-10

## TECH-111 — Analyzer: invalid cron literal

- **Area:** tooling
- **Statement:** The core package shall ship a Roslyn analyzer that flags invalid cron literals in [Recurring].
- **Applies to:** REQ-210, TECH-23
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.2 JOB-10

## TECH-112 — Core package contents

- **Area:** other
- **Statement:** The Bellhop core package shall contain the abstractions, engine, hosting integration, in-memory store, analyzers, OpenTelemetry instrumentation, health check, throttling, notifications, HTTP jobs and IJobContextAccessor.
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §6; §9 Q11 — "HTTP jobs in core or in a separate Bellhop.Http package? (Proposed: core, because the only dependency is Microsoft.Extensions.Http, and SEC-6 keeps it safe by default.)"

## TECH-113 — HTTP client for HTTP jobs

- **Area:** library
- **Statement:** HTTP jobs and webhook channels shall send requests through named HttpClient registrations from Microsoft.Extensions.Http.
- **Applies to:** REQ-420, INV-404
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-12; §4.14 SEC-6; §9 Q11

## TECH-114 — HttpRequestJob payload

- **Area:** other
- **Statement:** The core package shall provide a built-in HttpRequestJob payload with method, URL, headers, body, content type, named HttpClient, timeout, accepted status codes, an optional success predicate on the body written as a JSONPath with equals or exists (for example {"path": "$.status", "equals": "ok"}), and a response capture limit.
- **Applies to:** REQ-420, REQ-421, REQ-422
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-12
- **Notes:** Remote "agents" from Hangfire.HttpJob are out of scope. Decided by the owner on 2026-11-06: the success predicate is a declarative JSONPath rule, so it can come from configuration or the launch page and is safe to evaluate.

## TECH-115 — Webhook notification channel

- **Area:** protocol
- **Statement:** The notification engine shall deliver to a generic JSON webhook with a message template.
- **Applies to:** REQ-407, INV-401
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-11

## TECH-116 — Slack channel preset

- **Area:** service
- **Statement:** The notification engine shall offer a Slack incoming-webhook preset.
- **Applies to:** REQ-407
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-11; §7 — "Vendor-specific notification SDKs" are a non-goal

## TECH-117 — Microsoft Teams channel preset

- **Area:** service
- **Statement:** The notification engine shall offer a Microsoft Teams incoming-webhook preset.
- **Applies to:** REQ-407
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-11

## TECH-118 — ILogger channel

- **Area:** library
- **Statement:** The notification engine shall offer an ILogger channel that logs at Critical level.
- **Applies to:** REQ-407
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-11

## TECH-119 — SMTP channel

- **Area:** protocol
- **Statement:** The notification engine shall offer an SMTP email channel.
- **Applies to:** REQ-407
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-11 — "MUST (SMTP: SHOULD)"; §8 (M3); §9 Q10

## TECH-120 — Configuration-defined recurring jobs

- **Area:** library
- **Statement:** Configuration-defined recurring jobs shall be read through IOptionsMonitor so changes apply without a restart.
- **Applies to:** REQ-232
- **Strength:** may
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-10

## TECH-121 — MCP server

- **Area:** protocol
- **Statement:** The Bellhop.Mcp package shall implement a Model Context Protocol server over the dashboard JSON API with list, inspect, requeue, trigger and pause tools, using the same permissions and API keys.
- **Applies to:** TECH-92, INV-301
- **Strength:** may
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-19 — "MAY (1.x)"; §6; §8 (M3)

## TECH-122 — CLI tool

- **Area:** tooling
- **Statement:** The Bellhop.Cli dotnet tool shall export schema scripts, requeue dead letters, inspect jobs and generate basic-auth password hashes.
- **Applies to:** TECH-47, TECH-94, TECH-92
- **Strength:** may
- **Status:** approved
- **Source:** requirements.md §6 — "MAY, post-1.0"; §4.15 BLT-2

## TECH-123 — Benchmark harness

- **Area:** tooling
- **Statement:** The repository shall include a public benchmark harness that actually executes jobs on every compared system.
- **Applies to:** NFR-5, NFR-6, NFR-7, NFR-8
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §5 NFR-2; §8 (M2)

## TECH-124 — Product name and root namespace

- **Area:** language
- **Statement:** The packages shall use the product name Bellhop, the root C# namespace Bellhop and package ids of the form Bellhop and Bellhop.<Area>, such as Bellhop.PostgreSql and Bellhop.Dashboard.
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §9 Q1 — "Confirm the name Bellhop and the root namespace."
- **Notes:** Decided by the owner on 2026-11-06 (§9 Q1).

## TECH-125 — Hangfire migration adapter

- **Area:** library
- **Statement:** A separate legacy package shall provide Hangfire-style Enqueue(() => ...) sugar backed by Bellhop.
- **Applies to:** NFR-30
- **Strength:** may
- **Status:** retired
- **Source:** requirements.md §9 Q6; §7 — "Supporting Hangfire's expression-based Enqueue(() => ...) API" is a non-goal
- **Notes:** Retired. Decided by the owner on 2026-11-06 (§9 Q6): no compatibility package; expression-based jobs stay a non-goal and migration is covered by the side-by-side guide (NFR-30).

## TECH-126 — Store-native migration lock

- **Area:** datastore
- **Statement:** Each store shall serialise schema migrations with a lock native to that store: a PostgreSQL advisory lock, SQL Server sp_getapplock, a SQLite write transaction, or a Redis key set with NX and an expiry.
- **Applies to:** REQ-42
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-3
- **Notes:** Decided by the owner on 2026-11-06. Uses no lock library, so TECH-51 still holds.

## TECH-127 — Additive migrations within a major version

- **Area:** datastore
- **Statement:** Migrations within one major version shall only add schema objects or widen existing ones, so that library version N keeps working on schema N+1 until its nodes are replaced; removals wait for the next major version.
- **Applies to:** REQ-23, REQ-32, REQ-43, NFR-18
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-5
- **Notes:** Decided by the owner on 2026-11-06 as part of the accepted schema range (expected version or one older).

## TECH-128 — Client and worker registration

- **Area:** framework
- **Statement:** The AddBellhop builder shall offer AddClient(), which registers IJobClient and IRecurringJobManager for application code, and AddWorker(options), which registers the worker with its queues, concurrency and background duties and also registers the client.
- **Applies to:** REQ-52, REQ-20, REQ-40, TECH-11, TECH-19
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.1 SET-7
- **Notes:** Decided by the owner on 2026-11-06, replacing the node modes. Worker options (queues and their order, concurrency, the LongRunning limit) move from the global options to AddWorker. The dashboard stays MapBellhopDashboard on the endpoint builder (TECH-88).

## TECH-129 — Alerts registration

- **Area:** framework
- **Statement:** The AddBellhop builder shall offer AddAlerts(), an alerts registration separate from AddClient() and AddWorker(), that can be combined with them and with MapBellhopDashboard on one node or used alone on an alerts-only node.
- **Applies to:** hosting REQ-52, hosting REQ-59, integrations INV-411, integrations REQ-438, integrations REQ-403, integrations REQ-404
- **Strength:** must
- **Status:** approved
- **Notes:** Decided by the owner on 2026-11-06 (integrations findings F-6): alerting must keep working when the last worker is down. Decided by the owner on 2026-11-10: AddAlerts() on the AddBellhop builder, in the style of TECH-128, because a hosted background duty is registered on the service collection; app.UseBellhopAlerts(), suggested earlier, is not offered.

## TECH-130 — Redis reset safety in the claim and heartbeat scripts

- **Area:** datastore
- **Statement:** The Redis claim script and the recurring trigger script shall refuse to claim or create an occurrence while the generation marker is missing or flagged as reconciling, the heartbeat script shall, while it is missing or flagged, re-create a missing job record as Processing with its lease, concurrency-key hold and unique-key lock and cancel in the same script a pending job that took the unique key, new generation marker values shall be read from the server's TIME, and the claim, heartbeat and completion scripts shall take the node's last-seen marker value, make the redis REQ-507 or REQ-528 marker write themselves when it applies, together with redis REQ-523's unacknowledged reset record for a REQ-507 write, and return the generation marker and last-reset value they read and whether they wrote it, so the node logs and re-seeds under redis REQ-507, REQ-528 and REQ-530 before using the script's result and a claim keeps the last-reset value it read; every other marker read a worker makes uses a script that does the same.
- **Applies to:** redis REQ-507, redis REQ-521, redis REQ-522, redis REQ-526, redis REQ-527, redis REQ-528, redis REQ-530, redis REQ-534, TECH-56, TECH-62
- **Strength:** must
- **Status:** approved
- **Notes:** refiner-model 2026-11-06 redis F-1/F-2, owner's choice of full protection. Under ShardByQueue every hash tag carries its own marker copy. Decided by the owner on 2026-11-10: one marker per hash tag with detection per tag is acceptable, although the REQ-507/REQ-528 marker write, REQ-523's record written with it and REQ-527's advance are then not atomic across the whole namespace. Which hash slot REQ-523's record lives in is still open; see open questions. Redis run 2 (F-2, F-6): unique-key locks are re-created with the record, and marker values come from TIME. Redis run 4 F-1 and F-2: every script that reads the marker returns it, so detection happens on the reads a worker already makes, and the claim keeps the last-reset value for the resetSinceClaim test. Redis run 5 F-1: the script that reads the marker also makes the REQ-507 or REQ-528 write, because a write sent as a separate command could lose to another node's first marker or advance, and the flush then went unreported. Redis run 7 F-1: the REQ-507 write includes the unacknowledged reset record, so a reply lost after the script ran cannot hide the reset.

## Open questions

- TECH-130: under ShardByQueue (Redis Cluster), which hash slot does redis REQ-523's unacknowledged reset record live in? One generation marker per hash tag with detection per tag was accepted by the owner on 2026-11-10. Owner to decide.
