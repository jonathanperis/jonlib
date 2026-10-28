#!/usr/bin/env python3
"""Compare raymath's optional C++ operators with their Jonmath forms.

The pinned raymath.h is compiled as C++ with FP_CONTRACT off (the uncontracted
profile of the other raymath references) and every operator, including the
compound assignments, runs on finite inputs, zero divisors, nearly equal
pairs, subnormals, infinities and the canonical quiet-NaN payload. Same-type
operators are Bend's typed operator sugar, `(a - b : M.Vector3)`, which calls
Jonmath's T.add/T.sub/T.mul/T.div; scalar and matrix overloads and ==/!= are
the named functions the operators call. A compound assignment returns its
updated left operand, so it is the same Bend expression. Non-NaN results and
a single propagated canonical NaN payload stay bit-exact. A quiet NaN from an
invalid operation, or from two NaN operands, matches by NaN-ness before that
exact comparison.
"""
import hashlib
import json
import random
import struct
from pathlib import Path

from conformance import f32
import probekit
import quiet_nan
from probekit import ProbeFailure, run

SIZES = {'Vector2': 2, 'Vector3': 3, 'Vector4': 4, 'Quaternion': 4, 'Matrix': 16, 'float': 1}
MATRIX_FIELDS = ['m0', 'm4', 'm8', 'm12', 'm1', 'm5', 'm9', 'm13', 'm2', 'm6', 'm10', 'm14', 'm3', 'm7', 'm11', 'm15']


# Dotted Bend symbols the operators call. The strings are the names
# gate_evidence matches; the templates below are what the probe runs.
SCALE = {'Vector2': 'M.Vector2.scale', 'Vector3': 'M.Vector3.scale', 'Vector4': 'M.Vector4.scale'}
TRANSFORM = {'Vector2': 'M.Vector2.transform', 'Vector3': 'M.Vector3.transform'}
EQUALS = {'Vector2': 'M.Vector2.equals', 'Vector3': 'M.Vector3.equals', 'Vector4': 'M.Vector4.equals'}


def operators():
    """[(catalog name, C++ symbol, left type, right type, result type, Bend template)]."""
    rows = []

    def add(symbol, left, right, result, bend):
        right_c = f'const {right}&' if right != 'float' or left != 'Matrix' else 'const float'
        rows.append((f'operator{symbol}(const {left}&,{right_c})', symbol, left, right, result, bend))
        if symbol not in ('==', '!='):
            rows.append((f'operator{symbol}=({left}&,{right_c})', symbol + '=', left, right, result, bend))

    for name in ('Vector2', 'Vector3', 'Vector4'):
        add('+', name, name, name, f'({{a}} + {{b}} : M.{name})')
        add('-', name, name, name, f'({{a}} - {{b}} : M.{name})')
        add('*', name, 'float', name, f'{SCALE[name]}({{a}}, {{b}})')
        # raylib 6.2: float * vector (no compound form)
        rows.append((f'operator*(const float&,const {name}&)', '*', 'float', name, name, f'{SCALE[name]}({{b}}, {{a}})'))
        add('*', name, name, name, f'({{a}} * {{b}} : M.{name})')
        if name != 'Vector4':
            add('*', name, 'Matrix', name, f'{TRANSFORM[name]}({{a}}, {{b}})')
        add('/', name, 'float', name, f'{SCALE[name]}({{a}}, (1.0 / {{b}} : F32))')
        add('/', name, name, name, f'({{a}} / {{b}} : M.{name})')
        add('==', name, name, 'bool', f'{EQUALS[name]}({{a}}, {{b}})')
        add('!=', name, name, 'bool', f'Bool.not({EQUALS[name]}({{a}}, {{b}}))')
    add('+', 'Quaternion', 'float', 'Quaternion', 'M.Quaternion.add_value({a}, {b})')
    add('-', 'Quaternion', 'float', 'Quaternion', 'M.Quaternion.subtract_value({a}, {b})')
    add('*', 'Quaternion', 'Matrix', 'Quaternion', 'M.Quaternion.transform({a}, {b})')
    add('+', 'Matrix', 'Matrix', 'Matrix', '({a} + {b} : M.Matrix)')
    add('-', 'Matrix', 'Matrix', 'Matrix', '({a} - {b} : M.Matrix)')
    add('*', 'Matrix', 'Matrix', 'Matrix', '({a} * {b} : M.Matrix)')
    add('*', 'Matrix', 'float', 'Matrix', 'M.Matrix.multiply_value({a}, {b})')
    return rows


def fp(value):
    return struct.unpack('f', struct.pack('f', value))[0]


# Subnormals, both infinities, and the canonical quiet-NaN payload. Each
# operand is filled with one word so every component sees the same exceptional
# value. A negative quiet NaN (0xFFC00000) and a distinctive payload
# (0x7FC00001) are not in this corpus: constructing either F32 on the
# JavaScript lane yields the canonical positive quiet NaN 0x7FC00000, so an
# exact three-lane comparison cannot carry them. That canonicalization stays
# the gap on the matrix entries that already record it.
BIT_WORDS = (
    0x00000000, 0x80000000, 0x00000001, 0x00800000,
    0x3f800000, 0xbf800000, 0x7f800000, 0xff800000,
    0x7fc00000,
)


def cases(ops):
    rng = random.Random(0x0B5)
    result = []
    for op in ops:
        name, symbol, left, right, _, _ = op
        values = lambda kind: [fp(rng.uniform(-100, 100)) for _ in range(SIZES[kind])]
        for index in range(6):
            a, b = values(left), values(right)
            if symbol.startswith(('==', '!=')) and index < 3:
                # Equal, one-ULP-apart and epsilon-scale-apart pairs.
                b = [fp(x * (1 + (0, 2 ** -23, 1e-6)[index])) for x in a]
            if symbol.startswith('/') and index == 0:
                b = [0.0] * len(b)
            result.append((op, a, b))
        for left_word in BIT_WORDS:
            for right_word in BIT_WORDS:
                result.append((op, [left_word] * SIZES[left], [right_word] * SIZES[right]))
    return result


def bits(values):
    return isinstance(values[0], int)


def c_value(kind, values):
    if bits(values):
        if kind == 'float':
            return f'load(0x{values[0]:08x}u)'
        return kind + '{' + ','.join(f'load(0x{word:08x}u)' for word in values) + '}'
    if kind == 'float':
        return values[0].hex() + 'f'
    return f'{kind}{{' + ','.join(v.hex() + 'f' for v in values) + '}'


def libstdcxx_flags():
    """Headers for the g++ that is installed.

    clang++ 18 on a host whose libstdc++ is older than the version it was
    built to search does not find <cstdio> on its default path. The extra
    includes follow `g++ -dumpversion`, so a host whose g++ matches clang
    (GCC 14 in CI, GCC 13 here) resolves the same headers clang would have
    used.
    """
    version = run(['g++', '-dumpversion']).strip().split('.')[0]
    triple = run(['g++', '-dumpmachine']).strip()
    flags = []
    for path in (f'/usr/include/c++/{version}', f'/usr/include/{triple}/c++/{version}'):
        if Path(path).is_dir():
            flags.append('-I' + path)
    return flags


def native(probe, rows):
    lines = ['#include <cstdio>', '#include <cstring>', '#include <cstdlib>', '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"',
             'static unsigned sink;',
             'static float load(unsigned bits){volatile unsigned u=bits; unsigned copy=u; float x; std::memcpy(&x,&copy,4); sink+=copy; return x;}',
             'static unsigned bits(float x){unsigned b;std::memcpy(&b,&x,4);return b;}',
             'static void words(const float *v,int n){std::printf("[");for(int i=0;i<n;i++)std::printf("%s%u",i?",":"",bits(v[i]));std::puts("]");}',
             'static void emit(Vector2 v){float f[]={v.x,v.y};words(f,2);}',
             'static void emit(Vector3 v){float f[]={v.x,v.y,v.z};words(f,3);}',
             'static void emit(Vector4 v){float f[]={v.x,v.y,v.z,v.w};words(f,4);}',
             'static void emit(Matrix m){float f[]={' + ','.join('m.' + field for field in MATRIX_FIELDS) + '};words(f,16);}',
             'static void emit(bool b){std::puts(b?"true":"false");}',
             'int main(void){']
    for (_, symbol, left, right, _, _), a, b in rows:
        if symbol.endswith('=') and symbol not in ('==', '!='):
            lines.append(f'{{{left} x={c_value(left, a)};const {left}& r=(x {symbol} {c_value(right, b)});if(&r!=&x)std::abort();emit(x);}}')
        else:
            lines.append(f'emit({c_value(left, a)} {symbol} {c_value(right, b)});')
    source, binary = probe.work / 'reference.cpp', probe.work / 'reference'
    source.write_text('\n'.join(lines + ['(void)sink; return 0;}']) + '\n')
    run(['clang++', '-std=c++17', '-O2', '-ffp-contract=off', *libstdcxx_flags(),
         '-I' + str(probe.args.raylib_source / 'src'), source, '-o', binary])
    return run([binary])


PROGRAM = '''import Base
import ../../jonmath.bend as M
def word(bits: U32) -> F32:
  U32{b} = bits
  F32{b}
def words(values: List<F32>) -> IO(Unit):
  IO.print(List.show(~&1, ~U32, ~U32.show, List.map(~F32, ~U32, ~F32.bits, values)))
def v2(value: M.Vector2) -> IO(Unit):
  M.Vector2{x, y} = value
  words([x, y])
def v3(value: M.Vector3) -> IO(Unit):
  M.Vector3{x, y, z} = value
  words([x, y, z])
def v4(value: M.Vector4) -> IO(Unit):
  M.Vector4{x, y, z, w} = value
  words([x, y, z, w])
def matrix(value: M.Matrix) -> IO(Unit):
  M.Matrix{m0, m4, m8, m12, m1, m5, m9, m13, m2, m6, m10, m14, m3, m7, m11, m15} = value
  words([m0, m4, m8, m12, m1, m5, m9, m13, m2, m6, m10, m14, m3, m7, m11, m15])
def boolean(value: Bool) -> IO(Unit):
  match value:
    case True{}: IO.print("true")
    case False{}: IO.print("false")
def main() -> IO(Unit):
  do IO<Unit>:
'''
EMITTERS = {'Vector2': 'v2', 'Vector3': 'v3', 'Vector4': 'v4', 'Quaternion': 'v4', 'Matrix': 'matrix', 'bool': 'boolean'}
BEND_TYPES = {'Vector2': 'M.Vector2', 'Vector3': 'M.Vector3', 'Vector4': 'M.Vector4', 'Quaternion': 'M.Vector4', 'Matrix': 'M.Matrix'}


def bend_value(kind, values):
    if bits(values):
        if kind == 'float':
            return f'word({values[0]})'
        return BEND_TYPES[kind] + '{' + ', '.join(f'word({word})' for word in values) + '}'
    if kind == 'float':
        return f32(values[0])
    return BEND_TYPES[kind] + '{' + ', '.join(f32(v) for v in values) + '}'


def _base(symbol):
    if symbol in ('==', '!='):
        return symbol
    return symbol[0]


def combine(op, left, right):
    """One arithmetic step. A fresh NaN stays fresh; two NaNs are fresh."""
    if left == quiet_nan.FRESH or right == quiet_nan.FRESH:
        return quiet_nan.FRESH
    return quiet_nan.reduce_binary(op, left, right)


def chain(terms):
    acc = terms[0]
    for term in terms[1:]:
        acc = combine('add', acc, term)
    return acc


def result_kinds(symbol, left, right, a, b):
    """Per-result-component kind for a uniform bit case. None keeps every bit.

    Component add, subtract, multiply, divide and scale follow Sse: one NaN
    operand keeps that payload, and an invalid operation or two NaN operands
    is a fresh quiet NaN. Vector and quaternion transforms are the reference
    left-associated sums, including Vector2's explicit zero-Z term.
    """
    op = _base(symbol)
    if op in ('==', '!='):
        return None
    if left == 'Matrix' and right == 'Matrix' and op == '*':
        product = quiet_nan.reduce_binary('mul', a[0], b[0])
        # Same left-associated four-term sum as raymath and Matrix.product.cell.
        return [chain([product, product, product, product])] * 16
    if right == 'Matrix' and op == '*':
        matrix, vector = b[0], a[0]
        product = quiet_nan.reduce_binary('mul', matrix, vector)
        if left == 'Vector2':
            # m0*x + m4*y + m8*0 + m12
            mixed = chain([product, product, quiet_nan.reduce_binary('mul', matrix, 0), matrix])
        elif left == 'Vector3':
            # m0*x + m4*y + m8*z + m12
            mixed = chain([product, product, product, matrix])
        else:
            # Quaternion: m0*x + m4*y + m8*z + m12*w
            mixed = chain([product, product, product, product])
        return [mixed] * SIZES[left]
    if left == 'float' and op == '*':
        return [combine('mul', b[i], a[0]) for i in range(len(b))]
    if right == 'float' and op == '*':
        return [combine('mul', a[i], b[0]) for i in range(len(a))]
    if right == 'float' and op == '/':
        inverse = quiet_nan.reduce_binary('div', 0x3f800000, b[0])
        return [combine('mul', a[i], inverse) for i in range(len(a))]
    if right == 'float' and op in ('+', '-'):
        arith = 'add' if op == '+' else 'sub'
        return [combine(arith, a[i], b[0]) for i in range(len(a))]
    arith = {'+': 'add', '-': 'sub', '*': 'mul', '/': 'div'}[op]
    return [combine(arith, a[i], b[i]) for i in range(len(a))]


def canon(symbol, left, right, a, b, value):
    if not bits(a) or not isinstance(value, list):
        return value
    kinds = result_kinds(symbol, left, right, a, b)
    if kinds is None or len(kinds) != len(value):
        return value
    out = []
    for word, kind in zip(value, kinds):
        if kind == quiet_nan.FRESH and quiet_nan.quiet(word):
            out.append(0x7fc00000)
        else:
            out.append(word)
    return out


def render(selected, gpu):
    body = PROGRAM
    for (_, _, left, right, result, bend), a, b in selected:
        body += f'    {EMITTERS[result]}({bend.format(a=bend_value(left, a), b=bend_value(right, b))})\n'
    return body


def main():
    probe = probekit.Probe('operators', probekit.arguments(__doc__))
    ops = operators()
    names = {name for name, *_ in ops}
    catalog = json.loads((probekit.ROOT / 'api/reference.json').read_text())['entries']
    catalog = catalog if isinstance(catalog, list) else list(catalog.values())
    declared = {row['name'] for row in catalog if row['header'] == 'raymath.h' and row['kind'] == 'operator'}
    if names != declared:
        raise ProbeFailure(f'operators: mapping and catalog differ: {sorted(names ^ declared)}')
    rows = cases(ops)
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines()]
    if len(expected) != len(rows):
        raise ProbeFailure('operators: incomplete native output')
    lanes = probe.candidates(render, rows, batch=200, source_limit=80000)
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}

    def normalized(values):
        return [canon(op[1], op[2], op[3], a, b, value) for (op, a, b), value in zip(rows, values)]

    expected_n = normalized(expected)
    lanes_n = {lane: normalized(values) for lane, values in lanes.items()}
    probe.compare(expected_n, lanes_n, describe=lambda i: f'{rows[i][0][0]} #{i}')
    fresh = sum(left != right for left, right in zip(expected, expected_n) if isinstance(right, list))
    probe.finish(operators=len(ops), cases=len(rows), bit_cases=sum(bits(a) for _, a, _ in rows),
                 fresh_nan_rows=fresh, true_comparisons=sum(row is True for row in expected),
                 inputs_sha256=hashlib.sha256(json.dumps([(op[0], a, b) for op, a, b in rows]).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
