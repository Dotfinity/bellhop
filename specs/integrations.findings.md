# Findings: Bellhop notifications, HTTP jobs, outbound HTTP and the outbox

<!-- refiner-findings v1 | module: integrations | specHash: 60631c2ae0002044b1f3da5c2568767deaeff1602ab4fe25d5c7deaa6579063d | run: 2026-11-08 (run 6) | previous: model/integrations/previous.findings.md (run 5, specHash 05969b22d40d) -->

**Run:** 2026-11-08 (run 6, from `model/integrations/handoff.json`, base 55ee2c4: INV-412 and INV-413 modified, so handled marks are now kept per rule name and event settings; nothing impacted. REQ-403's notes changed too, but notes are annotation only. Recurring REQ-242 and REQ-234 also changed in the same round, and REQ-403 reads REQ-242's record, so the REQ-242 stand-in was regenerated and REQ-403 re-checked) · **Requirements file:** `specs/integrations.json` (specHash `60631c2ae000`) · **Models:** `model/integrations/IntegrationsAlertEvents.tla` (INV-412, INV-413, recurring REQ-242; regenerated), `IntegrationsAlerts.tla` (header only: it has one rule version, so its marks are that version's marks and no action changed; all its checks rerun). `IntegrationsNotifications.tla`, `IntegrationsHttp.tla` and `IntegrationsOutbox.tla` are byte-for-byte unchanged and were not rerun, because no item they model changed or was impacted. · **TLC:** 2.19 · **Result:** 1 finding: 0 contradictions · 0 gaps · 0 unprovable · 1 ambiguity · 0 modeling notes. Run 5's F-23 is resolved.

Every property ran in its own TLC run with `--stop-at-first --workers 2`, and each run was killed after 170 s if it had not finished. Three other modules were being checked on the same machine. No run threw a TLC exception or timed out; the largest space was 24,793 distinct states. `model/integrations/run_all.py IntegrationsAlert` reruns everything below (see *Reproduce*). The prose keeps only the steps of each trace that matter.

| Configuration | What it checks | Result | Distinct states |
|---|---|---|---|
| `IntegrationsAlertEvents.cfg` | as written: INV-412 per recorded change, INV-413 and the handled marks by name and event settings, REQ-242 records written by a trigger, a schedule change or **a pause (new)**; the recurring job may be paused and resumed; one job dead-lettered, requeued and dead-lettered again | one delivery per event ✓, every dead-letter alerted ✓, every missed instant alerted, including one dropped by a pause ✓, no alert for an event before the rule ✓ | 1,282 |
| `…_pauseReach.cfg` (new) | vacuity: an instant recorded by a pause is alerted | trap violated as expected ✓ (4 states) | 1,282 |
| `…_noReq242.cfg` | counterfactual: REQ-242 dropped, only the last outcome; pauses allowed | every missed instant alerted ✗ (stuttering, 8 states): the instant dropped by a pause leaves no trace, as expected | 853 |
| `…_perJob.cfg` | counterfactual: handled mark on the job | every dead-letter alerted ✗ (stuttering, 9 states), as expected | 384 |
| `…_newRule.cfg` | INV-413: rule added after events happened | all ✓ | 1,061 |
| `…_noInv413.cfg` | counterfactual: INV-413 dropped | no alert for an event before the rule ✗ (5 states), as expected | 3,420 |
| `…_readd.cfg` | rule removed and added back, records kept | one delivery ✓, both liveness ✓; no alert for an event while removed ✗ (6 states): accepted | 4,696 |
| `…_editTrigger.cfg` | trigger edited, name kept | all ✓ | 3,215 |
| `…_editTriggerNameOnly.cfg` | counterfactual: run 4's wording, a rule known by name only | no alert for an event before the rule watched it ✗ (5 states), as expected | 1,997 |
| `…_editBack.cfg` | **run-5 F-23 re-check**: trigger edited, then put back; as written (marks per name and event settings) | one delivery ✓, **a dead-letter owed before the edit is alerted after the rollback ✓ (was ✗)**; no alert for an event before the rule ✗ (6 states): accepted | 14,474 |
| `…_editBackPerName.cfg` (was `…_editBack`) | counterfactual: run 5's other reading, marks per name | owed dead-letter alerted after the rollback ✗ (stuttering, 10 states), as expected | 11,354 |
| `…_settingsBack.cfg` (new) | threshold or tolerance edited (same events watched), then put back; the rule has been running, so its original version is recorded; as written | owed dead-letter alerted after the rollback ✓; **one delivery per event ✗ (7 states): F-24** | 13,187 |
| `…_settingsBackPerName.cfg` (new) | counterfactual: as `…_settingsBack`, marks per name | one delivery ✓; owed dead-letter alerted after the rollback ✗ (stuttering, 10 states): run-5 F-23 again | 4,327 |
| `…_settingsBackSplit.cfg` (new) | F-24 option 1: delivery marks per name, start marks per name and event settings | all ✓ | 7,167 |
| `…_settingsFlap.cfg` (new) | a rolling deploy that changes a threshold moves the lease between versions three times (edits not fair); as written | one delivery per event ✗ (8 states): F-24 | 24,793 |
| `…_settingsFlapSplit.cfg` (new) | F-24 option 1 on the flap | one delivery per event ✓ | 12,753 |
| `…_mainSplit.cfg`, `…_editBackSplit.cfg` (new) | F-24 option 1 on the main run and the trigger edit-back | same results as as written: all ✓ on the main constants; on the edit-back, only the accepted "no alert for an event before the rule" ✗ (6 states) | 1,282 / 14,474 |
| `…_newSystem.cfg` | rule in code from the start, store records no rule yet | one delivery ✓; every event while the rule is configured alerted ✗ (stuttering, 7 states): accepted (run-4 F-21) | 462 |
| `…_newSystemCatchUp.cfg` | run-4 F-21 option 2 (not chosen) | all ✓ | 1,036 |
| `IntegrationsAlerts.cfg` | as written: rule already recorded; INV-412's write is a read and a later write that checks the lease and that the event is still unhandled | one delivery per event ✓, every event alerted ✓, SCN-405 ✓ | 949 |
| `…_newRule.cfg` | as written: INV-413's write is a read and a later write that checks the lease and that the rule is still unrecorded | all ✓ | 2,408 |
| `…_newRuleUnchecked.cfg` | counterfactual: run 4's INV-413 wording, an unchecked write | every event alerted ✗ (stuttering, 12 states), as expected | 2,879 |
| `…_newRuleFenced.cfg` | counterfactual: INV-413's write checks the lease only | every event alerted ✗ (stuttering, 14 states), as expected | 2,600 |
| `…_staleWrite.cfg` | counterfactual: run 4's INV-412 wording, a lease-only write | one delivery per event ✗ (12 states), as expected | 1,029 |
| `…_noInv412Replay.cfg` | counterfactual: INV-412 dropped, node memory replays | one delivery per event ✗ (7 states), as expected | 1,214 |
| `…_noInv412FromNow.cfg` | counterfactual: INV-412 dropped, node memory from now | every event alerted ✗ (stuttering, 9 states), as expected | 954 |
| `…_SCN404.cfg` | SCN-404 reachable | trap violated as expected ✓ (5 states) | 13 |
| `…_SCN406.cfg` | SCN-406 reachable, from its given | trap violated as expected ✓ (4 states) | 33 |

Trace lengths are in states, as TLC reports them (the initial state counts as one).

## Changes since last run

| Finding | Status | Fingerprint |
|---|---|---|
| F-23 | resolved | ambiguity · Chk_WatchedDeadLetterAlertedOnReturn/editBack · INV-412,INV-413,REQ-410 |
| F-24 | new | ambiguity · Inv_OneDeliveryPerEvent/settingsBack · INV-412,INV-413,REQ-410 |

1 resolved, 1 new, 0 still open

How run 5's finding was re-checked:

| Run 5 | Evidence in run 6 |
|---|---|
| F-23 (per-name marks: an edited rule's first evaluation marks what the previous version still owes, and a rollback never alerts it) | With marks per name and event settings, the dead-letter the original version owed is alerted after the rollback: trigger edit (`…_editBack.cfg`, ✓, 14,474 states) and threshold or tolerance edit (`…_settingsBack.cfg`, ✓, 13,187 states). Run 5's per-name reading, kept as a counterfactual, still loses it (`…_editBackPerName.cfg`, `…_settingsBackPerName.cfg`, 10 states each). |

Run 5 edited only the trigger, which moves the rule to other events, so neither version could alert the other's events. This run also edits a threshold or tolerance, where both versions watch the same events. That is what found F-24.

Recurring REQ-242 and REQ-234 (changed in this round): a record is now also written when an active job with missed instants is paused, orphaned or removed, and an instant passed over without a trigger counts as missed however recently it fell due. In the main cfg, an instant dropped by a pause is alerted under REQ-403 (`Liv_MissedAlerted` ✓, 1,282 states; reached in 4 states, `…_pauseReach.cfg`). Without the record it is not (`…_noReq242.cfg`, 8 states), because a pause creates no occurrence and so writes no last outcome either. REQ-403's new note ("so are instants already missed when a job is paused, orphaned or removed") holds.

## Accepted (not findings)

- **A rule starts at its first evaluation by a lease holder, not at its deploy** (run-4 F-21, INV-413 notes). On a new system, events before the first alerts node takes the notification lease are not alerted (`…_newSystem.cfg`, 7 states).
- **Removing and re-adding a rule alerts what happened while it was away** (INV-413 notes: "continues where it stopped and skips nothing"; `…_readd.cfg`, 6 states). The same holds for a version that is edited away and then put back (`…_editBack.cfg`, 6 states): it alerts its events from the time the edit was live, as INV-413's run-5 note says.
- **A renamed rule, or one whose trigger, threshold or tolerance is edited, is a new rule** (INV-413 notes). Events between the last evaluation of the old version and the first evaluation of the new one are alerted by neither version unless the old one comes back. This run met that case once more, in a run where the original version had never been evaluated before the edit; the settings cfgs now start from a rule that has been running (A-24).
- **A missed instant dropped by an operator's pause is alerted** (recurring REQ-234 and REQ-242, run 5). This includes an instant that fell due moments before the pause, and the record says the pause dropped it. Listed so the alert's audience is not surprised; the recurring module decided it.
- **Operator delete during a relay crash window** (REQ-436 notes, run-2 F-16), and the same with a lease pause. Not rerun, model unchanged: `IntegrationsOutbox_operatorDelete.cfg` and `…_operatorDeletePause.cfg`, `Inv_OneJobPerRow` ✗, 9 steps each in run 4.
- **INV-404 covers three headers and URL user info only** (run-1 F-10). Not rerun, model unchanged: `Chk_NoPayloadSecretAtAll` ✗, 4 steps in run 4.

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-24 | ambiguity | medium | INV-412, INV-413, REQ-410 | With marks per name and event settings, an event that an edited version alerted is alerted again by the original version after a rollback, and again on every move of the lease between versions during a rolling deploy. |

---

## F-24 · ambiguity · medium — An event alerted by one version of a rule is alerted again by another
<!-- finding: ambiguity | Inv_OneDeliveryPerEvent/settingsBack | INV-412,INV-413,REQ-410 -->

**Requirements involved**
- INV-412: *… for each one, create its delivery and mark it handled **for that rule's name and event settings (INV-413)** in one store write that succeeds only if the event is not yet marked handled for them, so that a node that takes over the notification lease **neither alerts an event again** nor skips one.*
- INV-413: *… when the notification lease holder evaluates a rule whose name and event settings (trigger, threshold and tolerance) the job store has no record of, … record the rule's name and event settings and mark every such event the store records as handled for that name and those event settings …* Notes: *"a rule whose trigger, threshold or tolerance is edited [is a new rule] … Run 5 F-23: … a rollback, or a rolling deploy that moved the lease back to a node with the previous version … continues where it stopped and skips nothing."*
- REQ-410: rules are identified by name; the code definition wins.
- INV-400: the subject cooldown is kept per rule and subject.

**What happens** (TLC, `Inv_OneDeliveryPerEvent`, `IntegrationsAlertEvents_settingsBack.cfg`, 7 states; the dead-letter version of the same trace is `…_settingsFlap.cfg`, 8 states)
1. Rule `ops-alerts` watches missed and late recurring occurrences with a tolerance of 5 minutes (REQ-403). It has been running, so the store records it with those settings (INV-413).
2. A developer lowers the tolerance to 2 minutes, keeps the name, and deploys. The lease holder evaluates the edited rule. The store has no record of `ops-alerts` with this tolerance, so INV-413 records it and marks every stored event handled for the new settings.
3. `nightly-export` misses its 02:00 run, and REQ-242 records the miss.
4. The holder alerts it under the edited rule and marks it handled for `ops-alerts` with a 2-minute tolerance (INV-412). This is delivery 1.
5. The edit is rolled back. A rolling deploy whose lease moves from a new-version node back to an old-version one has the same effect. The store has a record of `ops-alerts` with a 5-minute tolerance, so INV-413 does not apply, and the rule continues where it stopped.
6. The 02:00 miss is not marked handled for the 5-minute settings, so **INV-412 alerts it again**. This is delivery 2 for the same event and the same rule name.

During a rolling deploy the lease can move between old- and new-version nodes several times. On each move, the version that takes over alerts what the other version alerted since it last ran (`…_settingsFlap.cfg`). If the subject cooldown (INV-400) is kept per rule name and has not ended, the repeat is created as Suppressed and not sent. After a rollback that comes later than one cooldown (a threshold lowered for a week, then restored), the repeats are sent.

**Why** Run-5 F-23 put the handled marks on the version (name and event settings) so that a new version's first evaluation does not mark what the previous version still owes. But the same mark also records "a delivery was made", and per version that fact is invisible to the other version. When both versions watch the same events, which is the case for every threshold or tolerance edit, a rollback and a lease move between versions alert again what the other version already alerted. Whether that breaks INV-412's "neither alerts an event again" depends on whether the edited rule and the restored one are the same rule. INV-413's notes say an edit makes a new rule, and REQ-410 and the cooldown say a rule is its name. Run 5 tested only a trigger edit, where the two versions never watch the same events, so it could not show this.

**Options**
1. *(recommended)* **Keep two marks: "delivered" per rule name, "before its start" per version.** INV-412's write marks the event delivered for the rule's name and succeeds only if it is not yet delivered for the name. INV-413's first evaluation marks the stored events as before the start of that name and those event settings. An event is due for a version if it is neither delivered for the name nor before that version's start. Every version then alerts each event at most once in total (no duplicate across a rollback or a rolling deploy) and still alerts what an earlier version owed (F-23 stays resolved).
   - **Checked:** `…_settingsBackSplit.cfg` (7,167 states) and `…_settingsFlapSplit.cfg` (12,753): one delivery per event ✓ and the owed event alerted after the rollback ✓. The main run and the trigger edit-back give the same results as now (`…_mainSplit.cfg`, `…_editBackSplit.cfg`). The re-add was not rerun under this option.
   - Cost: two kinds of mark instead of one, each a phrase in one sentence. No new state beyond the mark, and no new trigger.
2. **Accept and say so.** Add to INV-413's notes that an event alerted by one version of a rule can be alerted again by another version after a rollback or during a rolling deploy, and that the subject cooldown suppresses the repeat if it is still open. Notes only. Cost: an operator who restores a threshold after a week gets that week's alerts a second time.
3. **Go back to marks per name** (run-5 F-23 option 2). No duplicates, but a rollback again skips what the original version owed (`…_settingsBackPerName.cfg`, 10 states). This reverses run 5's decision. Not recommended.

**Ready to apply (option 1)**
```json
{ "id": "INV-412", "ears": {
    "where": "a rule watches an event that is a single recorded state change: a job dead-lettered (REQ-400), an attempt that makes the Nth failure (REQ-401), or a recurring occurrence missed or late (REQ-403); a job that is requeued (jobs REQ-141, REQ-143) can produce such an event again",
    "shall": "find those events from what the job store records and, for each one that is neither delivered for the rule's name nor before the start of its name and event settings (INV-413), create its delivery and mark it delivered for the rule's name in one store write that succeeds only if the event is not yet marked delivered for that name, so that a node that takes over the notification lease, or a version of the rule that takes over from another, neither alerts an event again nor skips one" } }
{ "id": "INV-413", "ears": {
    "where": "a rule watches an event that is a single recorded state change (INV-412)",
    "when": "the notification lease holder evaluates a rule whose name and event settings (trigger, threshold and tolerance) the job store has no record of",
    "shall": "in one store write that checks the notification lease and succeeds only if the store still has no record of them, record the rule's name and event settings and mark every such event the store records as before the start of that name and those event settings, without creating deliveries for them" },
  "notes": "<existing notes> refiner-model 2026-11-08 run 6 F-24 (recommended option): run 5 kept one mark per version, which also hid from each version what the other had already delivered, so a rollback or a lease move between versions during a rolling deploy alerted the same event again whenever both versions watch it (any threshold or tolerance edit). Two marks now: 'delivered' per rule name, so a rule name alerts each event once, and 'before its start' per name and event settings, so a version's start does not hide what another version still owes." }
```

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. A-1 to A-23 are from runs 1 to 5; changes are marked.

| # | Assumption | Affects |
|---|---|---|
| A-1 | REQ-400…REQ-406 are abstracted to "the rule fires for subject s" at any moment in the cooldown model. What they watch belongs to jobs, recurring and hosting. The alerts model makes two kinds explicit: edge events (REQ-400, REQ-401, REQ-403) and the state-based node-lost trigger (REQ-404, with NodeLostAfter from hosting REQ-60 as a nondeterministic "goes stale"). | REQ-400…REQ-406 |
| A-2 | Backoff has no clock: the next attempt may come at any later moment. | REQ-408, REQ-412 |
| A-3 | Cooldowns, NodeLostAfter, tolerance, MisfireThreshold, retention and LeaseDuration end as nondeterministic events. The model cannot judge durations: retry span vs cooldown, retention vs relay recovery (REQ-436), how long a pause must be to let a stale write land, or (run 6) whether F-24's repeat falls inside a subject cooldown. Nor can it judge how much storage per-version records and marks take over years of edits. | INV-400, INV-407, INV-410, REQ-414, REQ-436, INV-412, INV-413 |
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
| A-14 | *(changed)* Bounds: 1 rule, 2 subjects, 3 delivery slots (4 in `…_cap2`), NotificationMaxAttempts 2, MaxDeliveriesPerCooldown 1 (2 in `…_cap2`). 2 alerts nodes, 2 edge events. 2 dead-letters and 2 moves of one recurring job's nextRunAt or pauses in `IntegrationsAlertEvents`, up to 3 configuration changes (`…_settingsFlap*`). 1 HTTP job, up to 3 hosts, maxAttempts 2, MaxRedirects 0 (1 in `…_transport`). 1 outbox row, 2 worker nodes. | all |
| A-15 | `IntegrationsAlertEvents` has one alerts node holding the lease throughout, and each store write is one step. Handovers and writes split into a read and a later write are in `IntegrationsAlerts`. Rule evaluation, including INV-413's first evaluation, is fair (it happens if it stays possible) but has no deadline. | INV-411, INV-412, INV-413 |
| A-16 | Dead-letters and failed attempts are found through the job's state history (jobs INV-116). A late start is findable if the occurrence job keeps its due instant (`scheduledAt`), so it is not modeled. A missed instant is found through recurring REQ-242's record. | INV-412, REQ-403 |
| A-17 | *(changed)* A rule is known by its name and event settings (INV-413). In the model the settings are the trigger (`watch`) and a version bit (`ver`) that stands for a threshold or tolerance: a trigger edit moves the rule to other events, a settings edit keeps them. Records are added, never replaced, so a rule edited back finds its earlier record (INV-413 notes). Handled marks are kept per name and event settings, as written; per name (run 5's other reading) and F-24's split are switches (`MarkScope`). Adding, removing and editing a rule are nondeterministic events, not fair, except in `…_readd.cfg` (re-add fair) and the edit-back cfgs (edits fair). A rolling deploy that moves the lease between nodes with and without the rule, or with two versions of it, is the same as a removal and re-add, or an edit and rollback. | INV-413, F-24 |
| A-18 | In `IntegrationsAlertEvents` a requeue (jobs REQ-141) is folded into the second dead-letter of the same job. Retention (jobs REQ-145) and operator deletes are not modeled; INV-412's notes accept that a removed job is no longer alerted. | INV-412 |
| A-19 | In `IntegrationsAlertEvents` one rule stands for a rule per event kind (it watches dead-letters and missed occurrences, `InitialWatch`), except in the trigger-edit cfgs, where it watches one kind and the edit switches it. INV-413 marks every stored event of every kind ("every such event"). | INV-413, F-24 |
| A-20 | One REQ-242 record (one move of nextRunAt or one pause, however many instants it passed) is one event for INV-412, so one delivery. REQ-403 says "when a recurring job's occurrence is missed"; the subject is the recurring job either way, so the subject cooldown would merge per-instant deliveries. | REQ-403, recurring REQ-242 |
| A-21 | In `IntegrationsAlerts` every INV-412 and INV-413 write is two steps: a read that decides it, and a write that checks the lease and its condition when it lands and, if either fails, changes nothing (the next evaluation reads again). A crash forgets a pending write. The node-memory counterfactuals keep a one-step write. That model has one rule version, so the per-version marks of run 6 are its single set of marks. | INV-411, INV-412, INV-413 |
| A-22 | A schedule change (recurring REQ-227) that moves nextRunAt past an overdue instant writes a REQ-242 record and no last outcome (REQ-231 records outcomes of occurrences, and the change creates none). Which component applies the change (node start, scheduler, operator) does not matter here. | REQ-403, recurring REQ-227, REQ-242 |
| A-23 | The REQ-242 record also says what became of each catch-up occurrence. A catch-up occurrence that starts later than the rule's tolerance after its due time would be a second event for REQ-403's "starts later" branch, with the same subject. It is not modeled (A-16), and the subject cooldown (INV-400) would merge the two deliveries. | REQ-403, INV-400, recurring REQ-242 |
| A-24 | *(new)* A pause, orphaning or removal of the active recurring job with an overdue instant (recurring REQ-214, REQ-205, REQ-207, REQ-213) is one action, `PauseMissed`: it writes a REQ-242 record and no last outcome, and stops triggers. A resume (REQ-215, or a restore, REQ-206) writes nothing; a removal is a pause never resumed. Instants that fall due while paused are not missed (REQ-234) and are not modeled. A pause with nothing overdue changes nothing here and is not modeled. A pause that comes after an instant was already alerted by REQ-403's "has not started" branch would be a second event with the same subject; it is not modeled (A-16), and the subject cooldown would merge them. | REQ-403, recurring REQ-242, REQ-234 |
| A-25 | *(new)* The settings-edit cfgs start from a rule that has been running, so the store records its original version (`RecordedAtStart`). Without it, a rollback is the original version's first evaluation, which is the accepted "neither version" gap rather than a rollback. The other cfgs keep run 5's start (no record). | F-24 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-400…REQ-409, REQ-412…REQ-416, INV-400, INV-407, INV-409, INV-410, INV-411, INV-412, INV-413, REQ-433, REQ-438 · REQ-420…REQ-422, REQ-434, INV-401…INV-404, INV-408 · REQ-430, REQ-432, REQ-435, REQ-436, INV-406, LIV-400 · SCN-400, SCN-402, SCN-403, SCN-404, SCN-406 (reachable), SCN-401, SCN-405 (hold) | REQ-410 (static merge of rule definitions and a page listing, no state change; its rule identity is used as A-17) · INV-405 (masking in the dashboard and logs is presentation) · REQ-431, REQ-437 (which enqueue path a configuration takes; no interleaving to explore) · REQ-411 (retired, moved to hosting REQ-60) |

Owner open questions already recorded, and not raised again here: no warning when rules exist but no node has the alerts registration, refused webhook hosts, and a test delivery left pending when no alerts node exists.

## Reproduce
From `specs/model/integrations/`, `python -X utf8 run_all.py IntegrationsAlert` reruns this run's two alert models. Without an argument it reruns everything, including the three unchanged models. Each check runs alone as `python run_tlc.py <Module>.tla --config <cfg with one INVARIANT or PROPERTY> --workers 2 --stop-at-first --no-deadlock`, killed after 170 s, plus a `TypeInv`-only run with deadlock checking for the HTTP and notification cfgs. Results land in `runs/` (gitignored), with a summary in `runs/summary.md` for the last invocation. Set `RUN_TLC` if `run_tlc.py` is not under `~/.claude-personal/skills/refiner-model/scripts/`.

## Next
Apply the chosen option to `integrations.json` with the `refiner-requirements` skill (it validates and diffs), then run this skill again. F-24 is the only open finding. Its option 1 changes one phrase in INV-412 and one in INV-413, and keeps run 5's fix.
