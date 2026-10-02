#!/usr/bin/env python3
"""Fresh standalone native-angle contract qualification. Never runs Bend.

Frozen source-derived expectations, runtime-pointer observations and unchanged
canonical raymath/image observations are deliberately separate evidence.
"""
import argparse
import copy
from datetime import datetime, timezone
import hashlib
import inspect
import json
import os
from pathlib import Path
import platform
import re
import shutil
import struct
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / 'tools/reference'
MANIFEST = REFERENCE / 'angle_qualification_v1.json'
MANIFEST_SHA256 = '31fe9fa37f986e51534509065d67eca0a74a58aae3831923d8d13d2cbe64d416'
CANONICAL_FLAGS = ['-std=c11', '-O2', '-fno-builtin-atan2f']
MODERN_FLAGS = ['-std=c11', '-O2', '-frounding-math', '-fno-fast-math',
                '-ffp-contract=off', '-fno-lto', '-fno-builtin-atan2f', '-fno-builtin-fma']
PROFILES = ('Apple2007AngleRn', 'Sun239AngleRn', 'Glibc241AngleRn')
LOADER_NAMES = ('LD_PRELOAD', 'LD_LIBRARY_PATH', 'LD_AUDIT', 'LD_BIND_NOW',
                'GLIBC_TUNABLES', 'LD_HWCAP_MASK', 'LD_ASSUME_KERNEL')


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False)


def strict_json(text):
    def unique(pairs):
        out = {}
        for key, value in pairs:
            if key in out: raise ValueError('Duplicate JSON field: ' + key)
            out[key] = value
        return out
    def nonfinite(value): raise ValueError('Nonfinite JSON: ' + value)
    return json.loads(text, object_pairs_hook=unique, parse_constant=nonfinite)


def word(value):
    if type(value) is not str or not re.fullmatch('[0-9a-f]{8}', value):
        raise ValueError('Expected canonical raw binary32 word')
    return int(value, 16)


def number(value):
    return struct.unpack('>f', struct.pack('>I', word(value)))[0]


def load_manifest(path=MANIFEST):
    if sha256(path) != MANIFEST_SHA256: raise ValueError('Frozen angle manifest drift')
    manifest = strict_json(Path(path).read_text())
    if manifest['schema'] != 1 or manifest['contract'] != 'native-angle-qualification-v1':
        raise ValueError('Unsupported angle manifest version')
    if tuple(manifest['profiles']) != PROFILES: raise ValueError('Angle profile manifest drift')
    ids = set()
    for row in manifest['scalar_controls']:
        if set(row) != {'id', 'y', 'x', 'expected', 'derivation'} or row['id'] in ids:
            raise ValueError('Malformed or duplicate scalar control')
        ids.add(row['id']); word(row['y']); word(row['x'])
        if set(row['expected']) != set(PROFILES): raise ValueError('Incomplete frozen expectation')
        for value in row['expected'].values(): word(value)
    for row in manifest['wrapper_controls']:
        if set(row) != {'id', 'api', 'args', 'intermediates', 'atan2_inputs', 'expected', 'derivation'} or row['id'] in ids:
            raise ValueError('Malformed or duplicate wrapper control')
        ids.add(row['id'])
        if row['api'] not in ('Vector2Angle', 'Vector2LineAngle', 'Vector3Angle'):
            raise ValueError('Unknown wrapper API')
        for value in row['args'] + row['atan2_inputs']: word(value)
        for entry in row['intermediates']:
            if len(entry) != 2 or type(entry[0]) is not str: raise ValueError('Malformed intermediate')
            word(entry[1])
        if set(row['expected']) != set(PROFILES): raise ValueError('Incomplete wrapper expectation')
        for value in row['expected'].values(): word(value)
    if not manifest['scalar_controls'] or not manifest['wrapper_controls']:
        raise ValueError('Empty qualification controls')
    return manifest


def control_document(manifest):
    kinds = {'Vector2Angle': ('vector_value', 'angle'),
             'Vector2LineAngle': ('vector_value', 'line_angle'),
             'Vector3Angle': ('vector3_value', 'angle')}
    cases = []
    for row in manifest['wrapper_controls']:
        kind, function = kinds[row['api']]
        cases.append(dict(id=row['id'], width=1, height=1, background=[0, 0, 0, 0],
                          operations=[dict(op=kind, function=function, x=0, y=0,
                                           args=[number(v) for v in row['args']])]))
    return dict(schema=1, cases=cases)


def strict_scalar(output, controls):
    lines = output.splitlines()
    if len(lines) != len(controls): raise ValueError('Wrong scalar observation count')
    rows = []
    for line, control in zip(lines, controls):
        row = strict_json(line)
        if type(row) is not dict or set(row) != {'id', 'y', 'x', 'result'}:
            raise ValueError('Malformed scalar observation fields')
        if any(row[key] != control[key] or type(row[key]) is not str for key in ('id', 'y', 'x')):
            raise ValueError('Wrong scalar identity/order/input words')
        word(row['result']); rows.append(row)
    return rows


def strict_wrappers(output, cases, parse_output):
    lines = output.splitlines()
    if len(lines) != len(cases): raise ValueError('Wrong wrapper observation count')
    rows = []
    for line, case in zip(lines, cases):
        row = strict_json(line)
        if type(row) is not dict or set(row) != {'id', 'width', 'height', 'pixels'}:
            raise ValueError('Malformed wrapper observation fields')
        if row['id'] != case['id'] or type(row['id']) is not str:
            raise ValueError('Wrong wrapper identity/order')
        if type(row['width']) is not int or type(row['height']) is not int or (row['width'], row['height']) != (1, 1):
            raise ValueError('Wrong wrapper dimensions/types')
        if type(row['pixels']) is not list or len(row['pixels']) != 1 or type(row['pixels'][0]) is not int or not 0 <= row['pixels'][0] <= 0xffffffff:
            raise ValueError('Wrong wrapper result shape/type')
        rows.append(row)
    if canonical_json(parse_output(output, cases)) != canonical_json(rows):
        raise ValueError('Canonical parser changed native observations')
    return rows


def match_profiles(manifest, scalar, wrappers, profiles=PROFILES):
    comparisons, matches = {}, []
    for profile in profiles:
        differences = []
        for context, controls, rows in (('runtime-pointer', manifest['scalar_controls'], scalar),
                                        ('canonical-wrapper', manifest['wrapper_controls'], wrappers)):
            if len(controls) != len(rows): raise ValueError('Incomplete matching observations')
            for control, row in zip(controls, rows):
                if row['id'] != control['id']: raise ValueError('Wrong matching observation order')
                actual = row['result'] if context == 'runtime-pointer' else f"{row['pixels'][0]:08x}"
                expected = control['expected'][profile]
                if actual != expected:
                    differences.append(dict(context=context, id=row['id'], expected=expected, observed=actual))
        comparisons[profile] = dict(mismatch_count=len(differences), differences=differences)
        if not differences: matches.append(profile)
    return matches, comparisons


def validate_context(meta, phase):
    fields = {'kind', 'profile', 'architecture', 'endian', 'binary32', 'binary64', 'eval_method',
              'rounding', 'nearest', 'control', 'x87_control', 'libc_version', 'symbol', 'symbol_path',
              'library_path', 'library_realpath', 'library_build_id', 'library_stat', 'loader_overrides'}
    if type(meta) is not dict or set(meta) != fields: raise ValueError('Malformed process context')
    expected = dict(kind=phase+'-context', profile='linux-glibc-elf-runtime-image-v1', endian='little',
                    binary32=True, binary64=True, eval_method=0, rounding=0, nearest=True,
                    symbol='atan2f', symbol_path='volatile-pointer-equals-dlsym-default')
    for key, value in expected.items():
        if type(meta[key]) is not type(value) or meta[key] != value:
            raise ValueError('Unsupported process context: ' + key)
    if type(meta['control']) is not int or not 0 <= meta['control'] < 2**64 or type(meta['x87_control']) is not int:
        raise ValueError('Malformed floating-point control words')
    if meta['architecture'] == 'x86_64':
        if meta['control'] & ((1<<15)|(1<<6)|(3<<13)) or not 0 <= meta['x87_control'] <= 65535 or meta['x87_control'] & (3<<10):
            raise ValueError('Unsupported MXCSR/x87 rounding, FTZ or DAZ')
    elif meta['architecture'] == 'aarch64':
        if meta['control'] & ((1<<24)|(1<<19)|(3<<22)|3) or meta['x87_control'] != 0:
            raise ValueError('Unsupported FPCR context')
    else: raise ValueError('Unsupported architecture metadata profile')
    if type(meta['libc_version']) is not str or not re.fullmatch(r'\d+\.\d+(?:\.\d+)?', meta['libc_version']):
        raise ValueError('Unknown glibc runtime version')
    for key in ('library_path', 'library_realpath'):
        if type(meta[key]) is not str or not Path(meta[key]).is_absolute(): raise ValueError('Missing loaded library path')
    if type(meta['library_build_id']) is not str or not re.fullmatch('[0-9a-f]{8,128}', meta['library_build_id']):
        raise ValueError('Missing loaded ELF build ID')
    if type(meta['library_stat']) is not list or len(meta['library_stat']) != 5 or any(type(x) is not int or x < 0 for x in meta['library_stat']):
        raise ValueError('Missing loaded library stat')
    if type(meta['loader_overrides']) is not dict or set(meta['loader_overrides']) != set(LOADER_NAMES):
        raise ValueError('Missing loader override observations')
    if any(v is not None for v in meta['loader_overrides'].values()):
        raise ValueError('Loader overrides are outside the supported metadata profile')
    return meta


def parse_context(stderr):
    lines = stderr.splitlines()
    if len(lines) != 2: raise ValueError('Expected one initial and one final process context')
    initial, final = (validate_context(strict_json(line), phase) for line, phase in zip(lines, ('initial', 'final')))
    # Exception/status flags can change, but never rounding/flush controls or identity.
    for key in initial.keys() - {'kind', 'control'}:
        if initial[key] != final[key]: raise ValueError('Process context changed: ' + key)
    mask = ~63 if initial['architecture'] == 'x86_64' else -1
    if initial['control'] & mask != final['control'] & mask:
        raise ValueError('Floating-point process controls changed')
    return dict(initial=initial, final=final)


def scalar_source(controls, pinned=False):
    target = 'aq_pinned_atan2f' if pinned else 'atan2f'
    text = '#include <math.h>\n#include <stdint.h>\n#include <stdio.h>\n#include <string.h>\n'
    if pinned: text += 'extern float aq_pinned_atan2f(float,float);\n'
    text += 'static float (*volatile call)(float,float)='+target+';\n'
    text += 'static float from(uint32_t u){float f;memcpy(&f,&u,4);return f;}\n'
    text += 'static uint32_t bits(float f){uint32_t u;memcpy(&u,&f,4);return u;}\n'
    text += 'int main(void){\n'
    for row in controls:
        text += 'printf("{\\"id\\":\\"%s\\",\\"y\\":\\"%08x\\",\\"x\\":\\"%08x\\",\\"result\\":\\"%08x\\"}\\n",'
        text += f'"{row["id"]}",0x{row["y"]}u,0x{row["x"]}u,bits(call(from(0x{row["y"]}u),from(0x{row["x"]}u))));\n'
    return text + 'return 0;}\n'


def mirror_source(controls):
    """Separate intermediate diagnostic; never modifies canonical C or headers."""
    out = '#include <math.h>\n#include <stdint.h>\n#include <stdio.h>\n#include <string.h>\n#pragma STDC FP_CONTRACT OFF\n'
    out += 'static float from(uint32_t u){float f;memcpy(&f,&u,4);return f;}\nstatic unsigned bits(float f){unsigned u;memcpy(&u,&f,4);return u;}\nint main(void){\n'
    for row in controls:
        out += '{\n'
        for i, raw in enumerate(row['args']): out += f'float a{i}=from(0x{raw}u);\n'
        if row['api'] == 'Vector2Angle':
            expressions = [('dot-p0','a0*a2'),('dot-p1','a1*a3'),('dot','v0+v1'),
                           ('det-p0','a0*a3'),('det-p1','a1*a2'),('det','v3-v4')]
        elif row['api'] == 'Vector2LineAngle':
            expressions = [('dy','a3-a1'),('dx','a2-a0')]
        else:
            expressions = [('cross-x-p0','a1*a5'),('cross-x-p1','a2*a4'),('cross-x','v0-v1'),
                           ('cross-y-p0','a2*a3'),('cross-y-p1','a0*a5'),('cross-y','v3-v4'),
                           ('cross-z-p0','a0*a4'),('cross-z-p1','a1*a3'),('cross-z','v6-v7'),
                           ('square-x','v2*v2'),('square-y','v5*v5'),('square-z','v8*v8'),
                           ('square-xy','v9+v10'),('square-xyz','v12+v11'),('length','sqrtf(v13)'),
                           ('dot-p0','a0*a3'),('dot-p1','a1*a4'),('dot-xy','v15+v16'),
                           ('dot-p2','a2*a5'),('dot','v17+v18')]
        if [x[0] for x in expressions] != [x[0] for x in row['intermediates']]:
            raise ValueError('Frozen intermediate order differs from source expression order')
        for i, (_, expression) in enumerate(expressions): out += f'float v{i}={expression};\n'
        out += f'printf("{{\\"id\\":\\"{row["id"]}\\",\\"words\\":[" );\n'
        for i in range(len(expressions)):
            out += f'printf("{"," if i else ""}\\"%08x\\"",bits(v{i}));\n'
        out += 'puts("]}");}\n'
    return out + 'return 0;}\n'


def runtime_wrapper_source(controls):
    """Runtime inputs through original pinned static-inline raymath functions."""
    out = '#include <stdint.h>\n#include <stdio.h>\n#include <string.h>\n#pragma STDC FP_CONTRACT OFF\n#define RAYMATH_STATIC_INLINE\n#include "raymath.h"\n'
    out += 'static float from(uint32_t u){float f;memcpy(&f,&u,4);return f;}\nstatic unsigned bits(float f){unsigned u;memcpy(&u,&f,4);return u;}\nint main(void){\n'
    for row in controls:
        out += '{\n'
        for i, raw in enumerate(row['args']): out += f'volatile float a{i}=from(0x{raw}u);\n'
        size = 3 if row['api'] == 'Vector3Angle' else 2
        left = ','.join('a'+str(i) for i in range(size))
        right = ','.join('a'+str(i) for i in range(size,2*size))
        call = f'{row["api"]}((Vector{size}){{{left}}},(Vector{size}){{{right}}})'
        out += 'printf("{\\"id\\":\\"%s\\",\\"width\\":1,\\"height\\":1,\\"pixels\\":[%u]}\\n",'
        out += f'"{row["id"]}",bits({call}));}}\n'
    return out + 'return 0;}\n'


def strict_mirror(text, controls):
    lines = text.splitlines()
    if len(lines) != len(controls): raise ValueError('Wrong intermediate mirror count')
    rows = []
    for line, control in zip(lines, controls):
        row = strict_json(line)
        expected = dict(id=control['id'], words=[value for _, value in control['intermediates']])
        if type(row) is not dict or row != expected or canonical_json(row) != canonical_json(expected):
            raise ValueError('Frozen source-order intermediate mismatch: '+control['id'])
        rows.append(row)
    return rows


def qualify(raylib_source, library, build_dir, *, c_source, cases_from, parse_output,
            requested_profile=None, runner=subprocess.run, timeout=120):
    work = Path(build_dir).resolve() / 'angle-reference'; work.mkdir(parents=True, exist_ok=True)
    report_path = work / 'results.json'
    report = dict(schema=1, contract='native-angle-qualification-v1', run_id=uuid.uuid4().hex,
                  started_at=datetime.now(timezone.utc).isoformat(), phase='setup', qualified=False,
                  selected_profile=None, parity_established=False, candidate_executed=False,
                  requested_profile=requested_profile, commands=[], contexts={}, observations={},
                  error=None, matching_profiles=[])
    def persist():
        temporary = report_path.with_suffix('.tmp')
        temporary.write_text(json.dumps(report, indent=2, allow_nan=False)+'\n'); temporary.replace(report_path)
    persist()  # Invalidate stale success before ANY read/build/setup dependency.
    snapshots = {}
    def track(path):
        path = Path(path).resolve(); digest = sha256(path)
        if str(path) in snapshots and snapshots[str(path)] != digest: raise ValueError('Tracked artifact changed: '+str(path))
        snapshots[str(path)] = digest
        return digest
    def execute(command, label):
        command = [str(v) for v in command]
        record = dict(argv=command, phase=label, completed=False, started_at=datetime.now(timezone.utc).isoformat())
        report['commands'].append(record); report['phase'] = label; persist()
        stdout = stderr = ''
        try:
            result = runner(command, capture_output=True, text=True, timeout=timeout)
            stdout, stderr = result.stdout, result.stderr
            if type(stdout) is not str or type(stderr) is not str: raise ValueError('Command output must be text')
            record['returncode'] = result.returncode
            if result.returncode != 0: raise RuntimeError(f'{label} exited {result.returncode}: {stderr.strip()}')
            record['completed'] = True
            return stdout, stderr
        except BaseException as error:
            def decode(value): return value.decode(errors='replace') if isinstance(value, bytes) else (value or '')
            stdout = decode(getattr(error, 'stdout', stdout)); stderr = decode(getattr(error, 'stderr', stderr))
            record['error'] = dict(type=type(error).__name__, message=str(error))
            raise
        finally:
            for suffix, content in (('stdout', stdout), ('stderr', stderr)):
                file = work / (label+'.'+suffix); file.write_text(content); track(file)
            record['finished_at'] = datetime.now(timezone.utc).isoformat(); persist()
    def compile_source(command, binary, label):
        binary.unlink(missing_ok=True)
        execute(command, label)
        if not binary.is_file() or binary.stat().st_size == 0:
            raise ValueError(label+': successful compiler did not produce a fresh nonempty artifact')
        track(binary)
    def enrich_context(context, label):
        meta = context['initial']; path = Path(meta['library_realpath'])
        if Path(meta['library_path']).resolve() != path or path.resolve() != path: raise ValueError('Loaded library realpath mismatch')
        st = path.stat()
        if [st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns//10**9, st.st_mtime_ns%10**9] != meta['library_stat']:
            raise ValueError('Loaded library identity changed after process observation')
        digest = track(path)
        notes, _ = execute(['readelf', '-n', path], label+'-library-notes')
        found = re.findall(r'Build ID:\s*([0-9a-f]+)', notes)
        if found != [meta['library_build_id']]: raise ValueError('Loaded/file ELF build ID mismatch')
        context['library'] = dict(path=meta['library_path'], realpath=str(path), sha256=digest,
                                  build_id=meta['library_build_id'], runtime_glibc=meta['libc_version'])
        return context
    def observe(binary, label):
        stdout, stderr = execute([binary], label)
        context = enrich_context(parse_context(stderr), label)
        report['contexts'][label] = context; persist()
        return stdout
    try:
        manifest = load_manifest(); track(MANIFEST)
        if __package__:
            from .angle_manifest_audit import audit
        else:
            from angle_manifest_audit import audit
        report['exact_manifest_audit'] = audit(manifest)
        track(ROOT/'tools/angle_manifest_audit.py')
        report['manifest_sha256'] = MANIFEST_SHA256
        report['profiles'] = manifest['profiles']
        if requested_profile is not None and requested_profile not in PROFILES:
            raise ValueError('Unknown explicitly requested angle profile')
        if platform.system() != 'Linux' or platform.machine().lower() not in ('x86_64', 'aarch64'):
            raise ValueError('Unsupported platform: only Linux glibc ELF runtime-image metadata is implemented')
        if any(os.environ.get(name) is not None for name in LOADER_NAMES):
            raise ValueError('Loader overrides are outside the supported profile')
        raylib_source, library = Path(raylib_source).resolve(), Path(library).resolve()
        for relative, digest in manifest['source_sha256'].items():
            if track(ROOT/relative) != digest: raise ValueError('Frozen source/toolchain drift: '+relative)
        track(__file__); track(REFERENCE/'angle_qualification_context.c')
        for callback in (c_source, cases_from, parse_output):
            file = inspect.getsourcefile(callback)
            if file is None or Path(file).resolve() != ROOT/'tools/conformance.py':
                raise ValueError('Callbacks must be unchanged canonical conformance functions')
            track(file)
        raylib = dict(source=str(raylib_source), library=str(library), library_sha256=track(library), headers={})
        for name, digest in manifest['raylib']['headers'].items():
            actual = track(raylib_source/'src'/name)
            if actual != digest: raise ValueError('Pinned raylib header drift: '+name)
            raylib['headers'][name] = actual
        revision, _ = execute(['git', '-C', raylib_source, 'rev-parse', 'HEAD'], 'raylib-revision')
        status, _ = execute(['git', '-C', raylib_source, 'status', '--porcelain', '--untracked-files=no', '--', 'src'], 'raylib-status')
        if revision.strip() != manifest['raylib']['revision'] or status.strip():
            raise ValueError('Pinned raylib source revision/status mismatch')
        raylib.update(revision=revision.strip(), source_status='clean tracked src')
        report['raylib'] = raylib
        compiler = shutil.which('clang')
        if not compiler: raise ValueError('Canonical clang compiler not found')
        compiler_path = Path(compiler).absolute(); compiler_real = compiler_path.resolve()
        version, _ = execute([compiler_path, '--version'], 'compiler-version')
        target, _ = execute([compiler_path, '-dumpmachine'], 'compiler-target')
        if not version.strip() or not target.strip(): raise ValueError('Missing compiler identity/target')
        report['compiler'] = dict(path=str(compiler_path), realpath=str(compiler_real), sha256=track(compiler_real),
                                  version=version.strip(), target=target.strip(), canonical_flags=CANONICAL_FLAGS,
                                  pinned_source_flags=MODERN_FLAGS)
        # Package metadata has an explicit policy: runtime images need not belong
        # to a package database. Unknown failures do not become guessed versions.
        package_path = shutil.which('dpkg-query')
        if not package_path: raise ValueError('Unsupported package metadata backend: dpkg-query required')
        package_output, _ = execute([package_path, '-W', '-f=${binary:Package} ${Version} ${Architecture}\\n'], 'package-inventory')
        package_lines = [line for line in package_output.splitlines() if re.match(r'^libc6(?::\S+)?\s', line)]
        if len(package_lines) > 1: raise ValueError('Ambiguous libc6 package metadata')
        report['package'] = dict(profile='runtime-image-not-package-membership-v1',
                                 status='package-record-present' if package_lines else 'not-in-successful-dpkg-inventory',
                                 package_record=package_lines[0] if package_lines else None,
                                 required_runtime_version='observed separately in every native process')
        document = control_document(manifest); cases = cases_from(copy.deepcopy(document))
        if canonical_json(cases) != canonical_json(document['cases']): raise ValueError('Canonical validator changed frozen controls')
        doc_path=work/'controls.json'; doc_path.write_text(canonical_json(document)+'\n'); track(doc_path)
        canonical = work/'canonical.c'; canonical.write_text(c_source(copy.deepcopy(cases))); track(canonical)
        report['canonical_source_sha256'] = sha256(canonical)
        context_object = work/'context.o'
        compile_source([compiler_path, *CANONICAL_FLAGS, '-c', REFERENCE/'angle_qualification_context.c', '-o', context_object], context_object, 'context-compile')
        binaries = {}
        for name, source_text in (('pointer', scalar_source(manifest['scalar_controls'])),
                                   ('intermediate-mirror', mirror_source(manifest['wrapper_controls'])),
                                   ('runtime-wrapper', runtime_wrapper_source(manifest['wrapper_controls']))):
            source = work/(name+'.c'); source.write_text(source_text); track(source)
            binary = work/name
            compile_source([compiler_path, *CANONICAL_FLAGS, '-I'+str(raylib_source/'src'), source, context_object, '-lm', '-ldl', '-o', binary], binary, name+'-compile')
            binaries[name] = binary
        binary = work/'canonical'
        compile_source([compiler_path, *CANONICAL_FLAGS, '-I'+str(raylib_source/'src'), canonical,
                        library, context_object, '-lm', '-ldl', '-o', binary], binary, 'canonical-compile')
        binaries['canonical'] = binary
        include = work/'include'; include.mkdir(exist_ok=True)
        for name, content in (('libm-alias-finite.h', '#define libm_alias_finite(a,b)\n'),
                              ('math_config.h', '#include "modern_atan2f_shim.h"\n')):
            file=include/name; file.write_text(content); track(file)
        pinned_source=work/'pinned.c'; pinned_source.write_text(scalar_source(manifest['scalar_controls'], True)); track(pinned_source)
        pinned_binary=work/'pinned'
        compile_source([compiler_path, *MODERN_FLAGS, '-I'+str(REFERENCE), '-I'+str(include),
                        '-D__ieee754_atan2f=aq_pinned_atan2f', REFERENCE/'modern_atan2f_glibc241.c',
                        pinned_source, context_object, '-lm', '-ldl', '-o', pinned_binary], pinned_binary, 'pinned-compile')
        pinned = strict_scalar(observe(pinned_binary, 'pinned-run'), manifest['scalar_controls'])
        if any(row['result'] != control['expected']['Glibc241AngleRn'] for row, control in zip(pinned, manifest['scalar_controls'])):
            raise ValueError('Independently compiled pinned modern source contradicts frozen expectation')
        report['observations']['pinned-source'] = pinned
        report['pinned_source_role'] = 'verifies intended modern contract only; never identifies installed libm'
        scalar = strict_scalar(observe(binaries['pointer'], 'pointer-run'), manifest['scalar_controls'])
        report['observations']['runtime-pointer'] = scalar
        wrappers = strict_wrappers(observe(binaries['canonical'], 'canonical-run'), cases, parse_output)
        report['observations']['canonical-wrapper'] = wrappers
        runtime_wrappers = strict_wrappers(observe(binaries['runtime-wrapper'], 'runtime-wrapper-run'), cases, parse_output)
        report['observations']['runtime-wrapper'] = runtime_wrappers
        if runtime_wrappers != wrappers: raise ValueError('Mixed canonical/runtime raymath wrapper results')
        mirror = strict_mirror(observe(binaries['intermediate-mirror'], 'mirror-run'), manifest['wrapper_controls'])
        report['observations']['source-order-intermediate-mirror'] = mirror
        report['intermediate_scope'] = 'separate source-order mirror, not instrumentation of canonical optimizer temporaries'
        stable_contexts = []
        for context in report['contexts'].values():
            stable = copy.deepcopy(context['initial']); stable.pop('kind')
            if stable['architecture'] == 'x86_64': stable['control'] &= ~63
            stable_contexts.append(stable)
        if any(value != stable_contexts[0] for value in stable_contexts[1:]):
            raise ValueError('Mixed process floating-point/loader contexts')
        libraries = [context['library'] for context in report['contexts'].values()]
        if any(library != libraries[0] for library in libraries[1:]): raise ValueError('Mixed loaded native library identities')
        matches, comparisons = match_profiles(manifest, scalar, wrappers)
        report.update(matching_profiles=matches, comparisons=comparisons)
        if len(matches) != 1: raise ValueError('Unsupported, mixed or ambiguous native angle signature; exactly one common contract required')
        if requested_profile is not None and matches != [requested_profile]:
            raise ValueError('Explicit requested profile does not match qualified native contract')
        # Identity is checked again at acceptance, not merely recorded once.
        if compiler_path.resolve() != compiler_real: raise ValueError('Compiler resolution drift')
        for path, digest in snapshots.items():
            if sha256(path) != digest: raise ValueError('Source/toolchain/artifact drift: '+path)
        final_revision, _ = execute(['git', '-C', raylib_source, 'rev-parse', 'HEAD'], 'final-raylib-revision')
        final_status, _ = execute(['git', '-C', raylib_source, 'status', '--porcelain', '--untracked-files=no', '--', 'src'], 'final-raylib-status')
        if final_revision != revision or final_status != status: raise ValueError('Raylib source status drift')
        if compiler_path.resolve() != compiler_real: raise ValueError('Compiler resolution drift at acceptance')
        for path, digest in snapshots.items():
            if sha256(path) != digest: raise ValueError('Source/toolchain/artifact drift at acceptance: '+path)
        report.update(qualified=True, selected_profile=matches[0], phase='qualified',
                      completed_at=datetime.now(timezone.utc).isoformat(), artifacts=snapshots)
        persist(); return report
    except BaseException as error:
        report.update(qualified=False, selected_profile=None, failed_at=datetime.now(timezone.utc).isoformat(),
                      error=dict(type=type(error).__name__, message=str(error)), artifacts=snapshots)
        persist(); raise


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument('--raylib-source', type=Path, required=True)
    parser.add_argument('--library', type=Path, required=True)
    parser.add_argument('--build-dir', type=Path, default=ROOT/'.build')
    parser.add_argument('--profile')
    parser.add_argument('--timeout', type=int, default=120)
    # One parser owns option semantics. Its explicitly supplied namespace also
    # retains the last destination action actually executed before error/help.
    # Parsing uses only Path/int conversions; no source is read or built here.
    args = argparse.Namespace(build_dir=ROOT/'.build')

    def admit(error=None):
        path = args.build_dir.resolve()/'angle-reference/results.json'
        path.parent.mkdir(parents=True,exist_ok=True)
        report = dict(schema=1,run_id=uuid.uuid4().hex,phase='argument-validation',qualified=False,
                      selected_profile=None,parity_established=False,candidate_executed=False,
                      started_at=datetime.now(timezone.utc).isoformat(),error=None)
        if error is not None:
            if isinstance(error,SystemExit) and error.code == 0:
                report.update(phase='help',completed_at=datetime.now(timezone.utc).isoformat())
            else:
                report.update(error=dict(type=type(error).__name__,message=str(error)),
                              failed_at=datetime.now(timezone.utc).isoformat())
        path.write_text(json.dumps(report,indent=2)+'\n')
        return path,report

    try:
        parser.parse_args(argv,namespace=args)
        if args.timeout <= 0: parser.error('--timeout must be positive')
    except BaseException as error:
        admit(error)
        raise
    path,admission = admit()
    try:
        from conformance import c_source, cases_from, parse_output
        report = qualify(args.raylib_source, args.library, args.build_dir, c_source=c_source,
                         cases_from=cases_from, parse_output=parse_output, requested_profile=args.profile, timeout=args.timeout)
    except BaseException as error:
        # qualify() maintains its richer report once admitted. Do not overwrite it.
        current = strict_json(path.read_text())
        if current.get('run_id') == admission['run_id']:
            admission.update(error=dict(type=type(error).__name__,message=str(error)),
                             failed_at=datetime.now(timezone.utc).isoformat())
            path.write_text(json.dumps(admission,indent=2)+'\n')
        raise
    print(json.dumps({key:report[key] for key in ('qualified','selected_profile','parity_established','candidate_executed')}))


if __name__ == '__main__': main()
