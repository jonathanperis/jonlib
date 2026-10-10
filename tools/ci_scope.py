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
  ports, the examples the probe's changed lines name, and, whenever the probe
  changed, three canaries (a plain window, a seeded example with a refusal and
  one that loads a file). A change at or below the probe's native driver
  (`C_DRIVER`), where the comparison itself lives, is `full`.
- `none`: only files no gate reads (workflows, unit tests, this tool,
  documentation). The Checks workflow covers them.

The base of the comparison is the previous head for a push to `main`, and the
merge base with `main` for any other branch or a pull request. When the base
cannot be found the scope is `full`. A push to `main` of a commit whose
Conformance run already succeeded on a branch (a fast-forward merge) is
`none`: the branch compared the same tree against an ancestor of that base.
A scheduled run is `none` when a scheduled or manual run (always full) of the
same commit already succeeded.

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
HUNK = re.compile(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@', re.M)


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


def named(diff, names):
    """The registered examples that the changed lines of a probe diff name."""
    found = set()
    for line in diff.splitlines():
        if line.startswith(('+', '-')) and not line.startswith(('+++', '---')):
            found.update(token for token in QUOTED.findall(line) if token in names)
    return found


def harness_changed(probe_source, diff):
    """Whether a probe diff reaches the native driver or the code below it."""
    lines = probe_source.splitlines()
    marker = next((index + 1 for index, line in enumerate(lines) if line.startswith(HARNESS_MARKER)), None)
    if marker is None:
        return True
    hunks = HUNK.findall(diff)
    return not hunks or any(int(start) + max(int(count or 1), 1) - 1 >= marker for start, count in hunks)


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
        if harness_changed(probe_source, probe_diff):
            return dict(mode='full', examples=[])
        examples |= named(probe_diff, names) | set(CANARIES)
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


def verified(runs, run_id, events):
    """Whether another Conformance run of this commit, started by one of the events, succeeded."""
    return any(run.get('conclusion') == 'success' and str(run.get('id')) != str(run_id) and run.get('event') in events for run in runs)


def accepted_events(env):
    """The events whose successful run of this commit makes this run redundant."""
    event = env.get('GITHUB_EVENT_NAME')
    if event == 'schedule':
        return FULL_EVENTS
    if event == 'push' and env.get('GITHUB_REF_NAME') == 'main':
        return ('push', *FULL_EVENTS)
    return ()


def already_verified(env=os.environ):
    """A push to main that a branch run already passed, or a nightly run of a commit already run in full."""
    events = accepted_events(env)
    if not events or not env.get('GH_TOKEN'):
        return False
    query = f"repos/{env['GITHUB_REPOSITORY']}/actions/workflows/conformance.yml/runs?head_sha={env['GITHUB_SHA']}&status=success&per_page=50"
    runs = json.loads(subprocess.run(['gh', 'api', query], check=True, capture_output=True, text=True).stdout)
    return verified(runs.get('workflow_runs', []), env.get('GITHUB_RUN_ID', ''), events)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--base', help='compare with this commit instead of reading the GitHub event')
    args = parser.parse_args(argv)
    try:
        base = args.base or base_ref()
        result = changed(base) if base else dict(mode='full', examples=[])
    except (subprocess.CalledProcessError, OSError, ValueError) as error:
        print(f'ci_scope: {error}; running everything', file=sys.stderr)
        result = dict(mode='full', examples=[])
    try:
        if not args.base and result['mode'] != 'none' and already_verified():
            result = dict(mode='none', examples=[], verified=True)
    except (subprocess.CalledProcessError, OSError, ValueError, KeyError) as error:
        print(f'ci_scope: {error}; keeping the scope', file=sys.stderr)
    print(json.dumps(result))
    output = os.environ.get('GITHUB_OUTPUT')
    if output:
        with open(output, 'a') as handle:
            print(f"mode={result['mode']}", file=handle)
            print('examples=' + ' '.join(f'--example={name}' for name in result['examples']), file=handle)
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a') as handle:
            reason = ' (this commit already passed)' if result.get('verified') else ''
            print(f"Conformance scope: **{result['mode']}**{reason} {' '.join(result['examples'])}", file=handle)


if __name__ == '__main__':
    main()
