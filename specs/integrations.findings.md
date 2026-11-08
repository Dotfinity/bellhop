# Findings: Bellhop notifications, HTTP jobs, outbound HTTP and the outbox

<!-- refiner-findings v1 | module: integrations | specHash: dce58296443f125005831955a247d675c6dcf37c8bb55724ad84209fa6598c28 | run: 2026-11-08 (run 8) | previous: model/integrations/previous.findings.md (run 7, specHash 7b719d5882c5) -->

**Run:** 2026-11-08 (run 8, from `model/integrations/handoff.json`, base ed02be0: INV-412 modified, so its purpose clause now ends "… or skips one after its start (INV-413)". INV-413 is impacted, and only its notes changed: they now accept run 7's F-25 and F-26.) · **Requirements file:** `specs/integrations.json` (specHash `dce58296443f`) · **Models:** `model/integrations/IntegrationsAlertEvents.tla` and `IntegrationsAlerts.tla` (INV-412, INV-413; liveness restated to the new wording, see below). `IntegrationsNotifications.tla`, `IntegrationsHttp.tla` and `IntegrationsOutbox.tla` are byte-for-byte unchanged. Nothing they model changed, and they were rerun anyway, so this report rests on a complete run of the module. · **TLC:** 2.19 · **Result:** 0 findings: 0 contradictions · 0 gaps · 0 unprovable · 0 ambiguities · 0 modeling notes. Run 7's F-25 and F-26 are resolved: the owner accepted both in INV-413's notes, and they are listed under *Accepted*.

Every property ran in its own TLC run with `--stop-at-first --workers 4`, and each run was killed after 400 s if it had not finished. Three other modules were being checked on the same machine. 189 runs: none threw a TLC exception or timed out. The largest space was 7,683,747 distinct states (`IntegrationsNotifications_cap2.cfg`, about 40 s per run). The largest alert space was 24,793 (`…_settingsFlapPerSettings`). `model/integrations/run_all.py` reruns everything below (see *Reproduce*). The prose keeps only the steps of each trace that matter.

**What changed in the models.** INV-412 now says that reading (a) of run 7 is the requirement: a version skips none of the events after its own start. The liveness properties were restated to say that, and they now run on every cfg except the vacuity traps:
- `IntegrationsAlertEvents`: `Liv_DeadLetterAlerted` and `Liv_MissedAlerted` say that an event which a version watches, and which is after that version's start, is delivered for the rule's name once that version is configured for good. The delivery can come from that version, or earlier from another version of the same name. Formally, for each event and name, `<>[](the event is the configured version's own) => <>(delivered for that name)`.
- `IntegrationsAlerts`: `Liv_EventAlerted` says that an event after the start of version v is delivered once the lease stays with a running node that runs v.
- Each version's start is now a history variable (`vStartDL`, `vStartMI`, `vStart`). It is written once, by the INV-413 write that first records the version. So a counterfactual that marks more events later, or shares marks across versions, cannot move the start and make the property vacuous.
- Run 7's properties, which said a name skips nothing across its versions (reading (b)), are kept as labelled checks: `Chk_DeadLetterAlertedAcrossVersions` and `Chk_MissedAlertedAcrossVersions` in `…_settingsEdit`, and `Chk_EventAlertedAcrossVersions` in the two rolling-deploy cfgs. Where they fail, INV-413's notes accept it.
- Run 7's `sinceNameEval` switch (F-25 option 2) was removed, with its `Evaluate` action and four `…SinceEval` cfgs. The owner chose against it and recorded why in INV-413's notes. Under the new wording it no longer tests a reading of any sentence, so it added no information.
- State counts are unchanged, except `…_editBackPerName`: 13,385, was 12,220. There the per-version start is a history variable kept apart from the per-name marks of the counterfactual. With 4 workers, a trace can come out one or two states longer or shorter than in run 7.

| Configuration | What it checks | Result | Distinct states |
|---|---|---|---|
| `IntegrationsAlertEvents.cfg` | as written: INV-412 per recorded change, "delivered" per name, "before the start" per name and event settings, REQ-242 records written by a trigger, a schedule change or a pause; one job dead-lettered, requeued and dead-lettered again | one delivery per event ✓, every dead-letter after the start alerted ✓, every missed instant after the start alerted ✓, no alert for an event before the rule ✓ | 1,282 |
| `…_pauseReach.cfg` | vacuity: an instant recorded by a pause is alerted | trap violated as expected ✓ (5 states) | 1,282 |
| `…_noReq242.cfg` | counterfactual: REQ-242 dropped | missed instant after the start alerted ✗ (stuttering, 9 states), as expected | 853 |
| `…_perJob.cfg` | counterfactual: marks on the job | dead-letter after the start alerted ✗ (stuttering, 9 states), as expected | 384 |
| `…_newRule.cfg` | INV-413: rule added after events happened | all ✓ | 1,061 |
| `…_noInv413.cfg` | counterfactual: INV-413 dropped | no alert for an event before the rule ✗ (5 states), as expected; liveness ✓ | 3,420 |
| `…_readd.cfg` | rule removed and added back, records kept | one delivery ✓, both liveness ✓; no alert for an event while removed ✗ (7 states): accepted | 4,696 |
| `…_editTrigger.cfg` | trigger edited, name kept | all ✓ (liveness newly run here) | 3,215 |
| `…_editTriggerNameOnly.cfg` | counterfactual: run 4's wording, a rule known by name only | no alert for an event before the rule watched it ✗ (7 states), as expected; liveness ✓ | 1,997 |
| `…_editBack.cfg` | trigger edited, then put back | one delivery ✓, both liveness ✓, owed dead-letter alerted after the rollback ✓; no alert for an event before the rule ✗ (7 states): accepted | 14,474 |
| `…_editBackPerName.cfg` | counterfactual: run 5's other reading, both marks per name | dead-letter after the start alerted ✗ (stuttering, 10 states), owed dead-letter alerted after the rollback ✗ (10 states), as expected (run-5 F-23) | 13,385 |
| `…_editWiden.cfg` | trigger widened, narrowed back, widened again; the versions watch overlapping events | one delivery ✓, **both liveness ✓**, owed missed instant alerted on return ✓; owed dead-letter alerted on return ✗ (stuttering, 10 states): **accepted** (run-7 F-25, INV-413 notes); no alert for an event before the rule ✗ (8 states): accepted | 8,876 |
| `…_editWidenPerSettings.cfg` | counterfactual: run 6's wording on the widened trigger | one delivery per event ✗ (8 states), as expected (run-6 F-24); liveness ✓ | 13,056 |
| `…_settingsBack.cfg` | threshold or tolerance edited, then put back | all ✓ | 7,167 |
| `…_settingsBackPerSettings.cfg` | counterfactual: run 6's wording | one delivery per event ✗ (7 states), as expected; liveness ✓ | 13,187 |
| `…_settingsBackPerName.cfg` | counterfactual: run 5's other reading | dead-letter ✗ (9 states), missed instant ✗ (11 states), owed dead-letter after the rollback ✗ (10 states), all stuttering, as expected | 5,729 |
| `…_settingsFlap.cfg` | a rolling deploy that changes a threshold moves the lease between versions three times | all ✓ (liveness newly run here) | 12,753 |
| `…_settingsFlapPerSettings.cfg` | counterfactual: run 6's wording | one delivery per event ✗ (7 states), as expected; liveness ✓ | 24,793 |
| `…_settingsEdit.cfg` | threshold or tolerance edited once, never put back | one delivery ✓, **both liveness ✓** (were ✗ under run 7's wording); name-wide checks `Chk_*AcrossVersions` ✗ (stuttering, 7 states each): **accepted** (run-7 F-25, INV-413 notes) | 2,421 |
| `…_rename.cfg` | rule renamed, then the rename rolled back | one delivery per event per name ✓, both liveness ✓, owed dead-letter alerted on return ✓; one delivery per event under any name ✗ (7 states): **accepted** (run-7 F-26, INV-413 notes) | 13,187 |
| `…_newSystem.cfg` | rule in code from the start, store records no rule yet | one delivery ✓, both liveness ✓; every event while the rule is configured alerted ✗ (stuttering, 6 states): accepted (run-4 F-21) | 462 |
| `…_newSystemCatchUp.cfg` | run-4 F-21 option 2 (not chosen) | all ✓ | 1,036 |
| `IntegrationsAlerts.cfg` | one version, recorded; INV-412's write is a read, then a write that checks the lease and that the event is not yet delivered for the name | one delivery per event ✓, every event after the start alerted ✓, SCN-405 ✓ | 949 |
| `…_rollingSettings.cfg` | a rolling deploy that changes a threshold: a1 runs the recorded version, a2 the edited one; the lease moves between them across a crash or a pause; two-step writes | all ✓, and run 7's wider check `Chk_EventAlertedAcrossVersions` ✓ | 2,703 |
| `…_rollingSettingsPerSettings.cfg` | counterfactual: run 6's wording on the same deploy | one delivery per event ✗ (12 states), as expected; liveness ✓ | 3,915 |
| `…_rollingNew.cfg` | as `…_rollingSettings`, neither version recorded yet | all ✓, `Chk_EventAlertedAcrossVersions` ✓ | 5,492 |
| `…_newRule.cfg` | INV-413's write is a read, then a write that checks the lease and that the version is still unrecorded | all ✓ | 2,408 |
| `…_newRuleUnchecked.cfg` | counterfactual: run 4's INV-413 wording, an unchecked write | event after the start alerted ✗ (stuttering, 14 states), as expected | 3,160 |
| `…_newRuleFenced.cfg` | counterfactual: INV-413's write checks the lease only | event after the start alerted ✗ (stuttering, 14 states), as expected | 2,706 |
| `…_staleWrite.cfg` | counterfactual: run 4's INV-412 wording, a lease-only write | one delivery per event ✗ (13 states), as expected | 1,029 |
| `…_noInv412Replay.cfg` | counterfactual: INV-412 dropped, node memory replays | one delivery per event ✗ (7 states), as expected | 1,214 |
| `…_noInv412FromNow.cfg` | counterfactual: INV-412 dropped, node memory from now | event after the start alerted ✗ (stuttering, 7 states), as expected | 954 |
| `…_SCN404.cfg` | SCN-404 reachable | trap violated as expected ✓ (5 states) | 13 |
| `…_SCN406.cfg` | SCN-406 reachable, from its given | trap violated as expected ✓ (4 states) | 40 |
| `IntegrationsNotifications.cfg` (unchanged, rerun) | cooldown, cap, failure path | all ✓, no deadlock | 176,927 |
| `…_cap2.cfg` (unchanged, rerun) | cap of 2 | all ✓, no deadlock | 7,683,747 |
| `…_SCN400.cfg` (unchanged, rerun) | SCN-400 reachable | trap violated as expected ✓ (4 states) | 75 |
| `IntegrationsHttp.cfg` (unchanged, rerun) | allowlist, private addresses, redirects, credentials, SCN-401 | all ✓, no deadlock; `Chk_NoPayloadSecretAtAll` ✗ (4 states): accepted (run-1 F-10) | 5,392 |
| `…_transport.cfg`, `…_wildcard.cfg` (unchanged, rerun) | redirects at the transport, wildcard hosts | all ✓, no deadlock | 2,313 / 748 |
| `…_SCN402.cfg` (unchanged, rerun) | SCN-402 reachable | trap violated as expected ✓ (5 states) | 45 |
| `IntegrationsOutbox.cfg` (unchanged, rerun) | one job per row, every row relayed | all ✓ | 199 |
| `…_noRetentionAssumption.cfg` (unchanged, rerun) | counterfactual: A-13 dropped | one job per row ✗ (10 states), as expected | 74 |
| `…_operatorDelete.cfg`, `…_operatorDeletePause.cfg` (unchanged, rerun) | operator delete during a relay crash window, with and without a lease pause | one job per row ✗ (9 states each): accepted (run-2 F-16) | 74 / 98 |
| `…_SCN403.cfg` (unchanged, rerun) | SCN-403 reachable | trap violated as expected ✓ (9 states) | 61 |

Trace lengths are in states, as TLC reports them (the initial state counts as one). The unchanged models give the same results as when they were last run (run 4).

**Is the new liveness vacuous?** No. The same formula fails under seven counterfactuals that each differ from an as-written cfg in one switch: per-name marks (`…_editBackPerName`, `…_settingsBackPerName`), marks on the job (`…_perJob`), REQ-242 dropped (`…_noReq242`), an unchecked or lease-only INV-413 write (`…_newRuleUnchecked`, `…_newRuleFenced`), and node memory (`…_noInv412FromNow`). So its antecedent is reached in those spaces. In the as-written cfgs, the antecedent holds in every behaviour in which the rule stays configured and an event happens after the start.

## Changes since last run

| Finding | Status | Fingerprint |
|---|---|---|
| F-25 | resolved | ambiguity · Liv_MissedAlerted/settingsEdit · INV-412,INV-413 |
| F-26 | resolved | ambiguity · Chk_OneDeliveryPerEventAnyName/rename · INV-400,INV-412,INV-413,REQ-410 |

2 resolved, 0 new, 0 still open

How run 7's findings were re-checked:

| Run 7 | Evidence in run 8 |
|---|---|
| F-25 (INV-412's "nor a version … skips one" was wider than INV-413 gives) | INV-412 now says "skips one after its start (INV-413)". Restated to that reading, both liveness properties hold in every as-written cfg, including the two that failed in run 7: `…_settingsEdit` (2,421 states) and `…_editWiden` (8,876). Run 7's name-wide reading still fails there: `Chk_*AcrossVersions` (7 states each), and on the widened trigger `Chk_WatchedDeadLetterAlertedOnReturn` (10 states). INV-413's new notes accept that, so it is listed under *Accepted*. |
| F-26 (a renamed rule and its old name alert the same event twice) | Unchanged behaviour: `Chk_OneDeliveryPerEventAnyName` ✗ (7 states), per-name one delivery ✓, liveness ✓ (`…_rename`, 13,187 states). INV-413's notes now say a renamed rule is a new rule for both marks and that the per-rule cooldown does not merge the repeat. Accepted. |

**What the new wording could change, and what it does change.** Three readings of the new clause were checked:
- *Does "after its start" also scope "alerts an event again"?* The clause ends "… alerts an event again or skips one after its start". Read either way, the verdict is the same: no as-written cfg gives two deliveries for one name, whether or not the event is before a version's start. Recorded as A-32.
- *Whose start, for the node?* "Neither a node that takes over the notification lease nor a version … skips one after its start (INV-413)". Read alone, "its" could mean the node's start, which would let a new holder skip events from before it took the lease. The "(INV-413)" reference names the rule version's start. INV-412's notes also say that events from while no node holds the lease "are alerted when a holder next runs, for rules the store already records". The model follows the notes, and `IntegrationsAlerts` checks it: `Liv_EventAlerted` asks for events after the version's start, not the node's. Recorded as A-31, not a finding, because the notes settle it.
- *Does reading (a) agree with "continues where it stopped and skips nothing" (INV-413 notes, re-add and rollback)?* Yes. A version that comes back owes what happened after its own start, including while it was away. The new liveness checks this in `…_readd`, `…_editBack`, `…_settingsBack`, `…_editWiden` and `…_rename`. "Delivered" per name keeps it from repeating what another version of the same name sent. All ✓.

Nothing new comes from the changed wording, and no fix is needed in another module.

## Accepted (not findings)

- **An event between one version's last evaluation and the next version's first is alerted by neither** (INV-413 notes, run 7 F-25: "is before the next version's start and is alerted by neither, unless the previous version comes back"). This applies to an edit that is not rolled back, and to a rename. Seen as run 7's name-wide checks failing: `…_settingsEdit.cfg`, `Chk_DeadLetterAlertedAcrossVersions` and `Chk_MissedAlertedAcrossVersions` ✗ (7 states each), and `…_editWiden.cfg`, `Chk_WatchedDeadLetterAlertedOnReturn` ✗ (10 states). In both cfgs the requirement's own liveness holds.
- **A renamed rule and its old name each alert the same event** when the rename is rolled back, or when a rolling deploy moves the lease between nodes with the two names. The per-rule subject cooldown does not merge the two deliveries (INV-413 notes, run 7 F-26: "a renamed rule is a new rule for both marks … Rules that should share deliveries keep one name"). `…_rename.cfg`, `Chk_OneDeliveryPerEventAnyName` ✗ (7 states).
- **A rule starts at its first evaluation by a lease holder, not at its deploy** (run-4 F-21, INV-413 notes). On a new system, events before the first alerts node takes the notification lease are not alerted (`…_newSystem.cfg`, `Chk_ConfiguredEventAlerted` ✗, 6 states).
- **Removing and re-adding a rule alerts what happened while it was away** (INV-413 notes: "continues where it stopped and skips nothing"; `…_readd.cfg`, `Chk_NoAlertForEventBeforeRule` ✗, 7 states). The same holds for a version that is edited away and then put back (`…_editBack.cfg`, 7 states; `…_editWiden.cfg`, 8 states). It does not alert again what another version of the same name delivered meanwhile.
- **A missed instant dropped by an operator's pause is alerted** (recurring REQ-234 and REQ-242, run 5; `…_pauseReach.cfg`).
- **Operator delete during a relay crash window** (REQ-436 notes, run-2 F-16), and the same with a lease pause: `IntegrationsOutbox_operatorDelete.cfg` and `…_operatorDeletePause.cfg`, `Inv_OneJobPerRow` ✗, 9 states each, rerun this time.
- **INV-404 covers three headers and URL user info only** (run-1 F-10): `IntegrationsHttp.cfg`, `Chk_NoPayloadSecretAtAll` ✗, 4 states, rerun this time.

## Summary

No findings. The requirements as written hold in every as-written configuration. Every failing check is a counterfactual, a vacuity trap, or a case the notes accept (listed above).

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. A-1 to A-28 are from runs 1 to 7; changes are marked.

| # | Assumption | Affects |
|---|---|---|
| A-1 | REQ-400…REQ-406 are abstracted to "the rule fires for subject s" at any moment in the cooldown model. What they watch belongs to jobs, recurring and hosting. The alerts model makes two kinds explicit: edge events (REQ-400, REQ-401, REQ-403) and the state-based node-lost trigger (REQ-404, with NodeLostAfter from hosting REQ-60 as a nondeterministic "goes stale"). | REQ-400…REQ-406 |
| A-2 | Backoff has no clock: the next attempt may come at any later moment. | REQ-408, REQ-412 |
| A-3 | Cooldowns, NodeLostAfter, tolerance, MisfireThreshold, retention and LeaseDuration end as nondeterministic events. The model cannot judge durations: retry span vs cooldown, retention vs relay recovery (REQ-436), how long a pause must be to let a stale write land, or how long the accepted window between two versions is (INV-413 notes: "about one evaluation interval" with an alerts node running through the deploy). Nor can it judge how much storage per-version records and marks take over years of edits. | INV-400, INV-407, INV-410, REQ-414, REQ-436, INV-412, INV-413 |
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
| A-14 | Bounds: 1 rule, 2 subjects, 3 delivery slots (4 in `…_cap2`), NotificationMaxAttempts 2, MaxDeliveriesPerCooldown 1 (2 in `…_cap2`). 2 alerts nodes, 2 edge events, 2 rule versions in `IntegrationsAlerts_rolling*`. 2 dead-letters and 2 moves of one recurring job's nextRunAt or pauses in `IntegrationsAlertEvents`, up to 3 configuration changes (`…_settingsFlap*`, `…_editWiden*`), 2 rule names (`…_rename`). 1 HTTP job, up to 3 hosts, maxAttempts 2, MaxRedirects 0 (1 in `…_transport`). 1 outbox row, 2 worker nodes. | all |
| A-15 | `IntegrationsAlertEvents` has one alerts node holding the lease throughout, and each store write is one step (the find and the conditional write coincide). Handovers and writes split into a read and a later write are in `IntegrationsAlerts`. Rule evaluation, including INV-413's first evaluation, is fair (it happens if it stays possible) but has no deadline. | INV-411, INV-412, INV-413 |
| A-16 | Dead-letters and failed attempts are found through the job's state history (jobs INV-116). A late start is findable if the occurrence job keeps its due instant (`scheduledAt`), so it is not modeled. A missed instant is found through recurring REQ-242's record. | INV-412, REQ-403 |
| A-17 | A rule is known by its name and event settings (INV-413). In `IntegrationsAlertEvents`, the settings are the trigger (`watch`) and a version bit (`ver`) that stands for a threshold or tolerance. A trigger edit moves the rule to other events, a widened trigger adds events, a settings edit keeps the same events, and a rename (a name bit `nm`) gives it a new name. Records are added, never replaced. "Delivered" is kept per name and "before the start" per name and event settings, as written. Run 6's per-version marks and run 5's per-name marks are switches (`MarkScope`). Adding, removing and editing a rule are nondeterministic events, not fair, except in `…_readd.cfg` (re-add fair) and the edit-back cfgs (edits fair). A rolling deploy that moves the lease between nodes with and without the rule, with two versions of it, or with two names, is the same as a removal and re-add, an edit and rollback, or a rename and rollback. | INV-412, INV-413 |
| A-18 | In `IntegrationsAlertEvents` a requeue (jobs REQ-141) is folded into the second dead-letter of the same job. Retention (jobs REQ-145) and operator deletes are not modeled; INV-412's notes accept that a removed job is no longer alerted. | INV-412 |
| A-19 | In `IntegrationsAlertEvents` one rule stands for a rule per event kind (it watches dead-letters and missed occurrences, `InitialWatch`), except in the trigger-edit cfgs, where it watches one kind and the edit switches or widens it. INV-413 marks every stored event of every kind ("every such event"). | INV-413 |
| A-20 | One REQ-242 record (one move of nextRunAt or one pause, however many instants it passed) is one event for INV-412, so one delivery. | REQ-403, recurring REQ-242 |
| A-21 | In `IntegrationsAlerts` every INV-412 and INV-413 write is two steps: a read that decides it, and a write that checks the lease and its condition when it lands and, if either fails, changes nothing (the next evaluation reads again). The read takes an event that is neither delivered for the name nor before the start of the version the node runs. The write checks "not yet delivered for that name", as INV-412 says, and under run 6's wording also the version's start marks. A crash forgets a pending write. The node-memory counterfactuals keep a one-step write. | INV-411, INV-412, INV-413 |
| A-22 | A schedule change (recurring REQ-227) that moves nextRunAt past an overdue instant writes a REQ-242 record and no last outcome. | REQ-403, recurring REQ-227, REQ-242 |
| A-23 | A catch-up occurrence that starts later than the rule's tolerance after its due time would be a second event for REQ-403's "starts later" branch, with the same subject. It is not modeled (A-16), and the subject cooldown (INV-400) would merge the two deliveries. | REQ-403, INV-400, recurring REQ-242 |
| A-24 | A pause, orphaning or removal of the active recurring job with an overdue instant is one action, `PauseMissed`: it writes a REQ-242 record and no last outcome, and stops triggers. A resume writes nothing. Instants that fall due while paused are not missed (REQ-234) and are not modeled. | REQ-403, recurring REQ-242, REQ-234 |
| A-25 | The settings-edit, widen and rename cfgs start from a rule that has been running, so the store records its original version (`RecordedAtStart`). The other cfgs keep run 5's start (no record). | INV-412, INV-413 |
| A-26 | INV-412 is applied only to a version the store records. INV-412's notes say events are alerted "for rules the store already records" and "events before a rule's first evaluation are not (INV-413)". Read on its own, "neither delivered … nor before the start of its name and event settings" would also let a version with no record yet (so no start) deliver every stored event before INV-413 runs. The notes rule that out. | INV-412, INV-413 |
| A-27 | In `IntegrationsAlerts_rolling*` each node runs a fixed version (a1 the recorded one, a2 the edited one), both versions watch the same events (a threshold or tolerance edit), and the lease moves between them only through the one crash and the one pause of A-10 and A-11. Trigger edits and renames across a handover are not modeled there. They differ only in which events each version owns, which `IntegrationsAlertEvents` covers. | INV-412, INV-413 |
| A-28 | Deliveries are counted per rule name. `Inv_OneDeliveryPerEvent` is per name, as INV-412 says. `Chk_OneDeliveryPerEventAnyName` (any name) is a check of a reading the notes reject, not a requirement. | INV-412 |
| ~~A-29~~ | *(removed)* Run 7's assumption for F-25 option 2 (`sinceNameEval`); the option was not chosen and the switch is gone. | — |
| A-30 | *(new)* "Skips none after its start" is checked as: an event that a version watches and that is after its start is delivered for the name **once that version is configured for good** (in `IntegrationsAlerts`, once the lease stays with a running node that runs it). A version that is edited away for good owes nothing, which is what INV-413's notes accept ("unless the previous version comes back"). A version that comes back owes what happened after its start, including while it was away (INV-413 notes on re-add and rollback). With bounded changes, every behaviour ends in one configuration, so "for good" always comes. | INV-412, INV-413 |
| A-31 | *(new)* "Its start (INV-413)" in INV-412's purpose clause is the start of the rule's name and event settings, for the node branch too, not the time a node took the lease. The "(INV-413)" reference and INV-412's notes ("events that happen while no node holds the lease … are alerted when a holder next runs, for rules the store already records") say so. | INV-412 |
| A-32 | *(new)* Whether "after its start" also scopes "alerts an event again" does not change any result: no as-written cfg gives two deliveries for one name, before or after a start. | INV-412 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-400…REQ-409, REQ-412…REQ-416, INV-400, INV-407, INV-409, INV-410, INV-411, INV-412, INV-413, REQ-433, REQ-438 · REQ-420…REQ-422, REQ-434, INV-401…INV-404, INV-408 · REQ-430, REQ-432, REQ-435, REQ-436, INV-406, LIV-400 · SCN-400, SCN-402, SCN-403, SCN-404, SCN-406 (reachable), SCN-401, SCN-405 (hold) | REQ-410 (static merge of rule definitions and a page listing, no state change; its rule identity is used as A-17) · INV-405 (masking in the dashboard and logs is presentation) · REQ-431, REQ-437 (which enqueue path a configuration takes; no interleaving to explore) · REQ-411 (retired, moved to hosting REQ-60) |

Owner open questions already recorded, and not raised again here: no warning when rules exist but no node has the alerts registration, refused webhook hosts, and a test delivery left pending when no alerts node exists.

## Reproduce
From `specs/model/integrations/`, `python -X utf8 run_all.py` reruns everything in this report (about 8 minutes on a shared machine). `run_all.py IntegrationsAlert` reruns only the two alert models. Each check runs alone as `python run_tlc.py <Module>.tla --config <cfg with one INVARIANT or PROPERTY> --workers 4 --stop-at-first --no-deadlock`, killed after 400 s, plus a `TypeInv`-only run with deadlock checking for the HTTP and notification cfgs. Results land in `runs/` (gitignored), with a summary in `runs/summary.md`. Set `RUN_TLC` if `run_tlc.py` is not under `~/.claude-personal/skills/refiner-model/scripts/`.

## Next
Nothing to decide this run. If the accepted items and the assumptions above (A-30 to A-32 are new) match what you mean, the integrations module's logic is done for now. To change anything, edit `integrations.json` with the `refiner-requirements` skill (it validates and diffs), then run this skill again.
