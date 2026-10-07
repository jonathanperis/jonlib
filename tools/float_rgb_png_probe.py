#!/usr/bin/env python3
"""Compare native float PNG raw-prefix memory export and normalized file export."""
import hashlib
import json
import struct

from bmp_probe import bend_bytes
from byte_probe import C_EMITTER, BEND_EMITTER, parse_results
from conformance import ROOT, source_gate
import probekit
from probekit import ProbeFailure

PRELUDE = ['#include "raylib.h"','#include <stdio.h>','#include <stdlib.h>','#include <string.h>',
           C_EMITTER,
           'static void emit(unsigned char *data,int size){for(int i=0;i<size;i++)byte(data[i]);end();}',
           'static void observe(Image source,unsigned char *encoded,int size,int file){if(!encoded)exit(2);emit(encoded,size);',
           'Image decoded=LoadImageFromMemory(".png",encoded,size);if(!decoded.data||decoded.width!=source.width||decoded.height!=source.height)exit(3);ImageFormat(&decoded,7);',
           'int n=source.width*source.height*4;Color *expected=file?LoadImageColors(source):NULL;',
           'if(memcmp(decoded.data,file?(void*)expected:source.data,n))exit(4);emit(decoded.data,n);if(expected)UnloadImageColors(expected);UnloadImage(decoded);}',
           'int main(void){SetTraceLogLevel(LOG_NONE);']
PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../src/hdr.bend as H
def reverse_into(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reverse_into(tail, Con{head, rest})
def input_bytes(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: input_bytes(tail, reverse_into(head, values))
def rgba(values: List<U32>, bytes: List<U32>) -> List<U32>:
  match values:
    case Nil{}: List.reverse(&1, U32, bytes)
    case Con{+color, rest}: rgba(rest, Con{J.Color.alpha(color), Con{J.Color.blue(color), Con{J.Color.green(color), Con{J.Color.red(color), bytes}}}})
'''+BEND_EMITTER+'''
def encoded(file: Bool, image: J.Surface) -> Result<&1, &1, J.Surface & J.Surface.Error, +List<U32>>:
  match file:
    case False{}: J.Surface.export_to_memory(image, ".png")
    case True{}: J.Surface.to_png(image)
def exported(result: Result<&1, &1, J.Surface & J.Surface.Error, +List<U32>>) -> Maybe<&2, +List<U32>>:
  match result:
    case Fail{_}: None{}
    case Done{bytes}: Some{bytes}
def encode(file: Bool, result: Maybe<J.Surface>) -> Maybe<&2, +List<U32>>:
  match result:
    case None{}: None{}
    case Some{image}: exported(encoded(file, image))
def checked(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "float PNG dimensions/owner/write differs")
def colors(width: U32, height: U32, +w: U32, +h: U32, result: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "decoded float PNG colors rejected")
    case Done{values}:
      do IO<Unit>:
        checked(U32.is_eq(width, w) && U32.is_eq(height, h))
        emit_bytes(~&1, rgba(values, Nil{}))
def decoded(width: U32, height: U32, result: Result<&1, &1, J.Surface.Error, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "float PNG round trip failed")
    case Done{J.Surface{+w, +h, format, pixels}}: colors(width, height, w, h, J.Surface.colors(J.Surface{w, h, format, pixels}))
def observed(width: U32, height: U32, result: Maybe<&2, +List<U32>>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid float PNG rejected")
    case Some{+bytes}:
      do IO<Unit>:
        emit_bytes(~&2, bytes)
        decoded(width, height, J.Surface.decode_pngBANG(bytes))
def write_ok(result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Done{_}: IO.pure(Unit, Unit{})
    case Fail{_}: IO.die(Unit, 1, "valid float PNG file write failed")
def save(path: String, result: Maybe<J.Surface>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "PNG file source rejected")
    case Some{image}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_png(image, path), write_ok)
def small(value: F32) -> J.Surface:
  J.Surface{1, 1, 9, J.Vectors{Array.new(M.Vector3, 0n, M.Vector3{value, 0.25, 0.75})}}
def owner_read(wanted: U32, bytes: List<U32>) -> Bool:
  match bytes:
    case Con{r0, Con{r1, Con{r2, Con{r3, Con{0, Con{0, Con{128, Con{62, Con{0, Con{0, Con{64, Con{63, Nil{}}}}}}}}}}}}}:
      U32.is_eq((r0 .|. (r1 << 8n) .|. (r2 << 16n) .|. (r3 << 24n) : U32), F32.bits(H.float_bits(wanted)))
    case _: False{}
def owner_entries(wanted: U32, data: (U32 & U32) & (U32 & List<U32>)) -> Bool:
  match data:
    case Tuple{Tuple{1, 1}, Tuple{9, bytes}}: owner_read(wanted, bytes)
    case _: False{}
def rejected(wanted: U32, result: Result<&1, &1, J.Surface & J.Surface.Error, +List<U32>>) -> Bool:
  match result:
    case Fail{Tuple{image, J.OutOfDomain{}}}: owner_entries(wanted, J.Surface.export(image))
    case _: False{}
# NaN samples are outside the checked export domain: the owner comes back intact
# (compared with same-backend bits: NaN payloads are not portable across backends).
def nan_owner_bits(value: M.Vector3) -> Bool:
  M.Vector3{r, g, b} = value
  U32.is_eq(F32.bits(r), F32.bits(H.float_bits(2143294004))) && U32.is_eq(F32.bits(g), 1048576000) && U32.is_eq(F32.bits(b), 1061158912)
def nan_owner_read(result: Array<M.Vector3> & M.Vector3) -> Bool:
  (_, value) = result
  nan_owner_bits(value)
def nan_rejected(result: Result<&1, &1, J.Surface & J.Surface.Error, +List<U32>>) -> Bool:
  match result:
    case Fail{Tuple{J.Surface{1, 1, 9, J.Vectors{values}}, J.OutOfDomain{}}}: nan_owner_read(Array.get(M.Vector3, values, 0))
    case _: False{}
def reject_memory() -> Bool:
  nan_rejected(J.Surface.export_to_memory(small(H.float_bits(2143294004)), ".png"))
def reject_file_bytes() -> Bool:
  rejected(1073741824, J.Surface.to_png(small(2.0)))
def rejected_write(result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.SourceError{image, J.OutOfDomain{}}}: checked(owner_entries(1073741824, J.Surface.export(image)))
    case _: IO.die(Unit, 1, "PNG write rejection lost source")
def failed_write(result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.FileError{_, _}}: checked(True{})
    case _: IO.die(Unit, 1, "PNG file error kind differs")
def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: emit_bytes(~&1, [1])
    case 1n+rest:
      do IO<Unit>:
        IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_png(small(0.5), OUTPUT), write_ok)
        IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_png(small(2.0), SENTINEL), rejected_write)
        IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_png(small(0.5), DIRECTORY), failed_write)
        closure_loop(rest)
def main() -> IO(Unit):
  do IO<Unit>:
'''


def fixtures():
    cases=[dict(id='split',width=1,height=1,bytes=list(struct.pack('<fff',0.5,0.25,0.75)),file=True)]
    special=[0,0x80000000,1,0x80000001,0x007fffff,0x7f800000,0xff800000,0x7f7fffff]
    cases.append(dict(id='raw-words',width=4,height=2,bytes=list(struct.pack('<24I',*(special*3))),file=False))
    for name,width,height in (('partial-prefix',3,2),('rows',5,3),('thin',1,7),('gradient',17,13)):
        values=[v for y in range(height) for x in range(width) for v in ((x+0.5)/width,(y+0.25)/height,((x*17+y*31)%256)/255)]
        cases.append(dict(id=name,width=width,height=height,bytes=list(struct.pack('<'+'f'*len(values),*values)),file=True))
    return cases


def reference_program(cases,work):
    lines=list(PRELUDE)
    for case in cases:
        path=work/(case['id']+'.raw');path.write_bytes(bytes(case['bytes']));output=work/('reference-'+case['id']+'.png')
        lines.append(f'{{Image image=LoadImageRaw({json.dumps(str(path.relative_to(ROOT)))},{case["width"]},{case["height"]},9,0);if(!image.data)return 5;int n=0;')
        lines.append('unsigned char *memory=ExportImageToMemory(image,".png",&n);observe(image,memory,n,0);MemFree(memory);')
        if case['file']:
            lines.append(f'if(!ExportImage(image,{json.dumps(str(output.relative_to(ROOT)))}))return 6;unsigned char *file=LoadFileData({json.dumps(str(output.relative_to(ROOT)))},&n);observe(image,file,n,1);UnloadFileData(file);')
        lines.append('UnloadImage(image);}')
    return '\n'.join(lines+['}'])+'\n'


def parse_lane(text,selected):
    """Group stdout rows per action; file actions read (then remove) what this lane wrote, so every lane must write its own."""
    rows,grouped=parse_results(text),[]
    for action in selected:
        if 'file' in action:
            path=action['file'];grouped.append(list(path.read_bytes()) if path.is_file() else None)
            if action.get('remove'):path.unlink(missing_ok=True)
        else:grouped.append(rows[:action['rows']]);rows=rows[action['rows']:]
    if rows:raise ProbeFailure(f'{len(rows)} unexpected trailing output rows')
    return grouped


def main():
    probe=probekit.Probe('float-rgb-png',probekit.arguments(__doc__))
    work=probe.work;cases=fixtures();text=probe.native(reference_program(cases,work));expected=parse_results(text)
    file_count=sum(c['file'] for c in cases)
    if len(expected)!=2*(len(cases)+file_count):raise ProbeFailure('Incomplete native float PNG output')
    if expected[1]!=[0,0,0,63] or expected[3]!=[127,63,191,255]:raise ProbeFailure('Native float PNG split is no longer distinguished')
    sentinel=work/'rejected.png';sentinel.write_bytes(b'unchanged');directory=work/'directory.png';directory.mkdir(exist_ok=True)
    probe.report['sources']=source_gate()
    # Each action: Bend line (BANG marks forced-GPU calls; cpu_only lines are absent from the GPU variant) and its CPU/GPU expectation.
    actions,rows=[],iter(expected)
    for case in cases:
        image=f'J.Surface.from_bytes({case["width"]}, {case["height"]}, 9, {bend_bytes(case["bytes"])})'
        for file in (False,True) if case['file'] else (False,):
            wanted=[next(rows),next(rows)]
            actions.append(dict(name=f'{case["id"]} {"file" if file else "memory"} PNG',rows=2,cpu=wanted,gpu=wanted,
                                line=f'observed({case["width"]}, {case["height"]}, encodeBANG({"True" if file else "False"}{{}}, {image}))'))
        if case['file']:
            output=work/('candidate-'+case['id']+'.png');output.unlink(missing_ok=True)
            actions.append(dict(name=f'{case["id"]} written PNG file',file=output,remove=True,cpu=list((work/('reference-'+case['id']+'.png')).read_bytes()),gpu=None,
                                cpu_only=True,line=f'save({json.dumps(str(output.relative_to(ROOT)))}, {image})'))
    actions+=[dict(name='rejected memory owner',rows=1,cpu=[[1]],gpu=[[1]],line='emit_bytes(~&1, [Bool.to_u32(reject_memoryBANG())])'),
              dict(name='rejected file-byte owner',rows=1,cpu=[[1]],gpu=[[1]],line='emit_bytes(~&1, [Bool.to_u32(reject_file_bytesBANG())])'),
              dict(name='100 write closure cycles',rows=1,cpu=[[1]],gpu=[],cpu_only=True,line='closure_loop(100n)'),
              dict(name='rejected write sentinel',file=sentinel,cpu=list(b'unchanged'),gpu=list(b'unchanged'),line=None)]

    def render(selected,gpu):
        bang='!' if gpu else '';body=PROGRAM.replace('BANG',bang)
        for key,path in [('OUTPUT',work/'candidate-closure.png'),('SENTINEL',sentinel),('DIRECTORY',directory)]:body=body.replace(key,json.dumps(str(path.relative_to(ROOT))))
        return body+''.join('    '+a['line'].replace('BANG',bang)+'\n' for a in selected if a['line'] and not (gpu and a.get('cpu_only')))

    lanes=probe.candidates(render,actions,batch=len(actions),fd_limit=64,parse=parse_lane);describe=lambda i:actions[i]['name']
    probe.compare([a['cpu'] for a in actions],{lane:rows for lane,rows in lanes.items() if lane!='gpu'},describe)
    if 'gpu' in lanes:probe.compare([a['gpu'] for a in actions],{'gpu':lanes['gpu']},describe)
    probe.finish(memory_images=len(cases),file_images=file_count,encoded_bytes=sum(len(v) for v in expected[::2]),decoded_bytes=sum(len(v) for v in expected[1::2]),
                 pure_rejected_owners=2,io_controls=2,closure_iterations=100,file_descriptor_limit=64,
                 inputs_sha256=hashlib.sha256(json.dumps(cases).encode()).hexdigest(),reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__=='__main__':
    main()
