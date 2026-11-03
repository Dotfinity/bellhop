# M1-24 Dashboard: overview, jobs and job detail

## Context

The three pages people use most: the overview with live counts over Server-Sent Events, the filterable jobs list, and the job detail with payload, timeline and attempts. Hangfire's dashboard has no filtering beyond state pages (H6), and TickerQ's graph endpoint loaded whole tables (T5). Every query here is keyset-paged and index-backed (DSH-8). Implements arch §10.2 (`overview`, `jobs`, `jobs/{id}`, `stream`) and the Overview, Jobs and Job detail rows of arch §10.4.

Files: `src/Bellhop.Dashboard/Api/OverviewEndpoints.cs`, `JobsEndpoints.cs`, `StreamEndpoint.cs` with the shared `OverviewBroadcaster`, and `Assets/js/pages/overview.js`, `jobs.js`, `job.js`, plus shared `table.js` and `format.js` if needed. Masking uses `IPayloadMasker` from M1-03.

**As a** operator
**I want** live counts, a filterable job list and full detail for any job
**so that** I can find out what happened to a job in seconds.

## Acceptance criteria

- Given the overview page open, when jobs change state, then the counts update within 3 s without a reload, through `api/stream` (DSH-7). When `EventSource` fails (simulated by blocking the stream endpoint), the page polls `api/overview` every 5 s, and a quiet "Live updates paused; refreshing every 5 s" note appears.
- Given 10 browser tabs on the overview, when the store calls are counted, then the store's statistics are read once per 2 s interval in total, not per tab. With no tab open, never (STO-6). Tested at the API level with 10 concurrent SSE clients.
- Given the jobs page with filters state = Failed, name, queue, tag and time range, then the URL hash reflects them (`#/jobs?state=Failed&queue=emails`), reloading restores them, and results match `api/jobs` with the same query.
- Given 120 matching jobs, then the first page shows 50, "Next page" shows the next 50, then 20, and "First page" returns to the start. The API never returns more than 500 (DSH-8).
- Given no match, then `No jobs match these filters.` is shown.
- Given a job id link, then the detail page shows: payload as indented JSON with `[Sensitive]` values shown as `***` (JOB-9, SEC-3); a state timeline with time, node and reason per transition (EXE-11); one entry per failed attempt with exception type and message, with the stack trace in an expandable section (RET-4); progress bar and message; tags; parameters (EXT-6); parent id as a link; recurring name as a link to the recurring page; trace id (from `traceparent`); and lease owner and expiry while processing.
- Given an attempt marked `Interrupted` in the timeline, then it is visibly distinct from a failed attempt (an "Interrupted" badge, EXE-4).
- Given an unknown job id in the URL, then `Job <id> was not found.` is shown, not an error page.
- Given the API's `jobs/{id}` response, then sensitive values are masked server-side; the raw payload never reaches the browser.
- Given a store failure during any request, then the page shows the store-error sentence from arch §10.4, with the detail behind a "Details" disclosure.
- Given times on these pages, then they are shown in the browser's time zone, with UTC in the `title` attribute.

## Tests

`OverviewEndpointTests`, `StreamEndpointTests` (shared broadcaster, no reads without clients), `JobsEndpointTests` (filters, paging, limit cap), `JobDetailEndpointTests` (masking, trace id, 404). Pages are checked by hand in the dev host against the seeded fixture (states, long payloads, many attempts, empty states, store down), in both themes at 360 px and 1280 px, with keyboard only, and recorded in Notes (A-20).

## Out of scope

Recurring, dead letters, queues and nodes pages (M1-25). Operate actions, captured logs, parent/child graph, free-text payload search (M2).

**Priority:** Must
**Depends on:** M1-07, M1-23
**Traces to:** DSH-5 (overview, jobs, detail), DSH-7, DSH-8, DSH-9, JOB-9, SEC-3, STO-6, EXE-4, EXE-11, RET-4; arch §10.2, §10.4, A-22

## Notes

Status: not started
