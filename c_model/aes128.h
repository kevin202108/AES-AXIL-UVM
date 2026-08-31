/* =============================================================================
 *  aes128.h  -  AES-128 encrypt API for DPI-C / standalone C unit test
 * -----------------------------------------------------------------------------
 *  Byte order matches the DUT and SV aes_ref_model:
 *    index 0 = most significant byte of the 128-bit value
 *    (KEY3/PT3/CT3 are the MS word on the AXI register map).
 * =============================================================================
 */
#ifndef AES128_H
#define AES128_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Encrypt one 128-bit block.  key/pt/ct are 16-byte arrays, index 0 = MSB. */
void aes128_encrypt(const uint8_t key[16],
                    const uint8_t pt[16],
                    uint8_t       ct[16]);

/* Returns 0 if built-in FIPS-197 + all-zero self-checks pass, else non-zero. */
int aes128_selfcheck(void);

#ifdef __cplusplus
}
#endif

#endif /* AES128_H */
