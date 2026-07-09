// =============================================================================
//  axil_monitor.svh  -  passive AXI4-Lite bus observer
// =============================================================================
class axil_monitor extends uvm_monitor;
    `uvm_component_utils(axil_monitor)

    virtual axil_if vif;
    uvm_analysis_port #(axil_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axil_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "axil_monitor: virtual interface 'vif' not set")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            mon_write();
            mon_read();
        join
    endtask

    task automatic mon_write();
        bit [7:0]  waddr;
        bit [31:0] wdata;
        bit [3:0]  wstrb;
        forever begin
            @(posedge vif.clk);
            if (vif.rst_n !== 1'b1) continue;
            if (vif.awvalid && vif.awready) waddr = vif.awaddr;
            if (vif.wvalid  && vif.wready)  begin wdata = vif.wdata; wstrb = vif.wstrb; end
            if (vif.bvalid  && vif.bready)  begin
                axil_item it = axil_item::type_id::create("mon_wr");
                it.is_write = 1'b1;
                it.addr     = waddr;
                it.data     = wdata;
                it.strb     = wstrb;
                it.resp     = vif.bresp;
                ap.write(it);
            end
        end
    endtask

    task automatic mon_read();
        bit [7:0] raddr;
        forever begin
            @(posedge vif.clk);
            if (vif.rst_n !== 1'b1) continue;
            if (vif.arvalid && vif.arready) raddr = vif.araddr;
            if (vif.rvalid  && vif.rready)  begin
                axil_item it = axil_item::type_id::create("mon_rd");
                it.is_write = 1'b0;
                it.addr     = raddr;
                it.data     = vif.rdata;
                it.strb     = 4'hF;
                it.resp     = vif.rresp;
                ap.write(it);
            end
        end
    endtask
endclass
