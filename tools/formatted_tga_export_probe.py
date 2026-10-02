#!/usr/bin/env python3
"""Exact checked formats 1..8 TGA file bytes, independent decoding and typed IO.

Uses actual pinned ExportImage; never ExportImageToMemory or ImageFormat to
prepare source pixels. CPU-1/CPU-2/JavaScript are separate exact lanes. No GPU
claim. Native error-return parity is deliberately not claimed for short writes.
"""
import argparse
import errno
from functools import partial
import hashlib
import json
from pathlib import Path
import random
import shutil
import struct
import subprocess
import sys
import time
import uuid

from byte_probe import BEND_EMITTER
from conformance import BUILD, ENV, ROOT, checkout, source_gate
from image_export_probe import limit_handles, limit_write_failures
from image_format_probe import r32_words

BPP = {1:1, 2:2, 3:2, 4:3, 5:2, 6:2, 7:4, 8:4}
BATCH_SIZE = 8
ITERATIONS = 100
SENTINEL = b'old output must be replaced\x00\xff' * 11
SEALED = {}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def seal(path):
    path = str(Path(path).resolve())
    observed = digest(path)
    if path in SEALED and SEALED[path] != observed: raise ValueError('Sealed artifact drift: '+path)
    SEALED[path] = observed


def verify_sealed():
    for path, expected in SEALED.items():
        if not Path(path).is_file() or digest(path) != expected: raise ValueError('Sealed artifact drift: '+path)


def strict_json(text):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result: raise ValueError('Duplicate JSON field')
            result[key] = value
        return result
    return json.loads(text, object_pairs_hook=unique)


def fixtures():
    rng = random.Random(0x7A481)
    result = []
    def add(name, fmt, width, height, data):
        if len(data) != width*height*BPP[fmt]: raise ValueError('Fixture byte shape')
        result.append(dict(id=name, format=fmt, width=width, height=height, data=list(data)))
    samples = {1:[b'\x00',b'\x7f',b'\xff'], 2:[b'\x11\x00',b'\x11\x7f',b'\x11\xff'],
               3:[struct.pack('<H',v) for v in (0,0xF801,0xFFFF)],
               4:[bytes(v) for v in ((0,1,2),(127,128,129),(255,254,253))],
               5:[struct.pack('<H',v) for v in (0,0xF800,0xF801)],
               6:[struct.pack('<H',v) for v in (0,0xA127,0xA12F)],
               7:[bytes(v) for v in ((17,63,201,0),(17,63,201,127),(17,63,201,255))],
               8:[struct.pack('<I',v) for v in (0,0x3F000000,0x3F800000)]}
    for fmt in BPP:
        def pattern(values): return b''.join(samples[fmt][v] for v in values)
        add(f'format-{fmt}-single',fmt,1,1,pattern([2]))
        for width in range(1,5):
            add(f'format-{fmt}-width-{width}',fmt,width,2,pattern([i%3 for i in range(width)]+[(i+1)%3 for i in range(width)]))
        for length in (1,2,3,127,128,129,130,255,256,257):
            add(f'format-{fmt}-repeat-{length}',fmt,length,1,pattern([0]*length))
            add(f'format-{fmt}-raw-{length}',fmt,length,1,pattern([i%3 for i in range(length)]))
        for name,values in [('aba',[0,1,0]),('abbc',[0,1,1,2]),('aab',[0,0,1]),('abb',[0,1,1]),('mixed',[0,1,2,2,2,0,1,0,1,1,2])]:
            add(f'format-{fmt}-{name}',fmt,len(values),1,pattern(values))
        add(f'format-{fmt}-identical-rows',fmt,3,2,pattern([0]*6))
        add(f'format-{fmt}-orientation',fmt,3,3,pattern([0,1,2,2,2,0,0,0,1]))
        for name,width,height in [('axis-row',4096,1),('axis-column',1,4096),('full-traversal',256,129)]:
            add(f'format-{fmt}-{name}',fmt,width,height,pattern([i%3 for i in range(width*height)]))
        mixed=[]
        while len(mixed)<514:
            length=rng.randrange(1,141)
            mixed.extend([rng.randrange(3)]*length if rng.randrange(2) else [rng.randrange(3) for _ in range(length)])
        add(f'format-{fmt}-seeded-mixed',fmt,257,2,pattern(mixed[:514]))
    for fmt in (2,7):
        values=[0,1,127,128,254,255,255,254,128,127,1,0]
        add(f'format-{fmt}-alpha-only',fmt,6,2,b''.join(bytes([17,a] if fmt==2 else [17,63,201,a]) for a in values))
        add(f'format-{fmt}-alpha-aba',fmt,3,1,b''.join(bytes([17,a] if fmt==2 else [17,63,201,a]) for a in [0,255,0]))
    for fmt in (3,5,6):
        words=[0,1,2,15,16,31,32,63,64,255,256,1023,1024,2047,2048,32767,32768,65534,65535,0xF801,0x003E]
        add(f'packed-{fmt}-boundaries',fmt,7,3,struct.pack('<21H',*words))
        add(f'packed-{fmt}-seeded',fmt,7,5,struct.pack('<35H',*[rng.randrange(65536) for _ in range(35)]))
    add('packed-5-alpha-only',5,6,1,struct.pack('<6H',*[0x8420|a for a in (0,1,0,0,1,1)]))
    add('packed-6-alpha-only',6,16,1,struct.pack('<16H',*[0x8420|a for a in range(16)]))
    words=r32_words()
    add('r32-truncation-boundaries',8,len(words),1,struct.pack('<'+'I'*len(words),*words))
    words=[0,0x80000000,1,2,0x007FFFFF,0x00800000,0x3F000000,0x3F000001,0x3F000002]
    add('r32-expanded-run-collapse',8,len(words),1,struct.pack('<9I',*words))
    add('rgba-alpha-zero-hidden-rgb',7,3,2,bytes(v for rgb in [(1,2,3),(255,127,0),(17,63,201),(128,254,1),(0,255,0),(255,0,255)] for v in [*rgb,0]))
    # Encoded file exceeds the generic raster loader's independent 1 MiB cap.
    add('rgba-large-raw',7,513,513,b''.join(bytes((i%251,(i//251)%251,(i//63001)%251,255)) for i in range(513*513)))
    if len({c['id'] for c in result})!=len(result): raise ValueError('Duplicate fixture ID')
    return result


def metadata(case):
    return dict({key:case[key] for key in ('id','format','width','height')}, decoded_format=decoded_format(case['format']))


def channels(fmt):
    return {1:1,2:2,4:3}.get(fmt,4)


def decoded_format(fmt):
    return fmt if fmt in (1,2,4) else 7


def decode_tga(data, case):
    """Strict independent export-layout decoder; no packet-selection algorithm."""
    if type(data) is not bytes: raise ValueError('TGA data must be bytes')
    width,height,fmt=(case[k] for k in ('width','height','format'))
    if any(type(v) is not int for v in (width,height,fmt)) or not 1<=width<=4096 or not 1<=height<=4096 or fmt not in BPP: raise ValueError('Invalid checked TGA dimensions/format')
    comp=channels(fmt)
    header=bytes([0,0,11 if comp<3 else 10,0,0,0,0,0,0,0,0,0])+struct.pack('<HH',width,height)+bytes([comp*8,8 if comp in (2,4) else 0])
    if data[:18]!=header: raise ValueError('TGA header/shape differs')
    position=18;rows=[]
    for _ in range(height):
        row=[]
        while len(row)<width:
            if position>=len(data): raise ValueError('Missing TGA packet')
            code=data[position];position+=1;count=(code&127)+1
            if len(row)+count>width: raise ValueError('TGA packet crosses row')
            samples=1 if code&128 else count
            needed=samples*comp
            if position+needed>len(data): raise ValueError('Short TGA packet payload')
            values=[]
            for _ in range(samples):
                value=data[position:position+comp];position+=comp
                if comp==1: rgba=(*value,*value,*value,255)
                elif comp==2: rgba=(value[0],value[0],value[0],value[1])
                else: rgba=(value[2],value[1],value[0],value[3] if comp==4 else 255)
                values.append(rgba)
            row.extend(values*count if code&128 else values)
        rows.append(row)
    if position!=len(data): raise ValueError('Extra TGA bytes after pixels')
    return [v for row in reversed(rows) for pixel in row for v in pixel]


def parse_rows(text, cases):
    lines = text.splitlines(); cursor = 0; rows = []
    for case in cases:
        if cursor>=len(lines): raise ValueError('Missing TGA metadata')
        row = strict_json(lines[cursor]); cursor += 1
        if (type(row) is not dict or row!=metadata(case) or
                any(type(row.get(k)) is not type(v) for k,v in metadata(case).items())):
            raise ValueError('TGA metadata identity/order/type differs')
        values = []
        for kind in ('encoded','pixels'):
            output = []
            while cursor<len(lines):
                part = strict_json(lines[cursor]); cursor += 1
                if part == 'end': break
                if (type(part) is not list or not 1<=len(part)<=256 or
                        any(type(v) is not int or not 0<=v<=255 for v in part)):
                    raise ValueError('Malformed TGA byte chunk')
                output.extend(part)
            else: raise ValueError('Unterminated TGA bytes')
            values.append(output)
        decoded = decode_tga(bytes(values[0]),case)
        if values[1]!=decoded: raise ValueError('Independent TGA decode differs')
        rows.append(dict(row,encoded=values[0],pixels=values[1]))
    if cursor!=len(lines): raise ValueError('Extra TGA records')
    return rows


C_PREFIX = r'''#include "raylib.h"
#include <float.h>
#include <fenv.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
_Static_assert(sizeof(float)==4 && sizeof(unsigned)==4 && sizeof(unsigned short)==2 && FLT_RADIX==2 && FLT_MANT_DIG==24, "binary32 required");
static void *typed_pixels(unsigned char *data,int size,int format){
    void *storage=data;
    if(format==3||format==5||format==6){
        unsigned short *samples=malloc((size_t)size);if(!samples)exit(6);
        for(int i=0;i<size/2;i++){unsigned short value;memcpy(&value,data+2*i,sizeof value);samples[i]=value;}
        storage=samples;
    }else if(format==8){
        float *samples=malloc((size_t)size);if(!samples)exit(6);
        for(int i=0;i<size/4;i++){float value;memcpy(&value,data+4*i,sizeof value);samples[i]=value;}
        storage=samples;
    }
    /* Typed assignment must preserve every raw word, including -0/subnormals. */
    if(memcmp(storage,data,(size_t)size))exit(7);
    return storage;
}
static int used;
static void emit(unsigned char *p,int n){for(int i=0;i<n;i++){if(!used)putchar('[');printf("%s%u",used?",":"",p[i]);if(++used==256){puts("]");used=0;}}if(used){puts("]");used=0;}puts("\"end\"");}
'''


def reference_program(cases, work):
    body = [C_PREFIX,'int main(void){SetTraceLogLevel(LOG_NONE);']
    for c in cases:
        path = work/(c['id']+'.raw'); output=work/('reference-'+c['id']+'.tga')
        body += ['{int n=0;unsigned char *data=LoadFileData('+json.dumps(str(path))+',&n);',
                 f'if(!data||n!={len(c["data"])})return 2;Image image={{typed_pixels(data,n,{c["format"]}),{c["width"]},{c["height"]},1,{c["format"]}}};',
                 'if(!ExportImage(image,'+json.dumps(str(output))+'))return 3;',
                 'unsigned char *file=LoadFileData('+json.dumps(str(output))+',&n);if(!file)return 4;',
                 'puts('+json.dumps(json.dumps(metadata(c),separators=(',',':')))+');emit(file,n);',
                 'Image decoded=LoadImageFromMemory(".tga",file,n);',
                 f'if(!decoded.data||decoded.width!={c["width"]}||decoded.height!={c["height"]}||decoded.format!={decoded_format(c["format"])})return 5;',
                 'ImageFormat(&decoded,7);emit(decoded.data,decoded.width*decoded.height*4);UnloadImage(decoded);UnloadFileData(file);if(image.data!=data)free(image.data);UnloadFileData(data);}']
    return '\n'.join(body+['return 0;}'])+'\n'


QUALIFY = C_PREFIX+r'''int main(void){SetTraceLogLevel(LOG_NONE);unsigned little=1;if(*(unsigned char*)&little!=1||fegetround()!=FE_TONEAREST)return 2;
unsigned words[]={65535,65535,65535,0x3f000000,0,0x80000000,1,0x007fffff,0x3f800000};
int formats[]={3,5,6,8,8,8,8,8,8};unsigned expected[]={0xf8fcf8ff,0xf8f8f8ff,0xffffffff,0x7f0000ff,255,255,255,255,0xff0000ff};
for(int i=0;i<9;i++){unsigned short packed=(unsigned short)words[i];float sample;memcpy(&sample,&words[i],sizeof sample);Image image={formats[i]==8 ? (void *)&sample : (void *)&packed,1,1,1,formats[i]};Color *c=LoadImageColors(image);if(!c||((unsigned)c->r<<24|(unsigned)c->g<<16|(unsigned)c->b<<8|c->a)!=expected[i])return 3;UnloadImageColors(c);}
puts("{\"controls\":9,\"little_endian\":true,\"round_to_nearest\":true}");return 0;}
'''


BEND_PREFIX = '''import Base
import ../../jonlib.bend as J
'''+BEND_EMITTER+'''
def rgba(values: List<U32>, bytes: List<U32>) -> List<U32>:
  match values:
    case Nil{}: List.reverse(&1, U32, bytes)
    case Con{+v, rest}: rgba(rest, Con{J.Color.alpha(v), Con{J.Color.blue(v), Con{J.Color.green(v), Con{J.Color.red(v), bytes}}}})
def decoded(width: U32, height: U32, result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "TGA decode failed")
    case Done{J.Surface{+w, +h, pixels}}:
      do IO<Unit>:
        checked(U32.is_eq(width, w) && U32.is_eq(height, h))
        emit_bytes(~&1, rgba(J.Surface.colors(J.Surface{w, h, pixels}), Nil{}))
def encoded(width: U32, height: U32, +bytes: +List<U32>) -> IO(Unit):
  do IO<Unit>:
    emit_bytes(~&2, bytes)
    decoded(width, height, J.Surface.decode_tga(bytes))
def pure(width: U32, height: U32, result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "TGA source rejected")
    case Some{image}: encoded(width, height, J.Image.Formatted.to_tga(image))
def save(path: String, result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "TGA write source rejected")
    case Some{image}: IO.try(Unit, J.Image.Formatted.write_tga(image, path))
def payload(+width: U32, +height: U32, +format: U32, path: String, result: Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "TGA input read failed")
    case Done{+bytes}:
      do IO<Unit>:
        pure(width, height, J.Image.Formatted.from_bytes(width, height, format, bytes))
        save(path, J.Image.Formatted.from_bytes(width, height, format, bytes))
def received(width: U32, height: U32, format: U32, path: String, result: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  (file, status) = result
  do IO<Unit>:
    Unit <- File.close(file)
    payload(width, height, format, path, status)
def opened(width: U32, height: U32, format: U32, size: U32, path: String, result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "TGA input open failed")
    case Done{file}: IO.bind(File & Result<&1, &1, U32 & String, +List<U32>>, Unit, File.read_bytes(file, size), received(width, height, format, path))
def checked(value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "TGA contract differs")
'''
# Bend definitions must precede callers.
_CHECKED = BEND_PREFIX[BEND_PREFIX.index('def checked('):]
BEND_PREFIX = BEND_PREFIX[:BEND_PREFIX.index('def decoded(')]+_CHECKED+BEND_PREFIX[BEND_PREFIX.index('def decoded('):BEND_PREFIX.index('def checked(')]


def candidate_program(cases, work):
    body = BEND_PREFIX+'def main() -> IO(Unit):\n  do IO<Unit>:\n'
    for c in cases:
        body += '    IO.print('+json.dumps(json.dumps(metadata(c),separators=(',',':')))+')\n'
        body += f'    IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open({json.dumps(str(work/(c["id"]+".raw")))}, "r"), opened({c["width"]}, {c["height"]}, {c["format"]}, {len(c["data"])+1}, {json.dumps(str(work/(c["id"]+".dat")))}))\n'
    return body.replace('import ../../jonlib.bend as J', 'import '+str(ROOT/'jonlib.bend')+' as J')


def io_program(work, failure):
    # Direct Base writes establish the exact host error code and message. Every
    # formatted write must return them unchanged, rather than merely any error.
    body = BEND_PREFIX+'''def direct(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>, File.open(path, "w"), J.Surface.qoi.opened([1]))
def status(+code: U32, message: String, result: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case Fail{Tuple{actual_code, actual_message}}: checked(U32.is_gt(code, 0) && U32.is_eq(code, actual_code) && String.eq(message, actual_message))
    case Done{_}: checked(U32.is_eq(code, 0))
def write(code: U32, message: String, path: String, image: Maybe<J.Image.Formatted>) -> IO(Unit):
  match image:
    case None{}: IO.die(Unit, 1, "TGA IO fixture rejected")
    case Some{owner}: IO.bind(Result<&1, &1, U32 & String, Unit>, Unit, J.Image.Formatted.write_tga(owner, path), status(code, message))
def loop(n: Nat, +code: U32, +message: String, +path: String) -> IO(Unit):
  match n:
    case 0n: IO.print("{\\"iterations\\":100,\\"writes\\":800}")
    case 1n+rest:
      do IO<Unit>:
'''
    for fmt,bpp in BPP.items():
        data = [0,0,0,63] if fmt==8 else [17]*bpp
        body += f'        write(code, message, path, J.Image.Formatted.from_bytes(1, 1, {fmt}, [{", ".join(map(str,data))}]))\n'
    body += '''        loop(rest, code, message, path)
def baseline(expected: U32, path: String, result: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case Done{_}:
      do IO<Unit>:
        checked(U32.is_eq(expected, 0))
        loop(100n, 0, "", path)
    case Fail{Tuple{+code, +message}}:
      do IO<Unit>:
        checked(U32.is_eq(code, expected) && Bool.not(String.eq(message, "")))
        loop(100n, code, message, path)
def main() -> IO(Unit):
  do IO<Unit>:
'''
    paths = [(work/'post-open.dat',errno.EFBIG)] if failure else [(work/'repeated.dat',0),(work/'missing-parent'/'output.dat',errno.ENOENT),(work/'directory',errno.EISDIR)]
    for path,code in paths:
        body += f'    IO.bind(Result<&1, &1, U32 & String, Unit>, Unit, direct({json.dumps(str(path))}), baseline({code}, {json.dumps(str(path))}))\n'
    return body.replace('import ../../jonlib.bend as J', 'import '+str(ROOT/'jonlib.bend')+' as J')


def verify_io(text, work, failure):
    rows = [strict_json(line) for line in text.splitlines()]
    marker = dict(iterations=ITERATIONS,writes=8*ITERATIONS)
    if len(rows)!=(1 if failure else 3) or any(type(r) is not dict or r!=marker or any(type(v) is not int for v in r.values()) for r in rows):
        raise ValueError('Incomplete TGA IO controls')
    if failure:
        if (work/'post-open.dat').read_bytes()!=b'': raise ValueError('Post-open failure did not truncate')
    else:
        if (work/'directory'/'sentinel').read_bytes()!=SENTINEL or (work/'missing-parent').exists(): raise ValueError('Open-error targets changed')
        c=dict(width=1,height=1,format=8)
        if decode_tga((work/'repeated.dat').read_bytes(),c)!=[127,0,0,255]: raise ValueError('Repeated final write differs')
    return dict(iterations=ITERATIONS, writes=8*ITERATIONS*(1 if failure else 3), file_descriptor_limit=64, exact_base_code_and_message=True, post_open=failure)


def record_run(command, work, label, *, preexec=None, timeout=600):
    verify_sealed()
    command = list(map(str,command))
    outputs = [Path(command[i+1]) for i,arg in enumerate(command[:-1]) if arg=='-o']
    for arg in command:
        path=Path(arg)
        if path.is_file() and path not in outputs: seal(path)
    for path in outputs: path.unlink(missing_ok=True)
    (work/(label+'.stdout')).unlink(missing_ok=True); (work/(label+'.stderr')).unlink(missing_ok=True)
    proc = subprocess.run(command,cwd=ROOT,env=ENV,text=True,capture_output=True,timeout=timeout,preexec_fn=preexec)
    (work/(label+'.stdout')).write_text(proc.stdout); (work/(label+'.stderr')).write_text(proc.stderr)
    (work/(label+'.command.json')).write_text(json.dumps(dict(command=command,exit_code=proc.returncode),indent=2)+'\n')
    if proc.returncode: raise ValueError(f'{label} exited {proc.returncode}: {proc.stderr[-2500:]}')
    if any(not p.is_file() or p.stat().st_size==0 for p in outputs): raise ValueError('Compiler output missing')
    for path in [*outputs,work/(label+'.stdout'),work/(label+'.stderr'),work/(label+'.command.json')]: seal(path)
    return proc.stdout


def tracked_sources(args):
    paths = [ROOT/'tools/formatted_tga_export_probe.py',ROOT/'tools/byte_probe.py',ROOT/'tools/image_export_probe.py',ROOT/'tools/image_format_probe.py',ROOT/'tools/conformance.py',ROOT/'tests/test_formatted_tga_export.py',ROOT/'toolchain.json']
    paths += [args.raylib_source/'src'/p for p in ('rtextures.c','raylib.h','config.h','external/stb_image_write.h','external/stb_image.h')]
    paths += [p for p in (args.bend_source/'bend2').rglob('*') if p.is_file() and p.suffix in ('.ts','.bend','.c','.js','.h')]
    return dict(library=source_gate(),dependencies={str(p):digest(p) for p in paths})


def report_directories(argv):
    """Exact option tokens only; respect -- and argparse's value classification."""
    result=[];index=0
    rules=argparse.ArgumentParser(add_help=False,allow_abbrev=False)
    while index<len(argv):
        token=argv[index]
        if token=='--': break
        if token.startswith('--build-dir='):
            result.append(Path(token.partition('=')[2]))
        elif token=='--build-dir' and index+1<len(argv) and rules._parse_optional(argv[index+1]) is None:
            index+=1;result.append(Path(argv[index]))
        index+=1
    return result or [BUILD/'formatted-tga-export-probe']


def admit_directories(argv):
    paths=report_directories(argv)
    for path in dict.fromkeys(p.resolve() for p in paths):
        path.mkdir(parents=True,exist_ok=True)
        (path/'results.json').write_text('{"passed":false,"phase":"argument-validation"}\n')
    return paths[-1].resolve()


def main(argv=None):
    argv=list(sys.argv[1:] if argv is None else argv)
    admitted=admit_directories(argv)
    parser=argparse.ArgumentParser(description=__doc__,allow_abbrev=False)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--build-dir',type=Path,default=BUILD/'formatted-tga-export-probe')
    parser.add_argument('--timeout',type=int,default=600)
    args=parser.parse_args(argv);destination=args.build_dir.resolve()
    if destination!=admitted: parser.error('Destination admission differs')
    if args.timeout<=0: parser.error('--timeout must be positive')
    record=partial(record_run,timeout=args.timeout)
    SEALED.clear()
    report_path=destination/'results.json'
    # A fresh namespace makes old files unusable without deleting arbitrary
    # caller-owned files in an explicit build directory.
    work=destination/('run-'+uuid.uuid4().hex)
    work.mkdir()
    started=time.monotonic(); lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    if sys.byteorder!='little': raise ValueError('Native checked-format profile requires little endian')
    cases=fixtures();(work/'inputs.json').write_text(json.dumps(cases,sort_keys=True)+'\n')
    seal(work/'inputs.json')
    tool_paths={tool:str(Path(shutil.which(tool)).absolute()) for tool in ('bun','clang','cmake')}
    tool_realpaths={tool:str(Path(path).resolve()) for tool,path in tool_paths.items()}
    for path in tool_paths.values(): seal(path)
    report=dict(passed=False,run_directory=str(work),tool_paths=tool_paths,tool_realpaths=tool_realpaths,images=len(cases),pixels=sum(c['width']*c['height'] for c in cases),sources=tracked_sources(args),lanes={},batches=[])
    for path in [*(ROOT/p for p in report['sources']['library']),*(Path(p) for p in report['sources']['dependencies'])]: seal(path)
    def save(): report_path.write_text(json.dumps(report,indent=2)+'\n')
    save()
    cmake=BUILD/'raylib'
    record(['cmake','-S',args.raylib_source,'-B',cmake,'-DPLATFORM=Memory','-DCMAKE_BUILD_TYPE=Release','-DBUILD_EXAMPLES=OFF','-DCUSTOMIZE_BUILD=ON','-DSUPPORT_MODULE_RAUDIO=OFF','-DSUPPORT_RPRAND_GENERATOR=ON','-DUSE_EXTERNAL_GLFW=OFF'],work,'configure')
    record(['cmake','--build',cmake,'--clean-first','--parallel','4'],work,'native-build')
    archive=cmake/'raylib/libraylib.a'
    report['native_build']={str(p):digest(p) for p in [archive,cmake/'CMakeCache.txt',cmake/'raylib/CMakeFiles/raylib.dir/flags.make']}
    for path in report['native_build']: seal(path)
    report['clang_version']=record(['clang','--version'],work,'clang-version').strip()
    report['bun_version']=record(['bun','--version'],work,'bun-version').strip()
    if report['bun_version']!=lock['bun']['version']: raise ValueError('Bun version differs')
    for name,program in [('qualification',QUALIFY),('reference',reference_program(cases,work))]:
        source=work/(name+'.c');source.write_text(program);seal(source)
        if name=='reference':
            for c in cases:
                path=work/(c['id']+'.raw');path.write_bytes(bytes(c['data']));seal(path)
        binary=work/name
        record(['clang','-std=c11','-O2','-fno-fast-math','-ffp-contract=off','-I'+str(args.raylib_source/'src'),source,archive,'-lm','-o',binary],work,name+'-compile')
        output=record([binary],work,name)
        if name=='qualification':
            expected=dict(controls=9,little_endian=True,round_to_nearest=True)
            q=strict_json(output)
            if type(q) is not dict or q!=expected or any(type(q[k]) is not type(v) for k,v in expected.items()): raise ValueError('Native archive qualification differs')
            report['qualification']=q
        else:
            reference=parse_rows(output,cases)
            for c in cases: seal(work/('reference-'+c['id']+'.tga'))
    # Exact packet controls independently pin the surprising native raw scan.
    for fmt in BPP:
        comp=channels(fmt)
        by_id={r['id']:bytes(r['encoded']) for r in reference}
        if by_id[f'format-{fmt}-aba'][18]!=0 or by_id[f'format-{fmt}-aba'][19+comp]!=1: raise ValueError('Native ABA packet rule differs')
        if by_id[f'format-{fmt}-abbc'][18]!=3: raise ValueError('Native ABBC packet rule differs')
        if by_id[f'format-{fmt}-identical-rows'][18]!=130 or by_id[f'format-{fmt}-identical-rows'][19+comp]!=130: raise ValueError('Native row reset differs')
    collapse=by_id['r32-expanded-run-collapse']
    if len(collapse)!=28 or collapse[18]!=133 or collapse[23]!=130: raise ValueError('Native expanded R32 run collapse differs')
    report['encoded_bytes']=sum(len(r['encoded']) for r in reference);report['decoded_bytes']=sum(len(r['pixels']) for r in reference)
    for lane in ('cpu-1','cpu-2','javascript'): report['lanes'][lane]=dict(passed=False,batches=[])
    for start in range(0,len(cases),BATCH_SIZE):
        batch=cases[start:start+BATCH_SIZE];index=start//BATCH_SIZE;source=work/f'candidate-{index}.bend';source.write_text(candidate_program(batch,work));seal(source)
        binary=work/f'candidate-{index}';js=work/f'candidate-{index}.js'
        record(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary,'-o',js],work,f'compile-{index}')
        for lane in report['lanes']:
            for c in batch:(work/(c['id']+'.dat')).write_bytes(SENTINEL)
            command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            text=record(command,work,f'{lane}-{index}',preexec=limit_handles)
            rows=parse_rows(text,batch)
            if rows!=reference[start:start+len(batch)]: raise ValueError(f'{lane} batch {index}: native TGA bytes or pixels differ')
            for c,row in zip(batch,rows):
                path=work/(c['id']+'.dat')
                if path.read_bytes()!=bytes(row['encoded']): raise ValueError(f'{lane}: real file differs for {c["id"]}')
                retained=work/(lane+'-'+c['id']+'.dat');shutil.copyfile(path,retained);seal(retained)
            report['lanes'][lane]['batches'].append(dict(start=start,images=len(batch),records=3*len(batch),passed=True))
            save()
        print(f'TGA batch {index+1}: {len(batch)} full files and decoded pixels passed on all three lanes',flush=True)
    (work/'directory').mkdir();(work/'directory'/'sentinel').write_bytes(SENTINEL);seal(work/'directory'/'sentinel')
    for failure in (False,True):
        name='failure' if failure else 'ordinary';source=work/(name+'.bend');source.write_text(io_program(work,failure));seal(source);binary=work/name;js=work/(name+'.js')
        record(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary,'-o',js],work,name+'-compile')
        for lane in report['lanes']:
            (work/'post-open.dat').write_bytes(SENTINEL);(work/'repeated.dat').write_bytes(SENTINEL)
            command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            text=record(command,work,lane+'-'+name,preexec=limit_write_failures if failure else limit_handles)
            report['lanes'][lane][name]=verify_io(text,work,failure)
            retained=work/(lane+'-'+name+'-final.dat')
            shutil.copyfile(work/('post-open.dat' if failure else 'repeated.dat'),retained);seal(retained)
            report['lanes'][lane][name]['retained_file']=str(retained)
            save()
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    if any(str(Path(shutil.which(tool)).absolute())!=tool_paths[tool] or str(Path(shutil.which(tool)).resolve())!=tool_realpaths[tool] for tool in tool_paths): raise ValueError('Tool executable path resolution drift')
    if tracked_sources(args)!=report['sources'] or any(digest(p)!=h for p,h in report['native_build'].items()): raise ValueError('Source/toolchain/native build drift')
    for lane in report['lanes']:
        if sum(b['images'] for b in report['lanes'][lane]['batches'])!=len(cases): raise ValueError('Incomplete lane cases')
        report['lanes'][lane]['passed']=True
    verify_sealed();report['sealed_artifacts']=dict(SEALED)
    report['artifacts']={(str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p)):digest(p) for p in work.rglob('*') if p.is_file() and p!=report_path}
    report.update(passed=True,elapsed_seconds=round(time.monotonic()-started,3));save()
    print(f'PASS: {len(cases)} native TGA files / {report["pixels"]} pixels and 3,200 typed IO checks per lane',flush=True)


if __name__=='__main__':main()
