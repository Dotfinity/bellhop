"""Print a TLC trace from runs/<name>.json as changed variables per step.
Usage: python trace.py runs/Redis_X__Inv_Y.json [var ...]"""
import json, sys
KEEP = sys.argv[2:] or ["node", "rs", "run", "marker", "flagged", "lastReset", "lastSeen", "reseeded", "resetVal",
                        "done", "waitDone", "hbPending", "leaseLost", "jobRec", "losses", "detections", "inits",
                        "pendingLoss", "resetRec", "codeRec", "learned", "reachable", "lostOutcome", "lostOutcomeLL",
                        "claimGen", "clock", "evicting", "snap"]
r = json.load(open(sys.argv[1], encoding="utf-8"))
print(r["status"], r.get("property"), "stutter" if r.get("stutter") else "", "back to", r.get("backToState"))
prev = {}
for st in r["trace"]:
    ch = {k: v for k, v in st["vars"].items() if prev.get(k) != v and k in KEEP}
    print(st["state"], st["action"][:40], ch if st["state"] > 1 else "")
    prev = st["vars"]
