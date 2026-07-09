// =============================================================================
//  aes_rtl.sv  -  AES-128 byte-serial core, vendored verbatim from
//                 AES_Core/src/ (do NOT edit here; edit the source files).
//  Modules: AES_Core, AES_MixColumn_Logic, AES_KeyExpand,
//           AES_LFSR_Controler, AES_Sbox (+ composite-field submodules).
// =============================================================================

// ---------------- AES_Sbox.v ----------------
module AES_Sbox
(
    input       [7:0] in_8bits,
    output      [7:0] out_8bits
);
    wire    [7:0]   delta_mapping_out;
    wire    [7:0]   inverse_delta_mapping_in, inverse_delta_mapping_out;

    Delta_Mapping delta
    (
        .in_8bits(in_8bits),
        .out_8bits(delta_mapping_out)
    );

    Inverse_GF2tp2tp2tp2 inverse_GF2tp2tp2tp2
    (
        .in_8bits(delta_mapping_out),
        .out_8bits(inverse_delta_mapping_in)
    );

    Inverse_Delta_Affine_Mapping inverse_delta
    (
        .in_8bits(inverse_delta_mapping_in),
        .out_8bits(inverse_delta_mapping_out)
    );

    assign out_8bits = inverse_delta_mapping_out ^ 8'h63;
endmodule

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//  choose polynomial = x^8 + x^4 + x^3 + x^2 + 1, alpha = 03, beta = 43 phi = 10, lambda = 1100               //
//  although 11,1000 has shorter critical path, after compile_ultra, it consume 10um^2 more area than 10,1100  //
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//(a1 * alpha + a0) * alpha = (a1 + a0) * alpha + a1
module Times_Phi
(
    input       [1:0]   in_2bits,
    output      [1:0]   out_2bits
);
    assign out_2bits[1] = in_2bits[1] ^ in_2bits[0];
    assign out_2bits[0] = in_2bits[1];
endmodule

//[(a2 + a0) * alpha + (a3 + a2 + a1 + a0)] * beta + [a3 * alpha + a2]
module Times_Lambda
(
    input       [3:0]   in_4bits,
    output      [3:0]   out_4bits
);
    assign out_4bits[3] = in_4bits[2] ^ in_4bits[0];
    assign out_4bits[2] = in_4bits[3] ^ in_4bits[2] ^ in_4bits[1] ^ in_4bits[0];
    assign out_4bits[1] = in_4bits[3];
    assign out_4bits[0] = in_4bits[2];
endmodule

//{ [a3 * alpha + a2] * beta + (a1 * alpha + a0) }^2 = [a3 * alpha + (a3 + a2)] * beta + [(a2 + a1) * alpha + (a3 + a1 + a0)]
module Squarer_GF2tp2tp2
(
    input       [3:0]   in_4bits,
    output      [3:0]   out_4bits
);
    assign out_4bits[3] = in_4bits[3];
    assign out_4bits[2] = in_4bits[3] ^ in_4bits[2];
    assign out_4bits[1] = in_4bits[2] ^ in_4bits[1];
    assign out_4bits[0] = in_4bits[3] ^ in_4bits[1] ^ in_4bits[0];
endmodule

//(a1 * alpha + a0)(b1 * alpha + b0) = (a1b1 + a1b0 + a0b1) * alpha + (a1b1 + a0b0)
module Multiplier_GF2tp2
(
    input       [1:0]   in_a_2bits,
    input       [1:0]   in_b_2bits,
    output      [1:0]   out_2bits
);
    assign out_2bits[1] = (in_a_2bits[1] & in_b_2bits[1]) ^ (in_a_2bits[1] & in_b_2bits[0]) ^ (in_a_2bits[0] & in_b_2bits[1]);
    assign out_2bits[0] = (in_a_2bits[1] & in_b_2bits[1]) ^ (in_a_2bits[0] & in_b_2bits[0]);
endmodule

//[{a3a2}{b3b2} + {a1a0}{b3b2} + {a3a2}{b1b0}] * beta + {a1a0}{b1b0} + {a3a2}{b3b2} * phi
module Multiplier_GF2tp2tp2
(
    input       [3:0]   in_a_4bits,
    input       [3:0]   in_b_4bits,
    output      [3:0]   out_4bits
);
    wire    [1:0]   multiplier_up_out, multiplier_mid_out, multiplier_bot_out;
    wire    [1:0]   out_phi;

    assign out_4bits[3:2] = multiplier_mid_out ^ multiplier_bot_out;
    assign out_4bits[1:0] = out_phi ^ multiplier_bot_out;

    Multiplier_GF2tp2 multiplier_up
    (
        .in_a_2bits(in_a_4bits[3:2]),
        .in_b_2bits(in_b_4bits[3:2]),
        .out_2bits(multiplier_up_out)
    );

    Multiplier_GF2tp2 multiplier_mid
    (
        .in_a_2bits(in_a_4bits[3:2] ^ in_a_4bits[1:0]),
        .in_b_2bits(in_b_4bits[3:2] ^ in_b_4bits[1:0]),
        .out_2bits(multiplier_mid_out)
    );

    Multiplier_GF2tp2 multiplier_bot
    (
        .in_a_2bits(in_a_4bits[1:0]),
        .in_b_2bits(in_b_4bits[1:0]),
        .out_2bits(multiplier_bot_out)
    );

    Times_Phi times_phi
    (
        .in_2bits(multiplier_up_out),
        .out_2bits(out_phi)
    );
endmodule

//a3' = a3a2a1 + a3a0 + a3 + a2
//a2' = a3a2a1 + a3a2a0 + a3a0 + a2a1 + a2
//a1' = a3a2a1 + a3a1a0 + a3 + a2a0 + a2 + a1
//a0' = a3a2a1 + a3a2a0 + a3a1a0 + a3a1 + a3a0 + a2a1a0 + a2a1 + a2 + a1 + a0
module Inverse_GF2tp2tp2
(
    input       [3:0]   in_4bits,
    output      [3:0]   out_4bits
);
    assign out_4bits[3] = ( &in_4bits[3:1] ) ^ ( &{in_4bits[3], in_4bits[0]} ) ^ in_4bits[3] ^ in_4bits[2];
    assign out_4bits[2] = ( &in_4bits[3:1] ) ^ ( &{in_4bits[3:2], in_4bits[0]} ) ^ ( &{in_4bits[3], in_4bits[0]} ) ^ ( &in_4bits[2:1] ) ^ in_4bits[2];
    assign out_4bits[1] = ( &in_4bits[3:1] ) ^ ( &{in_4bits[3], in_4bits[1:0]} ) ^ in_4bits[3] ^ ( &{in_4bits[2], in_4bits[0]} ) ^ in_4bits[2] ^ in_4bits[1];
    assign out_4bits[0] = ( &in_4bits[3:1] ) ^ ( &{in_4bits[3:2], in_4bits[0]} ) ^ ( &{in_4bits[3], in_4bits[1:0]} ) ^ ( &{in_4bits[3], in_4bits[1]} )
                          ^ ( &{in_4bits[3], in_4bits[0]} ) ^ ( &in_4bits[2:0] ) ^ ( &in_4bits[2:1] ) ^ in_4bits[2] ^ in_4bits[1] ^ in_4bits[0];
endmodule

//Xinmiao Zhang, High-Speed VLSI Architectures for the AES Algorithm Fig3
module Inverse_GF2tp2tp2tp2
(
    input       [7:0]   in_8bits,
    output      [7:0]   out_8bits
);
    wire    [3:0]   half_byte_addup;
    wire    [3:0]   squarer_out_4bits;
    wire    [3:0]   lambda_out_4bits;
    wire    [3:0]   multiplier_first_stage_out;
    wire    [3:0]   inverse_GF2tp2tp2_in, inverse_GF2tp2tp2_out;

    assign half_byte_addup = in_8bits[7:4] ^ in_8bits[3:0];

    Squarer_GF2tp2tp2 squarer
    (
        .in_4bits(in_8bits[7:4]),
        .out_4bits(squarer_out_4bits)
    );

    Times_Lambda times_lambda
    (
        .in_4bits(squarer_out_4bits),
        .out_4bits(lambda_out_4bits)
    );

    Multiplier_GF2tp2tp2 multiplier_1st_stage
    (
        .in_a_4bits(half_byte_addup),
        .in_b_4bits(in_8bits[3:0]),
        .out_4bits(multiplier_first_stage_out)
    );

    assign inverse_GF2tp2tp2_in = lambda_out_4bits ^ multiplier_first_stage_out;

    Inverse_GF2tp2tp2 inverse_GF2tp2tp2
    (
        .in_4bits(inverse_GF2tp2tp2_in),
        .out_4bits(inverse_GF2tp2tp2_out)
    );

    Multiplier_GF2tp2tp2 multiplier_2nd_stage_top
    (
        .in_a_4bits(in_8bits[7:4]),
        .in_b_4bits(inverse_GF2tp2tp2_out),
        .out_4bits(out_8bits[7:4])
    );

    Multiplier_GF2tp2tp2 multiplier_2nd_stage_bot
    (
        .in_a_4bits(half_byte_addup),
        .in_b_4bits(inverse_GF2tp2tp2_out),
        .out_4bits(out_8bits[3:0])
    );
endmodule

//delta matrix which maps byte in GF(2^8) in to GF(2^2^2^2)
/*
        / 1 0 0 0 0 0 0 0 \  / a0 \
        | 0 1 0 1 1 0 0 1 |  | a1 |
        | 0 1 1 1 0 0 1 0 |  | a2 |
        | 0 0 1 0 1 1 0 1 |  | a3 |
        | 0 0 0 0 1 1 1 0 |  | a4 |
        | 0 0 1 1 0 0 0 0 |  | a5 |
        | 0 1 1 1 1 0 1 1 |  | a6 |
        \ 0 0 0 0 0 1 0 1 /  \ a7 /
*/
module Delta_Mapping
(
    input       [7:0]   in_8bits,
    output      [7:0]   out_8bits
);
    assign out_8bits[0] = in_8bits[0] ^ in_8bits[4] ^ in_8bits[5] ^ in_8bits[6];
    assign out_8bits[1] = in_8bits[1] ^ in_8bits[2] ^ in_8bits[4] ^ in_8bits[7];
    assign out_8bits[2] = in_8bits[4] ^ in_8bits[7];
    assign out_8bits[3] = in_8bits[2] ^ in_8bits[4];
    assign out_8bits[4] = in_8bits[4] ^ in_8bits[5] ^ in_8bits[6];
    assign out_8bits[5] = in_8bits[2] ^ in_8bits[3];
    assign out_8bits[6] = in_8bits[1] ^ in_8bits[2] ^ in_8bits[3] ^ in_8bits[4] ^ in_8bits[6] ^ in_8bits[7];
    assign out_8bits[7] = in_8bits[5] ^ in_8bits[7];
endmodule

//delta matrix which maps byte in GF(2^8) in to GF(2^2^2^2)
/*
        / 1 0 0 0 0 0 0 0 \  / b0 \
        | 0 0 0 0 1 1 0 0 |  | b1 |
        | 0 0 1 0 1 0 0 0 |  | b2 |
        | 0 0 0 0 1 1 0 1 |  | b3 |
        | 0 0 0 0 1 0 0 0 |  | b4 |
        | 0 1 0 0 0 0 1 1 |  | b5 |
        | 0 0 1 0 0 0 1 1 |  | b6 |
        \ 0 1 0 1 0 0 0 0 /  \ b7 /
*/
module Inverse_Delta_Affine_Mapping
(
    input       [7:0]   in_8bits,
    output      [7:0]   out_8bits
);
    assign out_8bits[0] = in_8bits[0] ^ in_8bits[1] ^ in_8bits[3] ^ in_8bits[4] ^ in_8bits[5] ^ in_8bits[6] ^ in_8bits[7];
    assign out_8bits[1] = in_8bits[0] ^ in_8bits[2] ^ in_8bits[4] ^ in_8bits[5] ^ in_8bits[6] ^ in_8bits[7];
    assign out_8bits[2] = in_8bits[0] ^ in_8bits[3] ^ in_8bits[4] ^ in_8bits[5] ^ in_8bits[6];
    assign out_8bits[3] = in_8bits[0] ^ in_8bits[1] ^ in_8bits[3] ^ in_8bits[4] ^ in_8bits[5];
    assign out_8bits[4] = in_8bits[0] ^ in_8bits[1] ^ in_8bits[2] ^ in_8bits[3] ^ in_8bits[4] ^ in_8bits[5];
    assign out_8bits[5] = in_8bits[2] ^ in_8bits[4] ^ in_8bits[6];
    assign out_8bits[6] = in_8bits[4] ^ in_8bits[5];
    assign out_8bits[7] = in_8bits[2] ^ in_8bits[3] ^ in_8bits[4] ^ in_8bits[5];
endmodule
// ---------------- AES_LFSR_Controler.v ----------------
`timescale 1ns/1ps

`define ADD_ROUND_KEY_SUB_BYTES_0       5'h01
`define ADD_ROUND_KEY_SUB_BYTES_1       5'h02
`define ADD_ROUND_KEY_SUB_BYTES_2       5'h04
`define ADD_ROUND_KEY_SUB_BYTES_3       5'h08
`define ADD_ROUND_KEY_SUB_BYTES_4       5'h10
`define ADD_ROUND_KEY_SUB_BYTES_5       5'h05
`define ADD_ROUND_KEY_SUB_BYTES_6       5'h0A
`define ADD_ROUND_KEY_SUB_BYTES_7       5'h14
`define ADD_ROUND_KEY_SUB_BYTES_8       5'h0D
`define ADD_ROUND_KEY_SUB_BYTES_9       5'h1A
`define ADD_ROUND_KEY_SUB_BYTES_10      5'h11
`define ADD_ROUND_KEY_SUB_BYTES_11      5'h07
`define ADD_ROUND_KEY_SUB_BYTES_12      5'h0E
`define ADD_ROUND_KEY_SUB_BYTES_13      5'h1C
`define ADD_ROUND_KEY_SUB_BYTES_14      5'h1D
`define ADD_ROUND_KEY_SUB_BYTES_15      5'h1F
`define SHIFT_ROWS                      5'h1B
`define MIX_COLUMNS_0                   5'h13
`define MIX_COLUMNS_1                   5'h03
`define MIX_COLUMNS_2                   5'h06
`define MIX_COLUMNS_3                   5'h0C

`define ROUND_0     4'h1
`define ROUND_1     4'h2
`define ROUND_2     4'h4
`define ROUND_3     4'h8
`define ROUND_4     4'h3
`define ROUND_5     4'h6
`define ROUND_6     4'hC
`define ROUND_7     4'hB
`define ROUND_8     4'h5
`define ROUND_9     4'hA
`define ROUND_10    4'h7

module AES_LFSR_Controler
(
    input   clk,
    input   areset_n,
    output  is_key_expand_using_sbox,
    output  is_first_round,
    output  is_add_round_key_sub_bytes,
    output  is_shift_rows,
    output  is_skip_mix_columns,
    output  is_word_xor,
    output  is_rotate,
    output  is_add_rcon,
    output  is_non_linear_trans,
    output  ciphertext_valid,
    output  done
);
    reg [4:0] aes_loop_lsfr;    //x^5 + x^2 + 1
    reg [3:0] round_lfsr;       //x^4 + x + 1
    reg       running_round;
    
    assign is_key_expand_using_sbox = ( aes_loop_lsfr == `SHIFT_ROWS    ||
                                        aes_loop_lsfr == `MIX_COLUMNS_0 ||
                                        aes_loop_lsfr == `MIX_COLUMNS_1 ||
                                        aes_loop_lsfr == `MIX_COLUMNS_2     );

    assign is_first_round = (round_lfsr == `ROUND_0);

    assign is_add_round_key_sub_bytes = (   aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_0  ||
                                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_1  ||
                                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_2  ||
                                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_3  ||
                                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_4  ||
                                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_5  ||
                                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_6  ||
                                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_7  ||
                                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_8  ||
                                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_9  ||
                                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_10 ||
                                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_11 ||
                                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_12 ||
                                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_13 ||
                                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_14 ||
                                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_15    );

    assign is_shift_rows = (aes_loop_lsfr == `SHIFT_ROWS);

    assign is_skip_mix_columns = (round_lfsr == `ROUND_10);

    assign is_word_xor = (  aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_0  ||
                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_1  ||
                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_2  ||
                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_3  ||
                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_4  ||
                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_5  ||
                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_6  ||
                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_7  ||
                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_8  ||
                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_9  ||
                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_10 ||
                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_11    );

    assign is_rotate = (    aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_12 ||
                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_13 ||
                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_14 ||
                            aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_15    );

    assign is_add_rcon = (aes_loop_lsfr == `SHIFT_ROWS);

    assign is_non_linear_trans = is_key_expand_using_sbox;

    assign ciphertext_valid = running_round && is_first_round && is_add_round_key_sub_bytes;
    assign done = ciphertext_valid && (aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_15);

    always @(posedge clk or negedge areset_n) begin
        if(!areset_n) begin
            aes_loop_lsfr   <= #1 `ADD_ROUND_KEY_SUB_BYTES_0;
            round_lfsr      <= #1 `ROUND_0;
            running_round   <= #1 1'b0;
        end
        else begin
            if(round_lfsr == `ROUND_0 && aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_15) begin
                running_round <= #1 1'b1;
            end
            if(round_lfsr == `ROUND_10 && aes_loop_lsfr == `MIX_COLUMNS_2) begin
                aes_loop_lsfr   <= #1 `ADD_ROUND_KEY_SUB_BYTES_0;
                round_lfsr      <= #1 `ROUND_0;
            end
            else if(aes_loop_lsfr == `MIX_COLUMNS_3) aes_loop_lsfr <= #1 `ADD_ROUND_KEY_SUB_BYTES_0;
            else begin
                aes_loop_lsfr <= #1 {aes_loop_lsfr[3:2], aes_loop_lsfr[1] ^ aes_loop_lsfr[4], aes_loop_lsfr[0], aes_loop_lsfr[4]};

                if(aes_loop_lsfr == `ADD_ROUND_KEY_SUB_BYTES_15) round_lfsr <= #1 {round_lfsr[2:1], round_lfsr[0] ^ round_lfsr[3], round_lfsr[3]};
            end
        end
    end
endmodule
// ---------------- AES_KeyExpand.v ----------------
`timescale 1ns/1ps

module AES_KeyExpand
(
    input               clk,
    input               areset_n,
    input               is_first_round,
    input               is_word_xor,
    input               is_rotate,
    input               is_add_rcon,
    input               is_non_linear_trans,
    input       [7:0]   cipher_key_1byte,
    input       [7:0]   subbytes_out,
    output      [7:0]   subbytes_in,
    output      [7:0]   round_key_1byte
);
    reg [7:0] rcon_polynomial;
    reg [7:0] round_key_buffer [0:15];

    assign round_key_1byte = round_key_buffer[0];

    assign subbytes_in = round_key_buffer[13];

    integer i, j;
    always @(posedge clk or negedge areset_n) begin
        if(!areset_n) begin
            for(i = 4; i < 8; i = i + 1) begin
                round_key_buffer[i] <= #1 8'd0;
            end
        end
        else begin
            if(is_word_xor) begin
                round_key_buffer[3] <= #1 round_key_buffer[0] ^ round_key_buffer[4];
                for(i = 0; i < 3; i = i + 1) begin
                    round_key_buffer[i] <= #1 round_key_buffer[i + 1];
                end

                if(is_first_round) round_key_buffer[15] <= #1 cipher_key_1byte;
                else round_key_buffer[15] <= #1 round_key_buffer[0];
                for(j = 4; j < 15; j = j + 1) begin
                    round_key_buffer[j] <= #1 round_key_buffer[j + 1];
                end

                if(is_first_round) rcon_polynomial <= #1 8'b00000001;
            end
            else if(is_rotate) begin
                round_key_buffer[3] <= #1 round_key_buffer[4];
                for(i = 0; i < 3; i = i + 1) begin
                    round_key_buffer[i] <= #1 round_key_buffer[i + 1];
                end

                if(is_first_round) round_key_buffer[15] <= #1 cipher_key_1byte;
                else round_key_buffer[15] <= #1 round_key_buffer[0];
                for(j = 4; j < 15; j = j + 1) begin
                    round_key_buffer[j] <= #1 round_key_buffer[j + 1];
                end
            end
            else if(is_non_linear_trans) begin
                if(is_add_rcon) round_key_buffer[3] <= #1 subbytes_out ^ rcon_polynomial ^ round_key_buffer[0];
                else round_key_buffer[3] <= #1 subbytes_out ^ round_key_buffer[0];
                for(i = 0; i < 3; i = i + 1) begin
                    round_key_buffer[i] <= #1 round_key_buffer[i + 1];
                end
                
                round_key_buffer[15] <= #1 round_key_buffer[12];
                for(j = 12; j < 15; j = j + 1) begin
                    round_key_buffer[j] <= #1 round_key_buffer[j + 1];
                end

                if(is_add_rcon) rcon_polynomial <= #1 {     rcon_polynomial[6:4]                   ,
                                                            rcon_polynomial[3] ^ rcon_polynomial[7],
                                                            rcon_polynomial[2] ^ rcon_polynomial[7],
                                                            rcon_polynomial[1]                     ,
                                                            rcon_polynomial[0] ^ rcon_polynomial[7],
                                                            rcon_polynomial[7]                          };
            end
        end
    end
endmodule
// ---------------- AES_Core.v ----------------
`timescale 1ns/1ps
//Latency: 2080 ns throughput: 128 bits / 2090 ns
module AES_Core
(
    input               clk,
    input               areset_n,
    input       [7:0]   plaintext_1byte,
    input       [7:0]   cipher_key_1byte,
    output      [7:0]   ciphertext_1byte,
    output              ciphertext_valid,
    output              done
);
    reg [7:0] state_array [0:15];

    wire  is_key_expand_using_sbox;
    wire  is_first_round;
    wire  is_add_round_key_sub_bytes;
    wire  is_shift_rows;
    wire  is_skip_mix_columns;
    wire  is_word_xor;
    wire  is_rotate;
    wire  is_add_rcon;
    wire  is_non_linear_trans;

    wire [7:0] subbytes_in_key_expand;
    wire [7:0] round_key_1byte;
    reg [7:0] subbytes_in;
    wire [7:0] subbytes_out;
    always @(*) begin
        if(is_key_expand_using_sbox) subbytes_in = subbytes_in_key_expand;
        else begin
            if(is_first_round) subbytes_in = plaintext_1byte ^ cipher_key_1byte;
            else subbytes_in = round_key_1byte ^ state_array[0];
        end
    end

    AES_Sbox u_AES_Sbox
    (
        .in_8bits(subbytes_in),
        .out_8bits(subbytes_out)
    );

    wire [7:0] mix_columns_to_12, mix_columns_to_13, mix_columns_to_14, mix_columns_to_15;
    AES_MixColumn_Logic u_AES_MixColumn_Logic[3:0]
    (
        .in_columns({
                        state_array[0], state_array[1], state_array[2], state_array[3],
                        state_array[1], state_array[2], state_array[3], state_array[0],
                        state_array[2], state_array[3], state_array[0], state_array[1],
                        state_array[3], state_array[0], state_array[1], state_array[2]
                                                                                            }),
        .out_mix_columns({mix_columns_to_12, mix_columns_to_13, mix_columns_to_14, mix_columns_to_15})
    );

    AES_LFSR_Controler u_AES_LFSR_Controler
    (
        .clk(clk),
        .areset_n(areset_n),
        .is_key_expand_using_sbox(is_key_expand_using_sbox),
        .is_first_round(is_first_round),
        .is_add_round_key_sub_bytes(is_add_round_key_sub_bytes),
        .is_shift_rows(is_shift_rows),
        .is_skip_mix_columns(is_skip_mix_columns),
        .is_word_xor(is_word_xor),
        .is_rotate(is_rotate),
        .is_add_rcon(is_add_rcon),
        .is_non_linear_trans(is_non_linear_trans),
        .ciphertext_valid(ciphertext_valid),
        .done(done)
    );
    
    AES_KeyExpand u_AES_KeyExpand
    (
        .clk(clk),
        .areset_n(areset_n),
        .is_first_round(is_first_round),
        .is_word_xor(is_word_xor),
        .is_rotate(is_rotate),
        .is_add_rcon(is_add_rcon),
        .is_non_linear_trans(is_non_linear_trans),
        .cipher_key_1byte(cipher_key_1byte),
        .subbytes_out(subbytes_out),
        .subbytes_in(subbytes_in_key_expand),
        .round_key_1byte(round_key_1byte)
    );

    assign ciphertext_1byte = state_array[0] ^ round_key_1byte;

    integer i;
    always @(posedge clk) begin
        if(is_add_round_key_sub_bytes) begin
            state_array[15] <= #1 subbytes_out;
            for(i = 0; i < 15; i = i + 1) begin
                state_array[i] <= #1 state_array[i + 1];
            end
        end
        else if(is_shift_rows) begin
            state_array[13] <= #1 state_array[1];
            state_array[1] <= #1 state_array[5];
            state_array[5] <= #1 state_array[9];
            state_array[9] <= #1 state_array[13];

            state_array[14] <= #1 state_array[6];
            state_array[2] <= #1 state_array[10];
            state_array[6] <= #1 state_array[14];
            state_array[10] <= #1 state_array[2];

            state_array[15] <= #1 state_array[11];
            state_array[3] <= #1 state_array[15];
            state_array[7] <= #1 state_array[3];
            state_array[11] <= #1 state_array[7];
        end
        else begin //is_mix_columns
            if(!is_skip_mix_columns) begin
                state_array[12] <= #1 mix_columns_to_12;
                state_array[13] <= #1 mix_columns_to_13;
                state_array[14] <= #1 mix_columns_to_14;
                state_array[15] <= #1 mix_columns_to_15;

                state_array[8] <= #1 state_array[12];
                state_array[9] <= #1 state_array[13];
                state_array[10] <= #1 state_array[14];
                state_array[11] <= #1 state_array[15];

                state_array[4] <= #1 state_array[8];
                state_array[5] <= #1 state_array[9];
                state_array[6] <= #1 state_array[10];
                state_array[7] <= #1 state_array[11];

                state_array[0] <= #1 state_array[4];
                state_array[1] <= #1 state_array[5];
                state_array[2] <= #1 state_array[6];
                state_array[3] <= #1 state_array[7];
            end
        end
    end
endmodule

module AES_MixColumn_Logic (
    input   [31:0] in_columns,
    output  [7:0]  out_mix_columns
);
    wire [7:0] b0 = in_columns[31:24]; //02
    wire [7:0] b1 = in_columns[23:16]; //03
    wire [7:0] b2 = in_columns[15:8];  //01
    wire [7:0] b3 = in_columns[7:0];   //01

    wire [7:0] b0_xor_b1 = b0 ^ b1;
    wire [7:0] xtime = {b0_xor_b1[6:0], 1'b0} ^ (b0_xor_b1[7] ? 8'h1B : 8'h00);

    assign out_mix_columns = xtime ^ b1 ^ b2 ^ b3;
endmodule