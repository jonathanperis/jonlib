#!/usr/bin/env python3
"""Derive behavior, ownership, integration and performance gates from evidence.

The rules are the ones in docs/API-TRACKING.md. A stored `verified` value that
this module does not derive is rejected by `python3 tools/api_plan.py check`.
`--apply` rewrites only the `gates` object of each progress record.
"""
import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PROGRESS = ROOT / 'api' / 'progress.json'
GATES = ('availability', 'behavior', 'ownership', 'integration', 'targets', 'performance')
# Same allow-list as the Phase 1 exit measure. Libm: is open behavior work.
ALLOWED_GAPS = ('Targets:', 'Integration:', 'Performance:', 'Undefined native behavior:')
# A Targets gap may still withdraw a CI host. Metal is not one of those hosts.
HOST_UNCLAIMED = re.compile(r'\b(?:macOS|Linux) is not verified\b')
CI_HOSTS = frozenset(('linux', 'macos'))
EXACT_LANES = ('cpu-1', 'cpu-2', 'javascript')
# Words that state a consume/return owner mapping. "returns" alone does not:
# almost every numeric scope says it, and that is not an owner mapping.
MAPPING = re.compile(
    r'\b(owners?|ownership|consumes?|consumed|owned|affine|retains?|retained|unloads?|unloaded|disposes?|disposed|clones?|freed|pools?)\b',
    re.I)
OWNER_DEF = re.compile(
    r'(?i)(?:^|[._])(?:ownership|owned|unloaded|disposed|retained|released|consumed)(?:$|[._])')
DEF_SPLIT = re.compile(r'(?m)^(?=[ \t]*def\s)')
CALL = re.compile(r'\b([A-Za-z_][\w]*)\s*\(')
DOTTED = re.compile(r'\b[A-Za-z_][\w]*(?:\.[A-Za-z_][\w]*)+\b')
BEND_COMMENT = re.compile(r'#[^\n]*')
VERB = re.compile(r'\b((?:[A-Za-z_][\w]*\.)*)(unload_colors|unload|free)\s*\(')
METAL_LINE = 'Metal witness: {api_id} {revision} pass'
GATES_OBJECT = re.compile(r'"gates"\s*:\s*\{[^{}]*\}')
ENTRY_KEY = re.compile(r'(?m)^    ("(?:[^"\\]|\\.)*")\s*:\s*\{')
EXAMPLES_PROBE = 'tools/examples_probe.py'
CONFORMANCE = 'tools/conformance.py'
BENCHMARKS = frozenset(('docs/PERFORMANCE.md', 'tools/gradient_bench.py', 'tools/perf_examples.py'))


def bend_revision():
    if not hasattr(bend_revision, 'value'):
        bend_revision.value = json.loads((ROOT / 'toolchain.json').read_text())['bend']['revision']
    return bend_revision.value


def file_text(path):
    if path not in file_text.cache:
        file = ROOT / path
        file_text.cache[path] = file.read_text(errors='replace') if file.is_file() else None
    return file_text.cache[path]


file_text.cache = {}


def read_text(path):
    text = file_text(path)
    if text is None:
        raise FileNotFoundError(path)
    return text


def dotted_suffixes(text):
    found = set()
    for match in DOTTED.finditer(text):
        parts = match.group(0).split('.')
        for index in range(len(parts) - 1):
            found.add('.'.join(parts[index:]))
    return found


def bend_symbols(jonlib):
    """Dotted Bend names in a mapping, ignoring call arguments and prose."""
    return DOTTED.findall(jonlib or '')


def suffixes_of(symbol):
    parts = symbol.split('.')
    return ['.'.join(parts[index:]) for index in range(len(parts) - 1)]


def code_text(path, text):
    """Bend comments are not executed. Probe sources keep comments: generated
    programs and the name tables live in strings, and a listed name is a claim
    the probe then compares."""
    if path.endswith('.bend'):
        return BEND_COMMENT.sub('', text)
    return text


def split_defs(text):
    parts = DEF_SPLIT.split(text)
    defs = []
    for part in parts:
        match = re.match(r'[ \t]*def\s+([A-Za-z_][\w.]*)', part)
        if match:
            defs.append((match.group(1), part))
    return defs


def ownership_symbols(text):
    """Bend symbols an ownership test or a consume-call actually names.

    An ownership def is one whose name carries ownership, owned, unloaded,
    disposed, retained, released or consumed. The defs it calls directly are
    included once, so `unloaded` calling `Surface.unload` counts. A call of
    `unload`, `unload_colors` or `free` counts even from another def: that
    call is the consume.
    """
    defs = split_defs(text)
    by_leaf = {}
    for name, body in defs:
        by_leaf.setdefault(name.split('.')[-1], []).append(body)
    regions = []
    for name, body in defs:
        leaf = name.split('.')[-1]
        if OWNER_DEF.search(leaf) or OWNER_DEF.search(name):
            regions.append(body)
            for call in CALL.findall(body):
                regions.extend(by_leaf.get(call, ()))
    symbols = set()
    for region in regions:
        symbols.update(dotted_suffixes(region))
    for match in VERB.finditer(text):
        dotted = match.group(1) + match.group(2)
        symbols.update(suffixes_of(dotted) if '.' in dotted else ())
        if '.' in dotted:
            symbols.add(dotted)
    return symbols


def law_ownership_symbols(text):
    """Symbols named by a law whose own statement is about ownership."""
    symbols = set()
    for chunk in re.split(r'(?m)^(?=law )', text):
        if not chunk.startswith('law ') or not MAPPING.search(chunk):
            continue
        symbols.update(dotted_suffixes(chunk))
    return symbols


def referenced_sources(text, *, conformance):
    pattern = r"['\"]((?:tests|src)/[^'\"]+\.(?:bend|json))['\"]" if not conformance else \
        r"['\"](tests/(?:fixtures/)?[^'\"]+\.(?:bend|json))['\"]"
    found = []
    for path in re.findall(pattern, text):
        if path.endswith('_gpu.bend') or path in found:
            continue
        if (ROOT / path).is_file():
            found.append(path)
    return found


def is_exact_parity(script, text):
    """Bit-exact cpu-1, cpu-2 and javascript. probekit.Probe.compare requires
    every lane it ran, and those lanes are the three unless `--gpu` is passed.
    Hosted CI does not pass `--gpu`. conformance.py compares the same three
    lanes exactly and only adds `gpu-forced` under `--gpu`."""
    if script == CONFORMANCE:
        return all(lane in text for lane in EXACT_LANES) and 'def compare(' in text
    return 'probekit' in text and 'probe.compare(' in text


def load_gates():
    document = json.loads((ROOT / 'tools' / 'gates.json').read_text())
    witnesses = []
    for gate in document['gates']:
        if gate.get('diagnostic'):
            continue
        if CI_HOSTS - set(gate.get('os', ())):
            continue
        scripts = [word for word in gate['run'] if word.startswith('tools/') and word.endswith('.py')]
        if len(scripts) != 1:
            continue
        script = scripts[0]
        if script == EXAMPLES_PROBE or gate['id'].startswith('examples-'):
            continue
        command = ' '.join(gate['run'])
        if script != CONFORMANCE and 'raylib' not in command:
            continue
        text = read_text(script)
        if not is_exact_parity(script, text):
            continue
        files = [script, *referenced_sources(text, conformance=script == CONFORMANCE)]
        catalog = None
        if script == 'tools/enums_probe.py':
            catalog = 'enumerator'
        elif script == 'tools/macros_probe.py':
            catalog = 'macro'
        witnesses.append(dict(id=gate['id'], script=script, files=files, catalog=catalog))
    return witnesses


def catalog_keys():
    """Rows the enum and macro probes themselves select.

    Imported by module name from ``tools/`` so this file does not grow the
    conformance import graph (those probes import the API plan)."""
    import importlib
    import sys
    tools = str(ROOT / 'tools')
    if tools not in sys.path:
        sys.path.insert(0, tools)
    enums_probe = importlib.import_module('enums_probe')
    macros_probe = importlib.import_module('macros_probe')
    enums = {(header, name) for header, _enum, name in enums_probe.enumerators()}
    macros = {(header, name) for header, name, _kind, _bend in macros_probe.macros()}
    macros.update((header, name) for (header, name, _kind, _bend), _other in macros_probe.shared_options())
    return dict(enumerator=enums, macro=macros)


def owner_calls(text):
    """C function names called from an ownership def or the def it calls once."""
    defs = split_defs(text)
    by_leaf = {}
    for def_name, body in defs:
        by_leaf.setdefault(def_name.split('.')[-1], []).append(body)
    names = set()
    for def_name, body in defs:
        leaf = def_name.split('.')[-1]
        if not (OWNER_DEF.search(leaf) or OWNER_DEF.search(def_name)):
            continue
        blobs = [body]
        for call in CALL.findall(body):
            blobs.extend(by_leaf.get(call, ()))
        for blob in blobs:
            names.update(CALL.findall(blob))
    return names


STRING_NAME = re.compile(r"""(?P<q>['"])([A-Za-z_][A-Za-z0-9_]*)(?P=q)""")


def file_facts(path):
    text = code_text(path, read_text(path))
    return dict(strings={match.group(2) for match in STRING_NAME.finditer(text)},
                dotted=dotted_suffixes(text),
                ownership=ownership_symbols(text), owner_calls=owner_calls(text))


class EvidenceIndex:
    """What the parity gates actually execute, indexed for one repository."""

    def __init__(self, witnesses, facts, catalogs, laws, revision):
        self.witnesses = witnesses
        self.facts = facts
        self.catalogs = catalogs
        self.laws = laws
        self.revision = revision
        self.by_script = {item['script']: item for item in witnesses}

    @classmethod
    def load(cls):
        witnesses = load_gates()
        facts = {}
        for item in witnesses:
            for path in item['files']:
                facts.setdefault(path, file_facts(path))
        laws = set()
        if (ROOT / 'LAWS.bend').is_file():
            laws = law_ownership_symbols(code_text('LAWS.bend', read_text('LAWS.bend')))
        return cls(witnesses, facts, catalog_keys(), laws, bend_revision())

    def covers(self, witness, header, name, symbols):
        file_header = header if header.endswith('.h') else header + '.h'
        if witness['catalog'] == 'enumerator' and (file_header, name) in self.catalogs['enumerator']:
            return True
        if witness['catalog'] == 'macro' and (file_header, name) in self.catalogs['macro']:
            return True
        # A C name counts only as a string in the probe (a case table). A bare
        # call in generated C is often setup or teardown — CloseWindow() after
        # a frame dump is not a CloseWindow comparison. The Bend symbol has to
        # appear as a dotted name in the program the probe runs.
        identifier = bool(re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name))
        wanted = [suffix for symbol in symbols for suffix in suffixes_of(symbol)]
        for path in witness['files']:
            facts = self.facts[path]
            if identifier and name in facts['strings']:
                return True
            if any(suffix in facts['dotted'] for suffix in wanted):
                return True
        return False

    def ownership_hit(self, witness, name, symbols):
        identifier = bool(re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', name))
        wanted = [suffix for symbol in symbols for suffix in suffixes_of(symbol)]
        files = list(witness['files'])
        if witness['script'] == CONFORMANCE:
            files = [*files, 'LAWS.bend']
        for path in files:
            if path == 'LAWS.bend':
                symbols_here, calls = self.laws, set()
            else:
                facts = self.facts[path]
                symbols_here, calls = facts['ownership'], facts['owner_calls']
            if any(suffix in symbols_here for suffix in wanted):
                return True
            if identifier and name in calls:
                return True
        return False


def open_gaps(gaps):
    return [gap for gap in gaps if not gap.startswith(ALLOWED_GAPS)]


def unclaimed_hosts(gaps):
    """CI hosts the record itself says were not verified."""
    return [gap for gap in gaps if HOST_UNCLAIMED.search(gap)]


def mapping_stated(update):
    text = '\n'.join([update.get('scope') or '', *(update.get('adaptations') or [])])
    return bool(MAPPING.search(text))


def implemented(update):
    return update.get('status') in ('partial', 'complete') and bool(update.get('jonlib'))


def derive(index, api_id, update):
    """Return the six gates this record's evidence supports.

    `availability` and `targets` are not derived. A stored `verified` claim
    for either is dropped, because nothing here proves it. Any other stored
    value (`partial` or `unverified`, or a missing key) is kept, and a missing
    key stays `unverified` — the ledger's default, not a new partial claim.
    """
    header, _kind, name = api_id.split(':', 2)
    symbols = bend_symbols(update.get('jonlib'))
    evidence = [item.split('#')[0] for item in update.get('evidence') or []]
    cited = [index.by_script[path] for path in evidence if path in index.by_script]
    covered = [item for item in cited if index.covers(item, header, name, symbols)]
    gaps = open_gaps(update.get('gaps') or [])
    unclaimed = unclaimed_hosts(update.get('gaps') or [])
    ready = implemented(update)

    if ready and covered and not gaps and not unclaimed:
        behavior = 'verified'
    elif ready and cited:
        # A parity probe is cited, but it does not cover this API or an open
        # behavior gap remains. That is partial evidence, not a verification.
        behavior = 'partial'
    else:
        behavior = 'unverified'

    owner = ready and any(index.ownership_hit(item, name, symbols) for item in cited)
    stated = mapping_stated(update)
    if ready and owner and stated:
        ownership = 'verified'
    elif ready and (owner or stated):
        # One of the two ownership requirements holds. A behavior probe alone
        # is not ownership evidence.
        ownership = 'partial'
    else:
        ownership = 'unverified'

    integration_evidence = any(path == EXAMPLES_PROBE or path.startswith('examples/') for path in evidence)
    integration_gap = any(gap.startswith('Integration:') for gap in update.get('gaps') or [])
    integration = 'partial' if integration_evidence or integration_gap else 'unverified'

    performance_gap = any(gap.startswith('Performance:') for gap in update.get('gaps') or [])
    performance_evidence = any(path in BENCHMARKS for path in evidence)
    performance = 'partial' if performance_gap or performance_evidence else 'unverified'

    stored = update.get('gates') or {}

    def kept(gate):
        value = stored.get(gate, 'unverified')
        return value if value in ('partial', 'unverified') else 'unverified'

    return dict(availability=kept('availability'), behavior=behavior, ownership=ownership,
                integration=integration, targets=kept('targets'), performance=performance)


def blockers(index, api_id, update):
    """Why behavior and ownership are not verified. Empty when they are."""
    header, _kind, name = api_id.split(':', 2)
    symbols = bend_symbols(update.get('jonlib'))
    evidence = [item.split('#')[0] for item in update.get('evidence') or []]
    cited = [index.by_script[path] for path in evidence if path in index.by_script]
    covered = [item for item in cited if index.covers(item, header, name, symbols)]
    behavior, ownership = [], []
    if not implemented(update):
        behavior.append('not implemented (status partial/complete and a jonlib mapping)')
        ownership.append('not implemented (status partial/complete and a jonlib mapping)')
        return behavior, ownership
    if not cited:
        behavior.append('no bit-exact cpu-1/cpu-2/javascript parity probe on both CI hosts in evidence')
    elif not covered:
        behavior.append('cited parity probe does not name this API (' + ', '.join(item['id'] for item in cited) + ')')
    disallowed = open_gaps(update.get('gaps') or [])
    if disallowed:
        prefixes = []
        for gap in disallowed:
            prefixes.append(gap.split(':', 1)[0] if re.match(r'^[A-Z][A-Za-z0-9 ]{0,40}:', gap) else 'untagged')
        behavior.append('open behavior gap (' + ', '.join(prefixes) + ')')
    if unclaimed_hosts(update.get('gaps') or []):
        behavior.append('a CI host is explicitly not verified')
    if not any(index.ownership_hit(item, name, symbols) for item in cited):
        ownership.append('no affine/ownership test or proof names this Bend symbol or calls this C function')
    if not mapping_stated(update):
        ownership.append('scope/adaptations do not state the owner mapping')
    return behavior, ownership


def metal_proven(row):
    """Phase 1 exit witness. A row may carry `metal_witness` in a unit test;
    repository rows are decided by an evidence line for the current Bend pin."""
    if 'metal_witness' in row:
        return bool(row['metal_witness'])
    revision = bend_revision()
    marker = METAL_LINE.format(api_id=row.get('id', ''), revision=revision)
    for item in row.get('evidence') or []:
        text = file_text(item.split('#')[0])
        if text and any(line.strip() == marker for line in text.splitlines()):
            return True
    return False


def assessments(index, progress):
    rows = []
    for api_id, update in progress['entries'].items():
        gates = derive(index, api_id, update)
        behavior, ownership = blockers(index, api_id, update)
        rows.append(dict(id=api_id, header=api_id.split(':', 1)[0], gates=gates,
                         behavior=behavior, ownership=ownership))
    return rows


def mismatches(progress, index=None):
    """Human-readable rows whose stored gates are not the derived ones."""
    index = index or EvidenceIndex.load()
    problems = []
    for api_id, update in progress['entries'].items():
        derived = derive(index, api_id, update)
        stored = {gate: (update.get('gates') or {}).get(gate, 'unverified') for gate in GATES}
        if stored != derived:
            changed = [f'{gate} {stored[gate]} -> {derived[gate]}' for gate in GATES if stored[gate] != derived[gate]]
            problems.append(f'{api_id}: ' + '; '.join(changed))
    return problems


def check(progress, index=None):
    problems = mismatches(progress, index)
    if problems:
        shown = '\n  '.join(problems[:20])
        extra = f'\n  … {len(problems) - 20} more' if len(problems) > 20 else ''
        raise ValueError('api/progress.json gates must match the evidence derivation '
                         '(docs/API-TRACKING.md, tools/gate_evidence.py):\n  ' + shown + extra)


def compact_gates(gates):
    if any(gates[gate] not in ('unverified', 'partial', 'verified') for gate in GATES):
        raise ValueError(f'invalid derived gate {gates}')
    return '{' + ','.join(f'"{gate}":"{gates[gate]}"' for gate in GATES) + '}'


def object_end(text, start):
    """Index of the brace that closes the object opening at `start`."""
    depth = 0
    in_string = False
    escaped = False
    for index in range(start, len(text)):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == '\\':
                escaped = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == '{':
            depth += 1
        elif char == '}':
            depth -= 1
            if depth == 0:
                return index
    raise ValueError('unbalanced progress object')


def render_gates(gates, multiline, indent):
    if not multiline:
        return '"gates":' + compact_gates(gates)
    rows = ',\n'.join(f'{indent}  "{gate}": "{gates[gate]}"' for gate in GATES)
    return '"gates": {\n' + rows + '\n' + indent + '}'


def rewrite(text, progress, index=None):
    """Replace only each record's gates object. Every other field is untouched."""
    index = index or EvidenceIndex.load()
    derived = {api_id: derive(index, api_id, update) for api_id, update in progress['entries'].items()}
    spans = []
    for match in ENTRY_KEY.finditer(text):
        api_id = json.loads(match.group(1))
        if api_id not in derived:
            raise ValueError(f'progress entry is not in the catalog: {api_id}')
        start = match.end() - 1
        spans.append((api_id, start, object_end(text, start)))
    if {api_id for api_id, _start, _end in spans} != set(derived):
        raise ValueError('progress.json entries do not match the parsed records')
    pieces, cursor = [], 0
    for api_id, start, end in spans:
        region = text[start:end + 1]
        multiline = '\n' in region
        indent = '      '
        if multiline:
            field = re.search(r'\n( +)"', region)
            if field:
                indent = field.group(1)
        rendered = render_gates(derived[api_id], multiline, indent)
        found = GATES_OBJECT.search(region)
        if found:
            region = region[:found.start()] + rendered + region[found.end():]
        else:
            body, close = region[:-1], region[-1]
            trimmed = body.rstrip()
            padding = body[len(trimmed):]
            separator = '\n' + indent + rendered + padding if multiline else rendered
            region = trimmed + ',' + separator + close
        pieces.append(text[cursor:start])
        pieces.append(region)
        cursor = end + 1
    pieces.append(text[cursor:])
    text = ''.join(pieces)
    after = json.loads(text)
    for api_id, entry in progress['entries'].items():
        old = {key: value for key, value in entry.items() if key != 'gates'}
        new = {key: value for key, value in after['entries'][api_id].items() if key != 'gates'}
        if old != new:
            raise ValueError(f'{api_id}: gate rewrite changed a non-gate field')
        if after['entries'][api_id]['gates'] != derived[api_id]:
            raise ValueError(f'{api_id}: rewritten gates do not match the derivation')
    return text


def library(header):
    return 'jonmath' if header == 'raymath' else 'jonlib'


def phase_note(rows):
    """Phase 1 functions, using the same classifier as the ledger."""
    import importlib
    import sys
    tools = str(ROOT / 'tools')
    if tools not in sys.path:
        sys.path.insert(0, tools)
    api_plan = importlib.import_module('api_plan')
    reference = {row['id']: row for row in api_plan.read('reference.json')['entries']}
    phases = {item['id']: item['phase'] for item in api_plan.read('milestones.json')['milestones']}
    functions = [row for row in rows if reference[row['id']]['kind'] == 'function'
                 and phases[api_plan.classify(reference[row['id']])] == 1]
    behavior = [row for row in functions if row['gates']['behavior'] == 'verified']
    ownership = [row for row in functions if row['gates']['ownership'] == 'verified']
    both = [row for row in behavior if row['gates']['ownership'] == 'verified']
    lines = ['## Phase 1 functions', '',
             f'{len(functions)} Phase 1 functions. Behavior verified: {len(behavior)}. '
             f'Ownership verified: {len(ownership)}. Both: {len(both)}. '
             'The exit measure also requires a forced-Metal witness, and none is recorded, so it stays unmet.',
             '']
    if ownership and not both:
        lines.append('Ownership is verified but behavior is not, because an open gap or an unclaimed CI host remains:')
        lines.append('')
        for row in ownership:
            if row not in both:
                lines.append(f'- `{row["id"]}`: ' + '; '.join(row['behavior']))
        lines.append('')
    missing_test = [row['id'] for row in behavior if row['ownership'] == [
        'no affine/ownership test or proof names this Bend symbol or calls this C function']]
    noun = 'function' if len(missing_test) == 1 else 'functions'
    lines.append(f'{len(missing_test)} Phase 1 {noun} have behavior verified and state an owner mapping, '
                 'and have no ownership test that names them.')
    lines.append('')
    return lines


def report(rows):
    """Counts by header and the reasons the rest are not verified."""
    headers = sorted({row['header'] for row in rows})
    lines = ['# Behavior and ownership gate evidence', '',
             'Derived by `tools/gate_evidence.py` from `api/progress.json` and the parity gates.',
             'Criteria: `docs/API-TRACKING.md`.', '']
    lines.append('## Verified')
    lines.append('')
    lines.append('| Header | Library | Entries | Behavior | Ownership | Both |')
    lines.append('|---|---|---:|---:|---:|---:|')
    totals = dict(entries=0, behavior=0, ownership=0, both=0)
    by_library = {}
    for header in headers:
        group = [row for row in rows if row['header'] == header]
        behavior = sum(row['gates']['behavior'] == 'verified' for row in group)
        ownership = sum(row['gates']['ownership'] == 'verified' for row in group)
        both = sum(row['gates']['behavior'] == 'verified' and row['gates']['ownership'] == 'verified' for row in group)
        name = library(header)
        lines.append(f'| `{header}` | {name} | {len(group)} | {behavior} | {ownership} | {both} |')
        bucket = by_library.setdefault(name, dict(entries=0, behavior=0, ownership=0, both=0))
        for key, value in dict(entries=len(group), behavior=behavior, ownership=ownership, both=both).items():
            bucket[key] += value
            totals[key] += value
    lines.append(f'| **total** |  | {totals["entries"]} | {totals["behavior"]} | {totals["ownership"]} | {totals["both"]} |')
    lines.append('')
    lines.append('By library: ' + '; '.join(
        f'{name}: behavior {counts["behavior"]}, ownership {counts["ownership"]}, both {counts["both"]} of {counts["entries"]}'
        for name, counts in sorted(by_library.items())))
    lines.append('')
    both = [row['id'] for row in rows if row['gates']['behavior'] == 'verified' and row['gates']['ownership'] == 'verified']
    lines.append('Both gates verified:')
    lines.append('')
    lines += [f'- `{api_id}`' for api_id in both] or ['- none']
    lines.append('')
    lines += phase_note(rows)

    def histogram(kind):
        counts = {}
        for row in rows:
            reasons = row[kind]
            if not reasons:
                continue
            # One row can have several reasons. Count the combination so a
            # single-reason row is visibly close.
            label = ' AND '.join(reasons)
            counts[label] = counts.get(label, 0) + 1
        return sorted(counts.items(), key=lambda item: (-item[1], item[0]))

    lines.append('## What blocks behavior')
    lines.append('')
    for label, count in histogram('behavior'):
        lines.append(f'- {count}: {label}')
    lines.append('')
    lines.append('## What blocks ownership')
    lines.append('')
    for label, count in histogram('ownership'):
        lines.append(f'- {count}: {label}')
    lines.append('')
    close = [row for row in rows if row['behavior'] == [] or
             (len(row['behavior']) == 1 and row['behavior'][0].startswith('open behavior gap ('))]
    close = [row for row in close if row['behavior']]
    lines.append('## Close: behavior is blocked only by an open gap')
    lines.append('')
    lines.append(f'{len(close)} entries have a covering bit-exact probe and fail behavior only because a gap is open behavior work.')
    lines.append('')
    prefix_counts = {}
    for row in close:
        text = row['behavior'][0][len('open behavior gap ('):-1]
        for prefix in text.split(', '):
            prefix_counts[prefix] = prefix_counts.get(prefix, 0) + 1
    for prefix, count in sorted(prefix_counts.items(), key=lambda item: (-item[1], item[0])):
        lines.append(f'- {count} gaps tagged `{prefix}`')
    lines.append('')
    owner_close = [row for row in rows if not row['ownership'] or (len(row['ownership']) == 1)]
    only_test = [row for row in rows if row['ownership'] == ['no affine/ownership test or proof names this Bend symbol or calls this C function']]
    only_words = [row for row in rows if row['ownership'] == ['scope/adaptations do not state the owner mapping']]
    lines.append('## Close: ownership is one witness short')
    lines.append('')
    lines.append(f'{len(only_test)} entries state an owner mapping and have no ownership test or proof that names them.')
    lines.append(f'{len(only_words)} entries have an ownership test or proof and do not state the mapping in scope or adaptations.')
    lines.append('')
    if only_words:
        lines.append('Test present, mapping text missing:')
        lines.append('')
        for row in only_words:
            lines.append(f'- `{row["id"]}`')
        lines.append('')
    lines.append('## Integration and performance')
    lines.append('')
    for gate in ('integration', 'performance'):
        counts = {}
        for row in rows:
            counts[row['gates'][gate]] = counts.get(row['gates'][gate], 0) + 1
        lines.append(f'- `{gate}`: ' + ', '.join(f'{key} {counts.get(key, 0)}' for key in ('verified', 'partial', 'unverified')))
    lines.append('')
    lines.append('Neither is `verified`. Example replays are not desktop integration, and the benchmark tools are not parity gates. '
                 'The Phase 1 exit measure additionally requires a line `Metal witness: <id> <pinned Bend revision> pass` in an evidence file. '
                 'CPU and JavaScript results are not that witness.')
    lines.append('')
    return '\n'.join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true', help='rewrite gates in api/progress.json')
    parser.add_argument('--report', type=Path, help='write the blocker report')
    parser.add_argument('--check', action='store_true', help='fail when stored gates differ (the default)')
    args = parser.parse_args(argv)
    progress = json.loads(PROGRESS.read_text())
    index = EvidenceIndex.load()
    rows = assessments(index, progress)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(report(rows))
        print(f'wrote {args.report}')
    if args.apply:
        PROGRESS.write_text(rewrite(PROGRESS.read_text(), progress, index))
        print('rewrote gates in api/progress.json')
        return 0
    if args.report and not args.check:
        return 0
    try:
        check(progress, index)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    print(f'gates match the evidence derivation ({len(progress["entries"])} entries)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
