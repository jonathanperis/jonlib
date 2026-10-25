#!/usr/bin/env python3
"""Run the conformance gates declared in tools/gates.json.

Every gate is one command. `--shard K/N` runs a deterministic, duration-balanced
subset so CI can spread the gates over parallel jobs; every gate belongs to
exactly one shard. Diagnostic entries record evidence but are never parity
claims. Each gate's outcome and duration is written to .build/gates/<id>.json,
and the run writes .build/gate-results.json (id and pass/fail). The run fails
if a selected gate fails.

`--only` takes one id or several (repeatable, or comma- or space-separated).
`--failed-from FILE` reruns the gates that file recorded as failed.
`--plan-dispatch` resolves a manual pick or a rerun of a workflow run into
per-host shards for the Conformance pick workflow.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'tools' / 'gates.json'
OUT = ROOT / '.build' / 'gates'
RESULTS = ROOT / '.build' / 'gate-results.json'
# A picked list stays one job while it is only a few gates and under this many
# estimated minutes. Past either limit it is split into duration-balanced shards,
# at most the full matrix of 15.
FEW_GATES = 4
SHARD_MINUTES = 90
MAX_SHARDS = 15
HOST_ARTIFACTS = {'linux': 'gate-results-ubuntu-24.04', 'macos': 'gate-results-macos-15'}


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


def split_ids(values):
    """Ids from repeatable values, splitting each on commas and whitespace. Order kept, duplicates dropped."""
    found = []
    for value in values or []:
        for part in re.split(r'[\s,]+', value.strip()):
            if part and part not in found:
                found.append(part)
    return found


def unknown_ids(ids, gates):
    known = {gate['id'] for gate in gates}
    return [gate_id for gate_id in ids if gate_id not in known]


def pick_shards(gates, few=FEW_GATES, budget=SHARD_MINUTES, limit=MAX_SHARDS):
    """One group, or duration-balanced shards when the list is more than a few gates or over the budget."""
    if not gates:
        return []
    total = sum(gate.get('minutes', 1) for gate in gates)
    if len(gates) <= few and total <= budget:
        return [list(gates)]
    count = min(limit, len(gates), max(2, math.ceil(total / budget), math.ceil(len(gates) / few)))
    return [part for part in shards(gates, count)[0] if part]


def write_results(path, os_name, records):
    """Machine-readable id and pass/fail for the gates this invocation ran, in run order."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    document = dict(os=os_name, gates=[dict(id=item['id'], passed=True if item['passed'] else False) for item in records])
    path.write_text(json.dumps(document, indent=1) + '\n')
    return document


def failed_ids(document):
    """Ids whose `passed` is false. Raises ValueError when the document is not a result file."""
    if not isinstance(document, dict) or not isinstance(document.get('gates'), list):
        raise ValueError('results file must be an object with a gates list')
    if document.get('os') not in ('linux', 'macos'):
        raise ValueError('results file os must be linux or macos')
    found = []
    for entry in document['gates']:
        if not isinstance(entry, dict) or not isinstance(entry.get('id'), str) or not isinstance(entry.get('passed'), bool):
            raise ValueError('each gate result needs an id and a boolean passed')
        if entry['passed'] is False:
            found.append(entry['id'])
    return found


def read_results(path):
    try:
        document = json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f'results file is unreadable ({error})')
    failed_ids(document)
    return document


def merge_results(documents):
    """One document per host. A gate repeated across shards stays failed if any shard failed."""
    order, passed = {}, {}
    for document in documents:
        failed_ids(document)
        os_name = document['os']
        order.setdefault(os_name, [])
        passed.setdefault(os_name, {})
        for entry in document['gates']:
            if entry['id'] not in passed[os_name]:
                order[os_name].append(entry['id'])
            passed[os_name][entry['id']] = passed[os_name].get(entry['id'], True) and entry['passed']
    return [dict(os=os_name, gates=[dict(id=gate_id, passed=passed[os_name][gate_id]) for gate_id in ids])
            for os_name, ids in order.items()]


def merge_result_tree(directory):
    paths = sorted(Path(directory).rglob('*.json'))
    if not paths:
        raise ValueError(f'no result files in {directory}')
    merged = merge_results([read_results(path) for path in paths])
    if len(merged) != 1:
        raise ValueError('expected results for one host, got ' + ', '.join(document['os'] for document in merged))
    return merged[0]


def dispatch_plan(gates_text, hosts_choice, rerun_run, manifest, documents=None):
    """Per-host shard rows for a manual pick or a failed-gate rerun.

    A rerun uses the hosts that failed in `documents` and ignores `hosts_choice`.
    Returns {os: [row, ...]} and omits hosts with nothing to run.
    """
    gates_text = (gates_text or '').strip()
    rerun_run = (str(rerun_run) if rerun_run is not None else '').strip()
    if gates_text and rerun_run:
        raise ValueError('pass gates or rerun_failed_from, not both')
    if not gates_text and not rerun_run:
        raise ValueError('set gates or rerun_failed_from')
    by_id = {gate['id']: gate for gate in manifest}
    if rerun_run:
        if not re.fullmatch(r'\d+', rerun_run):
            raise ValueError('rerun_failed_from must be a run id')
        if documents is None:
            raise ValueError('rerun results are missing')
        selected = {}
        for document in documents:
            os_name = document.get('os')
            if os_name not in ('linux', 'macos'):
                raise ValueError('results file os must be linux or macos')
            for gate_id in failed_ids(document):
                if gate_id not in by_id:
                    raise ValueError(f'unknown gate id: {gate_id}')
                chosen = selected.setdefault(os_name, [])
                if gate_id not in chosen:
                    chosen.append(gate_id)
        if not selected:
            return {}
    else:
        choice = hosts_choice or 'linux'
        if choice not in ('linux', 'macos', 'both'):
            raise ValueError(f'unknown hosts choice: {choice}')
        ids = split_ids([gates_text])
        missing = unknown_ids(ids, manifest)
        if missing:
            raise ValueError('unknown gate id: ' + ', '.join(missing))
        wanted = ('linux', 'macos') if choice == 'both' else (choice,)
        selected = {}
        for os_name in wanted:
            absent = [gate_id for gate_id in ids if os_name not in by_id[gate_id]['os']]
            if absent and choice != 'both':
                raise ValueError(f'not declared for {os_name}: ' + ', '.join(absent))
            chosen = [gate_id for gate_id in ids if os_name in by_id[gate_id]['os']]
            if chosen:
                selected[os_name] = chosen
        if not selected:
            raise ValueError('no selected gate runs on the chosen hosts')
    rows = {}
    for os_name, ids in selected.items():
        parts = pick_shards([by_id[gate_id] for gate_id in ids])
        count = len(parts)
        rows[os_name] = [dict(shard=str(index), count=str(count), gates=','.join(gate['id'] for gate in part))
                         for index, part in enumerate(parts, 1)]
    return rows


def describe_plan(rows):
    if not rows:
        return 'No failed gates to rerun.'
    lines = []
    for os_name in ('linux', 'macos'):
        for row in rows.get(os_name, []):
            lines.append(f'{os_name} {row["shard"]}/{row["count"]}: {row["gates"]}')
    return '\n'.join(lines)


def write_outputs(path, rows):
    """GitHub Actions outputs. An idle row keeps a skipped job's matrix valid."""
    lines = []
    for os_name in ('linux', 'macos'):
        chosen = rows.get(os_name) or []
        payload = chosen or [dict(shard='1', count='1', gates='')]
        lines.append(f'run_{os_name}={"yes" if chosen else "no"}')
        lines.append(f'{os_name}={json.dumps(payload)}')
    text = '\n'.join(lines) + '\n'
    if path:
        with open(path, 'a') as handle:
            handle.write(text)
    return text


def download_run_results(run_id, repo, dest, run=None):
    """Result documents for a workflow run: the per-host artifact, or the shard artifacts if that is all it has."""
    if not re.fullmatch(r'\d+', str(run_id)):
        raise ValueError('rerun_failed_from must be a run id')
    run = run or subprocess.run
    dest = Path(dest)
    dest.mkdir(parents=True, exist_ok=True)
    documents, got = [], set()
    for os_name, name in HOST_ARTIFACTS.items():
        target = dest / name
        result = run(['gh', 'run', 'download', str(run_id), '--repo', repo, '--name', name, '--dir', str(target)],
                     capture_output=True, text=True)
        if result.returncode != 0:
            continue
        parsed = [read_results(path) for path in sorted(target.rglob('*.json'))]
        if parsed:
            got.add(os_name)
            documents.extend(parsed)
    if len(got) < len(HOST_ARTIFACTS):
        # A host whose merged artifact is missing may still have shard files.
        target = dest / 'shards'
        result = run(['gh', 'run', 'download', str(run_id), '--repo', repo, '--pattern', 'gate-results-*', '--dir', str(target)],
                     capture_output=True, text=True)
        if result.returncode == 0:
            for path in sorted(target.rglob('*.json')):
                document = read_results(path)
                if document['os'] not in got:
                    documents.append(document)
    if not documents:
        raise ValueError(f'run {run_id} has no gate-results artifacts')
    return merge_results(documents)


def summarize(value, depth=0):
    """Keep scalars and small structures; replace bulky lists/objects by their size."""
    if isinstance(value, dict):
        if depth > 2 or len(value) > 40:
            return {'items': len(value)}
        return {k: summarize(v, depth + 1) for k, v in value.items()}
    if isinstance(value, list):
        if len(value) > 12 or any(isinstance(v, (dict, list)) for v in value):
            return {'items': len(value)}
        return value
    if isinstance(value, str) and len(value) > 200:
        return value[:200] + '...'
    return value


def results_files():
    """Every probe results file with its modification stamp and size."""
    files = [p for p in (ROOT / '.build').rglob('results.json') if OUT not in p.parents]
    files += [p for p in [ROOT / '.build/conformance.json'] if p.exists()]
    return {p: (p.stat().st_mtime_ns, p.stat().st_size) for p in files}


def evidence(gate, before, passed, elapsed, os_name):
    """Compact summary of every results file the gate wrote (full files stay CI artifacts)."""
    files = sorted(p for p, stamp in results_files().items() if before.get(p) != stamp)
    reports = {}
    for path in files:
        raw = path.read_bytes()
        reports[str(path.relative_to(ROOT))] = dict(sha256=hashlib.sha256(raw).hexdigest(), summary=summarize(json.loads(raw)))
    lock = json.loads((ROOT / 'toolchain.json').read_text())
    return dict(gate=gate['id'], title=gate.get('title', ''), passed=passed, diagnostic=gate.get('diagnostic', False),
                os=os_name, machine=platform.machine(), seconds=elapsed,
                toolchain=dict(bend=lock['bend']['revision'], raylib=lock['raylib']['revision'], bun=lock['bun']['version']),
                reports=reports)


def command(gate, args):
    values = {'bend': str(args.bend_source), 'raylib': str(args.raylib_source), 'python': sys.executable}
    return [part.format(**values) for part in gate['run']]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend-source', type=Path)
    parser.add_argument('--raylib-source', type=Path)
    parser.add_argument('--shard', default='1/1', help='K/N: run the K-th of N balanced shards')
    parser.add_argument('--os', default=host_os(), choices=('linux', 'macos'))
    parser.add_argument('--only', action='append', default=[], help='gate ids to run (repeatable, comma- or space-separated)')
    parser.add_argument('--failed-from', type=Path, help='rerun gates recorded as failed in this results file')
    parser.add_argument('--results', type=Path, help=f'results file to write (default {RESULTS})')
    parser.add_argument('--plan', action='store_true', help='print the shard plan and exit')
    parser.add_argument('--plan-dispatch', action='store_true', help='resolve a manual pick or rerun into per-host shards and exit')
    parser.add_argument('--gates', default='', help='with --plan-dispatch, comma- or space-separated gate ids')
    parser.add_argument('--hosts', default='linux', choices=('linux', 'macos', 'both'), help='with --plan-dispatch, hosts for a picked run')
    parser.add_argument('--rerun-run', default='', help='with --plan-dispatch, workflow run id whose failed gates to rerun')
    parser.add_argument('--merge-results', type=Path, help='directory of shard result files to merge into one host file')
    parser.add_argument('--record', type=Path, help='also write compact per-gate evidence into this directory')
    parser.add_argument('--jobs', type=int, help='batches each probe compiles/runs concurrently (sets PROBEKIT_JOBS)')
    args = parser.parse_args(argv)
    if args.plan_dispatch:
        # Always publish a matrix, including after a refusal, so a skipped host job still expands.
        rows, code = {}, 0
        try:
            documents = None
            rerun = str(args.rerun_run).strip()
            if rerun:
                if not re.fullmatch(r'\d+', rerun):
                    raise ValueError('rerun_failed_from must be a run id')
                repo = os.environ.get('GITHUB_REPOSITORY', '')
                if not repo:
                    raise ValueError('GITHUB_REPOSITORY is not set')
                documents = download_run_results(rerun, repo, ROOT / '.build' / 'rerun-results')
            rows = dispatch_plan(args.gates, args.hosts, rerun, load(), documents)
        except ValueError as error:
            print(f'error: {error}', file=sys.stderr)
            code = 2
        if os.environ.get('GITHUB_OUTPUT'):
            write_outputs(os.environ['GITHUB_OUTPUT'], {} if code else rows)
        if code == 0:
            summary = describe_plan(rows)
            print(summary)
            if os.environ.get('GITHUB_STEP_SUMMARY'):
                with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as handle:
                    print(summary, file=handle)
        return code
    if args.merge_results:
        try:
            document = merge_result_tree(args.merge_results)
            write_results(args.results or RESULTS, document['os'], document['gates'])
        except ValueError as error:
            print(f'error: {error}', file=sys.stderr)
            return 2
        print(f"Merged {len(document['gates'])} gates for {document['os']}.")
        return 0
    if not args.bend_source or not args.raylib_source:
        parser.error('the following arguments are required: --bend-source, --raylib-source')
    index, count = map(int, args.shard.split('/'))
    if not 1 <= index <= count:
        parser.error('--shard must be K/N with 1 <= K <= N')
    manifest = load()
    gates = [g for g in manifest if args.os in g['os']]
    plan, minutes = shards(gates, count)
    if args.plan:
        for i, (selected, total) in enumerate(zip(plan, minutes), 1):
            print(f'shard {i}/{count}: ~{total:.0f} min, {len(selected)} gates: ' + ', '.join(g['id'] for g in selected))
        return 0
    only_ids = split_ids(args.only)
    if only_ids:
        missing = unknown_ids(only_ids, manifest)
        if missing:
            print('unknown gate id: ' + ', '.join(missing), file=sys.stderr)
            return 2
    chosen, restrict = only_ids, bool(only_ids)
    if args.failed_from:
        try:
            document = read_results(args.failed_from)
        except ValueError as error:
            print(f'error: {error}', file=sys.stderr)
            return 2
        if document['os'] != args.os:
            print(f"results file is for {document['os']}, this run is {args.os}", file=sys.stderr)
            return 2
        failed = failed_ids(document)
        missing = unknown_ids(failed, manifest)
        if missing:
            print('unknown gate id: ' + ', '.join(missing), file=sys.stderr)
            return 2
        chosen = [gate_id for gate_id in failed if gate_id in only_ids] if only_ids else list(failed)
        restrict = True
        if not chosen:
            write_results(args.results or RESULTS, args.os, [])
            print(f'No failed gates in {args.failed_from}.')
            return 0
    if restrict:
        on_host = {gate['id'] for gate in manifest if args.os in gate['os']}
        absent = [gate_id for gate_id in chosen if gate_id not in on_host]
        if absent:
            print(f'not declared for {args.os}: ' + ', '.join(absent), file=sys.stderr)
            return 2
    selected = [g for g in plan[index - 1] if not restrict or g['id'] in chosen]
    OUT.mkdir(parents=True, exist_ok=True)
    results_path = args.results or RESULTS
    records, failures = [], []
    write_results(results_path, args.os, records)
    for gate in selected:
        print(f'::group::{gate["id"]}' if os.environ.get('GITHUB_ACTIONS') else f'== {gate["id"]}', flush=True)
        started, before = time.monotonic(), results_files()
        env = dict(os.environ, BEND_NO_TELEMETRY='1', **({'PROBEKIT_JOBS': str(args.jobs)} if args.jobs else {}))
        result = subprocess.run(command(gate, args), cwd=ROOT, env=env)
        elapsed = round(time.monotonic() - started, 1)
        passed = result.returncode == 0
        record = evidence(gate, before, passed, elapsed, args.os)
        (OUT / f'{gate["id"]}.json').write_text(json.dumps(record, indent=1) + '\n')
        if args.record and passed:
            args.record.mkdir(parents=True, exist_ok=True)
            (args.record / f'{gate["id"]}-{args.os}.json').write_text(json.dumps(record, indent=1) + '\n')
        records.append(dict(id=gate['id'], passed=passed))
        write_results(results_path, args.os, records)
        if os.environ.get('GITHUB_ACTIONS'):
            print('::endgroup::', flush=True)
        print(f'{"PASS" if passed else "FAIL"} {gate["id"]} ({elapsed:.0f}s)', flush=True)
        if not passed:
            failures.append(gate['id'])
    print(f'Results: {results_path}', flush=True)
    if failures:
        print('Failed gates: ' + ', '.join(failures), flush=True)
        return 1
    print(f'All {len(selected)} gates in shard {index}/{count} passed on {args.os}.', flush=True)
    return 0


if __name__ == '__main__':
    sys.exit(main())
