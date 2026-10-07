#!/usr/bin/env python3
"""Compare bounded R32 RAW loading with pinned native bytes and closed handles.

Native controls use LoadImageRaw and SaveFileData only, never color conversion
or ExportImage's incidental float-to-byte casts. Invalid-domain payloads are
Jonlib's explicit checked-storage adaptation, not native rejection claims.
"""
import hashlib
import json
import struct
import sys

from byte_probe import C_EMITTER, BEND_EMITTER, parse_results
from image_export_probe import FILE_DESCRIPTOR_LIMIT, limited_runs
from image_format_probe import r32_words, word_bytes
import probekit
from probekit import ROOT, ProbeFailure

ERRORS = {'file':1,'request':2,'truncated':3,'large':4,'samples':5}
MAX_RUNTIME_RSS = 256*1024*1024
INVALID_WORDS = (0x80000001,0x807fffff,0x80800000,0xbf000000,0xbf800000,
                 0x3f800001,0x7f7fffff,0x7f800000,0xff800000,
                 0x7fc00000,0x7f800001,0x7fffffff,0xffc01234,0xff800001)


def fixture_specs():
    """Complete file contents are retained in the manifest, including ignored bytes."""
    samples = [('half',1,1,[0x3f000000]),
               ('edges',4,3,[0,0x80000000,1,2,0x007fffff,0x00800000,0x00800001,
                             0x3e800000,0x3f000000,0x3f000001,0x3f7fffff,0x3f800000]),
               ('thresholds',len(r32_words()),1,r32_words())]
    cases = []
    for name,width,height,words in samples:
        data = word_bytes(words)
        # The ignored prefix/tail include out-of-domain words to prove that only
        # the selected payload reaches checked construction. Nonfit uses byte zero.
        for variant,header,payload in (('plain',0,data),('header-exact',5,[255]*5+data),
                                      ('header-tail',5,[255]*5+data+[255]*7),
                                      ('nonfit',1,data),('maximum-header',2147483647-len(data),data)):
            cases.append(dict(name=name+'-'+variant,width=width,height=height,format=8,
                              header=header,data=payload,selected=data,error=None))
    data = word_bytes([0,0x80000000,1,0x007fffff]*8256)
    cases.append(dict(name='large-tail-validation',width=256,height=129,format=8,header=0,
                      data=data,selected=data,error=None))
    for size in range(4):
        cases.append(dict(name=f'truncated-{size}',width=1,height=1,format=8,header=0,
                          data=[255]*size,selected=None,error='truncated'))
    cases.append(dict(name='truncated-final-word',width=4,height=3,format=8,header=5,
                      data=word_bytes(samples[1][3])[:-1],selected=None,error='truncated'))
    cases.append(dict(name='missing',width=1,height=1,format=8,header=0,data=None,selected=None,error='file'))
    controls = []
    for word in INVALID_WORDS:
        # Invalid first/last samples catch incomplete or shortcut validation.
        for position,words in (('first',[word,0,1]),('last',[0x80000000,1,word])):
            controls.append(dict(name=f'invalid-{word:08x}-{position}',width=3,height=1,
                                 format=8,header=0,data=word_bytes(words),error='samples'))
    controls.append(dict(name='invalid-large-last',width=256,height=129,format=8,header=0,
                         data=data[:-4]+word_bytes([0x3f800001]),error='samples'))
    controls.extend([
        dict(name='invalid-selected-header',width=1,height=1,format=8,header=4,
             data=word_bytes([0x3f000000,0x7fc00000]),error='samples'),
        dict(name='invalid-fallback',width=1,height=1,format=8,header=5,
             data=word_bytes([0x80000001,0x3f000000]),error='samples'),
        dict(name='format14-present',width=1,height=1,format=14,header=0,
             data=word_bytes([0x3e800000,0x3f000000,0x3f400000]),error='request'),
        dict(name='format14-missing',width=1,height=1,format=14,header=0,data=None,error='request'),
        dict(name='zero-width',width=0,height=1,format=8,header=0,data=None,error='request'),
        dict(name='large-height',width=1,height=4097,format=8,header=0,data=None,error='request'),
        dict(name='overflow-header',width=1,height=1,format=8,header=2147483644,data=None,error='request'),
        dict(name='large-file',width=1,height=1,format=8,header=0,special='large',error='large'),
        dict(name='read-error',width=1,height=1,format=8,header=0,special='directory',error='file'),
        dict(name='bounded-sparse-header-tail',width=1,height=1,format=8,header=32*1024*1024,
             special='sparse',size=64*1024*1024,selected=word_bytes([0x80000000]),error=None)])
    return cases,controls


def prepare_inputs(work,cases,controls):
    for case in cases+controls:
        path = work/(case['name']+'.raw')
        if case.get('special') == 'large':
            with path.open('wb') as file:file.truncate(2147483648)
        elif case.get('special') == 'sparse':
            with path.open('wb') as file:
                file.truncate(case['size']);file.seek(case['header']);file.write(bytes(case['selected']))
        elif case.get('special') == 'directory':
            path.mkdir(exist_ok=True);(path/'entry').write_bytes(b'x')
        elif case['data'] is None:
            if path.exists():raise ValueError('Task-owned missing-file fixture unexpectedly exists')
        else:path.write_bytes(bytes(case['data']))
        case['path'] = str(path.relative_to(ROOT))


def image_row(case):
    return list(struct.pack('<III',case['width'],case['height'],case['format']))+case['selected']


def parse_rows(text,cases,native=False,closure=False):
    rows = parse_results(text)
    wanted = [None if native and case['error'] else [ERRORS[case['error']]] if case['error'] else image_row(case) for case in cases]
    if closure:wanted.append([1])
    if len(rows) != len(wanted):raise ValueError('R32 RAW result count differs')
    for index,(actual,expected) in enumerate(zip(rows,wanted)):
        if actual != expected:raise ValueError(f'R32 RAW exact result differs at {index}')
    return rows


def verify_files(work,cases,prefix):
    for case in cases:
        path = work/(prefix+'-'+case['name']+'.raw')
        if case['error']:
            if path.exists():raise ValueError('Failed R32 RAW load unexpectedly exported a file')
        elif not path.is_file() or path.read_bytes() != bytes(case['selected']):
            raise ValueError('Complete R32 RAW file bytes differ')


def clear_outputs(work,cases,prefix):
    for case in cases:(work/(prefix+'-'+case['name']+'.raw')).unlink(missing_ok=True)


def reference_program(cases,work):
    lines = [r'''#include "raylib.h"
#include <stdio.h>
#include <stdlib.h>
''' + C_EMITTER + '\n' + r'''static void emit(const char *path,const char *out,int w,int h,int header){
Image image=LoadImageRaw(path,w,h,PIXELFORMAT_UNCOMPRESSED_R32,header);
if(!image.data){puts("null");return;}
if(image.mipmaps!=1)exit(2);
int size=GetPixelDataSize(image.width,image.height,image.format);
if(!SaveFileData(out,image.data,size))exit(3);
word(image.width);word(image.height);word(image.format);
for(int i=0;i<size;i++)byte(((unsigned char*)image.data)[i]);end();UnloadImage(image);}
int main(void){SetTraceLogLevel(LOG_NONE);''']
    for case in cases:
        output = str((work/('reference-'+case['name']+'.raw')).relative_to(ROOT))
        lines.append(f'emit({json.dumps(case["path"])},{json.dumps(output)},{case["width"]},{case["height"]},{case["header"]});')
    return '\n'.join(lines+['}'])+'\n'


BEND_PROGRAM = '''import Base
import ../../jonlib.bend as J
'''+BEND_EMITTER+'''
def error_code(error: J.Surface.IOError) -> U32:
  match error:
    case J.FileError{_, _}: 1
    case J.DataError{J.InvalidRequest{}}: 2
    case J.DataError{J.TruncatedImageData{}}: 3
    case J.DataError{J.UnsupportedImageSize{}}: 4
    case J.DataError{J.OutOfDomain{}}: 5
    case _: 99
def emit_image(+width: U32, +height: U32, format: U32, bytes: List<U32>) -> IO(Unit):
  header = {[(width .&. 255 : U32), ((width >> 8n) .&. 255 : U32), 0, 0, (height .&. 255 : U32), ((height >> 8n) .&. 255 : U32), 0, 0, format, 0, 0, 0] : List<U32>}
  emit_bytes(~&1, List.append(&1, U32, header, bytes))
def emitted(data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = data
  emit_image(width, height, format, bytes)
def reloaded(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "valid R32 RAW reload failed")
    case Done{image}: emitted(J.Surface.export(image))
def written(path: String, width: U32, height: U32, format: U32, result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "valid R32 RAW write failed")
    case Done{_}: IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_raw(path, width, height, format, 0), reloaded)
def matched(ok: Bool, +path: String, image: J.Surface) -> IO(Unit):
  match ok:
    case False{}: IO.die(Unit, 1, "R32 RAW loaded metadata differs")
    case True{}:
      J.Surface{+width, +height, +format, pixels} = image
      IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_raw(J.Surface{width, height, format, pixels}, path), written(path, width, height, format))
def loaded(path: String, w: U32, h: U32, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{error}: emit_bytes(~&1, [error_code(error)])
    case Done{J.Surface{+width, +height, +format, pixels}}:
      matched(U32.is_eq(w, width) && U32.is_eq(h, height) && U32.is_eq(format, 8), path, J.Surface{width, height, format, pixels})
def checked(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "R32 RAW closure/error differs")
def required(expected: U32, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):
  match result:
    case Done{_}: checked(U32.is_eq(expected, 0))
    case Fail{error}: checked(U32.is_eq(expected, error_code(error)))
'''


def candidate_program(cases,controls,work,lane):
    program = BEND_PROGRAM+'''def closure_loop(n: Nat) -> IO(Unit):
  match n:
    case 0n: emit_bytes(~&1, [1])
    case 1n+rest:
      do IO<Unit>:
'''
    closure = ('half-plain','invalid-7fc00000-last','truncated-3','read-error','large-file')
    by_name = {case['name']:case for case in cases+controls}
    for name in closure:
        case = by_name[name]
        program += f'        IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_raw({json.dumps(case["path"])}, {case["width"]}, {case["height"]}, 8, {case["header"]}), required({ERRORS.get(case["error"],0)}))\n'
    program += '        closure_loop(rest)\ndef main() -> IO(Unit):\n  do IO<Unit>:\n'
    for case in cases+controls:
        output = str((work/(lane+'-'+case['name']+'.raw')).relative_to(ROOT))
        program += f'    IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_raw({json.dumps(case["path"])}, {case["width"]}, {case["height"]}, {case["format"]}, {case["header"]}), loaded({json.dumps(output)}, {case["width"]}, {case["height"]}))\n'
    return program+'    closure_loop(100n)\n'


def main():
    args = probekit.arguments(__doc__)
    if args.gpu:raise SystemExit('r32_raw_file_probe has no forced-GPU variant (file IO runs on CPU lanes only)')
    probe = probekit.Probe('r32-raw-file',args);work = probe.work
    if sys.byteorder != 'little':raise ProbeFailure('R32 RAW native profile requires little-endian storage')
    cases,controls = fixture_specs();prepare_inputs(work,cases,controls)
    clear_outputs(work,cases,'reference')
    text = probe.native(reference_program(cases,work))
    # Native successes must equal the independently selected payload; failures print null.
    native = parse_rows(text,cases,native=True);verify_files(work,cases,'reference')
    everything = cases+controls
    # One row per load: its output and the complete file it re-exported (None if absent); then the closure marker.
    expected = [[native[i] if i < len(cases) and native[i] is not None else
                 [ERRORS[case['error']]] if case['error'] else image_row(case),
                 None if case['error'] else case['selected']] for i,case in enumerate(everything)]+[[[1],None]]
    lanes,rss = {},{}
    for lane,output,peak in limited_runs(probe,'candidate',candidate_program(cases,controls,work,'candidate'),
                                        before=lambda lane:clear_outputs(work,everything,'candidate')):
        files = [list(path.read_bytes()) if path.is_file() else None
                 for path in (work/('candidate-'+case['name']+'.raw') for case in everything)]
        lanes[lane] = [[row,files[i] if i < len(files) else None] for i,row in enumerate(parse_results(output))]
        if not 0 < peak <= MAX_RUNTIME_RSS:
            raise ProbeFailure(f'{lane}: bounded-read runtime RSS exceeded {MAX_RUNTIME_RSS} bytes: {peak}')
        rss[lane] = peak
    probe.compare(expected,lanes,lambda i:everything[i]['name'] if i < len(everything) else 'closure')
    probe.finish(native_cases=len(cases),native_successes=sum(not c['error'] for c in cases),
                 controls=sum(bool(c['error']) for c in controls),bounded_read_controls=sum(not c['error'] for c in controls),
                 sample_controls=sum(c['error']=='samples' for c in controls),closure_iterations=100,
                 closure_paths=['success','samples','truncated','read','size'],file_descriptor_limit=FILE_DESCRIPTOR_LIMIT,
                 maximum_runtime_rss_bytes=MAX_RUNTIME_RSS,maximum_rss_bytes=rss,
                 compared_payload_bytes=sum(len(c['selected']) for c in cases if not c['error']),
                 inputs_sha256=hashlib.sha256(json.dumps([cases,controls]).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
