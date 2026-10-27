#!/usr/bin/env python3
"""Compare native SHA words: standard SHA-1 and SHA-256 (raylib 6.2 fixed the
SHA-256 padding that 6.0 sized with dataSize + 4)."""
import hashlib
import json
import struct

from checksum_probe import fixtures as checksum_fixtures
import probekit
from probekit import ROOT, ProbeFailure

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../src/sha.bend as Sha
def calculate(+bytes: +List<U32>) -> Maybe<&2, +List<U32>> & Maybe<&2, +List<U32>>:
  (J.Checksum.sha1_wide(bytes), J.Checksum.sha256_wide(bytes))
def shown(words: U32 & U32) -> IO(Unit):
  (high, low) = words
  IO.print(List.show(~&1, ~U32, ~U32.show, [high, low]))
def bits(+length: U32) -> IO(Unit):
  shown(Sha.bit_length.words(length))
def observed(result: Maybe<&2, +List<U32>> & Maybe<&2, +List<U32>>) -> IO(Unit):
  match result:
    case Tuple{Some{one}, Some{two}}: IO.print(List.show(~&2, ~U32, ~U32.show, List.append(&2, U32, one, two)))
    case Tuple{None{}, None{}}: IO.print("null")
    case _: IO.die(Unit, 1, "SHA acceptance differs")
def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "SHA fixture read failed")
    case Done{bytes}: observed(calculateBANG(bytes))
def main() -> IO(Unit):
  do IO<Unit>:
'''


# Lengths whose 8*length high word is zero, the first length that carries, and both
# signed-size ends. These rows compare the stored halves, not a multi-gigabyte digest.
BIT_LENGTHS = (0, 1, 55, 56, 63, 64, 1048576, 1048577, 536870911, 536870912, 2147483575, 2147483647)


def fixtures():
    original = checksum_fixtures()
    return [c for c in original if c['valid']] + [
        dict(bytes=[(i*73+11) % 256 for i in range(n)], valid=True, file=True, profile_length=n) for n in range(128)
    ] + [c for c in original if not c['valid']]


def bit_words(length):
    bits = 8 * length
    return [(bits >> 32) & 0xFFFFFFFF, bits & 0xFFFFFFFF]


def reference_program(cases, work):
    lines = ['#include "raylib.h"', '#include <stdio.h>', '#include <stdlib.h>',
             'int main(void){SetTraceLogLevel(LOG_NONE);unsigned char empty=0;']
    for i, case in enumerate(cases):
        if case['file']:
            (work/f'{i}.dat').write_bytes(bytes(case['bytes']))
        if not case['valid']:
            lines.append('puts("null");')
            continue
        path = json.dumps(str((work/f'{i}.dat').relative_to(ROOT)))
        lines += [f'{{int n=0;unsigned char *data=LoadFileData({path},&n);if(n!={len(case["bytes"])}||(!data&&n))return 2;',
                  'unsigned char *input=n?data:&empty;unsigned *one=ComputeSHA1(input,n);if(!one)return 3;putchar(\'[\');for(int j=0;j<5;j++)printf("%s%u",j?",":"",one[j]);',
                  'unsigned *two=ComputeSHA256(input,n);if(!two)return 4;for(int j=0;j<8;j++)printf(",%u",two[j]);puts("]");UnloadFileData(data);}']
    for length in BIT_LENGTHS:
        lines.append(f'{{unsigned long long bitsLen=8ULL*{length};printf("[%u,%u]\\n",(unsigned)(bitsLen>>32),(unsigned)bitsLen);}}')
    return '\n'.join(lines + ['}']) + '\n'


def check_reference(cases, expected):
    """Independently confirm the native oracle: standard SHA-1 and SHA-256 for every
    length, including 56..59 mod 64, where raylib 6.0's padding differed."""
    for case, row in zip(cases, expected):
        if not case['valid']:
            if row is not None:
                raise ProbeFailure('Invalid-input reference control differs')
            continue
        data = bytes(case['bytes'])
        one, two = list(struct.unpack('>5I', hashlib.sha1(data).digest())), list(struct.unpack('>8I', hashlib.sha256(data).digest()))
        if len(row) != 13 or row[:5] != one:
            raise ProbeFailure('Native SHA-1 or digest length differs')
        if row[5:] != two:
            raise ProbeFailure('Native SHA-256 differs from the standard digest')
        if case.get('profile_length') == 56 and struct.pack('>8I', *row[5:]).hex() != hashlib.sha256(data).hexdigest():
            raise ProbeFailure('Native SHA-256 at the old padding edge differs')


def main():
    probe = probekit.Probe('sha', probekit.arguments(__doc__))
    cases = fixtures()
    text = probe.native(reference_program(cases, probe.work))
    rows = [json.loads(line) for line in text.splitlines()]
    if len(rows) != len(cases) + len(BIT_LENGTHS):
        raise ProbeFailure('Incomplete native SHA output')
    expected, bits = rows[:len(cases)], rows[len(cases):]
    check_reference(cases, expected)
    if bits != [bit_words(length) for length in BIT_LENGTHS]:
        raise ProbeFailure('Native SHA bit-length words differ')
    indexed = list(enumerate(cases)) + [('bits', length) for length in BIT_LENGTHS]

    def render(selected, gpu):
        bang = '!' if gpu else ''
        body = PROGRAM.replace('BANG', bang)
        for item in selected:
            if item[0] == 'bits':
                body += f'    bits({item[1]})\n'
                continue
            i, case = item
            if case['file']:
                path = json.dumps(str((probe.work/f'{i}.dat').relative_to(ROOT)))
                body += f'    IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Image.file.bytes({path}, 2097152), loaded)\n'
            else:
                body += f'    observed(calculate{bang}({probekit.bend_list(case["bytes"])}))\n'
        return body

    probe.compare(rows, probe.candidates(render, indexed, batch=64))
    probe.finish(native_cases=sum(c['valid'] for c in cases), invalid_controls=sum(not c['valid'] for c in cases),
                 padding_edge_lengths=8, bit_lengths=len(BIT_LENGTHS),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
