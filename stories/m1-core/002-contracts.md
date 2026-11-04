# M1-02 Public and store contracts

## Context

Every later story implements something declared here. Fixing the contracts first means stories in different tracks can run in parallel without inventing shapes. This story creates the types in arch §3.1 (user-facing), §3.2 (options classes and their defaults, without binding or validation), §5.1 and §5.2 (store contracts), and `BellhopEventIds` with the ids fixed in arch §8.4. It adds behaviour only where the type is a value type with obvious semantics: `JobId` parsing and formatting, the internal per-instance `IJobIdGenerator` (UUIDv7, A-1; never static, TST-1), `RetryDecision` factories, and `JobContext.CreateForTest` (TST-5) backed by an in-memory progress and parameter sink.

Interfaces get XML docs that state their semantics (arch §5.3 for the store), because STO-1 requires "documented semantics for every method".

Files: `src/Bellhop/*.cs` for namespace `Bellhop`, `src/Bellhop/Storage/*.cs` for `Bellhop.Storage`, `src/Bellhop/Diagnostics/BellhopEventIds.cs`, and `PublicAPI.Unshipped.txt`.

**As a** builder of any later M1 story
**I want** the public and store contracts to exist and compile
**so that** I implement against a fixed shape instead of inventing one.

## Acceptance criteria

- Given the types listed in arch §3.1, §3.2, §5.1 and §5.2, when the solution builds, then each exists with the listed members and namespace, and `PublicAPI.Unshipped.txt` lists them.
- Given `IJobStore`, when its members are counted, then it has 24 methods and 1 property (STO-1), and every member has an XML doc stating its semantics from arch §5.3.
- Given one `JobIdGenerator` instance called 10,000 times with a `FakeTimeProvider` that advances 1 ms per call, when the ids are sorted by their string form, then the order equals creation order and there are no duplicates.
- Given one generator called twice in the same millisecond, when the ids are compared, then they differ and the second sorts after the first (monotonic within a millisecond, per instance). Two generator instances share no state.
- Given the public API file, then `JobId` has no static factory that creates new ids (generation is per instance, arch §3.1).
- Given a `JobId`, when it is formatted and parsed back, then it round-trips. Given `"not-an-id"`, `TryParse` returns false and `Parse` throws `FormatException` whose message contains the input.
- Given `JobContext.CreateForTest(attempt: 2)`, when a handler calls `ReportProgressAsync(0.5, "half")` and `Parameters.SetAsync("k", 42)`, then the context exposes progress 0.5 with message "half", and `Parameters.Get<int>("k")` returns 42, with no store or DI involved.
- Given `JobContext.CreateForTest`, when `ReportProgressAsync` is called with a fraction outside 0 to 1, then it throws `ArgumentOutOfRangeException` naming the parameter.
- Given `JobContext.CreateForTest(leaseToken: t)`, then `LeaseToken` is `t`; without one, it is a fresh non-empty `Guid` (refinement D-1).
- Given `BellhopEventIds`, when it is read, then it contains every id named in arch §8.4 with the documented value, as `public const int`.
- Given none of the deferred types in arch §1.3 (for example `ContinueWithAsync`, `UniqueKey`, `IJob<TResult>`, `StoreCapabilities.TransactionalEnqueue`), when the public API file is searched, then none appears.
- Given the attribute classes, then each constructor argument is exposed as a get-only property (arch §3.1 note), and the build has no CS9113 warning.

## Tests

- `JobIdTests`: ordering, monotonicity, round-trip, parse failures.
- `JobContextCreateForTestTests`: progress, parameters, argument validation.
- `RetryDecisionTests`: factories produce the right cases; a negative delay throws.
- `StoreContractShapeTests`: reflection test asserting the `IJobStore` member count (stops silent growth past STO-1).

## Out of scope

Any implementation of the interfaces (M1-03 onward). Options binding and validation (M1-08). Cron parsing behind `Schedule.Cron` (M1-04): until then, `Schedule` factory methods throw `NotImplementedException("Not built yet: Schedule.Cron (M1-04)")`. Placeholders of this form are allowed only between M1 stories, must name the story that removes them, and that story removes them; M1-05 and M1-18 add the same kind for store methods.

**Priority:** Must
**Depends on:** M1-01
**Traces to:** STO-1, JOB-5, JOB-6, TST-2, TST-5, EXT-1 to EXT-6, RET-2, RET-6, OBS-3; arch §3, §5, §8.4; refinement D-1

## Notes

Status: not started
