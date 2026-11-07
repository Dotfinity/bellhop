# Findings: Bellhop notifications, HTTP jobs, outbound HTTP and the outbox

<!-- refiner-findings v1 | module: integrations | specHash: 138efb1f8daa4ba9b02b768d3a815d1b75a018522437d5962b545f588738c03f | run: 2026-11-07 | previous: model/integrations/previous.findings.md (run 3, specHash 8d15657c8cd5) -->

**Run:** 2026-11-07 (run 4, from `model/integrations/handoff.json`: INV-412 modified, INV-413 added, NotificationRule modified (`name`), REQ-403 modified (mentions recurring `missedInstants`); 14 items impacted through NotificationRule) · **Requirements file:** `specs/integrations.json` (specHash `138efb1f8daa`) · **Models:** `model/integrations/IntegrationsAlertEvents.tla` (INV-412, INV-413, recurring REQ-242; regenerated), `IntegrationsAlerts.tla` (INV-413 and the store writes of INV-412/INV-413 across a lease handover; extended); `IntegrationsNotifications.tla`, `IntegrationsHttp.tla` and `IntegrationsOutbox.tla` byte-for-byte unchanged, rerun for the impacted items · **TLC:** 2.19, Java 25 · **Result:** 3 findings: 0 contradictions · 1 gap · 0 unprovable · 2 ambiguities · 0 modeling notes. All 3 run-3 findings are resolved.

Every property ran in its own TLC run with `--stop-at-first --workers 2`, and each run was killed after 170 s if it had not finished. Deadlock checking was a separate `TypeInv`-only run wherever a deadlock would be a finding. No run threw a TLC exception. `model/integrations/run_all.py` reruns everything (see *Reproduce*). The prose keeps only the steps of each trace that matter.

| Configuration | What it checks | Result | Distinct states |
|---|---|---|---|
| `IntegrationsAlertEvents.cfg` (regenerated) | as written: INV-412 per recorded change, INV-413 by name, REQ-242 miss records; one job dead-lettered, requeued and dead-lettered again; two missed instants | one delivery per event ✓, every dead-letter alerted ✓, **every missed instant alerted ✓ (was ✗)**, no alert for an event before the rule ✓ | 230 |
| `…_noReq242.cfg` (new) | counterfactual: REQ-242 dropped, only the last outcome | every missed instant alerted ✗ (stuttering, 6 steps), as expected: REQ-242 carries this | 241 |
| `…_perJob.cfg` | counterfactual: handled mark on the job | every dead-letter alerted ✗ (stuttering, 6 steps), as expected: INV-412's where-clause rules this out | 192 |
| `…_newRule.cfg` (replaces `…_newRuleAdded`) | INV-413: rule added after events happened | all ✓ | 509 |
| `…_noInv413.cfg` (replaces `…_newRuleStoreStart`) | counterfactual: INV-413 dropped | no alert for an event before the rule ✗ (5 steps), as expected | 1,488 |
| `…_readd.cfg` (new) | rule removed and added back, marks kept by name (INV-413 notes) | one delivery ✓, both liveness ✓; no alert for an event while removed ✗ (7 steps): accepted, see *Accepted* | 2,112 |
| `…_editTrigger.cfg` (new) | rule's trigger edited, name kept | **no alert for an event before the rule watched it ✗ (5 steps)**: F-22 | 931 |
| `…_editTriggerKeyed.cfg` (new) | F-22 option 1: INV-413 keyed by name and trigger settings | all ✓ | 1,240 |
| `…_newSystem.cfg` (new) | rule in code from the start, store records no rule name yet | one delivery ✓; **every event while the rule is configured alerted ✗ (stuttering, 7 steps)**: F-21 | 230 |
| `…_newSystemCatchUp.cfg` (new) | F-21 option 2: a store with no rule names starts every rule at the beginning | all ✓ | 480 |
| `IntegrationsAlerts.cfg` | lease + INV-412, rule already recorded, every write one step | INV-412 one delivery per event ✓, every event alerted ✓, SCN-405 ✓ | 445 |
| `…_newRule.cfg` (new) | INV-413 across a handover, every write one conditional step | all ✓ | 984 |
| `…_newRuleLiteral.cfg` (new) | INV-413's write as written: read, then an unchecked write | one delivery ✓, SCN-405 ✓, **every event after the rule's start alerted ✗ (stuttering, 12 steps)**: F-20 | 1,887 |
| `…_newRuleFenced.cfg` (new) | F-20 option 3: INV-413's write checks the lease only | one delivery ✓, SCN-405 ✓, **every event alerted ✗ (stuttering, 14 steps)** | 1,700 |
| `…_staleWrite.cfg` (new) | INV-412's write as written: read, then a write that checks the lease only | **one delivery per event ✗ (12 steps)**: F-20; every event alerted ✓, SCN-405 ✓ | 1,029 |
| `…_noInv412Replay.cfg` | counterfactual: INV-412 dropped, node memory replays | one delivery per event ✗ (7 steps), as expected | 1,214 |
| `…_noInv412FromNow.cfg` | counterfactual: INV-412 dropped, node memory from now | every event alerted ✗ (stuttering, 8 steps), as expected | 954 |
| `…_SCN404.cfg` | SCN-404 reachable | trap violated as expected ✓ (5 steps) | 13 |
| `…_SCN406.cfg` | SCN-406 reachable, from its given | trap violated as expected ✓ (3 steps) | 21 |
| `IntegrationsNotifications.cfg` | cooldown rules (INV-409, INV-410, REQ-433); cap 1; rerun for the items impacted through NotificationRule | INV-400 ✓, INV-407 ✓, failed-then-silent probe ✓, deadlock ✓ (unchanged) | 176,927 |
| `…_cap2.cfg` | cap 2, 4 delivery slots; rerun | INV-400 ✓, INV-407 ✓, deadlock ✓ (unchanged) | 7,683,747 |
| `…_SCN400.cfg` | SCN-400 reachable; rerun | trap violated as expected ✓ (4 steps) | 22 |
| `IntegrationsHttp.cfg` | main; regression rerun, model unchanged | INV-401 ✓, INV-402 ✓, INV-403 ✓, INV-404 ✓, SCN-401 ✓, redirect probe ✓, deadlock ✓; `Chk_NoPayloadSecretAtAll` ✗ (4 steps, accepted) | 5,392 |
| `…_wildcard.cfg` / `…_transport.cfg` / `…_SCN402.cfg` | regression rerun | all as in run 3 ✓; SCN-402 trap violated as expected (5 steps) | 748 / 2,313 / 41 |
| `IntegrationsOutbox.cfg` and its four variants | regression rerun, model unchanged | INV-406 ✓, LIV-400 ✓; `…_noRetentionAssumption` ✗ (10 steps, expected), `…_operatorDelete` and `…_operatorDeletePause` ✗ (9 steps each, accepted); SCN-403 trap violated as expected (9 steps) | 199 / 68 / 66 / 89 / 57 |

## Changes since last run

| Finding | Status | Fingerprint |
|---|---|---|
| F-17 | resolved | gap · Liv_MissedAlerted · INV-412,REQ-403,recurring.REQ-217,recurring.REQ-218,recurring.REQ-220,recurring.REQ-231 |
| F-18 | resolved | ambiguity · Chk_NoAlertForEventBeforeRule · INV-412,REQ-400,REQ-401,REQ-403,REQ-410 |
| F-19 | resolved | ambiguity · Liv_DeadLetterAlerted/perJob · INV-412,REQ-400,REQ-401,jobs.REQ-141,jobs.REQ-143 |
| F-20 | new | gap · Liv_EventAlerted/newRuleLiteral · INV-411,INV-412,INV-413,REQ-438 |
| F-21 | new | ambiguity · Chk_ConfiguredEventAlerted/newSystem · INV-412,INV-413 |
| F-22 | new | ambiguity · Chk_NoAlertForEventBeforeRule/editTrigger · INV-412,INV-413,REQ-401,REQ-403,REQ-410 |

3 resolved, 3 new, 0 still open

How each run-3 finding was re-checked:

| Run 3 | Evidence in run 4 |
|---|---|
| F-17 (a missed occurrence has no lasting record) | Recurring REQ-242 writes one record per trigger in the compare-and-set that advances nextRunAt. `Liv_MissedAlerted` now holds in the main `IntegrationsAlertEvents.cfg` (230 states), with no handover and the next occurrence finishing before the holder looks. With REQ-242 dropped it fails again (`…_noReq242.cfg`, 6 steps). Across restarts and lease handovers, a REQ-242 record is one more event "the job store records", which is what `IntegrationsAlerts.cfg` checks: one delivery per event and every event alerted, with a crash, a restart and a lease lapse under a running holder (445 states). |
| F-18 (where a rule added later starts) | INV-413. A rule added after events happened alerts none of them and every later one (`IntegrationsAlertEvents_newRule.cfg`, 509 states; across a handover, `IntegrationsAlerts_newRule.cfg`, 984 states, with each write one conditional step). Without INV-413 the old flood comes back (`…_noInv413.cfg`, 5 steps). Three edges of the new sentence are F-20, F-21 and F-22. |
| F-19 (what one event is) | INV-412's where-clause. A job dead-lettered, requeued and dead-lettered again gets two deliveries, one per dead-letter (`IntegrationsAlertEvents.cfg`, 230 states). Keeping the mark on the job fails again (`…_perJob.cfg`, 6 steps). Duplicates are bounded as the notes say: `Inv_OneDeliveryPerEvent` holds per recorded change, so a job gets at most one delivery per rule per time it is dead-lettered, which is 1 plus the number of operator requeues. |

## Accepted (not findings)

- **Removing and re-adding a rule alerts what happened while it was away** (INV-413 notes: "continues where it stopped and skips nothing"). `IntegrationsAlertEvents_readd.cfg`, `Chk_NoAlertForEventBeforeRule` ✗, 7 steps: d1 is dead-lettered; the holder first sees R and marks d1 (INV-413); R is removed (or the lease moves to a node of the previous version during a rolling deploy); d2 is dead-lettered; R comes back and d2 is alerted. This is what the notes ask for. The consequence to be aware of: a rule that is removed for weeks and then restored alerts the stored backlog of that period, capped by MaxDeliveriesPerCooldown plus a digest (INV-409, REQ-414). Both liveness properties hold (2,112 states).
- **A renamed rule is a new rule** (INV-413 notes). It is a removal plus an addition, so it starts the first time the holder sees the new name (`…_newRule.cfg`). Events between the last evaluation under the old name and the first under the new one are alerted by neither.
- **Operator delete during a relay crash window** (REQ-436 notes, run-2 F-16), and the same effect with a lease pause instead of a crash. `IntegrationsOutbox_operatorDelete.cfg` and `…_operatorDeletePause.cfg`, `Inv_OneJobPerRow` ✗, 9 steps each, unchanged.
- **INV-404 covers three headers and URL user info only** (run-1 F-10). `Chk_NoPayloadSecretAtAll` ✗, 4 steps, unchanged.

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-20 | gap | high | INV-411, INV-412, INV-413, REQ-438 | A holder whose lease lapsed between reading and writing can still land its write: INV-413's write checks nothing and skips an event; INV-412's write checks only that the node holds the lease, and a node that took it back alerts an event twice |
| F-21 | ambiguity | medium | INV-412, INV-413 | A rule starts at its first evaluation, not when it is configured: on a new system, events before the first alerts node takes the lease are never alerted, although INV-412's notes promise they are |
| F-22 | ambiguity | medium | INV-412, INV-413, REQ-410, REQ-401, REQ-403 | INV-413 knows a rule by name only, so editing its trigger, threshold or tolerance alerts every stored event that now matches: the flood INV-413 was written to prevent |

---

## F-20 · gap · high — A write decided before the lease lapsed still lands
<!-- finding: gap | Liv_EventAlerted/newRuleLiteral | INV-411,INV-412,INV-413,REQ-438 -->

**Requirements involved**
- INV-411: *The system shall evaluate notification rules, create their deliveries and send deliveries only on a running node that has the alerts registration and holds the notification lease, **checking the lease in the same store write that creates or updates the delivery**.*
- INV-412: *… the system shall find those events from what the job store records and mark each one handled for that rule in the same store write that creates its delivery, so that a node that takes over the notification lease **neither alerts an event again nor skips one**.*
- INV-413: *… when the notification lease holder evaluates a rule whose name the job store has no record of, the system shall record the rule's name in the store and mark every such event the store already records as handled for that rule, without creating deliveries for them.*
- REQ-438: the lease is taken for LeaseDuration and renewed every HeartbeatInterval.

**What happens**

*INV-413's write* (TLC, `Liv_EventAlerted`, `IntegrationsAlerts_newRuleLiteral.cfg`, 12 steps ending in stuttering). Rule R has just been deployed, and the store has no record of it.
1. a1 takes the notification lease (REQ-438). It evaluates R and finds no record of its name (INV-413), and starts its write.
2. Job d2 is dead-lettered. It happened before R's start, so it is not owed an alert.
3. a1 stalls (a long GC pause) past LeaseDuration. Its lease lapses, and a2 takes it (REQ-438).
4. a2 evaluates R, finds no record either, and starts its own INV-413 write.
5. a1 wakes up and its write lands: R is recorded, d2 is marked handled. INV-411 checks the lease only in writes that create or update a delivery, and this write creates none.
6. Job d1 is dead-lettered. R is now recorded, so d1 is owed an alert (INV-412).
7. a2's write lands: it marks every event the store records as handled, now including d1. **d1 is never alerted**, and a2 still holds the lease the whole time.

Checking the lease in INV-413's write is not enough (`…_newRuleFenced.cfg`, 14 steps). a1 reads "no record" and stalls. a2 takes the lease and records R, and then d1 is dead-lettered. a2 crashes and its lease expires. a1 is still running, so it takes the lease back, and its old write now passes the lease check and marks d1.

*INV-412's write* (TLC, `Inv_OneDeliveryPerEvent`, `IntegrationsAlerts_staleWrite.cfg`, 12 steps). R is long established.
1. d1 is dead-lettered. a1 holds the lease, finds d1 unhandled for R, and starts the write that creates its delivery.
2. a1 stalls past LeaseDuration, and a2 takes the lease. a2 finds d1 unhandled, creates its delivery and marks it handled (INV-412).
3. a2 crashes and its lease expires. a1 takes the lease back (REQ-438).
4. a1's write lands. It checks the lease, as INV-411 requires, and a1 does hold it again. **d1 gets a second delivery.**

When every write succeeds only if what it read still holds, everything passes (`IntegrationsAlerts.cfg`, 445 states; `…_newRule.cfg`, 984 states).

**Why** INV-411's fence answers "does this node hold the lease now?". The question that matters is "is what this node read still true?". The two differ for a write that was decided before a lease lapse and lands after it, either because no one took the lease from the node or because the node took it back. INV-413's write is not covered by the fence at all. The jobs and recurring modules already answer the same question with a compare-and-set on the value that was read (recurring REQ-216 on nextRunAt). The notification writes are the only store writes in these modules that act on an earlier read without one. Severity is high because a reachable state breaks INV-412, a `must`. The window is narrow: a pause longer than LeaseDuration, during a new rule's first evaluation or an event's delivery.

**Options**
1. *(recommended)* **Make both writes conditional on what they read.** INV-412's write creates the delivery only if the event is still not marked handled for the rule. INV-413's write records the name only if the store still has no record of it, and it checks the lease like the other notification writes. A write that fails because the state moved on is dropped, and the next evaluation reads again. This uses the existing compare-and-set pattern and needs no new concept.
2. **Fence with the lease term.** Every notification write carries the lease term it read under, and fails if the lease has been taken since, even by the same node. This fixes both traces, but it adds a term number to the notification lease, which no other lease in Bellhop has (REQ-435 relay, jobs REQ-164 cleanup).
3. **Extend INV-411's lease check to INV-413's write only.** This is not enough: `…_newRuleFenced.cfg` still loses d1 (14 steps), and the INV-412 duplicate remains.

**Ready to apply (option 1)**
```json
{ "id": "INV-412", "ears": {
    "where": "a rule watches an event that is a single recorded state change: a job dead-lettered (REQ-400), an attempt that makes the Nth failure (REQ-401), or a recurring occurrence missed or late (REQ-403); a job that is requeued (jobs REQ-141, REQ-143) can produce such an event again",
    "shall": "find those events from what the job store records and, for each one, create its delivery and mark it handled for that rule in one store write that succeeds only if the event is not yet marked handled for that rule, so that a node that takes over the notification lease neither alerts an event again nor skips one" },
  "notes": "…existing text kept… refiner-model 2026-11-07 run 4 F-20 (recommended option): the write is conditional on what was read, as recurring REQ-216's compare-and-set is, because INV-411's lease check passes for a node that took the lease back after a pause." }
{ "id": "INV-413", "ears": {
    "where": "a rule watches an event that is a single recorded state change (INV-412)",
    "when": "the notification lease holder evaluates a rule whose name the job store has no record of",
    "shall": "in one store write that checks the notification lease and succeeds only if the store still has no record of the name, record the rule's name and mark every such event the store records as handled for that rule, without creating deliveries for them" } }
```

---

## F-21 · ambiguity · medium — A rule starts at its first evaluation, so a new system can swallow its first events
<!-- finding: ambiguity | Chk_ConfiguredEventAlerted/newSystem | INV-412,INV-413 -->

**Requirements involved**
- INV-413: *… when the notification lease holder evaluates a rule whose name the job store has no record of, the system shall record the rule's name in the store and mark every such event the store already records as handled for that rule, without creating deliveries for them.* Its notes: *"a rule starts at the store's present the first time its name is seen."*
- INV-412's notes: *"Events that happen while no node holds the lease, **or while no alerts node runs at all, are alerted when a holder next runs**."*

**What happens** (TLC, `Chk_ConfiguredEventAlerted`, `IntegrationsAlertEvents_newSystem.cfg`, 7 steps ending in stuttering)
1. A new Bellhop system is deployed with rule R in code (REQ-410). The store has no rule names yet.
2. Job d1 is dead-lettered, and recurring job `report` misses an instant (recurring REQ-242 records it). No alerts node holds the notification lease yet. For example, the only alerts node is the dashboard host, which is deployed an hour after the workers.
3. The alerts node starts, takes the lease and evaluates R for the first time. The store has no record of R, so INV-413 marks d1 and the miss record as handled, with no delivery.
4. **d1 and the missed instant are never alerted**, although R was configured when they happened. Later events (d2) are alerted normally.

**Why** INV-413 places a rule's start at its first evaluation by a lease holder, which is the only moment the store can see. Its notes and rationale are about rules added to a running system, where starting at the present avoids a flood. On a system whose rules have been there from the start, the same sentence drops whatever happened before the first alerts node ran. That is exactly the case INV-412's notes say is alerted. Both sentences can be read as governing it. For a rule added to a running system, events between its deploy and its first evaluation are dropped the same way. That follows from the notes ("the first time its name is seen") and is not counted here.

**Options**
1. *(recommended)* **Accept it and say so.** A rule starts at its first evaluation by a lease holder. On a new system that is normally within one HeartbeatInterval of the first alerts node starting, and only an alerts node that starts later than the workers leaves a gap. Correct INV-412's notes so they do not promise more, and add the case to INV-413's notes. Nothing new to build.
2. **A store with no rule names starts every rule at the beginning.** The first evaluation on a store that records no rule name at all marks nothing, so everything still stored is alerted. Later rules start at the present. Model-checked: `…_newSystemCatchUp.cfg`, all ✓ (480 states). The cost is that the first upgrade of an existing installation to a version with notification rules also has no rule names. It then alerts the stored backlog once: up to 30 days of dead-letters (jobs REQ-104), capped by MaxDeliveriesPerCooldown plus a digest (INV-409, REQ-414).
3. **Record rule names when any node starts**, not only when the lease holder evaluates them, so a rule starts at its deploy. This moves the start close to the deploy, but it gives workers and clients a notification write that INV-411 keeps on alerts nodes. Not model-checked.

**Ready to apply (option 1)**
```json
{ "id": "INV-412", "notes": "…replace \"Events that happen while no node holds the lease, or while no alerts node runs at all, are alerted when a holder next runs\" with: Events that happen while no node holds the lease, or while no alerts node runs at all, are alerted when a holder next runs, for rules the store already records; events before a rule's first evaluation are not (INV-413)…" }
{ "id": "INV-413", "notes": "…existing text kept… refiner-model 2026-11-07 run 4 F-21 (recommended option): the start is the first evaluation by a lease holder, not the deploy. On a new system, events before the first alerts node takes the notification lease are not alerted; run the alerts registration with the first deployment to avoid the gap." }
```

---

## F-22 · ambiguity · medium — Editing a rule's trigger keeps its name and alerts the stored backlog
<!-- finding: ambiguity | Chk_NoAlertForEventBeforeRule/editTrigger | INV-412,INV-413,REQ-410,REQ-401,REQ-403 -->

**Requirements involved**
- INV-413: *… when the notification lease holder evaluates a rule **whose name** the job store has no record of …* Its rationale: *"Without it, deploying a new rule alerts every once-only event still stored, up to 30 days of dead-letters (jobs REQ-104) …"*. Its notes: *"A renamed rule is a new rule."*
- REQ-410: rules are identified by name, and the code definition wins.
- REQ-401: *Where a rule watches repeated failures with threshold N …*. REQ-403: *… starts later than the rule's tolerance after its due time …*. NotificationRule has a `trigger`, a `threshold` and a `tolerance`.

**What happens** (TLC, `Chk_NoAlertForEventBeforeRule`, `IntegrationsAlertEvents_editTrigger.cfg`, 5 steps)
1. Rule R watches dead-lettering. The holder has evaluated it, so the store records R's name (INV-413).
2. Recurring job `report` misses an instant (recurring REQ-242). R does not watch recurring jobs, so this is not R's event.
3. A developer changes R's trigger to recurring jobs and keeps the name `ops-alerts` (REQ-410), then deploys.
4. The holder evaluates R. The store has a record of the name, so INV-413 does not apply. INV-412 finds a stored miss record that is not marked handled for R. **It alerts the miss from before the edit**, and on a real store every miss record of the last RetentionDeadLettered.

The same happens without a trigger change. Lowering REQ-401's threshold from 5 to 3 makes every job in the store whose attempt 3 failed a new, unmarked event. Lowering REQ-403's tolerance makes old late starts late. When INV-413 knows a rule by its name and the settings that decide its events, the edited rule starts at the store's present like a renamed one (`…_editTriggerKeyed.cfg`, all ✓, 1,240 states).

**Why** INV-413 was written to stop a new rule from alerting the stored backlog. A rule whose trigger, threshold or tolerance changes watches a new set of events, but under the same name, so the backlog comes back through an edit. Both readings fit "a rule whose name …": the edited rule as the old rule (catch up) or as a new one (start now). The notes settle renames but not edits.

**Options**
1. *(recommended)* **Know a rule by its name and the settings that decide its events** (trigger, threshold, tolerance). An edit to any of them starts the rule again at the store's present, as a rename does. Changing the channel, template or cooldown does not. It is one phrase in INV-413's when-clause, and the behaviour matches the rename rule already in the notes.
2. **Accept the catch-up and document it.** An edited trigger, a lower threshold or a lower tolerance alerts the matching stored events once, capped by MaxDeliveriesPerCooldown plus a digest (INV-409, REQ-414).

**Ready to apply (option 1)**
```json
{ "id": "INV-413", "ears": {
    "where": "a rule watches an event that is a single recorded state change (INV-412)",
    "when": "the notification lease holder evaluates a rule whose name, trigger, threshold and tolerance together the job store has no record of",
    "shall": "in one store write that checks the notification lease and succeeds only if the store still has no record of them, record the rule's name, trigger, threshold and tolerance in the store and mark every such event the store records as handled for that rule, without creating deliveries for them" },
  "mentions": ["NotificationRule.name", "NotificationRule.trigger", "NotificationRule.threshold", "NotificationRule.tolerance", "Delivery.rule"],
  "notes": "…existing text kept… refiner-model 2026-11-07 run 4 F-22 (recommended option): a rule whose trigger, threshold or tolerance is edited is a new rule, like a renamed one; changing its channel, template or cooldown is not." }
```
(This snippet already includes F-20 option 1's write condition. If F-20 is decided differently, keep only the when-clause and the mentions.)

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.

| # | Assumption | Affects |
|---|---|---|
| A-1 | REQ-400…REQ-406 are abstracted to "the rule fires for subject s" at any moment in the cooldown model. What they watch belongs to jobs, recurring and hosting. The alerts model makes two kinds explicit: edge events (REQ-400, REQ-401, REQ-403) and the state-based node-lost trigger (REQ-404, with NodeLostAfter from hosting REQ-60 as a nondeterministic "goes stale"). | REQ-400…REQ-406 |
| A-2 | Backoff has no clock: the next attempt may come at any later moment. | REQ-408, REQ-412 |
| A-3 | Cooldowns, NodeLostAfter, tolerance, MisfireThreshold, retention and LeaseDuration end as nondeterministic events. The model cannot judge durations: retry span vs cooldown, retention vs relay recovery (REQ-436), how long a pause must be to let a stale write land (F-20). | INV-400, INV-407, INV-410, REQ-414, REQ-436, F-20 |
| A-4 | Closed deliveries and finished HTTP jobs are archived and free their slot. | all |
| A-5 | A digest delivery has no subject and is not counted (INV-409's "non-digest"). When both the subject cooldown and the cap apply, the delivery is deduplicated, not capped (INV-409 notes). | INV-409, REQ-414 |
| A-6 | Job lifecycle around an HTTP call: claim, then retry while attempt < maxAttempts, else dead-letter (jobs REQ-123/129/131). Lease expiry, job timeouts (REQ-138) and cancellation are not modeled; the HTTP request timeout is one response outcome. A job may list a 3xx status as accepted. | REQ-421, REQ-422, REQ-434, SCN-402 |
| A-7 | INV-401/INV-402 ("never send", "refuse") act as guards on REQ-420, as SCN-401 expects; REQ-434 is the step taken instead. | REQ-420, INV-401, INV-402, REQ-434, SCN-401 |
| A-8 | "Attempts made" in REQ-408/REQ-415 includes the attempt just rejected, so total attempts = NotificationMaxAttempts (REQ-412). | REQ-408, REQ-415, REQ-433 |
| A-9 | In the cooldown model, delivery creation is serialised, which is what INV-411's fenced write gives. The lease itself is modeled in `IntegrationsAlerts.tla`. | INV-409, INV-411 |
| A-10 | At most one crash per behaviour (relay node, or alerts node). | LIV-400, REQ-435, REQ-438 |
| A-11 | At most one lease expiry under a running holder (a missed renewal, e.g. a long pause). An alerts node's delivery writes check the lease (INV-411). The relay's row delete is not fenced (REQ-432 does not say), but it is idempotent. | REQ-432, REQ-435, REQ-438, INV-412, F-20 |
| A-12 | A crashed node is restarted by its host (fair) as a new instance that does not inherit its old lease. The old lease must expire first. A paused node that is still running may take the lease again once it is free. | REQ-438, INV-412, F-20 |
| A-13 | REQ-436 is encoded as a guard: retention never removes a job while the outbox row it came from is still pending. `…_noRetentionAssumption.cfg` shows the guarantee depends on it. | REQ-436, INV-406 |
| A-14 | Bounds: 1 rule, 2 subjects, 3 delivery slots (4 in `…_cap2`), NotificationMaxAttempts 2, MaxDeliveriesPerCooldown 1 (2 in `…_cap2`). 2 alerts nodes, 2 edge events. 2 dead-letters and 2 triggers of one recurring job in `IntegrationsAlertEvents`, up to 2 configuration changes. 1 HTTP job, up to 3 hosts, maxAttempts 2, MaxRedirects 0 (1 in `…_transport`). 1 outbox row, 2 worker nodes. | all |
| A-15 | `IntegrationsAlertEvents` has one alerts node holding the lease throughout, and each store write is one step. Handovers and writes split into a read and a later write are in `IntegrationsAlerts` (F-20). Rule evaluation, including INV-413's first evaluation, is fair (it happens if it stays possible) but has no deadline. | INV-411, INV-412, INV-413 |
| A-16 | Dead-letters and failed attempts are found through the job's state history (jobs INV-116). A late start is findable if the occurrence job keeps its due instant (`scheduledAt`), so it is not modeled. A missed instant is found through recurring REQ-242's record, one per trigger. | INV-412, REQ-403 |
| A-17 | A rule is identified by its name (REQ-410, INV-413). Adding, removing and editing a rule are nondeterministic events, not fair, except in `…_readd.cfg`, where the re-add is fair so that "continues where it stopped" can be checked. A rolling deploy that moves the lease between nodes with and without the rule is the same as a removal and a re-add. | INV-413, F-21, F-22 |
| A-18 | In `IntegrationsAlertEvents` a requeue (jobs REQ-141) is folded into the second dead-letter of the same job. Retention (jobs REQ-145) and operator deletes are not modeled; INV-412's notes accept that a removed job is no longer alerted. | INV-412 |
| A-19 | In `IntegrationsAlertEvents` one rule stands for a rule per event kind (it watches dead-letters and missed occurrences, `InitialWatch`), except in the edit cfgs, where it watches one kind and the edit switches it. INV-413 marks every stored event of every kind ("every such event"). | INV-413, F-22 |
| A-20 | One REQ-242 record (one trigger, however many instants it missed) is one event for INV-412, so one delivery. REQ-403 says "when a recurring job's occurrence is missed"; the subject is the recurring job either way, so the subject cooldown would merge per-instant deliveries. | REQ-403, recurring REQ-242 |
| A-21 | In `IntegrationsAlerts` a split write (F-20) is two steps: a read that decides the write, then the write. A crash forgets a pending write. "Conditional" writes are one step under the lease check, so they are both fenced and re-checked; the model does not separate the two checks. | INV-411, INV-412, INV-413, F-20 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-400…REQ-409, REQ-412…REQ-416, INV-400, INV-407, INV-409, INV-410, INV-411, INV-412, INV-413, REQ-433, REQ-438 · REQ-420…REQ-422, REQ-434, INV-401…INV-404, INV-408 · REQ-430, REQ-432, REQ-435, REQ-436, INV-406, LIV-400 · SCN-400, SCN-402, SCN-403, SCN-404, SCN-406 (reachable), SCN-401, SCN-405 (hold) | REQ-410 (static merge of rule definitions and a page listing, no state change; its rule identity by name is used as A-17) · INV-405 (masking in the dashboard and logs is presentation) · REQ-431, REQ-437 (which enqueue path a configuration takes; no interleaving to explore) · REQ-411 (retired, moved to hosting REQ-60) |

Owner open questions already recorded, and not raised again here: no warning when rules exist but no node has the alerts registration (F-21 option 1 relies on this being visible), refused webhook hosts, and a test delivery left pending when no alerts node exists.

## Reproduce
From `specs/model/integrations/`: `python -X utf8 run_all.py` reruns every check (or `run_all.py IntegrationsAlert` for the two alert models). Each check runs alone as `python run_tlc.py <Module>.tla --config <cfg with one INVARIANT or PROPERTY> --workers 2 --stop-at-first --no-deadlock`, killed after 170 s, plus a `TypeInv`-only run with deadlock checking for the HTTP and notification cfgs. Results land in `runs/` (gitignored), with a summary in `runs/summary.md`. Set `RUN_TLC` if `run_tlc.py` is not under `~/.claude-personal/skills/refiner-model/scripts/`.

## Next
Apply the chosen options to `integrations.json` with the `refiner-requirements` skill (it validates and diffs), then run this skill again. Decide F-20 first: its option changes the wording of both INV-412 and INV-413, and F-22's snippet builds on it.
