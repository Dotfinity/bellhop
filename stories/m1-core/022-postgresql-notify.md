# M1-22 PostgreSQL LISTEN/NOTIFY wake-ups

## Context

EXE-8 requires stores with notifications to use them, so other nodes pick up work within about 100 ms. The PostgreSQL store implements `IJobStoreNotifications`: `pg_notify` in the same transaction as enqueue, promotion and cancel requests, and a dedicated listening connection that reconnects with backoff. The engine's `NotificationLoop` (arch §7.8) maps signals to the wake signal and the cancel path built in M1-12. Without notifications, polling still covers everything; notifications only cut latency.

Files: `src/Bellhop.PostgreSql/PostgreSqlNotifications.cs` (listener), notify calls added to every statement that moves a job into `Enqueued` (create, promote, recover, release on shutdown, requeue, reroute, awaiting promotion) and to cancel requests (channel `bellhop_<schema>`; payload `r|<namespace>|<queue>` or `c|<namespace>|<jobId>`; signals for other namespaces are ignored), `src/Bellhop/Engine/NotificationLoop.cs`, and `StoreCapabilities.PushNotifications` reported when `UseNotifications = true`.

**As a** user with several nodes
**I want** a job enqueued on one node to start on another within about 100 ms, and cancels to arrive at once
**so that** latency is low without polling hard.

## Acceptance criteria

- Given two hosts on one database (A with `Mode = ClientOnly`, B a worker with `PollInterval = 5 s`), when A enqueues a job, then B starts it within 500 ms in the test (the target is about 100 ms; the measured p50 over 50 jobs goes in Notes) (EXE-8).
- Given a `Processing` job on B, when A calls `CancelAsync`, then B's handler token is cancelled within 500 ms, well before the heartbeat interval.
- Given a scheduled job promoted by any node's tick, then workers on every node subscribed to that queue are woken.
- Given a signal for another namespace, then it is ignored (STO-9).
- Given the listening connection is killed (`pg_terminate_backend` on its pid), then warning 1502 is logged, the listener reconnects with backoff (1 s → 30 s), info 1503 is logged, and a `Reconnected` signal triggers one claim. A job enqueued while disconnected is picked up by the next tick or by that claim, never lost.
- Given `UseNotifications = false`, then no listening connection is opened, `Capabilities` doesn't include `PushNotifications`, and jobs still run within `PollInterval`.
- Given an idle node with notifications, when queries are counted over 10 × `PollInterval`, then there are at most 10 queries plus the idle `LISTEN` connection's keepalive (STO-6).
- Given the host stops, then the listening connection is closed within `ShutdownTimeout`.

## Tests

`PostgreSqlNotificationLatencyTests`, `PostgreSqlCancelSignalTests`, `PostgreSqlNotificationReconnectTests`, `PostgreSqlIdleQueryCountTests`.

## Out of scope

Redis-based hybrid notifications (RED-16, M2+).

**Priority:** Must
**Depends on:** M1-12, M1-13, M1-20, M1-21
**Traces to:** EXE-8, SCH-6, STO-6, STO-9; arch §7.8

## Notes

Status: not started
