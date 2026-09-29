#!/usr/bin/env python3
"""Compare complete native CRC32/MD5 words and independent standard digests."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import struct
import zlib

from conformance import BUILD, ROOT, checkout, run, source_gate


def fixtures():
    rng=random.Random(0x68617368)
    messages=[bytes([i]) for i in range(256)]
    messages += [b'',b'abc',b'message digest',b'The quick brown fox jumps over the lazy dog',bytes(range(256))]
    for size in (55,56,57,63,64,65,119,120,127,128,129,255,256,257,4095,4096,4097,65535,65536,1048576):
        messages.append(bytes(rng.randrange(256) for _ in range(size)))
    return [dict(bytes=list(data),valid=True,file=True) for data in messages]+[
        dict(bytes=[256],valid=False,file=False),dict(bytes=[0,4294967295],valid=False,file=False),
        dict(bytes=[0]*1048577,valid=False,file=True)]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'checksum-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases=fixtures();lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
        'int main(void){SetTraceLogLevel(LOG_NONE);unsigned char empty=0;']
    for i,case in enumerate(cases):
        path=work/(str(i)+'.dat')
        if case['file']:path.write_bytes(bytes(case['bytes']))
        if not case['valid']:
            lines.append('puts("null");');continue
        lines += [f'{{int n=0;unsigned char *data=LoadFileData({json.dumps(str(path.relative_to(ROOT)))},&n);if(n!={len(case["bytes"])}||(!data&&n))return 2;',
                  'unsigned char *input=n?data:&empty;unsigned crc=ComputeCRC32(input,n);unsigned *digest=ComputeMD5(input,n);if(!digest)return 3;',
                  'printf("[%u,%u,%u,%u,%u]\\n",crc,digest[0],digest[1],digest[2],digest[3]);UnloadFileData(data);}']
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=[json.loads(line) for line in text.splitlines()]
    if len(expected)!=len(cases):raise ValueError('Incomplete native checksum output')
    for case,row in zip(cases,expected):
        if not case['valid']:
            if row is not None:raise ValueError('Invalid-input reference control differs')
            continue
        data=bytes(case['bytes']);standard=[zlib.crc32(data),*struct.unpack('<4I',hashlib.md5(data).digest())]
        if row!=standard:raise ValueError('Native checksum differs from standard digest profile')
    report=dict(passed=False,native_cases=sum(c['valid'] for c in cases),input_bytes=sum(len(c['bytes']) for c in cases if c['valid']),
                single_byte_vectors=256,invalid_controls=sum(not c['valid'] for c in cases),sources=source_gate(),
                inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),batch_limit=64,lanes={})
    program='''import Base
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
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        actual=[];report['lanes'][lane]=dict(passed=False,batches=[])
        for batch,start in enumerate(range(0,len(cases),64)):
            selected=cases[start:start+64];body=program.replace('BANG','!' if lane=='metal' else '')
            for i,case in enumerate(selected,start):
                if case['file']:
                    path=json.dumps(str((work/(str(i)+'.dat')).relative_to(ROOT)))
                    body+=f'    IO.bind(Result<&1, &1, J.Image.LoadError, +List<U32>>, Unit, J.Image.file.bytes({path}, 2097152), loaded)\n'
                else:body+='    observed(calculate'+('!' if lane=='metal' else '')+'(['+', '.join(map(str,case['bytes']))+']))\n'
            record=dict(start=start,cases=len(selected),phase='compile');report['lanes'][lane]['batches'].append(record);report_path.write_text(json.dumps(report,indent=2)+'\n')
            source=work/f'{lane}-{batch}.bend';source.write_text(body);binary=work/(f'{lane}-{batch}.js' if lane=='javascript' else f'{lane}-{batch}')
            run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
            record['phase']='run';report_path.write_text(json.dumps(report,indent=2)+'\n')
            command=['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
            rows=[json.loads(line) for line in run(command).splitlines()]
            if len(rows)!=len(selected):raise ValueError(f'{lane}: incomplete checksum batch {batch}')
            actual.extend(rows);record['phase']='complete';report_path.write_text(json.dumps(report,indent=2)+'\n')
        different=[i for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane].update(passed=actual==expected,different_cases=different);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: checksum differences {different}')
        print(f'{lane}: {report["native_cases"]} native/standard CRC32 and MD5 vectors and {report["invalid_controls"]} controls passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
