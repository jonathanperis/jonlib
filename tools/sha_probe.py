#!/usr/bin/env python3
"""Compare native SHA words, including raylib's SHA-256 padding quirk."""
import hashlib
import json
import struct

from checksum_probe import fixtures as checksum_fixtures
import probekit
from probekit import ROOT, ProbeFailure

PROGRAM = '''import Base
import ../../jonlib.bend as J
def calculate(+bytes: +List<U32>) -> Maybe<&2, +List<U32>> & Maybe<&2, +List<U32>>:
  (J.Checksum.sha1(bytes), J.Checksum.sha256(bytes))
def observed(result: Maybe<&2, +List<U32>> & Maybe<&2, +List<U32>>) -> IO(Unit):
  match result:
    case Tuple{Some{one}, Some{two}}: IO.print(List.show(~&2, ~U32, ~U32.show, List.append(&2, U32, one, two)))
    case Tuple{None{}, None{}}: IO.print("null")
    case _: IO.die(Unit, 1, "SHA acceptance differs")
def loaded(result: Result<&1, &1, J.Image.LoadError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "SHA fixture read failed")
    case Done{bytes}: observed(calculateBANG(bytes))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def fixtures():
    original = checksum_fixtures()
    return [c for c in original if c['valid']] + [
        dict(bytes=[(i*73+11) % 256 for i in range(n)], valid=True, file=True, profile_length=n) for n in range(128)
    ] + [c for c in original if not c['valid']]


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
    return '\n'.join(lines + ['}']) + '\n'


def check_reference(cases, expected):
    """Independently confirm the native oracle: standard SHA-1, and SHA-256 equal to
    the standard digest except for the pinned dataSize+4 padding rule (56..59 mod 64)."""
    quirks, profile_lengths = [], []
    for i, (case, row) in enumerate(zip(cases, expected)):
        if not case['valid']:
            if row is not None:
                raise ProbeFailure('Invalid-input reference control differs')
            continue
        data = bytes(case['bytes'])
        one, two = list(struct.unpack('>5I', hashlib.sha1(data).digest())), list(struct.unpack('>8I', hashlib.sha256(data).digest()))
        if len(row) != 13 or row[:5] != one:
            raise ProbeFailure('Native SHA-1 or digest length differs')
        quirk = 56 <= len(data) % 64 <= 59
        if (row[5:] != two) != quirk:
            raise ProbeFailure('Native SHA-256 padding profile differs')
        if quirk:
            quirks.append(i)
            if 'profile_length' in case:
                profile_lengths.append(case['profile_length'])
        if case.get('profile_length') == 56 and struct.pack('>8I', *row[5:]).hex() != '2c5f29559d2cfd998fa1172d913d53fb411003f9c38cf28edd78973119a264ee':
            raise ProbeFailure('Retained native SHA-256 counterexample differs')
    if profile_lengths != [56, 57, 58, 59, 120, 121, 122, 123]:
        raise ProbeFailure('Native padding counterexample coverage differs')
    return quirks


def main():
    probe = probekit.Probe('sha', probekit.arguments(__doc__))
    cases = fixtures()
    text = probe.native(reference_program(cases, probe.work))
    expected = [json.loads(line) for line in text.splitlines()]
    if len(expected) != len(cases):
        raise ProbeFailure('Incomplete native SHA output')
    quirks = check_reference(cases, expected)
    indexed = list(enumerate(cases))

    def render(selected, gpu):
        bang = '!' if gpu else ''
        body = PROGRAM.replace('BANG', bang)
        for i, case in selected:
            if case['file']:
                path = json.dumps(str((probe.work/f'{i}.dat').relative_to(ROOT)))
                body += f'    IO.bind(Result<&1, &1, J.Image.LoadError, +List<U32>>, Unit, J.Image.file.bytes({path}, 2097152), loaded)\n'
            else:
                body += f'    observed(calculate{bang}({probekit.bend_list(case["bytes"])}))\n'
        return body

    probe.compare(expected, probe.candidates(render, indexed, batch=64))
    probe.finish(native_cases=sum(c['valid'] for c in cases), invalid_controls=sum(not c['valid'] for c in cases),
                 padding_differences=len(quirks), reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
