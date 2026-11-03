"""Build probe copies of F1_JobLifecycle: two mutants that undo D-6 / D-5, and an edge check for the Mermaid diagram."""
import pathlib

here = pathlib.Path(__file__).parent
src = (here.parents[2] / "F1_JobLifecycle.tla").read_text(encoding="utf-8")


def swap(text, old, new, count):
    assert text.count(old) == count, (old, text.count(old))
    return text.replace(old, new)


# Mutant 1: recovery does not retire the token (iteration-1 behaviour), D-5 kept.
stale = swap(src, "/\\ ~recoveredSinceClaim[j]\n", "/\\ TRUE\n", 2)
(here / "stale" / "F1_JobLifecycle.tla").write_text(stale, encoding="utf-8", newline="\n")

# Mutant 2: shutdown releases a cancel-requested job back to the queue (iteration-1 behaviour).
shut = swap(src, "                   ELSE IF cancelReq[j] THEN \"Cancelled\"\n",
            "                   ELSE IF FALSE THEN \"Cancelled\"\n", 1)
(here / "shutdown" / "F1_JobLifecycle.tla").write_text(shut, encoding="utf-8", newline="\n")

# Edge probe: every status change is one the Mermaid diagram draws.
edges = """
Edges ==
    {<<"Scheduled", "Enqueued">>, <<"Failed", "Enqueued">>,
     <<"Scheduled", "Cancelled">>, <<"Enqueued", "Cancelled">>, <<"Failed", "Cancelled">>,
     <<"Enqueued", "Processing">>,
     <<"Processing", "Enqueued">>, <<"Processing", "DeadLettered">>,
     <<"Processing", "Cancelled">>, <<"Processing", "Succeeded">>, <<"Processing", "Failed">>,
     <<"Cancelled", "Enqueued">>, <<"DeadLettered", "Enqueued">>, <<"Succeeded", "Enqueued">>,
     <<"Scheduled", "Deleted">>, <<"Enqueued", "Deleted">>, <<"Failed", "Deleted">>,
     <<"Succeeded", "Deleted">>, <<"DeadLettered", "Deleted">>, <<"Cancelled", "Deleted">>}

OnlyDrawnEdges ==
    [][\\A j \\in Jobs : state'[j] # state[j] => <<state[j], state'[j]>> \\in Edges]_vars

====
"""
assert src.rstrip().endswith("====")
probe = src.rstrip()[:-4] + edges.lstrip("\n")
(here / "edges" / "F1_JobLifecycle.tla").write_text(probe, encoding="utf-8", newline="\n")
cfg = (here / "edges" / "F1_JobLifecycle.cfg").read_text(encoding="utf-8")
cfg = cfg.replace("PROPERTIES\n", "PROPERTIES\n    OnlyDrawnEdges\n")
(here / "edges" / "F1_JobLifecycle.cfg").write_text(cfg, encoding="utf-8", newline="\n")
