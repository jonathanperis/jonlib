"""Contracted-build rows shared by the raymath component probes.

Upstream's arm64 build (clang's default `-ffp-contract=on`) fuses each a*b + c
of one expression into one fused multiply-add. A probe that compares M.Fused{}
adds rows named `fused_<op>`, built here against the same raymath.h compiled
with contraction on. x86-64 builds without -mfma do not contract, so other
hosts have no contracted reference and skip the rows (`available`).

Rows are the probe's exceptional pairs (lerp over the probe's amounts) plus
seeded finite pairs with moderate exponents (no overflow in a product) and a
finite amount in [0, 1), where fusing changes the rounding. The contracted
reference is built at -O1, -O2 and -O3 and must print the same bits.
"""
import json
import platform
import random
import struct

from probekit import ProbeFailure, run


def available():
    return platform.machine() in ('arm64', 'aarch64')


def finite(rng):
    return (rng.getrandbits(1) << 31) | (rng.randrange(97, 158) << 23) | rng.getrandbits(23)


def unit(rng):
    return struct.unpack('<I', struct.pack('<f', rng.random()))[0]


def pairs(base, width, count, seed):
    """(argument words, amount or None): None takes every probe amount."""
    rng = random.Random(seed)
    rows = [(tuple(args), None) for args in base]
    for _ in range(count):
        rows.append((tuple(finite(rng) for _ in range(2 * width)), unit(rng)))
    return rows


def cases(rows, ops, lerps, amounts):
    """ops: (name, C expression, Bend def, shape, operands); lerps: (name, C function, Bend def)."""
    out = []
    for args, amount in rows:
        for op in ops:
            out.append(('fused_' + op[0], args))
        for name, _, _ in lerps:
            for value in (amounts if amount is None else (amount,)):
                out.append(('fused_' + name, args + (value,)))
    return out


def native(probe, ctype, width, rows, ops, lerps, amounts):
    """raymath with contraction on, printing rows in the order of `cases`."""
    fields = ', '.join(f'bits(f[{index}])' for index in range(width))
    lines = [
        '#include <stdio.h>', '#include <string.h>',
        '#define RAYMATH_STATIC_INLINE', '#include "raymath.h"',
        'static unsigned sink;',
        'static float load(unsigned bits){volatile unsigned u=bits; float x; memcpy(&x,(void*)&u,4); sink+=u; return x;}',
        'static unsigned bits(float x){unsigned b; memcpy(&b,&x,4); return b;}',
        f'static {ctype} V(const unsigned *w){{{ctype} v; float f[{width}];'
        f' for (int i = 0; i < {width}; i++) f[i] = load(w[i]); memcpy(&v, f, sizeof f); return v;}}',
        f'static void emitv({ctype} v){{float f[{width}]; memcpy(f, &v, sizeof f);'
        f' printf("[{",".join(["%u"] * width)}]\\n", {fields});}}',
        'static void emit1(float x){printf("%u\\n", bits(x));}',
        f'static const unsigned rows[][{2 * width + 2}] = {{',
    ]
    for args, amount in rows:
        words = [*args, int(amount is None), amount or 0]
        lines.append('  {' + ','.join(f'0x{word:08x}u' for word in words) + '},')
    lines.append('};')
    lines.append('static const unsigned amounts[] = {' + ','.join(f'0x{word:08x}u' for word in amounts) + '};')
    lines.append('int main(void){')
    lines.append('  for (unsigned i = 0; i < sizeof rows / sizeof rows[0]; i++) {')
    lines.append(f'    {ctype} a = V(rows[i]), b = V(rows[i] + {width});')
    lines.append(f'    unsigned all = rows[i][{2 * width}], own = rows[i][{2 * width + 1}];')
    for _, expr, _, shape, _ in ops:
        lines.append(f'    {"emitv" if shape == "v" else "emit1"}({expr.format(a="a", b="b")});')
    for _, function, _ in lerps:
        lines.append(f'    if (all) for (unsigned k = 0; k < sizeof amounts / sizeof amounts[0]; k++) emitv({function}(a, b, load(amounts[k])));')
        lines.append(f'    else emitv({function}(a, b, load(own)));')
    lines.append('  }')
    lines.append('  (void)sink; return 0;}')
    source = probe.work / 'reference-fused.c'
    source.write_text('\n'.join(lines) + '\n')
    return levels(probe, source)


def levels(probe, source, fold=None):
    """Upstream's arm64 Makefile builds at -O1 and its CMake Release at -O3; both
    must print the -O2 reference's bits, or the contracted contract is not one.
    `fold` (one parsed output line -> comparable value) applies the probe's own
    NaN folding: instruction selection may pick another fresh-NaN sign."""
    outputs = {}
    for level in ('-O2', '-O1', '-O3'):
        binary = probe.work / f'{source.stem}{level}'
        run(['clang', '-std=c11', level, '-ffp-contract=on', '-fno-builtin-atan2f',
             '-I' + str(probe.args.raylib_source / 'src'), source, '-lm', '-o', binary])
        outputs[level] = run([binary])
    def comparable(text):
        if fold is None:
            return text
        return [fold(json.loads(line)) for line in text.splitlines() if line.strip()]
    for level in ('-O1', '-O3'):
        if comparable(outputs[level]) != comparable(outputs['-O2']):
            raise ProbeFailure(f'{source.name}: the {level} contracted build prints other bits than -O2')
    probe.report['fused_levels'] = ['-O1', '-O2', '-O3']
    return outputs['-O2']


def call(name, args, ops, lerps, width, vec):
    """The Bend call of one fused row, or None when the row is not fused."""
    if not name.startswith('fused_'):
        return None
    op = name[len('fused_'):]
    a, b = vec(*args[:width]), vec(*args[width:2 * width])
    for lerp, _, wrapper in lerps:
        if op == lerp:
            return f'{wrapper}(M.Fused{{}}, {a}, {b}, word({args[2 * width]}))'
    for entry in ops:
        if entry[0] == op:
            operands = a if entry[4] == 1 else f'{a}, {b}'
            return f'{entry[2]}(M.Fused{{}}, {operands})'
    raise KeyError(name)


def shape(name, ops, lerps):
    op = name[len('fused_'):]
    if any(op == lerp for lerp, _, _ in lerps):
        return 'v'
    return next(entry[3] for entry in ops if entry[0] == op)
