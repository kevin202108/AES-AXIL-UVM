// =============================================================================
//  axil_driver.svh  -  AXI4-Lite master BFM
//  Optional backpressure: set config int "bp_max" > 0 to insert random idle
//  gaps and to delay BREADY/RREADY (stressing the slave's VALID-hold).
//  bp_max == 0 (default) reproduces the original cycle-accurate behaviour.
// =============================================================================
class axil_driver extends uvm_driver #(axil_item);
    `uvm_component_utils(axil_driver)

    virtual axil_if vif;
    int unsigned    bp_max  = 0;  // backpressure: max random delay (0 = off)
    int unsigned    stagger = 0;  // AW/W channel stagger: max gap (0 = together)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axil_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "axil_driver: virtual interface 'vif' not set")
        void'(uvm_config_db#(int unsigned)::get(this, "", "bp_max",  bp_max));
        void'(uvm_config_db#(int unsigned)::get(this, "", "stagger", stagger));
    endfunction

    // random delay in [0, bp_max]; always 0 when backpressure disabled
    function automatic int unsigned bp_delay();
        return (bp_max == 0) ? 0 : $urandom_range(bp_max);
    endfunction

    // Reset-aware: on ARESETN falling (even mid-transaction), abort driving,
    // re-init signals, wait for reset release, then resume. Normal tests (reset
    // stays high after power-on) are unaffected - the reset branch never fires.
    task run_phase(uvm_phase phase);
        forever begin
            init_signals();
            wait (vif.rst_n === 1'b1);
            @(posedge vif.clk);
            fork : ops
                forever begin
                    axil_item req;
                    seq_item_port.get_next_item(req);
                    if (req.is_write) drive_write(req);
                    else              drive_read(req);
                    seq_item_port.item_done();
                end
                @(negedge vif.rst_n);   // reset asserted -> bail out
            join_any
            disable ops;
        end
    endtask

    task automatic init_signals();
        vif.awaddr  <= '0;
        vif.awprot  <= '0;
        vif.awvalid <= 1'b0;
        vif.wdata   <= '0;
        vif.wstrb   <= '0;
        vif.wvalid  <= 1'b0;
        vif.bready  <= 1'b0;
        vif.araddr  <= '0;
        vif.arprot  <= '0;
        vif.arvalid <= 1'b0;
        vif.rready  <= 1'b0;
    endtask

    // ---- single write transaction --------------------------------------
    task automatic drive_write(axil_item req);
        bit aw_done;
        bit w_done;
        aw_done = 1'b0;
        w_done  = 1'b0;

        repeat (bp_delay()) @(posedge vif.clk);   // optional idle gap

        @(posedge vif.clk);
        vif.bready <= (bp_max == 0);   // assert now if no backpressure
        if (stagger == 0) begin
            // AW and W asserted together (default)
            vif.awaddr <= req.addr; vif.awprot <= 3'b000; vif.awvalid <= 1'b1;
            vif.wdata  <= req.data; vif.wstrb  <= req.strb; vif.wvalid <= 1'b1;
        end else begin
            // stagger the channels so one VALID is high while the other is
            // still low -> exercises the per-channel handshake conditions
            int unsigned g = $urandom_range(1, stagger);
            if ($urandom_range(0, 1)) begin
                vif.awaddr <= req.addr; vif.awprot <= 3'b000; vif.awvalid <= 1'b1;
                repeat (g) @(posedge vif.clk);
                vif.wdata  <= req.data; vif.wstrb  <= req.strb; vif.wvalid <= 1'b1;
            end else begin
                vif.wdata  <= req.data; vif.wstrb  <= req.strb; vif.wvalid <= 1'b1;
                repeat (g) @(posedge vif.clk);
                vif.awaddr <= req.addr; vif.awprot <= 3'b000; vif.awvalid <= 1'b1;
            end
        end

        // address + data handshakes (may complete on the same cycle)
        while (!(aw_done && w_done)) begin
            @(posedge vif.clk);
            if (vif.awready) begin vif.awvalid <= 1'b0; aw_done = 1'b1; end
            if (vif.wready)  begin vif.wvalid  <= 1'b0; w_done  = 1'b1; end
        end

        // delayed BREADY (stresses BVALID hold); no-op when backpressure off
        if (bp_max != 0) begin
            repeat (bp_delay()) @(posedge vif.clk);
            vif.bready <= 1'b1;
        end

        // write response handshake
        while (!vif.bvalid) @(posedge vif.clk);
        req.resp = vif.bresp;
        @(posedge vif.clk);
        vif.bready <= 1'b0;
    endtask

    // ---- single read transaction ---------------------------------------
    task automatic drive_read(axil_item req);
        repeat (bp_delay()) @(posedge vif.clk);   // optional idle gap

        @(posedge vif.clk);
        vif.araddr  <= req.addr;
        vif.arprot  <= 3'b000;
        vif.arvalid <= 1'b1;
        vif.rready  <= (bp_max == 0);   // assert now if no backpressure

        // address handshake
        do @(posedge vif.clk); while (!vif.arready);
        vif.arvalid <= 1'b0;

        // delayed RREADY (stresses RVALID hold); no-op when backpressure off
        if (bp_max != 0) begin
            repeat (bp_delay()) @(posedge vif.clk);
            vif.rready <= 1'b1;
        end

        // read data handshake
        while (!vif.rvalid) @(posedge vif.clk);
        req.data = vif.rdata;
        req.resp = vif.rresp;
        @(posedge vif.clk);
        vif.rready <= 1'b0;
    endtask
endclass
