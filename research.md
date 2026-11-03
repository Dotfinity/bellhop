# Bellhop — Research and Findings

| | |
|---|---|
| Status | Companion to [requirements.md](requirements.md) |
| Date | 2026-11-03 |
| Purpose | The evidence behind the requirements: feature inventories, grievances, the Redis landscape, the plugin ecosystem, and sources |

Requirement IDs such as SET-1, RED-5 or BLT-9 refer to requirements.md. Grievance IDs (H1 to H19, T1 to T16) are defined in §1.4 and §1.5 of this file. Claims the researchers could not verify are marked as such.

---

## 1. Hangfire and TickerQ

Research was done on 2026-11-03 across GitHub issues, the Hangfire forum, Hacker News, NuGet, vendor docs and third-party blogs. Sources are in the Appendix.

### 1.1 Feature comparison

| Area | Hangfire 1.8.25 (Aug 2026) | TickerQ 10.5.1 (Oct 2026) |
|---|---|---|
| Job definition | Expression tree `Enqueue(() => svc.Do(1))`, serialized as type + method + JSON args | `[TickerFunction("name")]` methods discovered by a Roslyn source generator; typed refs since 10.3 |
| One-off / delayed | Yes | "Time tickers" |
| Recurring | Cron via Cronos (seconds supported); misfire modes Relaxed / Strict / Ignorable | "Cron tickers", 5- or 6-field; schedule policies and catch-up modes in 10.5 |
| Continuations / chains / batches | Continuations free; batches and atomic creation **paid (Pro)** | `BatchParent` + run condition; typed chains in 10.5 |
| Storage | SQL Server official; Redis **paid**; PostgreSQL, Mongo, MySQL, SQLite community-maintained | EF Core (any provider), Redis, MongoDB, in-memory |
| Transactional enqueue with app data | No | `StageAsync` joins the app's EF transaction (10.5) |
| Dashboard | Bootstrap 3, polling, local-requests-only by default | React 19 + SignalR, auth mandatory in 10.5 |
| Retries | Global `AutomaticRetry` filter (10 attempts, exponential) | Per-entity retries with intervals; attribute-level in 10.5 |
| Overlap control for recurring jobs | `DisableConcurrentExecution` = distributed lock that **fails** the job on timeout | `SkipIfAlreadyRunning`, in-process only (not cross-node) |
| Throttling / rate limits | **Paid (Ace)** | Not available |
| Async execution | Sync-over-async: a dedicated thread blocks on the Task; storage API is synchronous | Async |
| Serialization | Newtonsoft.Json only, `TypeNameHandling.Auto` internally | System.Text.Json, AOT context, optional GZip |
| DI | Scope per job via `JobActivator`; no DI in filters | Handler DI; exception handler service |
| Testing | Static `JobStorage.Current`; extension-method API hard to mock | `ITickerClock` in 10.5; "sync mode" still open |
| OpenTelemetry | Contrib instrumentation, still beta | Separate instrumentation package |
| License | LGPL v3 core; Pro $500/yr, Business $1,500/yr, Enterprise $4,500/yr | Proprietary source-available since 10.5 (Oct 2026), certificate enforced at runtime; 10.4.0 is the last MIT/Apache release |
| Maturity | 12+ years, 438M downloads, ~900 open issues | Created 2023; 1.5M downloads; one maintainer with ~90% of commits |
| Plugin ecosystem | ~90 community packages built on static registries and Razor-emitted HTML; frequent breakage, no isolation | None; integrations (Slack, Teams, webhooks, OpenTelemetry) are first-party features |

### 1.2 What makes Hangfire great

- **Durability that "just works" on SQL Server.** Jobs survive app-pool recycles and restarts without a separate service. For years this alone made it the default choice.
- **The dashboard.** Repeatedly the top reason teams pick it. Seeing jobs, retrying them and triggering recurring jobs by hand is worth more than raw features.
- **One-line enqueue.** `BackgroundJob.Enqueue(() => svc.Do(1))` runs an existing method in the background with no new types. Argument values are captured at enqueue time.
- **A complete free core.** Retries, continuations, multi-server, queues, cancellation, and a dashboard in one package, free for commercial use.
- **Longevity and commercial backing.** Still actively released after twelve years.

### 1.3 What makes TickerQ great

- **Compile-time registration, no reflection.** Jobs are found by a source generator; typed function references remove magic strings.
- **Lives in your existing database and migrations.** For EF Core shops there is no extra infrastructure, and `StageAsync` lets you enqueue in the same transaction as your business data.
- **Free, modern, real-time dashboard.** Push updates, modern look, chain visualisation, no paid tier for batches.
- **Precision and simplicity.** Second-level cron, one-off and recurring in one model, per-attempt retry intervals, a setup that fits in 30 lines.
- **Efficient scheduling path.** An independent harness measured roughly two SQL statements per firing versus 26 for Quartz.NET.
- **It was MIT.** That was a major adoption driver, and its loss in Oct 2026 is now the loudest complaint.

### 1.4 Common grievances: Hangfire

Frequency: **High** = many threads over years, **Medium** = several, **Low** = few but credible.

| # | Grievance | Freq. |
|---|---|---|
| H1 | Renaming a type, method or namespace breaks stored jobs (`Could not load type`, `method with signature not found`); mixed-version rolling deploys fail | High |
| H2 | No built-in "skip if still running" for recurring jobs; `DisableConcurrentExecution` times out, throws and triggers retries; the author's skip gist can stop jobs permanently on multi-server | High |
| H3 | Jobs stuck in Processing after a crash until an invisibility timeout; manual requeue causes duplicate execution | High |
| H4 | SQL Server load: 200 ms queue poll keeps CPU busy, expiration manager spikes Azure DTU, deadlocks, and a folklore block of tuning options everyone copies | High |
| H5 | Dashboard returns 401 for any non-local request by default; JWT-only APIs cannot authenticate a browser; 401 returned where 403 is expected | High |
| H6 | Dashboard is dated (Bootstrap 3), not extensible, has no filtering beyond state pages and no per-job logs (Hangfire.Console is abandoned and bypasses `ILogger`) | Medium |
| H7 | Sync-over-async workers and a synchronous storage API; no `IAsyncDisposable` scope support | Medium |
| H8 | Newtonsoft-only serialization with `TypeNameHandling.Auto`; System.Text.Json requests open since 2021 | Medium |
| H9 | Filters are attributes constructed by reflection: no DI, and adding a global retry filter silently stacks a second one | Medium |
| H10 | Recurring job catch-up surprises: missed occurrences run late, double-trigger with two servers, a community package exists just to skip missed runs | Medium |
| H11 | Static `JobStorage.Current` makes tests flaky and multiple storages impossible; mocking `Enqueue` requires matching internal `Create(Job, State)` calls | Medium |
| H12 | Queue priority was alphabetical rather than array order on SQL Server; recurring and retried jobs ignore queues in some setups | Medium |
| H13 | No priority within a queue; no idempotency or dedupe key; the fingerprint gist cancels the job and returns no id | Medium |
| H14 | Batches, throttling (mutex, semaphore, rate limit) and Redis storage are paid; LGPL core makes some enterprises nervous | Medium |
| H15 | 1.8 upgrade friction: bring your own SqlClient, `Encrypt=true` default, compatibility level switches, opt-in heavy migrations | Medium |
| H16 | Community storage lags: MySQL effectively unmaintained, SQLite threadbare, PostgreSQL regressions | Medium |
| H17 | Cancellation token semantics confuse users; no first-class job result API | Low–Medium |
| H18 | Multi-tenant recurring jobs at scale (50k+ definitions) strain storage; per-tenant databases need manual managers | Low–Medium |
| H19 | OpenTelemetry only via contrib beta; no enqueue-side spans | Medium |

### 1.5 Common grievances: TickerQ

| # | Grievance | Freq. |
|---|---|---|
| T1 | Relicensed from MIT to proprietary in a **minor** bump (10.4 → 10.5) with runtime certificate enforcement that blocks job execution; users migrating to Quartz/NCrontab; MIT forks appeared within days | Very high (since Oct 2026) |
| T2 | Duplicate and concurrent executions across every major: 3–4 duplicates with 5 workers (2.0), a daily job ran 19 times (10.1), double-fire within 150 ms on ECS, one node ignoring another's lock (fixed only in 10.5-rc1); `MaxConcurrency` was not enforced at all until a fix; `SkipIfAlreadyRunning` is in-process only | Very high |
| T3 | Breaking changes between minor versions with no upgrade guide: entity renames, dashboard moved into a middleware branch breaking auth, cron removed from the attribute (compile error), 3 tables became 18 | Very high |
| T4 | Hidden `DbContext` registration breaks design-time factories, Aspire and integration tests; fresh projects fail with "No DbContext named TickerQDbContext"; cascade-path errors on SQL Server | Very high |
| T5 | Dashboard behind reverse proxies / `UsePathBase` / IIS virtual directories: doubled paths, SignalR 405s, random 403/404s; a graph endpoint loads the whole table and OOMs | Very high |
| T6 | Multi-instance startup seeded duplicate cron rows or crashed on unique-key violations (six separate issues before the 10.5 fix) | High |
| T7 | Documentation thin or wrong: samples call non-existent methods, cancellation semantics documented incorrectly, retention undocumented, status meanings inverted | High |
| T8 | Cron correctness: UTC-only then silently Local; restart pushed runs to the next day; 5-field expressions silently never fire on some versions; one provider never fires | High |
| T9 | Bus factor: one maintainer, Q&A unanswered for months, bulk-closing issues as "fixed in a release that needs a license" | High |
| T10 | Swallowed exceptions (`catch { }`) leave occurrences stuck in InProgress with no log line | Medium |
| T11 | EF Core was the only durable store for two years; the proposal for a persistence interface was closed the same day | Medium |
| T12 | Startup side effects: `UseTickerQ` hits the database even in Manual mode; OpenAPI build-time generation started the scheduler; dashboard controllers leak into Swagger; worker services hit NREs because ASP.NET Core was assumed | Medium |
| T13 | Source generator limits: only the last assembly's functions registered (plugins broke), generator emitted invalid code in several releases, new jobs require recompilation | Medium |
| T14 | No retention/cleanup until 10.5; occurrence tables grew unbounded | Medium |
| T15 | Performance claims unverified: the published benchmark never executed a job; independent measurement showed p50 14.7 ms schedule-to-execute and 73–78% punctuality on 1-second cron (competitor-authored) | Medium |
| T16 | Basic-auth-only dashboard for most of its life; packages must be pinned to one exact version; no deterministic test clock until 10.5 | Medium |

### 1.6 Lessons shared by both

1. **Stored job identity must be stable across deploys.** Both libraries bind storage to code shape (expression trees or generated names) and break on rename.
2. **Overlap and duplicate prevention must be enforced by the store, not in-process.** Both get this wrong in multi-node setups.
3. **Default behaviour must need no tuning.** Hangfire's options folklore and TickerQ's version-pinning are symptoms of defaults that do not hold.
4. **The dashboard is the product.** It must integrate with the host's auth, work behind proxies, show logs, and never be a security surprise.
5. **Trust is a feature.** Licensing changes, paywalled basics, and silent breaking changes drive people away faster than missing features.
6. **Observability and testing are table stakes in 2026**, not add-ons.

---

## 2. Redis and Redis-compatible servers

Why this matters: Hangfire's Redis storage is paid (H14 above), the community alternative is LGPL and requeues long-running jobs by mistake, and TickerQ's Redis layer shipped serialization bugs, refuses to start on Cluster or Sentinel, and silently loses recurring jobs after a flush. A correct, free, portable Redis store is an opening, and the Redis licensing split of 2024 means "Redis" now means several different servers.

**The landscape (verified 2026-11-03):**

| Server | License (OSI?) | API level | Maintained | Lua scripts | Streams | Cluster | Persistence | Notes |
|---|---|---|---|---|---|---|---|---|
| Redis 8.10 | RSALv2 / SSPLv1 / AGPLv3 (AGPL: yes) | reference | yes | yes | yes | yes | RDB + AOF | 7.2.4 was the last BSD release; 7.4 to 7.8 are non-OSI only |
| Valkey 9.1 | BSD-3 (yes) | Redis 7.2.4 plus own additions | yes, Linux Foundation | yes | yes | yes | RDB + AOF | Default engine at AWS ElastiCache/MemoryDB and GCP Memorystore; reports `redis_version 7.2.4` in INFO |
| Garnet 2.1 | MIT (yes) | ~7.4 | yes, Microsoft | opt-in (`--lua`), documented as slow | **no** | yes; no Sentinel | checkpoints + AOF, no commit-wait by default | Written in .NET; can run in-process |
| Dragonfly 2.0 | BSL 1.1 (**no**) | ~8.6 claimed | yes | yes, Lua 5.4 | partial | emulated; needs `--lock_on_hashtags` | snapshots only, no AOF | Rejects EVAL inside MULTI |
| Kvrocks 2.17 | Apache-2.0 (yes) | mixed | yes, Apache | yes | since 2.10 | CLUSTERX + controller | RocksDB, always on disk | Durable by design; no BRPOPLPUSH |
| KeyDB 6.3 | BSD-3 (yes) | Redis 6.2 | **no** release since Oct 2023 | yes | yes | yes | RDB + AOF | Open "is it abandoned?" issue |
| Redict 7.3 | LGPL-3.0 (yes) | Redis 7.2.4 | security fixes only | yes | yes | yes | RDB + AOF | |

Hosted: AWS ElastiCache (Redis OSS frozen at 7.1; Valkey 7.2 to 9.1 with optional synchronous durability since June 2026 for Valkey 9+), AWS MemoryDB (every write committed to a multi-AZ log before the ack), GCP Memorystore for Valkey, Azure Managed Redis (Redis Enterprise based, clustered by default; Azure Cache for Redis retires 2027 to 2028), Redis Cloud, Dragonfly Cloud, Upstash (REST mode has no blocking commands).

**What mature Redis job systems teach:**

- Sidekiq OSS loses a job if the process dies after `BRPOP`; Sidekiq Pro's `super_fetch` moves jobs into a per-process working list and recovers orphans at startup.
- BullMQ makes every state change one Lua script, holds a per-job lock key with a TTL the worker renews, detects stalled jobs in two phases, and requires one hash tag per queue on Cluster.
- Asynq uses pending and active lists, scheduled and retry sorted sets, and a lease sorted set scored by deadline; uniqueness is `SET NX` inside the enqueue script.
- Hangfire.Redis.StackExchange never refreshes the fetch timestamp while a job runs, so jobs longer than the invisibility timeout are requeued even when the worker is healthy. Hangfire.Pro.Redis has reported trouble on ElastiCache cluster mode and on Dragonfly.
- TickerQ's Redis package serialized child collections wrongly so jobs never ran, cached cron expressions without expiry so recurring sets went stale, fails closed on Cluster and Sentinel because script atomicity "cannot be proven", and documents that flushing keys stops recurring jobs.
- The client: StackExchange.Redis 3.4.31 (MIT) is the de facto .NET client and works against every server above, with two caveats: version 3.4.20 or later is needed for Valkey version detection, and `EVAL` inside `MULTI` must be avoided on Dragonfly. Valkey GLIDE for C# (1.1, Apache-2.0) is API-compatible but young.

**Lessons that become requirements:** stay on the command subset every server supports (sorted sets, lists, hashes, sets, pub/sub, `EVAL`); make every transition one script with all keys declared under one hash tag; recover by lease deadline, not fetch time; never fail closed on a topology; reconcile recurring definitions so a flush is survivable; tell the operator what persistence mode they are actually running.

---

## 3. Plugin ecosystems: Hangfire, Quartz.NET, TickerQ and others

**Hangfire's extension points (verified in 1.8.25 source).** Dashboard: `DashboardRoutes.Routes` (regex routes, Razor pages, commands, batch commands), `NavigationMenu.Items`, `JobsSidebarMenu.Items`, `DashboardMetrics.AddMetric`, `JobHistoryRenderer.Register`, `UseJobDetailsRenderer` (1.8, the only contribution wrapped in try/catch), `AddStylesheet`/`AddJavaScript` (1.8; earlier, plugins had to find the `/js[0-9]+` route and append to it, and Console and Tags still probe two regexes because the route name changed between versions), `IDashboardAuthorizationFilter`. Server: four filter interfaces plus two exception filters on `GlobalJobFilters`, `IJobFilterProvider`, `JobActivator`, `JobStorage` with `JobStorageFeatures` capability flags, `IBackgroundProcess` passed as `additionalProcesses`, custom `IState` with `GlobalStateHandlers`, per-job key/value parameters, `ILogProvider`.

**Why the ecosystem exists.** Every registry above is process-wide static state reached from one fluent `GlobalConfiguration.Configuration.UseXxx()` chain. A plugin is a single extension method with no ceremony, no DI container, and identical behaviour on OWIN and ASP.NET Core. That is how roughly 90 packages came to exist: hangfire.io/extensions.html lists 46 "common" extensions, 23 storages and 13 IoC adapters, explicitly "not endorsed by Hangfire OÜ".

**What it costs.** No per-instance scoping and order-dependent `UseXxx()` calls. UI is HTML emitted from C# `RazorPage` subclasses against Bootstrap 3 markup, so plugins copy internal CSS classes and break when markup changes (the 1.8 dark mode forced fixes in Console and Tags). No isolation: `Register` and `AddMetric` replace by name, any plugin can take any route or renderer, and a throwing plugin takes the page down except on job-details panels. Breaking changes are signalled only by `[Obsolete]` attributes and renamed route regexes, and the official Extensibility docs contain one page.

**Most-installed Hangfire plugins (NuGet total downloads, 2026-11-03):**

| Plugin | Need | Downloads | Status |
|---|---|---|---|
| Hangfire.Console (+ two forks) | per-job console output and progress bars | 28.6M | last push 2024-02, open "abandoned?" issue |
| OpenTelemetry.Instrumentation.Hangfire | traces and metrics | 13.1M | still beta |
| Hangfire.Autofac (+ 12 other DI adapters) | DI | 12.0M | active |
| Dashboard.BasicAuthorization / Dashboard.Basic.Authentication / Dashboard.Authorization | dashboard auth | 9.2M / 8.5M / 7.4M | one unmaintained since 2019, one GPL-3.0 |
| AspNetCore.HealthChecks.Hangfire | health check | 9.1M | active |
| Hangfire.Console.Extensions (+ Serilog) | `ILogger` to console bridge | 5.1M | active |
| Hangfire.Heartbeat | CPU and RAM per server | 2.4M | 2023 |
| Hangfire.MaximumConcurrentExecutions | per-job concurrency limit | 2.3M | last push 2018 |
| Hangfire.Dashboard.Dark | dark theme | 1.7M | obsoleted by 1.8 |
| Hangfire.JobsLogger | per-job log lines | 1.6M | 2023 |
| Hangfire.Dashboard.Management.v2 | launch jobs with parameters | 1.6M | 2024 |
| FaceIT.Hangfire.Tags (+ 8 per-storage packages) | tags and search | 1.6M plus | needs a package per storage |
| Hangfire.RecurringJobAdmin / RecurringJobExtensions | recurring job UI / config-defined jobs | 1.1M / 1.3M | 2024 / 2018 |
| Hangfire.DynamicJobs (official) | jobs by type and method name strings | 0.98M | active |
| Hangfire.MissionControl | launch with parameter forms | 0.67M | 2023 |
| Hangfire.Correlate | correlation ids | 0.53M | active |
| Hangfire.HttpJob | schedule HTTP calls from the dashboard | 0.42M, 654 stars | active |
| Hangfire.Atoms | job graphs | 81k | active |

Storage providers: PostgreSql 53.5M, MemoryStorage 32.8M, InMemory 17.3M (official), Redis.StackExchange 16.5M, Mongo 15.6M, MySqlStorage 5.5M, SQLite 2.2M, plus about fifteen smaller ones.

**Reading the numbers.** Three basic-auth packages with about 25M combined downloads, a 28.6M-download logging plugin that is abandoned, and a concurrency plugin untouched since 2018 say the same thing: the most-installed plugins fill gaps that should be core. Tags needing one package per storage says indexing must be a store contract. The remaining material (HTTP jobs, exporters, theme packs, outbox relays, custom editors) is small enough to build in too. Bellhop therefore ships no plugin API and builds all of it in (requirements.md §4.15 and ADR-3).

**Other ecosystems.** Quartz.NET exposes job, trigger and scheduler listeners ("must never throw") and `ISchedulerPlugin`; its dashboards (CrystalQuartz 2.7M, Quartzmin, SilkierQuartz) are third-party and each reimplements the UI, glued to the core by a history-recording plugin. TickerQ has no plugin mechanism; it ships integrations (Slack, Teams, webhooks, OpenTelemetry) as first-party features inside the dashboard. Sidekiq registers web extensions with a name, tab, index, asset directory and locales, and each extension adds its own routes and templates. bull-board extends only through queue adapters, server adapters and UI config with design tokens. Oban sells Pro as engine plus plugins plus workers, which Oban Web renders when present. Umbraco 14 declares extensions in a manifest with typed kinds (dashboard, section, workspace view, entity action, condition), the closest model a plugin system would follow. .NET Aspire resource commands (display name, icon, state callback, visibility) are a good shape for dashboard job actions. Bellhop decided against a plugin API (requirements.md ADR-3); these notes remain as the reference point if that decision is revisited.

**Hangfire plugins and the Bellhop requirement that replaces each (details in requirements.md §4.15):**

| Requirement | Bellhop feature | Replaces |
|---|---|---|
| BLT-1 | Per-job logs and progress | Hangfire.Console and forks, Console.Extensions, JobsLogger, Bonura.JobLogs (36M+ combined; Console abandoned) |
| BLT-2 | Dashboard auth presets | Dashboard.BasicAuthorization, Dashboard.Basic.Authentication, Dashboard.Authorization, Soenneker.BasicAuthentication (about 25M; one unmaintained since 2019, one GPL) |
| BLT-3 | DI without adapters | Hangfire.Autofac, Ninject, SimpleInjector, Unity, Windsor, StructureMap, Lamar, DryIoc, LightInject (13 packages, about 20M) |
| BLT-4 | Tracing and correlation | OpenTelemetry.Instrumentation.Hangfire (13.1M, still beta), Hangfire.Correlate, Extensions.ApplicationInsights |
| BLT-5 | Health and metrics | AspNetCore.HealthChecks.Hangfire (9.1M), Hangfire.Prometheus.NetCore, elmah.io heartbeats |
| BLT-6 | Node metrics | Hangfire.Heartbeat (2.4M) |
| BLT-7 | Throttling | Hangfire.MaximumConcurrentExecutions (2.3M, abandoned 2018), Hangfire.Throttling (Ace, paid) |
| BLT-8 | Launch page | Dashboard.Management.v2 and v1, MissionControl, Community.Forms, Community.JobsLauncher (about 2.6M) |
| BLT-9 | Tags | FaceIT.Hangfire.Tags plus 8 per-storage packages (about 4M), a2n.Tags |
| BLT-10 | Recurring job management | Hangfire.RecurringJobAdmin, RecurringJobExtensions, Be.Auto.RecurringJobManager, RecurringDateRange (about 2.8M) |
| BLT-11 | Notifications | Hangfire.HttpJob email alerts, TickerQ.Integrations (Slack, Teams, webhooks), elmah.io heartbeats |
| BLT-12 | HTTP jobs | Hangfire.HttpJob (654 stars) |
| BLT-13 | Insights | Community.Dashboard.Heatmap, Community.JobsInsights, custom `DashboardMetrics` users |
| BLT-14 | Readable failures | Hangfire.StackTrace (87k) |
| BLT-15 | Branding and localisation | Dashboard.Dark (1.7M, obsoleted by 1.8), Dashboard.Customize, Dashboard.Resources, themed forks |
| BLT-16 | `IJobContextAccessor` | Bonura.PerformContextAccessor, Console.Extensions accessor |
| BLT-17 | Outbox mode | Hangfire.Community.Outbox |
| BLT-18 | Already covered elsewhere | Hangfire.MAMQSqlExtension, Soenneker.SkipMissedRuns, Effektor.Idempotent, Extensions.Configuration, Hangfire.DynamicJobs |
| BLT-19 | MCP server | Nall.Hangfire.Mcp |

---

## 4. Traceability: findings to requirements

| Finding | Requirement(s) in requirements.md |
|---|---|
| H1 stored lambdas / type names break on rename | JOB-2, JOB-3, JOB-4 |
| H2, T2 no cross-node skip-if-running, lock timeouts, duplicates | REC-6, REC-7, CON-3, EXE-2 |
| H3 orphaned Processing jobs | EXE-3, EXE-4, EXE-6 |
| H4 SQL polling load, cleanup spikes, tuning folklore | EXE-8, STO-6, STO-7, NFR-3 |
| H5, T16 dashboard 401 confusion, basic-auth only | DSH-1, DSH-2, DSH-3 |
| H6 dated dashboard, no per-job logs | DSH-5, DSH-6, DSH-7, BLT-1, BLT-15 |
| H7 sync-over-async | EXE-1 |
| H8 Newtonsoft and TypeNameHandling | JOB-4, SEC-2 |
| H9 filters without DI | EXT-1 |
| H10, T8 catch-up and time-zone surprises | REC-4, REC-5, REC-10 |
| H11 static state hampers tests | TST-1, TST-2, TST-3 |
| H12, H13 queue order, in-queue priority, dedupe | CON-1, CON-2, SCH-5 |
| H14, T1 paywalls and relicensing | NFR-7, WF-1..3 free, RED (free Redis store) |
| H15, T3 upgrade friction and breaking minors | NFR-5, STO-5, SET-9 |
| H16 community storage lag | STO-8, RDV-10 |
| H17 cancellation and results | SCH-6, SCH-7, JOB-8 |
| H18 multi-tenant recurring scale | REC-7, REC-8, STO-9 |
| H19 observability | OBS-1..5 |
| T4, T11 hidden DbContext, EF-only storage | STO-2, STO-3, STO-4, SCH-8 |
| T5 dashboard behind proxies | DSH-4, DSH-8 |
| T6 duplicate seeded recurring rows | REC-3 |
| T7 thin or wrong docs | NFR-6 |
| T10 swallowed exceptions | OBS-3 |
| T12 startup side effects, Swagger pollution, ASP.NET coupling | SET-5, SET-6, DSH-7 |
| T13 source generator limits | JOB-1 (no generator required), SET-10 |
| T14 no retention | STO-7 |
| T15 unverified performance claims | NFR-2 |
| Redis: requeue of healthy long jobs, fail-closed topologies, flush loses recurring jobs (§2) | RED-5, RED-8, RED-9 |
| Hangfire plugin breakage: static registries, markup coupling, abandoned long tail (§3) | ADR-3: no plugin API; the functionality is built in and versioned with the host (NFR-5) |
| Most-installed Hangfire plugins fill core gaps: auth, logs, tags, concurrency, launch forms, recurring UI (§3) | BLT-1 to BLT-19 |

---

## Appendix — Sources

Hangfire
- Pricing and licensing: https://www.hangfire.io/pricing/ · https://www.hangfire.io/licenses.html
- Hangfire 2.0 "more a dream than a roadmap": https://github.com/HangfireIO/Hangfire/issues/929
- Type-load failures after rename: https://github.com/HangfireIO/Hangfire/issues/1415 · https://github.com/HangfireIO/Hangfire/issues/2469
- Skip-if-running and lock timeouts: https://github.com/HangfireIO/Hangfire/issues/935 · https://github.com/HangfireIO/Hangfire/issues/1799 · https://github.com/HangfireIO/Hangfire/issues/620
- Orphaned Processing jobs: https://github.com/HangfireIO/Hangfire/issues/2413 · https://github.com/HangfireIO/Hangfire/issues/2380
- SQL Server load: https://learn.microsoft.com/en-us/answers/questions/5892521/sql-server-instance-cpu-persistently-high · https://discuss.hangfire.io/t/performance-issue-in-hangfire-db/10472 · https://github.com/HangfireIO/Hangfire/issues/1447
- Dashboard auth: https://discuss.hangfire.io/t/hangfire-path-on-staging-machine-throws-a-401-unauthorized/100 · https://github.com/HangfireIO/Hangfire/issues/2186 · https://github.com/HangfireIO/Hangfire/issues/638
- Per-job logs: https://github.com/HangfireIO/Hangfire/issues/1970
- Sync-over-async: https://github.com/HangfireIO/Hangfire/issues/1658 · https://www.hangfire.io/blog/2016/07/16/hangfire-1.6.0.html
- System.Text.Json requests: https://github.com/HangfireIO/Hangfire/issues/2202 · https://github.com/HangfireIO/Hangfire/issues/2534
- Filters without DI: https://discuss.hangfire.io/t/dependency-injection-for-filter-attribute-non-global/6809
- Static storage and tests: https://github.com/HangfireIO/Hangfire/issues/917 · https://github.com/HangfireIO/Hangfire/issues/2399 · https://github.com/HangfireIO/Hangfire/issues/825
- Queue priority order: https://discuss.hangfire.io/t/multiple-queue-priority-order-is-not-working/784
- Dedupe and in-queue priority: https://github.com/HangfireIO/Hangfire/issues/2109 · https://discuss.hangfire.io/t/how-do-i-prevent-creation-of-duplicate-jobs/1222
- Multi-tenant recurring scale: https://discuss.hangfire.io/t/hangfire-multi-tenant-architecture-per-tenant-recurring-jobs-vs-dynamic-enqueueing-at-scale/11400
- OpenTelemetry contrib gaps: https://github.com/open-telemetry/opentelemetry-dotnet-contrib/issues/1534
- 1.8 upgrade notes: https://www.hangfire.io/blog/2023/04/28/hangfire-1.8.0.html
- Praise threads: https://news.ycombinator.com/item?id=36076667 · https://news.ycombinator.com/item?id=44938718

TickerQ
- Releases and NuGet: https://github.com/Arcenox-co/TickerQ/releases · https://www.nuget.org/packages/TickerQ
- Licensing (Oct 2026): https://tickerq.net/docs/5.x/getting-started/licensing · https://github.com/Arcenox-co/TickerQ/blob/main/LICENSE.md · https://github.com/Arcenox-co/TickerQ/pull/910 · https://github.com/Arcenox-co/TickerQ/blob/main/CLA.md
- Community reaction and migrations away: https://github.com/Arcenox-co/TickerQ/issues/885 · https://github.com/schulydev/SchulyServer/issues/310 · https://github.com/yanpitangui/household-app/pull/22
- Duplicate executions: https://github.com/Arcenox-co/TickerQ/issues/33 · https://github.com/Arcenox-co/TickerQ/issues/611 · https://github.com/Arcenox-co/TickerQ/issues/900 · https://github.com/Arcenox-co/TickerQ/issues/458 · https://github.com/Arcenox-co/TickerQ/discussions/917
- Duplicate seeded rows on multi-instance startup: https://github.com/Arcenox-co/TickerQ/issues/311 · https://github.com/Arcenox-co/TickerQ/issues/898
- Hidden DbContext registration: https://github.com/Arcenox-co/TickerQ/issues/457 · https://github.com/Arcenox-co/TickerQ/issues/867
- Breaking changes without guides: https://github.com/Arcenox-co/TickerQ/issues/261 · https://github.com/Arcenox-co/TickerQ/discussions/454 · https://github.com/Arcenox-co/TickerQ/issues/821
- Dashboard behind proxies: https://github.com/Arcenox-co/TickerQ/issues/332 · https://github.com/Arcenox-co/TickerQ/issues/896
- Cron and time zone issues: https://github.com/Arcenox-co/TickerQ/issues/320 · https://github.com/Arcenox-co/TickerQ/issues/904 · https://github.com/Arcenox-co/TickerQ/issues/83
- Swallowed exceptions: https://github.com/Arcenox-co/TickerQ/issues/893
- Startup side effects and ASP.NET coupling: https://github.com/Arcenox-co/TickerQ/issues/239 · https://github.com/Arcenox-co/TickerQ/discussions/203
- Persistence interface declined: https://github.com/Arcenox-co/TickerQ/issues/28
- Independent benchmark (Quartz.NET maintainers; competitor-authored): https://github.com/quartznet/quartznet/issues/3802
- Praise: https://antondevtips.com/blog/tickerq-the-modern-dotnet-job-scheduler-that-beats-quartz-and-hangfire · https://blog.promptly.mt/tickerq-dotnet-job-scheduler/

Redis and compatible servers
- Redis licensing and versions: https://redis.io/legal/licenses/ · https://redis.io/blog/agplv3/ · https://endoflife.date/redis
- Valkey: https://endoflife.date/valkey · https://valkey.io/blog/valkey-9-1-delivers-improvements-in-security-performance-and-more/ · https://aws.amazon.com/blogs/database/valkey-turns-two/ · StackExchange.Redis version detection fix https://github.com/StackExchange/StackExchange.Redis/issues/3278
- Garnet: https://microsoft.github.io/garnet/docs/commands/api-compatibility · Lua performance discussion https://github.com/microsoft/garnet/discussions/80 · no Functions https://github.com/microsoft/garnet/issues/2317 · no keyspace notifications https://github.com/microsoft/garnet/issues/915
- Dragonfly: https://github.com/dragonflydb/dragonfly/blob/main/LICENSE.md · https://www.dragonflydb.io/docs/command-reference/compatibility · https://www.dragonflydb.io/docs/integrations/bullmq · Hangfire.Pro.Redis on Dragonfly https://discuss.hangfire.io/t/using-hangfire-pro-redis-with-dragonfly/10602
- Kvrocks: https://kvrocks.apache.org/docs/supported-commands/ · https://github.com/apache/kvrocks/releases
- KeyDB abandonment question: https://github.com/Snapchat/KeyDB/issues/923 · Redict releases: https://codeberg.org/redict/redict/releases
- Hosted: ElastiCache durability https://aws.amazon.com/blogs/database/announcing-durability-for-amazon-elasticache/ · MemoryDB https://docs.aws.amazon.com/memorydb/latest/devguide/servicename-feature-overview.html · Azure Cache for Redis retirement https://techcommunity.microsoft.com/blog/azure-managed-redis/azure-cache-for-redis-retirement-what-to-know-and-how-to-prepare/4458721 · Upstash REST limits https://upstash.com/docs/redis/features/restapi
- Clients: https://www.nuget.org/packages/StackExchange.Redis · https://www.nuget.org/packages/Valkey.Glide/
- Queue patterns: Sidekiq reliability https://github.com/sidekiq/sidekiq/wiki/Reliability · BullMQ stalled jobs https://github.com/taskforcesh/bullmq/issues/4220 · Faktory worker lifecycle https://github.com/contribsys/faktory/wiki/Worker-Lifecycle · Celery visibility timeout https://github.com/celery/celery/issues/4976
- Hangfire.Redis.StackExchange requeue bug: https://github.com/marcoCasamento/Hangfire.Redis.StackExchange/issues/168 · Hangfire.Pro.Redis 3.2.0 notes https://www.hangfire.io/blog/2025/03/26/hangfire.pro.redis-3.2.0.html
- TickerQ Redis issues: https://github.com/Arcenox-co/TickerQ/issues/856 · https://github.com/Arcenox-co/TickerQ/issues/913 · https://github.com/Arcenox-co/TickerQ/issues/841 · https://tickerq.net/docs/5.x/guides/reliability
- Distributed locks: https://github.com/madelson/DistributedLock · https://www.nuget.org/packages/DistributedLock

Plugin ecosystems
- Hangfire extension points: https://github.com/HangfireIO/Hangfire/blob/main/src/Hangfire.Core/Dashboard/DashboardRoutes.cs · https://github.com/HangfireIO/Hangfire/blob/main/src/Hangfire.Core/Dashboard/DashboardMetrics.cs · https://github.com/HangfireIO/Hangfire/blob/main/src/Hangfire.Core/Dashboard/JobDetailsRenderer.cs · https://github.com/HangfireIO/Hangfire/blob/main/src/Hangfire.Core/Storage/JobStorageFeatures.cs · https://docs.hangfire.io/en/latest/extensibility/index.html
- Hangfire extensions list: https://www.hangfire.io/extensions.html · https://github.com/HangfireIO/Hangfire.io/blob/main/extensions.md
- Plugins referenced: https://github.com/pieceofsummer/Hangfire.Console · https://github.com/face-it/Hangfire.Tags · https://github.com/HangfireIO/Hangfire.Dashboard.Authorization · https://github.com/yuzd/Hangfire.Dashboard.BasicAuthorization · https://github.com/Xabaril/AspNetCore.Diagnostics.HealthChecks · https://github.com/ahydrax/Hangfire.Heartbeat · https://github.com/alastairtree/Hangfire.MaximumConcurrentExecutions · https://github.com/yuzd/Hangfire.HttpJob · https://github.com/ahydrax/Hangfire.Atoms · https://github.com/HangfireIO/Hangfire.DynamicJobs
- Quartz.NET listeners and plugins: https://www.quartz-scheduler.net/documentation/quartz-3.x/tutorial/trigger-and-job-listeners.html · https://www.quartz-scheduler.net/documentation/quartz-3.x/packages/quartz-plugins.html
- Sidekiq web extensions: https://github.com/sidekiq/sidekiq/blob/main/lib/sidekiq/web/config.rb · bull-board: https://github.com/felixmosh/bull-board · Oban Web and Pro: https://github.com/oban-bg/oban_web/releases · https://oban.dev/docs/pro/0.13.3/overview.html
