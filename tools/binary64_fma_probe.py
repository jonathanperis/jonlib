#!/usr/bin/env python3
"""Private bounded binary64 FMA: independent rational/native and CPU-1/2/JS gates."""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import re
import shutil
import subprocess
import time

from binary64_fma_oracle import BOUNDS, FRACTION, SIGN, checked, decode64, nearest64, power2, word
from conformance import BUILD, ROOT, checkout, source_gate

CHUNK = 256
LINE = 16
SEED = 0x64F0A
FIELDS = ('ah', 'al', 'bh', 'bl', 'ch', 'cl')
PREFLIGHT_COUNT = 9
FLAGS = ['-std=c11', '-O2', '-frounding-math', '-fno-fast-math',
         '-ffp-contract=off', '-fno-builtin-fma', '-fno-lto']
DEPENDENCIES = ('src/binary64_fma.bend', 'tools/binary64_fma_probe.py',
                'tools/binary64_fma_oracle.py', 'tests/test_binary64_fma.py',
                'tools/conformance.py', 'LAWS.bend', 'PROOF.bend', 'toolchain.json')


def normal(exponent, fraction=0, sign=0):
    if not -1022 <= exponent <= 1023 or not 0 <= fraction <= FRACTION or sign not in (0, 1):
        raise ValueError('Invalid normal binary64 parameters')
    return (sign << 63) | ((exponent + 1023) << 52) | fraction


def exact_bits(value):
    bits = nearest64(value)
    if decode64(bits >> 32, bits & 0xffffffff) != value:
        raise ValueError('Corpus rational is not exactly binary64-representable')
    return bits


# Hard-coded IEEE encodings, independent of both rounding implementations.
HAND = (
    (0x3ff0000000000001, 0x3feffffffffffffe, 0xbff0000000000000,
     0xb970000000000000, 'fused-not-split-control'),
    (0x2ea0000000000001, 0x2ea0000000000001, 0x9d50000000000002,
     0x16d0000000000000, 'minimum-positive-lattice-result'),
    (0xaea0000000000001, 0x2ea0000000000001, 0x1d50000000000002,
     0x96d0000000000000, 'minimum-negative-lattice-result'),
    (0x3ff0000000000000, 0x3ff0000000000000, 0x3ca0000000000000,
     0x3ff0000000000000, 'hand-even-tie'),
    (0x3ff0000000000001, 0x3ff0000000000000, 0x3ca0000000000000,
     0x3ff0000000000002, 'hand-odd-tie'),
)


def samples():
    """Deterministic, deduplicated and labeled; every allowed input exponent."""
    rows, seen = [], {}
    def add(a, b, c, label):
        key = tuple(word(value, 64) for value in (a, b, c))
        if key not in seen:
            row = dict(kind='fma', labels=[])
            row.update(zip(FIELDS, [part for value in key for part in (value >> 32, value & 0xffffffff)]))
            rows.append(row)
            seen[key] = row
        if label not in seen[key]['labels']:
            seen[key]['labels'].append(label)
    def signed(a, b, c, label):
        add(a, b, c, label)
        add(a ^ SIGN, b, c ^ SIGN, label)
    for a, b, c, expected, label in HAND:
        result = checked(a >> 32, a & 0xffffffff, b >> 32, b & 0xffffffff, c >> 32, c & 0xffffffff)
        if result != (expected >> 32, expected & 0xffffffff):
            raise ValueError('Exact rational oracle disagrees with fixed hand vector')
        add(a, b, c, label)
    one = normal(0)
    for a in (0, SIGN):
        for b in (0, SIGN):
            for c in (0, SIGN):
                add(a, b, c, 'all-zero-sign-combinations')
    for exponent in (-277, 0, 127):
        for sign_a in (0, 1):
            for sign_b in (0, 1):
                for sign_c in (0, 1):
                    add(sign_a << 63, normal(exponent, FRACTION, sign_b), sign_c << 63, 'zero-product-signs')
                    add(normal(exponent, FRACTION, sign_a), sign_b << 63, sign_c << 63, 'zero-product-signs')
    rng = random.Random(SEED)
    for operand, (minimum, maximum) in enumerate(BOUNDS):
        for exponent in range(minimum, maximum + 1):
            for sign in (0, 1):
                values = [normal(rng.randint(*BOUNDS[i]), rng.getrandbits(52), rng.getrandbits(1)) for i in range(3)]
                values[operand] = normal(exponent, rng.getrandbits(52), sign)
                add(*values, f'every-exponent-operand-{operand}')
                # Pure powers isolate extraction/positioning independently of random fractions.
                isolated = [one, one, 0]
                isolated[operand] = normal(exponent, 0, sign)
                if operand == 2:
                    isolated[0] = 0
                add(*isolated, f'every-power-of-two-operand-{operand}')
    # Exact midpoint, either side, odd/even retained significands, binade carries.
    tie_exponents = sorted({-501, -500, -278, -277, -1, 0, 1, 126, 127, 253, 254, *range(-480, 255, 32)})
    for exponent in tie_exponents:
        ea = max(-277, min(127, exponent // 2))
        eb = exponent - ea
        for fraction in (0, 1, FRACTION):
            for delta in (-1, 0, 1):
                label = ('reject-c-below-minimum-normal' if exponent == -501 and delta == -1
                         else 'ties-even-odd-carry-and-adjacent')
                signed(normal(ea, fraction), normal(eb), normal(exponent - 53) + delta, label)
                if fraction == FRACTION and delta >= 0:
                    signed(normal(ea, fraction), normal(eb), normal(exponent - 53) + delta,
                           'retained-53-bit-rounding-carry')
    cancellation_exponents = sorted({-554, -553, -552, -277, -1, 0, 1, 127, 253, 254, *range(-544, 255, 16)})
    for exponent in cancellation_exponents:
        ea = max(-277, min(127, exponent // 2))
        eb = exponent - ea
        signed(normal(ea), normal(eb), normal(exponent, sign=1), 'nonzero-exact-cancellation')
        signed(normal(ea, 1), normal(eb, 1), normal(exponent, 2, 1), 'deep-104-bit-cancellation')
        for delta in (-1, 1):
            signed(normal(ea, 1), normal(eb, 1), normal(exponent, 2, 1) + delta,
                   'deep-cancellation-neighbors')
    # Exact residues enumerate both alignment and final normalization branches.
    for residue in range(32):
        signed(normal(-277 + residue, FRACTION), normal(-277, FRACTION),
               normal(-542 + residue, FRACTION), f'alignment-residual-shift-{residue}')
        signed(normal(-277), normal(-262 + residue), normal(-554, FRACTION),
               f'normalization-residual-shift-{residue}')
    for bit in range(55):
        exponent = -554 + bit
        ea = exponent // 2
        signed(normal(ea, 1), normal(exponent - ea, 1), normal(exponent, 2, 1),
               f'normalization-left-shift-{55-bit}')
    # Carry/borrow chains across the full bounded accumulator span; no limb algorithm is reused.
    edge_exponents = (-277, -276, -129, -128, -1, 0, 1, 126, 127)
    for ea in edge_exponents:
        for eb in edge_exponents:
            for fraction in (0, 1, FRACTION):
                for ec in (-554, min(255, max(-554, ea + eb)), 255):
                    for c_sign in (0, 1):
                        signed(normal(ea, fraction), normal(eb, FRACTION), normal(ec, FRACTION, c_sign),
                               'extreme-gaps-long-carry-borrow')
    # Do not permit a zero shortcut to evade any invalid-operand check.
    for operand, (minimum, maximum) in enumerate(BOUNDS):
        invalid = [normal(e, f, s) for e in (-1022, minimum-1, maximum+1, 1023)
                   for f in (0, FRACTION) for s in (0, 1)]
        invalid += [(s << 63) | f for f in (1, 1 << 31, 1 << 51, FRACTION) for s in (0, 1)]
        invalid += [(s << 63) | (2047 << 52) | f for f in (0, 1, 1 << 32, 1 << 51, FRACTION)
                    for s in (0, 1)]
        for bad in invalid:
            for base in ([one, one, one], [0, 0, 0], [SIGN, SIGN, SIGN]):
                values = list(base)
                values[operand] = bad
                add(*values, f'reject-invalid-operand-{operand}')
    for index, row in enumerate(rows):
        row['id'] = index
    return rows


def expected_row(row):
    index = word(row['id'], 32)
    if row['kind'] != 'fma':
        raise ValueError('Unknown observation kind')
    result = checked(*(row[field] for field in FIELDS))
    return [index, 0, 0, 0] if result is None else [index, 1, *result]


def strict_json(text):
    def pairs(items):
        value = {}
        for key, item in items:
            if key in value:
                raise ValueError('Duplicate JSON key')
            value[key] = item
        return value
    def constant(value):
        raise ValueError('Nonfinite JSON constant')
    return json.loads(text, object_pairs_hook=pairs, parse_constant=constant)


def parse_output(text, selected):
    lines = text.splitlines()
    groups = [selected[start:start+LINE] for start in range(0, len(selected), LINE)]
    if len(lines) != len(groups):
        raise ValueError('Wrong output line count/framing')
    actual = []
    for line, group in zip(lines, groups):
        values = strict_json(line)
        if type(values) is not list or len(values) != 4 * len(group):
            raise ValueError('Wrong output shape/count')
        for value in values:
            word(value, 32)
        for offset, row in enumerate(group):
            result = values[4*offset:4*offset+4]
            if row['kind'] != 'fma' or result[0] != word(row['id'], 32) or result[1] not in (0, 1):
                raise ValueError('Wrong output ID or tag')
            if result[1] == 0 and result[2:] != [0, 0]:
                raise ValueError('Noncanonical rejected payload')
            actual.append(result)
    return actual


def compare(expected, actual):
    if len(expected) != len(actual):
        raise ValueError('Incomplete comparison')
    differences = [dict(id=a[0], expected=a, actual=b) for a, b in zip(expected, actual) if a != b]
    if differences:
        raise ValueError(f'Exact mismatch: {differences[:8]} (total {len(differences)})')


def program(selected):
    source = '''import Base
import ../../src/binary64_fma.bend as F
type Task is Data:
  Fma{index: U32, ah: U32, al: U32, bh: U32, bl: U32, ch: U32, cl: U32}
def observe(index: U32, value: Maybe<F.Words>, rest: List<U32>) -> List<U32>:
  match value:
    case None{}: Con{index, Con{0, Con{0, Con{0, rest}}}}
    case Some{pair}:
      F.Words{high, low} = pair
      Con{index, Con{1, Con{high, Con{low, rest}}}}
def one(task: Task, rest: List<U32>) -> List<U32>:
  match task:
    case Fma{index, ah, al, bh, bl, ch, cl}: observe(index, F.checked(ah, al, bh, bl, ch, cl), rest)
def calculate(values: +List<Task>) -> List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{task, rest}: one(task, calculate(rest))
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for start in range(0, len(selected), LINE):
        values = ['Fma{' + ','.join(str(value) for value in (row['id'], *(row[f] for f in FIELDS))) + '}'
                  for row in selected[start:start+LINE]]
        source += '    IO.print(List.show(~&1, ~U32, ~U32.show, calculate([' + ','.join(values) + '])))\n'
    return source


NATIVE = r'''#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <float.h>
#include <limits.h>
#include <fenv.h>
#include <math.h>
#include <inttypes.h>
#if defined(__x86_64__) || defined(__i386__)
#include <xmmintrin.h>
#elif !defined(__aarch64__)
#error Unsupported floating point control-register qualification
#endif
#ifdef __FAST_MATH__
#error Fast math invalidates this oracle
#endif
#pragma STDC FENV_ACCESS ON
#pragma STDC FP_CONTRACT OFF
_Static_assert(CHAR_BIT == 8 && sizeof(double) == 8, "word layout");
_Static_assert(FLT_RADIX == 2 && DBL_MANT_DIG == 53 && DBL_MIN_EXP == -1021 && DBL_MAX_EXP == 1024, "binary64");
static double (* volatile runtime_fma)(double, double, double) = fma;
static uint64_t evaluate(uint64_t a, uint64_t b, uint64_t c) {
  double da, db, dc; memcpy(&da,&a,8); memcpy(&db,&b,8); memcpy(&dc,&c,8);
  volatile double va=da, vb=db, vc=dc;
  volatile double computed=runtime_fma(va,vb,vc);
  double result=computed; uint64_t bits; memcpy(&bits,&result,8); return bits;
}
static int allowed(uint64_t value, int minimum, int maximum) {
  unsigned exponent=(unsigned)((value>>52)&2047);
  if (!exponent) return (value & UINT64_C(0x7fffffffffffffff)) == 0;
  return (int)exponent-1023 >= minimum && (int)exponent-1023 <= maximum;
}
int main(int argc, char **argv) {
  int initial=fegetround();
  if (argc != 2 || fesetround(FE_TONEAREST) || fegetround() != FE_TONEAREST) return 2;
  uint64_t control; const char *control_name;
#if defined(__x86_64__) || defined(__i386__)
  control=_mm_getcsr(); control_name="mxcsr";
  if (control & ((1u<<15) | (1u<<6) | (3u<<13))) return 3;
#else
  __asm__ volatile("mrs %0, fpcr" : "=r"(control)); control_name="fpcr";
  if (control & ((1ull<<24) | (1ull<<19) | (3ull<<22) | 3ull)) return 3;
#endif
  double one=1.0; uint64_t one_bits; memcpy(&one_bits,&one,8);
  if (one_bits != UINT64_C(0x3ff0000000000000)) return 4;
  static const uint64_t controls[][4] = {
    {UINT64_C(0x3ff0000000000001),UINT64_C(0x3feffffffffffffe),UINT64_C(0xbff0000000000000),UINT64_C(0xb970000000000000)},
    {UINT64_C(0x2ea0000000000001),UINT64_C(0x2ea0000000000001),UINT64_C(0x9d50000000000002),UINT64_C(0x16d0000000000000)},
    {UINT64_C(0x3ff0000000000000),UINT64_C(0x3ff0000000000000),UINT64_C(0x3ca0000000000000),UINT64_C(0x3ff0000000000000)},
    {UINT64_C(0x3ff0000000000001),UINT64_C(0x3ff0000000000000),UINT64_C(0x3ca0000000000000),UINT64_C(0x3ff0000000000002)},
    {UINT64_C(0x0000000000000000),UINT64_C(0xbff0000000000000),UINT64_C(0x8000000000000000),UINT64_C(0x8000000000000000)},
    {UINT64_C(0x0000000000000000),UINT64_C(0xbff0000000000000),UINT64_C(0x0000000000000000),UINT64_C(0x0000000000000000)},
    {UINT64_C(0x3ff0000000000000),UINT64_C(0x3ff0000000000000),UINT64_C(0xbff0000000000000),UINT64_C(0x0000000000000000)},
    {UINT64_C(0x0010000000000000),UINT64_C(0x3fe0000000000000),UINT64_C(0x0000000000000000),UINT64_C(0x0008000000000000)},
    {UINT64_C(0x0000000000000001),UINT64_C(0x3ff0000000000000),UINT64_C(0x0000000000000000),UINT64_C(0x0000000000000001)}
  };
  unsigned preflights=(unsigned)(sizeof controls/sizeof controls[0]);
  for (unsigned i=0;i<preflights;i++) {
    if (evaluate(controls[i][0],controls[i][1],controls[i][2]) != controls[i][3]) {
      fprintf(stderr,"Runtime libm fma preflight %u failed\n",i); return 7;
    }
  }
  printf("{\"rounding\":\"FE_TONEAREST\",\"initial_rounding\":%d,\"selected_rounding\":%d,\"control_name\":\"%s\",\"control\":%" PRIu64 ",\"ftz\":false,\"daz\":false,\"runtime_fma\":true,\"preflight_count\":%u}\n",initial,fegetround(),control_name,control,preflights);
  FILE *in=fopen(argv[1],"r"); if (!in) return 5;
  uint32_t index,ah,al,bh,bl,ch,cl; int count;
  while ((count=fscanf(in,"%" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32 " %" SCNu32,&index,&ah,&al,&bh,&bl,&ch,&cl)) == 7) {
    uint64_t a=((uint64_t)ah<<32)|al,b=((uint64_t)bh<<32)|bl,c=((uint64_t)ch<<32)|cl;
    if (!allowed(a,-277,127) || !allowed(b,-277,127) || !allowed(c,-554,255)) {
      printf("[%" PRIu32 ",0,0,0]\n",index); continue;
    }
    uint64_t bits=evaluate(a,b,c);
    printf("[%" PRIu32 ",1,%" PRIu32 ",%" PRIu32 "]\n",index,(uint32_t)(bits>>32),(uint32_t)bits);
  }
  if (count != EOF || ferror(in) || fclose(in)) return 6;
  return 0;
}
'''


def parse_native(text, rows):
    lines = text.splitlines()
    if len(lines) != len(rows) + 1:
        raise ValueError('Wrong native line count')
    metadata = strict_json(lines[0])
    keys = {'rounding', 'initial_rounding', 'selected_rounding', 'control_name',
            'control', 'ftz', 'daz', 'runtime_fma', 'preflight_count'}
    if type(metadata) is not dict or set(metadata) != keys:
        raise ValueError('Malformed native environment metadata')
    if (metadata['rounding'] != 'FE_TONEAREST' or metadata['ftz'] is not False or
            metadata['daz'] is not False or metadata['runtime_fma'] is not True or
            metadata['control_name'] not in ('mxcsr', 'fpcr')):
        raise ValueError('Unsupported native rounding/denormal/runtime environment')
    for key in ('initial_rounding', 'selected_rounding', 'control', 'preflight_count'):
        if type(metadata[key]) is not int or metadata[key] < 0:
            raise ValueError('Invalid native control metadata')
    if metadata['selected_rounding'] != 0 or metadata['preflight_count'] != PREFLIGHT_COUNT:
        raise ValueError('Unsupported native rounding or incomplete preflight')
    mask = ((1 << 15) | (1 << 6) | (3 << 13) if metadata['control_name'] == 'mxcsr'
            else (1 << 24) | (1 << 19) | (3 << 22) | 3)
    if metadata['control'] & mask:
        raise ValueError('Native rounding/denormal mode does not match metadata')
    groups = []
    for start in range(0, len(rows), LINE):
        combined = []
        for line in lines[1+start:1+min(start+LINE, len(rows))]:
            values = strict_json(line)
            if type(values) is not list or len(values) != 4:
                raise ValueError('Malformed native record')
            combined.extend(values)
        groups.append(json.dumps(combined))
    return metadata, parse_output('\n'.join(groups), rows)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def execute(command, work, name, timeout=600, env=None):
    command = [str(part) for part in command]
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
    # Match the pinned Bend CLI's supported CPU compiler predicate.  An unsupported
    # CC would silently fall back to another clang, invalidating compiler evidence.
    match = re.search(r'^(Apple )?(?:\w+ )?clang version (\d+)', compiler['version'], re.M)
    if match is None or int(match[2]) < 14:
        raise ValueError('Recorded compiler is not a supported Bend CPU clang')
    return {'CC': compiler['path']}


def assert_unchanged(before):
    after = {path: digest(ROOT/path) for path in before}
    if after != before:
        raise ValueError('Source/harness/toolchain drift during probe')


def final_source_gate(hashes, bend_source, lock, compilers=None, work=None):
    assert_unchanged(hashes)
    checkout(bend_source, lock['bend']['revision'], lock['bend'].get('patch'))
    for name, (command, expected) in (compilers or {}).items():
        if compiler_identity(command, work, name+'-final-version') != expected:
            raise ValueError('Compiler/runtime executable drift during probe')


def native_reference(rows, expected, work, clang):
    source = work/'reference.c'; source.write_text(NATIVE)
    inputs = work/'native-input.txt'
    inputs.write_text(''.join(' '.join(str(v) for v in (r['id'], *(r[f] for f in FIELDS)))+'\n' for r in rows))
    compiler = compiler_identity(clang, work, 'compiler-version')
    compile_fresh([clang, *FLAGS, source, '-lm', '-o', work/'reference'], [work/'reference'], work, 'native-compile')
    output = execute([work/'reference', inputs], work, 'native-run')
    environment, actual = parse_native(output, rows)
    compare(expected, actual)
    return dict(passed=True, observations=len(actual), compiler=compiler, flags=FLAGS, environment=environment)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source', type=Path, required=True)
    parser.add_argument('--clang', default='clang')
    parser.add_argument('--native-only', action='store_true', help='qualify oracle/native only; never reports candidate pass')
    args = parser.parse_args()
    work = BUILD/'binary64-fma-probe'; work.mkdir(parents=True, exist_ok=True)
    report_path = work/'results.json'
    report = dict(schema=1, passed=False, lanes={}, phase='initializing')
    write_json(report_path, report)
    start = time.monotonic()
    try:
        lock = json.loads((ROOT/'toolchain.json').read_text())
        checkout(args.bend_source, lock['bend']['revision'], lock['bend'].get('patch'))
        hashes = source_gate()
        dependencies = (*DEPENDENCIES, lock['bend']['patch']['path']) if lock['bend'].get('patch') else DEPENDENCIES
        for path in dependencies:
            hashes[path] = digest(ROOT/path)
        bun = compiler_identity('bun', work, 'bun-version')
        if bun['version'] != lock['bun']['version']:
            raise ValueError('Bun version does not match pinned toolchain')
        rows = samples()
        expected = [expected_row(row) for row in rows]
        write_json(work/'inputs.json', rows)
        write_json(work/'expected.json', expected)
        report.update(phase='native-qualification', observations=len(rows),
                      accepted=sum(row[1] for row in expected), rejected=sum(row[1] == 0 for row in expected),
                      coverage=dict(Counter(label for row in rows for label in row['labels'])),
                      seed=SEED, bun=bun, chunk_limit=CHUNK, output_line_limit=LINE,
                      sources=hashes, inputs_sha256=digest(work/'inputs.json'), oracle_sha256=digest(work/'expected.json'),
                      scope='private RN-even exact a*b+c; a/b zero or normal [-277,127]; c zero or normal [-554,255]',
                      gpu='not run; no device claim', host=dict(platform=platform.platform(), machine=platform.machine(),
                      libc=platform.libc_ver(), python=platform.python_version()), chunks=[], artifacts={})
        write_json(report_path, report)
        report['native'] = native_reference(rows, expected, work, args.clang)
        candidate_env = candidate_environment(report['native']['compiler'])
        report['candidate_compiler'] = dict(compiler=report['native']['compiler'], environment=candidate_env,
                                            flags_source='pinned bend2/main.ts cli_build CPU flags')
        write_json(work/'native-metadata.json', report['native'])
        report['native_metadata_sha256'] = digest(work/'native-metadata.json')
        compilers = {'compiler': (args.clang, report['native']['compiler']), 'bun': ('bun', bun)}
        names = ['inputs.json', 'expected.json', 'native-input.txt', 'reference.c', 'reference', 'native-metadata.json']
        names += [f'{prefix}.{suffix}' for prefix in ('compiler-version', 'bun-version', 'native-compile', 'native-run') for suffix in ('stdout', 'stderr')]
        print(f'Exact rational/runtime-libm oracle agreement: {len(rows)} checked inputs', flush=True)
        if args.native_only:
            final_source_gate(hashes, args.bend_source, lock, compilers, work)
            names += [f'{prefix}-final-version.{suffix}' for prefix in ('compiler', 'bun') for suffix in ('stdout', 'stderr')]
            report.update(phase='native-only-complete', artifacts={name: digest(work/name) for name in names},
                          elapsed_seconds=round(time.monotonic()-start, 3))
            write_json(report_path, report)
            print('Native qualification complete; candidate lanes not run and overall passed remains false', flush=True)
            return
        report['phase'] = 'candidate'
        write_json(report_path, report)
        cli = ['bun', args.bend_source/'bend2/main.ts']
        proof = execute([*cli, ROOT/'PROOF.bend', '--check-only'], work, 'proof')
        if proof.strip() != 'All terms check.':
            raise ValueError('Incomplete proof verdict')
        report['proof'] = proof.strip()
        totals = Counter()
        for batch, offset in enumerate(range(0, len(rows), CHUNK)):
            selected = rows[offset:offset+CHUNK]
            source = work/f'candidate-{batch:03}.bend'; source.write_text(program(selected))
            binary, js = work/f'candidate-{batch:03}', work/f'candidate-{batch:03}.js'
            compile_fresh([*cli, source, '-o', binary, '-o', js], [binary, js], work, f'compile-{batch:03}', env=candidate_env)
            for lane, command in (('cpu-1', [binary, '--gpu', 'off', '--threads', '1']),
                                  ('cpu-2', [binary, '--gpu', 'off', '--threads', '2']), ('javascript', ['bun', js])):
                actual = parse_output(execute(command, work, f'{lane}-{batch:03}'), selected)
                compare(expected[offset:offset+len(selected)], actual)
                totals[lane] += len(actual)
                report['lanes'][lane] = dict(passed=False, checked=totals[lane])
            report['chunks'].append(dict(index=batch, offset=offset, count=len(selected), passed=True))
            write_json(report_path, report)
            print(f'chunk {batch+1}: {len(selected)} observations match CPU-1/CPU-2/JS', flush=True)
        if set(totals) != {'cpu-1', 'cpu-2', 'javascript'} or any(value != len(rows) for value in totals.values()):
            raise ValueError('Incomplete lane coverage')
        final_source_gate(hashes, args.bend_source, lock, compilers, work)
        names += ['proof.stdout', 'proof.stderr']
        names += [f'{prefix}-final-version.{suffix}' for prefix in ('compiler', 'bun') for suffix in ('stdout', 'stderr')]
        for batch in range(len(report['chunks'])):
            names += [f'candidate-{batch:03}{suffix}' for suffix in ('.bend', '', '.js')]
            names += [f'{prefix}-{batch:03}.{suffix}' for prefix in ('compile', 'cpu-1', 'cpu-2', 'javascript') for suffix in ('stdout', 'stderr')]
        report.update(passed=True, phase='complete', artifacts={name: digest(work/name) for name in names},
                      elapsed_seconds=round(time.monotonic()-start, 3))
        for lane in report['lanes'].values():
            lane['passed'] = True
        write_json(report_path, report)
        print(f'PASS: {len(rows)} complete exact observations on each of three lanes', flush=True)
    except Exception as error:
        report.update(passed=False, error=str(error), elapsed_seconds=round(time.monotonic()-start, 3))
        write_json(report_path, report)
        raise


if __name__ == '__main__':
    main()
