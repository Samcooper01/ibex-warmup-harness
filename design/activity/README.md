# Power workload

The power score uses one pinned switching-activity file, `ibex_activity.tsv.gz`, the same for every
entry. For every flip-flop bit and input port bit of Ibex, it records toggles per clock cycle and the
fraction of time at logic 1, measured while a short program runs. The evaluator matches these to an
entry's flip-flops by name (`flow/eval/activity.py`) and lets OpenSTA propagate activity through the logic
between them. Every one of the pinned synthesis's 1,938 flip-flops and latches has its own entry.

## The program

`workload.c` runs four kernels, so every part of the core switches: a CRC-32 over a 256-byte buffer
(shifts, exclusive-or, branches), a 12 by 12 integer matrix multiply (multiplies, loads, stores), an
insertion sort of 64 values (compares, branches, memory traffic), and 48 rounds of divides and
remainders. It marks the start and end of the measured window with two writes, and ends by writing a
checksum. The measured window is 42,302 clock cycles.

## How the file is made

`make_activity.sh` makes it, and anyone can rerun it; entrants never need to. It simulates the pinned
synthesis of the golden RTL, the same gate netlist every entry is proven equivalent to, so the flip-flop
names in the file are the names in every entry's netlist, including the flattened register file and
the re-encoded state machines.

1. The pinned synthesis (`flow/eval/eval_synth.mk`), in the pinned container.
2. That netlist flattened into plain Verilog: cell logic from the typical-corner libraries, and the
   sequential cells from `sim_models.v`, which store the true value with asynchronous set and reset.
3. The program compiled for RV32IMC (`start.S`, `link.ld`, Zig 0.13.0's clang and linker).
4. A simulation with Icarus Verilog (`tb.v`): a 64 KiB memory on both ports. The simulation passes only
   if the core writes the same checksum the program gives when compiled and run natively, so the
   activity always comes from a correct run.
5. The trace over the measured window turned into the file (`vcd_to_activity.py`).

The whole run takes about two minutes.
