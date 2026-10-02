#!/usr/bin/env python3
"""Native original-format QOI ordinary files: exact bytes, typed IO and closure.

Explicit QOI selection ignores suffix; native LoadImage and explicit
LoadFileData/LoadImageFromMemory references are recorded separately.
"""
import argparse
import errno
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time
import uuid

import qoi_format_probe as memory
from byte_probe import BEND_EMITTER
from conformance import BUILD, ROOT, ENV, checkout, source_gate
from reference_environment import ReferenceEnvironment
from raw_file_probe import limit_handles
from r32_raw_file_probe import RESOURCE_RUNNER

BATCH_SIZE = 64
QOI_CAP = 83886102
MAX_SPARSE_RSS = 256*1024*1024
MAX_STRESS_RSS = 1024*1024*1024
LANES = ('cpu-1', 'cpu-2', 'javascript')


def fixtures():
    cases = [dict(c, filename=c['id']+'.qoi', route='LoadImage', regress=c['extended'] or c['id']=='c3-seeded-mix') for c in memory.fixtures()]
    by_id = {c['id']:c for c in cases}
    for channels in (3,4):
        original=by_id[f'c{channels}-s0-hidden-alpha-cache']
        for name,suffix,route in [('upper','.QOI','LoadImage'),('mixed','.QoI','explicit-qoi'),('without-extension','','explicit-qoi'),('misnamed','.png','explicit-qoi'),('spaces',' with spaces.qoi','LoadImage'),('many.parts','.v1.qoi','LoadImage'),('directory-dotfile','/.qoi','LoadImage')]:
            ident=f'path-c{channels}-{name}'
            cases.append(dict(original,id=ident,filename=ident+suffix,route=route,regress=True))
    return cases


def controls():
    result=[dict(c,filename='error-'+c['id']+'.qoi') for c in memory.controls() if all(0<=b<=255 for b in c['bytes'])]
    result += [dict(id='not-qoi-raster',filename='raster.qoi',bytes=list(b'P6\n1 1\n255\n\x12\x34\x56'),error=0,native=False)]
    for ident,filename,special,error in [('missing','missing.png','missing',5),('missing-parent','missing-parent/input.qoi','missing',5),('directory','directory.qoi','directory',5),('cap-plus-one','cap-plus-one.qoi','sparse',2),('cap-misleading','cap-plus-one.png','sparse',2),('host-size-overflow','host-size-overflow.qoi','overflow',5)]:
        result.append(dict(id=ident,filename=filename,special=special,error=error,native=False))
    return result


def prepare_inputs(work,cases,invalid):
    directory_stage=None
    for c in cases+invalid:
        path=work/'fixtures'/c['filename'];c['path']=str(path.relative_to(ROOT))
        special=c.get('special')
        if special=='missing':
            if path.exists():raise ValueError('Missing-file fixture unexpectedly exists')
            continue
        path.parent.mkdir(parents=True,exist_ok=True)
        if special=='directory':
            path.mkdir();(path/'entry').write_bytes(b'x')
            stage='open';fd=None
            try:
                fd=os.open(path,os.O_RDONLY);stage='size';os.fstat(fd);stage='read';os.read(fd,1)
                raise ValueError('Host directory unexpectedly readable')
            except OSError as error:directory_stage=dict(stage=stage,code=error.errno,message=error.strerror)
            finally:
                if fd is not None:os.close(fd)
        elif special in ('sparse','overflow'):
            prefix=memory.stream(1,1,4,0,[192]);size=QOI_CAP+1 if special=='sparse' else 4294967296
            with path.open('wb') as handle:handle.write(bytes(prefix));handle.truncate(size)
            c.update(size=size,prefix=prefix,sparse_recipe='write tiny prefix at offset 0, then truncate to logical size; never hash/read hole')
        else:path.write_bytes(bytes(c['bytes']))
    stress=dict(id='in-cap-full-read',filename='in-cap-full-read.qoi',error=0,size=1048577,special='stress',native=False)
    path=work/'fixtures'/stress['filename'];path.write_bytes(b'x'*stress['size']);stress['path']=str(path.relative_to(ROOT))
    return stress,directory_stage


def reference_program(cases,rejected):
    lines=[memory.C_PREFIX,'int main(void){SetTraceLogLevel(LOG_NONE);']
    for c in cases:
        if c.get('special') or len(c['bytes'])<22:raise ValueError('Unsafe native file fixture')
        path=json.dumps(c['path']);lines+=['{']
        if c['route']=='LoadImage':lines += [f'Image image=LoadImage({path});']
        elif c['route']=='explicit-qoi':
            lines += [f'int size=0;unsigned char *data=LoadFileData({path},&size);',f'if(!data||size!={len(c["bytes"])}||size<22){{if(data)UnloadFileData(data);return 7;}}',
                      'Image image=LoadImageFromMemory(".qoi",data,size);UnloadFileData(data);']
        else:raise ValueError('Unknown native file route')
        lines += ['if(!image.data)return 2;',f'if(image.width!={c["width"]}||image.height!={c["height"]}||image.mipmaps!=1||image.format!={4 if c["channels"]==3 else 7})return 3;',
                  f'if(GetPixelDataSize(image.width,image.height,image.format)!={c["width"]*c["height"]*c["channels"]})return 8;',
                  f'observed({json.dumps(c["id"])},"raw",image);','ImageFormat(&image,7);if(!image.data)return 4;',
                  f'observed({json.dumps(c["id"])},"normalized",image);UnloadImage(image);','}']
    for c in rejected:
        if c.get('special') or len(c['bytes'])<22 or not c.get('native'):raise ValueError('Unsafe native rejection file')
        lines += ['{',f'Image image=LoadImage({json.dumps(c["path"])});if(image.data){{UnloadImage(image);return 6;}}',
                  'puts('+json.dumps(json.dumps(dict(id=c['id'],role='rejected',rejected=True),separators=(',',':')))+');}']
    return '\n'.join(lines+['return 0;}'])+'\n'


# Reuse the strict chunk framing and checked owner observation, not a Python QOI oracle.
BEND_PREFIX = memory.BEND_PREFIX.replace('def reverse_into(',BEND_EMITTER+'def reverse_into(',1)+r'''
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
    case Done{_}: emit.error(id, 99)
    case Fail{error}: emit.error(id, load.error(error))
def surface.failed(id: String, result: Result<&1, &1, J.Image.LoadError, J.Surface>) -> IO(Unit):
  match result:
    case Done{_}: emit.error(id, 99)
    case Fail{error}: emit.error(id, load.error(error))
def require(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "QOI file boundary or closure differs")
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
    emit.error(id, 5)
def stage.short(result: Result<&1, &1, J.Image.LoadError, +List<U32>>) -> IO(Unit):
  IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Formatted>, Unit, J.Image.Formatted.qoi.file.loaded(result), required(3))
def stage.failure(result: Result<&1, &1, J.Image.LoadError, +List<U32>>) -> IO(Unit):
  IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Formatted>, Unit, J.Image.Formatted.qoi.file.loaded(result), exact.error(731, "stage-read-failure"))
def stage.opened(fail: Bool, result: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match fail result:
    case _ Fail{_}: IO.die(Unit, 1, "stage fixture open failed")
    case False{} Done{file}:
      IO.bind(Result<&1, &1, J.Image.LoadError, +List<U32>>, Unit,
        J.Image.file.read(2, (file, Done{[1]})), stage.short)
    case True{} Done{file}:
      IO.bind(Result<&1, &1, J.Image.LoadError, +List<U32>>, Unit,
        J.Image.file.read(2, (file, Fail{(731, "stage-read-failure")})), stage.failure)
'''


def candidate_program(actions):
    lines=[BEND_PREFIX,'def main() -> IO(Unit):','  do IO<Unit>:']
    for action in actions:
        c=action['case'];role=action['role'];ident=json.dumps(c['id']);path=json.dumps(c['path'])
        output='J.Image.Formatted';call=f'J.Image.Formatted.load_qoi({path})'
        if role=='raw':continuation=f'load.emitted({ident}, "raw")'
        elif role=='bridge':continuation=f'bridge.emitted({ident})'
        elif role=='error':
            continuation=f'load.failed({ident})'
            if c.get('special')=='overflow':continuation=f'file.failed({ident}, {errno.EOVERFLOW})'
            if action.get('mode')=='dispatch':output='J.Surface';call=f'J.Surface.load_image({path})';continuation=f'surface.failed({ident})'
        else:
            output='J.Surface';continuation=f'surface.emitted({ident}, {json.dumps(role)})'
            if role=='surface':call=f'J.Surface.load_qoi({path})'
            elif role=='dispatch':call=f'J.Surface.load_image({path})'
            elif role in ('uncontracted','fused'):call=f'J.Surface.load_image_for(J.{"UncontractedDecode" if role=="uncontracted" else "FusedDecode"}{{}}, {path})'
            else:raise ValueError('Unknown candidate file role')
        lines.append(f'    IO.bind(Result<&1, &1, J.Image.LoadError, {output}>, Unit, {call}, {continuation})')
    return '\n'.join(lines)+'\n'


def boundary_program(cases,invalid,reference=None):
    by_id={c['id']:c for c in cases+invalid}
    loads=[('c3-s0-hidden-alpha-cache',99),('c4-s0-hidden-alpha-cache',99),('magic',0),('directory',5),('cap-plus-one',2),('host-size-overflow',5)]
    lines=[BEND_PREFIX,'def closure_loop(n: Nat) -> IO(Unit):','  match n:','    case 0n: IO.pure(Unit, Unit{})','    case 1n+rest:','      do IO<Unit>:']
    for name,code in loads:
        continuation=f'required({code})'
        if code==99:
            channels=by_id[name]['channels']
            values=reference[name][0]['bytes'] if reference else ([12,34,56,200,100,50,12,34,56] if channels==3 else [12,34,56,0,200,100,50,64,12,34,56,0])
            continuation=f'success.required({4 if channels==3 else 7}, {memory.bend_bytes(values)})'
        if name=='host-size-overflow':continuation=f'file.code.required({errno.EOVERFLOW})'
        lines.append(f'        IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Formatted>, Unit, J.Image.Formatted.load_qoi({json.dumps(by_id[name]["path"])}), {continuation})')
    valid=json.dumps(by_id['c3-s0-hidden-alpha-cache']['path'])
    for value in ('False{}','True{}'):lines.append(f'        IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open({valid}, "r"), stage.opened({value}))')
    lines += ['        closure_loop(rest)','def main() -> IO(Unit):','  do IO<Unit>:','    require(U32.is_eq(J.Image.file.limit(J.QoiFile{}), 83886102) && (83886102 <= J.Image.file.limit(J.QoiFile{}) : U32) && Bool.not((83886103 <= J.Image.file.limit(J.QoiFile{}) : U32)))',
              '    require(J.Image.file.complete(0n, Nil{}) && J.Image.file.complete(2n, [1, 2]) && Bool.not(J.Image.file.complete(2n, [1])) && Bool.not(J.Image.file.complete(1n, [1, 2])))']
    synthetic=[('Fail{J.ImageFileError{719, "continuation-failure"}}','exact.error(719, "continuation-failure")'),('J.Image.file.payload(2, Fail{(727, "payload-failure")})','exact.error(727, "payload-failure")'),('J.Image.file.payload(2, Done{[1]})','required(3)'),('J.Image.file.payload(1, Done{[1, 2]})','required(3)'),('Done{[256]}','required(1)')]
    for value,cont in synthetic:lines.append(f'    IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Formatted>, Unit, J.Image.Formatted.qoi.file.loaded({value}), {cont})')
    lines += ['    closure_loop(100n)',f'    IO.bind(Result<&1, &1, J.Image.LoadError, J.Image.Formatted>, Unit, J.Image.Formatted.load_qoi({valid}), load.emitted("closure-final", "raw"))','    IO.print("{\\"closure_checks\\":true,\\"iterations\\":100,\\"paths_per_iteration\\":8,\\"synthetic_checks\\":7}")']
    return '\n'.join(lines)+'\n'


def parse_boundary(text,case,expected):
    lines=text.splitlines()
    terminal=dict(closure_checks=True,iterations=100,paths_per_iteration=8,synthetic_checks=7)
    row=memory.strict_json(lines[-1]) if lines else None
    if type(row) is not dict or row!=terminal or any(type(row.get(k)) is not type(v) for k,v in terminal.items()):raise ValueError('Missing strict closure terminal')
    final=dict(case,id='closure-final');rows=memory.parse_rows('\n'.join(lines[:-1]),[dict(case=final,role='raw')])
    if rows!=[dict(expected,id='closure-final')]:raise ValueError('Closure final load differs')
    return terminal


def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    destination=BUILD/'qoi-file-probe';destination.mkdir(parents=True,exist_ok=True)
    report_path=destination/'results.json';report_path.write_text('{"passed":false,"phase":"argument-validation"}\n')
    parser=argparse.ArgumentParser(description=__doc__,allow_abbrev=False)
    parser.add_argument('--bend-source',type=Path,required=True);parser.add_argument('--raylib-source',type=Path,required=True)
    args=parser.parse_args();started=time.monotonic();work=destination/('run-'+uuid.uuid4().hex);work.mkdir()
    lock=json.loads((ROOT/'toolchain.json').read_text());checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision'])
    reference_env=ReferenceEnvironment('clean-loader');cases,invalid=fixtures(),controls();stress,directory_stage=prepare_inputs(work,cases,invalid);rejected=[c for c in invalid if c.get('native')]
    inputs=work/'inputs.json';inputs.write_text(json.dumps(dict(cases=cases,controls=invalid,stress=stress),sort_keys=True)+'\n')
    paths=[ROOT/p for p in ('tools/qoi_file_probe.py','tests/test_qoi_file_harness.py','tools/qoi_format_probe.py','tools/raw_file_probe.py','tools/r32_raw_file_probe.py','tools/bmp_probe.py','tools/byte_probe.py','tools/conformance.py','tools/reference_environment.py','tools/runtime_image.py','toolchain.json','LAWS.bend','PROOF.bend','tests/fixtures/images.json')]
    paths += [args.raylib_source/'src'/p for p in ('rcore.c','rtextures.c','raylib.h','config.h','external/qoi.h')]
    paths += [p for p in (args.bend_source/'bend2').rglob('*') if p.is_file() and p.suffix in ('.ts','.bend','.c','.js','.h')]
    paths += [Path(shutil.which(tool)) for tool in ('bun','clang','cmake')]
    sealed={str(p):digest(p) for p in paths};sources=source_gate()
    report=dict(passed=False,run_directory=str(work),profile='native-qoi-formatted-files-v1',toolchain=lock,base_revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),host=dict(system=platform.system(),machine=platform.machine()),sources=sources,dependencies=sealed.copy(),inputs_sha256=digest(inputs),reference_environment=reference_env.receipt(),cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),typed_controls=len(invalid),native_rejections=len(rejected),native_routes={route:sum(c['route']==route for c in cases) for route in ('LoadImage','explicit-qoi')},batch_size=BATCH_SIZE,lanes={},closure_iterations=100,closure_paths_per_iteration=8,file_descriptor_limit=64,maximum_sparse_runtime_rss_bytes=MAX_SPARSE_RSS,maximum_stress_runtime_rss_bytes=MAX_STRESS_RSS,host_directory_observation=directory_stage,unrun=['GPU/Metal','Windows','browser JavaScript','big-endian','4096x4096 allocation/resource limit','concurrent/special files','generic formatted dispatch','OS close-error reporting'])
    def save():report_path.write_text(json.dumps(report,indent=2)+'\n')
    def seal(path):sealed[str(path)]=digest(path)
    def verify():
        reference_env.assert_unchanged()
        if source_gate()!=sources or any(not Path(p).is_file() or digest(p)!=h for p,h in sealed.items()):raise ValueError('QOI file source/tool/output drift')
        for c in invalid:
            if c.get('special') in ('sparse','overflow'):
                path=ROOT/c['path']
                if path.stat().st_size!=c['size']:raise ValueError('Sparse fixture size drift')
                with path.open('rb') as handle:
                    if handle.read(len(c['prefix']))!=bytes(c['prefix']):raise ValueError('Sparse fixture prefix drift')
    def run(command,label,native=False,resource_ceiling=None):
        verify();command=list(map(str,command));invocation=command
        if resource_ceiling:
            usage=work/(label+'.resource.json');invocation=[sys.executable,'-c',RESOURCE_RUNNER,str(usage),*command]
        began=time.monotonic()
        try:proc=subprocess.run(invocation,cwd=ROOT,env=reference_env.child() if native else ENV,text=True,capture_output=True,timeout=240 if resource_ceiling else 600,preexec_fn=limit_handles if resource_ceiling else None)
        except subprocess.TimeoutExpired as error:
            receipt=work/(label+'.command.json');receipt.write_text(json.dumps(dict(command=command,invocation=invocation,timed_out=True,elapsed_seconds=time.monotonic()-began)));seal(receipt);raise
        for ext,content in [('stdout',proc.stdout),('stderr',proc.stderr),('command.json',json.dumps(dict(command=command,invocation=invocation,returncode=proc.returncode,elapsed_seconds=round(time.monotonic()-began,3),descriptor_limit=64 if resource_ceiling else None)))]:
            path=work/(label+'.'+ext);path.write_text(content);seal(path)
        if proc.returncode:raise ValueError(f'{label} exited {proc.returncode}: {proc.stdout[-2000:]}{proc.stderr[-2000:]}')
        for i,arg in enumerate(command[:-1]):
            if arg=='-o':seal(Path(command[i+1]))
        resource_result=None
        if resource_ceiling:
            seal(usage);resource_result=json.loads(usage.read_text());rss=resource_result['maximum_rss_bytes']
            if type(rss) is not int or not 0<rss<=resource_ceiling:raise ValueError(f'{label}: runtime RSS {rss} exceeds fixed ceiling {resource_ceiling}')
            resource_result['elapsed_seconds']=round(time.monotonic()-began,3)
        return proc.stdout,resource_result
    # Small fixture contents are sealed; sparse holes are represented by recipe and size.
    for c in cases+invalid+[stress]:
        if c.get('special') not in ('sparse','overflow','missing','directory'):seal(ROOT/c['path'])
    seal(inputs);save()
    report['host']['bun']=run(['bun','--version'],'bun-version')[0].strip()
    if report['host']['bun']!=lock['bun']['version']:raise ValueError('Bun version differs')
    report['host']['clang']=run(['clang','--version'],'clang-version',True)[0].splitlines()[0]
    cmake=work/'native';run(['cmake','-S',args.raylib_source,'-B',cmake,'-DPLATFORM=Memory','-DCMAKE_BUILD_TYPE=Release','-DBUILD_EXAMPLES=OFF','-DCUSTOMIZE_BUILD=ON','-DSUPPORT_MODULE_RAUDIO=OFF','-DSUPPORT_RPRAND_GENERATOR=ON','-DUSE_EXTERNAL_GLFW=OFF'],'configure',True);run(['cmake','--build',cmake,'--parallel','4'],'native-build',True)
    archive=cmake/'raylib/libraylib.a'
    for path in (archive,cmake/'CMakeCache.txt',cmake/'raylib/CMakeFiles/raylib.dir/flags.make'):seal(path)
    source=work/'reference.c';source.write_text(reference_program(cases,rejected));seal(source);binary=work/'reference';run(['clang','-std=c11','-O2','-I'+str(args.raylib_source/'src'),source,archive,'-lm','-o',binary],'reference-compile',True)
    native_actions=[dict(case=c,role=role) for c in cases for role in ('raw','normalized')]+[dict(case=c,role='rejected') for c in rejected]
    reftext=run([binary],'reference',True)[0];rows=memory.parse_rows(reftext,native_actions);reference={c['id']:(rows[2*i],rows[2*i+1]) for i,c in enumerate(cases)}
    report.update(native_observations=len(native_actions),native_raw_bytes=sum(len(raw['bytes']) for raw,_ in reference.values()),native_normalized_bytes=sum(len(normal['bytes']) for _,normal in reference.values()),reference_sha256=hashlib.sha256(reftext.encode()).hexdigest())
    actions=[]
    for c in cases:
        raw,normal=reference[c['id']]
        roles=['raw']+(['bridge','surface']+(['dispatch','uncontracted','fused'] if c['route']=='LoadImage' else []) if c['regress'] else [])
        for role in roles:actions.append(dict(case=c,role=role,expected=dict(raw if role=='raw' else normal,role=role)))
        if c['regress'] and c['route']=='explicit-qoi':
            control=dict(c,id=c['id']+'-generic',error=0);actions.append(dict(case=control,role='error',mode='dispatch',expected=dict(id=control['id'],role='error',error=0)))
    actions += [dict(case=c,role='error',expected=dict(id=c['id'],role='error',error=c['error'])) for c in invalid]
    report.update(observations_per_lane=len(actions),compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions))
    for lane in LANES:report['lanes'][lane]=dict(passed=False,batches=[],differences=[])
    save()
    for start in range(0,len(actions),BATCH_SIZE):
        selected=actions[start:start+BATCH_SIZE];index=start//BATCH_SIZE;source=work/f'candidate-{index}.bend';source.write_text(candidate_program(selected));seal(source);binary=work/f'candidate-{index}';js=work/f'candidate-{index}.js'
        run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary,'-o',js],f'compile-{index}')
        for lane in LANES:
            command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            actual=memory.parse_rows(run(command,f'{lane}-{index}')[0],selected);delta=memory.differences([a['expected'] for a in selected],actual)
            report['lanes'][lane]['differences'].extend(delta);report['lanes'][lane]['batches'].append(dict(start=start,count=len(selected),passed=not delta));save()
        print(f'QOI file batch {index+1}: {len(selected)} observations compared on CPU-1/CPU-2/JavaScript',flush=True)
    # The unchanged pre-read source guard rejects sparse sizes before any payload read.
    # Runtime ceilings are post-run evidence, not live allocation limits; strict timeouts apply.
    for kind,program,ceiling in [('boundary',boundary_program(cases,invalid,reference),MAX_SPARSE_RSS),('stress',candidate_program([dict(case=stress,role='error')]),MAX_STRESS_RSS)]:
        source=work/(kind+'.bend');source.write_text(program);seal(source);binary=work/kind;js=work/(kind+'.js');run(['bun',args.bend_source/'bend2/main.ts',source,'-o',binary,'-o',js],kind+'-compile')
        for lane in LANES:
            command=['bun',js] if lane=='javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            text,usage=run(command,lane+'-'+kind,resource_ceiling=ceiling)
            if kind=='boundary':
                final=next(c for c in cases if c['id']=='c3-s0-hidden-alpha-cache');parse_boundary(text,final,reference[final['id']][0])
            else:memory.parse_rows(text,[dict(case=stress,role='error')])
            report['lanes'][lane][kind]=dict(passed=True,**usage);save()
        print('QOI file '+kind+': all three lanes passed',flush=True)
    checkout(args.bend_source,lock['bend']['revision'],lock['bend'].get('patch'));checkout(args.raylib_source,lock['raylib']['revision']);verify()
    for lane in report['lanes'].values():
        if sum(b['count'] for b in lane['batches'])!=len(actions):raise ValueError('Incomplete QOI file lane')
        lane['passed']=not lane['differences'] and lane['boundary']['passed'] and lane['stress']['passed']
    if any(not lane['passed'] for lane in report['lanes'].values()):save();raise ValueError('QOI file byte differences')
    report.update(passed=True,elapsed_seconds=round(time.monotonic()-started,3),artifacts=sealed);save()
    print(f'PASS: {len(cases)} native QOI files, {len(invalid)} typed file controls, {report["compared_bytes_per_lane"]} bytes per lane',flush=True)


if __name__=='__main__':main()
