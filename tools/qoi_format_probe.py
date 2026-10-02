#!/usr/bin/env python3
"""Exact native QOI format/bytes before normalization, strict errors and owners.

Memory-only, native channel-3 RGB888 / channel-4 RGBA8888, single mip level.
CPU-1, CPU-2 and JavaScript are independent lanes; no GPU or file claim.
"""
import argparse
import hashlib
import json
import platform
from pathlib import Path
import random
import shutil
import struct
import subprocess
import time
import uuid

from bmp_probe import bend_bytes
from byte_probe import BEND_EMITTER
from conformance import BUILD, ROOT, ENV, checkout, source_gate
from reference_environment import ReferenceEnvironment

BATCH_SIZE = 64
MARKER = [0, 0, 0, 0, 0, 0, 0, 1]


def header(width=1, height=1, channels=4, space=0):
    return list(b'qoif'+struct.pack('>II', width, height)+bytes([channels, space]))


def stream(width, height, channels, space, payload):
    return header(width, height, channels, space)+list(payload)+MARKER


def runs(count):
    return [253]*(count//62)+([191+count%62] if count%62 else [])


def fixtures():
    result = []
    def add(name, width, height, channels, space, payload, extended=False):
        result.append(dict(id=name, width=width, height=height, channels=channels,
                           space=space, bytes=stream(width,height,channels,space,payload), extended=extended))
    for channels in (3,4):
        for space in (0,1):
            prefix=f'c{channels}-s{space}-'
            def core(name, width, height, payload, extended=False):
                add(prefix+name,width,height,channels,space,payload,extended)
            core('initial-run',1,1,[192])
            core('initial-index',1,1,[0])
            core('rgb',1,1,[254,12,34,56])
            for alpha in (0,1,127,254,255): core(f'rgba-{alpha}',1,1,[255,12,34,56,alpha])
            # Full-alpha hashes are 22 and 42. RGB output cannot expose alpha,
            # so the third pixel discriminates against early alpha normalization.
            core('hidden-alpha-cache',3,1,[255,12,34,56,0,255,200,100,50,64,22],True)
            # RGBA(12,34,56,0) -> RGB(10,20,30,0), DIFF(+1,-2,+1),
            # LUMA(+6,-1,-9), INDEX22 restores first RGBA (hash22).
            core('alpha-through-rgb-diff-luma',5,1,[255,12,34,56,0,254,10,20,30,0x73,0x9f,0xf0,22])
            core('empty-index-rgb-alpha',3,1,[63,254,1,2,3,0])
            core('cache-collision',3,1,[254,1,0,0,254,65,0,0,56])
            core('cache-index0-index63',4,1,[255,0,0,0,0,255,21,0,0,0,0,63])
            core('run-inserts-black',3,1,[192,53,0])
            core('cache-after-run',4,1,[255,12,34,56,0,193,22])
            core('noncanonical-repeated-index',3,1,[0,0,0])
            for count in (1,2,61,62,63,64,124): core(f'run-{count}',count,1,runs(count))
            core('row-crossing-run',3,5,[255,17,63,201,127]+runs(13)+[22])
            # Reset near both wrap boundaries before all 64 DIFF encodings.
            diff=[]
            for byte in range(64,128): diff += [254,0 if byte%2 else 255,255 if byte%2 else 0,0,byte]
            core('all-diff',16,8,diff)
            luma=[]
            for anchor in (0,255):
                for dg in (0,1,31,32,62,63):
                    for residual in (0,15,0x70,0x88,0xf0,0xff): luma += [254,anchor,anchor,anchor,128+dg,residual]
            core('luma-boundaries',12,12,luma)
            core('byte-alpha-ramps',16,16,[v for i in range(256) for v in (255,i,255-i,i^85,i)])
    for channels in (3,4):
        add(f'c{channels}-axis-row',4096,1,channels,0,runs(4096))
        add(f'c{channels}-axis-column',1,4096,channels,1,runs(4096))
        # A moderate nonuniform image above 4096 pixels, compact runs/literals.
        payload=[]
        for i in range(82): payload += [255,i,255-i,i^85,i*3%256]+runs(61)
        payload += [254,7,11,13]+runs(18)
        add(f'c{channels}-moderate-nonuniform',81,63,channels,0,payload)
        rng=random.Random(0x514f49)
        payload=[];count=0
        while count<513:
            choice=rng.randrange(6)
            if choice==0: chunk=[rng.randrange(64)];n=1
            elif choice==1: chunk=[64+rng.randrange(64)];n=1
            elif choice==2: chunk=[128+rng.randrange(64),rng.randrange(256)];n=1
            elif choice==3: n=min(513-count,rng.randrange(1,63));chunk=[191+n]
            elif choice==4: chunk=[254,*[rng.randrange(256) for _ in range(3)]];n=1
            else: chunk=[255,*[rng.randrange(256) for _ in range(4)]];n=1
            payload+=chunk;count+=n
        add(f'c{channels}-seeded-mix',27,19,channels,1,payload)
    for case in json.loads((ROOT/'tests/fixtures/images.json').read_text())['cases']:
        if 'qoi' in case:
            data=case['qoi']
            result.append(dict(id='legacy-'+case['id'],width=case['width'],height=case['height'],
                               channels=data[12],space=data[13],bytes=data,extended=False))
    if len({c['id'] for c in result})!=len(result): raise ValueError('Duplicate QOI fixture ID')
    return result


def controls():
    result=[]
    def add(name,data,error,native=False): result.append(dict(id=name,bytes=data,error=error,native=native))
    h=header();valid=stream(1,1,4,0,[192])
    for n in range(14): add(f'header-prefix-{n}',h[:n],0)
    for name,index,value in [('magic',0,0),*[(f'channels-{c}',12,c) for c in (0,1,2,5)],('colorspace',13,2)]:
        data=valid.copy();data[index]=value;add(name,data,0,True)
    for axis in ('width','height'):
        for value in (0,4097,0xffffffff): add(f'{axis}-{value}',header(**{axis:value})+[192]+MARKER,2,value==0)
    for name,index in [('header-byte',0),('payload-byte',14),('tail-byte',22)]:
        data=valid.copy();data[index]=256;add(name,data,1)
    data=valid.copy();data[0]=0;data[-1]=256;add('bad-byte-before-bad-header',data,1)
    data=header(width=0)+[256];add('bad-byte-before-bad-size',data,1)
    add('no-opcode',h,3)
    for tag,need in [(254,3),(255,4),(128,1)]:
        for n in range(need):add(f'truncated-{tag}-{n}',h+[tag]+[1]*n,3)
    add('pixel-underflow',header(width=2)+[192],3)
    add('missing-marker',h+[192],4)
    for n in range(8):
        data=valid.copy();data[-8+n]^=1;add(f'marker-corrupt-{n}',data,4)
        add(f'marker-prefix-{n}',h+[192]+MARKER[:n],4)
    for name,tail in [('zero',[0]),('opcode',[192]),('second-marker',MARKER)]:add('extra-'+name,valid+tail,4)
    add('run-overflow-first',stream(1,1,4,0,[193]),4)
    add('run-overflow-62',stream(61,1,3,0,[253]),4)
    add('run-overflow-late',stream(2,1,4,0,[192,193]),4)
    for tag in (254,255,128):add(f'marker-absorbed-{tag}',h+[tag]+MARKER,4)
    return result


def strict_json(text):
    def unique(pairs):
        out={}
        for key,value in pairs:
            if key in out:raise ValueError('Duplicate JSON key')
            out[key]=value
        return out
    return json.loads(text,object_pairs_hook=unique)


def meta(case,role):
    return dict(id=case['id'],role=role,width=case['width'],height=case['height'],mipmaps=1,
                format=(4 if case['channels']==3 else 7) if role in ('raw','factory','owner') else 7)


def parse_rows(text, actions):
    lines=text.splitlines();cursor=0;rows=[]
    for action in actions:
        case,role=action['case'],action['role']
        if cursor>=len(lines):raise ValueError('Missing QOI record')
        row=strict_json(lines[cursor]);cursor+=1
        if role=='error':
            expected=dict(id=case['id'],role=role,error=case['error'])
        elif role=='rejected':expected=dict(id=case['id'],role=role,rejected=True)
        else:expected=meta(case,role)
        if type(row) is not dict or row!=expected or any(type(row.get(k)) is not type(v) for k,v in expected.items()):
            raise ValueError(f'QOI metadata/order/type differs: {case["id"]}/{role}: {row!r}')
        if role not in ('error','rejected'):
            output=[]
            while cursor<len(lines):
                chunk=strict_json(lines[cursor]);cursor+=1
                if chunk=='end':break
                if type(chunk) is not list or not 1<=len(chunk)<=256 or any(type(v) is not int or not 0<=v<=255 for v in chunk):raise ValueError('Malformed QOI byte chunk')
                output.extend(chunk)
            else:raise ValueError('Unterminated QOI bytes')
            if len(output)!=case['width']*case['height']*{4:3,7:4}[row['format']]:raise ValueError('QOI byte count differs')
            row=dict(row,bytes=output)
        rows.append(row)
    if cursor!=len(lines):raise ValueError('Extra QOI records')
    return rows


C_PREFIX=r'''#include "raylib.h"
#include <stdio.h>
#include <stdlib.h>
static void emit(const unsigned char *p,int n){for(int start=0;start<n;start+=256){putchar('[');for(int i=start;i<n&&i<start+256;i++)printf("%s%u",i==start?"":",",p[i]);puts("]");}puts("\"end\"");}
static void observed(const char *id,const char *role,Image image){
  printf("{\"id\":\"%s\",\"role\":\"%s\",\"width\":%d,\"height\":%d,\"mipmaps\":%d,\"format\":%d}\n",id,role,image.width,image.height,image.mipmaps,image.format);
  emit(image.data,GetPixelDataSize(image.width,image.height,image.format));
}
'''


def reference_program(cases, rejected):
    lines=[C_PREFIX,'int main(void){SetTraceLogLevel(LOG_NONE);']
    for c in cases:
        lines+=['{const unsigned char data[]={'+','.join(map(str,c['bytes']))+'};',
                'Image image=LoadImageFromMemory(".qoi",data,sizeof(data));if(!image.data)return 2;',
                f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!={4 if c["channels"]==3 else 7})return 3;',
                f'observed({json.dumps(c["id"])},"raw",image);',
                # Raw observation must precede ANY normalization.
                'ImageFormat(&image,7);if(!image.data)return 4;',
                f'observed({json.dumps(c["id"])},"normalized",image);UnloadImage(image);']
        if c['extended']:
            lines+=['image=LoadImageFromMemory(".QOI",data,sizeof(data));if(!image.data)return 5;',
                    f'observed({json.dumps(c["id"])},"raw",image);UnloadImage(image);']
        lines+=['}']
    for c in rejected:
        # qoi wrapper reads byte12 before its size guard. All native rejection
        # buffers AND declared lengths are >=22, with no huge dimensions.
        if len(c['bytes'])<22:raise ValueError('Unsafe native QOI rejection buffer')
        lines+=['{const unsigned char data[]={'+','.join(map(str,c['bytes']))+'};',
                'Image image=LoadImageFromMemory(".qoi",data,sizeof(data));if(image.data){UnloadImage(image);return 6;}',
                'puts('+json.dumps(json.dumps(dict(id=c['id'],role='rejected',rejected=True),separators=(',',':')))+');}']
    return '\n'.join(lines+['return 0;}'])+'\n'


BEND_PREFIX=r'''import Base
import ../../../jonlib.bend as J
def reverse_into(values: +List<U32>, rest: +List<U32>) -> +List<U32>:
  match values:
    case Nil{}: rest
    case Con{head, tail}: reverse_into(tail, Con{head, rest})
def input_bytes(chunks: +List<+List<U32>>, values: +List<U32>) -> +List<U32>:
  match chunks:
    case Nil{}: List.reverse(&2, U32, values)
    case Con{head, tail}: input_bytes(tail, reverse_into(head, values))
def words.read(format: U32, state: Array<U32> & U32) -> Array<U32> & Bool:
  (pixels, word) = state
  (pixels, Bool.not(U32.is_eq(format, 4)) || (word <= 16777215 : U32))
def words(n: Nat, +index: U32, +format: U32, state: Array<U32> & Bool) -> Array<U32> & Bool:
  match n state:
    case _ Tuple{pixels, False{}}: (pixels, False{})
    case 0n Tuple{pixels, True{}}: (pixels, True{})
    case 1n+rest Tuple{pixels, True{}}: words(rest, (index + 1 : U32), format, words.read(format, Array.get(U32, pixels, index)))
def checked.words(width: U32, height: U32, format: U32, state: Array<U32> & Bool) -> Maybe<J.Image.Formatted>:
  match state:
    case Tuple{pixels, True{}}: Some{J.FormattedImage{width, height, format, pixels}}
    case _: None{}
def checked(image: J.Image.Formatted) -> Maybe<J.Image.Formatted>:
  J.FormattedImage{+width, +height, +format, pixels} = image
  checked.words(width, height, format, words(U32.to_nat((width * height : U32)), 0, format, (pixels, True{})))
def decoded(result: Result<&1, &1, J.Image.DecodeError, J.Image.Formatted>) -> Maybe<J.Image.Formatted>:
  match result:
    case Fail{_}: None{}
    case Done{image}: checked(image)
def surface(result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> Maybe<J.Image.Formatted>:
  match result:
    case Fail{_}: None{}
    case Done{image}: Some{J.Surface.to_formatted(image)}
def bridge(result: Maybe<J.Image.Formatted>) -> Maybe<J.Image.Formatted>:
  match result:
    case None{}: None{}
    case Some{image}: Some{J.Surface.to_formatted(J.Image.Formatted.to_surface(image))}
def owner.got(result: J.Image.Formatted & Maybe<&2, U32>) -> Maybe<J.Image.Formatted>:
  match result:
    case Tuple{image, None{}}: Some{image}
    case _: None{}
def owner(result: Maybe<J.Image.Formatted>, x: U32) -> Maybe<J.Image.Formatted>:
  match result:
    case None{}: None{}
    case Some{image}: owner.got(J.Image.Formatted.get(image, x, 0))
def emit(id: String, role: String, data: (U32 & U32) & (U32 & List<U32>)) -> IO(Unit):
  ((width, height), (format, bytes)) = data
  do IO<Unit>:
    # Formatted owners are single-mip by contract; there is no mipmaps field.
    IO.print("{\"id\":\"" ++ id ++ "\",\"role\":\"" ++ role ++ "\",\"width\":" ++ U32.show(width) ++ ",\"height\":" ++ U32.show(height) ++ ",\"mipmaps\":1,\"format\":" ++ U32.show(format) ++ "}")
    emit_bytes(~&1, bytes)
def observed(id: String, role: String, result: Maybe<J.Image.Formatted>) -> IO(Unit):
  match result:
    case None{}: IO.die(Unit, 1, "valid QOI or owner invariant rejected")
    case Some{image}: emit(id, role, J.Image.Formatted.export(image))
def error.code(error: J.Image.DecodeError) -> U32:
  match error:
    case J.InvalidImageHeader{}: 0
    case J.InvalidImageByte{}: 1
    case J.UnsupportedImageSize{}: 2
    case J.TruncatedImageData{}: 3
    case J.InvalidImageStream{}: 4
def formatted.error(result: Result<&1, &1, J.Image.DecodeError, J.Image.Formatted>) -> U32:
  match result:
    case Fail{error}: error.code(error)
    case Done{_}: 99
def surface.error(result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> U32:
  match result:
    case Fail{error}: error.code(error)
    case Done{_}: 99
def emit.error(id: String, code: U32) -> IO(Unit):
  IO.print("{\"id\":\"" ++ id ++ "\",\"role\":\"error\",\"error\":" ++ U32.show(code) ++ "}")
'''


def candidate_program(actions):
    lines=[BEND_PREFIX.replace('def reverse_into(',BEND_EMITTER+'def reverse_into(',1),'def main() -> IO(Unit):']
    bindings={}
    for action in actions:
        c=action['case']
        if c['id'] not in bindings:
            name='input'+str(len(bindings));bindings[c['id']]=name
            lines.append(f'  +{name} = {{{bend_bytes(c["bytes"])} : +List<U32>}}')
    lines.append('  do IO<Unit>:')
    for action in actions:
        c=action['case'];role=action['role'];data=bindings[c['id']];ident=json.dumps(c['id'])
        decode=f'decoded(J.Image.Formatted.decode_qoi({data}))'
        if role=='error':
            mode=action['mode'];call='J.Image.Formatted' if mode=='formatted' else 'J.Surface'
            lines.append(f'    emit.error({ident}, {mode}.error({call}.decode_qoi({data})))');continue
        if role=='raw':image=decode
        elif role=='bridge':image=f'bridge({decode})'
        elif role=='surface':image=f'surface(J.Surface.decode_qoi({data}))'
        elif role in ('dispatch','upper'):image=f'surface(J.Surface.decode_image({json.dumps(".QOI" if role=="upper" else ".qoi")}, {data}))'
        elif role in ('uncontracted','fused'):image=f'surface(J.Surface.decode_image_for(J.{"UncontractedDecode" if role=="uncontracted" else "FusedDecode"}{{}}, ".QOI", {data}))'
        elif role=='factory':image=f'J.Image.Formatted.from_bytes({c["width"]}, {c["height"]}, {4 if c["channels"]==3 else 7}, {bend_bytes(action["expected"]["bytes"])})'
        elif role=='owner':image=f'owner({decode}, {c["width"]})'
        else:raise ValueError('Unknown QOI observation')
        lines.append(f'    observed({ident}, {json.dumps(role)}, {image})')
    return '\n'.join(lines)+'\n'


def differences(expected,actual):
    if len(expected)!=len(actual):raise ValueError('QOI comparison count differs')
    out=[]
    for a,b in zip(expected,actual):
        if a!=b:
            item=dict(id=a['id'],role=a['role'])
            if 'bytes' in a and 'bytes' in b:
                item['first_byte']=next((i for i,(x,y) in enumerate(zip(a['bytes'],b['bytes'])) if x!=y),min(len(a['bytes']),len(b['bytes'])))
            out.append(item)
    return out


def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    destination=BUILD/'qoi-format-probe';destination.mkdir(parents=True,exist_ok=True)
    report_path=destination/'results.json';report_path.write_text('{"passed":false,"phase":"argument-validation"}\n')
    parser=argparse.ArgumentParser(description=__doc__,allow_abbrev=False)
    parser.add_argument('--bend-source',type=Path,required=True)
    parser.add_argument('--raylib-source',type=Path,required=True)
    args=parser.parse_args();started=time.monotonic()
    work=destination/('run-'+uuid.uuid4().hex);work.mkdir()
    lock=json.loads((ROOT/'toolchain.json').read_text())
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'))
    checkout(args.raylib_source,lock['raylib']['revision'])
    reference_env=ReferenceEnvironment('clean-loader')
    cases,invalid=fixtures(),controls();rejected=[c for c in invalid if c['native']]
    inputs=work/'inputs.json';inputs.write_text(json.dumps(dict(cases=cases,controls=invalid),sort_keys=True)+'\n')
    paths=[ROOT/p for p in ('tools/qoi_format_probe.py','tests/test_qoi_format_harness.py','tools/bmp_probe.py','tools/byte_probe.py','tools/conformance.py','tools/reference_environment.py','tools/runtime_image.py','toolchain.json','LAWS.bend','PROOF.bend','tests/fixtures/images.json')]
    paths += [args.raylib_source/'src'/p for p in ('rtextures.c','raylib.h','config.h','external/qoi.h')]
    paths += [p for p in (args.bend_source/'bend2').rglob('*') if p.is_file() and p.suffix in ('.ts','.bend','.c','.js','.h')]
    paths += [Path(shutil.which(tool)) for tool in ('bun','clang','cmake')]
    sealed={str(p):digest(p) for p in paths};sources=source_gate()
    report=dict(passed=False,run_directory=str(work),profile='native-qoi-formatted-memory-v1',
                toolchain=lock,base_revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                host=dict(system=platform.system(),machine=platform.machine()),sources=sources,
                dependencies=sealed.copy(),inputs_sha256=digest(inputs),reference_environment=reference_env.receipt(),
                cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),typed_controls=len(invalid),native_rejections=len(rejected),batch_size=BATCH_SIZE,lanes={},
                unrun=['GPU/Metal','Windows','big-endian','4096x4096 allocation/resource limit','file IO','generic formatted dispatch'])
    def save():report_path.write_text(json.dumps(report,indent=2)+'\n')
    def seal(path):sealed[str(path)]=digest(path)
    def verify():
        reference_env.assert_unchanged()
        if source_gate()!=sources or any(not Path(p).is_file() or digest(p)!=h for p,h in sealed.items()):raise ValueError('QOI source/tool/output drift')
    def run(command,label,native=False):
        verify();command=list(map(str,command))
        proc=subprocess.run(command,cwd=ROOT,env=reference_env.child() if native else ENV,text=True,capture_output=True,timeout=600)
        for ext,content in [('stdout',proc.stdout),('stderr',proc.stderr),('command.json',json.dumps(dict(command=command,returncode=proc.returncode)))]:
            path=work/(label+'.'+ext);path.write_text(content);seal(path)
        if proc.returncode:raise ValueError(f'{label} exited {proc.returncode}: {proc.stdout[-2000:]}{proc.stderr[-2000:]}')
        for i,arg in enumerate(command[:-1]):
            if arg=='-o':seal(Path(command[i+1]))
        return proc.stdout
    seal(inputs);save()
    report['host']['bun']=run(['bun','--version'],'bun-version').strip()
    if report['host']['bun']!=lock['bun']['version']:raise ValueError('Bun version differs')
    report['host']['clang']=run(['clang','--version'],'clang-version',True).splitlines()[0]
    cmake=work/'native'
    run(['cmake','-S',args.raylib_source,'-B',cmake,'-DPLATFORM=Memory','-DCMAKE_BUILD_TYPE=Release','-DBUILD_EXAMPLES=OFF','-DCUSTOMIZE_BUILD=ON','-DSUPPORT_MODULE_RAUDIO=OFF','-DSUPPORT_RPRAND_GENERATOR=ON','-DUSE_EXTERNAL_GLFW=OFF'],'configure',True)
    run(['cmake','--build',cmake,'--parallel','4'],'native-build',True)
    archive=cmake/'raylib/libraylib.a'
    for path in (archive,cmake/'CMakeCache.txt',cmake/'raylib/CMakeFiles/raylib.dir/flags.make'):seal(path)
    source=work/'reference.c';source.write_text(reference_program(cases,rejected));seal(source)
    binary=work/'reference'
    run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,archive,'-lm','-o',binary],'reference-compile',True)
    actions=[]
    for c in cases:
        actions += [dict(case=c,role=role) for role in ('raw','normalized')]
        if c['extended']:actions.append(dict(case=c,role='raw'))
    actions += [dict(case=c,role='rejected') for c in rejected]
    report['native_observations']=len(actions)
    reftext=run([binary],'reference',True);rows=parse_rows(reftext,actions);reference={};cursor=0
    for c in cases:
        raw,normal=rows[cursor:cursor+2];cursor+=2
        if c['extended']:
            if rows[cursor]!=raw:raise ValueError('Uppercase native QOI differs')
            cursor+=1
        reference[c['id']]=(raw,normal)
    report['native_raw_bytes']=sum(len(raw['bytes']) for raw,_ in reference.values())
    report['native_normalized_bytes']=sum(len(normal['bytes']) for _,normal in reference.values())
    report['reference_sha256']=hashlib.sha256(reftext.encode()).hexdigest()
    actions=[]
    for c in cases:
        raw,normal=reference[c['id']]
        for role in ('raw','bridge','surface','dispatch',*(('upper','uncontracted','fused','factory','owner') if c['extended'] else ())):
            expected=dict(raw if role in ('raw','factory','owner') else normal,role=role)
            actions.append(dict(case=c,role=role,expected=expected))
    for c in invalid:
        for mode in ('formatted','surface'):actions.append(dict(case=c,role='error',mode=mode,expected=dict(id=c['id'],role='error',error=c['error'])))
    report['observations_per_lane']=len(actions)
    report['compared_bytes_per_lane']=sum(len(a['expected'].get('bytes',[])) for a in actions)
    for lane in ('cpu-1','cpu-2','javascript'):report['lanes'][lane]=dict(passed=False,batches=[],differences=[])
    save()
    for start in range(0,len(actions),BATCH_SIZE):
        selected=actions[start:start+BATCH_SIZE];index=start//BATCH_SIZE
        source=work/f'candidate-{index}.bend';source.write_text(candidate_program(selected));seal(source)
        binary=work/f'candidate-{index}';js=work/f'candidate-{index}.js'
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary,'-o',js],f'compile-{index}')
        for lane in report['lanes']:
            command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            actual=parse_rows(run(command,f'{lane}-{index}'),selected)
            delta=differences([a['expected'] for a in selected],actual)
            report['lanes'][lane]['differences'].extend(delta)
            report['lanes'][lane]['batches'].append(dict(start=start,count=len(selected),passed=not delta));save()

        print(f'QOI batch {index+1}: {len(selected)} observations compared on CPU-1/CPU-2/JavaScript',flush=True)
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision']);verify()
    for lane in report['lanes']:
        if sum(b['count'] for b in report['lanes'][lane]['batches'])!=len(actions):raise ValueError('Incomplete QOI lane')
        report['lanes'][lane]['passed']=not report['lanes'][lane]['differences']
    if any(not lane['passed'] for lane in report['lanes'].values()):
        save();raise ValueError('QOI byte differences: '+str({k:v['differences'] for k,v in report['lanes'].items()}))
    report.update(passed=True,elapsed_seconds=round(time.monotonic()-started,3),artifacts=sealed);save()
    print(f'PASS: {len(cases)} native QOI images, {len(invalid)} typed failures through both entrypoints, {report["compared_bytes_per_lane"]} bytes per lane',flush=True)


if __name__=='__main__':main()
