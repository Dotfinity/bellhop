# M1-08 Hosting, options and startup summary

## Context

P1 ("three lines to a working system") and P5 ("fail fast at startup with an actionable message") live here, along with the TickerQ startup grievances (T4, T12: hidden I/O at registration, scheduler started by build-time tools, ASP.NET Core assumed in worker services). This story wires `AddBellhop`, options binding and validation, node modes, the hosted service skeleton and the startup summary. The loops it starts are empty shells that later stories fill in (M1-12 worker, M1-13 scheduler, M1-14 reconcile).

Implements arch §3.2 (options with defaults and validation messages) and arch §6.3. Logs 1001 to 1005.

Files: `src/Bellhop/Diagnostics/BellhopHealthState.cs` (created empty here so later loops can write to it; M1-16 exposes it as a health check), `src/Bellhop/Engine/StoreClock.cs` (internal `IStoreClock`, estimated store time = node time + offset; the offset starts at zero and M1-13 updates it from each tick, arch §7.4), `src/Bellhop/Engine/JobEventsInvoker.cs` (internal: calls every registered `IJobEvents` and logs 1209 for one that throws, without failing the caller; used by the client, processor, scheduler and recurring engine), `src/Bellhop/Hosting/` (`BellhopServiceCollectionExtensions`, `BellhopOptions` binding and an `IValidateOptions<BellhopOptions>` with hand-written messages, `BellhopHostedService`, `StartupSummary`, internal `IStartupSummaryContributor`), finishing `BellhopBuilder`.

**As a** developer
**I want** `AddBellhop(...)` to give me a working, validated setup with no hidden I/O and a clear summary at startup
**so that** I know what is running and misconfiguration stops the app with a message telling me how to fix it.

## Acceptance criteria

- Given a host with `AddBellhop(b => b.AddJobsFromAssemblyContaining<Program>())` and nothing else, when it starts in `Production`, then it uses the in-memory store and logs warning 1002 with the text from arch §6.3. In `Development`, no warning is logged (SET-2).
- Given `appsettings.json` with `"Bellhop": { "PollInterval": "00:00:02", "Queues": ["critical","default"] }` and code `Configure(o => o.PollInterval = TimeSpan.FromSeconds(3))`, when options are resolved, then `PollInterval` is 3 s (code wins) and the queues come from configuration (SET-3).
- Given each option in arch §3.2 set outside its valid range, when the host starts, then startup fails, and the exception message names the option path, the given value, the valid range and both ways to set it (SET-3). One test per option, table-driven.
- Given no configuration at all, when options are resolved, then every default equals arch §3.2, including `Retention.Succeeded = 7 days` (SET-4, D6).
- Given `AddBellhop(...)` registered with a store whose every method throws, when the service provider is built and services are resolved but the host is **not** started, then no store method was called (SET-5). This proves build-time tools that build but don't run the host are safe.
- Given the registry from M1-03 with a duplicate name, when the host starts, then startup fails with the registry's message, logged as 1004.
- Given a job without an explicit `[JobName]`, when the host starts, then warning 1005 names the type and suggests `[JobName("...")]`.
- Given `Mode = ClientOnly`, when the host starts, then no worker, scheduler or reconcile step runs (SET-7, A-14). Given `WorkerOnly` or `Both`, the loop shells start.
- Given job types registered without handlers, when a `Both` node starts, then info 1007 lists them. On a `ClientOnly` node nothing is logged.
- Given `ShutdownTimeout + CancellationGracePeriod` greater than `HostOptions.ShutdownTimeout − 2 s` (for example `ShutdownTimeout = 60 s` with the host default of 30 s), when the host starts, then warning 1006 names both values and suggests raising `HostOptions.ShutdownTimeout`. With the defaults (20 s + 5 s against 30 s), nothing is logged.
- Given `UseStore<MyStore>()`, then `IJobStore` resolves to `MyStore`, and the in-memory default is not applied (EXT-4).
- Given any store, then `IJobIndex` is resolvable from DI (the store's implementation), so applications can add and query index entries (STO-11).
- Given a running host, when it starts, then one log entry with event id 1001 contains the store description, node name, mode, namespace, queues with limits, worker count, registered job count, and a recurring line per definition (filled in by M1-14), in the layout of arch §6.3 (SET-8).
- Given a PostgreSQL-like connection string with a password in options, when the startup summary and every startup log line are captured, then no line contains the password or the connection string (SEC-5).
- Given `store.InitializeAsync` throws, when the host starts, then host start fails with that exception, wrapped with `Bellhop could not initialize the job store: <message>` (A-5).
- Given a worker service host (`Host.CreateApplicationBuilder`, no ASP.NET Core), when it starts and stops, then it works the same way (SET-6). The core project has no ASP.NET Core reference (checked by a test over the assembly's references).
- Given two hosts in one process, each with its own in-memory store, when a job is created through one host's `IJobStore`, then the other host's store doesn't see it, and the two hosts' singletons (`BellhopHealthState`, options, registry) are distinct instances (TST-1).

## Tests

`OptionsBindingTests`, `OptionsValidationTests` (table-driven), `HostedServiceStartupTests` (with a recording fake store and a captured `ILogger`), `NoIoAtRegistrationTests`, `ModeTests`, `StartupSummaryTests`, `CoreDependencyTests` (the assembly references only the BCL and `Microsoft.Extensions.*`, SEC-4).

## Out of scope

Loop bodies (M1-12, M1-13, M1-14). The dashboard summary line (M1-23). PostgreSQL options validation (M1-18).

**Priority:** Must
**Depends on:** M1-03, M1-05
**Traces to:** SET-1 to SET-8, SET-10, TST-1, EXT-4, STO-11, SEC-4, SEC-5, P1, P5; arch §3.2, §6.1, §6.3, A-5, A-14

## Notes

Status: not started
