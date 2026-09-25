#!/usr/bin/env python3
"""Generate/check the complete API ledger and report evidence-backed progress."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess

if __package__:
    from .api_catalog import HEADERS, clang_audit, extract_catalog
else:
    from api_catalog import HEADERS, clang_audit, extract_catalog

ROOT = Path(__file__).resolve().parents[1]
API = ROOT / 'api'
STATUSES = {'not-started', 'in-progress', 'partial', 'blocked', 'complete'}
GATES = ('availability', 'behavior', 'ownership', 'integration', 'targets', 'performance')
DELTA_FIELDS = ('status', 'jonlib', 'scope', 'gaps', 'gates', 'evidence', 'blocker',
                'gate_evidence', 'target_results', 'milestone', 'api_dependencies')


def dump(value):
    return json.dumps(value, indent=2, ensure_ascii=False) + '\n'


def read(name):
    return json.loads((API / name).read_text())


def source_catalog(source):
    revision = json.loads((ROOT / 'toolchain.json').read_text())['raylib']['revision']
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, text=True).strip()
    if actual != revision:
        raise ValueError(f'Expected raylib {revision}, found {actual}')
    return extract_catalog(source, revision)


def classify(entry):
    header, kind, name, module, section = (entry[k] for k in ('header', 'kind', 'name', 'module', 'section'))
    lower = section.lower()
    if kind in ('configuration', 'switch'):
        return 'configuration'
    if kind == 'macro':
        if 'CLITERAL(Color)' in entry['signature']:
            return 'pixels'
        if name in ('PI', 'DEG2RAD', 'RAD2DEG', 'EPSILON'):
            return 'numerics'
        if header == 'raymath.h' and name in ('MatrixToFloat', 'Vector3ToFloat'):
            return 'raymath'
        if header == 'rlgl.h' and name.startswith('RL_') and 'DEFAULT_' not in name and 'TYPE' not in name:
            return 'rlgl-core'
        return 'configuration'
    if header == 'raymath.h':
        if kind == 'function' and name in ('Clamp', 'Lerp', 'Normalize', 'Remap', 'Wrap', 'FloatEquals'):
            return 'numerics'
        return 'raymath' if kind in ('function', 'operator', 'constant') else 'types'
    if kind not in ('function', 'operator'):
        return 'memory' if kind == 'callback' else 'types'
    if header == 'rcamera.h' or module == 'camera':
        return 'camera'
    if header == 'rgestures.h' or module == 'gestures':
        return 'input'
    if header == 'rlgl.h':
        return 'rlgl-advanced' if any(word in lower for word in ('buffer', 'shader', 'texture', 'framebuffer')) else 'rlgl-core'
    if module == 'textures':
        if name in ('LoadImageFromTexture', 'LoadImageFromScreen'):
            return 'textures'
        if name in ('ImageText', 'ImageTextEx', 'ImageDrawText', 'ImageDrawTextEx', 'GenImageText'):
            return 'fonts'
        if name in ('IsImageValid', 'GetImageAlphaBorder', 'GetImageColor', 'LoadImagePalette'):
            return 'images'
        if name in ('ImageResize', 'ImageResizeNN', 'ImageResizeCanvas', 'ImageFromImage', 'ImageCrop', 'ImageDraw', 'ImageMipmaps'):
            return 'resampling'
        if name == 'Fade' or name.startswith(('Color', 'GetColor', 'GetPixel', 'SetPixel', 'ImageFormat', 'LoadImageColors', 'UnloadImageColors')):
            return 'pixels'
        if name.startswith(('LoadImage', 'ExportImage')):
            return 'image-codecs'
        if name.startswith(('Image', 'GenImage', 'UnloadImage')):
            return 'images'
        return 'textures'
    if module == 'shapes':
        if name.startswith(('CheckCollision', 'GetCollision')):
            return 'collision'
        return 'textures' if 'ShapesTexture' in name else 'shapes'
    if module == 'text':
        return 'text-utils' if any(word in lower for word in ('strings management', 'codepoints management')) else 'fonts'
    if module == 'models':
        if 'Animation' in name or 'Animation' in section:
            return 'animation'
        if 'Material' in name:
            return 'materials'
        if 'Collision' in name or name.startswith('Get') and 'BoundingBox' in name:
            return 'collision'
        return 'models'
    if module == 'audio':
        if name == 'LoadSoundFromWave':
            return 'audio-device'
        if 'Music' in name or 'Stream' in name or 'Processor' in name:
            return 'audio-stream'
        if 'Wave' in name:
            return 'audio-codecs'
        return 'audio-device'
    if module == 'core':
        if 'AutomationEvent' in name:
            return 'frame'
        if name in ('BeginTextureMode', 'EndTextureMode', 'TakeScreenshot'):
            return 'textures'
        if name in ('BeginMode2D', 'EndMode2D', 'BeginBlendMode', 'EndBlendMode', 'BeginScissorMode', 'EndScissorMode', 'ClearBackground'):
            return 'shapes'
        if name in ('BeginMode3D', 'EndMode3D'):
            return 'models'
        if 'screen-space' in lower or 'Camera' in name:
            return 'camera'
        if 'Shader' in name:
            return 'shaders'
        if 'Vr' in name:
            return 'vr'
        if 'input-related' in lower:
            return 'input'
        if 'Random' in name:
            return 'random'
        if name.startswith('Mem') or 'TraceLog' in name:
            return 'memory'
        if 'file system' in lower or ('File' in name and 'Callback' in name):
            return 'files'
        if any(word in name for word in ('Window', 'Monitor', 'Clipboard', 'Cursor', 'EventWaiting')) or name in ('ToggleFullscreen', 'GetScreenWidth', 'GetScreenHeight', 'GetRenderWidth', 'GetRenderHeight', 'SetConfigFlags', 'OpenURL'):
            return 'window'
        return 'frame'
    raise ValueError(f'Unclassified function: {entry["id"]} ({module})')


def proposed(entry, milestone):
    name = entry['name']
    if entry['kind'] in ('type', 'alias', 'opaque', 'enum', 'callback'):
        return name
    if entry['kind'] == 'operator':
        return 'Math.' + name
    if entry['kind'] != 'function':
        return milestone['namespace'] + '.' + name
    if entry['header'] == 'raymath.h':
        for prefix in ('Quaternion', 'Vector2', 'Vector3', 'Vector4', 'Matrix'):
            if name.startswith(prefix):
                return prefix + '.' + snake(name[len(prefix):])
    if name.startswith('rl') and entry['header'] == 'rlgl.h':
        name = name[2:]
    return milestone['namespace'] + '.' + snake(name)


def snake(name):
    return re.sub(r'([a-z0-9])([A-Z])', r'\1_\2', re.sub(r'([A-Z]+)([A-Z][a-z])', r'\1_\2', name)).lower()


def local_evidence(value):
    return value.startswith(('https://', 'http://')) or (ROOT / value.split('#')[0]).is_file()


def acyclic(graph, label):
    visiting, done = set(), set()
    def visit(node):
        if node in visiting:
            raise ValueError(f'{label} dependency cycle at {node}')
        if node in done:
            return
        if node not in graph:
            raise ValueError(f'Unknown {label} dependency: {node}')
        visiting.add(node)
        for child in graph[node]:
            visit(child)
        visiting.remove(node)
        done.add(node)
    for node in graph:
        visit(node)


def make_ledger(reference, plan, progress):
    entries = reference['entries']
    ids = {entry['id'] for entry in entries}
    if len(ids) != len(entries):
        raise ValueError('Duplicate reference IDs')
    milestones = {item['id']: item for item in plan['milestones']}
    if len(milestones) != len(plan['milestones']):
        raise ValueError('Duplicate milestone IDs')
    acyclic({key: item['depends_on'] for key, item in milestones.items()}, 'milestone')
    updates = progress['entries']
    if reference.get('schema') != 1 or plan.get('schema') != 1 or progress.get('schema') != 1:
        raise ValueError('Expected API catalog/plan/progress schema 1')
    if tuple(plan['completion_gates']) != GATES:
        raise ValueError('Completion policy must retain all six parity gates')
    pin = json.loads((ROOT / 'toolchain.json').read_text())['raylib']['revision']
    if reference['revision'] != pin or reference['scope'] != list(HEADERS) or not entries:
        raise ValueError('Reference catalog must cover the pinned revision and headers')
    if set(updates) - ids:
        raise ValueError(f'Unknown progress IDs: {sorted(set(updates) - ids)}')
    direct = plan.get('api_dependencies', {})
    if (set(direct) | {target for row in direct.values() for target in row}) - ids:
        raise ValueError('Unknown API dependency ID')
    acyclic({key: direct.get(key, []) for key in ids}, 'API')
    if set(plan.get('priority_overrides', {})) - ids:
        raise ValueError('Unknown priority override ID')
    types = {}
    related = {}
    for entry in entries:
        related.setdefault((entry['kind'], entry['name']), []).append(entry['id'])
        if entry['kind'] in ('type', 'enum', 'alias', 'opaque', 'callback'):
            types.setdefault(entry['name'], []).append(entry)
    target_ids = {target['id'] for target in plan['targets']}
    if not target_ids or len(target_ids) != len(plan['targets']):
        raise ValueError('Target policy must be nonempty with unique IDs')
    symbols = set()
    for path in [ROOT / 'jonlib.bend', *sorted((ROOT / 'src').glob('**/*.bend'))]:
        if path.is_file():
            symbols.update(re.findall(r'^(?:def|type) ([\w.]+)', path.read_text(), re.M))
    rows = []
    for entry in entries:
        update = updates.get(entry['id'], {})
        status = update.get('status', 'not-started')
        if status not in STATUSES:
            raise ValueError(f'{entry["id"]}: invalid status {status}')
        milestone_id = update.get('milestone', classify(entry))
        if milestone_id not in milestones:
            raise ValueError(f'{entry["id"]}: unknown milestone')
        milestone = milestones[milestone_id]
        evidence = update.get('evidence', [])
        if any(not local_evidence(item) for item in evidence):
            raise ValueError(f'{entry["id"]}: missing evidence reference')
        if set(update.get('gates', {})) - set(GATES):
            raise ValueError(f'{entry["id"]}: unknown completion gate')
        gates = {gate: update.get('gates', {}).get(gate, 'unverified') for gate in GATES}
        if any(value not in ('unverified', 'partial', 'verified') for value in gates.values()):
            raise ValueError(f'{entry["id"]}: invalid gate status')
        if status in ('partial', 'complete') and (not update.get('jonlib') or not evidence):
            raise ValueError(f'{entry["id"]}: implemented status requires implementation and evidence')
        if status == 'blocked' and not update.get('blocker'):
            raise ValueError(f'{entry["id"]}: blocked status requires a concrete blocker')
        if status == 'complete':
            if update.get('gaps') or update.get('blocker') or any(value != 'verified' for value in gates.values()):
                raise ValueError(f'{entry["id"]}: completion requires all gates and no gaps')
            gate_evidence = update.get('gate_evidence', {})
            if any(not gate_evidence.get(gate) or any(not local_evidence(item) for item in gate_evidence[gate]) for gate in gates):
                raise ValueError(f'{entry["id"]}: completion requires evidence for every gate')
            if set(update.get('target_results', {})) != target_ids:
                raise ValueError(f'{entry["id"]}: completion requires every target to be accounted for')
            if entry['kind'] in ('function', 'operator') and (not update.get('symbols') or set(update['symbols']) - symbols):
                raise ValueError(f'{entry["id"]}: completed function requires actual Bend symbols')
            for result in update['target_results'].values():
                if result.get('status') not in ('verified', 'reference-not-supported') or not result.get('evidence') or not all(local_evidence(item) for item in result['evidence']):
                    raise ValueError(f'{entry["id"]}: target claim requires reference/verification evidence')
                if result['status'] == 'reference-not-supported' and not result.get('reason'):
                    raise ValueError(f'{entry["id"]}: reference target exclusion requires a reason')
        dependencies = []
        if entry['kind'] in ('function', 'callback', 'alias', 'operator', 'type', 'constant'):
            signatures = ' '.join(variant['signature'] for variant in entry['variants'])
            for name in sorted(set(re.findall(r'\b\w+\b', signatures)) & set(types)):
                choices = sorted(types[name], key=lambda t: (t['header'] != entry['header'], t['header'] != 'raylib.h', t['id']))
                if choices[0]['id'] != entry['id']:
                    dependencies.append(choices[0]['id'])
        if entry['kind'] == 'enumerator':
            dependencies.append(f'{entry["header"][:-2]}:enum:{entry["enum"]}')
        target = update.get('jonlib') or update.get('proposed_jonlib') or proposed(entry, milestone)
        if status == 'complete':
            next_step = 'Maintain the verified contract and rerun affected gates on changes.'
        elif update.get('blocker'):
            next_step = 'Resolve: ' + update['blocker']
        elif status == 'partial':
            next_step = 'Close documented gaps and unverified gates for ' + entry['name'] + '.'
        else:
            next_step = f'Derive {entry["name"]} semantics from the linked source, add a reference fixture, then implement {target}.'
        rows.append(dict(**entry, milestone=milestone_id, phase=milestone['phase'],
                         sequence=milestone['order'], status=status, jonlib=target,
                         mapping_state='implemented' if update.get('jonlib') and status in ('partial', 'complete') else 'proposed',
                         scope=update.get('scope', 'Entire declared contract, including conditional alternatives; detailed acceptance remains to be derived.'),
                         gaps=update.get('gaps', ['Implementation and full contract/platform verification pending.'] if status != 'complete' else []),
                         blocker=update.get('blocker'), gates=gates, evidence=evidence,
                         gate_evidence=update.get('gate_evidence', {}), target_results=update.get('target_results', {}),
                         symbols=update.get('symbols', []),
                         milestone_dependencies=milestone['depends_on'], type_dependencies=dependencies,
                         api_dependencies=direct.get(entry['id'], []),
                         related_declarations=[key for key in related[(entry['kind'], entry['name'])] if key != entry['id']],
                         verification=milestone['verify'], next_step=next_step,
                         priority=plan.get('priority_overrides', {}).get(entry['id'], 100 + milestone['phase'] * 100 + milestone['order'])))
    return dict(schema=1, reference_revision=reference['revision'], target_policy='Account for every applicable target in milestones.json; unsupported targets need source evidence.', entries=rows)


def summary(ledger, plan):
    rows = ledger['entries']
    core = [r for r in rows if r['header'] == 'raylib.h' and r['kind'] == 'function']
    functions = [r for r in rows if r['kind'] == 'function']
    def counts(items):
        return dict(total=len(items), **{state: sum(r['status'] == state for r in items) for state in sorted(STATUSES)})
    groups = []
    milestones = {item['id']: item for item in plan['milestones']}
    ordered, done = [], set()
    def schedule(item):
        if item['id'] not in done:
            for prerequisite in item['depends_on']:
                schedule(milestones[prerequisite])
            ordered.append(item)
            done.add(item['id'])
    for item in sorted(plan['milestones'], key=lambda x: (x['phase'], x['order'])):
        schedule(item)
    for milestone in ordered:
        members = [r for r in rows if r['milestone'] == milestone['id']]
        groups.append(dict(id=milestone['id'], title=milestone['title'], phase=milestone['phase'],
                           depends_on=milestone['depends_on'], **counts(members)))
    queue = sorted((r for r in rows if r['kind'] == 'function' and r['status'] != 'complete'),
                   key=lambda r: (r['priority'], r['status'] != 'partial', r['header'], r['line']))
    return dict(schema=1, reference_revision=ledger['reference_revision'],
                declaration_inventory=counts(rows), core_functions=counts(core), function_declarations=counts(functions),
                unique_c_function_names=len({r['name'] for r in functions}),
                kinds=dict(sorted(Counter(r['kind'] for r in rows).items())),
                headers={header: counts([r for r in rows if r['header'] == header]) for header in HEADERS},
                milestones=groups,
                next_work=[{key:r[key] for key in ('id','name','milestone','status','jonlib','next_step','milestone_dependencies','api_dependencies')} for r in queue[:20]])


def escape(value):
    return str(value).replace('|', '\\|').replace('\n', ' ')


def generated(reference, plan, progress):
    ledger = make_ledger(reference, plan, progress)
    report = summary(ledger, plan)
    outputs = {'api/ledger.json': dump(ledger), 'api/summary.json': dump(report)}
    legacy = {}
    for row in ledger['entries']:
        if row['header'] == 'raylib.h' and row['kind'] == 'function' and row['mapping_state'] == 'implemented':
            update = progress['entries'][row['id']]
            legacy[row['name']] = dict(jonlib=update['jonlib'], status=update.get('legacy_status', 'profile-covered'),
                                       scope=row['scope'], gaps=row['gaps'], api_id=row['id'], milestone=row['milestone'])
    outputs['docs/api-map.json'] = dump(legacy)
    dashboard = ['# API progression dashboard', '',
                 'Generated by `python3 tools/api_plan.py build`. Edit `api/progress.json` and `api/milestones.json`, not this page.', '',
                 '## Inventory and implementation are different', '',
                 f'- **{len(ledger["entries"])} declaration/support entries** are catalogued across all six scoped headers.',
                 f'- **{report["function_declarations"]["total"]} C function declarations**, representing **{report["unique_c_function_names"]} unique names**.',
                 f'- Core `raylib.h`: **{report["core_functions"]["total"]} functions**, **{report["core_functions"]["partial"]} partial**, **{report["core_functions"]["complete"]} complete**.',
                 '- Catalog coverage is not implementation completeness. Operators, constants, types and configuration controls have separate rows.',
                 '- Conditional variants and duplicate declarations are retained. Related IDs can share work, but do not automatically inherit completion.', '',
                 '## Complete checklists', '', '| Header | Entries | Checklist |', '|---|---:|---|']
    for header, counts in report['headers'].items():
        dashboard.append(f'| `{header}` | {counts["total"]} | [{header}](api/{header[:-2]}.md) |')
    dashboard += ['', '## Implementation sequence', '',
                  'Dependencies describe implementation prerequisites, not a requirement to finish every platform variant before starting a useful subset.', '',
                  '| Step | Phase | Work package | Entries | Partial | Complete | Prerequisites |', '|---|---:|---|---:|---:|---:|---|']
    for index, group in enumerate(report['milestones'], 1):
        dashboard.append(f'| {index} | {group["phase"]} | `{group["id"]}` — {group["title"]} | {group["total"]} | {group["partial"]} | {group["complete"]} | {", ".join(group["depends_on"]) or "—"} |')
    dashboard += ['', '## Next work queue', '', 'This is a priority queue with visible prerequisites, not a claim that every item is unblocked.', '']
    for row in report['next_work']:
        dashboard.append(f'- **`{row["id"]}`** ({row["status"]}, `{row["milestone"]}`): {row["next_step"]}')
    dashboard += ['', '## Closing an item', '',
                  'Mark `complete` only with all six gates verified, no remaining gaps, per-gate evidence and every target accounted for. A `reference-not-supported` target requires source evidence; it is not a way to discard difficult work.',
                  'Use `python3 tools/api_plan.py show API_ID` for an item and `python3 tools/api_plan.py report --since GIT_REF` for the actual progression delta.', '',
                  '## Target matrix', '',
                  'Each complete item needs results for these target configurations. Split hardware/OS/backend combinations in the linked evidence; build-only results are insufficient.', '',
                  '| Target ID | Required scope |', '|---|---|']
    dashboard += [f'| `{target["id"]}` | {target["scope"]} |' for target in plan['targets']]
    dashboard += ['', '[Tracking policy and update procedure](API-TRACKING.md)', '']
    outputs['docs/PROGRESS.md'] = '\n'.join(dashboard)
    for header in HEADERS:
        rows = [r for r in ledger['entries'] if r['header'] == header]
        lines = [f'# {header}: complete API/support checklist', '', '[Progress dashboard](../PROGRESS.md)', '',
                 'Generated from the pinned source; proposed Bend names are planning targets, not existing functions.',
                  'Each row inherits its milestone verification recipe and the six completion gates in the machine-readable ledger.', '',
                 '| Stable ID / source | Kind | Reference contract | Bend mapping | Status | Step |', '|---|---|---|---|---|---|']
        for row in rows:
            signature = row['signature']
            if row['kind'] in ('type', 'enum'):
                signature = row['name'] + ' — ' + '; '.join(row['variants'][0].get('members', []))
            lines.append(f'| [`{escape(row["id"])}`]({row["source"]}) | {row["kind"]} | `{escape(signature)}` | `{escape(row["jonlib"])}` ({row["mapping_state"]}) | {row["status"]} | `{row["milestone"]}` |')
        lines += ['', 'Full conditional variants, source lines, type/API dependencies, evidence and next actions are retained in [`api/ledger.json`](../../api/ledger.json).', '']
        outputs[f'docs/api/{header[:-2]}.md'] = '\n'.join(lines)
    return outputs, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('sync', 'build', 'check', 'report', 'show'))
    parser.add_argument('api_id', nargs='?')
    parser.add_argument('--raylib-source', type=Path)
    parser.add_argument('--since', help='Compare progression with this Git revision')
    parser.add_argument('--json', action='store_true', help='Print the full machine-readable report')
    parser.add_argument('--clang-audit', action='store_true', help='Independently audit function/overload counts using clang')
    args = parser.parse_args()
    if args.command == 'sync':
        if args.raylib_source is None:
            parser.error('sync requires --raylib-source')
        reference = source_catalog(args.raylib_source)
    else:
        reference = read('reference.json')
    plan, progress = read('milestones.json'), read('progress.json')
    outputs, report = generated(reference, plan, progress)
    if args.clang_audit:
        if args.raylib_source is None:
            parser.error('--clang-audit requires --raylib-source')
        audit = clang_audit(args.raylib_source, reference)
        print('Clang audit: ' + ', '.join(f'{row["header"]}/{row["language"]}={row["functions"]}' for row in audit))
    if args.command == 'sync':
        outputs['api/reference.json'] = dump(reference)
    if args.command in ('sync', 'build'):
        for relative, text in outputs.items():
            path = ROOT / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
    elif args.command == 'check':
        if args.raylib_source and source_catalog(args.raylib_source) != reference:
            raise ValueError('Pinned upstream source and committed reference catalog differ; review and sync explicitly')
        stale = [relative for relative, text in outputs.items() if not (ROOT / relative).is_file() or (ROOT / relative).read_text() != text]
        if stale:
            raise ValueError('Stale generated API files: ' + ', '.join(stale))
    elif args.command == 'show':
        rows = json.loads(outputs['api/ledger.json'])['entries']
        found = [row for row in rows if row['id'] == args.api_id]
        if len(found) != 1:
            raise ValueError('Supply an exact stable API ID from docs/PROGRESS.md or api/ledger.json')
        print(dump(found[0]))
        return
    elif args.command == 'report' and args.since:
        previous = json.loads(subprocess.check_output(['git', 'show', f'{args.since}:api/ledger.json'], cwd=ROOT, text=True))
        old = {row['id']: row for row in previous['entries']}
        rows = json.loads(outputs['api/ledger.json'])['entries']
        changed = [dict(id=row['id'], before=old.get(row['id'], {}).get('status', 'absent'), after=row['status'],
                        changes=[key for key in DELTA_FIELDS if old.get(row['id'], {}).get(key) != row.get(key)])
                   for row in rows if any(old.get(row['id'], {}).get(key) != row.get(key) for key in DELTA_FIELDS)]
        removed = sorted(set(old)-{row['id'] for row in rows})
        if args.json:
            print(dump(dict(summary=report, changed=changed, removed=removed)))
        else:
            for row in changed:
                print(f'{row["id"]}: {row["before"]} -> {row["after"]}; {", ".join(row["changes"])}')
            print(f'{len(changed)} changed entries; {len(removed)} removed entries')
        return
    if args.command == 'report' and args.json:
        print(dump(report))
    else:
        print(f'API plan {args.command}: {report["declaration_inventory"]["total"]} entries; {report["core_functions"]["partial"]}/600 core functions partial; {report["core_functions"]["complete"]} complete')
        if args.command == 'report':
            for row in report['next_work'][:5]:
                print(f'  {row["id"]} [{row["status"]}]: {row["next_step"]}')


if __name__ == '__main__':
    main()
