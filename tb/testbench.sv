// =============================================================================
//  testbench.sv  -  UVM top level for aes_axi_lite (Phase 2)
// -----------------------------------------------------------------------------
//  Split, one-class-per-file structure. This pane only pulls the pieces in and
//  instantiates the top module.  Files to add in EDA Playground (Testbench
//  pane "+"):
//      axil_if.svh        axil_pkg.svh       axil_item.svh
//      axil_driver.svh    axil_monitor.svh   axil_agent.svh
//      axil_scoreboard.svh axil_env.svh      axil_sequences.svh
//      axil_tests.svh     aes_ref_model.svh  aes_dpi.svh
//      axil_coverage.svh
//  Design pane "+": aes_rtl.sv; for DPI-C also aes128.c (from c_model/).
//  EDA Playground PRIMARY: enable "Use run.bash shell script", paste
//  sim/run.bash (links aes128.c for VCS/Xcelium; runs dpi + dual-oracle rand).
//  Without run.bash or Compile Options: Error-[DPI-DIFNF] (C not on vcs line).
//  Fallback (no script): Compile Options = aes128.c
//  Run options only matter when NOT using run.bash:
//      +UVM_TESTNAME=axil_dpi_test
//      +UVM_TESTNAME=axil_rand_test +NUM_BLOCKS=10
// =============================================================================
`timescale 1ns/1ps

`include "axil_if.svh"     // interface (outside the package)
`include "axil_pkg.svh"    // package -> includes every UVM component

module top;
    import uvm_pkg::*;
    import axil_pkg::*;
    `include "uvm_macros.svh"

    logic clk;
    logic rst_n;

    // clock : 100 MHz
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // reset : power-on, plus on-demand pulses triggered by a global uvm_event
    // (used by axil_reset_test for reset-in-the-middle).
    uvm_event rst_ev;
    initial begin
        rst_ev = uvm_event_pool::get_global("reset_req");
        rst_n  = 1'b0;
        repeat (5) @(posedge clk);
        rst_n  = 1'b1;
        forever begin
            rst_ev.wait_trigger();
            rst_n <= 1'b0;
            repeat (4) @(posedge clk);
            rst_n <= 1'b1;
        end
    end

    // interface
    axil_if intf (.clk(clk), .rst_n(rst_n));

    // DUT
    aes_axi_lite #(.ADDR_WIDTH(8), .DATA_WIDTH(32)) dut (
        .ACLK    (clk),
        .ARESETN (rst_n),
        .AWADDR  (intf.awaddr),
        .AWPROT  (intf.awprot),
        .AWVALID (intf.awvalid),
        .AWREADY (intf.awready),
        .WDATA   (intf.wdata),
        .WSTRB   (intf.wstrb),
        .WVALID  (intf.wvalid),
        .WREADY  (intf.wready),
        .BRESP   (intf.bresp),
        .BVALID  (intf.bvalid),
        .BREADY  (intf.bready),
        .ARADDR  (intf.araddr),
        .ARPROT  (intf.arprot),
        .ARVALID (intf.arvalid),
        .ARREADY (intf.arready),
        .RDATA   (intf.rdata),
        .RRESP   (intf.rresp),
        .RVALID  (intf.rvalid),
        .RREADY  (intf.rready)
    );

    // hand virtual interface to UVM and launch
    initial begin
        uvm_config_db#(virtual axil_if)::set(null, "*", "vif", intf);
        run_test("axil_smoke_test");
    end

    // -------------------------------------------------------------------------
    //  FSM state / transition coverage (sampled directly from the wrapper FSM)
    // -------------------------------------------------------------------------
`ifndef SYNTHESIS
    covergroup cg_fsm @(posedge clk);
        option.per_instance = 1;
        cp_fsm: coverpoint dut.state iff (rst_n) {
            bins s_idle = {3'd0};
            bins s_feed = {3'd1};
            bins s_wait = {3'd2};
            bins s_cap  = {3'd3};
            bins s_done = {3'd4};
            bins t_idle_feed = (3'd0 => 3'd1);
            bins t_feed_wait = (3'd1 => 3'd2);
            bins t_wait_cap  = (3'd2 => 3'd3);
            bins t_cap_done  = (3'd3 => 3'd4);
            bins t_done_idle = (3'd4 => 3'd0);
        }
        // byte-serial feed/capture indices reach both ends of the range
        cp_feed: coverpoint dut.feed_idx iff (rst_n) { bins lo = {5'd0}; bins hi = {5'd15}; }
        cp_cap:  coverpoint dut.cap_idx  iff (rst_n) { bins lo = {5'd0}; bins hi = {5'd15}; }
    endgroup
    cg_fsm cov_fsm = new();
    final $display("[COV-FSM] FSM state/transition coverage = %0.2f %%",
                   cov_fsm.get_inst_coverage());
`endif

    // waveform dump (optional, viewable in EDA Playground)
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, top);
    end

    // global watchdog (large enough for the 100-block random regression;
    // per-block poll_done has its own 2000-poll safety bound)
    initial begin
        #10000000;
        `uvm_fatal("TIMEOUT", "global watchdog expired")
    end
endmodule
