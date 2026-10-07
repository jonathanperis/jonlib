#!/usr/bin/env python3
"""Compare raymath's optional C++ operators with their Jonmath forms.

The pinned raymath.h is compiled as C++ with FP_CONTRACT off (the uncontracted
profile of the other raymath references) and every operator, including the
compound assignments, runs on finite inputs, zero divisors and nearly equal
pairs. Same-type operators are Bend's typed operator sugar, `(a - b : M.Vector3)`,
which calls Jonmath's T.add/T.sub/T.mul/T.div; scalar and matrix overloads and
==/!= are the named functions the operators call. A compound assignment
returns its updated left operand, so it is the same Bend expression. Every
result bit is compared on CPU-1, CPU-2 and JavaScript.
"""
import hashlib
import json
import random
import struct

from conformance import f32
import probekit
from probekit import ProbeFailure, run

SIZES = {'Vector2': 2, 'Vector3': 3, 'Vector4': 4, 'Quaternion': 4, 'Matrix': 16, 'float': 1}
MATRIX_FIELDS = ['m0', 'm4', 'm8', 'm12', 'm1', 'm5', 'm9', 'm13', 'm2', 'm6', 'm10', 'm14', 'm3', 'm7', 'm11', 'm15']


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
        add('*', name, 'float', name, f'M.{name}.scale({{a}}, {{b}})')
        add('*', name, name, name, f'({{a}} * {{b}} : M.{name})')
        if name != 'Vector4':
            add('*', name, 'Matrix', name, f'M.{name}.transform({{a}}, {{b}})')
        add('/', name, 'float', name, f'M.{name}.scale({{a}}, (1.0 / {{b}} : F32))')
        add('/', name, name, name, f'({{a}} / {{b}} : M.{name})')
        add('==', name, name, 'bool', f'M.{name}.equals({{a}}, {{b}})')
        add('!=', name, name, 'bool', f'Bool.not(M.{name}.equals({{a}}, {{b}}))')
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
    return result


def c_value(kind, values):
    if kind == 'float':
        return values[0].hex() + 'f'
    return f'{kind}{{' + ','.join(v.hex() + 'f' for v in values) + '}'


def native(probe, rows):
    lines = ['#include <cstdio>', '#include <cstring>', '#include <cstdlib>', '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"',
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
    source.write_text('\n'.join(lines + ['return 0;}']) + '\n')
    run(['clang++', '-std=c++17', '-O2', '-ffp-contract=off', '-I' + str(probe.args.raylib_source / 'src'), source, '-o', binary])
    return run([binary])


PROGRAM = '''import Base
import ../../jonmath.bend as M
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
    if kind == 'float':
        return f32(values[0])
    return BEND_TYPES[kind] + '{' + ', '.join(f32(v) for v in values) + '}'


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
    lanes = probe.candidates(render, rows, batch=120)
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    probe.compare(expected, lanes, describe=lambda i: f'{rows[i][0][0]} #{i}')
    probe.finish(operators=len(ops), cases=len(rows), true_comparisons=sum(row is True for row in expected),
                 inputs_sha256=hashlib.sha256(json.dumps([(op[0], a, b) for op, a, b in rows]).encode()).hexdigest(),
                 reference_sha256=hashlib.sha256(text.encode()).hexdigest())


if __name__ == '__main__':
    main()
