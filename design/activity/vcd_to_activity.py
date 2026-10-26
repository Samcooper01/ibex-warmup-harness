#!/usr/bin/env python3
"""Switching activity of Ibex over the workload's measured window, from the simulation trace.

usage: vcd_to_activity.py <trace.vcd> <window.txt> <out.tsv>

trace.vcd    the testbench's dump: every flip-flop's stored value ("<instance>.Q") and every input port
window.txt   "<start> <end>" in ns, the times of the program's MARK_START and MARK_END writes
out.tsv      one line per register or port, in the shape flow/eval/activity.py reads:
                 path  width  toggles_per_cycle(bit0,bit1,...)  duty(bit0,bit1,...)
             A flip-flop "if_stage_i.instr_rdata_id_o[3]$_DFFE_PN0P_" is bit 3 of the path
             if_stage_i/instr_rdata_id_o, the same key activity.py derives from the flip-flop's name in
             an entry's netlist. Header lines start with "#".

The clock period is 10 ns (tb.v). A bit's toggles count only changes between two known values inside
the window; its duty is the fraction of the window it spends at 1.
"""
import re, sys

vcd_path, win_path, out_path = sys.argv[1:4]
t0, t1 = (float(x) for x in open(win_path).read().split())
PERIOD_NS = 10.0
cycles = (t1 - t0) / PERIOD_NS

# ---- header: one entry per dumped variable ----
scale = 1.0                       # VCD time units in ns
vars_ = {}                        # id -> list of (key, bit) per vector bit, most significant first
f = open(vcd_path)
for line in f:
    if line.startswith("$timescale"):
        t = line if "$end" in line else line + next(f)
        m = re.search(r"(\d+)\s*(s|ms|us|ns|ps|fs)", t)
        scale = int(m.group(1)) * {"s": 1e9, "ms": 1e6, "us": 1e3, "ns": 1.0, "ps": 1e-3, "fs": 1e-6}[m.group(2)]
    elif line.startswith("$var"):
        p = line.split()
        width, code, name = int(p[2]), p[3], p[4].lstrip("\\")
        if name.endswith(".Q"):                          # a flip-flop's stored value
            base = name[:-2].split("$")[0]
            m = re.match(r"^(.*)\[(\d+)\]$", base)
            key, bit = (m.group(1), int(m.group(2))) if m else (base, 0)
            vars_[code] = [(key.replace(".", "/"), bit)]
        else:                                            # an input port, possibly a vector
            vars_[code] = [(name, width - 1 - i) for i in range(width)]
    elif line.startswith("$enddefinitions"):
        break

# per (key, bit): current value, time of the last change, toggles, time at 1
state = {kb: ["x", t0, 0, 0.0] for bits in vars_.values() for kb in bits}

def change(kb, v, now):
    s = state[kb]
    if now > t0 and s[0] == "1": s[3] += min(now, t1) - max(s[1], t0)
    if t0 < now <= t1 and s[0] in "01" and v in "01" and v != s[0]: s[2] += 1
    s[0], s[1] = v, now

now = 0.0
for line in f:
    c = line[0]
    if c == "#":
        now = int(line[1:]) * scale
        if now > t1: break
    elif c in "01xzXZ" and len(line) > 1:
        code = line[1:].strip()
        if code in vars_: change(vars_[code][0], c.lower(), now)
    elif c in "bB":
        val, code = line[1:].split()
        bits = vars_.get(code)
        if bits:
            val = val.lower().rjust(len(bits), "0" if val[0] in "01" else val[0])
            for kb, v in zip(bits, val[-len(bits):]): change(kb, v, now)
for kb, s in state.items():                             # close the window
    if s[0] == "1": s[3] += t1 - max(s[1], t0)

# ---- group bits by register ----
regs = {}
for (key, bit), s in state.items():
    regs.setdefault(key, {})[bit] = (s[2] / cycles, s[3] / (t1 - t0))
with open(out_path, "w") as out:
    out.write(f"# Ibex switching activity: window {t0:.0f} to {t1:.0f} ns, {cycles:.0f} cycles of {PERIOD_NS:g} ns\n")
    out.write("# path\twidth\ttoggles_per_cycle\tduty\n")
    for key in sorted(regs):
        bits = regs[key]; width = max(bits) + 1
        tr = ",".join(f"{bits[b][0]:.6g}" if b in bits else "0" for b in range(width))
        du = ",".join(f"{bits[b][1]:.4g}" if b in bits else "0" for b in range(width))
        out.write(f"{key}\t{width}\t{tr}\t{du}\n")
print(f"vcd_to_activity: {len(regs)} registers and ports, {len(state)} bits, {cycles:.0f} cycles")
