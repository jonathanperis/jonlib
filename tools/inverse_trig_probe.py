#!/usr/bin/env python3
"""Record Base inverse-trig differences from native float libm without claiming parity."""
import argparse
import json
from pathlib import Path
import platform
import random
import struct

from conformance import BUILD, ROOT, checkout, f32, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true')
    args = parser.parse_args()
    lock = json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    work = BUILD/'inverse-trig-probe';work.mkdir(parents=True,exist_ok=True)
    report_path = work/'results.json'
    report_path.write_text(json.dumps(dict(probe_completed=False,candidate_passed=False))+'\n')
    values = [-1.0,-0.0,0.0,1.0]
    for boundary in (0.5,0.57,0.62,0.975,1.0):
        bits = struct.unpack('I',struct.pack('f',boundary))[0]
        for adjacent in (bits-1,bits,bits+1):
            value = struct.unpack('f',struct.pack('I',adjacent))[0]
            if value<=1:values += [value,-value]
    rng = random.Random(0xA51C05)
    values += [struct.unpack('f',struct.pack('f',rng.uniform(-1,1)))[0] for _ in range(256)]
    values = list({struct.unpack('I',struct.pack('f',value))[0]:value for value in values}.values())
    source = work/'reference.c'
    source.write_text('#include <math.h>\n#include <stdio.h>\n#include <string.h>\n'+
        'static float (*volatile native_asin)(float)=asinf;static float (*volatile native_acos)(float)=acosf;\n'+
        'static const float values[]={'+','.join(value.hex()+'f' for value in values)+'};\n'+
        'static unsigned word(float value){unsigned bits;memcpy(&bits,&value,4);return bits;}\n'+
        'int main(void){for(unsigned i=0;i<sizeof(values)/sizeof(values[0]);i++)printf("%u %u\\n",word(native_asin(values[i])),word(native_acos(values[i])));}\n')
    run(['clang','-std=c11','-O2',source,'-lm','-o',work/'reference'])
    expected = [int(word) for word in run([work/'reference']).split()]
    if len(expected)!=2*len(values):raise ValueError('Incomplete inverse-trig reference')
    report = dict(probe_completed=False,candidate_passed=False,samples=len(values),
                  host=dict(system=platform.system(),machine=platform.machine(),libc=platform.libc_ver()),lanes={})
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        source = work/f'{lane}.bend'
        program = '''import Base
def calculate(values: +List<F32>) -> List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}: Con{F32.bits(F32.asin(value)), Con{F32.bits(F32.acos(value)), calculate(rest)}}
def main() -> IO(Unit):
  do IO<Unit>:
'''
        for start in range(0,len(values),32):
            program += f'    IO.print(List.show(~&1, ~U32, ~U32.show, calculate{"!" if lane=="metal" else ""}(['+','.join(f32(value) for value in values[start:start+32])+'])))\n'
        source.write_text(program)
        binary = work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary])
        command = ['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual = [word for line in run(command).splitlines() for word in json.loads(line)]
        if len(actual)!=len(expected):raise ValueError(f'{lane}: incomplete inverse-trig candidate')
        differences = [dict(function='asin' if index%2==0 else 'acos',input=values[index//2],
                            reference=f'{reference:08x}',candidate=f'{candidate:08x}')
                       for index,(reference,candidate) in enumerate(zip(expected,actual)) if reference!=candidate]
        report['lanes'][lane] = dict(candidate_passed=not differences,mismatch_count=len(differences),differences=differences[:16])
        print(f'{lane}: inverse-trig diagnostic {len(differences)} mismatches in {len(expected)} result words',flush=True)
        report_path.write_text(json.dumps(report,indent=2)+'\n')
    report['probe_completed'] = True
    report['candidate_passed'] = all(row['candidate_passed'] for row in report['lanes'].values())
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__ == '__main__':
    main()
