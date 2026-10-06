#!/usr/bin/env python3
"""Retain native perspective/tangent rounding evidence; this is not a parity gate."""
from decimal import Decimal, localcontext
import platform

import probekit

REFERENCE = '''/* Reference formulas from pinned raymath.h; zlib, LICENSES/raylib.txt. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
#define RAYMATH_STATIC_INLINE
#include "raymath.h"
static uint64_t bits64(double value) { uint64_t bits; memcpy(&bits,&value,8); return bits; }
static uint32_t bits32(float value) { uint32_t bits; memcpy(&bits,&value,4); return bits; }
int main(void) {
  volatile double input_fov=FOV,input_near=NEAR;
  double fov=input_fov,near=input_near;
  Matrix native=MatrixPerspective(fov,1.0,near,1000.0);
  double tangent=tan(fov*0.5),accurate=ACCURATE;
  double top=near*accurate,bottom=-top;
  float span=(float)(top-bottom);
  float scale=((float)near*2.0f)/span;
  printf("%llu %llu %u %u\\n",(unsigned long long)bits64(tangent),(unsigned long long)bits64(accurate),bits32(native.m5),bits32(scale));
}
'''


def accurate_tangent(value):
    with localcontext() as context:
        context.prec = 90
        x = Decimal.from_float(value)
        square = x*x
        sine = sine_term = x
        cosine = cosine_term = Decimal(1)
        for index in range(1,48):
            sine_term = -sine_term*square/Decimal((2*index)*(2*index+1))
            cosine_term = -cosine_term*square/Decimal((2*index-1)*(2*index))
            sine += sine_term
            cosine += cosine_term
        return float(sine/cosine)


def main():
    probe = probekit.Probe('perspective',probekit.arguments(__doc__,bend=False))
    fov = float.fromhex('0x1.caac02dacfefep+0')
    near = float.fromhex('0x1.99c7240652e10p-2')
    candidate = accurate_tangent(fov*0.5)
    # Header-only raymath: compiled against the pinned headers, not linked with the library.
    text = probe.native(REFERENCE.replace('FOV',fov.hex()).replace('NEAR',near.hex()).replace('ACCURATE',candidate.hex()),link_raylib=False)
    native_tan,accurate_tan,native_scale,accurate_scale = map(int,text.split())
    probe.diagnostic(probe_completed=True,candidate_passed=native_scale==accurate_scale,
                     reference_revision=probe.lock['raylib']['revision'],
                     host=dict(system=platform.system(),machine=platform.machine()),
                     fov_hex=fov.hex(),near_hex=near.hex(),aspect=1.0,far=1000.0,
                     native_tangent_bits=f'{native_tan:016x}',accurate_tangent_bits=f'{accurate_tan:016x}',
                     native_m5_bits=f'{native_scale:08x}',accurate_m5_bits=f'{accurate_scale:08x}',
                     candidate='90-digit sine/cosine series, rounded to binary64 before reference matrix arithmetic',
                     scope='One retained counterexample; not an implementation or full-domain proof')
    print(f'Perspective diagnostic: native m5={native_scale:08x}, high-precision candidate={accurate_scale:08x}; candidate match={native_scale==accurate_scale}')


if __name__ == '__main__':
    main()
