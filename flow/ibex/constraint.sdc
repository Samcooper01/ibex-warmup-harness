# Chipbase Warmup reference constraints. The clock period is the one knob entrants choose; everything
# else is fixed. The evaluator times every entry against this file, with only clk_period replaced.
set clk_name core_clock
set clk_port_name clk_i
set clk_period 1000
# Optimization targets for io paths (see $PLATFORM_DIR/constraints.sdc for the rationale).
set in2reg_max  [expr { $clk_period * 0.8 }]
set reg2out_max [expr { $clk_period * 0.8 }]
set in2out_max  [expr { $clk_period * 0.6 }]
source $::env(PLATFORM_DIR)/constraints.sdc
