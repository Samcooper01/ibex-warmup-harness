// Simulation models of the ASAP7 sequential cells in Ibex's pinned synthesis, read before the libraries
// so they replace the libraries' own (make_sim_netlist.ys). Each stores the true value on Q, so after
// flattening every flip-flop's state is the wire "<instance>.Q", named as in every entry's netlist.
// Unlike the equivalence gate's models (flow/eval/equiv.py), these keep the hardware's timing behaviour:
// asynchronous set and reset, and transparent latches.

module DFFHQNx1_ASAP7_75t_R (input CLK, input D, output QN);
  reg Q;
  always @(posedge CLK) Q <= D;
  assign QN = ~Q;
endmodule
module DFFHQNx2_ASAP7_75t_R (input CLK, input D, output QN);
  reg Q;
  always @(posedge CLK) Q <= D;
  assign QN = ~Q;
endmodule
module DFFHQNx3_ASAP7_75t_R (input CLK, input D, output QN);
  reg Q;
  always @(posedge CLK) Q <= D;
  assign QN = ~Q;
endmodule

// library: clear "!SETN" (Q = 1), preset "!RESETN" (Q = 0), both low gives Q = 1
module DFFASRHQNx1_ASAP7_75t_R (input CLK, input D, input RESETN, input SETN, output QN);
  reg Q;
  always @(posedge CLK or negedge RESETN or negedge SETN)
    if (!SETN) Q <= 1'b1;
    else if (!RESETN) Q <= 1'b0;
    else Q <= D;
  assign QN = ~Q;
endmodule

// latches: DLL is transparent while CLK is low (the clock gate's enable latch), DHL while it is high
module DLLx1_ASAP7_75t_R (input CLK, input D, output reg Q);
  always @(*) if (!CLK) Q = D;
endmodule
module DHLx1_ASAP7_75t_R (input CLK, input D, output reg Q);
  always @(*) if (CLK) Q = D;
endmodule
