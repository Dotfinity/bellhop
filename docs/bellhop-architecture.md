# Bellhop architecture (M1 — Core preview)

| | |
|---|---|
| Based on | [requirements.md](../requirements.md) Draft v0.2 (2026-11-03), §8 milestone M1, and the owner decisions D1 to D7 below |
| Evidence | [research.md](../research.md) (grievances are cited as H1…, T1…) |
| Stories | [stories/m1-core/](../stories/m1-core/README.md) (cited as M1-NN) |
| Status | Draft for review, 2026-11-03 |

This document is the plan a builder follows for M1. It fixes the contracts (public types, store interface, schema, options, event ids) so that stories can be built in parallel without deciding them under pressure. Every choice that requirements.md leaves open is marked inline as **Assumption A-n**, and every place where M1 deliberately differs from requirements.md is marked **Mismatch M-n**. Both are listed together in §13 for review.

Requirement ids (SET-1, EXE-4, …) refer to requirements.md.

---

## 0. Binding decisions

Taken by the project owner on 2026-11-03. They are binding for every M1 story. If one changes, add a dated amendment under it rather than rewriting it.

| # | Decision | What it means for the work |
|---|---|---|
| D1 | The product name and root namespace are **Bellhop** (resolves §9 Q1). | Packages `Bellhop`, `Bellhop.PostgreSql`, `Bellhop.Dashboard`, `Bellhop.Testing`; root namespace `Bellhop`. |
| D2 | The test stack is **xUnit v3, AwesomeAssertions, Moq and Bogus**, with **Testcontainers** for PostgreSQL. | Every test project uses these. The conformance suite (STO-8) is an xUnit v3 library. No other assertion or mocking library is added. |
| D3 | **PostgreSQL is the reference store** and is built first; SQL Server follows in M2 (resolves §9 Q2). | M1 ships the in-memory and PostgreSQL stores only. |
| D4 | **`AutoMigrate` defaults to true in every environment**, with the script export documented on the first page (resolves §9 Q4). | `PostgreSqlStoreOptions.AutoMigrate = true`. |
| D5 | The **dashboard front end is framework-free**: the embedded bundle stays under 300 KB, with no runtime CDN (resolves §9 Q3). | No React, no npm toolchain in M1 (see A-20). A test enforces the size budget. |
| D6 | **Succeeded jobs are retained for 7 days by default, and this is configurable** (resolves §9 Q5). This amends STO-7, which said 24 h. | `RetentionOptions.Succeeded = 7 days`. Requirements.md STO-7 is updated to match. |
| D7 | **Plan first.** M1 is broken into stories and reviewed before any code is written. | No story starts until the owner has reviewed the epic. |

---

## 1. Goals and non-goals for M1

### 1.1 Goal

A developer can paste the §3 snippets of requirements.md into a new ASP.NET Core app pointed at PostgreSQL. Fire-and-forget, delayed and recurring jobs then run correctly on one node or several, survive a node crash, retry and dead-letter, and show up in traces, metrics, a health check and a read-only dashboard. The same app can be unit-tested with `Bellhop.Testing` and no database.

### 1.2 In M1

Requirement ids per area. "Partial" means part of the requirement is in M1 and the rest is deferred, as stated.

| Area | In M1 |
|---|---|
| Setup | SET-1 to SET-10 (SET-8 dashboard line arrives with the dashboard story) |
| Job model | JOB-1, JOB-2 (except the analyzer, M2), JOB-3, JOB-4, JOB-5, JOB-6 (except batch id), JOB-7 (except `[Unique]` and `[Concurrency]`), JOB-9 (dashboard and JSON API only, since logs and traces carry no payload in M1) |
| Scheduling | SCH-1, SCH-2, SCH-4 (queue, priority, tags, timeout, retry override, parameters), SCH-6, SCH-10 |
| Recurring | REC-1 to REC-10; REC-11 (`ISchedule` interface public, built-in cron and interval only, see A-12) |
| Execution | EXE-1 to EXE-11 |
| Retries | RET-1 to RET-4, RET-5 (individual requeue only), RET-6 |
| Queues | CON-1 (strict order and per-queue limits), CON-2, CON-6 (without the `LongRunning` limit), CON-7 |
| Storage | STO-1, STO-2 (in-memory and PostgreSQL), STO-3, STO-4, STO-5 (version window rule, §4.6), STO-6, STO-7, STO-8 (suite exists in the repo, not yet packed), STO-9, STO-10, STO-11 |
| Dashboard | DSH-1, DSH-2, DSH-3 (view level only), DSH-4, DSH-5 (read-only parts), DSH-7, DSH-8, DSH-9 (read endpoints), DSH-10 |
| Observability | OBS-1 to OBS-5 |
| Testing | TST-1 to TST-5 |
| Extensibility | EXT-1, EXT-2, EXT-3, EXT-4, EXT-6 |
| Security | SEC-1, SEC-2, SEC-3, SEC-4, SEC-5 |
| NFR | NFR-1 (targets; AOT later), NFR-3, NFR-4, NFR-5 (public API tracking from day one) |

### 1.3 Deferred from M1, and what stands in for each

A deferred item is **omitted**, not stubbed: no type, option, button, menu entry or placeholder copy for it appears in M1.

| Deferred | Milestone | In M1 instead |
|---|---|---|
| Continuations, chains, batches (SCH-3, WF-*) | M2 | `JobState.Awaiting` exists and is used only by the recurring `Queue` overlap policy (§7.7). No `ContinueWithAsync`, `ChainAsync`, or batch id. |
| Unique keys (SCH-5), concurrency keys and rate limits (CON-3, CON-4, BLT-7) | M2 | Not present on `EnqueueOptions` or as attributes. |
| Transactional enqueue (SCH-8), `Bellhop.EntityFrameworkCore`, outbox (BLT-17) | M2 / M3 | Not present. `StoreCapabilities.TransactionalEnqueue` is not reported by either M1 store. |
| Job results, `IJob<TResult>`, `WaitForCompletionAsync`, `GetResultAsync` (JOB-8, SCH-7) | M2 (A-3) | Not present. |
| `EnqueueManyAsync` (SCH-9) | M2 | The store method takes a list (§5.2) so M2 needs no store change. |
| Bulk dead-letter requeue (RET-5 bulk) | M2 | Individual `RequeueAsync(id)`. |
| Queue pause and global maintenance pause (CON-5 for queues) | M2 | Recurring pause and resume exist (REC-9). |
| `LongRunning` concurrency limit (CON-6) | M2 | One node-wide limit plus optional per-queue limits. |
| Weighted round-robin queues (CON-1, MAY) | later | Strict priority order. |
| Dashboard operate actions (DSH-3 operate, DSH-12, BLT-8, BLT-10), Tags page (BLT-9), captured logs (DSH-6, BLT-1), parent/child graph (WF-4), node metrics (BLT-6) | M2 | Read-only pages. No retry, cancel, delete, trigger, pause, edit or launch control is rendered. |
| Dashboard OpenAPI document (DSH-9) | M2 (A-21) | JSON endpoints exist and are tested; the document is written when the API gains write endpoints. |
| Auth presets (BLT-2), correlation ids (BLT-4), notifications (BLT-11), HTTP jobs (BLT-12, SEC-6) | M2 | Host authorization policies only. |
| `IJobContextAccessor` (BLT-16) | M3 | Not present. |
| Analyzers (JOB-2 warning, JOB-10) | M2 | A startup **log warning** (event 1005) when a job type has no explicit `[JobName]` (A-6). |
| SQL Server, SQLite, Redis stores | M2 | — |
| Packing `Bellhop.Storage.Conformance` as a NuGet package | M2 | It exists as a test library in the repo and both M1 stores run it. |
| Benchmark harness (NFR-2), docs site, samples repo (NFR-6) | M2 | One sample web app and a getting-started page in the repo (M1-26). |
| Rolling-deploy test across two schema versions (STO-5) | M2 | M1 has only schema v1. The version-window rule is implemented and unit-tested (§4.6). |

Exact copy that must not appear anywhere in M1 (UI, logs, docs, XML docs): "Retry", "Requeue", "Cancel", "Delete", "Trigger now", "Pause", "Resume" or "Launch" as dashboard buttons or links; "Coming soon"; "Not available in this version"; "Upgrade". The API methods `RequeueAsync`, `CancelAsync`, `DeleteAsync` and the recurring manager's pause, resume and trigger methods exist in code and their docs; only the dashboard controls are deferred.

### 1.4 Non-goals

As requirements.md §7. In particular, M1 adds no plugin API (ADR-3) and no distributed-lock dependency (ADR-1).

---

## 2. Repository layout

```text
Bellhop.slnx
global.json                      SDK pin (10.0.x, rollForward latestFeature)
Directory.Build.props            TFMs, nullable, warnings-as-errors, version, analyzers
Directory.Packages.props         central package versions (exact)
.editorconfig
LICENSE                          MIT
src/
  Bellhop/                       core package (net8.0;net10.0)
    PublicAPI.Shipped.txt / PublicAPI.Unshipped.txt
    (root)                       user-facing public types, namespace Bellhop
    Storage/                     store-author contracts, namespace Bellhop.Storage
    Registry/                    job name table, metadata merge          (internal)
    Serialization/               System.Text.Json serializer, masking     (internal)
    Scheduling/                  cron parser, interval, time zones       (public ISchedule, Cron; parser internal)
    Client/                      IJobClient, enqueue pipeline            (internal impl)
    Engine/                      processor, worker, scheduler, recurring (internal)
    Storage/InMemory/            in-memory store                         (internal impl, public Use… extension)
    Hosting/                     AddBellhop, options, hosted service, startup summary
    Diagnostics/                 ActivitySource, Meter, health check, BellhopEventIds
  Bellhop.PostgreSql/            PostgreSQL store (depends on Npgsql)
    Migrations/V001__initial.sql (embedded resource)
  Bellhop.Dashboard/             ASP.NET Core dashboard + JSON API (FrameworkReference Microsoft.AspNetCore.App)
    Assets/                      index.html, app.js (ES modules), app.css — embedded resources
  Bellhop.Testing/               test harness (depends on Microsoft.Extensions.TimeProvider.Testing)
tests/
  Bellhop.Storage.Conformance/   abstract xUnit v3 test classes for IJobStore (library, not a test project)
  Bellhop.Tests/                 core unit tests + conformance run against the in-memory store
  Bellhop.PostgreSql.Tests/      conformance + PostgreSQL-specific tests (Testcontainers)
  Bellhop.Dashboard.Tests/       endpoint, security and JSON API tests (WebApplicationFactory)
  Bellhop.Testing.Tests/         harness tests
samples/
  Bellhop.Samples.Web/           the requirements.md §3 app, compiled in CI (M1-26)
docs/
  bellhop-architecture.md        this file
  getting-started.md             M1-26
stories/m1-core/                 the epic
```

Rules:

1. **Public surface is deliberate.** User-facing types live in namespace `Bellhop`; store-author contracts in `Bellhop.Storage`; everything else is `internal`. `Microsoft.CodeAnalysis.PublicApiAnalyzers` tracks the public API, so any public change shows up as a diff in `PublicAPI.Unshipped.txt` (NFR-5). Tests use `InternalsVisibleTo`.
2. **Core dependencies** are the BCL plus `Microsoft.Extensions.*` abstractions only (SEC-4): `DependencyInjection.Abstractions`, `Hosting.Abstractions`, `Logging.Abstractions`, `Options.ConfigurationExtensions`, `Options.DataAnnotations` (not needed if validation is hand-written; see M1-08), `Diagnostics.HealthChecks.Abstractions` and `Diagnostics.HealthChecks`. No cron library (A-11), no Newtonsoft, no Polly.
3. **No static mutable state** anywhere (TST-1). The `ActivitySource` and `Meter` are created per Bellhop instance through DI (`IMeterFactory` for the meter).
4. **One way per thing.** The store interface is the only persistence path; the engine never talks SQL. The engine's step functions (§7) are the only execution path. The hosted loops and the test harness both call them.
5. **A copied file cites its origin** in a header comment. M1 copies nothing from other projects.

---

## 3. Domain model (public contract)

These signatures are the contract. M1-02 creates them; later stories implement them. Small additions found necessary during a story are allowed and must be recorded in that story's Notes and in `PublicAPI.Unshipped.txt`. A change to a signature listed here needs an amendment to this section in the same commit.

### 3.1 User-facing types (`namespace Bellhop`)

```csharp
public interface IJob;                                   // marker; a job is a serializable data type (JOB-1)

public interface IJobHandler<in TJob> where TJob : IJob  // the only handler shape (JOB-5)
{
    Task HandleAsync(TJob job, JobContext ctx, CancellationToken ct);
}

public readonly record struct JobId(Guid Value)          // client-generated UUIDv7 (A-1)
{
    public static JobId New(TimeProvider time);          // time-ordered
    public static JobId Parse(string s);
    public static bool TryParse(string? s, out JobId id);
    public override string ToString();                   // "D" format, lower case
}

public enum JobState { Scheduled, Enqueued, Processing, Succeeded, Failed, DeadLettered, Cancelled, Awaiting, Unroutable }  // EXE-11

// Attributes: data only (JOB-7). All are [AttributeUsage(Class | Struct, Inherited = false)].
public sealed class JobNameAttribute(string name) : Attribute { public string Name { get; } public string[] Aliases { get; init; } = []; }
public sealed class QueueAttribute(string name) : Attribute;
public sealed class PriorityAttribute(int priority) : Attribute;
public sealed class RetryAttribute(int maxAttempts) : Attribute { public int[]? DelaysSeconds { get; init; } }
public sealed class TimeoutAttribute(int seconds) : Attribute;
public sealed class RecurringAttribute(string cron) : Attribute
{
    public string? Name { get; init; }                   // defaults to the job name
    public string TimeZone { get; init; } = "UTC";       // IANA id (REC-4)
    public OverlapPolicy Overlap { get; init; } = OverlapPolicy.Skip;
    public MisfireMode Misfire { get; init; } = MisfireMode.RunOnce;
    public int MisfireMax { get; init; } = 10;           // used by RunAll only
    public bool AllowRuntimeOverride { get; init; }
}
[AttributeUsage(Property | Parameter)] public sealed class SensitiveAttribute : Attribute;   // JOB-9

public enum OverlapPolicy { Skip, Queue, Allow, CancelPrevious }   // REC-6
public enum MisfireMode { RunOnce, Skip, RunAll }                  // REC-5

public sealed record RetrySettings(int MaxAttempts, IReadOnlyList<TimeSpan>? Delays = null);  // null delays = default backoff

public sealed class EnqueueOptions                        // SCH-4, M1 subset
{
    public string? Queue { get; init; }
    public int? Priority { get; init; }
    public IReadOnlyList<string>? Tags { get; init; }     // "key" or "key:value"
    public TimeSpan? Timeout { get; init; }
    public RetrySettings? Retry { get; init; }
    public IReadOnlyDictionary<string, object?>? Parameters { get; init; }   // EXT-6, serialized with the job serializer
}

public interface IJobClient                               // SCH-1, SCH-2, SCH-6; ordinary methods (TST-2)
{
    Task<JobId> EnqueueAsync<TJob>(TJob job, EnqueueOptions? options = null, CancellationToken ct = default) where TJob : IJob;
    Task<JobId> ScheduleAsync<TJob>(TJob job, DateTimeOffset at, EnqueueOptions? options = null, CancellationToken ct = default) where TJob : IJob;
    Task<JobId> ScheduleAsync<TJob>(TJob job, TimeSpan delay, EnqueueOptions? options = null, CancellationToken ct = default) where TJob : IJob;
    Task<CancelResult> CancelAsync(JobId id, CancellationToken ct = default);
    Task<bool> RequeueAsync(JobId id, CancellationToken ct = default);   // DeadLettered/Failed/Cancelled/Succeeded -> Enqueued, attempts reset (RET-5)
    Task<bool> DeleteAsync(JobId id, CancellationToken ct = default);    // removes a non-Processing job and its history
    Task<JobInfo?> GetAsync(JobId id, CancellationToken ct = default);
}

public enum CancelResult { Cancelled, CancellationRequested, AlreadyFinished, NotFound }

public sealed record JobInfo(JobId Id, string Name, JobState State, string Queue, int Priority, int Attempt, int MaxAttempts,
    DateTimeOffset CreatedAt, DateTimeOffset? DueAt, DateTimeOffset? StartedAt, DateTimeOffset? FinishedAt,
    IReadOnlyList<string> Tags, JobId? ParentId, string? RecurringName, double? Progress, string? ProgressMessage,
    IReadOnlyList<JobStateChange> History);

public sealed record JobStateChange(JobState State, DateTimeOffset At, string? Node, string Reason, int Attempt, JobError? Error);
public sealed record JobError(string Type, string Message, string? StackTrace);   // RET-4

public sealed class JobContext                            // JOB-6
{
    public JobId Id { get; }
    public string Name { get; }
    public int Attempt { get; }                           // 1-based
    public int MaxAttempts { get; }
    public DateTimeOffset EnqueuedAt { get; }             // creation time
    public DateTimeOffset? ScheduledAt { get; }           // due time for scheduled, retried and recurring jobs
    public string Queue { get; }
    public IReadOnlyList<string> Tags { get; }
    public JobId? ParentId { get; }
    public string? RecurringName { get; }
    public ILogger Logger { get; }                        // scoped with JobId, JobName, Attempt, Queue (OBS-4)
    public JobParameters Parameters { get; }              // EXT-6
    public ActivityContext TraceContext { get; }
    public Task ReportProgressAsync(double fraction, string? message = null, CancellationToken ct = default);
    public static JobContext CreateForTest(JobId? id = null, string name = "test", int attempt = 1, int maxAttempts = 5,
        string queue = "default", IEnumerable<string>? tags = null, ILogger? logger = null, TimeProvider? time = null);  // TST-5
}

public sealed class JobParameters                         // EXT-6
{
    public T? Get<T>(string key);
    public bool TryGet<T>(string key, out T? value);
    public Task SetAsync<T>(string key, T value, CancellationToken ct = default);   // persisted immediately
    public IReadOnlyCollection<string> Keys { get; }
}
```

Recurring jobs (REC-1, REC-2, REC-9, REC-11):

```csharp
public interface ISchedule
{
    string Kind { get; }                                  // "cron" | "interval" in M1
    string Expression { get; }                            // canonical, round-trips through Schedule.Parse
    DateTimeOffset? GetNextOccurrence(DateTimeOffset after, TimeZoneInfo timeZone);   // strictly after `after`
}

public static class Schedule                              // factory only; no state
{
    public static ISchedule Cron(string expression);      // 5 or 6 fields; throws FormatException naming the bad field
    public static ISchedule Every(TimeSpan interval);     // >= 1 s
    public static ISchedule Parse(string kind, string expression);
}

public static class Cron                                  // readable helpers returning cron strings
{
    public static string Minutely(); public static string Hourly(int minute = 0);
    public static string Daily(int hour = 0, int minute = 0);
    public static string Weekly(DayOfWeek day, int hour = 0, int minute = 0);
    public static string Monthly(int day = 1, int hour = 0, int minute = 0);
}

public sealed class RecurringOptions
{
    public string TimeZone { get; init; } = "UTC";
    public OverlapPolicy Overlap { get; init; } = OverlapPolicy.Skip;
    public MisfireMode Misfire { get; init; } = MisfireMode.RunOnce;
    public int MisfireMax { get; init; } = 10;
    public string? Queue { get; init; }
    public int? Priority { get; init; }
    public IReadOnlyList<string>? Tags { get; init; }
    public bool AllowRuntimeOverride { get; init; }       // code-defined only
}

public interface IRecurringJobManager
{
    Task<RecurringUpsertResult> AddOrUpdateAsync<TJob>(string name, ISchedule schedule, TJob? job = default,
        RecurringOptions? options = null, CancellationToken ct = default) where TJob : IJob;
    Task<bool> RemoveAsync(string name, CancellationToken ct = default);
    Task<TriggerResult> TriggerAsync(string name, CancellationToken ct = default);
    Task<TriggerResult> TriggerAsync<TJob>(string name, TJob payloadOverride, CancellationToken ct = default) where TJob : IJob;
    Task<bool> PauseAsync(string name, CancellationToken ct = default);
    Task<bool> ResumeAsync(string name, CancellationToken ct = default);
    Task<IReadOnlyList<RecurringJobInfo>> ListAsync(int offset = 0, int limit = 100, CancellationToken ct = default);
    Task<RecurringJobInfo?> GetAsync(string name, CancellationToken ct = default);
    Task<IReadOnlyList<DateTimeOffset>> GetNextOccurrencesAsync(string name, int count, CancellationToken ct = default);
}

public enum RecurringUpsertResult { Created, Updated, Unchanged }   // a rejected code-defined edit throws (REC-3)
public sealed record TriggerResult(JobId? JobId, RecurringOutcome Outcome);
public enum RecurringOutcome { Enqueued, Skipped, Queued, CancelledPrevious }
public sealed record RecurringJobInfo(string Name, string JobName, string ScheduleKind, string ScheduleExpression, string TimeZone,
    OverlapPolicy Overlap, MisfireMode Misfire, bool CodeDefined, bool Paused, bool Orphaned,
    DateTimeOffset? NextRunAt, DateTimeOffset? LastRunAt, RecurringOutcome? LastOutcome, JobId? LastJobId);
```

Extension points (EXT-1, EXT-2, EXT-3, RET-2, RET-6):

```csharp
public interface IJobMiddleware { Task InvokeAsync(JobExecutionContext ctx, JobExecutionDelegate next); }
public delegate Task JobExecutionDelegate(JobExecutionContext ctx);
public sealed class JobExecutionContext
{
    public JobContext Job { get; } public object Payload { get; } public Type JobType { get; }
    public IServiceProvider Services { get; } public CancellationToken CancellationToken { get; }
}

public interface IEnqueueMiddleware { Task InvokeAsync(EnqueueContext ctx, EnqueueDelegate next); }
public delegate Task EnqueueDelegate(EnqueueContext ctx);
public sealed class EnqueueContext
{
    public object Job { get; } public Type JobType { get; } public string JobName { get; }
    public string Queue { get; set; } public int Priority { get; set; }
    public IList<string> Tags { get; } public IDictionary<string, object?> Parameters { get; }
    public JobId? ParentId { get; }                       // set when enqueued from inside a handler (SCH-10)
}

public interface IJobSerializer
{
    string Serialize(object value, Type type);
    object Deserialize(string json, Type type);           // throws JobSerializationException
}

public interface IRetryPolicy { RetryDecision Decide(RetryContext context); }
public sealed record RetryContext(JobContext Job, Exception Exception, Type JobType);
public abstract record RetryDecision
{
    public static RetryDecision RetryAfter(TimeSpan delay);
    public static RetryDecision DeadLetter(string reason);
}
public sealed class PermanentJobFailureException(string message, Exception? inner = null) : Exception(message, inner);

public interface IJobEvents                               // all members default to no-op
{
    ValueTask OnEnqueuedAsync(JobEvent e) => default;
    ValueTask OnStartedAsync(JobEvent e) => default;
    ValueTask OnSucceededAsync(JobEvent e) => default;
    ValueTask OnFailedAsync(JobFailedEvent e) => default;        // WillRetry tells retry from dead-letter
    ValueTask OnDeadLetteredAsync(JobFailedEvent e) => default;
    ValueTask OnCancelledAsync(JobEvent e) => default;
    ValueTask OnRecurringMissedAsync(RecurringMissedEvent e) => default;
}
public sealed record JobEvent(JobId Id, string Name, string Queue, int Attempt, DateTimeOffset At, string? Reason);
public sealed record JobFailedEvent(JobId Id, string Name, string Queue, int Attempt, DateTimeOffset At, JobError Error, bool WillRetry, DateTimeOffset? RetryAt);
public sealed record RecurringMissedEvent(string Name, IReadOnlyList<DateTimeOffset> Missed, MisfireMode Policy, string Reason);
```

Configuration builder (SET-1, SET-10, JOB-7, REC-1, EXT-*):

```csharp
public static class BellhopServiceCollectionExtensions
{
    public static IServiceCollection AddBellhop(this IServiceCollection services, Action<BellhopBuilder>? configure = null);
}

public sealed class BellhopBuilder
{
    public IServiceCollection Services { get; }
    public BellhopBuilder Configure(Action<BellhopOptions> configure);          // code wins over IConfiguration (SET-3)
    public BellhopBuilder AddJobsFromAssemblyContaining<T>();
    public BellhopBuilder AddJobsFromAssembly(Assembly assembly);
    public JobBuilder<TJob> AddJob<TJob, THandler>() where TJob : IJob where THandler : class, IJobHandler<TJob>;
    public JobBuilder<TJob> ConfigureJob<TJob>() where TJob : IJob;             // fluent metadata for a scanned job (JOB-7)
    public BellhopBuilder AddRecurring<TJob>(string name, ISchedule schedule, TJob? job = default, RecurringOptions? options = null) where TJob : IJob;
    public BellhopBuilder UseMiddleware<TMiddleware>(Func<Type, bool>? appliesTo = null) where TMiddleware : class, IJobMiddleware;
    public BellhopBuilder UseEnqueueMiddleware<TMiddleware>() where TMiddleware : class, IEnqueueMiddleware;
    public BellhopBuilder UseSerializer<TSerializer>() where TSerializer : class, IJobSerializer;
    public BellhopBuilder UseRetryPolicy<TPolicy>() where TPolicy : class, IRetryPolicy;
    public BellhopBuilder UseJsonOptions(JsonSerializerOptions options);       // or a JsonSerializerContext via its Options
    public BellhopBuilder UseInMemoryStore();
    public BellhopBuilder UseStore<TStore>() where TStore : class, IJobStore;  // what UsePostgres calls (EXT-4)
}

public sealed class JobBuilder<TJob> where TJob : IJob                          // fluent wins over attributes (JOB-7)
{
    public JobBuilder<TJob> Named(string name, params string[] aliases);
    public JobBuilder<TJob> OnQueue(string queue);
    public JobBuilder<TJob> WithPriority(int priority);
    public JobBuilder<TJob> WithRetry(RetrySettings retry);
    public JobBuilder<TJob> WithRetryPolicy<TPolicy>() where TPolicy : class, IRetryPolicy;
    public JobBuilder<TJob> WithTimeout(TimeSpan timeout);
    public JobBuilder<TJob> Recurring(ISchedule schedule, RecurringOptions? options = null, string? name = null);
}
```

### 3.2 Options (`namespace Bellhop`), bound from `"Bellhop"` (SET-3, SET-4)

Every default is safe for a small production deployment (SET-4, NFR-3). Validation runs at startup; each failure message names the option path and the fix, for example: `Bellhop:PollInterval is 00:00:00.010; it must be between 00:00:00.100 and 00:01:00. Set it under "Bellhop:PollInterval" in configuration or with AddBellhop(b => b.Configure(o => o.PollInterval = ...)).`

| Option | Default | Valid range / rule |
|---|---|---|
| `Mode` | `Both` | `Both`, `ClientOnly`, `WorkerOnly` (SET-7) |
| `Namespace` | `""` | ≤ 64 chars, `[a-z0-9-_.]` (STO-9) |
| `NodeName` | `{MachineName}:{ProcessId}:{4 random hex}` | ≤ 200 chars |
| `Queues` | `["default"]` | non-empty, unique, names `[a-z0-9-_.:]{1,100}`; order is strict priority (CON-1) |
| `WorkerCount` | `max(8, 2 × ProcessorCount)` | 1 to 1000 (CON-6) |
| `QueueConcurrency` | empty | per-queue limit, 1 to `WorkerCount` |
| `PollInterval` | 1 s | 100 ms to 1 min (EXE-8) |
| `LeaseDuration` | 60 s | 10 s to 1 h; heartbeat every third (EXE-3, A-8) |
| `ShutdownTimeout` | 30 s | 0 to 10 min (EXE-6) |
| `CancellationGracePeriod` | 10 s | 0 to 5 min: after a timeout or shutdown cancels the token, how long before the handler is abandoned (EXE-7) |
| `DefaultTimeout` | none | > 0 when set |
| `Retry.MaxAttempts` | 5 | 1 to 100 (RET-1) |
| `Retry.Delays` | 10 s, 1 min, 5 min, 30 min | each > 0; the last repeats if attempts exceed the list; ±20% jitter |
| `MisfireThreshold` | 1 min | 1 s to 1 day (A-13) |
| `RecurringBatchSize` | 100 | 1 to 1000 |
| `NodeHeartbeatInterval` | 15 s | 1 s to 5 min |
| `NodeTimeout` | 5 min | > 4 × heartbeat; stale nodes are removed by cleanup |
| `ClockSkewWarningThreshold` | 5 s | 1 s to 10 min (EXE-9) |
| `Retention.Succeeded` | **7 days** (D6) | ≥ 1 min |
| `Retention.Cancelled` | 7 days | ≥ 1 min |
| `Retention.DeadLettered` | 30 days | ≥ 1 h (never deleted before it expires, RET-3) |
| `Cleanup.Interval` | 5 min | 10 s to 1 day |
| `Cleanup.BatchSize` | 500 | 10 to 10,000 (STO-7) |
| `Cleanup.PauseBetweenBatches` | 200 ms | 0 to 10 s |
| `Payload.SoftLimitBytes` | 65,536 | > 0 (STO-10) |
| `Payload.HardLimitBytes` | 1,048,576 | ≥ soft limit |
| `ExecutionMode` | `Background` | `Background`, `Inline` (TST-4) |
| `HealthCheck.SchedulingLagThreshold` | 1 min | > 0 (OBS-5) |
| `HealthCheck.DeadLetterGrowthThreshold` | 100 per hour | ≥ 0; 0 disables |
| `HealthCheck.StoreFailureThreshold` | 30 s | how long continuous store errors may last before the check is unhealthy |

`PostgreSqlStoreOptions` (bound from `"Bellhop:PostgreSql"`): `ConnectionString` (or an `NpgsqlDataSource` from DI), `Schema` (`bellhop`, a valid unquoted identifier), `AutoMigrate` (true, D4), `CommandTimeout` (30 s), `UseNotifications` (true).

---

## 4. Persistence

### 4.1 In-memory store

One instance per Bellhop instance (never static). All state behind one `lock`, so every method is atomic. Time comes from the injected `TimeProvider`, which plays the role of the database clock. Ordering is deterministic: ties are broken by `JobId`, which is time-ordered. Nothing survives a restart. That is its documented contract, and SET-2 warns about it outside Development.

### 4.2 PostgreSQL schema v1 (6 tables, STO-3)

All objects live in the configured schema (default `bellhop`). Every row carries `namespace` (STO-9). States are stored as text with a `CHECK`, so DBAs can read them. Timestamps are `timestamptz`; every due-check uses `now()` (EXE-9).

```sql
CREATE TABLE {schema}.meta (            -- schema version and short leases (EXE-10, ADR-1)
  key         text PRIMARY KEY,         -- 'schema_version' | 'lease:{namespace}:{name}'
  value       text NULL,
  owner       text NULL,
  expires_at  timestamptz NULL
);

CREATE TABLE {schema}.jobs (
  id                   uuid PRIMARY KEY,
  namespace            text NOT NULL,
  name                 text NOT NULL,
  payload              jsonb NOT NULL,
  queue                text NOT NULL,
  priority             int NOT NULL DEFAULT 0,
  state                text NOT NULL CHECK (state IN ('Scheduled','Enqueued','Processing','Succeeded','Failed','DeadLettered','Cancelled','Awaiting','Unroutable')),
  attempt              int NOT NULL DEFAULT 0,
  max_attempts         int NOT NULL,
  retry                jsonb NULL,         -- per-enqueue RetrySettings override
  timeout_ms           int NULL,
  created_at           timestamptz NOT NULL,
  due_at               timestamptz NULL,   -- Scheduled due time, or Failed retry time
  enqueued_at          timestamptz NULL,   -- last time it entered Enqueued (FIFO key)
  started_at           timestamptz NULL,
  finished_at          timestamptz NULL,   -- set on Succeeded/DeadLettered/Cancelled
  lease_owner          text NULL,
  lease_token          uuid NULL,
  lease_expires_at     timestamptz NULL,
  cancel_requested_at  timestamptz NULL,
  progress             real NULL,
  progress_message     text NULL,
  parent_id            uuid NULL,
  recurring_name       text NULL,
  trace_parent         text NULL,
  trace_state          text NULL,
  parameters           jsonb NOT NULL DEFAULT '{}',
  last_error           text NULL           -- "Type: message" of the latest failure, for lists
);
CREATE INDEX jobs_ready     ON {schema}.jobs (namespace, queue, priority DESC, enqueued_at, id) WHERE state = 'Enqueued';
CREATE INDEX jobs_due       ON {schema}.jobs (namespace, due_at) WHERE state IN ('Scheduled','Failed');
CREATE INDEX jobs_lease     ON {schema}.jobs (namespace, lease_expires_at) WHERE state = 'Processing';
CREATE INDEX jobs_state     ON {schema}.jobs (namespace, state, created_at DESC, id DESC);
CREATE INDEX jobs_finished  ON {schema}.jobs (namespace, state, finished_at) WHERE finished_at IS NOT NULL;
CREATE INDEX jobs_name      ON {schema}.jobs (namespace, name, created_at DESC, id DESC);
CREATE INDEX jobs_recurring ON {schema}.jobs (namespace, recurring_name, created_at) WHERE recurring_name IS NOT NULL AND state IN ('Scheduled','Enqueued','Processing','Failed','Awaiting');
CREATE INDEX jobs_unroutable ON {schema}.jobs (namespace, name) WHERE state = 'Unroutable';

CREATE TABLE {schema}.job_history (     -- every transition (EXE-11) and every attempt's error (RET-4)
  job_id         uuid NOT NULL REFERENCES {schema}.jobs(id) ON DELETE CASCADE,
  seq            bigint GENERATED ALWAYS AS IDENTITY,
  state          text NOT NULL,
  at             timestamptz NOT NULL,
  node           text NULL,
  reason         text NOT NULL,
  attempt        int NOT NULL,
  error_type     text NULL,
  error_message  text NULL,
  stack_trace    text NULL,
  PRIMARY KEY (job_id, seq)
);

CREATE TABLE {schema}.job_index (       -- STO-11; tags use index name 'tag'
  namespace   text NOT NULL,
  index_name  text NOT NULL,
  value       text NOT NULL,
  job_id      uuid NOT NULL REFERENCES {schema}.jobs(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL,
  PRIMARY KEY (namespace, index_name, value, job_id)
);
CREATE INDEX job_index_job ON {schema}.job_index (job_id);

CREATE TABLE {schema}.recurring_jobs (
  namespace               text NOT NULL,
  name                    text NOT NULL,
  job_name                text NOT NULL,
  payload                 jsonb NULL,
  schedule_kind           text NOT NULL,
  schedule_expr           text NOT NULL,
  time_zone               text NOT NULL,
  misfire                 text NOT NULL,
  misfire_max             int NOT NULL,
  overlap                 text NOT NULL,
  queue                   text NULL,
  priority                int NULL,
  tags                    text[] NOT NULL DEFAULT '{}',
  code_defined            boolean NOT NULL,
  defined_by              text NULL,       -- application name of the code that defined it (A-15)
  allow_runtime_override  boolean NOT NULL DEFAULT false,
  paused                  boolean NOT NULL DEFAULT false,
  orphaned_at             timestamptz NULL,
  next_run_at             timestamptz NULL,
  last_run_at             timestamptz NULL,
  last_outcome            text NULL,
  last_job_id             uuid NULL,
  created_at              timestamptz NOT NULL,
  updated_at              timestamptz NOT NULL,
  PRIMARY KEY (namespace, name)
);
CREATE INDEX recurring_due ON {schema}.recurring_jobs (namespace, next_run_at) WHERE NOT paused AND orphaned_at IS NULL;   -- REC-7

CREATE TABLE {schema}.nodes (
  namespace     text NOT NULL,
  id            text NOT NULL,
  host          text NOT NULL,
  mode          text NOT NULL,
  queues        text[] NOT NULL,
  worker_count  int NOT NULL,
  in_flight     int NOT NULL,
  version       text NOT NULL,
  started_at    timestamptz NOT NULL,
  heartbeat_at  timestamptz NOT NULL,
  PRIMARY KEY (namespace, id)
);
```

M1-18 owns this schema. Index changes found necessary during M1-19 to M1-21 are made in `V001` while nothing has shipped. After the first preview is published, every change is a new migration.

### 4.3 Migrations (STO-3)

- Scripts are embedded resources `V{NNN}__{slug}.sql` containing a `{schema}` placeholder. The schema name is validated as an identifier (`^[a-z_][a-z0-9_]{0,62}$`) before substitution, so nothing user-supplied is interpolated unchecked.
- `InitializeAsync` opens a transaction and takes `pg_advisory_xact_lock(hashtext('bellhop:migrate:' || schema))`, so several nodes starting at once migrate exactly once (REC-3 style idempotency). It then reads `meta.schema_version`, applies each missing script in order in that transaction, writes the new version and commits. It logs each applied version (event 1501).
- `AutoMigrate = false` with an older schema fails startup with: `Bellhop's PostgreSQL schema "bellhop" is at version 0 but this version of Bellhop needs version 1. AutoMigrate is off, so apply the script from BellhopPostgreSqlSchema.GetScript(fromVersion: 0, schema: "bellhop") and restart, or set Bellhop:PostgreSql:AutoMigrate to true.` (Mismatch M-1 for the method name.)
- `BellhopPostgreSqlSchema.GetScript(int fromVersion, string schema = "bellhop")` returns the concatenated scripts with the version updates. A test proves that the script and `AutoMigrate` produce identical catalogs.

### 4.4 Atomicity per operation

| Operation | How it stays atomic |
|---|---|
| Create jobs | One transaction: `INSERT` jobs + history + index rows; `pg_notify` in the same transaction (delivered on commit). |
| Claim (EXE-2) | One statement: a CTE selecting `FOR UPDATE SKIP LOCKED` from `jobs_ready` across the requested queues in their order, then `UPDATE … SET state='Processing', attempt=attempt+1, lease_*` with a new `lease_token`, plus a history insert, `RETURNING` the claimed rows. |
| Renew leases | One `UPDATE … WHERE (id, lease_token) IN (…)`; returns the rows renewed and their `cancel_requested_at`. Rows not returned were lost. |
| Complete | One transaction fenced by `WHERE id=@id AND state='Processing' AND lease_token=@token`. 0 rows: the lease was lost, nothing is written, and `false` is returned. For a recurring occurrence it also promotes the oldest `Awaiting` occurrence of the same recurring name (§7.7). |
| Tick | One statement of data-modifying CTEs (promote due, recover expired leases, reroute unroutable, heartbeat node, select due recurring, return `now()` and per-queue ready flags). `SKIP LOCKED` in every sub-select that updates, so concurrent ticks on N nodes never block or double-process. |
| Fire recurring (REC-7) | One transaction: `UPDATE recurring_jobs SET next_run_at=@new … WHERE namespace=@ns AND name=@name AND next_run_at=@expected` (compare-and-set). 0 rows: another node fired, return `NotFired`. Otherwise run the overlap check against `jobs_recurring` and insert the occurrence jobs. |
| Reconcile recurring (REC-3) | One transaction: `INSERT … ON CONFLICT (namespace, name) DO UPDATE` per definition, only when a field changed. `next_run_at` is recomputed only when the schedule or time zone changed (REC-10). Then mark orphans. |
| Purge (STO-7) | `DELETE … WHERE id IN (SELECT id … ORDER BY finished_at LIMIT @batch FOR UPDATE SKIP LOCKED)` using `jobs_finished`; history and index cascade. |

### 4.5 Ids

- `JobId` is a UUIDv7 generated by the client from `TimeProvider` (A-1). `Guid.CreateVersion7` does not exist on net8.0, so a small internal generator is used on both targets for identical behaviour. Insert of an existing id fails with `DuplicateJobIdException`. The id is never reused.
- Recurring definitions are keyed by `(namespace, name)`; names follow job-name rules (§6.1).
- Node ids come from `BellhopOptions.NodeName` and are unique per process start.
- `lease_token` is a fresh UUID per claim and acts as the fencing token.

### 4.6 Schema version window (STO-5)

Each library version declares `SchemaVersion` (the version it writes) and accepts databases at `SchemaVersion` or `SchemaVersion + 1`. A lower version is migrated when `AutoMigrate` is on and fails fast when it is off. A higher version than `SchemaVersion + 1` fails fast with `…schema is at version {n}, newer than this version of Bellhop supports ({min}–{max}). Upgrade the Bellhop packages on this node.` In M1 `SchemaVersion = 1`. Migrations must therefore be expand-only (add tables, columns and indexes; never drop or rename in the same release). The two-version rolling test lands with the first v2 migration in M2.

### 4.7 Missing or corrupt data

| Case | Behaviour |
|---|---|
| Schema missing, `AutoMigrate` on | Created. Log 1501. |
| Schema missing, `AutoMigrate` off | Startup fails (§4.3). |
| `meta.schema_version` unparsable | Startup fails: `…schema_version value "x" is not a number; the schema may have been edited by hand.` |
| Payload JSON no longer matches the type (breaking payload change) | `JobSerializationException`. The job is dead-lettered immediately with reason `DeserializationFailed` (retrying cannot help) and is requeueable after a fix (RET-5). Log 1203. |
| Job name with no handler on this node | `Unroutable` (§7.3); never failed or deleted (JOB-3). |
| Recurring row with an unknown schedule kind or invalid cron (edited in the database) | That definition is skipped and paused with `last_outcome = 'Invalid'`. Log 1404 with the name. Other definitions continue. |
| Unknown IANA time zone on this node | As above, reason `InvalidTimeZone`. |

---

## 5. Store contract (`namespace Bellhop.Storage`)

`IJobStore` has 24 methods and one property (STO-1 target: under 25). Every method is async, takes a `CancellationToken`, and is atomic as described in §4.4. Stores implement exactly this, plus `IJobIndex`, plus `IJobStoreNotifications` if they can push.

### 5.1 Interfaces

```csharp
public interface IJobStore
{
    StoreCapabilities Capabilities { get; }

    // lifecycle
    Task<StoreInfo> InitializeAsync(CancellationToken ct);                                  // migrate or verify schema; no-op for in-memory

    // jobs
    Task CreateJobsAsync(IReadOnlyList<NewJob> jobs, CancellationToken ct);                 // all or nothing
    Task<IReadOnlyList<ClaimedJob>> ClaimAsync(ClaimRequest request, CancellationToken ct);
    Task<RenewResult> RenewLeasesAsync(string nodeId, IReadOnlyList<LeaseRef> leases, TimeSpan duration, CancellationToken ct);
    Task<bool> CompleteAsync(Completion completion, CancellationToken ct);                  // false = lease lost, nothing written
    Task UpdateProgressAsync(LeaseRef lease, double fraction, string? message, CancellationToken ct);
    Task SetParameterAsync(JobId id, string key, string json, CancellationToken ct);
    Task<CancelResult> CancelAsync(JobId id, string reason, CancellationToken ct);
    Task<bool> RequeueAsync(JobId id, string reason, CancellationToken ct);
    Task<bool> DeleteAsync(JobId id, CancellationToken ct);

    // background
    Task<TickResult> TickAsync(TickRequest request, CancellationToken ct);
    Task ShutdownNodeAsync(string nodeId, IReadOnlyList<LeaseRef> release, CancellationToken ct);   // release leases, unregister node
    Task<bool> TryAcquireLeaseAsync(string name, string owner, TimeSpan duration, CancellationToken ct);
    Task<int> PurgeAsync(PurgeRequest request, CancellationToken ct);                       // one batch; returns rows deleted

    // recurring
    Task<ReconcileResult> ReconcileRecurringAsync(ReconcileRequest request, CancellationToken ct);
    Task<RecurringUpsertResult> UpsertRecurringAsync(RecurringDefinition definition, CancellationToken ct);   // runtime-defined
    Task<bool> RemoveRecurringAsync(string name, CancellationToken ct);
    Task<bool> SetRecurringPausedAsync(string name, bool paused, CancellationToken ct);
    Task<FireResult> FireRecurringAsync(RecurringFire fire, CancellationToken ct);
    Task<Page<RecurringDefinition>> QueryRecurringAsync(RecurringQuery query, CancellationToken ct);

    // read side (dashboard, client)
    Task<JobDetails?> GetJobAsync(JobId id, CancellationToken ct);
    Task<Page<JobSummary>> QueryJobsAsync(JobQuery query, CancellationToken ct);
    Task<StoreStatistics> GetStatisticsAsync(CancellationToken ct);
    Task<IReadOnlyList<NodeRecord>> GetNodesAsync(CancellationToken ct);
}

public interface IJobIndex                                                                  // STO-11
{
    Task AddAsync(JobId id, string index, string value, CancellationToken ct);
    Task RemoveAsync(JobId id, string index, string value, CancellationToken ct);
    Task<Page<JobId>> QueryAsync(string index, string value, PageRequest page, CancellationToken ct);
    Task<long> CountAsync(string index, string value, CancellationToken ct);
}

public interface IJobStoreNotifications                                                     // only stores with push (EXE-8)
{
    Task ListenAsync(Func<StoreSignal, ValueTask> onSignal, CancellationToken ct);         // runs until ct; reconnects internally
}
public abstract record StoreSignal { public sealed record JobsReady(string Queue) : StoreSignal; public sealed record CancelRequested(JobId Id) : StoreSignal; public sealed record Reconnected : StoreSignal; }

[Flags] public enum StoreCapabilities { None = 0, PushNotifications = 1, TransactionalEnqueue = 2, PayloadSearch = 4, ResultStorage = 8 }
```

The store is scoped to one namespace, which it takes from `BellhopOptions` at construction, so methods carry no namespace argument.

### 5.2 Records

```csharp
public sealed record StoreInfo(string Description, int SchemaVersion);        // "PostgreSQL 16.4, schema bellhop v1"; never a connection string (SEC-5)

public sealed record NewJob(JobId Id, string Name, string Payload, string Queue, int Priority, JobState State,   // Enqueued | Scheduled | Awaiting
    DateTimeOffset? DueAt, TimeSpan? Delay,                    // Scheduled: exactly one of them; Delay resolved on the store clock (EXE-9)
    int MaxAttempts, RetrySettings? Retry, TimeSpan? Timeout,
    IReadOnlyList<string> Tags, IReadOnlyDictionary<string, string> Parameters,   // values are JSON
    JobId? ParentId, string? RecurringName, string? TraceParent, string? TraceState, string Reason);

public sealed record ClaimRequest(string NodeId, IReadOnlyList<QueueSlots> Queues, IReadOnlyCollection<string> RoutableNames, TimeSpan LeaseDuration);
public sealed record QueueSlots(string Queue, int Max);       // in priority order; queues at their limit are omitted

public sealed record ClaimedJob(JobId Id, string Name, string Payload, string Queue, int Priority, int Attempt, int MaxAttempts,
    RetrySettings? Retry, TimeSpan? Timeout, DateTimeOffset CreatedAt, DateTimeOffset? DueAt, IReadOnlyList<string> Tags,
    IReadOnlyDictionary<string, string> Parameters, JobId? ParentId, string? RecurringName, string? TraceParent, string? TraceState,
    LeaseRef Lease, DateTimeOffset LeaseExpiresAt, bool Unroutable);   // Unroutable = name not in RoutableNames; already moved to Unroutable

public sealed record LeaseRef(JobId Id, Guid Token);
public sealed record RenewResult(IReadOnlyList<JobId> Lost, IReadOnlyList<JobId> CancelRequested);

public enum CompletionOutcome { Succeeded, Failed, DeadLettered, Cancelled }
public sealed record Completion(LeaseRef Lease, string NodeId, CompletionOutcome Outcome, DateTimeOffset? RetryAt, JobError? Error, string Reason);

public sealed record TickRequest(string NodeId, int BatchSize, IReadOnlyCollection<string> RoutableNames,
    IReadOnlyList<string> Queues, NodeHeartbeat? Heartbeat, bool IncludeRecurring);
public sealed record NodeHeartbeat(string Host, string Mode, IReadOnlyList<string> Queues, int WorkerCount, int InFlight, string Version);
public sealed record TickResult(DateTimeOffset StoreNow, int Promoted, IReadOnlyList<RecoveredJob> Recovered, int Rerouted,
    IReadOnlyList<string> QueuesWithReadyJobs, IReadOnlyList<RecurringDefinition> DueRecurring);
public sealed record RecoveredJob(JobId Id, string Name, string Queue, int Attempt, bool DeadLettered);

public sealed record PurgeRequest(IReadOnlyDictionary<JobState, TimeSpan> RetainFor, int BatchSize, TimeSpan NodeTimeout);

public sealed record RecurringDefinition(string Name, string JobName, string? Payload, string ScheduleKind, string ScheduleExpression,
    string TimeZone, MisfireMode Misfire, int MisfireMax, OverlapPolicy Overlap, string? Queue, int? Priority, IReadOnlyList<string> Tags,
    bool CodeDefined, string? DefinedBy, bool AllowRuntimeOverride, bool Paused, DateTimeOffset? OrphanedAt,
    DateTimeOffset? NextRunAt, DateTimeOffset? LastRunAt, RecurringOutcome? LastOutcome, JobId? LastJobId);

public sealed record ReconcileRequest(string DefinedBy, IReadOnlyList<RecurringDefinition> CodeDefined, DateTimeOffset Now,
    Func<RecurringDefinition, DateTimeOffset?> ComputeNextRun);   // engine computes; store calls it only for new or schedule-changed rows
public sealed record ReconcileResult(int Created, int Updated, int Unchanged, IReadOnlyList<string> Orphaned, IReadOnlyList<string> Restored);

public sealed record RecurringFire(string Name, DateTimeOffset ExpectedNextRunAt, DateTimeOffset? NewNextRunAt,
    IReadOnlyList<NewJob> Occurrences, OverlapPolicy Overlap, bool Manual);   // Manual = TriggerAsync: no CAS on next_run_at
public sealed record FireResult(bool Fired, RecurringOutcome? Outcome, IReadOnlyList<JobId> Created, IReadOnlyList<JobId> CancelRequested);

public sealed record JobQuery(JobState? State, string? Name, string? Queue, string? Tag, DateTimeOffset? From, DateTimeOffset? To,
    string? RecurringName, PageRequest Page);
public sealed record PageRequest(int Limit = 50, string? Cursor = null);      // keyset cursor, opaque (DSH-8)
public sealed record Page<T>(IReadOnlyList<T> Items, string? NextCursor);
public sealed record RecurringQuery(PageRequest Page, string? Name = null);

public sealed record JobSummary(JobId Id, string Name, JobState State, string Queue, int Priority, int Attempt, int MaxAttempts,
    DateTimeOffset CreatedAt, DateTimeOffset? DueAt, DateTimeOffset? StartedAt, DateTimeOffset? FinishedAt,
    double? Progress, string? LastError, string? RecurringName);
public sealed record JobDetails(JobSummary Summary, string Payload, IReadOnlyList<string> Tags, IReadOnlyDictionary<string, string> Parameters,
    JobId? ParentId, string? TraceParent, string? ProgressMessage, string? LeaseOwner, DateTimeOffset? LeaseExpiresAt,
    DateTimeOffset? CancelRequestedAt, IReadOnlyList<JobStateChange> History);

public sealed record StoreStatistics(IReadOnlyDictionary<JobState, long> ByState, IReadOnlyDictionary<string, long> EnqueuedByQueue,
    long SucceededLastHour, long FailedLastHour, DateTimeOffset StoreNow);
public sealed record NodeRecord(string Id, string Host, string Mode, IReadOnlyList<string> Queues, int WorkerCount, int InFlight,
    string Version, DateTimeOffset StartedAt, DateTimeOffset HeartbeatAt);
```

### 5.3 Method semantics (each is a conformance test group)

| Method | Semantics |
|---|---|
| `CreateJobsAsync` | Inserts all or none. `Enqueued` sets `enqueued_at = now`. `Scheduled` with `Delay` sets `due_at = store now + delay`. Duplicate id: `DuplicateJobIdException`, nothing written. Tags go into the index under `tag`. Wakes local workers and, with push, other nodes. |
| `ClaimAsync` | Claims up to `Max` per queue, in queue order, then priority descending, then `enqueued_at`, then id. Each claimed job goes to `Processing`, `attempt + 1`, new lease. A job whose name is not in `RoutableNames` goes to `Unroutable` with no attempt counted, and is returned with `Unroutable = true` so the engine can log it. N concurrent claimers never get the same job (conformance: 8 claimers, 1,000 jobs, each claimed exactly once). |
| `RenewLeasesAsync` | Extends the leases still held by `(id, token)`. Returns the ones lost, and the ones with a cancel request. |
| `CompleteAsync` | Fenced by lease token. `Succeeded`/`DeadLettered`/`Cancelled` set `finished_at`; `Failed` sets `due_at = RetryAt`. Clears the lease. Appends history with the error. Promotes the next `Awaiting` occurrence of the same recurring name, if any (§7.7). Records `last_outcome` on the recurring definition. |
| `CancelAsync` | `Scheduled`/`Enqueued`/`Failed`/`Awaiting`/`Unroutable` → `Cancelled` immediately. `Processing` → sets `cancel_requested_at` and signals (`CancellationRequested`). Terminal → `AlreadyFinished`. Missing → `NotFound`. |
| `RequeueAsync` | Any non-Processing state → `Enqueued`, `attempt = 0`, history reason as given. `Processing` → false. |
| `DeleteAsync` | Removes a non-Processing job with its history and index rows. `Processing` → false. |
| `TickAsync` | In one round-trip: (1) promote `Scheduled` and `Failed` jobs with `due_at <= now` to `Enqueued`, up to `BatchSize`; (2) recover `Processing` jobs with `lease_expires_at < now`: attempts remaining → `Enqueued` with reason `Interrupted`, else `DeadLettered` with reason `Interrupted` (EXE-4); (3) move `Unroutable` jobs whose name is in `RoutableNames` back to `Enqueued`; (4) upsert the node heartbeat when given; (5) when `IncludeRecurring`, return up to `BatchSize` definitions with `next_run_at <= now`, not paused and not orphaned; (6) return which of `Queues` have ready jobs, and `now`. |
| `ShutdownNodeAsync` | Releases the given leases back to `Enqueued` with reason `Shutdown`, attempt restored (A-9). Deletes the node row. |
| `TryAcquireLeaseAsync` | Inserts, or takes over an expired lease, or renews its own. Returns whether `owner` holds it. |
| `PurgeAsync` | Deletes up to `BatchSize` terminal jobs older than their state's retention (by `finished_at`), and nodes whose heartbeat is older than `NodeTimeout`. Never touches non-terminal jobs. |
| `ReconcileRecurringAsync` | Upserts every code-defined definition by name (idempotent, safe under concurrent calls). Marks orphaned the code-defined rows with the same `DefinedBy` that are absent from the request; clears `orphaned_at` on rows present again (A-15). Never deletes. A runtime-defined row with the same name as a code-defined one is replaced, since the code wins. |
| `UpsertRecurringAsync` | Runtime-defined create or update. Throws `RecurringDefinitionConflictException` when the existing row is code-defined and `AllowRuntimeOverride` is false. A schedule or time-zone change recomputes `next_run_at` from now (REC-10). |
| `FireRecurringAsync` | Compare-and-set on `next_run_at` (skipped when `Manual`). Then applies the overlap policy (§7.7) and inserts the occurrences. Returns `Fired = false` when the CAS lost. |
| Read methods | Keyset-paged, index-backed (DSH-8), never more than `Limit ≤ 500` rows. |

---

## 6. Core behaviour

### 6.1 Job registry (JOB-1 to JOB-3, JOB-7, SET-10, SEC-2)

- Built once at host start from every `AddJob…` call and scan; registration itself only records types (SET-5).
- Name = `[JobName]` or fluent `Named(...)`, else the type's simple name. Names match `^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$`.
- A name or alias claimed by two types fails startup: `Job name "send-email" is used by both App.SendEmail and Billing.SendEmail. Give one of them a different [JobName].`
- A job type without a handler, or a handler for an unregistered job, fails startup with the type names.
- Handler lookup is by stored name only, through the registry's dictionary (SEC-2). Aliases resolve to the same entry.
- Metadata merge order (last wins): global options → attributes → fluent `JobBuilder` → `EnqueueOptions`.
- `Registry.RoutableNames` = every name and alias with a handler on this node.

### 6.2 Serialization (JOB-4, STO-10, JOB-9)

- Default `JsonSerializerOptions`: `JsonSerializerDefaults.Web`, `UnmappedMemberHandling.Skip`, no `TypeInfoResolver` polymorphism beyond what the user declares with `[JsonDerivedType]`, enums as strings. `UseJsonOptions` replaces them; supplying options built on a `JsonSerializerContext` enables AOT later.
- The payload size is checked in the client after serialization. Over the soft limit, warning 1101 is logged with the job name and size. Over the hard limit, `JobPayloadTooLargeException` is thrown with: `The payload of job "x" is 1,203,331 bytes, over the 1,048,576-byte limit (Bellhop:Payload:HardLimitBytes). Store large data in your own storage and put a reference in the job.`
- Masking: `IPayloadMasker` (internal) walks the registered job type's properties and constructor parameters for `[Sensitive]`, recursing into nested records and collections, and replaces their values with `"***"` in a `JsonNode` copy. Used by the dashboard API. Pure function, unit-tested.

### 6.3 Hosting (SET-1 to SET-8)

- `AddBellhop` registers options (bound from `"Bellhop"`, then code `Configure` calls), the registry, the serializer, `IJobClient`, `IRecurringJobManager`, the engine, `TimeProvider.System` (only if none is registered) and one hosted service `BellhopHostedService`. It performs no I/O (SET-5).
- When no store is registered, `UseInMemoryStore()` is applied, and outside Development startup logs warning 1002 `No job store configured; using the in-memory store. Jobs are lost when the process stops. Call UsePostgres(...) or another store in AddBellhop.` (SET-2).
- `BellhopHostedService.StartAsync`: validate options → build registry → `store.InitializeAsync` → (worker modes) reconcile code-defined recurring jobs → start scheduler, worker and notification loops → log the startup summary (SET-8, event 1001). A failure in any step throws, so the host fails to start with the message (P5).
- `StopAsync`: graceful shutdown (§7.5).
- Mode `ClientOnly` runs no loops and does not reconcile (A-14). `WorkerOnly` runs everything but is expected not to enqueue; it is not prevented.
- Build-time tools (OpenAPI document generation, EF design-time) build the host but never start it, so nothing runs (SET-5). M1-08 proves this with a test that builds a host without starting it and asserts the store was never called.
- The startup summary is one multi-line log entry, for example:

```text
Bellhop started
  store      PostgreSQL 16.4, schema bellhop v1 (auto-migrate on)
  node       web-1:4120:9f3a  mode Both  namespace (default)
  queues     critical, default  workers 16 (critical ≤ 4)
  jobs       12 registered
  recurring  nightly-cleanup  0 3 * * *  Europe/Sofia  next 2026-11-04 03:00 +02:00
  dashboard  /jobs  (authorization: policy Admins)
```

The dashboard line is contributed by `Bellhop.Dashboard` through the internal `IStartupSummaryContributor`. Connection strings and passwords never appear (SEC-5).

### 6.4 Client (SCH-1, SCH-2, SCH-6, SCH-10, EXT-2)

`EnqueueAsync`: resolve the registration (unregistered job type → `InvalidOperationException` naming the type and `AddJob`) → build `EnqueueContext` from merged metadata → run `IEnqueueMiddleware` in registration order → serialize and size-check → create the `NewJob` with `ParentId` and trace context from the ambient job execution, if any (SCH-10, through an internal `AsyncLocal` owned by the Bellhop instance) → start a producer `Activity` → `store.CreateJobsAsync` → wake local workers → `IJobEvents.OnEnqueuedAsync`. Store exceptions propagate to the caller unchanged, with the job name in the log (event 1102). The client does not retry (A-2).

---

## 7. Engine flows

The engine is built from **step functions** with no loops inside them. The hosted loops call them on timers and signals; `Bellhop.Testing` calls them directly (§9).

| Step | Does |
|---|---|
| `JobProcessor.ExecuteAsync(ClaimedJob, CancellationToken shutdown)` | One attempt of one job, through to `CompleteAsync` |
| `WorkerLoop.ClaimOnceAsync()` | One claim call sized to free slots, which starts processors |
| `Scheduler.TickOnceAsync()` | One `TickAsync`, then fires due recurring definitions |
| `Cleanup.RunOnceAsync()` | Purge batches under the cleanup lease |
| `RecurringReconciler.ReconcileAsync()` | Startup upsert of code-defined definitions |

### 7.1 Worker loop (EXE-1, EXE-8, CON-1, CON-6)

1. Slots: a `SemaphoreSlim(WorkerCount)` plus one per queue with a limit. Workers are async tasks, not threads.
2. Wait for any of: a local wake signal (enqueue on this node, promotion by a tick, a push `JobsReady`), the tick result's `QueuesWithReadyJobs` being non-empty, or a free slot after a previous full claim.
3. Claim with `QueueSlots` = free slots per queue in configured order (queues at their limit omitted). If the claim returned as many jobs as requested, claim again immediately (the tight loop); otherwise wait.
4. Each claimed job runs `JobProcessor.ExecuteAsync` on its own task, releasing its slot on completion.
5. Store errors: log 1201, record the failure for the health check, and back off exponentially from `PollInterval` to 30 s; reset on success. The loop never exits on an exception, except when the host stops.

The tick (§7.4) runs every `PollInterval` and is the **only** periodic query when idle (STO-6). It tells the worker loop which queues have ready jobs, so an idle node with or without notifications costs one query per poll interval.

### 7.2 Heartbeat and cancellation (EXE-3, SCH-6)

- Every `LeaseDuration / 3`, one `RenewLeasesAsync` for all in-flight jobs on the node (nothing when idle).
- `Lost` ids: cancel the job's token with reason `LeaseLost` and log warning 1206. The final `CompleteAsync` returns false and the outcome is discarded with log 1207 (the job was recovered elsewhere; at-least-once, EXE-5).
- `CancelRequested` ids, or a push `CancelRequested` signal: cancel the job's token with reason `Cancelled`. Cross-node cancel latency is therefore ≤ `LeaseDuration / 3` without push and about 100 ms with PostgreSQL notifications.

### 7.3 Executing one job (`JobProcessor`, JOB-1, JOB-5, JOB-6, EXT-1, OBS-4, RET-6)

1. `ClaimedJob.Unroutable` → log warning 1202 (`Job {JobId} "{JobName}" has no handler on this node; it is Unroutable until a node with a handler starts.`) and stop. The store has already moved it.
2. Create the token: linked from shutdown, the job's own cancel source and the timeout (EXE-7).
3. Create an async DI scope (`await using`, EXE-1, BLT-3), a logger scope `{JobId, JobName, Attempt, Queue}`, and a consumer `Activity` (§8).
4. Deserialize the payload. On failure, dead-letter with reason `DeserializationFailed` (§4.7).
5. Build `JobContext` and set the ambient execution (for SCH-10).
6. `IJobEvents.OnStartedAsync`.
7. Run the middleware pipeline: middlewares registered with `UseMiddleware`, filtered by `appliesTo(jobType)`, in registration order, each resolved from the scope; the innermost step resolves `IJobHandler<TJob>` from the scope and calls `HandleAsync`.
8. Outcome:
   - returned → `Succeeded`.
   - `OperationCanceledException` with cancel reason `Cancelled` → `Cancelled`.
   - cancel reason `Timeout` → failure with `JobTimeoutException` (goes through retry, §7.6).
   - cancel reason `Shutdown` → not completed here; the lease is released by shutdown (§7.5).
   - cancel reason `LeaseLost` → nothing written.
   - any other exception (including middleware) → retry decision (§7.6).
9. `CompleteAsync` with up to 3 tries (200 ms, 1 s, 5 s) on transient store errors. If all fail, log error 1208 with the job id; the lease expires and recovery re-runs the job (at-least-once, documented).
10. Fire the matching `IJobEvents` method. Exceptions from event handlers are logged (1209) with the handler type and never change the job's outcome.

Timeout and abandonment (EXE-7): when the timeout fires, the token is cancelled. If the handler hasn't returned after `CancellationGracePeriod`, the processor stops waiting, completes the job as a `Timeout` failure, frees the slot and logs warning 1205 (`Handler for job {JobId} ignored cancellation and was abandoned after {Grace}; it may still be running.`). The abandoned task's eventual exception is observed and logged at debug level (A-10).

### 7.4 Scheduler tick (EXE-4, EXE-9, EXE-10)

Every `PollInterval` on every `Both`/`WorkerOnly` node:

1. `TickAsync` with the node's routable names and queues, a heartbeat every `NodeHeartbeatInterval`, and `IncludeRecurring = true`.
2. `Promoted > 0` or ready queues → wake the worker loop.
3. Each recovered job → log 1301 (`Job {JobId} lease expired on another node; requeued as attempt {n}` or `…dead-lettered after {n} attempts`) and update metrics.
4. Clock skew: compare `TimeProvider.GetUtcNow()` with `StoreNow`, corrected by half the round-trip. Above `ClockSkewWarningThreshold`, log warning 1302 at most once per 10 minutes.
5. Fire due recurring definitions (§7.7).
6. Errors: as §7.1 step 5, event 1303.

Cleanup runs every `Cleanup.Interval` on the node that wins `TryAcquireLeaseAsync("cleanup", node, 2 × Interval)`. It calls `PurgeAsync` repeatedly, with `PauseBetweenBatches` between calls, until a batch returns fewer than `BatchSize` rows (STO-7). It logs the total deleted at debug level and errors as 1304.

### 7.5 Graceful shutdown (EXE-6)

1. Stop claiming and ticking.
2. Wait up to `ShutdownTimeout` for in-flight jobs.
3. Cancel the remaining tokens with reason `Shutdown`, then wait up to `CancellationGracePeriod`.
4. `ShutdownNodeAsync` with the leases of jobs that still haven't completed, so another node picks them up at once. Log 1210 with their ids.
5. If the store call fails, the leases expire normally and recovery handles them (logged 1211).

### 7.6 Retries and dead letters (RET-1 to RET-4)

- Max attempts precedence: `EnqueueOptions.Retry` → fluent → `[Retry]` → `Retry.MaxAttempts`. It is stored on the job at enqueue (`max_attempts`), so recovery can decide without the handler's code.
- Decision on a failure: `PermanentJobFailureException` → dead-letter. `attempt >= max_attempts` → dead-letter with reason `AttemptsExhausted`. Otherwise the job's `IRetryPolicy` (fluent per job → global `UseRetryPolicy` → built-in) decides.
- The built-in policy uses the delays (job's `RetrySettings.Delays` or the options default) for attempt n (1-based, so the delay after attempt 1 is `Delays[0]`), the last repeating, with ±20% jitter from an injected `Random` (seeded in tests).
- `Failed` with `due_at = now + delay`; the tick promotes it when due.
- Every attempt's error (type, message, stack trace, node) is in `job_history` (RET-4). Dead-lettered jobs are kept for `Retention.DeadLettered` and never deleted earlier (RET-3).
- A policy that throws is treated as dead-letter with reason `RetryPolicyFailed`, and logged 1204.

### 7.7 Recurring jobs (REC-1 to REC-10)

**Definitions.** Code-defined (`[Recurring]`, `AddRecurring`, `JobBuilder.Recurring`) or runtime-defined (`IRecurringJobManager`). The recurring name defaults to the job name. A cron expression or time zone that fails to parse fails startup for code-defined jobs and throws `ArgumentException` at the call for runtime ones (REC-2).

**Reconciliation (REC-3).** At start on worker nodes: `ReconcileRecurringAsync(DefinedBy = IHostEnvironment.ApplicationName, …)`. Log 1401 with the counts and the orphaned names. Orphaned definitions are not fired and show as orphaned; they are restored when code defines them again.

**Next occurrence.** `ISchedule.GetNextOccurrence(after, tz)` returns the first occurrence strictly after `after`.

**Firing**, per due definition from the tick, with `now = StoreNow`:

1. Let `missed` be the occurrences in `[NextRunAt, now]` (`NextRunAt` included), capped at `MisfireMax + 1`, computed by repeated `GetNextOccurrence`. An occurrence is *late* when `now − occurrence > MisfireThreshold` (A-13).
2. Choose the occurrences to run:
   - `RunOnce`: one, scheduled at the latest occurrence ≤ now.
   - `Skip`: the latest occurrence ≤ now if it is not late; otherwise none.
   - `RunAll`: all occurrences in `missed`, at most `MisfireMax`, oldest first.
3. When any late occurrence is not run, log 1402 with the count and policy and raise `OnRecurringMissedAsync` (REC-5).
4. `NewNextRunAt = GetNextOccurrence(now, tz)` (strictly in the future, so no catch-up loop).
5. `FireRecurringAsync` with `ExpectedNextRunAt = NextRunAt`. `Fired = false` means another node won; this is normal and not logged above debug.

**Overlap (REC-6), enforced inside `FireRecurringAsync` in the same transaction.** An occurrence is *active* when it is in `Scheduled`, `Enqueued`, `Processing`, `Failed` or `Awaiting` with this `recurring_name`.

| Policy | No active occurrence | Active occurrence exists |
|---|---|---|
| `Skip` (default) | Insert as `Enqueued`; outcome `Enqueued` | Insert nothing; `last_outcome = Skipped`; log 1403 |
| `Queue` | Insert as `Enqueued` | Insert as `Awaiting`; outcome `Queued`. `CompleteAsync` of an occurrence promotes the oldest `Awaiting` one to `Enqueued` |
| `Allow` | Insert as `Enqueued` | Insert as `Enqueued` |
| `CancelPrevious` | Insert as `Enqueued` | Cancel the active ones (non-Processing → `Cancelled` at once; Processing → cancel requested), insert the new one as `Awaiting`; outcome `CancelledPrevious`. It is promoted when the previous one finishes (A-16) |

`TriggerAsync` (REC-9) calls `FireRecurringAsync` with `Manual = true`. It applies the same overlap policy, leaves `next_run_at` unchanged, and uses the override payload when given. Pause and resume flip `paused`; resume recomputes `next_run_at` from now (REC-10 applies, so no catch-up for the paused period).

**Time zones (REC-4).** Every definition stores an IANA id, default `UTC`. On Windows .NET resolves IANA ids through ICU, and an unknown id is a validation error. The cron evaluator works on local wall time and converts to UTC:

- A local time inside a DST gap (skipped) maps to the first valid instant after the gap, once. A daily `30 3 * * *` in `Europe/Sofia` on the spring-forward day runs at 04:00 local (03:00 to 04:00 is skipped there).
- A local time that occurs twice (fall-back) runs once, at its first (daylight) instance.

**Intervals.** `Every(interval)` is aligned to the Unix epoch in UTC, so every node computes the same instants and `Every(15 min)` fires at :00, :15, :30, :45 (A-12). The time zone is ignored for intervals and shown as UTC.

### 7.8 Push notifications (EXE-8)

When the store implements `IJobStoreNotifications` and the node runs workers, a `NotificationLoop` calls `ListenAsync` and maps `JobsReady(queue)` to a worker wake-up and `CancelRequested(id)` to a token cancel for in-flight jobs. The store reconnects internally with backoff (1 s → 30 s), logs 1502/1503, and raises `Reconnected`, which triggers one claim to cover anything missed while disconnected. Without push, polling at `PollInterval` covers everything; push only reduces latency.

---

## 8. Observability (OBS-1 to OBS-5)

### 8.1 Traces

`ActivitySource` named `Bellhop`, version = package version, created per instance.

| Span | Kind | Name | Attributes |
|---|---|---|---|
| Enqueue / schedule | Producer | `publish {queue}` | `messaging.system=bellhop`, `messaging.operation.type=send`, `messaging.destination.name={queue}`, `messaging.message.id={jobId}`, `bellhop.job.name` |
| Execute | Consumer | `process {queue}` | the above with `messaging.operation.type=process`, plus `bellhop.job.attempt`, `bellhop.job.outcome` |

The producer's `traceparent`/`tracestate` are stored on the job. The consumer span's parent is the stored context, and it also carries a link to it (A-17). Recurring occurrences have no producer and start a new trace. Exceptions are recorded as span events, and the status is set to error on failure.

### 8.2 Metrics

`Meter` named `Bellhop` from `IMeterFactory`. Tags: `bellhop.queue` and `bellhop.job.name` (job names are bounded by the registry, so cardinality is safe).

| Instrument | Type | Unit |
|---|---|---|
| `bellhop.jobs.enqueued` / `.started` / `.succeeded` / `.failed` / `.retried` / `.dead_lettered` / `.interrupted` | Counter | `{job}` |
| `bellhop.job.duration` | Histogram | `s` |
| `bellhop.job.scheduling_lag` (start − due or enqueue time) | Histogram | `s` |
| `bellhop.queue.depth` | ObservableGauge (from the last statistics read, refreshed at most every 15 s and only while observed) | `{job}` |
| `bellhop.workers.active` | ObservableUpDownCounter | `{worker}` |

### 8.3 Health check

`services.AddHealthChecks().AddBellhopHealthCheck(name = "bellhop", tags…)` reads an in-process `BellhopHealthState` singleton (no store call per probe).

| Check | Unhealthy when |
|---|---|
| Store reachable | Store calls have failed continuously for longer than `StoreFailureThreshold` |
| Schema version | `InitializeAsync` did not succeed |
| Worker loop alive | Worker modes: no loop iteration for 3 × `PollInterval` + 30 s |
| Scheduling lag | The p50 lag over the last minute is above `SchedulingLagThreshold` → Degraded |
| Dead-letter growth | Dead-lettered in the last hour is above `DeadLetterGrowthThreshold` → Degraded |

The data dictionary contains each value, for example `lagP50Seconds`.

### 8.4 Event ids (OBS-3)

`BellhopEventIds` (public static class of `const int`, so users can filter) is created by M1-02 with these ranges. Each story adds its ids within the range and documents them in XML docs. Ids are never reused or renumbered.

| Range | Area | Ids fixed by this document |
|---|---|---|
| 1000–1099 | Startup and configuration | 1001 summary, 1002 in-memory default, 1003 options invalid, 1004 registry invalid, 1005 job without explicit name |
| 1100–1199 | Client | 1101 payload over soft limit, 1102 enqueue failed |
| 1200–1299 | Worker and execution | 1201 claim failed, 1202 unroutable, 1203 deserialization failed, 1204 retry policy failed, 1205 handler abandoned, 1206 lease lost, 1207 completion discarded, 1208 completion failed, 1209 event handler failed, 1210 leases released on shutdown, 1211 release failed |
| 1300–1399 | Scheduler and cleanup | 1301 lease recovered, 1302 clock skew, 1303 tick failed, 1304 cleanup failed |
| 1400–1499 | Recurring | 1401 reconciled, 1402 occurrences missed, 1403 occurrence skipped (overlap), 1404 invalid definition, 1405 fire failed |
| 1500–1599 | PostgreSQL store | 1501 migration applied, 1502 notification connection lost, 1503 notification reconnected |
| 1600–1699 | Dashboard | 1601 anonymous in Development, 1602 dashboard SSE error |

---

## 9. Testing support (TST-1 to TST-5)

`Bellhop.Testing`:

```csharp
public sealed class BellhopTestHarness : IAsyncDisposable
{
    public static BellhopTestHarness Create(Action<IServiceCollection>? services = null, Action<BellhopBuilder>? bellhop = null,
        DateTimeOffset? start = null);
    public IServiceProvider Services { get; }
    public FakeTimeProvider Time { get; }
    public IJobClient Client { get; }
    public IRecurringJobManager Recurring { get; }
    public Task<int> RunPendingAsync(int maxJobs = 10_000, CancellationToken ct = default);   // drains Enqueued, including jobs enqueued by jobs
    public Task AdvanceTimeAsync(TimeSpan by, CancellationToken ct = default);                // steps through every due instant, ticking and draining at each
    public IReadOnlyList<HarnessJob<TJob>> Enqueued<TJob>() where TJob : IJob;               // every job of TJob created, in order
    public IReadOnlyList<HarnessJob> Jobs(JobState? state = null);
}
public sealed record HarnessJob<TJob>(JobId Id, TJob Payload, JobState State, string Queue, IReadOnlyList<string> Tags, int Attempt, DateTimeOffset? DueAt);
```

- The harness builds a real service provider with the in-memory store, a `FakeTimeProvider`, `Mode = Both`, and **no hosted loops**. It drives the step functions in §7 directly, so runs are deterministic and single-threaded from the test's point of view. Retry jitter uses a seeded `Random`.
- `Enqueued<T>()` returns plain records, so any assertion library works. `harness.Enqueued<SendWelcomeEmail>().Should().ContainSingle(...)` works with AwesomeAssertions, without the package depending on it (A-18).
- Inline mode (TST-4) is a core option: with `ExecutionMode = Inline`, `EnqueueAsync` creates the job, then claims and executes that job on the caller's thread with retries disabled (max attempts 1), and rethrows the handler's exception. `ScheduleAsync` stores the job as scheduled and doesn't run it. Background loops don't run in Inline mode (A-19).
- `JobContext.CreateForTest(...)` (TST-5) builds a context whose `ReportProgressAsync` and `Parameters.SetAsync` work in memory.

---

## 10. Dashboard (DSH-1 to DSH-10, M1 read-only)

### 10.1 Endpoint and security

- `app.MapBellhopDashboard(string path = "/bellhop")` returns a `RouteGroupBuilder`-backed `IEndpointConventionBuilder`, so `.RequireAuthorization`, `.AllowAnonymous` and `.RequireHost` work (DSH-1). Endpoints carry `ExcludeFromDescription` (DSH-7).
- **Security default (DSH-2).** A dashboard hosted service checks the materialized endpoints at start. In `Development`, an endpoint with no authorization metadata is allowed and logs 1601. In any other environment, startup fails with: `The Bellhop dashboard at "/jobs" has no authorization requirement. Add .RequireAuthorization("YourPolicy") to MapBellhopDashboard, or call .AllowAnonymous() if it is protected some other way.`
- **403, not 401** (H5): an endpoint filter on the dashboard group turns a forbidden challenge for an authenticated user into 403 for the JSON API and the HTML page, even with cookie authentication (no redirect to an access-denied page).
- View level only (DSH-3): `MapBellhopDashboard(...).RequireAuthorization(...)` guards everything. The operate policy arrives with the operate actions in M2.

### 10.2 JSON API (DSH-9, read endpoints)

All under `{path}/api`, JSON with camelCase, ids as strings, times as ISO 8601 UTC. Errors are `application/problem+json` with a plain `title` (`Job 0193… was not found.`).

| Endpoint | Returns |
|---|---|
| `GET api/overview` | `StoreStatistics` + node count + server time |
| `GET api/jobs?state&name&queue&tag&from&to&recurring&limit&cursor` | `Page<JobSummary>` |
| `GET api/jobs/{id}` | `JobDetails` with the payload **masked** (JOB-9) and the trace id parsed from `traceparent` |
| `GET api/recurring?limit&cursor` | `Page<RecurringJobInfo>` + next 5 occurrences each, computed in process |
| `GET api/queues` | Per configured and observed queue: depth (enqueued), processing, scheduled |
| `GET api/nodes` | `NodeRecord[]` with a computed `alive` flag (heartbeat newer than 3 × heartbeat interval) |
| `GET api/stream` | `text/event-stream` (DSH-7); event `overview` every 2 s with the overview payload |

The SSE stream uses one shared broadcaster per process. It reads the store only while at least one client is connected, so the dashboard adds no load when nobody is viewing it (STO-6). The page falls back to polling `api/overview` every 5 s when `EventSource` errors.

### 10.3 Front end (D5)

- `Assets/index.html`, `Assets/app.css`, and `Assets/js/*.js` as native ES modules. No build step, no npm, no framework (A-20). Embedded as resources and served with `ETag` and `Cache-Control: no-cache`.
- Hash routing (`#/jobs?state=Failed`, `#/jobs/{id}`, `#/recurring`, `#/dead-letters`, `#/queues`, `#/nodes`), so deep links work behind any proxy without server rewrites. All asset URLs are relative to the document (`./assets/app.js`), so `UsePathBase`, virtual directories and Front Door work (DSH-4).
- CSP on every dashboard response: `default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'`. No inline scripts or styles (DSH-10).
- Themes: light and dark through CSS custom properties, following `prefers-color-scheme` with a toggle saved in `localStorage`. Layout is responsive down to 360 px; every interactive element is keyboard-reachable with a visible focus ring.
- Budget: a test fails when the sum of embedded asset sizes exceeds 300 KB (D5).
- Times are shown in the browser's time zone with UTC on hover; recurring schedules always show their own time zone next to the expression (REC-4).

### 10.4 Pages (DSH-5, read-only)

| Page | Shows |
|---|---|
| Overview | Live counts per state, succeeded and failed in the last hour, enqueued by queue, nodes alive |
| Jobs | Filters: state, name, queue, tag, time range. Columns: id (short), name, state, queue, attempt n/max, created, finished, progress bar, last error. Keyset paging ("Next page" / "First page") |
| Job detail | Payload (masked, pretty JSON), state timeline, attempts with exception type, message and stack trace (expandable), progress and message, tags, parameters, parent id link, recurring name link, trace id, lease owner and expiry while processing |
| Recurring | Name, job, schedule with time zone, next 5 runs, last run, last outcome with job link, paused or orphaned badge |
| Dead letters | Jobs list fixed to `DeadLettered`, with the last error |
| Queues | Depth, processing and scheduled per queue |
| Nodes | Id, host, mode, queues, workers, in-flight, version, started, last heartbeat, alive or stale |

Empty states use plain sentences: `No jobs match these filters.`, `No recurring jobs are defined.`, `No dead-lettered jobs.`. A store error shows `The job store could not be reached. Retrying…` with the problem detail behind a "Details" disclosure.

---

## 11. Failure handling by boundary

| Boundary | Null / empty | Timeout | Duplicate | Concurrent | Partial failure |
|---|---|---|---|---|---|
| `IJobClient` calls | Null job → `ArgumentNullException`. Empty tag string → `ArgumentException`. | Store command timeout surfaces as the store's exception to the caller | Same `JobId` twice → `DuplicateJobIdException` (only possible on a caller retry of a failed insert) | Safe; no shared mutable state | Insert is one transaction: either the job exists or it doesn't |
| Store from engine loops | Empty claim/tick results are the idle case | Logged, backed off, health degraded after the threshold | Claims cannot double-claim (SKIP LOCKED / lock) | N nodes tick and claim concurrently by design (§4.4) | Complete fails after the handler succeeded → retried 3 times, then recovery re-runs the job (at-least-once, documented) |
| Handler | Handler returns null `Task` → treated as failure `InvalidOperationException` | Timeout → cancel, grace, abandon (§7.3) | At-least-once means duplicates within the lease window (EXE-5); docs recommend idempotent handlers | Concurrency is bounded by slots | Partial work before a crash is the handler's responsibility (documented) |
| Payload JSON | Missing properties take defaults; unknown properties ignored (JOB-4) | — | — | — | Undeserializable → dead-letter `DeserializationFailed` |
| Recurring definitions | No recurring jobs → nothing fires | Fire error on one definition is logged (1405) and the others continue | Two nodes fire → CAS lets exactly one win | Two nodes reconcile at start → upsert is idempotent | Fire is one transaction: CAS, overlap and insert together |
| PostgreSQL notifications | — | Connection drop → reconnect with backoff, then one catch-up claim | Duplicate signals only cause an extra empty claim | — | Lost signals are covered by the tick |
| Dashboard | Unknown job id → 404 problem detail | Store timeout → 503 problem detail; the UI shows the store-error sentence | — | Many viewers share one SSE broadcaster | A failed SSE connection falls back to polling |
| Startup | Missing store → in-memory + warning | Database unreachable at start → host start fails with the store's message; an orchestrator restarts the process (A-5) | Two nodes migrate at once → advisory lock | — | Migration is one transaction |

---

## 12. Build, test and lint

Established by M1-01 and copied into CLAUDE.md's Mechanics section by that story:

| Gate | Command |
|---|---|
| Build | `dotnet build Bellhop.slnx -c Release` (warnings are errors, analyzers on, public API tracked) |
| Test | `dotnet test --solution Bellhop.slnx -c Release` on .NET 10 with Microsoft.Testing.Platform, or `dotnet test Bellhop.slnx -c Release` under VSTest; M1-01 picks one and records it |
| Lint | `dotnet format Bellhop.slnx --verify-no-changes` |

- Tests run on both `net8.0` and `net10.0`.
- PostgreSQL tests use Testcontainers (`postgres:17-alpine`, A-4). When Docker is unavailable they are **skipped with a visible reason** (`Assert.Skip("Docker is not available: …")`), never silently passed. CI always has Docker, so they always run there.
- A GitHub Actions workflow (`.github/workflows/ci.yml`, Ubuntu) runs all three gates plus `dotnet list package --vulnerable --include-transitive` (SEC-4).
- Package versions at planning time (pin the latest stable at build time and record it): Npgsql 10.0.x, xunit.v3 4.0.x, AwesomeAssertions 9.6.x, Testcontainers.PostgreSql 4.16.x, Microsoft.Extensions.TimeProvider.Testing 10.x, Microsoft.CodeAnalysis.PublicApiAnalyzers 5.6.x. For net8.0, `Microsoft.Extensions.*` references use the 8.0.x line, so the core does not force newer runtime packages on .NET 8 hosts (A-7).

---

## 13. Assumptions and mismatches (for review)

### Assumptions

| # | Assumption | Why |
|---|---|---|
| A-1 | `JobId` is a client-generated UUIDv7 wrapped in a struct. | Time-ordered (good for FIFO and B-tree locality), available before insert, the same on every store. |
| A-2 | The client does not retry failed enqueues; the exception goes to the caller. | A blind retry could duplicate jobs; the caller knows whether its operation is idempotent. |
| A-3 | Job results (JOB-8, SCH-7) and `IJob<TResult>` move to M2. | They are SHOULD and not named in M1's scope. Adding them later is additive. |
| A-4 | Tests use PostgreSQL 17; M1 supports PostgreSQL 13 or newer (no syntax newer than 13 is used). | 13 is the oldest version still in common managed offerings; the minimum is stated in the docs. |
| A-5 | If the database is unreachable at start, the host fails to start rather than retrying forever. | Fail fast (P5); orchestrators restart processes. Hangfire-style "start anyway and retry" hides misconfiguration. |
| A-6 | The JOB-2 analyzer is M2; M1 logs warning 1005 at startup for jobs without an explicit name. | Analyzers are listed in M2. A log line gives the same signal without the analyzer project. |
| A-7 | `Microsoft.Extensions.*` package references are per TFM (8.0.x for net8.0, 10.0.x for net10.0). | Avoids forcing .NET 10 extension packages onto .NET 8 hosts. |
| A-8 | Lease 60 s, heartbeat every 20 s. | Duplicate and recovery window of one minute (EXE-5), against one batched write per node every 20 s while busy and none while idle. |
| A-9 | A lease released by graceful shutdown does not count as an attempt; a lease lost by a crash does (EXE-4). | Rolling deploys of long jobs must not dead-letter them; crashes still count, to stop poison jobs looping. |
| A-10 | An abandoned handler (EXE-7) frees its worker slot. | Otherwise a few stuck handlers starve the node. The risk (more concurrent work than `WorkerCount`) is logged per abandonment. |
| A-11 | The cron parser is written in-house. | SEC-4 allows only BCL and `Microsoft.Extensions.*` in the core; Cronos (MIT) would be a third-party dependency. The parser is about 400 lines plus tests, including the DST rules of REC-4. |
| A-12 | Custom `ISchedule` types (REC-11) are not persistable in M1; only `cron` and `interval` kinds exist. Intervals align to the Unix epoch. | Persisting custom kinds needs a registration and parsing contract; it is SHOULD and can be added without breaking `ISchedule`. Epoch alignment makes every node agree without stored anchors. |
| A-13 | An occurrence is "missed" when it is more than `MisfireThreshold` (1 min) late. | REC-5 needs a line between "on time but noticed 800 ms later" and "missed". |
| A-14 | `ClientOnly` nodes neither reconcile recurring jobs nor run loops. | A web node that does not scan all job assemblies would otherwise orphan definitions owned by worker services. |
| A-15 | Orphan marking is scoped by `defined_by = IHostEnvironment.ApplicationName`. | Two services sharing one namespace with different job sets would otherwise orphan each other's recurring jobs. It is still visible as orphaned, never deleted (REC-3). |
| A-16 | `CancelPrevious` inserts the new occurrence as `Awaiting` and starts it after the cancelled one finishes. | Starting it at once would overlap with a handler that is still cancelling, which the policy exists to prevent. |
| A-17 | The consumer span is a child of the stored producer context and also links to it. | One trace per job is what people expect in trace viewers; the link satisfies "linked" in OBS-1 for tools that follow links. |
| A-18 | `Bellhop.Testing` returns plain collections and depends on no assertion library. | The `.Should()` in TST-3 comes from the user's own library (AwesomeAssertions in this repo). |
| A-19 | In Inline mode only `EnqueueAsync` runs inline, with retries disabled; `ScheduleAsync` stores the job and nothing runs it. | TST-4 describes enqueue. Running scheduled work early would hide timing bugs in tests. |
| A-20 | The dashboard is hand-written vanilla ES modules with no build step and no automated browser tests in M1. JSON API and security are tested automatically; pages are verified by hand and recorded in story Notes. | D5 forbids a framework; a build step and Playwright are each a toolchain. Revisit in M2 when operate actions add interaction worth automating. |
| A-21 | The OpenAPI document for the JSON API (DSH-9) moves to M2. | The read API changes with every page in M1; documenting it once write endpoints exist avoids churn. |
| A-22 | Tags are stored at enqueue, shown on the job page and filterable in M1; the Tags page and tag bulk actions stay in M2 (BLT-9). | Tags are on `EnqueueOptions` (SCH-4, MUST) and the index (STO-11) is in M1, so filtering is index-backed and free. |
| A-23 | Two independent Bellhop instances in one process (TST-1) means two hosts or service providers. Named instances in one container are not supported. | Nothing static means two providers never share state, which covers the multi-test and multi-storage cases. |

### Mismatches

| # | Requirement says | M1 does | Why |
|---|---|---|---|
| M-1 | `BellhopSchema.GetScript(provider, fromVersion)` (STO-3) | `BellhopPostgreSqlSchema.GetScript(fromVersion, schema)` in the PostgreSQL package | The core cannot reference providers (SEC-4). Each store package exposes its own. |
| M-2 | `EnqueueAsync` reports `WasDuplicate` (SCH-5) | `EnqueueAsync` returns `JobId` | Uniqueness is M2. M2 decides between an `EnqueueResult` type and a separate method, and records the choice. |
| M-3 | STO-7 default Succeeded retention 24 h | 7 days | Owner decision D6. requirements.md is amended to match. |
| M-4 | DSH-2 "authenticated-but-unauthorized requests return 403" for any auth scheme | 403 from the dashboard's own endpoints, implemented by an endpoint filter | ASP.NET Core's cookie handler redirects by default; the filter makes the dashboard consistent without changing the host's global behaviour. |
| M-5 | REC-6 "record a `Skipped` occurrence" | `last_outcome = Skipped` on the definition, plus log 1403. No skipped job row | A row per skip would add terminal jobs that never ran. The per-occurrence history (BLT-10, last 50) arrives in M2. |

---

## 14. Milestone order

M1 is delivered as the stories in [stories/m1-core/](../stories/m1-core/README.md), in the dependency order drawn there, ending with an acceptance run (M1-27) of the sample app on PostgreSQL with three nodes and deliberate failures.
