#!/usr/bin/env python3
"""Record Base inverse-trig differences from native float libm without claiming parity."""
import json
import platform
import random
import struct

from conformance import f32
import probekit
from probekit import ProbeFailure

PROGRAM = '''import Base
def calculate(values: +List<F32>) -> List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}: Con{F32.bits(F32.asin(value)), Con{F32.bits(F32.acos(value)), calculate(rest)}}
def main() -> IO(Unit):
  do IO<Unit>:
'''


def samples():
    values = [-1.0,-0.0,0.0,1.0]
    for boundary in (0.5,0.57,0.62,0.975,1.0):
        bits = struct.unpack('I',struct.pack('f',boundary))[0]
        for adjacent in (bits-1,bits,bits+1):
            value = struct.unpack('f',struct.pack('I',adjacent))[0]
            if value<=1:values += [value,-value]
    rng = random.Random(0xA51C05)
    values += [struct.unpack('f',struct.pack('f',rng.uniform(-1,1)))[0] for _ in range(256)]
    return list({struct.unpack('I',struct.pack('f',value))[0]:value for value in values}.values())


def main():
    probe = probekit.Probe('inverse-trig',probekit.arguments(__doc__,raylib=False))
    values = samples()
    text = probe.native('#include <math.h>\n#include <stdio.h>\n#include <string.h>\n'+
        'static float (*volatile native_asin)(float)=asinf;static float (*volatile native_acos)(float)=acosf;\n'+
        'static const float values[]={'+','.join(value.hex()+'f' for value in values)+'};\n'+
        'static unsigned word(float value){unsigned bits;memcpy(&bits,&value,4);return bits;}\n'+
        'int main(void){for(unsigned i=0;i<sizeof(values)/sizeof(values[0]);i++)printf("%u %u\\n",word(native_asin(values[i])),word(native_acos(values[i])));}\n')
    expected = [int(word) for word in text.split()]
    if len(expected)!=2*len(values):raise ProbeFailure('Incomplete inverse-trig reference')

    def render(selected,gpu):
        program = PROGRAM
        for start in range(0,len(selected),32):
            program += f'    IO.print(List.show(~&1, ~U32, ~U32.show, calculate{"!" if gpu else ""}(['+','.join(f32(value) for value in selected[start:start+32])+'])))\n'
        return program

    def parse(out,selected):
        flat = [word for line in out.splitlines() for word in json.loads(line)]
        return [flat[i:i+2] for i in range(0,len(flat),2)]

    # Diagnostic only: differences are recorded per lane, never asserted.
    lanes = probe.candidates(render,values,batch=len(values),parse=parse)
    for lane,rows in lanes.items():
        actual = [word for row in rows for word in row]
        differences = [dict(function='asin' if index%2==0 else 'acos',input=values[index//2],
                            reference=f'{reference:08x}',candidate=f'{candidate:08x}')
                       for index,(reference,candidate) in enumerate(zip(expected,actual)) if reference!=candidate]
        probe.report['lanes'][lane] = dict(candidate_passed=not differences,mismatch_count=len(differences),differences=differences[:16])
        print(f'{lane}: inverse-trig diagnostic {len(differences)} mismatches in {len(expected)} result words',flush=True)
    probe.diagnostic(probe_completed=True,candidate_passed=all(row['candidate_passed'] for row in probe.report['lanes'].values()),
                     samples=len(values),host=dict(system=platform.system(),machine=platform.machine(),libc=platform.libc_ver()))


if __name__ == '__main__':
    main()
