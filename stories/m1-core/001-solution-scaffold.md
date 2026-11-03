# M1-01 Solution scaffold and gates

## Context

There is no code yet. This story creates the empty solution, the build settings every later story inherits, and the three gate commands, so that every later story can be judged by the same gate. It implements arch §2 (layout and rules) and arch §12 (build, test, lint), and it sets up the parts of SET-9 (one version, exact inter-package dependencies), NFR-1 (net8.0 and net10.0) and NFR-5 (public API tracking) that are pure build configuration.

Files to create:

- `Bellhop.slnx`, `global.json` (SDK 10.0.x, `rollForward: latestFeature`), `.editorconfig`, `LICENSE` (MIT, copyright "Bellhop contributors")
- `Directory.Build.props`: `TargetFrameworks` `net8.0;net10.0`, `Nullable` enable, `ImplicitUsings` enable, `LangVersion` latest, `TreatWarningsAsErrors` true, `AnalysisLevel` latest-recommended, `EnforceCodeStyleInBuild` true, `GenerateDocumentationFile` true for `src/`, one `Version` property (`0.1.0-preview.1`), deterministic builds, SourceLink-ready repository metadata
- `Directory.Packages.props` with central package management and exact versions (arch §12, A-7 per-TFM `Microsoft.Extensions.*`)
- Empty projects `src/Bellhop`, `src/Bellhop.PostgreSql`, `src/Bellhop.Dashboard`, `src/Bellhop.Testing`, and test projects `tests/Bellhop.Tests`, `tests/Bellhop.PostgreSql.Tests`, `tests/Bellhop.Dashboard.Tests`, `tests/Bellhop.Testing.Tests`, plus the library `tests/Bellhop.Storage.Conformance` (not a test project)
- `Microsoft.CodeAnalysis.PublicApiAnalyzers` on every `src/` project, with empty `PublicAPI.Shipped.txt` and `PublicAPI.Unshipped.txt`
- Package references between `src/` projects as `ProjectReference`. NuGet packs these as `>=` dependencies by default, so add an MSBuild step that makes them exact (`[0.1.0-preview.1]`), and record the approach in Notes (SET-9)
- `IsTrimmable` and `EnableTrimAnalyzer` on `src/Bellhop`, so trim warnings fail the build (NFR-1)
- `CHANGELOG.md` with an "Unreleased" section (NFR-5)
- `tests/Bellhop.Storage.Conformance` references `xunit.v3.extensibility.core` and `xunit.v3.assert`, not `xunit.v3` (it is a library of abstract test classes, arch §12)
- `.github/workflows/ci.yml`: Ubuntu, .NET 8 and 10, runs the three gates plus `dotnet list package --vulnerable --include-transitive` (SEC-4)
- The Mechanics section of `CLAUDE.md` filled in with Stack, Build, Test and Lint

**As a** contributor
**I want** a solution that builds, tests and lints with three commands
**so that** every story is checked against the same gate from the first commit.

## Acceptance criteria

- Given a fresh clone, when `dotnet build Bellhop.slnx -c Release` runs, then it succeeds for both target frameworks with zero warnings.
- Given a test project with one placeholder-free smoke test (for example, asserting that the core assembly's name is `Bellhop`), when the test command runs, then the test runs on net8.0 and net10.0 and passes.
- Given a file with a formatting violation, when `dotnet format Bellhop.slnx --verify-no-changes` runs, then it exits non-zero. Given the committed tree, it exits zero.
- Given a public type added to `src/Bellhop` without an entry in `PublicAPI.Unshipped.txt`, when the solution builds, then the build fails with RS0016.
- Given `dotnet pack src/Bellhop.PostgreSql -c Release`, when the `.nuspec` inside the package is inspected, then the dependency on `Bellhop` is the exact version `[0.1.0-preview.1]`.
- Given CLAUDE.md, when a new contributor reads the Mechanics section, then Stack, Build, Test and Lint show the exact commands from arch §12, including which `dotnet test` mode was chosen.
- Given the CI workflow, when it is linted with `actionlint` (if available locally) or read, then it runs build, test, format and the vulnerability check, and fails the job if any of them fails.

## Tests

- The smoke test above in `Bellhop.Tests`. The xUnit v3 runner is configured; AwesomeAssertions, Moq and Bogus are referenced centrally (D2).
- The pack and RS0016 checks are verified by hand once; the commands and output go in Notes.

## Out of scope

Any production type (M1-02). Docker-based tests (M1-18). Publishing packages.

**Priority:** Must
**Depends on:** –
**Traces to:** SET-9, NFR-1, NFR-5, NFR-7 (license), SEC-4; arch §2, §12; D2

## Notes

Status: not started
