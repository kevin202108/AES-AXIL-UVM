/* =============================================================================
 *  aes128_kat_check.c  -  offline C check of NIST KAT files vs aes128.c
 *
 *  No simulator / OpenSSL required. Reads the same hex vectors used by
 *  axil_kat_test ($readmemh format: one 32-nibble hex word per line).
 *
 *  Build & run (from repo root, Linux / Git Bash / WSL / school server):
 *      gcc -Wall -Wextra -O2 -o aes128_kat_check \
 *          c_model/aes128.c c_model/aes128_kat_check.c -I c_model
 *      ./aes128_kat_check tb/kat_key.dat tb/kat_pt.dat tb/kat_ct.dat
 *
 *  Default paths if argc == 1: tb/kat_key.dat tb/kat_pt.dat tb/kat_ct.dat
 * =============================================================================
 */
#include "aes128.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { KAT_N = 259, LINE_MAX = 128 };

/* Parse one 128-bit hex line into 16 bytes, index 0 = MSB. Returns 0 on ok. */
static int parse_hex128(const char *line, uint8_t out[16])
{
    const char *p = line;
    int nibbles = 0;
    uint8_t cur = 0;

    while (*p && isspace((unsigned char)*p))
        p++;

    while (*p && !isspace((unsigned char)*p) && *p != '#' && *p != '/') {
        int v;
        char c = *p++;
        if (c >= '0' && c <= '9')
            v = c - '0';
        else if (c >= 'a' && c <= 'f')
            v = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F')
            v = c - 'A' + 10;
        else
            return -1;

        if ((nibbles & 1) == 0)
            cur = (uint8_t)(v << 4);
        else
            out[nibbles / 2] = (uint8_t)(cur | (uint8_t)v);
        nibbles++;
        if (nibbles > 32)
            return -1;
    }

    return (nibbles == 32) ? 0 : -1;
}

static int load_file(const char *path, uint8_t vecs[][16], int expected)
{
    FILE *f = fopen(path, "r");
    char line[LINE_MAX];
    int n = 0;

    if (!f) {
        fprintf(stderr, "aes128_kat_check: cannot open %s\n", path);
        return -1;
    }

    while (fgets(line, sizeof line, f) != NULL) {
        const char *p = line;
        while (*p && isspace((unsigned char)*p))
            p++;
        if (*p == '\0' || *p == '#' || (*p == '/' && p[1] == '/'))
            continue;
        if (n >= expected) {
            fprintf(stderr, "aes128_kat_check: %s has more than %d vectors\n",
                    path, expected);
            fclose(f);
            return -1;
        }
        if (parse_hex128(p, vecs[n]) != 0) {
            fprintf(stderr, "aes128_kat_check: bad hex line %d in %s\n",
                    n, path);
            fclose(f);
            return -1;
        }
        n++;
    }
    fclose(f);

    if (n != expected) {
        fprintf(stderr, "aes128_kat_check: %s has %d vectors, expected %d\n",
                path, n, expected);
        return -1;
    }
    return 0;
}

static void hex16(const uint8_t b[16], char out[33])
{
    static const char *h = "0123456789abcdef";
    for (int i = 0; i < 16; i++) {
        out[i * 2]     = h[(b[i] >> 4) & 0xF];
        out[i * 2 + 1] = h[b[i] & 0xF];
    }
    out[32] = '\0';
}

int main(int argc, char **argv)
{
    const char *key_path = "tb/kat_key.dat";
    const char *pt_path  = "tb/kat_pt.dat";
    const char *ct_path  = "tb/kat_ct.dat";
    uint8_t keys[KAT_N][16];
    uint8_t pts[KAT_N][16];
    uint8_t cts[KAT_N][16];
    uint8_t got[16];
    int fail = 0;
    char ks[33], ps[33], gs[33], es[33];

    if (argc == 4) {
        key_path = argv[1];
        pt_path  = argv[2];
        ct_path  = argv[3];
    } else if (argc != 1) {
        fprintf(stderr,
                "usage: %s [key.dat pt.dat ct.dat]\n"
                "  default: tb/kat_key.dat tb/kat_pt.dat tb/kat_ct.dat\n",
                argv[0]);
        return 2;
    }

    if (aes128_selfcheck() != 0) {
        fprintf(stderr, "aes128_kat_check: built-in selfcheck FAIL\n");
        return 1;
    }

    if (load_file(key_path, keys, KAT_N) != 0 ||
        load_file(pt_path,  pts,  KAT_N) != 0 ||
        load_file(ct_path,  cts,  KAT_N) != 0)
        return 1;

    for (int i = 0; i < KAT_N; i++) {
        aes128_encrypt(keys[i], pts[i], got);
        if (memcmp(got, cts[i], 16) != 0) {
            fail++;
            hex16(keys[i], ks);
            hex16(pts[i],  ps);
            hex16(got,     gs);
            hex16(cts[i],  es);
            fprintf(stderr,
                    "vector %d MISMATCH\n  key=%s\n  pt =%s\n  got=%s\n  exp=%s\n",
                    i, ks, ps, gs, es);
            if (fail >= 5) {
                fprintf(stderr, "... stopping after 5 mismatches\n");
                break;
            }
        }
    }

    if (fail == 0) {
        printf("aes128_kat_check: PASS (%d vectors, C model == kat_ct.dat)\n",
               KAT_N);
        return 0;
    }

    printf("aes128_kat_check: FAIL (at least %d mismatches of %d)\n",
           fail, KAT_N);
    return 1;
}
