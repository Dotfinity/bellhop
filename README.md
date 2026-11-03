# Bellhop

Bellhop is a background-job and scheduling library for .NET 8+. It is built to be easy to set up, easy to use, and easy to configure when you need to, and to fix the things people complain about in Hangfire and TickerQ.

> **Status:** design phase. There is no code yet. The requirements are complete and open for review.

## What it will do

- Fire-and-forget, delayed and recurring jobs; continuations, chains and batches
- Retries with backoff, dead-lettering, cancellation and timeouts
- Multi-node execution with atomic claims and lease-based crash recovery
- Stores: PostgreSQL, SQL Server, SQLite, in-memory, and Redis or Redis-compatible servers (Valkey, Garnet, Dragonfly, Kvrocks)
- A dashboard secured by ASP.NET Core authorization, with live updates, per-job logs, tags, throttling, a launch page, recurring-job management and notifications
- OpenTelemetry traces and metrics, health checks, and a testing package with a fake clock and inline execution
- MIT licensed, with no paid tier and no runtime license checks

## What it will look like

```csharp
builder.Services.AddBellhop(bellhop =>
{
    bellhop.UsePostgres(connectionString);
    bellhop.AddJobsFromAssemblyContaining<Program>();
});

app.MapBellhopDashboard("/jobs").RequireAuthorization("Admins");
```

```csharp
[JobName("send-welcome-email")]
public sealed record SendWelcomeEmail(Guid UserId) : IJob;

public sealed class SendWelcomeEmailHandler(IEmailSender email) : IJobHandler<SendWelcomeEmail>
{
    public Task HandleAsync(SendWelcomeEmail job, JobContext ctx, CancellationToken ct)
        => email.SendWelcomeAsync(job.UserId, ct);
}

await jobs.EnqueueAsync(new SendWelcomeEmail(user.Id));
```

A job is a plain record with a stable name. The handler is an ordinary class built by dependency injection. No expression trees, no magic strings, and nothing breaks when you rename a class.

## Why it is different

- **Correct under concurrency by construction.** Every claim, recurring trigger and overlap decision is one atomic store operation. No in-process locks pretending to be distributed.
- **Defaults that need no tuning.** Adaptive polling, push notifications where the store supports them, paced cleanup, and a startup summary that tells you what is running.
- **Built in, not bolted on.** The things people install as Hangfire plugins (dashboard auth, per-job logs, tags, concurrency limits, launch forms, recurring-job UI, alerts, HTTP jobs) ship in the box.
- **Nothing is silent and nothing is static.** Every failure is logged with an event id, and everything resolves from DI so tests never fight global state.

## Documents

- [requirements.md](requirements.md): principles, requirements, packaging, phasing, open questions and design decisions
- [research.md](research.md): the evidence behind them, covering Hangfire and TickerQ, the Redis landscape, the plugin ecosystem and sources

## License

MIT. The license file will be added with the first code.
