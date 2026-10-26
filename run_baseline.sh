#!/usr/bin/env bash
# The reference flow. Ibex is built flat (flow/ibex/config.mk) to a finished layout, then two steps
# follow that the stock flow does not do:
#   hold loop     the post-global-route hold repair works from estimated parasitics, so the routed
#                 layout can miss hold by a few ps. While the worst hold slack is negative,
#                 flow/eco_hold.tcl repairs hold on the extracted parasitics, and the design is routed
#                 again from that database in a fresh variant (eco1, eco2, ...).
#   two corners   the flow runs at the platform default corner, BC (fast: FF libraries), which is the
#                 hold corner. Setup is judged at the slow corner, so the declared period comes from a
#                 slow-corner setup search on the finished layout, and hold is checked at the fast corner
#                 at that period.
# Runtime is measured the way the compute-budget gate measures it: the wall-clock time of the whole run.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
[ -d "$HERE/orfs" ] || { echo "run ./setup.sh first"; exit 1; }
# shellcheck disable=SC1091
source "$HERE/orfs/env.sh"
export WORK_HOME="$HERE/work"
mkdir -p "$WORK_HOME" "$HERE/baseline"
CORES=${CORES:-8}; HOLD_ROUNDS=${HOLD_ROUNDS:-3}
LOG="$WORK_HOME/runtimes.log"; : > "$LOG"
FLOW="$HERE/orfs/flow"; CFG="$HERE/flow/ibex/config.mk"; NICK=ibex
T_START=$(date +%s)

timed(){ # timed <name> <make args...>: run make, log "<name> <rc> <seconds> <peak kB>"
  local name=$1; shift; local t0; t0=$(date +%s)
  /usr/bin/time -v -o "$WORK_HOME/time_$name.txt" make -C "$FLOW" "$@" > "$WORK_HOME/log_$name.txt" 2>&1
  local rc=$?
  echo "$name $rc $(( $(date +%s) - t0 )) $(grep 'Maximum resident' "$WORK_HOME/time_$name.txt" | awk '{print $NF}')" >> "$LOG"
  return $rc
}
res(){ echo "$WORK_HOME/results/asap7/$NICK/$1"; }

echo "== flow ($CORES threads) =="
timed flow DESIGN_CONFIG="$CFG" NUM_CORES=$CORES || { echo "flow failed, see work/log_flow.txt"; exit 1; }

echo "== hold loop =="
V=base
for i in $(seq 1 "$HOLD_ROUNDS"); do
  make -C "$FLOW" DESIGN_CONFIG="$CFG" FLOW_VARIANT=$V open_6_final.odb < "$HERE/flow/hold_check.tcl" > "$WORK_HOME/log_hold_$V.txt" 2>&1
  wh=$(awk '/^WORST_HOLD/{print $2}' "$WORK_HOME/log_hold_$V.txt"); echo "$V: worst hold ${wh:-?} ps"
  [ -n "$wh" ] || { echo "hold check failed, see work/log_hold_$V.txt"; exit 1; }
  awk -v w="$wh" 'BEGIN{exit !(w >= 0)}' && break
  N=eco$i; margin=$([ "$i" = 1 ] && echo 15 || echo 25)
  for d in results logs reports objects; do
    mkdir -p "$WORK_HOME/$d/asap7/$NICK/$N"
    for f in "$WORK_HOME/$d/asap7/$NICK/$V"/{1_,2_,3_}* "$WORK_HOME/$d/asap7/$NICK/$V"/{clock_period.txt,mem.json}; do
      [ -e "$f" ] && cp -a "$f" "$WORK_HOME/$d/asap7/$NICK/$N/"
    done
  done
  cp "$(res $V)/5_route.sdc" "$(res $N)/4_cts.sdc"
  t0=$(date +%s)
  echo "source $HERE/flow/eco_hold.tcl" | ECO_MARGIN=$margin ECO_OUT="$(res $N)/4_cts.odb" \
    make -C "$FLOW" DESIGN_CONFIG="$CFG" FLOW_VARIANT=$V open_5_route.odb > "$WORK_HOME/log_eco_$N.txt" 2>&1
  [ -f "$(res $N)/4_cts.odb" ] || { echo "hold ECO failed, see work/log_eco_$N.txt"; exit 1; }
  cp -a "$(res $N)/4_cts.odb" "$(res $N)/4_1_cts.odb"; touch -r "$(res $N)/4_cts.odb" "$(res $N)/4_1_cts.odb" "$(res $N)/4_cts.sdc"
  echo "eco_$N 0 $(( $(date +%s) - t0 )) 0" >> "$LOG"
  timed "flow_$N" DESIGN_CONFIG="$CFG" FLOW_VARIANT=$N NUM_CORES=$CORES finish \
    || { echo "re-route $N failed, see work/log_flow_$N.txt"; exit 1; }
  V=$N
done
awk -v w="$wh" 'BEGIN{exit !(w >= 0)}' || { echo "hold not met after $HOLD_ROUNDS rounds (worst $wh ps)"; exit 1; }
RES=$(res $V); echo "final layout: $V"

echo "== declared period: slow-corner setup; fast-corner hold checked at that period =="
make -C "$FLOW" DESIGN_CONFIG="$CFG" FLOW_VARIANT=$V CORNER=WC SETUP_ONLY=1 run RUN_SCRIPT="$HERE/flow/time_at_period.tcl" SEARCH=1 \
  > "$WORK_HOME/log_period_slow.txt" 2>&1 || { echo "slow-corner period search failed, see work/log_period_slow.txt"; exit 1; }
P=$(cat "$RES/declared_period.txt")
make -C "$FLOW" DESIGN_CONFIG="$CFG" FLOW_VARIANT=$V run RUN_SCRIPT="$HERE/flow/time_at_period.tcl" PERIODS="$P" \
  > "$WORK_HOME/log_period_fast.txt" 2>&1
grep -E "^PERIOD" "$WORK_HOME/log_period_fast.txt" | awk '{ if ($6 < 0) { print "fast-corner hold fails at the declared period: " $0; exit 1 } }' || exit 1
echo "declared period $P ps"

cp "$RES/6_final.def" "$HERE/baseline/top.def"; cp "$RES/6_final.v" "$HERE/baseline/top.v"
cp "$RES/6_final.spef" "$HERE/baseline/top.spef"; cp "$RES/6_final.gds" "$HERE/baseline/final.gds"
echo "$P" > "$HERE/baseline/period.txt"
WORK_HOME="$WORK_HOME" python3 "$HERE/flow/metrics.py" $NICK $V > "$HERE/baseline/metrics.json"
python3 - "$LOG" "$HERE/baseline/runtime.json" "$(( $(date +%s) - T_START ))" <<'PY'
import sys, json
steps, peak = {}, 0
for l in open(sys.argv[1]):
    f = l.split()
    if len(f) >= 3:
        steps[f[0]] = int(f[2])
        if len(f) > 3 and f[3].isdigit(): peak = max(peak, int(f[3]))
out = {"wall_s": int(sys.argv[3]), "per_step_s": steps, "peak_kb_any": peak}
json.dump(out, open(sys.argv[2], "w"), indent=1)
print(f"wall clock {out['wall_s'] / 60:.1f} min; peak {peak / 1e6:.1f} GB")
PY
echo "Reference done. Artifacts in baseline/, metrics in baseline/metrics.json, runtime in baseline/runtime.json."
