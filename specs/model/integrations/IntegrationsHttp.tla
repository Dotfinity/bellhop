--------------------------- MODULE IntegrationsHttp ---------------------------
\* Generated from integrations.json (specHash 1ada134dcb35) — FEAT-401 HTTP jobs and outbound security.
\* Edit the requirements, not this file. Every action/property carries an @req comment.
\* The job lifecycle around the HTTP call is the jobs module, abstracted (assumption A-6).
EXTENDS Naturals, FiniteSets

CONSTANTS Jobs,             \* HTTP job slots
          Hosts,            \* destination hosts
          Allowlist,        \* @req INV-401  configured destination allowlist (empty by default)
          Private,          \* hosts that resolve to a private-network or loopback address (INV-402)
          ExplicitPrivate,  \* private hosts "explicitly allowed" (INV-402) — no requirement says how (F-8)
          MaxAttempts,      \* jobs REQ-100 maxAttempts (5 in the policy, 2 in the model)
          MaxRedirects,     \* @req REQ-416  0 by default
          Inv408Scope,      \* "application": INV-408 as written; "allPaths": every enqueue path (F-9 option 1)
          NULL

ASSUME Allowlist \subseteq Hosts /\ Private \subseteq Hosts /\ ExplicitPrivate \subseteq Private
ASSUME MaxAttempts \in Nat \ {0}
ASSUME MaxRedirects \in Nat                                     \* @req REQ-416
ASSUME Inv408Scope \in {"application", "allPaths"}

\* REQ-420 notes: HTTP jobs come from code, from the dashboard launch page and from configuration.
Sources  == {"application", "launchPage", "configuration"}
\* Credential carried by the job payload or configuration template (not by a named HttpClient):
\*   authHeader   = Authorization, Proxy-Authorization or Cookie header, or URL user info (INV-408's list)
\*   customSecret = a credential in any other header, e.g. X-Api-Key (F-10)
Creds    == {"none", "authHeader", "customSecret"}
JStatus  == {"none", "Enqueued", "Processing", "Failed", "Succeeded", "DeadLettered"}
Outcomes == {"accepted", "notAccepted", "predicateFails", "timeout",
             "redirectSameHost", "redirectOtherHost", "transportError"}

VARIABLES job, calls
vars == <<job, calls>>

JRec == [status: JStatus, host: Hosts \cup {NULL}, src: Sources \cup {NULL}, cred: Creds,
         attempt: 0..MaxAttempts, phase: {"idle", "inFlight", "noResponse"},
         redirects: 0..MaxRedirects, resp: Outcomes \cup {"none"}, stored: BOOLEAN]
Call == [job: Jobs, host: Hosts, cred: Creds, redirect: BOOLEAN]

TypeInv == /\ job \in [Jobs -> JRec]
           /\ calls \subseteq Call

Empty == [status |-> "none", host |-> NULL, src |-> NULL, cred |-> "none", attempt |-> 0,
          phase |-> "idle", redirects |-> 0, resp |-> "none", stored |-> FALSE]

Init == /\ job = [j \in Jobs |-> Empty]
        /\ calls = {}

\* @req INV-408  Enqueue (jobs module creation). An application enqueue whose payload carries an
\*               Authorization/Proxy-Authorization/Cookie header or URL user info is rejected and
\*               nothing is stored. As written the rule binds "an application"; Inv408Scope widens it.
Enqueue(j, h, src, cred) ==
  /\ job[j].status = "none"
  /\ ~(cred = "authHeader" /\ (src = "application" \/ Inv408Scope = "allPaths"))
  /\ job' = [job EXCEPT ![j] = [Empty EXCEPT !.status = "Enqueued", !.host = h, !.src = src, !.cred = cred]]
  /\ UNCHANGED calls

\* jobs REQ-123 / REQ-129 retry (abstracted, A-6): an enqueued job, or a failed one whose retryAt
\* has come, is claimed; the attempt number goes up.
Claim(j) ==
  /\ job[j].status \in {"Enqueued", "Failed"}
  /\ job[j].attempt < MaxAttempts
  /\ job' = [job EXCEPT ![j].status = "Processing", ![j].attempt = @ + 1, ![j].phase = "idle",
                        ![j].redirects = 0, ![j].resp = "none", ![j].stored = FALSE]
  /\ UNCHANGED calls

Allowed(h) == /\ h \in Allowlist                               \* @req INV-401
              /\ h \in Private => h \in ExplicitPrivate        \* @req INV-402

\* @req REQ-420  When an HTTP job executes, send the request through its named HttpClient.
\* @req INV-401 INV-402  "never send" read as a guard on REQ-420 (assumption A-7); SCN-401 expects it.
SendRequest(j) ==
  /\ job[j].status = "Processing"
  /\ job[j].phase = "idle"
  /\ Allowed(job[j].host)
  /\ job' = [job EXCEPT ![j].phase = "inFlight"]
  /\ calls' = calls \cup {[job |-> j, host |-> job[j].host, cred |-> job[j].cred, redirect |-> job[j].redirects > 0]}

\* jobs REQ-129 / REQ-131: the retry policy decides between Failed and DeadLettered.
FailAttempt(j, o, stored) ==
  job' = [job EXCEPT ![j].status = IF job[j].attempt < MaxAttempts THEN "Failed" ELSE "DeadLettered",
                     ![j].phase = "idle", ![j].resp = o, ![j].stored = stored]

\* @req REQ-421  accepted status and predicate holds: succeeded, response stored as result.
\* @req REQ-422  status not accepted, predicate fails, or timeout: fail the attempt, store the response if any.
\* @req INV-403  redirect followed only to the same host and at most MaxRedirects times; a redirect that
\*               is not followed is itself the response (REQ-422 notes: not accepted unless listed).
\* transportError (connection refused, DNS, TLS): no requirement says what happens (F-7) → no successor.
Respond(j, o) ==
  /\ job[j].status = "Processing"
  /\ job[j].phase = "inFlight"
  /\ CASE o = "accepted" ->
            job' = [job EXCEPT ![j].status = "Succeeded", ![j].phase = "idle", ![j].resp = o, ![j].stored = TRUE]
       [] o \in {"notAccepted", "predicateFails"} -> FailAttempt(j, o, TRUE)
       [] o = "timeout" -> FailAttempt(j, o, FALSE)
       [] o = "redirectSameHost" /\ job[j].redirects < MaxRedirects ->
            job' = [job EXCEPT ![j].phase = "idle", ![j].redirects = @ + 1]
       [] o = "redirectOtherHost" \/ (o = "redirectSameHost" /\ job[j].redirects >= MaxRedirects) ->
            \/ job' = [job EXCEPT ![j].status = "Succeeded", ![j].phase = "idle", ![j].resp = o, ![j].stored = TRUE]
            \/ FailAttempt(j, o, TRUE)
       [] o = "transportError" ->
            job' = [job EXCEPT ![j].phase = "noResponse", ![j].resp = o]
  /\ UNCHANGED calls

\* modeling artefact A-4: finished jobs free their slot (retention, jobs REQ-145).
Archive(j) ==
  /\ job[j].status \in {"Succeeded", "DeadLettered"}
  /\ job' = [job EXCEPT ![j] = Empty]
  /\ UNCHANGED calls

Next ==
  \/ \E j \in Jobs, h \in Hosts, s \in Sources, c \in Creds : Enqueue(j, h, s, c)
  \/ \E j \in Jobs : Claim(j) \/ SendRequest(j) \/ Archive(j) \/ \E o \in Outcomes : Respond(j, o)

Spec == Init /\ [][Next]_vars

\* @req INV-401  Never a request to a host off the allowlist.
Inv_AllowlistOnly == \A c \in calls : c.host \in Allowlist

\* @req INV-402  Never a request to a private/loopback address that is not explicitly allowed.
Inv_NoPrivate == \A c \in calls : c.host \in Private => c.host \in ExplicitPrivate

\* @req INV-403  Never more than MaxRedirects redirects; redirects stay on the job's host (by construction).
Inv_Redirects == \A j \in Jobs : job[j].redirects <= MaxRedirects

\* @req INV-404  Credentials only from named HttpClient registrations: no call carries a credential
\*               that came from a job payload or configuration template.
Inv_NoPayloadCredentials == \A c \in calls : c.cred = "none"

\* @req SCN-401  (negative, impossibleAt 1) An HTTP job to a host off the allowlist cannot send.
Scn401_RefusedOffAllowlist ==
  \A j \in Jobs : (job[j].status = "Processing" /\ job[j].host \notin Allowlist) => ~ENABLED SendRequest(j)

\* @req SCN-402  Trap for IntegrationsHttp_SCN402.cfg (expected to be VIOLATED): the 503 fails the
\*               attempt, the response is stored, and a retry is still due.
Scn402_NotReached ==
  ~(\E j \in Jobs : job[j].status = "Failed" /\ job[j].resp = "notAccepted" /\ job[j].stored /\ job[j].attempt < MaxAttempts)
=============================================================================
