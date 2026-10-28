#!/usr/bin/env python3
"""Compare matrix arithmetic on exceptional and subnormal inputs.

Add, subtract, multiply, multiply-by-scalar and trace run with contraction off.
A fresh quiet NaN is folded to the canonical positive payload before an exact
comparison. A NaN propagated from one operand keeps that payload. The
distinctive payload 0x7FC00001 is outside this corpus: JavaScript stores every
NaN as the canonical positive quiet NaN. Every other field is bit-exact.
"""
import json

import probekit
import quiet_nan
from probekit import ProbeFailure

WORDS = (
    0x00000000, 0x80000000, 0x00000001, 0x00800000,
    0x3f800000, 0x7f800000, 0xff800000,
    0x7fc00000,
)
OPS = (
    ('add', 'MatrixAdd(A,B)', 'M.Matrix.add({a}, {b})'),
    ('subtract', 'MatrixSubtract(A,B)', 'M.Matrix.subtract({a}, {b})'),
    ('multiply', 'MatrixMultiply(A,B)', 'M.Matrix.multiply({a}, {b})'),
    ('multiply_value', 'MatrixMultiplyValue(A,s)', 'M.Matrix.multiply_value({a}, word({s}))'),
    ('trace', 'MatrixTrace(A)', 'M.Matrix.trace({a})'),
)


def pairs():
    return [(op, left, right) for left in WORDS for right in WORDS for op, _, _ in OPS]


def native(probe, rows):
    lines = [
        '#include <stdio.h>', '#include <string.h>',
        '#pragma STDC FP_CONTRACT OFF', '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,(void*)&u,4); sink+=u; return x;}',
        'static unsigned bits(float x){unsigned b; memcpy(&b,&x,4); return b;}',
        'static Matrix fill(unsigned w){float x=load(w); Matrix m;',
        '  m.m0=m.m1=m.m2=m.m3=m.m4=m.m5=m.m6=m.m7=m.m8=m.m9=m.m10=m.m11=m.m12=m.m13=m.m14=m.m15=x; return m;}',
        'static void emitm(Matrix m){printf("[%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u]\\n",',
        '  bits(m.m0),bits(m.m4),bits(m.m8),bits(m.m12),bits(m.m1),bits(m.m5),bits(m.m9),bits(m.m13),',
        '  bits(m.m2),bits(m.m6),bits(m.m10),bits(m.m14),bits(m.m3),bits(m.m7),bits(m.m11),bits(m.m15));}',
        'static void emit1(float x){printf("%u\\n", bits(x));}',
        'int main(void){',
    ]
    calls = {
        'add': 'emitm(MatrixAdd(A,B));',
        'subtract': 'emitm(MatrixSubtract(A,B));',
        'multiply': 'emitm(MatrixMultiply(A,B));',
        'multiply_value': 'emitm(MatrixMultiplyValue(A,s));',
        'trace': 'emit1(MatrixTrace(A));',
    }
    for op, left, right in rows:
        lines.append(f'  {{Matrix A=fill(0x{left:08x}u); Matrix B=fill(0x{right:08x}u); float s=load(0x{right:08x}u); {calls[op]}}}')
    lines.append('  (void)sink; return 0;}')
    return probe.native('\n'.join(lines) + '\n', 'matrix-arith', extra_flags=('-ffp-contract=off',), link_raylib=False)


PROGRAM = '''import Base
import ../../jonmath.bend as M
def word(bits: U32) -> F32:
  U32{b} = bits
  F32{b}
def filled(bits: U32) -> M.Matrix:
  +value = word(bits)
  M.Matrix{value, value, value, value, value, value, value, value, value, value, value, value, value, value, value, value}
def showm(value: M.Matrix) -> IO(Unit):
  M.Matrix{m0, m4, m8, m12, m1, m5, m9, m13, m2, m6, m10, m14, m3, m7, m11, m15} = value
  IO.print(List.show(~&1, ~U32, ~U32.show, [F32.bits(m0), F32.bits(m4), F32.bits(m8), F32.bits(m12), F32.bits(m1), F32.bits(m5), F32.bits(m9), F32.bits(m13), F32.bits(m2), F32.bits(m6), F32.bits(m10), F32.bits(m14), F32.bits(m3), F32.bits(m7), F32.bits(m11), F32.bits(m15)]))
def show1(value: F32) -> IO(Unit):
  IO.print(U32.show(F32.bits(value)))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def render(selected, gpu):
    body = PROGRAM
    bend = {
        'add': 'showm(M.Matrix.add(filled({left}), filled({right})))',
        'subtract': 'showm(M.Matrix.subtract(filled({left}), filled({right})))',
        'multiply': 'showm(M.Matrix.multiply(filled({left}), filled({right})))',
        'multiply_value': 'showm(M.Matrix.multiply_value(filled({left}), word({right})))',
        'trace': 'show1(M.Matrix.trace(filled({left})))',
    }
    for op, left, right in selected:
        body += f'    {bend[op].format(left=left, right=right)}\n'
    return body


def _cell(left, right):
    product = quiet_nan.reduce_binary('mul', left, right)
    return quiet_nan.reduce('add', quiet_nan.reduce('add', quiet_nan.reduce('add', product, product), product), product)


def _trace(left):
    return quiet_nan.reduce('add', quiet_nan.reduce('add', left, left), quiet_nan.reduce('add', left, left))


def _kind(op, left, right, index):
    if op == 'add':
        return quiet_nan.reduce_binary('add', left, right)
    if op == 'subtract':
        return quiet_nan.reduce_binary('sub', left, right)
    if op == 'multiply_value':
        return quiet_nan.reduce_binary('mul', left, right)
    if op == 'multiply':
        return _cell(left, right)
    if op == 'trace':
        return _trace(left)
    raise KeyError(op)


def _canon(op, left, right, value):
    kind = _kind(op, left, right, 0)
    def fold(item):
        if isinstance(item, list):
            return [fold(one) for one in item]
        if kind == quiet_nan.FRESH and quiet_nan.quiet(item):
            return 0x7FC00000
        # A four-term product or a diagonal sum does not keep one quiet-NaN
        # sign across fields. Upstream's own build changes it by field.
        if op in ('multiply', 'trace') and quiet_nan.quiet(item):
            return 0x7FC00000
        return item
    return fold(value)


def main():
    probe = probekit.Probe('matrix-arith', probekit.arguments(__doc__))
    rows = pairs()
    text = native(probe, rows)
    expected = [json.loads(line) for line in text.splitlines() if line.strip()]
    if len(expected) != len(rows):
        raise ProbeFailure(f'matrix-arith: native produced {len(expected)} rows for {len(rows)}')
    lanes = probe.candidates(render, rows, batch=20)
    lanes = {lane: values for lane, values in lanes.items() if lane != 'gpu'}
    def aligned(values):
        return [_canon(op, left, right, value) for (op, left, right), value in zip(rows, values)]
    expected_n = aligned(expected)
    lanes_n = {lane: aligned(values) for lane, values in lanes.items()}
    probe.compare(expected_n, lanes_n, describe=lambda i: f'{rows[i][0]} {tuple(hex(word) for word in rows[i][1:])}')
    probe.finish(cases=len(expected), pairs=len(rows))


if __name__ == '__main__':
    main()
