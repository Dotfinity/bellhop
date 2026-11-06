--------------------------- MODULE IntegrationsHttp ---------------------------
\* Generated from integrations.json (specHash 8d15657c8cd5) — FEAT-401 HTTP jobs and outbound security.
\* Edit the requirements, not this file. Every action/property carries an @req comment.
\* The job lifecycle around the HTTP call is the jobs module, abstracted (assumption A-6).
\* Run 2 (handoff): INV-402, INV-404, INV-408, REQ-422 changed; REQ-434 added; SCN-402 re-checked.
\* Run 3 (handoff): REQ-434 no longer lists the redirect rules; RedirectRefused removed (run-2 F-14).
EXTENDS Naturals, FiniteSets

CONSTANTS Jobs,             \* HTTP job slots
          Hosts,            \* destination hosts
          Allowlist,        \* @req INV-401  hosts on the configured destination allowlist (empty by default)
          WildcardOnly,     \* hosts on the allowlist only through a wildcard entry, not by their own name (INV-402)
          Private,          \* hosts that resolve to a private-network or loopback address (INV-402)
          MaxAttempts,      \* jobs REQ-100 maxAttempts (5 in the policy, 2 in the model)
          MaxRedirects,     \* @req REQ-416  0 by default
          NULL

ASSUME Allowlist \subseteq Hosts /\ WildcardOnly \subseteq Allowlist /\ Private \subseteq Hosts
ASSUME MaxAttempts \in Nat \ {0}
ASSUME MaxRedirects \in Nat                                     \* @req REQ-416

\* REQ-420 notes: HTTP jobs come from code, from the dashboard launch page and from configuration.
Sources  == {"application", "launchPage", "configuration"}
\* Credential carried by the job payload or configuration template (not by a named HttpClient):
\*   authHeader   = Authorization, Proxy-Authorization or Cookie header, or URL user info (INV-404/INV-408 list)
\*   customSecret = a credential in any other header, e.g. X-Api-Key (outside INV-404 since run 2)
Creds    == {"none", "authHeader", "customSecret"}
JStatus  == {"none", "Enqueued", "Processing", "Failed", "Succeeded", "DeadLettered"}
\* Responses. A redirect that is not followed (other host, or the limit reached) moves the job to phase
\* "redirectRefused"; the unfollowed 3xx is then the response, decided by REQ-421/REQ-422.
Outcomes == {"accepted", "notAccepted", "predicateFails", "timeout",
             "redirectSameHost", "redirectOtherHost", "transportError"}
Reasons  == {"none", "refused"}

VARIABLES job, calls
vars == <<job, calls>>

JRec == [status: JStatus, host: Hosts \cup {NULL}, src: Sources \cup {NULL}, cred: Creds,
         attempt: 0..MaxAttempts, phase: {"idle", "inFlight", "redirectRefused"},
         redirects: 0..MaxRedirects, resp: Outcomes \cup {"none"}, stored: BOOLEAN,
         reason: Reasons, accept3xx: BOOLEAN]
Call == [job: Jobs, host: Hosts, cred: Creds, redirect: BOOLEAN]

TypeInv == /\ job \in [Jobs -> JRec]
           /\ calls \subseteq Call

Empty == [status |-> "none", host |-> NULL, src |-> NULL, cred |-> "none", attempt |-> 0,
          phase |-> "idle", redirects |-> 0, resp |-> "none", stored |-> FALSE,
          reason |-> "none", accept3xx |-> FALSE]

Init == /\ job = [j \in Jobs |-> Empty]
        /\ calls = {}

\* @req INV-408  Enqueue, schedule or recurring definition, from code, the launch page or configuration:
\*               a payload with an Authorization/Proxy-Authorization/Cookie header or URL user info is
\*               rejected and nothing is stored. accept3xx: whether the job lists a 3xx status as accepted.
Enqueue(j, h, src, cred, a3) ==
  /\ job[j].status = "none"
  /\ cred # "authHeader"
  /\ job' = [job EXCEPT ![j] = [Empty EXCEPT !.status = "Enqueued", !.host = h, !.src = src,
                                             !.cred = cred, !.accept3xx = a3]]
  /\ UNCHANGED calls

\* jobs REQ-123 / REQ-129 retry (abstracted, A-6): an enqueued job, or a failed one whose retryAt
\* has come, is claimed; the attempt number goes up.
Claim(j) ==
  /\ job[j].status \in {"Enqueued", "Failed"}
  /\ job[j].attempt < MaxAttempts
  /\ job' = [job EXCEPT ![j].status = "Processing", ![j].attempt = @ + 1, ![j].phase = "idle",
                        ![j].redirects = 0, ![j].resp = "none", ![j].stored = FALSE]
  /\ UNCHANGED calls

Allowed(h) == /\ h \in Allowlist                                          \* @req INV-401
              /\ h \in Private => h \in Allowlist \ WildcardOnly          \* @req INV-402 (exact entry)

\* @req REQ-420  When an HTTP job executes, send the request through its named HttpClient.
\* @req INV-401 INV-402  "never send" read as a guard on REQ-420 (assumption A-7); SCN-401 expects it.
SendRequest(j) ==
  /\ job[j].status = "Processing"
  /\ job[j].phase = "idle"
  /\ Allowed(job[j].host)
  /\ job' = [job EXCEPT ![j].phase = "inFlight"]
  /\ calls' = calls \cup {[job |-> j, host |-> job[j].host, cred |-> job[j].cred, redirect |-> job[j].redirects > 0]}

\* @req REQ-434  While processing, if the destination is refused by the allowlist or the private-address
\*               rule: dead-letter at once, without sending, with a reason naming the rule.
RefuseDestination(j) ==
  /\ job[j].status = "Processing"
  /\ job[j].phase = "idle"
  /\ ~Allowed(job[j].host)
  /\ job' = [job EXCEPT ![j].status = "DeadLettered", ![j].reason = "refused"]
  /\ UNCHANGED calls

\* jobs REQ-129 / REQ-131: the retry policy decides between Failed and DeadLettered.
FailAttempt(j, o, stored) ==
  job' = [job EXCEPT ![j].status = IF job[j].attempt < MaxAttempts THEN "Failed" ELSE "DeadLettered",
                     ![j].phase = "idle", ![j].resp = o, ![j].stored = stored]

\* @req REQ-421  accepted status and predicate holds: succeeded, response stored as result.
\* @req REQ-422  status not accepted, predicate fails, timeout, or no response (connection, DNS, TLS):
\*               fail the attempt, store the response if any.
\* @req INV-403  redirect followed only to the same host and at most MaxRedirects times. A redirect that
\*               is not followed goes to phase "redirectRefused" (decided below).
Respond(j, o) ==
  /\ job[j].status = "Processing"
  /\ job[j].phase = "inFlight"
  /\ CASE o = "accepted" ->
            job' = [job EXCEPT ![j].status = "Succeeded", ![j].phase = "idle", ![j].resp = o, ![j].stored = TRUE]
       [] o \in {"notAccepted", "predicateFails"} -> FailAttempt(j, o, TRUE)
       [] o \in {"timeout", "transportError"} -> FailAttempt(j, o, FALSE)
       [] o = "redirectSameHost" /\ job[j].redirects < MaxRedirects ->
            job' = [job EXCEPT ![j].phase = "idle", ![j].redirects = @ + 1]
       [] o = "redirectOtherHost" \/ (o = "redirectSameHost" /\ job[j].redirects >= MaxRedirects) ->
            job' = [job EXCEPT ![j].phase = "redirectRefused", ![j].resp = o]
  /\ UNCHANGED calls

\* @req REQ-421 REQ-422  The unfollowed 3xx is the response (REQ-422 notes: "a 3xx response is not
\*               followed and counts as not accepted unless listed"): succeed if a 3xx is accepted,
\*               otherwise fail the attempt.
RedirectAsResponse(j) ==
  /\ job[j].status = "Processing"
  /\ job[j].phase = "redirectRefused"
  /\ IF job[j].accept3xx
       THEN job' = [job EXCEPT ![j].status = "Succeeded", ![j].phase = "idle", ![j].stored = TRUE]
       ELSE FailAttempt(j, job[j].resp, TRUE)
  /\ UNCHANGED calls

\* modeling artefact A-4: finished jobs free their slot (retention, jobs REQ-145).
Archive(j) ==
  /\ job[j].status \in {"Succeeded", "DeadLettered"}
  /\ job' = [job EXCEPT ![j] = Empty]
  /\ UNCHANGED calls

Next ==
  \/ \E j \in Jobs, h \in Hosts, s \in Sources, c \in Creds, a \in BOOLEAN : Enqueue(j, h, s, c, a)
  \/ \E j \in Jobs : \/ Claim(j) \/ SendRequest(j) \/ RefuseDestination(j) \/ Archive(j)
                     \/ RedirectAsResponse(j)
                     \/ \E o \in Outcomes : Respond(j, o)

Spec == Init /\ [][Next]_vars

\* @req INV-401  Never a request to a host off the allowlist.
Inv_AllowlistOnly == \A c \in calls : c.host \in Allowlist

\* @req INV-402  Never a request to a private/loopback host unless the host itself is an allowlist entry.
Inv_NoPrivate == \A c \in calls : c.host \in Private => c.host \in Allowlist \ WildcardOnly

\* @req INV-403  Never more than MaxRedirects redirects; redirects stay on the job's host (by construction).
Inv_Redirects == \A j \in Jobs : job[j].redirects <= MaxRedirects

\* @req INV-404  Authorization/Proxy-Authorization/Cookie headers and URL user info never come from a
\*               payload or template: no call carries one.
Inv_NoPayloadCredentials == \A c \in calls : c.cred # "authHeader"

\* Run-1 check kept for the delta (old F-10): no call carries any payload credential, including a custom
\* secret header. Expected to be violated now: INV-404 deliberately names only the three headers.
Chk_NoPayloadSecretAtAll == \A c \in calls : c.cred = "none"

\* @req SCN-401  (negative, impossibleAt 1) An HTTP job to a host off the allowlist cannot send.
Scn401_RefusedOffAllowlist ==
  \A j \in Jobs : (job[j].status = "Processing" /\ job[j].host \notin Allowlist) => ~ENABLED SendRequest(j)

\* Probe kept from run 2 (F-14): an unfollowed redirect has exactly one way on, as a response
\* (REQ-421/REQ-422), and the refusal step REQ-434 does not apply to it.
Probe_RedirectOneRule ==
  \A j \in Jobs : job[j].phase = "redirectRefused" =>
                    (ENABLED RedirectAsResponse(j) /\ ~ENABLED RefuseDestination(j))

\* @req SCN-402  Trap for IntegrationsHttp_SCN402.cfg (expected to be VIOLATED): the 503 fails the
\*               attempt, the response is stored, and a retry is still due.
Scn402_NotReached ==
  ~(\E j \in Jobs : job[j].status = "Failed" /\ job[j].resp = "notAccepted" /\ job[j].stored /\ job[j].attempt < MaxAttempts)
=============================================================================
