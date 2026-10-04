#!/usr/bin/env python3
"""Independently replay a PIC memory evidence directory, read-only.

Every native and CPU/JS byte is parsed and compared again. This does not call
probe comparison, protocol parsing, action construction, partition validation,
or a Python PIC pixel decoder. Probe fixture/source generation is reused only
to bind the admitted corpus and the exact executable source to the receipts.
Synthetic unit-test records establish audit mechanics, never native parity.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import shlex

LANES = ('cpu-1', 'cpu-2', 'javascript')
RAW = {'raw', 'factory', 'owner', 'raw-roundtrip', 'alias-PIC'}
BASE_ROLES = ('raw', 'bridge', 'surface', 'factory', 'owner', 'raw-roundtrip')
EXTRA_ROLES = ('dispatch-pic', 'dispatch-PIC', 'uncontracted', 'fused')
MAX_ACTIONS = 32
MAX_SOURCE_BYTES = 196608
HEX = re.compile(r'[0-9a-f]{64}\Z')
REPORT_KEYS = set('passed oracle_source_ranges profile reconstruction run_directory toolchain base_revision host tool_paths tool_realpaths sources reference_environment inputs_sha256 legacy_cases legacy_pixels legacy_controls native_content_admission cases pixels typed_controls native_rejections batch_size source_byte_limit partition_strategy lanes candidate_mipmaps unrun native_build bun_version clang_version qualification native_partition_plan native_action_inventory native_batches reference_sha256 native_observations native_raw_bytes native_normalized_bytes native_all_observed_bytes observations_per_lane compared_bytes_per_lane raw_compared_bytes_per_lane normalized_compared_bytes_per_lane partition_plan action_inventory planned_batches elapsed_seconds sealed_artifacts'.split())


class ArtifactSeals(dict):
    def __init__(self, values):
        super().__init__(values)
        self.required = set()
        self.timeout_seconds = None


def require(condition, message):
    if not condition:
        raise ValueError('PIC audit: ' + message)


def strict_json(text):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'duplicate JSON key')
            result[key] = value
        return result
    def forbidden(value):
        raise ValueError('PIC audit: nonfinite JSON ' + value)
    def finite(value):
        if type(value) is float:
            require(math.isfinite(value), 'nonfinite JSON number')
        elif type(value) is dict:
            for item in value.values(): finite(item)
        elif type(value) is list:
            for item in value: finite(item)
    result = json.loads(text, object_pairs_hook=unique, parse_constant=forbidden)
    finite(result)
    return result


def equal(actual, expected, label):
    # JSON equality must not collapse true/1 or 1.0/1 at any nesting depth.
    require(type(actual) is type(expected), label + ' type differs')
    if type(expected) is dict:
        require(set(actual) == set(expected), label + ' keys differ')
        for key, value in expected.items(): equal(actual[key], value, label + '.' + str(key))
    elif type(expected) is list:
        require(len(actual) == len(expected), label + ' count differs')
        for index, (a, b) in enumerate(zip(actual, expected)): equal(a, b, label + '[' + str(index) + ']')
    else:
        require(actual == expected, label + ' value differs')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()


def path_at(value, root):
    require(type(value) is str and value != '', 'invalid artifact path')
    path = Path(value)
    return (path if path.is_absolute() else root / path).resolve()


def sealed_file(path, seals):
    key = str(Path(path).resolve())
    require(key in seals, 'unsealed artifact: ' + key)
    require(Path(key).is_file(), 'missing artifact: ' + key)
    require(type(seals[key]) is str and HEX.fullmatch(seals[key]) is not None, 'invalid artifact digest')
    data = Path(key).read_bytes()
    if isinstance(seals, ArtifactSeals): seals.required.add(key)
    require(sha(data) == seals[key], 'stale artifact: ' + key)
    return data


def metadata(case, role):
    if role.endswith('-error'):
        require(role in ('formatted-error', 'surface-error'), 'unknown error role')
        return dict(id=case['id'], role=role, error=case['error'])
    require(role in RAW | set(BASE_ROLES) | set(EXTRA_ROLES) | {'normalized'}, 'unknown image role')
    return dict(id=case['id'], role=role, width=case['width'], height=case['height'], mipmaps=1,
                format={3:4, 4:7}[case['channels']] if role in RAW else 7)


def parse_output(text, actions):
    """Exact independently framed rows; no fallback for missing or short chunks."""
    require(type(text) is str and text != '' and type(actions) is list and actions, 'empty observation stream')
    lines = text.splitlines()
    require(all(line.strip() for line in lines), 'blank observation line')
    values = [strict_json(line) for line in lines]
    cursor = 0
    result = []
    for action in actions:
        case, role = action['case'], action['role']
        expected = metadata(case, role)
        require(cursor < len(values), 'missing observation')
        equal(values[cursor], expected, 'observation metadata')
        cursor += 1
        if role.endswith('-error'):
            result.append(expected)
            continue
        length = case['width'] * case['height'] * (case['channels'] if role in RAW else 4)
        payload = []
        while len(payload) < length:
            require(cursor < len(values), 'missing payload chunk')
            chunk = values[cursor]
            cursor += 1
            require(type(chunk) is list and len(chunk) == min(256, length-len(payload)), 'incorrect full-byte chunk framing')
            require(all(type(byte) is int and 0 <= byte <= 255 for byte in chunk), 'nonbyte observation value')
            payload.extend(chunk)
        require(cursor < len(values), 'missing image terminal')
        equal(values[cursor], 'end', 'image terminal')
        cursor += 1
        result.append(dict(expected, bytes=payload))
    require(cursor == len(values), 'extra/reordered observation records')
    return result


def native_actions(cases):
    return [dict(case=c, role=role) for c in cases for role in
            ('raw', 'normalized', *(('alias-PIC',) if c['extended'] else ()))]


def actions_from_native(cases, controls, rows):
    """The sole pixel expectations are the actual pre/post-normal native bytes."""
    result = []
    references = {}
    cursor = 0
    for case in cases:
        require(cursor+2 <= len(rows), 'missing native raw/normalized pair')
        raw, normal = rows[cursor:cursor+2]
        equal({k:v for k,v in raw.items() if k != 'bytes'}, metadata(case, 'raw'), 'native raw')
        equal({k:v for k,v in normal.items() if k != 'bytes'}, metadata(case, 'normalized'), 'native normalized')
        cursor += 2
        if case['extended']:
            require(cursor < len(rows), 'missing native alias')
            equal(rows[cursor], dict(raw, role='alias-PIC'), 'native alias')
            cursor += 1
        references[case['id']] = (raw, normal)
        for role in (*BASE_ROLES, *(EXTRA_ROLES if case['extended'] else ())):
            result.append(dict(case=case, role=role, expected=dict(raw if role in RAW else normal, role=role),
                               normalized=normal['bytes']))
    require(cursor == len(rows), 'unexpected native records')
    for case in controls:
        for role in ('formatted-error', 'surface-error'):
            result.append(dict(case=case, role=role, expected=metadata(case, role)))
    return result, references


def inventory(actions):
    return [dict(id=a['case']['id'], role=a['role']) for a in actions]


def plan(items, generator, native=False):
    """Independent exhaustive ordered greedy boundaries and full identity seals."""
    require(type(items) is list and items, 'empty partition input')
    result = []
    start = 0
    while start < len(items):
        chosen = None
        for count in range(1, min(MAX_ACTIONS, len(items)-start)+1):
            selected = items[start:start+count]
            observations = native_actions(selected) if native else selected
            if len(observations) > MAX_ACTIONS: break
            source = generator(selected).encode('utf-8')
            require(bool(source), 'empty generated source')
            if len(source) > MAX_SOURCE_BYTES:
                require(count != 1, 'oversized source singleton')
                break
            row = dict(start=start, count=count, source_bytes=len(source), source_sha256=sha(source))
            if native:
                row.update(observations=len(observations), cases_sha256=sha(canonical(selected)),
                           compared_bytes=sum(a['case']['width']*a['case']['height']*(a['case']['channels'] if a['role'] in RAW else 4) for a in observations))
            else:
                row.update(actions_sha256=sha(canonical(selected)), compared_bytes=sum(len(a['expected'].get('bytes', [])) for a in selected))
            chosen = row
        require(chosen is not None, 'empty partition')
        result.append(chosen)
        start += chosen['count']
    return result


def validate_native_config(cache, flags):
    required = dict(PLATFORM='Memory', CMAKE_BUILD_TYPE='Release', CUSTOMIZE_BUILD='ON',
                    SUPPORT_FILEFORMAT_PIC='ON', SUPPORT_MODULE_RAUDIO='OFF', BUILD_EXAMPLES='OFF', USE_EXTERNAL_GLFW='OFF')
    observed = {}
    for line in cache.splitlines():
        if not line or line.startswith(('#', '//')): continue
        match = re.fullmatch(r'([^:=]+):[^=]+=(.*)', line)
        require(match is not None, 'malformed CMake cache')
        key, value = match.groups()
        require(key not in observed, 'duplicate CMake cache key')
        observed[key] = value
    for key, value in required.items(): equal(observed.get(key), value, 'native configuration ' + key)
    tokens = shlex.split(flags, comments=True)
    definitions = []
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token in ('-D', '-U'):
            index += 1
            require(index < len(tokens), 'incomplete native macro flag')
            token += tokens[index]
        if token.startswith(('-D', '-U')): definitions.append(token)
        index += 1
    for macro in ('SUPPORT_FILEFORMAT_PIC', 'EXTERNAL_CONFIG_FLAGS', 'PLATFORM_MEMORY'):
        found = [item for item in definitions if item[2:].split('=')[0] == macro]
        require(len(found) == 1 and found[0] in ('-D'+macro, '-D'+macro+'=1'), 'missing/ambiguous native macro ' + macro)
    require(not any(item[2:].split('=')[0].startswith('PLATFORM_') and item[2:].split('=')[0] != 'PLATFORM_MEMORY' for item in definitions), 'conflicting native platform')
    return required


def verify_environment(value):
    from reference_environment import LOADER_NAMES
    require(type(value) is dict and set(value) == {'schema','policy','scope','parent_loader','effective_child_loader'}, 'reference environment schema')
    equal(value['schema'], 1, 'reference environment version')
    equal(value['policy'], 'clean-loader', 'reference environment policy')
    equal(value['scope'], 'native-reference-and-compiler-children-only', 'reference environment scope')
    equal(value['effective_child_loader'], dict.fromkeys(LOADER_NAMES), 'effective loader environment')
    require(type(value['parent_loader']) is dict and set(value['parent_loader']) == set(LOADER_NAMES), 'parent loader schema')
    require(all(item is None or type(item) is str for item in value['parent_loader'].values()), 'parent loader value')


def verify_command(work, label, command, seals, environment=None):
    row = strict_json(sealed_file(work/(label+'.command.json'), seals).decode())
    expected_keys = {'command','reference_environment','timeout_seconds','exit_code','process_group_owned',
                     'process_group_id','cleanup_timeout_seconds','process_group_cleanup','leader_reaped',
                     'cleanup_elapsed_seconds','elapsed_seconds','artifacts'}
    require(type(row) is dict and set(row) == expected_keys, 'failed/malformed command receipt: ' + label)
    equal(row['command'], list(map(str, command)), 'command '+label)
    equal(row['reference_environment'], environment, 'command environment '+label)
    equal(row['exit_code'], 0, 'command exit '+label)
    equal(row['process_group_owned'], True, 'owned process group')
    equal(row['leader_reaped'], True, 'reaped process leader')
    equal(row['cleanup_timeout_seconds'], 5, 'cleanup bound')
    require(type(row['process_group_id']) is int and row['process_group_id'] > 0, 'invalid process group')
    require(type(row['timeout_seconds']) is int and row['timeout_seconds'] > 0, 'invalid work timeout')
    if isinstance(seals, ArtifactSeals):
        if seals.timeout_seconds is None: seals.timeout_seconds = row['timeout_seconds']
        equal(row['timeout_seconds'], seals.timeout_seconds, 'consistent command timeout')
    require(row['process_group_cleanup'] in ('already-exited', 'SIGKILL'), 'missing group cleanup')
    for key in ('elapsed_seconds','cleanup_elapsed_seconds'):
        require(type(row[key]) is float and math.isfinite(row[key]) and row[key] >= 0, 'invalid command timing')
    outputs = [Path(str(command[i+1])) for i, word in enumerate(command[:-1]) if str(word) == '-o']
    files = [work/(label+'.stdout'), work/(label+'.stderr'), *outputs]
    equal(row['artifacts'], {str(path): sha(sealed_file(path, seals)) for path in files}, 'command artifacts '+label)
    for path in outputs: require(path.stat().st_size > 0, 'empty compiler artifact')
    return sealed_file(work/(label+'.stdout'), seals).decode()


def git_revision(root):
    """Read Git HEAD/worktree indirection without running any subprocess."""
    git = root/'.git'
    if git.is_file():
        text = git.read_text().strip()
        require(text.startswith('gitdir: '), 'Git worktree indirection')
        git = (root/text[8:]).resolve()
    head = (git/'HEAD').read_text().strip()
    if not head.startswith('ref: '):
        require(re.fullmatch(r'[0-9a-f]{40}', head) is not None, 'Git revision')
        return head
    ref = head[5:]
    require(ref.startswith('refs/') and '..' not in Path(ref).parts, 'Git ref path')
    if (git/ref).is_file(): return (git/ref).read_text().strip()
    if (git/'commondir').is_file(): git = (git/(git/'commondir').read_text().strip()).resolve()
    if (git/ref).is_file(): return (git/ref).read_text().strip()
    if (git/'packed-refs').is_file():
        for line in (git/'packed-refs').read_text().splitlines():
            if line.endswith(' '+ref): return line.split(' ',1)[0]
    raise ValueError('PIC audit: unable to resolve pinned Git revision')


def source_inventory(root, bend, raylib):
    library = [root/'jonlib.bend', root/'jonmath.bend', *sorted((root/'src').rglob('*.bend'))]
    required = ('tools/pic_format_probe.py','tools/pic_format_audit.py','tests/test_pic_format_harness.py',
                'tools/pic_probe.py','tools/bmp_probe.py','tools/byte_probe.py','tools/conformance.py',
                'tools/reference_environment.py','tools/runtime_image.py','toolchain.json','LAWS.bend','PROOF.bend')
    dependencies = [root/item for item in required]
    dependencies += [path for path in raylib.rglob('*') if path.is_file() and
                     (path.suffix in ('.c','.h','.cmake','.in') or path.name in ('CMakeLists.txt','CMakeOptions.txt')) and '.git' not in path.parts]
    dependencies += [path for path in (bend/'bend2').rglob('*') if path.is_file() and path.suffix in ('.ts','.bend','.c','.js','.h')]
    return dict(library={str(path.relative_to(root)):sha(path.read_bytes()) for path in library},
                dependencies={str(path):sha(path.read_bytes()) for path in dependencies})


def audit(report_path):
    import pic_format_probe as probe
    report_path = Path(report_path).resolve()
    report = strict_json(report_path.read_text())
    require(type(report) is dict and set(report) == REPORT_KEYS, 'complete report schema required')
    equal(report.get('passed'), True, 'successful report')
    equal(report.get('profile'), 'native-pic-formatted-memory-v1', 'profile')
    equal(report['reconstruction'], 'fresh implementation; no previous runtime evidence reused', 'evidence origin')
    equal(report['native_content_admission'], 'strict global byte domain; actual PIC signature/header/all descriptors/all row packet controls and samples; malformed controls never native', 'native admission scope')
    equal(report['candidate_mipmaps'], 'implicit single-mip type contract, not stored/measured', 'candidate mipmap scope')
    equal(report['unrun'], ['GPU/Metal','Windows/browser','big-endian','exact-commit hosted CI',
          '4096x4096 allocation/resource limits','representative performance','formatted file IO',
          'generic formatted/float dispatch','native malformed recovery'], 'unrun scope')
    require(type(report['host']) is dict and set(report['host']) == {'system','machine'}, 'host schema')
    require(report['host']['system'] in ('Linux','Darwin') and type(report['host']['machine']) is str and bool(report['host']['machine']), 'host profile')
    require(type(report['elapsed_seconds']) is float and math.isfinite(report['elapsed_seconds']) and report['elapsed_seconds'] >= 0, 'report duration')
    root = probe.ROOT.resolve()
    work = path_at(report.get('run_directory'), root)
    require(work.parent == report_path.parent and re.fullmatch(r'run-[0-9a-f]{32}', work.name), 'run directory identity')
    seals = report.get('sealed_artifacts')
    require(type(seals) is dict and seals, 'artifact inventory absent')
    for path in seals:
        equal(str(Path(path).resolve()), path, 'canonical artifact path')
        sealed_file(path, seals)
    seals = ArtifactSeals(seals)
    inputs = strict_json(sealed_file(work/'inputs.json', seals).decode())
    equal(inputs, dict(cases=probe.fixtures(), controls=probe.controls()), 'complete fixture/control inventory')
    cases, controls = inputs['cases'], inputs['controls']
    equal(report.get('inputs_sha256'), sha((work/'inputs.json').read_bytes()), 'input hash')
    for key, value in dict(legacy_cases=33, legacy_pixels=8867, legacy_controls=24, cases=len(cases),
                           pixels=sum(c['width']*c['height'] for c in cases), typed_controls=len(controls),
                           native_rejections=0, batch_size=MAX_ACTIONS, source_byte_limit=MAX_SOURCE_BYTES,
                           partition_strategy='ordered-greedy-generated-source-v1').items(): equal(report.get(key), value, key)
    lock = strict_json((root/'toolchain.json').read_text())
    equal(report.get('toolchain'), lock, 'pinned toolchain')
    equal(report.get('base_revision'), git_revision(root), 'current library base revision')
    environment = report.get('reference_environment')
    verify_environment(environment)
    tools = report.get('tool_paths')
    require(type(tools) is dict and set(tools) == {'bun','clang','cmake'}, 'tool inventory')
    equal(report.get('tool_realpaths'), {key:str(path_at(value, root)) for key,value in tools.items()}, 'tool realpaths')
    for path in tools.values(): sealed_file(path_at(path, root), seals)
    configure = strict_json(sealed_file(work/'configure.command.json', seals).decode()).get('command')
    require(type(configure) is list and len(configure) > 3 and configure[:2] == ['cmake','-S'], 'configure command')
    raylib = path_at(configure[2], root)
    expected_configure = ['cmake','-S',str(raylib),'-B',str(work/'raylib-build'),'-DPLATFORM=Memory','-DCMAKE_BUILD_TYPE=Release','-DBUILD_EXAMPLES=OFF','-DCUSTOMIZE_BUILD=ON','-DSUPPORT_MODULE_RAUDIO=OFF','-DSUPPORT_RPRAND_GENERATOR=ON','-DSUPPORT_FILEFORMAT_PIC=ON','-DUSE_EXTERNAL_GLFW=OFF']
    verify_command(work, 'configure', expected_configure, seals, environment)
    build = report.get('native_build')
    require(type(build) is dict and set(build) == {'mode','configuration','compiler','compiler_version','artifacts'}, 'native build receipt')
    equal(build['mode'], 'fresh-isolated-build', 'fresh native build')
    cache = work/'raylib-build/CMakeCache.txt'
    flags = work/'raylib-build/raylib/CMakeFiles/raylib.dir/flags.make'
    equal(build['configuration'], validate_native_config(sealed_file(cache,seals).decode(),sealed_file(flags,seals).decode()), 'native build configuration')
    compiler_files = list((work/'raylib-build/CMakeFiles').glob('*/CMakeCCompiler.cmake'))
    require(len(compiler_files) == 1, 'compiler configuration inventory')
    text = sealed_file(compiler_files[0],seals).decode()
    compiler = {}
    for key in ('CMAKE_C_COMPILER','CMAKE_C_COMPILER_ID','CMAKE_C_COMPILER_VERSION'):
        found = re.findall(r'set\('+key+r' "([^"\n]+)"\)', text)
        require(len(found) == 1, 'compiler metadata missing/ambiguous')
        compiler[key] = found[0]
    equal(build['compiler'], compiler, 'archive compiler')
    # CMake records the invoked pathname, which may be a symlink. Commands and
    # artifact keys retain that spelling; sealed_file resolves only the seal.
    compiler_path = Path(compiler['CMAKE_C_COMPILER'])
    require(compiler_path.is_absolute(), 'absolute archive compiler path')
    version = verify_command(work,'archive-compiler-version',[compiler_path,'--version'],seals,environment)
    require(bool(version.strip()), 'empty archive compiler version')
    equal(build['compiler_version'],version,'archive compiler version')
    verify_command(work,'native-build',['cmake','--build',work/'raylib-build','--clean-first','--parallel','4'],seals,environment)
    archive = work/'raylib-build/raylib/libraylib.a'
    files = [cache,flags,*compiler_files,compiler_path,archive]
    equal(build['artifacts'],{str(path):sha(sealed_file(path,seals)) for path in files},'native build artifacts')
    require(archive.stat().st_size > 0,'empty native archive')
    equal(verify_command(work,'bun-version',['bun','--version'],seals).strip(),lock['bun']['version'],'Bun pin')
    equal(report.get('bun_version'),lock['bun']['version'],'reported Bun pin')
    equal(verify_command(work,'clang-version',['clang','--version'],seals,environment).strip(),report.get('clang_version'),'Clang version')
    equal(sealed_file(work/'qualification.c',seals),probe.QUALIFY.encode(),'qualification source')
    def ccommand(source,binary): return ['clang','-std=c11','-O2','-I'+str(raylib/'src'),source,archive,'-lm','-o',binary]
    verify_command(work,'qualification-compile',ccommand(work/'qualification.c',work/'qualification'),seals,environment)
    qualification = strict_json(verify_command(work,'qualification',[work/'qualification'],seals,environment))
    equal(qualification,probe.QUALIFICATION,'native qualification')
    equal(report.get('qualification'),qualification,'qualification receipt')
    native_plan = plan(cases,probe.reference_program,native=True)
    equal(report.get('native_partition_plan'),native_plan,'native partition plan')
    equal(report.get('native_action_inventory'),inventory(native_actions(cases)),'native action inventory')
    rows, native_outputs, batches = [], [], []
    labels = {'configure','archive-compiler-version','native-build','bun-version','clang-version','qualification-compile','qualification'}
    for index,part in enumerate(native_plan):
        selected = cases[part['start']:part['start']+part['count']]
        source, binary = work/f'reference-{index}.c', work/f'reference-{index}'
        equal(sealed_file(source,seals),probe.reference_program(selected).encode(),'native emitted source')
        verify_command(work,f'reference-{index}-compile',ccommand(source,binary),seals,environment)
        output = verify_command(work,f'reference-{index}',[binary],seals,environment)
        observed = parse_output(output,native_actions(selected))
        rows.extend(observed); native_outputs.append(output)
        batches.append(dict(part,bytes=sum(len(row['bytes']) for row in observed),passed=True,output_sha256=sha(output.encode())))
        labels.update((f'reference-{index}-compile',f'reference-{index}'))
    equal(report.get('native_batches'),batches,'native batch receipts')
    equal(report.get('reference_sha256'),sha(''.join(native_outputs).encode()),'native output aggregate')
    actions,references = actions_from_native(cases,controls,rows)
    equal(report.get('action_inventory'),inventory(actions),'candidate action inventory')
    partitions = plan(actions,probe.candidate_program)
    equal(report.get('partition_plan'),partitions,'candidate partition plan')
    equal(report.get('planned_batches'),len(partitions),'candidate partition count')
    counts = dict(native_observations=len(rows),native_raw_bytes=sum(len(a['bytes']) for a,b in references.values()),
                  native_normalized_bytes=sum(len(b['bytes']) for a,b in references.values()),native_all_observed_bytes=sum(len(row['bytes']) for row in rows),
                  observations_per_lane=len(actions),compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions),
                  raw_compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions if a['role'] in RAW),
                  normalized_compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions if a['role'] not in RAW))
    for key,value in counts.items(): equal(report.get(key),value,key)
    lanes = report.get('lanes')
    require(type(lanes) is dict and set(lanes) == set(LANES),'mandatory lanes')
    actual_batches = {lane:[] for lane in LANES}
    bend = None
    for index,part in enumerate(partitions):
        selected = actions[part['start']:part['start']+part['count']]
        source,binary,js = work/f'candidate-{index}.bend',work/f'candidate-{index}',work/f'candidate-{index}.js'
        equal(sealed_file(source,seals),probe.candidate_program(selected).encode(),'candidate emitted source')
        command = strict_json(sealed_file(work/f'compile-{index}.command.json',seals).decode()).get('command')
        require(type(command) is list and len(command) == 7 and command[0] == 'bun','candidate compiler command')
        current_bend = path_at(command[1],root).parent.parent
        require(path_at(command[1],root) == current_bend/'bend2/main.ts','Bend compiler entrypoint')
        if bend is None: bend = current_bend
        equal(current_bend,bend,'Bend checkout identity')
        verify_command(work,f'compile-{index}',['bun',bend/'bend2/main.ts',source,'-o',binary,'-o',js],seals)
        labels.add(f'compile-{index}')
        for lane in LANES:
            label = f'{lane}-{index}'
            command = ['bun',js] if lane == 'javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            output = verify_command(work,label,command,seals)
            actual = parse_output(output,selected)
            equal(actual,[a['expected'] for a in selected],lane+' full-byte replay')
            actual_batches[lane].append(dict(part,bytes=sum(len(row.get('bytes',[])) for row in actual),passed=True))
            labels.add(label)
    for lane in LANES: equal(lanes[lane],dict(passed=True,batches=actual_batches[lane],differences=[]),'lane receipt '+lane)
    equal({path.name[:-13] for path in work.glob('*.command.json')},labels,'command receipt inventory')
    equal(git_revision(raylib), lock['raylib']['revision'], 'raylib checkout revision')
    equal(git_revision(bend), lock['bend']['revision'], 'Bend checkout revision')
    overlay = lock['bend']['patch']
    equal(sha((root/overlay['path']).read_bytes()), overlay['sha256'], 'compiler overlay patch')
    for relative, wanted in overlay['files'].items():
        equal(sha((bend/relative).read_bytes()), wanted, 'compiler overlay file '+relative)
    sources = source_inventory(root,bend,raylib)
    equal(report.get('sources'),sources,'complete source inventory')
    for relative in sources['library']: sealed_file(root/relative,seals)
    for path in sources['dependencies']: sealed_file(path,seals)
    oracle = {}
    for relative,ranges in probe.SOURCE_RANGES.items():
        data = (raylib/relative).read_bytes()
        equal(sha(data),probe.SOURCE_SHA256[relative],'pinned oracle '+relative)
        lines = data.splitlines(keepends=True)
        oracle[relative] = dict(sha256=sha(data),ranges=[dict(first=first,last=last,sha256=sha(b''.join(lines[first-1:last]))) for first,last in ranges])
    equal(report.get('oracle_source_ranges'),oracle,'oracle ranges')
    equal(set(seals),seals.required,'complete artifact inventory')
    equal({str(path.resolve()) for path in work.iterdir() if path.is_file()},
          {path for path in seals.required if Path(path).parent == work},'generated artifact inventory')
    return dict(passed=True,profile=report['profile'],cases=len(cases),typed_controls=len(controls),
                native_observations=len(rows),observations_per_lane=len(actions),compared_bytes_per_lane=counts['compared_bytes_per_lane'],
                lanes=list(LANES),report_sha256=sha(report_path.read_bytes()))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,allow_abbrev=False)
    parser.add_argument('report',type=Path)
    args = parser.parse_args(argv)
    print(json.dumps(audit(args.report),sort_keys=True))


if __name__ == '__main__': main()
