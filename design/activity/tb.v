// Testbench for the power workload: Ibex's pinned synthesis (flattened by make_activity.sh) with a 64 KiB
// memory on both its instruction and data ports, loaded from the compiled program. Every request is granted
// at once and answered on the next clock. The program marks the measured window with writes to MARK_START
// and MARK_END, and ends by writing its checksum to RESULT; the testbench checks the checksum against
// +expect, writes the window's start and end times to +window, and dumps the flip-flops and inputs to
// +vcd (the signal list is the generated dump_signals.vh).
`timescale 1ns/1ps
module tb;
  localparam MARK_START = 32'h0001_0000, MARK_END = 32'h0001_0004, RESULT = 32'h0001_0008;
  localparam MAX_CYCLES = 2000000;

  reg clk = 1'b0, rst_n = 1'b0;
  always #5 clk = ~clk;                       // a 10 ns clock: cycles are window length / 10

  reg [31:0] mem [0:16383];                   // 64 KiB, word addressed
  reg [1023:0] hexfile, vcdfile, winfile;
  reg [31:0] expect;
  integer winfd, cycles = 0;
  real t_start = -1.0, t_end = -1.0;

  wire        instr_req, data_req, data_we;
  wire [31:0] instr_addr, data_addr, data_wdata;
  wire [3:0]  data_be;
  reg         instr_rvalid = 1'b0, data_rvalid = 1'b0;
  reg  [31:0] instr_rdata = 32'b0, data_rdata = 32'b0;

  ibex_core dut (
    .clk_i(clk), .rst_ni(rst_n), .test_en_i(1'b0), .hart_id_i(32'b0), .boot_addr_i(32'b0),
    .instr_req_o(instr_req), .instr_gnt_i(instr_req), .instr_rvalid_i(instr_rvalid),
    .instr_addr_o(instr_addr), .instr_rdata_i(instr_rdata), .instr_err_i(1'b0),
    .data_req_o(data_req), .data_gnt_i(data_req), .data_rvalid_i(data_rvalid), .data_we_o(data_we),
    .data_be_o(data_be), .data_addr_o(data_addr), .data_wdata_o(data_wdata), .data_rdata_i(data_rdata),
    .data_err_i(1'b0), .irq_software_i(1'b0), .irq_timer_i(1'b0), .irq_external_i(1'b0),
    .irq_fast_i(15'b0), .irq_nm_i(1'b0), .debug_req_i(1'b0), .fetch_enable_i(1'b1),
    .alert_minor_o(), .alert_major_o(), .core_sleep_o()
  );

  initial begin
    if (!$value$plusargs("hex=%s", hexfile) || !$value$plusargs("vcd=%s", vcdfile) ||
        !$value$plusargs("window=%s", winfile) || !$value$plusargs("expect=%h", expect)) begin
      $display("TB_ERROR usage: +hex=<file> +vcd=<file> +window=<file> +expect=<hex checksum>"); $finish;
    end
    $readmemh(hexfile, mem);
    $dumpfile(vcdfile);
    `include "dump_signals.vh"
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  // instruction port: read only
  always @(posedge clk) begin
    instr_rvalid <= instr_req;
    if (instr_req) instr_rdata <= mem[instr_addr[15:2]];
  end

  // data port: memory below 64 KiB, the three testbench registers above it
  always @(posedge clk) begin
    data_rvalid <= data_req;
    if (data_req && !data_we) data_rdata <= mem[data_addr[15:2]];
    if (data_req && data_we) begin
      if (data_addr == MARK_START) t_start = $realtime;
      else if (data_addr == MARK_END) t_end = $realtime;
      else if (data_addr == RESULT) begin
        winfd = $fopen(winfile, "w");
        $fdisplay(winfd, "%0.3f %0.3f", t_start, t_end);
        $fclose(winfd);
        if (t_start < 0 || t_end < 0) $display("TB_FAIL the program did not mark its window");
        else if (data_wdata !== expect) $display("TB_FAIL checksum %08x, expected %08x", data_wdata, expect);
        else $display("TB_PASS checksum %08x; window %0d cycles", data_wdata, $rtoi((t_end - t_start) / 10.0));
        $finish;
      end else if (data_addr[31:16] == 16'b0) begin
        if (data_be[0]) mem[data_addr[15:2]][7:0]   <= data_wdata[7:0];
        if (data_be[1]) mem[data_addr[15:2]][15:8]  <= data_wdata[15:8];
        if (data_be[2]) mem[data_addr[15:2]][23:16] <= data_wdata[23:16];
        if (data_be[3]) mem[data_addr[15:2]][31:24] <= data_wdata[31:24];
      end else begin
        $display("TB_FAIL write outside memory at %08x", data_addr); $finish;
      end
    end
  end

  always @(posedge clk) begin
    cycles = cycles + 1;
    if (cycles > MAX_CYCLES) begin $display("TB_FAIL no checksum after %0d cycles", MAX_CYCLES); $finish; end
  end
endmodule
