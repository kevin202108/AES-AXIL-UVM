// =============================================================================
//  axil_tests.svh  -  base / smoke / AES tests
// =============================================================================

// ---- base test -------------------------------------------------------------
class axil_base_test extends uvm_test;
    `uvm_component_utils(axil_base_test)

    axil_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axil_env::type_id::create("env", this);
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        uvm_top.print_topology();
    endfunction
endclass

// ---- smoke test ------------------------------------------------------------
class axil_smoke_test extends axil_base_test;
    `uvm_component_utils(axil_smoke_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axil_smoke_seq seq = axil_smoke_seq::type_id::create("seq");
        phase.raise_objection(this, "smoke start");
        seq.start(env.agent.seqr);
        phase.drop_objection(this, "smoke done");
    endtask
endclass

// ---- AES test --------------------------------------------------------------
class axil_aes_test extends axil_base_test;
    `uvm_component_utils(axil_aes_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axil_aes_seq seq = axil_aes_seq::type_id::create("seq");
        phase.raise_objection(this, "aes start");
        seq.start(env.agent.seqr);
        phase.drop_objection(this, "aes done");
    endtask
endclass

// ---- random regression test ------------------------------------------------
class axil_rand_test extends axil_base_test;
    `uvm_component_utils(axil_rand_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axil_rand_seq seq = axil_rand_seq::type_id::create("seq");
        phase.raise_objection(this, "rand start");
        seq.start(env.agent.seqr);
        phase.drop_objection(this, "rand done");
    endtask
endclass

// ---- WSTRB protocol test ---------------------------------------------------
class axil_wstrb_test extends axil_base_test;
    `uvm_component_utils(axil_wstrb_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axil_wstrb_seq seq = axil_wstrb_seq::type_id::create("seq");
        phase.raise_objection(this, "wstrb start");
        seq.start(env.agent.seqr);
        phase.drop_objection(this, "wstrb done");
    endtask
endclass

// ---- coverage-closure test -------------------------------------------------
class axil_full_test extends axil_base_test;
    `uvm_component_utils(axil_full_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axil_full_seq seq = axil_full_seq::type_id::create("seq");
        phase.raise_objection(this, "full start");
        seq.start(env.agent.seqr);
        phase.drop_objection(this, "full done");
    endtask
endclass

// ---- backpressure test -----------------------------------------------------
//  Enables driver backpressure (random idle + delayed READY) and runs the
//  full sequence. Exercises the BVALID/RVALID-hold protocol assertions.
class axil_bp_test extends axil_base_test;
    `uvm_component_utils(axil_bp_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        // turn on driver backpressure (max 4-cycle random delays)
        uvm_config_db#(int unsigned)::set(this, "env.agent.drv", "bp_max", 4);
        super.build_phase(phase);  // builds env -> driver reads bp_max
    endfunction

    task run_phase(uvm_phase phase);
        axil_full_seq seq = axil_full_seq::type_id::create("seq");
        phase.raise_objection(this, "bp start");
        seq.start(env.agent.seqr);
        phase.drop_objection(this, "bp done");
    endtask
endclass

// ---- back-to-back test -----------------------------------------------------
class axil_b2b_test extends axil_base_test;
    `uvm_component_utils(axil_b2b_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        axil_b2b_seq seq = axil_b2b_seq::type_id::create("seq");
        phase.raise_objection(this, "b2b start");
        seq.start(env.agent.seqr);
        phase.drop_objection(this, "b2b done");
    endtask
endclass

// ---- reset-in-the-middle test ----------------------------------------------
//  Launch an encryption, let it run partway (driver idle), pulse ARESETN via a
//  global uvm_event the top module listens on, then confirm clean recovery.
class axil_reset_test extends axil_base_test;
    `uvm_component_utils(axil_reset_test)

    virtual axil_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axil_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "reset_test: virtual interface 'vif' not set")
    endfunction

    task run_phase(uvm_phase phase);
        uvm_event              rst_ev = uvm_event_pool::get_global("reset_req");
        axil_kickoff_seq       ko  = axil_kickoff_seq::type_id::create("ko");
        axil_reset_recover_seq rec = axil_reset_recover_seq::type_id::create("rec");

        phase.raise_objection(this, "reset test");

        // 1) launch an encryption (no poll) -> FSM left running
        ko.start(env.agent.seqr);

        // 2) let it run partway; driver is now idle, so reset is safe
        repeat (40) @(posedge vif.clk);
        `uvm_info("RST", "asserting ARESETN mid-encryption", UVM_NONE)
        rst_ev.trigger();
        repeat (12) @(posedge vif.clk);   // reset pulse (4) + settle

        // 3) confirm idle + a fresh encryption is correct
        rec.start(env.agent.seqr);

        phase.drop_objection(this, "reset test");
    endtask
endclass

// ---- error-response test ---------------------------------------------------
class axil_err_test extends axil_base_test;
    `uvm_component_utils(axil_err_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        axil_err_seq seq = axil_err_seq::type_id::create("seq");
        phase.raise_objection(this, "err");
        seq.start(env.agent.seqr);
        phase.drop_objection(this, "err");
    endtask
endclass

// ---- WSTRB full-sweep test -------------------------------------------------
class axil_wstrb_sweep_test extends axil_base_test;
    `uvm_component_utils(axil_wstrb_sweep_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        axil_wstrb_sweep_seq seq = axil_wstrb_sweep_seq::type_id::create("seq");
        phase.raise_objection(this, "wstrb sweep");
        seq.start(env.agent.seqr);
        phase.drop_objection(this, "wstrb sweep");
    endtask
endclass

// ---- start-while-busy test -------------------------------------------------
class axil_busy_test extends axil_base_test;
    `uvm_component_utils(axil_busy_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        axil_busy_seq seq = axil_busy_seq::type_id::create("seq");
        phase.raise_objection(this, "busy");
        seq.start(env.agent.seqr);
        phase.drop_objection(this, "busy");
    endtask
endclass

// ---- reset-offset sweep test -----------------------------------------------
//  Pulse ARESETN at many points relative to an in-flight encryption and verify
//  clean recovery each time (reset is asserted while the driver is idle).
class axil_reset_sweep_test extends axil_base_test;
    `uvm_component_utils(axil_reset_sweep_test)
    virtual axil_if vif;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axil_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "reset_sweep: vif not set")
    endfunction
    task run_phase(uvm_phase phase);
        uvm_event rst_ev = uvm_event_pool::get_global("reset_req");
        int offs[] = '{5, 16, 30, 60, 100, 150};
        phase.raise_objection(this, "reset sweep");
        foreach (offs[i]) begin
            axil_kickoff_seq       ko  = axil_kickoff_seq::type_id::create("ko");
            axil_reset_recover_seq rec = axil_reset_recover_seq::type_id::create("rec");
            ko.start(env.agent.seqr);                 // launch encryption
            repeat (offs[i]) @(posedge vif.clk);      // reset at offset
            `uvm_info("RST", $sformatf("reset at offset %0d", offs[i]), UVM_MEDIUM)
            rst_ev.trigger();
            repeat (12) @(posedge vif.clk);
            rec.start(env.agent.seqr);                // verify recovery
        end
        `uvm_info("RST", "*** RESET SWEEP DONE ***", UVM_NONE)
        phase.drop_objection(this, "reset sweep");
    endtask
endclass

// ---- reset-during-handshake test -------------------------------------------
//  Trigger ARESETN while the driver is mid AXI transaction; the reset-aware
//  driver must recover and a fresh encryption must still be correct.
class axil_reset_hs_test extends axil_base_test;
    `uvm_component_utils(axil_reset_hs_test)
    virtual axil_if vif;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axil_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "reset_hs: vif not set")
    endfunction
    task run_phase(uvm_phase phase);
        uvm_event              rst_ev = uvm_event_pool::get_global("reset_req");
        axil_rand_seq          rs  = axil_rand_seq::type_id::create("rs");
        axil_reset_recover_seq rec = axil_reset_recover_seq::type_id::create("rec");
        rs.num_blocks = 3;
        phase.raise_objection(this, "reset hs");
        fork
            rs.start(env.agent.seqr);                 // continuous AXI activity
        join_none
        repeat (3) @(posedge vif.clk);                // driver now mid-transaction
        `uvm_info("RST", "reset during AXI handshake", UVM_NONE)
        rst_ev.trigger();
        repeat (4) @(posedge vif.clk);
        rs.kill();                                    // clean stop (no SEQREQZMB)
        repeat (12) @(posedge vif.clk);
        @(posedge vif.clk);
        rec.start(env.agent.seqr);                    // verify recovery
        phase.drop_objection(this, "reset hs");
    endtask
endclass

// ---- NIST KAT test ---------------------------------------------------------
class axil_kat_test extends axil_base_test;
    `uvm_component_utils(axil_kat_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        axil_kat_seq seq = axil_kat_seq::type_id::create("seq");
        phase.raise_objection(this, "kat");
        seq.start(env.agent.seqr);
        phase.drop_objection(this, "kat");
    endtask
endclass

// ---- X-injection test ------------------------------------------------------
class axil_xinj_test extends axil_base_test;
    `uvm_component_utils(axil_xinj_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    task run_phase(uvm_phase phase);
        axil_xinj_seq seq = axil_xinj_seq::type_id::create("seq");
        phase.raise_objection(this, "xinj");
        seq.start(env.agent.seqr);
        phase.drop_objection(this, "xinj");
    endtask
endclass

// ---- exhaustive reset sweep ------------------------------------------------
//  Pulse ARESETN at EVERY cycle through the FSM-relevant windows (FEED + the
//  transitions, and the CAP/DONE window) and verify clean recovery each time.
class axil_reset_exhaustive_test extends axil_base_test;
    `uvm_component_utils(axil_reset_exhaustive_test)
    virtual axil_if vif;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axil_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "reset_exhaustive: vif not set")
    endfunction

    // light per-point check: reset mid-encryption, confirm STATUS returns idle
    task automatic one_reset(int off);
        uvm_event             rst_ev = uvm_event_pool::get_global("reset_req");
        axil_kickoff_seq      ko  = axil_kickoff_seq::type_id::create("ko");
        axil_status_idle_seq  chk = axil_status_idle_seq::type_id::create("chk");
        ko.start(env.agent.seqr);
        repeat (off) @(posedge vif.clk);
        rst_ev.trigger();
        repeat (12) @(posedge vif.clk);
        chk.start(env.agent.seqr);     // STATUS must be idle (0)
    endtask

    task run_phase(uvm_phase phase);
        axil_reset_recover_seq rec = axil_reset_recover_seq::type_id::create("rec");
        phase.raise_objection(this, "reset exhaustive");
        // every cycle through FEED + FEED->WAIT (0..24)
        for (int off = 0; off <= 24; off++) one_reset(off);
        // every cycle through the WAIT->CAP->DONE window (200..230)
        for (int off = 200; off <= 230; off++) one_reset(off);
        // final full encryption to prove the DUT still works after 56 resets
        rec.start(env.agent.seqr);
        `uvm_info("RST", "*** EXHAUSTIVE RESET SWEEP DONE (56 points + recovery) ***", UVM_NONE)
        phase.drop_objection(this, "reset exhaustive");
    endtask
endclass

// ---- staggered AW/W test ---------------------------------------------------
//  Drives AWVALID and WVALID at different times (random order + gap) so each
//  channel's handshake condition is exercised with the other VALID still low.
//  Lifts condition coverage of the AXI write-handshake expressions.
class axil_stagger_test extends axil_base_test;
    `uvm_component_utils(axil_stagger_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        uvm_config_db#(int unsigned)::set(this, "env.agent.drv", "stagger", 3);
        super.build_phase(phase);  // driver reads stagger in its build
    endfunction
    task run_phase(uvm_phase phase);
        axil_full_seq seq = axil_full_seq::type_id::create("seq");
        phase.raise_objection(this, "stagger");
        seq.start(env.agent.seqr);
        phase.drop_objection(this, "stagger");
    endtask
endclass
