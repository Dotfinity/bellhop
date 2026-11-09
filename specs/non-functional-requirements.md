# Non-functional requirements — Bellhop

Format: refiner-nfr/1

## NFR-1 — Minimal setup

- **Category:** usability
- **Statement:** The system shall give a developer a working single-node setup with only AddBellhop(...), a store, AddWorker() and job registration, without creating a schema by hand, choosing polling intervals, writing an authorization filter, configuring a serializer, registering a hosted service or pinning package versions.
- **Measure:** the §3 Program.cs (register, pick a store, add the worker, map the dashboard) runs jobs end to end with no other Bellhop code or configuration; the dashboard line is optional
- **Verification:** demonstration
- **Applies to:** system, TECH-11, TECH-50, TECH-88
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.1 SET-1; §2 P1 — "Three lines to a working system."; §3 — "Things the developer did not have to do: ..."
- **Notes:** Decided by the owner on 2026-11-06: the client and the worker are opt-in (TECH-128); the §3 snippet in requirements.md now includes AddWorker().

## NFR-2 — Safe documented defaults

- **Category:** usability
- **Statement:** The system shall give every option a documented default that is safe for production on a small deployment without tuning.
- **Measure:** 100% of options listed in the option reference (NFR-26) have a default and a statement of when to change it
- **Verification:** inspection
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.1 SET-4

## NFR-3 — Zero-tuning deployment

- **Category:** reliability
- **Statement:** The system shall run a deployment of 3 nodes processing 100 jobs per minute correctly and quietly on default settings.
- **Measure:** 24 h soak, 3 nodes, 100 jobs/min, all defaults: 0 lost jobs, 0 duplicates outside the at-least-once window, 0 warnings or errors logged
- **Verification:** test
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-3 — "Tunables exist but are documented as 'you probably don't need this'."
- **Notes:** The 24 h duration and the "0 warnings" reading of "quietly" are mine; the source gives only the 3 nodes and 100 jobs/min. Decided by the owner on 2026-11-06: soak and load testing move to a later phase (M3), so this is not verified before 1.0.

## NFR-4 — Worker services and console hosts

- **Category:** compatibility
- **Statement:** The system shall support worker services and console hosts as first-class hosts.
- **Measure:** every feature except the dashboard works in a Generic Host worker and a console app that reference no ASP.NET Core package
- **Verification:** demonstration
- **Applies to:** system, TECH-9
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.1 SET-6 — "Worker services and console hosts are first-class."

## NFR-5 — Enqueue latency

- **Category:** performance
- **Statement:** When a job is enqueued on PostgreSQL, the system shall return within 2 ms at the median.
- **Measure:** enqueue p50 < 2 ms, PostgreSQL store, one node, on the reference machine (2 vCPU, 8 GB RAM)
- **Verification:** test
- **Applies to:** REQ-120, TECH-37, TECH-123
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §5 NFR-2
- **Notes:** Decided by the owner on 2026-11-06: the reference machine for every performance goal is 2 vCPU and 8 GB RAM, the size of a standard GitHub-hosted runner, so anyone can reproduce the numbers.

## NFR-6 — Schedule-to-start lag

- **Category:** performance
- **Statement:** When a job becomes due, the system shall start it within 100 ms at the median where notifications are available and within PollInterval otherwise, on any node.
- **Measure:** schedule-to-start lag p50 < 100 ms with notifications (PostgreSQL LISTEN/NOTIFY, Redis pub/sub), < PollInterval without; one node, PostgreSQL
- **Verification:** test
- **Applies to:** REQ-122, REQ-123, TECH-38, TECH-63
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §5 NFR-2; §4.5 EXE-8 — "other nodes pick up work within ~100 ms"
- **Notes:** EXE-8 (MUST) also requires the enqueuing node to wake its own workers immediately and adaptive polling otherwise; those are behaviour and implementation, measured here.

## NFR-7 — Throughput

- **Category:** performance
- **Statement:** The system shall process at least 1,000 no-op jobs per second per node.
- **Measure:** ≥ 1,000 no-op jobs/s per node, PostgreSQL store, modest hardware
- **Verification:** test
- **Applies to:** system, TECH-123
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §5 NFR-2

## NFR-8 — Cron punctuality

- **Category:** performance
- **Statement:** The system shall start recurring occurrences on time.
- **Measure:** ≥ 99% of occurrences of a 1-second cron schedule start less than 1 s after their due instant, on the reference machine with no other load
- **Verification:** test
- **Applies to:** REQ-216, TECH-123
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §5 NFR-2 — "1-second cron punctuality ≥ 99%"
- **Notes:** Decided by the owner on 2026-11-06: measured from the due instant to handler start.

## NFR-9 — Redis enqueue-to-start latency

- **Category:** performance
- **Statement:** When a job is enqueued on the Redis store, the system shall start it within 20 ms at the median.
- **Measure:** enqueue-to-start p50 < 20 ms against a local server with pub/sub wake-ups
- **Verification:** test
- **Applies to:** TECH-70, TECH-63
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-15

## NFR-10 — Idle store load

- **Category:** performance
- **Statement:** While a node is idle and notifications are available, the system shall issue at most one lightweight store query per PollInterval.
- **Measure:** ≤ 1 query per PollInterval per idle node, measured at the store
- **Verification:** test
- **Applies to:** REQ-103, TECH-38
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-6

## NFR-11 — Dashboard idle load

- **Category:** performance
- **Statement:** While nobody is viewing the dashboard, the system shall add no store load for it.
- **Measure:** 0 dashboard-originated store queries while no dashboard page or SSE stream is open
- **Verification:** test
- **Applies to:** dashboard
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-6

## NFR-12 — Idle CPU

- **Category:** performance
- **Statement:** While a node is idle, the system shall use CPU indistinguishable from an idle host.
- **Measure:** ≤ 1% of one core averaged over 10 minutes with no jobs, default PollInterval, PostgreSQL store, reference machine
- **Verification:** test
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-4
- **Notes:** Decided by the owner on 2026-11-06.

## NFR-13 — Memory footprint

- **Category:** scalability
- **Statement:** The system shall use memory proportional to the number of in-flight jobs, not to job history.
- **Measure:** steady-state memory does not grow with the number of stored jobs (1k vs 1M stored, same in-flight count)
- **Verification:** test
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-4

## NFR-14 — Recurring scale

- **Category:** scalability
- **Statement:** The system shall find due recurring jobs with one indexed range query per poll.
- **Measure:** 100,000 recurring definitions (multi-tenant) cost one range query per poll on NextRunAt
- **Verification:** test
- **Applies to:** REQ-216, TECH-45
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.4 REC-7

## NFR-15 — Cleanup I/O

- **Category:** performance
- **Statement:** The system shall run retention cleanup through an index in small paced batches so that it never spikes I/O.
- **Measure:** every cleanup query uses an index (no table scan in the plan); batches ≤ CleanupBatchSize with a pause between them
- **Verification:** inspection
- **Applies to:** REQ-145, REQ-109, TECH-67
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-7 — "Tables MUST be designed so cleanup hits an index, not a scan."

## NFR-16 — Dashboard query cost

- **Category:** scalability
- **Statement:** The system shall paginate every dashboard list and back every dashboard query by an index, never loading an entire table.
- **Measure:** 0 unpaginated lists; 0 table scans in dashboard query plans with 1M stored jobs
- **Verification:** inspection
- **Applies to:** dashboard, TECH-66
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.10 DSH-8

## NFR-17 — Bulk enqueue round-trips

- **Category:** performance
- **Statement:** When jobs are enqueued in bulk, the system shall use a single store round-trip per batch.
- **Measure:** 1 round-trip per EnqueueManyAsync call
- **Verification:** test
- **Applies to:** INV-102
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.3 SCH-9

## NFR-18 — Rolling-deploy schema compatibility

- **Category:** compatibility
- **Statement:** The system shall let library versions N and N+1 both read and write schema version N, so that nodes on two adjacent versions can run side by side.
- **Measure:** conformance suite passes with mixed N / N+1 nodes on schema N
- **Verification:** test
- **Applies to:** system, REQ-23
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-5; §2 P8

## NFR-19 — Job compatibility across versions

- **Category:** compatibility
- **Statement:** The system shall run jobs enqueued by version N on version N+1.
- **Measure:** jobs of every state written by N are processed correctly by N+1 in the upgrade test
- **Verification:** test
- **Applies to:** jobs
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-8

## NFR-20 — Semantic versioning

- **Category:** maintainability
- **Statement:** The system shall follow strict SemVer, with no breaking change in a minor or patch release, including attribute shapes, option names, table layout, dashboard auth behaviour and the JSON API.
- **Measure:** 0 breaking changes in minor or patch releases, checked by API-compatibility tooling and the schema diff
- **Verification:** inspection
- **Applies to:** system, TECH-92
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-5; §2 P8; Appendix A ADR-3 — "The JSON API (DSH-9) ... becomes a public contract."

## NFR-21 — Deprecation warnings

- **Category:** maintainability
- **Statement:** The system shall flag every deprecated API with an analyzer warning at least one minor release before removing it.
- **Measure:** every removal has an analyzer warning shipped ≥ 1 minor earlier
- **Verification:** inspection
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-5

## NFR-22 — Upgrade guides

- **Category:** maintainability
- **Statement:** The project shall publish an upgrade guide and a breaking-change list for every major version.
- **Measure:** 1 guide and 1 breaking-change list per major release
- **Verification:** inspection
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-5; §2 P8

## NFR-23 — Changelog

- **Category:** maintainability
- **Statement:** The project shall publish a changelog entry for every release.
- **Measure:** 1 changelog entry per release
- **Verification:** inspection
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-5

## NFR-24 — Getting-started page

- **Category:** usability
- **Statement:** The documentation shall open with a getting-started page that matches the §3 five-minute path exactly and can be completed in five minutes.
- **Measure:** page code identical to §3; a new user completes it in ≤ 5 min
- **Verification:** demonstration
- **Applies to:** NFR-1
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §3 — "The five-minute path, which the documentation's first page must match exactly"; §5 NFR-6

## NFR-25 — Concepts page

- **Category:** usability
- **Statement:** The documentation shall include a concepts page covering at-least-once delivery, leases, misfire, overlap and time zones, stating the duplicate window (the lease length) and recommending idempotent handlers and UniqueKey.
- **Measure:** each listed concept has a section; the duplicate window is stated with its default value
- **Verification:** inspection
- **Applies to:** REQ-10, REQ-102
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-6; §4.5 EXE-5

## NFR-26 — Option reference

- **Category:** usability
- **Statement:** The documentation shall list every option with its default.
- **Measure:** 100% of public options listed, generated or checked against the options types
- **Verification:** inspection
- **Applies to:** NFR-2
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-6

## NFR-27 — Samples repository

- **Category:** usability
- **Statement:** The project shall publish samples for a web app, a worker service, multi-tenancy (including middleware that restores tenant context from a tag), transactional enqueue and tests.
- **Measure:** each listed sample exists and builds in CI
- **Verification:** inspection
- **Applies to:** system, TECH-28
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-6; §4.13 EXT-5 (SHOULD)

## NFR-28 — Verified, versioned docs

- **Category:** maintainability
- **Statement:** The project shall version the documentation with the code and compile every documentation snippet in CI.
- **Measure:** docs live in the repo; CI fails when a snippet does not compile
- **Verification:** inspection
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-6

## NFR-29 — Recipe samples

- **Category:** usability
- **Statement:** The documentation shall show, as samples rather than packages, IDistributedLockProvider used from a handler, a [Lock("name")] execution middleware, a MediatR bridge through execution middleware and carbon-aware scheduling through ISchedule.
- **Measure:** each recipe present and compiled (NFR-28)
- **Verification:** inspection
- **Applies to:** TECH-51, TECH-28, TECH-25
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md Appendix A ADR-1; §4.15 "Not carried over, and why" — "ten-line samples in the docs"

## NFR-30 — Hangfire migration guide

- **Category:** usability
- **Statement:** The documentation shall include a guide for migrating from Hangfire's expression-based API.
- **Measure:** guide published by 1.0
- **Verification:** inspection
- **Applies to:** system, TECH-125
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §7 — "a migration guide is provided"

## NFR-31 — Redis durability documentation

- **Category:** reliability
- **Statement:** The Redis store's first documentation page shall state the data-loss windows plainly and name AWS MemoryDB, ElastiCache for Valkey 9 with synchronous durability, and Kvrocks as the options for durability-critical workloads, and shall state that the store refuses to start unless maxmemory-policy is noeviction; that after a flush, and when the first worker starts on a new server, claims and recurring occurrences pause for one LeaseDuration, with how to shorten that in tests by lowering LeaseDuration; that a job enqueued during that pause with the unique key of a job still running is cancelled with reason DuplicateAfterReset; that after a restore or failover to older data, jobs claimed since that copy may run again and their outcomes may be lost until the rollback is detected and reported; that a rollback to a state less than one RecurringReconcileInterval old is not detected; that a flush first seen by a newly started worker is not reported if every worker that saw the previous marker is paused until the marker is next advanced, although the outcomes of their runs are still recorded, and that either of these undetected losses also removes the unacknowledged record of an earlier reset whose script reply was lost; and that a failover to a server whose clock is behind is reported as a reset.
- **Measure:** present on the first page of the Redis store docs
- **Verification:** inspection
- **Applies to:** TECH-70, REQ-503, REQ-504, REQ-505, REQ-507, REQ-509, REQ-526, REQ-527, REQ-528, REQ-534
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-7
- **Notes:** refiner-model 2026-11-06 redis run 2 (F-1 to F-6): the pause is one LeaseDuration (was HeartbeatInterval), also applies to a new server, and rollbacks to older data are at-least-once by decision. Redis run 3 F-3 (option 2): the unreported late-join flush is documented rather than detected (REQ-528). Redis run 8 and run 9 F-1: so is what either undetected loss (the late-join flush, a rollback within one RecurringReconcileInterval) also removes, the record of an earlier reset whose reply was lost (REQ-523, REQ-532).

## NFR-32 — Redis transactional-enqueue documentation

- **Category:** usability
- **Statement:** The Redis store's first documentation page shall say that transactional enqueue is not available and point to the SQL stores or the outbox relay sample.
- **Measure:** present on the first page of the Redis store docs
- **Verification:** inspection
- **Applies to:** TECH-70, REQ-512, REQ-430
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-12

## NFR-33 — Redis capacity documentation

- **Category:** usability
- **Statement:** The Redis store's first documentation page shall explain the capacity trade-off of one hash tag per namespace and the ShardByQueue alternative.
- **Measure:** present on the first page of the Redis store docs
- **Verification:** inspection
- **Applies to:** TECH-64, TECH-65
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-9

## NFR-34 — Server-specific documentation

- **Category:** usability
- **Statement:** The documentation shall describe each supported Redis-compatible server's caveats, licence status and recommended settings.
- **Measure:** one section per server in TECH-71 to TECH-86 covering at least: Valkey (ElastiCache, MemoryDB and Memorystore connection examples, recommended as the default open-source choice); Redis (Redis 8 as a network service imposes no AGPL obligations on the application; 7.4 to 7.8 carry only non-OSI licences); Garnet (--lua, throughput bounded by its Lua performance); Dragonfly (BSL 1.1 licence, --cluster_mode=emulated --lock_on_hashtags, declared keys avoid the global script lock); Kvrocks (the self-hosted durable option); KeyDB (unmaintained, unpatched CVEs, not recommended for new deployments); Redict (server licence does not affect the client application)
- **Verification:** inspection
- **Applies to:** TECH-71, TECH-73, TECH-74, TECH-76, TECH-77, TECH-78, TECH-79
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-1 to RDV-8

## NFR-35 — Compatibility page

- **Category:** compatibility
- **Statement:** The documentation shall include a compatibility page generated from CI results that shows the last green date per server.
- **Measure:** page regenerated by CI; every server in the matrix has a last-green date
- **Verification:** inspection
- **Applies to:** TECH-87
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.2 RDV-10

## NFR-36 — Prometheus setup documentation

- **Category:** observability
- **Statement:** The documentation shall show Prometheus export as a two-line setup.
- **Measure:** the documented setup is ≤ 2 lines of application code
- **Verification:** inspection
- **Applies to:** TECH-99
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-5

## NFR-37 — Licence

- **Category:** compliance
- **Statement:** The project shall license every package under MIT, permanently.
- **Measure:** every package declares MIT; the governance docs commit to MIT for all future versions
- **Verification:** inspection
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-7; §2 P8 — "MIT forever"

## NFR-38 — No licence checks

- **Category:** compliance
- **Statement:** The system shall perform no runtime licence checks.
- **Measure:** 0 licence-check code paths
- **Verification:** inspection
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-7; §2 P8

## NFR-39 — No telemetry

- **Category:** privacy
- **Statement:** The system shall send no telemetry to the project or any third party.
- **Measure:** 0 outbound calls other than those the application configures (store, notifications, HTTP jobs, its own OpenTelemetry exporters)
- **Verification:** inspection
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-7

## NFR-40 — No paid tier

- **Category:** compliance
- **Statement:** The project shall offer every feature, including continuations, chains, batches and throttling, without a paid tier.
- **Measure:** 0 features gated behind payment
- **Verification:** inspection
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-7; §4.8 — "All of these are free."; §4.15 BLT-7 — "ship in 1.0, free"

## NFR-41 — Secrets never shown

- **Category:** security
- **Statement:** The system shall never write connection strings or other secrets to logs, the startup summary or the dashboard.
- **Measure:** 0 secrets found by a scan of logs, the startup summary and dashboard responses in the test suite
- **Verification:** test
- **Applies to:** REQ-19, dashboard
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.14 SEC-5

## NFR-42 — CSP-friendly dashboard

- **Category:** security
- **Statement:** The dashboard shall use no inline scripts so it works under a strict Content-Security-Policy.
- **Measure:** all pages work under script-src 'self' with no 'unsafe-inline'
- **Verification:** test
- **Applies to:** TECH-88
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.10 DSH-10

## NFR-43 — Constant-time password comparison

- **Category:** security
- **Statement:** When basic authentication checks a password, the system shall compare hashes in constant time.
- **Measure:** comparison uses a fixed-time equality primitive
- **Verification:** inspection
- **Applies to:** REQ-303, TECH-94
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-2

## NFR-44 — Dependency hygiene

- **Category:** security
- **Statement:** The project shall keep dependencies current and run a vulnerability scan in CI.
- **Measure:** CI fails on known high or critical vulnerabilities in dependencies
- **Verification:** inspection
- **Applies to:** system, TECH-8
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.14 SEC-4
- **Notes:** The failing severity level is my reading; the source only says "runs a vulnerability scan".

## NFR-45 — Contribution terms

- **Category:** compliance
- **Statement:** The project shall accept contributions under the DCO and shall not use a CLA that permits relicensing.
- **Measure:** DCO sign-off enforced on pull requests; no CLA
- **Verification:** inspection
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-7

## NFR-46 — Roadmap and triage SLA

- **Category:** maintainability
- **Statement:** The README shall state a public roadmap and say that issues are triaged on a best-effort basis.
- **Measure:** README links the roadmap and states best-effort triage
- **Verification:** inspection
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §5 NFR-7
- **Notes:** Decided by the owner on 2026-11-06: no triage SLA is promised. Security reports follow SECURITY.md.

## NFR-47 — Reverse proxies and path bases

- **Category:** compatibility
- **Statement:** The dashboard shall work behind reverse proxies, UsePathBase, IIS virtual directories and Azure Front Door without extra configuration beyond the standard forwarded-headers middleware.
- **Measure:** dashboard e2e tests pass under each of the four set-ups
- **Verification:** test
- **Applies to:** TECH-88, TECH-91
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.10 DSH-4

## NFR-48 — Themes

- **Category:** usability
- **Statement:** The dashboard shall offer dark, light and system themes.
- **Measure:** all three themes available on every page
- **Verification:** demonstration
- **Applies to:** TECH-88
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.10 DSH-10; §4.15 BLT-15

## NFR-49 — Responsive layout

- **Category:** usability
- **Statement:** The dashboard shall have a responsive layout in which every page and action is fully usable from 360 px wide upwards.
- **Measure:** every page and action usable at 360, 768, 1024 and 1440 px widths
- **Verification:** demonstration
- **Applies to:** TECH-88
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.10 DSH-10
- **Notes:** Decided by the owner on 2026-11-06: phones included, not read-only.

## NFR-50 — Keyboard navigation

- **Category:** accessibility
- **Statement:** The dashboard shall meet WCAG 2.2 level AA and be fully usable with the keyboard.
- **Measure:** no axe violations at WCAG 2.2 AA on any page in CI; every page and action reachable and operable by keyboard alone in a manual pass before each release
- **Verification:** test
- **Applies to:** TECH-88
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.10 DSH-10
- **Notes:** Decided by the owner on 2026-11-06: WCAG 2.2 AA applies. shadcn/ui's Radix primitives cover much of it; Magic UI animations must respect prefers-reduced-motion (TECH-93).

## NFR-51 — No swallowed exceptions

- **Category:** observability
- **Statement:** When any internal failure occurs (store, scheduler, serialization or recovery error), the system shall log it through ILogger with a stable EventId and the job id where applicable.
- **Measure:** every catch block in the engine logs with a catalogued EventId; catalogue published in the docs
- **Verification:** inspection
- **Applies to:** system, REQ-30
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.11 OBS-3; §2 P6 — "Every internal failure logs with an event id."

## NFR-52 — Localisation

- **Category:** localisation
- **Statement:** The dashboard shall keep every UI string in a resource bundle, with English built in and other languages added as JSON bundles through options or upstream contributions.
- **Measure:** 0 hard-coded UI strings
- **Verification:** inspection
- **Applies to:** TECH-88
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §4.15 BLT-15; §8 (M3)

## NFR-53 — No static state

- **Category:** maintainability
- **Statement:** The system shall hold no static or ambient state, so that two independent Bellhop instances can run in one process.
- **Measure:** test with two instances on different stores in one process passes; 0 mutable statics
- **Verification:** test
- **Applies to:** system
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.12 TST-1; §2 P7

## NFR-54 — Tracing coverage

- **Category:** observability
- **Statement:** The system shall emit a producer span at enqueue and a consumer span at execution, linked through the trace context stored on the job.
- **Measure:** every execution span links to its enqueue span in the test exporter
- **Verification:** test
- **Applies to:** REQ-154, TECH-97
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.11 OBS-1; §4.15 BLT-4

## NFR-55 — Metrics coverage

- **Category:** observability
- **Statement:** The system shall publish counters for enqueued, started, succeeded, failed, retried, dead-lettered and interrupted jobs, histograms for execution duration and scheduling lag, and observable gauges for queue depth per queue and active workers.
- **Measure:** all listed instruments present on the Bellhop meter
- **Verification:** test
- **Applies to:** TECH-98
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.11 OBS-2

## NFR-56 — Job-scoped log context

- **Category:** observability
- **Statement:** The system shall attach JobId, JobName, Attempt, Queue and CorrelationId to every log line written during a handler.
- **Measure:** 100% of handler log lines carry the five scope properties in the test logger
- **Verification:** test
- **Applies to:** TECH-16, REQ-168
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.11 OBS-4; §4.15 BLT-4

## NFR-57 — Concurrency and soak testing

- **Category:** reliability
- **Statement:** The project shall run concurrency and chaos tests (nodes killed mid-job, clock skew, duplicate starts) in CI.
- **Measure:** suites present and green on main
- **Verification:** inspection
- **Applies to:** system, TECH-105
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §5 NFR-9
- **Notes:** Decided by the owner on 2026-11-06: the nightly soak test that the source lists here is split out to NFR-61 and deferred.

## NFR-58 — Redis conformance and chaos testing

- **Category:** reliability
- **Statement:** The Redis store shall pass the store conformance suite against every Tier 1 and Tier 2 server, including Sentinel and Cluster topologies for Redis and Valkey, plus chaos tests that kill the primary mid-job and force a failover.
- **Measure:** suite green on every server in TECH-87
- **Verification:** test
- **Applies to:** TECH-70, TECH-87, TECH-105
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9.1 RED-14

## NFR-59 — Community store listing

- **Category:** compliance
- **Statement:** The project shall list a community store (MySQL, MongoDB or other) only after it passes the conformance suite.
- **Measure:** every listed store links to a green conformance run
- **Verification:** inspection
- **Applies to:** TECH-105
- **Strength:** must
- **Status:** approved
- **Source:** requirements.md §4.9 STO-8; §8 (M3)

## NFR-60 — Dashboard bundle size

- **Category:** performance
- **Statement:** The dashboard shall keep its embedded front-end bundle small.
- **Measure:** embedded bundle < ~300 KB
- **Verification:** inspection
- **Applies to:** TECH-93
- **Strength:** should
- **Status:** retired
- **Source:** requirements.md §9 Q3 — "whichever keeps the embedded bundle under ~300 KB and needs no runtime CDN"
- **Notes:** Retired. Decided by the owner on 2026-11-06: no bundle-size budget; the front end is React with shadcn/ui and Magic UI (TECH-93).

## NFR-61 — Multi-node soak test

- **Category:** reliability
- **Statement:** The project shall run a multi-node soak test in CI.
- **Measure:** suite present and green on main, nightly
- **Verification:** inspection
- **Applies to:** system, NFR-3
- **Strength:** should
- **Status:** approved
- **Source:** requirements.md §5 NFR-9
- **Notes:** Split out of NFR-57. Decided by the owner on 2026-11-06: soak and load testing move to a later phase (M3).

## NFR-62 — API key entropy

- **Category:** security
- **Statement:** The system shall generate every dashboard API key from a cryptographically secure random source with enough entropy that guessing a key without a lockout is infeasible.
- **Measure:** at least 256 bits of entropy per key, drawn from a cryptographically secure random number generator
- **Verification:** inspection
- **Applies to:** dashboard REQ-304, dashboard REQ-305, dashboard REQ-337, dashboard INV-308
- **Strength:** must
- **Status:** approved
- **Notes:** refiner-model 2026-11-06 dashboard F-2/F-3, owner's decision: API keys are never locked out and failed key attempts are not counted, so brute-force resistance rests on key entropy alone. Measure decided by the owner on 2026-11-10: 256 bits from a CSPRNG, as proposed.
