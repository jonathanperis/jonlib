#!/usr/bin/env python3
"""Compare integer pixel reads and full encoded buffers with native raylib."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

from conformance import BUILD, ROOT, checkout, run, source_gate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--gpu',action='store_true')
    args = parser.parse_args()
    if sys.byteorder!='little':raise ValueError('The current raw-pixel profile requires a little-endian reference')
    lock = json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    checkout(args.raylib_source,lock['raylib']['revision'])
    work = BUILD/'raw-pixel-probe';work.mkdir(parents=True,exist_ok=True)
    report_path = work/'results.json';report_path.write_text(json.dumps(dict(passed=False))+'\n')
    source = work/'reference.c'
    source.write_text('''#include "raylib.h"
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
''')
    binary = work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,BUILD/'raylib/raylib/libraylib.a','-lm','-o',binary])
    reference_text = run([binary])
    expected = [json.loads(line) for line in reference_text.splitlines()]
    if len(expected)!=1080:raise ValueError('Incomplete raw-pixel reference rows')
    report = dict(passed=False,read_formats=[2,3,5,6],exhaustive_reads=262144,write_cases=1792,
                  grayscale_write_checks=16777216,channel_quantizer_checks=768,
                  reference_sha256=hashlib.sha256(reference_text.encode()).hexdigest(),sources=source_gate(),lanes={})
    for lane in ('cpu','javascript',*(['metal'] if args.gpu else [])):
        program = '''import Base
import ../../jonlib.bend as J
def read_acc(result: Result<&2, &2, J.Pixel.Error, U32>, values: List<U32>) -> List<U32>:
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
def write_read(bytes: +List<U32>, result: Result<&2, &2, J.Pixel.Error, U32>) -> List<U32>:
  match result:
    case Fail{_}: [0]
    case Done{color}: Con{1, Con{color, byte_list(bytes)}}
def write_result(format: U32, result: Result<&2, &2, J.Pixel.Error, +List<U32>>) -> List<U32>:
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
'''.replace('BANG','!' if lane=='metal' else '')
        for format in (2,3,5,6):program += f'    read_blocks(256n, 0, {format})\n'
        for format in range(1,8):program += f'    write_blocks(8n, 0, {format})\n'
        source = work/f'{lane}.bend';source.write_text(program)
        binary = work/('candidate.js' if lane=='javascript' else f'candidate-{lane}')
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary],timeout=600)
        command = ['bun',binary] if lane=='javascript' else [binary,*(['--gpu','on'] if lane=='metal' else [])]
        actual = [json.loads(line) for line in run(command).splitlines()]
        report['lanes'][lane] = dict(passed=actual==expected)
        report_path.write_text(json.dumps(report,indent=2)+'\n')
        if actual!=expected:
            first = next((index for index,(a,b) in enumerate(zip(expected,actual)) if a!=b),min(len(expected),len(actual)))
            raise ValueError(f'{lane}: raw pixel reads or complete encoded buffers differ at row {first}')
        print(f'{lane}: 262144 packed reads and 1792 complete write/readback buffers match native raylib',flush=True)
    report['passed'] = True
    report_path.write_text(json.dumps(report,indent=2)+'\n')


if __name__ == '__main__':
    main()
