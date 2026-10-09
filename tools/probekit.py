"""Shared runner for differential probes against the pinned raylib reference.

A probe supplies fixtures, a C reference program and a Bend candidate program.
This module owns everything else: pinned-source checks, cached native raylib
builds per option set, one Bend compile per batch, the CPU-1/CPU-2/JavaScript
(and optional forced-GPU) lanes, exact comparison and the results file.

Typical probe:

    args = probekit.arguments(__doc__)
    probe = probekit.Probe('sha', args)
    expected = probe.native(reference_c)               # stdout of the C oracle
    lanes = probe.candidates(render, actions, batch=64)  # {lane: [rows...]}
    probe.compare(expected_rows, lanes)
    probe.finish(cases=len(actions))
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build'
ENV = dict(os.environ, BEND_NO_TELEMETRY='1')
CPU_LANES = ('cpu-1', 'cpu-2', 'javascript')
COMPILE_TIMEOUT = 1800
DEFAULT_RAYLIB_OPTIONS = ('PLATFORM=Memory', 'CMAKE_BUILD_TYPE=Release', 'BUILD_EXAMPLES=OFF',
                          'CUSTOMIZE_BUILD=ON', 'SUPPORT_MODULE_RAUDIO=OFF',
                          'SUPPORT_RPRAND_GENERATOR=ON', 'USE_EXTERNAL_GLFW=OFF')


class ProbeFailure(Exception):
    """A candidate/reference mismatch or a failed command."""


def run(command, *, cwd=ROOT, timeout=600, fd_limit=None, env=None):
    """Run a command and return stdout; raise ProbeFailure with output tails."""
    command = [str(part) for part in command]
    if fd_limit is not None:
        # Exec through a launcher: preexec_fn is unsafe with the batch thread pool.
        command = [sys.executable, '-c', 'import os,resource,sys;'
                   f'resource.setrlimit(resource.RLIMIT_NOFILE,({int(fd_limit)},{int(fd_limit)}));'
                   'os.execvp(sys.argv[1],sys.argv[1:])', *command]
    result = subprocess.run(command, cwd=cwd, env=env or ENV, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise ProbeFailure(f'Command failed ({result.returncode}): {" ".join(map(str, command))}\n'
                           + result.stdout[-4000:] + result.stderr[-4000:])
    return result.stdout


# Compiling one candidate that imports jonlib.bend peaks near 8 GB in the Bend
# compiler (measured October 2026; the JavaScript lane of a large codec batch
# peaks near 4.5 GB), so each concurrent batch is budgeted 9 GB of memory
# (hosted runners: Linux 16 GB -> 1 batch, macOS 7 GB -> 1). Two concurrent
# compiles exhausted a Linux runner. PROBEKIT_JOBS or --jobs override this.
MEMORY_PER_BATCH = 9 << 30
CGROUP_MEMORY = Path('/sys/fs/cgroup/memory.max')


def available_memory():
    """Physical memory, or the cgroup v2 limit when one is lower (containers)."""
    try:
        memory = os.sysconf('SC_PAGE_SIZE') * os.sysconf('SC_PHYS_PAGES')
    except (AttributeError, OSError, ValueError):
        memory = 0
    try:
        limit = int(CGROUP_MEMORY.read_text())
    except (OSError, ValueError):
        limit = 0
    return min(memory, limit) if memory and limit else memory or limit


def default_jobs():
    """Concurrent batches bounded by CPUs (at most 4) and available memory."""
    return max(1, min(4, os.cpu_count() or 1, available_memory() // MEMORY_PER_BATCH or 1))


def arguments(description, configure=None, argv=None, *, bend=True, raylib=True):
    """Common CLI: pinned checkouts, optional forced-GPU lane and batch parallelism.

    Bend-only probes (no native oracle) pass raylib=False; native-only diagnostics
    pass bend=False.
    """
    parser = argparse.ArgumentParser(description=description)
    if bend:
        parser.add_argument('--bend-source', type=Path, required=True)
    if raylib:
        parser.add_argument('--raylib-source', type=Path, required=True)
    parser.add_argument('--gpu', action='store_true', help='also run a forced-GPU lane; failure is fatal')
    parser.add_argument('--jobs', type=int, default=int(os.environ.get('PROBEKIT_JOBS', default_jobs())),
                        help='batches compiled/run concurrently (results keep plan order)')
    if configure:
        configure(parser)
    args = parser.parse_args(argv)
    if args.jobs < 1:
        parser.error('--jobs must be positive')
    return args


def pinned(args):
    """Fail unless both checkouts match toolchain.json (including the Bend overlay)."""
    from conformance import checkout
    lock = json.loads((ROOT / 'toolchain.json').read_text())
    if getattr(args, 'bend_source', None) is not None:
        checkout(args.bend_source, lock['bend']['revision'], lock['bend'].get('patch'))
        version = run(['bun', '--version']).strip()
        if version != lock['bun']['version']:
            raise ProbeFailure(f'bun {version} differs from pinned {lock["bun"]["version"]}')
    if getattr(args, 'raylib_source', None) is not None:
        checkout(args.raylib_source, lock['raylib']['revision'])
    return lock


def native_library(args, options=()):
    """Build (once per option set) and return the pinned raylib static library."""
    options = tuple(DEFAULT_RAYLIB_OPTIONS) + tuple(options)
    key = hashlib.sha256('\n'.join(options).encode()).hexdigest()[:12]
    build = BUILD / 'raylib' if not tuple(options[len(DEFAULT_RAYLIB_OPTIONS):]) else BUILD / f'raylib-{key}'
    library = build / 'raylib/libraylib.a'
    stamp = build / 'probekit-options.json'
    build.mkdir(parents=True, exist_ok=True)
    import fcntl
    with open(build.parent / f'{build.name}.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)  # concurrent probes share one cached build per option set
        if not (library.is_file() and stamp.is_file() and json.loads(stamp.read_text()) == list(options)):
            run(['cmake', '-S', args.raylib_source, '-B', build, *('-D' + o for o in options)])
            run(['cmake', '--build', build, '--parallel', '4'])
            stamp.write_text(json.dumps(list(options)) + '\n')
    return library


def compile_outputs(cli, source, *outputs, timeout=COMPILE_TIMEOUT):
    """Compile a Bend program once per output (native binary, .js, .c).

    One compiler process per output: a single process emitting both the native
    binary and the JavaScript peaks above their separate peaks combined with the
    C compiler (about 8.5 GB against 6.5 and 4 GB for a probe that reaches the
    TrueType and frame paths), which exceeds the hosted macOS runners' memory."""
    for output in outputs:
        run([*cli, source, '-o', output], timeout=timeout)


class Probe:
    """One probe run: a work directory, the native oracle and candidate lanes."""

    def __init__(self, name, args, *, raylib_options=()):
        self.name, self.args = name, args
        self.lock = pinned(args)
        self.work = BUILD / f'{name}-probe'
        self.work.mkdir(parents=True, exist_ok=True)
        self.results = self.work / 'results.json'
        self.results.write_text(json.dumps(dict(passed=False)) + '\n')
        self.library = native_library(args, raylib_options) if getattr(args, 'raylib_source', None) else None
        self.report = dict(passed=False, probe=name, toolchain=self.lock,
                           raylib_options=list(raylib_options), lanes={})

    def diagnostic(self, **summary):
        """Finish a report-only run: native observations are recorded, nothing is compared."""
        self.report.update(summary, passed=True, diagnostic=True)
        self.save()
        print(f'{self.name}: DIAGNOSTIC recorded (no parity claim): '
              + ', '.join(f'{k}={v}' for k, v in summary.items()), flush=True)

    @property
    def lanes(self):
        return CPU_LANES + (('gpu',) if self.args.gpu else ())

    def native(self, c_source, name='reference', *, fd_limit=None, extra_flags=(), link_raylib=True):
        """Compile a C program (against the reference library unless link_raylib=False) and return its stdout."""
        source, binary = self.work / f'{name}.c', self.work / name
        source.write_text(c_source)
        source_dir = getattr(self.args, 'raylib_source', None)
        raylib = (['-I' + str(source_dir / 'src')] if source_dir else []) + ([self.library] if link_raylib and self.library else [])
        run(['clang', '-std=c11', '-O2', '-fno-builtin-atan2f', *extra_flags, source, *raylib, '-lm', '-o', binary])
        return run([binary], fd_limit=fd_limit)

    def native_batches(self, render, items, *, batch, source_limit=None, name='reference', fd_limit=None):
        """Run render(selected) C programs over ordered batches; return concatenated stdout."""
        batches = plan_batches(items, batch, None if source_limit is None else
                               (lambda selected: len(render(selected).encode())), source_limit)
        self.report['native_batches'] = len(batches)
        return ''.join(self.native(render(selected), f'{name}-{index}', fd_limit=fd_limit)
                       for index, selected in enumerate(batches))

    def _compile(self, index, render):
        cli = ['bun', self.args.bend_source / 'bend2/main.ts']
        source, binary, script = (self.work / f'candidate-{index}.bend', self.work / f'candidate-{index}',
                                  self.work / f'candidate-{index}.js')
        source.write_text(render(False))
        # Compile time grows with batch size and machine load; it is a budget, not a check.
        compile_outputs(cli, source, binary, script)
        commands = {'cpu-1': [binary, '--gpu', 'off', '--threads', '1'],
                    'cpu-2': [binary, '--gpu', 'off', '--threads', '2'],
                    'javascript': ['bun', script]}
        if self.args.gpu:
            gpu_source, gpu_binary = self.work / f'candidate-{index}-gpu.bend', self.work / f'candidate-{index}-gpu'
            gpu_source.write_text(render(True))
            run([*cli, gpu_source, '-o', gpu_binary], timeout=COMPILE_TIMEOUT)
            commands['gpu'] = [gpu_binary, '--gpu', 'on']
        return commands

    def candidates(self, render, actions, *, batch=64, source_limit=None, fd_limit=None, parse=None, parse_lane=None):
        """Run every batch of actions on every lane; return {lane: [row, ...]} in plan order.

        render(selected_actions, gpu) returns Bend source text; parse(stdout, selected)
        returns the rows for that batch (default: one JSON value per output line).
        Batches hold at most `batch` actions and, if given, `source_limit` bytes of
        generated source (large programs exceed compiler budgets). parse_lane(stdout,
        selected, lane) replaces parse when rows depend on the lane (for example files
        each lane writes that the parser reads and removes).
        """
        if not actions:
            raise ProbeFailure(f'{self.name}: empty action list')
        parse = parse or (lambda text, selected: [json.loads(line) for line in text.splitlines() if line.strip()])
        batches = plan_batches(actions, batch, None if source_limit is None else
                               (lambda selected: len(render(selected, False).encode())), source_limit)

        def execute(item):
            index, selected = item
            commands = self._compile(index, lambda gpu: render(selected, gpu))
            rows = {}
            for lane, command in commands.items():
                text = run(command, fd_limit=fd_limit)
                rows[lane] = parse_lane(text, selected, lane) if parse_lane else parse(text, selected)
                if len(rows[lane]) != len(selected):
                    raise ProbeFailure(f'{self.name}: {lane} batch {index} produced {len(rows[lane])} rows '
                                       f'for {len(selected)} actions')
            return rows

        with ThreadPoolExecutor(max_workers=self.args.jobs) as pool:
            outcomes = list(pool.map(execute, enumerate(batches)))
        result = {lane: [row for outcome in outcomes for row in outcome[lane]] for lane in self.lanes}
        self.report['batches'] = len(batches)
        return result

    def compare(self, expected, lanes, describe=None):
        """Require every lane to equal the native rows exactly."""
        describe = describe or (lambda index: f'action {index}')
        for lane, actual in lanes.items():
            if len(actual) != len(expected):
                raise ProbeFailure(f'{self.name}: {lane} produced {len(actual)} rows, expected {len(expected)}')
            different = [i for i, (a, b) in enumerate(zip(expected, actual)) if a != b]
            self.report['lanes'][lane] = dict(passed=not different, rows=len(actual), different=different[:20])
            self.save()
            if different:
                first = different[0]
                raise ProbeFailure(f'{self.name}: {lane} differs at {len(different)} rows; first {describe(first)}: '
                                   f'raylib={json.dumps(expected[first])[:400]} jonlib={json.dumps(actual[first])[:400]}')

    def save(self):
        self.results.write_text(json.dumps(self.report, indent=2) + '\n')

    def finish(self, **summary):
        self.report.update(summary, passed=True)
        self.save()
        lanes = '/'.join(self.report['lanes'])
        details = ', '.join(f'{key}={value}' for key, value in summary.items())
        print(f'{self.name}: PASS on {lanes} ({details})', flush=True)


def plan_batches(actions, batch, measure=None, limit=None):
    """Split actions into ordered batches of at most `batch` items (and `limit` source bytes)."""
    if batch < 1:
        raise ValueError('batch size must be positive')
    batches, start = [], 0
    while start < len(actions):
        count = min(batch, len(actions) - start)
        if measure is not None:
            count = 1
            if measure(actions[start:start + 1]) > limit:
                raise ProbeFailure(f'action {start} alone exceeds the {limit}-byte source budget')
            while count < batch and start + count < len(actions) and measure(actions[start:start + count + 1]) <= limit:
                count += 1
        batches.append(actions[start:start + count])
        start += count
    return batches


def bend_list(values):
    """Render integers as a Bend list literal."""
    return '[' + ', '.join(map(str, values)) + ']'


def c_bytes(values):
    """Render integers as a C unsigned-char initializer."""
    return '{' + ','.join(map(str, values)) + '}'


if __name__ == '__main__':
    sys.exit('probekit is a library; run a *_probe.py script')
