#!/usr/bin/env python3
"""Compare ColorFromHSV where every channel cast is defined.

Each channel is k = fmodf(offset + hue/60, 6), then raylib's clamps, then
(unsigned char)((value - value*saturation*k)*255). The cast is defined when
that product is finite and lies in (-1, 256). Hues outside -32767..32767,
non-finite hues (a non-finite fmod makes every comparison fail, so k becomes
1) and saturation/value outside 0..1 are included when all three products stay
in the interval. A product outside it is undefined in C and is not a case.
"""
import hashlib
import json
import struct

import probekit
from probekit import ProbeFailure


def bits(value):
    return struct.unpack('<I', struct.pack('<f', float(value)))[0]


# Finite hues through the old corpus edge, then past it, then non-finite.
HUES = (
    0.0, -0.0, 1.0, 59.0, 60.0, 61.0, 120.0, 180.0, 240.0, 300.0,
    359.0, 360.0, -360.0, 32767.0, -32767.0, 32768.0, -32768.0,
    1.0e6, -1.0e6, 1.0e10, -1.0e10,
    struct.unpack('<f', struct.pack('<I', 0x7f7fffff))[0],
    struct.unpack('<f', struct.pack('<I', 0xff7fffff))[0],
    float('inf'), float('-inf'), float('nan'),
)
SATURATIONS = (0.0, -0.0, 0.25, 0.5, 1.0, 1.5, 2.0, -0.25, -1.0)
VALUES = (0.0, -0.0, 0.25, 0.5, 1.0, 1.001, 2.0, -0.001, -0.5, 0.003)


def candidates():
    rows, seen = [], set()

    def add(hue, saturation, value):
        triple = (bits(hue), bits(saturation), bits(value))
        if triple not in seen:
            seen.add(triple)
            rows.append(triple)

    for hue in HUES:
        for saturation in (0.0, 0.5, 1.0):
            for value in (0.0, 0.5, 1.0):
                add(hue, saturation, value)
    for hue in (0.0, 60.0, 180.0, 1.0e6, float('inf'), float('nan'), 32768.0, -32768.0):
        for saturation in SATURATIONS:
            for value in VALUES:
                add(hue, saturation, value)
    return rows


def native(probe, rows):
    lines = [
        '#include "raylib.h"',
        '#include <math.h>',
        '#include <stdio.h>',
        '#include <string.h>',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,&u,4); sink+=u; return x;}',
        # Uncontracted channel product. Defined when it is finite and in (-1, 256).
        'static int channel_defined(float hue, float saturation, float value, float offset) {',
        '  float phase = offset + hue/60.0f;',
        '  float k = fmodf(phase, 6.0f);',
        '  float t = 4.0f - k;',
        '  k = (t < k) ? t : k;',
        '  k = (k < 1.0f) ? k : 1.0f;',
        '  k = (k > 0.0f) ? k : 0.0f;',
        '  volatile float factor = value * saturation;',
        '  volatile float scaled_k = factor * k;',
        '  volatile float delta = value - scaled_k;',
        '  volatile float scaled = delta * 255.0f;',
        '  return isfinite(scaled) && scaled > -1.0f && scaled < 256.0f;',
        '}',
        'int main(void){SetTraceLogLevel(LOG_NONE);',
    ]
    for hue, saturation, value in rows:
        lines.append(
            '{float h=load(%u), s=load(%u), v=load(%u);'
            'if(channel_defined(h,s,v,5.0f)&&channel_defined(h,s,v,3.0f)&&channel_defined(h,s,v,1.0f)){'
            'Color c=ColorFromHSV(h,s,v);'
            'printf("1 %%u\\n",(unsigned)c.r<<24|(unsigned)c.g<<16|(unsigned)c.b<<8|c.a);'
            '}else printf("0\\n");}' % (hue, saturation, value)
        )
    lines.append('(void)sink; return 0;}')
    return probe.native('\n'.join(lines) + '\n', extra_flags=('-ffp-contract=off',))


def defined_rows(rows, text):
    lines = [line for line in text.splitlines() if line.strip()]
    if len(lines) != len(rows):
        raise ProbeFailure(f'color-hsv: native produced {len(lines)} rows for {len(rows)} candidates')
    kept = []
    for triple, line in zip(rows, lines):
        kind, _, color = line.partition(' ')
        if kind == '1':
            kept.append((triple, int(color)))
        elif kind != '0':
            raise ProbeFailure(f'color-hsv: unexpected native row {line!r}')
    if len(kept) < 64:
        raise ProbeFailure(f'color-hsv: only {len(kept)} defined casts')
    wide = [item for item in kept if item[0][0] not in {bits(v) for v in HUES if abs(v) <= 32767 and math_isfinite(v)}]
    if len(wide) < 16:
        raise ProbeFailure(f'color-hsv: only {len(wide)} casts outside the old hue corpus')
    return kept


def math_isfinite(value):
    return value == value and value not in (float('inf'), float('-inf'))


PROGRAM = '''import Base
import ../../jonlib.bend as J
def word(bits: U32) -> F32:
  U32{b} = bits
  F32{b}
def main() -> IO(Unit):
  do IO<Unit>:
'''


def render(selected, gpu):
    body = PROGRAM
    for (hue, saturation, value), _color in selected:
        body += f'    IO.print(U32.show(J.Color.from_hsv(word({hue}), word({saturation}), word({value}))))\n'
    return body


def main():
    probe = probekit.Probe('color-hsv', probekit.arguments(__doc__))
    rows = candidates()
    kept = defined_rows(rows, native(probe, rows))
    expected = [color for _triple, color in kept]
    lanes = probe.candidates(render, kept, batch=120)
    probe.compare(expected, lanes, lambda index: str(tuple(hex(word) for word in kept[index][0])))
    probe.finish(cases=len(kept),
                 candidates=len(rows),
                 inputs_sha256=hashlib.sha256(json.dumps([triple for triple, _color in kept]).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(json.dumps(expected).encode()).hexdigest())


if __name__ == '__main__':
    main()
