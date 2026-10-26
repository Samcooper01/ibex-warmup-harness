# Chipbase Warmup: Ibex RISC-V Core

<p align="center">
  <a href="https://github.com/The-OpenROAD-Project/OpenROAD"><img src="docs/img/logo_openroad.png" height="72" alt="OpenROAD"></a>&nbsp;&nbsp;&nbsp;&nbsp;
  <a href="https://github.com/YosysHQ/yosys"><img src="docs/img/logo_yosys.png" height="72" alt="Yosys"></a>&nbsp;&nbsp;&nbsp;&nbsp;
  <a href="https://www.klayout.de"><img src="docs/img/logo_klayout.png" height="72" alt="KLayout"></a>
</p>

<p align="center">
  <sub><b><a href="https://samcooper01.github.io/chipbase/challenges/ibex/">The warmup page</a></b>: the design, the rules, the scoring, and how to begin.</sub>
</p>

> **Status: under construction.** The harness, the reference flow, and the evaluator are here; the
> reference run, the power workload (`design/activity/`), and the reference values in `scoring.yaml`
> are not done yet. Until they are, the evaluator stops at the power step and does not score.

This repository is the evaluation harness for the warmup challenge on Chipbase, a free site for
learning physical design. It is a smaller companion to
[Chipbase Competition 01](https://github.com/Samcooper01/systolic-array-ai-accelerator-harness): the
same kind of harness, evaluator, and score, on a design that runs through the flow in under an hour.
Entrants implement Ibex [1], a 32-bit RISC-V [2] processor core, from RTL to a complete layout in the
ASAP7 predictive process [3], using only open-source tools. Every entry that passes all gates is scored
on clock period, area, and power relative to the reference flow included here.

## Getting started

Requirements: Docker, 8 or more hardware threads, and 16 GB of memory. Every tool comes from one pinned
container image, the OpenROAD-flow-scripts project's own, the same image as Competition 01.

    git clone https://github.com/Samcooper01/ibex-warmup-harness
    cd ibex-warmup-harness
    docker run --rm -it -v "$PWD":/work -w /work \
      openroad/orfs@sha256:6bc088ee563c76374f7ef5d0a3244d607a6162c8979f1815f92eef683c1169a4 bash

    # inside the container:
    ./setup.sh                  # links the container's tools and checks them
    ./run_baseline.sh           # the reference flow, into baseline/
    ./evaluate.sh baseline/     # every gate and the score

Once the reference values are set, the expected result is that every gate passes and the score is
1.000. The full report is written to `eval_work/baseline/evaluation.json`.

## Building an entry

An entry is a git repository of source only: `reproduce/Dockerfile` defines its container, and
`reproduce/run.sh` builds the layout from the pinned inputs. This repository's `reproduce/` already
packages the reference this way, so the simplest start is to fork it and modify the flow in `flow/`.

1. **Iterate** inside the container:

       ./run_baseline.sh           # runs your flow into baseline/
       ./evaluate.sh baseline/     # every gate and the score

2. **Test** once before submitting. Commit your work, then run the official runner in a terminal
   on your own machine, outside the container (it starts containers itself):

       judge/run_entry.sh

   It builds and runs your latest commit exactly as the official run does and scores it. The score
   lands in `eval_work/mine/evaluation.json`. It needs Git and Python 3; for an entry that is not a
   fork of this repository, give its location and commit: `judge/run_entry.sh <path or URL> <commit>`.

3. **Submit** by opening an issue on this repository with the entry's repository, the commit, and
   the `evaluation.json`.

The full specification is in `submission/README.md`.

## Reference implementation

The reference flow runs on OpenROAD-flow-scripts: Yosys [4] for synthesis, then OpenROAD [5] for
floorplanning, global placement [6], clock tree synthesis, and detailed routing [7]. Its configuration
(`flow/ibex/config.mk`) is OpenROAD-flow-scripts' own for Ibex, built flat. Beyond the stock flow, it
adds:

- **Hold closure loop** (`flow/eco_hold.tcl`): repairs hold on extracted parasitics and reroutes until
  the routed layout meets hold.
- **Two-corner timing**: the flow runs at the fast corner, and the declared period comes from a
  slow-corner setup search on the finished layout (`flow/time_at_period.tcl`).

Entrants may change any of this. What binds them is the result, which the gates check: timing at both
corners, IR drop, design rules, equivalence, and the compute budget.

## Details

[Problem definition](#problem-definition) ·
[Rules](#rules) ·
[Scoring](#scoring) ·
[Evaluation gates](#evaluation-gates) ·
[Reference results](#reference-results) ·
[Repository layout](#repository-layout) ·
[References](#references)

### Problem definition

Fixed and identical for all entrants:

- **Design.** Ibex in the configuration OpenROAD-flow-scripts ships: RV32IMC, a two-stage pipeline,
  a flip-flop register file, the fast multiplier, and no memory macros. Supplied as SystemVerilog in
  `design/rtl/`; the top module is `ibex_core`.
- **Process.** ASAP7 as shipped in OpenROAD-flow-scripts at the pinned commit.
- **Constraints.** `flow/ibex/constraint.sdc`, in which the clock period is the only free value. One
  clock, on `clk_i`; input-to-register and register-to-output paths within 80 percent of the period,
  input-to-output within 60 percent; no clock uncertainty, input drive, output load, or false paths.
  The evaluator times every entry against this file.
- **Power workload.** `design/activity/`: the switching activity of a short program run on the golden
  RTL (not made yet).

`versions.lock` records every pinned version.

### Rules

- **Permitted:** any open-source tools, stock or modified; custom open-source tooling in the entry's
  repository; any optimization; teams; and resubmission, with the best score counting.
- **Prohibited:** commercial or proprietary tools, libraries, or IP; hardened blocks (the design is
  built flat); changing the design's function or interface; changing synthesis in any way (no retiming,
  scan insertion, or register changes beyond what the pinned synthesis produces); modifying fixed
  inputs, constraints, the evaluator, or the runner; network access during the build; shipping a
  finished placement, routing, or gate-level netlist.
- **Chosen by the entrant:** the clock period; die size, aspect ratio, and utilization; I/O pin
  placement; clock-tree targets and useful skew; cell selection, including threshold-voltage mix; the
  power grid; and every other flow parameter.
- **Fixed:** the constraints apart from the period; the corners (setup at slow, hold at fast, power at
  typical); the 110 mV IR-drop limit; per-layer wire parasitics (M2 to M9); the switching activity.

### Scoring

$$
\mathrm{FOM} = \left(\frac{T_\mathrm{ref}}{T}\right)^{0.50} \cdot \left(\frac{A_\mathrm{ref}}{A}\right)^{0.30} \cdot \left(\frac{P_\mathrm{ref}}{P}\right)^{0.20}
$$

T is the declared clock period, at which the entry must pass setup; A is the die area; and P is the
total power at a fixed 1,000 ps clock under the pinned activity, so a slower clock does not lower it.
Higher is better; the reference scores 1.000. Speed weighs most because on a processor core the clock
period is where placement, sizing, buffering, and the clock tree show; synthesis fixes the cells, so
area comes down mostly to placement density. The weights are fixed and will not change once entries
arrive.

### Evaluation gates

An entry is ranked only if it passes all eight gates. `./evaluate.sh` checks gates 1 to 7 from the
layout alone, with the pinned tools; the official runner checks gate 8.

1. **Flat.** One layout of standard cells, with no hardened blocks.
2. **Timing.** Setup at the slow corner at the declared period and hold at the fast corner, on
   parasitics the evaluator extracts itself.
3. **Legality and routing.** No overlaps, every cell on the placement grid, no unrouted nets.
4. **Power integrity.** Worst static IR drop at most 110 mV.
5. **Design rules.** No shorts or via violations, per the detailed router's rule checker. Its other
   findings and the ASAP7 KLayout deck are informational, as in Competition 01.
6. **Logical equivalence.** The netlist is proven equivalent by ABC [8] to the evaluator's own
   synthesis of the golden RTL, so synthesis is fixed and everything after it is verified. If ABC
   cannot finish, the netlist is checked with 2,000,000 random vectors instead.
7. **Layout versus netlist.** The layout's pin-level connectivity matches its netlist.
8. **Compute budget.** The whole build takes 1 hour or less at 8 threads and 16 GB, timed by the
   official runner.

### Reference results

<!-- REF_RESULTS -->
Not measured yet: the reference run is pending. This table will hold the declared clock period, die
area, total power, worst IR drop, hold, design-rule count, equivalence, the build's wall-clock time,
and the evaluator's runtime.
<!-- /REF_RESULTS -->

### Repository layout

    design/               fixed inputs: rtl/ (with its LICENSE), activity/
    flow/ibex/            reference flow configuration, constraints, and wire parasitics
    flow/eval/            the evaluator
    reproduce/            the reference packaged as an entry
    judge/                the official runner and the clean-machine test
    setup.sh              links the pinned tools
    run_baseline.sh       runs the flow
    evaluate.sh           runs the evaluator
    scoring.yaml          gates, weights, and reference values
    versions.lock         every pinned version
    submission/           the submission specification
    docs/                 README images

    generated, not tracked: work/, baseline/, judge_work/, eval_work/

### References

1. lowRISC, "[Ibex Documentation](https://ibex-core.readthedocs.io/en/latest/)," and the
   [Ibex source](https://github.com/lowRISC/ibex).
2. A. Waterman and K. Asanović, Eds., "[The RISC-V Instruction Set
   Manual](https://github.com/riscv/riscv-isa-manual)," RISC-V International.
3. L. T. Clark et al., "[ASAP7: A 7-nm FinFET Predictive Process Design
   Kit](https://asu.elsevierpure.com/en/publications/asap7-a-7-nm-finfet-predictive-process-design-kit/),"
   *Microelectronics Journal*, vol. 53, pp. 105-115, July 2016.
4. C. Wolf and J. Glaser, "[Yosys: A Free Verilog Synthesis
   Suite](https://research.jku.at/en/publications/yosys-a-free-verilog-synthesis-suite/)," in
   *Proc. Austrochip Workshop on Microelectronics*, 2013, pp. 47-52.
5. T. Ajayi et al., "[Toward an Open-Source Digital Flow: First Learnings from the OpenROAD
   Project](https://par.nsf.gov/biblio/10171025)," in *Proc. 56th Annual Design Automation
   Conference*, 2019, pp. 76:1-76:4.
6. C.-K. Cheng, A. B. Kahng, I. Kang, and L. Wang, "[RePlAce: Advancing Solution Quality and
   Routability Validation in Global Placement](https://doi.org/10.1109/TCAD.2018.2859220)," *IEEE
   Transactions on Computer-Aided Design of Integrated Circuits and Systems*, vol. 38, no. 9,
   pp. 1717-1730, 2019.
7. A. B. Kahng, L. Wang, and B. Xu, "[TritonRoute: The Open-Source Detailed
   Router](https://doi.org/10.1109/TCAD.2020.3003234)," *IEEE Transactions on Computer-Aided Design
   of Integrated Circuits and Systems*, vol. 40, no. 3, pp. 547-559, 2021.
8. R. Brayton and A. Mishchenko, "[ABC: An Academic Industrial-Strength Verification
   Tool](https://doi.org/10.1007/978-3-642-14295-6_5)," in *Computer Aided Verification (CAV 2010)*,
   LNCS 6174, pp. 24-40, 2010.

Pinned software:
[OpenROAD-flow-scripts @ bde10c7](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/tree/bde10c79a2389ffe9c5d73445f177f81262059f9) ·
[container image](https://hub.docker.com/r/openroad/orfs) (tag 26Q3-48-gbde10c79a) ·
[Ibex @ 77d8010](https://github.com/lowRISC/ibex/tree/77d801001554cce8fe69e742e96539eecbe74425) [1] ·
[OpenROAD](https://github.com/The-OpenROAD-Project/OpenROAD) [5] ·
[Yosys](https://github.com/YosysHQ/yosys) [4] ·
[ABC](https://github.com/berkeley-abc/abc) [8] ·
[KLayout](https://www.klayout.de)

## About

The Chipbase Warmup was designed and built by Sam Cooper
([@Samcooper01](https://github.com/Samcooper01)). Questions, bug reports, and submissions go through
this repository's issues.

## License

The Ibex RTL in `design/rtl/` is lowRISC's, under the Apache License 2.0; the text is in
`design/rtl/LICENSE`.
