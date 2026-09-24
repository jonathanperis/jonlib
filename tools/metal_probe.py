#!/usr/bin/env python3
"""Diagnose Metal prefix failures; optional generated-C outlining experiment.

This never modifies Bend or Jonlib source and never changes the conformance gate.
A failed baseline remains a failure even when an experimental variant passes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess

from conformance import BUILD, ROOT, bend_source, cases_from, checkout, compare, parse_output, run, source_gate


def outline_circle(source):
    # This diagnostic is tied to the pinned compiler's emitted flat-loop layout.
    blocks = list(re.finditer(r'^INLINE Term (spin_\d+)\([^\n]*\) \{.*?^\}', source, re.M | re.S))
    matches = [block for block in blocks if 'Term _fuel_0' in block[0] and 'u32 _error_0' in block[0]]
    if len(matches) != 1:
        raise ValueError('Expected exactly one generated circle loop; refusing an ambiguous edit')
    block = matches[0]
    return source[:block.start()] + block[0].replace('INLINE Term', 'FAR Term', 1) + source[block.end():], block[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source', type=Path, default=Path.home() / 'Projetos/bendlang/bend')
    parser.add_argument('--counts', type=int, nargs='+', default=[20, 24, 26])
    parser.add_argument('--outline-circle', action='store_true', help='Also test one explicitly experimental no-inline generated-C change')
    args = parser.parse_args()
    if platform.system() != 'Darwin':
        raise ValueError('This diagnostic requires macOS and a real Metal device')
    lock = json.loads((ROOT / 'toolchain.json').read_text())
    checkout(args.bend_source, lock['bend']['revision'])
    cases = cases_from(json.loads((ROOT / 'tests/fixtures/images.json').read_text()))
    if any(count < 1 or count > len(cases) for count in args.counts):
        raise ValueError(f'Prefix counts must be 1..{len(cases)}')
    if json.loads((BUILD / 'scenarios.json').read_text()) != cases:
        raise ValueError('Run conformance.py first to establish the current reference fixtures')
    reference = parse_output((BUILD / 'reference.jsonl').read_text(), cases)
    report = dict(passed=False, bend=lock['bend'], sources=source_gate(),
                  reference_sha256=hashlib.sha256((BUILD / 'reference.jsonl').read_bytes()).hexdigest(),
                  experimental_outlining=args.outline_circle, results=[])
    report_path = BUILD / 'metal-probe.json'
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    for count in args.counts:
        source = BUILD / f'metal-prefix-{count}.bend'
        source.write_text(bend_source(cases[:count], gpu=True))
        c_file = BUILD / f'metal-prefix-{count}.c'
        run(['bun', args.bend_source / 'bend2/main.ts', source, '-o', c_file])
        original = c_file.read_text()
        variants = [('original', original, None)]
        if args.outline_circle:
            altered, symbol = outline_circle(original)
            variants.append(('outlined-experiment', altered, symbol))
        for variant, text, symbol in variants:
            stem = f'metal-{count}-{variant}'
            emitted = BUILD / f'{stem}.c'
            executable = BUILD / stem
            emitted.write_text(text)
            run(['clang', '-DBEND_METAL=1', '-x', 'objective-c', '-fobjc-arc',
                 '-fmodules', '-std=c11', '-O3', emitted, '-lpthread', '-lm', '-o', executable])
            for gpu in ('off', 'on'):
                result = subprocess.run([str(executable), '--gpu', gpu], capture_output=True, timeout=120)
                (BUILD / f'{stem}-{gpu}.stdout').write_bytes(result.stdout)
                (BUILD / f'{stem}-{gpu}.stderr').write_bytes(result.stderr)
                record = dict(count=count, variant=variant, gpu=gpu, exit_code=result.returncode,
                              passed=False, outlined_symbol=symbol,
                              stderr=result.stderr.decode(errors='replace')[-2000:])
                if result.returncode == 0:
                    try:
                        compare(reference[:count], parse_output(result.stdout.decode(), cases[:count]))
                        record['passed'] = True
                    except (ValueError, KeyError) as error:
                        record['comparison_error'] = str(error)
                report['results'].append(record)
                report_path.write_text(json.dumps(report, indent=2) + '\n')
                print(f'{count} scenarios / {variant} / GPU {gpu}: '
                      + ('exact pixel match' if record['passed'] else f'FAIL (exit {result.returncode})'), flush=True)
    report['passed'] = all(result['passed'] for result in report['results'])
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print('Diagnostic evidence: .build/metal-probe.json')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
