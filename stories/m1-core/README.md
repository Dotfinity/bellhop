# Epic M1: Core (preview)

Milestone M1 from requirements.md §8. It builds the core library, the in-memory and PostgreSQL stores, recurring jobs, observability, the testing package and a read-only dashboard, so a developer can follow requirements.md §3 end to end on PostgreSQL and test their jobs without a database.

The plan these stories implement is [docs/bellhop-architecture.md](../../docs/bellhop-architecture.md) (cited as "arch §n"). Requirement ids (SET-1, EXE-4, …) refer to [requirements.md](../../requirements.md). There is no gap analysis, because this is a greenfield repository.

## Goal

The sample app (M1-26) runs the §3 code unchanged against PostgreSQL on three nodes. Fire-and-forget, delayed and recurring jobs run exactly as the requirements describe, including after a node is killed mid-job. Jobs retry, dead-letter and show in traces, metrics, the health check and the read-only dashboard. The acceptance run (M1-27) records this.

## Binding decisions

Owner decisions of 2026-11-03, recorded in arch §0, where amendments go too.

| # | Decision | What it means for these stories |
|---|---|---|
| D1 | Name and root namespace: **Bellhop**. | Package and namespace names as in arch §2. |
| D2 | Tests: **xUnit v3, AwesomeAssertions, Moq, Bogus**; **Testcontainers** for PostgreSQL. | No other test, assertion or mocking library. |
| D3 | **PostgreSQL first**; SQL Server in M2. | M1 stores: in-memory and PostgreSQL. |
| D4 | **`AutoMigrate` on in every environment.** | Default `true`; the script export is documented on the getting-started page. |
| D5 | **Framework-free dashboard**, embedded bundle under 300 KB, no CDN. | Vanilla ES modules, no npm, with a size-budget test (A-20). |
| D6 | **Succeeded retention 7 days by default, configurable.** | `Retention.Succeeded = 7 d`; STO-7 is amended. |
| D7 | **Plan first.** | No story starts until the owner has reviewed this epic. |

Where sources disagree: the decisions above win over arch, and arch (with its listed assumptions and mismatches, arch §13) wins over requirements.md for M1 scope. Anything arch marks deferred (arch §1.3) is omitted entirely, never stubbed.

## Tracks and order

```text
Foundation and core               Storage (in-memory)           Engine                                 PostgreSQL                     Dashboard

M1-01 ─ M1-02 ─┬─ M1-03 registry
               ├─ M1-04 schedules
               └─ M1-05 mem: jobs ─┬─ M1-06 mem: recurring
                                   └─ M1-07 mem: nodes, routing, index

M1-03 + M1-05 ─ M1-08 hosting ─┬─ M1-09 client ─ M1-10 processor ─ M1-11 retries ─ (+M1-07) M1-12 worker loop
                               ├─ (+M1-07) M1-13 scheduler tick ─ (+M1-04, M1-06) M1-14 recurring engine
                               │      M1-12 + M1-14 ─ M1-15 overlap end to end
                               │      M1-11..M1-14 ─ M1-16 observability
                               │      M1-11, M1-12, M1-14 ─ M1-17 Bellhop.Testing
                               ├─ M1-18 pg schema ─ (+M1-05) M1-19 pg jobs ─┬─ (+M1-06) M1-20 pg recurring ─┐
                               │                                           └─ (+M1-07) M1-21 pg nodes ─────┴─ (+M1-12, M1-13) M1-22 pg notify
                               └─ M1-23 dashboard foundation ─┬─ (+M1-07) M1-24 overview, jobs, detail
                                                              └─ (+M1-07, M1-14) M1-25 recurring, dead letters, queues, nodes

M1-15, M1-16, M1-17, M1-20, M1-21, M1-22, M1-24, M1-25 ─ M1-26 sample + getting started ─ M1-27 acceptance run
```

The critical path is M1-01 → 02 → 05 → 08 → 09 → 10 → 11 → 12 → 15 → 26 → 27. Once M1-08 has landed, the PostgreSQL track (M1-18 onward) and the dashboard track (M1-23 onward) run beside the engine track.

Rules for the tracks:

- **Foundation first.** M1-01 and M1-02 land alone. M1-08 creates the shared engine pieces every loop writes to (`BellhopHealthState`, `IStoreClock`, `JobEventsInvoker`), so no later story has to wait for another to create them. M1-02 fixes the public and store contracts (arch §3, §5), the event-id ranges (arch §8.4) and the `PublicAPI` files, so every later story touches its own folder.
- **The store contract is defined by the conformance suite.** M1-05, M1-06 and M1-07 each add a conformance test group in `tests/Bellhop.Storage.Conformance` and make the in-memory store pass it. M1-19, M1-20 and M1-21 make PostgreSQL pass the same groups. Where the tracks meet, a PostgreSQL story is done when the same conformance classes pass on both stores.
- **Dashboard on fixtures first.** The dashboard stories run against the in-memory store seeded with Bogus data (`DashboardFixture`), so pages can be built and reviewed before PostgreSQL exists. They never call PostgreSQL directly.
- **Shared files.** `PublicAPI.Unshipped.txt`, `BellhopEventIds.cs`, `Directory.Packages.props` and `ServiceCollectionExtensions` are appended to by many stories. Each story adds only its own lines. A defect found in a shared file owned by an earlier story is fixed in its own commit that references the owning story.
- **Parallel stories** (same column, no arrow between them) can be built at once by separate agents in separate worktrees. Read the deliver-story skill's parallel-agents reference first.

## Stories

| Id | Story | Track | Depends on | Status |
|---|---|---|---|---|
| M1-01 | [Solution scaffold and gates](001-solution-scaffold.md) | Foundation | – | not started |
| M1-02 | [Public and store contracts](002-contracts.md) | Foundation | M1-01 | not started |
| M1-03 | [Job registry and serialization](003-job-registry-and-serialization.md) | Core | M1-02 | not started |
| M1-04 | [Schedules: cron, intervals and time zones](004-schedules.md) | Core | M1-02 | not started |
| M1-05 | [In-memory store: job lifecycle and conformance suite](005-in-memory-store-jobs.md) | Storage | M1-02 | not started |
| M1-06 | [In-memory store: recurring definitions](006-in-memory-store-recurring.md) | Storage | M1-05 | not started |
| M1-07 | [In-memory store: nodes, leases, purge, routing, index, statistics and namespaces](007-in-memory-store-nodes-index.md) | Storage | M1-05 | not started |
| M1-08 | [Hosting, options and startup summary](008-hosting-and-options.md) | Core | M1-03, M1-05 | not started |
| M1-09 | [Job client](009-job-client.md) | Core | M1-08 | not started |
| M1-10 | [Job execution pipeline](010-execution-pipeline.md) | Engine | M1-09 | not started |
| M1-11 | [Retries and dead letters](011-retries-and-dead-letters.md) | Engine | M1-10 | not started |
| M1-12 | [Worker loop, heartbeat, timeouts and shutdown](012-worker-loop.md) | Engine | M1-07, M1-11 | not started |
| M1-13 | [Scheduler tick, recovery and cleanup](013-scheduler-tick.md) | Engine | M1-07, M1-08 | not started |
| M1-14 | [Recurring jobs: reconciliation, firing and manager](014-recurring-engine.md) | Engine | M1-04, M1-06, M1-13 | not started |
| M1-15 | [Recurring overlap policies end to end](015-recurring-overlap.md) | Engine | M1-12, M1-14 | not started |
| M1-16 | [Traces, metrics and health check](016-observability.md) | Engine | M1-11, M1-12, M1-13, M1-14 | not started |
| M1-17 | [Bellhop.Testing harness and inline mode](017-testing-package.md) | Engine | M1-11, M1-12, M1-14 | not started |
| M1-18 | [PostgreSQL schema and migrations](018-postgresql-schema.md) | PostgreSQL | M1-08 | not started |
| M1-19 | [PostgreSQL store: job lifecycle](019-postgresql-jobs.md) | PostgreSQL | M1-05, M1-18 | not started |
| M1-20 | [PostgreSQL store: recurring definitions](020-postgresql-recurring.md) | PostgreSQL | M1-06, M1-19 | not started |
| M1-21 | [PostgreSQL store: nodes, leases, purge, index and statistics](021-postgresql-nodes-index.md) | PostgreSQL | M1-07, M1-19 | not started |
| M1-22 | [PostgreSQL LISTEN/NOTIFY wake-ups](022-postgresql-notify.md) | PostgreSQL | M1-12, M1-13, M1-20, M1-21 | not started |
| M1-23 | [Dashboard foundation: endpoint, security and shell](023-dashboard-foundation.md) | Dashboard | M1-08 | not started |
| M1-24 | [Dashboard: overview, jobs and job detail](024-dashboard-jobs.md) | Dashboard | M1-07, M1-23 | not started |
| M1-25 | [Dashboard: recurring, dead letters, queues and nodes](025-dashboard-recurring-queues-nodes.md) | Dashboard | M1-07, M1-14, M1-23 | not started |
| M1-26 | [Sample app and getting-started page](026-sample-and-getting-started.md) | Finish | M1-15, M1-16, M1-17, M1-20, M1-21, M1-22, M1-24, M1-25 | not started |
| M1-27 | [M1 acceptance run](027-acceptance-run.md) | Finish | M1-26 | not started |

Update the Status column when a story starts and when it's done. A finished story's file moves to `stories/completed/m1-core/`.

## Plan review

An independent cold review on 2026-11-03 found 2 blockers and 22 major issues in the first draft: stranded `Awaiting` recurring occurrences, a §3 snippet that can't run without an auth block, missing dependency edges, store contract gaps, and lifecycle holes under failure. All are fixed. Arch §15 summarises the changes, and the dependency edges above reflect what each story's criteria use, not only what it imports.

## Story format

```markdown
# M1-NN <title>

## Context
Why this exists, what it depends on, which arch §§ and requirement ids it implements; files to create.

**As a** <role> **I want** <capability> **so that** <outcome>.

## Acceptance criteria
- Given <state>, when <action>, then <observable result>.

## Tests
## Out of scope
**Priority:** Must | Should | Could
**Depends on:** M1-NN
**Traces to:** requirement ids, arch §

## Notes
Status: not started
```

## Definition of done for this epic (every story)

1. The gate passes: build (warnings as errors), tests on net8.0 and net10.0, and `dotnet format --verify-no-changes` (arch §12). PostgreSQL tests ran against Docker, or the story's Notes say why they couldn't.
2. New behaviour is tested. Every bug fixed has a regression test that fails without the fix. Failure paths are handled on purpose, logged with a stable event id (arch §8.4), and visible to the user as a plain sentence.
3. Every public API change appears in `PublicAPI.Unshipped.txt`, and signatures match arch §3 and §5 or are recorded as an amendment there in the same commit.
4. No static mutable state (TST-1). No dependency in the core beyond the BCL and `Microsoft.Extensions.*` (SEC-4).
5. Nothing deferred by arch §1.3 appears, as type, option, control or copy.
6. Dashboard stories only: pages checked by hand in light and dark themes at 360 px and 1280 px wide, keyboard-only navigation works, and the asset budget test passes.
7. No secrets, debug leftovers, commented-out code or TODOs without an owner.
8. Acceptance criteria are met, and Notes record what changed, what was verified, what was assumed, and where a reviewer should look hardest.
