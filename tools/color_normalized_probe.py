#!/usr/bin/env python3
"""Compare ColorFromNormalized where the C cast is defined.

Each component is multiplied by 255 in F32. The cast to unsigned char is
defined when that product is finite and lies in [0, 256). Subnormals, signed
zero and components outside 0..1 are included when the product stays in that
interval. A negative, non-finite or out-of-range product is undefined in C
and is not a case. Every byte is compared on CPU-1, CPU-2 and JavaScript.
"""
import hashlib
import json
import math
import struct

import probekit
from probekit import ProbeFailure

# Products are finite and in [0, 256): zeros, a subnormal, the least normal,
# a fraction below 1, one half, the float just below 1, 1, one ulp above 1,
# and the greatest component whose product is still below 256.
DEFINED = (
    0x00000000, 0x80000000,
    0x00000001, 0x00800000,
    0x3b805f9b,
    0x3f000000, 0x3f7fffff,
    0x3f800000, 0x3f800001,
    0x3f808080,
)


def product(bits):
    value = struct.unpack('<f', struct.pack('<I', bits & 0xffffffff))[0]
    try:
        packed = struct.pack('<f', value * 255.0)
    except OverflowError:
        return None
    result = struct.unpack('<f', packed)[0]
    if math.isfinite(result) and 0.0 <= result < 256.0:
        return result
    return None


def cases():
    for word in DEFINED:
        if product(word) is None:
            raise ProbeFailure(f'color-normalized: word {word} is outside the defined cast')
    anchors = (
        (0x00000000, 0x00000000, 0x00000000, 0x3f800000),
        (0x3f800000, 0x3f800000, 0x3f800000, 0x3f800000),
        (0x3f000000, 0x3f7fffff, 0x3f800001, 0x3f808080),
        (0x00000001, 0x00800000, 0x80000000, 0x3b805f9b),
    )
    rows, seen = [], set()

    def add(words):
        if words not in seen:
            seen.add(words)
            rows.append(words)

    for anchor in anchors:
        add(anchor)
        for index in range(4):
            for word in DEFINED:
                changed = list(anchor)
                changed[index] = word
                add(tuple(changed))
    for word in DEFINED:
        add((word, word, word, word))
    return rows


def native(probe, rows):
    lines = [
        '#include "raylib.h"', '#include <stdio.h>', '#include <string.h>',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,&u,4); sink+=u; return x;}',
        'int main(void){SetTraceLogLevel(LOG_NONE);',
    ]
    for words in rows:
        args = ','.join(f'load({word})' for word in words)
        lines.append(
            '{Color c=ColorFromNormalized((Vector4){' + args + '});'
            'printf("%u\\n",(unsigned)c.r<<24|(unsigned)c.g<<16|(unsigned)c.b<<8|c.a);}'
        )
    lines.append('(void)sink; return 0;}')
    return probe.native('\n'.join(lines) + '\n')


PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def word(bits: U32) -> F32:
  U32{b} = bits
  F32{b}
def main() -> IO(Unit):
  do IO<Unit>:
'''


def render(selected, gpu):
    body = PROGRAM
    for words in selected:
        fields = ', '.join(f'word({word})' for word in words)
        body += f'    IO.print(U32.show(J.Color.from_normalized(M.Vector4{{{fields}}})))\n'
    return body


def main():
    probe = probekit.Probe('color-normalized', probekit.arguments(__doc__))
    rows = cases()
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'color-normalized: native produced {len(expected)} rows for {len(rows)} cases')
    lanes = probe.candidates(render, rows, batch=200)
    probe.compare(expected, lanes, lambda index: str(tuple(hex(word) for word in rows[index])))
    probe.finish(cases=len(rows),
                 inputs_sha256=hashlib.sha256(json.dumps(rows).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
