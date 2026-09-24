#!/usr/bin/env python3
"""Compare raylib's default resize core with an explicitly diagnostic float-normalization variant.

The stock library is always the reference. No variant changes conformance expectations.
"""
import argparse
import hashlib
import json
from pathlib import Path
import random

from conformance import BUILD, ROOT, checkout, run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raylib-source', type=Path, default=Path.home() / 'Projetos/raysan5/raylib')
    parser.add_argument('--cases', type=int, default=512)
    args = parser.parse_args()
    if args.cases < 1:
        raise ValueError('At least one resize probe is required')
    lock = json.loads((ROOT / 'toolchain.json').read_text())['raylib']
    checkout(args.raylib_source, lock['revision'])
    library = BUILD / 'raylib/raylib/libraylib.a'
    if not library.is_file():
        raise ValueError('Run tools/conformance.py first to build the pinned reference library')
    work = BUILD / 'filter-probe'
    work.mkdir(exist_ok=True)
    rng = random.Random(20260925)
    cases = []
    for i in range(args.cases):
        w, h, nw, nh = [rng.randint(1, limit) for limit in (11, 9, 17, 15)]
        pixels = [[rng.randrange(256), rng.randrange(256), rng.randrange(256),
                   rng.choice([0, 1, 2, 64, 128, 254, 255])] for _ in range(w*h)]
        cases.append(dict(id=i, width=w, height=h, output_width=nw, output_height=nh, pixels=pixels))
    (work / 'cases.json').write_text(json.dumps(cases, indent=2) + '\n')
    c = [
        '#include "raylib.h"', '#include <stdio.h>', '#include <stdlib.h>', '#include <string.h>',
        '#define STB_IMAGE_RESIZE_STATIC', '#define STB_IMAGE_RESIZE_IMPLEMENTATION',
        '#ifdef FLOAT_NORMALIZATION', '#define STBIR_RENORMALIZE_IN_FLOAT', '#endif',
        '#include "external/stb_image_resize2.h"',
        'static void probe(int id, int w, int h, int nw, int nh, unsigned char *pixels) {',
        '  Image reference = GenImageColor(w, h, BLANK);',
        '  memcpy(reference.data, pixels, (size_t)w*h*4);',
        '  ImageResize(&reference, nw, nh);',
        '  unsigned char *candidate = stbir_resize_uint8_linear(pixels, w, h, 0, NULL, nw, nh, 0, STBIR_RGBA);',
        '  if (!candidate) exit(2);',
        '  unsigned char *actual = (unsigned char *)reference.data;',
        '  int differences = 0, first = -1;',
        '  for (int i = 0; i < nw*nh*4; i++) if (actual[i] != candidate[i]) { differences++; if (first < 0) first = i; }',
        '  printf(' + json.dumps('{"id":%d,"different_channels":%d,"first_index":%d,"reference":%d,"candidate":%d}\n')
        + ', id, differences, first, first < 0 ? -1 : actual[first], first < 0 ? -1 : candidate[first]);',
        '  free(candidate); UnloadImage(reference);', '}', 'int main(void) { SetTraceLogLevel(LOG_NONE);',
    ]
    # Emit independent raw inputs; neither reference result is synthesized in Python.
    for case in cases:
        pixels = ','.join(str(c) for pixel in case['pixels'] for c in pixel)
        c += ['{', f'unsigned char pixels[] = {{{pixels}}};',
              f'probe({case["id"]},{case["width"]},{case["height"]},{case["output_width"]},{case["output_height"]},pixels);', '}']
    c += ['return 0;', '}']
    source = work / 'probe.c'
    source.write_text('\n'.join(c) + '\n')
    report = dict(reference=lock, seed=20260925, cases=len(cases), variants={},
                  header_sha256=hashlib.sha256((args.raylib_source / 'src/external/stb_image_resize2.h').read_bytes()).hexdigest(),
                  inputs_sha256=hashlib.sha256((work / 'cases.json').read_bytes()).hexdigest())
    for name, flags in [('stock-control', []), ('float-normalization', ['-DFLOAT_NORMALIZATION'])]:
        binary = work / name
        run(['clang', '-std=c11', '-O3', '-fno-strict-aliasing', *flags,
             '-I' + str(args.raylib_source / 'src'), source, library, '-lm', '-o', binary])
        output = run([binary])
        rows = [json.loads(line) for line in output.splitlines()]
        if len(rows) != len(cases):
            raise ValueError('Resize probe lost result rows')
        mismatches = [row for row in rows if row['different_channels']]
        (work / f'{name}.json').write_text(json.dumps(rows, indent=2) + '\n')
        report['variants'][name] = dict(mismatching_cases=len(mismatches), different_channels=sum(row['different_channels'] for row in rows), first_mismatches=mismatches[:5])
        if name == 'float-normalization':
            report['counterexamples'] = [dict(input=cases[row['id']], mismatch=row) for row in mismatches[:5]]
        print(name, report['variants'][name], flush=True)
        if name == 'stock-control' and mismatches:
            raise ValueError('The standalone stock core did not match raylib; do not interpret the experiment')
    (work / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Diagnostic only; no filtered-resize API is marked compatible by this experiment.')


if __name__ == '__main__':
    main()
