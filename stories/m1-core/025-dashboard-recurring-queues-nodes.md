# M1-25 Dashboard: recurring, dead letters, queues and nodes

## Context

The remaining read-only pages of DSH-5: recurring jobs with their time zone and next runs (REC-4 requires the zone next to every schedule), dead letters, queues and nodes. Implements arch §10.2 (`recurring`, `queues`, `nodes`) and the matching rows of arch §10.4. Can be built in parallel with M1-24 once M1-23 has landed. The navigation entries already exist.

Files: `src/Bellhop.Dashboard/Api/RecurringEndpoints.cs`, `QueuesEndpoints.cs`, `NodesEndpoints.cs`, and `Assets/js/pages/recurring.js`, `dead-letters.js`, `queues.js`, `nodes.js`.

**As a** operator
**I want** to see every recurring job's schedule, zone and next runs, every dead-lettered job, queue depths and node health
**so that** I can tell whether scheduling and processing are healthy without querying the database.

## Acceptance criteria

- Given recurring definitions in several zones, then the recurring page shows, per definition: name, job name, schedule expression with its IANA zone beside it (for example `0 3 * * *  Europe/Sofia`), the next 5 runs in that zone with UTC on hover, last run, last outcome (Enqueued, Skipped, Queued, CancelledPrevious, Invalid) linking to the last job, and badges for paused, orphaned and code-defined (REC-4, REC-9 read side).
- Given an orphaned definition, then the badge text is `Orphaned: no longer defined in code` (REC-3).
- Given 230 definitions, then the page pages through 100 at a time (DSH-8).
- Given no definitions, then `No recurring jobs are defined.` is shown.
- Given the dead-letters page, then it lists `DeadLettered` jobs newest first, with name, queue, attempts, finished time and last error, each linking to the job page, paged like the jobs list. Empty: `No dead-lettered jobs.`
- Given configured queues `[critical, default]` and jobs in an extra queue `legacy` that no node serves, then the queues page shows all three, with enqueued, processing and scheduled counts, and marks `legacy` as `Not served by any live node`.
- Given 3 nodes, one with a heartbeat older than 3 × `NodeHeartbeatInterval`, then the nodes page shows each node's id, host, mode, queues, workers, in-flight, version, started and last heartbeat, with the stale one marked `Stale`.
- Given each page's API endpoint, then responses are bounded, index-backed and covered by tests, as in M1-24.
- Given any of these pages, then no pause, resume, trigger, requeue or edit control exists (arch §1.3).

## Tests

`RecurringEndpointTests` (next occurrences computed in the given zone, paging), `QueuesEndpointTests` (unserved queue detection), `NodesEndpointTests` (alive versus stale). Pages are checked by hand as in M1-24 and recorded in Notes.

## Out of scope

Recurring editing, trigger and pause from the UI (M2, BLT-10). Queue pause (M2). Node metrics charts (M2, BLT-6).

**Priority:** Must
**Depends on:** M1-06, M1-07, M1-23
**Traces to:** DSH-5 (recurring, dead letters, queues, nodes), DSH-8, REC-3, REC-4; arch §10.2, §10.4

## Notes

Status: not started
