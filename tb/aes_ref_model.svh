// =============================================================================
//  aes_ref_model.svh  -  independent AES-128 reference model (golden oracle)
// -----------------------------------------------------------------------------
//  Textbook table-based implementation (standard S-box + key schedule), fully
//  independent of the DUT's composite-field core. Used by the scoreboard/test
//  to predict ciphertext for arbitrary key/plaintext.
//
//  Byte convention matches the DUT: for a 128-bit value, byte index 0 is the
//  MOST significant byte (value[127:120]); KEY3/PT3/CT3 are the MS word.
// =============================================================================
class aes_ref_model;

    // standard AES S-box
    const static bit [7:0] sbox [0:255] = '{
        8'h63,8'h7c,8'h77,8'h7b,8'hf2,8'h6b,8'h6f,8'hc5,8'h30,8'h01,8'h67,8'h2b,8'hfe,8'hd7,8'hab,8'h76,
        8'hca,8'h82,8'hc9,8'h7d,8'hfa,8'h59,8'h47,8'hf0,8'had,8'hd4,8'ha2,8'haf,8'h9c,8'ha4,8'h72,8'hc0,
        8'hb7,8'hfd,8'h93,8'h26,8'h36,8'h3f,8'hf7,8'hcc,8'h34,8'ha5,8'he5,8'hf1,8'h71,8'hd8,8'h31,8'h15,
        8'h04,8'hc7,8'h23,8'hc3,8'h18,8'h96,8'h05,8'h9a,8'h07,8'h12,8'h80,8'he2,8'heb,8'h27,8'hb2,8'h75,
        8'h09,8'h83,8'h2c,8'h1a,8'h1b,8'h6e,8'h5a,8'ha0,8'h52,8'h3b,8'hd6,8'hb3,8'h29,8'he3,8'h2f,8'h84,
        8'h53,8'hd1,8'h00,8'hed,8'h20,8'hfc,8'hb1,8'h5b,8'h6a,8'hcb,8'hbe,8'h39,8'h4a,8'h4c,8'h58,8'hcf,
        8'hd0,8'hef,8'haa,8'hfb,8'h43,8'h4d,8'h33,8'h85,8'h45,8'hf9,8'h02,8'h7f,8'h50,8'h3c,8'h9f,8'ha8,
        8'h51,8'ha3,8'h40,8'h8f,8'h92,8'h9d,8'h38,8'hf5,8'hbc,8'hb6,8'hda,8'h21,8'h10,8'hff,8'hf3,8'hd2,
        8'hcd,8'h0c,8'h13,8'hec,8'h5f,8'h97,8'h44,8'h17,8'hc4,8'ha7,8'h7e,8'h3d,8'h64,8'h5d,8'h19,8'h73,
        8'h60,8'h81,8'h4f,8'hdc,8'h22,8'h2a,8'h90,8'h88,8'h46,8'hee,8'hb8,8'h14,8'hde,8'h5e,8'h0b,8'hdb,
        8'he0,8'h32,8'h3a,8'h0a,8'h49,8'h06,8'h24,8'h5c,8'hc2,8'hd3,8'hac,8'h62,8'h91,8'h95,8'he4,8'h79,
        8'he7,8'hc8,8'h37,8'h6d,8'h8d,8'hd5,8'h4e,8'ha9,8'h6c,8'h56,8'hf4,8'hea,8'h65,8'h7a,8'hae,8'h08,
        8'hba,8'h78,8'h25,8'h2e,8'h1c,8'ha6,8'hb4,8'hc6,8'he8,8'hdd,8'h74,8'h1f,8'h4b,8'hbd,8'h8b,8'h8a,
        8'h70,8'h3e,8'hb5,8'h66,8'h48,8'h03,8'hf6,8'h0e,8'h61,8'h35,8'h57,8'hb9,8'h86,8'hc1,8'h1d,8'h9e,
        8'he1,8'hf8,8'h98,8'h11,8'h69,8'hd9,8'h8e,8'h94,8'h9b,8'h1e,8'h87,8'he9,8'hce,8'h55,8'h28,8'hdf,
        8'h8c,8'ha1,8'h89,8'h0d,8'hbf,8'he6,8'h42,8'h68,8'h41,8'h99,8'h2d,8'h0f,8'hb0,8'h54,8'hbb,8'h16
    };

    // GF(2^8) multiply by x (modulo 0x11b)
    static function automatic bit [7:0] xtime(bit [7:0] b);
        return b[7] ? ((b << 1) ^ 8'h1b) : (b << 1);
    endfunction

    // GF(2^8) multiply
    static function automatic bit [7:0] gmul(bit [7:0] a, bit [7:0] b);
        bit [7:0] p  = 8'h00;
        bit [7:0] aa = a;
        bit [7:0] bb = b;
        for (int i = 0; i < 8; i++) begin
            if (bb[0]) p ^= aa;
            aa = xtime(aa);
            bb = bb >> 1;
        end
        return p;
    endfunction

    // key expansion : 11 round keys -> rk[0..175] (byte 0 = MS byte of word)
    static function automatic void key_expand(input bit [7:0] key [16],
                                              output bit [7:0] rk  [176]);
        bit [7:0] temp [4];
        bit [7:0] t0;
        bit [7:0] rcon = 8'h01;
        int i;
        for (i = 0; i < 16; i++) rk[i] = key[i];
        i = 16;
        while (i < 176) begin
            for (int j = 0; j < 4; j++) temp[j] = rk[i-4+j];
            if (i % 16 == 0) begin
                t0 = temp[0];                       // RotWord
                temp[0] = temp[1]; temp[1] = temp[2]; temp[2] = temp[3]; temp[3] = t0;
                for (int j = 0; j < 4; j++) temp[j] = sbox[temp[j]];  // SubWord
                temp[0] = temp[0] ^ rcon;           // Rcon
                rcon = xtime(rcon);
            end
            for (int j = 0; j < 4; j++) rk[i+j] = rk[i-16+j] ^ temp[j];
            i = i + 4;
        end
    endfunction

    static function automatic void add_round_key(ref bit [7:0] s [16],
                                                 input bit [7:0] rk [176], input int round);
        for (int i = 0; i < 16; i++) s[i] = s[i] ^ rk[round*16 + i];
    endfunction

    static function automatic void sub_bytes(ref bit [7:0] s [16]);
        for (int i = 0; i < 16; i++) s[i] = sbox[s[i]];
    endfunction

    // state is column-major: index = row + 4*col
    static function automatic void shift_rows(ref bit [7:0] s [16]);
        bit [7:0] t [16];
        for (int r = 0; r < 4; r++)
            for (int c = 0; c < 4; c++)
                t[r + 4*c] = s[r + 4*((c + r) % 4)];
        for (int i = 0; i < 16; i++) s[i] = t[i];
    endfunction

    static function automatic void mix_columns(ref bit [7:0] s [16]);
        bit [7:0] s0, s1, s2, s3;
        for (int c = 0; c < 4; c++) begin
            s0 = s[4*c]; s1 = s[4*c+1]; s2 = s[4*c+2]; s3 = s[4*c+3];
            s[4*c]   = gmul(8'h02,s0) ^ gmul(8'h03,s1) ^ s2 ^ s3;
            s[4*c+1] = s0 ^ gmul(8'h02,s1) ^ gmul(8'h03,s2) ^ s3;
            s[4*c+2] = s0 ^ s1 ^ gmul(8'h02,s2) ^ gmul(8'h03,s3);
            s[4*c+3] = gmul(8'h03,s0) ^ s1 ^ s2 ^ gmul(8'h02,s3);
        end
    endfunction

    // core encrypt on byte arrays (in[0]/key[0] = MS byte)
    static function automatic void encrypt(input  bit [7:0] in  [16],
                                           input  bit [7:0] key [16],
                                           output bit [7:0] out [16]);
        bit [7:0] s  [16];
        bit [7:0] rk [176];
        key_expand(key, rk);
        for (int i = 0; i < 16; i++) s[i] = in[i];
        add_round_key(s, rk, 0);
        for (int round = 1; round <= 9; round++) begin
            sub_bytes(s);
            shift_rows(s);
            mix_columns(s);
            add_round_key(s, rk, round);
        end
        sub_bytes(s);
        shift_rows(s);
        add_round_key(s, rk, 10);
        for (int i = 0; i < 16; i++) out[i] = s[i];
    endfunction

    // convenience 128-bit wrapper (matches DUT byte order: byte0 = MSB)
    static function automatic bit [127:0] encrypt128(bit [127:0] key, bit [127:0] pt);
        bit [7:0] k [16];
        bit [7:0] p [16];
        bit [7:0] o [16];
        bit [127:0] ct;
        for (int i = 0; i < 16; i++) begin
            k[i] = key[(15-i)*8 +: 8];
            p[i] = pt [(15-i)*8 +: 8];
        end
        encrypt(p, k, o);
        for (int i = 0; i < 16; i++) ct[(15-i)*8 +: 8] = o[i];
        return ct;
    endfunction

endclass
