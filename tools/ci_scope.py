#!/usr/bin/env python3
"""Decide how much of the conformance suite a change needs.

The Conformance workflow runs every gate on both hosts (about ten shards of
one to two hours each). A change that only adds or edits example ports cannot
alter any other gate: its evidence is the replay of those examples. This tool
classifies the files a push or pull request changed:

- `full`: anything that can reach a gate (the library, `src/`, the toolchain
  pins, a probe or another tool, fixtures, API ledgers, the pinned setup
  action) or a path this tool does not know. Scheduled and manual runs are
  always full.
- `examples`: only example ports (`examples/*.bend`), the tables and scripts
  of their probe (`tools/examples_probe.py` above its native driver), the
  examples plan and documentation. The examples to replay are the changed
  ports, the examples whose registration, table entry or script changed in the
  probe, and, whenever the probe changed, three canaries (a plain window, a
  seeded example with a refusal and one that loads a file). A change to code
  the examples share (the native driver `C_DRIVER` and everything below it,
  or a line above it that names no example and is not a new constant or a
  comment) is `full`.
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

    python3 tools/ci_scope.py                 # reads the GitHub event, writes mode/examples to $GITHUB_OUTPUT
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
CANARIES = ('core_basic_window', 'core_2d_camera', 'textures_logo_raylib')
HARNESS_MARKER = 'C_DRIVER = '
# Files no conformance gate reads.
HARNESS = ('tools/ci_scope.py', 'tools/example_tables.py', 'tools/examples_plan.py', 'tools/check_project.py')
EXAMPLE_FILES = (PROBE, 'api/examples.json')
REGISTERED = re.compile(r"^    '([a-z0-9_]+)': \('", re.M)
QUOTED = re.compile(r"'([a-z0-9_]+)'")
HUNK = re.compile(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@')
SCRIPT = re.compile(r"^        script\('([a-z0-9_]+)'")
# A line no existing script can depend on: blank, a comment, or new constants.
INERT = re.compile(r'^\s*(#.*)?$|^\(?[A-Z][A-Z0-9_]*(, [A-Z][A-Z0-9_]*)*\)? = \(?-?[0-9][0-9a-fx.]*(, -?[0-9][0-9a-fx.]*)*\)?$')


def kind(path):
    """'none', 'example' or 'full' for one changed path."""
    if path.endswith('.md') or path.startswith(('docs/', 'LICENSES/')) or path in ('LICENSE', '.gitignore'):
        return 'none'
    if path.startswith('.github/workflows/') or (path.startswith('tests/') and path.endswith('.py') and '/' not in path[len('tests/'):]):
        return 'none'
    if path in HARNESS:
        return 'none'
    if path in EXAMPLE_FILES or re.fullmatch(r'examples/[a-z0-9_]+\.bend', path):
        return 'example'
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


def scope(paths, probe_source='', probe_diff=''):
    """The mode and the examples to replay for the changed paths."""
    kinds = {path: kind(path) for path in paths}
    if not paths or 'full' in kinds.values():
        return dict(mode='full' if paths else 'none', examples=[])
    if 'example' not in kinds.values():
        return dict(mode='none', examples=[])
    names = registered(probe_source)
    examples = {Path(path).stem for path in paths if path.startswith('examples/')}
    if PROBE in paths:
        affected = probe_examples(probe_source, probe_diff, names)
        if affected is None:
            return dict(mode='full', examples=[])
        examples |= affected | set(CANARIES)
    unknown = sorted(examples - names)
    if unknown:
        # A port without a registration (or a deleted one) has no replay: run everything.
        return dict(mode='full', examples=[])
    if not examples:
        return dict(mode='none', examples=[])
    return dict(mode='examples', examples=sorted(examples))


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


def changed(base):
    paths = [line for line in git('diff', '--name-only', f'{base}..HEAD').splitlines() if line]
    probe_diff = git('diff', '-U0', f'{base}..HEAD', '--', PROBE) if PROBE in paths else ''
    probe = (ROOT / PROBE).read_text() if (ROOT / PROBE).is_file() else ''
    return scope(paths, probe, probe_diff)


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
            print(f'ci_scope: {error}; comparing with the event\'s base', file=sys.stderr)
            base = None
    try:
        base = base or base_ref()
        result = changed(base) if base else dict(mode='full', examples=[])
    except (subprocess.CalledProcessError, OSError, ValueError) as error:
        print(f'ci_scope: {error}; running everything', file=sys.stderr)
        result = dict(mode='full', examples=[])
    print(json.dumps(result) + note)
    output = os.environ.get('GITHUB_OUTPUT')
    if output:
        with open(output, 'a') as handle:
            print(f"mode={result['mode']}", file=handle)
            print('examples=' + ' '.join(f'--example={name}' for name in result['examples']), file=handle)
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a') as handle:
            print(f"Conformance scope: **{result['mode']}**{note} {' '.join(result['examples'])}", file=handle)


if __name__ == '__main__':
    main()
