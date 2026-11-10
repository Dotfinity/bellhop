# M2 — 1.0

M2 delivers 1.0 as hosting REQ-36 describes it: continuations, chains and batches, concurrency keys and throttling, tags, captured logs and progress, HTTP jobs and notifications, EF Core enqueue, analyzers, the store conformance suite, the SQL Server, SQLite and Redis stores on Tier 1 servers, the full dashboard (API keys, basic auth, roles, launch page and the remaining pages), the 1.0 documentation and the benchmark.

Done means every M2 story is done (ST-064 waits on the TECH-130 open question), every store passes the conformance suite, ST-076 has checked the release, and ST-077 has run 1.0 end to end on every store with deliberate failures and recorded the result.

## Stories

Generated from each story's `Status:` line; run `stories.py index` after changing one.

<!-- refiner-stories:begin stories -->
| # | Story | Depends on | Wave | Status |
|---|---|---|---|---|
| 38 | [ST-038 Continue jobs after their parent, and chain them](038-continuations-and-chains.md) | ST-030, ST-037 | 25 | not started |
| 39 | [ST-039 Group jobs into batches with batch continuations](039-batches.md) | ST-038 | 26 | not started |
| 40 | [ST-040 Enqueue in bulk, store job results and wait for completion](040-bulk-results-and-waiting.md) | ST-030, ST-037 | 25 | not started |
| 41 | [ST-041 Enqueue inside the application's database transaction](041-transactional-enqueue.md) | ST-030, ST-037 | 25 | not started |
| 42 | [ST-042 Throttle claims with concurrency keys, rate limits, LongRunning limits and weighted queues](042-throttling.md) | ST-030, ST-037 | 25 | not started |
| 43 | [ST-043 Run continuations, unique keys and concurrency keys inline](043-inline-continuations-and-keys.md) | ST-038, ST-042, ST-039 | 27 | not started |
| 44 | [ST-044 Tag jobs and carry correlation ids](044-tags-and-correlation.md) | ST-038, ST-033, ST-039, ST-043 | 28 | not started |
| 45 | [ST-045 Capture job logs and progress, and mask sensitive values](045-log-capture-and-progress.md) | ST-044 | 29 | not started |
| 46 | [ST-046 Share one store between applications with namespaces](046-namespaces.md) | ST-030, ST-037 | 25 | not started |
| 47 | [ST-047 Define recurring jobs in configuration and limit them to a validity window](047-recurring-configuration-and-windows.md) | ST-030, ST-037 | 25 | not started |
| 48 | [ST-048 Run HTTP jobs and guard outbound calls](048-http-jobs.md) | ST-030, ST-033, ST-038 | 26 | not started |
| 49 | [ST-049 Load alert rules and hold the notification lease on alerts nodes](049-alerts-lease.md) | ST-030, ST-032, ST-037 | 25 | not started |
| 50 | [ST-050 Send alerts through webhook, Slack, Teams and ILogger channels](050-alert-channels.md) | ST-049, ST-048 | 27 | not started |
| 51 | [ST-051 Alert on dead letters at most once per cooldown, with digests](051-alert-cooldowns.md) | ST-050 | 28 | not started |
| 52 | [ST-052 Alert on failures, failure rates, late recurring jobs, lost nodes, deep queues and waiting throttles](052-alert-events.md) | ST-051, ST-042 | 29 | not started |
| 53 | [ST-053 Ship Roslyn analyzers for job names, handlers, payloads and cron literals](053-analyzers.md) | ST-003, ST-012, ST-037 | 25 | not started |
| 54 | [ST-054 Publish the store conformance suite](054-conformance-suite.md) | ST-039, ST-040, ST-041, ST-043, ST-045, ST-046, ST-047, ST-052 | 30 | not started |
| 55 | [ST-055 Store jobs in SQL Server](055-sqlserver-store.md) | ST-054 | 31 | not started |
| 56 | [ST-056 Store jobs in SQLite for a single node](056-sqlite-store.md) | ST-054 | 31 | not started |
| 57 | [ST-057 Connect the Redis store and lay out its data model and scripts](057-redis-store-model.md) | ST-054 | 31 | not started |
| 58 | [ST-058 Run the job lifecycle on Redis with one script per transition](058-redis-job-scripts.md) | ST-057 | 32 | not started |
| 59 | [ST-059 Detect the Redis server and disclose its durability](059-redis-server-detection.md) | ST-058 | 33 | not started |
| 60 | [ST-060 Detect a Redis flush or reset and pause while reconciling](060-redis-reset-detection.md) | ST-059 | 34 | not started |
| 61 | [ST-061 Keep runs, unique keys and the reset record consistent across a Redis reset](061-redis-reset-recovery.md) | ST-060, ST-034 | 35 | not started |
| 62 | [ST-062 Prove the Redis store on Tier 1 servers and topologies](062-redis-tier-1.md) | ST-061 | 36 | not started |
| 63 | [ST-063 Wake SQL-store nodes through Redis notifications](063-redis-hybrid-notifications.md) | ST-058, ST-055 | 33 | not started |
| 64 | [ST-064 Shard the Redis store by queue on a Cluster](064-redis-shard-by-queue.md) | ST-061, ST-062 | 37 | blocked — open questions 1, 2 and 6 (TECH-130 record slot, TECH-58/TECH-65 tags, per-tag resets) |
| 65 | [ST-065 Grant dashboard permissions by role or claim](065-dashboard-roles.md) | ST-031, ST-037 | 25 | not started |
| 66 | [ST-066 Authenticate scripts with dashboard API keys](066-dashboard-api-keys.md) | ST-034, ST-055, ST-056, ST-062 | 37 | not started |
| 67 | [ST-067 Sign in to the dashboard with basic authentication](067-dashboard-basic-auth.md) | ST-066 | 38 | blocked — open question 1 (REQ-303: which permission a basic-auth user gets) |
| 68 | [ST-068 Launch jobs from the dashboard](068-dashboard-launch.md) | ST-048, ST-066, ST-055, ST-056, ST-062 | 38 | not started |
| 69 | [ST-069 Stream job logs and progress, and show job relationships](069-dashboard-job-logs-and-graph.md) | ST-045, ST-039 | 30 | not started |
| 70 | [ST-070 Show the tags and throttles pages](070-dashboard-tags-and-throttles.md) | ST-044, ST-042, ST-068, ST-055, ST-056, ST-062 | 39 | not started |
| 71 | [ST-071 Sample node metrics and show the nodes page](071-dashboard-nodes.md) | ST-034, ST-055, ST-056, ST-062 | 37 | not started |
| 72 | [ST-072 Build and review recurring schedules in the dashboard](072-dashboard-recurring-builder.md) | ST-047, ST-034, ST-068, ST-055, ST-056, ST-062 | 39 | not started |
| 73 | [ST-073 Publish the 1.0 option reference, guides and samples](073-docs-1-0.md) | ST-035, ST-041, ST-044, ST-055, ST-061, ST-062 | 37 | not started |
| 74 | [ST-074 Benchmark enqueue, scheduling, throughput and cron punctuality](074-benchmarks.md) | ST-055, ST-062 | 37 | not started |
| 75 | [ST-075 Prove every cleanup and dashboard query is indexed and paged](075-query-plans.md) | ST-055, ST-056, ST-062, ST-068, ST-069, ST-070, ST-071, ST-072 | 40 | not started |
| 76 | [ST-076 Prepare the 1.0 release: API compatibility, upgrades, changelog and package audit](076-release-1-0.md) | ST-052, ST-053, ST-064, ST-063, ST-065, ST-067, ST-073, ST-074, ST-075 | 41 | not started |
| 77 | [ST-077 Accept M2: run 1.0 end to end on every store](077-m2-acceptance.md) | ST-076 | 42 | not started |
<!-- refiner-stories:end stories -->
