#!/usr/bin/env bash
# Regression test for the equivalence gate: four deliberately broken copies of a netlist must fail, and
# the untouched original must pass. Run after any change under flow/eval/, inside the pinned container.
#
#   flow/eval/tests/planted_bugs.sh <result dir>     e.g. baseline/ after run_baseline.sh
#
# wire    the D inputs of two asynchronous-reset flip-flops are swapped
# gate    the 40th AND2x2 cell becomes an OR2x2
# enable  the clock gate's latch input is tied high, so the core's clock is never gated
# reset   one flip-flop's RESETN pin is tied high, so reset no longer clears it
# About 3 minutes; writes eval_work/planted_bugs/.
set -uo pipefail
RES=$(cd "${1:?usage: planted_bugs.sh <result dir>}" && pwd)
HERE=$(cd "$(dirname "$0")/../../.." && pwd)
# shellcheck disable=SC1091
source "$HERE/orfs/env.sh" > /dev/null 2>&1
export ORFS_HOME=${ORFS_HOME:-$HERE/orfs}
[ -f "$RES/top.v" ] || { echo "planted_bugs: $RES/top.v is missing"; exit 2; }
T="$HERE/eval_work/planted_bugs"; rm -rf "$T"; mkdir -p "$T"
for v in original wire gate enable reset; do mkdir -p "$T/$v/result"; cp "$RES/top.v" "$T/$v/result/top.v"; done
python3 - "$T" <<'PY'
import re, sys
t = sys.argv[1]
def edit(v, fn):
    p = f"{t}/{v}/result/top.v"; s = open(p).read(); s2 = fn(s)
    if s2 == s: sys.exit(f"planted_bugs: could not plant the {v} bug")
    open(p, "w").write(s2)
cell = re.compile(r"DFFASRHQNx1_ASAP7_75t_R \S+\s+\((.*?)\);", re.S)
def wire(s):
    found = []
    for m in cell.finditer(s):
        d = re.search(r"\.D\(([^()]+)\)", m.group(1))
        if d and all(d.group(1) != f[1] for f in found): found.append((m, d.group(1), m.start(1) + d.start(1), m.start(1) + d.end(1)))
        if len(found) == 2: break
    (a, da, a0, a1), (b, db, b0, b1) = found
    return s[:a0] + db + s[a1:b0] + da + s[b1:]
def gate(s):
    ms = list(re.finditer(r"AND2x2_ASAP7_75t_R ", s))
    m = ms[39]; return s[:m.start()] + "OR2x2_ASAP7_75t_R " + s[m.end():]
def enable(s):
    m = re.search(r"(DLLx\d_ASAP7_75t_R \S+\s+\(.*?\.D\()([^()]+)(\))", s, re.S)
    return s[:m.start(2)] + "1'b1" + s[m.end(2):]
def reset(s):
    m = re.search(r"(DFFASRHQNx1_ASAP7_75t_R \S+\s+\([^;]*?\.RESETN\()([^()]+)(\))", s, re.S)
    return s[:m.start(2)] + "1'b1" + s[m.end(2):]
for v, fn in (("wire", wire), ("gate", gate), ("enable", enable), ("reset", reset)): edit(v, fn)
PY
[ $? -eq 0 ] || exit 2
ok=1
for v in original wire gate enable reset; do
  out=$(python3 "$HERE/flow/eval/equiv.py" "$T/$v/result" "$T/$v/eval_work")
  want=$([ $v = original ] && echo PASS || echo FAIL)
  got=$(echo "$out" | awk '/^GATE equivalence/ {print $3}')
  # a planted bug counts as caught only for a real difference, not for a netlist the gate could not read
  if [ "$want" = FAIL ] && [ "$got" = FAIL ] && ! echo "$out" | grep -q "found a difference\|not equivalent"; then got="FAIL for another reason"; fi
  printf '%-9s expected %s, got %s\n' "$v" "$want" "${got:-nothing}"
  [ "$got" = "$want" ] || { ok=0; echo "$out" | grep "ibex_core:" | cut -c1-300; }
done
[ $ok = 1 ] && echo "planted_bugs: PASS (the original is proven and every planted bug is caught)" || { echo "planted_bugs: FAIL"; exit 1; }
