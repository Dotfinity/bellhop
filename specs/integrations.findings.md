# Findings: Bellhop notifications, HTTP jobs, outbound HTTP and the outbox

<!-- refiner-findings v1 | module: integrations | specHash: 3b92b190e27a93f98482220c751a5a6caf29d449158d98974cc3c0abbe884718 | run: 2026-11-06 | previous: model/integrations/previous.findings.md (run 1, specHash 1ada134dcb35) -->

**Run:** 2026-11-06 (run 2, from `model/integrations/handoff.json`) · **Requirements file:** `specs/integrations.json` (specHash `3b92b190e27a`) · **Models:** `model/integrations/IntegrationsNotifications.tla`, `IntegrationsAlerts.tla` (new), `IntegrationsHttp.tla`, `IntegrationsOutbox.tla` · **TLC:** 2.19, Java 25 · **Result:** 3 findings: 1 contradiction · 1 gap · 0 unprovable · 1 ambiguity · 0 modeling notes. All 13 findings of run 1 are resolved.

Every property ran in its own TLC run with `--stop-at-first`, so every trace below is the shortest one. Deadlock checking was a separate `TypeInv`-only run, wherever a deadlock would be a finding. No run threw a TLC exception, and no run timed out. `model/integrations/run_all.py` reruns everything (see *Reproduce*).

| Configuration | What it checks | Result | Distinct states |
|---|---|---|---|
| `IntegrationsNotifications.cfg` | cooldown rules as written (INV-409, INV-410, REQ-433); cap 1 | INV-400 ✓, INV-407 ✓, run-1 probe F-3 ✓, deadlock ✓ | 176,927 |
| `…_cap2.cfg` | cap 2, 4 delivery slots | INV-400 ✓, INV-407 ✓, deadlock ✓ | 7,683,747 |
| `…_SCN400.cfg` | SCN-400 reachable | trap violated as expected ✓ (4 steps) | 30 |
| `IntegrationsAlerts_storeCursor.cfg` | lease + "event marked handled in the store" | one delivery per event ✓, every event alerted ✓, SCN-405 ✓ | 445 |
| `…_nodeReplay.cfg` | lease + "each node remembers what it handled" | **one delivery per event ✗ (7 steps)**, every event alerted ✓, SCN-405 ✓ | 1,214 |
| `…_nodeFromNow.cfg` | lease + "a new holder starts from now" | one delivery per event ✓, **every event alerted ✗ (stuttering, 8 steps)**, SCN-405 ✓ | 954 |
| `…_SCN404.cfg` | SCN-404 reachable | trap violated as expected ✓ (5 steps) | 13 |
| `IntegrationsHttp.cfg` | main | INV-401 ✓, INV-402 ✓, INV-403 ✓, INV-404 ✓, SCN-401 ✓, deadlock ✓; **redirect probe ✗ (5 steps)**; run-1 check `Chk_NoPayloadSecretAtAll` ✗ (4, expected, see F-10 below) | 6,160 |
| `…_wildcard.cfg` | private host allowed only through a wildcard | INV-401 ✓, INV-402 ✓, deadlock ✓ | 844 |
| `…_transport.cfg` | allowed host only, MaxRedirects 1 | INV-401 ✓, INV-403 ✓, deadlock ✓ | 2,601 |
| `…_SCN402.cfg` | SCN-402 reachable | trap violated as expected ✓ (5 steps) | 41 |
| `IntegrationsOutbox.cfg` | REQ-432 + REQ-435 + REQ-436, one crash, one lease pause | INV-406 ✓, LIV-400 ✓ | 199 |
| `…_noRetentionAssumption.cfg` | REQ-436 dropped | INV-406 ✗ (10 steps): the assumption carries the guarantee, as REQ-436 says | 68 |
| `…_operatorDelete.cfg` | an operator deletes the job in the crash window | **INV-406 ✗ (9 steps)** | 66 |
| `…_SCN403.cfg` | SCN-403 reachable | trap violated as expected ✓ (9 steps) | 57 |

## Changes since last run

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | contradiction · Inv_OneSendPerSubjectCooldown · INV-400,INV-407,REQ-400,REQ-401,REQ-402,REQ-403,REQ-404,REQ-405,REQ-406 |
| F-2 | resolved | contradiction · Inv_OneSendPerSubjectCooldown/atCreate · INV-400,INV-407,REQ-408,REQ-412 |
| F-3 | resolved | gap · Probe_FailedThenSilent · INV-400,REQ-414,REQ-415 |
| F-4 | resolved | ambiguity · cooldown · INV-400,INV-407,REQ-414 |
| F-5 | resolved | ambiguity · REQ-401 · REQ-401 |
| F-6 | resolved | gap · REQ-404 · REQ-403,REQ-404,hosting.REQ-40 |
| F-7 | resolved | gap · Deadlock · INV-401,INV-402,INV-403,REQ-420,REQ-421,REQ-422 |
| F-8 | resolved | ambiguity · INV-402 · INV-401,INV-402 |
| F-9 | resolved | contradiction · Inv_NoPayloadCredentials · INV-404,INV-408,REQ-420 |
| F-10 | resolved | ambiguity · Inv_NoPayloadCredentials/allPaths · INV-404,INV-408 |
| F-11 | resolved | contradiction · Inv_OneJobPerRow · INV-406,REQ-432,jobs.REQ-107,jobs.REQ-145 |
| F-12 | resolved | unprovable · Liv_RowRelayed · LIV-400,REQ-432,SCN-403 |
| F-13 | resolved | gap · EnqueueAsync · REQ-430,REQ-431 |
| F-14 | new | contradiction · Probe_RedirectOneRule · INV-403,REQ-416,REQ-421,REQ-422,REQ-434 |
| F-15 | new | ambiguity · Chk_OneDeliveryPerEvent · INV-411,REQ-400,REQ-401,REQ-403,REQ-438 |
| F-16 | new | gap · Inv_OneJobPerRow/operatorDelete · INV-406,REQ-432,REQ-436,jobs.REQ-144 |

13 resolved, 3 new, 0 still open

How each run-1 finding was re-checked:

| Run 1 | Evidence in run 2 |
|---|---|
| F-1 (no Pending/Suppressed rule) | INV-409 decides at creation. `Inv_OneSendPerSubjectCooldown` and `Inv_RuleCap` hold in `IntegrationsNotifications.cfg` (176,927 states) and `…_cap2.cfg` (7,683,747 states). |
| F-2 (retrying delivery outlives the cooldown) | INV-410 holds the cooldowns open while a delivery created in them is pending; same two runs hold. |
| F-3 (failed first alert silences the cooldown) | REQ-433 closes the subject cooldown on failure. Run 1's probe `Probe_FailedThenSilent` now holds (176,927 states). |
| F-4 (one cooldown or two) | Glossary `cooldown`, `SubjectCooldown`, `RuleCooldown` and INV-409 name two periods; the model encodes both. Static. |
| F-5 ("fails for the Nth time") | REQ-401 now says "an attempt … ends with an exception or a timeout and the job's attempt number is N, whether the job becomes failed or dead-lettered". Static. |
| F-6 (no node-lost alert without a worker) | SCN-404 reachable: alerts node c1 (no worker) takes the lease and alerts on w1, the only worker, while it is down (5 steps). |
| F-7 (HTTP job stuck in Processing) | REQ-422 covers transport errors, REQ-434 dead-letters refused destinations. Deadlock runs pass in all three HTTP cfgs. |
| F-8 (allowlist vs private address) | INV-402 requires the host's own allowlist entry. `Inv_NoPrivate` holds in `…_wildcard.cfg` (a private host behind a wildcard is refused) and in the main run (a private host listed by name is called). |
| F-9 (launch page / configuration bypass INV-408) | INV-408 now covers every creation path. `Inv_NoPayloadCredentials` holds (6,160 states). |
| F-10 (INV-404 broader than INV-408) | INV-404 now names exactly the three headers and URL user info. Run 1's broader check `Chk_NoPayloadSecretAtAll` is still violated (an `X-Api-Key` header from the payload is sent, 4 steps), which INV-404's notes now accept on purpose. |
| F-11 (relay duplicates a finished job) | REQ-432 checks the outboxId against every stored job. `Inv_OneJobPerRow` holds (199 states) under REQ-436. Without REQ-436 it fails (10 steps), as REQ-436's notes say. A different path remains, see F-16. |
| F-12 (nobody takes over the relay lease) | REQ-435 obliges a running worker node to take it. `Liv_RowRelayed` holds with weak fairness on the takeover (199 states). |
| F-13 (`dbContext.EnqueueAsync` without outbox) | REQ-437 rejects the call. Static: nothing to explore (receipt `skipped`). |

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-14 | contradiction | medium | REQ-434, REQ-422, REQ-421, INV-403, REQ-416 | An unfollowed redirect is both a retryable failure (REQ-422) and a refusal that dead-letters at once (REQ-434) |
| F-15 | ambiguity | medium | INV-411, REQ-438, REQ-400, REQ-401, REQ-403 | After a notification-lease handover, an edge event (a dead-letter, the Nth failure, a missed occurrence) is alerted twice or not at all, depending on a rule nobody wrote |
| F-16 | gap | low | INV-406, REQ-432, REQ-436, jobs REQ-144 | An operator who deletes an outbox job during a relay crash window gets it back as a second job |

---

## F-14 · contradiction · medium — An unfollowed redirect is both a retryable failure and an immediate dead-letter
<!-- finding: contradiction | Probe_RedirectOneRule | INV-403,REQ-416,REQ-421,REQ-422,REQ-434 -->

**Requirements involved**
- REQ-434: *While an HTTP job is processing, if its destination is refused by the destination allowlist, the private-address rule **or the redirect rules**, then the system shall move the job to dead-lettered at once, without sending the request, with a reason that names the rule that refused it.*
- REQ-422: *… if the response status is not accepted, … then the system shall fail the attempt so the retry policy decides between Failed and DeadLettered …* Its notes (owner decision): *"With MaxRedirects 0 (REQ-416) a 3xx response is not followed and counts as not accepted unless listed."*
- REQ-421: *… if its status is one of the accepted status codes …, the system shall mark the job succeeded …*
- INV-403: *The system shall never follow a redirect to a different host and never follow more than MaxRedirects redirects.*

**What happens** (TLC, `Probe_RedirectOneRule`, `IntegrationsHttp.cfg`, 5 steps)
1. The application enqueues HTTP job j1 to `api` (on the allowlist), accepting 200 only (INV-408 passes).
2. A worker claims j1, attempt 1 (jobs REQ-123).
3. The request is sent (REQ-420).
4. `api` answers 302 to another path on the same host. MaxRedirects is 0 (REQ-416), so INV-403 forbids following it.
5. **Two rules now apply.** REQ-422, as its notes read, fails the attempt and retries (job → Failed, retry due). REQ-434 dead-letters j1 at once, because the redirect rules refused the destination. If the job had listed 302 as accepted, REQ-421 would instead mark it Succeeded.

**Why** INV-403 never follows a redirect to another host, so the target of a *followed* redirect is always the job's own, already allowed host. REQ-434's "redirect rules" clause can therefore only ever bite an *unfollowed* redirect, which is exactly the case the owner already decided in REQ-422's notes. The clause came in with run 1's F-7 fix and contradicts that decision.

**Options**
1. *(recommended)* Drop "or the redirect rules" from REQ-434. An unfollowed redirect stays a response, as REQ-422's notes say: accepted if listed (REQ-421), otherwise an ordinary failure. REQ-434 then covers only the allowlist and the private-address rule, the cases where no request may be sent at all.
2. Make every unfollowed redirect a permanent refusal: keep REQ-434, and delete the 3xx sentence from REQ-422's notes. A 3xx then can never be an accepted status. That reverses the owner's earlier decision, and a job that expects a 302 (for example to read a `Location` header) can never succeed.
3. Keep both, and give REQ-434 an `if` that excludes a 3xx response when MaxRedirects is reached or the target is another host. This has the same effect as option 1, in more words.

**Ready to apply (option 1)**
```json
{ "id": "REQ-434", "ears": { "while": "an HTTP job is processing",
    "if": "its destination is refused by the destination allowlist or the private-address rule",
    "shall": "move the job to dead-lettered at once, without sending the request, with a reason that names the rule that refused it" },
  "notes": "refiner-model 2026-11-06 F-7 option 1: retrying a host that is not allowed cannot succeed, so refusal is permanent. Run 2 F-14: a redirect that is not followed (INV-403, REQ-416) is a response, not a refusal; REQ-421/REQ-422 decide it." }
```

---

## F-15 · ambiguity · medium — Edge events across a notification-lease handover: alerted twice or not at all
<!-- finding: ambiguity | Chk_OneDeliveryPerEvent | INV-411,REQ-400,REQ-401,REQ-403,REQ-438 -->

**Requirements involved**
- INV-411: *The system shall evaluate notification rules, create their deliveries and send deliveries only on a running node that has the alerts registration and holds the notification lease, checking the lease in the same store write that creates or updates the delivery.*
- REQ-438: *Where notification rules are configured, when no running node with the alerts registration holds an unexpired notification lease, the system shall let one running node with the alerts registration take the notification lease for LeaseDuration and renew it every HeartbeatInterval while it runs.*
- REQ-400: *Where a rule watches dead-lettering, when a job is dead-lettered, the system shall create a delivery …* (REQ-401, the Nth failed attempt, and REQ-403, a missed or late occurrence, are also events that happen once.)

The lease decides **which node** writes, and the fenced write stops two nodes from writing at the *same* moment (run 1's assumption A-11 is closed for that). But a dead-letter happens on a worker node, possibly without the alerts registration. The lease holder has to learn about it, and after a handover the new holder has to know which events the old holder already reported. No requirement says how. State-based triggers (REQ-404 node lost, REQ-405 queue depth, REQ-402 failure rate) are unaffected: any holder sees the condition and the subject cooldown handles repeats.

**What happens** (TLC, `IntegrationsAlerts`, two alerts nodes a1 and a2, a1 also a worker)

*If each node remembers what it reported* (`…_nodeReplay.cfg`, `Chk_OneDeliveryPerEvent`, 7 steps):
1. Job e1 is dead-lettered (REQ-400 trigger).
2. a1 takes the notification lease (REQ-438).
3. a1 creates the delivery for e1 (REQ-400, INV-411).
4. a1 misses a renewal during a long pause, and its lease expires.
5. a2 takes the lease (REQ-438).
6. a2 has never reported e1, so **a2 creates a second delivery for e1**. Inside the subject cooldown it is recorded Suppressed. If the cooldown has ended (or the first delivery failed and REQ-433 closed it), the channel gets the same dead-letter twice.

*If a new holder only looks at events after it takes the lease* (`…_nodeFromNow.cfg`, `Chk_EventAlerted`, 8 steps, stuttering):
1. a1 takes the lease and then loses it during a pause (REQ-438).
2. While no node holds the lease, jobs e1 and e2 are dead-lettered.
3. a1 takes the lease again and starts from now. **e1 and e2 are never alerted.** The same happens to every event between an alerts node crashing and the next one taking over (up to LeaseDuration), and to everything that happens while no alerts node runs at all. That last case is already an open question for the owner.

*If the store marks each event handled in the same write that creates its delivery* (`…_storeCursor.cfg`): one delivery per event, and every event alerted. Both hold over 445 states.

**Options**
1. *(recommended)* **Events are consumed from the store.** Edge-triggered rules read their events from the job store, and the write that creates the delivery also records the event as handled, under the same lease check. A new holder continues where the old one stopped: exactly one delivery per event, none lost, and events that happen while no alerts node runs are reported when one starts. This also answers that open question.
2. **At-least-once.** A new holder re-reads a recent window of events (for example LeaseDuration back) and relies on the subject cooldown to suppress repeats. Duplicates reach the channel only when the cooldown has ended or REQ-433 closed it. Document this.
3. **Best effort.** A new holder starts from now. Events during a handover, or while no alerts node runs, are not alerted. Document this, and rely on the dashboard and logs.

**Ready to apply (option 1)**
```json
{ "id": "REQ-439", "kind": "invariant", "status": "proposed", "strength": "must", "entity": "Delivery",
  "ears": { "where": "a rule is triggered by an event that happens once (a job dead-lettered, the Nth failed attempt, a missed or late occurrence)",
    "shall": "read those events from the job store and record each one as handled in the same store write that creates its delivery, so that after a notification-lease handover the new holder neither reports an event again nor skips one" },
  "dependsOn": ["INV-411", "REQ-438", "REQ-400", "REQ-401", "REQ-403"],
  "rationale": "refiner-model 2026-11-06 run 2 F-15: with node-local memory a lease handover duplicates or loses edge events." }
```

---

## F-16 · gap · low — An operator delete during a relay crash window brings the outbox job back
<!-- finding: gap | Inv_OneJobPerRow/operatorDelete | INV-406,REQ-432,REQ-436,jobs.REQ-144 -->

**Requirements involved**
- INV-406 (should): *The system shall never create more than one job from the same outbox row, even if the relay crashes between enqueueing the job and deleting the row.*
- REQ-432: *… enqueue the row's job in the job store with the row's outboxId as its job id, creating nothing if a job with that id is still stored in any state, and then delete the row.*
- REQ-436: *… assume that every finished-job retention (jobs REQ-104) is much longer than LeaseDuration, so a crashed relay is replaced while the job it created is still stored.*
- jobs REQ-144: an operator can delete a job from the dashboard or the API.

**What happens** (TLC, `Inv_OneJobPerRow`, `IntegrationsOutbox_operatorDelete.cfg`, 9 steps)
1. The application commits outbox row o1 (REQ-430).
2. Worker n2 takes the relay lease (REQ-435) and enqueues job o1 (REQ-432).
3. An operator sees job o1 and deletes it (jobs REQ-144).
4. n2 crashes before deleting the row. Its lease expires, and n1 takes it (REQ-435).
5. n1 processes o1 again. No job with id o1 is stored, so **a second job o1 is created**.

**Why** REQ-436 rules out retention removing the job inside the window. An explicit delete is not covered. The window is short (one relay batch, or up to LeaseDuration after a relay crash), and the operator gets the job back rather than losing anything, hence `low`.

**Options**
1. *(recommended)* **Accept and document.** Extend REQ-436's notes: deleting an outbox-created job within LeaseDuration of its creation can re-create it if the relay crashed meanwhile. No mechanism is added.
2. **Keep a tombstone.** Deleting a job created from the outbox leaves its id stored (state "deleted") until the retention period, so REQ-432's insert-if-absent still sees it. This is a jobs-module change.
3. **Idempotency record** per outboxId, independent of the job (run 1 F-11 option 2).

**Ready to apply (option 1)**
```json
{ "id": "REQ-436", "notes": "refiner-model 2026-11-06 F-11: with the defaults (7 to 30 days against 60 s) this holds by a wide margin. If an application sets a retention close to the lease length, a row can be relayed twice. The model cannot judge durations, so this is stated rather than checked. Run 2 F-16 (accepted): an operator who deletes an outbox-created job (jobs REQ-144) while the relay that created it has crashed and not yet deleted the row gets the job back once; the window is at most LeaseDuration." }
```

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.

| # | Assumption | Affects |
|---|---|---|
| A-1 | REQ-400…REQ-406 are abstracted to "the rule fires for subject s" at any moment in the cooldown model. What they watch belongs to jobs, recurring and hosting. The alerts model makes two kinds explicit: edge events (REQ-400, REQ-401, REQ-403) and the state-based node-lost trigger (REQ-404, with NodeLostAfter from hosting REQ-60 as a nondeterministic "goes stale"). | REQ-400…REQ-406 |
| A-2 | Backoff has no clock: the next attempt may come at any later moment. | REQ-408, REQ-412 |
| A-3 | Cooldowns, NodeLostAfter and retention end as nondeterministic events. The model cannot judge durations: retry span vs cooldown, retention vs relay recovery (REQ-436). | INV-400, INV-407, INV-410, REQ-414, REQ-436 |
| A-4 | Closed deliveries and finished HTTP jobs are archived and free their slot. | all |
| A-5 | A digest delivery has no subject and is not counted (INV-409's "non-digest"). When both the subject cooldown and the cap apply, the delivery is deduplicated, not capped (INV-409 notes). | INV-409, REQ-414 |
| A-6 | Job lifecycle around an HTTP call: claim, then retry while attempt < maxAttempts, else dead-letter (jobs REQ-123/129/131). Lease expiry, job timeouts (REQ-138) and cancellation are not modeled; the HTTP request timeout is one response outcome. A job may list a 3xx status as accepted. | REQ-421, REQ-422, REQ-434, SCN-402 |
| A-7 | INV-401/INV-402 ("never send", "refuse") act as guards on REQ-420, as SCN-401 expects; REQ-434 is the step taken instead. | REQ-420, INV-401, INV-402, REQ-434, SCN-401 |
| A-8 | "Attempts made" in REQ-408/REQ-415 includes the attempt just rejected, so total attempts = NotificationMaxAttempts (REQ-412). | REQ-408, REQ-415, REQ-433 |
| A-9 | In the cooldown model, delivery creation is serialised, which is what INV-411's fenced write gives. The lease itself is modeled in `IntegrationsAlerts.tla`. | INV-409, INV-411 |
| A-10 | At most one crash per behaviour (relay node, or alerts node). | LIV-400, REQ-435, REQ-438 |
| A-11 | At most one lease expiry under a running holder (a missed renewal, e.g. a long pause). An alerts node's later writes are fenced (INV-411). The relay's row delete is not fenced (REQ-432 does not say), but it is idempotent. | REQ-432, REQ-435, REQ-438, F-15 |
| A-12 | A crashed node is restarted by its host (fair) as a new instance that does not inherit its old lease. The old lease must expire first. | REQ-438, F-15 |
| A-13 | REQ-436 is encoded as a guard: retention never removes a job while the outbox row it came from is still pending. `…_noRetentionAssumption.cfg` shows the guarantee depends on it. | REQ-436, INV-406 |
| A-14 | Bounds: 1 rule, 2 subjects, 3 delivery slots (4 in `…_cap2`), NotificationMaxAttempts 2, MaxDeliveriesPerCooldown 1 (2 in `…_cap2`). 2 alerts nodes, 2 edge events. 1 HTTP job, up to 3 hosts, maxAttempts 2, MaxRedirects 0 (1 in `…_transport`). 1 outbox row, 2 worker nodes. | all |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-400…REQ-409, REQ-412…REQ-416, INV-400, INV-407, INV-409, INV-410, INV-411, REQ-433, REQ-438 · REQ-420…REQ-422, REQ-434, INV-401…INV-404, INV-408 · REQ-430, REQ-432, REQ-435, REQ-436, INV-406, LIV-400 · SCN-400, SCN-402, SCN-403, SCN-404 (reachable), SCN-401, SCN-405 (hold) | REQ-410 (static merge of rule definitions and a page listing, no state change) · INV-405 (masking in the dashboard and logs is presentation) · REQ-431, REQ-437 (which enqueue path a configuration takes; no interleaving to explore) · REQ-411 (retired, moved to hosting REQ-60) |

Owner open questions already recorded, and not raised again here: events while no alerts node runs (answered by F-15 option 1), no warning when rules exist but no node has the alerts registration, refused webhook hosts, and a test delivery left pending when no alerts node exists. The model shows a concrete consequence only for the first; it is part of F-15's `nodeFromNow` trace.

## Reproduce
From `specs/model/integrations/`: `python -X utf8 run_all.py` reruns every check (or `run_all.py IntegrationsAlerts` for one model). Each check runs alone as `python run_tlc.py <Module>.tla --config <cfg with one INVARIANT or PROPERTY> --workers 2 --stop-at-first --no-deadlock`, plus a `TypeInv`-only run with deadlock checking for the HTTP and notification cfgs. Results land in `runs/` (gitignored), with a summary in `runs/summary.md`. Set `RUN_TLC` if `run_tlc.py` is not under `~/.claude-personal/skills/refiner-model/scripts/`.

## Next
Apply the chosen options to `integrations.json` with the `refiner-requirements` skill (it validates and diffs), then run this skill again.
