#!/usr/bin/env python3
"""Private finite binary64 narrowing: exact rational oracle, qualified C, CPU-1/2/JS."""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import struct
import subprocess
import time

from binary64_narrow_oracle import decode64, nearest, positive32, word
from conformance import BUILD, ROOT, checkout, source_gate

CHUNK = 512
LINE = 32
SEED = 0x6432E
HAND = (
    (0x36900000, 0x00000000, 0x00000000),
    (0x36900000, 0x00000001, 0x00000001),
    (0x36a7ffff, 0xffffffff, 0x00000001),
    (0x36a80000, 0x00000000, 0x00000002),
    (0x380fffff, 0xdfffffff, 0x007fffff),
    (0x380fffff, 0xe0000000, 0x00800000),
    (0x47efffff, 0xefffffff, 0x7f7fffff),
    (0x47efffff, 0xf0000000, 0x7f800000),
)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def rational64(value):
    bits = struct.unpack('>Q', struct.pack('>d', float(value)))[0]
    if decode64(bits >> 32, bits & 0xffffffff) != value:
        raise ValueError('Corpus rational is not exactly representable in binary64')
    return bits


def samples():
    """Fixed full corpus. Deduplication preserves all coverage labels."""
    rows, seen = [], {}
    def add(bits, label, promoted=None):
        word(bits, 64)
        if bits not in seen:
            row = dict(kind='narrow', high=bits >> 32, low=bits & 0xffffffff, labels=[])
            seen[bits] = row
            rows.append(row)
        row = seen[bits]
        if label not in row['labels']:
            row['labels'].append(label)
        if promoted is not None:
            row['promoted32'] = promoted
    def signs(bits, label):
        for sign in (0, 1 << 63):
            add(bits | sign, label)
    for high, low, expected in HAND:
        if nearest(high, low) != expected:
            raise ValueError('Exact rational oracle disagrees with a fixed hand vector')
        signs((high << 32) | low, 'hand-boundaries')
    rng = random.Random(SEED)
    for exponent in range(2047):
        for fraction in (0, 1, (1 << 52) - 1):
            signs((exponent << 52) | fraction, 'every-finite-exponent-transition')
        for _ in range(2):
            signs((exponent << 52) | rng.getrandbits(52), 'exponent-stratified-random')
    # All binary64 subnormal binades and both sides of each limb carry.
    for bit in range(52):
        for delta in (-1, 0, 1):
            signs((1 << bit) + delta, 'binary64-subnormal-binades')
    for exponent in (873, 874, 895, 896, 897, 898, 1023, 1150):
        for fraction_high in (0, 1, 0x7ffff, 0xfffff):
            for low in (0, 1, 0x7fffffff, 0x80000000, 0xfffffffe, 0xffffffff):
                signs((exponent << 52) | (fraction_high << 32) | low, 'limb-carries')
    # Midpoints have <=25 significant bits, hence are exact binary64 values.
    lower_words = { (e << 23) | f for e in range(255)
                    for f in (0, 1, 2, 0x3ffffe, 0x3fffff, 0x7ffffe, 0x7fffff) }
    lower_words |= { (1 << bit) + delta for bit in range(23) for delta in (-1, 0, 1) }
    for lower in sorted(lower_words):
        midpoint = (positive32(lower) + positive32(lower + 1)) / 2
        bits = rational64(midpoint)
        for delta in (-1, 0, 1):
            signs(bits + delta, 'even-odd-ties-and-adjacent64')
    # Sample every finite binary32 exponent and all subnormal binades exactly.
    roundtrip = { (e << 23) | f for e in range(255)
                  for f in (0, 1, 2, 0x3fffff, 0x400000, 0x7ffffe, 0x7fffff) }
    roundtrip |= { (1 << bit) + delta for bit in range(23) for delta in (-1, 0, 1) }
    for bits32 in sorted(roundtrip):
        bits64 = rational64(positive32(bits32))
        for sign in (0, 1):
            add(bits64 | (sign << 63), 'finite32-promote-narrow', bits32 | (sign << 31))
    for row in list(rows):
        if 'promoted32' in row:
            rows.append(dict(kind='promote', value=row['promoted32'], labels=['existing-promote-roundtrip']))
    for fraction in (0, 1, (1 << 51)-1, 1 << 51, (1 << 51)+1, (1 << 52)-1):
        signs((2047 << 52) | fraction, 'reject-infinity-and-nan')
    # Independent integer invariants exercise jam through and beyond 64 bits.
    limb_values = [0, 1, 2, 3, 0x7fffffff, 0x80000000, 0xffffffff,
                   0x100000000, 0x100000001, 0x8000000000000000, (1 << 64)-1]
    limb_values += [rng.getrandbits(64) for _ in range(7)]
    for count in range(66):
        for value in limb_values:
            rows.append(dict(kind='jam', count=count, high=value >> 32,
                             low=value & 0xffffffff, labels=['jam-invariant']))
    for quotient in (0, 1, 2, 3, 0x7ffffe, 0x7fffff, 0x800000, 0xfffffe, 0xffffff):
        for tail in range(8):
            rows.append(dict(kind='round', value=(quotient << 3) | tail,
                             labels=['guard-round-sticky-even-odd']))
    for index, row in enumerate(rows):
        row['id'] = index
    return rows


def expected_row(row):
    index = word(row['id'], 32)
    if row['kind'] == 'narrow':
        result = nearest(row['high'], row['low'])
        if 'promoted32' in row and result != row['promoted32']:
            raise ValueError('Oracle violates finite32 roundtrip')
        return [index, 0, 0, 0] if result is None else [index, 1, result, 0]
    if row['kind'] == 'promote':
        return [index, 1, word(row['value'], 32), 0]
    if row['kind'] == 'jam':
        value = (row['high'] << 32) | row['low']
        count = row['count']
        result = (value >> count) | int(value % (1 << count) != 0)
        return [index, 2, result >> 32, result & 0xffffffff]
    if row['kind'] == 'round':
        quotient, rest = divmod(row['value'], 8)
        result = quotient + (rest > 4 or (rest == 4 and quotient % 2 != 0))
        return [index, 3, result, 0]
    raise ValueError('Unknown observation kind')


def parse_output(text, selected):
    lines = text.splitlines()
    groups = [selected[start:start+LINE] for start in range(0, len(selected), LINE)]
    if len(lines) != len(groups):
        raise ValueError('Wrong output line count/framing')
    actual = []
    tags = {'narrow': {0, 1}, 'promote': {0, 1}, 'jam': {2}, 'round': {3}}
    for line, group in zip(lines, groups):
        values = json.loads(line)
        if type(values) is not list or len(values) != 4 * len(group):
            raise ValueError('Wrong output shape/count')
        for value in values:
            word(value, 32)
        for offset, row in enumerate(group):
            result = values[4*offset:4*offset+4]
            if result[0] != row['id'] or result[1] not in tags[row['kind']]:
                raise ValueError('Wrong output ID or tag')
            if (result[1] == 0 and result[2:] != [0, 0]) or (result[1] in (1, 3) and result[3] != 0):
                raise ValueError('Noncanonical output payload')
            actual.append(result)
    return actual


def compare(expected, actual):
    if len(expected) != len(actual):
        raise ValueError('Incomplete comparison')
    differences = [dict(id=a[0], expected=a, actual=b) for a, b in zip(expected, actual) if a != b]
    if differences:
        raise ValueError(f'Exact mismatch: {differences[:8]} (total {len(differences)})')


def assert_unchanged(before):
    after = {path: digest(ROOT/path) for path in before}
    if after != before:
        raise ValueError('Source/harness/toolchain drift during probe')


def program(selected):
    source = '''import Base
import ../../src/binary64_narrow.bend as N
import ../../src/float64.bend as D
type Task is Data:
  Narrow{index: U32, high: U32, low: U32}
  Jam{index: U32, count: Nat, high: U32, low: U32}
  Round{index: U32, value: U32}
  Promote{index: U32, value: U32}
def narrow(index: U32, value: Maybe<U32>, rest: List<U32>) -> List<U32>:
  match value:
    case None{}: Con{index, Con{0, Con{0, Con{0, rest}}}}
    case Some{word}: Con{index, Con{1, Con{word, Con{0, rest}}}}
def jam(index: U32, value: N.Wide, rest: List<U32>) -> List<U32>:
  N.Wide{high, low} = value
  Con{index, Con{2, Con{high, Con{low, rest}}}}
def promote.words(index: U32, pair: U32 & U32, rest: List<U32>) -> List<U32>:
  (high, low) = pair
  narrow(index, N.checked(high, low), rest)
def promote(index: U32, value: U32, rest: List<U32>) -> List<U32>:
  U32{bits} = value
  promote.words(index, D.promote(F32{bits}), rest)
def one(task: Task, rest: List<U32>) -> List<U32>:
  match task:
    case Narrow{index, high, low}: narrow(index, N.checked(high, low), rest)
    case Jam{index, count, high, low}: jam(index, N.Wide.jam(count, N.Wide{high, low}), rest)
    case Round{index, value}: Con{index, Con{3, Con{N.round(value), Con{0, rest}}}}
    case Promote{index, value}: promote(index, value, rest)
def calculate(values: +List<Task>) -> List<U32>:
  match values:
    case Nil{}: Nil{}
    case Con{task, rest}: one(task, calculate(rest))
def main() -> IO(Unit):
  do IO<Unit>:
'''
    for start in range(0, len(selected), LINE):
        inputs = []
        for row in selected[start:start+LINE]:
            if row['kind'] == 'narrow':
                inputs.append('Narrow{%d,%d,%d}' % (row['id'], row['high'], row['low']))
            elif row['kind'] == 'jam':
                inputs.append('Jam{%d,%dn,%d,%d}' % (row['id'], row['count'], row['high'], row['low']))
            elif row['kind'] == 'promote':
                inputs.append('Promote{%d,%d}' % (row['id'], row['value']))
            else:
                inputs.append('Round{%d,%d}' % (row['id'], row['value']))
        source += '    IO.print(List.show(~&1, ~U32, ~U32.show, calculate([' + ','.join(inputs) + '])))\n'
    return source


NATIVE = r'''#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <float.h>
#include <limits.h>
#include <fenv.h>
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
_Static_assert(CHAR_BIT == 8 && sizeof(float) == 4 && sizeof(double) == 8, "word layout");
_Static_assert(FLT_RADIX == 2 && FLT_MANT_DIG == 24 && FLT_MIN_EXP == -125 && FLT_MAX_EXP == 128, "binary32");
_Static_assert(DBL_MANT_DIG == 53 && DBL_MIN_EXP == -1021 && DBL_MAX_EXP == 1024, "binary64");
int main(int argc, char **argv) {
  int initial = fegetround();
  if (argc != 2 || fesetround(FE_TONEAREST) || fegetround() != FE_TONEAREST) return 2;
  uint64_t control;
  const char *control_name;
#if defined(__x86_64__) || defined(__i386__)
  control = _mm_getcsr(); control_name = "mxcsr";
  if (control & ((1u<<15) | (1u<<6) | (3u<<13))) return 3;
#else
  __asm__ volatile("mrs %0, fpcr" : "=r"(control)); control_name = "fpcr";
  if (control & ((1ull<<24) | (1ull<<19) | (3ull<<22))) return 3;
#endif
  double one = 1.0; uint64_t one_bits; memcpy(&one_bits,&one,8);
  if (one_bits != UINT64_C(0x3ff0000000000000)) return 4;
  float one32 = 1.0f; uint32_t one32_bits; memcpy(&one32_bits,&one32,4);
  if (one32_bits != UINT32_C(0x3f800000)) return 4;
  printf("{\"rounding\":\"FE_TONEAREST\",\"initial_rounding\":%d,\"selected_rounding\":%d,\"control_name\":\"%s\",\"control\":%" PRIu64 ",\"ftz\":false,\"daz\":false}\n",initial,fegetround(),control_name,control);
  FILE *in=fopen(argv[1],"r"); if (!in) return 5;
  uint32_t index,hi,lo;
  int count;
  while ((count=fscanf(in,"%" SCNu32 " %" SCNu32 " %" SCNu32,&index,&hi,&lo)) == 3) {
    if (((hi>>20)&2047)==2047) { printf("[%" PRIu32 ",0,0,0]\n",index); continue; }
    uint64_t bits=((uint64_t)hi<<32)|lo; double stored;
    memcpy(&stored,&bits,8); volatile double input=stored;
    volatile float converted=(float)input; float output=converted; uint32_t word;
    memcpy(&word,&output,4); printf("[%" PRIu32 ",1,%" PRIu32 ",0]\n",index,word);
  }
  if (count != EOF || ferror(in) || fclose(in)) return 6;
  return 0;
}
'''


def parse_native(text, rows):
    lines = text.splitlines()
    if len(lines) != len(rows) + 1:
        raise ValueError('Wrong native line count')
    metadata = json.loads(lines[0])
    keys = {'rounding','initial_rounding','selected_rounding','control_name','control','ftz','daz'}
    if type(metadata) is not dict or set(metadata) != keys:
        raise ValueError('Malformed native environment metadata')
    if (metadata['rounding'] != 'FE_TONEAREST' or metadata['ftz'] is not False or
            metadata['daz'] is not False or metadata['control_name'] not in ('mxcsr', 'fpcr')):
        raise ValueError('Unsupported native rounding/denormal environment')
    for key in ('initial_rounding','selected_rounding','control'):
        if type(metadata[key]) is not int or metadata[key] < 0:
            raise ValueError('Invalid native control metadata')
    if metadata['selected_rounding'] != 0:
        raise ValueError('Unsupported FE_TONEAREST representation')
    mask = (1 << 15) | (1 << 6) | (3 << 13) if metadata['control_name'] == 'mxcsr' else (1 << 24) | (1 << 19) | (3 << 22)
    if metadata['control'] & mask:
        raise ValueError('Native rounding/denormal mode does not match metadata')
    # Reframe scalar records into the same strict bounded parser.
    groups = []
    for start in range(0, len(rows), LINE):
        combined = []
        for line in lines[1+start:1+start+LINE]:
            values = json.loads(line)
            if type(values) is not list or len(values) != 4:
                raise ValueError('Malformed native record')
            combined.extend(values)
        groups.append(json.dumps(combined))
    return metadata, parse_output('\n'.join(groups), rows)


def execute(command, work, name, timeout=600):
    command = [str(part) for part in command]
    try:
        process = subprocess.run(command, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        for suffix, data in (('stdout', error.stdout), ('stderr', error.stderr)):
            (work/(name+'.'+suffix)).write_text(data.decode() if isinstance(data, bytes) else data or '')
        raise
    (work/(name+'.stdout')).write_text(process.stdout)
    (work/(name+'.stderr')).write_text(process.stderr)
    if process.returncode:
        raise ValueError(f'{name} exited {process.returncode}; retained stdout/stderr')
    return process.stdout


def compile_fresh(command, outputs, work, name):
    for path in outputs:
        path.unlink(missing_ok=True)
    execute(command, work, name)
    if any(not path.is_file() or path.stat().st_size == 0 for path in outputs):
        raise ValueError('Compiler succeeded without all fresh nonempty outputs')


def final_source_gate(hashes, bend_source, lock):
    assert_unchanged(hashes)
    checkout(bend_source, lock['bend']['revision'], lock['bend'].get('patch'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source', type=Path, required=True)
    parser.add_argument('--clang', default='clang')
    args = parser.parse_args()
    work = BUILD/'binary64-narrow-probe'; work.mkdir(parents=True, exist_ok=True)
    report_path = work/'results.json'
    # Invalidate stale success before dependency, environment, corpus or source checks.
    report = dict(schema=1, passed=False, lanes={}, phase='initializing')
    write_json(report_path, report)
    start = time.monotonic()
    try:
        lock = json.loads((ROOT/'toolchain.json').read_text())
        checkout(args.bend_source, lock['bend']['revision'], lock['bend'].get('patch'))
        hashes = source_gate()
        for path in ('tools/binary64_narrow_probe.py','tools/binary64_narrow_oracle.py',
                     'tools/conformance.py','tests/test_binary64_narrow.py','LAWS.bend','PROOF.bend','toolchain.json'):
            hashes[path] = digest(ROOT/path)
        bun_version = execute(['bun','--version'],work,'bun-version').strip()
        if bun_version != lock['bun']['version']:
            raise ValueError('Bun version does not match pinned toolchain')
        rows = samples()
        write_json(work/'inputs.json', rows)
        expected = [expected_row(row) for row in rows]
        write_json(work/'expected.json', expected)
        report.update(phase='native-qualification', observations=len(rows),
                      kind_counts=dict(Counter(row['kind'] for row in rows)),
                      coverage=dict(Counter(label for row in rows for label in row['labels'])),
                      seed=SEED, bun_version=bun_version, chunk_limit=CHUNK, output_line_limit=LINE,
                      sources=hashes, inputs_sha256=digest(work/'inputs.json'),
                      oracle_sha256=digest(work/'expected.json'),
                      scope='finite64 words to RN-even binary32 words; exponent2047 rejected',
                      gpu='not run; no device claim', host=dict(platform=platform.platform(),machine=platform.machine()),
                      chunks=[], artifacts={})
        write_json(report_path, report)
        native_rows = [row for row in rows if row['kind'] == 'narrow']
        native_input = work/'native-input.txt'
        native_input.write_text(''.join(f'{r["id"]} {r["high"]} {r["low"]}\n' for r in native_rows))
        source = work/'reference.c'; source.write_text(NATIVE)
        compiler = execute([args.clang,'--version'],work,'compiler-version').strip()
        flags = ['-std=c11','-O2','-frounding-math','-fno-fast-math','-ffp-contract=off']
        compile_fresh([args.clang,*flags,source,'-lm','-o',work/'reference'],[work/'reference'],work,'native-compile')
        text = execute([work/'reference',native_input],work,'native-run')
        metadata, native = parse_native(text,native_rows)
        compare([expected_row(row) for row in native_rows], native)
        report['native'] = dict(passed=True, observations=len(native), compiler=compiler, flags=flags, environment=metadata)
        write_json(work/'native-metadata.json', report['native'])
        report['native_metadata_sha256'] = digest(work/'native-metadata.json')
        report['phase'] = 'candidate'
        write_json(report_path, report)
        print(f'Exact rational/native oracle agreement: {len(native)} checked inputs', flush=True)
        cli = ['bun',args.bend_source/'bend2/main.ts']
        proof = execute([*cli,ROOT/'PROOF.bend','--check-only'],work,'proof')
        if proof.strip() != 'All terms check.':
            raise ValueError('Incomplete proof verdict')
        report['proof'] = proof.strip()
        totals = Counter()
        for batch, offset in enumerate(range(0,len(rows),CHUNK)):
            selected = rows[offset:offset+CHUNK]
            source = work/f'candidate-{batch:03}.bend'; source.write_text(program(selected))
            binary, js = work/f'candidate-{batch:03}', work/f'candidate-{batch:03}.js'
            compile_fresh([*cli,source,'-o',binary,'-o',js],[binary,js],work,f'compile-{batch:03}')
            for lane, command in (('cpu-1',[binary,'--gpu','off','--threads','1']),
                                  ('cpu-2',[binary,'--gpu','off','--threads','2']),('javascript',['bun',js])):
                text = execute(command,work,f'{lane}-{batch:03}')
                actual = parse_output(text,selected)
                compare(expected[offset:offset+len(selected)],actual)
                totals[lane] += len(actual)
                report['lanes'][lane] = dict(passed=False, checked=totals[lane])
            report['chunks'].append(dict(index=batch,offset=offset,count=len(selected),passed=True))
            write_json(report_path,report)
            print(f'chunk {batch+1}: {len(selected)} observations match CPU-1/CPU-2/JS',flush=True)
        if set(totals) != {'cpu-1','cpu-2','javascript'} or any(value != len(rows) for value in totals.values()):
            raise ValueError('Incomplete lane coverage')
        final_source_gate(hashes, args.bend_source, lock)
        # Only artifacts produced by this invocation are selected; old unrelated files cannot qualify it.
        names = ['inputs.json','expected.json','native-input.txt','reference.c','reference',
                 'native-metadata.json','compiler-version.stdout','compiler-version.stderr',
                 'native-compile.stdout','native-compile.stderr','native-run.stdout','native-run.stderr',
                 'proof.stdout','proof.stderr','bun-version.stdout','bun-version.stderr']
        for batch in range(len(report['chunks'])):
            names += [f'candidate-{batch:03}{suffix}' for suffix in ('.bend','','.js')]
            names += [f'{prefix}-{batch:03}.{suffix}' for prefix in ('compile','cpu-1','cpu-2','javascript') for suffix in ('stdout','stderr')]
        report['artifacts'] = {name:digest(work/name) for name in names}
        report.update(passed=True, phase='complete', elapsed_seconds=round(time.monotonic()-start,3))
        for lane in report['lanes'].values():
            lane['passed'] = True
        write_json(report_path,report)
        print(f'PASS: {len(rows)} complete exact observations on each of three lanes',flush=True)
    except Exception as error:
        report.update(passed=False, error=str(error), elapsed_seconds=round(time.monotonic()-start,3))
        write_json(report_path, report)
        raise


if __name__ == '__main__':
    main()
