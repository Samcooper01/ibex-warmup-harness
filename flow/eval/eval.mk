# Evaluator environment: the pinned platform (tech and cell LEFs, per-corner libraries, RCX rules), the
# pinned wire parasitics and the pinned constraints. The evaluator's scripts read the submitted layout
# themselves; nothing here comes from the entry.
export PLATFORM = asap7
CB := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))../..)
export DESIGN_NAME = ibex_core
export DESIGN_NICKNAME = eval
export LAYER_PARASITICS_FILE = $(CB)/flow/ibex/setRC.tcl
export SDC_FILE = $(CB)/flow/ibex/constraint.sdc
