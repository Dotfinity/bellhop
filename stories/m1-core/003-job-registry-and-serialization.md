# M1-03 Job registry and serialization

## Context

Stable job names are the fix for the most-cited Hangfire grievance (H1: renames break stored jobs), and safe deserialization is a security requirement (SEC-2). This story builds the job name table, the metadata merge and the default serializer, all in-process with no store. It implements arch §6.1 and §6.2.

Files: `src/Bellhop/Registry/` (`JobRegistry`, `JobRegistration`, `JobRegistryBuilder`, assembly scanner), `src/Bellhop/Serialization/` (`SystemTextJsonJobSerializer`, `PayloadMasker`, `JobSerializationException`, `JobPayloadTooLargeException`), and the `BellhopBuilder` methods that record registrations (`AddJob`, `AddJobsFromAssembly…`, `ConfigureJob`, `UseSerializer`, `UseJsonOptions`). `AddBellhop` itself is M1-08. This story exposes the builder through an internal constructor, so tests can create it.

**As a** developer
**I want** my jobs registered by a stable name with metadata from attributes or fluent configuration
**so that** renaming a class never breaks stored jobs and misconfiguration fails at startup with a clear message.

## Acceptance criteria

- Given `[JobName("send-welcome-email")] record SendWelcomeEmail : IJob` and its handler, when the registry is built, then the job resolves by `"send-welcome-email"` to the type and handler.
- Given a job type with no `[JobName]`, when the registry is built, then its name is the type's simple name and the registration is flagged so that M1-08 can log warning 1005.
- Given `[JobName("new-name", Aliases = ["old-name"])]`, when `"old-name"` is looked up, then it resolves to the same registration, and `RoutableNames` contains both names.
- Given two types that claim the same name or alias, when the registry is built, then it throws with the message from arch §6.1 naming both types.
- Given `AddJob<SendWelcomeEmail>()` with no handler (a client-only node, SET-7), when the registry is built, then the job resolves by name for enqueueing, is not in `RoutableNames`, and is reported in the registry's "no handler on this node" list (M1-08 logs it as 1007 in worker modes).
- Given a scanned assembly with a job type and no handler for it, then the job is registered without a handler, the same way.
- Given two handlers for one job type, when the registry is built, then it throws naming both handler types.
- Given a job name that violates the name rule in arch §6.1, when the registry is built, then it throws quoting the name and the rule.
- Given `AddJobsFromAssemblyContaining<A>()` and `AddJobsFromAssemblyContaining<B>()` for two different assemblies, when the registry is built, then jobs from both are registered (SET-10). Scanning the same assembly twice registers each job once.
- Given `[Queue("emails")]` on a type and `ConfigureJob<T>().OnQueue("bulk")`, when metadata is resolved, then the queue is `"bulk"` (fluent wins, JOB-7). The same holds for priority, retry and timeout. Attributes are read once; no attribute code executes.
- Given a stored name that is not in the table, when it is looked up, then the result is "not found", and no `Type.GetType` or other name-based type loading happens (SEC-2).
- Given a payload record with an extra JSON property and a missing one, when it is deserialized, then the extra one is ignored and the missing one takes its default (JOB-4).
- Given any serialized payload, when the JSON is inspected, then it contains no `$type` or type-name metadata unless the user declared `[JsonDerivedType]` (JOB-4).
- Given JSON that cannot bind (for example a string where an int is required), when it is deserialized, then `JobSerializationException` is thrown with the job name and the JSON path.
- Given `UseJsonOptions(custom)`, when a payload is serialized, then the custom options are used.
- Given `UseSerializer<MySerializer>()`, when a payload is serialized and deserialized, then `MySerializer` is used (EXT-3). Its XML docs and the interface's state that the output must be a JSON document (the PostgreSQL store keeps payloads as `jsonb`); a serializer that returns non-JSON fails at enqueue with a message naming the serializer type.
- Given a payload whose serialized size is over the hard limit, when the size check runs, then `JobPayloadTooLargeException` is thrown with the message in arch §6.2. Over the soft limit, the check returns a warning result carrying the size (the client logs it in M1-09).
- Given `record Login(string User, [property: Sensitive] string Password, Card Card)` where `Card` has a `[Sensitive] Number`, when the payload is masked, then `password` and `card.number` are `"***"` and other values are unchanged, including inside arrays of nested records.

## Tests

`JobRegistryTests`, `MetadataMergeTests`, `SystemTextJsonJobSerializerTests`, `PayloadSizeTests`, `PayloadMaskerTests`. Test fixtures live in two separate small assemblies, or in one assembly plus an `AssemblyBuilder`-free second test assembly project (`tests/Bellhop.Tests.ExternalJobs`), to prove multi-assembly scanning.

## Out of scope

The analyzer for missing names (M2, A-6). Logging (M1-08 logs 1004 and 1005 from the flags set here). Enqueue (M1-09).

**Priority:** Must
**Depends on:** M1-02
**Traces to:** JOB-1, JOB-2, JOB-3 (name table part), JOB-4, JOB-7, JOB-9, SET-10, STO-10, SEC-2, EXT-3; arch §6.1, §6.2

## Notes

Status: not started
