#!/usr/bin/env python3
"""The flow's own numbers for one run, for reference: usage: metrics.py <nickname> <variant>.

These are what the flow itself reports at the end of its run. The evaluator ignores them and measures
the layout itself; see flow/eval/evaluate.py.
"""
import json, glob, os, re, sys
W = os.environ.get("WORK_HOME", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "work"))
nick, var = sys.argv[1], sys.argv[2]
L, R, S = (f"{W}/{d}/asap7/{nick}/{var}" for d in ("logs", "reports", "results"))
m = {}
for f in sorted(glob.glob(f"{L}/6_*.json")):
    try: m.update(json.load(open(f)))
    except Exception: pass
g = m.get
out = {"design": nick, "variant": var}
rpt = f"{R}/6_finish.rpt"
if os.path.exists(rpt):
    mm = re.search(r"period_min = ([0-9.]+)", open(rpt).read()); out["period_min_ps"] = float(mm.group(1)) if mm else None
dp = f"{S}/declared_period.txt"
out["declared_period_ps"] = float(open(dp).read().split()[0]) if os.path.exists(dp) else None
out["setup_ws_ps"] = g("finish__timing__setup__ws"); out["hold_ws_ps"] = g("finish__timing__hold__ws")
out["die_area_um2"] = g("finish__design__die__area"); out["core_area_um2"] = g("finish__design__core__area")
out["stdcell_area_um2"] = g("finish__design__instance__area__stdcell"); out["stdcells"] = g("finish__design__instance__count__stdcell")
out["power_w"] = g("finish__power__total"); out["util_pct"] = g("finish__design__instance__utilization")
drc = f"{R}/5_route_drc.rpt"; out["drc_report_lines"] = sum(1 for _ in open(drc)) if os.path.exists(drc) else None
out["routed"] = os.path.exists(f"{S}/6_final.def")
print(json.dumps(out))
