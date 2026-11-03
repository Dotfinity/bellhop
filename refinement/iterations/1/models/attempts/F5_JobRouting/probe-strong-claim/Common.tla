---- MODULE Common ----
\* Shared definitions for the Bellhop M1 feature models (iteration 1).
EXTENDS Naturals, FiniteSets

\* REQ-001, REQ-014, REQ-018, REQ-035, REQ-039
CONSTANT Nodes

\* REQ-005, REQ-008, REQ-010, REQ-019, REQ-036
JobStates == {"Scheduled", "Enqueued", "Processing", "Succeeded", "Failed",
              "DeadLettered", "Cancelled", "Awaiting", "Unroutable"}

\* REQ-005, REQ-010, REQ-038
FinalStates == {"Succeeded", "DeadLettered", "Cancelled"}

\* REQ-019
ActiveStates == {"Scheduled", "Enqueued", "Processing", "Failed", "Awaiting"}

ASSUME Nodes # {}
====
