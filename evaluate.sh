#!/usr/bin/env bash
# The judge: re-derives every gate and number from an entry's result/ with the pinned tools and inputs
# (flow/eval/evaluate.py). usage: ./evaluate.sh result/ [--jobs N]
set -euo pipefail
RESULT=${1:?usage: ./evaluate.sh result/ [--jobs N]}; shift
HERE=$(cd "$(dirname "$0")" && pwd)
# the pinned OpenROAD-flow-scripts: orfs/ (linked by setup.sh), or ORFS_HOME, as judge/run_entry.sh sets it
ORFS=${ORFS_HOME:-$HERE/orfs}
[ -d "$ORFS" ] || { echo "run ./setup.sh first"; exit 1; }
# shellcheck disable=SC1091
source "$ORFS/env.sh" > /dev/null
export ORFS_HOME=$ORFS
# every step uses the official run's 8 threads: inside a container the flow still sees every host core.
# (The design-rule check is the evaluator's largest step, 9.3 GB on the reference at 1 thread or 8.)
export NUM_CORES=${NUM_CORES:-8}
exec python3 "$HERE/flow/eval/evaluate.py" "$RESULT" --work "$HERE/eval_work/$(basename "$(cd "$RESULT" && pwd)")" "$@"
