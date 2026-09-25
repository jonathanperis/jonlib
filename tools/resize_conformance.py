#!/usr/bin/env python3
"""Exact coefficient-bit and filtered-image probes against pinned raylib/stb."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import random
import platform

if __package__:
    from .conformance import BUILD, ROOT, bend_source, cases_from, c_source, checkout, compare, f32, parse_output, result_size, run, source_gate
else:
    from conformance import BUILD, ROOT, bend_source, cases_from, c_source, checkout, compare, f32, parse_output, result_size, run, source_gate


def coefficient_vectors(source, work):
    """Observe the stock normalization step, before clamp-edge folding."""
    header = (source / 'src/external/stb_image_resize2.h').read_text()
    start = '    // add all contribs\n'
    finish = '    ++contribs;\n    coeffs += coefficient_width;\n'
    if header.count(start) != 1 or header.count(finish) != 2:
        raise ValueError('Pinned coefficient instrumentation anchors changed')
    instrumented = header.replace(start, '''    printf("{\\"input\\":[");
    for (int q=0;q<=contribs->n1-contribs->n0;q++) {
      unsigned bits; memcpy(&bits,coeffs+q,4); printf("%s%u",q?",":"",bits);
    }
    printf("],\\"output\\":[");
''' + start).replace(finish, '''    for (int q=0;q<=e;q++) {
      unsigned bits; memcpy(&bits,coeffs+q,4); printf("%s%u",q?",":"",bits);
    }
    printf("]}\\n");
''' + finish, 1)
    observed = work / 'stb_observed.h'
    observed.write_text(instrumented)
    probe = work / 'coefficients.c'
    probe.write_text('''#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define STB_IMAGE_RESIZE_STATIC
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#define STBIR__HEADER_FILENAME "stb_observed.h"
#include "stb_observed.h"
int main(void) {
  for(int w=1;w<=17;w++) for(int n=1;n<=17;n++) {
    unsigned char *in=calloc(w,4);
    unsigned char *out=stbir_resize_uint8_linear(in,w,1,0,NULL,n,1,0,STBIR_RGBA);
    if (!out) return 2;
    free(in); free(out);
  }
  return 0;
}
''')
    binary = work / 'coefficients'
    run(['clang', '-std=c11', '-O3', '-fno-strict-aliasing', probe, '-lm', '-o', binary])
    rows = [json.loads(line) for line in run([binary]).splitlines()]
    unique = {}
    for row in rows:
        key = tuple(row['input'])
        if key in unique and unique[key] != row['output']:
            raise ValueError('Identical stock inputs had inconsistent normalization')
        unique[key] = row['output']
    if not unique:
        raise ValueError('No normalization vectors observed')
    vectors = [dict(input=list(key), output=value) for key, value in unique.items()]
    (work / 'coefficient-vectors.json').write_text(json.dumps(vectors, indent=2) + '\n')
    return vectors, hashlib.sha256(header.encode()).hexdigest()


def bend_coefficients(vectors, gpu=False):
    lines = ['import Base', 'import ../../src/resize_numeric.bend as N',
             'def bits(values: +List<F32>) -> List<U32>:', '  match values:',
             '    case Nil{}: Nil{}', '    case Con{v, rest}: Con{F32.bits(v), bits(rest)}',
             'def normalize(groups: List<+List<F32>>) -> List<List<U32>>:',
             '  match groups:', '    case Nil{}: Nil{}',
             '    case Con{group, rest}: Con{bits(N.normalize(group)), normalize(rest)}',
             'def show.row(values: List<U32>) -> String:', '  match values:',
             '    case Nil{}: ""', '    case Con{v, rest}: U32.show(v) ++ " " ++ show.row(rest)',
             'def show(values: List<List<U32>>) -> String:', '  match values:',
             '    case Nil{}: ""', '    case Con{v, rest}: show.row(v) ++ "\\n" ++ show(rest)',
             '']
    batches = [vectors[i:i+16] for i in range(0, len(vectors), 16)]
    for batch, rows in enumerate(batches):
        lines += [f'def inputs_{batch}() -> List<+List<F32>>:', '  [']
        for index, row in enumerate(rows):
            values = [struct.unpack('<f', struct.pack('<I', value))[0] for value in row['input']]
            lines.append('    [' + ', '.join(f32(value) for value in values) + ']' + (',' if index+1<len(rows) else ''))
        lines += ['  ]']
    lines += ['def main() -> IO(Unit):', '  do IO<Unit>:']
    for batch in range(len(batches)):
        lines += [f'    IO.print(show(normalize{"!" if gpu else ""}(inputs_{batch}())))']
    return '\n'.join(lines) + '\n'


def kernel_vectors(source, work):
    probe = work / 'kernels.c'
    probe.write_text('''#include <stdio.h>
#include <string.h>
#define STB_IMAGE_RESIZE_STATIC
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "external/stb_image_resize2.h"
int main(void) {
  for(int w=1;w<=17;w++) for(int n=1;n<=17;n++) {
    STBIR_RESIZE r;
    stbir_resize_init(&r,NULL,w,1,0,NULL,n,1,0,STBIR_RGBA,STBIR_TYPE_UINT8);
    if (!stbir_build_samplers(&r)) return 2;
    stbir__sampler *s=&r.samplers->horizontal;
    for(int p=0;p<n;p++) {
      stbir__contributors c=s->contributors[p];
      printf("%d",c.n0);
      for(int j=0;j<=c.n1-c.n0;j++) {
        unsigned bits; memcpy(&bits,s->coefficients+p*s->coefficient_width+j,4);
        printf(" %u",bits);
      }
      printf("\\n");
    }
    stbir_free_samplers(&r);
  }
  return 0;
}
''')
    binary = work / 'kernels'
    run(['clang', '-std=c11', '-O3', '-fno-strict-aliasing', '-I'+str(source/'src'), probe, '-lm', '-o', binary])
    return [[int(value) for value in line.split()] for line in run([binary]).splitlines()]


def bend_kernels(gpu=False):
    lines = ['import Base', 'import ../../src/resample.bend as R',
             'def bits(values: +List<F32>) -> List<U32>:', '  match values:',
             '    case Nil{}: Nil{}', '    case Con{v, rest}: Con{F32.bits(v), bits(rest)}',
             'def row(kernel: R.Kernel) -> List<U32>:', '  R.Kernel{first, weights} = kernel',
             '  Con{F32.to_u32(first), bits(weights)}',
             'def kernels(n: Nat, +i: U32, +w: U32, +out: U32) -> +List<R.Kernel>:',
             '  match n:', '    case 0n: Nil{}',
             '    case 1n+k: Con{R.Kernel.make(w, out, i), kernels(k, (i + 1 : U32), w, out)}',
             'def width(kernel: R.Kernel) -> U32:', '  R.Kernel{_, weights} = kernel',
             '  U32.from_nat(List.length(&2, F32, weights))',
             'def widest(values: +List<R.Kernel>) -> U32:', '  match values:',
             '    case Nil{}: 0', '    case Con{v, rest}: U32.max(width(v), widest(rest))',
             'def pack(values: +List<R.Kernel>, +wide: U32, +size: U32) -> List<List<U32>>:',
             '  match values:', '    case Nil{}: Nil{}',
             '    case Con{v, rest}: Con{row(R.Kernel.pack(wide, size, v)), pack(rest, wide, size)}',
             'def encoded(+values: +List<R.Kernel>, size: U32) -> List<List<U32>>:',
             '  pack(values, widest(values), size)',
             'def all(n: Nat, +w: U32, out: U32) -> List<List<U32>>:',
             '  encoded(kernels(n, 0, w, out), w)',
             'def show.row(values: List<U32>) -> String:', '  match values:',
             '    case Nil{}: ""', '    case Con{v, rest}: U32.show(v) ++ " " ++ show.row(rest)',
             'def show(values: List<List<U32>>) -> String:', '  match values:',
             '    case Nil{}: ""', '    case Con{v, rest}: show.row(v) ++ "\\n" ++ show(rest)',
             'def main() -> IO(Unit):', '  do IO<Unit>:']
    for w in range(1,18):
        for out in range(1,18):
            lines.append(f'    IO.print(show(all{"!" if gpu else ""}({out}n, {w}, {out})))')
    return '\n'.join(lines) + '\n'


def image_cases():
    rng = random.Random(20260925)
    cases = []
    for i in range(512):
        w, h, nw, nh = [rng.randint(1, limit) for limit in (11, 9, 17, 15)]
        pixels = [[rng.randrange(256), rng.randrange(256), rng.randrange(256),
                   rng.choice([0, 1, 2, 64, 128, 254, 255])] for _ in range(w*h)]
        operations = [dict(op='pixel', x=j%w, y=j//w, color=pixel) for j,pixel in enumerate(pixels)]
        operations.append(dict(op='resize', width=nw, height=nh))
        cases.append(dict(id=f'resize-{i:03}', width=w, height=h, background=[0,0,0,0], operations=operations))
    for i, (w,h,nw,nh,alpha) in enumerate([
        (1,1,1,1,0), (1,1,17,9,0), (7,5,7,5,255), (7,5,3,9,0),
        (31,1,3,1,255), (1,65,1,2,None), (33,35,3,2,None), (3,2,33,35,None),
        (17,13,1,1,None), (17,17,5,4,None), (17,17,2,17,None),
        (64,7,7,4,None), (4,64,13,1,None), (4096,1,1,1,None), (1,4096,1,1,None),
        (1,1,4096,1,128), (1,1,1,4096,128),
    ]):
        pixels = [[rng.randrange(256),rng.randrange(256),rng.randrange(256),
                   rng.choice([0,1,128,255]) if alpha is None else alpha] for _ in range(w*h)]
        if w*h > 512:
            # Large boundary images use 16 mixed-alpha bands, keeping generated
            # programs bounded while exercising the complete source allocation.
            horizontal = w >= h
            extent = w if horizontal else h
            step = (extent + 15) // 16
            operations = [dict(op='rectangle', x=at if horizontal else 0, y=0 if horizontal else at,
                               width=min(step,extent-at) if horizontal else w,
                               height=h if horizontal else min(step,extent-at), color=pixels[at//step])
                          for at in range(0,extent,step)]
        else:
            operations = [dict(op='pixel', x=j%w, y=j//w, color=pixel) for j,pixel in enumerate(pixels)]
        operations.append(dict(op='resize', width=nw, height=nh))
        cases.append(dict(id=f'resize-boundary-{i:02}', width=w, height=h, background=[0,0,0,0], operations=operations))
    return cases_from(dict(schema=1, cases=cases))


def verify_images(args, work):
    report_path = work / 'images-results.json'
    report_path.write_text(json.dumps(dict(passed=False)) + '\n')
    cases = image_cases()
    if args.case_prefix:
        cases = cases_from(dict(schema=1, cases=[case for case in cases if case['id'].startswith(args.case_prefix)]))
    library = BUILD / 'raylib/raylib/libraylib.a'
    if not library.is_file():
        raise ValueError('Run tools/conformance.py first to build the pinned reference')
    (work / 'images.json').write_text(json.dumps(dict(schema=1, cases=cases), indent=2) + '\n')
    reference_source = work / 'images.c'
    reference_source.write_text(c_source(cases))
    binary = work / 'images-reference'
    run(['clang', '-std=c11', '-O2', '-I'+str(args.raylib_source/'src'), reference_source, library, '-lm', '-o', binary])
    reference_text = run([binary])
    (work / 'images-reference.jsonl').write_text(reference_text)
    reference = parse_output(reference_text, cases)
    report = dict(passed=False, scenarios=len(cases), pixels=sum(w*h for w,h in map(result_size,cases)), lanes={},
                  source_sha256=source_gate(), fixtures_sha256=hashlib.sha256(json.dumps(cases,sort_keys=True).encode()).hexdigest(),
                  retained_counterexamples=[31,136,200,386], toolchain=json.loads((ROOT/'toolchain.json').read_text()),
                  host=dict(system=platform.system(), machine=platform.machine()),
                  reference_library_sha256=hashlib.sha256(library.read_bytes()).hexdigest())
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    lanes = [args.lane] if args.lane else ['cpu', 'javascript', *(['metal'] if args.gpu else [])]
    for name in lanes:
        outputs = []
        for batch, start in enumerate(range(0, len(cases), 64)):
            source = work / f'images-{name}-{batch}.bend'
            source.write_text(bend_source(cases[start:start+64], gpu=name=='metal').replace('import ../jonlib.bend', 'import ../../jonlib.bend'))
            binary = work / (f'images-{batch}.js' if name=='javascript' else f'images-{name}-{batch}')
            run(['bun', args.bend_source/'bend2/main.ts', source, '-o', binary])
            command = ['bun', binary] if name=='javascript' else [binary, *(['--gpu','on'] if name=='metal' else [])]
            outputs.append(run(command))
        output = ''.join(outputs)
        (work / f'images-{name}.jsonl').write_text(output)
        actual = parse_output(output, cases)
        compare(reference, actual)
        report['lanes'][name] = dict(passed=True)
        report_path.write_text(json.dumps(report, indent=2) + '\n')
        print(f'{name}: {len(cases)} default resize images, {report["pixels"]} exact pixels', flush=True)
    report['passed'] = True
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raylib-source', type=Path, default=Path.home() / 'Projetos/raysan5/raylib')
    parser.add_argument('--bend-source', type=Path, default=Path.home() / 'Projetos/bendlang/bend')
    parser.add_argument('--gpu', action='store_true')
    parser.add_argument('--images-only', action='store_true', help='Run whole-image comparisons without repeating coefficient probes')
    parser.add_argument('--lane', choices=('cpu', 'javascript', 'metal'), help='Run one image lane for focused diagnosis')
    parser.add_argument('--case-prefix', help='Select image cases by stable ID prefix for focused diagnosis')
    args = parser.parse_args()
    if args.lane == 'metal' and not args.gpu:
        parser.error('--lane metal requires --gpu')
    pins = json.loads((ROOT / 'toolchain.json').read_text())
    checkout(args.raylib_source, pins['raylib']['revision'])
    checkout(args.bend_source, pins['bend']['revision'], pins['bend'].get('patch'))
    work = BUILD / 'resize'
    work.mkdir(parents=True, exist_ok=True)
    if args.images_only:
        verify_images(args, work)
        return
    report_path = work / 'results.json'
    report_path.write_text(json.dumps(dict(passed=False)) + '\n')
    vectors, header_hash = coefficient_vectors(args.raylib_source, work)
    source = work / 'numeric.bend'
    source.write_text(bend_coefficients(vectors))
    cli = ['bun', args.bend_source / 'bend2/main.ts']
    run([*cli, source, '-o', work / 'numeric', '-o', work / 'numeric.js'])
    lanes = [('cpu', [work / 'numeric']), ('javascript', ['bun', work / 'numeric.js'])]
    if args.gpu:
        gpu_source = work / 'numeric_gpu.bend'
        gpu_source.write_text(bend_coefficients(vectors, gpu=True))
        run([*cli, gpu_source, '-o', work / 'numeric_gpu'])
        lanes.append(('metal', [work / 'numeric_gpu', '--gpu', 'on']))
    expected = [row['output'] for row in vectors]
    report = dict(passed=False, normalization_vectors=len(vectors), coefficients=sum(map(len, expected)),
                  header_sha256=header_hash, lanes={}, source_sha256=source_gate(),
                  toolchain=pins, host=dict(system=platform.system(), machine=platform.machine()))
    for name, command in lanes:
        actual = [[int(value) for value in line.split()] for line in run(command).splitlines() if line.strip()]
        (work / f'coefficients-{name}.json').write_text(json.dumps(actual) + '\n')
        mismatches = [i for i, (a, b) in enumerate(zip(actual, expected)) if a != b]
        if len(actual) != len(expected) or mismatches:
            report['mismatches'] = mismatches[:20]
            report_path.write_text(json.dumps(report, indent=2) + '\n')
            raise ValueError(f'{name}: normalization mismatch, rows {mismatches[:5]} ({len(actual)}/{len(expected)} rows)')
        report['lanes'][name] = dict(passed=True)
        print(f'{name}: {len(vectors)} normalization vectors, {report["coefficients"]} coefficient bits exact', flush=True)
    expected_kernels = kernel_vectors(args.raylib_source, work)
    for name in report['lanes']:
        source = work / f'kernels_{name}.bend'
        binary = work / ('kernels_js.js' if name == 'javascript' else f'kernels_{name}')
        source.write_text(bend_kernels(name == 'metal'))
        run([*cli, source, '-o', binary])
        command = ['bun', binary] if name == 'javascript' else [binary, *(['--gpu', 'on'] if name == 'metal' else [])]
        actual = [[int(value) for value in line.split()] for line in run(command).splitlines() if line.strip()]
        (work / f'kernels-{name}.json').write_text(json.dumps(actual) + '\n')
        (work / 'kernels-reference.json').write_text(json.dumps(expected_kernels) + '\n')
        mismatches = [i for i, (a,b) in enumerate(zip(actual, expected_kernels)) if a!=b]
        if len(actual) != len(expected_kernels) or mismatches:
            raise ValueError(f'{name}: kernel mismatch rows {mismatches[:10]} ({len(actual)}/{len(expected_kernels)})')
        print(f'{name}: {len(actual)} kernels match exact first index and coefficient bits', flush=True)
        report['lanes'][name]['kernels'] = len(actual)
    report['images'] = verify_images(args, work)
    report['passed'] = True
    report_path.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
