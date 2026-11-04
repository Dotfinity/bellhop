# Iteration 4 inputs

Date: 2026-11-04. Source documents: as in iteration 3. Common unchanged.

## Decided answers read by this iteration

- Everything iteration 3 read (iterations/3/inputs.md).
- D-22: cleanup orphans a definition only while at least one node of its application is live (REQ-030).

## Requirement text

As in iterations/3/inputs.md, except REQ-030, which now reads:

Now: A reconcile orphans the code-defined definitions of its application that are missing from its code, but only when no live node of that application still defines them; it never deletes them, and restores them with a fresh next run time when they come back. Cleanup applies the same orphaning rule on every run, so a definition that no live node of its application defines is orphaned within the node timeout plus one cleanup interval, even when no node starts. Cleanup orphans a definition only while at least one node of its application is live, so an application that is down keeps its definitions and their catch-up after downtime. Only a reconcile restores.
