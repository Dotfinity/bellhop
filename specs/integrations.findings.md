# Findings: Bellhop notifications, HTTP jobs, outbound HTTP and the outbox

<!-- refiner-findings v1 | module: integrations | specHash: 8d15657c8cd56fbaef557cb0f68bc07fc82d84921fd14b0a0ec8a1f2a945affe | run: 2026-11-06 | previous: model/integrations/previous.findings.md (run 2, specHash 3b92b190e27a) -->

**Run:** 2026-11-06 (run 3, from `model/integrations/handoff.json`: INV-412 added, REQ-434 modified, SCN-406 added, nothing impacted) · **Requirements file:** `specs/integrations.json` (specHash `8d15657c8cd5`) · **Models:** `model/integrations/IntegrationsAlerts.tla` (INV-412, SCN-406), `IntegrationsAlertEvents.tla` (new), `IntegrationsHttp.tla` (REQ-434); `IntegrationsNotifications.tla` and `IntegrationsOutbox.tla` byte-for-byte unchanged · **TLC:** 2.19, Java 25 · **Result:** 3 findings: 0 contradictions · 1 gap · 0 unprovable · 2 ambiguities · 0 modeling notes. All 3 run-2 findings are closed: F-14 and F-15 resolved, F-16 accepted by the owner.

Every property ran in its own TLC run with `--stop-at-first --workers 2`, and each run was killed after 170 s if it had not finished (none needed it). Deadlock checking was a separate `TypeInv`-only run wherever a deadlock would be a finding. No run threw a TLC exception, and no run timed out. `model/integrations/run_all.py` reruns everything (see *Reproduce*). The liveness traces below are the ones TLC printed. They are not always the shortest, so the prose keeps only the steps that matter.

| Configuration | What it checks | Result | Distinct states |
|---|---|---|---|
| `IntegrationsNotifications.cfg` | cooldown rules (INV-409, INV-410, REQ-433); cap 1 | not rerun: model unchanged and nothing in it is in the handoff. Run 2: INV-400 ✓, INV-407 ✓, deadlock ✓ | 176,927 (run 2) |
| `…_cap2.cfg` | cap 2, 4 delivery slots | not rerun (as above). Run 2: INV-400 ✓, INV-407 ✓, deadlock ✓ | 7,683,747 (run 2) |
| `…_SCN400.cfg` | SCN-400 reachable | not rerun (as above). Run 2: trap violated as expected ✓ | 30 (run 2) |
| `IntegrationsAlerts.cfg` (new) | lease + INV-412 (events found in the store, marked handled in the delivery's write) | INV-412 one delivery per event ✓, INV-412 every event alerted ✓, SCN-405 ✓ | 445 |
| `…_noInv412Replay.cfg` | counterfactual: INV-412 dropped, each node remembers what it handled | one delivery per event ✗ (7 steps), as expected: INV-412 carries this | 1,214 |
| `…_noInv412FromNow.cfg` | counterfactual: INV-412 dropped, a new holder starts from now | every event alerted ✗ (stuttering, 9 steps), as expected | 954 |
| `…_SCN404.cfg` | SCN-404 reachable | trap violated as expected ✓ (5 steps) | 13 |
| `…_SCN406.cfg` (new) | SCN-406 reachable, from its given | trap violated as expected ✓ (3 steps) | 19 |
| `IntegrationsAlertEvents.cfg` (new) | what the store records per event; rule exists from the start; a missed instant's only store trace is the last outcome | one delivery per event ✓, every dead-letter alerted ✓, **every missed instant alerted ✗ (stuttering, 7 steps)** | 91 |
| `…_missDurable.cfg` (new) | F-17 option 1: missed instants recorded in the store | all ✓ | 91 |
| `…_newRuleStoreStart.cfg` (new) | rule added later, catches up on the store | **no alert for an event before the rule ✗ (4 steps)**, others ✓ | 480 |
| `…_newRuleAdded.cfg` (new) | F-18 option 1: rule added later, starts at the store's present | all ✓ | 230 |
| `…_perJob.cfg` (new) | handled mark kept on the job; the job is dead-lettered twice | **every dead-letter alerted ✗ (stuttering, 6 steps)**, others ✓ | 78 |
| `IntegrationsHttp.cfg` | main | INV-401 ✓, INV-402 ✓, INV-403 ✓, INV-404 ✓, SCN-401 ✓, deadlock ✓, **redirect probe ✓ (was ✗)**; run-1 check `Chk_NoPayloadSecretAtAll` ✗ (4 steps, expected, accepted in INV-404's notes) | 5,392 |
| `…_wildcard.cfg` | private host allowed only through a wildcard | INV-401 ✓, INV-402 ✓, deadlock ✓ | 748 |
| `…_transport.cfg` | allowed host only, MaxRedirects 1 | INV-401 ✓, INV-403 ✓, redirect probe ✓ (added), deadlock ✓ | 2,313 |
| `…_SCN402.cfg` | SCN-402 reachable | trap violated as expected ✓ (5 steps) | 38 |
| `IntegrationsOutbox.cfg` | REQ-432 + REQ-435 + REQ-436, one crash, one lease pause | INV-406 ✓, LIV-400 ✓ | 199 |
| `…_noRetentionAssumption.cfg` | REQ-436 dropped | INV-406 ✗ (10 steps): the assumption carries the guarantee, as REQ-436 says | 68 |
| `…_operatorDelete.cfg` | an operator deletes the job in the crash window | INV-406 ✗ (9 steps): accepted (REQ-436 notes, run-2 F-16) | 64 |
| `…_operatorDeletePause.cfg` (new) | the same, with a lease pause instead of a crash | INV-406 ✗ (9 steps): same effect, see *Accepted* | 84 |
| `…_SCN403.cfg` | SCN-403 reachable | trap violated as expected ✓ (9 steps) | 58 |

## Changes since last run

| Finding | Status | Fingerprint |
|---|---|---|
| F-14 | resolved | contradiction · Probe_RedirectOneRule · INV-403,REQ-416,REQ-421,REQ-422,REQ-434 |
| F-15 | resolved | ambiguity · Chk_OneDeliveryPerEvent · INV-411,REQ-400,REQ-401,REQ-403,REQ-438 |
| F-16 | resolved | gap · Inv_OneJobPerRow/operatorDelete · INV-406,REQ-432,REQ-436,jobs.REQ-144 |
| F-17 | new | gap · Liv_MissedAlerted · INV-412,REQ-403,recurring.REQ-217,recurring.REQ-218,recurring.REQ-220,recurring.REQ-231 |
| F-18 | new | ambiguity · Chk_NoAlertForEventBeforeRule · INV-412,REQ-400,REQ-401,REQ-403,REQ-410 |
| F-19 | new | ambiguity · Liv_DeadLetterAlerted/perJob · INV-412,REQ-400,REQ-401,jobs.REQ-141,jobs.REQ-143 |

3 resolved, 3 new, 0 still open

How each run-2 finding was re-checked:

| Run 2 | Evidence in run 3 |
|---|---|
| F-14 (unfollowed redirect: retry or dead-letter) | REQ-434 no longer lists the redirect rules, so the model's `RedirectRefused` step is gone. `Probe_RedirectOneRule` (an unfollowed redirect has exactly one way on, as a response, and REQ-434 does not apply to it) now holds in `IntegrationsHttp.cfg` (5,392 states, MaxRedirects 0) and in `…_transport.cfg` (2,313 states, MaxRedirects 1, a redirect to another host or past the limit). The deadlock runs pass in all three HTTP cfgs, so no job is left stuck. |
| F-15 (edge events across a lease handover) | INV-412 is run 2's "storeCursor" reading. `Inv_OneDeliveryPerEvent` and `Liv_EventAlerted` hold in `IntegrationsAlerts.cfg` (445 states). SCN-406 is reachable (3 steps). Without INV-412, the two node-memory readings still fail (`…_noInv412Replay.cfg` duplicate, 7 steps; `…_noInv412FromNow.cfg` loss, 9 steps), so INV-412 is what carries the guarantee. INV-412 raises new questions about the events themselves: see F-17, F-18 and F-19. |
| F-16 (operator delete in the relay crash window) | Accepted in REQ-436's notes. The same 9-step trace still appears (`…_operatorDelete.cfg`), and it is now listed under *Accepted*, not as a finding. |

## Accepted (not findings)

- **Operator delete during a relay crash window** (REQ-436 notes, run-2 F-16). `IntegrationsOutbox_operatorDelete.cfg`, `Inv_OneJobPerRow` ✗, 9 steps: n2 takes the relay lease and enqueues job o1 (REQ-435, REQ-432); an operator deletes o1 (jobs REQ-144); n2 crashes before deleting the row; n1 takes the lease and enqueues o1 again. This is the path REQ-436's notes describe.
- **Same effect without a crash** (new probe, `IntegrationsOutbox_operatorDeletePause.cfg`, 9 steps): the relay that enqueued o1 is still running but misses its lease renewal (a long pause, A-11); n1 takes the lease and enqueues o1 again after the operator's delete. The window (at most LeaseDuration) and the consequence (one extra job, nothing lost) are the same as in the accepted case. Only the wording of the note differs: it says "has crashed". Not raised as a finding. If you want the note to be exact, write "has crashed or lost its relay lease".
- **INV-404 covers three headers and URL user info only** (run-1 F-10, accepted in INV-404's notes). `Chk_NoPayloadSecretAtAll` ✗, 4 steps, as before.

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-17 | gap | high | INV-412, REQ-403, recurring REQ-217, REQ-218, REQ-220, REQ-231 | INV-412 makes the alerts node find a missed occurrence in the job store, but nothing in the store records one for long, so a missed occurrence can go unalerted with no handover at all |
| F-18 | ambiguity | medium | INV-412, REQ-400, REQ-401, REQ-403, REQ-410 | A rule added or renamed after events happened: INV-412 lets it alert every once-only event still stored (up to 30 days of dead-letters), or none of them |
| F-19 | ambiguity | low | INV-412, REQ-400, REQ-401, jobs REQ-141, jobs REQ-143 | "An event that happens once": if the handled mark is kept on the job, a requeued job that is dead-lettered again, or reaches attempt N again, is never alerted |

---

## F-17 · gap · high — A missed occurrence has no lasting record in the job store, so INV-412 cannot find it
<!-- finding: gap | Liv_MissedAlerted | INV-412,REQ-403,recurring.REQ-217,recurring.REQ-218,recurring.REQ-220,recurring.REQ-231 -->

**Requirements involved**
- INV-412: *Where a rule watches an event that happens once: … or a recurring occurrence missed or late (REQ-403), the system shall **find those events from what the job store records** and mark each one handled for that rule in the same store write that creates its delivery …* Its notes: *"Events that happen while no node holds the lease, or while no alerts node runs at all, are alerted when a holder next runs."*
- REQ-403: *Where a rule watches recurring jobs, when a recurring job's occurrence is missed, starts later than the rule's tolerance after its due time, or has not started when the rule's tolerance after its due time has passed, the system shall create a delivery …* Its notes: *"Missed occurrences come from recurring REQ-220."*
- recurring REQ-220: *When a recurring job is triggered after one or more due instants were missed, the system shall log how the missed instants were handled and why, and raise the recurring-missed event.* jobs REQ-169 raises such events *"on the node that made the transition"*, in memory, after the store write.
- recurring REQ-218 (misfire Skip): *… create no occurrence for the missed instants … and advance nextRunAt to the next future occurrence.* REQ-217 (RunOnce, the default per REQ-201): *create a single occurrence for all missed instants …*
- recurring REQ-231: *When an occurrence's job succeeds, is dead-lettered or is cancelled, or an occurrence is skipped, the system shall record that outcome as the recurring job's last outcome.*

**What happens** (TLC, `Liv_MissedAlerted`, `IntegrationsAlertEvents.cfg`, 7 steps ending in stuttering; one alerts node holds the lease throughout, there is no handover)
1. Rule R watches recurring jobs (REQ-403), with a tolerance of 15 minutes. The hourly job `report` has misfire policy Skip.
2. `report` is due at 03:00. The workers are restarting, and the trigger runs at 03:10, more than MisfireThreshold (60 s, recurring REQ-234) late. So 03:00 is missed. Skip creates no occurrence and moves nextRunAt to 04:00 (REQ-218). The last outcome becomes "skipped" (REQ-231). The miss is logged and the recurring-missed event is raised in memory on the worker (REQ-220, jobs REQ-169). That worker is not the lease holder, and only the holder may create a delivery (INV-411).
3. The holder has not yet looked at R. No requirement says how soon after an event it must. In TLC's trace, the next step comes first; two dead-letters that also happen in the trace are alerted normally (REQ-400).
4. The 04:00 occurrence runs on time and succeeds. The last outcome becomes "succeeded" (REQ-231).
5. The holder now reads the store, as INV-412 requires. nextRunAt is 05:00 and the last outcome is "succeeded". **Nothing in the store says that 03:00 was missed, so the miss is never alerted.** The "has not started" branch of REQ-403 cannot catch it either: it reads the stored nextRunAt (REQ-403 notes), which moved past 03:00 at 03:10, before the 15-minute tolerance ran out.

With misfire **RunOnce, the default**, there is not even a "skipped" outcome. The trigger creates one ordinary occurrence for the missed instants (REQ-217), and no requirement records that the occurrence is a catch-up or which instants it covers. A miss that is detected between MisfireThreshold and the rule's tolerance therefore leaves no trace in the store at all, even when the holder never stops running.

With every missed instant recorded in the store (`…_missDurable.cfg`), every miss is alerted exactly once (91 states).

**Why** Before INV-412, REQ-403 got missed occurrences from REQ-220's in-memory event. INV-412 now requires the holder to find them in the store, but no recurring requirement writes them there. The last outcome is one field that the next outcome overwrites. It is enough only if the holder reads it before the next occurrence finishes, which is not the case for a job that runs every minute, or when no alerts node runs for one period. INV-412's notes promise to alert exactly those events when a holder comes back. Dead-letters and failed attempts do not have this problem, because the job's state history records each transition (jobs INV-116). A late start is also in the history, assuming the occurrence job keeps its due instant (`scheduledAt`).

**Options**
1. *(recommended)* **The trigger records the miss in the store.** A new recurring requirement: the same compare-and-set that advances nextRunAt (recurring REQ-216) also records the missed instants and how the misfire policy handled them, and that record is kept as long as a dead-lettered job (jobs REQ-104). INV-412 then finds it like any other event, and REQ-220's log line and in-memory event stay as they are. This is a recurring-module change.
2. **Drop the "missed" branch from INV-412 and rely on "has not started".** Missed occurrences are alerted only when the tolerance passes before the trigger runs. Misses caught by the trigger earlier than that are not alerted. Write this in REQ-403's notes. It is cheaper, but a rule with a long tolerance then reports almost no misses.
3. **Accept and document.** Missed-occurrence alerts are best effort: they are lost when the next occurrence finishes before the holder evaluates the rule, and always lost under RunOnce. This contradicts INV-412's notes, which would need to change.

**Ready to apply (option 1)** (in `recurring.json`; the next free id there is REQ-242)
```json
{ "id": "REQ-242", "kind": "invariant", "status": "proposed", "strength": "must", "entity": "RecurringJob",
  "ears": { "when": "a recurring job is triggered after one or more due instants were missed",
    "shall": "record the missed instants and how the misfire policy handled them in the job store, in the same compare-and-set that advances nextRunAt, and keep that record for RetentionDeadLettered" },
  "mentions": ["RecurringJob.nextRunAt", "RecurringJob.misfirePolicy"],
  "dependsOn": ["REQ-216", "REQ-217", "REQ-218", "REQ-219", "REQ-220"],
  "rationale": "integrations INV-412 makes the notification lease holder find missed occurrences in the job store; the last outcome (REQ-231) is overwritten by the next one, and RunOnce leaves no trace of a miss.",
  "notes": "refiner-model 2026-11-06 integrations run 3 F-17." }
```
and in `integrations.json`, REQ-403's notes: *"Missed occurrences are read from the store record of recurring REQ-242 (INV-412), not from REQ-220's in-memory event."*

---

## F-18 · ambiguity · medium — Where does a rule added after events happened start?
<!-- finding: ambiguity | Chk_NoAlertForEventBeforeRule | INV-412,REQ-400,REQ-401,REQ-403,REQ-410 -->

**Requirements involved**
- INV-412: *… shall find those events from what the job store records and mark each one handled **for that rule** in the same store write that creates its delivery …*
- REQ-400: *Where a rule watches dead-lettering, when a job is dead-lettered, the system shall create a delivery for that rule with the job as subject.* (REQ-401 and REQ-403 have the same shape.)
- REQ-410: *The system shall load rules from configuration and from code, use the code definition when a rule with the same name exists in both …* Rules are identified by name.
- jobs REQ-104: dead-lettered jobs are kept 30 days by default, and with them their state history.

**What happens** (TLC, `Chk_NoAlertForEventBeforeRule`, `IntegrationsAlertEvents_newRuleStoreStart.cfg`, 4 steps)
1. Job d1 is dead-lettered while no rule watches dead-lettering (jobs REQ-131). It stays in the store with its history (jobs INV-116, REQ-104).
2. A developer adds rule R, which watches dead-lettering, and deploys (REQ-410).
3. The lease holder evaluates R (INV-411). It finds d1 in the store, with no handled mark for R, so (INV-412) **it creates a delivery for d1, a dead-letter from before R existed.** On a real store, that means every dead-letter of the last 30 days: MaxDeliveriesPerCooldown alerts plus a digest naming the rest (INV-409, REQ-413, REQ-414). Renaming a rule has the same effect, because the new name has no marks.

The other reading, where a new rule's marks start at the store's present (`…_newRuleAdded.cfg`), never alerts an older event, and it still alerts every later one (230 states). Both readings fit INV-412's sentence. The where-clause of REQ-400 ("where a rule watches dead-lettering, when a job is dead-lettered") suggests the second, and INV-412's notes ("alerted when a holder next runs") suggest catching up. A catch-up flood on the first deploy and silence about old dead-letters are both possible, and the sentences do not say which one is intended.

A related point: during a rolling deploy the lease can move between a node that has R and a node that does not. If R's marks were dropped whenever a holder without R ran, R would start again from the present each time and skip the events in between.

**Options**
1. *(recommended)* **A rule starts at the store's present the first time its name is seen**, and its handled marks are kept by name from then on. Removing and re-adding a rule, or a rolling deploy, continues where it stopped. A renamed rule is a new rule. There is no flood on the first deploy, and no event is skipped once the rule exists.
2. **A new rule catches up on everything still stored.** Document that the first deploy of a rule, or a rename, alerts up to MaxDeliveriesPerCooldown old events plus a digest.
3. **Catch up a bounded window**, for example one rule cooldown back. This is a compromise, and it needs a number.

**Ready to apply (option 1)**
```json
{ "id": "INV-412", "notes": "refiner-model 2026-11-06 run 2 F-15 (recommended option; …existing text kept…). Run 3 F-18 (recommended option): a rule whose name is seen for the first time starts with every event already in the store marked handled; its marks are kept by rule name, so removing and re-adding the rule, or a rolling deploy in which the lease moves between nodes with and without it, continues where it stopped. A renamed rule is a new rule." }
```

---

## F-19 · ambiguity · low — "An event that happens once" is not once per job
<!-- finding: ambiguity | Liv_DeadLetterAlerted/perJob | INV-412,REQ-400,REQ-401,jobs.REQ-141,jobs.REQ-143 -->

**Requirements involved**
- INV-412: *Where a rule watches **an event that happens once**: a job dead-lettered (REQ-400), an attempt that makes the Nth failure (REQ-401) … shall … mark **each one** handled for that rule …* Its notes: *"How the store records events and the handled mark, for example a per-rule position in a store-assigned sequence of state changes, is an implementation choice."*
- jobs REQ-141: *When an operator requeues a dead-lettered job …, the system shall enqueue the job again with its attempt number reset to zero …* (REQ-143 does the same for succeeded and cancelled jobs, keeping their history.)
- REQ-401's notes: *"The count is the job's attempt number, so an operator requeue (jobs REQ-141) starts it again."*

**What happens** (TLC, `Liv_DeadLetterAlerted`, `IntegrationsAlertEvents_perJob.cfg`, 6 steps ending in stuttering, with the handled mark kept on the job)
1. Job j1 is dead-lettered (jobs REQ-131).
2. An operator requeues j1 (jobs REQ-141), and it is dead-lettered again.
3. The holder creates the delivery for the first dead-letter and marks j1 handled for R (INV-412).
4. **The second dead-letter is never alerted**, because j1 is already marked. REQ-400 asks for a delivery each time a job is dead-lettered. The same happens with REQ-401: after the requeue the count starts again (REQ-401 notes), the Nth failure happens a second time, and a mark on the job hides it.

With the mark kept per recorded state change (`IntegrationsAlertEvents.cfg`, the same two dead-letters of one job), both are alerted (91 states).

**Why** "Happens once" describes the kind of trigger (an edge, as opposed to the state-based REQ-402, REQ-404 and REQ-405), but read literally it says each job is dead-lettered once. A flag on the job row is the simplest way to "mark it handled in the same store write", and the notes leave the choice open. Severity is low because REQ-400 and REQ-401's notes point to the intended reading.

**Options**
1. *(recommended)* **Say what one event is.** Each recorded state change (a dead-letter transition, a failed attempt, a missed or late due instant) is its own event, so a requeued job can produce new ones. Reword INV-412's where-clause.
2. **One alert per job and kind, ever.** Keep the mark on the job, and document that a requeued job's later dead-letters and Nth failures are not alerted. This goes against REQ-401's notes.

**Ready to apply (option 1)**
```json
{ "id": "INV-412", "ears": {
    "where": "a rule watches an event that is a single recorded state change: a job dead-lettered (REQ-400), an attempt that makes the Nth failure (REQ-401), or a recurring occurrence missed or late (REQ-403); a job that is requeued (jobs REQ-141, REQ-143) can produce such an event again",
    "shall": "find those events from what the job store records and mark each one handled for that rule in the same store write that creates its delivery, so that a node that takes over the notification lease neither alerts an event again nor skips one" } }
```

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.

| # | Assumption | Affects |
|---|---|---|
| A-1 | REQ-400…REQ-406 are abstracted to "the rule fires for subject s" at any moment in the cooldown model. What they watch belongs to jobs, recurring and hosting. The alerts model makes two kinds explicit: edge events (REQ-400, REQ-401, REQ-403) and the state-based node-lost trigger (REQ-404, with NodeLostAfter from hosting REQ-60 as a nondeterministic "goes stale"). | REQ-400…REQ-406 |
| A-2 | Backoff has no clock: the next attempt may come at any later moment. | REQ-408, REQ-412 |
| A-3 | Cooldowns, NodeLostAfter, tolerance, MisfireThreshold and retention end as nondeterministic events. The model cannot judge durations: retry span vs cooldown, retention vs relay recovery (REQ-436), how soon the holder evaluates a rule vs how often a recurring job runs (F-17). | INV-400, INV-407, INV-410, REQ-414, REQ-436, F-17 |
| A-4 | Closed deliveries and finished HTTP jobs are archived and free their slot. | all |
| A-5 | A digest delivery has no subject and is not counted (INV-409's "non-digest"). When both the subject cooldown and the cap apply, the delivery is deduplicated, not capped (INV-409 notes). | INV-409, REQ-414 |
| A-6 | Job lifecycle around an HTTP call: claim, then retry while attempt < maxAttempts, else dead-letter (jobs REQ-123/129/131). Lease expiry, job timeouts (REQ-138) and cancellation are not modeled; the HTTP request timeout is one response outcome. A job may list a 3xx status as accepted. | REQ-421, REQ-422, REQ-434, SCN-402 |
| A-7 | INV-401/INV-402 ("never send", "refuse") act as guards on REQ-420, as SCN-401 expects; REQ-434 is the step taken instead. | REQ-420, INV-401, INV-402, REQ-434, SCN-401 |
| A-8 | "Attempts made" in REQ-408/REQ-415 includes the attempt just rejected, so total attempts = NotificationMaxAttempts (REQ-412). | REQ-408, REQ-415, REQ-433 |
| A-9 | In the cooldown model, delivery creation is serialised, which is what INV-411's fenced write gives. The lease itself is modeled in `IntegrationsAlerts.tla`. | INV-409, INV-411 |
| A-10 | At most one crash per behaviour (relay node, or alerts node). | LIV-400, REQ-435, REQ-438 |
| A-11 | At most one lease expiry under a running holder (a missed renewal, e.g. a long pause). An alerts node's later writes are fenced (INV-411). The relay's row delete is not fenced (REQ-432 does not say), but it is idempotent. | REQ-432, REQ-435, REQ-438, INV-412 |
| A-12 | A crashed node is restarted by its host (fair) as a new instance that does not inherit its old lease. The old lease must expire first. | REQ-438, INV-412 |
| A-13 | REQ-436 is encoded as a guard: retention never removes a job while the outbox row it came from is still pending. `…_noRetentionAssumption.cfg` shows the guarantee depends on it. | REQ-436, INV-406 |
| A-14 | Bounds: 1 rule, 2 subjects, 3 delivery slots (4 in `…_cap2`), NotificationMaxAttempts 2, MaxDeliveriesPerCooldown 1 (2 in `…_cap2`). 2 alerts nodes, 2 edge events. 2 dead-letters and 2 due instants of one recurring job in `IntegrationsAlertEvents`. 1 HTTP job, up to 3 hosts, maxAttempts 2, MaxRedirects 0 (1 in `…_transport`). 1 outbox row, 2 worker nodes. | all |
| A-15 | `IntegrationsAlertEvents` has one alerts node holding the lease throughout. Handovers are covered by `IntegrationsAlerts`, and F-17 needs none. Rule evaluation is fair (it happens if it stays possible) but has no deadline. | INV-411, INV-412, F-17 |
| A-16 | Dead-letters and failed attempts are found through the job's state history (jobs INV-116). A late start is findable if the occurrence job keeps its due instant (`scheduledAt`), so it is not modeled. Missed instants are modeled for misfire Skip, whose only stored trace is the last outcome (REQ-231). RunOnce leaves less, see F-17. | INV-412, REQ-403, F-17 |
| A-17 | A rule is identified by its name (REQ-410). "Rule added" is one nondeterministic event, not fair. Removal and rolling deploys are not modeled, only described in F-18. | F-18 |
| A-18 | In `IntegrationsAlertEvents` a requeue (jobs REQ-141) is folded into the second dead-letter of the same job. Retention (jobs REQ-145) and operator deletes are not modeled; INV-412's notes accept that a removed job is no longer alerted. | F-19, INV-412 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-400…REQ-409, REQ-412…REQ-416, INV-400, INV-407, INV-409, INV-410, INV-411, INV-412, REQ-433, REQ-438 · REQ-420…REQ-422, REQ-434, INV-401…INV-404, INV-408 · REQ-430, REQ-432, REQ-435, REQ-436, INV-406, LIV-400 · SCN-400, SCN-402, SCN-403, SCN-404, SCN-406 (reachable), SCN-401, SCN-405 (hold) | REQ-410 (static merge of rule definitions and a page listing, no state change; its rule identity by name is used as A-17) · INV-405 (masking in the dashboard and logs is presentation) · REQ-431, REQ-437 (which enqueue path a configuration takes; no interleaving to explore) · REQ-411 (retired, moved to hosting REQ-60) |

Owner open questions already recorded, and not raised again here: no warning when rules exist but no node has the alerts registration, refused webhook hosts, and a test delivery left pending when no alerts node exists. The run-2 question about events while no alerts node runs is answered by INV-412's notes; F-17 shows that missed occurrences are the exception.

## Reproduce
From `specs/model/integrations/`: `python -X utf8 run_all.py` reruns every check (or `run_all.py IntegrationsAlertEvents` for one model). Each check runs alone as `python run_tlc.py <Module>.tla --config <cfg with one INVARIANT or PROPERTY> --workers 2 --stop-at-first --no-deadlock`, killed after 170 s, plus a `TypeInv`-only run with deadlock checking for the HTTP and notification cfgs. Results land in `runs/` (gitignored), with a summary in `runs/summary.md`. Set `RUN_TLC` if `run_tlc.py` is not under `~/.claude-personal/skills/refiner-model/scripts/`.

## Next
Apply the chosen options to `integrations.json` (and, for F-17 option 1, `recurring.json`) with the `refiner-requirements` skill (it validates and diffs), then run this skill again.
