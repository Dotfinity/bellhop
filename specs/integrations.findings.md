# Findings: Bellhop notifications, HTTP jobs, outbound HTTP and the outbox

<!-- refiner-findings v1 | module: integrations | specHash: 05969b22d40d843e2560b7255c1db110572df3b057c3dc47d388c0cf764b5b78 | run: 2026-11-08 | previous: model/integrations/previous.findings.md (run 4, specHash 138efb1f8daa) -->

**Run:** 2026-11-08 (run 5, from `model/integrations/handoff.json`: INV-412 and INV-413 modified; nothing impacted. Recurring REQ-242 also changed in the same round, and REQ-403 reads its record, so the REQ-242 stand-in was regenerated and REQ-403 re-checked) · **Requirements file:** `specs/integrations.json` (specHash `05969b22d40d`) · **Models:** `model/integrations/IntegrationsAlertEvents.tla` (INV-412, INV-413, recurring REQ-242; regenerated), `IntegrationsAlerts.tla` (the store writes of INV-412 and INV-413 across a lease handover; regenerated). `IntegrationsNotifications.tla`, `IntegrationsHttp.tla` and `IntegrationsOutbox.tla` are byte-for-byte unchanged and were not rerun, because no item they model changed or was impacted. · **TLC:** 2.19, Java 25 · **Result:** 1 finding: 0 contradictions · 0 gaps · 0 unprovable · 1 ambiguity · 0 modeling notes. All 3 run-4 findings are resolved: F-20 and F-22 by the new sentences, and F-21 by being accepted in the notes.

Every property ran in its own TLC run with `--stop-at-first --workers 2`, and each run was killed after 170 s if it had not finished. No run threw a TLC exception or timed out. `model/integrations/run_all.py IntegrationsAlert` reruns everything below (see *Reproduce*). The prose keeps only the steps of each trace that matter.

| Configuration | What it checks | Result | Distinct states |
|---|---|---|---|
| `IntegrationsAlertEvents.cfg` | as written: INV-412 per recorded change, INV-413 by name and event settings, REQ-242 records written by a trigger **or a schedule change (new)**; one job dead-lettered, requeued and dead-lettered again | one delivery per event ✓, every dead-letter alerted ✓, every missed instant alerted, including one dropped by a schedule change ✓, no alert for an event before the rule ✓ | 462 |
| `…_noReq242.cfg` | counterfactual: REQ-242 dropped, only the last outcome | every missed instant alerted ✗ (stuttering, 8 steps): the instant dropped by a schedule change leaves no trace, as expected | 396 |
| `…_perJob.cfg` | counterfactual: handled mark on the job | every dead-letter alerted ✗ (stuttering, 8 steps), as expected | 384 |
| `…_newRule.cfg` | INV-413: rule added after events happened | all ✓ | 1,061 |
| `…_noInv413.cfg` | counterfactual: INV-413 dropped | no alert for an event before the rule ✗ (5 steps), as expected | 3,420 |
| `…_readd.cfg` | rule removed and added back, records kept | one delivery ✓, both liveness ✓; no alert for an event while removed ✗ (6 steps): accepted | 4,696 |
| `…_editTrigger.cfg` | run-4 F-22 re-check: trigger edited, name kept, as written | **all ✓ (was ✗)** | 3,215 |
| `…_editTriggerNameOnly.cfg` (was `…_editTriggerKeyed`) | counterfactual: run 4's wording, a rule known by name only | no alert for an event before the rule watched it ✗ (5 steps), as expected | 1,997 |
| `…_editBack.cfg` (new) | trigger edited, then put back (rollback); handled marks per rule name | one delivery ✓; **a dead-letter owed before the edit is alerted after the rollback ✗ (stuttering, 9 steps): F-23**; no alert for an event before the rule ✗ (7 steps): accepted | 11,354 |
| `…_editBackPerSettings.cfg` (new) | as `…_editBack`, marks per name and event settings | one delivery ✓, owed dead-letter alerted after the rollback ✓; no alert for an event before the rule ✗ (6 steps): accepted | 14,474 |
| `…_newSystem.cfg` | rule in code from the start, store records no rule yet | one delivery ✓; every event while the rule is configured alerted ✗ (stuttering, 6 steps): accepted (run-4 F-21) | 462 |
| `…_newSystemCatchUp.cfg` | run-4 F-21 option 2 (not chosen) | all ✓ | 1,036 |
| `IntegrationsAlerts.cfg` | as written: rule already recorded; INV-412's write is a read and a later write that checks the lease and that the event is still unhandled | **one delivery per event ✓, every event alerted ✓**, SCN-405 ✓ | 949 |
| `…_newRule.cfg` | as written: INV-413's write is a read and a later write that checks the lease and that the rule is still unrecorded | **all ✓** | 2,408 |
| `…_newRuleUnchecked.cfg` (was `…_newRuleLiteral`) | counterfactual: run 4's INV-413 wording, an unchecked write | every event after the rule's start alerted ✗ (stuttering, 14 steps), as expected | 2,879 |
| `…_newRuleFenced.cfg` | counterfactual: INV-413's write checks the lease only | every event alerted ✗ (stuttering, 14 steps), as expected | 2,600 |
| `…_staleWrite.cfg` | counterfactual: run 4's INV-412 wording, a lease-only write | one delivery per event ✗ (12 steps), as expected | 1,029 |
| `…_noInv412Replay.cfg` | counterfactual: INV-412 dropped, node memory replays | one delivery per event ✗ (7 steps), as expected | 1,214 |
| `…_noInv412FromNow.cfg` | counterfactual: INV-412 dropped, node memory from now | every event alerted ✗ (stuttering, 8 steps), as expected | 954 |
| `…_SCN404.cfg` | SCN-404 reachable | trap violated as expected ✓ (5 steps) | 13 |
| `…_SCN406.cfg` | SCN-406 reachable, from its given | trap violated as expected ✓ (4 steps) | 33 |

## Changes since last run

| Finding | Status | Fingerprint |
|---|---|---|
| F-20 | resolved | gap · Liv_EventAlerted/newRuleLiteral · INV-411,INV-412,INV-413,REQ-438 |
| F-21 | resolved | ambiguity · Chk_ConfiguredEventAlerted/newSystem · INV-412,INV-413 |
| F-22 | resolved | ambiguity · Chk_NoAlertForEventBeforeRule/editTrigger · INV-412,INV-413,REQ-401,REQ-403,REQ-410 |
| F-23 | new | ambiguity · Chk_WatchedDeadLetterAlertedOnReturn/editBack · INV-412,INV-413,REQ-410 |

3 resolved, 1 new, 0 still open

How each run-4 finding was re-checked:

| Run 4 | Evidence in run 5 |
|---|---|
| F-20 (a write decided before the lease lapsed still lands) | Both writes are now modeled as the sentences say: a read, then a later write that checks the lease and its condition when it lands and changes nothing if either no longer holds. A paused node keeps its pending write and may land it after it takes the lease back, which is the case run 4 found. One delivery per event and every event alerted hold with a crash, a restart and a lease pause (`IntegrationsAlerts.cfg`, 949 states; for a new rule `…_newRule.cfg`, 2,408 states). Run 4's wordings, kept as counterfactuals, still fail: the lease-only delivery write alerts twice (`…_staleWrite.cfg`, 12 steps), and an unchecked or lease-only INV-413 write loses an event (`…_newRuleUnchecked.cfg`, `…_newRuleFenced.cfg`, 14 steps each). |
| F-21 (a rule starts at its first evaluation) | Accepted in INV-413's notes, and INV-412's notes no longer promise more. The behaviour is unchanged (`…_newSystem.cfg`, 6 steps), and it is listed under *Accepted*. |
| F-22 (editing a rule's settings alerts the stored backlog) | INV-413 knows a rule by its name and event settings. An edited trigger starts at the store's present (`…_editTrigger.cfg`, all ✓, 3,215 states), and the name-only wording still fails (`…_editTriggerNameOnly.cfg`, 5 steps). Keying the record by settings raises the question in F-23. |

Recurring REQ-242 (changed in this round): its record is now also written when a schedule change (recurring REQ-227) moves nextRunAt past an overdue instant. In the main cfg, an instant dropped that way is alerted under REQ-403 (`Liv_MissedAlerted` ✓, 462 states). Without the record it is not (`…_noReq242.cfg`, 8 steps), because a schedule change creates no occurrence and so writes no last outcome either. REQ-403's run-4 note, which says such instants are alerted, holds.

## Accepted (not findings)

- **A rule starts at its first evaluation by a lease holder, not at its deploy** (run-4 F-21, INV-413 notes). On a new system, events before the first alerts node takes the notification lease are not alerted (`…_newSystem.cfg`, 6 steps).
- **Removing and re-adding a rule alerts what happened while it was away** (INV-413 notes: "continues where it stopped and skips nothing"; `…_readd.cfg`, 6 steps). The same holds for settings that are edited and then put back. Whichever way marks are kept, a dead-letter that happens while the edited version is live can be alerted after the rollback (`…_editBack.cfg`, 7 steps; `…_editBackPerSettings.cfg`, 6 steps). With marks kept per name, this happens unless the edited version's first evaluation has already marked it. For a threshold lowered from 5 to 3 for a week and then restored, that means the attempt-5 failures of that week, capped by MaxDeliveriesPerCooldown plus a digest (INV-409, REQ-414).
- **A renamed rule, or one whose trigger, threshold or tolerance is edited, is a new rule** (INV-413 notes). Events between the last evaluation of the old version and the first evaluation of the new one are alerted by neither version unless the old one comes back (F-23).
- **Operator delete during a relay crash window** (REQ-436 notes, run-2 F-16), and the same with a lease pause. Not rerun, model unchanged: `IntegrationsOutbox_operatorDelete.cfg` and `…_operatorDeletePause.cfg`, `Inv_OneJobPerRow` ✗, 9 steps each in run 4.
- **INV-404 covers three headers and URL user info only** (run-1 F-10). Not rerun, model unchanged: `Chk_NoPayloadSecretAtAll` ✗, 4 steps in run 4.

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-23 | ambiguity | medium | INV-412, INV-413, REQ-410 | Now that a rule is known by its name and event settings, "handled for that rule" can mean per name or per name and settings. Per name, an edited rule's first evaluation marks events the old version still owed, and a rollback never alerts them. |

---

## F-23 · ambiguity · medium — Which version of a rule an event is handled for
<!-- finding: ambiguity | Chk_WatchedDeadLetterAlertedOnReturn/editBack | INV-412,INV-413,REQ-410 -->

**Requirements involved**
- INV-412: *… for each one, create its delivery and mark it handled **for that rule** in one store write that succeeds only if the event is not yet marked handled **for that rule**, so that a node that takes over the notification lease neither alerts an event again **nor skips one**.*
- INV-413: *… when the notification lease holder evaluates a rule whose **name and event settings** (trigger, threshold and tolerance) the job store has no record of, the system shall … record the rule's name and event settings and mark every such event the store records as handled **for that rule** …* Its notes: *"Its record and handled marks are kept by name even while no node loads the rule, so removing and re-adding it, or a rolling deploy in which the lease moves between nodes with and without it, continues where it stopped and skips nothing."*
- REQ-410: rules are identified by name, and the code definition wins.

**What happens** (TLC, `Chk_WatchedDeadLetterAlertedOnReturn`, `IntegrationsAlertEvents_editBack.cfg`, 9 steps ending in stuttering, with marks kept per rule name)
1. Rule `ops-alerts` watches dead-lettering (REQ-400). The lease holder has evaluated it, so the store records `ops-alerts` with that trigger (INV-413).
2. Job d2 is dead-lettered. It is owed an alert (REQ-400, INV-412), and the holder has not reached it yet.
3. A developer changes `ops-alerts` to watch recurring jobs, keeps the name, and deploys.
4. The holder evaluates the edited rule. The store has no record of `ops-alerts` with this trigger, so INV-413 records it and marks every event the store records as handled "for that rule". With marks kept per name, that includes d2.
5. The edit is rolled back. A rolling deploy whose lease moves from a new-version node back to an old-version one has the same effect. The store has a record of `ops-alerts` watching dead-lettering, so INV-413 does not apply, and the rule continues where it stopped.
6. **d2 is marked handled for `ops-alerts` and is never alerted.** It happened while the rule watched dead-letters, and after the rule had started.

When the marks are kept per name and event settings, step 4 marks d2 only for the edited version, and the restored version alerts it after the rollback (`…_editBackPerSettings.cfg`, ✓, 14,474 states).

**Why** Run 4's F-22 made the store record of a rule carry its event settings, but the handled marks still say "for that rule". When a rule was known only by its name, that phrase was clear. Now it fits two readings: the name, which the notes' "kept by name" suggests, or the record (name and settings), which INV-413's "rule whose name and event settings" suggests. Under the first reading, INV-413's write for a new version marks events that an older version had not yet alerted. A rollback or a back-and-forth rolling deploy then skips them, which contradicts INV-412's "nor skips one" and the notes' "skips nothing". The window is the time between an event and the holder's next evaluation. That window is short, but it is exactly when a deploy restarts nodes and moves the lease.

**Options**
1. *(recommended)* **Keep handled marks per name and event settings, like the record.** Each version of a rule has its own start and marks. A rollback, or a rolling deploy that moves the lease back to an old-version node, continues the old version where it stopped and skips nothing. As with a re-add, it also alerts the old version's events from the time the edit was live (see *Accepted*). This is one phrase in each sentence and needs no new mechanism.
2. **Keep marks per name, and accept the skip.** An edited rule's first evaluation marks every stored event for the name, including those the previous version had not alerted yet, so a rollback does not alert them. Say so in INV-413's notes and qualify "skips nothing" there. Notes only.
3. **Make a rollback a new rule.** An edit replaces the record instead of adding one, so restored settings start again at the store's present. This removes the edited-period alerts after a rollback, but it drops the owed events too, and every time a rolling deploy moves the lease between versions the rule restarts and skips what happened since the last evaluation. This contradicts the rolling-deploy sentence in the notes. Not model-checked.

**Ready to apply (option 1)**
```json
{ "id": "INV-412", "ears": {
    "where": "a rule watches an event that is a single recorded state change: a job dead-lettered (REQ-400), an attempt that makes the Nth failure (REQ-401), or a recurring occurrence missed or late (REQ-403); a job that is requeued (jobs REQ-141, REQ-143) can produce such an event again",
    "shall": "find those events from what the job store records and, for each one, create its delivery and mark it handled for that rule's name and event settings (INV-413) in one store write that succeeds only if the event is not yet marked handled for them, so that a node that takes over the notification lease neither alerts an event again nor skips one" } }
{ "id": "INV-413", "ears": {
    "where": "a rule watches an event that is a single recorded state change (INV-412)",
    "when": "the notification lease holder evaluates a rule whose name and event settings (trigger, threshold and tolerance) the job store has no record of",
    "shall": "in one store write that checks the notification lease and succeeds only if the store still has no record of them, record the rule's name and event settings and mark every such event the store records as handled for that name and those event settings, without creating deliveries for them" },
  "notes": "…replace \"Its record and handled marks are kept by name\" with \"Its records and handled marks are kept per name and event settings\"… refiner-model 2026-11-08 run 5 F-23 (recommended option): handled marks belong to a version of the rule like its record, so an edit's first evaluation does not mark what the previous version still owes; a rollback, or a rolling deploy that moves the lease back to a node with the previous version, continues that version where it stopped and also alerts its events from the time the edit was live, as a re-add does." }
```

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.

| # | Assumption | Affects |
|---|---|---|
| A-1 | REQ-400…REQ-406 are abstracted to "the rule fires for subject s" at any moment in the cooldown model. What they watch belongs to jobs, recurring and hosting. The alerts model makes two kinds explicit: edge events (REQ-400, REQ-401, REQ-403) and the state-based node-lost trigger (REQ-404, with NodeLostAfter from hosting REQ-60 as a nondeterministic "goes stale"). | REQ-400…REQ-406 |
| A-2 | Backoff has no clock: the next attempt may come at any later moment. | REQ-408, REQ-412 |
| A-3 | Cooldowns, NodeLostAfter, tolerance, MisfireThreshold, retention and LeaseDuration end as nondeterministic events. The model cannot judge durations: retry span vs cooldown, retention vs relay recovery (REQ-436), how long a pause must be to let a stale write land. | INV-400, INV-407, INV-410, REQ-414, REQ-436, INV-412, INV-413 |
| A-4 | Closed deliveries and finished HTTP jobs are archived and free their slot. | all |
| A-5 | A digest delivery has no subject and is not counted (INV-409's "non-digest"). When both the subject cooldown and the cap apply, the delivery is deduplicated, not capped (INV-409 notes). | INV-409, REQ-414 |
| A-6 | Job lifecycle around an HTTP call: claim, then retry while attempt < maxAttempts, else dead-letter (jobs REQ-123/129/131). Lease expiry, job timeouts (REQ-138) and cancellation are not modeled; the HTTP request timeout is one response outcome. A job may list a 3xx status as accepted. | REQ-421, REQ-422, REQ-434, SCN-402 |
| A-7 | INV-401/INV-402 ("never send", "refuse") act as guards on REQ-420, as SCN-401 expects; REQ-434 is the step taken instead. | REQ-420, INV-401, INV-402, REQ-434, SCN-401 |
| A-8 | "Attempts made" in REQ-408/REQ-415 includes the attempt just rejected, so total attempts = NotificationMaxAttempts (REQ-412). | REQ-408, REQ-415, REQ-433 |
| A-9 | In the cooldown model, delivery creation is serialised, which is what INV-411's fenced write gives. The lease itself is modeled in `IntegrationsAlerts.tla`. | INV-409, INV-411 |
| A-10 | At most one crash per behaviour (relay node, or alerts node). | LIV-400, REQ-435, REQ-438 |
| A-11 | At most one lease expiry under a running holder (a missed renewal, e.g. a long pause). The relay's row delete is not fenced (REQ-432 does not say), but it is idempotent. | REQ-432, REQ-435, REQ-438, INV-412, INV-413 |
| A-12 | A crashed node is restarted by its host (fair) as a new instance that does not inherit its old lease. The old lease must expire first. A paused node that is still running may take the lease again once it is free. | REQ-438, INV-412, INV-413 |
| A-13 | REQ-436 is encoded as a guard: retention never removes a job while the outbox row it came from is still pending. `…_noRetentionAssumption.cfg` shows the guarantee depends on it. | REQ-436, INV-406 |
| A-14 | Bounds: 1 rule, 2 subjects, 3 delivery slots (4 in `…_cap2`), NotificationMaxAttempts 2, MaxDeliveriesPerCooldown 1 (2 in `…_cap2`). 2 alerts nodes, 2 edge events. 2 dead-letters and 2 moves of one recurring job's nextRunAt in `IntegrationsAlertEvents`, up to 2 configuration changes. 1 HTTP job, up to 3 hosts, maxAttempts 2, MaxRedirects 0 (1 in `…_transport`). 1 outbox row, 2 worker nodes. | all |
| A-15 | `IntegrationsAlertEvents` has one alerts node holding the lease throughout, and each store write is one step. Handovers and writes split into a read and a later write are in `IntegrationsAlerts`. Rule evaluation, including INV-413's first evaluation, is fair (it happens if it stays possible) but has no deadline. | INV-411, INV-412, INV-413 |
| A-16 | Dead-letters and failed attempts are found through the job's state history (jobs INV-116). A late start is findable if the occurrence job keeps its due instant (`scheduledAt`), so it is not modeled. A missed instant is found through recurring REQ-242's record. | INV-412, REQ-403 |
| A-17 | A rule is known by its name and event settings (INV-413); in the model, the settings are the trigger, and a threshold or tolerance edit is the same kind of change. Records are added, never replaced, so a rule edited back finds its earlier record (INV-413 notes, "kept … continues where it stopped"). Where its handled marks are kept is F-23; the cfgs without edits do not depend on it and use "per name". Adding, removing and editing a rule are nondeterministic events, not fair, except in `…_readd.cfg` (re-add fair) and `…_editBack*.cfg` (edits fair). A rolling deploy that moves the lease between nodes with and without the rule, or with two versions of it, is the same as a removal and re-add, or an edit and rollback. | INV-413, F-23 |
| A-18 | In `IntegrationsAlertEvents` a requeue (jobs REQ-141) is folded into the second dead-letter of the same job. Retention (jobs REQ-145) and operator deletes are not modeled; INV-412's notes accept that a removed job is no longer alerted. | INV-412 |
| A-19 | In `IntegrationsAlertEvents` one rule stands for a rule per event kind (it watches dead-letters and missed occurrences, `InitialWatch`), except in the edit cfgs, where it watches one kind and the edit switches it. INV-413 marks every stored event of every kind ("every such event"). | INV-413, F-23 |
| A-20 | One REQ-242 record (one move of nextRunAt, however many instants it passed) is one event for INV-412, so one delivery. REQ-403 says "when a recurring job's occurrence is missed"; the subject is the recurring job either way, so the subject cooldown would merge per-instant deliveries. | REQ-403, recurring REQ-242 |
| A-21 | In `IntegrationsAlerts` every INV-412 and INV-413 write is two steps: a read that decides it, and a write that checks the lease and its condition when it lands and, if either fails, changes nothing (the next evaluation reads again). A crash forgets a pending write. The node-memory counterfactuals keep a one-step write. | INV-411, INV-412, INV-413 |
| A-22 | (run 5) A schedule change (recurring REQ-227) that moves nextRunAt past an overdue instant writes a REQ-242 record and no last outcome (REQ-231 records outcomes of occurrences, and the change creates none). Which component applies the change (node start, scheduler, operator) does not matter here. | REQ-403, recurring REQ-227, REQ-242 |
| A-23 | (run 5) The REQ-242 record also says what became of each catch-up occurrence. A catch-up occurrence that starts later than the rule's tolerance after its due time would be a second event for REQ-403's "starts later" branch, with the same subject. It is not modeled (A-16), and the subject cooldown (INV-400) would merge the two deliveries. | REQ-403, INV-400, recurring REQ-242 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-400…REQ-409, REQ-412…REQ-416, INV-400, INV-407, INV-409, INV-410, INV-411, INV-412, INV-413, REQ-433, REQ-438 · REQ-420…REQ-422, REQ-434, INV-401…INV-404, INV-408 · REQ-430, REQ-432, REQ-435, REQ-436, INV-406, LIV-400 · SCN-400, SCN-402, SCN-403, SCN-404, SCN-406 (reachable), SCN-401, SCN-405 (hold) | REQ-410 (static merge of rule definitions and a page listing, no state change; its rule identity is used as A-17) · INV-405 (masking in the dashboard and logs is presentation) · REQ-431, REQ-437 (which enqueue path a configuration takes; no interleaving to explore) · REQ-411 (retired, moved to hosting REQ-60) |

Owner open questions already recorded, and not raised again here: no warning when rules exist but no node has the alerts registration, refused webhook hosts, and a test delivery left pending when no alerts node exists.

## Reproduce
From `specs/model/integrations/`, `python -X utf8 run_all.py IntegrationsAlert` reruns this run's two alert models. Without an argument it reruns everything, including the three unchanged models. Each check runs alone as `python run_tlc.py <Module>.tla --config <cfg with one INVARIANT or PROPERTY> --workers 2 --stop-at-first --no-deadlock`, killed after 170 s, plus a `TypeInv`-only run with deadlock checking for the HTTP and notification cfgs. Results land in `runs/` (gitignored), with a summary in `runs/summary.md` for the last invocation. Set `RUN_TLC` if `run_tlc.py` is not under `~/.claude-personal/skills/refiner-model/scripts/`.

## Next
Apply the chosen option to `integrations.json` with the `refiner-requirements` skill (it validates and diffs), then run this skill again. F-23 is the only open finding, and its option 1 changes one phrase in INV-412 and INV-413.
