#!/usr/bin/env python3
"""Compare raylib's default resize core with an explicitly diagnostic float-normalization variant.

The stock library is always the reference. No variant changes conformance expectations.
"""
import hashlib
import json
import random

import probekit
from probekit import ProbeFailure


def fixtures(count):
    rng = random.Random(20260925)
    cases = []
    for i in range(count):
        w, h, nw, nh = [rng.randint(1, limit) for limit in (11, 9, 17, 15)]
        pixels = [[rng.randrange(256), rng.randrange(256), rng.randrange(256),
                   rng.choice([0, 1, 2, 64, 128, 254, 255])] for _ in range(w*h)]
        cases.append(dict(id=i, width=w, height=h, output_width=nw, output_height=nh, pixels=pixels))
    return cases


def reference_program(cases):
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
    return '\n'.join(c + ['return 0;', '}']) + '\n'


def main():
    args = probekit.arguments(__doc__, lambda parser: parser.add_argument('--cases', type=int, default=512), bend=False)
    if args.cases < 1:
        raise ProbeFailure('At least one resize probe is required')
    probe = probekit.Probe('filter', args)
    work = probe.work
    cases = fixtures(args.cases)
    (work / 'cases.json').write_text(json.dumps(cases, indent=2) + '\n')
    source = reference_program(cases)
    variants = {}
    summary = dict(reference=probe.lock['raylib'], seed=20260925, cases=len(cases), variants=variants,
                   header_sha256=hashlib.sha256((args.raylib_source / 'src/external/stb_image_resize2.h').read_bytes()).hexdigest(),
                   inputs_sha256=hashlib.sha256((work / 'cases.json').read_bytes()).hexdigest())
    for name, flags in [('stock-control', []), ('float-normalization', ['-DFLOAT_NORMALIZATION'])]:
        output = probe.native(source, name, extra_flags=['-O3', '-fno-strict-aliasing', *flags])
        rows = [json.loads(line) for line in output.splitlines()]
        if len(rows) != len(cases):
            raise ProbeFailure('Resize probe lost result rows')
        mismatches = [row for row in rows if row['different_channels']]
        (work / f'{name}.json').write_text(json.dumps(rows, indent=2) + '\n')
        variants[name] = dict(mismatching_cases=len(mismatches), different_channels=sum(row['different_channels'] for row in rows),
                              first_mismatches=mismatches[:5], output_sha256=hashlib.sha256(output.encode()).hexdigest())
        if name == 'float-normalization':
            summary['counterexamples'] = [dict(input=cases[row['id']], mismatch=row) for row in mismatches[:5]]
        print(name, {k: v for k, v in variants[name].items() if k != 'output_sha256'}, flush=True)
        # The one hard gate: the standalone stock core must reproduce linked raylib exactly.
        if name == 'stock-control' and mismatches:
            raise ProbeFailure('The standalone stock core did not match raylib; do not interpret the experiment')
    probe.report.update(summary)
    probe.diagnostic(cases=len(cases), **{f'{name}_mismatching_cases': v['mismatching_cases'] for name, v in variants.items()})
    print('Diagnostic only; no filtered-resize API is marked compatible by this experiment.')


if __name__ == '__main__':
    main()
