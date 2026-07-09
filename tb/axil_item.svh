// =============================================================================
//  axil_item.svh  -  AXI4-Lite transaction + sequencer typedef
// =============================================================================
class axil_item extends uvm_sequence_item;
    rand bit          is_write;
    rand bit   [7:0]  addr;
    rand logic [31:0] data;   // 4-state so X-injection tests can carry X bytes
    rand bit   [3:0]  strb;
         bit   [1:0]  resp;   // captured BRESP / RRESP

    constraint c_align { addr[1:0] == 2'b00; }     // word aligned
    constraint c_strb  { soft strb == 4'hF;   }     // full word by default

    `uvm_object_utils_begin(axil_item)
        `uvm_field_int(is_write, UVM_ALL_ON)
        `uvm_field_int(addr,     UVM_ALL_ON)
        `uvm_field_int(data,     UVM_ALL_ON)
        `uvm_field_int(strb,     UVM_ALL_ON)
        `uvm_field_int(resp,     UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axil_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("%s addr=0x%02h data=0x%08h strb=0x%01h resp=%0d",
                         is_write ? "WR" : "RD", addr, data, strb, resp);
    endfunction
endclass

typedef uvm_sequencer #(axil_item) axil_sequencer;
