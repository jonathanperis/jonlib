#!/usr/bin/env python3
"""Exact checked formats 1..8 BMP file bytes, independent decoding and typed IO.

Uses actual pinned ExportImage; never ExportImageToMemory or ImageFormat to
prepare source pixels. CPU-1/CPU-2/JavaScript are separate exact lanes. No GPU
claim. Native error-return parity is deliberately not claimed for short writes.
"""
import argparse
import errno
import hashlib
import json
from pathlib import Path
import random
import shutil
import struct
import subprocess
import sys
import time

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
    rng = random.Random(0xB481)
    result = []
    def add(name, fmt, width, height, data):
        if len(data) != width*height*BPP[fmt]: raise ValueError('Fixture byte shape')
        result.append(dict(id=name, format=fmt, width=width, height=height, data=list(data)))
    def pattern(fmt, count):
        if fmt == 8:
            values = [0, 0x80000000, 1, 0x007fffff, 0x00800000, 0x3f000000, 0x3f7fffff, 0x3f800000]
            return b''.join(struct.pack('<I', values[i % len(values)]) for i in range(count))
        values = [0, 255, 1, 127, 128, 254, 17, 63, 201, 2, 253, 37, 239]
        return bytes(values[i % len(values)] for i in range(count*BPP[fmt]))
    for fmt in BPP:
        for width in range(1, 5): add(f'format-{fmt}-padding-{width}', fmt, width, 2, pattern(fmt, width*2))
        for name, width, height in [('thin',1,31), ('axis-row',4096,1), ('axis-column',1,4096), ('full-traversal',256,129)]:
            add(f'format-{fmt}-{name}', fmt, width, height, pattern(fmt,width*height))
    for alpha in [0,1,127,128,254,255]:
        add(f'gray-alpha-{alpha}',2,3,2,bytes(v for gray in [0,17,127,128,254,255] for v in [gray,alpha]))
    for fmt in [3,5,6]:
        words = [0,1,2,15,16,31,32,63,64,255,256,1023,1024,2047,2048,32767,32768,65534,65535,0xF801,0x003E]
        add(f'packed-{fmt}-boundaries',fmt,7,3,struct.pack('<'+'H'*len(words),*words))
        words = [rng.randrange(65536) for _ in range(35)]
        add(f'packed-{fmt}-seeded',fmt,7,5,struct.pack('<35H',*words))
    words = r32_words()
    add('r32-truncation-boundaries',8,len(words),1,struct.pack('<'+'I'*len(words),*words))
    add('rgba-alpha-zero',7,3,2,bytes(v for rgb in [(1,2,3),(255,127,0),(17,63,201),(128,254,1),(0,255,0),(255,0,255)] for v in [*rgb,0]))
    if len({c['id'] for c in result}) != len(result): raise ValueError('Duplicate fixture ID')
    return result


def metadata(case):
    return {key:case[key] for key in ('id','format','width','height')}


def decode_bmp(data, case):
    """Independent, strict decoder for the two native-export layouts only."""
    if type(data) is not bytes: raise ValueError('BMP data must be bytes')
    width,height,fmt = (case[k] for k in ('width','height','format'))
    direct = fmt in (1,2,4)
    offset,depth = (54,24) if direct else (122,32)
    stride = (width*3+3)&~3 if direct else width*4
    size = offset+stride*height
    fields = [size,0,offset,40 if direct else 108,width,height,(depth<<16)|1,0 if direct else 3,0,0,0,0,0]
    if not direct: fields += [0xff0000,0xff00,0xff,0xff000000]+[0]*13
    header = b'BM'+struct.pack('<'+'I'*len(fields),*fields)
    if len(data)!=size or len(header)!=offset or data[:offset]!=header: raise ValueError('BMP header/shape differs')
    pixels = bytearray()
    for y in range(height):
        row = data[offset+(height-1-y)*stride:offset+(height-y)*stride]
        if direct and any(row[width*3:]): raise ValueError('Nonzero BMP row padding')
        for x in range(width):
            at = x*(depth//8)
            b,g,r = row[at:at+3]
            pixels.extend((r,g,b,255 if direct else row[at+3]))
    return list(pixels)


def parse_rows(text, cases):
    lines = text.splitlines(); cursor = 0; rows = []
    for case in cases:
        if cursor>=len(lines): raise ValueError('Missing BMP metadata')
        row = strict_json(lines[cursor]); cursor += 1
        if (type(row) is not dict or row!=metadata(case) or
                any(type(row.get(k)) is not type(v) for k,v in metadata(case).items())):
            raise ValueError('BMP metadata identity/order/type differs')
        values = []
        for kind in ('encoded','pixels'):
            output = []
            while cursor<len(lines):
                part = strict_json(lines[cursor]); cursor += 1
                if part == 'end': break
                if (type(part) is not list or not 1<=len(part)<=256 or
                        any(type(v) is not int or not 0<=v<=255 for v in part)):
                    raise ValueError('Malformed BMP byte chunk')
                output.extend(part)
            else: raise ValueError('Unterminated BMP bytes')
            values.append(output)
        decoded = decode_bmp(bytes(values[0]),case)
        if values[1]!=decoded: raise ValueError('Independent BMP decode differs')
        rows.append(dict(row,encoded=values[0],pixels=values[1]))
    if cursor!=len(lines): raise ValueError('Extra BMP records')
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
        path = work/(c['id']+'.raw'); output=work/('reference-'+c['id']+'.bmp')
        body += ['{int n=0;unsigned char *data=LoadFileData('+json.dumps(str(path))+',&n);',
                 f'if(!data||n!={len(c["data"])})return 2;Image image={{typed_pixels(data,n,{c["format"]}),{c["width"]},{c["height"]},1,{c["format"]}}};',
                 'if(!ExportImage(image,'+json.dumps(str(output))+'))return 3;',
                 'unsigned char *file=LoadFileData('+json.dumps(str(output))+',&n);if(!file)return 4;',
                 'puts('+json.dumps(json.dumps(metadata(c),separators=(',',':')))+');emit(file,n);',
                 'Image decoded=LoadImageFromMemory(".bmp",file,n);',
                 f'if(!decoded.data||decoded.width!={c["width"]}||decoded.height!={c["height"]})return 5;',
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
    case Fail{_}: IO.die(Unit, 1, "BMP decode failed")
    case Done{J.Surface{+w, +h, pixels}}:
      do IO<Unit>:
        checked(U32.is_eq(width, w) && U32.is_eq(height, h))
        emit_bytes(~&1, rgba(J.Surface.colors(J.Surface{w, h, pixels}), Nil{}))
def encoded(width: U32, height: U32, +bytes: +List<U32>) -> IO(Unit):
  do IO<Unit>:
    emit_bytes(~&2, bytes)
    decoded(width, height, J.Surface.decode_bmp(bytes))
def pure(width: U32, height: U32, result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "BMP source rejected")
    case Some{image}: encoded(width, height, J.Image.Formatted.to_bmp(image))
def save(path: String, result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "BMP write source rejected")
    case Some{image}: IO.try(Unit, J.Image.Formatted.write_bmp(image, path))
def payload(+width: U32, +height: U32, +format: U32, path: String, result: Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "BMP input read failed")
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
    case Fail{_}: IO.die(Unit, 1, "BMP input open failed")
    case Done{file}: IO.bind(File & Result<&1, &1, U32 & String, +List<U32>>, Unit, File.read_bytes(file, size), received(width, height, format, path))
def checked(value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "BMP contract differs")
'''
# Bend definitions must precede callers.
_CHECKED = BEND_PREFIX[BEND_PREFIX.index('def checked('):]
BEND_PREFIX = BEND_PREFIX[:BEND_PREFIX.index('def decoded(')]+_CHECKED+BEND_PREFIX[BEND_PREFIX.index('def decoded('):BEND_PREFIX.index('def checked(')]


def candidate_program(cases, work):
    body = BEND_PREFIX+'def main() -> IO(Unit):\n  do IO<Unit>:\n'
    for c in cases:
        body += '    IO.print('+json.dumps(json.dumps(metadata(c),separators=(',',':')))+')\n'
        body += f'    IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open({json.dumps(str(work/(c["id"]+".raw")))}, "r"), opened({c["width"]}, {c["height"]}, {c["format"]}, {len(c["data"])+1}, {json.dumps(str(work/(c["id"]+".dat")))}))\n'
    return body


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
    case None{}: IO.die(Unit, 1, "BMP IO fixture rejected")
    case Some{owner}: IO.bind(Result<&1, &1, U32 & String, Unit>, Unit, J.Image.Formatted.write_bmp(owner, path), status(code, message))
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
    return body


def verify_io(text, work, failure):
    rows = [strict_json(line) for line in text.splitlines()]
    marker = dict(iterations=ITERATIONS,writes=8*ITERATIONS)
    if len(rows)!=(1 if failure else 3) or any(type(r) is not dict or r!=marker or any(type(v) is not int for v in r.values()) for r in rows):
        raise ValueError('Incomplete BMP IO controls')
    if failure:
        if (work/'post-open.dat').read_bytes()!=b'': raise ValueError('Post-open failure did not truncate')
    else:
        if (work/'directory'/'sentinel').read_bytes()!=SENTINEL or (work/'missing-parent').exists(): raise ValueError('Open-error targets changed')
        c=dict(width=1,height=1,format=8)
        if decode_bmp((work/'repeated.dat').read_bytes(),c)!=[127,0,0,255]: raise ValueError('Repeated final write differs')
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
    paths = [ROOT/'tools/formatted_bmp_export_probe.py',ROOT/'tools/byte_probe.py',ROOT/'tools/image_export_probe.py',ROOT/'tools/image_format_probe.py',ROOT/'tools/conformance.py',ROOT/'tests/test_formatted_bmp_export.py',ROOT/'toolchain.json']
    paths += [args.raylib_source/'src'/p for p in ('rtextures.c','raylib.h','config.h','external/stb_image_write.h','external/stb_image.h')]
    paths += [p for p in (args.bend_source/'bend2').rglob('*') if p.is_file() and p.suffix in ('.ts','.bend','.c','.js','.h')]
    return dict(library=source_gate(),dependencies={str(p):digest(p) for p in paths})


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    args=parser.parse_args();work=BUILD/'formatted-bmp-export-probe'
    SEALED.clear()
    work.mkdir(parents=True,exist_ok=True)
    report_path=work/'results.json';report_path.write_text('{"passed":false}\n')
    # No old result, generated program or file can certify a fresh run.
    for path in work.iterdir():
        if path.name=='results.json': continue
        if path.is_symlink(): raise ValueError('Unexpected probe symlink')
        if path.is_dir(): shutil.rmtree(path)
        else: path.unlink()
    started=time.monotonic(); lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    if sys.byteorder!='little': raise ValueError('Native checked-format profile requires little endian')
    cases=fixtures();(work/'inputs.json').write_text(json.dumps(cases,sort_keys=True)+'\n')
    seal(work/'inputs.json')
    for tool in ('bun','clang','cmake'): seal(shutil.which(tool))
    report=dict(passed=False,images=len(cases),pixels=sum(c['width']*c['height'] for c in cases),sources=tracked_sources(args),lanes={},batches=[])
    def save(): report_path.write_text(json.dumps(report,indent=2)+'\n')
    save()
    cmake=BUILD/'raylib'
    record_run(['cmake','-S',args.raylib_source,'-B',cmake,'-DPLATFORM=Memory','-DCMAKE_BUILD_TYPE=Release','-DBUILD_EXAMPLES=OFF','-DCUSTOMIZE_BUILD=ON','-DSUPPORT_MODULE_RAUDIO=OFF','-DSUPPORT_RPRAND_GENERATOR=ON','-DUSE_EXTERNAL_GLFW=OFF'],work,'configure')
    record_run(['cmake','--build',cmake,'--clean-first','--parallel','4'],work,'native-build')
    archive=cmake/'raylib/libraylib.a'
    report['native_build']={str(p):digest(p) for p in [archive,cmake/'CMakeCache.txt',cmake/'raylib/CMakeFiles/raylib.dir/flags.make']}
    for path in report['native_build']: seal(path)
    report['bun_version']=record_run(['bun','--version'],work,'bun-version').strip()
    if report['bun_version']!=lock['bun']['version']: raise ValueError('Bun version differs')
    for name,program in [('qualification',QUALIFY),('reference',reference_program(cases,work))]:
        source=work/(name+'.c');source.write_text(program)
        if name=='reference':
            for c in cases:
                path=work/(c['id']+'.raw');path.write_bytes(bytes(c['data']));seal(path)
        binary=work/name
        record_run(['clang','-std=c11','-O2','-fno-fast-math','-ffp-contract=off','-I'+str(args.raylib_source/'src'),source,archive,'-lm','-o',binary],work,name+'-compile')
        output=record_run([binary],work,name)
        if name=='qualification':
            expected=dict(controls=9,little_endian=True,round_to_nearest=True)
            q=strict_json(output)
            if type(q) is not dict or q!=expected or any(type(q[k]) is not type(v) for k,v in expected.items()): raise ValueError('Native archive qualification differs')
            report['qualification']=q
        else:
            reference=parse_rows(output,cases)
            for c in cases: seal(work/('reference-'+c['id']+'.bmp'))
    # Dedicated invariants supplement exact native bytes, without replacing them.
    alpha_rows=[r['encoded'] for r in reference if r['id'].startswith('gray-alpha-')]
    if len(alpha_rows)!=6 or any(r!=alpha_rows[0] for r in alpha_rows): raise ValueError('Native gray-alpha discard differs')
    report['encoded_bytes']=sum(len(r['encoded']) for r in reference);report['decoded_bytes']=sum(len(r['pixels']) for r in reference)
    for lane in ('cpu-1','cpu-2','javascript'): report['lanes'][lane]=dict(passed=False,batches=[])
    for start in range(0,len(cases),BATCH_SIZE):
        batch=cases[start:start+BATCH_SIZE];index=start//BATCH_SIZE;source=work/f'candidate-{index}.bend';source.write_text(candidate_program(batch,work))
        binary=work/f'candidate-{index}';js=work/f'candidate-{index}.js'
        record_run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary,'-o',js],work,f'compile-{index}')
        for lane in report['lanes']:
            for c in batch:(work/(c['id']+'.dat')).write_bytes(SENTINEL)
            command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            text=record_run(command,work,f'{lane}-{index}',preexec=limit_handles)
            rows=parse_rows(text,batch)
            if rows!=reference[start:start+len(batch)]: raise ValueError(f'{lane} batch {index}: native BMP bytes or pixels differ')
            for c,row in zip(batch,rows):
                path=work/(c['id']+'.dat')
                if path.read_bytes()!=bytes(row['encoded']): raise ValueError(f'{lane}: real file differs for {c["id"]}')
                retained=work/(lane+'-'+c['id']+'.dat');shutil.copyfile(path,retained);seal(retained)
            report['lanes'][lane]['batches'].append(dict(start=start,images=len(batch),records=3*len(batch),passed=True))
            save()
        print(f'BMP batch {index+1}: {len(batch)} full files and decoded pixels passed on all three lanes',flush=True)
    (work/'directory').mkdir();(work/'directory'/'sentinel').write_bytes(SENTINEL)
    for failure in (False,True):
        name='failure' if failure else 'ordinary';source=work/(name+'.bend');source.write_text(io_program(work,failure));binary=work/name;js=work/(name+'.js')
        record_run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary,'-o',js],work,name+'-compile')
        for lane in report['lanes']:
            (work/'post-open.dat').write_bytes(SENTINEL);(work/'repeated.dat').write_bytes(SENTINEL)
            command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            text=record_run(command,work,lane+'-'+name,preexec=limit_write_failures if failure else limit_handles)
            report['lanes'][lane][name]=verify_io(text,work,failure);save()
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    if tracked_sources(args)!=report['sources'] or any(digest(p)!=h for p,h in report['native_build'].items()): raise ValueError('Source/toolchain/native build drift')
    for lane in report['lanes']:
        if sum(b['images'] for b in report['lanes'][lane]['batches'])!=len(cases): raise ValueError('Incomplete lane cases')
        report['lanes'][lane]['passed']=True
    verify_sealed();report['sealed_artifacts']=dict(SEALED)
    report['artifacts']={str(p.relative_to(ROOT)):digest(p) for p in work.rglob('*') if p.is_file() and p!=report_path}
    report.update(passed=True,elapsed_seconds=round(time.monotonic()-started,3));save()
    print(f'PASS: {len(cases)} native BMP files / {report["pixels"]} pixels and 3,200 typed IO checks per lane',flush=True)


if __name__=='__main__':main()
