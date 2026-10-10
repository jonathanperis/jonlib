#!/usr/bin/env python3
"""Decide how much of the conformance suite a change needs.

A complete Conformance run is every gate of tools/gates.json on both hosts
(about ten shards of one to two hours each, and hosted macOS runs five jobs at
a time). Most changes cannot reach most gates. This tool classifies the files
a push or pull request changed and picks one of three scopes:

- `full`: every gate. A library definition changed or was removed, the
  toolchain pins, the gate runner, the pinned setup action, a fixture, or any
  path this tool cannot place. Scheduled and manual runs are always full.
- `scoped`: only the gates and examples the change can reach, on both hosts:
  - a library file that only gained whole top-level definitions (every
    existing definition is byte for byte where it was) runs the main corpus
    with `PROOF.bend` and the core examples, besides the gates below;
  - `LAWS.bend` and `PROOF.bend` run the gates whose tool names them, an API
    ledger the gates that run the API plan, and a file under
    `tools/reference/` every gate that can reach a tool naming it;
  - a tool runs the gates that reach it (the tool a gate runs, the tools its
    source names, and what those import, transitively);
  - `tools/gates.json` runs the gates whose command or hosts changed;
  - an example port (`examples/<name>.bend`), and the tables and scripts of
    `tools/examples_probe.py` above its native driver, replay the changed
    ports, the examples whose registration, table entry, prediction or script
    changed, and three canaries (a plain window, a seeded example with a
    refusal, one that loads a file). A change to code the examples share (the
    native driver `C_DRIVER` and everything below it, or a line above it that
    names no example and is not a new constant or a comment) runs every
    examples gate.
  More than three jobs of gates per host is `full`.
- `none`: only files no gate reads (workflows, unit tests, this tool,
  documentation). The Checks workflow covers them.

The base of the comparison is the previous head for a push to `main`, and the
merge base with `main` for any other branch or a pull request. When the base
cannot be found the scope is `full`. A push to `main` is compared with the
pushed head itself or one of its parents when that commit's Conformance run
already succeeded: a fast-forward merge of a passing branch has nothing left
to run, and a merge commit only what `main` had gained since the branch
started. A scheduled run is `none` when a scheduled or manual run (always
full) of the same commit already succeeded.

    python3 tools/ci_scope.py                 # reads the GitHub event, writes mode/matrix to $GITHUB_OUTPUT
    python3 tools/ci_scope.py --base REF      # prints the scope of REF..HEAD
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PROBE = 'tools/examples_probe.py'
MANIFEST = 'tools/gates.json'
CANARIES = ('core_basic_window', 'core_2d_camera', 'textures_logo_raylib')
HARNESS_MARKER = 'C_DRIVER = '
# Files no conformance gate reads.
HARNESS = ('tools/ci_scope.py', 'tools/example_tables.py', 'tools/examples_plan.py', 'tools/check_project.py')
EXAMPLE_FILES = (PROBE, 'api/examples.json')
# What a library file that only gained definitions runs: the corpus with PROOF.bend, and the core examples.
LIBRARY_GATES = ('conformance', 'examples-core')
HOSTS = (('linux', 'ubuntu-24.04'), ('macos', 'macos-15'))
# Estimated minutes (the manifest's, measured on macOS) per scoped job, and the jobs per host before a run is full.
PART_MINUTES, MAX_PARTS = 100, 3
REGISTERED = re.compile(r"^    '([a-z0-9_]+)': \('", re.M)
QUOTED = re.compile(r"'([a-z0-9_]+)'")
HUNK = re.compile(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@')
SCRIPT = re.compile(r"^        script\('([a-z0-9_]+)'")
# A line no existing script can depend on: blank, a comment, or new constants.
INERT = re.compile(r'^\s*(#.*)?$|^\(?[A-Z][A-Z0-9_]*(, [A-Z][A-Z0-9_]*)*\)? = \(?-?[0-9][0-9a-fx.]*(, -?[0-9][0-9a-fx.]*)*\)?$')
IMPORT = re.compile(r'^\s*(?:from\s+([a-z_0-9]+)\s+import\b|import\s+([a-z_0-9, ]+?)(?:\s+as\s+\w+)?\s*$)', re.M)
TOOL = re.compile(r'tools/([a-z_0-9]+)\.py')
FULL = dict(mode='full', gates=[], examples=[])


def full(reason):
    return dict(FULL, reason=reason)
NONE = dict(mode='none', gates=[], examples=[])


def kind(path):
    """'none', 'example', 'library', 'named', 'manifest', 'tool' or 'full' for one changed path."""
    if path.endswith('.md') or path.startswith(('docs/', 'LICENSES/')) or path in ('LICENSE', '.gitignore'):
        return 'none'
    if path.startswith('.github/workflows/') or (path.startswith('tests/') and path.endswith('.py') and '/' not in path[len('tests/'):]):
        return 'none'
    if path in HARNESS:
        return 'none'
    if path in EXAMPLE_FILES or re.fullmatch(r'examples/[a-z0-9_]+\.bend', path):
        return 'example'
    if path in ('jonlib.bend', 'jonmath.bend', 'jongui.bend') or re.fullmatch(r'src/(lgpl/)?[a-z0-9_]+\.bend', path):
        return 'library'
    if path in ('LAWS.bend', 'PROOF.bend') or re.fullmatch(r'api/[a-z0-9_]+\.json', path) or path.startswith('tools/reference/'):
        return 'named'
    if path == MANIFEST:
        return 'manifest'
    if re.fullmatch(r'tools/[a-z_0-9]+\.py', path) and path != 'tools/run_gates.py':
        return 'tool'
    return 'full'


def registered(probe_source):
    """The example names the probe registers."""
    return set(REGISTERED.findall(probe_source))


def hunks(diff):
    """(first new line, last new line, removed lines, added lines) of each hunk of a -U0 diff."""
    found = []
    for line in diff.splitlines():
        match = HUNK.match(line)
        if match:
            first, count = int(match[1]), int(match[2]) if match[2] is not None else 1
            found.append((max(first, 1), max(first, 1) + max(count, 1) - 1, [], []))
        elif found and line[:1] in ('-', '+'):
            found[-1][2 if line[0] == '-' else 3].append(line[1:])
    return found


def entries(lines, names):
    """Each registered name quoted in the lines with the text up to the next one (and, for the first, the text before it)."""
    text = ' '.join(' '.join(lines).split())
    marks = [match for match in QUOTED.finditer(text) if match[1] in names]
    return {(match[1], text[:match.start()] * (index == 0), text[match.end():following.start() if following else len(text)])
            for index, (match, following) in enumerate(zip(marks, [*marks[1:], None]))}


def probe_examples(probe_source, diff, names):
    """The examples a probe diff affects, or None when it reaches code every example shares.

    Shared code is the native driver (`C_DRIVER`) and everything below it, and
    above it any changed line that names no example, unless it only adds
    comments or constants. Inside `scripts()` a line belongs to the script it
    continues. Elsewhere a name counts when the text that follows it changed
    (its registration, a table value, set membership).
    """
    lines = probe_source.splitlines()
    marker = next((index + 1 for index, line in enumerate(lines) if line.startswith(HARNESS_MARKER)), None)
    opening = next((index + 1 for index, line in enumerate(lines) if line.startswith('def scripts():')), None)
    found = hunks(diff)
    if marker is None or opening is None or not found:
        return None
    closing = next(index + 1 for index in range(opening, len(lines)) if lines[index][:1].strip())
    examples = set()
    for first, last, removed, added in found:
        if last >= marker or (first < closing and last >= opening and not (opening < first and last < closing)):
            return None
        if opening < first and last < closing:
            if not all(line.startswith('        ') or not line.strip() for line in removed + added):
                return None
            code = lambda line: line.strip() and not line.lstrip().startswith('#')
            numbers = [number for number, line in zip(range(first, last + 1), added) if code(line)] + [first] * any(map(code, removed))
            for number in numbers:
                owner = next((SCRIPT.match(lines[index])[1] for index in range(number - 1, opening, -1) if SCRIPT.match(lines[index])), None)
                examples |= {owner} & names
            examples |= {name for line in removed + added for name in QUOTED.findall(line) if name in names}
            continue
        changed = entries(removed, names) ^ entries(added, names)
        if not changed and not (all(INERT.match(line) for line in added) and all(not line.strip() or line.lstrip().startswith('#') for line in removed)):
            if not (entries(removed, names) or entries(added, names)):
                return None
        examples |= {entry[0] for entry in changed}
    return examples


def blocks(text):
    """The top-level blocks of a Bend source: a line at column 0 with the indented lines under it."""
    found = []
    for line in text.splitlines():
        if line[:1].strip() or not found:
            found.append([line])
        else:
            found[-1].append(line)
    return ['\n'.join(block).rstrip() for block in found]


def additive(old, new):
    """Whether `new` is `old` with whole top-level blocks inserted: every existing block unchanged and in order."""
    remaining = iter(blocks(new))
    return all(any(block == candidate for candidate in remaining) for block in blocks(old))


def reach(tool, read, known):
    """A tool and the tools it imports, transitively."""
    if tool not in known:
        known[tool] = None  # a cycle ends here; the first caller completes the set
        found = {tool}
        for module, modules in IMPORT.findall(read(tool)):
            for name in ([module] if module else [name.strip() for name in modules.split(',')]):
                other = f'tools/{name}.py'
                if other != tool and read(other):
                    found |= reach(other, read, known) or {other}
        known[tool] = found
    return known[tool]


def entries_of(gate):
    """The tools a gate's command runs."""
    return [word for word in gate['run'] if TOOL.fullmatch(word)]


def gate_tools(gate, read, known):
    """Every tool a gate can run: its own, the tools their sources name, and what all of those import."""
    found = set()
    for entry in entries_of(gate):
        for tool in [entry, *sorted(f'tools/{name}.py' for name in TOOL.findall(read(entry)))]:
            if read(tool):
                found |= reach(tool, read, known) or {tool}
    return found


def command(gate):
    return (gate.get('run'), sorted(gate.get('os', [])), bool(gate.get('diagnostic')))


def parts(gates):
    """The gates packed into jobs of about PART_MINUTES, longest first; None past MAX_PARTS."""
    bins = []
    for gate in sorted(gates, key=lambda gate: (-gate.get('minutes', 1), gate['id'])):
        fit = next((part for part in bins if sum(g.get('minutes', 1) for g in part) + gate.get('minutes', 1) <= PART_MINUTES), None)
        if fit is None:
            bins.append([gate])
        else:
            fit.append(gate)
    return bins if len(bins) <= MAX_PARTS else None


def matrix(gates, examples):
    """The scoped jobs: each part of the gates on each host that runs them, and the examples on both."""
    include = []
    for system, runner in HOSTS:
        for number, part in enumerate(parts([gate for gate in gates if system in gate['os']]), 1):
            include.append(dict(os=runner, part=f'gates {number}', gates=' '.join(f"--only={gate['id']}" for gate in part), examples=''))
        if examples:
            include.append(dict(os=runner, part='examples', gates='', examples=' '.join(f'--example={name}' for name in examples)))
    return dict(include=include)


def scope(status, old, new, diff):
    """The mode, gates and examples for a change.

    `status` maps each changed path to 'A', 'M' or 'D'; `old` and `new` read a
    path before and after the change ('' when absent) and `diff` gives its -U0
    diff.
    """
    kinds = {path: kind(path) for path in status}
    unplaced = sorted(path for path, what in kinds.items() if what == 'full')
    if unplaced:
        return full('no rule places ' + ', '.join(unplaced[:4]))
    try:
        manifest = {gate['id']: gate for gate in json.loads(new(MANIFEST))['gates']}
    except (ValueError, KeyError, TypeError):
        return full('the gate manifest is unreadable')
    known, probe_source = {}, new(PROBE)
    names = registered(probe_source)
    reaching = lambda path: {name for name, gate in manifest.items() if path in gate_tools(gate, new, known)}
    naming = lambda text: {name for name, gate in manifest.items() if any(text in new(tool) for tool in gate_tools(gate, new, known))}
    running = lambda text: {name for name, gate in manifest.items() if any(text in new(entry) for entry in entries_of(gate))}
    gates, examples = set(), set()
    for path, what in kinds.items():
        if what == 'library':
            if status[path] == 'D' or not additive(old(path), new(path)) or not set(LIBRARY_GATES) <= set(manifest):
                return full(f'{path} changed or lost a definition')
            gates |= set(LIBRARY_GATES)
        elif what == 'named':
            # A proof file is read by the gate whose tool names it; a ledger by the gates that run the API plan;
            # reference material by any gate that can reach a tool naming it.
            found = (naming('reference/' + path.split('/')[2]) if path.startswith('tools/reference/')
                     else reaching('tools/api_plan.py') if path.startswith('api/') else running(path))
            if not found:
                return full(f'no gate names {path}')
            gates |= found
        elif what == 'manifest':
            try:
                before = {gate['id']: gate for gate in json.loads(old(path))['gates']}
            except (ValueError, KeyError, TypeError):
                return full('the previous gate manifest is unreadable')
            gates |= {name for name, gate in manifest.items() if name not in before or command(before[name]) != command(gate)}
        elif what == 'tool':
            found = reaching(path)
            if status[path] == 'D' or (not found and status[path] != 'A'):
                return full(f'no gate reaches {path}')
            gates |= found
        elif path == PROBE:
            affected = probe_examples(probe_source, diff(path), names)
            if affected is None:
                gates |= reaching(path)
            else:
                examples |= affected | set(CANARIES)
        elif path.startswith('examples/'):
            examples.add(Path(path).stem)
    if examples - names:
        # A port without a registration (or a deleted one) has no replay: run everything.
        return full('no replay is registered for ' + ', '.join(sorted(examples - names)))
    selected = [manifest[name] for name in sorted(gates)]
    if parts(selected) is None:
        return full(f'{len(selected)} gates are affected, more than {MAX_PARTS} jobs per host')
    if not selected and not examples:
        return NONE
    return dict(mode='scoped', gates=[gate['id'] for gate in selected], examples=sorted(examples), matrix=matrix(selected, sorted(examples)))


def git(*args):
    return subprocess.run(['git', *args], cwd=ROOT, check=True, capture_output=True, text=True).stdout


def base_ref(env=os.environ):
    """The commit to compare with, or None for a full run."""
    event = env.get('GITHUB_EVENT_NAME', '')
    if event in ('schedule', 'workflow_dispatch'):
        return None
    payload = {}
    if env.get('GITHUB_EVENT_PATH') and Path(env['GITHUB_EVENT_PATH']).is_file():
        payload = json.loads(Path(env['GITHUB_EVENT_PATH']).read_text())
    if event == 'push' and env.get('GITHUB_REF_NAME') == 'main':
        before = payload.get('before', '')
        return before if re.fullmatch(r'[0-9a-f]{40}', before) and set(before) != {'0'} else None
    target = payload.get('pull_request', {}).get('base', {}).get('ref', 'main') if event == 'pull_request' else 'main'
    return git('merge-base', f'origin/{target}', 'HEAD').strip()


def show(commit, path):
    result = subprocess.run(['git', 'show', f'{commit}:{path}'], cwd=ROOT, capture_output=True, text=True, errors='replace')
    return result.stdout if result.returncode == 0 else ''


def changed(base, head='HEAD'):
    """The scope of base..head."""
    rows = [line.split('\t') for line in git('diff', '--name-status', '--no-renames', f'{base}..{head}').splitlines() if line]
    status = {path: letter[0] for letter, path in rows}
    cache = {}
    read = lambda commit: lambda path: cache[commit, path] if (commit, path) in cache else cache.setdefault((commit, path), show(commit, path))
    return scope(status, read(base), read(head), lambda path: git('diff', '-U0', f'{base}..{head}', '--', path))


FULL_EVENTS = ('schedule', 'workflow_dispatch')
RUN_EVENTS = ('push', *FULL_EVENTS)


def verified(runs, run_id, events):
    """Whether another Conformance run of a commit, started by one of the events, succeeded."""
    return any(run.get('conclusion') == 'success' and str(run.get('id')) != str(run_id) and run.get('event') in events for run in runs)


def passed(sha, events, env=os.environ):
    """Ask GitHub whether a Conformance run of the commit succeeded."""
    query = f"repos/{env['GITHUB_REPOSITORY']}/actions/workflows/conformance.yml/runs?head_sha={sha}&status=success&per_page=50"
    runs = json.loads(subprocess.run(['gh', 'api', query], check=True, capture_output=True, text=True).stdout)
    return verified(runs.get('workflow_runs', []), env.get('GITHUB_RUN_ID', ''), events)


def verified_base(commits, env=os.environ, passed=passed):
    """For a push to main, the pushed head or one of its parents that already passed.

    `commits` is the head followed by its parents. A fast-forward merge pushes a
    head that passed on its branch (nothing left to run); a merge commit differs
    from the merged branch's passing head by what main had gained since.
    """
    if env.get('GITHUB_EVENT_NAME') != 'push' or env.get('GITHUB_REF_NAME') != 'main' or not env.get('GH_TOKEN'):
        return None
    return next((sha for sha in [*commits[:1], *reversed(commits[1:])] if passed(sha, RUN_EVENTS, env)), None)


def nightly_done(env=os.environ, passed=passed):
    """A scheduled run of a commit that a scheduled or manual (complete) run already passed."""
    return env.get('GITHUB_EVENT_NAME') == 'schedule' and bool(env.get('GH_TOKEN')) and passed(env['GITHUB_SHA'], FULL_EVENTS, env)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--base', help='compare with this commit instead of reading the GitHub event')
    parser.add_argument('--head', default='HEAD', help='the changed commit (with --base)')
    args = parser.parse_args(argv)
    base, note = args.base, ''
    if not base:
        try:
            if nightly_done():
                base, note = 'HEAD', ' (a complete run of this commit already passed)'
            else:
                base = verified_base(git('rev-list', '--parents', '-n', '1', 'HEAD').split())
                note = f' (compared with {base[:7]}, whose run passed)' if base else ''
        except (subprocess.CalledProcessError, OSError, ValueError, KeyError) as error:
            print(f"ci_scope: {error}; comparing with the event's base", file=sys.stderr)
            base = None
    try:
        base = base or base_ref()
        result = changed(base, args.head) if base else full('a scheduled or manual run, or no base to compare with')
    except (subprocess.CalledProcessError, OSError, ValueError) as error:
        result = full(f'the change could not be read ({error})')
    summary = f"{result['mode']}{note}" + (f": {result['reason']}" if result.get('reason') else '') + ''.join(f'\n  {key}: ' + ' '.join(result[key]) for key in ('gates', 'examples') if result[key])
    print(summary)
    output = os.environ.get('GITHUB_OUTPUT')
    if output:
        with open(output, 'a') as handle:
            print(f"mode={result['mode']}", file=handle)
            # A skipped job's matrix must still expand: one inert row when nothing is scoped.
            idle = dict(include=[dict(os=HOSTS[0][1], part='none', gates='', examples='')])
            print('matrix=' + json.dumps(result.get('matrix', idle)), file=handle)
    step = os.environ.get('GITHUB_STEP_SUMMARY')
    if step:
        with open(step, 'a') as handle:
            print('Conformance scope: ' + summary.replace('\n', '\n\n'), file=handle)


if __name__ == '__main__':
    main()
