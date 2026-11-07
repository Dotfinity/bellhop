"""Print one line per finished check in runs/ (status, property, distinct states, trace length).
Usage: python summary.py [substring]"""
import json, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent
for f in sorted((HERE / "runs").glob("*.json")):
    if len(sys.argv) > 1 and sys.argv[1] not in f.name:
        continue
    r = json.loads(f.read_text())
    print(f"{f.stem:55} {r['status']:9} {r.get('property') or '':32} {r['stats'].get('distinctStates')} "
          f"{r['stats'].get('seconds')}s trace={len(r['trace'])}")
