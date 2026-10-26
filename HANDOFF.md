# Handoff: Chipbase Warmup harness

Development record. The harness was built on 2026-10-25 from the Competition 01 harness
(`Samcooper01/systolic-array-ai-accelerator-harness`), cut down to a flat design with no memory macros,
and validated the same day in the pinned container.

## What came from Competition 01, and what changed

- **Same:** the pinned container, OpenROAD-flow-scripts commit, tools, `setup.sh`, the hold loop
  (`flow/eco_hold.tcl`, `flow/hold_check.tcl`), the period search (`flow/time_at_period.tcl`), the
  wire parasitics (`flow/ibex/setRC.tcl`), and the evaluator's proof machinery (`flow/eval/regcut.py`,
  `regsim.py`, `cutpoints.py`, `align_cuts.py`, `vecsim.py`, `seqsim.py`).
- **Changed:** `run_baseline.sh` (flat: no blocks, no slow block models; runtime is wall clock),
  `flow/eval/evaluate.py` (no block step; a flat gate), `drc.py` and `lvs.py` (one layout),
  `activity.py` (clock `core_clock`, ports `clk_i` and `rst_ni`), `judge/run_entry.sh` (wall-clock
  budget, 8 threads, 16 GB), `evaluate.sh` (8 threads), `scoring.yaml`, `versions.lock`.
- **Equivalence (`equiv.py`):** no black boxes; Ibex's RTL list and include directory. Two models are
  new, both found on the first run: Ibex's 1,664 asynchronous-reset flip-flops (`DFFASRHQNx1`) lost their
  names in Yosys's `async2sync` and could not be paired, and the clock gate's latch (`DLLx1`) became a
  flip-flop type `regcut.py` rejects. Both are now modelled so each stored value keeps its name
  (`<instance>.Q`); the reset nets and the latch's input are still compared.
- **Reference flow:** `flow/ibex/config.mk` is ORFS's own Ibex config made flat. `SWAP_ARITH_OPERATORS`
  is left out: ORFS refuses it without `OPENROAD_HIERARCHICAL`, and it changes synthesis.
- **Power workload (`design/activity/`):** new. It simulates the pinned synthesis netlist, not the RTL,
  so the activity's names match every entry's flip-flops (the register file is one flattened 992-bit
  vector there, and state machines are re-encoded). `make_activity.sh` rebuilds it in about two minutes.

## Validation (2026-10-25, pinned container, 8 CPUs, 10 GB memory cap)

| Check | Result |
|---|---|
| Pinned synthesis | 36 s, 0.27 GB; 19,043 cells, 1,937 flip-flops, 1 latch |
| Equivalence, synthesis against itself | proven, 1,938 of 1,938 paired; 29 s, 0.5 GB |
| `flow/eval/tests/planted_bugs.sh` | original proven; swapped wire, wrong gate, broken clock enable, broken reset each fail with a real difference |
| Power workload | checksum a890a19b matches the native run; 42,302 cycles; 1,938 of 1,938 flip-flops covered |
| `./run_baseline.sh` | 15.1 min, peak 4.5 GB; hold met without a repair round; declared 2,126 ps |
| `./evaluate.sh baseline/` | all gates pass, score 1.000; 1.6 min, peak 9.3 GB |
| `judge/run_entry.sh` | budget gate pass (903 s of 3,600); identical numbers, score 1.000; 16.6 min in all |
| `judge/validate_reference.sh` (fresh clone, the README's commands) | all gates pass, score 1.000, identical numbers; flow 14.7 min, peak 4.7 GB; 18 min in all, setup included |

The evaluator's peak is the design-rule check (`drt::check_drc`): 9.3 GB at 1 thread or 8, so it does
not depend on the thread count. It is within the 16 GB limit, but it is the largest step, larger than
the flow itself.

## Open items

1. **Site.** The warmup page (`app/challenge_content.py` and `app/templates/challenge_ibex.html` in the
   chipbase repository) carries these numbers; keep it in step with `README.md` and `scoring.yaml`.
