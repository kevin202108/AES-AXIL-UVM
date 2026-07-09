// =============================================================================
//  axil_agent.svh  -  driver + monitor + sequencer
// =============================================================================
class axil_agent extends uvm_agent;
    `uvm_component_utils(axil_agent)

    axil_driver    drv;
    axil_monitor   mon;
    axil_sequencer seqr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = axil_monitor::type_id::create("mon", this);
        if (get_is_active() == UVM_ACTIVE) begin
            drv  = axil_driver   ::type_id::create("drv",  this);
            seqr = axil_sequencer::type_id::create("seqr", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (get_is_active() == UVM_ACTIVE)
            drv.seq_item_port.connect(seqr.seq_item_export);
    endfunction
endclass
