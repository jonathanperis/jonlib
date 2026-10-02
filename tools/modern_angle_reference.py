#!/usr/bin/env python3
"""Pinned glibc-2.41 finite atan2f reference, native qualification and corpus.

No Bend candidate runs here. The unmodified MIT source and its instrumented
finite adaptation are independently compiled into separate symbols. Native libm
is diagnostic only: it never defines or selects this pinned-source profile.
"""
import argparse
import copy
from collections import Counter
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import re
import shutil
import struct
import subprocess
import time
import uuid

import runtime_image

from angle_probe import GNU_CONTROL, samples as old_samples

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / 'tools/reference'
SOURCE_SHA256 = '96f9c81b6e870c256cc0757f6d88f5290ed35db8d5b640b9e757d6feca96ae38'
SOURCE_COMMIT = '74f59e9271cbb4071671e5a474e7d4f1622b186f'
SOURCE_BLOB = '82a0151293cda9cf89d6a18b6f8b35d4fdaeddd4'
OLD_INPUTS_SHA256 = 'e97e8ae61b081cbf56aaedf449be5e40795523ee73deba21649e297d20d499fb'
HISTORICAL_IDS_SHA256 = '8d930f13acdb6cb3a1be6261f334970ab2baa694a15116d6246774659be62976'
HISTORICAL_DIFFERENCES_SHA256 = 'f30b754eb1211a2037aa74a057c772772f379aa7754914e540c88db7023b5832'
HISTORICAL_RESULTS_SHA256 = 'a5e42c9cd97f039c497cef59bc37828ffb3884d92334d554322cbff5da930a71'
CONSTANTS_SHA256 = 'e8a88784533e3309745eea6e6c41dc88e3cda7f11f988afc225e844f7d6c5bdd'
FLAGS = ['-std=c11', '-O2', '-frounding-math', '-fno-fast-math',
         '-ffp-contract=off', '-fno-lto', '-fno-builtin-atan2f', '-fno-builtin-fma']
SEED = 0xA74A241
TRACE_TAGS = dict(zip(('z','z2','z4','z8','cn0','cn2','cn4','cd0','cd2','cd4',
    'rational','signed_z','initial_r','tiny_z','tiny_residual','tiny_zz','tiny_cz',
    'tiny_e','tiny_product','tiny_adjusted','zh','zl','z2h','z2l','poly_ch','poly_cl',
    'ph','pl','signed_zh','signed_zl','product_ph','product_pl','sh','sl','th','dh',
    'tm','corrected_tm','final_r'), range(1,40)))
BRANCHES = dict(zip(('rational','shortcut','ambiguous','tiny','tiny_boundary',
    'tiny_increment','tiny_decrement','general','correction','correction_up',
    'correction_down','zero','reject'), (1<<i for i in range(13))))


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def hash_json(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',',':')).encode()).hexdigest()


def _u32(value):
    return type(value) is int and 0 <= value <= 0xffffffff


def bits(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def double_words(value):
    word = struct.unpack('<Q', struct.pack('<d', value))[0]
    return word >> 32, word & 0xffffffff


def source_paths():
    return [Path(__file__).resolve(), ROOT/'tools/angle_probe.py', ROOT/'tools/runtime_image.py',
            ROOT/'LICENSES/core-math-atan2f.txt',
            *(REFERENCE/name for name in ('modern_atan2f_glibc241.c',
                'modern_atan2f_adapted.c','modern_atan2f_shim.h',
                'modern_atan2f_trace.h','modern_atan2f_driver.c',
                'runtime_image.h','runtime_image.c','runtime_image_macho.h','runtime_image_macho.c',
                'modern_atan2f_general_cases.json','modern_atan2f_historical.json','modern_atan2f_README.md'))]


def _constants():
    source = (REFERENCE/'modern_atan2f_glibc241.c').read_text()
    result = {}
    token = r'[-+]?0x[0-9a-f.]+p[-+]?\d+'
    for name, width in (('cn',1),('cd',1),('c',2)):
        expression = rf'static const double {name}\[(?:32)?\](?:\[2\])?\s*=\s*\{{(.*?)\n\s*\}};'
        match = re.search(expression, source, re.S)
        if not match: raise ValueError('Pinned coefficient array missing: '+name)
        values = re.findall(token, match[1])
        if len(values) != (64 if width == 2 else 7):
            raise ValueError('Pinned coefficient array width changed: '+name)
        for i, value in enumerate(values):
            key = f'{name}{i//2}{"hl"[i%2]}' if width == 2 else f'{name}{i}'
            result[key] = double_words(float.fromhex(value))
    pi=float.fromhex('0x1.921fb54442d18p+1')
    half=float.fromhex('0x1.921fb54442d18p+0')
    low=float.fromhex('0x1.1a62633145c07p-54')
    for name, values in (('off',(0.0,half,pi,half,-0.0,-half,-pi,-half)),
                         ('offl',(0.0,low,2*low,low,-0.0,-low,-2*low,-low)),
                         ('m',(0.,1.)), ('sgn',(1.,-1.))):
        for i,value in enumerate(values): result[f'{name}{i}']=double_words(value)
    for name,literal in (('tiny_c','-0x1.5555555555555p-2'),
                         ('correction_test','0x1p-60'),
                         ('correction_up','0x1.4p+0'),('correction_down','0x1.8p-1')):
        result[name]=double_words(float.fromhex(literal))
    return result


CONSTANTS = _constants()


def assert_pins():
    if sha256(REFERENCE/'modern_atan2f_glibc241.c') != SOURCE_SHA256:
        raise ValueError('Pinned glibc scalar source hash mismatch')
    if hash_json(CONSTANTS) != CONSTANTS_SHA256 or _constants() != CONSTANTS:
        raise ValueError('Pinned exact coefficient/offset words changed')
    values=old_samples()
    if len(values)!=1086 or hashlib.sha256(json.dumps(values).encode()).hexdigest()!=OLD_INPUTS_SHA256:
        raise ValueError('Historical 1086-case corpus changed')
    historical=json.loads((REFERENCE/'modern_atan2f_historical.json').read_text())
    if hash_json(historical['difference_ids'])!=HISTORICAL_IDS_SHA256 or hash_json(historical['differences'])!=HISTORICAL_DIFFERENCES_SHA256 or historical['full_results_sha256']!=HISTORICAL_RESULTS_SHA256:
        raise ValueError('Historical difference IDs/words changed')
    return {str(path):sha256(path) for path in source_paths()}


def samples():
    """All historical cases first and unchanged; independently generated extras."""
    rows=[]; seen=set()
    def add(y,x,label,keep=False):
        if not _u32(y) or not _u32(x): raise ValueError('Corpus words must be U32')
        if keep or (y,x) not in seen:
            rows.append(dict(id=len(rows),y=y,x=x,labels=[label])); seen.add((y,x))
        else:
            # Preserve independent historical entries, add labels to first match.
            for row in rows:
                if (row['y'],row['x'])==(y,x):
                    if label not in row['labels']: row['labels'].append(label)
                    break
    def signs(y,x,label):
        for sy in (0,0x80000000):
            for sx in (0,0x80000000): add(y^sy,x^sx,label)
    for i,(y,x) in enumerate(old_samples()): add(bits(y),bits(x),f'historical-{i}',keep=True)
    edges=(0,1,2,0x003fffff,0x00400000,0x007ffffe,0x007fffff,
           0x00800000,0x00800001,0x3f7fffff,0x3f800000,0x3f800001,
           0x7f7ffffe,0x7f7fffff)
    for y in edges:
        for x in edges: signs(y,x,'finite-boundary-cross-product')
    for exp in range(0,255):
        word=(exp<<23)|1
        signs(word,word,'equal-every-exponent')
        for delta in (-1,1):
            other=word+delta
            if 0<=other<0x7f800000:
                add(word,other,'adjacent-every-exponent')
                add(other,word,'adjacent-every-exponent-swapped')
        # Guard transitions are raw-word distances, including subnormal cases.
        for distance in (25,27):
            for delta in (-1,0,1):
                other=word+(distance<<23)+delta
                if other<0x7f800000:
                    add(word,other,f'guard-{distance}-delta-{delta}')
                    add(other,word,f'guard-{distance}-delta-{delta}-swapped')
    for bit in range(23):
        for frac in (1<<bit,0x7fffff^(1<<bit)):
            signs(frac,0x00800000,'subnormal-bit-pattern')
            signs(0x00800000,frac,'subnormal-bit-pattern-swapped')
    for y in (1,0x80000001): add(y,0x0c800000,'minimum-general-ratio')
    for x in (0x75000000,0x7b000000,0x7b800000,0x7f000000):
        for y in (1,0x80000001): add(y,x,'literal-tiny-gradual-product')
    rng=random.Random(SEED)
    for i in range(512):
        # Independently stratified exponent/significand/sign, not uniform reals.
        y=(rng.randrange(255)<<23)|rng.getrandbits(23)|(rng.getrandbits(1)<<31)
        x=(rng.randrange(255)<<23)|rng.getrandbits(23)|(rng.getrandbits(1)<<31)
        add(y,x,'deterministic-bit-stratified'); add(x,y,'deterministic-bit-stratified-swapped')
    for y,x in old_samples()[62:94]:
        for exponent in (-80,-20,20,80):
            add(bits(math.ldexp(y,exponent)),bits(math.ldexp(x,exponent)),f'common-rescale-{exponent}')
    path=REFERENCE/'modern_atan2f_general_cases.json'
    if path.exists():
        for case in json.loads(path.read_text())['cases']:
            signs(int(case['y'],16),int(case['x'],16),'native-only-general-search')
            signs(int(case['x'],16),int(case['y'],16),'native-only-general-search-swapped')
    for bad in (0x7f800000,0xff800000,0x7fc00000,0xffc00001,0x7f800001,0xff800001):
        for other in (0,0x80000000,1,0x3f800000,bad):
            add(bad,other,'nonfinite-checked-rejection'); add(other,bad,'nonfinite-checked-rejection')
    return rows


def _run(command,work,label,*,input_text=None,timeout=120):
    """Keep full stdout/stderr and command/status even on nonzero/timeout."""
    work=Path(work); work.mkdir(parents=True,exist_ok=True)
    command=[str(x) for x in command]
    record=dict(command=command,timeout=timeout,started=time.time())
    try:
        result=subprocess.run(command,input=input_text,text=True,capture_output=True,timeout=timeout)
        stdout,stderr=result.stdout,result.stderr; record['returncode']=result.returncode
    except subprocess.TimeoutExpired as error:
        def decode(value): return value.decode(errors='replace') if isinstance(value,bytes) else (value or '')
        stdout,stderr=decode(error.stdout),decode(error.stderr);record['timeout_expired']=True
    record['elapsed']=time.time()-record['started']
    (work/f'{label}.stdout').write_text(stdout);(work/f'{label}.stderr').write_text(stderr)
    (work/f'{label}.command.json').write_text(json.dumps(record,indent=2)+'\n')
    if record.get('returncode')!=0: raise RuntimeError(f'{label} failed; see {work}/{label}.stderr')
    return stdout


def compiler_identity(compiler):
    path=shutil.which(str(compiler))
    if not path: raise ValueError('C compiler not found: '+str(compiler))
    path=Path(path).resolve()
    version=subprocess.run([str(path),'--version'],check=True,capture_output=True,text=True).stdout
    identity=dict(path=str(path),sha256=sha256(path),version=version)
    if platform.system()=='Darwin':
        target=subprocess.run([str(path),'-dumpmachine'],check=True,capture_output=True,text=True).stdout.strip()
        if not target: raise ValueError('Missing Darwin compiler target')
        identity['target']=target
    return identity


def darwin_toolchain_snapshot(work, label):
    work=Path(work)
    commands=(('os-build',['/usr/bin/sw_vers','-buildVersion']),
              ('sdk-path',['xcrun','--sdk','macosx','--show-sdk-path']),
              ('sdk-version',['xcrun','--sdk','macosx','--show-sdk-version']))
    values={key:_run(command,work,label+'-'+key).strip() for key,command in commands}
    if not values['os-build'] or not values['sdk-version'] or not Path(values['sdk-path']).is_absolute():
        raise ValueError('Missing Darwin SDK/OS identity')
    sdk_settings=Path(values['sdk-path'])/'SDKSettings.json'
    settings_hash=sha256(sdk_settings)
    context=dict(os_build=values['os-build'],sdk_path=values['sdk-path'],sdk_version=values['sdk-version'],
        sdk_settings_sha256=settings_hash,sdk_role='xcrun-selected SDK; actual compiler invocation retained separately')
    artifacts={str(sdk_settings):settings_hash}
    for key,_ in commands:
        for suffix in ('.stdout','.stderr','.command.json'):
            p=work/(label+'-'+key+suffix);artifacts[str(p)]=sha256(p)
    return context,artifacts


def recheck_darwin_toolchain(native,work,label):
    if platform.system()!='Darwin': return
    if compiler_identity(native['compiler']['path'])!=native['compiler']:
        raise ValueError('Darwin compiler/target identity drift')
    context,artifacts=darwin_toolchain_snapshot(work,label)
    if context!=native['darwin_toolchain']: raise ValueError('Darwin OS/SDK identity drift')
    for name,digest in artifacts.items():
        if name in native['artifacts'] and native['artifacts'][name]!=digest:
            raise ValueError('Darwin context artifact drift')
    if compiler_identity(native['compiler']['path'])!=native['compiler']:
        raise ValueError('Darwin compiler/target identity drift after context observation')
    for name,digest in native['artifacts'].items():
        if sha256(name)!=digest: raise ValueError('Darwin source/toolchain/artifact drift: '+name)
    native['artifacts'].update(artifacts)


def build_native(work,compiler='clang'):
    work=Path(work).resolve(); work.mkdir(parents=True,exist_ok=True)
    pins=assert_pins(); identity=compiler_identity(compiler)
    if platform.system()=='Darwin' and any(os.environ.get(key) is not None for key in runtime_image.DARWIN_LOADER_NAMES):
        raise ValueError('Darwin loader overrides are outside the supported profile')
    darwin_toolchain=None;context_artifacts={}
    if platform.system()=='Darwin':
        darwin_toolchain,context_artifacts=darwin_toolchain_snapshot(work,'darwin-initial')
    include=work/'include'; include.mkdir(exist_ok=True)
    (include/'libm-alias-finite.h').write_text('#define libm_alias_finite(a,b)\n')
    (include/'math_config.h').write_text('#include "modern_atan2f_shim.h"\n')
    (include/'modern_atan2f_sun.h').write_text(GNU_CONTROL)
    binary=work/'reference'; binary.unlink(missing_ok=True)
    command=[identity['path'],*FLAGS,'-I'+str(REFERENCE),'-I'+str(include),
             '-D__ieee754_atan2f=modern_atan2f_original',
             *(REFERENCE/name for name in ('modern_atan2f_glibc241.c','modern_atan2f_adapted.c','modern_atan2f_driver.c')),
             *([REFERENCE/'runtime_image.c', REFERENCE/'runtime_image_macho.c'] if platform.system()=='Darwin' else []),
             '-lm',*(['-ldl'] if platform.system()=='Linux' else []),'-o',binary]
    _run(command,work,'native-compile')
    if compiler_identity(compiler)!=identity or assert_pins()!=pins: raise ValueError('Compiler/source drift during native compilation')
    qualification=validate_metadata(_strict_json(_run([binary,'--qualify'],work,'native-preflight').strip()))
    preflight_final_environment=_final_context(work/'native-preflight.stderr')
    validate_process_identity(qualification, preflight_final_environment)
    preflight_libraries=runtime_libraries(qualification)
    artifacts={**pins,**context_artifacts,**{str(p):sha256(p) for p in include.iterdir()},str(binary):sha256(binary)}
    if platform.system()=='Darwin':
        _run([*command[:-2],'-###','-o',binary],work,'darwin-compiler-invocation')
        for suffix in ('.stdout','.stderr','.command.json'):
            p=work/('darwin-compiler-invocation'+suffix);artifacts[str(p)]=sha256(p)
        final_context,final_artifacts=darwin_toolchain_snapshot(work,'darwin-preflight-final')
        if final_context!=darwin_toolchain: raise ValueError('Darwin OS/SDK changed during compilation')
        artifacts.update(final_artifacts)
    return dict(binary=binary,compiler=identity,flags=FLAGS.copy(),source_commit=SOURCE_COMMIT,
                darwin_toolchain=darwin_toolchain,
                source_blob=SOURCE_BLOB,source_sha256=SOURCE_SHA256,constants_sha256=CONSTANTS_SHA256,
                artifacts=artifacts,preflight_environment=qualification,preflight_libraries=preflight_libraries,preflight_final_environment=preflight_final_environment,system=platform.system(),machine=platform.machine())


def _strict_json(text):
    def unique(pairs):
        result={}
        for key,value in pairs:
            if key in result: raise ValueError('Duplicate JSON key: '+key)
            result[key]=value
        return result
    def bad(value): raise ValueError('Nonfinite JSON constant: '+value)
    return json.loads(text,object_pairs_hook=unique,parse_constant=bad)


def validate_metadata(meta):
    required={'kind','rounding','initial_rounding','control','ftz','daz','binary32','binary64',
              'excess_precision','fma_controls','narrow_controls','gradual_controls',
              'atan2_library','fma_library','literal_atan2','pointer_atan2','original_atan2'}
    if platform.system()=='Darwin': required |= {'runtime_images','x87_control','symbol_path','loader_overrides'}
    if type(meta) is not dict or set(meta) not in (required,required|{'libc','libc_version'}):
        raise ValueError('Malformed native qualification metadata')
    expected=dict(kind='qualification',rounding='FE_TONEAREST',ftz=False,daz=False,
                  binary32=True,binary64=True,excess_precision=False,
                  fma_controls=9,narrow_controls=7,gradual_controls=4)
    for key,value in expected.items():
        if type(meta[key]) is not type(value) or meta[key]!=value: raise ValueError('Failed native qualification: '+key)
    if type(meta['initial_rounding']) is not int or type(meta['control']) is not int or not 0<=meta['control']<1<<64:
        raise ValueError('Malformed control word')
    if platform.machine().lower() in ('x86_64','amd64','i386','i686'):
        if meta['initial_rounding']!=0 or meta['control']&((1<<15)|(1<<6)|(3<<13)):
            raise ValueError('Unqualified x86 control word')
    elif platform.machine().lower() in ('aarch64','arm64'):
        if meta['initial_rounding']!=0 or meta['control']&((1<<24)|(1<<19)|(3<<22)|3):
            raise ValueError('Unqualified AArch64 control word')
    else: raise ValueError('Unsupported architecture qualification')
    for key in ('atan2_library','fma_library'):
        if type(meta[key]) is not str or not Path(meta[key]).is_absolute(): raise ValueError('Missing library identity')
    if platform.system()=='Darwin': validate_darwin_metadata(meta, paths=meta)
    for key in ('literal_atan2','pointer_atan2','original_atan2'):
        if not _u32(meta[key]): raise ValueError('Malformed literal/pointer control')
    if 'libc' in meta and (type(meta['libc']) is not str or type(meta['libc_version']) is not str):
        raise ValueError('Malformed libc version')
    return meta


def validate_final_context(meta):
    keys={'kind','rounding','rounding_code','control','ftz','daz'}
    if platform.system()=='Darwin': keys |= {'runtime_images','x87_control','symbol_path','loader_overrides'}
    if type(meta) is not dict or set(meta)!=keys: raise ValueError('Malformed final native context')
    if meta['kind']!='final-context' or meta['rounding']!='FE_TONEAREST' or type(meta['rounding_code']) is not int or meta['rounding_code']!=0:
        raise ValueError('Final native rounding changed')
    if meta['ftz'] is not False or meta['daz'] is not False or type(meta['control']) is not int or not 0<=meta['control']<1<<64:
        raise ValueError('Unqualified final native control word')
    if platform.machine().lower() in ('x86_64','amd64','i386','i686'):
        forbidden=(1<<15)|(1<<6)|(3<<13)
    elif platform.machine().lower() in ('aarch64','arm64'):
        forbidden=(1<<24)|(1<<19)|(3<<22)|3
    else: raise ValueError('Unsupported final architecture qualification')
    if meta['control']&forbidden: raise ValueError('Final native control state changed')
    if platform.system()=='Darwin': validate_darwin_metadata(meta)
    return meta


def validate_darwin_metadata(meta, paths=None):
    images=runtime_image.validate_images(meta['runtime_images'],paths)
    host={'arm64':'aarch64','aarch64':'aarch64','x86_64':'x86_64'}.get(platform.machine().lower())
    if host is None or images['atan2_library']['architecture']!=host:
        raise ValueError('Darwin image/host architecture mismatch')
    if type(meta['x87_control']) is not int or not 0<=meta['x87_control']<=65535:
        raise ValueError('Malformed Darwin x87 control')
    if (host=='x86_64' and meta['x87_control']&(3<<10)) or (host=='aarch64' and meta['x87_control']!=0):
        raise ValueError('Unsupported Darwin x87 control')
    if meta['symbol_path']!='volatile-pointers-equal-dlsym-default':
        raise ValueError('Unproven Darwin function pointers')
    overrides=meta['loader_overrides']
    if type(overrides) is not dict or set(overrides)!=set(runtime_image.DARWIN_LOADER_NAMES) or any(value is not None for value in overrides.values()):
        raise ValueError('Unsupported Darwin loader overrides')


def validate_process_identity(initial, final):
    if platform.system()=='Darwin':
        for key in ('runtime_images','x87_control','symbol_path','loader_overrides'):
            if initial[key]!=final[key]: raise ValueError('Native process image/control changed: '+key)
        mask=~63 if platform.machine().lower()=='x86_64' else -1
        if initial['control']&mask != final['control']&mask:
            raise ValueError('Native process floating-point controls changed')


def validate_cross_process(first, second):
    if platform.system()=='Darwin':
        def stable(meta):
            result=copy.deepcopy(meta)
            result['runtime_images']=runtime_image.stable_images(result['runtime_images'])
            if platform.machine().lower()=='x86_64': result['control'] &= ~63
            return result
        if stable(first)!=stable(second):
            raise ValueError('Mixed native Darwin process contexts')


def runtime_libraries(environment):
    if platform.system()=='Darwin':
        return runtime_image.enrich_images(environment['runtime_images'])
    return {key:dict(path=str(Path(environment[key]).resolve()),sha256=sha256(Path(environment[key]).resolve()))
            for key in ('atan2_library','fma_library')}


def recheck_runtime_libraries(native):
    """Fresh native process re-attests cache-backed code after candidate work.

    An old receipt, OS name or missing on-disk image can never authorize success.
    The original compiler/source/binary snapshots are checked before execution.
    """
    libraries=native.get('libraries')
    if type(libraries) is not dict or set(libraries)!={'atan2_library','fma_library'}:
        raise ValueError('Missing qualified runtime library identities')
    if platform.system()!='Darwin':
        for info in libraries.values():
            if type(info) is not dict or set(info)!={'path','sha256'} or type(info['path']) is not str or not Path(info['path']).is_absolute():
                raise ValueError('Malformed runtime library identity')
            if sha256(info['path'])!=info['sha256']: raise ValueError('Qualified runtime library drift during probe')
        return
    binary=Path(native['binary'])
    if not binary.is_absolute() or str(binary) not in native['artifacts']:
        raise ValueError('Missing attestation executable identity')
    for name,digest in native['artifacts'].items():
        if sha256(name)!=digest: raise ValueError('Native attestation artifact drift: '+name)
    label='runtime-recheck-'+uuid.uuid4().hex
    environment=validate_metadata(_strict_json(_run([binary,'--qualify'],binary.parent,label).strip()))
    final=_final_context(binary.parent/(label+'.stderr'))
    validate_process_identity(environment,final)
    validate_cross_process(native['environment'],environment)
    if runtime_libraries(environment)!=libraries:
        raise ValueError('Qualified Darwin runtime image drift during probe')
    recheck_darwin_toolchain(native,binary.parent,label+'-darwin')
    native.setdefault('runtime_rechecks',[]).append(dict(label=label,initial=environment,final=final))
    for suffix in ('.stdout','.stderr','.command.json'):
        path=binary.parent/(label+suffix);native['artifacts'][str(path)]=sha256(path)


def _final_context(path):
    lines=Path(path).read_text().splitlines()
    if not lines: raise ValueError('Missing final native control state')
    return validate_final_context(_strict_json(lines[-1]))


def _expected_tags(mask):
    if mask in (2048,4096): return []
    tags=[1]
    if mask&1: tags+=list(range(2,11))
    tags += [11,12,13]
    if mask&8:
        tags+=list(range(14,19))
        if mask&16: tags+=[19]
        return tags+[20]
    if mask&128:
        tags+=list(range(21,25))+[25,26]*31+list(range(27,38))
        if mask&256: tags+=[38]
    return tags+[39]


def parse_native(text,rows):
    lines=text.splitlines()
    if len(lines)!=len(rows)+1: raise ValueError('Wrong native observation count')
    environment=validate_metadata(_strict_json(lines[0])); records=[]
    fields={'id','y','x','accepted','pinned','original','native','sun','mask','index','gt','final','events'}
    for line,row in zip(lines[1:],rows):
        record=_strict_json(line)
        if type(record) is not dict or set(record)!=fields: raise ValueError('Malformed native record')
        if any(not _u32(record[k]) for k in ('id','y','x','mask','index','gt')): raise ValueError('Noncanonical native integers')
        if any(record[k]!=row[k] for k in ('id','y','x')): raise ValueError('Native input order/identity mismatch')
        finite=(row['y']&0x7fffffff)<0x7f800000 and (row['x']&0x7fffffff)<0x7f800000
        if type(record['accepted']) is not bool or record['accepted']!=finite: raise ValueError('Wrong finite acceptance')
        if not finite:
            if any(record[k] is not None for k in ('pinned','original','native','sun','final')) or record['mask']!=4096 or record['index'] or record['gt'] or record['events']!=[]:
                raise ValueError('Rejected input performed candidate operations')
        else:
            if any(not _u32(record[k]) for k in ('pinned','original','native','sun')): raise ValueError('Malformed binary32 result')
            if any(record[k]&0x7fffffff>=0x7f800000 for k in ('pinned','original')): raise ValueError('Pinned finite-input result is nonfinite')
            if record['pinned']!=record['original']: raise ValueError('Instrumented adaptation disagrees with unmodified pinned source')
            if type(record['final']) is not list or len(record['final'])!=2 or not all(map(_u32,record['final'])): raise ValueError('Malformed final binary64')
            if record['final'][0]&0x7ff00000==0x7ff00000: raise ValueError('Pinned final binary64 is nonfinite')
            mask=record['mask']
            if mask&~8191 or mask&4096 or record['index']>7 or record['gt']>1: raise ValueError('Invalid branch/classification')
            if mask&2048 and mask!=2048: raise ValueError('Zero return has extra branch flags')
            ax,ay=row['x']&0x7fffffff,row['y']&0x7fffffff
            early_zero=ay==0 and (ax==0 or row['x']>>31==0)
            if (mask==2048)!=early_zero: raise ValueError('Wrong early-zero branch')
            if mask==2048:
                if record['index'] or record['gt']: raise ValueError('Early-zero classification must be unset')
            else:
                gt=int(ay>ax); index=(row['y']>>31)*4+(row['x']>>31)*2+gt
                if record['gt']!=gt or record['index']!=index: raise ValueError('Wrong magnitude/quadrant classification')
                if bool(mask&1)!=(abs(ax-ay)<(27<<23)): raise ValueError('Wrong rational/shortcut guard')
                if mask&16 and not mask&8 or mask&256 and not mask&128: raise ValueError('Branch lacks its parent')
                if bool(mask&1)==bool(mask&2) or bool(mask&8)==bool(mask&128) and mask&4:
                    raise ValueError('Impossible branch combination')
                if bool(mask&4)!=bool(mask&(8|128)) or bool(mask&16)!=bool(mask&(32|64)):
                    raise ValueError('Missing ambiguity/tiny branch')
                if mask&32 and mask&64 or mask&512 and mask&1024: raise ValueError('Conflicting branch choices')
                if bool(mask&256)!=bool(mask&(512|1024)): raise ValueError('Missing correction branch')
            events=record['events']
            if type(events) is not list or len(events)>128 or any(type(e) is not list or len(e)!=3 or not all(map(_u32,e)) for e in events):
                raise ValueError('Malformed raw-word trace')
            if any(e[1]&0x7ff00000==0x7ff00000 for e in events): raise ValueError('Pinned intermediate is nonfinite')
            if [e[0] for e in events]!=_expected_tags(mask): raise ValueError('Wrong trace checkpoint sequence')
            if events:
                words={e[0]:(e[1]<<32)|e[2] for e in events}
                if bool(mask&4)!=(((words[13]+8)&0xfffffff)<=16): raise ValueError('Wrong low-bit ambiguity branch')
                if mask&4 and bool(mask&8)!=(ay<ax and (ax-ay)>>23>=25): raise ValueError('Wrong tiny/general guard')
                if mask&8 and bool(mask&16)!=((words[14]&0xfffffff)==0): raise ValueError('Wrong tiny boundary guard')
                if record['final']!=events[-1][1:]: raise ValueError('Final value differs from final checkpoint')
        records.append(record)
    return environment,records


def native_reference(rows,work,compiler='clang'):
    work=Path(work).resolve(); build=build_native(work,compiler)
    if any(type(r) is not dict or any(not _u32(r.get(k)) for k in ('id','y','x')) for r in rows):
        raise ValueError('Invalid reference input')
    if len({r['id'] for r in rows})!=len(rows): raise ValueError('Duplicate reference row IDs')
    input_text=''.join(f'{r["id"]} {r["y"]:08x} {r["x"]:08x}\n' for r in rows)
    (work/'native-input.txt').write_text(input_text)
    output=_run([build['binary']],work,'native-run',input_text=input_text)
    environment,records=parse_native(output,rows)
    final_environment=_final_context(work/'native-run.stderr')
    validate_process_identity(environment,final_environment)
    validate_cross_process(build['preflight_environment'],environment)
    libraries=runtime_libraries(environment)
    if libraries!=build['preflight_libraries']: raise ValueError('Runtime library identity changed after qualification')
    package=None
    if platform.system()=='Linux' and shutil.which('dpkg-query'):
        try:
            package=dict(available=True,identity=_run(['dpkg-query','-W','-f=${Package} ${Version} ${Architecture}\\n','libc6'],work,'libc-package').strip())
        except RuntimeError:
            package=dict(available=False,reason=(work/'libc-package.stderr').read_text().strip())
    if compiler_identity(compiler)!=build['compiler'] or assert_pins()!={str(p):build['artifacts'][str(p)] for p in source_paths()}:
        raise ValueError('Compiler/source drift during native execution')
    for name,digest in build['artifacts'].items():
        if sha256(name)!=digest: raise ValueError('Native artifact drift: '+name)
    recheck_darwin_toolchain(build,work,'darwin-native-final')
    historical=[(bits(y),bits(x)) for y,x in old_samples()]
    prefix=[(r['y'],r['x']) for r in rows[:1086]]
    baseline={}
    if prefix==historical:
        differences=[r['id'] for r in records[:1086] if r['pinned']!=r['sun']]
        results=[[r['id'],r['y'],r['x'],r['pinned'],r['sun']] for r in records[:1086]]
        changed=[r for r in results if r[3]!=r[4]]
        if len(differences)!=178 or hash_json(differences)!=HISTORICAL_IDS_SHA256 or hash_json(changed)!=HISTORICAL_DIFFERENCES_SHA256 or hash_json(results)!=HISTORICAL_RESULTS_SHA256:
            raise ValueError('Historical pinned/Sun difference IDs or output words changed')
        baseline=dict(count=1086,input_sha256=OLD_INPUTS_SHA256,pinned_sun_difference_count=178,
                      difference_indices=differences,difference_ids_sha256=HISTORICAL_IDS_SHA256,
                      differences_sha256=HISTORICAL_DIFFERENCES_SHA256,full_results_sha256=HISTORICAL_RESULTS_SHA256,
                      native_sun_difference_count=sum(r['native']!=r['sun'] for r in records[:1086]))
    coverage={name:sum(bool(r['mask']&flag) for r in records) for name,flag in BRANCHES.items()}
    metadata={k:v for k,v in build.items() if k!='binary'}
    metadata.update(binary=str(build['binary']),environment=environment,final_environment=final_environment,libraries=libraries,
                    libc_package=package,inputs_sha256=hashlib.sha256(input_text.encode()).hexdigest(),
                    observations=len(records),adapted_original_equal=True,
                    pinned_native_difference_count=sum(r['accepted'] and r['pinned']!=r['native'] for r in records),
                    baseline=baseline,coverage=coverage)
    generated=['native-input.txt']
    for prefix in ('native-compile','native-preflight','native-run', *(['libc-package'] if package is not None else [])):
        generated.extend(prefix+suffix for suffix in ('.stdout','.stderr','.command.json'))
    for name in generated:
        path=work/name; metadata['artifacts'][str(path)]=sha256(path)
    (work/'native-metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
    return metadata,records


def native_search(work,compiler,mode,budget):
    limits={'uniform':200000000,'boundary':1000000,'tiny':200000000}
    options={'uniform':'--search','boundary':'--search-boundary','tiny':'--search-tiny'}
    if mode not in limits or type(budget) is not int or not 0<budget<=limits[mode]:
        raise ValueError('Search mode/budget outside bounded domain')
    work=Path(work).resolve(); build=build_native(work,compiler)
    label='native-'+mode+'-search'
    output=_run([build['binary'],options[mode],str(budget),str(SEED)],work,label,timeout=180)
    values=[_strict_json(line) for line in output.splitlines()[1:]]
    rows=[{key:r[key] for key in ('id','y','x')} for r in values]
    environment,records=parse_native(output,rows)
    final_environment=_final_context(work/(label+'.stderr'))
    if compiler_identity(compiler)!=build['compiler'] or assert_pins()!={str(p):build['artifacts'][str(p)] for p in source_paths()}:
        raise ValueError('Compiler/source drift during native input generation')
    for path,digest in build['artifacts'].items():
        if sha256(path)!=digest: raise ValueError('Search artifact drift: '+path)
    validate_process_identity(environment,final_environment)
    validate_cross_process(build['preflight_environment'],environment)
    if runtime_libraries(environment)!=build['preflight_libraries']:
        raise ValueError('Search library identity drift')
    recheck_darwin_toolchain(build,work,'darwin-search-final')
    metadata={**build,'binary':str(build['binary']),'mode':mode,'budget':budget,'seed':SEED,
              'environment':environment,'final_environment':final_environment,
              'retained_observations':len(records),'candidate_run':False,'passed':False,
              'generator_summary':'\n'.join((work/(label+'.stderr')).read_text().splitlines()[:-1]),
              'coverage':{name:sum(bool(r['mask']&flag) for r in records) for name,flag in BRANCHES.items()}}
    for prefix in ('native-compile','native-preflight',label):
        for suffix in ('.stdout','.stderr','.command.json'):
            path=work/(prefix+suffix); metadata['artifacts'][str(path)]=sha256(path)
    (work/'native-search-metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
    return metadata


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work',type=Path,default=ROOT/'.build/modern-angle-reference')
    parser.add_argument('--compiler',default='clang')
    search=parser.add_mutually_exclusive_group()
    search.add_argument('--search-trials',type=int,default=0)
    search.add_argument('--search-boundaries',type=int,default=0)
    search.add_argument('--search-tiny',type=int,default=0)
    args=parser.parse_args()
    if args.search_boundaries or args.search_trials or args.search_tiny:
        mode='boundary' if args.search_boundaries else 'tiny' if args.search_tiny else 'uniform'
        budget=args.search_boundaries or args.search_trials or args.search_tiny
        metadata=native_search(args.work,args.compiler,mode,budget)
        print(json.dumps(dict(native_only=True,candidate_run=False,passed=False,mode=mode,budget=budget,
                              retained_observations=metadata['retained_observations'],coverage=metadata['coverage'])))
    else:
        metadata,records=native_reference(samples(),args.work,args.compiler)
        (args.work/'native-records.json').write_text(json.dumps(records)+'\n')
        print(json.dumps(dict(native_qualified=True,candidate_run=False,passed=False,
                              observations=len(records),coverage=metadata['coverage'],
                              pinned_native_differences=metadata['pinned_native_difference_count'])))


if __name__=='__main__': main()
