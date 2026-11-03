# M1-18 PostgreSQL schema and migrations

## Context

PostgreSQL is the reference store (D3). This story creates the `Bellhop.PostgreSql` package's foundation: options, `UsePostgres`, the v1 schema from arch §4.2, the embedded, idempotent, concurrency-safe migration runner from arch §4.3, the version-window rule from arch §4.6, the script export (M-1), and the Testcontainers fixture every later PostgreSQL story uses. `InitializeAsync` is the only store method implemented here; the others throw `NotImplementedException("Not built yet: <method> (M1-19)")` until their story lands.

It answers T3 and T4 (TickerQ's growing table count and hidden `DbContext`) and H15 (Hangfire's upgrade friction): 6 tables, no EF Core, plain ADO.NET through Npgsql (STO-2, STO-4).

Files: `src/Bellhop.PostgreSql/` (`PostgreSqlStoreOptions` with validation, `BellhopBuilderPostgreSqlExtensions.UsePostgres(string)` and `UsePostgres(Action<PostgreSqlStoreOptions>)`, `PostgreSqlJobStore` skeleton, `Migrations/V001__initial.sql`, `MigrationRunner`, `BellhopPostgreSqlSchema`), `tests/Bellhop.PostgreSql.Tests/` (`PostgresFixture` with Testcontainers `postgres:17-alpine`, one database per test class, skip-with-reason when Docker is unavailable).

**As a** developer or DBA
**I want** Bellhop to create and upgrade its own small schema safely, or hand me the exact script
**so that** setup is zero-effort by default and still DBA-friendly when automatic migration is off.

## Acceptance criteria

- Given `bellhop.UsePostgres(connectionString)` in the §3 snippet, when the host starts against an empty database, then schema `bellhop` exists with exactly the 6 tables and indexes of arch §4.2, `meta.schema_version` is `1`, and info 1501 logs `Applied Bellhop schema version 1 to "bellhop"` (STO-3, D4).
- Given an existing `NpgsqlDataSource` registered in DI and `UsePostgres()` with no connection string, then the store uses that data source.
- Given `Schema = "jobs_v2"`, then all objects are created in `jobs_v2`. Given `Schema = "bad;name"`, then option validation fails at startup naming `Bellhop:PostgreSql:Schema` and the identifier rule.
- Given 5 hosts starting at once against an empty database, when all have started, then the schema was applied exactly once (one 1501 log in total), and no host failed (advisory lock, arch §4.3).
- Given the schema is already at version 1, when a host starts, then no DDL runs and no 1501 is logged.
- Given an empty database and `AutoMigrate = false`, when the host starts, then startup fails with the message in arch §4.3, naming `BellhopPostgreSqlSchema.GetScript` (M-1).
- Given `BellhopPostgreSqlSchema.GetScript(0, "custom")` applied by hand with `psql` semantics (executed as one batch), then a host with `AutoMigrate = false` starts. The catalog it produced (tables, columns, types, indexes, from `information_schema` and `pg_indexes`) equals what `AutoMigrate` produces.
- Given `meta.schema_version = 2` (one ahead), then the host starts (rolling-deploy window). Given `3`, then startup fails with the message in arch §4.6. Given `"x"`, then startup fails with the message in arch §4.7. The window rule is also unit-tested without a database.
- Given a wrong password, when the host starts, then startup fails with Npgsql's authentication error wrapped as in M1-08 (A-5), and neither the startup summary nor any log line contains the password or the connection string (SEC-5).
- Given the startup summary, then the store line reads `PostgreSQL <server version>, schema bellhop v1 (auto-migrate on)` (SET-8).
- Given a machine without Docker, then every PostgreSQL test is reported as skipped with the reason `Docker is not available: <detail>`, not passed.

## Tests

`MigrationTests` (fresh, idempotent, concurrent, custom schema), `ScriptExportTests` (catalog equality), `SchemaVersionWindowTests` (unit and integration), `PostgreSqlOptionsTests`, `ConnectionSecretTests`.

## Out of scope

Every store method other than `InitializeAsync` (M1-19 to M1-21). LISTEN/NOTIFY (M1-22). The two-version rolling test (M2, when v2 exists).

**Priority:** Must
**Depends on:** M1-02
**Traces to:** STO-2, STO-3, STO-4, STO-5, SET-8, SEC-5, D3, D4; arch §4.2 to §4.7, M-1, A-4, A-5

## Notes

Status: not started
