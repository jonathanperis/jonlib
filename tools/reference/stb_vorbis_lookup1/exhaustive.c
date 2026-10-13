// Exhaustive check of the rule src/vorbis_codebook.bend answers
// lookup1_values by, against stb_vorbis's own function with the host's
// binary64 log, exp and pow.
//
// stb_vorbis estimates the integer root as
//    r = (int) floor(exp((float) log((float) entries) / dim))
// and corrects it by one upward only: its answer is the root R (the largest
// integer whose dim-th power is at most entries) when the estimate is R or
// R - 1, and -1 otherwise. The estimate's argument is ln(entries)/dim after
// two float roundings, a relative error of at most 2^-23 (and a little),
// so the estimate is the root times e^(ln(entries)*d) with |d| <= 2^-23:
//   - it is below R + 1 when ln(entries)*d < ln((R+1)^dim / entries), which
//     holds when 17*P < (P - entries)*2^23 for P = (R+1)^dim (ln(entries) is
//     under 16.64 and ln(P/entries) is at least (P - entries)/P), and for
//     every entries up to 2^19 (P is at least entries + 1 and
//     entries*ln(entries) is under 2^23 there);
//   - it is at least R - 1 for dim >= 2 (R is at most 4095) and, for dim 1,
//     for entries up to 2^19.
// Where the rule is not sure, the answer depends on the C library's last
// bits and the port refuses the codebook.
//
// The correction itself is `(int) floor(pow((float) r+1, dim)) <= entries`:
// a conversion to int of a power that is 2^31 or more when the estimate is
// R and (R+1)^dim is that large, which C leaves undefined (x86-64 makes it
// INT_MIN, and stb_vorbis then answers R + 1). That is every codebook of 31
// dimensions or more, and those of 20 to 23 dimensions whose root is 2: the
// port refuses them too.
//
// This program runs every entries from 1 to 2^24 - 1 (the setup reads 24
// bits) with a list of dimensions and counts: the sure pairs, the sure
// pairs where stb_vorbis answers something else (must be 0), what
// stb_vorbis answers on the unsure ones, and on the undefined ones.
//
// Usage: exhaustive <first> <last> ; prints
//   pairs sure differences unsure unsure_root unsure_minus_one unsure_other
//   undefined undefined_root undefined_above
#include "external/stb_vorbis.c"
#include <stdio.h>
#include <stdlib.h>

// base^dim, or 2^26 from there up.
static unsigned power(unsigned base, unsigned dim)
{
    unsigned long long p = 1;
    if (base <= 1) return base;
    for (unsigned k = 0; k < dim && p < (1u << 26); k++) p *= base;
    return p < (1u << 26)? (unsigned)p : (1u << 26);
}

// The largest r with r^dim <= n, for n from 1 to 2^24 - 1 and dim >= 1.
static unsigned root(unsigned n, unsigned dim)
{
    unsigned r = 0;
    for (unsigned bit = 1u << 23; bit; bit >>= 1) if (power(r | bit, dim) <= n) r |= bit;
    return r;
}

// Whether (r + 1)^dim is 2^31 or more, for the root r of an entries below 2^24.
static int undefined(unsigned dim, unsigned r)
{
    return (r == 1 && dim >= 31) || (r == 2 && dim >= 20);
}

static int sure(unsigned n, unsigned dim, unsigned r)
{
    unsigned p;
    if (n <= (1u << 19)) return 1;
    if (dim == 1) return 0;
    p = power(r + 1, dim);
    if (p >= 2*n) return 1;
    return (p - n) > ((17*p) >> 23);
}

static const unsigned dims[] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 31, 32, 33, 64, 255, 256, 1000, 32767, 32768, 65535 };

int main(int argc, char **argv)
{
    unsigned first = (unsigned)strtoul(argv[1], NULL, 0), last = (unsigned)strtoul(argv[2], NULL, 0);
    unsigned long long pairs = 0, sures = 0, differences = 0, unsure = 0, unsure_root = 0, unsure_minus = 0, unsure_other = 0, undefineds = 0, undefined_root = 0, undefined_above = 0;
    (void)argc;
    for (unsigned n = first; n < last; n++)
        for (unsigned d = 0; d < sizeof(dims)/sizeof(dims[0]); d++)
        {
            unsigned r = root(n, dims[d]);
            int native = lookup1_values((int)n, (int)dims[d]);
            pairs++;
            if (undefined(dims[d], r)) { undefineds++; if (native == (int)r) undefined_root++; else if (native == (int)r + 1) undefined_above++; }
            else if (sure(n, dims[d], r)) { sures++; if (native != (int)r) { differences++; if (differences < 10) fprintf(stderr, "entries %u dim %u: stb %d root %u\n", n, dims[d], native, r); } }
            else { unsure++; if (native == (int)r) unsure_root++; else if (native == -1) unsure_minus++; else unsure_other++; }
        }
    printf("%llu %llu %llu %llu %llu %llu %llu %llu %llu %llu\n", pairs, sures, differences, unsure, unsure_root, unsure_minus, unsure_other, undefineds, undefined_root, undefined_above);
    return 0;
}
