# M1-26 Sample app and getting-started page

## Context

requirements.md §3 is a promise: the documentation's first page must match it exactly, and it must work in five minutes (P1, NFR-6). This story builds `samples/Bellhop.Samples.Web` from the §3 snippets *verbatim*, writes `docs/getting-started.md` from that sample, and adds a check that keeps the two in sync. The sample is also the system under test for the acceptance run (M1-27). Fixes TickerQ's T7 (samples calling methods that don't exist).

Files: `samples/Bellhop.Samples.Web/` (Program.cs, `Jobs/SendWelcomeEmail.cs`, `Jobs/SendFollowUpEmail.cs`, `Jobs/NightlyCleanup.cs`, `RegisterUser.cs`, a fake `IEmailSender`, a minimal endpoint to register a user, plus demo endpoints for the acceptance run in a separate `DemoEndpoints.cs`: enqueue N configurable no-op, slow or always-failing jobs; cancel a job by id; requeue a job by id; and the health check at `/health`, `appsettings.json`, a `docker-compose.yml` with PostgreSQL), `docs/getting-started.md`, `tests/Bellhop.Tests/Docs/GettingStartedSnippetTests.cs`, and README "Status" and quick-start updates.

The getting-started page covers, in this order: install packages; the §3 code; run PostgreSQL with Docker; run the app and open `/jobs`; what happened (schema created automatically, D4, and how to get the script instead, `BellhopPostgreSqlSchema.GetScript`); testing with `Bellhop.Testing` (one example); at-least-once delivery, the lease window (60 s) and idempotent handlers (EXE-5); OpenTelemetry and Prometheus in two lines (BLT-5 doc part); the defaults table with a link to arch §3.2 for now.

**As a** developer evaluating Bellhop
**I want** a getting-started page whose code is exactly what runs
**so that** I can go from nothing to a working dashboard in five minutes.

## Acceptance criteria

- Given the sample's sources, then each §3 code block appears in them verbatim, as a contiguous block. The sample adds only: `using` lines; an auth block in `Program.cs` that registers an authentication scheme and the "Admins" policy (M-6); `app.MapHealthChecks("/health")`; and a call to map the demo endpoints from `DemoEndpoints.cs`. `GettingStartedSnippetTests` extracts the C# blocks from `docs/getting-started.md` and asserts each appears verbatim in the sample sources, so the doc can't drift (NFR-6).
- Given the getting-started page, then it shows the §3 blocks verbatim, followed by a short "Define the Admins policy" block with the auth lines the sample uses, and a sentence saying any policy or `.AllowAnonymous()` works (M-6).
- Given `docker compose up -d` in the sample folder and `dotnet run`, when `/jobs` is opened in Development as a user who satisfies "Admins" (the sample's dev sign-in), then the dashboard shows the overview, and `nightly-cleanup` on the recurring page with `0 3 * * *  Europe/Sofia` and its next run (manual check, recorded in Notes with timings: clone to dashboard in minutes).
- Given `POST /users` on the sample, then a `send-welcome-email` job runs at once, and a `SendFollowUpEmail` job appears as scheduled 3 days ahead.
- Given the sample started with `ASPNETCORE_ENVIRONMENT=Production` and the §3 `RequireAuthorization("Admins")`, then it starts, and `/jobs` requires the policy. If the policy call is removed, startup fails with the DSH-2 message. Shown in Notes.
- Given the README, then "Status" says M1 preview, links the getting-started page, and no longer says there is no code.
- Given the getting-started page, then every option it mentions exists with the stated default.

## Tests

`GettingStartedSnippetTests`. The sample builds in the gate. Running it is manual and recorded in Notes.

## Out of scope

The docs site, samples repo, worker-service and multi-tenant samples (M2, NFR-6).

**Priority:** Must
**Depends on:** M1-15, M1-16, M1-17, M1-20, M1-21, M1-22, M1-24, M1-25
**Traces to:** P1, NFR-6 (M1 part), SET-1, EXE-5, DSH-2, D4; requirements.md §3; arch M-6

## Notes

Status: not started
