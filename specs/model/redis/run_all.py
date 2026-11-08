"""Run every Redis cfg the way the findings were produced (cfgs come from gen_cfgs.py).

Each INVARIANT is checked on its own with --stop-at-first (one clean trace per property instead of
thousands under -continue), each PROPERTY is checked on its own (TLC reports one liveness counter-example per run), and scenario
cfgs run as written. Results: runs/<cfg>__<check>.json/.md and an index in run.json / run.md.
Usage: python run_all.py [cfg ...]   (default: all *.cfg here)
"""
import json, os, pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
RUN_TLC = pathlib.Path.home() / ".claude-personal/skills/refiner-model/scripts/run_tlc.py"
SCENARIO = re.compile(r"_SCN\d+(Reach)?$")


def split(cfg_text):
    head, inv, props, sec = [], [], [], None
    for line in cfg_text.splitlines():
        s = line.strip()
        if s in ("INVARIANTS", "PROPERTIES"):
            sec = s
            continue
        if s in ("ACTION_CONSTRAINT", "CONSTRAINT"):
            sec = None   # constraint lines stay in the head of every per-check cfg
        if sec == "INVARIANTS" and s: inv.append(s)
        elif sec == "PROPERTIES" and s: props.append(s)
        else: head.append(line)
    return "\n".join(head), inv, props


def kill_tlc(cfg_name):
    if os.name == "nt":
        ps = ("Get-CimInstance Win32_Process -Filter \"name='java.exe'\" | "
              f"Where-Object {{ $_.CommandLine -like '*{cfg_name}*' }} | "
              "ForEach-Object { Stop-Process -Id $_.ProcessId -Force }")
        subprocess.run(["powershell", "-NoProfile", "-Command", ps])
    else:
        subprocess.run(["pkill", "-f", cfg_name])


def run(cfg_path, label, text, no_deadlock):
    tmp = HERE / f"_{cfg_path.stem}__{label}.cfg"
    tmp.write_text(text + "\n")
    out = HERE / "runs" / f"{cfg_path.stem}__{label}"
    cmd = [sys.executable, str(RUN_TLC), "Redis.tla", "--config", tmp.name, "--workers", os.environ.get("TLC_WORKERS", "4"),
           "--stop-at-first", "--timeout", "150", "--out", f"{out}.json", "--md", f"{out}.md"]
    if no_deadlock: cmd.append("--no-deadlock")
    try:
        # run_tlc.py's own --timeout does not stop TLC on Windows; enforce it here and stop only
        # the java process that runs this check's temporary cfg.
        subprocess.run(cmd, cwd=HERE, timeout=170)
    except subprocess.TimeoutExpired:
        kill_tlc(tmp.name)
        pathlib.Path(f"{out}.json").write_text(json.dumps({"status": "timeout", "property": None,
                                                           "stats": {}, "trace": []}))
        pathlib.Path(f"{out}.md").write_text(f"### TLC result for `Redis.tla`: **timeout** (170 s)\n")
    tmp.unlink()
    res_path = pathlib.Path(f"{out}.json")
    if not res_path.exists():
        return {"cfg": cfg_path.name, "check": label, "status": "no-result", "property": None,
                "distinctStates": None, "seconds": None, "traceLength": 0, "file": None}
    res = json.loads(res_path.read_text())
    if "unexpected exception" in pathlib.Path(f"{out}.md").read_text().lower():
        res["status"] = "tlc-exception"
    return {"cfg": cfg_path.name, "check": label, "status": res["status"], "property": res["property"],
            "distinctStates": res["stats"].get("distinctStates"), "seconds": res["stats"].get("seconds"),
            "traceLength": len(res["trace"]), "file": f"runs/{out.name}.json"}


def main():
    (HERE / "runs").mkdir(exist_ok=True)
    cfgs = [HERE / c for c in sys.argv[1:]] or sorted(HERE.glob("Redis*.cfg"))
    index_path = HERE / os.environ.get("RUN_INDEX", "run.json")
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
    index_path.with_suffix(".md").write_text("# TLC runs for Redis.tla\n\n" + "\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
