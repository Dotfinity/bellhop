# How to think about this codebase

You are working inside a system: code, data, infrastructure, the people who
run it, and the people who will change it after you. Every change is an
intervention in that system. The patterns below are how a senior engineer
sees a change before making it.

## 1. Everything is connected — find the edges before you cut

Code has no isolated parts. A function has callers, data has readers, a
config value has consumers you can't see from where you're standing.
- Before touching anything, map what depends on it: grep for usages, trace
  the data it produces, find who consumes the output.
- Treat public APIs, database schema, persisted formats, config, and
  background jobs as *contracts*. Changing a contract is a different kind of
  change from changing an implementation: it needs a compatibility story,
  not just a diff.
- Estimate blast radius explicitly in the plan. "This touches three callers
  and one table" is a plan; "update the service" is not.

## 2. History is signal, not noise

The current shape of the code is the residue of decisions and incidents.
Odd-looking code is usually a scar, not a mistake.
- Read git history and blame before "fixing" anything that looks wrong.
  Assume the workaround was deliberate until you know why it's there.
- When an existing pattern is genuinely wrong, say so and propose a change.
  Never silently fork it — two patterns for one thing is worse than one
  imperfect one.

## 3. Boundaries are where trust changes

Inside the system, data has already been checked. At the edges — user
input, external APIs, files, queues, other services — it hasn't.
- Validate hard at boundaries; trust internal code. Re-validating
  everywhere doesn't add safety, it adds noise that hides the real checks.
- Boundaries are also where things fail: timeouts, malformed responses,
  partial writes. Every crossing needs an answer to "and if this doesn't
  come back?"

## 4. Failure is a normal state of the system, not an exception to it

Networks drop, jobs run twice, two requests arrive at once, disks fill.
A design that only works on the happy path doesn't work.
- For every operation ask: null, empty, timeout, duplicate, concurrent,
  partial failure. Decide what happens in each case, on purpose.
- Make retried operations idempotent. If something can run twice, it will.
- Don't swallow exceptions. Either handle the failure meaningfully or let
  it propagate with enough context to be diagnosed.

## 5. Close the feedback loop — you don't know until the system tells you

A change is a hypothesis. Tests, builds, logs, and reviews are how the
system reports back. Skipping them isn't speed; it's flying blind.
- Run build, tests, and lint before claiming anything works, and again
  after every fix.
- Tests are the loop that stays closed after you leave: test behaviour, not
  implementation; give every bug a regression test that fails without the
  fix; cover the failure cases from pattern 4, not just the happy path.


## 8. Every addition is a liability the system carries forever

Code, dependencies, abstractions, and config all have ongoing cost: they
must be understood, maintained, secured, and worked around.
- Solve the stated problem with the simplest thing that works. No
  speculative abstraction, no config for a case nobody has.
- Don't add a dependency for a few lines of code. When you do, know why,
  and check its license and maintenance.
- Prefer existing patterns to new ones; the cost of a second way of doing
  something is paid by everyone, forever.

## 9. Entropy is the default — drift accumulates unless resisted

Systems decay through small neglects: stale comments, commented-out code,
leftover debug lines, docs that no longer match.
- Leave what you touch slightly better than you found it.
- Keep that cleanup out of the same commit as the feature. Mixed commits
  destroy the history that pattern 2 depends on.
- No commented-out code, no debug leftovers, no TODOs without an owner.

## 10. The humans are part of the system — information has to flow

The next person to touch this — a developer, a reviewer, an AI agent — has
none of your context. What you don't write down is lost.
- Comments explain *why*, only where the why isn't obvious: workarounds,
  business rules, traps. Never restate what the code does.
- Commit messages explain the why; one logical change per commit.
- Stories record the decisions and trade-offs made during implementation,
  not just the requirement.
- When finishing, report what changed, what you verified, what you assumed,
  and where the reviewer should look hardest.

## 11. Ambiguity is a signal to stop, not to guess

A wrong assumption early is the most expensive error in the system,
because everything downstream inherits it.
- If the task has more than one reasonable reading, ask.
- If you must proceed, state the assumption where it can be seen and
  challenged.

---

# Mechanics

## Project
- Stack: 
- Build: 
- Test: 

## Stories
- `stories/` holds stories and bugs; epics get a named sub folder.
- Filename `NNN-short-slug.md` with Title, Context, Acceptance criteria, Notes.
- Completed stories move to `stories/completed/`.

## Commits
- Always commit your work once build, tests and lint pass; don't wait to be
  asked. Never push unless asked.
- Make commits atomic where possible: one logical change each (a story, a
  fix, a refactor), which builds and passes tests on its own. When work for
  several changes is in the tree, stage each one's files and hunks
  separately rather than committing them together.
- `<type>: <summary>` — feat, fix, refactor, chore, docs. Body says why.
- Reference the story slug. Never combine unrelated changes.

## Definition of done
- Build, tests, lint pass. New behaviour tested;
- Failure paths handled and observable.
- No secrets, debug leftovers, or dead code.
- Story acceptance criteria met, Notes updated.


## Workflow

1) write code
2) write tests
3) test
4) do code review
5) do security review
6) fix findings
7) commit changes and start next story