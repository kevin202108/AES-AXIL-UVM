// =============================================================================
//  axil_if.svh  -  AXI4-Lite signal bundle + protocol assertions (SVA)
// =============================================================================
interface axil_if (input logic clk, input logic rst_n);
    // write address
    logic [7:0]  awaddr;
    logic [2:0]  awprot;
    logic        awvalid;
    logic        awready;
    // write data
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;
    // write response
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;
    // read address
    logic [7:0]  araddr;
    logic [2:0]  arprot;
    logic        arvalid;
    logic        arready;
    // read data
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;

    // -------------------------------------------------------------------------
    //  AMBA AXI4-Lite handshake assertions (sim only)
    //   1) VALID must stay asserted until the matching READY (no withdrawal)
    //   2) payload must be stable while VALID && !READY
    // -------------------------------------------------------------------------
`ifndef SYNTHESIS
    // VALID held until READY
    property p_vld_stable(valid, ready);
        @(posedge clk) disable iff (!rst_n) (valid && !ready) |=> valid;
    endproperty

    // payload stable while stalled (VALID && !READY)
    property p_sig_stable(valid, ready, sig);
        @(posedge clk) disable iff (!rst_n) (valid && !ready) |=> $stable(sig);
    endproperty

    a_awvalid_stable: assert property (p_vld_stable(awvalid, awready))
        else $error("AXI: AWVALID dropped before AWREADY");
    a_wvalid_stable:  assert property (p_vld_stable(wvalid, wready))
        else $error("AXI: WVALID dropped before WREADY");
    a_arvalid_stable: assert property (p_vld_stable(arvalid, arready))
        else $error("AXI: ARVALID dropped before ARREADY");
    a_bvalid_stable:  assert property (p_vld_stable(bvalid, bready))
        else $error("AXI: BVALID dropped before BREADY");
    a_rvalid_stable:  assert property (p_vld_stable(rvalid, rready))
        else $error("AXI: RVALID dropped before RREADY");

    a_awaddr_stable: assert property (p_sig_stable(awvalid, awready, awaddr))
        else $error("AXI: AWADDR changed while stalled");
    a_wdata_stable:  assert property (p_sig_stable(wvalid, wready, wdata))
        else $error("AXI: WDATA changed while stalled");
    a_wstrb_stable:  assert property (p_sig_stable(wvalid, wready, wstrb))
        else $error("AXI: WSTRB changed while stalled");
    a_araddr_stable: assert property (p_sig_stable(arvalid, arready, araddr))
        else $error("AXI: ARADDR changed while stalled");
    a_bresp_stable:  assert property (p_sig_stable(bvalid, bready, bresp))
        else $error("AXI: BRESP changed while stalled");
    a_rdata_stable:  assert property (p_sig_stable(rvalid, rready, rdata))
        else $error("AXI: RDATA changed while stalled");

    // control handshake signals must never be X/Z after reset
    a_ctrl_known: assert property (@(posedge clk) disable iff (!rst_n)
        !$isunknown({awvalid, wvalid, bvalid, arvalid, rvalid,
                     awready, wready, bready, arready, rready}))
        else $error("AXI: a handshake control signal is X/Z");

    // this slave only ever issues OKAY (00) or SLVERR (10)
    a_bresp_legal: assert property (@(posedge clk) disable iff (!rst_n)
        bvalid |-> (bresp == 2'b00 || bresp == 2'b10))
        else $error("AXI: illegal BRESP");
    a_rresp_legal: assert property (@(posedge clk) disable iff (!rst_n)
        rvalid |-> (rresp == 2'b00 || rresp == 2'b10))
        else $error("AXI: illegal RRESP");

    // -------------------------------------------------------------------------
    //  Cover properties: witnesses that the interesting scenarios actually
    //  happen. Same form a formal tool (JasperGold/VC Formal) would consume.
    // -------------------------------------------------------------------------
    c_aw_hs:    cover property (@(posedge clk) disable iff (!rst_n) awvalid && awready);
    c_w_hs:     cover property (@(posedge clk) disable iff (!rst_n) wvalid  && wready);
    c_b_hs:     cover property (@(posedge clk) disable iff (!rst_n) bvalid  && bready);
    c_ar_hs:    cover property (@(posedge clk) disable iff (!rst_n) arvalid && arready);
    c_r_hs:     cover property (@(posedge clk) disable iff (!rst_n) rvalid  && rready);
    c_bp_bwait: cover property (@(posedge clk) disable iff (!rst_n) bvalid && !bready); // B backpressure
    c_bp_rwait: cover property (@(posedge clk) disable iff (!rst_n) rvalid && !rready); // R backpressure
    c_slverr:   cover property (@(posedge clk) disable iff (!rst_n)
                    (bvalid && bready && bresp == 2'b10) ||
                    (rvalid && rready && rresp == 2'b10));                              // error response seen
`endif
endinterface
