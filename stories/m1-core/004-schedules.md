# M1-04 Schedules: cron, intervals and time zones

## Context

Cron correctness was a major TickerQ failure (T8: silently local time, 5-field expressions that never fire) and the source of Hangfire catch-up surprises (H10). The core may not depend on a cron library (SEC-4), so this story writes the parser and evaluator in-house (A-11). It is a pure function library with no store or engine involvement, so it can run in parallel with the storage track.

It implements `Schedule.Cron`, `Schedule.Every`, `Schedule.Parse`, the `Cron` helpers and the time-zone and DST rules of arch §7.7 ("Time zones" and "Intervals"). It replaces the M1-02 placeholder in `Schedule`.

Files: `src/Bellhop/Scheduling/` (`CronExpression` internal, `CronSchedule`, `IntervalSchedule`, `Schedule`, `Cron`, `TimeZoneResolver`).

Cron grammar (document it in the XML docs of `Schedule.Cron`):

- 5 fields `minute hour day-of-month month day-of-week`, or 6 with a leading `second`.
- Each field: `*`, a number, a range `a-b`, a list `a,b,c`, a step `*/n` or `a-b/n`. Month names `JAN`–`DEC`, day names `SUN`–`SAT` (case-insensitive). Day-of-week 0 and 7 are both Sunday.
- When both day-of-month and day-of-week are restricted, a day matches if either matches (standard Vixie cron rule).
- Not supported in M1, with a clear error: `L`, `W`, `#`, `?`, and `@` macros. The helpers in `Cron` cover the common cases.

**As a** developer
**I want** cron and interval schedules that behave identically on every node and across DST changes
**so that** recurring jobs fire when I expect, never silently late or twice.

## Acceptance criteria

- Given `Schedule.Cron("0 3 * * *")`, when the next occurrence after 2026-11-03T02:59:59Z in UTC is requested, then it is 2026-11-03T03:00:00Z. Given 6 fields `"*/10 * * * * *"`, the next occurrence after 12:00:05 is 12:00:10.
- Given an invalid expression such as `"61 * * * *"`, `"* * *"` or `"0 3 * * MON#2"`, when `Schedule.Cron` is called, then it throws `FormatException` whose message names the field (for example `minute`), the bad value, and the allowed range (REC-2).
- Given `"30 2 * * *"` in `Europe/Sofia`, when the next occurrence after 2027-03-27T12:00Z is requested (the spring-forward night, when local 03:00–04:00 does not exist on 2027-03-28), then it is 2027-03-28 02:30 local (still valid that day, before the gap). Given `"30 3 * * *"` over the same night, then it is 2027-03-28 04:00 local, the first valid instant after the gap, and only once (REC-4).
- Given `"30 3 * * *"` in `Europe/Sofia` across the fall-back night (2026-10-25, when local 03:00–04:00 occurs twice), when occurrences are enumerated across that night, then 03:30 local appears exactly once, at the first (daylight) instance (REC-4).
- Given `"0 * * * *"` in a time zone with a 30-minute DST shift (`Australia/Lord_Howe`), when occurrences across its DST change are enumerated, then no hour is produced twice and none is skipped except wall-clock hours that do not exist.
- Given `Schedule.Every(TimeSpan.FromMinutes(15))`, when the next occurrence after 10:07:00Z is requested, then it is 10:15:00Z on every call and node, whatever the time zone argument (A-12). Given an interval under 1 s, it throws `ArgumentOutOfRangeException`.
- Given an IANA id such as `"Europe/Sofia"` on Windows and Linux, when it is resolved, then the same `TimeZoneInfo` rules apply. Given `"Mars/Olympus"`, then resolution fails with `Unknown time zone "Mars/Olympus". Use an IANA id such as "Europe/Sofia" or "UTC".`
- Given `Cron.Daily(hour: 3)`, `Cron.Weekly(DayOfWeek.Monday, 9)` and the other helpers, when they are called, then they return the expected cron strings, and out-of-range arguments throw.
- Given any schedule, when `Schedule.Parse(s.Kind, s.Expression)` is called, then an equal schedule results (round-trip, needed for persistence).
- Given `"0 0 31 2 *"` (February 31st), when the next occurrence is requested, then it returns null within bounded time (searching at most 5 years ahead) instead of looping.

## Tests

`CronParserTests` (grammar, errors), `CronScheduleTests` (next occurrence table-driven over many cases), `CronDstTests` (Sofia gap and overlap, Lord Howe, New York, UTC), `IntervalScheduleTests`, `CronHelpersTests`, plus a property-style test with Bogus: random valid expressions and random instants, checking that the next occurrence is strictly after the input and matches every field.

## Out of scope

Misfire and overlap logic (M1-14, M1-15). Persisting custom `ISchedule` kinds (A-12).

**Priority:** Must
**Depends on:** M1-02
**Traces to:** REC-2, REC-4, REC-11 (built-in kinds), SEC-4; arch §7.7, A-11, A-12

## Notes

Status: not started
