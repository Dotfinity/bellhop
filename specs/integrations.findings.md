# Findings: Bellhop notifications, HTTP jobs, outbound HTTP and the outbox

<!-- refiner-findings v1 | module: integrations | specHash: 7b719d5882c5246ed81e99575065f7270c6f01162e77d443b96eeabee9fd070f | run: 2026-11-08 (run 7) | previous: model/integrations/previous.findings.md (run 6, specHash 60631c2ae000) -->

**Run:** 2026-11-08 (run 7, from `model/integrations/handoff.json`, base 319dd72: INV-412 and INV-413 modified, so there are now two marks: "delivered" per rule name and "before the start" per name and event settings. Nothing impacted.) · **Requirements file:** `specs/integrations.json` (specHash `7b719d5882c5`) · **Models:** `model/integrations/IntegrationsAlertEvents.tla` (INV-412, INV-413; regenerated) and `IntegrationsAlerts.tla` (INV-412, INV-413; regenerated: the two marks, plus two alerts nodes that may run two versions of the rule). `IntegrationsNotifications.tla`, `IntegrationsHttp.tla` and `IntegrationsOutbox.tla` are byte-for-byte unchanged and were not rerun, because nothing they model changed or was impacted. · **TLC:** 2.19 · **Result:** 2 findings: 0 contradictions · 0 gaps · 0 unprovable · 2 ambiguities · 0 modeling notes. Run 6's F-24 is resolved.

Every property ran in its own TLC run with `--stop-at-first --workers 4`, and each run was killed after 400 s if it had not finished. Three other modules were being checked on the same machine. No run threw a TLC exception or timed out; the largest space was 31,369 distinct states. `model/integrations/run_all.py IntegrationsAlert` reruns everything below (see *Reproduce*). The prose keeps only the steps of each trace that matter.

The two-mark wording is now the default in every as-written cfg. Run 6's per-version marks and run 5's per-name marks are kept as labelled counterfactuals (`…PerSettings`, `…PerName`). Run 6's four `…Split` cfgs were removed, because they are now the as-written cfgs with the same names minus `Split`. Their results are unchanged. Counterfactual state counts differ from run 6 (for example `…_editBackPerName` 12,220, was 11,354). The two marks are now kept apart, so states that one set of marks used to merge are now distinct. With 4 workers, a trace can also come out one state longer or shorter than in run 6.

| Configuration | What it checks | Result | Distinct states |
|---|---|---|---|
| `IntegrationsAlertEvents.cfg` | as written: INV-412 per recorded change, "delivered" per name, "before the start" per name and event settings, REQ-242 records written by a trigger, a schedule change or a pause; one job dead-lettered, requeued and dead-lettered again | one delivery per event ✓, every dead-letter alerted ✓, every missed instant alerted ✓, no alert for an event before the rule ✓ | 1,282 |
| `…_pauseReach.cfg` | vacuity: an instant recorded by a pause is alerted | trap violated as expected ✓ (4 states) | 1,282 |
| `…_noReq242.cfg` | counterfactual: REQ-242 dropped | every missed instant alerted ✗ (stuttering, 9 states), as expected | 853 |
| `…_perJob.cfg` | counterfactual: marks on the job | every dead-letter alerted ✗ (stuttering, 6 states), as expected | 384 |
| `…_newRule.cfg` | INV-413: rule added after events happened | all ✓ | 1,061 |
| `…_noInv413.cfg` | counterfactual: INV-413 dropped | no alert for an event before the rule ✗ (5 states), as expected | 3,420 |
| `…_readd.cfg` | **rerun under the two marks**: rule removed and added back, records kept | one delivery ✓, both liveness ✓; no alert for an event while removed ✗ (8 states): accepted | 4,696 |
| `…_editTrigger.cfg` | **rerun**: trigger edited, name kept | all ✓ | 3,215 |
| `…_editTriggerNameOnly.cfg` | counterfactual: run 4's wording, a rule known by name only | no alert for an event before the rule watched it ✗ (5 states), as expected | 1,997 |
| `…_editBack.cfg` | trigger edited, then put back; as written | one delivery ✓, a dead-letter owed before the edit is alerted after the rollback ✓; no alert for an event before the rule ✗ (6 states): accepted | 14,474 |
| `…_editBackPerName.cfg` | counterfactual: run 5's other reading, both marks per name | owed dead-letter alerted after the rollback ✗ (stuttering, 10 states), as expected (run-5 F-23) | 12,220 |
| `…_editWiden.cfg` (new) | trigger widened (dead-letters → dead-letters and missed occurrences), narrowed back, widened again; the two versions watch overlapping events; as written | one delivery ✓, owed missed instant alerted on return ✓; owed dead-letter alerted on return ✗ (stuttering, 10 states): **F-25**; no alert for an event before the rule ✗ (9 states): accepted | 8,876 |
| `…_editWidenPerSettings.cfg` (new) | counterfactual: run 6's wording on the widened trigger | one delivery per event ✗ (7 states): run-6 F-24 on overlapping triggers | 13,056 |
| `…_settingsBack.cfg` | **run-6 F-24 re-check**: threshold or tolerance edited, then put back; the rule has been running; as written | one delivery per event ✓ (was ✗), owed dead-letter alerted after the rollback ✓ | 7,167 |
| `…_settingsBackPerSettings.cfg` (was `…_settingsBack`) | counterfactual: run 6's wording | one delivery per event ✗ (7 states), as expected (F-24) | 13,187 |
| `…_settingsBackPerName.cfg` | counterfactual: run 5's other reading | owed dead-letter alerted after the rollback ✗ (stuttering, 10 states), as expected | 5,729 |
| `…_settingsFlap.cfg` | **F-24 re-check**: a rolling deploy that changes a threshold moves the lease between versions three times; as written | one delivery per event ✓ (was ✗) | 12,753 |
| `…_settingsFlapPerSettings.cfg` (was `…_settingsFlap`) | counterfactual: run 6's wording | one delivery per event ✗ (7 states), as expected | 24,793 |
| `…_settingsEdit.cfg` (new) | threshold or tolerance edited once, never put back; as written | one delivery ✓; every dead-letter alerted ✗ (stuttering, 10 states), every missed instant alerted ✗ (stuttering, 9 states): **F-25** | 2,421 |
| `…_rename.cfg` (new) | rule renamed, then the rename rolled back (or the lease moves between nodes with the two names); as written | one delivery per event per name ✓, owed dead-letter alerted on return ✓; **one delivery per event under any name ✗ (7 states): F-26** | 13,187 |
| `…_settingsEditSinceEval.cfg`, `…_editTriggerSinceEval.cfg`, `…_editWidenSinceEval.cfg`, `…_settingsBackSinceEval.cfg` (new) | F-25 option 2 (not a requirement): a new version's start spares what was recorded since the name's last evaluation | edit without rollback: all ✓ (5,170); trigger edit: one delivery ✓, no alert for an event before the rule ✗ (8 states), the cost of the option; widened trigger: all ✓ except the accepted "before the rule" ✗ (5 states) (31,369); settings edit-back: all ✓ (12,046) | 16,533 (trigger) |
| `…_newSystem.cfg` | **rerun**: rule in code from the start, store records no rule yet | one delivery ✓; every event while the rule is configured alerted ✗ (stuttering, 9 states): accepted (run-4 F-21) | 462 |
| `…_newSystemCatchUp.cfg` | run-4 F-21 option 2 (not chosen) | all ✓ | 1,036 |
| `IntegrationsAlerts.cfg` | **rerun under the two marks**: one version, recorded; INV-412's write is a read, then a write that checks the lease and that the event is not yet delivered for the name | one delivery per event ✓, every event alerted ✓, SCN-405 ✓ | 949 |
| `…_rollingSettings.cfg` (new) | a rolling deploy that changes a threshold: a1 runs the recorded version, a2 the edited one; the lease moves between them across a crash or a pause; every write is two steps; as written | one delivery per event ✓, every event alerted ✓, SCN-405 ✓ | 2,703 |
| `…_rollingSettingsPerSettings.cfg` (new) | counterfactual: run 6's wording on the same deploy | one delivery per event ✗ (12 states): run-6 F-24 across a lease handover | 3,915 |
| `…_rollingNew.cfg` (new) | as `…_rollingSettings`, neither version recorded yet: both nodes may run INV-413's two-step write for their own version | all ✓ | 5,492 |
| `…_newRule.cfg` | as written: INV-413's write is a read, then a write that checks the lease and that the version is still unrecorded | all ✓ | 2,408 |
| `…_newRuleUnchecked.cfg` | counterfactual: run 4's INV-413 wording, an unchecked write | every event alerted ✗ (stuttering, 14 states), as expected | 3,160 |
| `…_newRuleFenced.cfg` | counterfactual: INV-413's write checks the lease only | every event alerted ✗ (stuttering, 14 states), as expected | 2,706 |
| `…_staleWrite.cfg` | counterfactual: run 4's INV-412 wording, a lease-only write | one delivery per event ✗ (13 states), as expected | 1,029 |
| `…_noInv412Replay.cfg` | counterfactual: INV-412 dropped, node memory replays | one delivery per event ✗ (7 states), as expected | 1,214 |
| `…_noInv412FromNow.cfg` | counterfactual: INV-412 dropped, node memory from now | every event alerted ✗ (stuttering, 8 states), as expected | 954 |
| `…_SCN404.cfg` | SCN-404 reachable | trap violated as expected ✓ (5 states) | 13 |
| `…_SCN406.cfg` | SCN-406 reachable, from its given | trap violated as expected ✓ (4 states) | 38 |

Trace lengths are in states, as TLC reports them (the initial state counts as one).

## Changes since last run

| Finding | Status | Fingerprint |
|---|---|---|
| F-24 | resolved | ambiguity · Inv_OneDeliveryPerEvent/settingsBack · INV-412,INV-413,REQ-410 |
| F-25 | new | ambiguity · Liv_MissedAlerted/settingsEdit · INV-412,INV-413 |
| F-26 | new | ambiguity · Chk_OneDeliveryPerEventAnyName/rename · INV-400,INV-412,INV-413,REQ-410 |

1 resolved, 2 new, 0 still open

How run 6's finding was re-checked:

| Run 6 | Evidence in run 7 |
|---|---|
| F-24 (per-version marks: an event alerted by one version is alerted again by another after a rollback or on a rolling-deploy lease move) | With "delivered" per name, one delivery per event holds after a threshold or tolerance rollback (`…_settingsBack.cfg`, 7,167 states), on a three-move flap (`…_settingsFlap.cfg`, 12,753), on a widened trigger whose versions overlap (`…_editWiden.cfg`, 8,876), and across a real lease handover between two nodes on two versions with two-step writes (`IntegrationsAlerts_rollingSettings.cfg`, 2,703). The owed event is still alerted after a rollback, so run-5 F-23 stays resolved. Run 6's wording, kept as a counterfactual, still alerts twice (7, 7, 7 and 12 states). |

What the brief asked to rerun:
- **Re-add** (`…_readd.cfg`): unchanged, one delivery ✓ and both liveness ✓. A rule that comes back alerts what happened while it was away (accepted, see below).
- **New rule, new system, trigger edit**: unchanged results (`…_newRule`, `…_newSystem`, `…_editTrigger`).
- **Lease handover and stale writes** (`IntegrationsAlerts.tla`): with one version, the INV-412 write condition "not yet marked delivered for that name" gives one delivery per event (949 states, same count as run 6). A stale holder cannot gain a "before the start" mark between its read and its write. Only INV-413's first evaluation writes that mark, it runs only while the version is unrecorded, and INV-412 reads only recorded versions. So checking "delivered" alone at the write is enough. With two versions on two nodes (`…_rollingSettings`, `…_rollingNew`), this run checked the stale holder's write across a version change too. a1 reads an event as due for version A and pauses past LeaseDuration. a2 takes the lease on version B and either delivers the event (then a1's write fails on "delivered") or has it marked before B's start (then a1's write still lands, and delivers what A owed exactly once). Both hold.
- **Event delivered under one version and marked "before the start" under another**: reached in `…_settingsFlap`, `…_editWiden` and `…_rollingSettings`, both orders. No duplicate and no lost event follow from it.

New consequences of the split: none for duplicates within one name. Two edges remain, and both are about what happens *between* versions or names: F-25 (an event between one version's last evaluation and the next version's first), and F-26 (a rename, which the two-mark wording treats as a different rule).

## Accepted (not findings)

- **A rule starts at its first evaluation by a lease holder, not at its deploy** (run-4 F-21, INV-413 notes). On a new system, events before the first alerts node takes the notification lease are not alerted (`…_newSystem.cfg`, 9 states).
- **Removing and re-adding a rule alerts what happened while it was away** (INV-413 notes: "continues where it stopped and skips nothing"; `…_readd.cfg`, 8 states). The same holds for a version that is edited away and then put back (`…_editBack.cfg`, 6 states; `…_editWiden.cfg`, 9 states). Since run 7 it does not alert again what another version of the same name delivered meanwhile.
- **A missed instant dropped by an operator's pause is alerted** (recurring REQ-234 and REQ-242, run 5).
- **Operator delete during a relay crash window** (REQ-436 notes, run-2 F-16), and the same with a lease pause. Not rerun, model unchanged: `IntegrationsOutbox_operatorDelete.cfg` and `…_operatorDeletePause.cfg`, `Inv_OneJobPerRow` ✗, 9 steps each in run 4.
- **INV-404 covers three headers and URL user info only** (run-1 F-10). Not rerun, model unchanged: `Chk_NoPayloadSecretAtAll` ✗, 4 steps in run 4.

Run 6 listed one more item here: events between the old version's last evaluation and the new version's first are alerted by neither. INV-412's new purpose clause now appears to promise the opposite, so that item is F-25 this run.

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-25 | ambiguity | low | INV-412, INV-413 | INV-412 now says a version of the rule that takes over from another "skips" no event, but INV-413 still starts an edited version at the store's present, so an event recorded just before the edit is alerted by neither version. |
| F-26 | ambiguity | low | INV-412, INV-413, REQ-410, INV-400 | A renamed rule and its old name each alert the same event when the rename is rolled back or a rolling deploy moves the lease between them, and the per-rule cooldown does not merge the two. |

---

## F-25 · ambiguity · low — "Nor a version that takes over … skips one" is wider than INV-413 gives
<!-- finding: ambiguity | Liv_MissedAlerted/settingsEdit | INV-412,INV-413 -->

**Requirements involved**
- INV-412: *… for each one that is neither delivered for the rule's name nor before the start of its name and event settings (INV-413), create its delivery … so that neither a node that takes over the notification lease **nor a version of the rule that takes over from another** alerts an event again **or skips one**.*
- INV-413: *… when the notification lease holder evaluates a rule whose name and event settings … the job store has no record of, … record the rule's name and event settings and **mark every such event the store records as before the start** of that name and those event settings …*
- INV-412 notes: *"Events that happen while no node holds the lease, or while no alerts node runs at all, are alerted when a holder next runs, **for rules the store already records**; events before a rule's first evaluation are not (INV-413)."*

**What happens** (TLC, `Liv_MissedAlerted`, `IntegrationsAlertEvents_settingsEdit.cfg`, 9 states, stuttering; `Liv_DeadLetterAlerted` gives the dead-letter version, 10 states)
1. Rule `ops-alerts` watches missed recurring occurrences with a 5-minute tolerance and has been running, so the store records it (INV-413).
2. `nightly-export`'s schedule is changed while its 02:00 instant is overdue. REQ-242 records the instant as missed. The holder has not evaluated the rule since.
3. A developer lowers the tolerance to 2 minutes, keeps the name, and deploys. The 5-minute version is never evaluated again.
4. The holder evaluates the edited rule. The store has no record of `ops-alerts` with a 2-minute tolerance, so INV-413 marks every stored event, the 02:00 miss included, as before the start of the new version.
5. **The 02:00 miss is never alerted.** It is before the new version's start, and the version that owed it does not come back.

The window is the time between the old version's last evaluation and the new version's first. That is at least one evaluation interval, and longer if the deploy leaves no alerts node running for a while. A widened trigger shows the same thing (`…_editWiden.cfg`, `Chk_WatchedDeadLetterAlertedOnReturn`, 10 states). A dead-letter recorded under the narrow version, just before the second widening, is marked before the wide version's start.

**Why** Runs 4 to 6 accepted this gap: an edited rule is a new rule and starts at the store's present (run-4 F-22, so a lowered threshold does not alert the stored backlog), and run 6 listed it under *Accepted*. Run 6's F-24 snippet, which the owner applied, added "nor a version of the rule that takes over from another … skips one" to INV-412. That phrase came from this skill's own text, and it has two readings:
- (a) A version skips none of *its own* events, the ones after its start. This holds in every cfg (`…_settingsBack`, `…_editBack`, `…_editWiden` for missed instants, `…_rename`).
- (b) Across its versions, a rule name skips no event it watches. This fails in the trace above.

`must` sentences should not need the reader to pick one.

**Options**
1. *(recommended)* **Say reading (a) in the sentence and record the gap.** End INV-412's purpose clause with "… alerts an event again or skips one after its start (INV-413)", and add one line to INV-413's notes. Wording only: no state, no new behaviour, and it keeps what the owner accepted in runs 4 to 6. Cost: the gap stays. An event recorded between the old version's last evaluation and the new version's first is lost unless the old version comes back. Running an alerts node through the deploy keeps the window to about one evaluation interval.
2. **Close the gap: a new version starts where its name stopped.** INV-413 marks before the start only the events the store had recorded at the rule name's last evaluation, and the store keeps that point per name. On a name never evaluated before, the start stays at the store's present.
   - **Checked** (`RuleStart = "sinceNameEval"`): the edit without rollback alerts everything (`…_settingsEditSinceEval.cfg`, 5,170 states, both liveness ✓); the widened trigger and the settings rollback keep their results (`…_editWidenSinceEval`, `…_settingsBackSinceEval`).
   - **Cost:** a new store record (the name's last evaluation point, written at the end of every evaluation). A trigger edit then alerts the new trigger's events from that window too (`…_editTriggerSinceEval.cfg`, `Chk_NoAlertForEventBeforeRule` ✗, 8 states). That is a small slice of the backlog run-4 F-22 kept out. A rule removed for weeks and re-added with new settings would alert those weeks.
3. **Keep the sentence and say reading (a) in the notes only.** Cheapest, but the `must` sentence keeps reading as (b) to anyone who skips the notes.

**Ready to apply (option 1)**
```json
{ "id": "INV-412", "ears": {
    "where": "a rule watches an event that is a single recorded state change: a job dead-lettered (REQ-400), an attempt that makes the Nth failure (REQ-401), or a recurring occurrence missed or late (REQ-403); a job that is requeued (jobs REQ-141, REQ-143) can produce such an event again",
    "shall": "find those events from what the job store records and, for each one that is neither delivered for the rule's name nor before the start of its name and event settings (INV-413), create its delivery and mark the event delivered for the rule's name in one store write that succeeds only if the event is not yet marked delivered for that name, so that neither a node that takes over the notification lease nor a version of the rule that takes over from another alerts an event again or skips one after its start (INV-413)" } }
{ "id": "INV-413",
  "notes": "<existing notes> refiner-model 2026-11-08 run 7 F-25 (recommended option): INV-412's 'skips none' is about the events after a version's start. An event recorded between the last evaluation of one version and the first evaluation of the next (an edit that is not rolled back, or a rename) is before the next version's start and is alerted by neither, unless the previous version comes back. Keeping an alerts node running through the deploy keeps that window to about one evaluation interval. Starting a new version where its name last stopped was not chosen: it needs a per-name evaluation point and alerts a slice of the new trigger's backlog (run 4 F-22)." }
```

---

## F-26 · ambiguity · low — A renamed rule and its old name alert the same event twice
<!-- finding: ambiguity | Chk_OneDeliveryPerEventAnyName/rename | INV-400,INV-412,INV-413,REQ-410 -->

**Requirements involved**
- INV-412: *… mark the event delivered **for the rule's name** … succeeds only if the event is not yet marked delivered for that name …* Notes: *"'delivered' is kept per rule name, the rule's identity for users and for the subject cooldown (REQ-410, INV-400)".*
- INV-413 notes: *"Its records and start marks are kept per name and event settings even while no node loads the rule, so removing and re-adding it … continues where it stopped and skips nothing. **A renamed rule is a new rule.**"*
- REQ-410: rules are identified by name; the code definition wins.
- INV-400: one delivery per rule and subject within a cooldown.

**What happens** (TLC, `Chk_OneDeliveryPerEventAnyName`, `IntegrationsAlertEvents_rename.cfg`, 7 states)
1. Rule `ops-alerts` watches dead-letters and has been running; the store records it.
2. A developer renames it `ops-dead-letters` and deploys. The holder evaluates the new name for the first time and INV-413 records it (nothing stored yet to mark).
3. `invoice-sync` is dead-lettered. The holder alerts it under `ops-dead-letters` and marks it delivered for that name (INV-412). Delivery 1.
4. The rename is rolled back, or a rolling deploy moves the lease back to a node that still has `ops-alerts`. The store has a record of `ops-alerts`, so INV-413 does not apply, and the rule continues where it stopped.
5. The dead-letter is neither delivered for `ops-alerts` nor before its start, so **INV-412 alerts it again**. Delivery 2, under the old name. The subject cooldown is kept per rule, so it does not suppress this one.

Per name, the requirement holds: each name alerts the event once (`Inv_OneDeliveryPerEvent` ✓, 13,187 states). The owed dead-letter is still alerted on return (✓). During a rolling deploy that renames a rule, every event in the overlap can go out once under each name. If the rename is never rolled back, nothing is sent twice, but F-25's window applies to the new name.

**Why** Two rules with different names that watch the same event should both alert it; that is what two rules are for. A rename is the one case where the two names are meant to be one rule, and nothing in the requirements links them. Run 6's F-24 fix made the name the unit of "delivered", so a rename is now the only edit that can repeat an alert, and this run is the first that modeled one.

**Options**
1. *(recommended)* **Accept and say so.** Add to INV-413's notes that a rename rolled back, or a rolling deploy moving the lease between the two names, re-alerts under the old name what the new name delivered, and that the per-rule cooldown does not merge them. Notes only. Cost: duplicates during rename deploys and rollbacks, which are rare and visible on the Notifications page as two rules.
2. **Let a rule name the names it replaces.** Give `NotificationRule` a `formerNames` attribute; INV-412 treats an event as delivered for a rule if it is delivered for its name or for one of its former names. No duplicates. Cost: a new attribute, a REQ-410 sentence about it, a wider write condition in INV-412, and a decision on what `formerNames` means for INV-400's cooldown. Not checked in this run.
3. **Mark "delivered" per event across all rules.** Not recommended: two different rules that watch dead-letters, for example one for e-mail and one for a webhook, would then deliver once between them.

**Ready to apply (option 1)**
```json
{ "id": "INV-413",
  "notes": "<existing notes> refiner-model 2026-11-08 run 7 F-26 (recommended option): a renamed rule is a new rule for both marks. When a rename is rolled back, or a rolling deploy moves the lease between nodes with the old and the new name, the old name alerts what happened while it was away, including events the new name already delivered, and the subject cooldown, kept per rule (INV-400), does not suppress the repeat." }
```

If option 1 is chosen for both findings, the two INV-413 notes lines can be appended together.

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun. A-1 to A-25 are from runs 1 to 6; changes are marked.

| # | Assumption | Affects |
|---|---|---|
| A-1 | REQ-400…REQ-406 are abstracted to "the rule fires for subject s" at any moment in the cooldown model. What they watch belongs to jobs, recurring and hosting. The alerts model makes two kinds explicit: edge events (REQ-400, REQ-401, REQ-403) and the state-based node-lost trigger (REQ-404, with NodeLostAfter from hosting REQ-60 as a nondeterministic "goes stale"). | REQ-400…REQ-406 |
| A-2 | Backoff has no clock: the next attempt may come at any later moment. | REQ-408, REQ-412 |
| A-3 | *(changed)* Cooldowns, NodeLostAfter, tolerance, MisfireThreshold, retention and LeaseDuration end as nondeterministic events. The model cannot judge durations: retry span vs cooldown, retention vs relay recovery (REQ-436), how long a pause must be to let a stale write land, how long F-25's window is, or whether F-26's repeat falls inside a cooldown (it does not, the cooldown is per rule). Nor can it judge how much storage per-version records and marks take over years of edits. | INV-400, INV-407, INV-410, REQ-414, REQ-436, INV-412, INV-413 |
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
| A-14 | *(changed)* Bounds: 1 rule, 2 subjects, 3 delivery slots (4 in `…_cap2`), NotificationMaxAttempts 2, MaxDeliveriesPerCooldown 1 (2 in `…_cap2`). 2 alerts nodes, 2 edge events, 2 rule versions in `IntegrationsAlerts_rolling*`. 2 dead-letters and 2 moves of one recurring job's nextRunAt or pauses in `IntegrationsAlertEvents`, up to 3 configuration changes (`…_settingsFlap*`, `…_editWiden*`), 2 rule names (`…_rename`). 1 HTTP job, up to 3 hosts, maxAttempts 2, MaxRedirects 0 (1 in `…_transport`). 1 outbox row, 2 worker nodes. | all |
| A-15 | `IntegrationsAlertEvents` has one alerts node holding the lease throughout, and each store write is one step (the find and the conditional write coincide). Handovers and writes split into a read and a later write are in `IntegrationsAlerts`. Rule evaluation, including INV-413's first evaluation, is fair (it happens if it stays possible) but has no deadline. | INV-411, INV-412, INV-413 |
| A-16 | Dead-letters and failed attempts are found through the job's state history (jobs INV-116). A late start is findable if the occurrence job keeps its due instant (`scheduledAt`), so it is not modeled. A missed instant is found through recurring REQ-242's record. | INV-412, REQ-403 |
| A-17 | *(changed)* A rule is known by its name and event settings (INV-413). In `IntegrationsAlertEvents`, the settings are the trigger (`watch`) and a version bit (`ver`) that stands for a threshold or tolerance. A trigger edit moves the rule to other events, a widened trigger (run 7) adds events, a settings edit keeps the same events, and a rename (run 7, a name bit `nm`) gives it a new name. Records are added, never replaced. "Delivered" is kept per name and "before the start" per name and event settings, as written. Run 6's per-version marks and run 5's per-name marks are switches (`MarkScope`). Adding, removing and editing a rule are nondeterministic events, not fair, except in `…_readd.cfg` (re-add fair) and the edit-back cfgs (edits fair). A rolling deploy that moves the lease between nodes with and without the rule, with two versions of it, or with two names, is the same as a removal and re-add, an edit and rollback, or a rename and rollback. | INV-412, INV-413, F-25, F-26 |
| A-18 | In `IntegrationsAlertEvents` a requeue (jobs REQ-141) is folded into the second dead-letter of the same job. Retention (jobs REQ-145) and operator deletes are not modeled; INV-412's notes accept that a removed job is no longer alerted. | INV-412 |
| A-19 | In `IntegrationsAlertEvents` one rule stands for a rule per event kind (it watches dead-letters and missed occurrences, `InitialWatch`), except in the trigger-edit cfgs, where it watches one kind and the edit switches or widens it. INV-413 marks every stored event of every kind ("every such event"). | INV-413 |
| A-20 | One REQ-242 record (one move of nextRunAt or one pause, however many instants it passed) is one event for INV-412, so one delivery. | REQ-403, recurring REQ-242 |
| A-21 | *(changed)* In `IntegrationsAlerts` every INV-412 and INV-413 write is two steps: a read that decides it, and a write that checks the lease and its condition when it lands and, if either fails, changes nothing (the next evaluation reads again). The read takes an event that is neither delivered for the name nor before the start of the version the node runs. The write checks "not yet delivered for that name", as INV-412 now says, and under run 6's wording also the version's start marks. A crash forgets a pending write. The node-memory counterfactuals keep a one-step write. | INV-411, INV-412, INV-413 |
| A-22 | A schedule change (recurring REQ-227) that moves nextRunAt past an overdue instant writes a REQ-242 record and no last outcome. | REQ-403, recurring REQ-227, REQ-242 |
| A-23 | A catch-up occurrence that starts later than the rule's tolerance after its due time would be a second event for REQ-403's "starts later" branch, with the same subject. It is not modeled (A-16), and the subject cooldown (INV-400) would merge the two deliveries. | REQ-403, INV-400, recurring REQ-242 |
| A-24 | A pause, orphaning or removal of the active recurring job with an overdue instant is one action, `PauseMissed`: it writes a REQ-242 record and no last outcome, and stops triggers. A resume writes nothing. Instants that fall due while paused are not missed (REQ-234) and are not modeled. | REQ-403, recurring REQ-242, REQ-234 |
| A-25 | The settings-edit, widen and rename cfgs start from a rule that has been running, so the store records its original version (`RecordedAtStart`). The other cfgs keep run 5's start (no record). | F-24, F-25, F-26 |
| A-26 | *(new)* INV-412 is applied only to a version the store records. INV-412's notes say events are alerted "for rules the store already records" and "events before a rule's first evaluation are not (INV-413)". Read on its own, the new phrase "neither delivered … nor before the start of its name and event settings" would also let a version with no record yet (so no start) deliver every stored event before INV-413 runs. The notes rule that out, so it is an assumption, not a finding. | INV-412, INV-413 |
| A-27 | *(new)* In `IntegrationsAlerts_rolling*` each node runs a fixed version (a1 the recorded one, a2 the edited one), both versions watch the same events (a threshold or tolerance edit), and the lease moves between them only through the one crash and the one pause of A-10 and A-11. Trigger edits and renames across a handover are not modeled there. They differ only in which events each version owns, which `IntegrationsAlertEvents` covers. | INV-412, INV-413 |
| A-28 | *(new)* Deliveries are counted per rule name. `Inv_OneDeliveryPerEvent` is per name, as INV-412 says. `Chk_OneDeliveryPerEventAnyName` (any name) is a check of one reading, not a requirement. | INV-412, F-26 |
| A-29 | *(new)* F-25 option 2 only: an evaluation ends with nothing due for the rule as configured (`Evaluate`), and only then does the store keep the name's position. That position is the dead-letters and miss records stored at that point. A rule that has been running starts with a position of "nothing stored". | F-25 |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-400…REQ-409, REQ-412…REQ-416, INV-400, INV-407, INV-409, INV-410, INV-411, INV-412, INV-413, REQ-433, REQ-438 · REQ-420…REQ-422, REQ-434, INV-401…INV-404, INV-408 · REQ-430, REQ-432, REQ-435, REQ-436, INV-406, LIV-400 · SCN-400, SCN-402, SCN-403, SCN-404, SCN-406 (reachable), SCN-401, SCN-405 (hold) | REQ-410 (static merge of rule definitions and a page listing, no state change; its rule identity is used as A-17) · INV-405 (masking in the dashboard and logs is presentation) · REQ-431, REQ-437 (which enqueue path a configuration takes; no interleaving to explore) · REQ-411 (retired, moved to hosting REQ-60) |

Owner open questions already recorded, and not raised again here: no warning when rules exist but no node has the alerts registration, refused webhook hosts, and a test delivery left pending when no alerts node exists. Neither finding needs a change in another module.

## Reproduce
From `specs/model/integrations/`, `python -X utf8 run_all.py IntegrationsAlert` reruns this run's two alert models. Without an argument it reruns everything, including the three unchanged models. Each check runs alone as `python run_tlc.py <Module>.tla --config <cfg with one INVARIANT or PROPERTY> --workers 4 --stop-at-first --no-deadlock`, killed after 400 s, plus a `TypeInv`-only run with deadlock checking for the HTTP and notification cfgs. Run 7 raised the workers from 2 to 4 and the timeout from 170 s to 400 s in `run_all.py`. Results land in `runs/` (gitignored), with a summary in `runs/summary.md`. Set `RUN_TLC` if `run_tlc.py` is not under `~/.claude-personal/skills/refiner-model/scripts/`.

## Next
Apply the chosen options to `integrations.json` with the `refiner-requirements` skill (it validates and diffs), then run this skill again. Decide F-25 first: it is about a `must` sentence that the last round's snippet widened. Its option 1 changes four words in INV-412 and adds one note to INV-413. F-26's option 1 is a note on the same item.
