#!/usr/bin/env python3
"""Compare integer pixel reads and full encoded buffers with native raylib."""
import hashlib
import json
import sys

from conformance import source_gate
import probekit
from probekit import ProbeFailure

PROGRAM = '''import Base
import ../../jonlib.bend as J
def read_acc(result: Result<&2, &2, J.Surface.Error, U32>, values: List<U32>) -> List<U32>:
  match result:
    case Fail{_}: Con{0, Con{0, values}}
    case Done{color}: Con{color, Con{1, values}}
def read_chunk(n: Nat, +word: U32, +format: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: List.reverse(&1, U32, values)
    case 1n+rest: read_chunk(rest, (word + 1 : U32), format, read_acc(J.Pixel.get_color([(word .&. 255 : U32), (word >> 8n : U32)], format), values))
def read_blocks(n: Nat, +start: U32, +format: U32) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+rest:
      do IO<Unit>:
        IO.print(List.show(~&1, ~U32, ~U32.show, read_chunkBANG(256n, start, format, Nil{})))
        read_blocks(rest, (start + 256 : U32), format)
def byte_list(bytes: +List<U32>) -> List<U32>:
  match bytes:
    case Nil{}: Nil{}
    case Con{head, rest}: Con{head, byte_list(rest)}
def write_read(bytes: +List<U32>, result: Result<&2, &2, J.Surface.Error, U32>) -> List<U32>:
  match result:
    case Fail{_}: [0]
    case Done{color}: Con{1, Con{color, byte_list(bytes)}}
def write_result(format: U32, result: Result<&2, &2, J.Surface.Error, +List<U32>>) -> List<U32>:
  match result:
    case Fail{_}: [0]
    case Done{+bytes}: write_read(bytes, J.Pixel.get_color(bytes, format))
def written(+value: U32, +format: U32) -> List<U32>:
  color = J.Color.rgba(value, (value * 73 % 256 : U32), (value * 151 % 256 : U32), (value * 197 % 256 : U32))
  write_result(format, J.Pixel.set_color([17,34,51,68,85,102,119,136], color, format))
def reversed_into(values: List<U32>, rest: List<U32>) -> List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reversed_into(tail, Con{head, rest})
def write_chunk(n: Nat, +value: U32, +format: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: List.reverse(&1, U32, values)
    case 1n+rest: write_chunk(rest, (value + 1 : U32), format, reversed_into(written(value, format), values))
def write_blocks(n: Nat, +start: U32, +format: U32) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+rest:
      do IO<Unit>:
        IO.print(List.show(~&1, ~U32, ~U32.show, write_chunkBANG(32n, start, format, Nil{})))
        write_blocks(rest, (start + 32 : U32), format)
def main() -> IO(Unit):
  do IO<Unit>:
'''


REFERENCE = '''#include "raylib.h"
#include <stdint.h>
#include <stdio.h>
#include <math.h>
#pragma STDC FP_CONTRACT OFF
int main(void) {
  SetTraceLogLevel(LOG_NONE);
  for(unsigned i=0;i<16777216u;i++) {
    Color color={i>>16,i>>8,i,255}; unsigned char actual=0;
    SetPixelColor(&actual,color,1);
    float r=(float)color.r/255.0f,g=(float)color.g/255.0f,b=(float)color.b/255.0f;
    unsigned char expected=(unsigned char)((r*0.299f+g*0.587f+b*0.114f)*255.0f);
    if(actual!=expected){fprintf(stderr,"grayscale write arithmetic mismatch\\n");return 2;}
  }
  for(int limit=15;limit<=63;limit=limit==15?31:limit==31?63:64) for(int i=0;i<256;i++)
    if((unsigned)round(((float)i/255.0f)*limit)!=(unsigned)(2*i*limit+255)/510){fprintf(stderr,"pixel quantizer mismatch\\n");return 3;}
  const int formats[]={2,3,5,6};
  for(unsigned f=0;f<4;f++)for(unsigned start=0;start<65536;start+=256){
    putchar('[');
    for(unsigned i=0;i<256;i++) {
      unsigned word=start+i;union {uint64_t alignment;unsigned char bytes[8];} input;
      input.bytes[0]=word&255;input.bytes[1]=word>>8;
      printf("%s1,%u",i?",":"",(unsigned)ColorToInt(GetPixelColor(input.bytes,formats[f])));
    }
    puts("]");
  }
  for(int format=1;format<=7;format++)for(unsigned start=0;start<256;start+=32){
    putchar('[');
    for(unsigned i=0;i<32;i++) {
      unsigned value=start+i;Color color={value,(value*73)&255,(value*151)&255,(value*197)&255};
      union {uint64_t alignment;unsigned char bytes[8];} output;
      for(int j=0;j<8;j++)output.bytes[j]=(j+1)*17;
      SetPixelColor(output.bytes,color,format);
      printf("%s1,%u",i?",":"",(unsigned)ColorToInt(GetPixelColor(output.bytes,format)));
      for(int j=0;j<8;j++)printf(",%u",output.bytes[j]);
    }
    puts("]");
  }
}
'''


def actions():
    """One action per printed row: 256-word read blocks per format, then 32-value write blocks per format."""
    return ([('read',fmt,start) for fmt in (2,3,5,6) for start in range(0,65536,256)]+
            [('write',fmt,start) for fmt in range(1,8) for start in range(0,256,32)])


def render(selected, gpu):
    """Collapse contiguous blocks of one format into a single recursive read_blocks/write_blocks call."""
    body = PROGRAM.replace('BANG','!' if gpu else '');runs = []
    for kind,fmt,start in selected:
        step = 256 if kind=='read' else 32
        if runs and runs[-1][:2]==[kind,fmt] and runs[-1][2]+step*runs[-1][3]==start:runs[-1][3] += 1
        else:runs.append([kind,fmt,start,1])
    return body+''.join(f'    {kind}_blocks({count}n, {start}, {fmt})\n' for kind,fmt,start,count in runs)


def main():
    probe = probekit.Probe('raw-pixel',probekit.arguments(__doc__))
    if sys.byteorder!='little':raise ProbeFailure('The current raw-pixel profile requires a little-endian reference')
    probe.report['sources'] = source_gate()
    reference_text = probe.native(REFERENCE)
    expected = [json.loads(line) for line in reference_text.splitlines()]
    if len(expected)!=1080:raise ProbeFailure('Incomplete raw-pixel reference rows')
    plan = actions()
    probe.compare(expected,probe.candidates(render,plan,batch=len(plan)),describe=lambda index:f'row {index} ({plan[index][0]} format {plan[index][1]} from {plan[index][2]})')
    probe.finish(read_formats=[2,3,5,6],exhaustive_reads=262144,write_cases=1792,
                 grayscale_write_checks=16777216,channel_quantizer_checks=768,
                 reference_sha256=hashlib.sha256(reference_text.encode()).hexdigest())

if __name__ == '__main__':
    main()
