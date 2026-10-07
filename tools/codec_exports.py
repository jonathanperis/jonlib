"""Shared driver for checked native-format export probes (J.Surface.to_<codec>/write_<codec>).

A codec spec supplies fixtures, the native program (actual pinned ExportImage on
typed source pixels, never ExportImageToMemory or ImageFormat), a strict parser
with an independent decoder, the Bend candidate and the typed-IO programs. The
driver runs, in order:

  qualification   fixed native controls (endianness, rounding, packed/R32 colors)
  reference       complete native files plus decoded RGBA8; codec invariants
  candidates      batched CPU-1/CPU-2/JavaScript lanes under RLIMIT_NOFILE=64; each
                  lane must replace a sentinel with the complete file it writes
  typed IO        ordinary (success, ENOENT, EISDIR with exact Base code/message)
                  and post-open failure (RLIMIT_FSIZE=0 -> EFBIG, truncation) runs,
                  100 iterations per lane under RLIMIT_NOFILE=64

No GPU claim; native error-return parity is deliberately not claimed for short writes.
"""
import errno
import hashlib
import json
import shutil
import sys

from byte_probe import BEND_EMITTER
from image_export_probe import FILE_DESCRIPTOR_LIMIT, limited_runs
import probekit
from probekit import ProbeFailure

BPP = {1:1, 2:2, 3:2, 4:3, 5:2, 6:2, 7:4, 8:4}
ITERATIONS = 100
SENTINEL = b'old output must be replaced\x00\xff' * 11
NATIVE_FLAGS = ('-fno-fast-math', '-ffp-contract=off')


def strict_json(text):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result: raise ValueError('Duplicate JSON field')
            result[key] = value
        return result
    return json.loads(text, object_pairs_hook=unique)


def typed_equal(actual, expected):
    return type(actual) is dict and actual == expected and all(type(actual[k]) is type(v) for k, v in expected.items())


TYPED_PIXELS = r'''static void *typed_pixels(unsigned char *data,int size,int format){
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
'''
# Packed/R32 sources read through LoadImageColors must give these exact colors.
COLOR_CONTROLS = r'''unsigned words[]={65535,65535,65535,0x3f000000,0,0x80000000,1,0x007fffff,0x3f800000};
int formats[]={3,5,6,8,8,8,8,8,8};unsigned expected[]={0xf8fcf8ff,0xf8f8f8ff,0xffffffff,0x7f0000ff,255,255,255,255,0xff0000ff};
for(int i=0;i<9;i++){unsigned short packed=(unsigned short)words[i];float sample;memcpy(&sample,&words[i],sizeof sample);Image image={formats[i]==8 ? (void *)&sample : (void *)&packed,1,1,1,formats[i]};Color *c=LoadImageColors(image);if(!c||((unsigned)c->r<<24|(unsigned)c->g<<16|(unsigned)c->b<<8|c->a)!=expected[i])return 3;UnloadImageColors(c);}
'''
RASTER_C_PREFIX = r'''#include "raylib.h"
#include <float.h>
#include <fenv.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
_Static_assert(sizeof(float)==4 && sizeof(unsigned)==4 && sizeof(unsigned short)==2 && FLT_RADIX==2 && FLT_MANT_DIG==24, "binary32 required");
'''+TYPED_PIXELS+r'''    /* Typed assignment must preserve every raw word, including -0/subnormals. */
    if(memcmp(storage,data,(size_t)size))exit(7);
    return storage;
}
static int used;
static void emit(unsigned char *p,int n){for(int i=0;i<n;i++){if(!used)putchar('[');printf("%s%u",used?",":"",p[i]);if(++used==256){puts("]");used=0;}}if(used){puts("]");used=0;}puts("\"end\"");}
'''
RASTER_QUALIFY = (RASTER_C_PREFIX+r'''int main(void){SetTraceLogLevel(LOG_NONE);unsigned little=1;if(*(unsigned char*)&little!=1||fegetround()!=FE_TONEAREST)return 2;
'''+COLOR_CONTROLS+r'''puts("{\"controls\":9,\"little_endian\":true,\"round_to_nearest\":true}");return 0;}
''', dict(controls=9, little_endian=True, round_to_nearest=True))

# Written for BMP; Raster substitutes the codec name.
RASTER_BEND_PREFIX = '''import Base
import ../../jonlib.bend as J
'''+BEND_EMITTER+'''
def rgba(values: List<U32>, bytes: List<U32>) -> List<U32>:
  match values:
    case Nil{}: List.reverse(&1, U32, bytes)
    case Con{+v, rest}: rgba(rest, Con{J.Color.alpha(v), Con{J.Color.blue(v), Con{J.Color.green(v), Con{J.Color.red(v), bytes}}}})
def checked(value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "BMP contract differs")
def colors(valid: Bool, result: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "BMP decoded colors unavailable")
    case Done{values}:
      do IO<Unit>:
        checked(valid)
        emit_bytes(~&1, rgba(values, Nil{}))
def decoded(width: U32, height: U32, result: Result<&1, &1, J.Surface.Error, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "BMP decode failed")
    case Done{J.Surface{+w, +h, format, pixels}}:
      colors(U32.is_eq(width, w) && U32.is_eq(height, h), J.Surface.colors(J.Surface{w, h, format, pixels}))
def encoded(width: U32, height: U32, +bytes: +List<U32>) -> IO(Unit):
  do IO<Unit>:
    emit_bytes(~&2, bytes)
    decoded(width, height, J.Surface.decode_bmp(bytes))
def exported(width: U32, height: U32, result: Result<&1, &1, J.Surface & J.Surface.Error, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "BMP export rejected")
    case Done{bytes}: encoded(width, height, bytes)
def pure(width: U32, height: U32, result: Maybe<J.Surface>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "BMP source rejected")
    case Some{image}: exported(width, height, J.Surface.to_bmp(image))
def written(result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "BMP write failed")
    case Done{_}: IO.pure(Unit, Unit{})
def save(path: String, result: Maybe<J.Surface>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "BMP write source rejected")
    case Some{image}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_bmp(image, path), written)
def payload(+width: U32, +height: U32, +format: U32, path: String, result: Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "BMP input read failed")
    case Done{+bytes}:
      do IO<Unit>:
        pure(width, height, J.Surface.from_bytes(width, height, format, bytes))
        save(path, J.Surface.from_bytes(width, height, format, bytes))
def received(width: U32, height: U32, format: U32, path: String, result: File & Result<&1, &1, U32 & String, +List<U32>>) -> IO(Unit):
  (file, status) = result
  do IO<Unit>:
    Unit <- File.close(file)
    payload(width, height, format, path, status)
def opened(width: U32, height: U32, format: U32, size: U32, path: String, result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "BMP input open failed")
    case Done{file}: IO.bind(File & Result<&1, &1, U32 & String, +List<U32>>, Unit, File.read_bytes(file, size), received(width, height, format, path))
'''
# Direct Base writes establish the exact host error code and message. Every
# formatted write must return them unchanged, rather than merely any error.
RASTER_IO = '''def direct(path: String) -> IO(Result<&1, &1, U32 & String, Unit>):
  IO.bind(Result<&1, &1, U32 & String, File>, Result<&1, &1, U32 & String, Unit>, File.open(path, "w"), J.Image.file.write.opened([1]))
def status(+code: U32, message: String, result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{J.FileError{actual_code, actual_message}}: checked(U32.is_gt(code, 0) && U32.is_eq(code, actual_code) && String.eq(message, actual_message))
    case Done{_}: checked(U32.is_eq(code, 0))
    case _: checked(False{})
def write(code: U32, message: String, path: String, image: Maybe<J.Surface>) -> IO(Unit):
  match image:
    case None{}: IO.die(Unit, 1, "BMP IO fixture rejected")
    case Some{owner}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_bmp(owner, path), status(code, message))
def loop(n: Nat, +code: U32, +message: String, +path: String) -> IO(Unit):
  match n:
    case 0n: IO.print("{\\"iterations\\":100,\\"writes\\":800}")
    case 1n+rest:
      do IO<Unit>:
'''
IO_TAIL = '''        loop(rest, code, message, path)
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


def io_targets(work, failure):
    """(path, expected Base errno) for the ordinary or post-open-failure IO run."""
    if failure:
        return [(work/'post-open.dat', errno.EFBIG)]
    return [(work/'repeated.dat', 0), (work/'missing-parent'/'output.dat', errno.ENOENT), (work/'directory', errno.EISDIR)]


class Raster:
    """BMP/TGA: metadata line, complete encoded file and independently decoded RGBA8 per image."""
    batch = 8

    def __init__(self, name, fixtures, decode, metadata, check_reference):
        self.name, self.fixtures, self.decode, self.metadata, self.check_reference = name, fixtures, decode, metadata, check_reference
        self.qualification = RASTER_QUALIFY
        self.prefix = RASTER_BEND_PREFIX.replace('BMP', name.upper()).replace('_bmp', '_'+name)

    def prepare(self, work, cases):
        for c in cases:
            (work/(c['id']+'.raw')).write_bytes(bytes(c['data']))
        shutil.rmtree(work/'missing-parent', ignore_errors=True)
        (work/'directory').mkdir(exist_ok=True);(work/'directory'/'sentinel').write_bytes(SENTINEL)

    def reference_program(self, cases, work):
        body = [RASTER_C_PREFIX,'int main(void){SetTraceLogLevel(LOG_NONE);']
        for c in cases:
            path = work/(c['id']+'.raw'); output=work/(f'reference-{c["id"]}.{self.name}'); meta = self.metadata(c)
            check = f'||decoded.format!={meta["decoded_format"]}' if 'decoded_format' in meta else ''
            body += ['{int n=0;unsigned char *data=LoadFileData('+json.dumps(str(path))+',&n);',
                     f'if(!data||n!={len(c["data"])})return 2;Image image={{typed_pixels(data,n,{c["format"]}),{c["width"]},{c["height"]},1,{c["format"]}}};',
                     'if(!ExportImage(image,'+json.dumps(str(output))+'))return 3;',
                     'unsigned char *file=LoadFileData('+json.dumps(str(output))+',&n);if(!file)return 4;',
                     'puts('+json.dumps(json.dumps(meta,separators=(',',':')))+');emit(file,n);',
                     f'Image decoded=LoadImageFromMemory(".{self.name}",file,n);',
                     f'if(!decoded.data||decoded.width!={c["width"]}||decoded.height!={c["height"]}{check})return 5;',
                     'ImageFormat(&decoded,7);emit(decoded.data,decoded.width*decoded.height*4);UnloadImage(decoded);UnloadFileData(file);if(image.data!=data)free(image.data);UnloadFileData(data);}']
        return '\n'.join(body+['return 0;}'])+'\n'

    def parse_rows(self, text, cases):
        name = self.name.upper(); lines = text.splitlines(); cursor = 0; rows = []
        for case in cases:
            if cursor>=len(lines): raise ValueError(f'Missing {name} metadata')
            row = strict_json(lines[cursor]); cursor += 1
            if not typed_equal(row, self.metadata(case)): raise ValueError(f'{name} metadata identity/order/type differs')
            values = []
            for kind in ('encoded','pixels'):
                output = []
                while cursor<len(lines):
                    part = strict_json(lines[cursor]); cursor += 1
                    if part == 'end': break
                    if (type(part) is not list or not 1<=len(part)<=256 or
                            any(type(v) is not int or not 0<=v<=255 for v in part)):
                        raise ValueError(f'Malformed {name} byte chunk')
                    output.extend(part)
                else: raise ValueError(f'Unterminated {name} bytes')
                values.append(output)
            if values[1]!=self.decode(bytes(values[0]),case): raise ValueError(f'Independent {name} decode differs')
            rows.append(dict(row,encoded=values[0],pixels=values[1]))
        if cursor!=len(lines): raise ValueError(f'Extra {name} records')
        return rows

    def candidate_program(self, cases, work):
        body = self.prefix+'def main() -> IO(Unit):\n  do IO<Unit>:\n'
        for c in cases:
            body += '    IO.print('+json.dumps(json.dumps(self.metadata(c),separators=(',',':')))+')\n'
            body += f'    IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open({json.dumps(str(work/(c["id"]+".raw")))}, "r"), opened({c["width"]}, {c["height"]}, {c["format"]}, {len(c["data"])+1}, {json.dumps(str(work/(c["id"]+".dat")))}))\n'
        return body

    def expected_file(self, case, row):
        return row['encoded']

    def reset(self, work, cases):
        for c in cases: (work/(c['id']+'.dat')).write_bytes(SENTINEL)

    def observed(self, work, cases):
        """The complete file this lane wrote over the sentinel; then restore the sentinel for the next lane."""
        files = [list((work/(c['id']+'.dat')).read_bytes()) if (work/(c['id']+'.dat')).is_file() else None for c in cases]
        self.reset(work, cases)
        return files

    def io_program(self, work, failure):
        body = self.prefix+RASTER_IO.replace('BMP', self.name.upper()).replace('_bmp', '_'+self.name)
        for fmt,bpp in BPP.items():
            data = [0,0,0,63] if fmt==8 else [17]*bpp
            body += f'        write(code, message, path, J.Surface.from_bytes(1, 1, {fmt}, [{", ".join(map(str,data))}]))\n'
        body += IO_TAIL
        for path,code in io_targets(work, failure):
            body += f'    IO.bind(Result<&1, &1, U32 & String, Unit>, Unit, direct({json.dumps(str(path))}), baseline({code}, {json.dumps(str(path))}))\n'
        return body

    def reset_io(self, work):
        (work/'post-open.dat').write_bytes(SENTINEL);(work/'repeated.dat').write_bytes(SENTINEL)

    def verify_io(self, text, work, failure):
        name = self.name.upper(); rows = [strict_json(line) for line in text.splitlines()]
        marker = dict(iterations=ITERATIONS,writes=8*ITERATIONS)
        if len(rows)!=(1 if failure else 3) or any(not typed_equal(r, marker) for r in rows):
            raise ValueError(f'Incomplete {name} IO controls')
        if failure:
            if (work/'post-open.dat').read_bytes()!=b'': raise ValueError('Post-open failure did not truncate')
        else:
            if (work/'directory'/'sentinel').read_bytes()!=SENTINEL or (work/'missing-parent').exists(): raise ValueError('Open-error targets changed')
            if self.decode((work/'repeated.dat').read_bytes(),dict(width=1,height=1,format=8))!=[127,0,0,255]: raise ValueError('Repeated final write differs')
        return dict(iterations=ITERATIONS, writes=8*ITERATIONS*(1 if failure else 3))

    def summary(self, cases, rows):
        return dict(encoded_bytes=sum(len(r['encoded']) for r in rows), decoded_bytes=sum(len(r['pixels']) for r in rows))


def main(codec, description, argv=None):
    args = probekit.arguments(description, argv=argv)
    if args.gpu:
        raise SystemExit(f'formatted_{codec.name}_export_probe has no forced-GPU variant (no GPU claim)')
    probe = probekit.Probe(f'formatted-{codec.name}-export', args)
    if sys.byteorder != 'little':
        raise ProbeFailure('Native checked-format profile requires little endian')
    work, cases = probe.work, codec.fixtures()
    codec.prepare(work, cases)
    program, wanted = codec.qualification
    if not typed_equal(strict_json(probe.native(program, 'qualification', extra_flags=NATIVE_FLAGS)), wanted):
        raise ProbeFailure('Native archive qualification differs')
    text = probe.native(codec.reference_program(cases, work), extra_flags=NATIVE_FLAGS)
    reference = codec.parse_rows(text, cases)
    # Dedicated invariants supplement exact native bytes, without replacing them.
    invariants = codec.check_reference(cases, reference, work) or {}
    expected = [dict(row, file=codec.expected_file(case, row)) for case, row in zip(cases, reference)]
    codec.reset(work, cases)

    def parse_lane(output, selected, lane):
        return [dict(row, file=file) for row, file in zip(codec.parse_rows(output, selected), codec.observed(work, selected))]

    lanes = probe.candidates(lambda selected, gpu: codec.candidate_program(selected, work), cases, batch=codec.batch,
                             fd_limit=FILE_DESCRIPTOR_LIMIT, parse_lane=parse_lane)
    probe.compare(expected, lanes, lambda i: cases[i]['id'])
    io = {}
    for failure in (False, True):
        name = 'failure' if failure else 'ordinary'
        for lane, output, _ in limited_runs(probe, name, codec.io_program(work, failure), before=lambda lane: codec.reset_io(work), fsize=failure):
            io.setdefault(lane, {})[name] = codec.verify_io(output, work, failure)
    probe.finish(images=len(cases), pixels=sum(c['width']*c['height'] for c in cases), **codec.summary(cases, reference), **invariants,
                 typed_io=io['cpu-1'], file_descriptor_limit=FILE_DESCRIPTOR_LIMIT,
                 inputs_sha256=hashlib.sha256(json.dumps(cases, sort_keys=True).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())
