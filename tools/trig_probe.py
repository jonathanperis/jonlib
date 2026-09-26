#!/usr/bin/env python3
"""Check bounded gradient trigonometry against the host's actual sinf/cosf."""
import argparse
import json
from pathlib import Path

from conformance import BUILD, ROOT, checkout, gradient_reference, run, source_gate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source', type=Path, required=True)
    parser.add_argument('--gpu', action='store_true')
    parser.add_argument('--full', action='store_true', help='Check every integral direction in -32767..32767')
    parser.add_argument('--gnu-control', action='store_true', help='Check the Arm/GNU polynomial against its independent C model on any host')
    parser.add_argument('--rotation', action='store_true', help='Use ImageRotate degree-to-radian evaluation instead of linear gradients')
    args = parser.parse_args()
    if args.gnu_control and args.full:
        parser.error('The independent GNU control covers the one-cycle fast-reduction domain')
    pins = json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source, pins['bend']['revision'], pins['bend'].get('patch'))
    work = BUILD/'trig-probe'
    work.mkdir(exist_ok=True)
    report_path = work/'results.json'
    report_path.write_text(json.dumps(dict(passed=False))+'\n')
    limit = 32767 if args.full else 360
    count = 2*limit+1
    c = work/'reference.c'
    c.write_text('''/* Arm optimized-routines polynomial; MIT alternative, see LICENSES/arm-math.txt. */
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#pragma STDC FP_CONTRACT OFF
static void arm_model(float input, float *co, float *si) {
  double x=(double)input;
  unsigned bits; memcpy(&bits,&input,4);
  int n=0;
  if (((bits>>20)&0x7ff) >= 0x3f4) {
    n=((int32_t)(x*0x1.45F306DC9C883p+23)+0x800000)>>24;
    x -= n*0x1.921FB54442D18p0;
  }
  double x2=x*x,x3=x*x2,x4=x2*x2,x5=x3*x2,x6=x4*x2;
  double s1=0x1.1107605230bc4p-7+x2*(-0x1.994eb3774cf24p-13);
  double c2=-0x1.6c087e89a359dp-10+x2*0x1.99343027bf8c3p-16;
  double s=x+x3*(-0x1.555545995a603p-3);
  double c1=1+x2*(-0x1.ffffffd0c621cp-2);
  double c=c1+x4*0x1.55553e1068f19p-5;
  float sr=s+x5*s1,cr=c+x6*c2;
  switch(n&3) { case 0:*co=cr;*si=sr;break;case 1:*co=-sr;*si=cr;break;case 2:*co=-cr;*si=-sr;break;default:*co=sr;*si=-cr; }
}
int main(void) {
  for(int i=-LIMIT;i<=LIMIT;i++) {
    float r=RADIANS;
    float c,s; unsigned cb,sb;
#ifdef GNU_CONTROL
    arm_model(r,&c,&s);
#else
    c=cosf(r);s=sinf(r);
#endif
    memcpy(&cb,&c,4); memcpy(&sb,&s,4);
    printf("%u %u\\n",cb,sb);
  }
  return 0;
}
'''.replace('RADIANS','(float)i*3.14159265358979323846f/180.0f' if args.rotation else '(float)(90-i)/180.0f*3.14159f'))
    reference = work/'reference'
    run(['clang','-std=c11','-O2',f'-DLIMIT={limit}',*(['-DGNU_CONTROL'] if args.gnu_control else []),c,'-lm','-o',reference])
    expected = [[int(v) for v in line.split()] for line in run([reference]).splitlines()]
    lanes = ['cpu','javascript', *(['metal'] if args.gpu else [])]
    gnu = args.gnu_control or gradient_reference()=='GnuGradient'
    report = dict(passed=False,directions=count,limit=limit,operation='rotation' if args.rotation else 'gradient',profile='GnuGradient' if gnu else 'AccurateGradient',reference='arm-model' if args.gnu_control else 'native-libm',source_sha256=source_gate(),lanes={})
    for lane in lanes:
        source = work/f'{lane}.bend'
        source.write_text('''import Base
import ../../src/trig.bend as T
def bits(pair: F32 & F32) -> U32 & U32:
  (c, s) = pair
  (F32.bits(c), F32.bits(s))
def values(n: Nat, +direction: F32) -> List<(U32 & U32)>:
  match n:
    case 0n: Nil{}
    case 1n+k:
      Con{bits(T.sincos_for(GNU_PROFILE, RADIANS)), values(k, (direction + 1.0 : F32))}
def row(pair: U32 & U32) -> String:
  (c, s) = pair
  U32.show(c) ++ " " ++ U32.show(s) ++ "\\n"
def show(items: List<(U32 & U32)>) -> String:
  match items:
    case Nil{}: ""
    case Con{pair, rest}: row(pair) ++ show(rest)
def batches(n: Nat, +direction: F32) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+k:
      do IO<Unit>:
        IO.print(show(valuesBANG(32n, direction)))
        batches(k, (direction + 32.0 : F32))
def main() -> IO(Unit):
  do IO<Unit>:
    batches(BATCHESn, F32.neg(LIMIT.0))
    IO.print(show(valuesBANG(REMAINDERn, LAST.0)))
'''.replace('RADIANS','(direction * 3.14159265358979323846 / 180.0 : F32)' if args.rotation else '((90.0 - direction) / 180.0 * 3.14159 : F32)').replace('GNU_PROFILE','True{}' if gnu else 'False{}').replace('BANG','!' if lane=='metal' else '').replace('BATCHES',str(count//32))
            .replace('LIMIT',str(limit)).replace('REMAINDER',str(count%32)).replace('LAST',str(-limit+32*(count//32))))
        binary = work/('javascript.js' if lane=='javascript' else lane)
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary])
        command = ['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual = [[int(v) for v in line.split()] for line in run(command).splitlines() if line.strip()]
        mismatches = [dict(direction=i-limit,reference=a,candidate=b) for i,(a,b) in enumerate(zip(expected,actual)) if a!=b]
        report['lanes'][lane] = dict(passed=not mismatches and len(actual)==len(expected),mismatches=mismatches[:16],mismatch_count=len(mismatches))
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        if not report['lanes'][lane]['passed']:
            raise ValueError(f'{lane}: trigonometry mismatches: {mismatches[:3]}')
        print(f'{lane}: {count} directions match exact {report["reference"]} bits ({report["profile"]})',flush=True)
    report['passed'] = True
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__ == '__main__':
    main()
