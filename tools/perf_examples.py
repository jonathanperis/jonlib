#!/usr/bin/env python3
"""Measure Jonlib's example ports against the native raylib examples: time
per frame, whole-run wall time, peak memory and the cost of mixing audio
headless. A measurement, not a gate: nothing here passes or fails on a
number.

Programs. The examples are the ones tools/examples_probe.py replays, built
the same way: the reference is the unmodified raylib example compiled with
the probe's driver and linked with its clock-injected memory-platform raylib
(examples_probe.build_reference), the candidate is the probe's generated
replay program (examples_probe.render) compiled by the pinned Bend to a
native binary (and, with --js, to JavaScript). The working directory, the
resource paths, the scratch directories and the scripted clocks are the
probe's. Neither side sleeps: SetTargetFPS waits end at once on the
scripted clock, on both sides.

Workload. For each example one probe script (the first whose frames Jonlib
answers on this host, or --script) is the "base" script, and "steady" is the
same script followed by --extra-frames idle frames (no input; a 60 FPS frame
of 4 ms). Both sides print every frame: raylib's driver as runs of the color
buffer (one line per frame, flushed), Jonlib as the same runs plus the
presented quadtree. That serialization is part of both measurements.

Timing. Wall time is from the process start to its exit; peak memory is the
process's maximum resident set (os.wait4). The reference runs base and
steady as two processes and prints a line per frame, so its time per frame
is also measured directly (median and 95th percentile of the steady run's
extra frames). Jonlib's replay is a pure function of the script and prints
one line per script, so its program runs base, steady and base again in one
process and the time per frame is the difference: (steady - base) / extra,
with the intervals between its output lines. The reference's time per frame
is computed the same way, from its two processes' wall times, and the ratio
compares those two.

Audio. Without a device, latency itself cannot be measured: what a device
adds (its period, the host's scheduling, the output buffer) is not there.
What can be measured is the work a period costs: country.mp3 played as a
music stream, each of --audio-periods periods one device callback of 480
frames (10 ms at 48000 Hz) followed by UpdateMusicStream, as
tools/reference/audio_clock.c drives raudio's miniaudio null backend and as
J.AudioClock drives Jonlib's mixer. The cost of one period is the difference
of the wall times with and without the periods, divided by their count; the
music's GetMusicTimePlayed must be the same on both sides.

    python3 tools/perf_examples.py --bend-source ~/bend --raylib-source ~/raylib \
        [--example NAME ... | --category CAT | --all] [--runs 3] [--js]

Results: .build/perf/results.json and .build/perf/results.md.
"""
import contextlib
import json
import os
import platform
import statistics
import subprocess
import sys
import time

import examples_probe as ep
import input_probe as ip
import probekit
from conformance import gradient_reference
from probekit import BUILD, ROOT, ProbeFailure

WORK = BUILD / 'perf'
DEFAULT_EXAMPLES = ('shapes_basic_shapes', 'shapes_bouncing_ball', 'textures_bunnymark', 'textures_sprite_animation',
                    'text_font_spritefont', 'text_format_text', 'models_loading_gltf', 'models_animation_timing',
                    'core_2d_camera', 'gui_style', 'audio_music_stream')
# A probe script with an idle frame of the 60 FPS target (examples_probe.quick).
IDLE = ([], 0.002, 0.004)
AUDIO_FILE = 'examples/audio/resources/country.mp3'

AUDIO_C = r'''#include "raylib.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
void JonlibAudioClockStop(void);
void JonlibAudioClockPump(unsigned periods);
int main(int argc, char **argv)
{
    unsigned periods = 0; const char *path = "";
    for (int i = 1; i + 1 < argc; i++) {
        if (!strcmp(argv[i], "--periods")) periods = (unsigned)atoi(argv[i + 1]);
        if (!strcmp(argv[i], "--file")) path = argv[i + 1];
    }
    SetTraceLogLevel(LOG_NONE);
    InitAudioDevice();
    JonlibAudioClockStop();
    Music music = LoadMusicStream(path);
    if (!IsMusicValid(music)) { printf("not loaded\n"); return 0; }
    PlayMusicStream(music);
    for (unsigned i = 0; i < periods; i++) { JonlibAudioClockPump(1); UpdateMusicStream(music); }
    float played = GetMusicTimePlayed(music);
    unsigned bits; memcpy(&bits, &played, 4);
    printf("%u\n", bits);
    return 0;
}
'''

AUDIO_BEND = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M

def device.of(mixed: J.AudioDevice & Maybe<&2, +List<U32>>) -> J.AudioDevice:
  match mixed:
    case Tuple{+device, _}: device

# n periods: one device callback of 480 frames (J.AudioClock's period), then UpdateMusicStream.
def pump(n: Nat, updated: J.AudioDevice & J.Music) -> J.AudioDevice & J.Music:
  match n:
    case 0n: updated
    case 1n+k:
      (+audio, +music) = updated
      pump(k, J.Music.update(device.of(J.AudioDevice.mix(audio, 480)), music))

def played(t: Maybe<F32>) -> String:
  match t:
    case None{}: "null"
    case Some{+v}: U32.show(F32.bits(v))

def report.music(r: J.AudioDevice & J.Music) -> String:
  (+audio, +music) = r
  played(J.Music.time_played(audio, music))

def report(loaded: J.AudioDevice & Result<&1, &1, J.Wave.IOError, J.Music>, +n: U32) -> String:
  match loaded:
    case Tuple{+audio, Fail{_}}: "not loaded"
    case Tuple{+audio, Done{+music}}: report.music(pump(U32.to_nat(n), (J.Music.play(audio, music), music)))

# "--file PATH" and "--periods N".
def options(args: List<String>, +mode: U32, path: String, +n: U32) -> String & U32:
  match args:
    case Nil{}: (path, n)
    case Con{+a, rest}:
      match mode:
        case 1: options(rest, 0, a, n)
        case 2: options(rest, 0, path, J.Desktop.frames_arg(["--frames", a]))
        case _: options(rest, Bool.pick(U32, String.eq(a, "--file"), 1, Bool.pick(U32, String.eq(a, "--periods"), 2, 0)), path, n)

def run.with(parsed: String & U32) -> IO(Unit):
  (path, +n) = parsed
  IO.bind(J.AudioDevice & Result<&1, &1, J.Wave.IOError, J.Music>, Unit, J.Music.load(J.AudioDevice.init(J.AudioDevice.none()), path),
    r => IO.print(report(r, n)))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
'''


# -----------------------------------------------------------------------------
# Pure helpers

def percentile(values, q):
    """The nearest-rank q-th percentile (0 < q <= 100) of a nonempty sequence."""
    if not values:
        raise ValueError('percentile of no values')
    ordered = sorted(values)
    rank = max(1, -(-len(ordered) * q // 100))
    return ordered[min(len(ordered), int(rank)) - 1]


def summary(values):
    """median/p95/mean/min/max of a nonempty list of numbers (None for none)."""
    if not values:
        return None
    return dict(median=statistics.median(values), p95=percentile(values, 95), mean=statistics.fmean(values),
                min=min(values), max=max(values), samples=len(values))


def intervals(times):
    """Differences between successive times."""
    return [later - earlier for earlier, later in zip(times, times[1:])]


def steady_script(script, extra):
    """A raw script (frames as (events, gap, draw)) followed by `extra` idle frames."""
    if extra < 0:
        raise ValueError('extra frames must be nonnegative')
    return dict(script, frames=list(script['frames']) + [IDLE] * extra)


def split_candidate(line_times, wall, extra):
    """Jonlib's program prints base, steady and base again; from the times of its three lines (seconds since start)
    and its wall time: startup (process start to the first script's setup), the base script (setup and frames), the time per
    extra frame ((steady - base)/extra) and the exit. None for the parts the lines cannot give (fewer than three lines, or
    lines that came out together because the output was not flushed per line)."""
    if len(line_times) != 3 or extra < 1:
        return dict(startup=None, base=None, per_frame=None, exit=None, line_timing=False)
    first, second, third = line_times
    steady, base = second - first, third - second
    together = steady <= 0 or base <= 0 or (third - first) < 0.01 * wall
    if together:
        return dict(startup=None, base=None, per_frame=None, exit=None, line_timing=False)
    return dict(startup=first - base, base=base, per_frame=(steady - base) / extra, exit=wall - third, line_timing=True)


def per_frame_from_walls(base_wall, steady_wall, extra):
    """The differential time per extra frame from two processes' wall times."""
    return (steady_wall - base_wall) / extra if extra > 0 else None


def ratio(candidate, reference):
    return candidate / reference if candidate is not None and reference not in (None, 0) and reference > 0 else None


def median_of(runs, key):
    values = [run[key] for run in runs if run.get(key) is not None]
    return statistics.median(values) if values else None


def ms(value):
    return '-' if value is None else f'{value * 1000:.2f}' if value < 0.1 else f'{value * 1000:.0f}'


def mib(kib):
    return '-' if kib is None else f'{kib / 1024:.0f}'


def times_text(value):
    return '-' if value is None else f'{value:.0f}x' if value >= 10 else f'{value:.1f}x'


def render_table(results):
    """The Markdown tables of a results document."""
    lines = ['| Example | Frames (base + extra) | raylib ms/frame (median, p95) | raylib ms/frame (diff) | Jonlib ms/frame (diff) | '
             'Ratio | raylib wall ms (steady) | Jonlib wall ms (3 scripts) | raylib peak MiB | Jonlib peak MiB | Output equal |',
             '|---|---|---|---|---|---|---|---|---|---|---|']
    for name, entry in results.get('examples', {}).items():
        if entry.get('skipped'):
            lines.append(f'| {name} | {entry["skipped"]} | | | | | | | | | |')
            continue
        native, jonlib = entry['native'], entry['cpu-1']
        direct = native.get('frame_lines') or {}
        lines.append(f'| {name} | {entry["base_frames"]} + {entry["extra_frames"]} | {ms(direct.get("median"))}, {ms(direct.get("p95"))} | '
                     f'{ms(native["per_frame"])} | {ms(jonlib["per_frame"])} | {times_text(entry.get("ratio"))} | '
                     f'{ms(native["steady_wall"])} | {ms(jonlib["wall"])} | {mib(native["peak_rss_kib"])} | {mib(jonlib["peak_rss_kib"])} | '
                     f'{"yes" if entry.get("output_equal") else "NO"} |')
    if any('javascript' in entry for entry in results.get('examples', {}).values()):
        lines += ['', '| Example | JavaScript ms/frame (diff) | Ratio to raylib | JavaScript wall ms | JavaScript peak MiB |', '|---|---|---|---|---|']
        for name, entry in results['examples'].items():
            js = entry.get('javascript')
            if js:
                lines.append(f'| {name} | {ms(js["per_frame"])} | {times_text(ratio(js["per_frame"], entry["native"]["per_frame"]))} | '
                             f'{ms(js["wall"])} | {mib(js["peak_rss_kib"])} |')
    audio = results.get('audio')
    if audio and not audio.get('skipped'):
        lines += ['', '| Audio (country.mp3 music stream) | raylib | Jonlib CPU-1 | Ratio |', '|---|---|---|---|',
                  f'| ms per 10 ms period (callback + UpdateMusicStream) | {ms(audio["native"]["per_period"])} | '
                  f'{ms(audio["cpu-1"]["per_period"])} | {times_text(audio.get("ratio"))} |',
                  f'| share of real time | {pct(audio["native"]["per_period"])} | {pct(audio["cpu-1"]["per_period"])} | |',
                  f'| peak MiB ({audio["periods"]} periods) | {mib(audio["native"]["peak_rss_kib"])} | {mib(audio["cpu-1"]["peak_rss_kib"])} | |',
                  f'| time played equal | {"yes" if audio.get("output_equal") else "NO"} | | |']
    return '\n'.join(lines) + '\n'


def pct(per_period):
    return '-' if per_period is None else f'{per_period / 0.010 * 100:.1f}%'


# -----------------------------------------------------------------------------
# Processes

def measure(command, *, cwd, env=None, stdin=subprocess.DEVNULL, timeout=ep.LANE_TIMEOUT):
    """Run a command; return its wall time, the time (since start) and text of each stdout line, its peak RSS (KiB) and
    stderr's tail. Raises ProbeFailure on a nonzero exit."""
    started = time.perf_counter()
    process = subprocess.Popen([str(part) for part in command], cwd=cwd, env=env or probekit.ENV, stdin=stdin,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    lines, times = [], []
    deadline = started + timeout
    for raw in process.stdout:
        times.append(time.perf_counter() - started)
        lines.append(raw.decode().rstrip('\n'))
        if time.perf_counter() > deadline:
            process.kill()
    stderr = process.stderr.read().decode(errors='replace')
    _, status, usage = os.wait4(process.pid, 0)
    wall = time.perf_counter() - started
    process.returncode = os.waitstatus_to_exitcode(status)
    if process.returncode:
        raise ProbeFailure(f'perf: {" ".join(map(str, command))} failed ({process.returncode}): {stderr[-2000:]}')
    return dict(wall=wall, lines=lines, times=times, peak_rss_kib=usage.ru_maxrss, stderr=stderr[-2000:])


class Context:
    """What examples_probe's builders read from a Probe: its work directory, arguments and reference library."""

    def __init__(self, args):
        self.args = args
        self.lock = probekit.pinned(args)
        self.work = WORK
        self.work.mkdir(parents=True, exist_ok=True)
        self.library = probekit.native_library(args, ip.OPTIONS)
        definitions = ip.variant_definitions(self.library)
        wanted = dict(SUPPORT_CUSTOM_FRAME_CONTROL=False, SUPPORT_BUSY_WAIT_LOOP=False, SUPPORT_PARTIALBUSY_WAIT_LOOP=True,
                      SUPPORT_AUTOMATION_EVENTS=True, SUPPORT_GESTURES_SYSTEM=True, SUPPORT_SCREEN_CAPTURE=True)
        if definitions != wanted:
            raise ProbeFailure(f'perf: reference build definitions {definitions}, expected {wanted}')


@contextlib.contextmanager
def untimed():
    """examples_probe.scripts() with its scripts' frames still as (events, gap, draw): its own timed() is set aside
    while it runs, so that idle frames can be added before the clocks are computed."""
    held = ep.timed
    ep.timed = lambda item: item
    try:
        yield
    finally:
        ep.timed = held


def raw_scripts():
    with untimed():
        return ep.scripts()


def choose_script(example, scripts, libm, wanted=None):
    """The example's script to measure: `wanted`, else the first one Jonlib answers on every frame and C defines."""
    own = [item for item in scripts if item['example'] == example]
    if wanted:
        own = [item for item in own if item['name'] in (wanted, f'{example}-{wanted}')]
    for item in own:
        if item['name'] not in ep.UNDEFINED_FROM and ep.refusal(ep.timed(item), libm) is None:
            return item
    return None


def unsupported(example):
    if example in ep.LISTED:
        return 'its setup takes directory listings'
    if example == 'textures_logo_raylib':
        return 'its program takes one script'
    return None


def native_cwd(ctx, example, index):
    """The reference's working directory, as examples_probe.native_frames chooses it."""
    in_module = example == 'textures_logo_raylib' or example in ep.IO_SETUP
    cwd = ctx.args.raylib_source / 'examples' / ep.resource_module(example) if in_module else ctx.work
    if example in ep.SCRATCH:
        cwd = ep.scratch(ctx, index, native=True) / ep.WORKING.get(example, '')
    return cwd


def expected_line(example, frames):
    width, height = ep.size_of(example)
    return '|'.join(ep.expected_row(runs, width, height) for runs in frames) + '|'


def measure_example(ctx, example, script, libm, extra, runs, js):
    base = ep.timed(script)
    steady = ep.timed(steady_script(script, extra))
    # Candidate scripts: base, steady, base. Reference scripts: base (index 0) and steady (index 1).
    items = [base, steady, base]
    entry = dict(script=script['name'], base_frames=len(script['frames']), extra_frames=extra)
    logo = ctx.args.raylib_source / 'examples/textures/resources/raylib_logo.png'
    directories = {index: ep.scratch(ctx, index) for index, item in enumerate(items) if item['example'] in ep.SCRATCH}
    source = ctx.work / f'{example}.bend'
    source.write_text(ep.render(items, libm, logo, ctx.args.raylib_source, directories)([example], False))
    binary, javascript = ctx.work / f'{example}-candidate', ctx.work / f'{example}-candidate.js'
    cli = ['bun', ctx.args.bend_source / 'bend2/main.ts']
    print(f'{example}: compiling the candidate', flush=True)
    started = time.perf_counter()
    probekit.compile_outputs(cli, source, binary, *([javascript] if js else []))
    entry['compile_seconds'] = time.perf_counter() - started
    reference = ep.build_reference(ctx, example)

    native_runs, lanes = [], {'cpu-1': [binary, '--gpu', 'off', '--threads', '1']}
    if js:
        lanes['javascript'] = ['bun', javascript]
    lane_runs = {lane: [] for lane in lanes}
    native_output = None
    for repeat in range(runs):
        measured = {}
        for index, item in enumerate((base, steady)):
            path = ctx.work / f'script-{example}-{index}.txt'
            path.write_text(ep.script_text(item))
            ep.scratch_reset(ctx, items, native=True)
            measured[index] = measure([reference], cwd=native_cwd(ctx, example, index),
                                      env=dict(probekit.ENV, JONLIB_EXAMPLE_SCRIPT=str(path)))
        frames = {index: [line[2:] for line in m['lines'] if line.startswith('F ')] for index, m in measured.items()}
        if native_output is None:
            native_output = [expected_line(example, frames[0]), expected_line(example, frames[1])]
        frame_times = [t for t, line in zip(measured[1]['times'], measured[1]['lines']) if line.startswith('F ')]
        extra_intervals = intervals(frame_times)[-extra:] if extra else []
        native_runs.append(dict(base_wall=measured[0]['wall'], steady_wall=measured[1]['wall'],
                                per_frame=per_frame_from_walls(measured[0]['wall'], measured[1]['wall'], extra),
                                frame_intervals=extra_intervals, peak_rss_kib=max(m['peak_rss_kib'] for m in measured.values())))
        for lane, command in lanes.items():
            ep.scratch_reset(ctx, items)
            m = measure(command, cwd=ROOT)
            split = split_candidate(m['times'], m['wall'], extra)
            if repeat == 0:
                lines = [line for line in m['lines'] if line.strip()]
                equal = lines == [native_output[0], native_output[1], native_output[0]]
                entry.setdefault('lane_output_equal', {})[lane] = equal
            lane_runs[lane].append(dict(wall=m['wall'], peak_rss_kib=m['peak_rss_kib'], **split))
        print(f'{example}: run {repeat + 1}/{runs}: raylib {native_runs[-1]["per_frame"] * 1000:.2f} ms/frame, Jonlib '
              + ', '.join(f'{lane} {ms(r[-1]["per_frame"])} ms/frame' for lane, r in lane_runs.items()), flush=True)

    entry['native'] = dict(per_frame=median_of(native_runs, 'per_frame'), base_wall=median_of(native_runs, 'base_wall'),
                           steady_wall=median_of(native_runs, 'steady_wall'), peak_rss_kib=max(r['peak_rss_kib'] for r in native_runs),
                           frame_lines=summary([t for r in native_runs for t in r['frame_intervals']]), runs=native_runs)
    for lane, measured in lane_runs.items():
        entry[lane] = dict(per_frame=median_of(measured, 'per_frame'), wall=median_of(measured, 'wall'),
                           startup=median_of(measured, 'startup'), base=median_of(measured, 'base'),
                           peak_rss_kib=max(r['peak_rss_kib'] for r in measured), runs=measured)
    entry['output_equal'] = all(entry['lane_output_equal'].values())
    entry['ratio'] = ratio(entry['cpu-1']['per_frame'], entry['native']['per_frame'])
    return entry


def measure_audio(ctx, periods, runs):
    path = ctx.args.raylib_source / AUDIO_FILE
    include = '-I' + str(ctx.args.raylib_source / 'src')
    source, binary = ctx.work / 'audio.c', ctx.work / 'audio-reference'
    source.write_text(AUDIO_C)
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', include, '-c', source, '-o', ctx.work / 'audio.o'])
    probekit.run(['clang', '-std=c11', '-D_DEFAULT_SOURCE', '-O2', '-ffp-contract=off', '-w', '-DMA_ENABLE_ONLY_SPECIFIC_BACKENDS', '-DMA_ENABLE_NULL',
                  include, '-c', ep.AUDIO_CLOCK_UNIT, '-o', ctx.work / 'audio-clock.o'])
    probekit.run(['clang', ctx.work / 'audio.o', ctx.work / 'audio-clock.o', ctx.library, '-lm', '-lpthread', '-ldl', '-o', binary])
    bend, candidate = ctx.work / 'audio.bend', ctx.work / 'audio-candidate'
    bend.write_text(AUDIO_BEND)
    print('audio: compiling the candidate', flush=True)
    probekit.compile_outputs(['bun', ctx.args.bend_source / 'bend2/main.ts'], bend, candidate)
    sides = {'native': [binary], 'cpu-1': [candidate, '--gpu', 'off', '--threads', '1']}
    out = dict(file=AUDIO_FILE, periods=periods)
    outputs = {}
    for side, command in sides.items():
        samples = []
        for _ in range(runs):
            empty = measure([*command, '--file', path, '--periods', '0'], cwd=ROOT)
            full = measure([*command, '--file', path, '--periods', str(periods)], cwd=ROOT)
            outputs[side] = full['lines']
            samples.append(dict(per_period=(full['wall'] - empty['wall']) / periods, load_wall=empty['wall'], wall=full['wall'],
                                peak_rss_kib=full['peak_rss_kib']))
        out[side] = dict(per_period=median_of(samples, 'per_period'), load_wall=median_of(samples, 'load_wall'),
                         peak_rss_kib=max(s['peak_rss_kib'] for s in samples), runs=samples, output=outputs[side])
        print(f'audio: {side} {ms(out[side]["per_period"])} ms per period', flush=True)
    out['output_equal'] = outputs['native'] == outputs['cpu-1'] and outputs['native'] != ['not loaded']
    out['ratio'] = ratio(out['cpu-1']['per_period'], out['native']['per_period'])
    return out


def machine():
    model = next((line.split(':', 1)[1].strip() for line in open('/proc/cpuinfo') if line.startswith('model name')), platform.processor()) \
        if os.path.exists('/proc/cpuinfo') else platform.processor()
    memory, limit = probekit.memory_limits()
    clang = subprocess.run(['clang', '--version'], capture_output=True, text=True).stdout.splitlines()
    return dict(cpu=model, cpus=os.cpu_count(), memory_bytes=memory, cgroup_memory_bytes=limit or None, system=platform.platform(),
                clang=clang[0] if clang else None, bun=subprocess.run(['bun', '--version'], capture_output=True, text=True).stdout.strip())


def configure(parser):
    parser.add_argument('--example', action='append', choices=sorted(ep.EXAMPLES), help='measure these examples')
    parser.add_argument('--category', choices=sorted({name.split('_')[0] for name in ep.EXAMPLES}), help="one category's examples")
    parser.add_argument('--all', action='store_true', help='every registered example')
    parser.add_argument('--script', help='the script to measure (with one --example)')
    parser.add_argument('--runs', type=int, default=3, help='measured runs of each program (default 3)')
    parser.add_argument('--extra-frames', type=int, default=30, help='idle frames added to the steady script (default 30)')
    parser.add_argument('--js', action='store_true', help='also measure the JavaScript lane (50-90x slower than native)')
    parser.add_argument('--audio-periods', type=int, default=300, help='10 ms periods mixed by the audio measurement (default 300)')
    parser.add_argument('--no-audio', action='store_true', help='skip the audio measurement')


def selected(args):
    if args.all:
        return list(ep.EXAMPLES)
    if args.category:
        return [name for name in ep.EXAMPLES if name.split('_')[0] == args.category]
    return list(args.example or DEFAULT_EXAMPLES)


def main():
    args = probekit.arguments(__doc__, configure)
    if args.runs < 1 or args.extra_frames < 1 or args.audio_periods < 1:
        sys.exit('--runs, --extra-frames and --audio-periods must be positive')
    if args.script and len(args.example or []) != 1:
        sys.exit('--script takes exactly one --example')
    ctx = Context(args)
    libm = gradient_reference()
    results = dict(tool='tools/perf_examples.py', toolchain=ctx.lock, machine=machine(), libm=libm, runs=args.runs,
                   extra_frames=args.extra_frames, examples={})
    report = WORK / 'results.json'
    scripts = raw_scripts()

    def save():
        report.write_text(json.dumps(results, indent=2) + '\n')
        (WORK / 'results.md').write_text(render_table(results))

    for example in selected(args):
        reason = unsupported(example)
        script = None if reason else choose_script(example, scripts, libm, args.script)
        if script is None:
            results['examples'][example] = dict(skipped=reason or f'no script Jonlib answers on every frame under {libm}')
            print(f'{example}: skipped ({results["examples"][example]["skipped"]})', flush=True)
            save()
            continue
        if len(script['frames']) + args.extra_frames >= ep.MAX_FRAMES:
            sys.exit(f'{example}: {len(script["frames"])} + {args.extra_frames} frames exceed the driver\'s {ep.MAX_FRAMES - 1}')
        try:
            results['examples'][example] = measure_example(ctx, example, script, libm, args.extra_frames, args.runs, args.js)
        except ProbeFailure as failure:
            results['examples'][example] = dict(skipped=f'failed: {str(failure).splitlines()[0][:200]}')
            print(f'{example}: FAILED {failure}', flush=True)
        save()
    if not args.no_audio:
        try:
            results['audio'] = measure_audio(ctx, args.audio_periods, args.runs)
        except ProbeFailure as failure:
            results['audio'] = dict(skipped=f'failed: {str(failure).splitlines()[0][:200]}')
            print(f'audio: FAILED {failure}', flush=True)
    save()
    print(render_table(results))


if __name__ == '__main__':
    main()
