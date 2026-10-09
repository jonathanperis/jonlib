#!/usr/bin/env python3
"""Compare the host libm's tan and asinf with correct rounding over raylib's argument sets.

Diagnostic (never a parity result). tools/reference/libm_survey.c evaluates
the host `tan` on every binary64 argument MatrixPerspective and BeginMode3D
can receive from a binary32 fovy, and the host `asinf` on every binary32 in
[-1, 1] (QuaternionToEuler), against CORE-MATH's correctly rounded cr_tan and
cr_asinf (tools/reference/core_math, MIT). The glibc 2.41 e_asinf.c source is
compared with cr_asinf on the same inputs. Counterexamples (the smallest
mismatching input of every exponent bucket) and every input the binary64
asin cross-check leaves ambiguous are recomputed with the independent exact
oracle tools/cr_libm_oracle.py, which must agree with CORE-MATH.

--stride N evaluates every N-th input word (the gate default, 64); --stride 1
is exhaustive (a few minutes per mode on 2-4 threads). Results are written to
.build/libm-survey-probe/results.json. docs/PERSPECTIVE.md and
docs/INVERSE-TRIG.md record the exhaustive results per host.
"""
import hashlib
import json
import os
import platform
import struct

import probekit
from probekit import ROOT, ProbeFailure
import cr_libm_oracle as oracle

REFERENCE = ROOT / 'tools/reference'
SOURCES = {
    'core_math/tan.c': 'dd662b7af88a86d85e01b88c57f9df4b6019ddfd02120ca381b5ba42283987ae',
    'core_math/asinf.c': '4049d40ec6ff224aa0b5030354a201b155dd52acc1f05988078e5d00d91c2418',
    'core_math/glibc241_e_asinf.c': '8b34f085bb2a64a15c75212ec4a0cc3a2eddc7d35583bf2c5921257158339061',
}
MODES = ('tan-perspective', 'tan-begin3d', 'asinf')
SHIMS = {
    'libm-alias-finite.h': '#define libm_alias_finite(a, b)\n',
    'math_config.h': '#include <math.h>\n#include <stdint.h>\n#include <string.h>\n'
                     '#ifndef __glibc_likely\n#define __glibc_likely(x) __builtin_expect(!!(x), 1)\n#endif\n'
                     '#ifndef __glibc_unlikely\n#define __glibc_unlikely(x) __builtin_expect(!!(x), 0)\n#endif\n'
                     'static inline uint32_t asuint(float f) { uint32_t u; memcpy(&u, &f, 4); return u; }\n'
                     'static inline float __math_invalidf(float x) { return (x - x) / (x - x); }\n',
}


def check_sources():
    for name, digest in SOURCES.items():
        if hashlib.sha256((REFERENCE / name).read_bytes()).hexdigest() != digest:
            raise ProbeFailure(f'libm-survey: pinned {name} changed')


def build(work):
    include = work / 'include'
    include.mkdir(parents=True, exist_ok=True)
    for name, text in SHIMS.items():
        (include / name).write_text(text)
    binary = work / 'libm-survey'
    probekit.run(['clang', '-std=gnu11', '-O2', '-ffp-contract=off', '-I' + str(include),
                  '-D__ieee754_asinf=glibc241_asinf', REFERENCE / 'libm_survey.c', REFERENCE / 'core_math/tan.c',
                  REFERENCE / 'core_math/asinf.c', REFERENCE / 'core_math/glibc241_e_asinf.c', '-lm', '-lpthread',
                  '-o', binary])
    return binary


def evaluate(binary, mode, words):
    rows = {}
    for start in range(0, len(words), 200):
        text = probekit.run([binary, 'eval', mode, *(f'{w:08x}' for w in words[start:start + 200])])
        for line in text.splitlines():
            fields = [int(item, 16) for item in line.split()]
            rows[fields[0]] = fields[1:]
    return rows


def f32(word):
    return struct.unpack('<f', struct.pack('<I', word))[0]


def confirm(binary, mode, result):
    """Recompute counterexamples and ambiguous inputs with the exact oracle."""
    firsts = sorted(int(entry[2], 16) for entry in result['buckets'].values() if len(entry) > 2)
    ambiguous = [int(w, 16) for w in result['ambiguous_words']]
    words = sorted(set(firsts) | set(ambiguous) | {w | 0x80000000 for w in firsts})
    rows = evaluate(binary, mode, words)
    counterexamples = []
    for word in words:
        if mode == 'asinf':
            native, correct, source = rows[word]
            exact = oracle.asinf_bits(word)
            if source != correct:
                raise ProbeFailure(f'libm-survey: glibc 2.41 asinf source differs from CORE-MATH at {word:08x}')
            argument = word
        else:
            argument, native, correct = rows[word]
            exact = oracle.tan_bits(argument)
        if exact != correct:
            raise ProbeFailure(f'libm-survey: CORE-MATH {mode} differs from the exact oracle at input {word:08x}')
        if word in firsts and native == exact:
            raise ProbeFailure(f'libm-survey: recorded counterexample {word:08x} is not one')
        if native != exact:
            counterexamples.append(dict(input=f'{word:08x}', argument=f'{argument:x}', native=f'{native:x}',
                                        correctly_rounded=f'{exact:x}'))
    smallest = firsts[0] if firsts else None
    return dict(oracle_checked=len(words), counterexamples=counterexamples[:12],
                smallest_counterexample=None if smallest is None else f'{smallest:08x}',
                agreement=('none observed' if smallest is None else
                           f'native equals correct rounding for every evaluated input word of magnitude below {smallest:08x}'
                           + f' (|input| < {f32(smallest).hex()})'))


def main():
    def configure(parser):
        parser.add_argument('--threads', type=int, default=2)
        parser.add_argument('--stride', type=int, default=64)
        parser.add_argument('--modes', nargs='+', choices=MODES, default=list(MODES))
    args = probekit.arguments(__doc__, configure, bend=False, raylib=False)
    probe = probekit.Probe('libm-survey', args)
    check_sources()
    binary = build(probe.work)
    try:
        libc = os.confstr('CS_GNU_LIBC_VERSION')
    except (ValueError, OSError, AttributeError):
        libc = None
    summary = {}
    for mode in args.modes:
        result = json.loads(probekit.run([binary, mode, str(args.threads), str(args.stride)], timeout=7200))
        if result['source_mismatches']:
            raise ProbeFailure(f'libm-survey: glibc 2.41 asinf source differs from CORE-MATH on {result["source_mismatches"]} inputs')
        confirmed = confirm(binary, mode, result)
        summary[mode] = dict(evaluated=result['evaluated'], native_mismatches=result['native_mismatches'],
                             ambiguous_checked=result['ambiguous'], buckets=result['buckets'], **confirmed)
        print(f'libm-survey: {mode}: {result["native_mismatches"]} of {result["evaluated"]} native results differ '
              f'from correct rounding (stride {args.stride}); smallest counterexample input '
              f'{confirmed["smallest_counterexample"]}', flush=True)
    probe.report.update(modes=summary,
                        scope='Host libm against correct rounding on raylib argument sets; not a parity result')
    probe.diagnostic(host=dict(system=platform.system(), machine=platform.machine(), libc=libc), stride=args.stride,
                     native_mismatches={mode: item['native_mismatches'] for mode, item in summary.items()},
                     smallest_counterexample={mode: item['smallest_counterexample'] for mode, item in summary.items()})


if __name__ == '__main__':
    main()
