// =============================================================================
//  axil_scoreboard.svh  -  reference register model + read-back checker
//  Checks RW registers (idx 0..8) against a mirror model. STATUS (9) and
//  CIPHERTEXT (12..15) are dynamic -> observed only (checked by the AES test).
// =============================================================================
class axil_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(axil_scoreboard)

    uvm_analysis_imp #(axil_item, axil_scoreboard) ap_imp;

    // reference model, indexed by register word index (addr >> 2)
    bit [31:0] model [int];

    int unsigned n_writes;
    int unsigned n_reads;   // checked reads (RW registers only)
    int unsigned n_pass;
    int unsigned n_fail;
    int unsigned n_obs;     // observed reads of dynamic regs (STATUS/CT)

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap_imp = new("ap_imp", this);
    endfunction

    // writable register indices : KEY0..3 (0-3), PT0..3 (4-7), CTRL (8)
    function bit is_writable(int idx);
        return (idx >= 0 && idx <= 8);
    endfunction

    // expected read value per register index
    function bit [31:0] predict_read(int idx);
        if (idx >= 0 && idx <= 8)
            return model.exists(idx) ? model[idx] : 32'h0;
        else if (idx == 9)
            return 32'h0;            // STATUS : idle in MVP
        else
            return 32'h0;            // unmapped
    endfunction

    function bit [31:0] apply_strb(bit [31:0] cur, bit [31:0] nw, bit [3:0] s);
        bit [31:0] r = cur;
        for (int b = 0; b < 4; b++)
            if (s[b]) r[b*8 +: 8] = nw[b*8 +: 8];
        return r;
    endfunction

    function void write(axil_item t);
        int idx = t.addr >> 2;
        if (t.is_write) begin
            n_writes++;
            if (is_writable(idx))
                model[idx] = apply_strb(model.exists(idx) ? model[idx] : 32'h0,
                                        t.data, t.strb);
            `uvm_info("SB", $sformatf("observed %s", t.convert2string()), UVM_HIGH)
        end else if (idx >= 0 && idx <= 8) begin
            // RW register : check against mirror model
            bit [31:0] exp = predict_read(idx);
            n_reads++;
            if (t.data === exp) begin
                n_pass++;
                `uvm_info("SB", $sformatf("READ  PASS idx=%0d addr=0x%02h got=0x%08h",
                                          idx, t.addr, t.data), UVM_MEDIUM)
            end else begin
                n_fail++;
                `uvm_error("SB", $sformatf("READ  FAIL idx=%0d addr=0x%02h got=0x%08h exp=0x%08h",
                                           idx, t.addr, t.data, exp))
            end
        end else begin
            // STATUS / CIPHERTEXT : dynamic, not modelled here (checked by AES test)
            n_obs++;
            `uvm_info("SB", $sformatf("READ  OBS  idx=%0d addr=0x%02h got=0x%08h (dynamic reg)",
                                      idx, t.addr, t.data), UVM_HIGH)
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SB", $sformatf(
            "SCOREBOARD SUMMARY : writes=%0d checked_reads=%0d pass=%0d fail=%0d observed=%0d",
            n_writes, n_reads, n_pass, n_fail, n_obs), UVM_NONE)
        if (n_fail == 0)
            `uvm_info("SB", "*** SCOREBOARD: NO REGISTER MISMATCHES ***", UVM_NONE)
        else
            `uvm_error("SB", "*** SCOREBOARD: REGISTER MISMATCH ***")
    endfunction
endclass
