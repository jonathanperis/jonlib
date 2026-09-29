#!/usr/bin/env python3
"""Compare native SHA words, including raylib's SHA-256 padding quirk."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from checksum_probe import fixtures as checksum_fixtures
from conformance import BUILD, ROOT, checkout, run, source_gate


def fixtures():
    original=checksum_fixtures()
    return [c for c in original if c['valid']]+[
        dict(bytes=[(i*73+11)%256 for i in range(n)],valid=True,file=True,profile_length=n) for n in range(128)
    ]+[c for c in original if not c['valid']]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true');args=parser.parse_args()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    work=BUILD/'sha-probe';work.mkdir(parents=True,exist_ok=True);report_path=work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    cases=fixtures();lines=['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>',
        'int main(void){SetTraceLogLevel(LOG_NONE);unsigned char empty=0;']
    for i,case in enumerate(cases):
        path=work/(str(i)+'.dat')
        if case['file']:path.write_bytes(bytes(case['bytes']))
        if not case['valid']:
            lines.append('puts("null");');continue
        lines += [f'{{int n=0;unsigned char *data=LoadFileData({json.dumps(str(path.relative_to(ROOT)))},&n);if(n!={len(case["bytes"])}||(!data&&n))return 2;',
                  'unsigned char *input=n?data:&empty;unsigned *one=ComputeSHA1(input,n);if(!one)return 3;putchar(\'[\');for(int j=0;j<5;j++)printf("%s%u",j?",":"",one[j]);',
                  'unsigned *two=ComputeSHA256(input,n);if(!two)return 4;for(int j=0;j<8;j++)printf(",%u",two[j]);puts("]");UnloadFileData(data);}']
    source=work/'reference.c';source.write_text('\n'.join(lines+['}'])+'\n');binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary]);text=run([binary]);expected=[json.loads(line) for line in text.splitlines()]
    if len(expected)!=len(cases):raise ValueError('Incomplete native SHA output')
    quirks=[];profile_lengths=[]
    for i,(case,row) in enumerate(zip(cases,expected)):
        if not case['valid']:
            if row is not None:raise ValueError('Invalid-input reference control differs')
            continue
        data=bytes(case['bytes']);one=list(struct.unpack('>5I',hashlib.sha1(data).digest()));two=list(struct.unpack('>8I',hashlib.sha256(data).digest()))
        if len(row)!=13 or row[:5]!=one:raise ValueError('Native SHA-1 or digest length differs')
        quirk=56<=len(data)%64<=59
        if (row[5:]!=two)!=quirk:raise ValueError('Native SHA-256 padding profile differs')
        if quirk:
            quirks.append(dict(case=i,bytes=len(data),native=row[5:],standard=two))
            if 'profile_length' in case:profile_lengths.append(case['profile_length'])
        if case.get('profile_length')==56 and struct.pack('>8I',*row[5:]).hex()!='2c5f29559d2cfd998fa1172d913d53fb411003f9c38cf28edd78973119a264ee':
            raise ValueError('Retained native SHA-256 counterexample differs')
    if profile_lengths!=[56,57,58,59,120,121,122,123]:raise ValueError('Native padding counterexample coverage differs')
    report=dict(passed=False,native_cases=sum(c['valid'] for c in cases),input_bytes=sum(len(c['bytes']) for c in cases if c['valid']),
                invalid_controls=sum(not c['valid'] for c in cases),sha256_standard_differences=quirks,profile_counterexample_lengths=profile_lengths,sources=source_gate(),
                inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest(),batch_limit=64,lanes={})
    program='''import Base
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
            if len(rows)!=len(selected):raise ValueError(f'{lane}: incomplete SHA batch {batch}')
            actual.extend(rows);record['phase']='complete';report_path.write_text(json.dumps(report,indent=2)+'\n')
        different=[i for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane].update(passed=actual==expected,different_cases=different);report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:raise ValueError(f'{lane}: SHA differences {different}')
        print(f'{lane}: {report["native_cases"]} native SHA-1/SHA-256 vectors, {len(quirks)} retained native padding differences and {report["invalid_controls"]} controls passed',flush=True)
    report['passed']=True;report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__':
    main()
