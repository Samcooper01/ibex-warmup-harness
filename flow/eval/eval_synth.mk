# The pinned synthesis, run by the evaluator (equiv.py): the golden Ibex RTL through the pinned Yosys with
# the pinned settings, flat. The entry's final netlist must be equivalent to this output. Settings an
# entrant may not change: the RTL, the constraint file (its clock period steers synthesis), the frontend,
# and the hierarchy mode (flat, as in the reference flow).
include $(dir $(lastword $(MAKEFILE_LIST)))eval.mk
export DESIGN_NICKNAME = evalsynth_$(DESIGN_NAME)
export VERILOG_FILES = $(sort $(wildcard $(CB)/design/rtl/*.sv)) $(CB)/design/rtl/syn/prim_clock_gating.v
export VERILOG_INCLUDE_DIRS = $(CB)/design/rtl/prim
export SYNTH_HDL_FRONTEND = slang
export SYNTH_HIERARCHICAL = 0
