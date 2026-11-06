# Findings: Bellhop notifications, HTTP jobs, outbound HTTP and the outbox

<!-- refiner-findings v1 | module: integrations | specHash: 1ada134dcb356f92a1eca62c2b52dc8979b2c0929d6bc3e3b6cc105481ada548 | run: 2026-11-06 | previous: none -->

**Run:** 2026-11-06 · **Requirements file:** `specs/integrations.json` (specHash `1ada134dcb35`) · **Models:** `model/integrations/IntegrationsNotifications.tla`, `IntegrationsHttp.tla`, `IntegrationsOutbox.tla` · **TLC:** 2.19 (tla2tools.jar, latest release), Java 25 · **Result:** 13 findings: 4 contradictions · 4 gaps · 1 unprovable · 4 ambiguities · 0 modeling notes

The module is modelled as three TLA+ specs, one per feature. The features share no state, and one combined spec would multiply their state spaces. Each property was checked in its own TLC run (`--stop-at-first`, so every trace below is the shortest one), plus one deadlock-only run per configuration. `-continue` was not used because TLC 2.19 threw an internal `ArrayIndexOutOfBoundsException` while it rebuilt thousands of traces, which aborted the search.

| Configuration | What it checks | Result | Distinct states |
|---|---|---|---|
| `IntegrationsNotifications.cfg` | sentences as written | INV-400 ✗ (5 steps), INV-407 ✗ (5), deadlock ✓ | 3,949,328 (full) |
| `…_atCreate.cfg` | F-1 option 1 | INV-400 ✗ (7), INV-407 ✗ (6), probe F-3 ✗ (5), deadlock ✓ | 883,937 |
| `…_atSend.cfg` | F-1 option 2 | INV-400 ✗ (5), INV-407 ✗ (5), deadlock ✓ | 490,651 |
| `…_atCreateHold.cfg` | F-1 option 1 + F-2 option 1 | INV-400 ✓, INV-407 ✓, probe F-3 ✗ (5), deadlock ✓ | 324,835 |
| `…_SCN400.cfg` | SCN-400 reachable | trap violated as expected ✓ (4 steps) | 74 |
| `IntegrationsHttp.cfg` | main | INV-401 ✓, INV-402 ✓, INV-403 ✓, SCN-401 ✓, INV-404 ✗ (4), **deadlock** (3) | 1,064 |
| `…_allPaths.cfg` | F-9 option 1 | INV-404 ✗ (4), deadlock (5) | 18 / 76 |
| `…_transport.cfg` | allowed host only, MaxRedirects 1 | INV-401 ✓, INV-403 ✓, **deadlock** (5) | 4,635 |
| `…_SCN402.cfg` | SCN-402 reachable | trap violated as expected ✓ (5 steps) | 29 |
| `IntegrationsOutbox.cfg` | main (jobs unique key) | INV-406 ✗ (9), LIV-400 ✓ *(under A-9)* | 152 |
| `…_anyStoredJob.cfg` | F-11 option | INV-406 ✗ (10) | 113 |
| `…_noTakeover.cfg` | lease rule as written | LIV-400 ✗ stuttering (8) | 152 |
| `…_SCN403.cfg` | SCN-403 reachable | trap violated as expected ✓ (9 steps) | 91 |

Raw traces: `model/integrations/run_*.md` (one section per property).

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | contradiction | high | INV-400, INV-407, REQ-400…REQ-406 | Nothing says when a new delivery is Pending and when it is Suppressed, so two alerts for one subject can both be sent |
| F-2 | contradiction | high | INV-400, INV-407, REQ-408, REQ-412 | A delivery still retrying when the cooldown ends is sent alongside the next one |
| F-3 | gap | medium | INV-400, REQ-415, REQ-414 | The first alert fails after 5 attempts, later ones in the cooldown are suppressed, and nobody is told |
| F-4 | ambiguity | medium | INV-400, INV-407, REQ-414, glossary "cooldown" | Is the cooldown one period per rule, or one per rule and subject? |
| F-5 | ambiguity | medium | REQ-401, jobs REQ-129/131/132/138/141 | Does "fails for the Nth time" include the final, dead-lettering failure? |
| F-6 | gap | medium | REQ-404, REQ-403, hosting REQ-40 | The node-lost alert cannot fire when the last worker is down, the case it exists for |
| F-7 | gap | medium | REQ-420, REQ-421, REQ-422, INV-401…INV-403 | A refused destination or a transport error leaves an HTTP job processing forever |
| F-8 | ambiguity | medium | INV-401, INV-402 | Does an allowlist entry count as "explicitly allowed" for a private address? |
| F-9 | contradiction | high | INV-404, INV-408, REQ-420 | Launch-page and configuration HTTP jobs can send an Authorization header from the payload |
| F-10 | ambiguity | medium | INV-404, INV-408 | INV-404 forbids payload "credentials", but INV-408 only catches three header names |
| F-11 | contradiction | medium | INV-406, REQ-432, jobs REQ-107, REQ-145 | After a relay crash, a row whose job already finished is relayed again into a second job |
| F-12 | unprovable | medium | LIV-400, REQ-432, SCN-403 | No requirement obliges any node to take over the relay lease |
| F-13 | gap | low | REQ-430, REQ-431 | dbContext.EnqueueAsync is unspecified when the store has its own database and outbox mode is off |

---

## F-1 · contradiction · high — Nothing says when a new delivery is Pending and when it is Suppressed
<!-- finding: contradiction | Inv_OneSendPerSubjectCooldown | INV-400,INV-407,REQ-400,REQ-401,REQ-402,REQ-403,REQ-404,REQ-405,REQ-406 -->

**Requirements involved**
- REQ-400: *Where a rule watches dead-lettering, when a job is dead-lettered, the system shall create a delivery for that rule with the job as subject.* (`to: Pending, Suppressed`; REQ-401…REQ-406 have the same shape)
- INV-400: *The system shall never send more than one non-test delivery for the same rule and subject within the rule's cooldown; later ones within the cooldown are recorded as suppressed.*
- INV-407: *The system shall never send more than MaxDeliveriesPerCooldown non-test, non-digest deliveries for the same rule within its cooldown, whatever their subjects; …*

**What happens** (TLC counter-example, `Inv_OneSendPerSubjectCooldown`, 5 steps; `Inv_RuleCap` fails on the same trace)
1. A sync-crm job is dead-lettered. Rule R creates delivery d1 for sync-crm as Pending (REQ-400), and the cooldown for R / sync-crm starts.
2. Two minutes later a second sync-crm job is dead-lettered. REQ-400 creates d2, and nothing in the creation rule makes it Suppressed, so it is **Pending** too.
3. The channel accepts d1, which is marked Sent (REQ-407).
4. The channel accepts d2, which is marked Sent (REQ-407). **Two deliveries for R / sync-crm were sent within one cooldown, violating INV-400.** With the model's cap of 1, INV-407 is violated too.

**Why** The seven creation transitions may end in Pending or Suppressed, but none of them says which. INV-400 and INV-407 describe the result ("later ones … are recorded as suppressed") without a transition that produces it. The skill models a `to` list with no condition as an outside decision, so TLC is free to pick Pending.

**Options**
1. *(recommended)* **Decide at creation, counting deliveries created as pending.** A new non-test delivery is Suppressed if a counted delivery for the same rule and subject was created as Pending within the cooldown, or if MaxDeliveriesPerCooldown were created for the rule within its cooldown. Checked in `…_atCreate.cfg`: this closes the trace above, but F-2 remains. With F-2's fix as well (`…_atCreateHold.cfg`), INV-400 and INV-407 hold over 324,835 states.
2. **Decide at creation, counting deliveries sent.** This matches INV-400's verb "send", but it fails at once (`…_atSend.cfg`, 5 steps). d1 and d2 are both created before either is sent, and neither sees a sent delivery.
3. **Decide at send time.** Before each attempt, check whether another delivery for the subject was sent within the cooldown, and if so turn this one Suppressed. This needs a new Pending → Suppressed transition, and suppressed deliveries then have to be counted at send time.

**Ready to apply (option 1)** — a new invariant; add it to FEAT-400's members.
```json
{ "id": "INV-409", "kind": "invariant", "status": "proposed", "strength": "must", "entity": "Delivery",
  "ears": { "when": "a non-test, non-digest delivery is created for a rule and subject",
            "shall": "create it as suppressed if a non-test, non-digest delivery for the same rule and subject was created as pending within the cooldown, or if MaxDeliveriesPerCooldown non-test, non-digest deliveries for the rule were created as pending within the rule's cooldown, and as pending otherwise" },
  "mentions": ["Delivery.Pending", "Delivery.Suppressed", "Delivery.isTest", "Delivery.isDigest", "NotificationRule.cooldown"],
  "dependsOn": ["INV-400", "INV-407", "REQ-413"],
  "notes": "Decision rule for the to: [Pending, Suppressed] of REQ-400 to REQ-406 (findings F-1)." }
```

---

## F-2 · contradiction · high — A delivery still retrying when the cooldown ends is sent alongside the next one
<!-- finding: contradiction | Inv_OneSendPerSubjectCooldown/atCreate | INV-400,INV-407,REQ-408,REQ-412 -->

**Requirements involved**
- INV-400 (above): never more than one non-test delivery **sent** for the same rule and subject **within** the cooldown.
- REQ-408: *While a delivery is pending, if its channel rejects the message or cannot be reached, and fewer than NotificationMaxAttempts attempts have been made, then the system shall retry the delivery with backoff.*
- REQ-412: *… at most NotificationMaxAttempts times, 5 by default, with backoff from about 10 seconds to 10 minutes between attempts.*

**What happens** (TLC counter-example under F-1 option 1, `…_atCreate.cfg`, `Inv_OneSendPerSubjectCooldown`, 7 steps)
1. A sync-crm job is dead-lettered. d1 is created Pending and the R / sync-crm cooldown starts (REQ-400 with F-1 option 1).
2. The cooldown for R / sync-crm ends, and so does R's rule cooldown, while d1 is still pending. In real time this means d1 is still retrying: with 5 attempts and backoff up to 10 minutes, the retries run past a 10-minute cooldown.
3. Another sync-crm job is dead-lettered. No cooldown is open, so d2 is created Pending and a new cooldown starts.
4. The channel recovers and accepts d2, which is marked Sent (REQ-407).
5. d1's next retry is accepted and d1 is marked Sent (REQ-407/REQ-408). **Two sends for R / sync-crm within the new cooldown, violating INV-400.** INV-407 fails the same way with two subjects (6 steps).

**Why** Suppression is decided when a delivery is created, but sending can happen up to NotificationMaxAttempts × backoff later. The retry span is longer than a typical cooldown. The model cannot judge the actual durations; it shows the order of events is allowed.

**Options**
1. *(recommended)* **A cooldown does not end while a delivery created in it is still pending.** Checked in `…_atCreateHold.cfg`: INV-400 and INV-407 hold. The trade-off is that a cooldown can last up to the full retry span (about 20 minutes with the defaults).
2. **Reword INV-400/INV-407 to talk about creation** ("never create more than one pending delivery … within the cooldown"). This is easy to enforce, but two messages can then still reach the channel seconds apart, which INV-400 means to prevent.
3. **A newer delivery supersedes an older pending one** for the same rule and subject: the older one becomes Suppressed. This needs a new Pending → Suppressed transition.

**Ready to apply (option 1)**
```json
{ "id": "INV-410", "kind": "invariant", "status": "proposed", "strength": "must", "entity": "Delivery",
  "ears": { "while": "a non-test, non-digest delivery created within a cooldown is pending",
            "shall": "keep that cooldown open, for its rule and subject and for its rule" },
  "mentions": ["Delivery.Pending", "Delivery.isTest", "Delivery.isDigest", "NotificationRule.cooldown"],
  "dependsOn": ["INV-400", "INV-407", "REQ-408"],
  "notes": "Retries (REQ-412: up to 5 attempts, backoff to 10 min) outlast a typical cooldown (findings F-2)." }
```

---

## F-3 · gap · medium — The first alert fails, later ones in the cooldown are suppressed, and nobody is told
<!-- finding: gap | Probe_FailedThenSilent | INV-400,REQ-414,REQ-415 -->

**Requirements involved**
- INV-400 (above): later deliveries within the cooldown are recorded as suppressed.
- REQ-415: *… if its channel rejects the message or cannot be reached, and NotificationMaxAttempts attempts have been made, then the system shall mark the delivery failed, log an error …*
- REQ-414: *When a rule's cooldown ends and deliveries for it were suppressed **by the per-rule cap** during that cooldown, the system shall create one digest delivery …*

**What happens** (TLC counter-example of a probe invariant — not a requirement — `Probe_FailedThenSilent`, under F-1 option 1 and also with F-2 option 1, 5 steps)
1. A sync-crm job is dead-lettered and d1 is created Pending (REQ-400).
2. A second sync-crm job is dead-lettered. d2 is Suppressed because d1 is in the cooldown (INV-400 / F-1 option 1).
3. The Slack webhook rejects d1, and d1 is retried (REQ-408).
4. The webhook rejects d1 again. d1 has used its attempts and is marked Failed (REQ-415).
5. **R / sync-crm has two incidents, no sent message, and no digest.** REQ-414 covers only cap suppression, so if the channel recovers within the cooldown nothing is sent.

**Why** Deduplication assumes the first delivery reaches the channel. A failed first delivery still blocks the cooldown.

**Options**
1. *(recommended)* **A failed delivery ends the cooldown for its rule and subject**, so the next event creates a new Pending delivery. The cost is that a channel that stays down produces one Failed delivery per event (each already logged by REQ-415).
2. **Widen REQ-414**: the digest also reports deliveries suppressed by deduplication when the delivery that opened the cooldown failed.
3. **Accept it.** Failed deliveries are listed on the Notifications page and logged (REQ-415 notes). State this in INV-400's notes.

**Ready to apply (option 1)**
```json
{ "id": "REQ-417", "kind": "invariant", "status": "proposed", "strength": "must", "entity": "Delivery",
  "ears": { "when": "a non-test, non-digest delivery is marked failed",
            "shall": "end the cooldown of its rule and subject, so that the next event for that subject creates a pending delivery" },
  "mentions": ["Delivery.Failed", "Delivery.subject", "NotificationRule.cooldown"],
  "dependsOn": ["INV-400", "REQ-415"] }
```

---

## F-4 · ambiguity · medium — Is the cooldown one period per rule, or one per rule and subject?
<!-- finding: ambiguity | cooldown | INV-400,INV-407,REQ-414 -->

**Requirements involved**
- Glossary *cooldown*: *Per rule: the period in which repeated deliveries for the same subject are suppressed (INV-400).*
- INV-400: *… for the same rule and subject within the rule's cooldown …*
- INV-407 / REQ-414: *… within its cooldown …* / *When a rule's cooldown ends …*

**Example** Rule R has a 10-minute cooldown. Job name A fails at 00:00 and its delivery is sent. Job name B fails at 00:09 and its delivery is sent. B fails again at 00:11.
- *Reading 1, one period per rule, starting with A at 00:00:* R's cooldown ended at 00:10, so B's second delivery at 00:11 is sent. B was deduplicated for only 2 minutes.
- *Reading 2, one period per rule and subject:* B's cooldown runs from 00:09 to 00:19, so the 00:11 delivery is suppressed. The per-rule cap (INV-407) and the digest (REQ-414) then need their own per-rule period, but nothing says when that one starts.

The model uses reading 2, with two timers of the same length (assumption A-5).

**Options**
1. *(recommended)* **Two periods of the rule's cooldown length.** The subject period starts with the first pending delivery for that rule and subject (INV-400). The rule period starts with the first pending delivery of the rule (INV-407, REQ-414).
2. **One period per rule** for both deduplication and the cap. This is simpler, but deduplication for a subject that first fires late in the period is short.
3. **A per-subject period only, with the cap over a sliding window** of one cooldown length. There is no "end of the rule's cooldown" any more, so REQ-414 needs its own trigger.

**Ready to apply (option 1)** — glossary entries (annotation) plus the wording INV-409 above already uses.
```json
{ "glossary": {
    "cooldown": "Per rule, a length of time. Two periods of that length run independently: the subject cooldown (INV-400) starts with the first pending non-test, non-digest delivery for the rule and subject; the rule cooldown (INV-407, REQ-414) starts with the first pending non-test, non-digest delivery of the rule." } }
```

---

## F-5 · ambiguity · medium — Does "fails for the Nth time" include the final, dead-lettering failure?
<!-- finding: ambiguity | REQ-401 | REQ-401 -->

**Requirements involved**
- REQ-401: *Where a rule watches repeated failures with threshold N, when a job fails for the Nth time, the system shall create a delivery …* (mentions `jobs.Job.attempt`)
- jobs REQ-129 (attempt below maxAttempts → **Failed**), REQ-131 (maxAttempts reached → **DeadLettered**), REQ-132 (lease expired → Enqueued, *keeping the attempt counted*), REQ-138 (timeout → Failed with reason Timeout), REQ-141 (requeue resets the attempt number to zero).

**Example** A job has maxAttempts = 3 and rule R watches repeated failures with N = 3. Attempts 1 and 2 throw, so the job is Failed each time (REQ-129). Attempt 3 throws, so the job is DeadLettered (REQ-131). If "fails" means "becomes Failed", the job failed twice and **R never fires**, not even with N = maxAttempts. Other open points: a lease-expiry interruption counts the attempt but is not a failure; and after an operator requeue resets the attempt number, it is unclear whether the count starts again.

**Options**
1. *(recommended)* **Count failed attempts.** Each attempt that ends with an exception or timeout counts, whether the job then becomes Failed or DeadLettered. Lease-expiry interruptions do not count. The count is the job's attempt number, so a requeue starts it again.
2. **Count transitions to Failed only.** Then N must be below maxAttempts for the rule to fire; document that.
3. **Count across jobs of one name**, like REQ-402. That becomes a different trigger, a failure count per job name.

**Ready to apply (option 1)**
```json
{ "id": "REQ-401", "ears": { "where": "a rule watches repeated failures with threshold N",
    "when": "an attempt of a job ends with an exception or a timeout and the job's attempt number is N, whether the job becomes failed or dead-lettered",
    "shall": "create a delivery for that rule with the job as subject" } }
```

---

## F-6 · gap · medium — The node-lost alert cannot fire when the last worker is down
<!-- finding: gap | REQ-404 | REQ-403,REQ-404,hosting.REQ-40 -->

**Requirements involved**
- REQ-404: *Where a rule watches nodes, when a node has sent no heartbeat for NodeLostAfter, the system shall create a delivery for that rule with the node as subject.*
- hosting REQ-40: *While a node has no worker registered, the system shall run no background duty on that node: … or notification check.*
- REQ-403 notes: *'Late' needs someone to notice an occurrence that never fired, for example when every node is down; who raises it then is open.*

**Example** A deployment runs one worker node and two web nodes that are clients only. The worker crashes. The web nodes keep serving and enqueueing, but they run no notification check (hosting REQ-40), so **no node-lost delivery is ever created**. Missed or late recurring occurrences (REQ-403) also go unreported, and enqueued jobs pile up silently. The only signal is the dashboard banner (dashboard REQ-341), which someone has to be looking at. (This is a static finding; the triggers are abstracted in the model, assumption A-1.)

**Options**
1. **Exception to hosting REQ-40**: client nodes with notifications configured run the node-lost and missed-occurrence checks while no worker is alive. This touches the hosting module and gives web nodes a background duty.
2. *(recommended)* **Accept it and say so.** Alerting needs a live worker. Pair it with an external probe of the health endpoint (hosting REQ-31…) and record the decision in REQ-404's notes. This is the cheapest option and keeps the client/worker model clean.
3. **A "no worker alive" rule** evaluated by any node that serves the dashboard, using the same condition as dashboard REQ-341.

**Ready to apply (option 2)** — annotation only.
```json
{ "id": "REQ-404", "notes": "Notification checks run only on worker nodes (hosting REQ-40), so when the last worker is down no node-lost delivery is created; the dashboard banner (dashboard REQ-341) and an external probe of the health endpoint cover that case. Decided by the owner on <date> (findings F-6)." }
```

---

## F-7 · gap · medium — A refused destination or a transport error leaves an HTTP job processing forever
<!-- finding: gap | Deadlock | REQ-420,REQ-421,REQ-422,INV-401,INV-402,INV-403 -->

**Requirements involved**
- REQ-420: *When an HTTP job executes, the system shall send the request described by its payload through the named HttpClient it references …*
- INV-401 / INV-402: *never send … to a host that is not on the configured destination allowlist* / *… refuse to send the request.*
- REQ-422: *… if the response status is not accepted, the success predicate does not hold, or the request times out, then the system shall fail the attempt …*

**What happens** (TLC deadlock, `IntegrationsHttp.cfg`, 3 steps)
1. An application enqueues an HTTP job to internal-api, which is on the allowlist but resolves to a private address.
2. A worker claims the job and it is processing (jobs REQ-123).
3. INV-402 refuses the request, so REQ-420 cannot send it, and neither REQ-421 nor REQ-422 applies because there is no response and no timeout. **No requirement moves the job on.** The handler is still running, so the lease keeps being renewed (jobs REQ-126) and lease recovery never takes it over. SCN-401's job to 169.254.169.254 ends in the same state.

A second trace (`IntegrationsHttp_transport.cfg`, 5 steps) has an allowed host whose connection is refused (or DNS or TLS fails) after sending. Again REQ-422's three conditions do not match. REQ-422's notes say *"everything that is not an accepted response is an ordinary handler failure"*, but the sentence does not.

**Why** REQ-421 and REQ-422 cover the responses that arrive. They do not cover a request that is never sent, or one that gets no HTTP response. The same question applies to webhook notification channels: with the allowlist empty by default, every Slack, Teams or webhook delivery is refused. Whether that counts as "cannot be reached", and so is retried five times by REQ-408, is not said.

**Options**
1. *(recommended)* **Refusal is permanent; transport errors are ordinary failures.** Add REQ-423: a refused destination dead-letters the job at once, naming the rule that refused it (retrying a host that is not allowed cannot succeed). Widen REQ-422's `if` to "any outcome other than an accepted response" so transport errors use the retry policy.
2. **Everything not accepted is an ordinary failure**, including refusal: widen REQ-422 only. The cost is maxAttempts useless retries and a dead-letter whose reason must still name the allowlist.
3. **Refuse at enqueue** when the host is not on the allowlist, like INV-408. This catches mistakes earlier, but the allowlist can change between enqueue and execution, so the execution-time rule is still needed.

**Ready to apply (option 1)**
```json
{ "id": "REQ-422", "ears": { "while": "an HTTP job is processing",
    "if": "the response status is not accepted, the success predicate does not hold, the request times out, or no response arrives because the connection, name resolution or TLS handshake fails",
    "shall": "fail the attempt so the retry policy decides between Failed and DeadLettered, and store the response if there was one" } },
{ "id": "REQ-423", "kind": "transition", "status": "proposed", "strength": "must", "entity": "jobs.Job",
  "actor": "system", "from": ["Processing"], "to": ["DeadLettered"],
  "ears": { "while": "an HTTP job is processing",
            "if": "its destination is refused by the destination allowlist, the private-address rule or the redirect rules",
            "shall": "move the job to dead-lettered at once, without sending the request, with a reason that names the rule that refused it" },
  "mentions": ["HttpCall.host", "HttpCall.resolvedAddress", "HttpCall.redirects"],
  "dependsOn": ["INV-401", "INV-402", "INV-403"] }
```

---

## F-8 · ambiguity · medium — Does an allowlist entry count as "explicitly allowed" for a private address?
<!-- finding: ambiguity | INV-402 | INV-401,INV-402 -->

**Requirements involved**
- INV-401: *never send … to a host that is not on the configured destination allowlist, which is empty by default.*
- INV-402: *If the destination resolves to a private-network or loopback address that is **not explicitly allowed**, then the system shall refuse to send the request.*

**Example** The allowlist contains `internal-api.corp`, which resolves to 10.0.0.5. INV-401 allows the request. Whether INV-402 refuses it depends on what "explicitly allowed" means:
- *Reading 1:* the allowlist entry is the explicit permission, so the request is sent.
- *Reading 2:* a separate setting is needed, but no requirement, TECH or option defines one, so the request can never be sent.

The model uses reading 2 (`ExplicitPrivate = {}`). Under that reading the F-7 deadlock trace above is this case.

**Options**
1. *(recommended)* **The allowlist entry is the explicit permission**, but only for the host name listed (no wildcard covers a private address). Simple; DNS rebinding is already accepted in INV-402's notes.
2. **A separate list of allowed private networks** (CIDR ranges), e.g. an `AllowedPrivateNetworks` option. This is stricter and adds an option plus a TECH entry.
3. **Never allow private addresses.** Simplest, but internal APIs can then never be called from HTTP jobs.

**Ready to apply (option 1)**
```json
{ "id": "INV-402", "ears": {
    "if": "the destination resolves to a private-network or loopback address and its host name is not itself an entry on the destination allowlist",
    "shall": "refuse to send the request" } }
```

---

## F-9 · contradiction · high — Launch-page and configuration HTTP jobs can send an Authorization header from the payload
<!-- finding: contradiction | Inv_NoPayloadCredentials | INV-404,INV-408,REQ-420 -->

**Requirements involved**
- INV-404: *The system shall take credentials for outbound calls only from named HttpClient registrations, never from job payloads or **configuration templates**.*
- INV-408: *If **an application** enqueues an HTTP job whose payload sets an Authorization, Proxy-Authorization or Cookie header, or whose URL carries user information, then the system shall reject the enqueue …* (INV-404 notes: *enforced at enqueue by INV-408*)
- REQ-420 notes: *HTTP jobs can be enqueued, scheduled or made recurring from code, **from the launch page and from configuration**.*

**What happens** (TLC counter-example, `Inv_NoPayloadCredentials`, 4 steps)
1. An operator launches an HTTP job to api.example.com from the dashboard launch page, with `Authorization: Bearer …` in the payload. INV-408 binds only "an application", so the job is stored.
2. A worker claims it (jobs REQ-123).
3. REQ-420 sends the request with the Authorization header from the payload. **This violates INV-404.** A recurring HTTP job defined in configuration with a Cookie header takes the same path: the occurrence enqueue is done by the scheduler, not by "an application".

**Why** The enforcement (INV-408) covers one of the three creation paths that REQ-420's notes list.

**Options**
1. *(recommended)* **INV-408 covers every path.** Code, launch page and configuration all apply, including recurring definitions, which are rejected when the definition is loaded rather than at each occurrence. (`IntegrationsHttp_allPaths.cfg` confirms this closes the trace; F-10 remains.)
2. **Check at send time** instead: REQ-420 strips or refuses forbidden headers whatever the job's origin. This catches everything, but the job fails late rather than being rejected at creation.
3. **Both**: reject at creation, and refuse at send as a safety net.

**Ready to apply (option 1)**
```json
{ "id": "INV-408", "ears": {
    "if": "an HTTP job is enqueued, scheduled or defined as recurring, from code, from the launch page or from configuration, with a payload that sets an Authorization, Proxy-Authorization or Cookie header or a URL that carries user information",
    "shall": "reject it with an error that points to named HttpClient registrations, and store nothing; a recurring definition from configuration is rejected when it is loaded" } }
```

---

## F-10 · ambiguity · medium — INV-404 forbids payload "credentials", but INV-408 only catches three header names
<!-- finding: ambiguity | Inv_NoPayloadCredentials/allPaths | INV-404,INV-408 -->

**Requirements involved** INV-404 and INV-408 (quoted in F-9).

**What happens** (TLC counter-example with F-9 option 1 applied, `IntegrationsHttp_allPaths.cfg`, 4 steps)
1. An application enqueues an HTTP job to api.example.com whose payload sets `X-Api-Key: sk_live_…`. INV-408 does not list that header, so the job is stored.
2. A worker claims it.
3. REQ-420 sends the request with the key from the payload. If an API key counts as a credential, **this violates INV-404**. Under INV-408's list it does not.

**Why** INV-404 says "credentials" without defining them. INV-408 enforces a fixed list of three headers plus URL user info. The model takes "credentials" to include any secret-bearing header, so the two disagree.

**Options**
1. *(recommended)* **Make INV-404 say exactly what is enforced**: never take Authorization, Proxy-Authorization or Cookie headers or URL user info from payloads or templates. Document that other secrets belong on named HttpClient registrations. The guarantee is honest and checkable.
2. **Add a configurable list of credential header names** (default: the three plus `X-Api-Key` and `Api-Key`), checked by INV-408. Broader, but it needs a new option and TECH entry, and is still a list.
3. **Allow only headers that the named HttpClient registration permits**: payload headers outside a per-client allowed list are rejected. Strongest, and the most configuration.

**Ready to apply (option 1)**
```json
{ "id": "INV-404", "ears": {
    "shall": "take Authorization, Proxy-Authorization and Cookie headers and URL user information for outbound calls only from named HttpClient registrations, never from job payloads or configuration templates" } }
```

---

## F-11 · contradiction · medium — After a relay crash, a row whose job already finished is relayed again into a second job
<!-- finding: contradiction | Inv_OneJobPerRow | INV-406,REQ-432,jobs.REQ-107,jobs.REQ-145 -->

**Requirements involved**
- REQ-432 (should): *… the system shall enqueue the row's job in the job store, **keyed by the row's outboxId so a repeated relay creates no second job**, and then delete the row.*
- INV-406 (should): *The system shall never create more than one job from the same outbox row, even if the relay crashes between enqueueing the job and deleting the row.*
- jobs REQ-107: *… treat Scheduled, Enqueued, Processing, Awaiting, Failed and Unroutable as the active states for uniqueness …* (a unique key is held only until the job is Succeeded, DeadLettered or Cancelled) · jobs REQ-145: finished jobs are removed after their retention.

**What happens** (TLC counter-example, `IntegrationsOutbox.cfg`, `Inv_OneJobPerRow`, 9 steps)
1. The application writes outbox row o1 and commits its transaction (REQ-430). o1 is pending.
2. Node B takes the relay lease (assumption A-9).
3. Node B relays o1: job j1 is enqueued with key o1 (REQ-432, first half).
4. j1 runs and succeeds. Its unique key is released (jobs REQ-107).
5. Node B crashes before deleting o1 and loses the lease.
6. Node A takes the relay lease.
7. Node A relays o1 again. No *active* job holds key o1, so **job j2 is created: a second job from o1, violating INV-406.**

If the key is instead checked against every stored job, finished or not (`…_anyStoredJob.cfg`, 10 steps), the same happens when retention cleanup (jobs REQ-145) removes j1 before the next relay. The model cannot judge whether retention (days) always outlasts relay recovery (about one lease length); that is a quantity question for the owner.

**Why** "Keyed by outboxId" is the only idempotency mechanism, and REQ-432 does not say what it is. The one key the jobs module defines (unique key, REQ-107/REQ-150) protects only while the job is active, but the crash window ends with the job possibly already finished. Handlers are fast and the relay waits a lease length, so that is likely.

**Options**
1. *(recommended)* **Use the outboxId as the job id, with insert-if-absent against every stored job**, and state the assumption that finished-job retention is much longer than the relay lease. This closes the trace above; the retention trace remains as a documented assumption.
2. **A separate idempotency record** per outboxId in the job store, kept for a fixed period (for example 7 days) that is longer than any relay outage. This is independent of job retention, but adds another store structure.
3. **Accept at-least-once** (hosting REQ-7/REQ-10) and downgrade INV-406 to "within the unique-key window". Duplicates become the handler's problem.

**Ready to apply (option 1)**
```json
{ "id": "REQ-432", "ears": { "while": "an outbox row is pending",
    "when": "the relay, running on one worker node that holds the relay lease, processes its next batch",
    "shall": "enqueue the row's job in the job store with the row's outboxId as its job id, creating nothing if a job with that id is still stored in any state, and then delete the row" },
  "notes": "A finished job's retention (jobs REQ-145) must be much longer than the time a crashed relay takes to be replaced (one relay lease), or a row can be relayed twice (findings F-11)." }
```

---

## F-12 · unprovable · medium — No requirement obliges any node to take over the relay lease
<!-- finding: unprovable | Liv_RowRelayed | LIV-400,REQ-432,SCN-403 -->

**Requirements involved**
- LIV-400 (should): *While an outbox row is pending and at least one node can run the relay, the system shall eventually enqueue its job and delete the row.*
- REQ-432: *… when the relay, running on one worker node **that holds the relay lease**, processes its next batch …*
- SCN-403 given: *… the relay enqueues its job and crashes before marking o1 relayed; **another node takes the relay lease**.*

**What happens** (TLC liveness counter-example, `IntegrationsOutbox_noTakeover.cfg`, 8 steps, ends in stuttering)
1. The application writes o1. Node B takes the relay lease, and the application commits, so o1 is pending.
2. Node B relays o1 and crashes before deleting it. The lease is free.
3. Node A is running and could run the relay, but no requirement says it must take the lease. **o1 stays pending forever**, so LIV-400 fails.

With lease takeover assumed (A-9, main run), LIV-400 holds (152 states).

**Why** The relay lease appears only as a condition. Nothing says how it is acquired, how long it lasts, or that a free or expired one is taken; compare the cleanup lease, jobs REQ-164. SCN-403 depends on the missing rule.

**Options**
1. *(recommended)* **Add the takeover rule**: when no worker node holds an unexpired relay lease, a running worker node takes it, for RelayLeaseDuration (an assumption with a default, like jobs REQ-102).
2. **Run the relay on every worker node** without a lease, relying on F-11's idempotency. Simpler, but concurrent relays then race on every row.
3. **Downgrade LIV-400 to `info`**: drop the liveness claim and keep the scenario as an example only.

**Ready to apply (option 1)**
```json
{ "id": "REQ-433", "kind": "invariant", "status": "proposed", "strength": "should", "entity": "OutboxRow",
  "ears": { "where": "outbox mode is configured",
            "when": "no running worker node holds an unexpired relay lease",
            "shall": "let one running worker node take the relay lease for RelayLeaseDuration and renew it while it runs" },
  "mentions": ["OutboxRow.Pending"], "dependsOn": ["REQ-432", "LIV-400"],
  "notes": "Needs an assumption requirement for RelayLeaseDuration (findings F-12)." }
```

---

## F-13 · gap · low — dbContext.EnqueueAsync is unspecified when the store has its own database and outbox mode is off
<!-- finding: gap | EnqueueAsync | REQ-430,REQ-431 -->

**Requirements involved**
- REQ-430 (should): *Where outbox mode is configured, when an application calls dbContext.EnqueueAsync, the system shall write the job as an outbox row …*
- REQ-431 (should): *Where the job store shares the application's database and outbox mode is not configured, when an application calls dbContext.EnqueueAsync, the system shall enqueue directly in the context's current transaction.*

**Example** An application uses the Redis store (its own database) without outbox mode and calls `dbContext.EnqueueAsync(job)` inside an EF transaction. Neither REQ-430 nor REQ-431 applies. The job could be enqueued outside the transaction (lost atomicity, silently), rejected, or ignored. NFR (Redis first page) points users to the outbox, so the case is realistic. (Static finding: the configuration choice has no interleaving to check, so REQ-431 is not in the model.)

**Options**
1. *(recommended)* **Reject the call** with an error that names outbox mode. Failing closed protects the transactional guarantee the API's name implies.
2. **Enqueue directly, non-transactionally, and log a warning.** Convenient, but the atomicity loss is silent.
3. **Refuse at startup** when the EF package is registered against a store that does not share the database and outbox mode is off. Earliest, but the EF package may be registered for other reasons.

**Ready to apply (option 1)**
```json
{ "id": "REQ-434", "kind": "invariant", "status": "proposed", "strength": "should", "entity": "OutboxRow",
  "ears": { "where": "the job store does not share the application's database and outbox mode is not configured",
            "when": "an application calls dbContext.EnqueueAsync",
            "shall": "reject the call with an error that names outbox mode, and enqueue nothing" },
  "dependsOn": ["REQ-430", "REQ-431"] }
```

---

## Modeling assumptions
These are decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.

| # | Assumption | Affects |
|---|---|---|
| A-1 | The seven triggers of REQ-400…REQ-406 are abstracted to "the rule fires for subject s" at any moment. What they watch belongs to jobs, recurring and hosting. NodeLostAfter (REQ-411) only times REQ-404's trigger and is absorbed by this. | REQ-400…REQ-406, REQ-411 |
| A-2 | Backoff has no clock: the next attempt may come at any later moment. | REQ-408, REQ-412 |
| A-3 | Cooldowns and retention end as nondeterministic events. The model cannot judge durations (retry span vs cooldown, retention vs relay recovery). | INV-400, INV-407, REQ-414, F-2, F-11 |
| A-4 | Closed deliveries and finished HTTP jobs are archived and free their slot. | all |
| A-5 | Two cooldown timers of the rule's length: one per rule and subject (INV-400) and one per rule (INV-407, REQ-414), each started by the first counted Pending delivery (see F-4). Test and digest deliveries neither count nor start a cooldown; a digest has no subject; deduplication takes precedence over the cap when both apply. | INV-400, INV-407, REQ-409, REQ-414 |
| A-6 | Job lifecycle around an HTTP call: claim, then retry while attempt < maxAttempts, else dead-letter (jobs REQ-123/129/131). Lease expiry, job timeouts (REQ-138) and cancellation are not modeled; the HTTP "request timeout" is one response outcome. | REQ-421, REQ-422, SCN-402 |
| A-7 | INV-401/INV-402 ("never send", "refuse") act as guards on REQ-420, as SCN-401 expects. So INV-401, INV-402 and SCN-401 hold by construction, and the question becomes F-7. | REQ-420, INV-401, INV-402, SCN-401 |
| A-8 | "Attempts made" in REQ-408/REQ-415 includes the attempt just rejected, so total attempts = NotificationMaxAttempts (REQ-412). | REQ-408, REQ-415 |
| A-9 | A worker node can take a free relay lease (not in the requirements). This is fair in the main run and unfair in `…_noTakeover.cfg` (F-12). | REQ-432, LIV-400, SCN-403 |
| A-10 | At most one relay crash per behaviour, the reading of "at least one node can run the relay". | LIV-400 |
| A-11 | Creating a delivery (deciding Pending or Suppressed, then storing it) is atomic across nodes. A race between two worker nodes detecting the same threshold breach is not modeled. | INV-400, INV-407 |
| A-12 | Bounds: 1 rule, 2 subjects, 3 delivery slots, NotificationMaxAttempts 2, MaxDeliveriesPerCooldown 1. 1 HTTP job, 3 hosts, maxAttempts 2, MaxRedirects 0 (1 in `…_transport.cfg`). 1 outbox row, 2 nodes, 2 job slots. | all |

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-400…REQ-409, REQ-411…REQ-416, INV-400, INV-407 · REQ-420…REQ-422, INV-401…INV-404, INV-408 · REQ-430, REQ-432, INV-406, LIV-400 · SCN-400 (reachable), SCN-401 (holds), SCN-402 (reachable), SCN-403 (reachable) | REQ-410 (static merge of rule definitions plus a page listing; no state change to check) · INV-405 (masking in the dashboard and logs is presentation, not state) · REQ-431 (configuration choice between enqueue paths; no interleaving; see F-13) |

## Reproduce
From `specs/model/integrations/`: `python run_tlc.py <Module>.tla --config <cfg> --stop-at-first --no-deadlock` once per invariant or property listed in the cfg, plus one run with `TypeInv` only and deadlock checking on (the outbox and scenario cfgs run with `--no-deadlock`).

## Next
Apply the chosen options to `specs/integrations.json` with the `refiner-requirements` skill (it validates and diffs), then run this skill again. Findings whose fingerprint disappears are listed as resolved in the next report.
