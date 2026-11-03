# M1-23 Dashboard foundation: endpoint, security and shell

## Context

The dashboard is where both incumbents hurt most (H5: 401 for every remote request, 401 where 403 is meant; T5: broken behind proxies and `UsePathBase`, SignalR 405s, controllers leaking into Swagger). This story creates the `Bellhop.Dashboard` package: the endpoint mapping and convention builder, the secure-by-default startup check, the 403 behaviour, CSP, embedded assets, the HTML shell with navigation and themes, the JSON API scaffold with problem details, and the startup-summary line. Pages are M1-24 and M1-25. Implements arch §10.1, §10.2 (scaffold and error format) and §10.3.

The dashboard reads only through `IJobStore`, `IRecurringJobManager` and options. It is built and reviewed against the in-memory store seeded by a `DashboardFixture` (Bogus) in `tests/Bellhop.Dashboard.Tests`, and by a small dev host (`tests/Bellhop.Dashboard.DevHost`, not packed) that seeds the same data for manual review.

Files: `src/Bellhop.Dashboard/` (`DashboardEndpointRouteBuilderExtensions.MapBellhopDashboard`, `DashboardSecurityCheck`, `DashboardAuthorizationResultHandler` (an `IAuthorizationMiddlewareResultHandler` decorator, arch §10.1), `CspHeaders`, `EmbeddedAssets`, `DashboardApi` group, `ProblemResults`, the summary contributor), `Assets/index.html`, `Assets/app.css`, `Assets/js/app.js` (router, `api.js` fetch wrapper, `theme.js`, `nav.js`), `tests/Bellhop.Dashboard.Tests/`, `tests/Bellhop.Dashboard.DevHost/`.

**As a** operator
**I want** to mount the dashboard with one line, secured by my app's own authorization, working behind any proxy
**so that** I get a dashboard without a security surprise or a path-base bug.

## Acceptance criteria

- Given `app.MapBellhopDashboard("/jobs").RequireAuthorization("Admins")`, when an anonymous request hits `/jobs/` or `/jobs/api/overview`, then the response is the host's normal challenge (401 or a login redirect), and an authenticated user without the policy gets **403** with no redirect, for both the page and the API (DSH-1, DSH-2, M-4).
- Given `.AllowAnonymous()` or `.RequireHost("admin.example.com")`, then they behave as on any endpoint (DSH-1).
- Given `Production` and `MapBellhopDashboard("/jobs")` with no authorization call, when the host starts, then startup fails with the message in arch §10.1. In `Development`, it starts, and notice 1601 says the dashboard is anonymous (DSH-2, P5).
- Given `Production`, no authorization call on the dashboard, and an `AuthorizationOptions.FallbackPolicy` that requires an authenticated user, then the host starts (the fallback policy counts).
- Given the host's own endpoints with cookie authentication, when an authenticated user is forbidden on one of them, then the host's normal behaviour (a redirect) is unchanged. Only dashboard endpoints get the 403 (M-4).
- Given a request to `/jobs` without a trailing slash, then it redirects to `/jobs/`, and the page's relative asset URLs resolve.
- Given the host uses `UsePathBase("/app")`, or is accessed through a reverse proxy with `X-Forwarded-Prefix` and the forwarded-headers middleware, when `/app/jobs/` is loaded, then every asset and API call resolves under `/app/jobs/` (relative URLs only) and the page renders (DSH-4).
- Given any dashboard response, then it has the CSP header from arch §10.3, and the HTML contains no inline `<script>` or `style=` attributes (DSH-10). A test parses the HTML to check.
- Given the embedded assets, then their total size is under 300 KB (D5). A test sums them.
- Given an app using Swashbuckle or `Microsoft.AspNetCore.OpenApi`, then no dashboard endpoint appears in the generated document (DSH-7).
- Given an API request for a resource that doesn't exist, then the response is 404 `application/problem+json` with a plain `title`. Given the store throws, then 503 with `title` `The job store could not be reached.` and the error type in `detail` (arch §10.2).
- Given the shell, when it loads, then a header shows "Bellhop", the navigation shows exactly Overview, Jobs, Recurring, Dead letters, Queues and Nodes, and a theme toggle switches light and dark, defaulting to the OS preference and remembered across reloads (DSH-10).
- Given keyboard only, then every navigation link and the theme toggle can be reached with Tab and activated, with a visible focus ring.
- Given the host's startup summary, then it includes `dashboard  /jobs  (authorization: policy Admins)`, or `(anonymous, Development)` (SET-8).
- Given the page, then no control for an operate action exists (arch §1.3 copy rule).

## Tests

`DashboardSecurityTests` (WebApplicationFactory with a test auth handler: anonymous, authenticated without policy, authorized, Development vs Production), `PathBaseTests`, `CspAndInlineScriptTests`, `AssetBudgetTests`, `ApiExplorerExclusionTests`, `ProblemDetailsTests`. The shell's look and keyboard behaviour are checked by hand in the dev host, in Chrome and Firefox, light and dark, at 360 px and 1280 px, and recorded in Notes (A-20).

## Out of scope

Page contents (M1-24, M1-25). Operate level and auth presets (M2). OpenAPI document (A-21).

**Priority:** Must
**Depends on:** M1-08 (reads the store through `IJobStore`; pages are built on the in-memory store, so M1-07 is needed before M1-24 and M1-25)
**Traces to:** DSH-1, DSH-2, DSH-3 (view), DSH-4, DSH-7, DSH-9 (scaffold), DSH-10, SEC-1, SET-8, D5; arch §10.1 to §10.3, M-4, A-20, A-21

## Notes

Status: not started
