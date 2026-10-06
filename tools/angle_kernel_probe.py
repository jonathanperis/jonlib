#!/usr/bin/env python3
"""Host-independent atan2f kernel and checked angle-wrapper gate.

The native oracle is compiled from pinned C sources: glibc-2.41 e_atan2f (unmodified,
plus its instrumented adaptation for branch/trace words) and Sun 2.39 e_atan2f/s_atanf.
Jonmath's kernels are compared per profile over the frozen corpora; the checked wrappers
are compared per profile against original raymath Vector2Angle/Vector2LineAngle/
Vector3Angle compiled with atan2f routed to that pinned kernel, and every rejection stage
is checked against exact rational arithmetic. Apple2007 has no portable source: it is
compared with native libm only on Darwin hosts whose native profile selects it.
"""
from collections import Counter
from fractions import Fraction
import hashlib
import itertools
import json
import math
import platform
import random
import struct

import probekit
import native_profiles as profiles
from native_profiles import fp, rn
from angle_probe import samples as old_samples
from binary64_narrow_oracle import nearest as narrow64

REFERENCE = probekit.ROOT / 'tools/reference'
FLAGS = ['-std=c11', '-O2', '-frounding-math', '-fno-fast-math', '-ffp-contract=off', '-fno-lto',
         '-fno-builtin-atan2f', '-fno-builtin-fma']
PROFILES = profiles.ANGLE_PROFILES
APIS = profiles.APIS
ARITIES = (4, 4, 6)
STAGES = ({1, 2, *range(10, 16), 31, 32}, {1, 2, 10, 11, 31, 32, 33}, {1, 2, *range(10, 33)})
KERNEL_BATCH, WRAPPER_BATCH = 256, 64
SEED = 0xA74A241
BRANCHES = dict(zip(('rational', 'shortcut', 'ambiguous', 'tiny', 'tiny_boundary', 'tiny_increment',
                     'tiny_decrement', 'general', 'correction', 'correction_up', 'correction_down',
                     'zero', 'reject'), (1 << i for i in range(13))))
TINY_PRODUCT, TRACE_TAGS = 19, set(range(1, 40))
# Checked Bend helper failures carry (operation, operand count); never a successful zero.
FAILURE_ARITIES = {op: 4 for op in (4, *range(10, 17), *range(20, 51), 80, 82, 83, 84, 85, 86, 88, 180, 182,
                                    183, 184, 185, 187, 188, 189, 190, 191, 200, 201, 202, 203, 204, 206,
                                    207, 208, 209, 210, 212, 213, 214, 215, 216, 224, 225, 226, 227, 228,
                                    230, 231, 232, 233)}
FAILURE_ARITIES.update({1000 + 16 * i + offset: 4 for i in range(31) for offset in range(14)})
FAILURE_ARITIES.update({op: 6 for op in (81, 181, 186, 205, *(1003 + 16 * i for i in range(31)))})
FAILURE_ARITIES.update({op: 1 for op in (2, 3, 223, 9000, 9001, 9002)})
FAILURE_ARITIES.update({1: 2, 222: 2})


def bits(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def finite(word):
    return (word & 0x7fffffff) < 0x7f800000


def normal(word):
    magnitude = word & 0x7fffffff
    return magnitude == 0 or 0x00800000 <= magnitude < 0x7f800000


def hash_json(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


# ---------------------------------------------------------------- scalar kernel corpus
def kernel_rows():
    """Historical 1,086 cases first and unchanged, generated strata, then manifest controls."""
    rows, seen = [], {}
    def put(y, x, label, keep=False):
        if keep or (y, x) not in seen:
            seen.setdefault((y, x), len(rows))
            rows.append(dict(id=len(rows), y=y, x=x, labels=[label]))
        elif label not in rows[seen[y, x]]['labels']:
            rows[seen[y, x]]['labels'].append(label)
    def signs(y, x, label):
        for sy, sx in itertools.product((0, 0x80000000), repeat=2):
            put(y ^ sy, x ^ sx, label)
    for i, (y, x) in enumerate(old_samples()):
        put(bits(y), bits(x), f'historical-{i}', keep=True)
    edges = (0, 1, 2, 0x003fffff, 0x00400000, 0x007ffffe, 0x007fffff, 0x00800000, 0x00800001,
             0x3f7fffff, 0x3f800000, 0x3f800001, 0x7f7ffffe, 0x7f7fffff)
    for y, x in itertools.product(edges, repeat=2):
        signs(y, x, 'finite-boundary-cross-product')
    for exponent in range(255):
        word = (exponent << 23) | 1
        signs(word, word, 'equal-every-exponent')
        for delta in (-1, 1):
            if 0 <= word + delta < 0x7f800000:
                put(word, word + delta, 'adjacent-every-exponent')
                put(word + delta, word, 'adjacent-every-exponent-swapped')
        for distance, delta in itertools.product((25, 27), (-1, 0, 1)):  # raw-word guard distances
            other = word + (distance << 23) + delta
            if other < 0x7f800000:
                put(word, other, f'guard-{distance}-delta-{delta}')
                put(other, word, f'guard-{distance}-delta-{delta}-swapped')
    for bit in range(23):
        for fraction in (1 << bit, 0x7fffff ^ (1 << bit)):
            signs(fraction, 0x00800000, 'subnormal-bit-pattern')
            signs(0x00800000, fraction, 'subnormal-bit-pattern-swapped')
    for y in (1, 0x80000001):
        put(y, 0x0c800000, 'minimum-general-ratio')
    for x, y in itertools.product((0x75000000, 0x7b000000, 0x7b800000, 0x7f000000), (1, 0x80000001)):
        put(y, x, 'literal-tiny-gradual-product')
    rng = random.Random(SEED)
    for _ in range(512):  # stratified exponent/significand/sign, not uniform reals
        y = (rng.randrange(255) << 23) | rng.getrandbits(23) | (rng.getrandbits(1) << 31)
        x = (rng.randrange(255) << 23) | rng.getrandbits(23) | (rng.getrandbits(1) << 31)
        put(y, x, 'deterministic-bit-stratified'); put(x, y, 'deterministic-bit-stratified-swapped')
    for (y, x), exponent in itertools.product(old_samples()[62:94], (-80, -20, 20, 80)):
        put(bits(math.ldexp(y, exponent)), bits(math.ldexp(x, exponent)), f'common-rescale-{exponent}')
    for case in json.loads((REFERENCE / 'modern_atan2f_general_cases.json').read_text())['cases']:
        signs(int(case['y'], 16), int(case['x'], 16), 'native-only-general-search')
        signs(int(case['x'], 16), int(case['y'], 16), 'native-only-general-search-swapped')
    for bad in (0x7f800000, 0xff800000, 0x7fc00000, 0xffc00001, 0x7f800001, 0xff800001):
        for other in (0, 0x80000000, 1, 0x3f800000, bad):
            put(bad, other, 'nonfinite-checked-rejection'); put(other, bad, 'nonfinite-checked-rejection')
    for control in profiles.load_manifest()['scalar_controls']:
        put(int(control['y'], 16), int(control['x'], 16), 'manifest-' + control['id'], keep=True)
        rows[-1]['frozen'] = {p: int(v, 16) for p, v in control['expected'].items()}
    return rows


def expected_tags(mask):
    if mask in (2048, 4096):
        return []
    tags = [1] + (list(range(2, 11)) if mask & 1 else []) + [11, 12, 13]
    if mask & 8:
        return tags + list(range(14, 19)) + ([19] if mask & 16 else []) + [20]
    if mask & 128:
        tags += list(range(21, 25)) + [25, 26] * 31 + list(range(27, 38)) + ([38] if mask & 256 else [])
    return tags + [39]


def parse_kernel_native(text, rows):
    """Driver records with independent branch/classification/trace sanity checks."""
    lines = text.splitlines()
    if len(lines) != len(rows):
        raise probekit.ProbeFailure('Wrong native kernel observation count')
    records = []
    for line, row in zip(lines, rows):
        r = json.loads(line)
        if [r['id'], r['y'], r['x']] != [row['id'], row['y'], row['x']] or r['accepted'] != (finite(row['y']) and finite(row['x'])):
            raise probekit.ProbeFailure(f'Native input order/acceptance mismatch at {row["id"]}')
        mask, ax, ay = r['mask'], row['x'] & 0x7fffffff, row['y'] & 0x7fffffff
        problem = None
        if not r['accepted']:
            if any(r[k] is not None for k in ('pinned', 'original', 'native', 'sun', 'final')) or (mask, r['index'], r['gt'], r['events']) != (4096, 0, 0, []):
                problem = 'rejected input performed kernel work'
        elif r['pinned'] != r['original']:
            problem = 'instrumented adaptation differs from the unmodified pinned source'
        elif (mask == 2048) != (ay == 0 and (ax == 0 or row['x'] >> 31 == 0)) or mask & 4096:
            problem = 'wrong early-zero branch'
        elif mask != 2048 and (r['gt'] != int(ay > ax) or r['index'] != (row['y'] >> 31) * 4 + (row['x'] >> 31) * 2 + int(ay > ax)):
            problem = 'wrong magnitude/quadrant classification'
        elif mask != 2048 and (bool(mask & 1) != (abs(ax - ay) < (27 << 23)) or bool(mask & 1) == bool(mask & 2)
                               or bool(mask & 4) != bool(mask & (8 | 128)) or bool(mask & 16) != bool(mask & (32 | 64))
                               or bool(mask & 256) != bool(mask & (512 | 1024)) or (mask & 16 and not mask & 8)):
            problem = 'impossible branch combination'
        elif [e[0] for e in r['events']] != expected_tags(mask):
            problem = 'wrong trace checkpoint sequence'
        elif r['events']:
            words = {e[0]: (e[1] << 32) | e[2] for e in r['events']}
            if (bool(mask & 4) != (((words[13] + 8) & 0xfffffff) <= 16) or
                    (mask & 4 and bool(mask & 8) != (ay < ax and (ax - ay) >> 23 >= 25)) or
                    (mask & 8 and bool(mask & 16) != ((words[14] & 0xfffffff) == 0)) or r['final'] != r['events'][-1][1:]):
                problem = 'trace contradicts branch guards'
        if problem:
            raise probekit.ProbeFailure(f'Native kernel record {row["id"]}: {problem}')
        records.append(r)
    return records


def kernel_coverage(records):
    """Required strata of the pinned branch structure; report unreachable paths explicitly."""
    counts = Counter({name: sum(bool(r['mask'] & flag) for r in records) for name, flag in BRANCHES.items()})
    accepted = [r for r in records if r['accepted'] and r['mask'] != 2048]
    products = Counter()
    for r in records:
        for tag, high, low in r['events']:
            if tag == TINY_PRODUCT:
                exponent, fraction = high >> 20 & 2047, ((high & 0xfffff) << 32) | low
                products['normal' if exponent else 'subnormal' if fraction else 'negative_zero' if high >> 31 else 'positive_zero'] += 1
    missing = [name for name in BRANCHES if name != 'tiny_increment' and not counts[name]]
    if {r['index'] for r in accepted} != set(range(8)) or {r['gt'] for r in accepted} != {0, 1}:
        missing.append('reduction-indices-or-magnitude-orders')
    missing += ['tiny-product-' + name for name in ('normal', 'subnormal', 'negative_zero') if not products[name]]
    if missing:
        raise probekit.ProbeFailure('Incomplete required kernel corpus coverage: ' + ', '.join(missing))
    return dict(branches=dict(counts), tiny_products=dict(products),
                unhit=['tiny_increment', 'tiny_nonboundary', 'correction_guard_false'],
                unhit_reason='RN-unreachable; implemented and exercised by the synthetic helper controls')


def historical_check(rows, records):
    """Pinned-source and Sun words on the 1,086 historical inputs equal the frozen record."""
    frozen = json.loads((REFERENCE / 'modern_atan2f_historical.json').read_text())
    results = [[r['id'], r['y'], r['x'], r['pinned'], r['sun']] for r in records[:1086]]
    differences = [row for row in results if row[3] != row[4]]
    if (len(results) != frozen['full_result_count'] or hash_json(results) != frozen['full_results_sha256']
            or differences != frozen['differences'] or [row[0] for row in differences] != frozen['difference_ids']):
        raise probekit.ProbeFailure('Pinned glibc/Sun historical words differ from the frozen record')
    return dict(rows=len(results), pinned_sun_differences=len(differences))


def apple_contract(row, record):
    """Apple2007 is host-qualified only in the legacy finite/normal domain: zero-or-normal
    inputs and native result. Host libm is not the Apple2007 source in gradual underflow."""
    return record['accepted'] and all(normal(word) for word in (row['y'], row['x'], record['native']))


def kernel_expected(rows, records, apple):
    """Expected candidate rows: modern packet words, then Sun/Apple legacy words for finite inputs."""
    expected = []
    for row, r in zip(rows, records):
        if r['accepted']:
            final = r['final']
            value, checked = [1, *final], [1, r['pinned']]
            legacy = dict(sun=r['sun'], apple=r['native'] if apple and apple_contract(row, r) else None)
        else:
            value, checked, legacy = [0, 1, 2, row['y'], row['x']], [0, 0], dict(sun=None, apple=None)
        modern = [row['id'], r['mask'], r['index'], r['gt'], *checked, *value, len(r['events'])]
        for tag, high, low in r['events']:
            modern += [tag, 1, high, low]
        expected.append(dict(modern=modern, **legacy))
    return expected


def parse_modern(values, row_id):
    """Framing of one serialized modern packet; checked words narrow the final binary64."""
    def value(offset):
        tag, first, second = values[offset:offset + 3]
        if tag == 1:
            if first >> 20 & 2047 == 2047:
                raise probekit.ProbeFailure('Nonfinite successful binary64 payload')
            return values[offset:offset + 3], offset + 3
        if tag != 0 or FAILURE_ARITIES.get(first) != second:
            raise probekit.ProbeFailure('Invalid failure operation/operand framing')
        return values[offset:offset + 3 + second], offset + 3 + second
    if (values[0] != row_id or values[1] & ~8191 or values[2] > 7 or values[3] > 1 or values[4] > 1
            or (not values[4] and values[5]) or (values[4] and values[5] >> 23 & 255 == 255)):
        raise probekit.ProbeFailure(f'Malformed modern packet header at {row_id}')
    try:
        final, offset = value(6)
        count, offset = values[offset], offset + 1
        for _ in range(count):
            if values[offset] not in TRACE_TAGS:
                raise probekit.ProbeFailure('Unknown trace event tag')
            _, offset = value(offset + 1)
    except (IndexError, ValueError):
        raise probekit.ProbeFailure(f'Truncated modern packet at {row_id}') from None
    if offset != len(values) or values[4:6] != ([1, narrow64(*final[1:])] if final[0] == 1 else [0, 0]):
        raise probekit.ProbeFailure(f'Unframed words or checked result not the narrowed final at {row_id}')
    return values


def kernel_program(selected, gpu=False):
    source = '''import Base
import ../../src/modern_angle.bend as A
import ../../src/binary64_fma.bend as F
import ../../src/angle.bend as L
def raw(value: U32) -> F32:
  U32{bits} = value
  F32{bits}
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
def legacy(finite: U32, +y: U32, +x: U32, rest: List<U32>) -> List<U32>:
  match finite:
    case 0: rest
    case _: Con{F32.bits(L.atan2(True{}, raw(y), raw(x))), Con{F32.bits(L.atan2(False{}, raw(y), raw(x))), rest}}
type AngleTask is Data:
  AngleTask{id: U32, y: U32, x: U32, finite: U32}
def emit(tasks: +List<AngleTask>) -> IO(Unit):
  match tasks:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{AngleTask{id, +y, +x, finite}, rest}:
      do IO<Unit>:
        IO.print(List.show(~&1, ~U32, ~U32.show, legacy(finite, y, x, observe(id, A.traced(y, x), A.checked(y, x)))))
        emit(rest)
def main() -> IO(Unit):
  emit(['''
    tasks = ','.join(f'AngleTask{{{r["id"]},{r["y"]},{r["x"]},{int(finite(r["y"]) and finite(r["x"]))}}}' for r in selected)
    return source + tasks + '])\n'


def parse_kernel(text, selected):
    out = []
    for line, row in zip(text.splitlines(), selected):
        values = json.loads(line)
        accepted = finite(row['y']) and finite(row['x'])
        legacy, modern = (values[:2], values[2:]) if accepted else ([None, None], values)
        out.append(dict(modern=parse_modern(modern, row['id']), sun=legacy[0], apple=legacy[1]))
    return out


def modern_synthetic():
    """Fixed direct-helper controls for RN-unreachable paths and failure propagation."""
    cases = []
    def value(word):
        return f'A.Good{{F.Words{{{word >> 32},{word & 0xffffffff}}}}}'
    def failure(operation, operands):
        return f'A.Failed{{{operation},[' + ','.join(map(str, operands)) + ']}'
    def put(expression, result, events=(), packet=False):
        checked = [1, narrow64(*result[1:])] if result[0] else [0, 0]
        expected = [len(cases), 0, 0, 0, *checked, *result, len(events)]
        for tag, event in events:
            expected += [tag, *event]
        cases.append(dict(expression=expression if packet else f'A.Packet{{{expression},0,0,0,Nil{{}}}}', expected=expected))
    for word, increment in ((0, True), (1, False), (0x3ff00000ffffffff, True), (0x3ff0000100000000, False),
                            (0xbff00000ffffffff, True), (0xbff0000100000000, False),
                            (0x8000000000000001, False), (0x8000000000000000, True)):
        result = (word + (1 if increment else -1)) & ((1 << 64) - 1)
        put(f'A.tiny.stepped({increment}{{}},{word >> 32},{word & 0xffffffff})', [1, result >> 32, result & 0xffffffff])
    one, zero, invalid = value(0x3ff0000000000000), value(0), value(0x7ff0000000000000)
    for name, operation in (('add', 4), ('sub', 20), ('mul', 10), ('div', 16), ('gradual', 88)):
        put(f'A.{name}({operation},{invalid},{one})', [0, operation, 4, 0x7ff00000, 0, 0x3ff00000, 0])
    put(f'A.fma(81,{invalid},{one},{zero})', [0, 81, 6, 0x7ff00000, 0, 0x3ff00000, 0, 0, 0])
    put('A.promote(2,2139095040)', [0, 2, 1, 0x7f800000])
    failed, failed_wire = failure(81, [1, 2, 3, 4, 5, 6]), [0, 81, 6, 1, 2, 3, 4, 5, 6]
    for name, operation in (('add', 4), ('sub', 20), ('mul', 10), ('div', 16), ('gradual', 88)):
        put(f'A.{name}({operation},{one},{failed})', failed_wire)
    for position in range(3):
        operands = [one, one, zero]; operands[position] = failed
        put('A.fma(81,' + ','.join(operands) + ')', failed_wire)
    put(f'A.add(4,{failure(16, [7, 8, 9, 10])},{failed})', [0, 16, 4, 7, 8, 9, 10])
    put(f'A.tiny.boundary({value(0x3ff0000000000001)},{failed},0,0,0,Nil{{}})', failed_wire, packet=True)
    put(f'A.general.prepare({failed},{zero},0,0,0,Nil{{}})', failed_wire, packet=True)
    final = [1, 0x3ff00000, 1]
    put(f'A.correction.compare.ready(False{{}},{one},{value(0x3cb0000000000000)},0,0,0,Nil{{}})', final, [(39, final)], packet=True)
    put('A.tiny.boundary.ready(False{},1072693248,1,A.Good{F.Words{0,0}},0,0,0,Nil{})', final, [(20, final)], packet=True)
    return cases


def modern_synthetic_program(selected, gpu=False):
    source = kernel_program([])[:kernel_program([]).index('type AngleTask')]
    source += ('def observe_synthetic(id: U32, +packet: A.Packet) -> List<U32>:\n'
               '  observe(id, packet, A.checked.packet(packet))\ndef main() -> IO(Unit):\n  do IO<Unit>:\n')
    for case in selected:
        source += f'    IO.print(List.show(~&1, ~U32, ~U32.show, observe_synthetic({case["expected"][0]}, {case["expression"]})))\n'
    return source


# ---------------------------------------------------------------- checked wrapper corpus
def round32(value, zero=0):
    """Exact RN-even including overflow to infinity and gradual underflow."""
    if not value:
        return zero
    sign = 0x80000000 if value < 0 else 0
    if abs(value) >= Fraction(2) ** 128 - Fraction(2) ** 103:
        return sign | 0x7f800000
    return rn(value)


def multiply(a, b):
    return round32(fp(a) * fp(b), (a ^ b) & 0x80000000)


def plus(a, b):
    return round32(fp(a) + fp(b), 0x80000000 if a == b == 0x80000000 else 0)


def minus(a, b):
    return plus(a, b ^ 0x80000000)


def square_root(word):
    if word & 0x7fffffff == 0:
        return word
    target, low, high = fp(word), 0, 0x7f7fffff
    if target < 0:
        raise ValueError('Negative rational square root')
    while low < high:
        middle = (low + high + 1) // 2
        if fp(middle) ** 2 <= target:
            low = middle
        else:
            high = middle - 1
    midpoint = (fp(low) + fp(low + 1)) / 2
    return low if target < midpoint ** 2 or (target == midpoint ** 2 and low % 2 == 0) else low + 1


def domain(row):
    """(first failing stage or 0, checked trace, atan2 pair) by exact rational arithmetic."""
    a, trace = row['args'], []
    if not all(map(finite, a)):
        return 1, trace, None
    class Rejected(Exception):
        pass
    def check(stage, value):
        trace.append([stage, value])
        if not normal(value):
            raise Rejected(stage)
        return value
    try:
        if row['api'] == 0:
            x, y, u, v = a
            p0 = check(10, multiply(x, u)); p1 = check(11, multiply(y, v)); dot = check(12, plus(p0, p1))
            q0 = check(13, multiply(x, v)); q1 = check(14, multiply(y, u)); det = check(15, minus(q0, q1))
            return 0, trace, [det, dot]
        if row['api'] == 1:
            return 0, trace, [check(10, minus(a[3], a[1])), check(11, minus(a[2], a[0]))]
        x, y, z, u, v, w = a
        products = [check(stage, multiply(a[i], a[j])) for stage, (i, j) in
                    enumerate(((1, 5), (2, 4), (2, 3), (0, 5), (0, 4), (1, 3)), 10)]
        cross = [check(stage, minus(products[i], products[i + 1])) for stage, i in enumerate((0, 2, 4), 16)]
        squares = [check(stage, multiply(value, value)) for stage, value in enumerate(cross, 19)]
        square = check(23, plus(check(22, plus(squares[0], squares[1])), squares[2]))
        length = check(25, square_root(square))
        p0 = check(26, multiply(x, u)); p1 = check(27, multiply(y, v)); p2 = check(28, multiply(z, w))
        return 0, trace, [length, check(30, plus(check(29, plus(p0, p1)), p2))]
    except Rejected as error:
        return error.args[0], trace, None


def wrapper_rows():
    """Frozen manifest wrapper controls, signed zeros, nonfinite fields and stage controls."""
    rows = []
    def put(api, args, label, frozen=None):
        rows.append(dict(id=len(rows), api=api, args=list(args), label=label, frozen=frozen))
    for row in profiles.load_manifest()['wrapper_controls']:
        put(APIS.index(row['api']), [int(v, 16) for v in row['args']], 'frozen-' + row['id'],
            {p: int(v, 16) for p, v in row['expected'].items()})
    one, half, minimum, maximum = 0x3f800000, 0x3f000000, 0x00800000, 0x7f7fffff
    for api, arity in enumerate(ARITIES):
        for signs in itertools.product((0, 0x80000000), repeat=arity):
            put(api, signs, 'all-signed-zeros-%d-%s' % (api, ''.join('1' if v else '0' for v in signs)))
        for position, special in itertools.product(range(arity), (0x7f800000, 0xff800000, 0x7fc00000, 0xffc00001, 0x7f800001, 0xff800001)):
            args = [one] * arity; args[position] = special
            put(api, args, f'nonfinite-api{api}-field{position}-{special:08x}')
    controls = [
        (0, [minimum, one, half, one], 'v2-dot-product-10'), (0, [0, minimum, 0, half], 'v2-dot-product-11'),
        (0, [minimum, minimum, one, 0xbf800001], 'v2-dot-cancellation-12'), (0, [minimum, one, one, half], 'v2-det-product-13'),
        (0, [one, minimum, half, one], 'v2-det-product-14'), (0, [minimum, minimum, one, 0x3f800001], 'v2-det-cancellation-15'),
        (0, [maximum, 0, 0x40000000, one], 'v2-product-overflow'), (0, [maximum, maximum, one, one], 'v2-dot-overflow'),
        (0, [maximum, maximum, 0xbf800000, one], 'v2-det-overflow'), (0, [0x3f800001, one, one, 0x3f7ffffe], 'fma-sensitive-determinant'),
        (1, [0, 0, 0x7f000000, one], 'output-only-subnormal'), (1, [0, 0, 0x7f000000, minimum], 'accepted-tiny-negative-zero'),
        (1, [one, minimum, 0x40000000, minimum + 1], 'line-subnormal-dy'), (1, [minimum, 0, minimum + 1, one], 'line-subnormal-dx'),
        (1, [maximum ^ 0x80000000, 0, maximum, one], 'line-overflow-dx'), (1, [0, maximum ^ 0x80000000, one, maximum], 'line-overflow-dy'),
        (2, [0, 0, one, 0x5f400000, 0xdf400000, 0], 'v3-first-length-sum-overflow-22'),
        (2, [one, 0xbf800000, 0, 0x5f200000, 0, 0xdf200000], 'v3-final-length-sum-overflow-23'),
        (2, [0, minimum, minimum, 0, one, 0x3f800001], 'v3-cross-cancellation-16'),
        (2, [minimum, 0, minimum, 0x3f800001, 0, one], 'v3-cross-cancellation-17'),
        (2, [minimum, minimum, 0, one, 0x3f800001, 0], 'v3-cross-cancellation-18'),
        (2, [0, one, 0, 0, 0, 0x1c800000], 'v3-square-subnormal-19'), (2, [0, 0, one, 0x1c800000, 0, 0], 'v3-square-subnormal-20'),
        (2, [one, 0, 0, one, 0x1c800000, 0], 'v3-square-subnormal-21'), (2, [one, 0, 0, 0, 0x62800000, 0], 'v3-square-overflow'),
        (2, [maximum, 0, 0, maximum, 0, 0], 'v3-dot-overflow-26'), (2, [0, maximum, 0, 0, maximum, 0], 'v3-dot-overflow-27'),
        (2, [0, 0, maximum, 0, 0, maximum], 'v3-dot-overflow-28'), (2, [maximum, maximum, 0, one, one, 0], 'v3-dot-sum-overflow-29'),
        (2, [0x7effffff] * 3 + [one] * 3, 'v3-dot-sum-overflow-30'),
        (2, [0xcb800000, 0x4b800000, one, one, one, one], 'left-associated-dot'),
        (2, [0, one, 0xbf800000, 0xb9800000, 0x3f5364be, 0x3ea6c97c], 'left-associated-squares'),
        (0, [1, 0, 0, 0], 'subnormal-input-accepted-zero-products'), (0, [1, 0, 0x7e800000, 0], 'subnormal-input-accepted-normal-product'),
        (0, [minimum, 0, minimum, 0], 'underflow-to-zero-allowed'), (2, [1, 0, 0, 0, 0, 0], 'v3-subnormal-input-accepted-zero-products'),
        (1, [1, 0, 0x00800001, one], 'line-subnormal-input-normal-difference'),
    ]
    for stage, (i, j) in enumerate(((1, 5), (2, 4), (2, 3), (0, 5), (0, 4), (1, 3)), 10):
        args = [0] * 6; args[i] = minimum; args[j] = half
        controls.append((2, args, f'v3-cross-product-subnormal-{stage}'))
    for api, args, label in controls:
        put(api, args, label)
    required = ({1, *range(10, 16)}, {1, 10, 11}, {1, *range(10, 24), *range(26, 31)})
    for api, stages in enumerate(required):
        if {domain(row)[0] for row in rows if row['api'] == api} - {0} != stages:
            raise probekit.ProbeFailure('Incomplete reachable wrapper stage coverage')
    return rows


def wrapper_native_source(rows, profile):
    """Ordered checked mirror plus original raymath, both with atan2f routed to one kernel."""
    if profile == 'Apple2007AngleRn':
        kernel = ('static float (*volatile host_atan2f)(float,float) = atan2f;\n'
                  'static float kernel_atan2f(float y, float x) { return host_atan2f(y, x); }\n')
    else:
        kernel = f'float kernel_atan2f(float,float);\n'
    table = ',\n'.join('{' + ','.join(f'{v}u' for v in [r['id'], r['api'], *r['args'], *[0] * (6 - len(r['args']))]) + '}' for r in rows)
    return r'''#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#pragma STDC FENV_ACCESS ON
#pragma STDC FP_CONTRACT OFF
''' + kernel + r'''#define atan2f kernel_atan2f
#define RAYMATH_STATIC_INLINE
#include "raymath.h"
static uint32_t bits(float x) { uint32_t w; memcpy(&w,&x,4); return w; }
static float raw(uint32_t w) { float x; memcpy(&x,&w,4); return x; }
static int normal(float x) { uint32_t w=bits(x)&0x7fffffffu; return !w || (w>=0x00800000u && w<0x7f800000u); }
typedef struct { uint32_t tag,stage,value,scalar,count,trace[64]; } Observation;
static int take(Observation *r,uint32_t stage,float value) {
  r->trace[2*r->count]=stage; r->trace[2*r->count+1]=bits(value); ++r->count;
  if (!normal(value)) { r->stage=stage; return 0; } return 1;
}
#define STEP(name,stage,expression) float name=(expression); if (!take(&r,stage,name)) goto finish
static Observation ordered(uint32_t api, const uint32_t *words) {
  Observation r={0};
  for (unsigned i=0;i<(api==2?6u:4u);++i)
    if ((words[i]&0x7fffffffu)>=0x7f800000u) { r.stage=1; return r; }
  float yarg=0,xarg=0;
  if (api==0) {
    float x=raw(words[0]),y=raw(words[1]),u=raw(words[2]),v=raw(words[3]);
    STEP(p0,10,x*u); STEP(p1,11,y*v); STEP(dot,12,p0+p1);
    STEP(q0,13,x*v); STEP(q1,14,y*u); STEP(det,15,q0-q1);
    yarg=det; xarg=dot;
  } else if (api==1) {
    float x=raw(words[0]),y=raw(words[1]),u=raw(words[2]),v=raw(words[3]);
    STEP(dy,10,v-y); STEP(dx,11,u-x); yarg=dy; xarg=dx;
  } else {
    float x=raw(words[0]),y=raw(words[1]),z=raw(words[2]),u=raw(words[3]),v=raw(words[4]),w=raw(words[5]);
    STEP(a0,10,y*w); STEP(a1,11,z*v); STEP(b0,12,z*u); STEP(b1,13,x*w); STEP(c0,14,x*v); STEP(c1,15,y*u);
    STEP(cx,16,a0-a1); STEP(cy,17,b0-b1); STEP(cz,18,c0-c1);
    STEP(sx,19,cx*cx); STEP(sy,20,cy*cy); STEP(sz,21,cz*cz);
    STEP(sxy,22,sx+sy); STEP(square,23,sxy+sz);
    if (!(square>=0.0f)) { r.stage=24; goto finish; }
    STEP(length,25,sqrtf(square));
    STEP(p0,26,x*u); STEP(p1,27,y*v); STEP(p2,28,z*w);
    STEP(dxy,29,p0+p1); STEP(dot,30,dxy+p2); yarg=length; xarg=dot;
  }
  {
    float scalar=kernel_atan2f(yarg,xarg); r.scalar=bits(scalar);
    if (!take(&r,32,scalar)) goto finish;
    float result=scalar;
    if (api==1) { result=-scalar; if (!take(&r,33,result)) goto finish; }
    r.tag=1; r.value=bits(result);
  }
finish: return r;
}
__attribute__((noinline)) static float original(uint32_t api,const uint32_t *words) {
  if (api==0) { Vector2 a={raw(words[0]),raw(words[1])},b={raw(words[2]),raw(words[3])}; return Vector2Angle(a,b); }
  if (api==1) { Vector2 a={raw(words[0]),raw(words[1])},b={raw(words[2]),raw(words[3])}; return Vector2LineAngle(a,b); }
  Vector3 a={raw(words[0]),raw(words[1]),raw(words[2])},b={raw(words[3]),raw(words[4]),raw(words[5])};
  return Vector3Angle(a,b);
}
static volatile uint32_t inputs[][8]={''' + table + r'''};
int main(void) {
  for (unsigned row=0;row<sizeof(inputs)/sizeof(inputs[0]);++row) {
    uint32_t values[8]; for (unsigned i=0;i<8;++i) values[i]=inputs[row][i];
    uint32_t api=values[1];
    Observation r=ordered(api,values+2);
    printf("[%u,%u,%u,%u,%u,%u,%u",values[0],r.tag,r.stage,r.value,bits(original(api,values+2)),r.scalar,r.count);
    for (unsigned i=0;i<2*r.count;++i) printf(",%u",r.trace[i]);
    puts("]");
  }
  return 0;
}
'''


def parse_wrapper_native(text, rows, profile):
    """Ordered mirror and original raymath must agree with exact rational stages and each other."""
    lines = text.splitlines()
    if len(lines) != len(rows):
        raise probekit.ProbeFailure('Wrong native wrapper observation count')
    records = []
    for line, row in zip(lines, rows):
        value = json.loads(line)
        row_id, tag, stage, result, actual, scalar, count = value[:7]
        trace = [value[i:i + 2] for i in range(7, len(value), 2)]
        fail, expected, pair = domain(row)
        if row_id != row['id'] or len(trace) != count:
            raise probekit.ProbeFailure('Native wrapper framing/order mismatch')
        if fail:
            ok = [tag, stage, result, scalar] == [0, fail, 0, 0] and trace == expected
        else:
            final = scalar ^ (0x80000000 if row['api'] == 1 else 0)
            expected = expected + [[32, scalar]] + ([[33, final]] if row['api'] == 1 and normal(scalar) else [])
            ok = (finite(scalar) and trace == expected and actual == final and
                  [tag, stage, result] == ([1, 0, final] if normal(scalar) else [0, 32, 0]))
            if row['frozen'] is not None and actual != row['frozen'][profile]:
                raise probekit.ProbeFailure(f'{profile} raymath differs from frozen control {row["label"]}')
        if not ok:
            raise probekit.ProbeFailure(f'{profile} raymath/ordered mirror/exact domain disagree at {row["label"]}')
        records.append(dict(private=[tag, stage, result], public=[tag, result], actual=actual, valid=pair is not None))
    return records


def wrapper_program(selected, gpu=False):
    source = '''import Base
import ../../jonmath.bend as M
import ../../src/checked_angle.bend as C
import ../../src/angle.bend as LA
def raw(value: U32) -> F32:
  U32{bits} = value
  F32{bits}
def pack(value: Result<&2, &2, U32, F32>, rest: List<U32>) -> List<U32>:
  match value:
    case Fail{stage}: Con{0, Con{stage, Con{0, rest}}}
    case Done{value}: Con{1, Con{0, Con{F32.bits(value), rest}}}
def maybe(value: Maybe<F32>, rest: List<U32>) -> List<U32>:
  match value:
    case None{}: Con{0, Con{0, rest}}
    case Some{value}: Con{1, Con{F32.bits(value), rest}}
def reference(profile: U32) -> M.Libm:
  match profile:
    case 0: M.AppleLibm{}
    case 1: M.Glibc239Libm{}
    case _: M.Glibc241Libm{}
# Unchecked Apple/Sun kernels as raymath's legacy wrappers compute them.
def line.legacy(gnu: Bool, start: M.Vector2, end: M.Vector2) -> F32:
  M.Vector2{x, y} = start
  M.Vector2{u, v} = end
  F32.neg(LA.atan2(gnu, (v - y : F32), (u - x : F32)))
def legacy2(enabled: U32, line: U32, +left: M.Vector2, +right: M.Vector2) -> List<U32>:
  match enabled:
    case 0: [0,0,0,0]
    case _:
      match line:
        case 0: [1,F32.bits(LA.atan2(False{},M.Vector2.cross_product(left,right),M.Vector2.dot_product(left,right))),F32.bits(LA.atan2(True{},M.Vector2.cross_product(left,right),M.Vector2.dot_product(left,right))),F32.bits(M.Vector2.angle(left,right))]
        case _: [1,F32.bits(line.legacy(False{},left,right)),F32.bits(line.legacy(True{},left,right)),F32.bits(M.Vector2.line_angle(left,right))]
def legacy3(enabled: U32, +left: M.Vector3, +right: M.Vector3) -> List<U32>:
  match enabled:
    case 0: [0,0,0,0]
    case _: [1,F32.bits(LA.atan2(False{},M.Vector3.length(M.Vector3.cross_product(left,right)),M.Vector3.dot_product(left,right))),F32.bits(LA.atan2(True{},M.Vector3.length(M.Vector3.cross_product(left,right)),M.Vector3.dot_product(left,right))),F32.bits(M.Vector3.angle(left,right))]
def angle2(+profile: U32, +x: F32, +y: F32, +u: F32, +v: F32, rest: List<U32>) -> List<U32>:
  +left = {M.Vector2{x,y} : M.Vector2}
  +right = {M.Vector2{u,v} : M.Vector2}
  pack(C.vector2(profile,x,y,u,v), maybe(M.Vector2.angle_for(reference(profile),left,right), rest))
def line2(+profile: U32, +x: F32, +y: F32, +u: F32, +v: F32, rest: List<U32>) -> List<U32>:
  +left = {M.Vector2{x,y} : M.Vector2}
  +right = {M.Vector2{u,v} : M.Vector2}
  pack(C.line(profile,x,y,u,v), maybe(M.Vector2.line_angle_for(reference(profile),left,right), rest))
def profile3(+profile: U32, +x: F32, +y: F32, +z: F32, +u: F32, +v: F32, +w: F32, rest: List<U32>) -> List<U32>:
  +left = {M.Vector3{x,y,z} : M.Vector3}
  +right = {M.Vector3{u,v,w} : M.Vector3}
  pack(C.vector3(profile,x,y,z,u,v,w), maybe(M.Vector3.angle_for(reference(profile),left,right), rest))
def observe.api(api: U32, id: U32, legacy: U32, +x: F32, +y: F32, +z: F32, +u: F32, +v: F32, +w: F32) -> List<U32>:
  match api:
    case 0:
      +left = {M.Vector2{x,y} : M.Vector2}
      +right = {M.Vector2{u,v} : M.Vector2}
      Con{id,angle2(0,x,y,u,v,angle2(1,x,y,u,v,angle2(2,x,y,u,v,legacy2(legacy,0,left,right))))}
    case 1:
      +left = {M.Vector2{x,y} : M.Vector2}
      +right = {M.Vector2{u,v} : M.Vector2}
      Con{id,line2(0,x,y,u,v,line2(1,x,y,u,v,line2(2,x,y,u,v,legacy2(legacy,1,left,right))))}
    case _:
      +left = {M.Vector3{x,y,z} : M.Vector3}
      +right = {M.Vector3{u,v,w} : M.Vector3}
      Con{id,profile3(0,x,y,z,u,v,w,profile3(1,x,y,z,u,v,w,profile3(2,x,y,z,u,v,w,legacy3(legacy,left,right))))}
type Task is Data:
  Task{id: U32, api: U32, legacy: U32, x: U32, y: U32, z: U32, u: U32, v: U32, w: U32}
def observe(task: Task) -> List<U32>:
  Task{id,api,legacy,x,y,z,u,v,w} = task
  observe.api(api,id,legacy,raw(x),raw(y),raw(z),raw(u),raw(v),raw(w))
def emit(tasks: +List<Task>) -> IO(Unit):
  match tasks:
    case Nil{}: IO.pure(Unit, Unit{})
    case Con{task,rest}:
      do IO<Unit>:
        IO.print(List.show(~&1, ~U32, ~U32.show, observe(task)))
        emit(rest)
def main() -> IO(Unit):
  emit(['''
    tasks = []
    for row in selected:
        args = row['args'] if row['api'] == 2 else [*row['args'][:2], 0, *row['args'][2:], 0]
        tasks.append('Task{' + ','.join(map(str, [row['id'], row['api'], int(domain(row)[0] == 0), *args])) + '}')
    return source + ','.join(tasks) + '])\n'


def wrapper_consistency(row, values):
    """Profile-independent invariants of one candidate row (also covers hosts without Apple)."""
    if len(values) != 20 or values[0] != row['id']:
        raise probekit.ProbeFailure(f'Wrong wrapper row shape at {row["label"]}')
    legacy = values[16:20]
    for p, profile in enumerate(PROFILES):
        tag, stage, word, present, payload = values[1 + 5 * p:6 + 5 * p]
        if [present, payload] != [tag, word] or (tag and (stage or not normal(word))) or (not tag and (stage not in STAGES[row['api']] or word)):
            raise probekit.ProbeFailure(f'{profile} public/private checked result mismatch at {row["label"]}')
        if p < 2 and legacy[0] and [present, payload] != ([1, legacy[1 + p]] if normal(legacy[1 + p]) else [0, 0]):
            raise probekit.ProbeFailure(f'{profile} checked result differs from the retained legacy API at {row["label"]}')
        if row['frozen'] is not None and legacy[0] and [present, payload] != ([1, row['frozen'][profile]] if normal(row['frozen'][profile]) else [0, 0]):
            raise probekit.ProbeFailure(f'{profile} checked result differs from frozen control {row["label"]}')
    if legacy[0] and (legacy[3] != legacy[1] or (row['frozen'] is not None and legacy[1:3] != [row['frozen'][p] for p in PROFILES[:2]])):
        raise probekit.ProbeFailure(f'Legacy default/frozen control mismatch at {row["label"]}')
    if not legacy[0] and (any(values[4:6]) or any(values[9:11]) or any(values[14:16]) or any(legacy)):
        raise probekit.ProbeFailure(f'Pre-scalar rejection accepted at {row["label"]}')
    return values


def wrapper_expected(rows, native):
    """Candidate layout: id, (private tag/stage/word, public tag/word) per profile, legacy flag/Apple/Sun/default."""
    expected = []
    for i, row in enumerate(rows):
        values = [row['id']]
        for profile in PROFILES:
            record = native[profile][i] if profile in native else None
            values += record['private'] + record['public'] if record else [None] * 5
        valid = domain(row)[0] == 0
        apple, sun = (native[p][i]['actual'] if valid and p in native else (0 if not valid else None) for p in PROFILES[:2])
        values += [int(valid), apple, sun, apple]
        expected.append(values)
    return expected


def checked_synthetic():
    cases = []
    def put(expression, tag, stage, value=0):
        cases.append(dict(expression=expression, expected=[len(cases), tag, stage, value]))
    put('C.scalar_result(None{})', 0, 31)
    for value in (1, 0x80000001, 0x7f800000, 0xff800000, 0x7fc00001, 0x7f800001):
        put(f'C.scalar_result(Some{{{value}}})', 0, 32)
    for value in (0xbf800000, 0x80800000, 1, 0x7f800000, 0xff800000, 0x7fc00001, 0x7f800001):
        put(f'C.sqrt(raw({value}))', 0, 24)
    for value in (0, 0x80000000, 0x3f800000, 0x00800000):
        put(f'C.sqrt(raw({value}))', 1, 0, square_root(value))
    for stage in range(10, 34):
        put(f'C.normal({stage},raw(1))', 0, stage)
    for name, arity in (('vector2', 4), ('line', 4), ('vector3', 6)):
        put(f'C.{name}(3,' + ','.join(['raw(0)'] * arity) + ')', 0, 2)
    return cases


def checked_synthetic_program(selected, gpu=False):
    source = wrapper_program([])[:wrapper_program([]).index('def maybe(')] + 'def main() -> IO(Unit):\n  do IO<Unit>:\n'
    for case in selected:
        source += f'    IO.print(List.show(~&1, ~U32, ~U32.show, Con{{{case["expected"][0]},pack({case["expression"]},Nil{{}})}}))\n'
    return source


# ---------------------------------------------------------------- native oracle build
def build_oracle(probe):
    """Compile pinned sources once: kernel objects, the trace driver and per-profile wrappers."""
    work, include = probe.work, probe.work / 'include'
    include.mkdir(exist_ok=True)
    shims = {'libm-alias-finite.h': '#define libm_alias_finite(a,b)\n',
             'libm-alias-float.h': '#define libm_alias_float(a,b)\n',
             'math-underflow.h': '#define math_check_force_underflow(x) ((void)0)\n',
             'math_config.h': '#include "modern_atan2f_shim.h"\n',
             'math_private.h': '#include <stdint.h>\n#include <string.h>\nfloat __atanf(float);\n'
                               '#define GET_FLOAT_WORD(i,d) do { float f_=(d); uint32_t u_; memcpy(&u_,&f_,4); (i)=u_; } while (0)\n'
                               '#define SET_FLOAT_WORD(d,i) do { uint32_t u_=(i); float f_; memcpy(&f_,&u_,4); (d)=f_; } while (0)\n'}
    for name, text in shims.items():
        (include / name).write_text(text)
    cc = ['clang', *FLAGS, '-I' + str(REFERENCE), '-I' + str(include)]
    objects = {'glibc': (['-D__ieee754_atan2f=glibc241_atan2f'], REFERENCE / 'modern_atan2f_glibc241.c'),
               'sun-e': (['-D__ieee754_atan2f=sun239_atan2f', '-D__atanf=sun239_atanf'], REFERENCE / 'angle_sources/sun_e_atan2f.c'),
               'sun-s': (['-D__atanf=sun239_atanf'], REFERENCE / 'angle_sources/sun_s_atanf.c')}
    for name, (defines, source) in objects.items():
        probekit.run([*cc, *defines, '-c', source, '-o', work / f'{name}.o'])
    kernels = [work / f'{name}.o' for name in objects]
    driver = work / 'kernel-oracle'
    probekit.run([*cc, REFERENCE / 'modern_atan2f_driver.c', REFERENCE / 'modern_atan2f_adapted.c', *kernels, '-lm', '-o', driver])
    return cc, kernels, driver


def native_wrappers(probe, cc, kernels, rows, available):
    native = {}
    for profile in available:
        source, binary = probe.work / f'wrapper-{profile}.c', probe.work / f'wrapper-{profile}'
        source.write_text(wrapper_native_source(rows, profile))
        symbol = {'Sun239AngleRn': 'sun239_atan2f', 'Glibc241AngleRn': 'glibc241_atan2f'}.get(profile)
        defines = [f'-Dkernel_atan2f={symbol}'] if symbol else []
        probekit.run([*cc, *defines, '-I' + str(probe.args.raylib_source / 'src'), source,
                      *(kernels if symbol else []), '-lm', '-o', binary])
        native[profile] = parse_wrapper_native(probekit.run([binary]), rows, profile)
    return native


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('angle-kernel', args)
    try:
        host = profiles.angle_profile(args.raylib_source, probe.work / 'host-profile', probekit.run)
    except ValueError as error:  # the pinned-source gate does not depend on the host profile
        host = dict(selected_profile=None, error=str(error))
    apple = platform.system() == 'Darwin' and host['selected_profile'] == 'Apple2007AngleRn'
    available = (PROFILES if apple else PROFILES[1:])
    probe.report.update(host_profile=host, profiles=dict(pinned_source=list(PROFILES[1:]),
                        host_qualified=['Apple2007AngleRn'] if apple else [],
                        unverified=[] if apple else ['Apple2007AngleRn kernel/wrapper (needs a Darwin host selecting it)']))
    cc, kernels, driver = build_oracle(probe)

    rows = kernel_rows()
    (probe.work / 'kernel-inputs.txt').write_text(''.join(f'{r["id"]} {r["y"]:08x} {r["x"]:08x}\n' for r in rows))
    records = parse_kernel_native(probekit.run([driver, probe.work / 'kernel-inputs.txt']), rows)
    frozen = [(row, r) for row, r in zip(rows, records) if 'frozen' in row]
    for row, r in frozen:
        if [r['sun'], r['pinned']] != [row['frozen'][p] for p in PROFILES[1:]] or (apple and r['native'] != row['frozen'][PROFILES[0]]):
            raise probekit.ProbeFailure(f'Pinned kernel differs from frozen manifest control {row["labels"]}')
    probe.report.update(kernel_rows=len(rows), kernel_finite=sum(r['accepted'] for r in records),
                        historical=historical_check(rows, records), coverage=kernel_coverage(records),
                        host_pinned_differences=sum(r['accepted'] and r['native'] != r['pinned'] for r in records),
                        host_sun_differences=sum(r['accepted'] and r['native'] != r['sun'] for r in records))
    expected = kernel_expected(rows, records, apple)
    lanes = probe.candidates(kernel_program, rows, batch=KERNEL_BATCH, parse=parse_kernel)
    for row, values in zip(rows, lanes['cpu-1']):
        if 'frozen' in row and [values['sun'], values['apple']] != [row['frozen'][p] for p in PROFILES[1::-1]]:
            raise probekit.ProbeFailure(f'Legacy kernel differs from frozen manifest control {row["labels"]}')
    # Recorded, never compared: Apple outside its contract (or every Apple word without a Darwin oracle).
    probe.report['apple_outside_contract_differences'] = [
        dict(id=row['id'], y=f'{row["y"]:08x}', x=f'{row["x"]:08x}', native=f'{r["native"]:08x}', jonlib=f'{v["apple"]:08x}')
        for row, r, v in zip(rows, records, lanes['cpu-1'])
        if apple and r['accepted'] and not apple_contract(row, r) and v['apple'] != r['native']]
    lanes = {lane: [value if wanted['apple'] is not None else dict(value, apple=None) for wanted, value in zip(expected, values)]
             for lane, values in lanes.items()}
    probe.compare(expected, {f'kernel/{lane}': values for lane, values in lanes.items()},
                  lambda i: f'kernel row {rows[i]["id"]} {rows[i]["labels"][:2]} y={rows[i]["y"]:08x} x={rows[i]["x"]:08x}')

    cases = modern_synthetic()
    lanes = probe.candidates(modern_synthetic_program, cases, batch=len(cases))
    probe.compare([case['expected'] for case in cases], {f'modern-synthetic/{lane}': v for lane, v in lanes.items()})

    wrappers = wrapper_rows()
    native = native_wrappers(probe, cc, kernels, wrappers, available)
    expected = wrapper_expected(wrappers, native)
    lanes = probe.candidates(wrapper_program, wrappers, batch=WRAPPER_BATCH,
                             parse=lambda text, selected: [wrapper_consistency(row, json.loads(line))
                                                           for line, row in zip(text.splitlines(), selected)])
    lanes = {lane: [[None if e is None else v for e, v in zip(wanted, values)] for wanted, values in zip(expected, rows_)]
             for lane, rows_ in lanes.items()}  # profiles without a native oracle on this host
    probe.compare(expected, {f'wrapper/{lane}': values for lane, values in lanes.items()},
                  lambda i: f'wrapper {wrappers[i]["label"]}')

    cases = checked_synthetic()
    lanes = probe.candidates(checked_synthetic_program, cases, batch=len(cases))
    probe.compare([case['expected'] for case in cases], {f'checked-synthetic/{lane}': v for lane, v in lanes.items()})

    accepted = {p: sum(r['private'][0] for r in native[p]) for p in available}
    probe.finish(kernel_rows=len(rows), apple_kernel_rows=sum(e['apple'] is not None for e in kernel_expected(rows, records, apple)),
                 apple_outside_contract_differences=len(probe.report['apple_outside_contract_differences']),
                 wrapper_rows=len(wrappers), synthetic=len(cases) + len(modern_synthetic()),
                 compared_profiles='/'.join(p[:-7] for p in available), wrapper_accepted=accepted,
                 rejection_stages=dict(Counter(str(domain(row)[0]) for row in wrappers)))


if __name__ == '__main__':
    main()
