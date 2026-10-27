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
def float_chunk(n: Nat, +word: U32, +format: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: List.reverse(&1, U32, values)
    case 1n+rest: float_chunk(rest, (word + 1 : U32), format, read_acc(J.Pixel.get_color([(word .&. 255 : U32), ((word >> 8n) .&. 255 : U32), ((word >> 16n) .&. 255 : U32), (word >> 24n : U32)], format), values))
def float_blocks(n: Nat, +start: U32, +format: U32) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+rest:
      do IO<Unit>:
        IO.print(List.show(~&1, ~U32, ~U32.show, float_chunkBANG(256n, start, format, Nil{})))
        float_blocks(rest, (start + 256 : U32), format)
def half_chunk(n: Nat, +word: U32, +format: U32, values: List<U32>) -> List<U32>:
  match n:
    case 0n: List.reverse(&1, U32, values)
    case 1n+rest: half_chunk(rest, (word + 1 : U32), format, read_acc(J.Pixel.get_color([(word .&. 255 : U32), (word >> 8n : U32)], format), values))
def half_blocks(n: Nat, +start: U32, +format: U32) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+rest:
      do IO<Unit>:
        IO.print(List.show(~&1, ~U32, ~U32.show, half_chunkBANG(256n, start, format, Nil{})))
        half_blocks(rest, (start + 256 : U32), format)
def noop_pack(bytes: +List<U32>) -> List<U32>:
  Con{1, byte_list(bytes)}
def noop_acc(result: Result<&2, &2, J.Surface.Error, +List<U32>>, values: List<U32>) -> List<U32>:
  match result:
    case Fail{_}: Con{0, values}
    case Done{+bytes}: reversed_into(noop_pack(bytes), values)
/*EXTRA*/
def main() -> IO(Unit):
  do IO<Unit>:
'''


REFERENCE = r'''#include "raylib.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#pragma STDC FP_CONTRACT OFF
static int cast_defined(float value) {
  float scaled = value * 255.0f;
  return scaled > -1.0f && scaled < 256.0f;
}
static float bits_to_float(uint32_t bits) {
  float value;
  memcpy(&value, &bits, 4);
  return value;
}
/* Pinned HalfToFloat, used only to decide whether the cast is defined. */
static float HalfToFloat(unsigned short x) {
  union { float fm; unsigned int ui; } uni;
  const unsigned int e = (x & 0x7c00) >> 10;
  const unsigned int m = (x & 0x03ff) << 13;
  uni.fm = (float)m;
  const unsigned int v = uni.ui >> 23;
  uni.ui = (x & 0x8000) << 16 | (e != 0)*((e + 112) << 23 | m) | ((e == 0)&(m != 0))*((v - 37) << 23 | ((m << (150 - v)) & 0x007fe000));
  return uni.fm;
}
static int sample_defined(int format, const unsigned char *bytes, int count) {
  if (format >= 8 && format <= 10) {
    for (int i = 0; i + 4 <= count; i += 4) {
      uint32_t bits = (uint32_t)bytes[i] | ((uint32_t)bytes[i+1] << 8) | ((uint32_t)bytes[i+2] << 16) | ((uint32_t)bytes[i+3] << 24);
      if (!cast_defined(bits_to_float(bits))) return 0;
    }
    return 1;
  }
  for (int i = 0; i + 2 <= count; i += 2) {
    unsigned short bits = (unsigned short)(bytes[i] | (bytes[i+1] << 8));
    if (!cast_defined(HalfToFloat(bits))) return 0;
  }
  return 1;
}
int main(void) {
  SetTraceLogLevel(LOG_NONE);
  for(unsigned i=0;i<16777216u;i++) {
    Color color={i>>16,i>>8,i,255}; unsigned char actual=0;
    SetPixelColor(&actual,color,1);
    float r=(float)color.r/255.0f,g=(float)color.g/255.0f,b=(float)color.b/255.0f;
    unsigned char expected=(unsigned char)((r*0.299f+g*0.587f+b*0.114f)*255.0f);
    if(actual!=expected){fprintf(stderr,"grayscale write arithmetic mismatch\n");return 2;}
  }
  for(int limit=15;limit<=63;limit=limit==15?31:limit==31?63:64) for(int i=0;i<256;i++)
    if((unsigned)round(((float)i/255.0f)*limit)!=(unsigned)(2*i*limit+255)/510){fprintf(stderr,"pixel quantizer mismatch\n");return 3;}
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
  for(unsigned start=0;start<65536u;start+=256u){
    putchar('[');
    for(unsigned i=0;i<256u;i++) {
      unsigned word=start+i; unsigned char bytes[2]={word&255u,word>>8};
      if(!cast_defined(HalfToFloat((unsigned short)word))) printf("%s0,0",i?",":"");
      else printf("%s1,%u",i?",":"",(unsigned)ColorToInt(GetPixelColor(bytes,11)));
    }
    puts("]");
  }
  const unsigned float_starts[]={0u,0x3f000000u,0x3f800000u,0x3f808000u,0x80000000u,0xbb808000u};
  for(unsigned s=0;s<6u;s++){
    putchar('[');
    for(unsigned i=0;i<256u;i++) {
      unsigned word=float_starts[s]+i; unsigned char bytes[4]={word&255u,(word>>8)&255u,(word>>16)&255u,word>>24};
      if(!cast_defined(bits_to_float(word))) printf("%s0,0",i?",":"");
      else printf("%s1,%u",i?",":"",(unsigned)ColorToInt(GetPixelColor(bytes,8)));
    }
    puts("]");
  }
  /*PIXEL*/
}
'''

# Contiguous R32 words. The two boundary blocks contain the last defined
# positive and negative casts and the next undefined word.
FLOAT_STARTS = (0x00000000, 0x3F000000, 0x3F800000, 0x3F808000, 0x80000000, 0xBB808000)
NOOP_BYTES = [17, 34, 51, 68, 85, 102, 119, 136]
NOOP_COLOR = (10, 20, 30, 40)


def le(word, size):
    return [(word >> (8 * index)) & 255 for index in range(size)]


def wide_cases():
    """Float and half pixels, default formats, and short buffers.

    A short buffer is a native overread, so the reference prints the Jonlib
    failure without calling GetPixelColor. An undefined cast does the same.
    """
    return [
        (9, le(0x3F808080, 4) + le(0xBB808080, 4) + le(0x3F000000, 4)),
        (9, le(0x40000000, 4) + le(0, 4) + le(0, 4)),
        (10, le(0x3F808080, 4) + le(0x3F000000, 4) + le(0, 4) + le(0x80000000, 4)),
        (10, le(0, 4) + le(0, 4) + le(0, 4) + le(0x40000000, 4)),
        (12, le(0x3C00, 2) + le(0, 2) + le(0x3800, 2)),
        (12, le(0x7C00, 2) + le(0, 2) + le(0, 2)),
        (13, le(0x3C00, 2) + le(0x3800, 2) + le(0, 2) + le(0x3C00, 2)),
        (0, [9, 9, 9, 9]),
        (14, [1, 2, 3, 4]),
        (24, [1, 2, 3, 4]),
        (100, [1]),
        (2147483648, [0]),
        (4294967295, [255, 255]),
        (8, [1, 2, 3]),
        (9, le(0, 4) + le(0, 4)),
        (11, [1]),
        (13, le(0, 2) * 3),
    ]


def noop_cases():
    """Formats SetPixelColor does not write, including a short and an empty list."""
    formats = (0, 8, 9, 10, 11, 12, 13, 14, 15, 16, 23, 24, 25, 100, 2147483648, 4294967295)
    return [(fmt, list(NOOP_BYTES)) for fmt in formats] + [(8, [1, 2, 3]), (14, [])]


def bend_list(values):
    return '[' + ','.join(str(value) for value in values) + ']'


def extra_defs():
    # read_acc/noop_acc prepend; List.reverse in wide_values/noop_values restores order.
    wide = 'Nil{}'
    for fmt, values in wide_cases():
        wide = f'read_acc(J.Pixel.get_color({bend_list(values)}, {fmt}), {wide})'
    color = 'J.Color.rgba(%d, %d, %d, %d)' % NOOP_COLOR
    noop = 'Nil{}'
    for fmt, values in noop_cases():
        noop = f'noop_acc(J.Pixel.set_color({bend_list(values)}, {color}, {fmt}), {noop})'
    return (
        'def wide_values() -> List<U32>:\n'
        f'  List.reverse(&1, U32, {wide})\n'
        'def wide_row() -> IO(Unit):\n'
        '  IO.print(List.show(~&1, ~U32, ~U32.show, wide_values()))\n'
        'def noop_values() -> List<U32>:\n'
        f'  List.reverse(&1, U32, {noop})\n'
        'def noop_row() -> IO(Unit):\n'
        '  IO.print(List.show(~&1, ~U32, ~U32.show, noop_values()))\n'
    )


def c_format(fmt):
    """A C int expression for a format code, including values past INT_MAX."""
    return f'(int){fmt}u' if fmt >= 2147483648 else str(fmt)


def reference_extra():
    """C rows for the wide reads and the no-op writes."""
    lines = ['  {', '    putchar(\'[\');', '    int first=1;']
    for fmt, values in wide_cases():
        array = ','.join(str(value) for value in values) or '0'
        count = len(values)
        code = c_format(fmt)
        # kind: 2 short (fewer bytes than the format), 1 default color, 0 float/half
        if fmt in (8, 9, 10, 11, 12, 13):
            need = {8: 4, 9: 12, 10: 16, 11: 2, 12: 6, 13: 8}[fmt]
            kind = 0 if count >= need else 2
        else:
            kind = 1
        lines.append(
            f'    {{ unsigned char b[{max(count, 1)}]={{{array}}};'
            f' if(!first) putchar(\',\'); first=0;'
            f' if({kind}==2 || ({kind}==0 && !sample_defined({code}, b, {count}))) printf("0,0");'
            f' else printf("1,%u",(unsigned)ColorToInt(GetPixelColor(b, {code}))); }}'
        )
    lines += ['    puts("]");', '  }', '  {', '    Color color={10,20,30,40};', '    putchar(\'[\');', '    int first=1;']
    for fmt, values in noop_cases():
        count = len(values)
        array = ','.join(str(value) for value in values) or '0'
        # An empty initializer is not valid C when count is 0; skip the buffer.
        code = c_format(fmt)
        if count == 0:
            lines.append(
                f'    {{ unsigned char b[1]={{0}}; if(!first) putchar(\',\'); first=0;'
                f' SetPixelColor(b, color, {code}); printf("1"); }}'
            )
        else:
            lines.append(
                f'    {{ unsigned char b[{count}]={{{array}}}; if(!first) putchar(\',\'); first=0;'
                f' SetPixelColor(b, color, {code}); printf("1");'
                f' for(int j=0;j<{count};j++) printf(",%u", b[j]); }}'
            )
    lines += ['    puts("]");', '  }']
    return '\n'.join(lines) + '\n'


def actions():
    """One action per printed row."""
    return ([('read', fmt, start) for fmt in (2, 3, 5, 6) for start in range(0, 65536, 256)]
            + [('write', fmt, start) for fmt in range(1, 8) for start in range(0, 256, 32)]
            + [('half', 11, start) for start in range(0, 65536, 256)]
            + [('float', 8, start) for start in FLOAT_STARTS]
            + [('wide', 0, 0), ('noop', 0, 0)])


def render(selected, gpu):
    """Collapse contiguous blocks of one format into one recursive call."""
    body = PROGRAM.replace('BANG', '!' if gpu else '').replace('/*EXTRA*/', extra_defs())
    runs, tail = [], []
    for kind, fmt, start in selected:
        if kind in ('wide', 'noop'):
            tail.append(kind)
            continue
        step = 32 if kind == 'write' else 256
        if runs and runs[-1][:2] == [kind, fmt] and runs[-1][2] + step * runs[-1][3] == start:
            runs[-1][3] += 1
        else:
            runs.append([kind, fmt, start, 1])
    calls = ''.join(f'    {kind}_blocks({count}n, {start}, {fmt})\n' for kind, fmt, start, count in runs)
    calls += ''.join(f'    {kind}_row()\n' for kind in tail)
    return body + calls


def main():
    probe = probekit.Probe('raw-pixel', probekit.arguments(__doc__))
    if sys.byteorder != 'little':
        raise ProbeFailure('The current raw-pixel profile requires a little-endian reference')
    probe.report['sources'] = source_gate()
    reference_text = probe.native(REFERENCE.replace('  /*PIXEL*/\n', reference_extra()))
    expected = [json.loads(line) for line in reference_text.splitlines()]
    plan = actions()
    if len(expected) != len(plan):
        raise ProbeFailure(f'Incomplete raw-pixel reference rows ({len(expected)} != {len(plan)})')
    probe.compare(expected, probe.candidates(render, plan, batch=len(plan)),
                  describe=lambda index: f'row {index} ({plan[index][0]} format {plan[index][1]} from {plan[index][2]})')
    probe.finish(read_formats=[2, 3, 5, 6], exhaustive_reads=262144, write_cases=1792,
                 half_reads=65536, float_reads=len(FLOAT_STARTS) * 256,
                 wide_reads=len(wide_cases()), noop_writes=len(noop_cases()),
                 grayscale_write_checks=16777216, channel_quantizer_checks=768,
                 reference_sha256=hashlib.sha256(reference_text.encode()).hexdigest())


if __name__ == '__main__':
    main()
