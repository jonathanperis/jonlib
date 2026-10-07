#!/usr/bin/env python3
"""Exact finite/normal atan2 bit probes against native libm or a Sun GNU control."""
import hashlib
import json
import platform
import random
import struct

import probekit
from conformance import f32, gradient_reference


GNU_CONTROL = r'''
/* Sun float atan/atan2 adaptation. Copyright (C) 1993 Sun Microsystems, Inc.
 * Developed at SunPro. Permission to use, copy, modify and distribute this
 * software is freely granted, provided this notice is preserved.
 * See LICENSES/sun-math.txt for source provenance. */
static unsigned word(float x) { unsigned b; memcpy(&b,&x,4); return b; }
static float gnu_atan(float x) {
  const float hi[]={4.6364760399e-01f,7.8539812565e-01f,9.8279368877e-01f,1.5707962513e+00f};
  const float lo[]={5.0121582440e-09f,3.7748947079e-08f,3.4473217170e-08f,7.5497894159e-08f};
  const float a[]={3.3333334327e-01f,-2.0000000298e-01f,1.4285714924e-01f,-1.1111110449e-01f,9.0908870101e-02f,-7.6918758452e-02f,6.6610731184e-02f,-5.8335702866e-02f,4.9768779427e-02f,-3.6531571299e-02f,1.6285819933e-02f};
  unsigned bits=word(x);int id=-1;
  if(bits>=0x4c000000)return hi[3]+lo[3];
  if(bits<0x3ee00000) { if(bits<0x31000000)return x; }
  else if(bits<0x3f980000) {
    if(bits<0x3f300000) {id=0;x=(2*x-1)/(2+x);} else {id=1;x=(x-1)/(x+1);}
  } else if(bits<0x401c0000) {id=2;x=(x-1.5f)/(1+1.5f*x);}
  else {id=3;x=-1/x;}
  float z=x*x,w=z*z;
  float s1=z*(a[0]+w*(a[2]+w*(a[4]+w*(a[6]+w*(a[8]+w*a[10])))));
  float s2=w*(a[1]+w*(a[3]+w*(a[5]+w*(a[7]+w*a[9]))));
  return id<0?x-x*(s1+s2):hi[id]-((x*(s1+s2)-lo[id])-x);
}
static float gnu_atan2(float y,float x) {
  const float pi=3.1415927410f,half=1.5707963705f,low=-8.7422776573e-08f;
  unsigned hx=word(x),hy=word(y),ix=hx&0x7fffffff,iy=hy&0x7fffffff;
  int m=(hy>>31)|((hx>>30)&2);
  if(iy==0)return m<2?y:m==2?pi:-pi;
  if(ix==0)return hy>>31?-half:half;
  int k=((int32_t)iy-(int32_t)ix)>>23;
  float z=k>60?half+0.5f*low:((hx>>31)&&k<-60)?0:gnu_atan(fabsf(y/x));
  switch(m) {case 0:return z;case 1:return -z;case 2:return pi-(z-low);default:return(z-low)-pi;}
}
'''
FOLDING = r'''#include <math.h>
#include <stdio.h>
#include <string.h>
static unsigned word(float x) { unsigned b;memcpy(&b,&x,4);return b; }
int main(void) {
  float (*volatile native)(float,float)=atan2f;
  printf("%u %u %u %u\n",word(atan2f(0.0f,-1.0f)),word(native(0.0f,-1.0f)),word(atan2f(1.0f,-1e-20f)),word(native(1.0f,-1e-20f)));
}
'''
BATCH = 16  # samples per printed line; one program holds every sample


def samples():
    fp = lambda value: struct.unpack('f',struct.pack('f',value))[0]
    values = [(y,x) for y in (0.0,-0.0,1.0,-1.0) for x in (0.0,-0.0,1.0,-1.0)]
    values += [(fp(1e-20),1.0),(1.0,fp(1e-20)),(1.0,fp(-1e-20)),(fp(-1e-20),-1.0)]
    for boundary in (2**-29,0.4375,0.6875,1.1875,2.4375,2**25,2**-22):
        word = struct.unpack('I',struct.pack('f',boundary))[0]
        for adjacent in (word-1,word,word+1):
            value = struct.unpack('f',struct.pack('I',adjacent))[0]
            values += [(value,1.0),(value,-1.0)]
    rng = random.Random(0xA7A2)
    values += [(fp(rng.uniform(-100,100)),fp(rng.uniform(-100,100))) for _ in range(1024)]
    return values


def reference_source(values, gnu_control):
    function = 'gnu_atan2' if gnu_control else 'native_atan2'
    return ('#include <math.h>\n#include <stdint.h>\n#include <stdio.h>\n#include <string.h>\n#pragma STDC FP_CONTRACT OFF\n'
            + GNU_CONTROL + '\nstatic float (*volatile native_atan2)(float,float)=atan2f;\nstatic const float samples[][2]={'
            + ','.join('{' + ','.join(v.hex() + 'f' for v in pair) + '}' for pair in values) + '};\n'
            f'int main(void) {{ for(unsigned i=0;i<sizeof(samples)/sizeof(samples[0]);i++) {{ float value={function}'
            '(samples[i][0],samples[i][1]); unsigned bits=word(value); printf("%u\\n",bits); } }\n')


def candidate_source(selected, gpu, gnu):
    program = '''import Base
import ../../src/angle.bend as A
type Sample is Data:
  Sample{y: F32, x: F32}
def calculate(values: +List<Sample>) -> List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{Sample{y, x}, rest}: Con{F32.bits(A.atan2(PROFILE, y, x)), calculate(rest)}
def main() -> IO(Unit):
  do IO<Unit>:
'''.replace('PROFILE', 'True{}' if gnu else 'False{}')
    for start in range(0, len(selected), BATCH):
        inputs = ','.join('Sample{' + ','.join(f32(v) for v in pair) + '}' for pair in selected[start:start + BATCH])
        program += f'    IO.print(List.show(~&1, ~U32, ~U32.show, calculate{"!" if gpu else ""}([{inputs}])))\n'
    return program


def main():
    args = probekit.arguments(__doc__, lambda parser: parser.add_argument('--gnu-control', action='store_true'), raylib=False)
    probe = probekit.Probe('angle-gnu' if args.gnu_control else 'angle', args)
    values = samples()
    gnu = args.gnu_control or gradient_reference() == 'Glibc239Libm'
    expected = [int(line) for line in probe.native(reference_source(values, args.gnu_control), link_raylib=False).splitlines()]
    if len(expected) != len(values):
        raise probekit.ProbeFailure('Incomplete atan2 reference result set')
    # Diagnostic only: literal (possibly compile-time folded) versus runtime native calls.
    (probe.work / 'folding.c').write_text(FOLDING)
    probekit.run(['clang', '-std=c11', '-O2', probe.work / 'folding.c', '-lm', '-o', probe.work / 'folding'])
    folding = [f'{int(v):08x}' for v in probekit.run([probe.work / 'folding']).split()]
    probe.report.update(samples=len(values), profile='gnu' if gnu else 'apple',
                        reference='sun-control' if args.gnu_control else 'native-libm',
                        inputs_sha256=hashlib.sha256(json.dumps(values).encode()).hexdigest(),
                        reference_sha256=hashlib.sha256('\n'.join(map(str, expected)).encode()).hexdigest(),
                        host=dict(system=platform.system(), machine=platform.machine(), libc=platform.libc_ver()),
                        constant_folding=dict(zip(('literal_pi', 'native_pi', 'literal_near_half_pi', 'native_near_half_pi'), folding)))
    lanes = probe.candidates(lambda selected, gpu: candidate_source(selected, gpu, gnu), values, batch=len(values),
                             parse=lambda text, selected: [w for line in text.splitlines() for w in json.loads(line)])
    probe.compare(expected, lanes, lambda i: f'sample {i} (y, x)={values[i]}')
    probe.finish(samples=len(values), profile=probe.report['profile'], reference=probe.report['reference'])


if __name__ == '__main__':
    main()
