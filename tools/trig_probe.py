#!/usr/bin/env python3
"""Check bounded gradient trigonometry against the host's actual sinf/cosf."""
import argparse
import json
from pathlib import Path

from conformance import BUILD, ROOT, checkout, run, source_gate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source', type=Path, required=True)
    parser.add_argument('--gpu', action='store_true')
    parser.add_argument('--full', action='store_true', help='Check every integral direction in -32767..32767')
    args = parser.parse_args()
    pins = json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source, pins['bend']['revision'], pins['bend'].get('patch'))
    work = BUILD/'trig-probe'
    work.mkdir(exist_ok=True)
    report_path = work/'results.json'
    report_path.write_text(json.dumps(dict(passed=False))+'\n')
    limit = 32767 if args.full else 360
    count = 2*limit+1
    c = work/'reference.c'
    c.write_text('''#include <math.h>
#include <stdio.h>
#include <string.h>
#pragma STDC FP_CONTRACT OFF
int main(void) {
  for(int i=-LIMIT;i<=LIMIT;i++) {
    float r=(float)(90-i)/180.0f*3.14159f;
    float c=cosf(r),s=sinf(r); unsigned cb,sb;
    memcpy(&cb,&c,4); memcpy(&sb,&s,4);
    printf("%u %u\\n",cb,sb);
  }
  return 0;
}
''')
    reference = work/'reference'
    run(['clang','-std=c11','-O2',f'-DLIMIT={limit}',c,'-lm','-o',reference])
    expected = [[int(v) for v in line.split()] for line in run([reference]).splitlines()]
    lanes = ['cpu','javascript', *(['metal'] if args.gpu else [])]
    report = dict(passed=False,directions=count,limit=limit,source_sha256=source_gate(),lanes={})
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
      Con{bits(T.sincos(((90.0 - direction) / 180.0 * 3.14159 : F32))), values(k, (direction + 1.0 : F32))}
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
'''.replace('BANG','!' if lane=='metal' else '').replace('BATCHES',str(count//32))
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
        print(f'{lane}: {count} directions match exact sinf/cosf bits',flush=True)
    report['passed'] = True
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__ == '__main__':
    main()
