/* =============================================================================
 *  aes128_selftest.c  -  standalone gcc check (no simulator required)
 *
 *  Build & run (from repo root):
 *      gcc -Wall -Wextra -O2 -o aes128_selftest \
 *          c_model/aes128.c c_model/aes128_selftest.c -I c_model
 *      ./aes128_selftest
 * =============================================================================
 */
#include "aes128.h"
#include <stdio.h>

int main(void)
{
    int rc = aes128_selfcheck();
    if (rc == 0) {
        printf("aes128_selftest: PASS (FIPS-197 + all-zero)\n");
        return 0;
    }
    printf("aes128_selftest: FAIL (code=%d)\n", rc);
    return 1;
}
