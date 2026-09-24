#!/usr/bin/env python3
"""Local compiler regression subset for the declared Bend overlay; no cluster access."""
import argparse
import json
from pathlib import Path
import re

from conformance import BUILD, ROOT, checkout, run

TESTS = [
    'run/metal_inline_budget', 'run/array_map_loop', 'run/matrix_multiply_array',
    'run/array_poly_elem', 'run/stencil3d', 'run/array_fork', 'run/array_atomic_fadd',
    'run/fork_leaf_result_loop', 'run/fork_shared_flat',
    'reg/spin_refs_dead_seg', 'reg/brw_spin_lent', 'reg/borrow_nested_flat',
    'reg/brw_arrays', 'compile/array_dynamic_closure',
    'compile/fork_leaf_budget', 'compile/fork_leaf_handoff',
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source', type=Path, default=Path.home() / 'Projetos/bendlang/bend')
    parser.add_argument('--gpu', action='store_true', help='Also force device execution for tests containing bang calls')
    args = parser.parse_args()
    lock = json.loads((ROOT / 'toolchain.json').read_text())['bend']
    checkout(args.bend_source, lock['revision'], lock.get('patch'))
    work = BUILD / 'bend-regressions'
    work.mkdir(parents=True, exist_ok=True)
    report = dict(passed=False, toolchain=lock, results=[])
    report_path = work / 'results.json'
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    cli = ['bun', args.bend_source / 'bend2/main.ts']
    for name in TESTS:
        source = args.bend_source / 'tests' / (name + '.bend')
        text = source.read_text()
        expected = '\n'.join(line[2:] for line in text.splitlines() if line.startswith('#|')).strip()
        if not expected:
            raise ValueError(f'{name}: missing upstream expected output')
        binary = work / name.replace('/', '-')
        c_file, js_file = Path(str(binary) + '.c'), Path(str(binary) + '.js')
        run([*cli, source, '--check-only'])
        run([*cli, source, '-o', c_file, '-o', js_file])
        device = args.gpu and re.search(r'!\(', '\n'.join(line for line in text.splitlines() if not line.startswith('#')))
        if device:
            run([*cli, source, '-o', binary])
        else:
            # Explicit CPU build avoids requiring a GPU on hosted macOS runners.
            run(['clang', '-std=c11', '-O3', c_file, '-lpthread', '-lm', '-o', binary])
        if name == 'run/metal_inline_budget':
            emitted = c_file.read_text()
            if 'FAR Term call_spin_' not in emitted or not re.search(r'^FAR Term spin_\d+', emitted, re.M):
                raise ValueError('The regression must combine a Metal dispatch boundary with an existing FAR helper')
        lanes = [('cpu', [binary, '--gpu', 'off', '--threads', '2']), ('javascript', ['bun', js_file])]
        if device:
            lanes.append(('gpu-forced', [binary, '--gpu', 'on']))
        for lane, command in lanes:
            actual = run(command).strip()
            if actual != expected:
                raise ValueError(f'{name}/{lane}: expected {expected!r}, got {actual!r}')
        report['results'].append(dict(test=name, lanes=[lane for lane, _ in lanes], passed=True))
        report_path.write_text(json.dumps(report, indent=2) + '\n')
        print(name + ': ' + ', '.join(lane for lane, _ in lanes) + ' PASS', flush=True)
    report['passed'] = True
    report_path.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
