#!/usr/bin/env python3
"""Compare the private PNG quality-8 compressor byte-for-byte with linked stb."""
import hashlib
import json
import random

from byte_probe import BEND_EMITTER, parse_results
from conformance import source_gate
import probekit
from probekit import ProbeFailure

PROGRAM = '''import Base
import ../../src/deflate.bend as D
import ../../src/formats.bend as F
'''+BEND_EMITTER+'''def fill(bytes: +List<U32>, +at: U32, input: Array<U32>) -> Array<U32>:
  match bytes:
    case Nil{}: input
    case Con{byte, rest}: fill(rest, (at + 1 : U32), Array.set(U32, input, at, byte))
def checked(valid: Bool, +size: U32, bytes: +List<U32>) -> Maybe<&2, D.Stream>:
  match valid:
    case False{}: None{}
    case True{}:
      depth = Bool.pick(Nat, (size <= 1 : U32), 0n, 1n+U32.log2((size - 1 : U32)))
      Some{D.compress(size, fill(bytes, 0, Array.new(U32, depth, 0)))}
def compressed(+size: U32, +bytes: +List<U32>) -> Maybe<&2, D.Stream>:
  checked(F.valid(bytes, size, True{}), size, bytes)
def emit(result: Maybe<&2, D.Stream>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "incomplete compressor input")
    case Some{D.Stream{+size, bytes}}:
      emit_bytes(~&2, Con{(size >> 24n : U32), Con{((size >> 16n) .&. 255 : U32), Con{((size >> 8n) .&. 255 : U32), Con{(size .&. 255 : U32), bytes}}}})
def payload(size: U32, result: Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "compressor fixture read failed")
    case Done{bytes}: emit(compressedBANG(size, bytes))
def received(size: U32, result: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  (file, status) = result
  do IO<Unit>:
    Unit <- File.close(file)
    payload(size, status)
def opened(+size: U32, result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "compressor fixture open failed")
    case Done{file}: IO.bind(File & Result<&1, &1, U32 & String, +List<U32>>, Unit, File.read_bytes(file, size), received(size))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def fixtures():
    rng=random.Random(0xdef1a7e)
    cases=[('empty',b''),('one',b'A'),('two',b'AB'),('three',b'AAA'),('four',b'AAAA'),
           ('alphabet',bytes(range(256))*2),('run259',b'A'*259),('run260',b'A'*260),
           ('lazy',b'abcdx'+b'bcdefghijklmnopqrstuvwxyz'+b'abcdefghijklmnopqrstuvwxyzz'),
           ('bucket-eviction',b''.join(b'abc'+i.to_bytes(2,'little') for i in range(96))*2)]
    for distance in (32767,32768):
        base=b'\xfa\xfb\xfc'+b'A'*(distance-3)
        cases.append((f'window-{distance}',base+base[:258]))
    for size in (5552,32766,32767,32768,65534):
        cases.append((f'random-{size}',bytes(rng.randrange(256) for _ in range(size))))
    return cases


def reference_program(cases, work):
    lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
           'unsigned char *stbi_zlib_compress(unsigned char*,int,int*,int);',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for name,data in cases:
        path=work/f'{name}.data';path.write_bytes(data)
        lines += ['{',f'FILE *file=fopen({json.dumps(str(path))},"rb");if(!file)return 1;',
                  f'unsigned char *data=malloc({max(1,len(data))});if(fread(data,1,{len(data)},file)!={len(data)})return 2;fclose(file);',
                  f'int size=0;unsigned char *out=stbi_zlib_compress(data,{len(data)},&size,8);if(!out)return 3;',
                  'printf("[%u,%u,%u,%u",(unsigned)size>>24,((unsigned)size>>16)&255,((unsigned)size>>8)&255,(unsigned)size&255);',
                  'for(int i=0;i<size;i++)printf(",%u",out[i]);puts("]");free(data);MemFree(out);','}']
    return '\n'.join(lines+['}'])+'\n'


def main():
    probe=probekit.Probe('deflate',probekit.arguments(__doc__))
    probe.report['sources']=source_gate()
    cases=fixtures()
    text=probe.native(reference_program(cases,probe.work));expected=[json.loads(line) for line in text.splitlines()]
    if len(expected)!=len(cases) or any(int.from_bytes(bytes(row[:4]),'big')!=len(row)-4 for row in expected):raise ProbeFailure('Incomplete native compressor results')

    def render(selected,gpu):
        body=PROGRAM.replace('BANG','!' if gpu else '')
        for name,data in selected:
            body+=f'    IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open({json.dumps(str(probe.work/f"{name}.data"))}, "r"), opened({len(data)}))\n'
        return body

    # One program holds every stream, as before.
    probe.compare(expected,probe.candidates(render,cases,batch=len(cases),parse=lambda out,selected:parse_results(out)),
                  describe=lambda index:f'stream {cases[index][0]}')
    probe.finish(cases=len(cases),input_bytes=sum(len(data) for _,data in cases),encoded_bytes=sum(len(row)-4 for row in expected),
                 inputs_sha256=hashlib.sha256(b''.join(len(data).to_bytes(4,'big')+data for _,data in cases)).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())

if __name__=='__main__':
    main()
