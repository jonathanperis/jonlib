#!/usr/bin/env python3
"""Compare complete private sdefl Huffman lengths/codes and retained frequencies."""
import hashlib
import json
import random
import struct

from byte_probe import BEND_EMITTER, parse_results
from conformance import source_gate
import probekit
from probekit import ROOT, ProbeFailure

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../src/sdeflate_huffman.bend as H
def frequencies(bytes: +List<U32>, +index: U32, values: Array<U32>) -> Maybe<Array<U32>>:
  match bytes:
    case Nil{}: Some{values}
    case Con{a, Con{b, Con{c, Con{d, rest}}}}:
      frequencies(rest, (index + 1 : U32), Array.set(U32, values, index, (a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32)))
    case _: None{}
def calculate(count: U32, maximum: U32, result: Maybe<Array<U32>>) -> Maybe<&1, (Array<U32> & H.Codes)>:
  match result:
    case None{}: None{}
    case Some{values}: Some{H.build(count, maximum, values)}
def word_bytes(n: Nat, +word: U32, bytes: List<U32>) -> List<U32>:
  match n:
    case 0n: bytes
    case 1n+rest: word_bytes(rest, (word >> 8n : U32), Con{(word .&. 255 : U32), bytes})
def array_bytes(values: List<U32>, bytes: List<U32>) -> List<U32>:
  match values:
    case Nil{}: bytes
    case Con{value, rest}: array_bytes(rest, word_bytes(4n, value, bytes))
'''+BEND_EMITTER+'''
def observed(+count: U32, result: Maybe<&1, (Array<U32> & H.Codes)>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "Huffman fixture words invalid")
    case Some{Tuple{frequencies, H.Codes{lengths, words}}}:
      a = array_bytes(J.Image.list.take(~U32, Array.to_list(~U32, frequencies), U32.to_nat(count)), Nil{})
      b = array_bytes(J.Image.list.take(~U32, Array.to_list(~U32, lengths), U32.to_nat(count)), a)
      c = array_bytes(J.Image.list.take(~U32, Array.to_list(~U32, words), U32.to_nat(count)), b)
      emit_bytes(~&1, List.reverse(&1, U32, c))
def loaded(+count: U32, maximum: U32, result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "Huffman fixture read failed")
    case Done{bytes}: observed(count, calculateBANG(count, maximum, frequencies(bytes, 0, Array.new(U32, H.depth(count), 0))))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def fixtures():
    rng=random.Random(0x68756666);cases=[]
    for count,maximum in ((288,14),(32,15),(19,7)):
        vectors=[[0]*count,[1]*count,[i%17 for i in range(count)],
                 [(0,1,count-2,count-1,count,count+1)[i%6] for i in range(count)]]
        for symbol,frequency in ((0,1),(1,8193),(count-1,262145)):
            values=[0]*count;values[symbol]=frequency;vectors.append(values)
        if count==288:
            values=[0]*count;values[256]=1;vectors.append(values)
        high=[262145//count]*count;high[0]+=262145-sum(high);vectors.append(high)
        fib=[1,1]
        while len(fib)<min(count,25):fib.append(fib[-1]+fib[-2])
        vectors += [fib+[0]*(count-len(fib)),list(reversed(fib+[0]*(count-len(fib))))]
        vectors += [[rng.randrange(512) if rng.randrange(4) else 0 for _ in range(count)] for _ in range(24)]
        for values in vectors:
            if len(values)!=count or sum(values)>262145:raise ValueError('Huffman fixture leaves the private frequency domain')
            cases.append(dict(count=count,maximum=maximum,frequencies=values))
    return cases


def reference_program(cases, work):
    lines=['#include <stdio.h>','#include <stdlib.h>','#define SDEFL_IMPLEMENTATION','#include "sdefl.h"',
           'static int used=0;static void byte(unsigned v){if(!used)putchar(\'[\');printf("%s%u",used?",":"",v);if(++used==256){puts("]");used=0;}}',
           'static void word(unsigned v){for(int i=0;i<4;i++)byte((v>>(8*i))&255);}',
           'static void end(void){if(used){puts("]");used=0;}puts("\\\"end\\\"");}',
           'static void observe(const char *path,unsigned count,unsigned maximum){unsigned freq[288]={0},codes[288]={0};unsigned char lengths[288]={0};FILE *file=fopen(path,"rb");if(!file)exit(2);',
           'for(unsigned i=0;i<count;i++){unsigned char b[4];if(fread(b,1,4,file)!=4)exit(3);freq[i]=(unsigned)b[0]|((unsigned)b[1]<<8)|((unsigned)b[2]<<16)|((unsigned)b[3]<<24);}fclose(file);',
           'sdefl_huff(lengths,codes,freq,count,maximum);for(unsigned i=0;i<count;i++)word(freq[i]);for(unsigned i=0;i<count;i++)word(lengths[i]);for(unsigned i=0;i<count;i++)word(codes[i]);end();}',
           'int main(void){']
    for i,case in enumerate(cases):
        path=work/f'{i}.dat';path.write_bytes(struct.pack('<'+'I'*case['count'],*case['frequencies']))
        lines.append(f'observe({json.dumps(str(path.relative_to(ROOT)))},{case["count"]},{case["maximum"]});')
    return '\n'.join(lines+['}'])+'\n'


def main():
    args=probekit.arguments(__doc__);probe=probekit.Probe('sdeflate-huffman',args)
    probe.report['sources']=source_gate()
    cases=fixtures()
    # sdefl is header-only; the oracle includes the pinned header and references nothing from the linked library.
    text=probe.native(reference_program(cases,probe.work),extra_flags=['-I'+str(args.raylib_source/'src/external')]);expected=parse_results(text)
    if len(expected)!=len(cases):raise ProbeFailure('Incomplete native Huffman tables')
    for case,row in zip(cases,expected):
        if len(row)!=case['count']*12 or row[:case['count']*4]!=list(struct.pack('<'+'I'*case['count'],*case['frequencies'])):
            raise ProbeFailure('Native Huffman owner/table shape differs')

    def render(selected,gpu):
        body=PROGRAM.replace('BANG','!' if gpu else '')
        for i,case in selected:
            path=json.dumps(str((probe.work/f'{i}.dat').relative_to(ROOT)))
            body+=f'    IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Image.file.bytes({path}, 1152), loaded({case["count"]}, {case["maximum"]}))\n'
        return body

    probe.compare(expected,probe.candidates(render,list(enumerate(cases)),batch=64,parse=lambda out,selected:parse_results(out)))
    probe.finish(cases=len(cases),table_entries=sum(c['count'] for c in cases),profiles=[[288,14],[32,15],[19,7]],
                 inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())

if __name__=='__main__':
    main()
