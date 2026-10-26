# Handoff: Chipbase Warmup harness

Development record. The harness was built on 2026-10-25 from the Competition 01 harness
(`Samcooper01/systolic-array-ai-accelerator-harness`), cut down to a flat design with no memory macros.
Nothing in it has been run yet: the machine was busy with another job, so every script below was
written and syntax-checked but not executed.

## What came from Competition 01, and what changed

- **Same:** the pinned container, OpenROAD-flow-scripts commit, tools, `setup.sh`, the hold loop
  (`flow/eco_hold.tcl`, `flow/hold_check.tcl`), the period search (`flow/time_at_period.tcl`), the
  wire parasitics (`flow/ibex/setRC.tcl`), and the evaluator's proof machinery (`flow/eval/regcut.py`,
  `regsim.py`, `cutpoints.py`, `align_cuts.py`, `vecsim.py`, `seqsim.py`).
- **Changed:** `run_baseline.sh` (flat: no blocks, no slow block models; runtime is wall clock),
  `flow/eval/evaluate.py` (no block step; a flat gate), `drc.py` and `lvs.py` (one layout),
  `equiv.py` (no black boxes; Ibex's RTL list and include directory; a model for the
  asynchronous-reset flip-flop), `activity.py` (clock `core_clock`, ports `clk_i` and `rst_ni`),
  `judge/run_entry.sh` (wall-clock budget, 8 threads, 16 GB), `scoring.yaml`, `versions.lock`.
- **Reference flow:** `flow/ibex/config.mk` is ORFS's own Ibex config made flat. `SWAP_ARITH_OPERATORS`
  is left out: ORFS refuses it without `OPENROAD_HIERARCHICAL`, and it changes synthesis.

## Open items, in order

1. **Pinned synthesis and equivalence on Ibex.** Run the pinned synthesis (`flow/eval/eval_synth.mk`)
   and the equivalence gate on its own output first. Two things are new compared with Competition 01:
   the 1,665 asynchronous-reset flip-flops (`DFFASRHQNx1`, modelled in `equiv.py`), and the clock gate's
   latch (`DLLx1`, one instance, from `prim_clock_gating`). `regcut.py` has not seen a latch before.
2. **Power workload.** Write the program, the testbench, and the trace-to-activity script in
   `design/activity/` (see its README), and make `ibex_activity.tsv.gz`. The pinned image has no
   simulator or RISC-V compiler; whatever is used is recorded in `versions.lock`.
3. **Reference run.** `./run_baseline.sh`, then `./evaluate.sh baseline/`; confirm the build fits the
   1 hour budget on 8 threads with room to spare (an earlier hierarchical Ibex run took about 26 minutes
   on 32 threads, not a like-for-like number).
4. **Reference values.** Fill `scoring.yaml` (`baseline:`) and the README's reference results.
5. **Clean-machine test.** `judge/validate_reference.sh`, and `judge/run_entry.sh` on the reference.
6. **Site.** Fill the warmup page (`app/challenge_content.py` in the chipbase repository): reference
   numbers, the reference layout section, `repo_url`, and the starting-file links.
