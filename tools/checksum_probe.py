#!/usr/bin/env python3
"""Compare complete native CRC32/MD5 words and independent standard digests."""
import hashlib
import json
import random
import struct
import zlib

from conformance import source_gate
import probekit
from probekit import ROOT, ProbeFailure

PROGRAM = '''import Base
import ../../jonlib.bend as J
def calculate(+bytes: +List<U32>) -> Maybe<&2, U32> & Maybe<&2, +List<U32>>:
  (J.Checksum.crc32(bytes), J.Checksum.md5(bytes))
def observed(result: Maybe<&2, U32> & Maybe<&2, +List<U32>>) -> IO(Unit):
  match result:
    case Tuple{Some{crc}, Some{words}}: IO.print(List.show(~&2, ~U32, ~U32.show, Con{crc, words}))
    case Tuple{None{}, None{}}: IO.print("null")
    case _: IO.die(Unit, 1, "checksum acceptance differs")
def loaded(result: Result<&1, &1, J.Image.LoadError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "checksum fixture read failed")
    case Done{bytes}: observed(calculateBANG(bytes))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def fixtures():
    rng=random.Random(0x68617368)
    messages=[bytes([i]) for i in range(256)]
    messages += [b'',b'abc',b'message digest',b'The quick brown fox jumps over the lazy dog',bytes(range(256))]
    for size in (55,56,57,63,64,65,119,120,127,128,129,255,256,257,4095,4096,4097,65535,65536,1048576):
        messages.append(bytes(rng.randrange(256) for _ in range(size)))
    return [dict(bytes=list(data),valid=True,file=True) for data in messages]+[
        dict(bytes=[256],valid=False,file=False),dict(bytes=[0,4294967295],valid=False,file=False),
        dict(bytes=[0]*1048577,valid=False,file=True)]


def reference_program(cases, work):
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'int main(void){SetTraceLogLevel(LOG_NONE);unsigned char empty=0;']
    for i,case in enumerate(cases):
        if case['file']:(work/f'{i}.dat').write_bytes(bytes(case['bytes']))
        if not case['valid']:
            lines.append('puts("null");');continue
        lines += [f'{{int n=0;unsigned char *data=LoadFileData({json.dumps(str((work/f"{i}.dat").relative_to(ROOT)))},&n);if(n!={len(case["bytes"])}||(!data&&n))return 2;',
                  'unsigned char *input=n?data:&empty;unsigned crc=ComputeCRC32(input,n);unsigned *digest=ComputeMD5(input,n);if(!digest)return 3;',
                  'printf("[%u,%u,%u,%u,%u]\\n",crc,digest[0],digest[1],digest[2],digest[3]);UnloadFileData(data);}']
    return '\n'.join(lines+['}'])+'\n'


def check_reference(cases, expected):
    """Independently confirm the native oracle against zlib CRC32 and hashlib MD5."""
    if len(expected)!=len(cases):raise ProbeFailure('Incomplete native checksum output')
    for case,row in zip(cases,expected):
        if not case['valid']:
            if row is not None:raise ProbeFailure('Invalid-input reference control differs')
            continue
        data=bytes(case['bytes']);standard=[zlib.crc32(data),*struct.unpack('<4I',hashlib.md5(data).digest())]
        if row!=standard:raise ProbeFailure('Native checksum differs from standard digest profile')


def main():
    probe=probekit.Probe('checksum',probekit.arguments(__doc__))
    probe.report['sources']=source_gate()
    cases=fixtures()
    text=probe.native(reference_program(cases,probe.work));expected=[json.loads(line) for line in text.splitlines()]
    check_reference(cases,expected)

    def render(selected,gpu):
        bang='!' if gpu else '';body=PROGRAM.replace('BANG',bang)
        for i,case in selected:
            if case['file']:
                path=json.dumps(str((probe.work/f'{i}.dat').relative_to(ROOT)))
                body+=f'    IO.bind(Result<&1, &1, J.Image.LoadError, +List<U32>>, Unit, J.Image.file.bytes({path}, 2097152), loaded)\n'
            else:body+=f'    observed(calculate{bang}({probekit.bend_list(case["bytes"])}))\n'
        return body

    probe.compare(expected,probe.candidates(render,list(enumerate(cases)),batch=64))
    probe.finish(native_cases=sum(c['valid'] for c in cases),input_bytes=sum(len(c['bytes']) for c in cases if c['valid']),
                 single_byte_vectors=256,invalid_controls=sum(not c['valid'] for c in cases),
                 inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
