---- MODULE CommonCheck ----
EXTENDS Common
VARIABLE tick
Init == tick = FALSE
Next == tick' = ~tick
Spec == Init /\ [][Next]_tick
====
