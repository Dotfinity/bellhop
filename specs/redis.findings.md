# Findings: Bellhop Redis store behaviour

<!-- refiner-findings v1 | module: redis | specHash: 214a6f8075bba701eb524f53beaf9f4a225bf3b297ab34cfae4ca723060f0feb | run: 2026-11-07 (run 3) | previous: specs/model/redis/previous.findings.md (run 2, specHash 934f2065132c) -->

**Run:** 2026-11-07, run 3 · **Requirements file:** `specs/redis.json` (specHash `214a6f8075bb`) · **Model:** `specs/model/redis/Redis.tla` (36 cfgs from `gen_cfgs.py`) · **TLC:** 2.19. Every check ran alone with `--stop-at-first --workers 2` and a 170 s limit: 85 checks, no TLC exceptions, no timeouts in the final set (two earlier timeouts were bounded, see *Passed checks*). The largest space is `Redis_Flush2.cfg`: 5,212,197 distinct states in about 125 s.
**Result:** 5 findings: 2 contradictions · 1 gap · 0 unprovable · 2 ambiguities · 0 modeling notes. All 6 run-2 findings are gone: F-1, F-2, F-3, F-4 and F-6 are resolved, and F-5 is accepted (rollbacks are at-least-once by decision).

This run regenerated the reset machinery from `handoff.json` (REQ-507, REQ-508, REQ-509, REQ-522, REQ-526, REQ-527, REQ-528, REQ-530, new REQ-534, SCN-500/503/504, new SCN-507/508) and re-checked the impacted ids, REQ-521 above all, because the glossary's `resetSinceClaim` now uses the marker's last-reset value. The run-2 option switches `OptGlobalValues` and `OptResumeFlag` are now the default behaviour: marker values come from a server clock, and REQ-530 rejoins any value the node has not finished.

**The LeaseDuration wait, without a clock (A-18).** When a node's store becomes reconciling, the model notes every run that is live at that moment. A run leaves that list when it renews or re-creates its record. When LeaseDuration has passed for that node, every run still on the list has gone a whole LeaseDuration without a successful heartbeat, so its lease has expired as it would without any reset (jobs REQ-102, REQ-132). The model marks such a run *lease-lost*. A lease-lost run that keeps running beside a newer claim is the ordinary at-least-once case: `Inv_ConcurrencyKeyMax` and `Inv_SingleClaim` do not count it. Its outcome is still checked, by a separate invariant (`Inv_NoLostOutcomeLeaseLost`), because REQ-521's notes promise it. Store-state invariants (jobs INV-100, recurring INV-204) count every record, whoever wrote it.

**The rule holds in the cases it was written for.** These pass with no lease-lost run in any counter-example:
- a single flush with two workers (`Redis.cfg`, 531,393 states);
- a flush plus an outage for every node (`Redis_Outage.cfg`, 2,732,328), or plus one node dropping its connection (`Redis_Drop.cfg`, 2,166,996);
- a node that first reads the marker after the flush (`Redis_LateJoin.cfg`, 1,561,890).

In all of these, no second job takes the concurrency key, no job runs twice, the pause always ends, and no kept-lease outcome is lost. Unique keys and recurring overlap also hold across one flush (`Redis_Unique.cfg` 471,673, `Redis_Recurring.cfg` 393,373).

The five findings are what is left:
- a second flush caught by a node that is already reconciling (F-1);
- a lease-lost run brought back by a later flush (F-2);
- a flush that only a late node saw, followed by a marker advance (F-3);
- two requirements that both apply to one marker read (F-4);
- one trigger that reads wider than intended (F-5).

## Changes since last run
| Finding | Status |
|---|---|
| F-1 (run 2): late first look "initialises" the store and ends the pause | resolved. REQ-528 now flags the first marker and REQ-507 judges flagged markers too. `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Inv_NoLostOutcome` and `Inv_NoFalseReset` pass on `Redis_LateJoin.cfg` (1,561,890 states). SCN-507 is reachable in 14 steps. |
| F-2 (run 2): work created during the pause collides with the re-created run | resolved for one flush. `Inv_UniqueKey` passes on `Redis_Unique.cfg` (471,673) and `Inv_RecurringOverlap` on `Redis_Recurring.cfg` (393,373). SCN-508 is reachable in 12 steps (j2 is cancelled in the re-creating write). Two flushes: new F-2. |
| F-3 (run 2): an outage uses up the wait before the run re-asserts | resolved. Everything passes on `Redis_Outage.cfg` (2,732,328) and `Redis_Drop.cfg` (2,166,996), including `Inv_NoLostOutcomeLeaseLost`, so the last-reset value records the outcome of a run that missed the reconciliation. |
| F-4 (run 2): flag stuck after a reconnection | resolved. `Liv_Reseeded` passes on `Redis_LivOutage.cfg` (8,612) and `Redis_LivDrop.cfg` (200,752). |
| F-5 (run 2): claims continue against a rolled-back image | accepted (option 2). `Redis_Restore.cfg` and `Redis_RestoreOlder.cfg` still violate `Inv_SingleClaim`, `Inv_ConcurrencyKeyMax` and `Inv_NoLostOutcome` in 10 to 12 steps. Every trace is a job claimed after the copy that runs again, or whose outcome is lost before the rollback is detected, which is exactly what the REQ-507 and REQ-526 notes and NFR-31 accept. No consequence beyond those notes was found. |
| F-6 (run 2): two nodes pick marker values independently, false second reset | resolved. `Inv_NoFalseReset` and `Inv_OneEventPerReset` pass on `Redis_Flush2.cfg` (5,212,197; the second flush lands during a reconciliation, which is the shape of the run-2 trace), on `Redis.cfg` and on `Redis_RestoreFR.cfg` (267,796). |
| F-1 … F-5 (this run) | new |

`findings_delta.py` output (fingerprints; F-numbers are per run, so the first six rows are run 2's numbers):

| Finding | Status | Fingerprint |
|---|---|---|
| F-1 | resolved | contradiction · Inv_ConcurrencyKeyMax · REQ-521,REQ-522,REQ-526,REQ-528,jobs:INV-108 |
| F-2 | resolved | contradiction · REQ-526 · REQ-522,REQ-526,jobs:INV-100,recurring:INV-204 |
| F-3 | resolved | contradiction · Inv_ConcurrencyKeyMax · REQ-509,REQ-521,REQ-522,REQ-529,jobs:INV-108 |
| F-4 | resolved | gap · Liv_Reseeded · LIV-500,REQ-509,REQ-526,REQ-529,REQ-530 |
| F-5 | resolved | contradiction · Inv_SingleClaim · REQ-507,REQ-521,REQ-522,REQ-526,jobs:INV-103,jobs:INV-108 |
| F-6 | resolved | gap · Inv_NoFalseReset · REQ-507,REQ-527,SCN-500 |
| F-1 | new | contradiction · Inv_ConcurrencyKeyMax · REQ-507,REQ-509,REQ-522,REQ-526,jobs:INV-108 |
| F-2 | new | contradiction · Inv_RecurringOverlap · REQ-509,REQ-522,REQ-534,jobs:INV-100,recurring:INV-204 |
| F-3 | new | gap · Inv_NoLostOutcomeLeaseLost · REQ-507,REQ-521,REQ-527,REQ-528 |
| F-4 | new | ambiguity · Liv_LossReported · REQ-507,REQ-530,SCN-507 |
| F-5 | new | ambiguity · REQ-523 · REQ-523,REQ-528,SCN-503 |

6 resolved, 5 new, 0 still open (run-2 F-5 is listed as resolved because its fingerprint is gone; it was accepted, not fixed)

## Summary
| # | Kind | Severity | Requirements | One line |
|---|---|---|---|---|
| F-1 | contradiction | high | REQ-509, REQ-507, REQ-522, REQ-526, jobs INV-108 | A second flush detected by a node that is already reconciling does not restart its wait, so the flag is cleared moments after it was set, beside a run that kept its lease |
| F-2 | contradiction | high | REQ-522, REQ-534, REQ-509, jobs INV-100, recurring INV-204 | A run whose lease expired in one reset re-creates its record at the next one; the store then holds two Processing occurrences or two active jobs with one unique key, and REQ-534 cannot cancel a Processing job |
| F-3 | gap | high | REQ-528, REQ-527, REQ-507, REQ-521 | If a late node initialises the store after a flush and the node that saw the old marker misses that reconciliation, the next advance hides the flush for good: it is never reported, and that node's run loses its outcome |
| F-4 | ambiguity | medium | REQ-507, REQ-530, SCN-507 | A flagged marker older than the node's last value matches both REQ-507 and REQ-530; if REQ-530 is taken, the node "remembers" the lowest value and the flush is never reported |
| F-5 | ambiguity | low | REQ-523, REQ-528, SCN-503 | REQ-523's trigger, "a compare-and-set of a reconciling generation marker succeeds", now also matches REQ-528's first write, which must not record a reset |

Decide **F-1 first**. It breaks the Max = 1 guarantee with a run that never lost its lease, and it does so under the plain reading of REQ-509. The fix is one clause, and the model has checked it: `Redis_Flush2Restart.cfg` passes `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim` and `Inv_NoLostOutcome` (5,025,069 states). F-2 is next. It touches REQ-522, the same sentence F-1 depends on, and its recommended fix has also been checked. F-3 and F-4 both concern how a node judges REQ-528's lowest-value marker, so decide them together.

---

## F-1 · contradiction · high — A second flush caught by a reconciling node does not restart its wait
<!-- finding: contradiction | Inv_ConcurrencyKeyMax | REQ-507,REQ-509,REQ-522,REQ-526,jobs:INV-108 -->

**Requirements involved**
- REQ-509: *While the store is reconciling, when this node has re-seeded the code-defined recurring jobs, the queue registry and its registration, and **LeaseDuration has passed since its store became reconciling**, the system shall clear the reconciling flag on the generation marker if it is still set on the value this reconciliation is for, and mark the store ready.*
- REQ-507: *… **while the store is ready or reconciling**, when the generation marker is found missing, … the system shall replace the marker … with the Redis server's current time …, flagged as reconciling, … and in either case start re-seeding …* (RedisStore: Ready, Reconciling → Reconciling)
- REQ-522: *While the generation marker is missing or flagged as reconciling, if a heartbeat or progress write finds its job's record missing and the store was reset since the claim, the system shall re-create the job's record as processing …*
- REQ-526: *While the generation marker is missing or flagged as reconciling, the system shall claim no job and create no recurring occurrence.*
- jobs INV-108: *… never admit a claim that would make more jobs with the same concurrency key processing at once … than that key's Max …*

**What happens** (TLC, `Redis_Flush2.cfg`, `Inv_ConcurrencyKeyMax`, 18 steps; j1 and j2 share concurrency key `tenant:42`, Max = 1)
1. n2 claims j1 and runs it.
2. FLUSHALL. n1 finds the marker missing, writes flagged value T1 and becomes reconciling. Its LeaseDuration wait starts (REQ-507, REQ-509).
3. j1's next heartbeat re-creates its record with its `tenant:42` hold (REQ-522). j1 has renewed its lease.
4. LeaseDuration passes for n1. n1 has not finished re-seeding yet, so it is still reconciling.
5. A second FLUSHALL, for example a test or recovery script run twice. j1's record and hold are gone again.
6. n1, still reconciling, finds the marker missing and writes flagged value T2 (REQ-507: "ready or reconciling"). Its store does not *become* reconciling; it already is. So the wait in REQ-509 is already over.
7. n1 re-seeds for T2 and immediately clears the flag on T2 (REQ-509: re-seeded, LeaseDuration has passed since its store became reconciling, flag still set on the value this reconciliation is for).
8. j2 with `tenant:42` is enqueued and n1 claims it. **j1 is still running on n2 with a lease it renewed one step before the second flush, and j2 now runs beside it under Max = 1.**

j1 is not lease-lost here. It heartbeated after the first flush, and the flag on T2 was cleared at once, not one lease after it was set. That breaks the rule REQ-509's notes state: "the flag is never cleared less than one lease after it was set".

**Why** REQ-509 measures the wait from a state change: the store *becoming* reconciling. REQ-507 also writes a new flagged value on a store that is *already* reconciling, so the newest flag inherits a wait that started before its flush. The notes mention only the reconnection that restarts the wait (REQ-529, REQ-530), not a new detection.

**Options**
1. *(recommended)* **Restart the wait at every reconciling write.** REQ-509 waits LeaseDuration "since this node last started re-seeding (REQ-507, REQ-528, REQ-530)". REQ-507 says "in either case start re-seeding", so a second detection restarts the wait. Checked: with this reading, `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim` and `Inv_NoLostOutcome` pass on `Redis_Flush2Restart.cfg` (5,025,069 states).
2. **Tie the clear to the value the reconciliation started with.** REQ-509 clears the flag only on the value that was current when this node's store became reconciling. A later value is then cleared only after the node goes ready and rejoins it through REQ-530, which starts a new wait. This is safe too, but it takes a detour through Ready, and "the value this reconciliation is for" has to be redefined.
3. **Leave the reconciliation on a new detection.** REQ-507 from Reconciling moves the store to Ready, and REQ-530 then rejoins the new value with a fresh wait. This is the same effect as option 2, and it costs an extra transition in the RedisStore diagram.

**Ready to apply (option 1)**
```json
{ "id": "REQ-509", "ears": { "while": "the store is reconciling",
    "when": "this node has re-seeded the code-defined recurring jobs, the queue registry and its registration, and LeaseDuration has passed since it last started re-seeding (REQ-507, REQ-528, REQ-530)",
    "shall": "clear the reconciling flag on the generation marker if it is still set on the value this reconciliation is for, and mark the store ready" } }
```

---

## F-2 · contradiction · high — A later flush brings back a run whose lease already expired
<!-- finding: contradiction | Inv_RecurringOverlap | REQ-509,REQ-522,REQ-534,jobs:INV-100,recurring:INV-204 -->

**Requirements involved**
- REQ-522 (quoted in F-1). It requires the marker to be missing or flagged, the record missing, and the store reset since the claim. It says nothing about the run's own lease.
- REQ-534: *When a run's job record is re-created after a store reset (REQ-522) with a unique key that another active job holds, the system shall cancel that other job with reason DuplicateAfterReset in the same write …* (from: Scheduled, Enqueued, Awaiting, Unroutable).
- recurring INV-204: *… never have two of its occurrences' jobs in the Processing state at the same time.*
- jobs INV-100: *… never hold two active jobs with the same unique key …*
- REQ-522 notes: *"After it, a run that never re-asserted is treated like any run whose lease expired: its heartbeat re-creates nothing, so it never becomes a second holder beside a job claimed after the pause."*

**What happens** (TLC, `Redis_Recurring2.cfg`, `Inv_RecurringOverlap`, 18 steps; j1 and j2 are occurrences of `nightly-cleanup`, overlap Skip)
1. n2 runs occurrence j1. FLUSHALL. n1 detects it and reconciles (REQ-507).
2. n2 goes a whole LeaseDuration without a heartbeat landing (a GC pause, or a stalled connection), so j1's lease expires. This is the case the rule accepts. n1 clears the flag (REQ-509).
3. The scheduler finds no unfinished occurrence, because j1's record is gone, and creates j2. n1 claims j2. So far this is the ordinary at-least-once case: j1's handler runs beside j2 with an expired lease (recurring REQ-238).
4. A second FLUSHALL. Both records are gone.
5. n1's heartbeat re-creates j2 (REQ-522).
6. n2's heartbeat re-creates **j1** too. The marker is missing, j1's record is missing, and the store was reset since j1's claim, so REQ-522 applies. **Two occurrences of `nightly-cleanup` are now Processing in the store**, which breaks recurring INV-204. j1 holds a lease that expired before the second flush.

With unique keys (`Redis_Unique2.cfg`, `Inv_UniqueKey`, 18 steps) the trace is the same. At step 6, j1 is re-created with `invoice:7` while j2 holds it as **Processing**. REQ-534 says to cancel "that other job", but Processing is not one of its from-states. Either the write breaks REQ-534's diagram, or two active jobs hold one unique key, which breaks jobs INV-100. The concurrency key and the queue limit are counted twice in the same way.

Without a reset this cannot happen. An expired lease is recovered (jobs REQ-132), and the stale run's token is refused from then on (jobs INV-128). The second flush wipes both the recovery and the token, so the run comes back.

**Why** REQ-522 decides by the marker's state ("missing or flagged"), not by whether the run still holds a valid lease. After one reconciliation, an expired run is excluded only because the flag is no longer set. The next flush sets it again.

**Options**
1. *(recommended)* **Re-create only a lease that has not expired.** REQ-522 adds: "and the run's leaseExpiresAt has not passed by the Redis server's clock". This is "a detected flush ends every lease" stated as a test. A run that could not re-assert in time stays expired at every later reset, as it would under jobs REQ-132. Its outcome is still recorded by REQ-521. Checked: `Inv_UniqueKey` passes on `Redis_Unique2Opt.cfg` (1,720,733 states), and `Inv_RecurringOverlap` passes on `Redis_Recurring2Opt.cfg` (1,398,965).
2. **Let REQ-534 resolve Processing collisions too**, by cancelling the job whose claim is older. Cancelling a running job needs a cooperative stop (jobs REQ-186) and does not stop the handler. It also does not cover recurring overlap or concurrency keys.
3. **Accept and document**: add to NFR-31 that two resets in a row can bring back a run whose lease had expired. Then add "except after two store resets (redis REQ-522)" to jobs INV-100 and recurring INV-204.

**Ready to apply (option 1)**
```json
{ "id": "REQ-522", "ears": { "while": "the generation marker is missing or flagged as reconciling",
    "if": "a heartbeat or progress write finds its job's record missing, the store was reset since the claim, and the run's leaseExpiresAt has not passed by the Redis server's clock",
    "shall": "re-create the job's record as processing with the run's claiming node, leaseToken, leaseExpiresAt, queue, concurrency key, unique key and recurring occurrence, so that queue limits, concurrency keys, unique keys and recurring overlap count the run again, and let the run continue" } }
```

---

## F-3 · gap · high — A flush that only a late node saw is hidden by the next advance
<!-- finding: gap | Inv_NoLostOutcomeLeaseLost | REQ-507,REQ-521,REQ-527,REQ-528 -->

**Requirements involved**
- REQ-528: *… when the generation marker is found missing, if this node has not seen a generation marker since it started, the system shall write the first generation marker at the lowest value, flagged as reconciling, … without recording a reset.* (It gives the first marker no last-reset value.)
- REQ-527: *… advance the unflagged generation marker to the Redis server's current time by compare-and-set …; the last-reset value is left as it is* (notes).
- REQ-507: detects a marker that is missing, or "older than the last value this node saw".
- REQ-521 with the glossary's *resetSinceClaim*: *"the generation marker is missing, flagged as reconciling, or older than the value read when the job was claimed, or the marker's last-reset value is later than the value read when the job was claimed, or this node has detected or learned of a reset since the claim."*
- REQ-528 notes: *"a node that saw an earlier marker still finds this one older and reports the reset (REQ-507)"*. REQ-521 notes: *"the marker's last-reset value … also covers a run on a node that missed the whole reconciliation … so its outcome is recorded rather than lost."*

**What happens: lost outcome** (TLC, `Redis_LateJoin.cfg`, `Inv_NoLostOutcomeLeaseLost`, 14 steps)
1. n2 claims j1 at marker value T0 and runs it. n1 has started but has not read the marker yet.
2. FLUSHALL. n1 reads for the first time, finds the marker missing, and writes the lowest value, flagged, with no last-reset value (REQ-528).
3. For one LeaseDuration, n2 neither looks at the marker nor lands a heartbeat (a long GC pause, or a stalled connection). A-2 lets a node look at any time. j1's lease expires, which the rule accepts.
4. n1 re-seeds and clears the flag (REQ-509). Later it advances the marker to the server's current time T1 > T0 (REQ-527).
5. n2 recovers and j1 completes. Its record is missing. Is the store "reset since the claim"? The marker T1 is present, unflagged and newer than T0. It has no last-reset value. n2 never detected or learned of anything. So REQ-521 does not apply, the completion is refused, and **j1 disappears from history**.

**What happens: the flush is never reported** (TLC, `Redis_LivLateJoinAdv.cfg`, `Liv_LossReported`, 13 steps, ends stuttering; no job involved)
The steps are the same without j1. After step 4, n2 reads T1, which is newer than the T0 it saw, so REQ-507 never fires. **No StoreWasReset event, no REQ-523 ERROR, no unacknowledged reset, no Degraded health.** Runtime-defined recurring jobs, the maintenance pause, queue pauses and throttle limits were silently reset, and nobody is told. Without an advance the same flush is reported (`Liv_LossReported` passes on `Redis_LivLateJoin507.cfg`, 42,552 states).

**Why** After REQ-528 and REQ-527, the marker no longer carries the fact that a flush happened. The lowest value is the only trace, and the first advance, which uses the server clock since run-2 F-6, overwrites it. REQ-507's last-reset value was added to cover runs that missed a reconciliation, but REQ-528's marker carries none.

**Options**
1. *(recommended)* **Give the first marker a last-reset value, and let a node detect an initialisation it never saw.**
   - REQ-528 writes the server's current time as the first marker's last-reset value, marked as an initialisation.
   - Every node remembers the last-reset value it last saw, as well as the last value (glossary `lastSeenMarker`).
   - REQ-507 also fires when it finds an initialisation last-reset value later than the last-reset value this node last saw.
   - The node that wrote the first marker, and any node that read it, has seen that value, so nothing changes for them. A node that remembers an earlier marker, as n2 does, detects and reports the flush. Its run's outcome is then recorded through `resetSinceClaim`'s last-reset clause, with no glossary change.
   - Side effect: a job claimed on a new server before the first advance also counts as "reset since the claim", so REQ-521 would write a minimal record if its record went missing for another reason.
   - This option has **not** been model-checked. The next run should check it.
2. **Record only the outcome**: REQ-528 writes the server's current time as the last-reset value, and nothing else changes. The lost outcome is fixed. The flush still goes unreported in this case, and NFR-31 has to say so ("a flush is reported only if a node that saw the old marker checks it before the next RecurringReconcileInterval").
3. **Accept and document both** in NFR-31 and in the REQ-528 and REQ-521 notes, which currently promise the opposite.

**Ready to apply (option 1)**
```json
[
  { "id": "REQ-528", "ears": { "where": "the worker is registered", "while": "the store is ready", "when": "the generation marker is found missing",
      "if": "this node has not seen a generation marker since it started",
      "shall": "write the first generation marker at the lowest value, with the Redis server's current time as its last-reset value marked as an initialisation, flagged as reconciling, only if none exists yet, log at INFO that it initialised the store and that claims start when the reconciliation ends, and start re-seeding the code-defined recurring jobs, the queue registry and this node's registration without recording a reset" } },
  { "id": "REQ-507", "ears": { "where": "the worker is registered", "while": "the store is ready or reconciling",
      "when": "the generation marker is found missing, or with a value older than the last value this node saw, whether or not it is flagged as reconciling, or with a last-reset value marked as an initialisation that is later than the last last-reset value this node saw",
      "if": "this node has seen a generation marker since it started",
      "shall": "replace the marker, by compare-and-set against what it found, with the Redis server's current time as both its value and its last-reset value, flagged as reconciling, log the ERROR event StoreWasReset if its own write succeeded, and in either case start re-seeding the code-defined recurring jobs, the queue registry and this node's registration" } }
]
```
Glossary `generationMarker`, append: *"Every node also remembers the last last-reset value it saw."*

---

## F-4 · ambiguity · medium — REQ-507 and REQ-530 both apply to the lowest-value first marker
<!-- finding: ambiguity | Liv_LossReported | REQ-507,REQ-530,SCN-507 -->

**Requirements involved**
- REQ-507: *… when the generation marker is found … with a value older than the last value this node saw, **whether or not it is flagged as reconciling** …*
- REQ-530: *Where the worker is registered, while the store is ready, when the generation marker is found flagged as reconciling with a value whose reconciliation this node has not finished, the system shall start re-seeding … without logging StoreWasReset, **and remember the value**.*
- SCN-507 (then): *"One StoreWasReset event was logged …"*

**What happens** (TLC, `Redis_LivLateJoin.cfg`, `Liv_LossReported`, 15 steps, ends stuttering)
1. n1 has seen marker T0. FLUSHALL. n2 reads first and writes the lowest value, flagged (REQ-528).
2. n1, still ready, reads the flagged lowest value. Both REQ-507 (older than T0) and REQ-530 (flagged, not finished) apply. The sentences do not say which one wins.
3. If REQ-530 is taken, n1 rejoins silently and "remembers the value", so its last value is now the lowest one. From then on nothing is older than what n1 remembers.
4. Both nodes reconcile and clear the flag. **The flush is never reported**, and SCN-507's "one StoreWasReset event" does not happen.

When REQ-507 takes precedence, `Liv_LossReported` passes (`Redis_LivLateJoin507.cfg`, 42,552 states), and SCN-507 is reachable (14 steps).

**Why** Run-2 F-1 made REQ-507 apply to flagged markers. REQ-530 already applied to them. The two sentences now overlap on exactly the marker SCN-507 relies on.

**Options**
1. *(recommended)* **Exclude REQ-507's case from REQ-530.** Add to REQ-530's `if`: "the value is not older than the last value this node saw". REQ-507 then always handles an older flagged marker. Checked as `Prio507` (above).
2. **Make "remember" monotonic.** REQ-530 remembers the value only if it is later than the one the node remembers. The flush is then reported at the node's next look (REQ-507 also applies while reconciling), but this relies on that look happening before the clear and the next advance (see F-3).
3. **Order them in the notes only**: say in REQ-530 that REQ-507 takes precedence. This is weaker, because the precedence lives outside the sentences.

**Ready to apply (option 1)**
```json
{ "id": "REQ-530", "ears": { "where": "the worker is registered", "while": "the store is ready",
    "when": "the generation marker is found flagged as reconciling with a value whose reconciliation this node has not finished",
    "if": "that value is not older than the last value this node saw",
    "shall": "start re-seeding the code-defined recurring jobs, the queue registry and this node's registration without logging StoreWasReset, and remember the value" } }
```

---

## F-5 · ambiguity · low — REQ-523's trigger now matches REQ-528's first write
<!-- finding: ambiguity | REQ-523 | REQ-523,REQ-528,SCN-503 -->

**Requirements involved**
- REQ-523: *When this node's compare-and-set of a reconciling generation marker succeeds (REQ-507), the system shall log an ERROR …, record the reset as unacknowledged in the store, and remember it …*
- REQ-528: *… write the first generation marker at the lowest value, flagged as reconciling, only if none exists yet … without recording a reset.*
- SCN-503 (then): *"… no StoreWasReset event or reset ERROR was logged, no reset is recorded as unacknowledged …"*

**Example** SCN-503, step 2. On a new server, n1 writes the first marker "only if none exists yet", which is a compare-and-set, and the marker it writes is now a reconciling one. Read literally, REQ-523's trigger fires: an ERROR is logged and a reset is recorded as unacknowledged. That contradicts REQ-528 ("without recording a reset") and SCN-503's outcome. Only the parenthetical "(REQ-507)" points the other way. The model follows REQ-528 and SCN-503 (`Redis_SCN503.cfg`, trap reached in 8 steps; `Inv_NoFalseReset` passes on `Redis_Fresh.cfg`, 1,096 states).

**Options**
1. *(recommended)* Name the requirement in the trigger: "When this node's compare-and-set in REQ-507 succeeds".
2. Leave it, relying on the parenthetical.

**Ready to apply (option 1)**
```json
{ "id": "REQ-523", "ears": { "when": "this node's compare-and-set in REQ-507 succeeds",
    "shall": "log an ERROR saying that runtime-defined recurring jobs, the maintenance pause, queue pauses, runtime throttle limits and recurring-job pauses may have been lost and are back at their defaults, record the reset as unacknowledged in the store, and remember it until it finds the reset acknowledged" } }
```

---

## Checked and accepted (not findings)
| Check | Config | Result | Why it is not a finding |
|---|---|---|---|
| Rollback to older data (restore, lagging replica) | `Redis_Restore.cfg`, `Redis_RestoreOlder.cfg` | `Inv_NoLostOutcome` (10, 11 steps), `Inv_SingleClaim` (11, 12), `Inv_ConcurrencyKeyMax` (11, 12) violated | Run-2 F-5, option 2 accepted. Every trace is a claim made after the copy that runs again, or an outcome lost before detection. That is what the REQ-507 and REQ-526 notes and NFR-31 describe. No other consequence was found. |
| Runtime eviction (policy changes after startup) | `Redis_Evict.cfg` | `Inv_ConcurrencyKeyMax` (12 steps), `Inv_NoLostOutcome` (11) violated | REQ-531 states that resets caused by eviction are not detected; REQ-505 refuses eviction at startup |
| A lease-lost run beside a newer claim | every cfg | excluded from `Inv_ConcurrencyKeyMax` and `Inv_SingleClaim` (A-18) | The stated rule: a run that did not heartbeat for a whole LeaseDuration lost its lease as under jobs REQ-132 (recurring REQ-238). F-2 and F-3 are the consequences of such runs that go beyond running beside a newer claim. |
| A flush no running worker saw | `Redis_LivLateJoin507.cfg` before A-17 was narrowed | `Liv_LossReported` violated | REQ-528's notes state that such a flush goes unreported. The late-join cfgs now require one worker to have seen the marker (A-17) |

## Passed checks
| Check | Config | Distinct states | Meaning |
|---|---|---|---|
| `Inv_NoFalseReset`, `Inv_OneEventPerReset`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Inv_UnackedUntilOperator`, `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Scn_NoClaimWhileFlagged` | `Redis.cfg` (two workers, one flush) | 531,393 each | The "a detected flush ends every lease" rule holds for one flush |
| the same except `Inv_ConcurrencyKeyMax` (F-1) | `Redis_Flush2.cfg` (second flush during a reconciliation) | 5,212,197 | No false or double report, no lost outcome, record kept, no job run twice (run-2 F-6) |
| `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Inv_NoLostOutcome` | `Redis_Flush2Restart.cfg` (F-1 option 1) | 5,025,069 | The recommended reading of REQ-509 removes F-1 |
| `Inv_ConcurrencyKeyMax`, `Inv_SingleClaim`, `Inv_NoLostOutcome`, `Inv_NoLostOutcomeLeaseLost`, `Scn_NoClaimWhileFlagged` | `Redis_Outage.cfg` / `Redis_Drop.cfg` | 2,732,328 / 2,166,996 | Outages and single-node drops during the pause (run-2 F-3) |
| everything except `Inv_NoLostOutcomeLeaseLost` (F-3) | `Redis_LateJoin.cfg`; `Redis_LateJoinLiteral.cfg` | 1,561,890; 1,628,973 | A late first look no longer ends the pause (run-2 F-1) |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique.cfg` / `Redis_Recurring.cfg` (one flush) | 471,673 / 393,373 | REQ-534 and the occurrence pause close run-2 F-2 for one flush |
| `Inv_UniqueKey` / `Inv_RecurringOverlap` | `Redis_Unique2Opt.cfg` / `Redis_Recurring2Opt.cfg` (F-2 option 1) | 1,720,733 / 1,398,965 | The lease test in REQ-522 removes F-2 |
| `Inv_UniqueKey` | `Redis_Shard.cfg` | 1,240 | jobs INV-100's per-queue scope matches INV-500 |
| `Inv_NoFalseReset`, `Inv_OneEventPerReset` | `Redis_RestoreFR.cfg` | 267,796 | Rollbacks cause no false or double report |
| `Inv_NoFalseReset`, `Inv_ConcurrencyKeyMax` | `Redis_Fresh.cfg` (two workers, new server) | 1,096 | A new server is initialised, not reported (SCN-503) |
| `Liv_Reseeded`, `Liv_MarkerWritten`, `Liv_LossReported`, `Liv_UnackedRestored` | `Redis_Liveness.cfg` | 49,135 | One flush: re-seeded, marker written, reported, record kept |
| `Liv_LossReported`, `Liv_UnackedRestored`, `Liv_Reseeded` | `Redis_LivFlush2.cfg` | 508,728 | Two flushes, one during reconciliation |
| `Liv_LossReported`, `Liv_Reseeded` | `Redis_LivRestore.cfg` | 598,896 | A rollback to an older marker is eventually reported |
| `Liv_Reseeded` | `Redis_LivOutage.cfg` / `Redis_LivDrop.cfg` (`Liv_LossReported` too) | 8,612 / 200,752 | No stuck pause after a reconnection (run-2 F-4) |
| `Liv_Reseeded` | `Redis_LivLateJoin.cfg`, `Redis_LivLateJoin507.cfg` (`Liv_LossReported` too) | 44,469 / 42,552 | The pause always ends after a late first look |
| `Liv_Reseeded`, `Scn_ClientNoDetect` (SCN-506) | `Redis_ClientOnly.cfg` | 14,420 | A client-only node never reconciles |
| `Inv_UnreachableIsUnhealthy`, `Inv_UnhealthyOnlyWithCause` | `Redis_Health.cfg` | 64,386 | Health precedence matches hosting |
| `Scn_NoEvalNoReady` (SCN-501) | `Redis_SCN501.cfg` | 56 | A server without EVAL never becomes ready |
| SCN-500, 503, 504, 505, 507, 508 traps violated as expected | `Redis_SCN5xx.cfg` | 946 / 71 / 13,802 / 847 / 40,382 / 1,094 | Positive scenarios are reachable in 10, 8, 15, 10, 14 and 12 steps. In SCN-504 and SCN-507, j1's claim predates the flush. |

Bounded checks:
- `Redis_Flush2.cfg` without a constraint timed out at 170 s on its first three invariants. It now allows the second flush only while a node is reconciling (`ActC_SecondLossDuringReconcile`), which is the shape of F-1 and of run-2 F-6.
- `Redis_Unique2.cfg` and `Redis_Recurring2.cfg` (and their Opt variants) allow it only after the first reconciliation has ended everywhere (`ActC_SecondLossAfterReconcile`).
- `Inv_NoFalseReset` on `Redis_Restore.cfg` timed out at 170 s twice. It is checked on `Redis_RestoreFR.cfg` instead (one job, one claim).

## Modeling assumptions
Decisions taken where the sentences were silent. Each one shapes the results above; if one is wrong, say so and rerun.
| # | Assumption | Affects |
|---|---|---|
| A-1 | "The store is ready" (REQ-500) is one of the startup checks of hosting REQ-18 | REQ-500, REQ-502, REQ-505, SCN-501 |
| A-2 | A worker reads the marker at any time while its store is ready or reconciling (REQ-507, REQ-528, REQ-530 give no interval) | F-3, F-4 |
| A-3 | Re-seeding writes the recurring definitions, the queue registry and the node's registration in one step | REQ-507, REQ-528, REQ-530, LIV-500 |
| A-5 | Only `actor: system` steps are (weakly) fair, including heartbeats (jobs REQ-126), plus the passage of time (`LeaseElapses`). The server becomes unreachable at most once per run, every outage ends, and a dropped node reconnects | all liveness checks |
| A-6 | used_memory above RedisMemoryDegradedShare is a boolean that can change at any time; HealthyAfterPasses = 1 | REQ-519, REQ-520 |
| A-8 | A stopped node's run and memory disappear with it | `Redis_ClientOnly.cfg` |
| A-9 | "Processing at once" in jobs INV-108, and "holds an unexpired claim" in INV-103, mean handlers running under a claim whose lease has not expired | F-1 |
| A-10 | All model jobs share one concurrency key; with `UniqueKeys` they share one unique key; with `Recurring` they are occurrences of one recurring job with overlap Skip | F-2 |
| A-12 | A restore or failover rolls the whole server back to an image taken earlier, marker included | accepted rollback rows |
| A-14 | Job ids and lease tokens are fresh | all |
| A-16 | A refused heartbeat or completion (jobs INV-128) does not stop the handler | F-2, F-3 |
| A-17 | Without `LateJoin`, every worker has read the marker before data is lost. With `LateJoin`, at least one has; REQ-528's notes accept that a loss no running node saw goes unreported | F-3, F-4 |
| A-18 | **LeaseDuration without a clock.** "LeaseDuration has passed since its store became reconciling" (REQ-509) is an event `LeaseElapses(n)` that may happen at any time after n's store became reconciling. Every run live at that moment that has not renewed or re-created its record since has gone a whole LeaseDuration without a successful heartbeat. It is marked lease-lost (its lease has expired, jobs REQ-102/REQ-132) until it ends, and the handler-level invariants do not count it. A claim starts a fresh lease. REQ-132's recovery itself is not modeled, because after a flush there is no record to recover | F-1, F-2, F-3 and every safety result |
| A-19 | The compare-and-set in REQ-507 is atomic; a node that loses it reads the winner's flagged value later | REQ-507, REQ-530 |
| A-21 | Only a rollback to an older marker value counts as a detectable loss in `Liv_LossReported`; same-value rollbacks and runtime evictions are documented as undetected (NFR-31, REQ-531) | `Liv_LossReported` |
| A-22 | A node remembers the last value it saw from ordinary reads, claims and its own writes. REQ-530's "remember the value" is taken literally: the last value becomes the flagged value it joins, even if that is lower | F-4 |
| A-23 | REQ-528's first marker has no last-reset value (the sentence gives none) | F-3 |
| A-24 | Marker values from "the Redis server's current time" (REQ-507, REQ-527) are modeled as a counter that every new value increases, flushes and rollbacks included; REQ-528's lowest value does not move it | F-3, run-2 F-6 |
| A-25 | A node "has finished a value's reconciliation" once REQ-509 found the marker at that value, cleared or already unflagged (REQ-530 notes) | REQ-530, LIV-500 |
| A-26 | A single node can lose its connection (REQ-529) while the others stay connected; its store is connecting until it reconnects, and it neither heartbeats nor completes meanwhile | `Redis_Drop.cfg`, `Redis_LivDrop.cfg` |

(A-20 from run 2 is now REQ-527's wording: only an unflagged marker is advanced.)

## Coverage
| Modeled | Skipped (reason) |
|---|---|
| REQ-500 to REQ-505, REQ-507 to REQ-510, REQ-512, REQ-513, REQ-519 to REQ-534 (REQ-533 absorbed), LIV-500, LIV-501, INV-500, SCN-500, SCN-501, SCN-503 to SCN-508 | REQ-506 (reporting content, no state) · REQ-511 (topology acceptance, a TECH/conformance concern) · REQ-514 (needs real durations; checked statically, run-1 F-11 resolved) · REQ-515 (node registrations by age need a clock) · REQ-516, REQ-517, INV-501, SCN-502 (strength `may`) · REQ-518 (info) |

## How to reproduce
From `specs/model/redis/`:
- `python gen_cfgs.py` writes the cfgs and removes ones it no longer writes.
- `python run_all.py [cfg …]` runs each invariant and each property alone with `--stop-at-first --workers 2`. It enforces a 170 s limit per run and stops only that run's TLC process if the limit is hit. Results go to `runs/` and `run.md`, which are gitignored.
- `python trace.py runs/<cfg>__<check>.json` prints a trace as changed variables per step.

Switches in the model that are not requirements:
- `Prio507`: REQ-507 wins the overlap (F-4). `TRUE` only in `Redis_LateJoin`, `Redis_LivLateJoin507` and `Redis_LivLateJoinAdv`.
- `RestartWaitOnDetect`: F-1 option 1. `TRUE` only in `Redis_Flush2Restart`.
- `OptLeaseCheck`: F-2 option 1. `TRUE` only in `Redis_Unique2Opt` and `Redis_Recurring2Opt`.

`OptLeaseCheck` was added after most cfgs had run. With `FALSE` the model is unchanged, so those results stand.

## Next
Decide F-1 and F-2 first. Both are reachable breaks of jobs INV-108, jobs INV-100 or recurring INV-204, and both fixes are checked. Then decide F-3 and F-4 together; they concern the same marker read. F-5 is a wording fix. Apply the chosen options to `specs/redis.json` with the `refiner-requirements` skill, then run this skill again. The next run should check F-3 option 1, which this run did not.

Already open questions, unchanged by this run: one marker per hash tag under ShardByQueue (TECH-130), the StaleNodeAge value (REQ-533), and whether REQ-531 should report Unhealthy instead of an ERROR.
