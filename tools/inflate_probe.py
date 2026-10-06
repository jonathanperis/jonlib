#!/usr/bin/env python3
"""Verify bounded raw DEFLATE against raylib and independently generated streams."""
import hashlib
import json
import random
import struct
import zlib

from byte_probe import BEND_EMITTER, parse_results
from conformance import source_gate
import probekit
from probekit import ProbeFailure

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../src/inflate.bend as D
''' + BEND_EMITTER + '''
def emit(result: Maybe<List<U32>>) -> IO(Unit):
  match result:
    case None{}: IO.print("null")
    case Some{bytes}: emit_bytes(~&1, bytes)
def payload(+maximum: U32, result: Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "compressed fixture read failed")
    case Done{+bytes}:
      do IO<Unit>:
        emit(J.Compression.decompressBANG(bytes, maximum))
        emit(D.decompressBANG(False{}, bytes, maximum))
def received(maximum: U32, result: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  (file, status) = result
  do IO<Unit>:
    Unit <- File.close(file)
    payload(maximum, status)
def opened(size: U32, maximum: U32, result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "compressed fixture open failed")
    case Done{file}: IO.bind(File & Result<&1, &1, U32 & String, +List<U32>>, Unit, File.read_bytes(file, size), received(maximum))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def compress(data, level=6, strategy=zlib.Z_DEFAULT_STRATEGY):
    obj=zlib.compressobj(level,zlib.DEFLATED,-15,8,strategy)
    return obj.compress(data)+obj.flush()


class Bits:
    def __init__(self):self.bits=[]
    def put(self,value,size):self.bits.extend((value>>i)&1 for i in range(size))
    def code(self,value,size):self.bits.extend((value>>i)&1 for i in reversed(range(size)))
    def fixed(self,value):
        if value<144:self.code(48+value,8)
        elif value<256:self.code(400+value-144,9)
        elif value<280:self.code(value-256,7)
        else:self.code(192+value-280,8)
    def data(self):return bytes(sum(bit<<j for j,bit in enumerate(self.bits[i:i+8])) for i in range(0,len(self.bits),8))


def fixtures():
    rng=random.Random(0x1f1a7e)
    biased=bytes(rng.choice(b'abcdeeeeeeeeeeeeeeffffffffffffffffffffff') for _ in range(8192))
    distant=bytes(rng.randrange(256) for _ in range(32768))
    inputs=[]
    for name,data in [('empty',b''),('bytes',bytes(range(256))),('overlap',b'x'*4096),('pattern',b'abcde'*900),('dynamic',biased)]:
        for mode,level,strategy in [('stored',0,zlib.Z_DEFAULT_STRATEGY),('fixed',9,zlib.Z_FIXED),('default',6,zlib.Z_DEFAULT_STRATEGY)]:
            inputs.append(dict(id=f'{name}-{mode}',data=data,compressed=compress(data,level,strategy)))
    inputs.append(dict(id='distance-window',data=distant+distant[:512],compressed=compress(distant+distant[:512])))
    bits=Bits();bits.put(3,3)
    bits.fixed(285);bits.code(29,5);bits.put(8191,13)
    bits.fixed(284);bits.put(27,5);bits.code(29,5);bits.put(8191,13);bits.fixed(256)
    inputs.append(dict(id='exact-distance-32768',data=distant+distant[:512],compressed=b'\x00'+struct.pack('<HH',32768,32767)+distant+bits.data()))
    order=[16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15]
    bits=Bits();bits.put(5,3);bits.put(0,5);bits.put(0,5);bits.put(14,4)
    for index in order[:18]:bits.put({0:1,1:2,18:2}.get(index,0),3)
    bits.code(3,2);bits.put(54,7);bits.code(2,2)
    bits.code(3,2);bits.put(127,7);bits.code(3,2);bits.put(41,7);bits.code(2,2);bits.code(0,1)
    bits.code(0,1);bits.code(1,1)
    inputs.append(dict(id='literal-only-no-distances',data=b'A',compressed=bits.data()))
    bits=Bits();bits.put(5,3);bits.put(0,5);bits.put(0,5);bits.put(10,4)
    for index in order[:14]:bits.put({0:1,3:3,16:3,17:3,18:3}.get(index,0),3)
    bits.code(4,3);bits.code(5,3);bits.put(3,2)
    bits.code(6,3);bits.put(0,3);bits.code(7,3);bits.put(127,7);bits.code(7,3);bits.put(97,7)
    bits.code(4,3);bits.code(0,1)
    for symbol in range(8):bits.code(symbol,3)
    inputs.append(dict(id='code-length-repeats',data=bytes(range(7)),compressed=bits.data()))
    obj=zlib.compressobj(6,zlib.DEFLATED,-15)
    stream=obj.compress(b'abc'*100)+obj.flush(zlib.Z_SYNC_FLUSH)+obj.compress(b'abc'*1000)+obj.flush()
    inputs.append(dict(id='multiple-blocks',data=b'abc'*1100,compressed=stream))
    inputs.append(dict(id='trailing-data',data=b'abc',compressed=compress(b'abc')+b'ignored'))
    inputs.append(dict(id='input-size-boundary',data=b'',compressed=b'\x03\x00'+bytes(1048574)))
    malformed=[dict(id='empty-input',compressed=b'',maximum=1),dict(id='reserved-block',compressed=b'\x07',maximum=1),
               dict(id='stored-truncated',compressed=b'\x01\x01\x00\xfe\xff',maximum=1),
               dict(id='stored-complement',compressed=b'\x01\x01\x00\xff\xffA',maximum=1),
               dict(id='fixed-truncated',compressed=b'\x03',maximum=1)]
    for name,lit,dist in [('distance-before-output',257,0),('reserved-length',286,None),('reserved-distance',257,30)]:
        bits=Bits();bits.put(3,3)
        if name=='reserved-distance':bits.fixed(65)
        bits.fixed(lit)
        if dist is not None:bits.code(dist,5)
        malformed.append(dict(id=name,compressed=bits.data(),maximum=10))
    for name,lengths in [('oversubscribed-tree',[1,1,1,1]),('leading-repeat',[1,0,0,1])]:
        bits=Bits();bits.put(5,3);bits.put(0,14)
        for size in lengths:bits.put(size,3)
        if name=='leading-repeat':bits.code(1,1);bits.put(0,2)
        malformed.append(dict(id=name,compressed=bits.data(),maximum=10))
    for name in ('overlap-fixed','dynamic-default','bytes-stored'):
        case=next(case for case in inputs if case['id']==name)
        malformed.append(dict(id=f'{name}-limit',compressed=case['compressed'],maximum=len(case['data'])-1))
    malformed.append(dict(id='output-request-limit',compressed=b'\x03\x00',maximum=67108865))
    malformed.append(dict(id='input-size-limit',compressed=b'\x03\x00'+bytes(1048575),maximum=0))
    for case in inputs:
        if zlib.decompress(case['compressed'],-15)!=case['data']:raise ValueError(f'Invalid generated fixture: {case["id"]}')
    return inputs,malformed


NATIVE_PAYLOADS=[b'Native raylib compression '*100,bytes(range(256))*8]


def reference_program(inputs, work):
    lines=['#include "raylib.h"','#include "external/stb_image.h"','#include <stdio.h>',
           'static void emit(unsigned char *data,int size){putchar(\'[\');for(int i=0;i<size;i++)printf("%s%u",i?",":"",data[i]);puts("]");}',
           'static int pair(unsigned char *src,int size,int capacity){int n=0;unsigned char *data=DecompressData(src,size,&n);emit(data,n);MemFree(data);',
           'unsigned char *png=MemAlloc(capacity?capacity:1);n=stbi_zlib_decode_noheader_buffer((char*)png,capacity,(const char*)src,size);if(n<0)return 0;emit(png,n);MemFree(png);return 1;}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
    for case in inputs:
        path=work/f'{case["id"]}.deflate';path.write_bytes(case['compressed'])
        lines += ['{int size=0,n=0;',f'unsigned char *src=LoadFileData({json.dumps(str(path))},&size);',
                  f'if(!src)return 2;if(!pair(src,size,{len(case["data"])}))return 4;UnloadFileData(src);}}']
    for i,payload in enumerate(NATIVE_PAYLOADS):
        source=work/f'native-{i}.data';source.write_bytes(payload)
        path=work/f'native-{i}.deflate'
        lines += ['{int size=0,n=0,output=0;',f'unsigned char *src=LoadFileData({json.dumps(str(source))},&size);',
                  'if(!src)return 2;unsigned char *compressed=CompressData(src,size,&n);',
                  f'if(!SaveFileData({json.dumps(str(path))},compressed,n))return 3;',
                  'if(!pair(compressed,n,size))return 4;MemFree(compressed);UnloadFileData(src);}']
    return '\n'.join(lines+['}'])+'\n'


def main():
    probe=probekit.Probe('inflate',probekit.arguments(__doc__))
    probe.report['sources']=source_gate()
    work=probe.work;inputs,malformed=fixtures()
    text=probe.native(reference_program(inputs,work));expected=[json.loads(line) for line in text.splitlines()]
    for i,payload in enumerate(NATIVE_PAYLOADS):inputs.append(dict(id=f'native-{i}',data=payload,compressed=(work/f'native-{i}.deflate').read_bytes()))
    originals=[list(case['data']) for case in inputs]
    if expected[1::2]!=originals:raise ProbeFailure('Native stb DEFLATE output differs from original payloads')
    native_expected=[list(case['data'][:300] if case['id']=='multiple-blocks' else case['data']) for case in inputs]
    if expected[::2]!=native_expected:raise ProbeFailure('Native raw DEFLATE output differs from its recorded empty-stored-block rule')
    kinds=sorted({(case['compressed'][0]>>1)&3 for case in inputs})
    if kinds!=[0,1,2]:raise ProbeFailure('Stored, fixed and dynamic reference blocks are all required')
    requests=[dict(id=c['id'],compressed=c['compressed'],maximum=len(c['data'])) for c in inputs]+malformed
    for case in malformed:(work/f'{case["id"]}.deflate').write_bytes(case['compressed'])
    expected += [None]*(2*len(malformed)+2)
    # Each action prints the public decoder row then the PNG-oriented decoder row; the last is the out-of-range byte control.
    actions=requests+[None];pairs=[expected[i:i+2] for i in range(0,len(expected),2)]

    def render(selected,gpu):
        bang='!' if gpu else '';body=PROGRAM.replace('BANG',bang)
        for case in selected:
            if case is None:
                body+=f'    emit(J.Compression.decompress{bang}([256], 1))\n    emit(D.decompress{bang}(False{{}}, [256], 1))\n'
            else:
                body+=f'    IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open({json.dumps(str(work/(case["id"]+".deflate")))}, "r"), opened({len(case["compressed"])}, {case["maximum"]}))\n'
        return body

    def parse(out,selected):
        rows=parse_results(out)
        return [rows[i:i+2] for i in range(0,len(rows),2)]

    probe.compare(pairs,probe.candidates(render,actions,batch=len(actions),parse=parse),
                  describe=lambda index:f'stream {actions[index]["id"] if actions[index] else "byte-256 control"}')
    probe.finish(valid_streams=len(inputs),invalid_controls=len(malformed)+1,block_kinds=kinds,
                 native_output_bytes=sum(map(len,native_expected)),png_output_bytes=sum(map(len,originals)),
                 empty_stored_block=dict(native_prefix_bytes=300,png_complete_bytes=3300),output_chunk_limit=256,
                 inputs_sha256=hashlib.sha256(json.dumps([dict(c,compressed=list(c['compressed'])) for c in requests]).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())

if __name__=='__main__':
    main()
