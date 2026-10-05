#!/usr/bin/env python3
"""Native-format PIC file verification, with fresh source-scoped evidence.

Never submit malformed, oversized or special-file controls to native. Actual
LoadImage/explicit PIC routes are independent; observe raw bytes before RGBA8.
All file-eligible memory streams are reused unchanged as sealed files. The
uncapped memory positive above 1 MiB remains an exact pre-read rejection control.
The unchanged PIC safety scan admits native inputs; malformed controls are never
submitted to native. Nonbyte controls retain exact U32 values in continuations.
"""
import argparse
import errno
from functools import partial
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import shutil
import shlex
import subprocess
import sys
import time
import uuid

import pic_format_probe as memory
from byte_probe import BEND_EMITTER
from conformance import BUILD, ROOT, ENV, checkout, source_gate
from reference_environment import ReferenceEnvironment
from r32_raw_file_probe import RESOURCE_RUNNER
from pic_probe import pic
from png_probe import png
from bmp_probe import bitmap
from qoi_format_probe import stream as qoi_stream
from tga_format_probe import targa

BATCH_SIZE = 32
PIC_CAP = 1048576
MAX_SPARSE_RSS = 256*1024*1024
MAX_STRESS_RSS = 1024*1024*1024
LANES = memory.LANES
BASE_KEYS = {'id','bytes','width','height','channels','extended'}
FILE_KEYS = {'filename','route','regress','path'}
# Only these exact-case aliases are admitted to actual LoadImage; every macro
# is explicitly enabled and checked in both CMake and compiled flags below.
ALIAS_MACROS = ('BMP','PNG','TGA','JPG','GIF','PIC','PNM','PSD')
ALIAS_NAMES = ('bmp','png','tga','jpg','jpeg','gif','pic','pgm','ppm','psd')
RECOGNIZED = {'.'+name for name in ALIAS_NAMES} | {'.'+name.upper() for name in ALIAS_NAMES}
SOURCE_BYTE_LIMIT = memory.SOURCE_BYTE_LIMIT
# File dispatch/read provenance augments, rather than replaces, every pinned
# PIC memory decoder range. Never infer native file dispatch from memory tests.
FILE_SOURCE_RANGES = {'src/rtextures.c': [(263,293),(411,472)],
                      'src/rcore.c': [(1966,2030),(2475,2482)],
                      'src/external/stb_image.h': [(1755,1790)]}
FILE_SOURCE_SHA256 = {'src/rtextures.c': memory.SOURCE_SHA256['src/rtextures.c'],
                      'src/rcore.c': '502c3656661d07aa117a1f4b97dbfdd4a9b12cda6ee8eb4ab7afd31b657b5dd2',
                      'src/external/stb_image.h': memory.SOURCE_SHA256['src/external/stb_image.h']}


def validate_reference_sources(root):
    result=memory.validate_reference_sources(root)
    for relative,ranges in FILE_SOURCE_RANGES.items():
        data=(Path(root)/relative).read_bytes()
        if hashlib.sha256(data).hexdigest()!=FILE_SOURCE_SHA256[relative]:raise ValueError('Pinned PIC file oracle source differs: '+relative)
        lines=data.splitlines(keepends=True)
        entry=result.setdefault(relative,dict(sha256=FILE_SOURCE_SHA256[relative],ranges=[]))
        entry['ranges'].extend(dict(first=first,last=last,sha256=hashlib.sha256(b''.join(lines[first-1:last])).hexdigest()) for first,last in ranges)
    return result


def tiny_pic():
    return list(pic(1,1,[(0xe0,[0x0c22384e])]))


def extension(path):
    """Pinned GetFileExtension: last dot of the WHOLE path, excluding index 0."""
    if type(path) is not str or '\0' in path:raise ValueError('Unsafe extension path')
    index=path.rfind('.')
    return path[index:] if index>0 else ''


def validate_fixture_names(cases):
    """Reserve the whole fixture namespace before IO, also on casefolding hosts.

    Include missing paths, directories and their generated entries: none may
    alias an ordinary, sparse or stress file, or change a parent directory's
    spelling. This is a conservative name check, not host qualification.
    """
    nodes={};claimed=set()
    for c in cases:
        entries=[(c['filename'],c.get('special')=='directory')]
        if c.get('special')=='directory':entries.append((c['filename']+'/entry',False))
        for filename,is_directory in entries:
            parts=Path(filename).parts
            if not parts:raise ValueError('Empty fixture path')
            for index in range(1,len(parts)+1):
                name=Path(*parts[:index]).as_posix();key=name.casefold()
                directory=index<len(parts) or is_directory
                if key in nodes and nodes[key]!=(name,directory):
                    raise ValueError('Casefold fixture path collision: '+name)
                nodes[key]=(name,directory)
            if key in claimed:raise ValueError('Duplicate/casefold fixture name: '+filename)
            claimed.add(key)


def validate_cases(cases):
    if type(cases) is not list or not cases:raise ValueError('Empty native file cases')
    for c in cases:
        if type(c) is not dict or not BASE_KEYS|{'filename','route','regress'}<=c.keys() or c.keys()-BASE_KEYS-FILE_KEYS:raise ValueError('Native file schema differs')
        if type(c['regress']) is not bool or type(c['filename']) is not str or not c['filename'] or '\0' in c['filename']:raise ValueError('Unsafe file name/regression flag')
        if Path(c['filename']).is_absolute() or '..' in Path(c['filename']).parts:raise ValueError('Escaping fixture filename')
        if type(c['route']) is not str or c['route'] not in ('LoadImage','explicit-pic'):raise ValueError('Unknown native PIC route')
        if 'path' in c and (type(c['path']) is not str or not c['path'] or '\0' in c['path']):raise ValueError('Unsafe native path')
        # Real files are always directory-qualified. A whole-path literal .pic
        # is a separate token contract; it is not the path used by these files.
        path=c.get('path','fixtures/'+c['filename'])
        recognized=extension(path) in RECOGNIZED
        if (c['route']=='LoadImage')!=recognized:raise ValueError('Native route does not match whole-path dispatch')
        if type(c['bytes']) is not list or len(c['bytes'])>PIC_CAP:raise ValueError('Oversized native fixture')
    memory.validate_cases([{k:c[k] for k in BASE_KEYS} for c in cases])
    validate_fixture_names(cases)


def fixtures():
    cases=[dict(c,filename=c['id']+'.pic',route='LoadImage',regress=c['extended']) for c in memory.fixtures() if len(c['bytes'])<=PIC_CAP]
    originals={c['id']:c for c in cases}
    suffixes=[(name+'-'+case,'.'+(name if case=='lower' else name.upper()))
              for name in ALIAS_NAMES for case in ('lower','upper')]
    suffixes += [('mixed','.PiC'),('mixed-jpeg','.JpEg'),('pnm','.pnm'),('PNM','.PNM'),
                 ('qoi','.qoi'),('QOI','.QOI'),('arbitrary','.dat'),('suffixless',''),
                 ('trailing-dot','.'),('spaces',' with spaces.pic'),('dots','.a.b.pic'),
                 ('dotfile','/.pic'),('dotfile-unsupported','/.dat'),
                 ('directory-dot','.pic/leaf'),('dotted-parent','.folder/leaf.pic')]
    for channels in (3,4):
        original=originals[f'c{channels}-single']
        for name,suffix in suffixes:
            ident=f'path-c{channels}-{name}';filename=ident+suffix
            # Keep stable IDs and exact suffixes without aliasing lower-case
            # fixtures on the case-insensitive hosted macOS filesystem.
            if name in ('PNM','QOI'):filename=ident+'-upper'+suffix
            cases.append(dict(original,id=ident,filename=filename,route='LoadImage' if extension('fixtures/'+filename) in RECOGNIZED else 'explicit-pic',regress=True))
    validate_cases(cases);return cases


def controls():
    result=[dict(c,filename='error-'+c['id']+'.pic') for c in memory.controls() if all(type(b) is int and 0<=b<=255 for b in c['bytes'])]
    inherited=next(c for c in memory.fixtures() if c['id']=='encoded-over-one-mib')
    result.append(dict(id=inherited['id'],bytes=inherited['bytes'],filename='error-encoded-over-one-mib.pic',error=2))
    # These other-codec byte streams remain candidate-only. Native .pic chooses
    # stb content detection and is not a content-exclusive PIC oracle.
    other_codecs=[('not-pic-qoi',qoi_stream(1,1,4,0,[255,12,34,56,78])),
                  ('not-pic-bmp',bitmap(1,1,[0x12345678])),
                  ('not-pic-png',list(png(1,1,6,bytes([12,34,56,78])))),
                  ('not-pic-tga',targa(1,1,4,[12,34,56,78]))]
    for ident,data in other_codecs:
        result.append(dict(id=ident,filename=ident+'.pic',bytes=list(data),error=0))
    for ident,filename,special,error in [('missing','missing.qoi','missing',5),('missing-parent','missing-parent/input.pic','missing',5),('directory','directory.pic','directory',5),('cap-plus-one','cap-plus-one.pic','sparse',2),('cap-misleading','cap-plus-one.qoi','sparse',2),('larger-file','larger-file.pic','large',2),('host-size-overflow','host-size-overflow.pic','overflow',5)]:
        result.append(dict(id=ident,filename=filename,special=special,error=error))
    if len({c['id'] for c in result})!=len(result):raise ValueError('Duplicate control ID')
    return result



def synthetic_controls():
    """Unrepresentable U32 words retain exact values in continuation-only controls."""
    result=[dict(c) for c in memory.controls() if any(v>255 for v in c['bytes'])]
    memory.validate_controls(result)
    return result


def validate_controls(cases):
    if type(cases) is not list:raise ValueError('Malformed file control sequence')
    ids=set()
    for c in cases:
        required={'id','filename','error'};special=c.get('special') if type(c) is dict else None
        allowed=required|{'path','special','size','prefix','sparse_recipe'} if special is not None else required|{'path','bytes'}
        if type(c) is not dict or not required<=c.keys() or c.keys()-allowed:raise ValueError('File control schema differs')
        if type(c['id']) is not str or re.fullmatch(r'[A-Za-z0-9_-]+',c['id']) is None or c['id'] in ids:raise ValueError('Unsafe/duplicate file control ID')
        ids.add(c['id'])
        if type(c['filename']) is not str or not c['filename'] or '\0' in c['filename'] or Path(c['filename']).is_absolute() or '..' in Path(c['filename']).parts:raise ValueError('Unsafe file control filename')
        if 'path' in c and (type(c['path']) is not str or not c['path'] or '\0' in c['path']):raise ValueError('Unsafe file control path')
        if type(c['error']) is not int or c['error'] not in range(6):raise ValueError('Unsafe file control error')
        if c['id']=='encoded-over-one-mib' and special is not None:raise ValueError('Inherited memory-positive cap control must remain an exact ordinary file')
        if special is None:
            if 'bytes' not in c:raise ValueError('Missing file control bytes')
            if c['id']=='encoded-over-one-mib':
                original=next(v for v in memory.fixtures() if v['id']==c['id'])
                if type(c['bytes']) is not list or len(c['bytes'])!=PIC_CAP+1 or c['bytes']!=original['bytes'] or any(type(v) is not int or not 0<=v<=255 for v in c['bytes']) or c['error']!=2:raise ValueError('Inherited memory-positive cap control differs')
                memory.inspect_header(c['bytes'])
            else:
                if type(c['bytes']) is not list or len(c['bytes'])>PIC_CAP:raise ValueError('Oversized ordinary malformed control changes pre-read error')
                memory.validate_controls([{k:c[k] for k in ('id','bytes','error')}])
            if any(v>255 for v in c['bytes']):raise ValueError('Nonbyte value must remain synthetic/memory-only')
        else:
            expected={'missing':5,'directory':5,'sparse':2,'large':2,'overflow':5}
            if type(special) is not str or special not in expected or c['error']!=expected[special]:raise ValueError('File control kind/error differs')
            if special not in ('sparse','large','overflow') and c.keys() & {'size','prefix','sparse_recipe'}:raise ValueError('Unexpected non-sparse recipe')
            if special in ('sparse','large','overflow') and c.keys() & {'size','prefix','sparse_recipe'}:
                if not {'size','prefix','sparse_recipe'}<=c.keys():raise ValueError('Incomplete sparse file recipe')
                size={'sparse':PIC_CAP+1,'large':256*1024*1024,'overflow':4294967296}[special]
                if type(c['size']) is not int or c['size']!=size or c.get('prefix')!=tiny_pic() or any(type(v) is not int for v in c['prefix']):raise ValueError('Sparse file control recipe differs')
                if c.get('sparse_recipe')!='tiny valid prefix then truncate; holes never loaded or hashed':raise ValueError('Sparse file control recipe missing')
    validate_fixture_names(cases)


def prepare_inputs(work,cases,invalid):
    validate_cases(cases);validate_controls(invalid);directory_stage=None
    original=next(c for c in cases if c['id']=='c3-single')
    stress=dict(original,id='exact-cap-accepted',filename='exact-cap.pic',regress=False)
    stress['bytes']=original['bytes']+[i%256 for i in range(PIC_CAP-len(original['bytes']))]
    validate_cases([stress]);validate_fixture_names(cases+invalid+[stress])
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
            size={'sparse':PIC_CAP+1,'large':256*1024*1024,'overflow':4294967296}[special]
            prefix=tiny_pic()
            with path.open('wb') as handle:handle.write(bytes(prefix));handle.truncate(size)
            c.update(size=size,prefix=prefix,sparse_recipe='tiny valid prefix then truncate; holes never loaded or hashed')
        else:path.write_bytes(bytes(c['bytes']))
    path=work/'fixtures'/stress['filename'];stress['path']=str(path.relative_to(ROOT));path.write_bytes(bytes(stress['bytes']))
    validate_cases([stress]);return stress,directory_stage


def verify_inputs(cases,invalid,stress):
    validate_cases(cases);validate_cases([stress]);validate_controls(invalid)
    validate_fixture_names(cases+invalid+[stress])
    for c in cases+[stress]:
        path=ROOT/c['path']
        if not path.is_file() or path.read_bytes()!=bytes(c['bytes']):raise ValueError('Native file identity drift')
    # Missing and directory fixtures are intentionally not ordinary sealed files.
    for c in invalid:
        path=ROOT/c['path'];special=c.get('special')
        if special is None and (not path.is_file() or path.read_bytes()!=bytes(c['bytes'])):raise ValueError('File control identity drift')
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
        path=json.dumps(c['path']);fmt=memory.FORMATS[c['channels']];raw_size=c['width']*c['height']*c['channels'];lines+=['{']
        if c['route']=='LoadImage':lines.append(f'Image image=LoadImage({path});')
        else:
            lines += [f'int size=0;unsigned char *data=LoadFileData({path},&size);',f'if(!data||size!={len(c["bytes"])}){{if(data)UnloadFileData(data);return 7;}}',
                      'Image image=LoadImageFromMemory(".pic",data,size);UnloadFileData(data);']
        lines += ['if(!image.data)return 2;',f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!={fmt}||GetPixelDataSize(image.width,image.height,image.format)!={raw_size}){{UnloadImage(image);return 3;}}',
                  f'observed({json.dumps(c["id"])},"raw",image);','ImageFormat(&image,7);if(!image.data)return 4;',
                  f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!=7||GetPixelDataSize(image.width,image.height,image.format)!={c["width"]*c["height"]*4}){{UnloadImage(image);return 5;}}',
                  f'observed({json.dumps(c["id"])},"normalized",image);UnloadImage(image);','}']
    return '\n'.join(lines+['return 0;}'])+'\n'


def native_actions(cases):
    return [dict(case=c,role=role) for c in cases for role in ('raw','normalized')]


def native_partition_entry(cases,start,count,program):
    selected=cases[start:start+count];actions=native_actions(selected)
    return dict(start=start,count=count,observations=len(actions),source_bytes=len(program),
                source_sha256=hashlib.sha256(program).hexdigest(),
                cases_sha256=hashlib.sha256(json.dumps(selected,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
                compared_bytes=sum(a['case']['width']*a['case']['height']*(a['case']['channels'] if a['role'] in memory.RAW_ROLES else 4) for a in actions))


def validate_native_partitions(cases,partitions):
    validate_cases(cases)
    if type(partitions) is not list or not partitions:raise ValueError('Empty native PIC partition plan')
    cursor=0
    for part in partitions:
        if type(part) is not dict or set(part)!={'start','count','observations','source_bytes','source_sha256','cases_sha256','compared_bytes'}:raise ValueError('Native PIC partition schema differs')
        if any(type(part[k]) is not int for k in ('start','count','observations','source_bytes','compared_bytes')):raise ValueError('Native PIC partition integer types differ')
        if part['start']!=cursor or part['count']<1 or cursor+part['count']>len(cases) or not 1<=part['observations']<=BATCH_SIZE or not 0<part['source_bytes']<=SOURCE_BYTE_LIMIT:raise ValueError('Native PIC partition order or budget differs')
        program=reference_program(cases[cursor:cursor+part['count']]).encode()
        if part!=native_partition_entry(cases,cursor,part['count'],program):raise ValueError('Native PIC partition source/input identity differs')
        cursor+=part['count']
    if cursor!=len(cases):raise ValueError('Incomplete native PIC partition coverage')


def plan_native_partitions(cases):
    validate_cases(cases);plan=[];start=0
    while start<len(cases):
        chosen=None
        for count in range(1,min(BATCH_SIZE,len(cases)-start)+1):
            selected=cases[start:start+count]
            if len(native_actions(selected))>BATCH_SIZE:break
            program=reference_program(selected).encode()
            if not program or len(program)>SOURCE_BYTE_LIMIT:
                if count==1:raise ValueError('Native PIC singleton source budget exceeded')
                break
            chosen=native_partition_entry(cases,start,count,program)
        if chosen is None:raise ValueError('Empty native PIC partition')
        plan.append(chosen);start+=chosen['count']
    validate_native_partitions(cases,plan);return plan


def finish_native(cases,partitions,batches):
    validate_native_partitions(cases,partitions)
    if type(batches) is not list or len(batches)!=len(partitions):raise ValueError('Native PIC batch count differs')
    for batch,part in zip(batches,partitions):
        if type(batch) is not dict or set(batch)!={*part,'bytes','passed','output_sha256'}:raise ValueError('Native PIC batch schema differs')
        if any(type(batch[k]) is not type(v) or batch[k]!=v for k,v in part.items()) or batch['passed'] is not True:raise ValueError('Native PIC batch partition differs')
        if type(batch['bytes']) is not int or batch['bytes']!=part['compared_bytes'] or type(batch['output_sha256']) is not str or re.fullmatch('[0-9a-f]{64}',batch['output_sha256']) is None:raise ValueError('Native PIC byte coverage/output digest differs')


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
def roundtrip.emitted(id: String, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  observed(id, "raw-roundtrip", roundtrip(loaded(result)))
# Factory uses native reference bytes after an independently successful reopen.
# raw-roundtrip instead reconstructs the bytes exported from its own reopened owner.
def factory.emitted(id: String, width: U32, height: U32, format: U32, bytes: +List<U32>, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "PIC factory reopen failed")
    case Done{_}: observed(id, "factory", J.Image.Formatted.from_bytes(width, height, format, bytes))
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
    case False{}: IO.die(Unit, 1, "PIC file boundary or closure differs")
def required(expected: U32, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Done{_}: require(U32.is_eq(expected, 99))
    case Fail{error}: require(U32.is_eq(expected, load.error(error)))
def exact.error(code: U32, message: String, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Fail{J.ImageFileError{actual, text}}: require(U32.is_eq(code, actual) && String.eq(message, text))
    case _: require(False{})
def file.code.required(expected: U32, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  match result:
    case Fail{J.ImageFileError{code, _}}: require(U32.is_eq(expected, code))
    case _: require(False{})
def file.failed(id: String, expected: U32, message: String, result: Result<&1, &1, J.Image.LoadError, J.Image.Formatted>) -> IO(Unit):
  do IO<Unit>:
    exact.error(expected, message, result)
    emit.error(id, "formatted-error", 5)
'''
BEND_PREFIX += r'''
def surface.pic.loaded(result: Result<&1, &1, J.Image.LoadError, +List<U32>>) -> IO(Result<&1, &1, J.Image.LoadError, J.Surface>):
  match result:
    case Fail{error}: IO.pure(Result<&1, &1, J.Image.LoadError, J.Surface>, Fail{error})
    case Done{bytes}: IO.pure(Result<&1, &1, J.Image.LoadError, J.Surface>, J.Image.file.decoded(J.Surface, J.Surface.decode_pic(bytes)))
def surface.pic(path: String) -> IO(Result<&1, &1, J.Image.LoadError, J.Surface>):
  IO.bind(Result<&1, &1, J.Image.LoadError, +List<U32>>, Result<&1, &1, J.Image.LoadError, J.Surface>, J.Image.file.bytes(path, J.Image.file.limit(J.RasterFile{})), surface.pic.loaded)
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
  IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Formatted>, Unit, J.Image.Formatted.pic.file.loaded(result), stage.emitted(id, expected))
def stage.failed(id: String, code: U32, message: String, result: Result<&1, &1, J.Image.LoadError, +List<U32>>) -> IO(Unit):
  IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Formatted>, Unit, J.Image.Formatted.pic.file.loaded(result), stage.exact(id, code, message))
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


def candidate_actions(cases,invalid,reference,synthetic=None):
    validate_cases(cases);validate_controls(invalid)
    synthetic=[] if synthetic is None else synthetic
    memory.validate_controls(synthetic)
    if any(not any(v>255 for v in c['bytes']) for c in synthetic):raise ValueError('Byte-safe control mislabeled as synthetic-only')
    all_ids=[c['id'] for c in cases+invalid+synthetic]
    if len(set(all_ids))!=len(all_ids):raise ValueError('Accepted/file/synthetic control identities overlap')
    if type(reference) is not dict or set(reference)!={c['id'] for c in cases}:raise ValueError('Native file reference coverage differs')
    # Full strict framing is rechecked before any candidate expectation is used.
    framed=[]
    for c in cases:
        pair=reference[c['id']]
        if type(pair) not in (list,tuple) or len(pair)!=2:raise ValueError('Incomplete native file pair')
        for row in pair:
            if type(row) is not dict or type(row.get('bytes')) is not list:raise ValueError('Incomplete native file bytes')
            framed.append(json.dumps({k:v for k,v in row.items() if k!='bytes'}))
            framed += [json.dumps(row['bytes'][i:i+256]) for i in range(0,len(row['bytes']),256)]+['"end"']
    memory.parse_rows('\n'.join(framed),[dict(case=c,role=role) for c in cases for role in ('raw','normalized')])
    actions=[]
    for c in cases:
        raw,normal=reference[c['id']]
        roles=['raw','owner','bridge','surface','factory','raw-roundtrip']+(['dispatch-pic','uncontracted','fused'] if c['regress'] and c['route']=='LoadImage' else [])
        for role in roles:
            actions.append(dict(case=c,role=role,expected=dict(raw if role in memory.RAW_ROLES else normal,role=role),normalized=normal['bytes']))
        if c['regress'] and c['route']=='explicit-pic':
            control=dict(c,id=c['id']+'-generic',error=0)
            actions.append(dict(case=control,role='surface-error',expected=dict(id=control['id'],role='surface-error',error=0)))
    actions += [dict(case=c,role='formatted-error',expected=dict(id=c['id'],role='formatted-error',error=c['error'])) for c in invalid]
    actions += [dict(case=c,role='formatted-error',synthetic=True,expected=dict(id=c['id'],role='formatted-error',error=c['error'])) for c in synthetic]
    memory.validate_action_sequence(actions)
    return actions


def candidate_program(actions):
    memory.validate_action_sequence(actions)
    lines=[BEND_PREFIX,'def main() -> IO(Unit):','  do IO<Unit>:']
    for a in actions:
        c=a['case'];role=a['role'];ident=json.dumps(c['id'])
        if a.get('synthetic'):
            if a['synthetic'] is not True or role!='formatted-error':raise ValueError('Malformed synthetic continuation action')
            memory.validate_controls([c])
            if not any(v>255 for v in c['bytes']):raise ValueError('Byte-safe synthetic continuation')
            lines.append(f'    IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Formatted>, Unit, J.Image.Formatted.pic.file.loaded(Done{{{memory.input_expression(c["bytes"])}}}), load.failed({ident}))')
            continue
        path=json.dumps(c['path']);output='J.Image.Formatted';call=f'J.Image.Formatted.load_pic({path})'
        if role=='raw':continuation=f'load.emitted({ident}, "raw")'
        elif role=='raw-roundtrip':continuation=f'roundtrip.emitted({ident})'
        elif role=='factory':continuation=f'factory.emitted({ident}, {c["width"]}, {c["height"]}, {memory.FORMATS[c["channels"]]}, {memory.input_expression(a["expected"]["bytes"])})'
        elif role=='owner':
            first=int.from_bytes(bytes(a['normalized'][:4]),'big');last=int.from_bytes(bytes(a['normalized'][-4:]),'big')
            continuation=f'owner.emitted({ident}, {c["width"]}, {c["height"]}, {first}, {last})'
        elif role=='bridge':continuation=f'bridge.emitted({ident})'
        elif role=='formatted-error':
            continuation=f'load.failed({ident})'
            code={'overflow':errno.EOVERFLOW,'directory':errno.EISDIR,'missing':errno.ENOENT}.get(c.get('special'))
            if code is not None:continuation=f'file.failed({ident}, {code}, {json.dumps(os.strerror(code))})'
        elif role in ('surface','dispatch-pic','uncontracted','fused','surface-error'):
            output='J.Surface';continuation=f'surface.emitted({ident}, {json.dumps(role)})'
            if role=='surface':call=f'surface.pic({path})'
            elif role in ('dispatch-pic','surface-error'):call=f'J.Surface.load_image({path})'
            else:call=f'J.Surface.load_image_for(J.{"UncontractedDecode" if role=="uncontracted" else "FusedDecode"}{{}}, {path})'
            if role=='surface-error':continuation=f'surface.failed({ident})'
        else:raise ValueError('Unknown file candidate role')
        lines.append(f'    IO.bind(Result<&1, &1, J.Image.LoadError, {output}>, Unit, {call}, {continuation})')
    return '\n'.join(lines)+'\n'


# Each closure action emits a framed record: a terminal claim alone cannot pass.
BOUNDARY_LOADS=('c3-single','c4-single','not-pic-qoi','directory','cap-plus-one','host-size-overflow')
STAGES=(('stage-short',3),('stage-read-failure',5),('stage-size-failure',5),('stage-long',3))
SYNTHETIC=(('continuation-error',5),('payload-error',5),('payload-short',3),('payload-long',3),('invalid-byte',1),('empty-header',0),('bad-size',2),('wrapped-stream',4))
ITERATIONS=100
TERMINAL=dict(closure_checks=True,iterations=ITERATIONS,paths_per_iteration=len(BOUNDARY_LOADS)+len(STAGES),synthetic_checks=len(SYNTHETIC),records=ITERATIONS*(len(BOUNDARY_LOADS)+len(STAGES))+len(SYNTHETIC)+1)


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
    actions+=cycle*ITERATIONS
    c=dict(by_id['c3-single'],id='closure-final');actions.append(dict(case=c,role='raw',expected=dict(reference['c3-single'][0],id='closure-final')))
    return actions


def boundary_program(cases,invalid):
    by_id={c['id']:c for c in cases+invalid};loop_actions=[]
    for ident in BOUNDARY_LOADS:
        c=by_id[ident];loop_actions.append(dict(case=c,role='formatted-error' if 'error' in c else 'raw',expected=dict(id=c['id'],role='formatted-error' if 'error' in c else 'raw')))
    body=candidate_program(loop_actions).split('  do IO<Unit>:\n')[-1]
    lines=[BEND_PREFIX,'def closure_loop(n: Nat) -> IO(Unit):','  match n:','    case 0n: IO.pure(Unit, Unit{})','    case 1n+rest:','      do IO<Unit>:']
    lines += ['    '+line for line in body.rstrip().splitlines()]
    valid=json.dumps(by_id['c3-single']['path'])
    for mode in range(4):lines.append(f'        IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open({valid}, "r"), stage.opened({mode}))')
    lines += ['        closure_loop(rest)','def main() -> IO(Unit):','  do IO<Unit>:',
              '    require(U32.is_eq(J.Image.file.limit(J.RasterFile{}), 1048576) && (1048576 <= J.Image.file.limit(J.RasterFile{}) : U32) && Bool.not((1048577 <= J.Image.file.limit(J.RasterFile{}) : U32)))',
              '    require(String.eq(J.Image.file.token(".pic"), "") && String.eq(J.Image.file.token("dir/.pic"), ".pic") && String.eq(J.Image.file.token("dir.pic/leaf"), ".pic/leaf"))',
              '    require(J.Image.file.complete(0n, Nil{}) && J.Image.file.complete(2n, [1, 2]) && Bool.not(J.Image.file.complete(2n, [1])) && Bool.not(J.Image.file.complete(1n, [1, 2])))']
    synthetic=[('Fail{J.ImageFileError{719, "continuation-failure"}}','stage.exact("continuation-error", 719, "continuation-failure")'),
               ('J.Image.file.payload(2, Fail{(727, "payload-failure")})','stage.exact("payload-error", 727, "payload-failure")'),
               ('J.Image.file.payload(2, Done{[1]})','stage.emitted("payload-short", 3)'),
               ('J.Image.file.payload(1, Done{[1, 2]})','stage.emitted("payload-long", 3)'),
               ('Done{[256]}','stage.emitted("invalid-byte", 1)'),('Done{Nil{}}','stage.emitted("empty-header", 0)'),
               ('Done{'+memory.bend_bytes(next(c['bytes'] for c in memory.controls() if c['id']=='axis-92-0'))+'}','stage.emitted("bad-size", 2)')]
    for value,continuation in synthetic:
        lines.append(f'    IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Formatted>, Unit, J.Image.Formatted.pic.file.loaded({value}), {continuation})')
    lines += ['    stage.emitted("wrapped-stream", 4, J.Image.file.decoded(J.Image.Formatted, Fail{J.InvalidImageStream{}}))',
              '    closure_loop(100n)',f'    IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Formatted>, Unit, J.Image.Formatted.load_pic({valid}), load.emitted("closure-final", "raw"))',
              '    IO.print('+json.dumps(json.dumps(TERMINAL,separators=(',',':')))+')']
    return '\n'.join(lines)+'\n'


def parse_boundary(text,actions):
    lines=text.splitlines();row=memory.strict_json(lines[-1]) if lines else None
    if type(row) is not dict or row!=TERMINAL or any(type(row.get(k)) is not type(v) for k,v in TERMINAL.items()):raise ValueError('Missing strict PIC closure terminal')
    if len(actions)!=TERMINAL['records']:raise ValueError('Boundary expected count differs')
    actual=memory.parse_rows('\n'.join(lines[:-1]),actions)
    if memory.differences([a['expected'] for a in actions],actual):raise ValueError('Closure record differs')
    return row



def boundary_source_contract():
    source=(ROOT/'jonlib.bend').read_text()
    names=('Image.file.limit','Image.file.complete','Image.file.payload','Image.file.read','Image.file.bounded','Image.file.sized','Image.file.opened','Image.file.bytes','Image.file.decoded','Image.Formatted.pic.file.loaded','Image.Formatted.load_pic')
    sections={name:'def '+name+'('+source.split('def '+name+'(',1)[1].split('\ndef ',1)[0] for name in names}
    bounded=sections['Image.file.bounded'];read=sections['Image.file.read'];wrapper=sections['Image.Formatted.load_pic'];continuation=sections['Image.Formatted.pic.file.loaded']
    if not bounded.index('case False{}:')<bounded.index('File.close(file)')<bounded.index('case True{}:')<bounded.index('File.read_bytes(file, size)'):raise ValueError('Pre-read cap/close source ordering differs')
    if bounded.count('File.read_bytes(')!=1 or not read.index('File.close(file)')<read.index('Image.file.payload(size, status)'):raise ValueError('Single read/close-before-processing source ordering differs')
    if 'Image.file.bounded((size <= limit : U32), file, size)' not in sections['Image.file.sized']:raise ValueError('Inclusive pre-read cap differs')
    if 'Image.file.bytes(path, Image.file.limit(RasterFile{})), Image.Formatted.pic.file.loaded)' not in wrapper or 'Image.file.decoded(Image.Formatted, Image.Formatted.decode_pic(bytes))' not in continuation:raise ValueError('Explicit PIC continuation contract differs')
    return dict(kind='source-order evidence plus separately observed runtime controls; not an IO proof',close_guarantee='File.close is called; Base cannot report OS close failure',source_sha256=memory.digest(ROOT/'jonlib.bend'),definitions={name:dict(source=text,sha256=hashlib.sha256(text.encode()).hexdigest()) for name,text in sections.items()})


def qualification_program():
    # Native path-token semantics are qualified independently of Python and Bend.
    checks='if(GetFileExtension(".pic")!=NULL||GetFileExtension("dir/.pic")==NULL||strcmp(GetFileExtension("dir/.pic"),".pic")||GetFileExtension("dir.pic/leaf")==NULL||strcmp(GetFileExtension("dir.pic/leaf"),".pic/leaf"))return 14;'
    return '#include <string.h>\n'+memory.qualification_program().replace('SetTraceLogLevel(LOG_NONE);','SetTraceLogLevel(LOG_NONE);'+checks,1)


def tracked_sources(args):
    result=memory.tracked_sources(args)
    for name in ('tools/pic_file_probe.py','tools/pic_file_audit.py','tests/test_pic_file_harness.py','tests/test_pic_file_audit.py','tools/raw_file_probe.py','tools/r32_raw_file_probe.py','tools/pic_probe.py','tools/png_probe.py','tools/bmp_probe.py','tools/qoi_format_probe.py','tools/tga_format_probe.py','tools/tga_probe.py'):
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
    return result or [BUILD/'pic-file-probe']


def admit_directories(argv):
    paths=report_directories(argv)
    for path in dict.fromkeys(p.resolve() for p in paths):
        path.mkdir(parents=True,exist_ok=True);(path/'results.json').write_text('{"passed":false,"phase":"argument-validation"}\n')
    return paths[-1].resolve()


def record_run(command,work,label,*,timeout=600,environment=None,receipt=None,require_output=False,descriptor_limit=None):
    if timeout<=0:raise ValueError('Timeout must be positive')
    return memory.record_run(command,work,label,timeout=timeout,environment=environment,receipt=receipt,require_output=require_output)


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


def validate_alias_config(cache,flags):
    memory.validate_native_config(cache,flags)
    fields=dict(re.findall(r'^([A-Za-z_][A-Za-z0-9_]*):[^=\n]+=(.*)$',cache,re.M))
    tokens=shlex.split(flags,comments=True);definitions=[];index=0
    while index<len(tokens):
        token=tokens[index]
        if token in ('-D','-U'):
            if index+1>=len(tokens):raise ValueError('Incomplete native alias macro')
            index+=1;token+=tokens[index]
        if token.startswith(('-D','-U')):definitions.append(token)
        index+=1
    for name in ALIAS_MACROS:
        macro='SUPPORT_FILEFORMAT_'+name
        selected=[t for t in definitions if t[2:].split('=')[0]==macro]
        if fields.get(macro)!='ON' or len(selected)!=1 or selected[0] not in ('-D'+macro,'-D'+macro+'=1'):raise ValueError('Native file alias missing/disabled/ambiguous: '+macro)
    return dict(enabled_macros=['SUPPORT_FILEFORMAT_'+n for n in ALIAS_MACROS],recognized_tokens=sorted(RECOGNIZED),extension_rule='last dot of entire path; index zero excluded')


def native_archive(args,work,record):
    def explicit_record(command,*pos,**options):
        command=list(command)
        if '-DCUSTOMIZE_BUILD=ON' in command:
            command += ['-DSUPPORT_FILEFORMAT_'+name+'=ON' for name in ALIAS_MACROS if name!='PIC']
        output=record(command,*pos,**options)
        if '-DCUSTOMIZE_BUILD=ON' in command:
            base=work/'raylib-build';validate_alias_config((base/'CMakeCache.txt').read_text(),(base/'raylib/CMakeFiles/raylib.dir/flags.make').read_text())
        return output
    archive,receipt=memory.native_archive(args,work,explicit_record)
    base=work/'raylib-build';receipt['file_aliases']=validate_alias_config((base/'CMakeCache.txt').read_text(),(base/'raylib/CMakeFiles/raylib.dir/flags.make').read_text())
    return archive,receipt


def partition_entry(actions,start,count):
    selected=actions[start:start+count];program=candidate_program(selected).encode('utf-8')
    if not 0<len(program)<=SOURCE_BYTE_LIMIT:raise ValueError('PIC file partition source budget exceeded')
    return dict(start=start,count=count,source_bytes=len(program),source_sha256=hashlib.sha256(program).hexdigest(),actions_sha256=memory.action_digest(selected),compared_bytes=sum(len(a['expected'].get('bytes',[])) for a in selected))


def validate_partitions(actions,partitions,source_limit=SOURCE_BYTE_LIMIT):
    memory.validate_action_sequence(actions)
    if type(source_limit) is not int or not 0<source_limit<=SOURCE_BYTE_LIMIT:raise ValueError('Invalid file partition source budget')
    if type(partitions) is not list or not partitions:raise ValueError('Empty file partition plan')
    cursor=0
    for entry in partitions:
        if type(entry) is not dict or set(entry)!={'start','count','source_bytes','source_sha256','actions_sha256','compared_bytes'}:raise ValueError('File partition schema differs')
        if any(type(entry[k]) is not int for k in ('start','count','source_bytes','compared_bytes')):raise ValueError('File partition integer type differs')
        if entry['start']!=cursor or not 1<=entry['count']<=BATCH_SIZE or cursor+entry['count']>len(actions):raise ValueError('Noncontiguous/incomplete file partition')
        if not 0<entry['source_bytes']<=source_limit or entry['compared_bytes']<0:raise ValueError('File partition budget differs')
        expected=partition_entry(actions,cursor,entry['count'])
        if entry!=expected or any(type(entry[k]) is not type(v) for k,v in expected.items()):raise ValueError('File partition source/action identity differs')
        cursor+=entry['count']
    if cursor!=len(actions):raise ValueError('Incomplete file partition coverage')


def plan_partitions(actions,source_limit=SOURCE_BYTE_LIMIT):
    memory.validate_action_sequence(actions)
    if type(source_limit) is not int or not 0<source_limit<=SOURCE_BYTE_LIMIT:raise ValueError('Invalid file partition source budget')
    plan=[];start=0
    while start<len(actions):
        selected=None
        for count in range(1,min(BATCH_SIZE,len(actions)-start)+1):
            program=candidate_program(actions[start:start+count]).encode('utf-8')
            if len(program)>source_limit:
                if count==1:raise ValueError('File singleton exceeds source budget: '+str(start))
                break
            selected=partition_entry(actions,start,count)
        if selected is None:raise ValueError('Empty file partition')
        plan.append(selected);start+=selected['count']
    validate_partitions(actions,plan,source_limit)
    return plan


def resource_plan(actions):
    if type(actions) is not list or not actions:raise ValueError('Empty resource actions')
    return dict(observations=len(actions),compared_bytes=sum(len(a['expected'].get('bytes',[])) for a in actions),actions_sha256=memory.action_digest(actions))


def finish_lanes(lanes,actions,partitions,resources=None):
    # A previous pass flag never survives a failed replay attempt.
    if type(lanes) is dict:
        for value in lanes.values():
            if type(value) is dict:value['passed']=False
    validate_partitions(actions,partitions)
    if resources is not None and (type(resources) is not dict or set(resources)!={'boundary','sparse','exact_cap'}):raise ValueError('Missing resource action coverage')
    if type(lanes) is not dict or set(lanes)!=set(LANES):raise ValueError('Missing mandatory file lanes')
    for lane in LANES:
        result=lanes[lane]
        if type(result) is not dict or type(result.get('batches')) is not list or type(result.get('differences')) is not list or result['differences']:raise ValueError('Malformed/differing file lane')
        result['passed']=False
        if len(result['batches'])!=len(partitions):raise ValueError('Incomplete file lane batches')
        for batch,planned in zip(result['batches'],partitions):
            if type(batch) is not dict or set(batch)!={*planned,'bytes','passed'} or batch['passed'] is not True:raise ValueError('File batch schema/pass differs')
            if any(type(batch[k]) is not type(v) or batch[k]!=v for k,v in planned.items()):raise ValueError('File batch partition differs')
            if type(batch['bytes']) is not int or batch['bytes']!=planned['compared_bytes']:raise ValueError('File batch byte coverage differs')
        for kind in ('boundary','sparse','exact_cap'):
            resource=result.get(kind,{})
            required={'passed','maximum_rss_bytes','elapsed_seconds','descriptor_limit','maximum_rss_acceptance_bytes','observations','compared_bytes','actions_sha256','stdout_sha256'}
            if type(resource) is not dict or set(resource)!=required or resource.get('passed') is not True or type(resource.get('descriptor_limit')) is not int or resource['descriptor_limit']!=64:raise ValueError('Missing file resource lane')
            if type(resource['observations']) is not int or resource['observations']<=0 or type(resource['compared_bytes']) is not int or resource['compared_bytes']<0:raise ValueError('Invalid resource observation/byte coverage')
            if any(type(resource[k]) is not str or re.fullmatch(r'[0-9a-f]{64}',resource[k]) is None for k in ('actions_sha256','stdout_sha256')):raise ValueError('Invalid resource evidence digest')
            if type(resource['elapsed_seconds']) not in (int,float) or not math.isfinite(resource['elapsed_seconds']) or resource['elapsed_seconds']<0:raise ValueError('Invalid resource elapsed time')
            if resources is not None:
                expected=resource_plan(resources[kind])
                if any(type(resource[k]) is not type(v) or resource[k]!=v for k,v in expected.items()):raise ValueError('Resource action coverage differs')
            ceiling=MAX_STRESS_RSS if kind=='exact_cap' else MAX_SPARSE_RSS;rss=resource.get('maximum_rss_bytes')
            if type(rss) is not int or not 0<rss<=ceiling or type(resource.get('maximum_rss_acceptance_bytes')) is not int or resource['maximum_rss_acceptance_bytes']!=ceiling:raise ValueError('Incomplete resource acceptance receipt')
    for lane in LANES:lanes[lane]['passed']=True


def run_probe(argv):
    parsing=False
    # Only argparse's successful help exit during parsing is read-only. Parser
    # initialization failures also reset destinations before reaching the caller.
    try:
        parser=argparse.ArgumentParser(description=__doc__,allow_abbrev=False)
        parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
        parser.add_argument('--build-dir',type=Path,default=BUILD/'pic-file-probe')
        parser.add_argument('--reference-env',choices=('clean-loader',),default='clean-loader');parser.add_argument('--timeout',type=int,default=600)
        parsing=True;args=parser.parse_args(argv)
    except BaseException as error:
        if not parsing or not isinstance(error,SystemExit) or error.code!=0:
            memory.SEALED.clear();admit_directories(argv)
        raise
    memory.SEALED.clear();admitted=admit_directories(argv)
    destination=args.build_dir.resolve()
    if destination!=admitted:parser.error('Destination admission differs')
    if args.timeout<=0:parser.error('--timeout must be positive')
    reference_env=ReferenceEnvironment(args.reference_env);reference_env.require_clear()
    record=partial(record_run,timeout=args.timeout);native_record=partial(record,environment=reference_env.child(),receipt=reference_env.receipt())
    report_path=destination/'results.json';work=destination/('run-'+uuid.uuid4().hex);work.mkdir()
    started=time.monotonic();lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    if sys.byteorder!='little':raise ValueError('PIC requires little-endian profile')
    cases,invalid,synthetic=fixtures(),controls(),synthetic_controls();stress,directory_stage=prepare_inputs(work,cases,invalid)
    if directory_stage is None or directory_stage['stage']!='read' or directory_stage['code']!=errno.EISDIR or directory_stage.get('message')!=os.strerror(errno.EISDIR):raise ValueError('Unqualified directory/read profile')
    inputs=work/'inputs.json';inputs.write_text(json.dumps(dict(cases=cases,controls=invalid,synthetic_controls=synthetic,exact_cap=stress),sort_keys=True)+'\n');memory.seal(inputs)
    for c in cases+invalid+[stress]:
        if not c.get('special'):memory.seal(ROOT/c['path'])
    tool_paths={}
    for tool in ('bun','clang','cmake'):
        path=shutil.which(tool)
        if path is None:raise ValueError('Required tool missing: '+tool)
        tool_paths[tool]=str(Path(path).absolute());memory.seal(path)
    tool_paths['python']=str(Path(sys.executable).absolute());memory.seal(tool_paths['python'])
    tool_realpaths={k:str(Path(p).resolve()) for k,p in tool_paths.items()}
    report=dict(passed=False,oracle_source_ranges=validate_reference_sources(args.raylib_source),profile='native-pic-formatted-files-v1',evidence_origin='NEW source-scoped file run; earlier memory evidence remains separate',run_directory=str(work),toolchain=lock,base_revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),host=dict(system=platform.system(),machine=platform.machine()),tool_paths=tool_paths,tool_realpaths=tool_realpaths,sources=tracked_sources(args),reference_environment=reference_env.receipt(),inputs_sha256=memory.digest(inputs),native_content_admission='unchanged PIC memory admission: actual header/all descriptors/all row controls/counts/samples; malformed and overcap controls never native; native suffix shares stb sniffing',cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),typed_controls=len(invalid)+len(synthetic),file_controls=len(invalid),synthetic_controls=len(synthetic),native_rejections=0,native_routes={r:sum(c['route']==r for c in cases) for r in ('LoadImage','explicit-pic')},batch_size=BATCH_SIZE,source_byte_limit=SOURCE_BYTE_LIMIT,partition_strategy='ordered-greedy-generated-source-v1',lanes={lane:dict(passed=False,batches=[],differences=[]) for lane in LANES},candidate_mipmaps='implicit single-mip type contract, not stored/measured',factory_role='native-byte factory reconstruction gated by a distinct successful public reopen; not a second loader-byte comparison',raw_roundtrip_role='reopened loader bytes exported and reconstructed through from_bytes',closure=TERMINAL,file_descriptor_limit=64,host_directory_observation=directory_stage,boundary_source_contract=boundary_source_contract(),unrun=['GPU/Metal','Windows/macOS/browser','big-endian','exact-commit hosted CI','maximum-area allocation/resource limits','representative performance','concurrent/special files','OS close-error reporting','generic formatted/float dispatch','native malformed recovery'])
    for path in [*(ROOT/p for p in report['sources']['library']),*(Path(p) for p in report['sources']['dependencies'])]:memory.seal(path)
    def save():report_path.write_text(json.dumps(report,indent=2)+'\n')
    def verify():
        reference_env.assert_receipt(report['reference_environment']);verify_inputs(cases,invalid,stress)
        if validate_reference_sources(args.raylib_source)!=report['oracle_source_ranges']:raise ValueError('Pinned PIC file oracle drift')
        if tracked_sources(args)!=report['sources']:raise ValueError('PIC file source/toolchain drift')
        if any((str(Path(sys.executable).absolute()) if k=='python' else str(Path(shutil.which(k)).absolute()) if shutil.which(k) else None)!=p or str(Path(p).resolve())!=tool_realpaths[k] for k,p in tool_paths.items()):raise ValueError('Tool resolution drift')
    save();archive,report['native_build']=native_archive(args,work,native_record);save()
    report['bun_version']=record(['bun','--version'],work,'bun-version',require_output=True).strip()
    if report['bun_version']!=lock['bun']['version']:raise ValueError('Bun version differs')
    report['clang_version']=native_record(['clang','--version'],work,'clang-version',require_output=True).strip()
    # Fresh native qualification precedes every accepted file observation.
    verify();program=qualification_program()
    if not 0<len(program.encode())<=SOURCE_BYTE_LIMIT:raise ValueError('Qualification source budget differs')
    source=work/'qualification.c';source.write_text(program);memory.seal(source);binary=work/'qualification'
    native_record(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,archive,'-lm','-o',binary],work,'qualification-compile')
    report['qualification']=memory.qualification(native_record([binary],work,'qualification',require_output=True));save()
    native_plan=plan_native_partitions(cases);report.update(native_partition_plan=native_plan,native_action_inventory=memory.inventory(native_actions(cases)),native_batches=[]);save()
    file_reference={};native_outputs=[]
    for index,part in enumerate(native_plan):
        verify();selected=cases[part['start']:part['start']+part['count']];program=reference_program(selected).encode()
        if native_partition_entry(cases,part['start'],part['count'],program)!=part:raise ValueError('Native PIC file partition drift')
        source=work/f'reference-{index}.c';source.write_bytes(program);memory.seal(source);binary=work/f'reference-{index}'
        native_record(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,archive,'-lm','-o',binary],work,f'reference-{index}-compile')
        output=native_record([binary],work,f'reference-{index}',require_output=True)
        rows=memory.parse_rows(output,native_actions(selected));native_outputs.append(output)
        file_reference.update({c['id']:(rows[2*i],rows[2*i+1]) for i,c in enumerate(selected)})
        report['native_batches'].append(dict(part,bytes=sum(len(row['bytes']) for row in rows),passed=True,output_sha256=hashlib.sha256(output.encode()).hexdigest()));save()
    finish_native(cases,native_plan,report['native_batches'])
    report['reference_sha256']=hashlib.sha256(''.join(native_outputs).encode()).hexdigest();save()
    verify();program=reference_program([stress])
    if not 0<len(program.encode())<=SOURCE_BYTE_LIMIT:raise ValueError('Exact-cap native source budget differs')
    source=work/'exact-cap-reference.c';source.write_text(program);memory.seal(source);binary=work/'exact-cap-reference'
    native_record(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,archive,'-lm','-o',binary],work,'exact-cap-reference-compile')
    output=native_record([binary],work,'exact-cap-reference',require_output=True)
    rows=memory.parse_rows(output,native_actions([stress]));stress_reference={stress['id']:(rows[0],rows[1])}
    report['exact-cap-reference_sha256']=hashlib.sha256(output.encode()).hexdigest()
    actions=candidate_actions(cases,invalid,file_reference,synthetic)
    partitions=plan_partitions(actions);report['partitions']=partitions;report['action_inventory']=memory.inventory(actions)
    report.update(native_observations=2*len(cases),native_raw_bytes=sum(len(raw['bytes']) for raw,_ in file_reference.values()),native_normalized_bytes=sum(len(normal['bytes']) for _,normal in file_reference.values()),observations_per_lane=len(actions),compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions),raw_compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions if a['role'] in memory.RAW_ROLES),normalized_compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions if a['role'] not in memory.RAW_ROLES),exact_cap=dict(size=PIC_CAP,native_reference=stress_reference[stress['id']][0],native_normalized=stress_reference[stress['id']][1]));save()
    for index,planned in enumerate(partitions):
        start=planned['start'];verify();selected=actions[start:start+planned['count']]
        if partition_entry(actions,start,planned['count'])!=planned:raise ValueError('File source partition drift')
        source=work/f'candidate-{index}.bend';source.write_text(candidate_program(selected));memory.seal(source);binary=work/f'candidate-{index}';js=work/f'candidate-{index}.js'
        record(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary,'-o',js],work,f'compile-{index}')
        for lane in LANES:
            command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            actual=memory.parse_rows(record(command,work,f'{lane}-{index}',require_output=True),selected);delta=memory.differences([a['expected'] for a in selected],actual)
            report['lanes'][lane]['differences'].extend(delta);report['lanes'][lane]['batches'].append(dict(**planned,bytes=sum(len(r.get('bytes',[])) for r in actual),passed=not delta));save()
        print(f'PIC file batch {index+1}: {len(selected)} observations compared on CPU-1/CPU-2/JavaScript',flush=True)
    boundary=boundary_actions(cases,invalid,file_reference)
    stress_actions=candidate_actions([stress],[],stress_reference)
    sparse_actions=[dict(case=c,role='formatted-error',expected=dict(id=c['id'],role='formatted-error',error=c['error'])) for c in invalid if c.get('special') in ('sparse','large','overflow')]
    resources=dict(boundary=boundary,sparse=sparse_actions,exact_cap=stress_actions)
    report['resource_plans']={kind:resource_plan(expected) for kind,expected in resources.items()};save()
    for kind,program,ceiling in [('boundary',boundary_program(cases,invalid),MAX_SPARSE_RSS),('sparse',candidate_program(sparse_actions),MAX_SPARSE_RSS),('exact_cap',candidate_program(stress_actions),MAX_STRESS_RSS)]:
        verify()
        if not 0<len(program.encode())<=SOURCE_BYTE_LIMIT:raise ValueError('Resource source budget differs: '+kind)
        source=work/(kind+'.bend');source.write_text(program);memory.seal(source);binary=work/kind;js=work/(kind+'.js')
        record(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary,'-o',js],work,kind+'-compile')
        for lane in LANES:
            command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            output,usage=resource_run(command,work,lane+'-'+kind,ceiling,ENV,None,min(args.timeout,240))
            if kind=='boundary':parse_boundary(output,boundary)
            else:
                expected=stress_actions if kind=='exact_cap' else sparse_actions
                if memory.parse_rows(output,expected)!=[a['expected'] for a in expected]:raise ValueError('Resource control bytes/error differ')
            report['lanes'][lane][kind]=dict(passed=True,**usage,**resource_plan(resources[kind]),stdout_sha256=hashlib.sha256(output.encode()).hexdigest());save()
        print('PIC file '+kind+': all three lanes passed',flush=True)
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision']);verify()
    finish_native(cases,native_plan,report['native_batches']);finish_lanes(report['lanes'],actions,partitions,resources);memory.verify_sealed()
    report.update(passed=True,elapsed_seconds=round(time.monotonic()-started,3),sealed_artifacts=dict(memory.SEALED));save()
    print(f'PASS: {len(cases)} native PIC files, {len(invalid)} file and {len(synthetic)} synthetic-only typed controls, {report["compared_bytes_per_lane"]} bytes per lane',flush=True)


def main(argv=None):
    argv=list(sys.argv[1:] if argv is None else argv)
    try:run_probe(argv)
    except Exception as error:
        # Argument failures already reset every named destination; runtime
        # failures also retain the last partial report and durable seal list.
        path=report_directories(argv)[-1].resolve()/'results.json'
        report=dict(passed=False,phase='runtime-failure')
        try:
            previous=memory.strict_json(path.read_text())
            if type(previous) is dict:report=previous
        except (OSError,ValueError):pass
        report.update(passed=False,failure=dict(type=type(error).__name__,message=str(error)),sealed_artifacts=dict(memory.SEALED))
        try:
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
        except OSError as report_error:
            # Keep the original failure even when its receipt cannot be saved.
            if hasattr(error,'add_note'):error.add_note('Could not save failed PIC report: '+str(report_error))
        raise


if __name__=='__main__':main()
