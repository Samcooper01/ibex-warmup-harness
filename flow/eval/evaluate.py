#!/usr/bin/env python3
"""The judge: takes an entry's result/ and re-derives every number with the pinned tools.

usage: evaluate.py <result/> [--work DIR] [--skip STEP,...]

Everything is measured from the submitted layout (DEF) and the pinned inputs; the entry's own SPEF,
timing models and reports are ignored. Steps (each prints PASS/FAIL or a number):
  1  read          top.def, top.v, period.txt; the design must be flat (no blocks/)
  2  timing        parasitics; setup at the slow corner at the declared period (WC); hold at the fast
                   corner (BC); placement legality; unrouted nets; die area
  3  power         pinned switching activity (design/activity/) at the typical corner (TC) and the
                   fixed reference clock
  4  IR drop       static, VDD and VSS, against the pinned limit
  5  DRC           the detailed router's rule checker                             (drc.py)
  6  equivalence   the netlist against the evaluator's own pinned synthesis       (equiv.py)
  7  layout vs netlist                                                            (lvs.py)
  8  score         FOM from scoring.yaml
Results go to <work>/evaluation.json and a summary on stdout. Exit status 0 only if every gate passes.
"""
import argparse, json, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
HARNESS = os.path.abspath(os.path.join(HERE, "..", ".."))
ORFS = os.environ.get("ORFS_HOME", os.path.join(HARNESS, "orfs"))
FLOW = os.path.join(ORFS, "flow")
EVAL_MK = os.path.join(HERE, "eval.mk")
ACTIVITY = os.path.join(HARNESS, "design", "activity", "ibex_activity.tsv.gz")

ap = argparse.ArgumentParser()
ap.add_argument("result"); ap.add_argument("--work"); ap.add_argument("--skip", default="")
args = ap.parse_args()
RES = os.path.abspath(args.result)
WORK = os.path.abspath(args.work or os.path.join(RES, "..", "eval_work"))
SKIP = set(s for s in args.skip.split(",") if s)
os.makedirs(WORK, exist_ok=True)
out = {"gates": {}, "metrics": {}, "notes": []}

def say(msg): print(msg, flush=True)
def gate(name, ok, detail=""):
    out["gates"][name] = {"pass": bool(ok), "detail": detail}
    say(f"   {'PASS' if ok else 'FAIL'}  {name}{('  ' + detail) if detail else ''}")

def run(script, log, corner, env):
    """Run one evaluator Tcl script through the flow's make environment; return its EVAL lines."""
    e = dict(os.environ); e.update({k: str(v) for k, v in env.items()})
    e["EVAL_WORK"] = WORK; e["WORK_HOME"] = os.path.join(WORK, "orfs_work")
    cmd = ["make", "-C", FLOW, f"DESIGN_CONFIG={EVAL_MK}", f"CORNER={corner}", "run", f"RUN_SCRIPT={os.path.join(HERE, script)}"]
    with open(log, "w") as f:
        rc = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, env=e).returncode
    vals = {}
    for line in open(log):
        if line.startswith("EVAL "):
            _, k, v = line.rstrip("\n").split(" ", 2); vals[k] = v
    return rc, vals

# ---- 1 read ----
say("1  read")
for f in ("top.def", "top.v", "period.txt"):
    if not os.path.exists(os.path.join(RES, f)): say(f"FAIL: missing {f}"); sys.exit(2)
period = float(open(os.path.join(RES, "period.txt")).read().strip())
say(f"   period {period:g} ps")
out["metrics"]["declared_period_ps"] = period
# the warmup is flat: one layout of standard cells. A hardened block would show up as blocks/ in the
# result; a block master inside top.def has no LEF here, so reading the layout fails in step 2.
blockdir = os.path.join(RES, "blocks")
blocks = sorted(f for f in (os.listdir(blockdir) if os.path.isdir(blockdir) else []) if f.endswith((".def", ".v")))
gate("flat (one layout, no hardened blocks)", not blocks, f"blocks/ holds {', '.join(blocks)}" if blocks else "")

tdef = os.path.join(RES, "top.def")

# ---- 2 timing: hold, legality, routing, area at the fast corner, then setup at the slow corner ----
say("2  timing at both corners, legality, routing, area")
# hold first: it extracts the parasitics and lists the flip-flops; setup then reuses them
rh, vh = run("top.tcl", os.path.join(WORK, "top_hold_BC.log"), "BC", {"EVAL_MODE": "hold", "EVAL_DEF": tdef, "EVAL_PERIOD": period})
fs_executor = ThreadPoolExecutor(1)
fs = fs_executor.submit(run, "top.tcl", os.path.join(WORK, "top_setup_WC.log"), "WC", {"EVAL_MODE": "setup", "EVAL_DEF": tdef, "EVAL_PERIOD": period})
hold = float(vh.get("hold_wns_ps", "nan"))
gate("hold (fast corner)", rh == 0 and hold >= 0, f"worst slack {hold:.1f} ps")
gate("placement legal", vh.get("placement_legal") == "1")
gate("routing complete", vh.get("unrouted_nets") == "0", f"unrouted nets {vh.get('unrouted_nets')}")
area = float(vh.get("die_area_um2", "nan")); out["metrics"]["die_area_um2"] = area
say(f"   die area {area:.0f} um2")

# ---- 3 power and 4 IR drop ----
say("3  power: pinned switching activity, typical corner, fixed 1,000 ps reference clock")
if not os.path.exists(ACTIVITY): say(f"FAIL: missing pinned activity {ACTIVITY}"); sys.exit(2)
r = subprocess.run([sys.executable, os.path.join(HERE, "activity.py"), ACTIVITY, os.path.join(WORK, "top.flops.tsv"),
                    os.path.join(WORK, "top.ports.tsv"), "", os.path.join(WORK, "top.activity.tcl")], capture_output=True, text=True)
m = re.search(r"flops (\d+)/(\d+)", r.stdout); cov = (int(m.group(1)), int(m.group(2))) if m else (0, 0)
rt, vt = run("top.tcl", os.path.join(WORK, "top_power_TC.log"), "TC",
             {"EVAL_MODE": "power", "EVAL_DEF": tdef, "EVAL_PERIOD": period, "EVAL_ACTIVITY_TCL": os.path.join(WORK, "top.activity.tcl")})
rs, vs = fs.result(); setup = float(vs.get("setup_wns_ps", "nan"))
gate("setup (slow corner, declared period)", rs == 0 and setup >= 0, f"worst slack {setup:.1f} ps")
total = float(vt.get("top_power_w", "nan"))
out["metrics"].update({"power_w": total, "activity_coverage_flops": f"{cov[0]}/{cov[1]}"})
say(f"   power {total:.6f} W; activity on {cov[0]}/{cov[1]} flip-flops ({100.0 * cov[0] / max(cov[1], 1):.2f}%)")

say("4  IR drop")
ir = []
for line in open(os.path.join(WORK, "top_power_TC.log")):
    m = re.search(r"Worstcase IR drop:\s*([0-9.eE+-]+)\s*V", line)
    if m: ir.append(float(m.group(1)) * 1000.0)
limit = None
for line in open(os.path.join(HARNESS, "scoring.yaml")):
    m = re.match(r"\s*ir_drop_limit_mv:\s*([0-9.]+)", line)
    if m: limit = float(m.group(1))
worst = max(ir) if ir else float("nan")
out["metrics"]["ir_drop_mv"] = worst
gate("IR drop", bool(ir) and limit is not None and worst <= limit, f"worst {worst:.1f} mV (limit {limit} mV)")

# ---- 5-7: DRC, equivalence, layout vs netlist (separate scripts) ----
for step, script in (("5  DRC", "drc.py"), ("6  equivalence", "equiv.py"), ("7  layout vs netlist", "lvs.py")):
    say(step)
    key = script[:-3]
    if key in SKIP: say("   skipped"); continue
    r = subprocess.run([sys.executable, os.path.join(HERE, script), RES, WORK], capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    found = False
    for line in r.stdout.splitlines():
        m = re.match(r"GATE (\S+) (PASS|FAIL) ?(.*)", line)
        if m: out["gates"][m.group(1)] = {"pass": m.group(2) == "PASS", "detail": m.group(3)}; found = True
    if not found: gate(key, False, f"{script} gave no verdict: {(r.stderr or r.stdout).strip()[-300:]}")

# ---- 8 score ----
say("8  score")
sc = open(os.path.join(HARNESS, "scoring.yaml")).read()
def num(k):  # a plain number, or a fraction such as 1/3
    m = re.search(rf"^\s*{k}:\s*([0-9.eE+-]+)(?:\s*/\s*([0-9.eE+-]+))?", sc, re.M)
    return None if not m else float(m.group(1)) / (float(m.group(2)) if m.group(2) else 1.0)
T0, A0, P0 = num("T_base_ps"), num("A_base_um2"), num("P_base_w")
a, b_, g = num("a"), num("b"), num("g")
if None in (T0, A0, P0, a, b_, g):
    say("   not scored: scoring.yaml reference values or weights are not set")
else:
    fom = (T0 / period) ** a * (A0 / area) ** b_ * (P0 / total) ** g
    out["metrics"]["fom"] = fom; say(f"   FOM {fom:.3f}  (T {period:g} ps, A {area:.0f} um2, P {total:.6f} W)")
allpass = all(v["pass"] for v in out["gates"].values())
out["all_gates_pass"] = allpass
json.dump(out, open(os.path.join(WORK, "evaluation.json"), "w"), indent=1)
say(f"== {'ALL GATES PASS' if allpass else 'SOME GATES FAIL'}; details in {WORK}/evaluation.json")
sys.exit(0 if allpass else 1)
