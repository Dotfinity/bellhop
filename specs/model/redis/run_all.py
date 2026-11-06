"""Run every Redis cfg the way the findings were produced.

Each INVARIANT is checked on its own with --stop-at-first (one clean trace per property instead of
thousands under -continue), each PROPERTY is checked on its own (TLC reports one liveness counter-example per run), and scenario
cfgs run as written. Results: runs/<cfg>__<check>.json/.md and an index in run.json / run.md.
Usage: python run_all.py [cfg ...]   (default: all *.cfg here)
"""
import json, pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
RUN_TLC = pathlib.Path.home() / ".claude-personal/skills/refiner-model/scripts/run_tlc.py"
SCENARIO = re.compile(r"_SCN\d+$")


def split(cfg_text):
    head, inv, props, sec = [], [], [], None
    for line in cfg_text.splitlines():
        s = line.strip()
        if s in ("INVARIANTS", "PROPERTIES"):
            sec = s
            continue
        if sec == "INVARIANTS" and s: inv.append(s)
        elif sec == "PROPERTIES" and s: props.append(s)
        else: head.append(line)
    return "\n".join(head), inv, props


def run(cfg_path, label, text, no_deadlock):
    tmp = HERE / f"_{cfg_path.stem}__{label}.cfg"
    tmp.write_text(text + "\n")
    out = HERE / "runs" / f"{cfg_path.stem}__{label}"
    cmd = [sys.executable, str(RUN_TLC), "Redis.tla", "--config", tmp.name, "--workers", "2",
           "--stop-at-first", "--out", f"{out}.json", "--md", f"{out}.md"]
    if no_deadlock: cmd.append("--no-deadlock")
    subprocess.run(cmd, cwd=HERE)
    tmp.unlink()
    res = json.loads(pathlib.Path(f"{out}.json").read_text())
    return {"cfg": cfg_path.name, "check": label, "status": res["status"], "property": res["property"],
            "distinctStates": res["stats"].get("distinctStates"), "seconds": res["stats"].get("seconds"),
            "traceLength": len(res["trace"]), "file": f"runs/{out.name}.json"}


def main():
    (HERE / "runs").mkdir(exist_ok=True)
    cfgs = [HERE / c for c in sys.argv[1:]] or sorted(HERE.glob("Redis*.cfg"))
    index_path = HERE / "run.json"
    index = json.loads(index_path.read_text()) if index_path.exists() else []
    for cfg in cfgs:
        index = [r for r in index if r["cfg"] != cfg.name]
        head, inv, props = split(cfg.read_text())
        if SCENARIO.search(cfg.stem):
            body = head + "\nINVARIANTS\n" + "\n".join("  " + i for i in inv)
            index.append(run(cfg, "scenario", body, no_deadlock=True))
            continue
        for i in inv:
            if i == "TypeInv": continue
            index.append(run(cfg, i, head + "\nINVARIANTS\n  TypeInv\n  " + i, no_deadlock=False))
        for p in props:
            body = head + "\nINVARIANTS\n  TypeInv\nPROPERTIES\n  " + p
            index.append(run(cfg, p, body, no_deadlock=False))
    index_path.write_text(json.dumps(index, indent=2) + "\n")
    lines = ["| cfg | check | status | property | distinct states | s | trace |", "|---|---|---|---|---|---|---|"]
    lines += [f"| {r['cfg']} | {r['check']} | {r['status']} | {r['property'] or ''} | {r['distinctStates']} | {r['seconds']} | {r['traceLength']} |" for r in index]
    (HERE / "run.md").write_text("# TLC runs for Redis.tla\n\n" + "\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
