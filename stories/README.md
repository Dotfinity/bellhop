# Stories — Bellhop

Implementation stories generated from the specs with refiner-stories. The table under *Order* is the implementation order: take the first story that is not started and whose dependencies are done. Stories in the same wave can be built in parallel. Each story quotes the spec items it implements verbatim, and the specs win over anything else written here. `trace.json` records which story owns which item; `stories.py check` keeps the two in step.

The tables below are generated. A story's status lives on the `Status:` line of its Notes: change it there, then run `stories.py index`. Edits made inside the tables are overwritten.

## Standing constraints

Every story honours these. Each is owned by the story that puts its check in place.

<!-- refiner-stories:begin standing -->
- **TECH-1** (owned by ST-001): Every Bellhop package shall target .NET 8 and .NET 10 (both LTS).
- **TECH-2** (owned by ST-001): No Bellhop package shall target .NET Framework.
- **TECH-3** (owned by ST-001): The core package shall be safe for IL trimming.
- **TECH-8** (owned by ST-001): The core package shall depend only on the BCL and Microsoft.Extensions.* abstractions.
- **TECH-9** (owned by ST-001): The core package shall not depend on ASP.NET Core or Entity Framework Core.
- **TECH-12** (owned by ST-004): The core package shall take all time from System.TimeProvider.
- **TECH-48** (owned by ST-029): No store shall require the application to register, expose or migrate an Entity Framework Core DbContext.
- **TECH-50** (owned by ST-001): All first-party NuGet packages shall ship with the same version number and declare exact-version dependencies on each other.
- **TECH-51** (owned by ST-001): No first-party package shall require an external lock service or a distributed-lock library such as DistributedLock; all coordination shall live in the job store.
- **TECH-124** (owned by ST-001): The packages shall use the product name Bellhop, the root C# namespace Bellhop and package ids of the form Bellhop and Bellhop.<Area>, such as Bellhop.PostgreSql and Bellhop.Dashboard.
- **NFR-28** (owned by ST-035): The project shall version the documentation with the code and compile every documentation snippet in CI.
- **NFR-38** (owned by ST-076): The system shall perform no runtime licence checks.
- **NFR-39** (owned by ST-076): The system shall send no telemetry to the project or any third party.
- **NFR-41** (owned by ST-006): The system shall never write connection strings or other secrets to logs, the startup summary or the dashboard.
- **NFR-51** (owned by ST-035): When any internal failure occurs (store, scheduler, serialization or recovery error), the system shall log it through ILogger with a stable EventId and the job id where applicable.
- **NFR-53** (owned by ST-036): The system shall hold no static or ambient state, so that two independent Bellhop instances can run in one process.
<!-- refiner-stories:end standing -->

## Order

<!-- refiner-stories:begin order -->
| # | Story | Epic | Milestone | Depends on | Wave | Status |
|---|---|---|---|---|---|---|
| 1 | [ST-001 Set up the repository, packages and CI gates](m1-core-preview/001-repository-and-ci.md) | m1-core-preview | M1 | – | 1 | not started |
| 2 | [ST-002 Define jobs, handlers and their payload contract](m1-core-preview/002-job-contracts.md) | m1-core-preview | M1 | ST-001 | 2 | not started |
| 3 | [ST-003 Evaluate cron and interval schedules in UTC or a local time zone](m1-core-preview/003-schedules.md) | m1-core-preview | M1 | ST-002 | 3 | not started |
| 4 | [ST-004 Define the job store contract and the in-memory store](m1-core-preview/004-store-contract.md) | m1-core-preview | M1 | ST-002 | 3 | not started |
| 5 | [ST-005 Register Bellhop with AddBellhop, AddClient and AddWorker](m1-core-preview/005-host-registration.md) | m1-core-preview | M1 | ST-004, ST-003 | 4 | not started |
| 6 | [ST-006 Start a node: option validation, schema checks and the startup summary](m1-core-preview/006-node-startup.md) | m1-core-preview | M1 | ST-005 | 5 | not started |
| 7 | [ST-007 Enqueue and schedule jobs](m1-core-preview/007-enqueue-and-schedule.md) | m1-core-preview | M1 | ST-006 | 6 | not started |
| 8 | [ST-008 Claim and run jobs on a worker](m1-core-preview/008-claim-and-run.md) | m1-core-preview | M1 | ST-007 | 7 | not started |
| 9 | [ST-009 Order claims by queue and priority, and pause queues or all processing](m1-core-preview/009-queues-and-pauses.md) | m1-core-preview | M1 | ST-008 | 8 | not started |
| 10 | [ST-010 Hook into execution: middleware, parameters and job events](m1-core-preview/010-execution-pipeline.md) | m1-core-preview | M1 | ST-008 | 8 | not started |
| 11 | [ST-011 Retry failing jobs and dead-letter them](m1-core-preview/011-retries-and-dead-letters.md) | m1-core-preview | M1 | ST-008, ST-010 | 9 | not started |
| 12 | [ST-012 Track worker nodes and mark jobs no worker can handle as unroutable](m1-core-preview/012-worker-nodes-and-unroutable.md) | m1-core-preview | M1 | ST-008 | 8 | not started |
| 13 | [ST-013 Renew leases and recover jobs from lost nodes](m1-core-preview/013-leases-and-recovery.md) | m1-core-preview | M1 | ST-011, ST-012, ST-009 | 10 | not started |
| 14 | [ST-014 Time out handlers that run too long](m1-core-preview/014-timeouts.md) | m1-core-preview | M1 | ST-013 | 11 | not started |
| 15 | [ST-015 Report node health](m1-core-preview/015-health-check.md) | m1-core-preview | M1 | ST-011, ST-012 | 10 | not started |
| 16 | [ST-016 Survive store outages, migration races and clock skew](m1-core-preview/016-startup-resilience.md) | m1-core-preview | M1 | ST-006, ST-015 | 11 | not started |
| 17 | [ST-017 Shut down gracefully and hand unfinished jobs to other nodes](m1-core-preview/017-graceful-shutdown.md) | m1-core-preview | M1 | ST-014, ST-016 | 12 | not started |
| 18 | [ST-018 Cancel jobs, including running ones](m1-core-preview/018-cancellation.md) | m1-core-preview | M1 | ST-017 | 13 | not started |
| 19 | [ST-019 Enforce unique keys](m1-core-preview/019-uniqueness.md) | m1-core-preview | M1 | ST-008, ST-018 | 14 | not started |
| 20 | [ST-020 Requeue and delete jobs](m1-core-preview/020-requeue-and-delete.md) | m1-core-preview | M1 | ST-018, ST-019 | 15 | not started |
| 21 | [ST-021 Clean up finished jobs after their retention](m1-core-preview/021-retention-cleanup.md) | m1-core-preview | M1 | ST-020 | 16 | not started |
| 22 | [ST-022 Declare recurring jobs in code and reconcile them across nodes](m1-core-preview/022-recurring-definitions.md) | m1-core-preview | M1 | ST-003, ST-006, ST-012 | 9 | not started |
| 23 | [ST-023 Manage recurring jobs at runtime](m1-core-preview/023-recurring-management.md) | m1-core-preview | M1 | ST-022 | 10 | not started |
| 24 | [ST-024 Start recurring occurrences under each overlap policy](m1-core-preview/024-recurring-overlap.md) | m1-core-preview | M1 | ST-023, ST-018, ST-019 | 15 | not started |
| 25 | [ST-025 Skip waiting occurrences when a recurring job stops, and record each outcome](m1-core-preview/025-recurring-overlap-outcomes.md) | m1-core-preview | M1 | ST-024, ST-018 | 16 | not started |
| 26 | [ST-026 Trigger recurring jobs on schedule, once across nodes, with misfire handling](m1-core-preview/026-recurring-trigger.md) | m1-core-preview | M1 | ST-025, ST-009, ST-010, ST-021 | 17 | not started |
| 27 | [ST-027 Test jobs with Bellhop.Testing and inline execution](m1-core-preview/027-testing-harness.md) | m1-core-preview | M1 | ST-021, ST-026 | 18 | not started |
| 28 | [ST-028 Emit OpenTelemetry traces and metrics](m1-core-preview/028-tracing-and-metrics.md) | m1-core-preview | M1 | ST-010, ST-014, ST-018, ST-026, ST-021 | 18 | not started |
| 29 | [ST-029 Create and migrate the PostgreSQL schema](m1-core-preview/029-postgres-schema.md) | m1-core-preview | M1 | ST-016 | 12 | not started |
| 30 | [ST-030 Run jobs and recurring jobs on PostgreSQL](m1-core-preview/030-postgres-jobs.md) | m1-core-preview | M1 | ST-029, ST-021, ST-026, ST-027 | 19 | not started |
| 31 | [ST-031 Mount the dashboard and protect it](m1-core-preview/031-dashboard-access.md) | m1-core-preview | M1 | ST-006 | 6 | not started |
| 32 | [ST-032 Build the dashboard shell, overview page and live updates](m1-core-preview/032-dashboard-shell.md) | m1-core-preview | M1 | ST-031, ST-015, ST-030 | 20 | not started |
| 33 | [ST-033 Browse jobs on the jobs list and job detail pages](m1-core-preview/033-dashboard-jobs.md) | m1-core-preview | M1 | ST-032 | 21 | not started |
| 34 | [ST-034 Operate recurring jobs, dead letters and queues from the dashboard](m1-core-preview/034-dashboard-operate.md) | m1-core-preview | M1 | ST-033 | 22 | not started |
| 35 | [ST-035 Write the getting-started, concepts and recipe docs with compiled snippets](m1-core-preview/035-docs-core-preview.md) | m1-core-preview | M1 | ST-028, ST-034 | 23 | not started |
| 36 | [ST-036 Measure idle cost, memory, recurring scale and static state](m1-core-preview/036-core-qualities.md) | m1-core-preview | M1 | ST-030 | 20 | not started |
| 37 | [ST-037 Accept M1: run the core preview end to end on real infrastructure](m1-core-preview/037-m1-acceptance.md) | m1-core-preview | M1 | ST-035, ST-036 | 24 | not started |
| 38 | [ST-038 Continue jobs after their parent, and chain them](m2-1-0/038-continuations-and-chains.md) | m2-1-0 | M2 | ST-030, ST-037 | 25 | not started |
| 39 | [ST-039 Group jobs into batches with batch continuations](m2-1-0/039-batches.md) | m2-1-0 | M2 | ST-038 | 26 | not started |
| 40 | [ST-040 Enqueue in bulk, store job results and wait for completion](m2-1-0/040-bulk-results-and-waiting.md) | m2-1-0 | M2 | ST-030, ST-037 | 25 | not started |
| 41 | [ST-041 Enqueue inside the application's database transaction](m2-1-0/041-transactional-enqueue.md) | m2-1-0 | M2 | ST-030, ST-037 | 25 | not started |
| 42 | [ST-042 Throttle claims with concurrency keys, rate limits, LongRunning limits and weighted queues](m2-1-0/042-throttling.md) | m2-1-0 | M2 | ST-030, ST-037 | 25 | not started |
| 43 | [ST-043 Run continuations, unique keys and concurrency keys inline](m2-1-0/043-inline-continuations-and-keys.md) | m2-1-0 | M2 | ST-038, ST-042, ST-039 | 27 | not started |
| 44 | [ST-044 Tag jobs and carry correlation ids](m2-1-0/044-tags-and-correlation.md) | m2-1-0 | M2 | ST-038, ST-033, ST-039, ST-043 | 28 | not started |
| 45 | [ST-045 Capture job logs and progress, and mask sensitive values](m2-1-0/045-log-capture-and-progress.md) | m2-1-0 | M2 | ST-044 | 29 | not started |
| 46 | [ST-046 Share one store between applications with namespaces](m2-1-0/046-namespaces.md) | m2-1-0 | M2 | ST-030, ST-037 | 25 | not started |
| 47 | [ST-047 Define recurring jobs in configuration and limit them to a validity window](m2-1-0/047-recurring-configuration-and-windows.md) | m2-1-0 | M2 | ST-030, ST-037 | 25 | not started |
| 48 | [ST-048 Run HTTP jobs and guard outbound calls](m2-1-0/048-http-jobs.md) | m2-1-0 | M2 | ST-030, ST-033, ST-038 | 26 | not started |
| 49 | [ST-049 Load alert rules and hold the notification lease on alerts nodes](m2-1-0/049-alerts-lease.md) | m2-1-0 | M2 | ST-030, ST-032, ST-037 | 25 | not started |
| 50 | [ST-050 Send alerts through webhook, Slack, Teams and ILogger channels](m2-1-0/050-alert-channels.md) | m2-1-0 | M2 | ST-049, ST-048 | 27 | not started |
| 51 | [ST-051 Alert on dead letters at most once per cooldown, with digests](m2-1-0/051-alert-cooldowns.md) | m2-1-0 | M2 | ST-050 | 28 | not started |
| 52 | [ST-052 Alert on failures, failure rates, late recurring jobs, lost nodes, deep queues and waiting throttles](m2-1-0/052-alert-events.md) | m2-1-0 | M2 | ST-051, ST-042 | 29 | not started |
| 53 | [ST-053 Ship Roslyn analyzers for job names, handlers, payloads and cron literals](m2-1-0/053-analyzers.md) | m2-1-0 | M2 | ST-003, ST-012, ST-037 | 25 | not started |
| 54 | [ST-054 Publish the store conformance suite](m2-1-0/054-conformance-suite.md) | m2-1-0 | M2 | ST-039, ST-040, ST-041, ST-043, ST-045, ST-046, ST-047, ST-052 | 30 | not started |
| 55 | [ST-055 Store jobs in SQL Server](m2-1-0/055-sqlserver-store.md) | m2-1-0 | M2 | ST-054 | 31 | not started |
| 56 | [ST-056 Store jobs in SQLite for a single node](m2-1-0/056-sqlite-store.md) | m2-1-0 | M2 | ST-054 | 31 | not started |
| 57 | [ST-057 Connect the Redis store and lay out its data model and scripts](m2-1-0/057-redis-store-model.md) | m2-1-0 | M2 | ST-054 | 31 | not started |
| 58 | [ST-058 Run the job lifecycle on Redis with one script per transition](m2-1-0/058-redis-job-scripts.md) | m2-1-0 | M2 | ST-057 | 32 | not started |
| 59 | [ST-059 Detect the Redis server and disclose its durability](m2-1-0/059-redis-server-detection.md) | m2-1-0 | M2 | ST-058 | 33 | not started |
| 60 | [ST-060 Detect a Redis flush or reset and pause while reconciling](m2-1-0/060-redis-reset-detection.md) | m2-1-0 | M2 | ST-059 | 34 | not started |
| 61 | [ST-061 Keep runs, unique keys and the reset record consistent across a Redis reset](m2-1-0/061-redis-reset-recovery.md) | m2-1-0 | M2 | ST-060, ST-034 | 35 | not started |
| 62 | [ST-062 Prove the Redis store on Tier 1 servers and topologies](m2-1-0/062-redis-tier-1.md) | m2-1-0 | M2 | ST-061 | 36 | not started |
| 63 | [ST-063 Wake SQL-store nodes through Redis notifications](m2-1-0/063-redis-hybrid-notifications.md) | m2-1-0 | M2 | ST-058, ST-055 | 33 | not started |
| 64 | [ST-064 Shard the Redis store by queue on a Cluster](m2-1-0/064-redis-shard-by-queue.md) | m2-1-0 | M2 | ST-061, ST-062 | 37 | blocked — open questions 1, 2 and 6 (TECH-130 record slot, TECH-58/TECH-65 tags, per-tag resets) |
| 65 | [ST-065 Grant dashboard permissions by role or claim](m2-1-0/065-dashboard-roles.md) | m2-1-0 | M2 | ST-031, ST-037 | 25 | not started |
| 66 | [ST-066 Authenticate scripts with dashboard API keys](m2-1-0/066-dashboard-api-keys.md) | m2-1-0 | M2 | ST-034, ST-055, ST-056, ST-062 | 37 | not started |
| 67 | [ST-067 Sign in to the dashboard with basic authentication](m2-1-0/067-dashboard-basic-auth.md) | m2-1-0 | M2 | ST-066 | 38 | blocked — open question 1 (REQ-303: which permission a basic-auth user gets) |
| 68 | [ST-068 Launch jobs from the dashboard](m2-1-0/068-dashboard-launch.md) | m2-1-0 | M2 | ST-048, ST-066, ST-055, ST-056, ST-062 | 38 | not started |
| 69 | [ST-069 Stream job logs and progress, and show job relationships](m2-1-0/069-dashboard-job-logs-and-graph.md) | m2-1-0 | M2 | ST-045, ST-039 | 30 | not started |
| 70 | [ST-070 Show the tags and throttles pages](m2-1-0/070-dashboard-tags-and-throttles.md) | m2-1-0 | M2 | ST-044, ST-042, ST-068, ST-055, ST-056, ST-062 | 39 | not started |
| 71 | [ST-071 Sample node metrics and show the nodes page](m2-1-0/071-dashboard-nodes.md) | m2-1-0 | M2 | ST-034, ST-055, ST-056, ST-062 | 37 | not started |
| 72 | [ST-072 Build and review recurring schedules in the dashboard](m2-1-0/072-dashboard-recurring-builder.md) | m2-1-0 | M2 | ST-047, ST-034, ST-068, ST-055, ST-056, ST-062 | 39 | not started |
| 73 | [ST-073 Publish the 1.0 option reference, guides and samples](m2-1-0/073-docs-1-0.md) | m2-1-0 | M2 | ST-035, ST-041, ST-044, ST-055, ST-061, ST-062 | 37 | not started |
| 74 | [ST-074 Benchmark enqueue, scheduling, throughput and cron punctuality](m2-1-0/074-benchmarks.md) | m2-1-0 | M2 | ST-055, ST-062 | 37 | not started |
| 75 | [ST-075 Prove every cleanup and dashboard query is indexed and paged](m2-1-0/075-query-plans.md) | m2-1-0 | M2 | ST-055, ST-056, ST-062, ST-068, ST-069, ST-070, ST-071, ST-072 | 40 | not started |
| 76 | [ST-076 Prepare the 1.0 release: API compatibility, upgrades, changelog and package audit](m2-1-0/076-release-1-0.md) | m2-1-0 | M2 | ST-052, ST-053, ST-064, ST-063, ST-065, ST-067, ST-073, ST-074, ST-075 | 41 | not started |
| 77 | [ST-077 Accept M2: run 1.0 end to end on every store](m2-1-0/077-m2-acceptance.md) | m2-1-0 | M2 | ST-076 | 42 | not started |
| 78 | [ST-078 Relay jobs through an outbox in the application's database](m3-1-x/078-outbox.md) | m3-1-x | M3 | ST-041, ST-073, ST-077 | 43 | not started |
| 79 | [ST-079 Send alerts by email over SMTP](m3-1-x/079-smtp-channel.md) | m3-1-x | M3 | ST-050, ST-077 | 43 | not started |
| 80 | [ST-080 Show readable exception chains, branding and localised UI strings](m3-1-x/080-dashboard-polish.md) | m3-1-x | M3 | ST-069, ST-077 | 43 | not started |
| 81 | [ST-081 Compute insights rollups and show the insights page](m3-1-x/081-dashboard-insights.md) | m3-1-x | M3 | ST-071, ST-077 | 43 | not started |
| 82 | [ST-082 Support Tier 2 and Tier 3 Redis-compatible servers](m3-1-x/082-redis-tier-2-and-3.md) | m3-1-x | M3 | ST-062, ST-077 | 43 | not started |
| 83 | [ST-083 Test the Redis store in process with a Garnet fixture](m3-1-x/083-garnet-fixture.md) | m3-1-x | M3 | ST-082, ST-027 | 44 | not started |
| 84 | [ST-084 Run the Redis CI matrix and publish the compatibility page](m3-1-x/084-redis-ci-matrix.md) | m3-1-x | M3 | ST-082 | 44 | not started |
| 85 | [ST-085 Verify Native AOT with a JsonSerializerContext](m3-1-x/085-native-aot.md) | m3-1-x | M3 | ST-077 | 43 | not started |
| 86 | [ST-086 Ship the Bellhop CLI tool](m3-1-x/086-cli.md) | m3-1-x | M3 | ST-067, ST-055, ST-056, ST-077 | 43 | not started |
| 87 | [ST-087 Expose the dashboard API to MCP clients](m3-1-x/087-mcp-server.md) | m3-1-x | M3 | ST-066, ST-065, ST-077 | 43 | not started |
| 88 | [ST-088 Run the zero-tuning and multi-node soak tests](m3-1-x/088-soak-tests.md) | m3-1-x | M3 | ST-077 | 43 | not started |
| 89 | [ST-089 List community stores only after they pass the conformance suite](m3-1-x/089-community-stores.md) | m3-1-x | M3 | ST-077 | 43 | not started |
| 90 | [ST-090 Accept M3: run 1.x end to end, including Tier 2 servers](m3-1-x/090-m3-acceptance.md) | m3-1-x | M3 | ST-078, ST-079, ST-080, ST-081, ST-083, ST-084, ST-085, ST-086, ST-087, ST-088, ST-089 | 45 | not started |
<!-- refiner-stories:end order -->

## Deferred

<!-- refiner-stories:begin deferred -->
| Id | Strength | Reason |
|---|---|---|
| TECH-72 | may | may; the owner deferred it on 2026-11-10 until the Valkey GLIDE C# client is mature, because a builder cannot judge 'once that client is mature' |
<!-- refiner-stories:end deferred -->
