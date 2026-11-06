#!/usr/bin/env python3
"""Rerun every integrations check the way integrations.findings.md reports it.

    python -X utf8 run_all.py [cfg-prefix ...]      (from specs/model/integrations)

Each INVARIANT/PROPERTY of each cfg runs alone with --stop-at-first (TLC 2.19 crashes under -continue),
deadlock checking is a separate TypeInv-only run where a deadlock means something, and scenario cfgs run
as they are with --no-deadlock. A run that exceeds TIMEOUT seconds is killed with its whole process tree
(run_tlc.py's own --timeout does not stop java on Windows). Results: runs/<cfg>__<check>.json/.md and
runs/summary.md (all gitignored). Set RUN_TLC to point at run_tlc.py if it is not in the default place.
"""
import json, os, pathlib, re, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
RUN_TLC = os.environ.get("RUN_TLC", str(pathlib.Path.home() / ".claude-personal/skills/refiner-model/scripts/run_tlc.py"))
TIMEOUT = 170
# cfgs whose deadlocks are real findings; the others have a finite environment by design (A-10, A-12).
DEADLOCK_CFGS = {"IntegrationsHttp", "IntegrationsHttp_transport", "IntegrationsHttp_wildcard",
                 "IntegrationsNotifications", "IntegrationsNotifications_cap2"}


def split_cfg(text):
    head, checks, section = [], {"INVARIANTS": [], "PROPERTIES": []}, None
    for line in text.splitlines():
        s = line.strip()
        if s in checks:
            section = s
            continue
        if section and s and not s.startswith("\\*"):
            checks[section].append(s)
        elif not section:
            head.append(line)
    return "\n".join(head), checks


def run(tla, cfg_path, out, flags):
    cmd = [sys.executable, "-X", "utf8", RUN_TLC, tla, "--config", cfg_path, "--workers", "2",
           "--stop-at-first", "--timeout", str(TIMEOUT + 30), "--out", f"runs/{out}.json", "--md", f"runs/{out}.md"] + flags
    p = subprocess.Popen(cmd, cwd=HERE)
    try:
        p.wait(timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        if os.name == "nt":
            subprocess.run(["taskkill", "/T", "/F", "/PID", str(p.pid)], capture_output=True)
        else:
            p.kill()
        return {"status": "timeout", "property": None, "stats": {}, "exception": False}
    res = json.loads((HERE / "runs" / f"{out}.json").read_text(encoding="utf-8"))
    md = (HERE / "runs" / f"{out}.md").read_text(encoding="utf-8")
    res["exception"] = "unexpected exception" in md.lower()
    return res


def main():
    (HERE / "runs").mkdir(exist_ok=True)
    prefixes = sys.argv[1:]
    rows = []
    for cfg in sorted(HERE.glob("Integrations*.cfg")):
        if prefixes and not any(cfg.stem.startswith(p) for p in prefixes):
            continue
        tla = cfg.stem.split("_")[0] + ".tla"
        head, checks = split_cfg(cfg.read_text(encoding="utf-8"))
        jobs = []
        if "_SCN" in cfg.stem:
            jobs.append(("scenario", cfg.name, ["--no-deadlock"]))
        else:
            for kind in ("INVARIANTS", "PROPERTIES"):
                for c in checks[kind]:
                    tmp = HERE / f"_tmp_{cfg.stem}__{c}.cfg"
                    tmp.write_text(f"{head}\n{kind}\n  {c}\n", encoding="utf-8")
                    jobs.append((c, tmp.name, ["--no-deadlock"]))
            if cfg.stem in DEADLOCK_CFGS:
                tmp = HERE / f"_tmp_{cfg.stem}__deadlock.cfg"
                tmp.write_text(f"{head}\nINVARIANTS\n  TypeInv\n", encoding="utf-8")
                jobs.append(("deadlock", tmp.name, []))
        for name, path, flags in jobs:
            res = run(tla, path, f"{cfg.stem}__{name}", flags)
            if path.startswith("_tmp_"):
                (HERE / path).unlink(missing_ok=True)
            st = res.get("stats", {})
            rows.append((cfg.stem, name, res["status"], res.get("property"), st.get("distinctStates"),
                         len(res.get("trace", [])), res["exception"]))
            print(*rows[-1], sep=" | ", flush=True)
    lines = ["| cfg | check | status | property | distinct states | trace length | exception |", "|---|---|---|---|---|---|---|"]
    lines += [f"| {' | '.join(str(x) for x in r)} |" for r in rows]
    (HERE / "runs" / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
