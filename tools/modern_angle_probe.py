#!/usr/bin/env python3
"""Private pinned finite atan2f gate, with exact words, branches and coarse trace.

The pinned C source supplies expectations before the candidate is compiled.
Host libm is a separately qualified diagnostic, never an oracle selector.
Every candidate program is bounded and emits serial, individually framed rows.
"""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time

import modern_angle_reference as reference
from binary64_narrow_oracle import nearest as narrow64
from conformance import BUILD, ROOT, checkout, source_gate

CHUNK = 256
LANES = ('cpu-1', 'cpu-2', 'javascript')
FIELDS = ('y', 'x')
DEPENDENCIES = ('src/modern_angle.bend', 'tools/modern_angle_probe.py',
                'tools/modern_angle_reference.py', 'tools/angle_probe.py',
                'tools/binary64_narrow_oracle.py', 'tools/modern_angle_bounds.py', 'tests/test_modern_angle.py',
                'tools/conformance.py', 'LAWS.bend', 'PROOF.bend', 'toolchain.json')
MAX_EVENTS = 128
# Checked helper failures are serialized, never converted into successful zero.
BINARY_OPERATIONS = {4, *range(10, 17), *range(20, 51), 80, 82, 83, 84, 85, 86, 88,
                     180, 182, 183, 184, 185, 187, 188, 189, 190, 191,
                     200, 201, 202, 203, 204, 206, 207, 208, 209, 210,
                     212, 213, 214, 215, 216, 224, 225, 226, 227, 228, 230, 231, 232, 233}
FAILURE_ARITIES = {operation: 4 for operation in BINARY_OPERATIONS}
for _index in range(31):
    FAILURE_ARITIES.update({1000 + 16*_index + offset: 4 for offset in range(14)})
FAILURE_ARITIES.update({operation: 6 for operation in (81, 181, 186, 205, *(1003 + 16*i for i in range(31)))})
FAILURE_ARITIES.update({operation: 1 for operation in (2, 3, 223, 9000, 9001, 9002)})
FAILURE_ARITIES.update({1: 2, 222: 2})


def word(value, bits=32):
    if type(value) is not int or not 0 <= value < 1 << bits:
        raise ValueError('Expected an unsigned integer word')
    return value


def strict_json(text):
    if type(text) is not str:
        raise ValueError('Expected JSON text')
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('Duplicate JSON key')
            result[key] = value
        return result
    def constant(value):
        raise ValueError('Nonfinite JSON constant')
    return json.loads(text, object_pairs_hook=pairs, parse_constant=constant)


def validate_rows(rows):
    if type(rows) is not list or not rows:
        raise ValueError('Expected a nonempty input record list')
    ids = set()
    for row in rows:
        if type(row) is not dict or set(row) not in ({'id', 'y', 'x'}, {'id', 'y', 'x', 'labels'}):
            raise ValueError('Malformed input record')
        for field in ('id', *FIELDS):
            word(row[field])
        if row['id'] in ids:
            raise ValueError('Duplicate input observation ID')
        ids.add(row['id'])
        if 'labels' in row and (type(row['labels']) is not list or
                any(type(label) is not str or not label for label in row['labels']) or
                len(set(row['labels'])) != len(row['labels'])):
            raise ValueError('Malformed input labels')


def good(high, low):
    word(high); word(low)
    if high >> 20 & 2047 == 2047:
        raise ValueError('Nonfinite successful binary64 payload')
    return [1, high, low]


def parse_value(values, offset):
    if len(values) < offset + 3:
        raise ValueError('Truncated value frame')
    tag, first, second = values[offset:offset+3]
    if tag == 1:
        good(first, second)
        return values[offset:offset+3], offset+3
    if tag != 0 or first not in FAILURE_ARITIES or second != FAILURE_ARITIES[first]:
        raise ValueError('Invalid failure operation/operand framing')
    end = offset + 3 + second
    if end > len(values):
        raise ValueError('Truncated failure operands')
    return values[offset:end], end


def parse_record(values, row):
    if type(values) is not list or len(values) < 10:
        raise ValueError('Wrong output shape/count')
    for value in values:
        word(value)
    if values[0] != row['id']:
        raise ValueError('Wrong output ID/order')
    if values[1] & ~8191 or values[2] > 7 or values[3] not in (0, 1):
        raise ValueError('Malformed branch/index/gt fields')
    if values[4] not in (0, 1) or (values[4] == 0 and values[5] != 0):
        raise ValueError('Noncanonical checked result framing')
    if values[4] and values[5] >> 23 & 255 == 255:
        raise ValueError('Nonfinite successful binary32 payload')
    final, offset = parse_value(values, 6)
    if offset >= len(values):
        raise ValueError('Missing event count')
    count = values[offset]; offset += 1
    if count > MAX_EVENTS:
        raise ValueError('Excessive event count')
    events = []
    for _ in range(count):
        if offset >= len(values):
            raise ValueError('Missing event tag')
        tag = values[offset]; offset += 1
        if tag not in set(reference.TRACE_TAGS.values()):
            raise ValueError('Unknown trace event tag')
        value, offset = parse_value(values, offset)
        events.append([tag, *value])
    if offset != len(values):
        raise ValueError('Extra or unframed output words')
    if final[0] == 1:
        if values[4] != 1 or values[5] != narrow64(*final[1:]):
            raise ValueError('Checked result does not directly narrow final binary64')
    elif values[4] != 0:
        raise ValueError('Checked succeeded despite explicit helper failure')
    return values


def parse_output(text, rows):
    validate_rows(rows)
    if type(text) is not str:
        raise ValueError('Expected output text')
    lines = text.splitlines()
    if len(lines) != len(rows):
        raise ValueError('Wrong output line count/framing')
    return [parse_record(strict_json(line), row) for line, row in zip(lines, rows)]


def validate_observations(values):
    if type(values) is not list or not values:
        raise ValueError('Missing observations')
    ids = set()
    for value in values:
        if type(value) is not list or not value:
            raise ValueError('Malformed observation')
        word(value[0])
        if value[0] in ids:
            raise ValueError('Duplicate observation ID')
        ids.add(value[0])
        parse_record(value, {'id': value[0]})


def compare(expected, actual):
    validate_observations(expected)
    validate_observations(actual)
    if len(expected) != len(actual):
        raise ValueError('Incomplete comparison')
    differences = [dict(id=a[0], expected=a, actual=b) for a, b in zip(expected, actual) if a != b]
    if differences:
        raise ValueError(f'Exact word/branch/trace mismatch: {differences[:4]} (total {len(differences)})')


def program(rows):
    validate_rows(rows)
    if len(rows) > CHUNK:
        raise ValueError('Candidate program exceeds bounded serial chunk limit')
    source = '''import Base
import ../../src/modern_angle.bend as A
import ../../src/binary64_fma.bend as F
def append(values: +List<U32>, rest: List<U32>) -> List<U32>:
  match values:
    case Nil{}: rest
    case Con{value, tail}: Con{value, append(tail, rest)}
def encode_value(value: A.Value, rest: List<U32>) -> List<U32>:
  match value:
    case A.Good{F.Words{high, low}}: Con{1, Con{high, Con{low, rest}}}
    case A.Failed{operation, +operands}:
      Con{0, Con{operation, Con{U32.from_nat(List.length(&2, U32, operands)), append(operands, rest)}}}
def encode_events(values: +List<A.TraceEvent>) -> List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{A.TraceEvent{tag, value}, rest}: Con{tag, encode_value(value, encode_events(rest))}
def encode_checked(value: Maybe<U32>, rest: List<U32>) -> List<U32>:
  match value:
    case None{}: Con{0, Con{0, rest}}
    case Some{word}: Con{1, Con{word, rest}}
def observe(id: U32, packet: A.Packet, checked: Maybe<U32>) -> List<U32>:
  A.Packet{value, mask, index, gt, +events} = packet
  tail = encode_value(value, Con{U32.from_nat(List.length(&2, A.TraceEvent, events)), encode_events(events)})
  Con{id, Con{mask, Con{index, Con{gt, encode_checked(checked, tail)}}}}
type AngleTask is Data:
  AngleTask{id: U32, y: U32, x: U32}
def emit(tasks: +List<AngleTask>) -> IO(Unit):
  match tasks:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{AngleTask{id, +y, +x}, rest}:
      do IO<Unit>:
        IO.print(List.show(~&1, ~U32, ~U32.show, observe(id, A.traced(y, x), A.checked(y, x))))
        emit(rest)
def main() -> IO(Unit):
  emit(['''
    source += ','.join('AngleTask{%d,%d,%d}' % (row['id'], row['y'], row['x']) for row in rows)
    return source + '])\n'


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def execute(command, work, name, timeout=600, env=None):
    command = [str(part) for part in command]
    for suffix in ('stdout', 'stderr'):
        (work/(name+'.'+suffix)).unlink(missing_ok=True)
    try:
        process = subprocess.run(command, cwd=ROOT, env=dict(os.environ, BEND_NO_TELEMETRY='1', **(env or {})),
                                 text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        for suffix, data in (('stdout', error.stdout), ('stderr', error.stderr)):
            (work/(name+'.'+suffix)).write_text(data.decode() if isinstance(data, bytes) else data or '')
        raise
    (work/(name+'.stdout')).write_text(process.stdout)
    (work/(name+'.stderr')).write_text(process.stderr)
    if process.returncode:
        raise ValueError(f'{name} exited {process.returncode}; retained stdout/stderr')
    return process.stdout


def compile_fresh(command, outputs, work, name, env=None):
    for path in outputs:
        path.unlink(missing_ok=True)
    execute(command, work, name, env=env)
    if any(not path.is_file() or path.stat().st_size == 0 for path in outputs):
        raise ValueError('Compiler succeeded without all fresh nonempty outputs')


def compiler_identity(command, work, name):
    resolved = shutil.which(str(command))
    if resolved is None:
        raise ValueError(f'Missing compiler/runtime: {command}')
    path = Path(resolved).resolve()
    return dict(path=str(path), sha256=digest(path), version=execute([command, '--version'], work, name).strip())


def candidate_environment(compiler):
    match = re.search(r'^(Apple )?(?:\w+ )?clang version (\d+)', compiler['version'], re.M)
    if match is None or int(match[2]) < 14:
        raise ValueError('Recorded compiler is not a supported Bend CPU clang')
    return {'CC': compiler['path']}


def source_hashes(lock):
    hashes = dict(source_gate())
    paths = set(DEPENDENCIES)
    paths.update(str(path.relative_to(ROOT)) for path in reference.source_paths())
    paths.update(str(path.relative_to(ROOT)) for path in sorted((ROOT/'tools/reference').glob('modern_atan2f*')) if path.is_file())
    if lock['bend'].get('patch'):
        paths.add(lock['bend']['patch']['path'])
    for path in sorted(paths):
        hashes[path] = digest(ROOT/path)
    return hashes


def assert_unchanged(before, lock):
    if source_hashes(lock) != before:
        raise ValueError('Source/harness/toolchain drift during probe')


def final_source_gate(hashes, bend_source, lock, compilers=None, work=None):
    assert_unchanged(hashes, lock)
    checkout(bend_source, lock['bend']['revision'], lock['bend'].get('patch'))
    for name, (command, expected) in (compilers or {}).items():
        if compiler_identity(command, work, name+'-final-version') != expected:
            raise ValueError('Compiler/runtime executable drift during probe')


def retain_artifacts(report, work, names):
    retained = report.setdefault('artifacts', {})
    for name in names:
        current = digest(work/name)
        if name in retained and retained[name] != current:
            raise ValueError('Input/program/output artifact drift during probe: ' + name)
        retained[name] = current


def assert_artifacts_unchanged(report, work):
    for name, expected in report.get('artifacts', {}).items():
        if digest(work/name) != expected:
            raise ValueError('Input/program/output artifact drift during probe: ' + name)



def validate_candidate_constants(source):
    """Check every declared word against the independently source-pinned table."""
    reference.assert_pins()
    if type(source) is not str:
        raise ValueError('Expected candidate source text')
    bodies = {}
    for match in re.finditer(r'^def constant\.(\w+)\([^\n]*\) -> [^\n]+:\n(.*?)(?=^def |\Z)', source, re.M | re.S):
        name, body = match.groups()
        if name in bodies:
            raise ValueError('Duplicate candidate constant declaration')
        bodies[name] = '\n'.join(line for line in body.splitlines() if line.strip() and not line.lstrip().startswith('#'))
    scalar_names = {'zero': 'm0', 'one': 'm1', 'minus_one': 'sgn1', 'third': 'tiny_c',
                    'small': 'correction_test', 'up': 'correction_up', 'down': 'correction_down'}
    expected_names = set(scalar_names) | {'cn', 'cd', 'coefficient', 'offset', 'offset_low'}
    if set(bodies) != expected_names:
        raise ValueError('Missing or unexpected candidate constant declaration')
    parsed = {}
    pair = r'Good\{F\.Words\{([0-9]+),\s*([0-9]+)\}\}'
    for name, key in scalar_names.items():
        match = re.fullmatch(r'\s*'+pair+r'\s*', bodies[name])
        if not match:
            raise ValueError('Nonliteral candidate scalar constant: '+name)
        parsed[key] = tuple(word(int(value)) for value in match.groups())
    parsed['sgn0'] = parsed['m1']
    for name, prefix, count, failure in (('cn', 'cn', 7, 9000), ('cd', 'cd', 7, 9000),
                                        ('offset', 'off', 8, 9002), ('offset_low', 'offl', 8, 9002)):
        lines = bodies[name].splitlines()
        if lines[0].strip() != 'match index:' or len(lines) != count+2:
            raise ValueError('Malformed candidate constant table: '+name)
        for index, line in enumerate(lines[1:-1]):
            match = re.fullmatch(r'\s*case ([0-9]+): '+pair+r'\s*', line)
            if not match or int(match[1]) != index:
                raise ValueError('Missing/reordered candidate constant table entry: '+name)
            parsed[prefix+str(index)] = tuple(word(int(value)) for value in match.groups()[1:])
        if re.sub(r'\s', '', lines[-1]) != f'case_:Failed{{{failure},[index]}}':
            raise ValueError('Malformed constant-table rejection: '+name)
    lines = bodies['coefficient'].splitlines()
    if lines[0].strip() != 'match index:' or len(lines) != 34:
        raise ValueError('Malformed double-double coefficient table')
    for index, line in enumerate(lines[1:-1]):
        match = re.fullmatch(r'\s*case ([0-9]+): DoubleDouble\{'+pair+r',\s*'+pair+r'\}\s*', line)
        if not match or int(match[1]) != index:
            raise ValueError('Missing/reordered double-double coefficient')
        fields = tuple(word(int(value)) for value in match.groups()[1:])
        parsed[f'c{index}h'], parsed[f'c{index}l'] = fields[:2], fields[2:]
    if re.sub(r'\s', '', lines[-1]) != 'case_:DoubleDouble{Failed{9001,[index]},Failed{9001,[index]}}':
        raise ValueError('Malformed double-double coefficient rejection')
    if parsed != reference.CONSTANTS:
        differences = sorted(key for key in set(parsed) | set(reference.CONSTANTS) if parsed.get(key) != reference.CONSTANTS.get(key))
        raise ValueError('Candidate coefficient/offset/scalar word mismatch: '+str(differences))
    return parsed


def expected_records(rows, records):
    """Consume only source-pinned native observations; host values are diagnostics."""
    validate_rows(rows)
    if type(records) is not list or len(records) != len(rows):
        raise ValueError('Incomplete pinned native reference')
    expected = []
    keys = {'id', 'y', 'x', 'accepted', 'pinned', 'original', 'native', 'sun',
            'mask', 'index', 'gt', 'final', 'events'}
    for row, record in zip(rows, records):
        if type(record) is not dict or set(record) != keys:
            raise ValueError('Malformed pinned native record')
        if any(type(record[field]) is not int or record[field] != row[field] for field in ('id', *FIELDS)):
            raise ValueError('Native input ID/word/order mismatch')
        finite = all((row[field] >> 23 & 255) != 255 for field in FIELDS)
        if type(record['accepted']) is not bool or record['accepted'] != finite:
            raise ValueError('Native accepted tag does not match finite-input domain')
        if type(record['events']) is not list:
            raise ValueError('Malformed native event list')
        if finite:
            for field in ('pinned', 'original', 'native', 'sun'):
                word(record[field])
            if record['pinned'] != record['original']:
                raise ValueError('Adapted source disagrees with exact pinned original')
            if type(record['final']) is not list or len(record['final']) != 2:
                raise ValueError('Missing final binary64 reference')
            value = good(*record['final'])
            checked = [1, record['pinned']]
        else:
            if (any(record[field] is not None for field in ('pinned', 'original', 'native', 'sun', 'final')) or
                    record['events'] != [] or record['mask'] != 4096 or record['index'] != 0 or record['gt'] != 0):
                raise ValueError('Noncanonical rejected reference record')
            value = [0, 1, 2, row['y'], row['x']]
            checked = [0, 0]
        observation = [row['id'], record['mask'], record['index'], record['gt'], *checked, *value, len(record['events'])]
        for event in record['events']:
            if type(event) is not list or len(event) != 3:
                raise ValueError('Malformed reference event')
            observation.extend([event[0], *good(*event[1:])])
        expected.append(parse_record(observation, row))
    return expected


def merge_native_artifacts(report, native, work):
    artifacts = native.get('artifacts')
    if type(artifacts) is not dict or not artifacts:
        raise ValueError('Missing native artifact evidence')
    for name, expected in artifacts.items():
        path = Path(name)
        if not path.is_absolute():
            path = work/path
        try:
            relative = str(path.resolve().relative_to(work.resolve()))
        except ValueError:
            context=native.get('darwin_toolchain')
            sdk_settings=None
            if native.get('system')=='Darwin' and type(context) is dict and type(context.get('sdk_path')) is str and Path(context['sdk_path']).is_absolute():
                sdk_settings=(Path(context['sdk_path'])/'SDKSettings.json').resolve()
            if path.resolve()==sdk_settings:
                if expected!=context.get('sdk_settings_sha256') or digest(path)!=expected:
                    raise ValueError('Darwin SDK settings artifact drift')
                report.setdefault('native_context_artifacts',{})[str(path)]=expected
                continue
            if path.resolve() not in {value.resolve() for value in reference.source_paths()}:
                raise ValueError('Native generated artifact outside evidence directory') from None
            if digest(path) != expected:
                raise ValueError('Native source artifact drift: '+name)
            report.setdefault('native_source_artifacts', {})[str(path)] = expected
            continue
        if type(expected) is not str or not re.fullmatch(r'[0-9a-f]{64}', expected) or digest(path) != expected:
            raise ValueError('Native artifact drift or malformed evidence: ' + name)
        retained = report.setdefault('artifacts', {})
        if relative in retained and retained[relative] != expected:
            raise ValueError('Native artifact changed previously retained evidence')
        retained[relative] = expected


def lane_commands(binary, javascript, bun):
    return (('cpu-1', [binary, '--gpu', 'off', '--threads', '1']),
            ('cpu-2', [binary, '--gpu', 'off', '--threads', '2']),
            ('javascript', [bun, javascript]))


def validate_coverage(records):
    """Require independently selected core strata; report unhit paths explicitly."""
    if type(records) is not list or not records:
        raise ValueError('Missing native coverage records')
    counts = Counter({name: 0 for name in reference.BRANCHES})
    products = Counter(); indices = set(); magnitudes = set(); quadrants = set()
    for record in records:
        mask = word(record['mask'])
        for name, flag in reference.BRANCHES.items(): counts[name] += bool(mask & flag)
        if record['accepted']:
            quadrants.add((record['y'] >> 31, record['x'] >> 31))
            if mask != 2048:
                indices.add(record['index']); magnitudes.add(record['gt'])
        if mask & 8 and not mask & 16: counts['tiny_nonboundary'] += 1
        if mask & 128 and not mask & 256: counts['correction_guard_false'] += 1
        for tag, high, low in record['events']:
            if tag == reference.TRACE_TAGS['tiny_product']:
                exponent = high >> 20 & 2047
                fraction = ((high & 0xfffff) << 32) | low
                category = 'normal' if exponent else 'subnormal' if fraction else 'negative_zero' if high >> 31 else 'positive_zero'
                products[category] += 1
    required = set(reference.BRANCHES) - {'tiny_increment'}
    missing = sorted(name for name in required if not counts[name])
    if indices != set(range(8)): missing.append('all-eight-reduction-indices')
    if magnitudes != {0, 1}: missing.append('both-magnitude-orders')
    if quadrants != {(0,0), (0,1), (1,0), (1,1)}: missing.append('all-sign-quadrants')
    for name in ('normal', 'subnormal', 'negative_zero'):
        if not products[name]: missing.append('tiny-product-'+name)
    if missing:
        raise ValueError('Incomplete required native corpus coverage: '+', '.join(missing))
    exclusions = ('tiny_increment', 'tiny_nonboundary', 'correction_guard_false')
    for name in exclusions: counts.setdefault(name, 0)
    return dict(required=sorted(required), actual=dict(counts), tiny_products=dict(products),
                reduction_indices=sorted(indices), magnitude_orders=sorted(magnitudes),
                sign_quadrants=sorted([list(pair) for pair in quadrants]),
                required_strata_covered=True, unhit_excluded=[name for name in exclusions if not counts[name]],
                excluded_from_required=dict(tiny_increment='RN tiny sign product is nonpositive; raw increment implemented and synthetically checked',
                    tiny_nonboundary='RN binary32 quotient boundary separation exceeds16ulp while ambiguity plus rational perturbation is below15ulp; preserved and synthetically checked; see MODERN-ANGLE-BOUNDS.md',
                    correction_guard_false='re-promoted binary32 th +/- th*2^-60 rounds to th in binary64; false helper implemented and synthetically checked'),
                synthetic='separate direct-helper gate, never added to native branch counts')


def synthetic_cases():
    """Fixed direct helper controls, never counted as reachable atan2 branches."""
    cases = []
    def value(bits):
        return f'A.Good{{F.Words{{{bits >> 32},{bits & 0xffffffff}}}}}'
    def failure(operation, operands):
        return f'A.Failed{{{operation},['+','.join(map(str, operands))+']}'
    def add(label, expression, result, events=None, packet=False):
        index = len(cases)
        checked = [1, narrow64(*result[1:])] if result[0] else [0, 0]
        events = [] if events is None else events
        expected = [index, 0, 0, 0, *checked, *result, len(events)]
        for tag, event in events: expected.extend([tag, *event])
        parse_record(expected, {'id': index})
        cases.append(dict(id=index, label=label, packet=expression if packet else f'A.Packet{{{expression},0,0,0,Nil{{}}}}', expected=expected))
    for bits, increment in ((0, True), (1, False), (0x3ff00000ffffffff, True), (0x3ff0000100000000, False),
                            (0xbff00000ffffffff, True), (0xbff0000100000000, False),
                            (0x8000000000000001, False), (0x8000000000000000, True)):
        result = (bits + (1 if increment else -1)) & ((1 << 64)-1)
        add('synthetic-raw-'+('increment' if increment else 'decrement'),
            f'A.tiny.stepped({"True" if increment else "False"}{{}},{bits >> 32},{bits & 0xffffffff})',
            good(result >> 32, result & 0xffffffff))
    one, zero, invalid = value(0x3ff0000000000000), value(0), value(0x7ff0000000000000)
    for name, operation in (('add', 4), ('sub', 20), ('mul', 10), ('div', 16), ('gradual', 88)):
        operands = [0x7ff00000, 0, 0x3ff00000, 0]
        add('synthetic-invalid-'+name, f'A.{name}({operation},{invalid},{one})', [0, operation, 4, *operands])
    add('synthetic-invalid-fma', f'A.fma(81,{invalid},{one},{zero})', [0, 81, 6, 0x7ff00000, 0, 0x3ff00000, 0, 0, 0])
    add('synthetic-invalid-promote', 'A.promote(2,2139095040)', [0, 2, 1, 0x7f800000])
    failed = failure(81, [1,2,3,4,5,6]); failed_wire = [0,81,6,1,2,3,4,5,6]
    for name, operation in (('add', 4), ('sub', 20), ('mul', 10), ('div', 16), ('gradual', 88)):
        add('synthetic-propagate-'+name, f'A.{name}({operation},{one},{failed})', failed_wire)
    for position in range(3):
        operands = [one, one, zero]; operands[position] = failed
        add('synthetic-propagate-fma-'+str(position), 'A.fma(81,'+','.join(operands)+')', failed_wire)
    other = failure(16, [7,8,9,10])
    add('synthetic-dependency-left-failure-precedence', f'A.add(4,{other},{failed})', [0,16,4,7,8,9,10])
    add('synthetic-tiny-nonboundary-propagation', f'A.tiny.boundary({value(0x3ff0000000000001)},{failed},0,0,0,Nil{{}})', failed_wire, packet=True)
    add('synthetic-general-prenarrow-propagation', f'A.general.prepare({failed},{zero},0,0,0,Nil{{}})', failed_wire, packet=True)
    final = good(0x3ff00000, 1)
    add('synthetic-final-correction-guard-false', f'A.correction.compare.ready(False{{}},{one},{value(0x3cb0000000000000)},0,0,0,Nil{{}})', final, [(39, final)], packet=True)
    final = good(0x3ff00000, 1)
    add('synthetic-tiny-nonboundary-success', 'A.tiny.boundary.ready(False{},1072693248,1,A.Good{F.Words{0,0}},0,0,0,Nil{})', final, [(20, final)], packet=True)
    return cases


def synthetic_program(cases):
    if type(cases) is not list or not 0 < len(cases) <= CHUNK:
        raise ValueError('Invalid bounded synthetic case count')
    header = program([dict(id=0, y=0, x=0)]).split('type AngleTask is Data:')[0]
    header += '''def observe_synthetic(id: U32, +packet: A.Packet) -> List<U32>:
  observe(id, packet, A.checked.packet(packet))
def main() -> IO(Unit):
  do IO<Unit>:
'''
    seen = set()
    for case in cases:
        if type(case) is not dict or set(case) != {'id', 'label', 'packet', 'expected'} or case['id'] in seen:
            raise ValueError('Malformed synthetic case')
        word(case['id']); seen.add(case['id'])
        parse_record(case['expected'], {'id': case['id']})
        header += f'    IO.print(List.show(~&1, ~U32, ~U32.show, observe_synthetic({case["id"]}, {case["packet"]})))\n'
    return header


def assert_runtime_libraries(native):
    reference.recheck_runtime_libraries(native)


def run_synthetic(report, work, cli, environment, bun):
    cases = synthetic_cases()
    inputs = work/'synthetic-inputs.json'; write_json(inputs, cases)
    source = work/'synthetic.bend'; source.write_text(synthetic_program(cases))
    retain_artifacts(report, work, [inputs.name, source.name])
    binary, javascript = work/'synthetic', work/'synthetic.js'
    compile_fresh([*cli, source, '-o', binary, '-o', javascript], [binary, javascript], work, 'synthetic-compile', env=environment)
    retain_artifacts(report, work, [binary.name, javascript.name, 'synthetic-compile.stdout', 'synthetic-compile.stderr'])
    rows = [dict(id=case['id'], y=0, x=0) for case in cases]
    expected = [case['expected'] for case in cases]
    result = dict(passed=False, observations=len(cases), scope='synthetic direct internal helper controls; no reachable kernel branch claim', lanes={})
    report['synthetic'] = result
    for lane, command in lane_commands(binary, javascript, bun):
        name = 'synthetic-'+lane
        output = execute(command, work, name)
        retain_artifacts(report, work, [name+'.stdout', name+'.stderr'])
        compare(expected, parse_output(output, rows))
        result['lanes'][lane] = dict(passed=True, checked=len(cases))
    result['passed'] = True
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source', type=Path, required=True)
    parser.add_argument('--clang', default='clang')
    parser.add_argument('--native-only', action='store_true', help='qualify pinned/host source only; never reports candidate pass')
    args = parser.parse_args()
    work = BUILD/'modern-angle-probe'; work.mkdir(parents=True, exist_ok=True)
    report_path = work/'results.json'
    report = dict(schema=1, passed=False, lanes={}, chunks=[], artifacts={}, phase='initializing')
    write_json(report_path, report)
    start = time.monotonic()
    try:
        lock = strict_json((ROOT/'toolchain.json').read_text())
        checkout(args.bend_source, lock['bend']['revision'], lock['bend'].get('patch'))
        reference.assert_pins()
        hashes = source_hashes(lock)
        validate_candidate_constants((ROOT/'src/modern_angle.bend').read_text())
        execute([sys.executable, ROOT/'tools/modern_angle_bounds.py'], work, 'bounds')
        retain_artifacts(report, work, ['bounds.stdout', 'bounds.stderr'])
        bun = compiler_identity('bun', work, 'bun-version')
        compiler = compiler_identity(args.clang, work, 'compiler-version')
        if bun['version'] != lock['bun']['version']:
            raise ValueError('Bun version does not match pinned toolchain')
        environment = candidate_environment(compiler)
        compilers = {'compiler': (args.clang, compiler), 'bun': ('bun', bun)}
        retain_artifacts(report, work, [f'{name}-version.{suffix}' for name in ('compiler', 'bun') for suffix in ('stdout', 'stderr')])
        rows = reference.samples()
        validate_rows(rows)
        if [row['id'] for row in rows] != list(range(len(rows))):
            raise ValueError('Full corpus IDs must preserve source-defined order')
        write_json(work/'inputs.json', rows)
        retain_artifacts(report, work, ['inputs.json'])
        report.update(phase='native-qualification', observations=len(rows), sources=hashes,
                      inputs_sha256=digest(work/'inputs.json'), bun=bun, compiler=compiler,
                      candidate_compiler=dict(compiler=compiler, environment=environment,
                          flags_source='pinned bend2/main.ts cli_build CPU flags'),
                      chunk_limit=CHUNK, output_line_limit=1,
                      coverage=dict(Counter(label for row in rows for label in row.get('labels', []))),
                      scope='private pinned finite atan2f; exact final64, final32, branch/index/gt and ordered coarse traces; no public consumer',
                      gpu='not run; no device claim',
                      host=dict(platform=platform.platform(), machine=platform.machine(), libc=platform.libc_ver(), python=platform.python_version()))
        write_json(report_path, report)
        native, records = reference.native_reference(rows, work/'native-reference', compiler['path'])
        merge_native_artifacts(report, native, work)
        assert_artifacts_unchanged(report, work)
        reference.validate_metadata(native['environment'])
        assert_runtime_libraries(native)
        merge_native_artifacts(report, native, work)
        expected = expected_records(rows, records)
        report['native'] = native
        report['branch_coverage'] = validate_coverage(records)
        write_json(work/'expected.json', expected)
        write_json(work/'native-metadata.json', native)
        write_json(work/'native-records.json', records)
        retain_artifacts(report, work, ['expected.json', 'native-metadata.json', 'native-records.json'])
        report.update(expected_sha256=digest(work/'expected.json'), accepted=sum(record['accepted'] for record in records),
                      rejected=sum(not record['accepted'] for record in records),
                      host_mismatch_count=sum(record['accepted'] and record['native'] != record['pinned'] for record in records))
        write_json(report_path, report)
        print(f'Pinned native source qualified: {len(rows)} ordered observations', flush=True)
        if args.native_only:
            final_source_gate(hashes, args.bend_source, lock, compilers, work)
            reference.assert_pins()
            assert_runtime_libraries(native)
            merge_native_artifacts(report, native, work)
            assert_artifacts_unchanged(report, work)
            retain_artifacts(report, work, [f'{prefix}-final-version.{suffix}' for prefix in ('compiler', 'bun') for suffix in ('stdout', 'stderr')])
            report.update(phase='native-only-complete', elapsed_seconds=round(time.monotonic()-start, 3))
            write_json(report_path, report)
            print('Native qualification complete; candidate lanes not run and overall passed remains false', flush=True)
            return
        report['phase'] = 'candidate'
        write_json(report_path, report)
        cli = [bun['path'], args.bend_source/'bend2/main.ts']
        proof = execute([*cli, ROOT/'PROOF.bend', '--check-only'], work, 'proof')
        retain_artifacts(report, work, ['proof.stdout', 'proof.stderr'])
        if proof.strip() != 'All terms check.':
            raise ValueError('Incomplete proof verdict')
        report['proof'] = proof.strip()
        run_synthetic(report, work, cli, environment, bun['path'])
        write_json(report_path, report)
        totals = Counter()
        for batch, offset in enumerate(range(0, len(rows), CHUNK)):
            selected = rows[offset:offset+CHUNK]
            source = work/f'candidate-{batch:03}.bend'; source.write_text(program(selected))
            retain_artifacts(report, work, [source.name])
            binary, javascript = work/f'candidate-{batch:03}', work/f'candidate-{batch:03}.js'
            compile_fresh([*cli, source, '-o', binary, '-o', javascript], [binary, javascript], work, f'compile-{batch:03}', env=environment)
            retain_artifacts(report, work, [binary.name, javascript.name, f'compile-{batch:03}.stdout', f'compile-{batch:03}.stderr'])
            for lane, command in lane_commands(binary, javascript, bun['path']):
                output = execute(command, work, f'{lane}-{batch:03}')
                retain_artifacts(report, work, [f'{lane}-{batch:03}.stdout', f'{lane}-{batch:03}.stderr'])
                actual = parse_output(output, selected)
                compare(expected[offset:offset+len(selected)], actual)
                totals[lane] += len(actual)
                report['lanes'][lane] = dict(passed=False, checked=totals[lane])
                write_json(report_path, report)
            report['chunks'].append(dict(index=batch, offset=offset, count=len(selected), passed=True))
            write_json(report_path, report)
            print(f'chunk {batch+1}: {len(selected)} words/branches/traces match CPU-1/CPU-2/JS', flush=True)
        if set(totals) != set(LANES) or any(value != len(rows) for value in totals.values()):
            raise ValueError('Incomplete lane coverage')
        final_source_gate(hashes, args.bend_source, lock, compilers, work)
        reference.assert_pins()
        assert_runtime_libraries(native)
        merge_native_artifacts(report, native, work)
        assert_artifacts_unchanged(report, work)
        retain_artifacts(report, work, [f'{prefix}-final-version.{suffix}' for prefix in ('compiler', 'bun') for suffix in ('stdout', 'stderr')])
        report.update(passed=True, phase='complete', elapsed_seconds=round(time.monotonic()-start, 3))
        for lane in report['lanes'].values():
            lane['passed'] = True
        write_json(report_path, report)
        print(f'PASS: {len(rows)} exact complete observations on each of three lanes', flush=True)
    except Exception as error:
        report.update(passed=False, error=str(error), elapsed_seconds=round(time.monotonic()-start, 3))
        write_json(report_path, report)
        raise


if __name__ == '__main__':
    main()
