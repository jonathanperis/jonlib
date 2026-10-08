#!/usr/bin/env python3
"""Compare Jonlib's Core (input, automation events, timing, gestures) with
pinned raylib's memory platform replaying the same scripts.

Reference build. Pinned raylib on PLATFORM=Memory, built for this probe with
CMAKE_C_FLAGS="-ffp-contract=off -include tools/reference/input_clock.h" and
SUPPORT_CUSTOM_FRAME_CONTROL=OFF, SUPPORT_BUSY_WAIT_LOOP=OFF. The shim header
only renames identifiers: GetTime() calls read the script's clock (on macOS
rcore_memory.c's GetTime returns 0.0, so neither frame timing nor rgestures.h
timeouts could otherwise be exercised, and SetTargetFPS would hang in
WaitTime), and WaitTime's usleep/nanosleep record the request and advance the
clock to the script's end-of-wait time. The two SUPPORT_* options restore
config.h's defaults: probekit's CUSTOMIZE_BUILD=ON parses every
"#define SUPPORT_X 0" in config.h as ON, which would compile EndDrawing without
timing or PollInputEvents. The probe checks the variant's compile definitions.
On macOS it also runs every script whose clock stays 0 (and that never waits)
against the same variant without the shim, where GetTime() is the platform's
own 0.0, and requires identical rows: the shim changes nothing else.

Scripts. Each script runs in a fresh native process (rgestures.h and GetFPS
keep static state across InitWindow) and in its own directory (TakeScreenshot
files). Operations: PlayAutomationEvent of every event type (out-of-range
indexes only as contracts), BeginDrawing/EndDrawing with scripted clocks
(EndDrawing calls PollInputEvents), PollInputEvents and UpdateGestures alone,
ProcessGestureEvent with explicit times, mouse/cursor/exit-key/gesture-flag
setters, SetTargetFPS, GetKeyPressed/GetCharPressed drains, GetFPS, automation
recording (SetAutomationEventList, Start/Stop, SetAutomationEventBaseFrame,
capacity overflow), ExportAutomationEventList file bytes and
LoadAutomationEventList of crafted text files. A query row records every
keyboard, mouse, touch, gamepad, gesture, window, frame-time and screenshot
query (the screenshot count is the number of screenshot%03i.png files
written). Before each EndDrawing Jonlib prints Core.frame_wait; the harness
maps it to the sleep request WaitTime makes on the host (usleep microseconds
on macOS, nanosleep seconds/nanoseconds on Linux) and compares that with the
recorded request.

Contracts (Jonlib must answer null; never run natively): event indexes outside
raylib's arrays, negative gamepad/touch indexes, GetMouseX/GetTouchX
conversions out of int range, GetFPS before its first sample (1/0), recording
an (int) position of 2^31, starting a recording without a list, a wait end
before the WaitTime destination, export of an event type above 23, and event
files with out-of-range numbers, an over-long description, "0x" without hex
digits or more than 16384 events.

The rgestures.h swipe and pinch angles use atan2f: the M.Libm profile is the
host's, selected from native controls (tools/native_profiles.py). CPU-1, CPU-2
and JavaScript lanes.
"""
import hashlib
import json
import platform
import re
import shutil
import struct

import probekit
import native_profiles
from probekit import ROOT, ProbeFailure

SHIM = ROOT / 'tools/reference/input_clock.h'
OPTIONS = ('CMAKE_C_FLAGS=-ffp-contract=off -include ' + str(SHIM),
           'SUPPORT_CUSTOM_FRAME_CONTROL=OFF', 'SUPPORT_BUSY_WAIT_LOOP=OFF')
PLAIN_OPTIONS = ('CMAKE_C_FLAGS=-ffp-contract=off', 'SUPPORT_CUSTOM_FRAME_CONTROL=OFF', 'SUPPORT_BUSY_WAIT_LOOP=OFF')
PROFILES = {'Apple2007AngleRn': 'AppleLibm', 'Sun239AngleRn': 'Glibc239Libm', 'Glibc241AngleRn': 'Glibc241Libm'}

(EVENT_NONE, KEY_UP, KEY_DOWN, KEY_PRESSED, KEY_RELEASED, MOUSE_UP, MOUSE_DOWN, MOUSE_POSITION, MOUSE_WHEEL,
 PAD_CONNECT, PAD_DISCONNECT, PAD_UP, PAD_DOWN, PAD_AXIS, TOUCH_UP, TOUCH_DOWN, TOUCH_POSITION, GESTURE,
 WINDOW_CLOSE, WINDOW_MAXIMIZE, WINDOW_MINIMIZE, WINDOW_RESIZE, SCREENSHOT, SET_FPS) = range(24)

KEYS = [-1, 0, 32, 65, 66, 256, 259, 260, 300, 301, 340, 511, 512]
BUTTONS = [-1, 0, 1, 2, 3, 4, 5, 6, 7]
PAD_BUTTONS = [0, 1, 15, 31, 32]
GESTURE_FLAGS = [0, 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 3]


def f32(value):
    return struct.unpack('<f', struct.pack('<f', value))[0]


def fbits(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def dbits(value):
    return struct.unpack('<Q', struct.pack('<d', value))[0]


def word(value):
    return value & 0xFFFFFFFF


def s32(value):
    value = word(value)
    return f'(int){value}u' if value >= 1 << 31 else str(value)


# -----------------------------------------------------------------------------
# Scripts

def ev(kind, p0=0, p1=0, p2=0, p3=0, frame=0):
    return ('play', kind, p0, p1, p2, p3, frame)


def frame(begin, end, after=None):
    """BeginDrawing at `begin`, EndDrawing at `end`; a wait (if any) ends at `after`."""
    return [('clock', begin), ('begin',), ('clock', end), ('end', end if after is None else after)]


def script(name, ops, width=320, height=240, start=0.0, contract=None):
    return dict(name=name, ops=ops, width=width, height=height, start=start, contract=contract)


def keyboard_scripts():
    out = []
    ops = [('query',), ev(KEY_DOWN, 65), ev(KEY_DOWN, 65), ev(KEY_DOWN, 66), ('query',), ('keys',)]
    ops += frame(0, 0) + [('query',), ('keys',)]
    ops += [ev(KEY_UP, 65), ('query',)] + frame(0, 0) + [('query',)]
    ops += [ev(KEY_PRESSED, 32), ev(KEY_RELEASED, 32), ev(KEY_DOWN, 0), ev(KEY_DOWN, 511), ev(KEY_DOWN, 259),
            ev(KEY_DOWN, 260), ev(KEY_DOWN, 300), ('query',)] + frame(0, 0) + [('query',)]
    ops += [ev(KEY_UP, 260), ev(KEY_UP, 259), ev(KEY_UP, 300), ('query',)] + frame(0, 0) + [('query',), ('keys',), ('chars',)]
    ops += [('exit_key', 66), ev(KEY_DOWN, 256), ('query',), ('keys',)]
    # PollInputEvents called directly (custom frame control).
    ops += [ev(KEY_DOWN, 70), ev(TOUCH_DOWN, 2), ('poll',), ('query',), ('keys',)]
    out.append(script('keys-basic', ops))
    # Queue overflow: 20 distinct keys in one frame, then a held key re-pressed.
    ops = [('keys_down', 40, 20), ('query',), ('keys',), ('keys',)] + frame(0, 0)
    ops += [('keys_down', 40, 3), ev(KEY_DOWN, 70), ('keys',)] + frame(0, 0) + [('query',), ('keys',)]
    ops += [('keys_down', 1, 17), ('keys',), ('keys',)]
    out.append(script('keys-queue', ops))
    # F12 (key 301): its previous state is never updated on the memory platform.
    ops = [ev(KEY_DOWN, 301), ('query',)] + frame(0, 0) + [('query',)] + frame(0, 0) + [ev(KEY_UP, 301), ('query',)]
    ops += frame(0, 0) + [('query',), ev(SCREENSHOT), ev(SCREENSHOT), ('query',)]
    out.append(script('keys-f12', ops, 16, 8))
    return out


def mouse_scripts():
    out = []
    ops = [('query',)]
    for b in range(8):
        ops.append(ev(MOUSE_DOWN, b))
    ops += [('query',)] + frame(0, 0) + [('query',)]
    ops += [ev(MOUSE_UP, 1), ev(MOUSE_UP, 7), ('query',)] + frame(0, 0) + [('query',)]
    ops += [ev(MOUSE_POSITION, 100, 50), ev(MOUSE_WHEEL, 2, -3), ('query',)] + frame(0, 0)
    ops += [ev(MOUSE_POSITION, -7, 16777217), ev(MOUSE_WHEEL, -5, 4), ('query',)]
    ops += [ev(MOUSE_WHEEL, 3, 3), ('query',), ev(MOUSE_WHEEL, 0, 0), ('query',)]
    ops += [('mouse_offset', -10, 25), ('mouse_scale', 0.5, -2.0), ('query',)]
    ops += [('mouse_scale', f32(1.0 / 3.0), 1e-3), ev(MOUSE_POSITION, 2147483647, -2147483648), ('query',)]
    ops += [('mouse_scale', 1.0, 1.0), ('mouse_offset', 0, 0), ('mouse_position', 33, 44), ('query',)]
    ops += [('hide_cursor',), ('query',), ('show_cursor',), ('query',), ('disable_cursor',), ('query',),
            ('mouse_position', 1, 2), ('enable_cursor',), ('query',)]
    out.append(script('mouse', ops, 641, 479))
    return out


def touch_scripts():
    ops = [ev(TOUCH_DOWN, 0), ev(TOUCH_DOWN, 3), ev(TOUCH_DOWN, 7), ev(TOUCH_POSITION, 0, 12, -4), ev(TOUCH_POSITION, 7, 300, 400),
           ('query',)] + frame(0, 0) + [('query',)]
    ops += [ev(TOUCH_UP, 3), ev(MOUSE_DOWN, 3), ('query',)] + frame(0, 0) + [('query',)]
    ops += [ev(TOUCH_UP, 0), ev(TOUCH_UP, 7), ev(TOUCH_POSITION, 0, 16777217, 5), ('query',)] + frame(0, 0) + [('query',)]
    return [script('touch', ops)]


def gamepad_scripts():
    ops = [('query',), ev(PAD_CONNECT, 0), ev(PAD_CONNECT, 3), ev(PAD_DOWN, 0, 0), ev(PAD_DOWN, 0, 31), ev(PAD_DOWN, 3, 15),
           ev(PAD_DOWN, 2, 1), ('query',)]
    ops += [ev(PAD_AXIS, 0, 0, 16384), ev(PAD_AXIS, 0, 1, -32768), ev(PAD_AXIS, 0, 4, -32768), ev(PAD_AXIS, 0, 5, 100),
            ev(PAD_AXIS, 3, 7, 2147483647), ev(PAD_AXIS, 3, 4, -40000), ev(PAD_AXIS, 2, 2, 5), ('query',)]
    ops += frame(0, 0) + [('query',), ev(PAD_UP, 0, 0), ev(PAD_DISCONNECT, 3), ('query',)] + frame(0, 0) + [('query',)]
    ops += [ev(PAD_CONNECT, 2), ev(PAD_AXIS, 0, 1, 1), ('query',)]
    return [script('gamepads', ops)]


def window_scripts():
    ops = [('query',), ev(WINDOW_MAXIMIZE), ev(WINDOW_MINIMIZE), ev(WINDOW_RESIZE, 100, 100), ev(EVENT_NONE, 5),
           ev(24, 1), ev(99, 1), ('query',), ev(SCREENSHOT), ('query',), ev(WINDOW_CLOSE), ('query',)]
    ops += frame(0, 0) + [('query',), ev(SET_FPS, 0)] + frame(0, 0) + [('query',)]
    return [script('window', ops, 8, 8)]


def timing_scripts():
    out = []
    # SetTargetFPS(30): waits until 1/30 s after the previous frame end.
    ops = [('target_fps', 30)]
    t = 1.0
    for update, draw in ((0.004, 0.006), (0.01, 0.02), (0.02, 0.02), (0.0, 0.0), (0.001, 0.0005)):
        begin, end = t + update, t + update + draw
        wait_end = t + 1.0 / 30.0 + 0.00025
        ops += frame(begin, end, wait_end) + [('query',), ('fps',)]
        t = wait_end if update + draw < 1.0 / 30.0 else end
    ops += [('target_fps', 0), ('target_fps', -5)] + frame(t + 0.01, t + 0.02) + [('query',), ('fps',)]
    ops += [ev(SET_FPS, 144)] + frame(t + 0.021, t + 0.022, t + 0.03) + [('query',), ('fps',)]
    out.append(script('timing-target', ops, start=1.0))
    # GetFPS's 30-sample average with irregular frames, and base-frame resets.
    ops = []
    t = 0.5
    steps = [0.016, 0.017, 0.0165, 0.033, 0.005, 0.1, 0.016, 0.016, 0.02, 0.012] * 4
    for k, step in enumerate(steps):
        ops += frame(t + step * 0.25, t + step) + [('fps',)]
        if k % 9 == 0:
            ops += [('fps',), ('query',)]
        t += step
    ops += [('base_frame', 0), ('fps',), ('clock', t + 1.0), ('fps',), ('base_frame', 7), ('fps',)]
    out.append(script('timing-fps', ops, start=0.5))
    # Large clocks and a frame time that is exactly zero.
    ops = frame(1e6, 1e6 + 0.25) + [('query',), ('fps',)] + frame(1e6 + 0.25, 1e6 + 0.25) + [('query',), ('fps',)]
    ops += frame(2e6, 2e6 + 1e-9) + [('query',), ('fps',)]
    out.append(script('timing-large', ops, start=1e6))
    return out


def pts(*xy):
    return [(float(xy[i]), float(xy[i + 1])) for i in range(0, len(xy), 2)]


def gesture(action, count, *xy):
    return ('gesture', action, count, pts(*xy))


def gesture_scripts():
    out = []
    # Tap, hold (UpdateGestures in PollInputEvents), double tap, drag, swipes.
    ops = [('clock', 1.0), gesture(1, 1, 100, 100), ('query',), ('clock', 1.05), gesture(0, 1, 100, 100), ('query',)]
    ops += frame(1.06, 1.07) + [('clock', 1.08), ('query',), ('clock', 1.2), gesture(1, 1, 100, 100), ('query',)]
    ops += frame(1.21, 1.22) + [('clock', 1.5), ('query',), ('clock', 1.6), gesture(2, 1, 130, 110), ('query',)]
    ops += [('clock', 1.65), gesture(2, 1, 160, 120), ('query',), ('clock', 1.9), gesture(0, 1, 170, 125), ('query',)]
    ops += frame(1.91, 1.92) + [('query',)]
    for k, (dx, dy) in enumerate(((50, 0), (0, -50), (-50, 0), (0, 50), (40, -40), (-1, 60), (30, 1))):
        base = 3.0 + k
        ops += [('clock', base), gesture(1, 1, 200, 200)] + frame(base + 0.01, base + 0.02)
        ops += [('clock', base + 0.1), gesture(0, 1, 200 + dx, 200 + dy), ('query',)]
        ops += frame(base + 0.11, base + 0.12) + [('query',)]
    # A hold, then a slow release (no swipe), a drag (timeout) and its release.
    ops += [('clock', 11.0), gesture(1, 1, 50, 50)] + frame(11.0, 11.01) + [('clock', 11.4), ('query',)]
    ops += [('clock', 11.45), gesture(2, 1, 52, 51), ('clock', 11.5), gesture(2, 1, 60, 70), ('query',)]
    ops += [('clock', 12.0), gesture(0, 1, 61, 71), ('query',)] + frame(12.01, 12.02) + [('query',)]
    out.append(script('gestures-touch', ops, 64, 64, start=1.0))
    # Pinch: two points down, moves outward, inward and tiny, two-point up,
    # three points, cancel, INPUT_GESTURE and SetGesturesEnabled.
    ops = [('clock', 2.0), gesture(1, 2, 100, 100, 200, 100), ('query',), ('clock', 2.1), gesture(2, 2, 90, 100, 210, 100), ('query',)]
    ops += [('clock', 2.2), gesture(2, 2, 120, 110, 180, 90), ('query',), ('clock', 2.3), gesture(2, 2, 120.001, 110, 180, 90.002), ('query',)]
    ops += [('clock', 2.6), ('query',)] + frame(2.61, 2.62) + [('clock', 2.7), ('query',)]
    ops += [('clock', 2.8), gesture(0, 2, 120, 110, 180, 90), ('query',), gesture(1, 3, 1, 2, 3, 4), ('query',), gesture(3, 1, 5, 5), ('query',)]
    ops += [ev(GESTURE, 64), ('query',)] + frame(2.9, 2.95) + [('query',), ev(GESTURE, 3), ('gestures_enabled', 1), ('query',)]
    ops += [ev(GESTURE, 2), ('query',)] + frame(3.0, 3.01) + [('clock', 3.5), ('query',), ('gestures_enabled', 1023), ('query',)]
    ops += [ev(GESTURE, 0x80000004), ('query',)]
    # UpdateGestures called directly: a tap becomes a hold timed at the call.
    ops += [('clock', 4.0), gesture(1, 1, 7, 7), ('clock', 4.25), ('update_gestures',), ('clock', 4.5), ('query',), ('update_gestures',), ('query',)]
    out.append(script('gestures-pinch', ops, 64, 64, start=2.0))
    # Every clock zero (the macOS memory platform's own GetTime): taps become
    # double taps, a release with a zero time step divides by zero.
    ops = [gesture(1, 1, 10, 10), gesture(0, 1, 10, 10), gesture(1, 1, 10, 10), ('query',), gesture(0, 1, 10, 10), ('query',),
           gesture(1, 1, 20, 20), gesture(0, 1, 40, 20), ('query',)] + frame(0, 0) + [('query',)]
    ops += [gesture(1, 1, 30, 30), gesture(0, 1, 30, 30), ('query',)] + frame(0, 0) + [('query',)]
    out.append(script('gestures-zero-clock', ops, 64, 64))
    return out


def recording_scripts():
    out = []
    ops = [ev(KEY_DOWN, 65), ev(KEY_DOWN, 300), ev(MOUSE_DOWN, 2), ev(MOUSE_POSITION, 7, 9), ev(MOUSE_WHEEL, 0, -2), ev(TOUCH_DOWN, 1),
           ev(TOUCH_POSITION, 1, 30, 40), ev(PAD_CONNECT, 1), ev(PAD_DOWN, 1, 4), ev(PAD_DOWN, 2, 6), ev(PAD_AXIS, 1, 0, -100),
           ev(PAD_AXIS, 1, 5, -32768), ev(PAD_AXIS, 1, 4, 3), ev(GESTURE, 16)]
    ops += [('list_new',), ('base_frame', 5), ('record_start',), ev(KEY_DOWN, 66)] + frame(0, 0)
    ops += [('list',), ev(KEY_UP, 65)] + frame(0, 0) + [('list',), ('record_stop',), ev(KEY_UP, 300), ev(TOUCH_UP, 1)]
    ops += frame(0, 0) + [('record_start',), ('mouse_position', 8, 9)] + frame(0, 0) + [('record_stop',), ('list',), ('export', True), ('query',)]
    out.append(script('recording', ops))
    # Capacity: every key held fills the 16384 events in 32 frames.
    ops = [('keys_down', 0, 512), ev(MOUSE_DOWN, 0), ('list_new',), ('record_start',)]
    for _ in range(33):
        ops += frame(0, 0)
    ops += [('list',), ('record_stop',)] + frame(0, 0) + [('list',)]
    out.append(script('recording-capacity', ops))
    return out


EXPORTED = (b'#\n# comment\n#\n\nc 4\ne 0 2 65 0 0 0 // Event: INPUT_KEY_DOWN\ne 3 7 -12 40 0 0 // Event: INPUT_MOUSE_POSITION\n'
            b'e 4 13 1 0 -100 0 // Event: INPUT_GAMEPAD_AXIS_MOTION\ne 9 23 30 0 0 0 // Event: ACTION_SETTARGETFPS\n')


def load_texts():
    """(name, file bytes, whether raylib's reader is defined on it, whether its events all have a name)."""
    long_line = b'e 1 2 3 4 5 6 ' + b'x' * 250 + b'\n'
    return [
        ('exported', EXPORTED, True, True),
        ('hex-octal-count', b'c 0x10\nc 017\nc -3\ne 1 2\ne\ne +5 -6 7 8 9 10 11\n', True, False),
        ('partial-fields', b'e 7 x 1\ne 8 9 -\ne 1 2 3 4 5 6\n\n  e 1 1\ne-1 -2 -3 -4 -5 -6 desc\n', True, False),
        ('signed-fields', b'e-1 +3 -3 -4 -5 -6 desc\ne 2147483647 23 0 0 0 0\n', True, True),
        ('no-final-newline', b'e 1 2 3 4 5 6\ne 2 3 4 5 6 7', True, True),
        ('crlf-tabs', b'e\t1\t2\t3\t4\t5\t6\t// d\r\ne 2147483647 -2147483648 0 0 0 0\r\n', True, False),
        ('crlf-named', b'e\t1\t2\t3\t4\t5\t6\t// d\r\ne 7 22 -2147483648 2147483647 0 0\r\n', True, True),
        ('nul-and-long', b'e 1 2\x00 3\ne 9 9 9 9 9 9 ' + b'y' * 60 + b'\n' + b'e 1 2 3 4 5 6' + b' ' * 250 + b'\n', True, True),
        ('long-line-split', b'c 1\n' + b'e 5 5 5 5 5 5\n' + b'z' * 254 + b'e 2 2 2 2 2 2\n' + b'x' * 255 + b'e 3 3 3 3 3 3\n', True, True),
        ('type-24', b'e 1 24 0 0 0 0\n', True, False),
        ('empty', b'', True, True),
        ('description-overflow', long_line, False, False),
        ('int-overflow', b'e 2147483648 1 1 1 1 1\n', False, False),
        ('int-underflow', b'e 1 -2147483649 1 1 1 1\n', False, False),
        ('count-overflow', b'c 0x80000000\n', False, False),
        ('hex-without-digits', b'c 0x\ne 1 1 1 1 1 1\n', False, False),
        ('too-many-events', b'e 1\n' * 16385, False, False),
    ]


def load_scripts():
    out = []
    ops = []
    for name, text, defined, named in load_texts():
        ops.append(('load', name, text, defined))
        if defined:
            ops.append(('export', named))
    out.append(script('load-export', ops))
    ops = [('load', 'replay', EXPORTED, True), ('list',)]
    for e in (ev(KEY_DOWN, 65), ev(MOUSE_POSITION, -12, 40), ev(PAD_CONNECT, 1), ev(PAD_AXIS, 1, 0, -100), ev(SET_FPS, 30)):
        ops.append(e)
    ops += [('query',)] + frame(0.0, 0.01, 0.04) + [('query',)]
    out.append(script('load-replay', ops))
    return out


def contract_scripts():
    """Each script's last operation is undefined in raylib; Jonlib must answer null there."""
    rows = [
        ('key-down-512', [ev(KEY_DOWN, 512)]), ('key-up-negative', [ev(KEY_UP, -1)]),
        ('mouse-button-8', [ev(MOUSE_DOWN, 8)]), ('gamepad-connect-4', [ev(PAD_CONNECT, 4)]),
        ('gamepad-connect-negative', [ev(PAD_DISCONNECT, -1)]), ('gamepad-button-32', [ev(PAD_DOWN, 0, 32)]),
        ('gamepad-axis-8', [ev(PAD_AXIS, 1, 8, 0)]), ('touch-down-8', [ev(TOUCH_DOWN, 8)]),
        ('touch-position-8', [ev(TOUCH_POSITION, 8, 0, 0)]),
        ('gamepad-available-negative', [('query_pad_available', -1)]),
        ('gamepad-button-negative', [ev(PAD_CONNECT, 0), ('query_pad_button', 0, -1)]),
        ('gamepad-axis-count-4', [('query_axis_count', 4)]),
        ('gamepad-axis-negative', [ev(PAD_CONNECT, 2), ('query_axis', 2, -1)]),
        ('touch-position-negative', [('query_touch_position', -1)]),
        ('mouse-x-overflow', [('mouse_scale', 1e10, 1.0), ev(MOUSE_POSITION, 1, 1), ('query_mouse_x',)]),
        ('touch-x-overflow', [ev(TOUCH_POSITION, 0, 2147483647, 0), ('query_touch_x',)]),
        ('fps-before-sample', frame(0.0, 0.001) + [('clock', 0.002), ('fps',)]),
        ('record-int-position', [ev(MOUSE_POSITION, 2147483647, 0), ('list_new',), ('record_start',)] + frame(0, 0)),
        ('record-without-list', [('record_start',)]),
        ('wait-not-reached', [('target_fps', 10)] + frame(0.0, 0.01, 0.05)),
    ]
    return [script(name, ops, contract=len(ops) - 1) for name, ops in rows]


def scripts():
    return (keyboard_scripts() + mouse_scripts() + touch_scripts() + gamepad_scripts() + window_scripts()
            + timing_scripts() + gesture_scripts() + recording_scripts() + load_scripts() + contract_scripts())


# -----------------------------------------------------------------------------
# Native harness

C_PRELUDE = r'''#define _POSIX_C_SOURCE 200809L
#include "raylib.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/stat.h>

typedef struct { int touchAction; int pointCount; int pointId[8]; Vector2 position[8]; } GestureEvent;
void ProcessGestureEvent(GestureEvent event);
void UpdateGestures(void);

static double probe_clock = 0.0, probe_after = 0.0;
static int probe_slept = 0;
static char probe_sleep[64];
double JonlibProbeTime(void) { return probe_clock; }
int JonlibProbeUsleep(unsigned int us) { probe_slept = 1; snprintf(probe_sleep, 64, "%u", us); probe_clock = probe_after; return 0; }
int JonlibProbeNanosleep(const struct timespec *req, struct timespec *rem)
{ probe_slept = 1; snprintf(probe_sleep, 64, "%lld.%ld", (long long)req->tv_sec, (long)req->tv_nsec); probe_clock = probe_after; (void)rem; return 0; }

static double dbl(unsigned long long b) { double d; memcpy(&d, &b, 8); return d; }
static float flt(unsigned b) { float f; memcpy(&f, &b, 4); return f; }
static unsigned fb(float f) { unsigned b; memcpy(&b, &f, 4); return b; }
static int row_started = 0;
static void row(void) { printf("\n@"); row_started = 1; }
static int fits(float v) { return v >= -2147483648.0f && v < 2147483648.0f; }
static void vec(Vector2 v) { printf("%u,%u", fb(v.x), fb(v.y)); }

static AutomationEventList list;
static int list_set = 0;

static void dump_list(const char *tag, AutomationEventList l)
{
    unsigned sum = 0;
    for (unsigned i = 0; i < l.count; i++)
    {
        AutomationEvent e = l.events[i];
        sum = sum*31u + (e.frame*3u + e.type*5u + (unsigned)e.params[0]*7u + (unsigned)e.params[1]*11u + (unsigned)e.params[2]*13u + (unsigned)e.params[3]*17u);
    }
    row(); printf("%s %u %u %u", tag, l.count, l.capacity, sum);
    if (l.count <= 40) for (unsigned i = 0; i < l.count; i++)
    {
        AutomationEvent e = l.events[i];
        printf(i ? ";" : " "); printf("%d,%d,%d,%d,%d,%d", (int)e.frame, (int)e.type, e.params[0], e.params[1], e.params[2], e.params[3]);
    }
}

static void export_list(void)
{
    row(); printf("X ");
    remove("export.rae");
    if (!ExportAutomationEventList(list, "export.rae")) { printf("failed"); return; }
    FILE *f = fopen("export.rae", "rb"); int c;
    while ((c = fgetc(f)) != EOF) printf("%02x", c);
    fclose(f);
}

static void load_list(const unsigned char *bytes, size_t n)
{
    FILE *f = fopen("load.rae", "wb"); fwrite(bytes, 1, n, f); fclose(f);
    if (list_set) UnloadAutomationEventList(list);
    list = LoadAutomationEventList("load.rae"); list_set = 1;
    SetAutomationEventList(&list);
    dump_list("P", list);
}

static int screenshots(void)
{
    int n = 0; struct stat st; char name[64];
    for (;;) { snprintf(name, 64, "screenshot%03i.png", n); if (stat(name, &st) != 0) return n; n++; }
}

static const int keys[] = { KEYS };
static const int buttons[] = { BUTTONS };
static const int pad_buttons[] = { PAD_BUTTONS };
static const unsigned gesture_flags[] = { GESTURE_FLAGS };
#define COUNT(a) ((int)(sizeof(a)/sizeof((a)[0])))

static void query(void)
{
    row(); printf("Q");
    for (int i = 0; i < COUNT(keys); i++) { int k = keys[i];
        printf(" k%d:%d%d%d%d%d", k, IsKeyPressed(k), IsKeyPressedRepeat(k), IsKeyDown(k), IsKeyReleased(k), IsKeyUp(k)); }
    for (int i = 0; i < COUNT(buttons); i++) { int b = buttons[i];
        printf(" m%d:%d%d%d%d", b, IsMouseButtonPressed(b), IsMouseButtonDown(b), IsMouseButtonReleased(b), IsMouseButtonUp(b)); }
    Vector2 m = GetMousePosition();
    printf(" mx:"); if (fits(m.x)) printf("%d", GetMouseX()); else printf("null");
    printf(" my:"); if (fits(m.y)) printf("%d", GetMouseY()); else printf("null");
    printf(" mp:"); vec(m); printf(" md:"); vec(GetMouseDelta()); printf(" mw:%u", fb(GetMouseWheelMove())); printf(" mv:"); vec(GetMouseWheelMoveV());
    printf(" cur:%d%d", IsCursorHidden(), IsCursorOnScreen());
    Vector2 t = GetTouchPosition(0);
    printf(" tx:"); if (fits(t.x)) printf("%d", GetTouchX()); else printf("null");
    printf(" ty:"); if (fits(t.y)) printf("%d", GetTouchY()); else printf("null");
    for (int i = 0; i <= 8; i++) { printf(" tp%d:", i); vec(GetTouchPosition(i)); }
    for (int i = 0; i <= 9; i++) printf(" ti%d:%d", i, GetTouchPointId(i));
    printf(" tc:%d", GetTouchPointCount());
    for (int g = 0; g <= 4; g++)
    {
        printf(" ga%d:%d", g, IsGamepadAvailable(g));
        for (int i = 0; i < COUNT(pad_buttons); i++) { int b = pad_buttons[i];
            printf(" gb%d.%d:%d%d%d%d", g, b, IsGamepadButtonPressed(g, b), IsGamepadButtonDown(g, b), IsGamepadButtonReleased(g, b), IsGamepadButtonUp(g, b)); }
        for (int a = 0; a <= 8; a++) printf(" gx%d.%d:%u", g, a, fb(GetGamepadAxisMovement(g, a)));
    }
    for (int g = 0; g <= 3; g++) printf(" gn%d:%d gname%d:%d", g, GetGamepadAxisCount(g), g, (int)strlen(GetGamepadName(g)));
    printf(" gl:%d", GetGamepadButtonPressed());
    printf(" gd:%d gi:", GetGestureDetected());
    for (int i = 0; i < COUNT(gesture_flags); i++) printf("%d", IsGestureDetected(gesture_flags[i]));
    printf(" gh:%u gv:", fb(GetGestureHoldDuration())); vec(GetGestureDragVector());
    printf(" gg:%u pv:", fb(GetGestureDragAngle())); vec(GetGesturePinchVector()); printf(" pa:%u", fb(GetGesturePinchAngle()));
    printf(" close:%d ft:%u shots:%d", WindowShouldClose(), fb(GetFrameTime()), screenshots());
}

static void play(unsigned frame, unsigned type, int p0, int p1, int p2, int p3)
{
    AutomationEvent e = { frame, type, { p0, p1, p2, p3 } };
    PlayAutomationEvent(e);
}

static void gesture(int action, int count, float x0, float y0, float x1, float y1)
{
    GestureEvent e = { 0 };
    e.touchAction = action; e.pointCount = count;
    e.position[0] = (Vector2){ x0, y0 }; e.position[1] = (Vector2){ x1, y1 };
    ProcessGestureEvent(e);
}

static void end_frame(double after)
{
    probe_slept = 0; probe_after = after;
    EndDrawing();
    row(); printf("W:%s", probe_slept ? probe_sleep : "-");
    probe_clock = after;
}
'''


def c_double(value):
    return f'dbl({dbits(value)}ull)'


def c_float(value):
    return f'flt({fbits(value)}u)'


def c_op(op):
    name, a = op[0], op[1:]
    if name == 'clock':
        return f'probe_clock = {c_double(a[0])};'
    if name == 'play':
        kind, p0, p1, p2, p3, frm = a
        return f'play({word(frm)}u, {word(kind)}u, {s32(p0)}, {s32(p1)}, {s32(p2)}, {s32(p3)});'
    if name == 'begin':
        return 'BeginDrawing();'
    if name == 'end':
        return f'end_frame({c_double(a[0])});'
    if name == 'gesture':
        action, count, points = a
        (x0, y0), (x1, y1) = (points + [(0.0, 0.0), (0.0, 0.0)])[:2]
        return f'gesture({action}, {count}, {c_float(x0)}, {c_float(y0)}, {c_float(x1)}, {c_float(y1)});'
    simple = {
        'query': 'query();', 'poll': 'PollInputEvents();', 'update_gestures': 'UpdateGestures();',
        'hide_cursor': 'HideCursor();', 'show_cursor': 'ShowCursor();', 'enable_cursor': 'EnableCursor();',
        'disable_cursor': 'DisableCursor();', 'record_start': 'StartAutomationEventRecording();',
        'record_stop': 'StopAutomationEventRecording();',
        'list': 'dump_list("L", list);', 'fps': 'row(); printf("F %d", GetFPS());',
        'list_new': 'if (list_set) UnloadAutomationEventList(list); list = LoadAutomationEventList(NULL); list_set = 1; SetAutomationEventList(&list);',
        'keys': 'row(); printf("K"); for (int i = 0; i < 18; i++) printf(" %d", GetKeyPressed());',
        'chars': 'row(); printf("C"); for (int i = 0; i < 3; i++) printf(" %d", GetCharPressed());',
    }
    if name in simple:
        return simple[name]
    if name == 'export':
        return 'export_list();' if a[0] else 'row(); printf("X null");'
    if name == 'keys_down':
        return f'for (int k = {a[0]}; k < {a[0] + a[1]}; k++) play(0, {KEY_DOWN}, k, 0, 0, 0);'
    if name == 'mouse_position':
        return f'SetMousePosition({a[0]}, {a[1]});'
    if name == 'mouse_offset':
        return f'SetMouseOffset({a[0]}, {a[1]});'
    if name == 'mouse_scale':
        return f'SetMouseScale({c_float(a[0])}, {c_float(a[1])});'
    if name == 'exit_key':
        return f'SetExitKey({a[0]});'
    if name == 'gestures_enabled':
        return f'SetGesturesEnabled({word(a[0])}u);'
    if name == 'target_fps':
        return f'SetTargetFPS({a[0]});'
    if name == 'base_frame':
        return f'SetAutomationEventBaseFrame({a[0]});'
    if name == 'load':
        _, text, defined = a
        if not defined:
            return 'row(); printf("P null");'
        data = ','.join(str(b) for b in text) or '0'
        return f'{{ static const unsigned char data[] = {{ {data} }}; load_list(data, {len(text)}); }}'
    raise ValueError(f'no native form for {name}')


def c_program(items):
    lines = [C_PRELUDE.replace('KEYS', ', '.join(map(str, KEYS))).replace('PAD_BUTTONS', ', '.join(map(str, PAD_BUTTONS)))
             .replace('BUTTONS', ', '.join(map(str, BUTTONS))).replace('GESTURE_FLAGS', ', '.join(f'{f}u' for f in GESTURE_FLAGS)),
             'int main(int argc, char **argv)', '{', '    if (argc != 3 || chdir(argv[2]) != 0) return 2;',
             '    if (!freopen("/dev/null", "r", stdin)) return 3;', '    SetTraceLogLevel(LOG_NONE);', '    switch (atoi(argv[1]))', '    {']
    for index, item in enumerate(items):
        ops = item['ops'] if item['contract'] is None else item['ops'][:item['contract']]
        lines.append(f'    case {index}:')
        lines.append(f'        probe_clock = {c_double(item["start"])}; InitWindow({item["width"]}, {item["height"]}, "");')
        lines += [f'        {c_op(op)}' for op in ops]
        lines.append('        CloseWindow(); break;')
    lines += ['    default: return 4;', '    }', '    printf("\\n");', '    return 0;', '}', '']
    return '\n'.join(lines)


# -----------------------------------------------------------------------------
# Bend candidate

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M

type Run is Data:
  Live{core: J.Core, out: String}
  Dead{out: String}

def f64(+high: U32, +low: U32) -> M.Float64:
  M.Float64{high, low}

def fl(+bits: U32) -> F32:
  U32{b} = bits
  F32{b}

def int(+w: U32) -> String:
  Bool.pick(String, (w >= 2147483648 : U32), "-" ++ U32.show((0 - w : U32)), U32.show(w))

def bits(+x: F32) -> String:
  U32.show(F32.bits(x))

def bit(b: Bool) -> String:
  match b:
    case True{}: "1"
    case False{}: "0"

def vec(+v: M.Vector2) -> String:
  M.Vector2{x, y} = v
  bits(x) ++ "," ++ bits(y)

def mint(m: Maybe<U32>) -> String:
  match m:
    case None{}: "null"
    case Some{v}: int(v)

def mbit(m: Maybe<Bool>) -> String:
  match m:
    case None{}: "n"
    case Some{v}: bit(v)

def mf32(m: Maybe<F32>) -> String:
  match m:
    case None{}: "null"
    case Some{v}: bits(v)

def mvec(m: Maybe<M.Vector2>) -> String:
  match m:
    case None{}: "null"
    case Some{v}: vec(v)

def mlen(m: Maybe<String>) -> String:
  match m:
    case None{}: "null"
    case Some{s}: U32.show(U32.from_nat(String.length(s)))

def add(+out: String, +row: String) -> String:
  Bool.pick(String, String.is_empty(out), row, out ++ " | " ++ row)

def start(core: Maybe<J.Core>) -> Run:
  match core:
    case None{}: Dead{"null"}
    case Some{c}: Live{c, ""}

def step(+out: String, next: Maybe<J.Core>) -> Run:
  match next:
    case None{}: Dead{add(out, "null")}
    case Some{c}: Live{c, out}

def finish(run: Run) -> String:
  match run:
    case Live{_, out}: out
    case Dead{out}: out

# -- queries

def q.key(+c: J.Core, +k: U32) -> String:
  " k" ++ int(k) ++ ":" ++ bit(J.Input.is_key_pressed(c, k)) ++ bit(J.Input.is_key_pressed_repeat(c, k)) ++ bit(J.Input.is_key_down(c, k))
    ++ bit(J.Input.is_key_released(c, k)) ++ bit(J.Input.is_key_up(c, k))

def q.keys(+c: J.Core, keys: +List<U32>) -> String:
  match keys:
    case Nil{}: ""
    case Con{+k, rest}: q.key(c, k) ++ q.keys(c, rest)

def q.button(+c: J.Core, +b: U32) -> String:
  " m" ++ int(b) ++ ":" ++ bit(J.Input.is_mouse_button_pressed(c, b)) ++ bit(J.Input.is_mouse_button_down(c, b))
    ++ bit(J.Input.is_mouse_button_released(c, b)) ++ bit(J.Input.is_mouse_button_up(c, b))

def q.buttons(+c: J.Core, buttons: +List<U32>) -> String:
  match buttons:
    case Nil{}: ""
    case Con{+b, rest}: q.button(c, b) ++ q.buttons(c, rest)

def q.mouse(+c: J.Core) -> String:
  " mx:" ++ mint(J.Input.get_mouse_x(c)) ++ " my:" ++ mint(J.Input.get_mouse_y(c)) ++ " mp:" ++ vec(J.Input.get_mouse_position(c))
    ++ " md:" ++ vec(J.Input.get_mouse_delta(c)) ++ " mw:" ++ bits(J.Input.get_mouse_wheel_move(c)) ++ " mv:" ++ vec(J.Input.get_mouse_wheel_move_v(c))
    ++ " cur:" ++ bit(J.Input.is_cursor_hidden(c)) ++ bit(J.Input.is_cursor_on_screen(c))

def q.touch_positions(n: Nat, +c: J.Core, +i: U32) -> String:
  match n:
    case 0n: ""
    case 1n+k: " tp" ++ int(i) ++ ":" ++ mvec(J.Input.get_touch_position(c, i)) ++ q.touch_positions(k, c, (i + 1 : U32))

def q.touch_ids(n: Nat, +c: J.Core, +i: U32) -> String:
  match n:
    case 0n: ""
    case 1n+k: " ti" ++ int(i) ++ ":" ++ mint(J.Input.get_touch_point_id(c, i)) ++ q.touch_ids(k, c, (i + 1 : U32))

def q.touch(+c: J.Core) -> String:
  " tx:" ++ mint(J.Input.get_touch_x(c)) ++ " ty:" ++ mint(J.Input.get_touch_y(c)) ++ q.touch_positions(9n, c, 0) ++ q.touch_ids(10n, c, 0)
    ++ " tc:" ++ int(J.Input.get_touch_point_count(c))

def q.pad_button(+c: J.Core, +g: U32, +b: U32) -> String:
  " gb" ++ int(g) ++ "." ++ int(b) ++ ":" ++ mbit(J.Input.is_gamepad_button_pressed(c, g, b)) ++ mbit(J.Input.is_gamepad_button_down(c, g, b))
    ++ mbit(J.Input.is_gamepad_button_released(c, g, b)) ++ mbit(J.Input.is_gamepad_button_up(c, g, b))

def q.pad_buttons(+c: J.Core, +g: U32, buttons: +List<U32>) -> String:
  match buttons:
    case Nil{}: ""
    case Con{+b, rest}: q.pad_button(c, g, b) ++ q.pad_buttons(c, g, rest)

def q.axes(n: Nat, +c: J.Core, +g: U32, +a: U32) -> String:
  match n:
    case 0n: ""
    case 1n+k: " gx" ++ int(g) ++ "." ++ int(a) ++ ":" ++ mf32(J.Input.get_gamepad_axis_movement(c, g, a)) ++ q.axes(k, c, g, (a + 1 : U32))

def q.pads(n: Nat, +c: J.Core, +g: U32, +buttons: +List<U32>) -> String:
  match n:
    case 0n: ""
    case 1n+k: " ga" ++ int(g) ++ ":" ++ mbit(J.Input.is_gamepad_available(c, g)) ++ q.pad_buttons(c, g, buttons) ++ q.axes(9n, c, g, 0)
      ++ q.pads(k, c, (g + 1 : U32), buttons)

def q.counts(n: Nat, +c: J.Core, +g: U32) -> String:
  match n:
    case 0n: ""
    case 1n+k: " gn" ++ int(g) ++ ":" ++ mint(J.Input.get_gamepad_axis_count(c, g)) ++ " gname" ++ int(g) ++ ":" ++ mlen(J.Input.get_gamepad_name(g))
      ++ q.counts(k, c, (g + 1 : U32))

def q.flags(+c: J.Core, flags: +List<U32>) -> String:
  match flags:
    case Nil{}: ""
    case Con{+f, rest}: bit(J.Gestures.is_detected(c, f)) ++ q.flags(c, rest)

def q.gestures(+c: J.Core, +now: M.Float64) -> String:
  " gd:" ++ int(J.Gestures.get_detected(c)) ++ " gi:" ++ q.flags(c, GESTURE_FLAGS) ++ " gh:" ++ mf32(J.Gestures.get_hold_duration(c, now))
    ++ " gv:" ++ vec(J.Gestures.get_drag_vector(c)) ++ " gg:" ++ bits(J.Gestures.get_drag_angle(c)) ++ " pv:" ++ vec(J.Gestures.get_pinch_vector(c))
    ++ " pa:" ++ bits(J.Gestures.get_pinch_angle(c))

def q.row(+c: J.Core, +now: M.Float64) -> String:
  "Q" ++ q.keys(c, KEYS) ++ q.buttons(c, BUTTONS) ++ q.mouse(c) ++ q.touch(c) ++ q.pads(5n, c, 0, PAD_BUTTONS) ++ q.counts(4n, c, 0)
    ++ " gl:" ++ int(J.Input.get_gamepad_button_pressed(c)) ++ q.gestures(c, now) ++ " close:" ++ bit(J.Core.window_should_close(c))
    ++ " ft:" ++ bits(J.Core.get_frame_time(c)) ++ " shots:" ++ int(J.Core.screenshot_count(c))

def op.query(run: Run, +now: M.Float64) -> Run:
  match run:
    case Dead{out}: Dead{out}
    case Live{+core, +out}: Live{core, add(out, q.row(core, now))}

# -- operations

def op.play(run: Run, +e: J.AutomationEvent) -> Run:
  match run:
    case Dead{out}: Dead{out}
    case Live{+core, +out}: step(out, J.Core.play_automation_event(core, e))

def op.keys_down(n: Nat, +key: U32, run: Run) -> Run:
  match n:
    case 0n: run
    case 1n+k: op.keys_down(k, (key + 1 : U32), op.play(run, J.AutomationEvent{0, 2, key, 0, 0, 0}))

def op.begin(run: Run, +now: M.Float64) -> Run:
  match run:
    case Dead{out}: Dead{out}
    case Live{+core, +out}: step(out, J.Core.begin_drawing(core, now))

def wait.row(m: Maybe<M.Float64>) -> String:
  match m:
    case None{}: "W:null"
    case Some{M.Float64{high, low}}: "W:" ++ U32.show(high) ++ "," ++ U32.show(low)

def op.end.done(+out: String, +row: String, next: Maybe<J.Core>) -> Run:
  match next:
    case None{}: Dead{add(out, "null")}
    case Some{c}: Live{c, add(out, row)}

def op.end(run: Run, +now: M.Float64, +after: M.Float64) -> Run:
  match run:
    case Dead{out}: Dead{out}
    case Live{+core, +out}: op.end.done(out, wait.row(J.Core.frame_wait(core, now)), J.Core.end_drawing(core, now, after))

def op.poll(run: Run, +now: M.Float64) -> Run:
  match run:
    case Dead{out}: Dead{out}
    case Live{+core, +out}: Live{J.Core.poll_input_events(core, now), out}

def op.update(run: Run, +now: M.Float64) -> Run:
  match run:
    case Dead{out}: Dead{out}
    case Live{+core, +out}: Live{J.Gestures.update(core, now), out}

def op.gesture(+libm: M.Libm, run: Run, +e: J.GestureEvent, +now: M.Float64) -> Run:
  match run:
    case Dead{out}: Dead{out}
    case Live{+core, +out}: step(out, J.Gestures.process_event_for(libm, core, e, now))

def op.setter(+kind: U32, +core: J.Core, +a: U32, +b: U32) -> J.Core:
  match kind:
    case 0: J.Input.set_mouse_position(core, a, b)
    case 1: J.Input.set_mouse_offset(core, a, b)
    case 2: J.Input.set_mouse_scale(core, fl(a), fl(b))
    case 3: J.Input.set_exit_key(core, a)
    case 4: J.Gestures.set_enabled(core, a)
    case 5: J.Core.set_target_fps(core, a)
    case 6: J.Input.hide_cursor(core)
    case 7: J.Input.show_cursor(core)
    case 8: J.Input.enable_cursor(core)
    case 9: J.Input.disable_cursor(core)
    case 10: J.Core.stop_automation_event_recording(core)
    case 11: J.Core.set_automation_event_base_frame(core, a)
    case _: J.Core.set_automation_event_list(core, J.AutomationEventList.new())

def op.set(run: Run, +kind: U32, +a: U32, +b: U32) -> Run:
  match run:
    case Dead{out}: Dead{out}
    case Live{+core, +out}: Live{op.setter(kind, core, a, b), out}

def op.record_start(run: Run) -> Run:
  match run:
    case Dead{out}: Dead{out}
    case Live{+core, +out}: step(out, J.Core.start_automation_event_recording(core))

def pops.add(+acc: String, popped: J.Core & U32) -> J.Core & String:
  (core, value) = popped
  (core, acc ++ " " ++ int(value))

def pops.one(+chars: Bool, state: J.Core & String) -> J.Core & String:
  (+core, +acc) = state
  pops.add(acc, Bool.pick((J.Core & U32), chars, J.Input.get_char_pressed(core), J.Input.get_key_pressed(core)))

def pops(n: Nat, +chars: Bool, state: J.Core & String) -> J.Core & String:
  match n:
    case 0n: state
    case 1n+k: pops(k, chars, pops.one(chars, state))

def op.pops.done(+out: String, result: J.Core & String) -> Run:
  (core, row) = result
  Live{core, add(out, row)}

def op.pops(run: Run, +chars: Bool) -> Run:
  match run:
    case Dead{out}: Dead{out}
    case Live{+core, +out}: op.pops.done(out, pops(Bool.pick(Nat, chars, 3n, 18n), chars, (core, Bool.pick(String, chars, "C", "K"))))

def op.fps.pair(+out: String, pair: J.Core & U32) -> Run:
  (core, fps) = pair
  Live{core, add(out, "F " ++ int(fps))}

def op.fps.done(+out: String, result: Maybe<(J.Core & U32)>) -> Run:
  match result:
    case None{}: Dead{add(out, "null")}
    case Some{pair}: op.fps.pair(out, pair)

def op.fps(run: Run, +now: M.Float64) -> Run:
  match run:
    case Dead{out}: Dead{out}
    case Live{+core, +out}: op.fps.done(out, J.Core.get_fps(core, now))

# -- automation lists

def ev.check(events: +List<J.AutomationEvent>, +acc: U32) -> U32:
  match events:
    case Nil{}: acc
    case Con{J.AutomationEvent{f, t, p0, p1, p2, p3}, rest}:
      ev.check(rest, (acc * 31 + (f * 3 + t * 5 + p0 * 7 + p1 * 11 + p2 * 13 + p3 * 17) : U32))

def ev.text(events: +List<J.AutomationEvent>, +first: Bool) -> String:
  match events:
    case Nil{}: ""
    case Con{J.AutomationEvent{f, t, p0, p1, p2, p3}, rest}:
      Bool.pick(String, first, " ", ";") ++ int(f) ++ "," ++ int(t) ++ "," ++ int(p0) ++ "," ++ int(p1) ++ "," ++ int(p2) ++ "," ++ int(p3)
        ++ ev.text(rest, False{})

def list.events(short: Bool, +events: +List<J.AutomationEvent>) -> String:
  match short:
    case False{}: ""
    case True{}: ev.text(events, True{})

def list.row(+tag: String, +list: J.AutomationEventList) -> String:
  J.AutomationEventList{capacity, +count, +events} = list
  tag ++ " " ++ U32.show(count) ++ " " ++ U32.show(capacity) ++ " " ++ U32.show(ev.check(events, 0)) ++ list.events((count <= 40 : U32), events)

def list.maybe(+tag: String, list: Maybe<J.AutomationEventList>) -> String:
  match list:
    case None{}: tag ++ " none"
    case Some{l}: list.row(tag, l)

def op.list(run: Run) -> Run:
  match run:
    case Dead{out}: Dead{out}
    case Live{+core, +out}: Live{core, add(out, list.maybe("L", J.Core.automation_event_list(core)))}

def hex.digit(+d: U32) -> Char:
  Chr{Bool.pick(U32, (d < 10 : U32), (d + 48 : U32), (d + 87 : U32))}

def hex(text: String) -> String:
  match text:
    case SNil{}: ""
    case SCon{c, rest}:
      +code = Char.to_u32(c)
      SCon{hex.digit(((code >> 4n) .&. 15 : U32)), SCon{hex.digit((code .&. 15 : U32)), hex(rest)}}

def export.row(text: Maybe<String>) -> String:
  match text:
    case None{}: "X null"
    case Some{t}: "X " ++ hex(t)

def export.list(list: Maybe<J.AutomationEventList>) -> Maybe<String>:
  match list:
    case None{}: None{}
    case Some{l}: J.AutomationEventList.export_text(l)

def op.export(run: Run) -> Run:
  match run:
    case Dead{out}: Dead{out}
    case Live{+core, +out}: Live{core, add(out, export.row(export.list(J.Core.automation_event_list(core))))}

def op.load.done(+core: J.Core, +out: String, list: Maybe<J.AutomationEventList>) -> Run:
  match list:
    case None{}: Live{core, add(out, "P null")}
    case Some{+l}: Live{J.Core.set_automation_event_list(core, l), add(out, list.row("P", l))}

def op.load(run: Run, +bytes: +List<U32>) -> Run:
  match run:
    case Dead{out}: Dead{out}
    case Live{+core, +out}: op.load.done(core, out, J.AutomationEventList.parse(bytes))

# -- contract queries (their result decides the run)

def op.maybe(+core: J.Core, +out: String, +row: String) -> Run:
  Bool.pick(Run, String.contains(row, "null") || String.contains(row, ":n"), Dead{add(out, "null")}, Live{core, add(out, row)})

def op.contract.row(+kind: U32, +c: J.Core, +a: U32, +b: U32) -> String:
  match kind:
    case 0: "pad:" ++ mbit(J.Input.is_gamepad_available(c, a))
    case 1: "button:" ++ mbit(J.Input.is_gamepad_button_down(c, a, b))
    case 2: "count:" ++ mint(J.Input.get_gamepad_axis_count(c, a))
    case 3: "axis:" ++ mf32(J.Input.get_gamepad_axis_movement(c, a, b))
    case 4: "touch:" ++ mvec(J.Input.get_touch_position(c, a))
    case 5: "mx:" ++ mint(J.Input.get_mouse_x(c))
    case _: "tx:" ++ mint(J.Input.get_touch_x(c))

def op.contract(run: Run, +kind: U32, +a: U32, +b: U32) -> Run:
  match run:
    case Dead{out}: Dead{out}
    case Live{+core, +out}: op.maybe(core, out, op.contract.row(kind, core, a, b))
'''

def b_double(value):
    bits = dbits(value)
    return f'f64({bits >> 32}, {bits & 0xFFFFFFFF})'


def b_list(values):
    return '[' + ', '.join(str(word(v)) for v in values) + ']'


def b_op(op, run, clock, libm):
    """(Bend expression for the next run, new clock)."""
    name, a = op[0], op[1:]
    now = b_double(clock)
    if name == 'clock':
        return run, a[0]
    if name == 'play':
        kind, p0, p1, p2, p3, frm = a
        return f'op.play({run}, J.AutomationEvent{{{word(frm)}, {word(kind)}, {word(p0)}, {word(p1)}, {word(p2)}, {word(p3)}}})', clock
    if name == 'begin':
        return f'op.begin({run}, {now})', clock
    if name == 'end':
        return f'op.end({run}, {now}, {b_double(a[0])})', a[0]
    if name == 'query':
        return f'op.query({run}, {now})', clock
    if name == 'poll':
        return f'op.poll({run}, {now})', clock
    if name == 'update_gestures':
        return f'op.update({run}, {now})', clock
    if name == 'gesture':
        action, count, points = a
        positions = ', '.join(f'M.Vector2{{fl({fbits(x)}), fl({fbits(y)})}}' for x, y in points)
        return f'op.gesture(M.{libm}{{}}, {run}, J.GestureEvent{{{word(action)}, {word(count)}, [], [{positions}]}}, {now})', clock
    setters = {'mouse_position': 0, 'mouse_offset': 1, 'mouse_scale': 2, 'exit_key': 3, 'gestures_enabled': 4, 'target_fps': 5,
               'hide_cursor': 6, 'show_cursor': 7, 'enable_cursor': 8, 'disable_cursor': 9, 'record_stop': 10, 'base_frame': 11,
               'list_new': 12}
    if name in setters:
        values = [fbits(v) for v in a] if name == 'mouse_scale' else [word(v) for v in a]
        values = (values + [0, 0])[:2]
        return f'op.set({run}, {setters[name]}, {values[0]}, {values[1]})', clock
    if name == 'record_start':
        return f'op.record_start({run})', clock
    if name == 'keys':
        return f'op.pops({run}, False{{}})', clock
    if name == 'chars':
        return f'op.pops({run}, True{{}})', clock
    if name == 'fps':
        return f'op.fps({run}, {now})', clock
    if name == 'keys_down':
        return f'op.keys_down({a[1]}n, {a[0]}, {run})', clock
    if name == 'list':
        return f'op.list({run})', clock
    if name == 'export':
        return f'op.export({run})', clock
    if name == 'load':
        return f'op.load({run}, LOAD_{a[0].replace("-", "_").upper()}())', clock
    contracts = {'query_pad_available': 0, 'query_pad_button': 1, 'query_axis_count': 2, 'query_axis': 3,
                 'query_touch_position': 4, 'query_mouse_x': 5, 'query_touch_x': 6}
    if name in contracts:
        values = ([word(v) for v in a] + [0, 0])[:2]
        return f'op.contract({run}, {contracts[name]}, {values[0]}, {values[1]})', clock
    raise ValueError(f'no Bend form for {name}')


def b_script(index, item, libm):
    clock = item['start']
    lines = [f'def script.{index}() -> String:', f'  r0 = start(J.Core.init_window({item["width"]}, {item["height"]}, {b_double(clock)}))']
    run = 'r0'
    for k, op in enumerate(item['ops']):
        expression, clock = b_op(op, run, clock, libm)
        if expression != run:
            lines.append(f'  r{k + 1} = {expression}')
            run = f'r{k + 1}'
    lines.append(f'  finish({run})')
    return '\n'.join(lines)


def load_defs(items):
    """One def per loaded file: its bytes as a list (large files as a generated loop)."""
    seen, defs = set(), []
    for item in items:
        for op in item['ops']:
            if op[0] != 'load' or op[1] in seen:
                continue
            seen.add(op[1])
            name, text = op[1].replace('-', '_').upper(), op[2]
            if name == 'TOO_MANY_EVENTS':
                lines = text.count(b'\n')
                defs.append('def load.repeat(n: Nat, +acc: +List<U32>) -> +List<U32>:\n  match n:\n    case 0n: acc\n'
                            '    case 1n+k: load.repeat(k, Con{101, Con{32, Con{49, Con{10, acc}}}})\n\n'
                            f'def LOAD_{name}() -> +List<U32>:\n  load.repeat({lines}n, Nil{{}})')
            else:
                defs.append(f'def LOAD_{name}() -> +List<U32>:\n  {b_list(text)}')
    return defs


def render(libm, items):
    def build(selected, gpu):
        body = [PROGRAM.replace('GESTURE_FLAGS', b_list(GESTURE_FLAGS)).replace('PAD_BUTTONS', b_list(PAD_BUTTONS))
                .replace('BUTTONS', b_list(BUTTONS)).replace('KEYS', b_list(KEYS))]
        body += load_defs([items[i] for i in selected])
        body += [b_script(i, items[i], libm) for i in selected]
        body.append('def main() -> IO(Unit):\n  do IO<Unit>:\n' + '\n'.join(f'    IO.print(script.{i}())' for i in selected) + '\n')
        return '\n\n'.join(body)
    return build


# -----------------------------------------------------------------------------
# Comparison

def sleep_request(high, low):
    """The sleep WaitTime(seconds) requests on this host (SUPPORT_PARTIALBUSY_WAIT_LOOP)."""
    seconds = struct.unpack('<d', struct.pack('<Q', (high << 32) | low))[0]
    if seconds == 0.0:
        return '-'
    sleep = seconds - seconds * 0.05
    if platform.system() == 'Darwin':
        return str(int(sleep * 1000000.0) & 0xFFFFFFFF)
    whole = int(sleep)
    return f'{whole}.{int((sleep - whole) * 1000000000)}'


def normalize(row):
    """Bend W rows carry Core.frame_wait's binary64 words; map them to the host's sleep request."""
    parts = []
    for part in row.split(' | '):
        match = re.fullmatch(r'W:(\d+),(\d+)', part)
        parts.append(f'W:{sleep_request(int(match.group(1)), int(match.group(2)))}' if match else part)
    return ' | '.join(parts)


def variant_definitions(library):
    flags = (library.parent / 'CMakeFiles/raylib.dir/flags.make').read_text()
    return {name: f'-D{name}' in flags.split() for name in
            ('SUPPORT_CUSTOM_FRAME_CONTROL', 'SUPPORT_BUSY_WAIT_LOOP', 'SUPPORT_PARTIALBUSY_WAIT_LOOP', 'SUPPORT_AUTOMATION_EVENTS',
             'SUPPORT_GESTURES_SYSTEM', 'SUPPORT_SCREEN_CAPTURE')}


def native_rows(probe, binary, index, item, tag='run'):
    """The rows a native script prints, in its own fresh directory."""
    directory = probe.work / f'{tag}-{index}'
    shutil.rmtree(directory, ignore_errors=True)
    directory.mkdir(parents=True)
    return [line[1:] for line in probekit.run([binary, str(index), str(directory)]).splitlines() if line.startswith('@')]


def zero_clock(item):
    """Whether a script's clock stays 0 and it never sets a target FPS (its wait would never end)."""
    ops = item['ops'] if item['contract'] is None else item['ops'][:item['contract']]
    if item['start'] != 0.0:
        return False
    for op in ops:
        if op[0] in ('clock', 'end') and op[1] != 0.0:
            return False
        if (op[0] == 'target_fps' and op[1] >= 1) or (op[0] == 'play' and op[1] == SET_FPS and op[2] >= 1):
            return False
    return True


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('input', args, raylib_options=OPTIONS)
    definitions = variant_definitions(probe.library)
    wanted = dict(SUPPORT_CUSTOM_FRAME_CONTROL=False, SUPPORT_BUSY_WAIT_LOOP=False, SUPPORT_PARTIALBUSY_WAIT_LOOP=True,
                  SUPPORT_AUTOMATION_EVENTS=True, SUPPORT_GESTURES_SYSTEM=True, SUPPORT_SCREEN_CAPTURE=True)
    if definitions != wanted:
        raise ProbeFailure(f'input: reference build definitions {definitions}, expected {wanted}')
    symbols = probekit.run(['nm', probe.library])
    if 'JonlibProbeTime' not in symbols or not re.search(r'\bT _?rlPlatformGetTime\b', symbols):
        raise ProbeFailure('input: the reference build does not route GetTime() through the probe clock')

    selection = native_profiles.angle_profile(args.raylib_source, probe.work / 'angle', probekit.run)
    libm = PROFILES[selection['selected_profile']]

    items = scripts()
    source = probe.work / 'reference.c'
    binary = probe.work / 'reference'
    source.write_text(c_program(items))
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', source, '-I' + str(args.raylib_source / 'src'), probe.library,
                  '-lm', '-o', binary])
    expected = [' | '.join(native_rows(probe, binary, index, item) + (['null'] if item['contract'] is not None else []))
                for index, item in enumerate(items)]

    # Shim transparency (macOS, where the unmodified memory platform's GetTime
    # is 0): scripts whose clock never leaves 0 and that never wait must print
    # the same rows against the build without the shim.
    unhooked = []
    if platform.system() == 'Darwin':
        library = probekit.native_library(args, PLAIN_OPTIONS)
        control = probe.work / 'reference-unhooked'
        probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', source, '-I' + str(args.raylib_source / 'src'), library,
                      '-lm', '-o', control])
        for index, item in enumerate(items):
            if zero_clock(item):
                if native_rows(probe, control, index, item, 'unhooked') != native_rows(probe, binary, index, item):
                    raise ProbeFailure(f'input: script {item["name"]} differs between the shimmed and unmodified builds')
                unhooked.append(item['name'])
        probe.report['unhooked_control'] = unhooked

    actions = list(range(len(items)))
    lanes = probe.candidates(render(libm, items), actions, batch=8,
                             parse=lambda text, selected: [normalize(line) for line in text.splitlines() if line.strip()])
    probe.compare(expected, lanes, describe=lambda i: f'script {items[i]["name"]}')
    rows = sum(e.count(' | ') + 1 for e in expected)
    probe.finish(scripts=len(items), rows=rows, unhooked_control=len(unhooked), contracts=sum(item['contract'] is not None for item in items),
                 operations=sum(len(item['ops']) for item in items), libm=libm, sleep=platform.system(),
                 scripts_sha256=hashlib.sha256(json.dumps(items, default=repr).encode()).hexdigest())


if __name__ == '__main__':
    main()
