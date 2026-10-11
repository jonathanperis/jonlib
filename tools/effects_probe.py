#!/usr/bin/env python3
"""Compare the driver's Effects programs (IO in the loop) with a raylib loop.

Reference. tools/reference/driver_effects.c, a loop that writes and reads a
file before BeginDrawing (S: SaveFileText of the frame counter; L:
LoadFileText) and writes it after EndDrawing (F still down), compiled and
driven as tools/examples_probe.py drives the raylib examples: the hooks of
tools/reference/example_driver.h play each scripted frame's automation
events, set its clocks and print its color buffer. Each script runs in a
fresh process and an empty directory.

Candidate. tools/reference/driver_effects.bend, the same loop as a J.Effects
program (its update and its `after` in IO), replayed by J.Program.replay_io
with the same events and clocks in a directory emptied before each lane. Per
frame it prints the framebuffer and the presented Image, which must be
raylib's: the text drawn shows the counter, what S saved, what L read and
the frame of the last write after EndDrawing, so a step run in another order
or a file written with other bytes changes a frame.

Scripts: `missing` reads before anything was written (LoadFileText's NULL);
`files` saves, reads the save back, holds F over two frames (each write
after EndDrawing is what the next frame's L reads) and saves again. The file
left by `files` must hold the same bytes on both sides. CPU-1, CPU-2 and
JavaScript lanes.
"""
import hashlib
import json
import shutil

import examples_probe as ep
import input_probe as ip
import probekit
from conformance import gradient_reference
from probekit import ROOT, ProbeFailure

NAME = 'driver_effects'
FILE = 'effects.txt'
KEY_S, KEY_L, KEY_F = 83, 76, 70


def register():
    """The reference loop and its Bend module as a program of the examples probe."""
    ep.EXAMPLES[NAME] = (str(ROOT / 'tools/reference/driver_effects.c'), 'Ex.setup(RESOURCES, core, frame)')
    ep.MODULES[NAME] = '../../tools/reference/driver_effects.bend'
    ep.SIZES[NAME] = (160, 90)
    ep.IO_SETUP.add(NAME)
    ep.EFFECTS.add(NAME)
    ep.SCRATCH.add(NAME)


def scripts():
    key, quick, slow = ep.key, ep.quick, ep.slow
    return [ep.timed(item) for item in (
        # L with no file: LoadFileText answers NULL (the Bend module: a Fail), the number stays 0.
        ep.script(NAME, 'missing', [quick(), quick([key(KEY_L)]), quick([key(KEY_L, False)])]),
        # S writes "2"; L reads it; F down: after EndDrawing "1004" is written, which the next frame's L reads
        # while F, still down, writes "1005" after it; F up; L reads 1005; S writes "8".
        ep.script(NAME, 'files', [quick(), quick([key(KEY_S)]), quick([key(KEY_S, False), key(KEY_L)]), quick([key(KEY_L, False), key(KEY_F)]),
                                  quick([key(KEY_L)]), slow([key(KEY_F, False), key(KEY_L, False)]), quick([key(KEY_L)]),
                                  quick([key(KEY_L, False), key(KEY_S)])]),
    )]


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('driver-effects', args, raylib_options=ip.OPTIONS)
    definitions = ip.variant_definitions(probe.library)
    if not (definitions.get('SUPPORT_AUTOMATION_EVENTS') and not definitions.get('SUPPORT_CUSTOM_FRAME_CONTROL')):
        raise ProbeFailure(f'driver-effects: reference build definitions {definitions}')
    register()
    libm = gradient_reference()
    items = scripts()
    directory = probe.work / 'candidate'
    shutil.rmtree(directory, ignore_errors=True)
    directory.mkdir(parents=True)
    ep.DIRECTORIES[NAME] = str(directory) + '/'
    left = {}

    def parse_lane(text, selected, lane):
        path = directory / FILE
        left[lane] = path.read_bytes() if path.is_file() else None
        shutil.rmtree(directory)
        directory.mkdir()
        return ['\n'.join(line for line in text.splitlines() if line.strip())]

    lanes = probe.candidates(ep.render(items, libm, None, probe.args.raylib_source), [NAME], batch=1, timeout=ep.LANE_TIMEOUT, parse_lane=parse_lane)

    binary = ep.build_reference(probe, NAME)
    width, height = ep.size_of(NAME)
    rows, files = [], {}
    for index, item in enumerate(items):
        frames = ep.native_frames(probe, binary, index, item)
        if len(frames) != len(item['frames']):
            raise ProbeFailure(f'driver-effects: the reference drew {len(frames)} frames of {item["name"]}, expected {len(item["frames"])}')
        if len(set(frames)) != len(frames):
            raise ProbeFailure(f'driver-effects: two frames of {item["name"]} are the same (the counter is drawn in each)')
        rows.append('|'.join(ep.expected_row(runs, width, height) for runs in frames) + '|')
        path = probe.work / f'native-{index}' / FILE
        files[item['name']] = path.read_bytes() if path.is_file() else None
    if files != {f'{NAME}-missing': None, f'{NAME}-files': b'8'}:
        raise ProbeFailure(f'driver-effects: the reference left {files}, expected no file after `missing` and "8" after `files`')

    def describe(i):
        for item, a, b in zip(items, rows, lanes['cpu-1'][i].split('\n')):
            if a != b:
                fa, fb = a.split('|'), b.split('|')
                first = next((k for k, (x, y) in enumerate(zip(fa, fb)) if x != y), min(len(fa), len(fb)))
                return f'script {item["name"]}, frame {first} ({len(fa) - 1} frames expected, {len(fb) - 1} drawn)'
        return f'{len(rows)} scripts expected'

    probe.compare(['\n'.join(rows)], lanes, describe=describe)
    for lane, data in left.items():
        if data != files[f'{NAME}-files']:
            raise ProbeFailure(f'driver-effects: {lane} left {data!r} in {FILE}, the reference {files[f"{NAME}-files"]!r}')
    probe.finish(scripts=len(items), frames=sum(len(item['frames']) for item in items), libm=libm, file=files[f'{NAME}-files'].decode(),
                 scripts_sha256=hashlib.sha256(json.dumps(items, default=repr).encode()).hexdigest())


if __name__ == '__main__':
    main()
