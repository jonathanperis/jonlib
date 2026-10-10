#!/usr/bin/env python3
"""Check gradient/rotation trigonometry against the host's actual sinf/cosf (or, with --gnu-control, the glibc model)."""
from conformance import gradient_reference, source_gate
import probekit
from probekit import ROOT, ProbeFailure

MODEL = (ROOT / 'tools/reference/glibc_sinf/model.c').read_text()

# arm_model: glibc's x86_64 sinf/cosf (the FMA ifunc variants) on every
# binary32 argument; tools/reference/glibc_sinf/model.c, docs/SINCOSF.md.
REFERENCE = '''/* Arm optimized-routines sinf/cosf as glibc x86_64 runs them; MIT alternative, see LICENSES/arm-math.txt. */
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#pragma STDC FP_CONTRACT OFF
#define FUSED 1
#define MODEL_SINF arm_model_sinf
#define MODEL_COSF arm_model_cosf
''' + MODEL + '''static void arm_model(float input, float *co, float *si) {
  *co = arm_model_cosf(input);
  *si = arm_model_sinf(input);
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
'''
PROGRAM = '''import Base
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
'''


def main():
    parser = []

    def configure(p):
        parser.append(p)
        p.add_argument('--full', action='store_true', help='Check every integral direction in -32767..32767')
        p.add_argument('--gnu-control', action='store_true', help='Check the GNU profile against the glibc sinf/cosf model on any host')
        p.add_argument('--rotation', action='store_true', help='Use ImageRotate degree-to-radian evaluation instead of linear gradients')

    args = probekit.arguments(__doc__, configure, raylib=False)
    probe = probekit.Probe('trig', args)
    limit = 32767 if args.full else 360
    count = 2*limit+1
    text = probe.native(REFERENCE.replace('RADIANS', '(float)i*3.14159265358979323846f/180.0f' if args.rotation else '(float)(90-i)/180.0f*3.14159f'),
                        extra_flags=[f'-DLIMIT={limit}', *(['-DGNU_CONTROL'] if args.gnu_control else [])])
    expected = [[int(v) for v in line.split()] for line in text.splitlines()]
    if len(expected) != count:
        raise ProbeFailure('Incomplete trigonometry reference')
    gnu = args.gnu_control or gradient_reference() == 'Glibc239Libm'
    probe.report['source_sha256'] = source_gate()
    directions = list(range(-limit, limit+1))

    def render(selected, gpu):
        # The program walks a contiguous direction range in 32-direction prints, as before.
        first, total = selected[0], len(selected)
        if selected != list(range(first, first+total)):
            raise ProbeFailure('Trigonometry batches must be contiguous direction ranges')
        return (PROGRAM.replace('RADIANS', '(direction * 3.14159265358979323846 / 180.0 : F32)' if args.rotation else '((90.0 - direction) / 180.0 * 3.14159 : F32)')
                .replace('GNU_PROFILE', 'True{}' if gnu else 'False{}').replace('BANG', '!' if gpu else '').replace('BATCHES', str(total//32))
                .replace('LIMIT', str(-first)).replace('REMAINDER', str(total % 32)).replace('LAST', str(first+32*(total//32))))

    def parse(text, selected):
        return [[int(v) for v in line.split()] for line in text.splitlines() if line.strip()]

    probe.compare(expected, probe.candidates(render, directions, batch=len(directions), parse=parse),
                  describe=lambda index: f'direction {directions[index]}')
    probe.finish(directions=count, limit=limit, operation='rotation' if args.rotation else 'gradient',
                 profile='Glibc239Libm' if gnu else 'AppleLibm', reference='arm-model' if args.gnu_control else 'native-libm')


if __name__ == '__main__':
    main()
