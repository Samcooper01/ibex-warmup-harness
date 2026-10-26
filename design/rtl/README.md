# The golden RTL

Ibex, lowRISC's 32-bit RISC-V core, copied unchanged from OpenROAD-flow-scripts at the pinned commit
(`flow/designs/src/ibex_sv` at `bde10c7`), which vendors it from
[lowRISC/ibex @ 77d8010](https://github.com/lowRISC/ibex/tree/77d801001554cce8fe69e742e96539eecbe74425)
in its default configuration. `ORFS_README.md` is that folder's own note on where it came from and what
was pruned.

- `*.sv`: the core; the top module is `ibex_core`
- `syn/prim_clock_gating.v`: the clock gate used for synthesis
- `prim/`: include files only (assertion macros), passed as an include directory, not as sources

Every entry synthesizes from these files with the pinned settings (`flow/eval/eval_synth.mk`). They are
licensed under the Apache License 2.0; the text is in `LICENSE`.
