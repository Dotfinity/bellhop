# Findings: Bellhop recurring jobs

<!-- refiner-findings v1 | module: recurring | specHash: 577c79cef0e7a3329bb335ff06542f1779e2fc1db8e814f3c61790b86ce87aa6 | run: 2026-11-06 | previous: none -->

**Run:** 2026-11-06 · **Requirements file:** `specs/recurring.json` (specHash `577c79cef0e7`) · **Model:** `specs/model/recurring/Recurring.tla` · **TLC:** 2.19, every invariant that holds was checked to completion with no TLC exception (5 cfgs, 106,624 to 5,451,100 distinct states, ≤ 80 s each); results per cfg in [How to reproduce](#how-to-reproduce)
**Result:** 11 findings — 4 contradictions · 3 gaps · 0 unprovable · 4 ambiguities · 0 modeling notes

The model has no clock. Anything that depends on real amounts of time (DST, time zones, validity windows, the 60 s misfire threshold as a number) is outside what it can judge; see *Coverage*.

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | contradiction | high | INV-204, REQ-221, REQ-223, REQ-224 | Under Queue(1), a new occurrence starts while an earlier one is still waiting, then both run |
| F-2 | contradiction | high | INV-204, REQ-223, REQ-224, REQ-233 | Under Queue(max ≥ 2), one finished run releases every waiting occurrence at once |
| F-3 | contradiction | medium | INV-204, REQ-221, jobs REQ-138/REQ-186, jobs REQ-132 | A timed-out handler that was abandoned keeps running while the next occurrence starts |
| F-4 | contradiction | medium | INV-210, REQ-227, REQ-215, REQ-206 | During maintenance, a schedule change, resume or restore moves nextRunAt, which INV-210 forbids |
| F-5 | gap | medium | REQ-204, REQ-206 | A job that comes back from Orphaned with changed code keeps the old stored definition |
| F-6 | gap | medium | REQ-203, REQ-204, REQ-208, REQ-213 | A runtime job and a code job with the same name merge into a runtime job running code's definition |
| F-7 | gap | medium | REQ-221, REQ-222, REQ-235, jobs REQ-124 | An unroutable occurrence job blocks its recurring job for good |
| F-8 | ambiguity | medium | REQ-224, REQ-213, REQ-207, REQ-214, REQ-205 | Waiting occurrences still start after their job is paused, orphaned or removed |
| F-9 | ambiguity | medium | REQ-217, REQ-218, INV-207 | When older instants were missed and the newest is on time, how many occurrences are created? |
| F-10 | ambiguity | medium | REQ-227, REQ-204 | Does a schedule change that arrives with new code recompute nextRunAt? |
| F-11 | ambiguity | low | REQ-205, REQ-207 | "The orphan policy" is not an attribute of anything |

---

## F-1 · contradiction · high — Under Queue(1), a new occurrence starts while an earlier one is still waiting, then both run
<!-- finding: contradiction | INV-204 | REQ-221,REQ-223,REQ-224 -->

**Requirements involved**
- INV-204: *Where a recurring job's overlap policy is Skip or Queue, the system shall never have two of its occurrences' jobs processing at the same time on any nodes.*
- REQ-221: *When an occurrence is created and no earlier occurrence of the same recurring job has an unfinished job, the system shall enqueue a job with the recurring job's payload and record the occurrence as started.*
- REQ-223: *When an occurrence is created while an earlier occurrence of the same recurring job has an unfinished job, if the overlap policy is Queue and fewer occurrences than its maximum are waiting, then the system shall record the occurrence as waiting for the earlier ones to finish.*
- REQ-224: *While an occurrence is waiting, when the earlier occurrence's job succeeds, is dead-lettered or is cancelled, the system shall enqueue a job for the waiting occurrence and record it as started.*

**What happens** (TLC counter-example, `Inv_NoOverlapProcessing`, `Recurring_F_WaitingRace.cfg`, 11 states)
A job runs every minute with overlap Queue and the default maximum of 1 (as in SCN-210).
1. The 10:00 occurrence is created; nothing runs, so it is started and its job enqueued — REQ-221.
2. The 10:01 occurrence is created while the 10:00 job is unfinished; it is recorded as waiting — REQ-223.
3. A worker claims the 10:00 job and it succeeds (jobs REQ-123, REQ-127).
4. Before REQ-224 has started the 10:01 occurrence, the 10:02 occurrence is created. REQ-221 asks whether an earlier occurrence *has an unfinished job*. The 10:00 job is finished, and the 10:01 occurrence is waiting, so it has no job at all. The answer is "no", so 10:02 is started and its job enqueued — REQ-221.
5. REQ-224 now starts the waiting 10:01 occurrence (its earlier occurrence's job succeeded).
6. A worker claims the 10:01 job, and another claims the 10:02 job. **Two occurrences' jobs are processing; INV-204 is violated.** The runs also start out of order (10:02 before 10:01).

TLC found it with occurrences created by "trigger now" (REQ-226), which uses the same decision rule as the scheduler (REQ-216). The same steps with scheduled triggers give the same result.

**Why** The overlap check in REQ-221/REQ-223/REQ-235 looks only at *jobs*, and a waiting occurrence has no job yet. Nothing links the end of the earlier job to REQ-224 in the same step, so between them the waiting occurrence is invisible to the check.

**Options**
1. *(recommended)* Make waiting occurrences count as "in the way". REQ-221 starts a new occurrence only if no earlier occurrence has an unfinished job **or is waiting**, and the Queue branches decide in the same situation. A new 10:02 then sees 10:01 waiting and is skipped with QueueFull (max 1), or waits behind it (max ≥ 2, see F-2).
2. Require REQ-224 to happen in the same store write as the earlier job's completion (a jobs-module hook). This closes the race for max 1 only and still leaves F-2.
3. Redefine "unfinished" in the glossary to include waiting occurrences. This is the same as option 1 but hidden in an annotation, and glossary edits are not semantic, so nothing would be re-modeled.

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-221", "ears": { "when": "an occurrence is created and no earlier occurrence of the same recurring job has an unfinished job or is waiting",
      "shall": "enqueue a job with the recurring job's payload and record the occurrence as started" } },
  { "id": "REQ-223", "ears": { "when": "an occurrence is created while an earlier occurrence of the same recurring job has an unfinished job or is waiting",
      "if": "the overlap policy is Queue and fewer occurrences than its maximum are waiting",
      "shall": "record the occurrence as waiting for the earlier ones to finish" } },
  { "id": "REQ-235", "ears": { "when": "an occurrence is created while an earlier occurrence of the same recurring job has an unfinished job or is waiting",
      "if": "the overlap policy is Queue and its maximum of waiting occurrences is already reached",
      "shall": "start nothing and record the occurrence as skipped with reason QueueFull" } }
]
```
REQ-222 and REQ-225 can keep their wording, because no occurrence waits under Skip, Allow or CancelPrevious. Keep the same `when` phrase on all four so the same-trigger lint still groups them.

---

## F-2 · contradiction · high — Under Queue(max ≥ 2), one finished run releases every waiting occurrence at once
<!-- finding: contradiction | INV-204 | REQ-223,REQ-224,REQ-233 -->

**Requirements involved**
- INV-204 (as in F-1).
- REQ-224: *While an occurrence is waiting, when the earlier occurrence's job succeeds, is dead-lettered or is cancelled, the system shall enqueue a job for the waiting occurrence and record it as started.* (notes: "With several waiting occurrences, the oldest starts first.")
- REQ-233: *The system shall allow at most MaxQueuedOccurrences waiting occurrences per recurring job under the Queue overlap policy, 1 by default.* (notes: configurable per job as Queue(max))

**What happens** (TLC trace, probe `Probe_NewerWaiterStartsBesideOlder`, `Recurring_P_QueueTwoWaiters.cfg`, 9 states; the probe is a modeling aid, not a requirement)
A job runs every minute with overlap Queue(2).
1. 10:00 is started and its job enqueued — REQ-221.
2. 10:01 is created while 10:00's job is unfinished, so it waits — REQ-223.
3. 10:02 is created while 10:00's job is unfinished. One occurrence is waiting, which is fewer than 2, so 10:02 waits too — REQ-223.
4. 10:00's job is claimed and succeeds (jobs REQ-127).
5. REQ-224 starts 10:01, the oldest waiting occurrence.
6. 10:02 is still waiting, and *its* earlier occurrence's job (10:00) has succeeded. That is all REQ-224's `when` asks for, so REQ-224 can start 10:02 right away, while 10:01's job is still unfinished. When both are claimed, **INV-204 is violated**.

**Why** Each waiting occurrence waits for "the earlier occurrence's job", which is the job that was running when it was created, not for the occurrence just ahead of it in the queue. The "oldest first" note orders the starts but does not serialize them.

**Options**
1. *(recommended)* A waiting occurrence starts only when every earlier occurrence of the same job is finished **and** none of them is still waiting. That makes it a true FIFO with one runner.
2. Keep REQ-224 but release only one waiting occurrence per finished job, and turn the note into requirement text. The result is the same but harder to read.
3. Fix the maximum at 1 (drop configurability from REQ-233). This removes the case, but option 1 is still needed for F-1.

**Ready to apply (option 1)**
```json
{ "id": "REQ-224", "ears": { "while": "an occurrence is waiting",
    "when": "every earlier occurrence of the same recurring job has a job that succeeded, was dead-lettered or was cancelled, and no earlier occurrence is waiting",
    "shall": "enqueue a job for the waiting occurrence and record it as started" } }
```

---

## F-3 · contradiction · medium — A timed-out handler that was abandoned keeps running while the next occurrence starts
<!-- finding: contradiction | INV-204 | REQ-221,jobs.REQ-138,jobs.REQ-186,jobs.REQ-132 -->

**Requirements involved**
- INV-204 (as in F-1). Its notes say: *"Expected to fail when a lease expires and the job is recovered while the original node still runs it (the at-least-once window, REQ-10). The model should report that case."*
- REQ-221 (as in F-1). The glossary defines "unfinished" as not Succeeded, DeadLettered or Cancelled.
- jobs REQ-186: *…if the handler is still running TimeoutGracePeriod later …, and the attempt number has reached maxAttempts …, then the system shall abandon the handler if it is still running and move the job to dead-lettered with reason Timeout.*

**What happens** (TLC counter-example, `Inv_NoOverlapRunning`, `Recurring_F_RunningHandlers.cfg`, 7 states)
nightly-cleanup is code-defined with overlap Skip.
1. Node A starts and creates nightly-cleanup — REQ-203.
2. An occurrence is created and started — REQ-221 (TLC used trigger now, REQ-226; a scheduled trigger gives the same result).
3. A worker on A claims the job.
4. The handler overruns its timeout and grace period on its last attempt. The job is dead-lettered and the handler is abandoned, **but it is still executing** — jobs REQ-186.
5. The next occurrence is created. The earlier job is dead-lettered, so it counts as finished, and the new occurrence is started — REQ-221.
6. A worker claims the new job. **Two runs of nightly-cleanup are executing at once; INV-204 ("on any nodes") is violated.**

The case named in the notes (lease expiry, jobs REQ-132) is also reachable. The old handler keeps running after its job is recovered, the recovered job succeeds on another node, and the next occurrence starts while the old handler still runs. The timeout path above is shorter and is **not** covered by the notes.

**Why** INV-204 promises something about *handlers*, and the jobs module cannot keep that promise once a handler is abandoned or partitioned away. With the narrow reading (job *status* Processing), this path does not violate INV-204. Only F-1 and F-2 do.

**Options**
1. *(recommended)* Restate INV-204 in terms of the store: never two of its occurrences' jobs **in state Processing** at the same time. Add an `info` item saying that abandoned or lease-lost handlers can still overlap (the at-least-once window).
2. Keep INV-204 as written and treat a dead-letter for Timeout as "unfinished" until the abandoned handler has actually stopped. This needs a new job attribute and a jobs-module requirement.
3. Accept and tag: `"tags": ["accepted-at-least-once"]`, with the notes extended to cover timeouts. Later runs will report it as low.

**Ready to apply (option 1)**
```json
[
  { "id": "INV-204", "ears": { "where": "a recurring job's overlap policy is Skip or Queue",
      "shall": "never have two of its occurrences' jobs in the Processing state at the same time" } },
  { "id": "REQ-238", "kind": "info", "status": "approved",
    "ears": { "shall": "not prevent a handler that was abandoned on timeout or lost its lease from still running while the next occurrence's job runs (the at-least-once window, jobs REQ-10)" },
    "mentions": ["RecurringJob.overlapPolicy"] }
]
```

---

## F-4 · contradiction · medium — During maintenance, a schedule change, resume or restore moves nextRunAt, which INV-210 forbids
<!-- finding: contradiction | INV-210 | REQ-227,REQ-215,REQ-206 -->

**Requirements involved**
- INV-210: *While the global maintenance pause is on, the system shall never create an occurrence on schedule, and leave nextRunAt unchanged so that instants missed meanwhile go through the misfire policy when maintenance ends.*
- REQ-227: *When a recurring job's schedule changes, the system shall compute nextRunAt from now, never from the last execution, and create no catch-up occurrence for the old schedule.*
- REQ-215: *When an operator resumes a paused recurring job, the system shall mark the job active and compute nextRunAt from now.* REQ-206 does the same on restore.

**What happens** (TLC counter-example, `Prop_MaintenanceKeepsNextRunAt`, `Recurring_F_Maintenance.cfg`, 5 states)
1. An operator adds a runtime job, active — REQ-208.
2. Its next due instant passes.
3. The operator turns maintenance on (jobs REQ-162). The instant is now one that INV-210 says must go through the misfire policy later.
4. The operator changes the job's schedule — REQ-212, REQ-227. **nextRunAt is recomputed from now while maintenance is on; INV-210 is violated**, and the missed instant is dropped instead of being handled by the misfire policy.

Resuming a paused job (REQ-215) or a node bringing back an orphaned one (REQ-206) during maintenance does the same.

**Why** INV-210's "leave nextRunAt unchanged" is written as an absolute rule, but it is meant to stop the *scheduler* from advancing nextRunAt. Operator actions that are defined to reset nextRunAt "from now" collide with it.

**Options**
1. *(recommended)* Narrow INV-210 to the scheduler: during maintenance no trigger runs, so no trigger advances nextRunAt. Operator and reconciliation actions keep their own "from now" rules.
2. Make REQ-215, REQ-227 and REQ-206 leave nextRunAt alone while maintenance is on, and recompute it when maintenance ends. Users would then see a nextRunAt that ignores their change for a while.
3. Refuse schedule edits and resumes while maintenance is on. This is heavy-handed.

**Ready to apply (option 1)**
```json
{ "id": "INV-210", "ears": { "while": "the global maintenance pause is on",
    "shall": "never create an occurrence on schedule and never advance nextRunAt by a scheduled trigger, so that instants missed meanwhile go through the misfire policy when maintenance ends" } }
```

---

## F-5 · gap · medium — A job that comes back from Orphaned with changed code keeps the old stored definition
<!-- finding: gap | RecurringJob.definitionHash | REQ-204,REQ-206 -->

**Requirements involved**
- REQ-204 (`from: Active, Paused`): *When a node with the worker registered starts and the hash of a code-defined recurring job's code definition differs from the stored definitionHash, the system shall update the stored definition and definitionHash to match the code, keeping its paused or active state.*
- REQ-206: *When a running worker node declares an orphaned recurring job again, the system shall return the job to the state it had before it was orphaned, with nextRunAt computed from now.*

**What happens** (TLC trace, probe `Probe_StaleDefinitionAfterRestore`, `Recurring_P_StaleDefinition.cfg`, 8 states)
1. Node A starts on release v1, which declares weekly-report; the job is created with v1's definition — REQ-203.
2. A is redeployed with v3, which no longer declares weekly-report. The scheduler orphans it — REQ-205.
3. A is redeployed with v2, which declares weekly-report again **with a changed schedule**. At startup REQ-204 does not apply, because the job is Orphaned and REQ-204 covers only Active and Paused.
4. A, now running, declares it, and REQ-206 brings it back to Active.
5. **Every running node runs v2, but the stored definition and hash are still v1's.** weekly-report runs on the old schedule until some node restarts and REQ-204 fires.

**Why** REQ-204 skips orphaned jobs and REQ-206 restores only the state, so neither one carries the new definition across.

**Options**
1. *(recommended)* Make REQ-206 apply the code definition when it restores the job.
2. Let REQ-204 run before REQ-206 on orphaned jobs, by adding `Orphaned` to its `from`. That needs a sentence on ordering ("then return it to its earlier state").
3. Leave it and document that a restart is needed. This is surprising after a rollback.

**Ready to apply (option 1)**
```json
{ "id": "REQ-206", "ears": { "when": "a running worker node declares an orphaned recurring job again",
    "shall": "return the job to the state it had before it was orphaned, update the stored definition and definitionHash to match that node's code definition, and compute nextRunAt from now" },
  "mentions": ["RecurringJob.stateBeforeOrphan", "RecurringJob.nextRunAt", "RecurringJob.definitionHash", "hosting.Node.Running"] }
```

---

## F-6 · gap · medium — A runtime job and a code job with the same name merge into a runtime job running code's definition
<!-- finding: gap | RecurringJob.origin | REQ-203,REQ-204,REQ-208,REQ-213 -->

**Requirements involved**
- REQ-208: *When an operator adds a recurring job through IRecurringJobManager or the dashboard and no definition with its name exists, the system shall create a runtime-defined recurring job…*
- REQ-203: *…a code-defined recurring job has no stored definition with its name…* → create.
- REQ-204: *…the hash of a code-defined recurring job's code definition differs from the stored definitionHash…* → update the stored definition, keeping its state.

**What happens** (TLC trace, probe `Probe_RuntimeJobTakenOverByCode`, `Recurring_P_RuntimeTakenOver.cfg`, 3 states)
1. An operator adds nightly-cleanup from the dashboard; it is runtime-defined, with no definitionHash — REQ-208.
2. A release that declares nightly-cleanup in code starts on node A. REQ-203 does not fire, because a definition with that name exists. REQ-204 does fire: the stored definitionHash (none) differs from the code's.
3. **The stored job now has code's definition and hash but is still `origin: runtime`.** The operator can still edit it (REQ-212) and remove it (REQ-213). After a removal the next start re-creates it as code (REQ-203). REQ-205 never orphans it, because it is not "code-defined".

The reverse case is not covered either: REQ-208 says what happens when the name is free, but not when a code-defined job already has it (error? silent no-op?).

**Options**
1. *(recommended)* Names are unique across origins and a collision is an error on both sides. The API refuses to add a name that is already stored, and a starting node whose code declares a name stored as runtime-defined stops with a message naming the job (like REQ-210).
2. Code wins. REQ-204 also sets the origin to code, which makes the job read-only from then on; runtime edits are lost silently.
3. Runtime wins. REQ-204 applies only when the stored origin is code, and the node logs a warning that the code declaration is ignored.

**Ready to apply (option 1)**
```json
[
  { "id": "INV-211", "kind": "invariant", "status": "approved", "strength": "must", "entity": "RecurringJob",
    "ears": { "if": "an operator adds a recurring job through IRecurringJobManager or the dashboard with a name that is already stored",
      "shall": "reject the call with an error that names the existing job and its origin, and store nothing" },
    "mentions": ["RecurringJob.name", "RecurringJob.origin"] },
  { "id": "REQ-236", "kind": "transition", "status": "approved", "strength": "must", "entity": "hosting.Node", "actor": "Host",
    "from": ["Starting"], "to": ["StartupFailed"],
    "ears": { "while": "a node is starting", "if": "a code-defined recurring job has the name of a stored runtime-defined recurring job",
      "shall": "stop the node from starting with a message that names the job and says it is already defined at runtime" },
    "mentions": ["RecurringJob.name", "RecurringJob.origin"] }
]
```

---

## F-7 · gap · medium — An unroutable occurrence job blocks its recurring job for good
<!-- finding: gap | Occurrence.job | REQ-221,REQ-222,REQ-235,jobs.REQ-124 -->

**Requirements involved**
- REQ-222: *When an occurrence is created while an earlier occurrence of the same recurring job has an unfinished job, if the overlap policy is Skip, then the system shall start nothing and record the occurrence as skipped.*
- Glossary *unfinished*: not Succeeded, DeadLettered or Cancelled (REQ-221 notes: "A run waiting to retry therefore blocks the next one").
- jobs REQ-124: *…if no running worker node lists a handler for its name or any of its aliases, then the system shall mark the job unroutable without failing, retrying or deleting it.*

**What happens** (TLC trace, probe `Probe_UnroutableBlocksNext`, `Recurring_P_UnroutableBlocks.cfg`, 5 states)
1. An occurrence of a Skip-policy job is started and its job enqueued — REQ-221.
2. A release removes the job's *handler* but still declares the recurring job, so no orphaning happens (REQ-205). The job becomes Unroutable — jobs REQ-124.
3. The next occurrence is created and the Unroutable job counts as unfinished, so it is skipped — REQ-222.

TLC took steps 2 and 3 in the other order. They commute, because Enqueued and Unroutable are both "unfinished". **Every later occurrence is skipped as well** (or QueueFull under Queue), until an operator cancels the unroutable job. No requirement raises an alert or ends the block.

**Options**
1. *(recommended)* Treat Unroutable as finished for overlap decisions. The next occurrence is then decided by its own handler availability and also becomes unroutable, which is visible on the dashboard.
2. Keep it blocking, and add a requirement that a recurring job blocked by an unroutable job is reported (health check Degraded, dashboard warning).
3. Accept and document it in the REQ-221 notes.

**Ready to apply (option 1)** (the glossary is annotation, so the rule goes into the sentences that use it)
```json
{ "id": "REQ-221", "ears": { "when": "an occurrence is created and no earlier occurrence of the same recurring job has a job that is not succeeded, dead-lettered, cancelled or unroutable, or is waiting",
    "shall": "enqueue a job with the recurring job's payload and record the occurrence as started" } }
```
(This merges with F-1's change. Use the same wording in REQ-222, REQ-223, REQ-225 and REQ-235, and update the glossary entry *unfinished* to match.)

---

## F-8 · ambiguity · medium — Waiting occurrences still start after their job is paused, orphaned or removed
<!-- finding: ambiguity | Occurrence.Waiting | REQ-224,REQ-213,REQ-207,REQ-214,REQ-205 -->

**Requirements involved**
- REQ-224 (as in F-2). It has no condition on the recurring job's own state.
- REQ-213: *When an operator removes a runtime-defined recurring job, or an orphaned one of any origin, the system shall delete the definition.* REQ-207 removes it as well.
- REQ-214: *When an operator pauses a recurring job …, the system shall mark the job paused.* INV-201 covers only occurrences created on schedule.

**Example** A runtime job every minute with Queue. At 10:01 its occurrence waits behind the 10:00 run. At 10:01:30 the operator removes the job (REQ-213), or pauses it (REQ-214). At 10:01:40 the 10:00 run succeeds, and REQ-224 enqueues the 10:01 job "with the recurring job's payload", but there is no longer a definition to take the payload from (removal), or the operator just paused the job (pause). The model takes this reading: `StartWaiting` has no guard on the job's state.

**Options**
1. *(recommended)* Pausing, orphaning and removing all drop the waiting occurrences. Add a transition that records them as skipped with a reason.
2. Waiting occurrences are already decided and still start. Say so in REQ-224, and have the occurrence copy the payload when it is created, so removal does not matter.
3. Pause keeps them waiting until resume; removal skips them. This is the most nuanced option and needs two requirements.

**Ready to apply (option 1)**
```json
{ "id": "REQ-237", "kind": "transition", "status": "approved", "strength": "must", "entity": "Occurrence", "actor": "system",
  "from": ["Waiting"], "to": ["Skipped"],
  "ears": { "when": "a recurring job is paused, orphaned or removed while it has waiting occurrences",
    "shall": "record each waiting occurrence as skipped with reason Paused, Orphaned or Removed" },
  "mentions": ["Occurrence.reason", "RecurringJob.Paused", "RecurringJob.Orphaned"] }
```

---

## F-9 · ambiguity · medium — When older instants were missed and the newest is on time, how many occurrences are created?
<!-- finding: ambiguity | REQ-217 | REQ-217,REQ-218,INV-207 -->

**Requirements involved**
- REQ-217: *…if the misfire policy is RunOnce, then the system shall create a single catch-up occurrence for all missed instants.*
- REQ-218: *…if the misfire policy is Skip, then the system shall create no occurrence for the missed instants and only advance nextRunAt to the next future occurrence.*
- INV-207: *When a recurring job is triggered no more than MisfireThreshold after its due instant, the system shall treat the instant as on time and create its occurrence whatever the misfire policy.*

**Example** An hourly job. The schedulers are stalled from 01:59 and the first poll runs at 03:00:30. 02:00 is missed (60 min late); 03:00 is 30 s late, which is on time by INV-207.
- Skip: REQ-218 says "create no occurrence … and **only** advance nextRunAt", which gives none. INV-207 says 03:00 gets its occurrence, which gives one.
- RunOnce: either one occurrence (the catch-up covers 02:00 and 03:00), or two (a catch-up for 02:00 plus 03:00's own). With the default overlap Skip, the second of the two is immediately skipped, which logs a spurious overlap.

The model creates at most one occurrence per trigger (assumption A-5), so it cannot tell these apart.

**Options**
1. *(recommended)* Judge the newest due instant on its own and merge the catch-up into it. Skip creates 03:00 only if it is on time. RunOnce creates one occurrence. RunAll creates one per missed instant plus the on-time one, within its maximum.
2. Treat the whole trigger as a misfire once any instant was missed (Skip creates nothing, RunOnce one), and change INV-207 to say so.
3. Treat each instant separately (RunOnce creates two), and accept the overlap skip.

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-217", "ears": { "when": "a recurring job is triggered after one or more due instants were missed",
      "if": "the misfire policy is RunOnce",
      "shall": "create a single occurrence for all missed instants and, if the most recent due instant is on time, for that instant too" } },
  { "id": "REQ-218", "ears": { "when": "a recurring job is triggered after one or more due instants were missed",
      "if": "the misfire policy is Skip",
      "shall": "create no occurrence for the missed instants, create the occurrence of the most recent due instant only if it is on time (INV-207), and advance nextRunAt to the next future occurrence" } }
]
```

---

## F-10 · ambiguity · medium — Does a schedule change that arrives with new code recompute nextRunAt?
<!-- finding: ambiguity | REQ-227 | REQ-227,REQ-204 -->

**Requirements involved**
- REQ-227 (`actor: Operator`): *When a recurring job's schedule changes, the system shall compute nextRunAt from now, never from the last execution, and create no catch-up occurrence for the old schedule.*
- REQ-204: *…update the stored definition and definitionHash to match the code, keeping its paused or active state.* It says nothing about nextRunAt.

**Example** (SCN-203's job, with the change made in code) An hourly job last ran at 09:00 with nextRunAt 10:00. At 09:30 a deploy changes it in code to daily at 08:00. If REQ-227 covers only operator edits (as its `actor` says), REQ-204 leaves nextRunAt at 10:00, and the job runs once at 10:00 under its new daily definition, which is exactly what SCN-203 rules out for dashboard edits. The model follows `actor` and leaves nextRunAt unchanged in REQ-204.

**Options**
1. *(recommended)* REQ-204 recomputes nextRunAt from now when the schedule part of the definition changed.
2. Make REQ-227 actor-neutral (`actor: system`) and list REQ-204 in its `dependsOn`, so that it explicitly covers code and configuration changes.
3. Leave it and document that a code change takes effect after the next run.

**Ready to apply (option 1)**
```json
{ "id": "REQ-204", "ears": { "when": "a node with the worker registered starts and the hash of a code-defined recurring job's code definition differs from the stored definitionHash",
    "shall": "update the stored definition and definitionHash to match the code, keeping its paused or active state, and, if the schedule changed, compute nextRunAt from now as in REQ-227" },
  "mentions": ["RecurringJob.schedule", "RecurringJob.origin", "RecurringJob.definitionHash", "RecurringJob.nextRunAt"] }
```

---

## F-11 · ambiguity · low — "The orphan policy" is not an attribute of anything
<!-- finding: ambiguity | RecurringJob.orphanPolicy | REQ-205,REQ-207 -->

**Requirements involved**
- REQ-205: *…if the orphan policy is the default, then …mark it orphaned…*; REQ-207: *…if the orphan policy is set to delete, then the system shall remove the definition.*

**Example** Two code-defined jobs, A and B, both drop out of a release. Is the policy set once for the application (both are deleted) or per job (A is deleted and B is orphaned)? The entity has no `orphanPolicy` attribute and the glossary has no entry, so `mentions` cannot point at it, and impact analysis will miss changes to it. The model uses one global policy and explores both values.

**Options**
1. *(recommended)* Add a per-job attribute `orphanPolicy` (default Orphan), mention it in REQ-205 and REQ-207, and add a glossary entry.
2. Make it a global option: an `assumption` requirement naming it (for example `Bellhop:Recurring:OrphanPolicy`), which REQ-205 and REQ-207 then `dependsOn`.

**Ready to apply (option 1)**
```json
{ "entities": [ { "name": "RecurringJob", "attributes": ["…existing…", "orphanPolicy"] } ],
  "requirements": [
    { "id": "REQ-205", "mentions": ["RecurringJob.origin", "RecurringJob.stateBeforeOrphan", "RecurringJob.orphanPolicy", "hosting.Node.Running"] },
    { "id": "REQ-207", "mentions": ["RecurringJob.origin", "RecurringJob.orphanPolicy", "hosting.Node.Running"] } ],
  "glossary": { "orphanPolicy": "What happens to a code- or configuration-defined job no live node declares: Orphan (default, REQ-205) or Delete (REQ-207)." } }
```

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.
| # | Assumption | Affects |
|---|---|---|
| A-1 | No clock. Each job keeps a count of due instants passed since nextRunAt was set (0, 1, "2 or more"), and time passing is a nondeterministic step. "nextRunAt computed from now" resets the count to 0. | REQ-215, REQ-216, REQ-227, REQ-206, INV-210 |
| A-2 | REQ-216's compare-and-set is one atomic step, so INV-203 and SCN-200 hold by construction. The model checks that the old instant cannot fire again, not that the store implements the CAS. | INV-203, SCN-200 |
| A-3 | "Missed" (later than MisfireThreshold) is a nondeterministic choice when one instant is due and always true when two or more are due. This assumes the schedule interval exceeds MisfireThreshold. | REQ-217–REQ-219, REQ-234, INV-207 |
| A-4 | RunAll(max) is modeled with max = 1, which makes it indistinguishable from RunOnce. | REQ-219 |
| A-5 | A trigger creates at most one occurrence (see F-9). | REQ-216–REQ-219 |
| A-6 | Every modeled node has the worker registered. A node "declares" exactly what its release declares, and "live" means Running. The scheduler (triggers, orphan sweep) runs only while some worker node runs (hosting REQ-40). | REQ-203–REQ-207, REQ-216 |
| A-7 | REQ-224 is a separate system step after the earlier job finishes, not part of the jobs module's completion write (F-1 depends on this; option 2 there is the alternative). | REQ-224 |
| A-8 | At node start, REQ-203 and REQ-204 are applied together for every declared name. The store is keyed by name, so INV-200 and SCN-207 hold by construction and their concurrency claim is not judged. | REQ-203, REQ-204, INV-200, SCN-207 |
| A-9 | Overlap and misfire policies are fixed per job for a whole run. REQ-212 changes the definition content and possibly the schedule (nondeterministic), but not the policies. | REQ-212, REQ-221–REQ-225 |
| A-10 | jobs.Job is reduced to Enqueued / Processing / Failed / Succeeded / DeadLettered / Cancelled / Unroutable plus a "handler still executing" flag (lease lost, jobs REQ-132; abandoned on timeout, jobs REQ-138/REQ-186). Operator cancellation of arbitrary jobs, continuations and retention are not modeled. | INV-204, REQ-221–REQ-225 |
| A-11 | Finished occurrences free their slot (modeling artefact), but not while a waiting occurrence still refers to them. | all |
| A-12 | INV-204 is checked in two readings: job *status* Processing (`Inv_NoOverlapProcessing`) and any executing handler (`Inv_NoOverlapRunning`). | INV-204, F-1–F-3 |
| A-13 | definitionHash is the hash of the code definition last applied. A runtime edit under AllowRuntimeOverride changes the stored definition but not the hash (REQ-204 notes). | REQ-204, REQ-212 |
| A-14 | Configuration-defined jobs are not modeled (INV-209 and REQ-232 are `may`). | INV-209, REQ-232 |
| A-15 | The same-trigger warnings from `validate` were checked: REQ-205/REQ-207 and REQ-221/REQ-222/REQ-223/REQ-225/REQ-235 are each one action, and their guards are complementary and exhaustive. | — |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-201–REQ-208, REQ-211–REQ-227, REQ-233–REQ-235, INV-200, INV-201, INV-203, INV-204, INV-206, INV-207, INV-210, SCN-200–SCN-212 | REQ-200, REQ-228, REQ-229, REQ-230, INV-202, INV-208 (need a real clock: time zones, DST, validity window) · REQ-209, REQ-210 (schedule/time-zone validity not representable) · INV-205 (no exceptions or lock waits in the model) · REQ-231 (bookkeeping, nothing depends on it) · REQ-232, INV-209 (strength `may`) |

Not judged although modeled: INV-200, INV-203, SCN-200 and SCN-207 hold by construction (A-2, A-8). REQ-219 is modeled only with max = 1 (A-4).

## How to reproduce
All commands are run from `specs/model/recurring`, with `R=~/.claude-personal/skills/refiner-model/scripts/run_tlc.py`. The `run*.json`/`run*.md` outputs are gitignored and are regenerated by these commands. The non-scenario cfgs are generated by `gen_cfgs.sh` in the same folder, which holds the constant sets in one place.

TLC 2.19 throws "unexpected exception" when `-continue` has to rebuild many traces, and stops early, so every check uses `--stop-at-first`. Each check below completed with no exception. One combined cfg over every constant set does not finish: it passed 13M distinct states without finishing, because two jobs × two nodes × occurrence slots × every policy multiply. The checks are therefore split by concern, each with the smallest pools that still exercise it. Deadlock checking is on in every non-scenario run, and none was found.

| Check | Command (`python $R Recurring.tla …`) | Result |
|---|---|---|
| Main: INV-201, INV-210 (no trigger), INV-204 (status), REQ-233, SCN-200/202 — 1 job, 2 slots, Skip/Queue × RunOnce/Skip | `--config Recurring.cfg --stop-at-first` | passed, 565,104 distinct states, 7 s |
| Definitions: REQ-211/SCN-205, INV-206/SCN-212, SCN-208 — 2 jobs, 2 nodes, 2 releases, both orphan policies | `--config Recurring_Defs.cfg --stop-at-first` | passed, 106,624 distinct, 2 s |
| Overlap Queue(1), 3 slots: REQ-233 | `--config Recurring_OverlapQueue.cfg --stop-at-first` | passed, 5,451,100 distinct, 79 s |
| Overlap Queue(2), 3 slots: REQ-233 | `--config Recurring_OverlapQueue2.cfg --stop-at-first` | passed, 4,740,100 distinct, 70 s |
| Overlap, all four policies, 2 slots: REQ-233, INV-204 (status) | `--config Recurring_OverlapAll.cfg --stop-at-first` | passed, 1,071,648 distinct, 13 s |
| F-1 trace | `--config Recurring_F_WaitingRace.cfg --stop-at-first` | `Inv_NoOverlapProcessing` violated, 11 states |
| F-2 trace (probe) | `--config Recurring_P_QueueTwoWaiters.cfg --stop-at-first` | probe violated, 9 states |
| F-3 trace | `--config Recurring_F_RunningHandlers.cfg --stop-at-first` | `Inv_NoOverlapRunning` violated, 7 states |
| F-4 trace | `--config Recurring_F_Maintenance.cfg --stop-at-first` | `Prop_MaintenanceKeepsNextRunAt` violated, 5 states (run_tlc reports status "error", exit 13) |
| F-5 trace (probe) | `--config Recurring_P_StaleDefinition.cfg --stop-at-first` | probe violated, 8 states |
| F-6 trace (probe) | `--config Recurring_P_RuntimeTakenOver.cfg --stop-at-first` | probe violated, 3 states |
| F-7 trace (probe) | `--config Recurring_P_UnroutableBlocks.cfg --stop-at-first` | probe violated, 5 states |
| SCN-201, 203, 204, 206, 209 (legs `SCN209`, `SCN209b`), 210, 211 | `--config Recurring_SCNnnn.cfg --no-deadlock --stop-at-first` | every trap violated as expected (2–4 states): all reachable |

`Inv_NoOverlapProcessing` passes in the 2-slot cfgs only because F-1 needs three occurrences; with three slots it fails (F-1). Note also that `run_tlc.py`'s `--timeout` did not stop a TLC process on Windows during this run, so wrap long runs in `timeout 170`.

Probes (`Probe_…`) are modeling aids, not requirements: each one asserts that a situation is unreachable, and its violation is the example for a finding.

## Next
Apply the chosen options to `specs/recurring.json` with the `refiner-requirements` skill (it validates and diffs), then run `refiner-model` again. F-1, F-2 and F-7 all edit REQ-221–REQ-235, so decide them together. Findings whose fingerprint disappears are listed as resolved in the next report.
