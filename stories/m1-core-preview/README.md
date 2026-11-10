# M1 — Core preview

M1 delivers the core preview that hosting REQ-36 describes: the job model and IJobClient, the in-memory and PostgreSQL stores, fire-and-forget, delayed and recurring jobs, retries and dead letters, leases and recovery, OpenTelemetry, the health check, Bellhop.Testing and the first dashboard pages. By the owner's decisions of 2026-11-10 it also builds unique keys (FEAT-103) and the queue and maintenance pauses, because M1 items depend on them.

Done means every M1 story is done, every M1 behaviour passes on both the in-memory store and PostgreSQL, and ST-037 has run the preview end to end on real infrastructure with deliberate failures and recorded the result.

## Stories

Generated from each story's `Status:` line; run `stories.py index` after changing one.

<!-- refiner-stories:begin stories -->
| # | Story | Depends on | Wave | Status |
|---|---|---|---|---|
| 1 | [ST-001 Set up the repository, packages and CI gates](001-repository-and-ci.md) | – | 1 | not started |
| 2 | [ST-002 Define jobs, handlers and their payload contract](002-job-contracts.md) | ST-001 | 2 | not started |
| 3 | [ST-003 Evaluate cron and interval schedules in UTC or a local time zone](003-schedules.md) | ST-002 | 3 | not started |
| 4 | [ST-004 Define the job store contract and the in-memory store](004-store-contract.md) | ST-002 | 3 | not started |
| 5 | [ST-005 Register Bellhop with AddBellhop, AddClient and AddWorker](005-host-registration.md) | ST-004, ST-003 | 4 | not started |
| 6 | [ST-006 Start a node: option validation, schema checks and the startup summary](006-node-startup.md) | ST-005 | 5 | not started |
| 7 | [ST-007 Enqueue and schedule jobs](007-enqueue-and-schedule.md) | ST-006 | 6 | not started |
| 8 | [ST-008 Claim and run jobs on a worker](008-claim-and-run.md) | ST-007 | 7 | not started |
| 9 | [ST-009 Order claims by queue and priority, and pause queues or all processing](009-queues-and-pauses.md) | ST-008 | 8 | not started |
| 10 | [ST-010 Hook into execution: middleware, parameters and job events](010-execution-pipeline.md) | ST-008 | 8 | not started |
| 11 | [ST-011 Retry failing jobs and dead-letter them](011-retries-and-dead-letters.md) | ST-008, ST-010 | 9 | not started |
| 12 | [ST-012 Track worker nodes and mark jobs no worker can handle as unroutable](012-worker-nodes-and-unroutable.md) | ST-008 | 8 | not started |
| 13 | [ST-013 Renew leases and recover jobs from lost nodes](013-leases-and-recovery.md) | ST-011, ST-012, ST-009 | 10 | not started |
| 14 | [ST-014 Time out handlers that run too long](014-timeouts.md) | ST-013 | 11 | not started |
| 15 | [ST-015 Report node health](015-health-check.md) | ST-011, ST-012 | 10 | not started |
| 16 | [ST-016 Survive store outages, migration races and clock skew](016-startup-resilience.md) | ST-006, ST-015 | 11 | not started |
| 17 | [ST-017 Shut down gracefully and hand unfinished jobs to other nodes](017-graceful-shutdown.md) | ST-014, ST-016 | 12 | not started |
| 18 | [ST-018 Cancel jobs, including running ones](018-cancellation.md) | ST-017 | 13 | not started |
| 19 | [ST-019 Enforce unique keys](019-uniqueness.md) | ST-008, ST-018 | 14 | not started |
| 20 | [ST-020 Requeue and delete jobs](020-requeue-and-delete.md) | ST-018, ST-019 | 15 | not started |
| 21 | [ST-021 Clean up finished jobs after their retention](021-retention-cleanup.md) | ST-020 | 16 | not started |
| 22 | [ST-022 Declare recurring jobs in code and reconcile them across nodes](022-recurring-definitions.md) | ST-003, ST-006, ST-012 | 9 | not started |
| 23 | [ST-023 Manage recurring jobs at runtime](023-recurring-management.md) | ST-022 | 10 | not started |
| 24 | [ST-024 Start recurring occurrences under each overlap policy](024-recurring-overlap.md) | ST-023, ST-018, ST-019 | 15 | not started |
| 25 | [ST-025 Skip waiting occurrences when a recurring job stops, and record each outcome](025-recurring-overlap-outcomes.md) | ST-024, ST-018 | 16 | not started |
| 26 | [ST-026 Trigger recurring jobs on schedule, once across nodes, with misfire handling](026-recurring-trigger.md) | ST-025, ST-009, ST-010, ST-021 | 17 | not started |
| 27 | [ST-027 Test jobs with Bellhop.Testing and inline execution](027-testing-harness.md) | ST-021, ST-026 | 18 | not started |
| 28 | [ST-028 Emit OpenTelemetry traces and metrics](028-tracing-and-metrics.md) | ST-010, ST-014, ST-018, ST-026, ST-021 | 18 | not started |
| 29 | [ST-029 Create and migrate the PostgreSQL schema](029-postgres-schema.md) | ST-016 | 12 | not started |
| 30 | [ST-030 Run jobs and recurring jobs on PostgreSQL](030-postgres-jobs.md) | ST-029, ST-021, ST-026, ST-027 | 19 | not started |
| 31 | [ST-031 Mount the dashboard and protect it](031-dashboard-access.md) | ST-006 | 6 | not started |
| 32 | [ST-032 Build the dashboard shell, overview page and live updates](032-dashboard-shell.md) | ST-031, ST-015, ST-030 | 20 | not started |
| 33 | [ST-033 Browse jobs on the jobs list and job detail pages](033-dashboard-jobs.md) | ST-032 | 21 | not started |
| 34 | [ST-034 Operate recurring jobs, dead letters and queues from the dashboard](034-dashboard-operate.md) | ST-033 | 22 | not started |
| 35 | [ST-035 Write the getting-started, concepts and recipe docs with compiled snippets](035-docs-core-preview.md) | ST-028, ST-034 | 23 | not started |
| 36 | [ST-036 Measure idle cost, memory, recurring scale and static state](036-core-qualities.md) | ST-030 | 20 | not started |
| 37 | [ST-037 Accept M1: run the core preview end to end on real infrastructure](037-m1-acceptance.md) | ST-035, ST-036 | 24 | not started |
<!-- refiner-stories:end stories -->
