// =============================================================================
//  axil_sequences.svh  -  base / smoke / AES sequences
// =============================================================================

// ---- base sequence: read/write/poll helpers --------------------------------
class axil_base_seq extends uvm_sequence #(axil_item);
    `uvm_object_utils(axil_base_seq)

    logic [31:0] last_read;   // 4-state: result of the most recent do_read()
    bit   [1:0]  last_resp;   // BRESP/RRESP of the most recent access

    function new(string name = "axil_base_seq");
        super.new(name);
    endfunction

    task automatic do_write(bit [7:0] a, bit [31:0] d, bit [3:0] s = 4'hF);
        axil_item req = axil_item::type_id::create("req");
        start_item(req);
        if (!req.randomize() with { is_write == 1; addr == a; data == d; strb == s; })
            `uvm_fatal("RNDW", "write randomize failed")
        finish_item(req);
        last_resp = req.resp;
    endtask

    // write with X on the non-strobed bytes (strobed bytes carry d)
    task automatic do_write_x(bit [7:0] a, bit [31:0] d, bit [3:0] s);
        axil_item req = axil_item::type_id::create("req");
        start_item(req);
        req.is_write = 1'b1;
        req.addr     = a;
        req.strb     = s;
        for (int b = 0; b < 4; b++)
            req.data[b*8 +: 8] = s[b] ? d[b*8 +: 8] : 8'hxx;
        finish_item(req);
        last_resp = req.resp;
    endtask

    task automatic do_read(bit [7:0] a);
        axil_item req = axil_item::type_id::create("req");
        start_item(req);
        if (!req.randomize() with { is_write == 0; addr == a; strb == 4'hF; })
            `uvm_fatal("RNDR", "read randomize failed")
        finish_item(req);
        last_read = req.data;   // driver writes the read data back into req
        last_resp = req.resp;
    endtask

    // poll STATUS (0x24) until done(bit0)=1, with a safety bound
    task automatic poll_done(int max_polls = 2000);
        int n = 0;
        do begin
            do_read(8'h24);
            n++;
            if (n >= max_polls)
                `uvm_fatal("POLL", "STATUS.done never asserted")
        end while (last_read[0] !== 1'b1);
        `uvm_info("SEQ", $sformatf("done asserted after %0d polls (STATUS=0x%08h)",
                                   n, last_read), UVM_MEDIUM)
    endtask
endclass

// ---- smoke sequence: write each RW register, then read all back ------------
class axil_smoke_seq extends axil_base_seq;
    `uvm_object_utils(axil_smoke_seq)

    function new(string name = "axil_smoke_seq");
        super.new(name);
    endfunction

    task body();
        // KEY0..KEY3, PT0..PT3, CTRL  ->  offsets 0x00 .. 0x20
        bit [7:0] addrs [9];
        foreach (addrs[i]) addrs[i] = i * 4;

        // 1) write a unique pattern to every RW register
        foreach (addrs[i])
            do_write(addrs[i], 32'hA5A5_0000 | (i << 8) | i);

        // 2) read them all back (scoreboard checks against model)
        foreach (addrs[i])
            do_read(addrs[i]);
    endtask
endclass

// ---- AES encryption sequence: program, start, poll, read & check -----------
//  Uses the FIPS-197 known-answer vector.
class axil_aes_seq extends axil_base_seq;
    `uvm_object_utils(axil_aes_seq)

    // FIPS-197 Appendix B / C.1 vector
    //   plaintext = 00112233445566778899aabbccddeeff
    //   key       = 000102030405060708090a0b0c0d0e0f
    //   cipher    = 69c4e0d86a7b0430d8cdb78070b4c55a
    bit [31:0] exp_ct3 = 32'h69c4e0d8;
    bit [31:0] exp_ct2 = 32'h6a7b0430;
    bit [31:0] exp_ct1 = 32'hd8cdb780;
    bit [31:0] exp_ct0 = 32'h70b4c55a;

    function new(string name = "axil_aes_seq");
        super.new(name);
    endfunction

    task body();
        bit [31:0] ct0, ct1, ct2, ct3;
        bit        ok;

        // 1) program plaintext (PT3 = MSW) and key (KEY3 = MSW)
        do_write(8'h1C, 32'h00112233);  // PT3
        do_write(8'h18, 32'h44556677);  // PT2
        do_write(8'h14, 32'h8899aabb);  // PT1
        do_write(8'h10, 32'hccddeeff);  // PT0
        do_write(8'h0C, 32'h00010203);  // KEY3
        do_write(8'h08, 32'h04050607);  // KEY2
        do_write(8'h04, 32'h08090a0b);  // KEY1
        do_write(8'h00, 32'h0c0d0e0f);  // KEY0

        // 2) launch one encryption
        do_write(8'h20, 32'h0000_0001); // CTRL.start

        // 3) wait for completion
        poll_done();

        // 4) read ciphertext
        do_read(8'h3C); ct3 = last_read;
        do_read(8'h38); ct2 = last_read;
        do_read(8'h34); ct1 = last_read;
        do_read(8'h30); ct0 = last_read;

        // 5) compare against the known answer
        `uvm_info("AES", $sformatf("ciphertext got = %08h%08h%08h%08h",
                                   ct3, ct2, ct1, ct0), UVM_NONE)
        `uvm_info("AES", $sformatf("ciphertext exp = %08h%08h%08h%08h",
                                   exp_ct3, exp_ct2, exp_ct1, exp_ct0), UVM_NONE)
        ok = (ct3 === exp_ct3) && (ct2 === exp_ct2) &&
             (ct1 === exp_ct1) && (ct0 === exp_ct0);
        if (ok)
            `uvm_info ("AES", "*** AES ENCRYPT TEST PASSED (FIPS-197) ***", UVM_NONE)
        else
            `uvm_error("AES", "*** AES ENCRYPT TEST FAILED ***")
    endtask
endclass

// ---- random regression: N blocks, dual golden (SV + C via DPI-C) ------------
//  Per block: SV aes_ref_model and C dpi_encrypt128 must agree; DUT vs C.
//  Requires c_model/aes128.c linked (same as axil_dpi_test).
class axil_rand_seq extends axil_base_seq;
    `uvm_object_utils(axil_rand_seq)

    int num_blocks = 100;   // override with +NUM_BLOCKS=<n>

    function new(string name = "axil_rand_seq");
        super.new(name);
    endfunction

    // one encryption: program key/pt, start, poll, read ciphertext
    task automatic run_block(bit [127:0] key, bit [127:0] pt, output bit [127:0] got);
        do_write(8'h0C, key[127:96]);  // KEY3 (MSW)
        do_write(8'h08, key[95:64]);   // KEY2
        do_write(8'h04, key[63:32]);   // KEY1
        do_write(8'h00, key[31:0]);    // KEY0
        do_write(8'h1C, pt[127:96]);   // PT3 (MSW)
        do_write(8'h18, pt[95:64]);    // PT2
        do_write(8'h14, pt[63:32]);    // PT1
        do_write(8'h10, pt[31:0]);     // PT0
        do_write(8'h20, 32'h0000_0001);// CTRL.start
        poll_done();
        do_read(8'h3C); got[127:96] = last_read;  // CT3
        do_read(8'h38); got[95:64]  = last_read;  // CT2
        do_read(8'h34); got[63:32]  = last_read;  // CT1
        do_read(8'h30); got[31:0]   = last_read;  // CT0
    endtask

    task body();
        int pass = 0;
        int fail = 0;
        int dual_fail = 0;
        bit [127:0] key, pt, exp_sv, exp_c, got;

        void'($value$plusargs("NUM_BLOCKS=%d", num_blocks));
        `uvm_info("RAND", $sformatf("random dual-oracle regression: %0d blocks", num_blocks), UVM_NONE)

        for (int n = 0; n < num_blocks; n++) begin
            key = {$urandom, $urandom, $urandom, $urandom};
            pt  = {$urandom, $urandom, $urandom, $urandom};
            exp_sv = aes_ref_model::encrypt128(key, pt);
            exp_c  = dpi_encrypt128(key, pt);
            if (exp_c !== exp_sv) begin
                dual_fail++;
                fail++;
                `uvm_error("RAND", $sformatf(
                    "block %0d dual-golden MISMATCH\n  key=%032h\n  pt =%032h\n  C  =%032h\n  SV =%032h",
                    n, key, pt, exp_c, exp_sv))
                continue;  // do not run DUT if oracles disagree
            end
            run_block(key, pt, got);
            if (got === exp_c) begin
                pass++;
                `uvm_info("RAND", $sformatf("block %0d PASS ct=%032h", n, got), UVM_HIGH)
            end else begin
                fail++;
                `uvm_error("RAND", $sformatf(
                    "block %0d DUT MISMATCH\n  key=%032h\n  pt =%032h\n  got=%032h\n  exp=%032h",
                    n, key, pt, got, exp_c))
            end
        end

        `uvm_info("RAND", $sformatf(
            "RANDOM TEST: %0d blocks  pass=%0d  fail=%0d  dual_fail=%0d",
            num_blocks, pass, fail, dual_fail), UVM_NONE)
        if (fail == 0)
            `uvm_info ("RAND", "*** RANDOM TEST PASSED (dual oracle) ***", UVM_NONE)
        else
            `uvm_error("RAND", "*** RANDOM TEST FAILED ***")
    endtask
endclass

// ---- protocol: WSTRB partial-byte writes -----------------------------------
//  Exercises the DUT byte-enable logic. Each partial write is followed by a
//  read-back; the scoreboard's apply_strb model checks only strobed bytes
//  changed (no extra checker needed).
class axil_wstrb_seq extends axil_base_seq;
    `uvm_object_utils(axil_wstrb_seq)

    function new(string name = "axil_wstrb_seq");
        super.new(name);
    endfunction

    // preset a register, partial-overwrite it, then read back
    task automatic strb_case(bit [7:0] a, bit [31:0] preset,
                             bit [31:0] d, bit [3:0] s);
        do_write(a, preset, 4'hF);   // seed full word
        do_write(a, d, s);           // partial-byte overwrite
        do_read (a);                 // scoreboard verifies result
    endtask

    task body();
        strb_case(8'h00, 32'hFFFFFFFF, 32'h11223344, 4'b0001); // byte0 -> FFFFFF44
        strb_case(8'h04, 32'h00000000, 32'hAABBCCDD, 4'b1010); // byte1,3 -> AA00CC00
        strb_case(8'h08, 32'hFFFFFFFF, 32'h12345678, 4'b1100); // byte2,3 -> 1234FFFF
        strb_case(8'h0C, 32'h00000000, 32'hDEADBEEF, 4'b0110); // byte1,2 -> 00ADBE00
        // also confirm a zero-strobe write changes nothing
        strb_case(8'h10, 32'hCAFEBABE, 32'hFFFFFFFF, 4'b0000); // -> CAFEBABE
    endtask
endclass

// ---- coverage-closure sequence ---------------------------------------------
//  One run that exercises every reachable coverage bin: write+readback all RW
//  registers (full strobe), partial/zero strobes, and one golden-checked
//  encryption (covers STATUS poll + CIPHERTEXT reads).
class axil_full_seq extends axil_base_seq;
    `uvm_object_utils(axil_full_seq)

    function new(string name = "axil_full_seq");
        super.new(name);
    endfunction

    task body();
        bit [127:0] key, pt, exp, got;

        // (1) write then read back every RW register (full strobe)
        for (int i = 0; i <= 8; i++)
            do_write(i*4, 32'hA5A5_0000 | (i << 8) | i, 4'hF);
        for (int i = 0; i <= 8; i++)
            do_read(i*4);

        // (2) partial-byte and zero-strobe writes (strb coverage)
        do_write(8'h00, 32'h11223344, 4'b0001); do_read(8'h00);
        do_write(8'h04, 32'hAABBCCDD, 4'b1010); do_read(8'h04);
        do_write(8'h08, 32'hDEADBEEF, 4'b0000); do_read(8'h08);

        // (3) one encryption -> STATUS poll + CIPHERTEXT reads, golden-checked
        key = 128'h000102030405060708090a0b0c0d0e0f;
        pt  = 128'h00112233445566778899aabbccddeeff;
        exp = aes_ref_model::encrypt128(key, pt);
        do_write(8'h0C, key[127:96]); do_write(8'h08, key[95:64]);
        do_write(8'h04, key[63:32]);  do_write(8'h00, key[31:0]);
        do_write(8'h1C, pt[127:96]);  do_write(8'h18, pt[95:64]);
        do_write(8'h14, pt[63:32]);   do_write(8'h10, pt[31:0]);
        do_write(8'h20, 32'h0000_0001);
        poll_done();
        do_read(8'h3C); got[127:96] = last_read;
        do_read(8'h38); got[95:64]  = last_read;
        do_read(8'h34); got[63:32]  = last_read;
        do_read(8'h30); got[31:0]   = last_read;

        // (4) one unmapped read -> SLVERR (covers cp_resp.slverr bin)
        do_read(8'h28);
        if (last_resp !== 2'b10)
            `uvm_error("FULL", $sformatf("unmapped read should be SLVERR, got resp=%0d", last_resp))

        if (got === exp)
            `uvm_info ("FULL", "encryption check PASSED", UVM_NONE)
        else
            `uvm_error("FULL", $sformatf("encryption MISMATCH got=%032h exp=%032h", got, exp))
    endtask
endclass

// ---- back-to-back: key written once, N consecutive blocks (plaintext only) -
//  Tests that the KEY register persists across encryptions and that the FSM
//  cleanly re-arms for tightly consecutive blocks.
class axil_b2b_seq extends axil_base_seq;
    `uvm_object_utils(axil_b2b_seq)

    int num_blocks = 8;

    function new(string name = "axil_b2b_seq");
        super.new(name);
    endfunction

    task body();
        bit [127:0] key = 128'h000102030405060708090a0b0c0d0e0f;
        bit [127:0] pt, exp, got;
        int pass = 0, fail = 0;

        // program key ONCE
        do_write(8'h0C, key[127:96]); do_write(8'h08, key[95:64]);
        do_write(8'h04, key[63:32]);  do_write(8'h00, key[31:0]);

        for (int n = 0; n < num_blocks; n++) begin
            pt  = {$urandom, $urandom, $urandom, $urandom};
            exp = aes_ref_model::encrypt128(key, pt);
            // only plaintext changes between blocks
            do_write(8'h1C, pt[127:96]); do_write(8'h18, pt[95:64]);
            do_write(8'h14, pt[63:32]);  do_write(8'h10, pt[31:0]);
            do_write(8'h20, 32'h0000_0001);   // start
            poll_done();
            do_read(8'h3C); got[127:96] = last_read;
            do_read(8'h38); got[95:64]  = last_read;
            do_read(8'h34); got[63:32]  = last_read;
            do_read(8'h30); got[31:0]   = last_read;
            if (got === exp) pass++;
            else begin
                fail++;
                `uvm_error("B2B", $sformatf("block %0d MISMATCH got=%032h exp=%032h", n, got, exp))
            end
        end
        `uvm_info("B2B", $sformatf("BACK-TO-BACK: %0d blocks (key reused) pass=%0d fail=%0d",
                                   num_blocks, pass, fail), UVM_NONE)
        if (fail == 0)
            `uvm_info ("B2B", "*** BACK-TO-BACK TEST PASSED ***", UVM_NONE)
        else
            `uvm_error("B2B", "*** BACK-TO-BACK TEST FAILED ***")
    endtask
endclass

// ---- kickoff: program key/pt + start, return WITHOUT polling -----------------
//  Used by the reset-in-the-middle test to leave an encryption in flight.
class axil_kickoff_seq extends axil_base_seq;
    `uvm_object_utils(axil_kickoff_seq)

    function new(string name = "axil_kickoff_seq");
        super.new(name);
    endfunction

    task body();
        bit [127:0] key = 128'h000102030405060708090a0b0c0d0e0f;
        bit [127:0] pt  = 128'h00112233445566778899aabbccddeeff;
        do_write(8'h0C, key[127:96]); do_write(8'h08, key[95:64]);
        do_write(8'h04, key[63:32]);  do_write(8'h00, key[31:0]);
        do_write(8'h1C, pt[127:96]);  do_write(8'h18, pt[95:64]);
        do_write(8'h14, pt[63:32]);   do_write(8'h10, pt[31:0]);
        do_write(8'h20, 32'h0000_0001);   // start, then return (no poll)
    endtask
endclass

// ---- reset recovery: confirm idle after reset, then a clean encryption ------
class axil_reset_recover_seq extends axil_aes_seq;
    `uvm_object_utils(axil_reset_recover_seq)

    function new(string name = "axil_reset_recover_seq");
        super.new(name);
    endfunction

    task body();
        // after a mid-encryption reset, STATUS must read idle (done=0, busy=0)
        do_read(8'h24);
        if (last_read !== 32'h0)
            `uvm_error("RST", $sformatf("STATUS not idle after reset: 0x%08h", last_read))
        else
            `uvm_info ("RST", "STATUS idle after reset (0x00000000)", UVM_NONE)
        // a fresh FIPS-197 encryption must still be correct
        super.body();
    endtask
endclass

// ---- protocol: error response (SLVERR) on unmapped / out-of-range ----------
class axil_err_seq extends axil_base_seq;
    `uvm_object_utils(axil_err_seq)

    int errs = 0;

    function new(string name = "axil_err_seq");
        super.new(name);
    endfunction

    task automatic expect_resp(string what, bit [1:0] got, bit [1:0] exp);
        if (got !== exp) begin
            errs++;
            `uvm_error("ERR", $sformatf("%s: resp=%0d expected %0d", what, got, exp))
        end else begin
            `uvm_info ("ERR", $sformatf("%s: resp=%0d (ok)", what, got), UVM_MEDIUM)
        end
    endtask

    task body();
        // unmapped index (0x28 = idx10, 0x2C = idx11) -> SLVERR
        do_read (8'h28);                 expect_resp("read  unmapped 0x28",  last_resp, 2'b10);
        do_write(8'h2C, 32'hdeadbeef);   expect_resp("write unmapped 0x2C",  last_resp, 2'b10);
        // out-of-range upper bits (0x40 aliases idx0 but addr[7:6]!=0) -> SLVERR
        do_read (8'h40);                 expect_resp("read  oor 0x40",       last_resp, 2'b10);
        // mapped RW access -> OKAY
        do_write(8'h00, 32'h12345678);   expect_resp("write mapped KEY0",    last_resp, 2'b00);
        do_read (8'h00);                 expect_resp("read  mapped KEY0",    last_resp, 2'b00);
        // write to read-only STATUS -> accepted+ignored, OKAY (not SLVERR)
        do_write(8'h24, 32'hffffffff);   expect_resp("write RO STATUS",      last_resp, 2'b00);

        if (errs == 0) `uvm_info ("ERR", "*** ERROR-RESPONSE TEST PASSED ***", UVM_NONE)
        else           `uvm_error("ERR", "*** ERROR-RESPONSE TEST FAILED ***")
    endtask
endclass

// ---- protocol: sweep all 16 WSTRB values -----------------------------------
class axil_wstrb_sweep_seq extends axil_base_seq;
    `uvm_object_utils(axil_wstrb_sweep_seq)

    function new(string name = "axil_wstrb_sweep_seq");
        super.new(name);
    endfunction

    task body();
        // for each strobe value, preset known, partial-write, read back
        // (scoreboard apply_strb model checks only strobed bytes changed)
        for (int s = 0; s < 16; s++) begin
            do_write(8'h00, 32'h00000000, 4'hF);     // known baseline
            do_write(8'h00, 32'hAABBCCDD, s[3:0]);   // strobe under test
            do_read (8'h00);
        end
        `uvm_info("WSTRB", "*** WSTRB SWEEP (16 values) DONE ***", UVM_NONE)
    endtask
endclass

// ---- spec: start written while busy must be IGNORED ------------------------
//  Documents/locks the intended behaviour: a CTRL.start during an in-flight
//  encryption does not disturb it; the original result is still correct.
class axil_busy_seq extends axil_base_seq;
    `uvm_object_utils(axil_busy_seq)

    function new(string name = "axil_busy_seq");
        super.new(name);
    endfunction

    task body();
        bit [127:0] key = 128'h000102030405060708090a0b0c0d0e0f;
        bit [127:0] pt  = 128'h00112233445566778899aabbccddeeff;
        bit [127:0] exp = aes_ref_model::encrypt128(key, pt);
        bit [127:0] got;

        do_write(8'h0C, key[127:96]); do_write(8'h08, key[95:64]);
        do_write(8'h04, key[63:32]);  do_write(8'h00, key[31:0]);
        do_write(8'h1C, pt[127:96]);  do_write(8'h18, pt[95:64]);
        do_write(8'h14, pt[63:32]);   do_write(8'h10, pt[31:0]);
        do_write(8'h20, 32'h0000_0001);     // start

        // hammer start again while the FSM is busy -> must be ignored
        do_read(8'h24);
        `uvm_info("BUSY", $sformatf("STATUS during run = 0x%08h (busy)", last_read), UVM_MEDIUM)
        do_write(8'h20, 32'h0000_0001);     // 2nd start while busy
        do_write(8'h20, 32'h0000_0001);     // 3rd start while busy

        poll_done();
        do_read(8'h3C); got[127:96] = last_read;
        do_read(8'h38); got[95:64]  = last_read;
        do_read(8'h34); got[63:32]  = last_read;
        do_read(8'h30); got[31:0]   = last_read;
        if (got === exp)
            `uvm_info ("BUSY", "*** START-WHILE-BUSY IGNORED, result correct (PASS) ***", UVM_NONE)
        else
            `uvm_error("BUSY", $sformatf("start-while-busy corrupted result got=%032h exp=%032h", got, exp))
    endtask
endclass

// ---- NIST AESAVS KAT (Known-Answer Test) -----------------------------------
//  Reads 259 vectors (VarTxt 128 + VarKey 128 + 3 corners) from .dat files.
//  Per vector (dual oracle + file known-answer, same order as axil_rand_seq):
//    1) SV aes_ref_model vs C dpi_encrypt128 must agree
//    2) live oracles must match kat_ct.dat
//    3) DUT ciphertext vs C expected (and thus vs file)
//  Requires c_model/aes128.c linked (same as axil_dpi_test / axil_rand_test).
//  Add files kat_key.dat / kat_pt.dat / kat_ct.dat (bare names) in EDA Playground.
class axil_kat_seq extends axil_rand_seq;
    `uvm_object_utils(axil_kat_seq)

    localparam int KAT_N = 259;

    bit [127:0] keys [KAT_N];
    bit [127:0] pts  [KAT_N];
    bit [127:0] cts  [KAT_N];

    function new(string name = "axil_kat_seq");
        super.new(name);
    endfunction

    task body();
        bit [127:0] got, exp_sv, exp_c;
        int pass = 0, fail = 0, dual_fail = 0, file_fail = 0;

        $readmemh("kat_key.dat", keys);
        $readmemh("kat_pt.dat",  pts);
        $readmemh("kat_ct.dat",  cts);
        `uvm_info("KAT", $sformatf(
            "running %0d NIST KAT vectors (dual oracle + file)", KAT_N), UVM_NONE)

        for (int i = 0; i < KAT_N; i++) begin
            exp_sv = aes_ref_model::encrypt128(keys[i], pts[i]);
            exp_c  = dpi_encrypt128(keys[i], pts[i]);

            // 1) dual golden: C vs SV
            if (exp_c !== exp_sv) begin
                dual_fail++;
                fail++;
                `uvm_error("KAT", $sformatf(
                    "vector %0d dual-golden MISMATCH\n  key=%032h\n  pt =%032h\n  C  =%032h\n  SV =%032h",
                    i, keys[i], pts[i], exp_c, exp_sv))
                continue;  // do not run DUT if oracles disagree
            end

            // 2) live oracles vs NIST file known-answer
            if (exp_c !== cts[i]) begin
                file_fail++;
                fail++;
                `uvm_error("KAT", $sformatf(
                    "vector %0d oracle vs kat_ct.dat MISMATCH\n  key=%032h\n  pt =%032h\n  C  =%032h\n  file=%032h",
                    i, keys[i], pts[i], exp_c, cts[i]))
                continue;
            end

            // 3) DUT vs C (implies vs file when steps 1–2 pass)
            run_block(keys[i], pts[i], got);
            if (got === exp_c) begin
                pass++;
                `uvm_info("KAT", $sformatf("vector %0d PASS ct=%032h", i, got), UVM_HIGH)
            end else begin
                fail++;
                `uvm_error("KAT", $sformatf(
                    "vector %0d DUT MISMATCH\n  key=%032h\n  pt =%032h\n  got=%032h\n  exp=%032h",
                    i, keys[i], pts[i], got, exp_c))
            end
        end

        `uvm_info("KAT", $sformatf(
            "NIST KAT: %0d vectors  pass=%0d  fail=%0d  dual_fail=%0d  file_fail=%0d",
            KAT_N, pass, fail, dual_fail, file_fail), UVM_NONE)
        if (fail == 0)
            `uvm_info ("KAT", "*** NIST KAT TEST PASSED (dual oracle) ***", UVM_NONE)
        else
            `uvm_error("KAT", "*** NIST KAT TEST FAILED ***")
    endtask
endclass

// ---- lightweight: confirm STATUS reads idle (used by exhaustive reset) -----
class axil_status_idle_seq extends axil_base_seq;
    `uvm_object_utils(axil_status_idle_seq)
    function new(string name = "axil_status_idle_seq");
        super.new(name);
    endfunction
    task body();
        do_read(8'h24);
        if (last_read !== 32'h0)
            `uvm_error("RST", $sformatf("STATUS not idle after reset: 0x%08h", last_read))
    endtask
endclass

// ---- X-injection: X on non-strobed bytes must not corrupt / leak -----------
class axil_xinj_seq extends axil_base_seq;
    `uvm_object_utils(axil_xinj_seq)

    function new(string name = "axil_xinj_seq");
        super.new(name);
    endfunction

    task automatic check_no_x(bit [7:0] a, bit [31:0] exp);
        do_read(a);
        if ($isunknown(last_read))
            `uvm_error("XINJ", $sformatf("X leaked into read 0x%02h: got=0x%08h", a, last_read))
        else if (last_read !== exp)
            `uvm_error("XINJ", $sformatf("addr 0x%02h got=0x%08h exp=0x%08h", a, last_read, exp))
        else
            `uvm_info ("XINJ", $sformatf("addr 0x%02h = 0x%08h (clean)", a, last_read), UVM_MEDIUM)
    endtask

    task body();
        // preset, then partial-write with X on non-strobed bytes
        do_write  (8'h00, 32'hA5A5A5A5, 4'hF);
        do_write_x(8'h00, 32'h000000DD, 4'b0001);  // byte0=DD, rest X -> A5A5A5DD
        check_no_x(8'h00, 32'hA5A5A5DD);

        do_write  (8'h04, 32'hFFFFFFFF, 4'hF);
        do_write_x(8'h04, 32'hAA00CC00, 4'b1010);  // byte1,3 -> AA,CC; rest X -> AAFFCCFF
        check_no_x(8'h04, 32'hAAFFCCFF);

        do_write  (8'h08, 32'h00000000, 4'hF);
        do_write_x(8'h08, 32'h12345678, 4'b0000);  // zero strobe, all X -> unchanged 0
        check_no_x(8'h08, 32'h00000000);

        `uvm_info("XINJ", "*** X-INJECTION TEST DONE ***", UVM_NONE)
    endtask
endclass

// ---- DPI-C minimum check: C model vs FIPS / SV golden / DUT ----------------
//  Step 1: aes128_selfcheck() in C (FIPS-197 + all-zero)
//  Step 2: DPI encrypt vs hard-coded FIPS ciphertext
//  Step 3: DPI encrypt vs aes_ref_model (dual golden)
//  Step 4: one DUT encryption vs C expected (end-to-end co-sim)
//  Requires c_model/aes128.c linked (EDA Playground: Design tab "aes128.c").
class axil_dpi_seq extends axil_rand_seq;
    `uvm_object_utils(axil_dpi_seq)

    function new(string name = "axil_dpi_seq");
        super.new(name);
    endfunction

    task body();
        bit [127:0] key = 128'h000102030405060708090a0b0c0d0e0f;
        bit [127:0] pt  = 128'h00112233445566778899aabbccddeeff;
        bit [127:0] exp_fips = 128'h69c4e0d86a7b0430d8cdb78070b4c55a;
        bit [127:0] exp_c, exp_sv, got_dut;
        int sc;

        // --- 1) C built-in self-check ---
        sc = aes128_selfcheck();
        if (sc == 0)
            `uvm_info("DPI", "aes128_selfcheck() PASS", UVM_NONE)
        else
            `uvm_error("DPI", $sformatf("aes128_selfcheck() FAIL code=%0d", sc))

        // --- 2) DPI vs FIPS-197 known answer ---
        exp_c = dpi_encrypt128(key, pt);
        `uvm_info("DPI", $sformatf("C model CT = %032h", exp_c), UVM_NONE)
        if (exp_c === exp_fips)
            `uvm_info("DPI", "DPI vs FIPS-197 PASS", UVM_NONE)
        else
            `uvm_error("DPI", $sformatf("DPI vs FIPS FAIL got=%032h exp=%032h",
                                        exp_c, exp_fips))

        // --- 3) dual golden: C vs SV ---
        exp_sv = aes_ref_model::encrypt128(key, pt);
        if (exp_c === exp_sv)
            `uvm_info("DPI", "dual golden (C vs SV) PASS", UVM_NONE)
        else
            `uvm_error("DPI", $sformatf("dual golden FAIL C=%032h SV=%032h",
                                        exp_c, exp_sv))

        // --- 4) DUT vs C model ---
        run_block(key, pt, got_dut);
        if (got_dut === exp_c)
            `uvm_info("DPI", "DUT vs C model PASS", UVM_NONE)
        else
            `uvm_error("DPI", $sformatf("DUT vs C FAIL got=%032h exp_c=%032h",
                                        got_dut, exp_c))

        if (sc == 0 && exp_c === exp_fips && exp_c === exp_sv && got_dut === exp_c)
            `uvm_info("DPI", "*** DPI-C MINIMUM TEST PASSED ***", UVM_NONE)
        else
            `uvm_error("DPI", "*** DPI-C MINIMUM TEST FAILED ***")
    endtask
endclass
