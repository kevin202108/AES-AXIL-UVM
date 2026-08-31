// =============================================================================
//  aes_dpi.svh  -  DPI-C import + SV wrappers for the C AES-128 golden model
// -----------------------------------------------------------------------------
//  C side: c_model/aes128.c  (aes128_encrypt, aes128_selfcheck)
//  Byte order: index 0 = MSB (matches DUT / aes_ref_model).
//
//  EDA Playground: Design tab "aes128.c" + enable "Use run.bash shell script"
//  (sim/run.bash links aes128.c). Tabs alone are not linked — see
//  doc/VERIFICATION.md §4.3.
// =============================================================================

// Fixed-size unpacked arrays map cleanly to C char/uint8_t[16] on VCS/Xcelium.
import "DPI-C" function void aes128_encrypt(
    input  byte key[16],
    input  byte pt[16],
    output byte ct[16]
);

// Optional: C built-in self-check (FIPS-197 + all-zero). Returns 0 on pass.
import "DPI-C" function int aes128_selfcheck();

// ---------------------------------------------------------------------------
//  Convenience wrappers (same 128-bit layout as aes_ref_model::encrypt128)
// ---------------------------------------------------------------------------
function automatic void dpi_bytes_from_128(input bit [127:0] v, output byte b[16]);
    for (int i = 0; i < 16; i++)
        b[i] = v[(15 - i) * 8 +: 8];
endfunction

function automatic bit [127:0] dpi_128_from_bytes(input byte b[16]);
    bit [127:0] v;
    for (int i = 0; i < 16; i++)
        v[(15 - i) * 8 +: 8] = b[i];
    return v;
endfunction

function automatic bit [127:0] dpi_encrypt128(bit [127:0] key, bit [127:0] pt);
    byte k[16], p[16], o[16];
    dpi_bytes_from_128(key, k);
    dpi_bytes_from_128(pt, p);
    aes128_encrypt(k, p, o);
    return dpi_128_from_bytes(o);
endfunction
