#!/usr/bin/env python3
"""Independently replay a PIC file evidence directory, read-only.

Every native and CPU/JS byte is parsed and compared again. This does not call
probe comparison, protocol parsing, action construction, partition validation,
or a Python PIC pixel decoder. Probe fixture/source generation is reused only
to bind the admitted corpus and the exact executable source to the receipts.
Synthetic unit-test records establish audit mechanics, never native parity.
"""
import argparse
import errno
import os
import platform
import hashlib
import json
import math
from pathlib import Path
import re
import shlex

LANES = ('cpu-1', 'cpu-2', 'javascript')
MAX_ACTIONS = 32
MAX_SOURCE_BYTES = 196608
HEX = re.compile(r'[0-9a-f]{64}\Z')
CAP = 1048576
MAX_SPARSE_RSS = 256*1024*1024
MAX_STRESS_RSS = 1024*1024*1024
ALIAS_MACROS = ('BMP','PNG','TGA','JPG','GIF','PIC','PNM','PSD')
ALIAS_NAMES = ('bmp','png','tga','jpg','jpeg','gif','pic','pgm','ppm','psd')
TOKENS = {'.'+name for name in ALIAS_NAMES} | {'.'+name.upper() for name in ALIAS_NAMES}
BASE_ROLES = ('raw','owner','bridge','surface','factory','raw-roundtrip')
EXTRA_ROLES = ('dispatch-pic','uncontracted','fused')
RAW = {'raw','factory','owner','raw-roundtrip'}
BOUNDARY_LOADS = ('c3-single','c4-single','not-pic-qoi','directory','cap-plus-one','host-size-overflow')
STAGES = (('stage-short',3),('stage-read-failure',5),('stage-size-failure',5),('stage-long',3))
SYNTHETIC = (('continuation-error',5),('payload-error',5),('payload-short',3),('payload-long',3),('invalid-byte',1),('empty-header',0),('bad-size',2),('wrapped-stream',4))
ITERATIONS = 100
TERMINAL = dict(closure_checks=True,iterations=ITERATIONS,paths_per_iteration=len(BOUNDARY_LOADS)+len(STAGES),synthetic_checks=len(SYNTHETIC),records=ITERATIONS*(len(BOUNDARY_LOADS)+len(STAGES))+len(SYNTHETIC)+1)
REPORT_KEYS = set('passed oracle_source_ranges profile evidence_origin run_directory toolchain base_revision host tool_paths tool_realpaths sources reference_environment inputs_sha256 native_content_admission cases pixels typed_controls file_controls synthetic_controls native_rejections native_routes batch_size source_byte_limit partition_strategy lanes candidate_mipmaps factory_role raw_roundtrip_role closure file_descriptor_limit host_directory_observation boundary_source_contract unrun native_build bun_version clang_version qualification native_partition_plan native_action_inventory native_batches reference_sha256 exact-cap-reference_sha256 partitions action_inventory native_observations native_raw_bytes native_normalized_bytes observations_per_lane compared_bytes_per_lane raw_compared_bytes_per_lane normalized_compared_bytes_per_lane exact_cap resource_plans elapsed_seconds sealed_artifacts'.split())



class ArtifactSeals(dict):
    def __init__(self, values):
        super().__init__(values)
        self.required = set()
        self.timeout_seconds = None


def require(condition, message):
    if not condition:
        raise ValueError('PIC file audit: ' + message)


def strict_json(text):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'duplicate JSON key')
            result[key] = value
        return result
    def forbidden(value):
        raise ValueError('PIC file audit: nonfinite JSON ' + value)
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
        if expected and all(type(item) is int for item in expected):
            require(all(type(item) is int for item in actual),label + ' integer element type differs')
            require(actual == expected,label + ' integer elements differ')
        else:
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
    return [dict(case=c, role=role) for c in cases for role in ('raw','normalized')]


def actions_from_native(cases, controls, rows, synthetic=None):
    """Expectations come solely from freshly retained native raw/normal frames."""
    require(len(rows) == 2*len(cases), 'native raw/normal pair count')
    actions, references = [], {}
    for index, case in enumerate(cases):
        raw, normal = rows[2*index:2*index+2]
        for role, row in [('raw',raw),('normalized',normal)]:
            equal({k:v for k,v in row.items() if k != 'bytes'}, metadata(case,role), 'native '+role)
            require(type(row.get('bytes')) is list and len(row['bytes']) == case['width']*case['height']*(case['channels'] if role == 'raw' else 4), 'native byte length')
            require(all(type(v) is int and 0 <= v <= 255 for v in row['bytes']), 'native byte type')
        references[case['id']] = (raw,normal)
        roles = BASE_ROLES + (EXTRA_ROLES if case['regress'] and case['route'] == 'LoadImage' else ())
        for role in roles:
            actions.append(dict(case=case,role=role,expected=dict(raw if role in RAW else normal,role=role),normalized=normal['bytes']))
        if case['regress'] and case['route'] == 'explicit-pic':
            control = dict(case,id=case['id']+'-generic',error=0)
            actions.append(dict(case=control,role='surface-error',expected=metadata(control,'surface-error')))
    for case in controls:
        actions.append(dict(case=case,role='formatted-error',expected=metadata(case,'formatted-error')))
    for case in synthetic or []:
        actions.append(dict(case=case,role='formatted-error',synthetic=True,expected=metadata(case,'formatted-error')))
    require(len({(a['case']['id'],a['role']) for a in actions}) == len(actions), 'duplicate action identity')
    return actions, references


def boundary_actions(cases, controls, references):
    by_id = {c['id']:c for c in cases+controls}
    result = []
    def error_action(ident, error):
        case = dict(id=ident,error=error)
        return dict(case=case,role='formatted-error',expected=metadata(case,'formatted-error'))
    result.extend(error_action(ident,error) for ident,error in SYNTHETIC)
    cycle = []
    for ident in BOUNDARY_LOADS:
        case = by_id[ident]
        if ident in references:
            cycle.append(dict(case=case,role='raw',expected=references[ident][0]))
        else:
            cycle.append(dict(case=case,role='formatted-error',expected=metadata(case,'formatted-error')))
    cycle.extend(error_action(ident,error) for ident,error in STAGES)
    result.extend(cycle*ITERATIONS)
    final = dict(by_id['c3-single'],id='closure-final')
    result.append(dict(case=final,role='raw',expected=dict(references['c3-single'][0],id='closure-final')))
    equal(len(result),TERMINAL['records'],'closure record count')
    return result


def parse_boundary(text, actions):
    lines = text.splitlines()
    require(bool(lines), 'missing closure observations')
    equal(strict_json(lines[-1]), TERMINAL, 'closure terminal')
    equal(len(actions),TERMINAL['records'],'closure expected records')
    rows = parse_output('\n'.join(lines[:-1]), actions)
    equal(rows,[a['expected'] for a in actions],'every closure byte/error frame')
    return rows


def resource_plan(actions):
    return dict(observations=len(actions),compared_bytes=sum(len(a['expected'].get('bytes',[])) for a in actions),actions_sha256=sha(canonical(actions)))


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


def verify_command(work, label, command, seals, environment=None, resource=False):
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
        equal(row['timeout_seconds'], min(seals.timeout_seconds,240) if resource else seals.timeout_seconds, 'consistent command timeout')
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
    raise ValueError('PIC file audit: unable to resolve pinned Git revision')


def source_inventory(root, bend, raylib):
    library = [root/'jonlib.bend', root/'jonmath.bend', *sorted((root/'src').rglob('*.bend'))]
    required = ('tools/pic_format_probe.py','tools/pic_format_audit.py','tests/test_pic_format_harness.py',
                'tools/pic_probe.py','tools/bmp_probe.py','tools/byte_probe.py','tools/conformance.py',
                'tools/reference_environment.py','tools/runtime_image.py','toolchain.json','LAWS.bend','PROOF.bend',
                'tools/pic_file_probe.py','tools/pic_file_audit.py','tests/test_pic_file_harness.py','tests/test_pic_file_audit.py',
                'tools/raw_file_probe.py','tools/r32_raw_file_probe.py','tools/png_probe.py','tools/qoi_format_probe.py','tools/tga_format_probe.py','tools/tga_probe.py')
    dependencies = [root/item for item in required]
    dependencies += [path for path in raylib.rglob('*') if path.is_file() and
                     (path.suffix in ('.c','.h','.cmake','.in') or path.name in ('CMakeLists.txt','CMakeOptions.txt')) and '.git' not in path.parts]
    dependencies += [path for path in (bend/'bend2').rglob('*') if path.is_file() and path.suffix in ('.ts','.bend','.c','.js','.h')]
    return dict(library={str(path.relative_to(root)):sha(path.read_bytes()) for path in library},
                dependencies={str(path):sha(path.read_bytes()) for path in dependencies})


def validate_alias_config(cache, flags):
    validate_native_config(cache,flags)
    fields = dict(re.findall(r'^([A-Za-z_][A-Za-z0-9_]*):[^=\n]+=(.*)$',cache,re.M))
    tokens = shlex.split(flags,comments=True)
    definitions = []
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token in ('-D','-U'):
            index += 1
            require(index < len(tokens),'incomplete alias macro')
            token += tokens[index]
        if token.startswith(('-D','-U')): definitions.append(token)
        index += 1
    for name in ALIAS_MACROS:
        macro = 'SUPPORT_FILEFORMAT_'+name
        selected = [t for t in definitions if t[2:].split('=')[0] == macro]
        equal(fields.get(macro),'ON','alias cache '+macro)
        require(len(selected) == 1 and selected[0] in ('-D'+macro,'-D'+macro+'=1'),'effective alias flag '+macro)
    return dict(enabled_macros=['SUPPORT_FILEFORMAT_'+name for name in ALIAS_MACROS],recognized_tokens=sorted(TOKENS),extension_rule='last dot of entire path; index zero excluded')


def expected_inputs(probe, root, work):
    """Bind generated corpus to exact retained file paths without making files."""
    import copy
    cases = copy.deepcopy(probe.fixtures())
    controls = copy.deepcopy(probe.controls())
    synthetic = copy.deepcopy(probe.synthetic_controls())
    for case in cases+controls:
        case['path'] = str((work/'fixtures'/case['filename']).relative_to(root))
        if case.get('special') in ('sparse','large','overflow'):
            case.update(size={'sparse':CAP+1,'large':256*1024*1024,'overflow':4294967296}[case['special']],
                        prefix=probe.tiny_pic(),sparse_recipe='tiny valid prefix then truncate; holes never loaded or hashed')
    original = next(c for c in cases if c['id'] == 'c3-single')
    stress = dict(original,id='exact-cap-accepted',filename='exact-cap.pic',regress=False)
    stress['bytes'] = original['bytes']+[i%256 for i in range(CAP-len(original['bytes']))]
    stress['path'] = str((work/'fixtures'/stress['filename']).relative_to(root))
    return dict(cases=cases,controls=controls,synthetic_controls=synthetic,exact_cap=stress)


def verify_files(inputs, root, work, seals):
    """Never hash, read through or trust a seal for a sparse file's holes."""
    expected_files = set()
    sparse_paths = {str((root/c['path']).resolve()) for c in inputs['controls'] if c.get('special') in ('sparse','large','overflow')}
    require(not (set(seals) & sparse_paths),'sparse holes must never be sealed/read')
    for case in [*inputs['cases'],*inputs['controls'],inputs['exact_cap']]:
        path = root/case['path']
        equal(path.resolve(),path.absolute(),'canonical fixture identity')
        require(path.is_relative_to(work/'fixtures'),'fixture escaped run')
        special = case.get('special')
        if special == 'missing':
            require(not path.exists() and not path.is_symlink(),'missing fixture appeared')
        elif special == 'directory':
            require(path.is_dir(),'directory fixture absent')
            equal((path/'entry').read_bytes(),b'x','directory entry')
            expected_files.add(path/'entry')
        elif special in ('sparse','large','overflow'):
            require(path.is_file(),'sparse fixture absent')
            equal(path.stat().st_size,case['size'],'sparse stat size')
            with path.open('rb') as handle:
                equal(handle.read(len(case['prefix'])),bytes(case['prefix']),'sparse bounded prefix')
            expected_files.add(path)
        else:
            equal(sealed_file(path,seals),bytes(case['bytes']),'complete fixture bytes')
            expected_files.add(path)
    actual = {p for p in (work/'fixtures').rglob('*') if not p.is_dir()}
    equal(actual,expected_files,'complete fixture file inventory')


def boundary_source_contract(root):
    source = (root/'jonlib.bend').read_text()
    names = ('Image.file.limit','Image.file.complete','Image.file.payload','Image.file.read','Image.file.bounded','Image.file.sized','Image.file.opened','Image.file.bytes','Image.file.decoded','Image.Formatted.pic.file.loaded','Image.Formatted.load_pic')
    sections = {}
    for name in names:
        require(source.count('def '+name+'(') == 1,'missing/ambiguous file source definition')
        sections[name] = 'def '+name+'('+source.split('def '+name+'(',1)[1].split('\ndef ',1)[0]
    bounded, read = sections['Image.file.bounded'], sections['Image.file.read']
    require(bounded.index('case False{}:') < bounded.index('File.close(file)') < bounded.index('case True{}:') < bounded.index('File.read_bytes(file, size)'),'pre-read cap and close ordering')
    require(bounded.count('File.read_bytes(') == 1 and read.index('File.close(file)') < read.index('Image.file.payload(size, status)'),'single read/close before processing')
    require('Image.file.bounded((size <= limit : U32), file, size)' in sections['Image.file.sized'],'inclusive file cap')
    require('Image.file.bytes(path, Image.file.limit(RasterFile{})), Image.Formatted.pic.file.loaded)' in sections['Image.Formatted.load_pic'],'explicit PIC wrapper')
    require('Image.file.decoded(Image.Formatted, Image.Formatted.decode_pic(bytes))' in sections['Image.Formatted.pic.file.loaded'],'explicit PIC continuation')
    return dict(kind='source-order evidence plus separately observed runtime controls; not an IO proof',close_guarantee='File.close is called; Base cannot report OS close failure',source_sha256=sha(source.encode()),definitions={name:dict(source=text,sha256=sha(text.encode())) for name,text in sections.items()})


def verify_resource(work, label, command, seals, actions, kind, lane_receipt, python):
    from r32_raw_file_probe import RESOURCE_RUNNER
    launcher, usage = work/(label+'.resource-runner.py'), work/(label+'.resource.json')
    expected_source = 'import resource\nresource.setrlimit(resource.RLIMIT_NOFILE,(64,64))\n'+RESOURCE_RUNNER
    equal(sealed_file(launcher,seals),expected_source.encode(),'resource RLIMIT launcher source')
    output = verify_command(work,label,[python,launcher,usage,*command],seals,resource=True)
    observed = parse_boundary(output,actions) if kind == 'boundary' else parse_output(output,actions)
    equal(observed,[a['expected'] for a in actions],'complete resource replay '+label)
    usage_row = strict_json(sealed_file(usage,seals).decode())
    require(type(usage_row) is dict and set(usage_row) == {'maximum_rss_bytes'},'resource usage schema')
    ceiling = MAX_STRESS_RSS if kind == 'exact_cap' else MAX_SPARSE_RSS
    rss = usage_row['maximum_rss_bytes']
    require(type(rss) is int and 0 < rss <= ceiling,'resource RSS ceiling')
    require(type(lane_receipt) is dict,'resource receipt type')
    elapsed = lane_receipt.get('elapsed_seconds')
    require(type(elapsed) is float and math.isfinite(elapsed) and elapsed >= 0,'resource elapsed time')
    equal(lane_receipt,dict(passed=True,maximum_rss_bytes=rss,elapsed_seconds=elapsed,descriptor_limit=64,
          maximum_rss_acceptance_bytes=ceiling,**resource_plan(actions),stdout_sha256=sha(output.encode())), 'resource receipt '+label)


def audit(report_path):
    import pic_file_probe as probe
    import pic_format_probe as memory
    report_path = Path(report_path).resolve()
    report = strict_json(report_path.read_text())
    require(type(report) is dict and set(report) == REPORT_KEYS,'complete report schema required')
    for key,value in dict(passed=True,profile='native-pic-formatted-files-v1',
          evidence_origin='NEW source-scoped file run; earlier memory evidence remains separate',
          native_content_admission='unchanged PIC memory admission: actual header/all descriptors/all row controls/counts/samples; malformed and overcap controls never native; native suffix shares stb sniffing',
          candidate_mipmaps='implicit single-mip type contract, not stored/measured',
          factory_role='native-byte factory reconstruction gated by a distinct successful public reopen; not a second loader-byte comparison',
          raw_roundtrip_role='reopened loader bytes exported and reconstructed through from_bytes',
          closure=TERMINAL,file_descriptor_limit=64,
          host_directory_observation=dict(stage='read',code=errno.EISDIR,message=os.strerror(errno.EISDIR)),
          unrun=['GPU/Metal','Windows/macOS/browser','big-endian','exact-commit hosted CI','maximum-area allocation/resource limits','representative performance','concurrent/special files','OS close-error reporting','generic formatted/float dispatch','native malformed recovery']).items():
        equal(report[key],value,key)
    require(type(report['host']) is dict and set(report['host']) == {'system','machine'},'host schema')
    require(report['host']['system'] in ('Linux','Darwin'),'supported directory/read host')
    equal(report['host']['system'],platform.system(),'same-host directory/errno replay')
    require(type(report['host']['machine']) is str and bool(report['host']['machine']),'host machine')
    require(type(report['elapsed_seconds']) is float and math.isfinite(report['elapsed_seconds']) and report['elapsed_seconds'] >= 0,'report duration')
    root = probe.ROOT.resolve()
    work = path_at(report['run_directory'],root)
    require(work.parent == report_path.parent and re.fullmatch(r'run-[0-9a-f]{32}',work.name),'run directory identity')
    values = report['sealed_artifacts']
    require(type(values) is dict and values,'artifact inventory absent')
    for path,digest in values.items():
        equal(str(Path(path).resolve()),path,'canonical artifact path')
        require(type(digest) is str and HEX.fullmatch(digest) is not None,'artifact digest type')
    seals = ArtifactSeals(values)
    inputs = strict_json(sealed_file(work/'inputs.json',seals).decode())
    equal(inputs,expected_inputs(probe,root,work),'complete file/synthetic input inventory')
    verify_files(inputs,root,work,seals)
    cases,controls,synthetic,stress = inputs['cases'],inputs['controls'],inputs['synthetic_controls'],inputs['exact_cap']
    equal(report['inputs_sha256'],sha((work/'inputs.json').read_bytes()),'input hash')
    for key,value in dict(cases=len(cases),pixels=sum(c['width']*c['height'] for c in cases),typed_controls=len(controls)+len(synthetic),
          file_controls=len(controls),synthetic_controls=len(synthetic),native_rejections=0,
          native_routes={r:sum(c['route'] == r for c in cases) for r in ('LoadImage','explicit-pic')},
          batch_size=MAX_ACTIONS,source_byte_limit=MAX_SOURCE_BYTES,partition_strategy='ordered-greedy-generated-source-v1').items(): equal(report[key],value,key)
    equal(report['boundary_source_contract'],boundary_source_contract(root),'file source-order contract')
    lock = strict_json((root/'toolchain.json').read_text())
    equal(report['toolchain'],lock,'pinned toolchain')
    equal(report['base_revision'],git_revision(root),'current library revision')
    environment = report['reference_environment']; verify_environment(environment)
    paths = report['tool_paths']
    require(type(paths) is dict and set(paths) == {'bun','clang','cmake','python'},'complete tool inventory')
    require(all(type(path) is str and Path(path).is_absolute() for path in paths.values()),'absolute tool paths')
    equal(report['tool_realpaths'],{k:str(path_at(v,root)) for k,v in paths.items()},'tool realpaths')
    for path in paths.values(): sealed_file(path_at(path,root),seals)
    configure = strict_json(sealed_file(work/'configure.command.json',seals).decode()).get('command')
    require(type(configure) is list and len(configure) > 3 and configure[:2] == ['cmake','-S'],'configure command')
    raylib = path_at(configure[2],root)
    expected_configure = ['cmake','-S',str(raylib),'-B',str(work/'raylib-build'),'-DPLATFORM=Memory','-DCMAKE_BUILD_TYPE=Release','-DBUILD_EXAMPLES=OFF','-DCUSTOMIZE_BUILD=ON','-DSUPPORT_MODULE_RAUDIO=OFF','-DSUPPORT_RPRAND_GENERATOR=ON','-DSUPPORT_FILEFORMAT_PIC=ON','-DUSE_EXTERNAL_GLFW=OFF']
    expected_configure += ['-DSUPPORT_FILEFORMAT_'+name+'=ON' for name in ALIAS_MACROS if name != 'PIC']
    verify_command(work,'configure',expected_configure,seals,environment)
    build = report['native_build']
    require(type(build) is dict and set(build) == {'mode','configuration','compiler','compiler_version','artifacts','file_aliases'},'native build schema')
    equal(build['mode'],'fresh-isolated-build','fresh build')
    cache,flags = work/'raylib-build/CMakeCache.txt',work/'raylib-build/raylib/CMakeFiles/raylib.dir/flags.make'
    cache_text,flags_text = sealed_file(cache,seals).decode(),sealed_file(flags,seals).decode()
    equal(build['configuration'],validate_native_config(cache_text,flags_text),'native configuration')
    equal(build['file_aliases'],validate_alias_config(cache_text,flags_text),'all effective file aliases')
    compiler_files = list((work/'raylib-build/CMakeFiles').glob('*/CMakeCCompiler.cmake'))
    require(len(compiler_files) == 1,'compiler configuration inventory')
    text = sealed_file(compiler_files[0],seals).decode(); compiler = {}
    for key in ('CMAKE_C_COMPILER','CMAKE_C_COMPILER_ID','CMAKE_C_COMPILER_VERSION'):
        found = re.findall(r'set\('+key+r' "([^"\n]+)"\)',text)
        require(len(found) == 1,'compiler metadata missing/ambiguous'); compiler[key] = found[0]
    equal(build['compiler'],compiler,'archive compiler')
    compiler_path = Path(compiler['CMAKE_C_COMPILER'])
    require(compiler_path.is_absolute(),'absolute archive compiler path')
    version = verify_command(work,'archive-compiler-version',[compiler_path,'--version'],seals,environment)
    require(bool(version.strip()),'empty archive compiler version')
    equal(build['compiler_version'],version,'archive compiler version')
    verify_command(work,'native-build',['cmake','--build',work/'raylib-build','--clean-first','--parallel','4'],seals,environment)
    archive = work/'raylib-build/raylib/libraylib.a'
    files = [cache,flags,*compiler_files,compiler_path,archive]
    equal(build['artifacts'],{str(path):sha(sealed_file(path,seals)) for path in files},'native build artifacts')
    require(archive.stat().st_size > 0,'empty archive')
    equal(verify_command(work,'bun-version',['bun','--version'],seals).strip(),lock['bun']['version'],'Bun pin')
    equal(report['bun_version'],lock['bun']['version'],'reported Bun pin')
    equal(verify_command(work,'clang-version',['clang','--version'],seals,environment).strip(),report['clang_version'],'Clang version')
    def ccommand(source,binary): return ['clang','-std=c11','-O2','-I'+str(raylib/'src'),source,archive,'-lm','-o',binary]
    equal(sealed_file(work/'qualification.c',seals),probe.qualification_program().encode(),'qualification source')
    require(0 < (work/'qualification.c').stat().st_size <= MAX_SOURCE_BYTES,'qualification source budget')
    verify_command(work,'qualification-compile',ccommand(work/'qualification.c',work/'qualification'),seals,environment)
    qualification = strict_json(verify_command(work,'qualification',[work/'qualification'],seals,environment))
    equal(qualification,memory.QUALIFICATION,'native qualification')
    equal(report['qualification'],qualification,'qualification receipt')
    labels = {'configure','archive-compiler-version','native-build','bun-version','clang-version','qualification-compile','qualification'}
    native_plan = plan(cases,probe.reference_program,native=True)
    equal(report['native_partition_plan'],native_plan,'native partition plan')
    equal(report['native_action_inventory'],inventory(native_actions(cases)),'native action inventory')
    rows,outputs,batches = [],[],[]
    for index,part in enumerate(native_plan):
        selected = cases[part['start']:part['start']+part['count']]
        source,binary = work/f'reference-{index}.c',work/f'reference-{index}'
        equal(sealed_file(source,seals),probe.reference_program(selected).encode(),'native emitted source')
        verify_command(work,f'reference-{index}-compile',ccommand(source,binary),seals,environment)
        output = verify_command(work,f'reference-{index}',[binary],seals,environment)
        observed = parse_output(output,native_actions(selected))
        rows.extend(observed); outputs.append(output)
        batches.append(dict(part,bytes=sum(len(row['bytes']) for row in observed),passed=True,output_sha256=sha(output.encode())))
        labels.update((f'reference-{index}-compile',f'reference-{index}'))
    equal(report['native_batches'],batches,'native batches')
    equal(report['reference_sha256'],sha(''.join(outputs).encode()),'native output aggregate')
    source,binary = work/'exact-cap-reference.c',work/'exact-cap-reference'
    exact_source = probe.reference_program([stress]).encode()
    require(0 < len(exact_source) <= MAX_SOURCE_BYTES,'exact cap native source budget')
    equal(sealed_file(source,seals),exact_source,'exact cap native source')
    verify_command(work,'exact-cap-reference-compile',ccommand(source,binary),seals,environment)
    output = verify_command(work,'exact-cap-reference',[binary],seals,environment)
    stress_rows = parse_output(output,native_actions([stress]))
    equal(report['exact-cap-reference_sha256'],sha(output.encode()),'exact cap native hash')
    equal(report['exact_cap'],dict(size=CAP,native_reference=stress_rows[0],native_normalized=stress_rows[1]),'exact cap native receipt')
    labels.update(('exact-cap-reference-compile','exact-cap-reference'))
    actions,references = actions_from_native(cases,controls,rows,synthetic)
    equal(report['action_inventory'],inventory(actions),'candidate action inventory')
    partitions = plan(actions,probe.candidate_program)
    equal(report['partitions'],partitions,'candidate partition plan')
    counts = dict(native_observations=len(rows),native_raw_bytes=sum(len(a['bytes']) for a,b in references.values()),native_normalized_bytes=sum(len(b['bytes']) for a,b in references.values()),observations_per_lane=len(actions),compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions),raw_compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions if a['role'] in RAW),normalized_compared_bytes_per_lane=sum(len(a['expected'].get('bytes',[])) for a in actions if a['role'] not in RAW))
    for key,value in counts.items(): equal(report[key],value,key)
    lanes = report['lanes']
    require(type(lanes) is dict and set(lanes) == set(LANES),'mandatory lanes')
    for lane in LANES:
        require(type(lanes[lane]) is dict and set(lanes[lane]) == {'passed','batches','differences','boundary','sparse','exact_cap'},'complete lane schema')
        equal(lanes[lane]['passed'],True,'lane passed')
        equal(lanes[lane]['differences'],[],'lane differences')
    actual_batches = {lane:[] for lane in LANES}; bend = None
    for index,part in enumerate(partitions):
        selected = actions[part['start']:part['start']+part['count']]
        source,binary,js = work/f'candidate-{index}.bend',work/f'candidate-{index}',work/f'candidate-{index}.js'
        equal(sealed_file(source,seals),probe.candidate_program(selected).encode(),'candidate emitted source')
        command = strict_json(sealed_file(work/f'compile-{index}.command.json',seals).decode()).get('command')
        require(type(command) is list and len(command) == 7 and command[0] == 'bun','candidate compiler command')
        current_bend = path_at(command[1],root).parent.parent
        equal(path_at(command[1],root),current_bend/'bend2/main.ts','Bend entrypoint')
        if bend is None: bend = current_bend
        equal(current_bend,bend,'Bend checkout identity')
        verify_command(work,f'compile-{index}',['bun',bend/'bend2/main.ts',source,'-o',binary,'-o',js],seals)
        labels.add(f'compile-{index}')
        for lane in LANES:
            label = f'{lane}-{index}'
            command = ['bun',js] if lane == 'javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            actual = parse_output(verify_command(work,label,command,seals),selected)
            equal(actual,[a['expected'] for a in selected],lane+' every byte')
            actual_batches[lane].append(dict(part,bytes=sum(len(r.get('bytes',[])) for r in actual),passed=True)); labels.add(label)
    for lane in LANES: equal(lanes[lane]['batches'],actual_batches[lane],'all lane batches')
    boundary = boundary_actions(cases,controls,references)
    stress_actions,_ = actions_from_native([stress],[],stress_rows)
    sparse = [dict(case=c,role='formatted-error',expected=metadata(c,'formatted-error')) for c in controls if c.get('special') in ('sparse','large','overflow')]
    resources = dict(boundary=boundary,sparse=sparse,exact_cap=stress_actions)
    equal(report['resource_plans'],{k:resource_plan(v) for k,v in resources.items()},'resource plans')
    for kind,expected in resources.items():
        program = probe.boundary_program(cases,controls) if kind == 'boundary' else probe.candidate_program(expected)
        require(0 < len(program.encode()) <= MAX_SOURCE_BYTES,'resource source budget')
        source,binary,js = work/(kind+'.bend'),work/kind,work/(kind+'.js')
        equal(sealed_file(source,seals),program.encode(),'resource source '+kind)
        verify_command(work,kind+'-compile',['bun',bend/'bend2/main.ts',source,'-o',binary,'-o',js],seals)
        labels.add(kind+'-compile')
        for lane in LANES:
            command = ['bun',js] if lane == 'javascript' else [binary,'--gpu','off','--threads',lane[-1]]
            label = lane+'-'+kind
            verify_resource(work,label,command,seals,expected,kind,lanes[lane][kind],paths['python'])
            labels.add(label)
    equal({path.name[:-13] for path in work.glob('*.command.json')},labels,'command receipt inventory')
    equal(git_revision(raylib),lock['raylib']['revision'],'raylib checkout revision')
    equal(git_revision(bend),lock['bend']['revision'],'Bend checkout revision')
    overlay = lock['bend']['patch']
    equal(sha((root/overlay['path']).read_bytes()),overlay['sha256'],'compiler overlay patch')
    for relative,wanted in overlay['files'].items(): equal(sha((bend/relative).read_bytes()),wanted,'compiler overlay '+relative)
    sources = source_inventory(root,bend,raylib)
    equal(report['sources'],sources,'complete source inventory')
    for relative in sources['library']: sealed_file(root/relative,seals)
    for path in sources['dependencies']: sealed_file(path,seals)
    oracle = {}
    for ranges,hashes in ((memory.SOURCE_RANGES,memory.SOURCE_SHA256),(probe.FILE_SOURCE_RANGES,probe.FILE_SOURCE_SHA256)):
        for relative,sections in ranges.items():
            data = (raylib/relative).read_bytes(); equal(sha(data),hashes[relative],'pinned oracle '+relative)
            lines = data.splitlines(keepends=True)
            entry = oracle.setdefault(relative,dict(sha256=sha(data),ranges=[]))
            entry['ranges'].extend(dict(first=first,last=last,sha256=sha(b''.join(lines[first-1:last]))) for first,last in sections)
    equal(report['oracle_source_ranges'],oracle,'oracle source ranges')
    equal(set(seals),seals.required,'complete artifact seal inventory')
    equal({str(p.resolve()) for p in work.iterdir() if p.is_file()},{path for path in seals.required if Path(path).parent == work},'generated artifact inventory')
    return dict(passed=True,profile=report['profile'],cases=len(cases),file_controls=len(controls),synthetic_controls=len(synthetic),native_observations=len(rows),observations_per_lane=len(actions),compared_bytes_per_lane=counts['compared_bytes_per_lane'],resource_observations={kind:len(values) for kind,values in resources.items()},lanes=list(LANES),report_sha256=sha(report_path.read_bytes()))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,allow_abbrev=False)
    parser.add_argument('report',type=Path)
    args = parser.parse_args(argv)
    print(json.dumps(audit(args.report),sort_keys=True))


if __name__ == '__main__': main()
