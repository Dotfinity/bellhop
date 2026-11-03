# M1-27 M1 acceptance run

## Context

A recorded run of the real thing, not automated tests: the sample app (M1-26) on PostgreSQL in Docker, three nodes, real jobs, with deliberate failures. It answers whether M1 does what requirements.md and arch promise outside the unit and conformance tests, and it is where surprises surface. Findings become new stories with their evidence, and are **not** fixed inside this story. Each finding's regression test belongs to the story that fixes it.

Setup: PostgreSQL 17 in Docker; three sample instances (`node-1`, `node-2`, `node-3`, all `Mode = Both`, `WorkerCount = 8`, ports 5001 to 5003) on one database; one instance runs the dashboard; an OpenTelemetry collector or `dotnet-counters` for metrics; a load script (`samples/Bellhop.Samples.Web/load.ps1` or `.sh`) that calls the sample's demo endpoints.

**As the** project owner
**I want** to see M1 survive realistic use and deliberate failure on PostgreSQL
**so that** I know the preview is trustworthy before anyone else depends on it.

## What to run and record

Record each scenario's inputs, wall time, observations, screenshots of the dashboard where relevant, and the verdict (pass, or fail with a new story id).

1. **Cold start, three nodes at once** against an empty database: one migration (one 1501 log), one copy of each recurring definition, three startup summaries. Record start-up time.
2. **Throughput:** enqueue 10,000 no-op jobs from one node; time to drain on 3 nodes; jobs/s per node (NFR-2 target ≥ 1,000/s/node, SHOULD); enqueue p50 (target < 2 ms); enqueue-to-start p50 with notifications (target < 100 ms). Record database CPU while draining.
3. **Idle cost:** all three nodes idle for 5 minutes. Count queries per node from `pg_stat_statements` (STO-6: about one per `PollInterval` per node) and CPU (NFR-4).
4. **Kill a node mid-job:** start 20 jobs of 2 minutes each, `kill -9` node-2. Within about one lease length (60 s), its jobs are `Enqueued` with reason `Interrupted` and run on other nodes as attempt 2. The dashboard shows the interrupted attempt distinctly (EXE-4). Record the recovery time per job.
5. **Graceful restart:** stop node-3 normally while 10 long jobs run. They are released with reason `Shutdown`, picked up at once elsewhere, and their attempt is not counted (EXE-6, A-9).
6. **Recurring, every 10 s, on 3 nodes for 10 minutes:** exactly one occurrence per instant (60 occurrences, zero duplicates by query on `jobs`). Cron punctuality: start lag per occurrence, p50 and p99 (NFR-2: 1-second cron punctuality ≥ 99%).
7. **Overlap Skip:** a recurring job every 10 s that runs 25 s: occurrences are skipped, never overlap, never fail or retry. `last_outcome = Skipped` is visible.
8. **Retries and dead letters:** a job failing every time. It is retried with backoff (shorten the delays through configuration), dead-letters on attempt 5, shows every attempt's exception on the job page, then `RequeueAsync` through a demo endpoint runs it again with attempt 1.
9. **Cancel across nodes:** cancel a running 2-minute job from another node's API. The handler stops within about 1 s (notifications), and the state is `Cancelled`.
10. **Database outage:** `docker pause` PostgreSQL for 60 s during load. Nodes log store errors with event ids, the health check turns Unhealthy after `StoreFailureThreshold`, nothing crashes, and processing resumes within a few seconds of unpausing. Count duplicates (expected only within the lease window) and lost jobs (expected: none).
11. **Notification connection cut:** `pg_terminate_backend` on the listener. 1502 and 1503 are logged, and jobs keep flowing.
12. **Clock skew:** start a node with a skewed clock if feasible (container with `faketime`), and check warning 1302. Record if not feasible.
13. **Retention:** set `Retention.Succeeded` to 2 minutes and confirm paced purge (batches of 500) after expiry, with no I/O spike visible in database stats.
14. **Dashboard behind a path base:** run node-1 with `UsePathBase("/ops")` behind a proxy (YARP or nginx container) and confirm every page, SSE and deep link work (DSH-4). Production mode with a policy returns 403 for an authenticated user without it.
15. **Traces and metrics:** one job's trace in the collector shows the producer span on the enqueuing node and the consumer span on the executing node in one trace. The counters match the run's counts.

Also record the total time spent and any cost (machine and duration). Note every rough edge in the developer experience, even when it isn't a bug.

## Acceptance criteria

- Given the run, then Notes contain one entry per scenario with inputs, numbers, observations and a verdict.
- Given any failure or surprise, then a new story file exists under `stories/` with its evidence (logs, numbers, screenshots), and is linked from Notes. Nothing is fixed in this story.
- Given the NFR-2 targets (SHOULD), then measured values are recorded against them, whether met or not.

## Tests

The run is the test. Nothing is automated in this story.

## Out of scope

Fixing findings. Chaos automation and soak tests (NFR-9, M2).

**Priority:** Must
**Depends on:** M1-26
**Traces to:** M1 goal (requirements.md §8), EXE-4 to EXE-10, REC-6, REC-7, STO-6, STO-7, NFR-2, NFR-4, DSH-4, OBS-1 to OBS-5; arch §11

## Notes

Status: not started
