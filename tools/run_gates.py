#!/usr/bin/env python3
"""Run the conformance gates declared in tools/gates.json.

Every gate is one command. `--shard K/N` runs a deterministic, duration-balanced
subset so CI can spread the gates over parallel jobs; every gate belongs to
exactly one shard. Diagnostic entries record evidence but are never parity
claims. Each gate's outcome and duration is written to .build/gates/<id>.json;
the run fails if any non-diagnostic gate fails.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'tools' / 'gates.json'
OUT = ROOT / '.build' / 'gates'


def load(path=MANIFEST):
    gates = json.loads(Path(path).read_text())['gates']
    ids = [g['id'] for g in gates]
    if len(ids) != len(set(ids)):
        raise ValueError('duplicate gate ids')
    return gates


def host_os():
    return {'Linux': 'linux', 'Darwin': 'macos'}.get(platform.system(), platform.system().lower())


def shards(gates, count):
    """Longest-processing-time assignment: deterministic and roughly balanced."""
    bins = [[] for _ in range(count)]
    load_minutes = [0.0] * count
    for gate in sorted(gates, key=lambda g: (-g['minutes'], g['id'])):
        target = min(range(count), key=lambda i: (load_minutes[i], i))
        bins[target].append(gate)
        load_minutes[target] += gate['minutes']
    order = {g['id']: i for i, g in enumerate(gates)}
    return [sorted(b, key=lambda g: order[g['id']]) for b in bins], load_minutes


def command(gate, args):
    values = {'bend': str(args.bend_source), 'raylib': str(args.raylib_source), 'python': sys.executable}
    return [part.format(**values) for part in gate['run']]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source', type=Path, required=True)
    parser.add_argument('--raylib-source', type=Path, required=True)
    parser.add_argument('--shard', default='1/1', help='K/N: run the K-th of N balanced shards')
    parser.add_argument('--os', default=host_os(), choices=('linux', 'macos'))
    parser.add_argument('--only', action='append', default=[], help='run only these gate ids')
    parser.add_argument('--plan', action='store_true', help='print the shard plan and exit')
    args = parser.parse_args(argv)
    index, count = map(int, args.shard.split('/'))
    if not 1 <= index <= count:
        parser.error('--shard must be K/N with 1 <= K <= N')
    gates = [g for g in load() if args.os in g['os']]
    plan, minutes = shards(gates, count)
    if args.plan:
        for i, (selected, total) in enumerate(zip(plan, minutes), 1):
            print(f'shard {i}/{count}: ~{total:.0f} min, {len(selected)} gates: ' + ', '.join(g['id'] for g in selected))
        return 0
    selected = [g for g in plan[index - 1] if not args.only or g['id'] in args.only]
    OUT.mkdir(parents=True, exist_ok=True)
    failures = []
    for gate in selected:
        print(f'::group::{gate["id"]}' if os.environ.get('GITHUB_ACTIONS') else f'== {gate["id"]}', flush=True)
        started = time.monotonic()
        result = subprocess.run(command(gate, args), cwd=ROOT, env=dict(os.environ, BEND_NO_TELEMETRY='1'))
        elapsed = round(time.monotonic() - started, 1)
        passed = result.returncode == 0
        (OUT / f'{gate["id"]}.json').write_text(json.dumps(dict(id=gate['id'], passed=passed, diagnostic=gate.get('diagnostic', False),
                                                                returncode=result.returncode, seconds=elapsed, os=args.os)) + '\n')
        if os.environ.get('GITHUB_ACTIONS'):
            print('::endgroup::', flush=True)
        print(f'{"PASS" if passed else "FAIL"} {gate["id"]} ({elapsed:.0f}s)', flush=True)
        if not passed:
            failures.append(gate['id'])
    if failures:
        print('Failed gates: ' + ', '.join(failures), flush=True)
        return 1
    print(f'All {len(selected)} gates in shard {index}/{count} passed on {args.os}.', flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
