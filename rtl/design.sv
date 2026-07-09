// =============================================================================
//  aes_axi_lite  -  AXI4-Lite wrapper around the byte-serial AES-128 core
//                   (Phase 2)
// -----------------------------------------------------------------------------
//  Phase 2 wires the AES_Core behind the AXI4-Lite register file.
//
//  Completion detection:
//    The AES core exposes done and ciphertext_valid signals. The wrapper
//    monitors these signals to track the encryption phase and capture the
//    ciphertext bytes.
//      - S_FEED: stream 16 plaintext/key bytes to the core.
//      - S_WAIT: wait for the core to assert core_ct_valid.
//      - S_CAP : capture 16 ciphertext bytes as they are validated.
//
//  Requires aes_rtl.sv (AES_Core, AES_LFSR_Controler, AES_KeyExpand, AES_Sbox).
//
//  Register map (32-bit, byte addressable, ADDR_LSB = 2):
//    0x00 KEY0  RW  key[31:0]          0x10 PT0  RW  plaintext[31:0]
//    0x04 KEY1  RW  key[63:32]         0x14 PT1  RW  plaintext[63:32]
//    0x08 KEY2  RW  key[95:64]         0x18 PT2  RW  plaintext[95:64]
//    0x0C KEY3  RW  key[127:96]        0x1C PT3  RW  plaintext[127:96]
//    0x20 CTRL    RW  bit0 = start (write 1 to launch one encryption)
//    0x24 STATUS  RO  bit0 = done, bit1 = busy
//    0x30 CT0     RO  ciphertext[31:0]   0x38 CT2 RO ciphertext[95:64]
//    0x34 CT1     RO  ciphertext[63:32]  0x3C CT3 RO ciphertext[127:96]
//
//  Byte order: KEY3/PT3/CT3 are the MOST significant word.  The first byte
//  streamed in/out (index 0) is the MSB, i.e. KEY3[31:24] / CT3[31:24].
//  For the FIPS-197 vector  PT = 00112233445566778899aabbccddeeff :
//      PT3=0x00112233 PT2=0x44556677 PT1=0x8899aabb PT0=0xccddeeff
// =============================================================================
`timescale 1ns/1ps

// AES core RTL lives in a separate design file (added in EDA Playground).
// SystemVerilog added files are not auto-compiled, so pull it in by include.
`include "aes_rtl.sv"

module aes_axi_lite #(
    parameter integer ADDR_WIDTH = 8,
    parameter integer DATA_WIDTH = 32
)(
    input  wire                      ACLK,
    input  wire                      ARESETN,

    // ---- Write address channel ----
    input  wire [ADDR_WIDTH-1:0]     AWADDR,
    input  wire [2:0]                AWPROT,
    input  wire                      AWVALID,
    output wire                      AWREADY,

    // ---- Write data channel ----
    input  wire [DATA_WIDTH-1:0]     WDATA,
    input  wire [(DATA_WIDTH/8)-1:0] WSTRB,
    input  wire                      WVALID,
    output wire                      WREADY,

    // ---- Write response channel ----
    output wire [1:0]                BRESP,
    output wire                      BVALID,
    input  wire                      BREADY,

    // ---- Read address channel ----
    input  wire [ADDR_WIDTH-1:0]     ARADDR,
    input  wire [2:0]                ARPROT,
    input  wire                      ARVALID,
    output wire                      ARREADY,

    // ---- Read data channel ----
    output wire [DATA_WIDTH-1:0]     RDATA,
    output wire [1:0]                RRESP,
    output wire                      RVALID,
    input  wire                      RREADY
);

    localparam integer ADDR_LSB          = 2;
    localparam integer OPT_MEM_ADDR_BITS = 3;   // 4 index bits -> 16 words

    // ----------------------------------------------------------------
    //  AXI signal registers (classic AMBA AXI4-Lite slave template)
    // ----------------------------------------------------------------
    reg [ADDR_WIDTH-1:0] axi_awaddr;
    reg                  axi_awready;
    reg                  axi_wready;
    reg [1:0]            axi_bresp;
    reg                  axi_bvalid;
    reg [ADDR_WIDTH-1:0] axi_araddr;
    reg                  axi_arready;
    reg [DATA_WIDTH-1:0] axi_rdata;
    reg [1:0]            axi_rresp;
    reg                  axi_rvalid;
    reg                  aw_en;

    assign AWREADY = axi_awready;
    assign WREADY  = axi_wready;
    assign BRESP   = axi_bresp;
    assign BVALID  = axi_bvalid;
    assign ARREADY = axi_arready;
    assign RDATA   = axi_rdata;
    assign RRESP   = axi_rresp;
    assign RVALID  = axi_rvalid;

    // ----------------------------------------------------------------
    //  Architectural registers
    // ----------------------------------------------------------------
    reg [31:0] key_reg [0:3];   // 0x00..0x0C
    reg [31:0] pt_reg  [0:3];   // 0x10..0x1C
    reg [31:0] ctrl_reg;        // 0x20  (bit0 = start)
    reg [7:0]  ct_bytes [0:15]; // captured ciphertext, [0] = first byte out

    // STATUS (0x24) is driven by the FSM
    reg  done_flag;
    reg  busy_flag;
    wire [31:0] status_reg = {30'b0, busy_flag, done_flag};

    // assembled 128-bit ciphertext: ct_bytes[0] is the most significant byte
    wire [127:0] ct128 = { ct_bytes[0],  ct_bytes[1],  ct_bytes[2],  ct_bytes[3],
                           ct_bytes[4],  ct_bytes[5],  ct_bytes[6],  ct_bytes[7],
                           ct_bytes[8],  ct_bytes[9],  ct_bytes[10], ct_bytes[11],
                           ct_bytes[12], ct_bytes[13], ct_bytes[14], ct_bytes[15] };

    integer k;

    // ================================================================
    //  AXI4-Lite write channel
    // ================================================================
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            axi_awready <= 1'b0;
            aw_en       <= 1'b1;
        end else begin
            if (~axi_awready && AWVALID && WVALID && aw_en) begin
                axi_awready <= 1'b1;
                aw_en       <= 1'b0;
            end else if (BREADY && axi_bvalid) begin
                aw_en       <= 1'b1;
                axi_awready <= 1'b0;
            end else begin
                axi_awready <= 1'b0;
            end
        end
    end

    always @(posedge ACLK) begin
        if (!ARESETN) begin
            axi_awaddr <= {ADDR_WIDTH{1'b0}};
        end else if (~axi_awready && AWVALID && WVALID && aw_en) begin
            axi_awaddr <= AWADDR;
        end
    end

    always @(posedge ACLK) begin
        if (!ARESETN) begin
            axi_wready <= 1'b0;
        end else if (~axi_wready && WVALID && AWVALID && aw_en) begin
            axi_wready <= 1'b1;
        end else begin
            axi_wready <= 1'b0;
        end
    end

    wire        slv_reg_wren = axi_wready && WVALID && axi_awready && AWVALID;
    wire [OPT_MEM_ADDR_BITS:0] wr_index =
            axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB];

    // start pulse: AXI write of 1 to CTRL.bit0
    wire start_pulse = slv_reg_wren && (wr_index == 4'd8) && WSTRB[0] && WDATA[0];

    // address decode for error response: a write target is "mapped" only if the
    // upper address bits are 0 and the index hits a real register (0..9, 12..15).
    // Unmapped writes complete with SLVERR (2'b10); RO writes (STATUS/CT) are
    // accepted-and-ignored with OKAY.
    wire wr_mapped = (axi_awaddr[ADDR_WIDTH-1:ADDR_LSB+OPT_MEM_ADDR_BITS+1] == '0)
                   && ((wr_index <= 4'd9) || (wr_index >= 4'd12));

    // ----------------------------------------------------------------
    //  SIMULATION-ONLY fault injection (excluded from synthesis).
    //  +define+SIM_FAULT_INJECT  and  +FAULT=<n>:
    //    1 = read-mux aliases KEY1 -> KEY0   2 = KEY2 ignores writes
    // ----------------------------------------------------------------
`ifdef SIM_FAULT_INJECT
    integer    fault_arg;
    reg [31:0] fault_mode;
    initial begin
        fault_mode = 32'd0;
        if ($value$plusargs("FAULT=%d", fault_arg)) fault_mode = fault_arg;
        if (fault_mode != 0)
            $display("[DUT] *** SIM_FAULT_INJECT ACTIVE : FAULT=%0d ***", fault_mode);
    end
    wire wr_drop = (fault_mode == 32'd2) && (wr_index == 4'd2);
`else
    wire wr_drop = 1'b0;
`endif

    integer b;
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            for (k = 0; k < 4; k = k + 1) begin
                key_reg[k] <= 32'h0;
                pt_reg[k]  <= 32'h0;
            end
            ctrl_reg <= 32'h0;
        end else if (slv_reg_wren && !wr_drop) begin
            case (wr_index)
                4'd0, 4'd1, 4'd2, 4'd3:
                    for (b = 0; b < (DATA_WIDTH/8); b = b + 1)
                        if (WSTRB[b])
                            key_reg[wr_index[1:0]][b*8 +: 8] <= WDATA[b*8 +: 8];
                4'd4, 4'd5, 4'd6, 4'd7:
                    for (b = 0; b < (DATA_WIDTH/8); b = b + 1)
                        if (WSTRB[b])
                            pt_reg[wr_index[1:0]][b*8 +: 8] <= WDATA[b*8 +: 8];
                4'd8:
                    for (b = 0; b < (DATA_WIDTH/8); b = b + 1)
                        if (WSTRB[b])
                            ctrl_reg[b*8 +: 8] <= WDATA[b*8 +: 8];
                default: ; // RO / unmapped: ignore
            endcase
        end
    end

    always @(posedge ACLK) begin
        if (!ARESETN) begin
            axi_bvalid <= 1'b0;
            axi_bresp  <= 2'b00;
        end else begin
            if (axi_awready && AWVALID && ~axi_bvalid && axi_wready && WVALID) begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= wr_mapped ? 2'b00 : 2'b10;  // OKAY / SLVERR
            end else if (BREADY && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end
        end
    end

    // ================================================================
    //  AXI4-Lite read channel
    // ================================================================
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            axi_arready <= 1'b0;
            axi_araddr  <= {ADDR_WIDTH{1'b0}};
        end else begin
            if (~axi_arready && ARVALID) begin
                axi_arready <= 1'b1;
                axi_araddr  <= ARADDR;
            end else begin
                axi_arready <= 1'b0;
            end
        end
    end

    wire [OPT_MEM_ADDR_BITS:0] rd_index =
            axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB];

    // a read is "mapped" iff upper addr bits are 0 and index hits a real reg
    wire rd_mapped = (axi_araddr[ADDR_WIDTH-1:ADDR_LSB+OPT_MEM_ADDR_BITS+1] == '0)
                   && ((rd_index <= 4'd9) || (rd_index >= 4'd12));

    always @(posedge ACLK) begin
        if (!ARESETN) begin
            axi_rvalid <= 1'b0;
            axi_rresp  <= 2'b00;
        end else begin
            if (axi_arready && ARVALID && ~axi_rvalid) begin
                axi_rvalid <= 1'b1;
                axi_rresp  <= rd_mapped ? 2'b00 : 2'b10;  // OKAY / SLVERR
            end else if (axi_rvalid && RREADY) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    wire slv_reg_rden = axi_arready & ARVALID & ~axi_rvalid;

    reg [DATA_WIDTH-1:0] reg_data_out;
    always @(*) begin
        case (rd_index)
            4'd0:    reg_data_out = key_reg[0];
            4'd1:    reg_data_out = key_reg[1];
            4'd2:    reg_data_out = key_reg[2];
            4'd3:    reg_data_out = key_reg[3];
            4'd4:    reg_data_out = pt_reg[0];
            4'd5:    reg_data_out = pt_reg[1];
            4'd6:    reg_data_out = pt_reg[2];
            4'd7:    reg_data_out = pt_reg[3];
            4'd8:    reg_data_out = ctrl_reg;
            4'd9:    reg_data_out = status_reg;
            4'd12:   reg_data_out = ct128[31:0];    // CT0
            4'd13:   reg_data_out = ct128[63:32];   // CT1
            4'd14:   reg_data_out = ct128[95:64];   // CT2
            4'd15:   reg_data_out = ct128[127:96];  // CT3
            default: reg_data_out = 32'h0;
        endcase
`ifdef SIM_FAULT_INJECT
        if (fault_mode == 32'd1 && rd_index == 4'd1)
            reg_data_out = key_reg[0];   // FAULT 1: alias KEY1 -> KEY0
`endif
    end

    always @(posedge ACLK) begin
        if (!ARESETN) begin
            axi_rdata <= {DATA_WIDTH{1'b0}};
        end else if (slv_reg_rden) begin
            axi_rdata <= reg_data_out;
        end
    end

    // ================================================================
    //  AES engine + completion FSM
    // ================================================================
    // The core is a continuous pipeline:
    //   S_FEED : stream 16 input bytes to the core
    //   S_WAIT : wait for the core to assert ciphertext_valid (core_ct_valid)
    //   S_CAP  : capture 16 ciphertext bytes as they are validated by core_ct_valid
    localparam S_IDLE = 3'd0,
               S_FEED = 3'd1,
               S_WAIT = 3'd2,
               S_CAP  = 3'd3,
               S_DONE = 3'd4;

    reg [2:0] state;
    reg       core_areset_n;   // active-low reset to AES core
    reg [4:0] feed_idx;        // 0..15
    reg [4:0] cap_idx;         // 0..15

    // 128-bit views (word 3 is most significant; byte 0 = MSB)
    wire [127:0] key128 = { key_reg[3], key_reg[2], key_reg[1], key_reg[0] };
    wire [127:0] pt128  = { pt_reg[3],  pt_reg[2],  pt_reg[1],  pt_reg[0]  };

    // byte being streamed in (index 0 = MSB)
    wire [7:0] pt_byte  = pt128 [(15 - feed_idx) * 8 +: 8];
    wire [7:0] key_byte = key128[(15 - feed_idx) * 8 +: 8];

    reg  [7:0] core_pt;
    reg  [7:0] core_key;
    always @(*) begin
        if (state == S_FEED) begin
            core_pt  = pt_byte;
            core_key = key_byte;
        end else begin
            core_pt  = 8'h00;
            core_key = 8'h00;
        end
    end

    wire [7:0] core_ct;
    wire       core_ct_valid;
    wire       core_done;
    AES_Core u_core (
        .clk              (ACLK),
        .areset_n         (core_areset_n),
        .plaintext_1byte  (core_pt),
        .cipher_key_1byte (core_key),
        .ciphertext_1byte (core_ct),
        .ciphertext_valid (core_ct_valid),
        .done             (core_done)
    );

    integer c;
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            state         <= S_IDLE;
            core_areset_n <= 1'b0;
            feed_idx      <= 5'd0;
            cap_idx       <= 5'd0;
            done_flag     <= 1'b0;
            busy_flag     <= 1'b0;
            for (c = 0; c < 16; c = c + 1) ct_bytes[c] <= 8'h00;
        end else begin
            case (state)
                S_IDLE: begin
                    busy_flag <= 1'b0;
                    if (start_pulse) begin
                        state         <= S_FEED;
                        core_areset_n <= 1'b1;   // release core -> start encrypting
                        busy_flag     <= 1'b1;
                        done_flag     <= 1'b0;
                        feed_idx      <= 5'd0;
                        cap_idx       <= 5'd0;
                    end else begin
                        core_areset_n <= 1'b0;   // hold core in reset while idle
                    end
                end

                // stream 16 input bytes
                S_FEED: begin
                    feed_idx <= feed_idx + 5'd1;
                    if (feed_idx == 5'd15)
                        state <= S_WAIT;
                end

                // wait for ciphertext valid from core
                S_WAIT: begin
                    if (core_ct_valid) begin
                        ct_bytes[0] <= core_ct;   // first ciphertext byte (MSB)
                        cap_idx     <= 5'd1;
                        state       <= S_CAP;
                    end
                end

                // capture the remaining 15 ciphertext bytes
                S_CAP: begin
                    if (core_ct_valid) begin
                        ct_bytes[cap_idx] <= core_ct;
                        cap_idx           <= cap_idx + 5'd1;
                    end
                    if (core_done) begin
                        core_areset_n <= 1'b0;   // park core in reset
                        busy_flag     <= 1'b0;
                        done_flag     <= 1'b1;
                        state         <= S_DONE;
                    end
                end

                S_DONE: begin
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

`ifdef AES_DEBUG
    // sim-only diagnostics: enable with +define+AES_DEBUG
    integer cyc;
    always @(posedge ACLK) begin
        if (!ARESETN) begin
            cyc <= 0;
        end else begin
            if (start_pulse)
                $display("[DBG] start_pulse @cyc=%0d (state=%0d)", cyc, state);
            if (state != S_IDLE) cyc <= cyc + 1;
            // bounded per-cycle trace (one encryption ~230 cycles)
            if (state != S_IDLE && cyc < 260)
                $display("[TRACE] cyc=%0d st=%0d ct_val=%b done=%b feed_idx=%0d cap_idx=%0d core_ct=%02h",
                         cyc, state, core_ct_valid, core_done, feed_idx, cap_idx, core_ct);
            if (state == S_DONE)
                $display("[DUT] DONE @cyc=%0d  ciphertext = %032h", cyc, ct128);
        end
    end
`endif

endmodule
