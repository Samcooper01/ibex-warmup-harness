#!/usr/bin/env bash
# Make the pinned switching-activity file, design/activity/ibex_activity.tsv.gz. A maintainer's tool: entrants
# never run it, they use the file. Run from the harness root on the host, with Docker, Python 3 and Icarus
# Verilog installed; it starts the pinned container itself for the synthesis.
#
#   1  the pinned synthesis of the golden RTL (flow/eval/eval_synth.mk), in the pinned container
#   2  that netlist flattened into plain Verilog: cell logic from the typical-corner libraries, sequential
#      cells from sim_models.v (turned into Yosys flip-flop and latch cells by proc, and checked for
#      conflicting drivers and logic loops), so every flip-flop's state is the wire "<instance>.Q"
#   3  the workload (workload.c, start.S, link.ld) compiled for RV32IMC with Zig's clang and linker
#   4  the list of signals to dump: every flip-flop and every input port
#   5  the simulation (tb.v); it fails unless the core writes the checksum the same program gives when
#      compiled and run on this machine
#   6  the trace over the measured window, turned into the activity file (vcd_to_activity.py)
# Work files go to work/activity/. The versions used are the ones recorded in versions.lock.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/../.." && pwd); cd "$HERE"
A=design/activity; W=work/activity; mkdir -p "$W"
IMG=$(awk '$1 == "container" {print $3}' versions.lock)
ZIG_VERSION=0.13.0
[ -x "$W/venv/bin/python" ] || { python3 -m venv "$W/venv"; "$W/venv/bin/pip" install -q "ziglang==$ZIG_VERSION"; }
ZIG="$W/venv/bin/python -m ziglang"
command -v iverilog > /dev/null || { echo "make_activity: Icarus Verilog (iverilog) is required"; exit 1; }

echo "1-2  pinned synthesis and the flat simulation netlist (container)"
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$HERE":/work -w /work "$IMG" bash -c '
  set -e; source orfs/env.sh > /dev/null 2>&1
  W=/work/work/activity; S=$W/synth
  make -C orfs/flow DESIGN_CONFIG=/work/flow/eval/eval_synth.mk WORK_HOME=$S EVAL_WORK=$W synth > $W/synth.log 2>&1
  N=$S/results/asap7/evalsynth_ibex_core/base/1_2_yosys.v
  mkdir -p $W/lib; LIBS=""
  for f in orfs/flow/platforms/asap7/lib/NLDM/asap7sc7p5t_*_RVT_TT_nldm_*.lib*; do
    o=$W/lib/$(basename ${f%.gz}); [ -f $o ] || { case $f in *.gz) zcat $f > $o;; *) cp $f $o;; esac; }; LIBS="$LIBS $o"
  done
  yosys -q -l $W/sim_netlist.log -p "read_verilog design/activity/sim_models.v; read_liberty -ignore_redef -ignore_miss_func $LIBS; read_verilog $N; hierarchy -top ibex_core; proc; flatten; opt_clean; check -assert; write_verilog -noattr $W/ibex_sim.v"
'

echo "3    the workload"
$ZIG cc -target riscv32-freestanding-none -mcpu=generic_rv32+m+c -O2 -ffreestanding -nostdlib -fno-builtin \
  -Wl,-T,$A/link.ld -o "$W/workload.elf" $A/start.S $A/workload.c
$ZIG objcopy -O binary "$W/workload.elf" "$W/workload.bin"
python3 - "$W/workload.bin" "$W/workload.hex" <<'PY'
import sys
b = open(sys.argv[1], "rb").read(); b += b"\0" * (-len(b) % 4)
open(sys.argv[2], "w").write("".join(f"{int.from_bytes(b[i:i + 4], 'little'):08x}\n" for i in range(0, len(b), 4)))
PY
cc -O2 -o "$W/workload_host" $A/workload.c
EXPECT=$("$W/workload_host")
echo "     expected checksum $EXPECT"

echo "4    the signals to dump"
python3 - "$W/ibex_sim.v" "$W/dump_signals.vh" <<'PY'
import re, sys
t = open(sys.argv[1]).read()
regs = re.findall(r"^\s*reg\s+(?:\[[^\]]*\]\s+)?(\\\S+\.Q)\s*;", t, re.M)
ports = re.findall(r"^\s*input\s+(?:\[[^\]]*\]\s+)?(\S+?)\s*;", t, re.M)
with open(sys.argv[2], "w") as f:
    for r in regs: f.write(f"$dumpvars(1, tb.dut.{r} );\n")
    for p in ports: f.write(f"$dumpvars(1, tb.dut.{p});\n")
print(f"     {len(regs)} flip-flops and latches, {len(ports)} input ports")
PY

echo "5    simulation"
iverilog -g2005 -I "$W" -o "$W/sim.vvp" $A/tb.v "$W/ibex_sim.v"
vvp -n "$W/sim.vvp" +hex="$W/workload.hex" +vcd="$W/trace.vcd" +window="$W/window.txt" +expect="$EXPECT" | tee "$W/sim.log"
grep -q "^TB_PASS" "$W/sim.log" || { echo "make_activity: the simulation did not pass"; exit 1; }

echo "6    activity"
python3 $A/vcd_to_activity.py "$W/trace.vcd" "$W/window.txt" "$W/ibex_activity.tsv"
gzip -9n -c "$W/ibex_activity.tsv" > $A/ibex_activity.tsv.gz
echo "wrote $A/ibex_activity.tsv.gz"
