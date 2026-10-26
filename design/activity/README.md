# Power workload

Not made yet. It is published together with the reference run, and the evaluator stops at the power
step until it exists.

The power score uses one pinned switching-activity file, `ibex_activity.tsv.gz`, the same for every
entry. It will come from a short program run on the golden RTL in simulation: integer arithmetic,
multiplies and divides, loads and stores, and branches, so every part of the core switches. For every
register bit, the file records its toggles per clock cycle and the fraction of time it is at logic 1,
over the window in which the program runs. The evaluator matches these to the netlist's flip-flops by
register name (`flow/eval/activity.py`) and lets OpenSTA propagate activity through the logic between them.

When it is made, this folder will hold the program's source, the testbench, the script that turns the
simulation trace into the activity file, and the file itself, and `versions.lock` will record the
compiler and simulator versions used.
