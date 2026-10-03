#!/usr/bin/env python3
"""Reconstructed native-format P5/P6 file verification, with fresh run evidence.

Never submit malformed, oversized or special-file controls to native. Actual
LoadImage/explicit PNM routes are independent; observe raw bytes before RGBA8.
Historical lost evidence is not reused to validate this reconstruction.
"""
import argparse
import errno
from functools import partial
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid

import pnm_format_probe as memory
from byte_probe import BEND_EMITTER
from conformance import BUILD, ROOT, ENV, checkout, source_gate
from reference_environment import ReferenceEnvironment
from raw_file_probe import limit_handles
from r32_raw_file_probe import RESOURCE_RUNNER

BATCH_SIZE = 32
PNM_CAP = 1048576
MAX_SPARSE_RSS = 256*1024*1024
MAX_STRESS_RSS = 1024*1024*1024
LANES = memory.LANES
BASE_KEYS = {'id','bytes','width','height','channels','maximum','header_bytes','raster_bytes','extended'}
FILE_KEYS = {'filename','route','regress','path'}
RECOGNIZED = {'.png','.bmp','.tga','.pgm','.ppm','.jpg','.jpeg','.gif','.pic','.psd',
              '.PNG','.BMP','.TGA','.PGM','.PPM','.JPG','.JPEG','.GIF','.PIC','.PSD'}


def validate_cases(cases):
    if not cases:raise ValueError('Empty native file cases')
    for c in cases:
        if type(c) is not dict or not BASE_KEYS|{'filename','route','regress'}<=c.keys() or c.keys()-BASE_KEYS-FILE_KEYS:raise ValueError('Native file schema differs')
        if type(c['regress']) is not bool or type(c['filename']) is not str or not c['filename'] or '\0' in c['filename']:raise ValueError('Unsafe file name/regression flag')
        if Path(c['filename']).is_absolute() or '..' in Path(c['filename']).parts:raise ValueError('Escaping fixture filename')
        if c['route'] not in ('LoadImage','explicit-pnm'):raise ValueError('Unknown native PNM route')
        suffix=Path(c['filename']).name;index=suffix.rfind('.');suffix=suffix[index:] if index>=0 else ''
        recognized=suffix in RECOGNIZED
        if (c['route']=='LoadImage')!=recognized:raise ValueError('Native route does not match filename dispatch')
        if len(c['bytes'])>PNM_CAP:raise ValueError('Oversized native fixture')
        if 'path' in c and (type(c['path']) is not str or not c['path'] or '\0' in c['path']):raise ValueError('Unsafe native path')
    memory.validate_cases([{k:c[k] for k in BASE_KEYS} for c in cases])
    if len({c['filename'] for c in cases})!=len(cases):raise ValueError('Duplicate file fixture name')


def fixtures():
    cases=[dict(c,filename=c['id']+('.pgm' if c['channels']==1 else '.ppm'),route='LoadImage',regress=c['extended']) for c in memory.fixtures()]
    originals={c['id']:c for c in cases}
    suffixes=[('upper-pgm','.PGM'),('upper-ppm','.PPM'),('cross','.ppm'),('raster-alias','.png'),
              ('spaces',' with spaces.pgm'),('dots','.a.b.ppm'),('dotfile','/.pgm'),('jpg','.jpg'),('gif','.gif'),
              ('mixed','.PgM'),('pnm','.pnm'),('suffixless',''),('qoi','.qoi'),('unsupported','.dat'),('mixed-ppm','.PpM')]
    for channels in (1,3):
        for maximum in (255,256):
            original=originals[f'c{channels}-max{maximum}-single']
            for name,suffix in suffixes:
                if name=='cross':suffix='.ppm' if channels==1 else '.pgm'
                ident=f'path-c{channels}-max{maximum}-{name}'
                cases.append(dict(original,id=ident,filename=ident+suffix,route='LoadImage' if name in [n for n,_ in suffixes[:9]] else 'explicit-pnm',regress=True))
    validate_cases(cases);return cases


def controls():
    result=[dict(c,filename='error-'+c['id']+'.pgm') for c in memory.controls() if all(type(b) is int and 0<=b<=255 for b in c['bytes'])]
    for ident,data in [('not-pnm-qoi',b'qoif'+bytes(40)),('not-pnm-png',b'\x89PNG\r\n\x1a\n'+bytes(40)),('ascii-P3',b'P3\n1 1\n255\n0 0 0\n')]:
        result.append(dict(id=ident,filename=ident+'.ppm',bytes=list(data),error=0))
    for ident,filename,special,error in [('missing','missing.qoi','missing',5),('missing-parent','missing-parent/input.pnm','missing',5),('directory','directory.ppm','directory',5),('cap-plus-one','cap-plus-one.ppm','sparse',2),('cap-misleading','cap-plus-one.qoi','sparse',2),('larger-file','larger-file.pgm','large',2),('host-size-overflow','host-size-overflow.pnm','overflow',5)]:
        result.append(dict(id=ident,filename=filename,special=special,error=error))
    if len({c['id'] for c in result})!=len(result):raise ValueError('Duplicate control ID')
    return result


def prepare_inputs(work,cases,invalid):
    validate_cases(cases);directory_stage=None
    for c in cases+invalid:
        path=work/'fixtures'/c['filename'];c['path']=str(path.relative_to(ROOT));special=c.get('special')
        if special=='missing':
            if path.exists():raise ValueError('Missing fixture exists')
            continue
        path.parent.mkdir(parents=True,exist_ok=True)
        if special=='directory':
            path.mkdir();(path/'entry').write_bytes(b'x');fd=None;stage='open'
            try:
                fd=os.open(path,os.O_RDONLY);stage='size';os.fstat(fd);stage='read';os.read(fd,1)
                raise ValueError('Directory unexpectedly readable')
            except OSError as error:directory_stage=dict(stage=stage,code=error.errno,message=error.strerror)
            finally:
                if fd is not None:os.close(fd)
        elif special in ('sparse','large','overflow'):
            size={'sparse':PNM_CAP+1,'large':256*1024*1024,'overflow':4294967296}[special]
            prefix=list(memory.header()+b'\x7f')
            with path.open('wb') as handle:handle.write(bytes(prefix));handle.truncate(size)
            c.update(size=size,prefix=prefix,sparse_recipe='tiny valid prefix then truncate; holes never loaded or hashed')
        else:path.write_bytes(bytes(c['bytes']))
    original=next(c for c in cases if c['id']=='c1-max255-single')
    stress=dict(original,id='exact-cap-accepted',filename='exact-cap.pgm',regress=False)
    stress['bytes']=original['bytes']+[i%256 for i in range(PNM_CAP-len(original['bytes']))]
    path=work/'fixtures'/stress['filename'];stress['path']=str(path.relative_to(ROOT));path.write_bytes(bytes(stress['bytes']))
    validate_cases([stress]);return stress,directory_stage


def verify_inputs(cases,invalid,stress):
    # Missing and directory fixtures are intentionally not ordinary sealed files.
    for c in invalid:
        path=ROOT/c['path'];special=c.get('special')
        if special=='missing' and path.exists():raise ValueError('Missing fixture appeared')
        if special=='directory' and (not path.is_dir() or (path/'entry').read_bytes()!=b'x'):raise ValueError('Directory fixture drift')
        if special in ('sparse','large','overflow'):
            if not path.is_file() or path.stat().st_size!=c['size']:raise ValueError('Sparse size drift')
            with path.open('rb') as handle:
                if handle.read(len(c['prefix']))!=bytes(c['prefix']):raise ValueError('Sparse prefix drift')
    memory.verify_sealed()


def reference_program(cases):
    validate_cases(cases)
    lines=[memory.C_PREFIX,'int main(void){if(!little_endian())return 10;SetTraceLogLevel(LOG_NONE);']
    for c in cases:
        if 'path' not in c:raise ValueError('Native fixture path missing')
        path=json.dumps(c['path']);fmt=1 if c['channels']==1 else 4;raw_size=c['width']*c['height']*c['channels'];lines+=['{']
        if c['route']=='LoadImage':lines.append(f'Image image=LoadImage({path});')
        else:
            lines += [f'int size=0;unsigned char *data=LoadFileData({path},&size);',f'if(!data||size!={len(c["bytes"])}){{if(data)UnloadFileData(data);return 7;}}',
                      'Image image=LoadImageFromMemory(".ppm",data,size);UnloadFileData(data);']
        lines += ['if(!image.data)return 2;',f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(image.width,image.height,image.format)!={raw_size}){{UnloadImage(image);return 3;}}',
                  f'observed({json.dumps(c["id"])},"raw",image);','ImageFormat(&image,7);if(!image.data)return 4;',
                  f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!=7||GetPixelDataSize(image.width,image.height,image.format)!={c["width"]*c["height"]*4}){{UnloadImage(image);return 5;}}',
                  f'observed({json.dumps(c["id"])},"normalized",image);UnloadImage(image);','}']
    return '\n'.join(lines+['return 0;}'])+'\n'


BEND_PREFIX = memory.BEND_PREFIX.replace('import ../../../jonlib.bend as J', 'import '+str(ROOT/'jonlib.bend')+' as J').replace('def reverse_into(',BEND_EMITTER+'def reverse_into(',1)+r'''
def loaded(result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> Maybe<J.Image.Formatted>:
  match result:
    case Fail{_}: None{}
    case Done{image}: checked(image)
def surface.loaded(result: Result<&1, &1, J.Image.LoadError, J.Surface>) -> Maybe<J.Image.Formatted>:
  match result:
    case Fail{_}: None{}
    case Done{image}: Some{J.Surface.to_formatted(image)}
def load.error(error: J.Image.LoadError) -> U32:
  match error:
    case J.ImageFileError{_, _}: 5
    case J.ImageDecodeError{error}: error.code(error)
def load.emitted(id: String, role: String, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  observed(id, role, loaded(result))
def bridge.emitted(id: String, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  observed(id, "bridge", bridge(loaded(result)))
def surface.emitted(id: String, role: String, result: Result<&1, &1, J.Image.LoadError, J.Surface>) -> IO(Unit):
  observed(id, role, surface.loaded(result))
def load.failed(id: String, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Done{_}: emit.error(id, "formatted-error", 99)
    case Fail{error}: emit.error(id, "formatted-error", load.error(error))
def surface.failed(id: String, result: Result<&1, &1, J.Image.LoadError, J.Surface>) -> IO(Unit):
  match result:
    case Done{_}: emit.error(id, "surface-error", 99)
    case Fail{error}: emit.error(id, "surface-error", load.error(error))
def require(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "PNM file boundary or closure differs")
def required(expected: U32, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Done{_}: require(U32.is_eq(expected, 99))
    case Fail{error}: require(U32.is_eq(expected, load.error(error)))
def exact.error(code: U32, message: String, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Fail{J.ImageFileError{actual, text}}: require(U32.is_eq(code, actual) && String.eq(message, text))
    case _: require(False{})
def bytes.eq(actual: List<U32>, expected: +List<U32>) -> Bool:
  match actual expected:
    case Nil{} Nil{}: True{}
    case Con{a, rest} Con{b, tail}: U32.is_eq(a, b) && bytes.eq(rest, tail)
    case _ _: False{}
def success.exported(format: U32, bytes: +List<U32>, data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  match data:
    case Tuple{Tuple{3, 1}, Tuple{actual, values}}: require(U32.is_eq(format, actual) && bytes.eq(values, bytes))
    case _: require(False{})
def success.required(format: U32, bytes: +List<U32>, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Done{image}: success.exported(format, bytes, J.Image.Formatted.export(image))
    case _: require(False{})
def file.code.required(expected: U32, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Fail{J.ImageFileError{code, _}}: require(U32.is_eq(expected, code))
    case _: require(False{})
def file.failed(id: String, expected: U32, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  do IO<Unit>:
    file.code.required(expected, result)
    emit.error(id, "formatted-error", 5)
'''
BEND_PREFIX += r'''
def surface.pnm.loaded(result: Result<&1, &1, J.Image.LoadError, +List<U32>>) -> IO(Result<&1, &1, J.Image.LoadError, J.Surface>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, J.Image.LoadError, J.Surface>, Fail{error})
    case Done{bytes}: IO.pure(Result<&1, &1, J.Image.LoadError, J.Surface>, J.Image.file.decoded(J.Surface, J.Surface.decode_pnm(bytes)))
def surface.pnm(path: String) -> IO(Result<&1, &1, J.Image.LoadError, J.Surface>):
  IO.bind(Result<&1, &1, J.Image.LoadError, +List<U32>>, Result<&1, &1, J.Image.LoadError, J.Surface>, J.Image.file.bytes(path, J.Image.file.limit(J.RasterFile{})), surface.pnm.loaded)
def owner.emitted(id: String, +width: U32, +height: U32, first: U32, last: U32, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  observed(id, "owner", owner(loaded(result), width, height, first, last))
def stage.emitted(id: String, +expected: U32, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  do IO<Unit>:
    required(expected, result)
    emit.error(id, "formatted-error", expected)
def stage.exact(id: String, code: U32, message: String, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  do IO<Unit>:
    exact.error(code, message, result)
    emit.error(id, "formatted-error", 5)
def stage.loaded(id: String, expected: U32, result: Result<&1, &1, J.Image.LoadError, +List<U32>>) -> IO(Unit):
  IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Formatted>, Unit, J.Image.Formatted.pnm.file.loaded(result), stage.emitted(id, expected))
def stage.failed(id: String, code: U32, message: String, result: Result<&1, &1, J.Image.LoadError, +List<U32>>) -> IO(Unit):
  IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Formatted>, Unit, J.Image.Formatted.pnm.file.loaded(result), stage.exact(id, code, message))
def stage.opened(mode: U32, result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match mode result:
    case _ Fail{_}: IO.die(Unit, 1, "stage fixture open failed")
    case 0 Done{file}:
      IO.bind(Result<&1, &1, J.Image.LoadError, +List<U32>>, Unit, J.Image.file.read(2, (file, Done{[1]})), stage.loaded("stage-short", 3))
    case 1 Done{file}:
      IO.bind(Result<&1, &1, J.Image.LoadError, +List<U32>>, Unit, J.Image.file.read(2, (file, Fail{(731, "stage-read-failure")})), stage.failed("stage-read-failure", 731, "stage-read-failure"))
    case 2 Done{file}:
      IO.bind(Result<&1, &1, J.Image.LoadError, +List<U32>>, Unit, J.Image.file.sized(1048576, (file, Fail{(733, "stage-size-failure")})), stage.failed("stage-size-failure", 733, "stage-size-failure"))
    case _ Done{file}:
      IO.bind(Result<&1, &1, J.Image.LoadError, +List<U32>>, Unit, J.Image.file.read(1, (file, Done{[1, 2]})), stage.loaded("stage-long", 3))
'''


def candidate_actions(cases,invalid,reference):
    actions=[]
    for c in cases:
        raw,normal=reference[c['id']]
        roles=['raw']+(['owner','bridge','surface']+(['dispatch-ppm','uncontracted','fused'] if c['route']=='LoadImage' else []) if c['regress'] else [])
        for role in roles:
            actions.append(dict(case=c,role=role,expected=dict(raw if role in ('raw','owner') else normal,role=role),normalized=normal['bytes']))
        if c['regress'] and c['route']=='explicit-pnm':
            control=dict(c,id=c['id']+'-generic',error=0)
            actions.append(dict(case=control,role='surface-error',expected=dict(id=control['id'],role='surface-error',error=0)))
    actions += [dict(case=c,role='formatted-error',expected=dict(id=c['id'],role='formatted-error',error=c['error'])) for c in invalid]
    return actions


def candidate_program(actions):
    if not actions:raise ValueError('Empty file actions')
    lines=[BEND_PREFIX,'def main() -> IO(Unit):','  do IO<Unit>:']
    for a in actions:
        c=a['case'];role=a['role'];ident=json.dumps(c['id']);path=json.dumps(c['path']);output='J.Image.Formatted';call=f'J.Image.Formatted.load_pnm({path})'
        if role=='raw':continuation=f'load.emitted({ident}, "raw")'
        elif role=='owner':
            first=int.from_bytes(bytes(a['normalized'][:4]),'big');last=int.from_bytes(bytes(a['normalized'][-4:]),'big')
            continuation=f'owner.emitted({ident}, {c["width"]}, {c["height"]}, {first}, {last})'
        elif role=='bridge':continuation=f'bridge.emitted({ident})'
        elif role=='formatted-error':
            continuation=f'load.failed({ident})'
            code={'overflow':errno.EOVERFLOW,'directory':errno.EISDIR,'missing':errno.ENOENT}.get(c.get('special'))
            if code is not None:continuation=f'file.failed({ident}, {code})'
        elif role in ('surface','dispatch-ppm','uncontracted','fused','surface-error'):
            output='J.Surface';continuation=f'surface.emitted({ident}, {json.dumps(role)})'
            if role=='surface':call=f'surface.pnm({path})'
            elif role in ('dispatch-ppm','surface-error'):call=f'J.Surface.load_image({path})'
            else:call=f'J.Surface.load_image_for(J.{"UncontractedDecode" if role=="uncontracted" else "FusedDecode"}{{}}, {path})'
            if role=='surface-error':continuation=f'surface.failed({ident})'
        else:raise ValueError('Unknown file candidate role')
        lines.append(f'    IO.bind(Result<&1, &1, J.Image.LoadError, {output}>, Unit, {call}, {continuation})')
    return '\n'.join(lines)+'\n'


# Each closure action emits a framed record: a terminal claim alone cannot pass.
BOUNDARY_LOADS=('c1-max255-single','c3-max256-single','not-pnm-qoi','directory','cap-plus-one','host-size-overflow')
STAGES=(('stage-short',3),('stage-read-failure',5),('stage-size-failure',5),('stage-long',3))
SYNTHETIC=(('continuation-error',5),('payload-error',5),('payload-short',3),('payload-long',3),('invalid-byte',1),('empty-header',0),('bad-size',2),('wrapped-stream',4))
TERMINAL=dict(closure_checks=True,iterations=100,paths_per_iteration=10,synthetic_checks=8,records=1009)


def boundary_actions(cases,invalid,reference):
    by_id={c['id']:c for c in cases+invalid};actions=[]
    for ident,error in SYNTHETIC:
        c=dict(id=ident,error=error);actions.append(dict(case=c,role='formatted-error',expected=dict(id=ident,role='formatted-error',error=error)))
    cycle=[]
    for ident in BOUNDARY_LOADS:
        c=by_id[ident]
        if ident in reference:cycle.append(dict(case=c,role='raw',expected=reference[ident][0]))
        else:cycle.append(dict(case=c,role='formatted-error',expected=dict(id=ident,role='formatted-error',error=c['error'])))
    for ident,error in STAGES:
        c=dict(id=ident,error=error);cycle.append(dict(case=c,role='formatted-error',expected=dict(id=ident,role='formatted-error',error=error)))
    actions+=cycle*100
    c=dict(by_id['c1-max255-single'],id='closure-final');actions.append(dict(case=c,role='raw',expected=dict(reference['c1-max255-single'][0],id='closure-final')))
    return actions


def boundary_program(cases,invalid):
    by_id={c['id']:c for c in cases+invalid};loop_actions=[]
    for ident in BOUNDARY_LOADS:
        c=by_id[ident];loop_actions.append(dict(case=c,role='formatted-error' if 'error' in c else 'raw'))
    body=candidate_program(loop_actions).split('  do IO<Unit>:\n')[-1]
    lines=[BEND_PREFIX,'def closure_loop(n: Nat) -> IO(Unit):','  match n:','    case 0n: IO.pure(Unit, Unit{})','    case 1n+rest:','      do IO<Unit>:']
    lines += ['    '+line for line in body.rstrip().splitlines()]
    valid=json.dumps(by_id['c1-max255-single']['path'])
    for mode in range(4):lines.append(f'        IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open({valid}, "r"), stage.opened({mode}))')
    lines += ['        closure_loop(rest)','def main() -> IO(Unit):','  do IO<Unit>:',
              '    require(U32.is_eq(J.Image.file.limit(J.RasterFile{}), 1048576) && (1048576 <= J.Image.file.limit(J.RasterFile{}) : U32) && Bool.not((1048577 <= J.Image.file.limit(J.RasterFile{}) : U32)))',
              '    require(J.Image.file.complete(0n, Nil{}) && J.Image.file.complete(2n, [1, 2]) && Bool.not(J.Image.file.complete(2n, [1])) && Bool.not(J.Image.file.complete(1n, [1, 2])))']
    synthetic=[('Fail{J.ImageFileError{719, "continuation-failure"}}','stage.exact("continuation-error", 719, "continuation-failure")'),
               ('J.Image.file.payload(2, Fail{(727, "payload-failure")})','stage.exact("payload-error", 727, "payload-failure")'),
               ('J.Image.file.payload(2, Done{[1]})','stage.emitted("payload-short", 3)'),
               ('J.Image.file.payload(1, Done{[1, 2]})','stage.emitted("payload-long", 3)'),
               ('Done{[256]}','stage.emitted("invalid-byte", 1)'),('Done{Nil{}}','stage.emitted("empty-header", 0)'),
               ('Done{'+memory.bend_bytes(list(memory.header(width=0)))+'}','stage.emitted("bad-size", 2)')]
    for value,continuation in synthetic:
        lines.append(f'    IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Formatted>, Unit, J.Image.Formatted.pnm.file.loaded({value}), {continuation})')
    lines += ['    stage.emitted("wrapped-stream", 4, J.Image.file.decoded(J.Image.Formatted, Fail{J.InvalidImageStream{}}))',
              '    closure_loop(100n)',f'    IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Formatted>, Unit, J.Image.Formatted.load_pnm({valid}), load.emitted("closure-final", "raw"))',
              '    IO.print('+json.dumps(json.dumps(TERMINAL,separators=(',',':')))+')']
    return '\n'.join(lines)+'\n'


def parse_boundary(text,actions):
    lines=text.splitlines();row=memory.strict_json(lines[-1]) if lines else None
    if type(row) is not dict or row!=TERMINAL or any(type(row.get(k)) is not type(v) for k,v in TERMINAL.items()):raise ValueError('Missing strict PNM closure terminal')
    if len(actions)!=TERMINAL['records']:raise ValueError('Boundary expected count differs')
    actual=memory.parse_rows('\n'.join(lines[:-1]),actions)
    if memory.differences([a['expected'] for a in actions],actual):raise ValueError('Closure record differs')
    return row


def tracked_sources(args):
    result=memory.tracked_sources(args)
    for name in ('tools/pnm_file_probe.py','tests/test_pnm_file_harness.py','tools/raw_file_probe.py','tools/r32_raw_file_probe.py'):
        path=ROOT/name;result['dependencies'][str(path)]=memory.digest(path)
    return result


def report_directories(argv):
    result=[];index=0;rules=argparse.ArgumentParser(add_help=False,allow_abbrev=False)
    while index<len(argv):
        token=argv[index]
        if token=='--':break
        if token.startswith('--build-dir='):result.append(Path(token.partition('=')[2]))
        elif token=='--build-dir' and index+1<len(argv) and rules._parse_optional(argv[index+1]) is None:index+=1;result.append(Path(argv[index]))
        index+=1
    return result or [BUILD/'pnm-file-probe']


def admit_directories(argv):
    paths=report_directories(argv)
    for path in dict.fromkeys(p.resolve() for p in paths):
        path.mkdir(parents=True,exist_ok=True);(path/'results.json').write_text('{"passed":false,"phase":"argument-validation"}\n')
    return paths[-1].resolve()


def record_run(command,work,label,*,timeout=600,environment=None,receipt=None,require_output=False,descriptor_limit=None):
    """Sealed local recorder with ownership of compiler/runtime descendants.

    Every invocation runs in a new POSIX session. Timeout or interruption kills
    the whole owned group, including Bun's Clang child or resource candidates.
    Shared published runners remain unchanged.
    """
    if os.name!='posix':raise ValueError('Process-group profile requires POSIX')
    if timeout<=0:raise ValueError('Timeout must be positive')
    memory.verify_sealed();command=list(map(str,command))
    outputs=[Path(command[i+1]) for i,arg in enumerate(command[:-1]) if arg=='-o']
    for arg in command:
        path=Path(arg)
        if path not in outputs and path.is_file():memory.seal(path)
    for path in outputs:path.unlink(missing_ok=True)
    for ext in ('stdout','stderr','command.json'):(work/(label+'.'+ext)).unlink(missing_ok=True)
    started=time.monotonic();timed_out=False;interrupted=None;process=None;output='';error='';exit_code=None
    def cleanup():
        if process is not None:
            try:os.killpg(process.pid,signal.SIGKILL)
            except ProcessLookupError:pass
    try:
        process=subprocess.Popen(command,cwd=ROOT,env=ENV if environment is None else environment,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
        try:output,error=process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out=True;cleanup();output,error=process.communicate(timeout=5)
        except BaseException as failure:
            interrupted=failure;cleanup();output,error=process.communicate(timeout=5)
        exit_code=process.returncode
    except OSError as failure:
        interrupted=failure;error=str(failure)
    finally:cleanup()
    row=dict(command=command,exit_code=exit_code,timed_out=timed_out,timeout=timeout,elapsed_seconds=round(time.monotonic()-started,3),reference_environment=receipt,process_group_owned=True,process_group_cleanup='SIGKILL after completion or timeout',descriptor_limit=descriptor_limit)
    if interrupted is not None:row['interrupted_or_startup_error']=type(interrupted).__name__
    for ext,value in [('stdout',output),('stderr',error),('command.json',json.dumps(row,indent=2)+'\n')]:
        path=work/(label+'.'+ext);path.write_text(value);memory.seal(path)
    if interrupted is not None:raise interrupted
    if timed_out:raise ValueError('PNM process group timed out: '+label)
    if exit_code:raise ValueError(f'{label} exited {exit_code}: {error[-2000:]}')
    if require_output and not output.strip():raise ValueError('Process output missing')
    if any(not p.is_file() or p.stat().st_size==0 for p in outputs):raise ValueError('Compiler output missing')
    for path in outputs:memory.seal(path)
    return output


def record_resource(command,work,label,**options):
    # Only resource_run's launcher actually sets RLIMIT_NOFILE to 64.
    options.setdefault('require_output',True)
    return record_run(command,work,label,descriptor_limit=64,**options)


def resource_run(command,work,label,ceiling,environment,receipt,timeout):
    if type(ceiling) is not int or ceiling not in (MAX_SPARSE_RSS,MAX_STRESS_RSS):raise ValueError('Unknown resource ceiling')
    usage=work/(label+'.resource.json');usage.unlink(missing_ok=True)
    # This thin launcher owns RLIMIT before its fresh measurement child starts.
    launcher=work/(label+'.resource-runner.py')
    launcher.write_text('import resource\nresource.setrlimit(resource.RLIMIT_NOFILE,(64,64))\n'+RESOURCE_RUNNER)
    memory.seal(launcher);began=time.monotonic()
    output=record_resource([sys.executable,launcher,usage,*command],work,label,timeout=timeout,environment=environment,receipt=receipt,require_output=True)
    if not usage.is_file():raise ValueError('Missing resource receipt')
    memory.seal(usage);value=memory.strict_json(usage.read_text())
    if type(value) is not dict or set(value)!={'maximum_rss_bytes'} or type(value['maximum_rss_bytes']) is not int or not 0<value['maximum_rss_bytes']<=ceiling:raise ValueError('Invalid/excessive child RSS')
    return output,dict(**value,elapsed_seconds=round(time.monotonic()-began,3),descriptor_limit=64,maximum_rss_acceptance_bytes=ceiling)


def finish_lanes(lanes,actions):
    memory.finish_lanes(lanes,actions)
    for lane in LANES:
        lanes[lane]['passed']=False
        for kind in ('boundary','sparse','exact_cap'):
            result=lanes[lane].get(kind,{})
            if result.get('passed') is not True or type(result.get('descriptor_limit')) is not int or result['descriptor_limit']!=64:raise ValueError('Missing file resource lane')
            ceiling=MAX_STRESS_RSS if kind=='exact_cap' else MAX_SPARSE_RSS
            rss=result.get('maximum_rss_bytes')
            if type(rss) is not int or not 0<rss<=ceiling or type(result.get('maximum_rss_acceptance_bytes')) is not int or result['maximum_rss_acceptance_bytes']!=ceiling:raise ValueError('Incomplete resource acceptance receipt')
        lanes[lane]['passed']=True


def main(argv=None):
    argv=list(sys.argv[1:] if argv is None else argv);admitted=admit_directories(argv)
    parser=argparse.ArgumentParser(description=__doc__,allow_abbrev=False)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    parser.add_argument('--build-dir',type=Path,default=BUILD/'pnm-file-probe')
    parser.add_argument('--reference-env',choices=('clean-loader',),default='clean-loader');parser.add_argument('--timeout',type=int,default=600)
    args=parser.parse_args(argv);destination=args.build_dir.resolve()
    if destination!=admitted:parser.error('Destination admission differs')
    if args.timeout<=0:parser.error('--timeout must be positive')
    memory.SEALED.clear();reference_env=ReferenceEnvironment(args.reference_env);reference_env.require_clear()
    record=partial(record_run,timeout=args.timeout);native_record=partial(record,environment=reference_env.child(),receipt=reference_env.receipt())
    report_path=destination/'results.json';work=destination/('run-'+uuid.uuid4().hex);work.mkdir()
    started=time.monotonic();lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    if sys.byteorder!='little':raise ValueError('PNM requires little-endian profile')
    cases,invalid=fixtures(),controls();stress,directory_stage=prepare_inputs(work,cases,invalid)
    if directory_stage is None or directory_stage['stage']!='read' or directory_stage['code']!=errno.EISDIR:raise ValueError('Unqualified directory/read profile')
    inputs=work/'inputs.json';inputs.write_text(json.dumps(dict(cases=cases,controls=invalid,exact_cap=stress),sort_keys=True)+'\n');memory.seal(inputs)
    for c in cases+invalid+[stress]:
        if not c.get('special'):memory.seal(ROOT/c['path'])
    tool_paths={}
    for tool in ('bun','clang','cmake'):
        path=shutil.which(tool)
        if path is None:raise ValueError('Required tool missing: '+tool)
        tool_paths[tool]=str(Path(path).absolute());memory.seal(path)
    tool_realpaths={k:str(Path(p).resolve()) for k,p in tool_paths.items()}
    report=dict(passed=False,profile='native-pnm-formatted-files-reconstructed-v1',evidence_origin='NEW reconstruction run; lost historical report is not verification',run_directory=str(work),toolchain=lock,base_revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),host=dict(system=platform.system(),machine=platform.machine()),tool_paths=tool_paths,tool_realpaths=tool_realpaths,sources=tracked_sources(args),reference_environment=reference_env.receipt(),inputs_sha256=memory.digest(inputs),cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),typed_controls=len(invalid),native_rejections=0,native_routes={r:sum(c['route']==r for c in cases) for r in ('LoadImage','explicit-pnm')},batch_size=BATCH_SIZE,lanes={lane:dict(passed=False,batches=[],differences=[]) for lane in LANES},candidate_mipmaps='implicit single-mip type contract, not stored/measured',closure=TERMINAL,file_descriptor_limit=64,host_directory_observation=directory_stage,unrun=['GPU/Metal','Windows/macOS/browser','big-endian','exact-commit hosted CI','maximum-area allocation/resource limits','representative performance','concurrent/special files','OS close-error reporting','generic formatted/float dispatch','native malformed recovery'])
    for path in [*(ROOT/p for p in report['sources']['library']),*(Path(p) for p in report['sources']['dependencies'])]:memory.seal(path)
    def save():report_path.write_text(json.dumps(report,indent=2)+'\n')
    def verify():
        reference_env.assert_receipt(report['reference_environment']);verify_inputs(cases,invalid,stress)
        if tracked_sources(args)!=report['sources']:raise ValueError('PNM file source/toolchain drift')
        if any(shutil.which(k) is None or str(Path(shutil.which(k)).absolute())!=p or str(Path(shutil.which(k)).resolve())!=tool_realpaths[k] for k,p in tool_paths.items()):raise ValueError('Tool resolution drift')
    save();archive,report['native_build']=memory.native_archive(args,work,native_record);save()
    report['bun_version']=record(['bun','--version'],work,'bun-version',require_output=True).strip()
    if report['bun_version']!=lock['bun']['version']:raise ValueError('Bun version differs')
    report['clang_version']=native_record(['clang','--version'],work,'clang-version',require_output=True).strip()
    # Fresh native qualification precedes every accepted file observation.
    for name,program in [('qualification',memory.QUALIFY),('reference',reference_program(cases)),('exact-cap-reference',reference_program([stress]))]:
        verify();source=work/(name+'.c');source.write_text(program);memory.seal(source);binary=work/name
        native_record(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,archive,'-lm','-o',binary],work,name+'-compile')
        output=native_record([binary],work,name,require_output=True)
        if name=='qualification':report['qualification']=memory.qualification(output)
        else:
            selected=cases if name=='reference' else [stress]
            rows=memory.parse_rows(output,[dict(case=c,role=role) for c in selected for role in ('raw','normalized')])
            reference={c['id']:(rows[2*i],rows[2*i+1]) for i,c in enumerate(selected)}
            report[name+'_sha256']=hashlib.sha256(output.encode()).hexdigest()
            if name=='reference':file_reference=reference
            else:stress_reference=reference
    actions=candidate_actions(cases,invalid,file_reference)
    report.update(native_observations=2*len(cases),native_raw_bytes=sum(len(raw['bytes']) for raw,_ in file_reference.values()),native_normalized_bytes=sum(len(normal['bytes']) for _,normal in file_reference.values()),observations_per_lane=len(actions),compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions),exact_cap=dict(size=PNM_CAP,native_reference=stress_reference[stress['id']][0]));save()
    for start in range(0,len(actions),BATCH_SIZE):
        verify();selected=actions[start:start+BATCH_SIZE];index=start//BATCH_SIZE
        source=work/f'candidate-{index}.bend';source.write_text(candidate_program(selected));memory.seal(source);binary=work/f'candidate-{index}';js=work/f'candidate-{index}.js'
        record(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary,'-o',js],work,f'compile-{index}')
        for lane in LANES:
            command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            actual=memory.parse_rows(record(command,work,f'{lane}-{index}',require_output=True),selected);delta=memory.differences([a['expected'] for a in selected],actual)
            report['lanes'][lane]['differences'].extend(delta);report['lanes'][lane]['batches'].append(dict(start=start,count=len(selected),bytes=sum(len(r.get('bytes',[])) for r in actual),passed=not delta));save()
        print(f'PNM file batch {index+1}: {len(selected)} observations compared on CPU-1/CPU-2/JavaScript',flush=True)
    boundary=boundary_actions(cases,invalid,file_reference)
    stress_actions=candidate_actions([stress],[],stress_reference)
    sparse_actions=[dict(case=c,role='formatted-error',expected=dict(id=c['id'],role='formatted-error',error=c['error'])) for c in invalid if c.get('special') in ('sparse','large','overflow')]
    for kind,program,ceiling in [('boundary',boundary_program(cases,invalid),MAX_SPARSE_RSS),('sparse',candidate_program(sparse_actions),MAX_SPARSE_RSS),('exact_cap',candidate_program(stress_actions),MAX_STRESS_RSS)]:
        verify();source=work/(kind+'.bend');source.write_text(program);memory.seal(source);binary=work/kind;js=work/(kind+'.js')
        record(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary,'-o',js],work,kind+'-compile')
        for lane in LANES:
            command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            output,usage=resource_run(command,work,lane+'-'+kind,ceiling,ENV,None,min(args.timeout,240))
            if kind=='boundary':parse_boundary(output,boundary)
            else:
                expected=stress_actions if kind=='exact_cap' else sparse_actions
                if memory.parse_rows(output,expected)!=[a['expected'] for a in expected]:raise ValueError('Resource control bytes/error differ')
            report['lanes'][lane][kind]=dict(passed=True,**usage);save()
        print('PNM file '+kind+': all three lanes passed',flush=True)
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision']);verify()
    finish_lanes(report['lanes'],actions);memory.verify_sealed()
    report.update(passed=True,elapsed_seconds=round(time.monotonic()-started,3),sealed_artifacts=dict(memory.SEALED));save()
    print(f'PASS: {len(cases)} native PNM files, {len(invalid)} checked-only typed controls, {report["compared_bytes_per_lane"]} bytes per lane',flush=True)


if __name__=='__main__':main()
