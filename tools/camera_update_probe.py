#!/usr/bin/env python3
"""Compare Jonlib's UpdateCamera (J.Camera.update_for) with pinned raylib's,
driven by the same automation events and clocks.

Reference. The clock-injected memory-platform raylib of tools/input_probe.py
(-ffp-contract=off, tools/reference/input_clock.h, config.h's frame control):
per scripted frame the harness plays the frame's automation events
(PlayAutomationEvent), calls UpdateCamera(&camera, mode) on every camera of
the script, prints each camera's position, target and up bits, then runs
BeginDrawing and EndDrawing at the frame's clocks (EndDrawing times the frame,
waits for SetTargetFPS until the scripted `after` and polls input), so
GetFrameTime, IsKeyDown/IsKeyPressed (with the memory platform's 260-key
quirk), GetMouseDelta, the middle button, GetMouseWheelMove and gamepad 0 are
raylib's own. Each script runs in a fresh process (raylib keeps the frame time
across InitWindow). By default UpdateCamera is the linked library's
(uncontracted) with the host libm; --gnu-libm instead compiles the pinned
rcamera.h implementation into the harness (functions renamed, the library still
supplying the input state) with sinf/cosf from the Arm optimized-routines model
of tools/trig_probe.py and atan2f from the pinned glibc 2.39 (Sun) or 2.41
source, checking the glibc profiles on any host.

Contracts. A C oracle repeats UpdateCamera's steps on a copy with raylib's
camera functions and decides where Jonlib must answer None (from then on the
camera is "none"): a sinf/cosf argument outside the M.Libm profile (any
nonzero one under AppleLibm; under the glibc profiles subnormal ones and
|angle| > 6.283186f), and lockView angles outside the checked atan2f contract
(docs/CAMERA.md). Frames before a refusal are compared bit for bit (NaN words
as one class). CPU-1, CPU-2 and JavaScript lanes.

Scripts cover every mode (CAMERA_CUSTOM, FREE, ORBITAL, FIRST_PERSON,
THIRD_PERSON and an out-of-range mode), the arrow, Q/E, W/A/S/D, space and
left-control keys, KP_SUBTRACT/KP_ADD (held: the 260-key quirk presses them
every frame), mouse positions (the memory platform's GetMouseDelta measures
from the origin), the middle button pan, wheel zoom, a connected gamepad's
sticks (including the 0.25 thresholds), frames shorter and longer than the
60 FPS target, and random and degenerate cameras (zero, huge, NaN and
infinite components, up parallel to the view).
"""
import hashlib
import json
import math
import random
import struct

from camera_probe import ORACLE as TURN_ORACLE, cameras as camera_rows, word, gnu_objects, GNU_LIBM
from conformance import gradient_reference
import input_probe as ip
import native_profiles
import probekit
from probekit import ROOT, ProbeFailure

NAN = 0x7FC00000
TARGET = 1.0 / 60
WIDTH, HEIGHT = 800, 450

(KEY_UP_EVENT, KEY_DOWN_EVENT, MOUSE_UP, MOUSE_DOWN, MOUSE_POSITION, MOUSE_WHEEL, PAD_CONNECT, PAD_AXIS, SET_FPS) = (1, 2, 5, 6, 7, 8, 9, 13, 23)
KEY_RIGHT, KEY_LEFT, KEY_DOWN, KEY_UP = 262, 263, 264, 265
KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E, KEY_SPACE, KEY_CTRL, KP_SUB, KP_ADD = 87, 65, 83, 68, 81, 69, 32, 341, 333, 334
MODES = [0, 1, 2, 3, 4, 5]


# -----------------------------------------------------------------------------
# Scripts

def key(code, down=True):
    return (KEY_DOWN_EVENT if down else KEY_UP_EVENT, code, 0, 0)


def quick(events=()):
    return (list(events), 0.002, 0.004)


def slow(events=()):
    return (list(events), 0.003, 0.021)


def timed(start, frames):
    """Clocks as tools/examples_probe.py computes them: a 60 FPS target from the
    first frame (ACTION_SETTARGETFPS is played before its EndDrawing)."""
    previous, out = start, []
    for events, gap, draw in frames:
        begin = previous + gap
        update = begin - previous
        end = begin + draw
        frame = update + (end - begin)
        after = end + (TARGET - frame) if frame < TARGET else end
        out.append(dict(events=events, begin=begin, end=end, after=after))
        previous = after
    return out


def script(name, cams, frames, start=0.25):
    frames = [(([(SET_FPS, 60, 0, 0)] if i == 0 else []) + events, gap, draw) for i, (events, gap, draw) in enumerate(frames)]
    return dict(name=name, start=start, cameras=cams, frames=timed(start, frames))


def standard_camera():
    return ([0.2, 2.0, 4.0], [0.0, 2.0, 0.0], [0.0, 1.0, 0.0], 60.0, 0)


def every_mode(camera):
    return [(camera, mode) for mode in MODES]


def scripts():
    rng = random.Random(0xC0A7E)
    base = standard_camera()
    third = ([0.0, 2.0, -100.0], [0.0, 2.0, 0.0], [0.0, 1.0, 0.0], 45.0, 0)
    flat = ([10.0, 2.0, 10.0], [0.0, 0.0, 0.0], [0.0, 0.0, 1.0], 45.0, 1)
    sideways = ([1.0, 0.5, -3.0], [2.0, 1.0, 0.0], [0.9, 0.3, 0.1], 45.0, 0)
    out = [
        script('still', every_mode(base), [quick(), quick(), slow(), quick()]),
        script('arrows', every_mode(base), [quick(), quick([key(KEY_UP)]), quick(), slow([key(KEY_UP, False), key(KEY_LEFT)]),
                                           quick([key(KEY_DOWN)]), quick([key(KEY_LEFT, False), key(KEY_RIGHT)]), quick([key(KEY_DOWN, False)]),
                                           slow([key(KEY_RIGHT, False)])]),
        script('roll', every_mode(sideways), [quick([key(KEY_Q)]), quick(), slow([key(KEY_Q, False), key(KEY_E)]), quick(), quick([key(KEY_E, False)])]),
        script('wasd', every_mode(base), [quick([key(KEY_W)]), quick(), slow([key(KEY_W, False), key(KEY_A)]), quick([key(KEY_S)]),
                                         quick([key(KEY_A, False), key(KEY_D)]), slow(), quick([key(KEY_S, False), key(KEY_D, False)]), quick()]),
        script('wasd-plane', every_mode(flat) + every_mode(sideways), [quick([key(KEY_W), key(KEY_D)]), slow(), quick([key(KEY_W, False), key(KEY_A)]),
                                                                       quick([key(KEY_S)]), quick()]),
        script('vertical', every_mode(base), [quick([key(KEY_SPACE)]), quick(), quick([key(KEY_SPACE, False), key(KEY_CTRL)]), slow(),
                                             quick([key(KEY_CTRL, False)])]),
        script('zoom-keys', every_mode(third), [quick([key(KP_SUB)]), quick(), quick([key(KP_SUB, False), key(KP_ADD)]), quick(),
                                               quick([key(KP_ADD, False)]), quick()]),
        script('wheel', every_mode(base), [quick(), quick([(MOUSE_WHEEL, 0, 1, 0)]), quick(), quick([(MOUSE_WHEEL, 0, -3, 0)]),
                                          quick([(MOUSE_WHEEL, 2, 1, 0)]), quick([(MOUSE_WHEEL, 0, 0, 0)])]),
        script('mouse', every_mode(base), [quick(), quick([(MOUSE_POSITION, 10, 0, 0)]), quick(), quick([(MOUSE_POSITION, 0, 0, 0)]),
                                          quick([(MOUSE_POSITION, 0, 30, 0)]), quick([(MOUSE_POSITION, 400, 225, 0)]), quick()]),
        script('pan', every_mode(base), [quick([(MOUSE_DOWN, 2, 0, 0)]), quick([(MOUSE_POSITION, 5, 0, 0)]), quick([(MOUSE_POSITION, 0, 7, 0)]),
                                        quick([(MOUSE_POSITION, 0, 0, 0)]), quick([(MOUSE_UP, 2, 0, 0)]), quick()]),
        script('gamepad', every_mode(base), [quick([(PAD_CONNECT, 0, 0, 0)]), quick([(PAD_AXIS, 0, 1, -8192)]), quick([(PAD_AXIS, 0, 0, 8192)]),
                                            quick([(PAD_AXIS, 0, 1, 8191), (PAD_AXIS, 0, 0, -20000)]), slow([(PAD_AXIS, 0, 1, 30000)]),
                                            quick([(PAD_AXIS, 0, 2, 4000)]), quick([(PAD_AXIS, 0, 3, -3000), (PAD_AXIS, 0, 2, 0)]),
                                            quick([(PAD_AXIS, 0, 3, 0), (PAD_AXIS, 0, 1, 0), (PAD_AXIS, 0, 0, 0)])]),
        script('combined', every_mode(third), [quick([key(KEY_W), key(KEY_LEFT), (MOUSE_WHEEL, 0, 2, 0)]), slow([key(KEY_Q)]),
                                              quick([key(KEY_W, False), key(KEY_UP), (MOUSE_POSITION, 3, 4, 0)]),
                                              quick([key(KEY_LEFT, False), key(KEY_Q, False), key(KEY_UP, False), key(KEY_SPACE)]), quick()]),
    ]
    # Degenerate and random cameras through movement-only and rotating frames.
    special = camera_rows(rng, 30)
    for index in range(0, len(special), 6):
        group = special[index:index + 6]
        cams = [(camera, MODES[(index + k) % len(MODES)]) for k, camera in enumerate(group)]
        out.append(script(f'special-{index // 6}', cams, [quick([key(KEY_W)]), quick([key(KEY_D), (MOUSE_WHEEL, 0, 1, 0)]),
                                                          slow([key(KEY_UP)]), quick([key(KEY_UP, False), key(KEY_RIGHT)]), quick()]))
    for index in range(4):
        cams = [(camera_rows(rng, 30)[-1 - k], rng.choice(MODES + [0xFFFFFFFF])) for k in range(6)]
        frames = []
        held = set()
        for _ in range(8):
            events = []
            for code in rng.sample([KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_Q, KEY_E, KEY_SPACE, KEY_CTRL, KP_SUB], 3):
                events.append(key(code, code not in held))
                held.symmetric_difference_update({code})
            if rng.random() < 0.4:
                events.append((MOUSE_POSITION, rng.randrange(800), rng.randrange(450), 0))
            if rng.random() < 0.3:
                events.append((MOUSE_WHEEL, 0, rng.choice((-2, -1, 1, 2)), 0))
            frames.append(rng.choice((quick, slow))(events))
        out.append(script(f'random-{index}', cams, frames, start=rng.choice((0.25, 1000.5, 3.0))))
    return out


def f32_words(values):
    return [word(float(v)) for v in values]


def encode(item):
    """Script words: start (hi, lo), camera count, cameras (11 words and the mode),
    frame count, frames (event count, events of 4 words, begin/end/after hi, lo)."""
    out = []
    bits = struct.unpack('<Q', struct.pack('<d', item['start']))[0]
    out += [bits >> 32, bits & 0xFFFFFFFF, len(item['cameras'])]
    for (position, target, up, fovy, projection), mode in item['cameras']:
        out += f32_words([*position, *target, *up, fovy]) + [projection & 0xFFFFFFFF, mode & 0xFFFFFFFF]
    out.append(len(item['frames']))
    for frame in item['frames']:
        out.append(len(frame['events']))
        for kind, a, b, c in frame['events']:
            out += [kind, a & 0xFFFFFFFF, b & 0xFFFFFFFF, c & 0xFFFFFFFF]
        for name in ('begin', 'end', 'after'):
            bits = struct.unpack('<Q', struct.pack('<d', frame[name]))[0]
            out += [bits >> 32, bits & 0xFFFFFFFF]
    return out


# -----------------------------------------------------------------------------
# Reference

CONTROL_NAMES = ['GetCameraForward', 'GetCameraUp', 'GetCameraRight', 'CameraMoveForward', 'CameraMoveUp', 'CameraMoveRight',
                 'CameraMoveToTarget', 'CameraYaw', 'CameraPitch', 'CameraRoll', 'GetCameraViewMatrix', 'GetCameraProjectionMatrix',
                 'UpdateCamera', 'UpdateCameraPro']

HARNESS = r'''
static double probe_clock = 0.0, probe_after = 0.0;
double JonlibProbeTime(void) { return probe_clock; }
int JonlibProbeUsleep(unsigned int us) { (void)us; probe_clock = probe_after; return 0; }
int JonlibProbeNanosleep(const struct timespec *req, struct timespec *rem) { (void)req; (void)rem; probe_clock = probe_after; return 0; }

static double dbl(unsigned hi, unsigned lo) { unsigned long long b = ((unsigned long long)hi << 32) | lo; double d; memcpy(&d, &b, 8); return d; }

/* UpdateCamera's steps on a copy, with the refusal checks Jonlib applies
   before each rotation (camera_probe's turnable/pitch_ok). */
#define PITCH(a) do { float a_ = (a); if (!pitch_ok(c, a_, lock)) return 0; CameraPitch(&c, a_, lock, around, false); } while (0)
#define YAW(a) do { float a_ = (a); if (!half_turnable(a_)) return 0; CameraYaw(&c, a_, around); } while (0)
#define ROLL(a) do { float a_ = (a); if (!half_turnable(a_)) return 0; CameraRoll(&c, a_); } while (0)
static int update_ok(Camera c, int mode)
{
    Vector2 delta = GetMouseDelta();
    bool plane = (mode == CAMERA_FIRST_PERSON) || (mode == CAMERA_THIRD_PERSON);
    bool around = (mode == CAMERA_THIRD_PERSON) || (mode == CAMERA_ORBITAL);
    bool lock = (mode == CAMERA_FREE) || (mode == CAMERA_FIRST_PERSON) || (mode == CAMERA_THIRD_PERSON) || (mode == CAMERA_ORBITAL);
    float move = 5.4f*GetFrameTime(), rot = 0.03f*GetFrameTime(), pan = 2.0f*GetFrameTime(), orbit = 0.5f*GetFrameTime();
    if (mode == CAMERA_CUSTOM) return 1;
    if (mode == CAMERA_ORBITAL) return turnable(orbit, orbit);
    if (IsKeyDown(KEY_DOWN)) PITCH(-rot);
    if (IsKeyDown(KEY_UP)) PITCH(rot);
    if (IsKeyDown(KEY_RIGHT)) YAW(-rot);
    if (IsKeyDown(KEY_LEFT)) YAW(rot);
    if (IsKeyDown(KEY_Q)) ROLL(-rot);
    if (IsKeyDown(KEY_E)) ROLL(rot);
    if ((mode == CAMERA_FREE) && IsMouseButtonDown(MOUSE_BUTTON_MIDDLE))
    {
        if (delta.x > 0.0f) CameraMoveRight(&c, pan, plane);
        if (delta.x < 0.0f) CameraMoveRight(&c, -pan, plane);
        if (delta.y > 0.0f) CameraMoveUp(&c, -pan);
        if (delta.y < 0.0f) CameraMoveUp(&c, pan);
    }
    else { YAW(-delta.x*0.003f); PITCH(-delta.y*0.003f); }
    if (IsKeyDown(KEY_W)) CameraMoveForward(&c, move, plane);
    if (IsKeyDown(KEY_A)) CameraMoveRight(&c, -move, plane);
    if (IsKeyDown(KEY_S)) CameraMoveForward(&c, -move, plane);
    if (IsKeyDown(KEY_D)) CameraMoveRight(&c, move, plane);
    if (IsGamepadAvailable(0))
    {
        YAW(-(GetGamepadAxisMovement(0, GAMEPAD_AXIS_RIGHT_X)*2)*0.003f);
        PITCH(-(GetGamepadAxisMovement(0, GAMEPAD_AXIS_RIGHT_Y)*2)*0.003f);
    }
    return 1;
}

static unsigned in[100000];
int main(int argc, char **argv)
{
    FILE *f = fopen(argv[1], "rb"); int n = 0; unsigned char b[4];
    while (n < 100000 && fread(b, 1, 4, f) == 4) in[n++] = b[0] | b[1] << 8 | b[2] << 16 | (unsigned)b[3] << 24;
    fclose(f);
    int at = 0;
    probe_clock = dbl(in[0], in[1]); at = 2;
    SetTraceLogLevel(LOG_NONE);
    InitWindow(WIDTH, HEIGHT, "");
    int count = (int)in[at++];
    Camera cams[16]; int modes[16], alive[16];
    for (int i = 0; i < count; i++) { cams[i] = cam(in + at); modes[i] = (int)in[at + 11]; alive[i] = 1; at += 12; }
    int frames = (int)in[at++];
    for (int k = 0; k < frames; k++)
    {
        int events = (int)in[at++];
        for (int e = 0; e < events; e++)
        {
            AutomationEvent ev = { 0, in[at], { (int)in[at + 1], (int)in[at + 2], (int)in[at + 3], 0 } };
            PlayAutomationEvent(ev);
            at += 4;
        }
        for (int i = 0; i < count; i++)
        {
            if (i) putchar(' ');
            if (alive[i] && update_ok(cams[i], modes[i])) { UpdateCamera(&cams[i], modes[i]); camera_text(cams[i]); }
            else { alive[i] = 0; printf("none"); }
        }
        putchar('|');
        probe_clock = dbl(in[at], in[at + 1]);
        BeginDrawing();
        probe_clock = dbl(in[at + 2], in[at + 3]);
        probe_after = dbl(in[at + 4], in[at + 5]);
        EndDrawing();
        probe_clock = probe_after;
        at += 6;
    }
    putchar('\n');
    CloseWindow();
    return 0;
}
'''


def oracle_helpers():
    """camera_probe's refusal helpers (turnable, pitch_ok, ...) without its sections."""
    return TURN_ORACLE[:TURN_ORACLE.index('static unsigned in[400000];')]


def native_source(arithmetic_gnu, header, control):
    head = '#include <limits.h>\n#include <math.h>\n#include <stdio.h>\n#include <string.h>\n#include <time.h>\n'
    if control:
        head += header + ''.join(f'#define {name} ctl_{name}\n' for name in CONTROL_NAMES)
        head += ('#include "raylib.h"\n#include "rlgl.h"\n#define RAYMATH_STATIC_INLINE\n#define RCAMERA_IMPLEMENTATION\n'
                 '/* Unaltered pinned rcamera.h (zlib, LICENSES/raylib.txt), its functions renamed. */\n#include "rcamera.h"\n')
    else:
        head += '#include "raylib.h"\n#include "rcamera.h"\n'
    head += f'#define FUSED 0\n#define GNU {int(arithmetic_gnu)}\n#define WIDTH {WIDTH}\n#define HEIGHT {HEIGHT}\n'
    return head + oracle_helpers() + HARNESS


# -----------------------------------------------------------------------------
# Candidate

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def float(+w: U32) -> F32:
  U32{x} = w
  F32{x}
def words(bytes: +List<U32>) -> +List<U32>:
  match bytes:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}: Con{(a .|. (b << 8n) .|. (c << 16n) .|. (d << 24n) : U32), words(rest)}
    case _: Nil{}
def bits(+x: F32) -> String:
  U32.show(F32.bits(x))
def v3(v: M.Vector3) -> String:
  M.Vector3{x, y, z} = v
  bits(x) ++ "," ++ bits(y) ++ "," ++ bits(z)
def camera_text(c: J.Camera3D) -> String:
  J.Camera3D{p, t, u, _, _} = c
  v3(p) ++ "," ++ v3(t) ++ "," ++ v3(u)
def maybe_camera(m: Maybe<J.Camera3D>) -> String:
  match m:
    case None{}: "none"
    case Some{c}: camera_text(c)
def vector(+x: U32, +y: U32, +z: U32) -> M.Vector3:
  M.Vector3{float(x), float(y), float(z)}
def f64(+hi: U32, +lo: U32) -> M.Float64:
  M.Float64{hi, lo}
type Cam is Type:
  Cam{camera: Maybe<J.Camera3D>, mode: U32}
def cams.read(n: Nat, values: +List<U32>, acc: List<Cam>) -> List<Cam> & +List<U32>:
  match n values:
    case 1n+k Con{a, Con{b, Con{c, Con{d, Con{e, Con{f, Con{g, Con{h, Con{i, Con{j, Con{p, Con{m, rest}}}}}}}}}}}}:
      cams.read(k, rest, Con{Cam{Some{J.Camera3D{vector(a, b, c), vector(d, e, f), vector(g, h, i), float(j), p}}, m}, acc})
    case _ _: (List.reverse(&1, Cam, acc), values)
def play(core: Maybe<J.Core>, +kind: U32, +p0: U32, +p1: U32, +p2: U32) -> Maybe<J.Core>:
  match core:
    case None{}: None{}
    case Some{+c}: J.Core.play_automation_event(c, J.AutomationEvent{0, kind, p0, p1, p2, 0})
def events(n: Nat, core: Maybe<J.Core>, values: +List<U32>) -> Maybe<J.Core> & +List<U32>:
  match n values:
    case 1n+k Con{kind, Con{p0, Con{p1, Con{p2, rest}}}}: events(k, play(core, kind, p0, p1, p2), rest)
    case _ _: (core, values)
def cam.updated(+mode: U32, result: Maybe<J.Camera3D>) -> Cam & String:
  match result:
    case None{}: (Cam{None{}, mode}, "none")
    case Some{+c}: (Cam{Some{c}, mode}, camera_text(c))
def cam.update.with(+core: J.Core, +mode: U32, camera: Maybe<J.Camera3D>) -> Cam & String:
  match camera:
    case None{}: (Cam{None{}, mode}, "none")
    case Some{c}: cam.updated(mode, J.Camera.update_for(ARITH, LIBM, core, c, mode))
def cam.update(+core: J.Core, cam: Cam) -> Cam & String:
  Cam{camera, +mode} = cam
  cam.update.with(core, mode, camera)
def cams.join(first: Bool, text: String, rest: String) -> String:
  match first:
    case True{}: text ++ rest
    case False{}: " " ++ text ++ rest
def cams.rest(first: Bool, done: Cam & String, after: List<Cam> & String) -> List<Cam> & String:
  (cam, text) = done
  (others, more) = after
  (Con{cam, others}, cams.join(first, text, more))
def cams.update(cams: List<Cam>, +core: J.Core, first: Bool) -> List<Cam> & String:
  match cams:
    case Nil{}: (Nil{}, "")
    case Con{cam, rest}: cams.rest(first, cam.update(core, cam), cams.update(rest, core, False{}))
def step.end(core: Maybe<J.Core>, +end: M.Float64, +after: M.Float64) -> Maybe<J.Core>:
  match core:
    case None{}: None{}
    case Some{+c}: J.Core.end_drawing(c, end, after)
def timed(core: Maybe<J.Core>, values: +List<U32>) -> Maybe<J.Core> & +List<U32>:
  match core values:
    case Some{+c} Con{bh, Con{bl, Con{eh, Con{el, Con{ah, Con{al, rest}}}}}}: (step.end(J.Core.begin_drawing(c, f64(bh, bl)), f64(eh, el), f64(ah, al)), rest)
    case _ _: (None{}, Nil{})
type Run is Type:
  Run{core: Maybe<J.Core>, cams: List<Cam>, values: +List<U32>, out: String}
def run.timed(cams: List<Cam>, out: String, next: Maybe<J.Core> & +List<U32>) -> Run:
  (core, values) = next
  Run{core, cams, values, out}
def run.updated(+core: J.Core, values: +List<U32>, out: String, updated: List<Cam> & String) -> Run:
  (cams, text) = updated
  run.timed(cams, out ++ text ++ "|", timed(Some{core}, values))
def run.played.with(cams: List<Cam>, out: String, core: Maybe<J.Core>, values: +List<U32>) -> Run:
  match core:
    case None{}: Run{None{}, cams, Nil{}, out ++ "null"}
    case Some{+c}: run.updated(c, values, out, cams.update(cams, c, True{}))
def run.played(cams: List<Cam>, out: String, played: Maybe<J.Core> & +List<U32>) -> Run:
  (core, values) = played
  run.played.with(cams, out, core, values)
def run.with(core: Maybe<J.Core>, cams: List<Cam>, values: +List<U32>, out: String) -> Run:
  match core values:
    case Some{+c} Con{count, rest}: run.played(cams, out, events(U32.to_nat(count), Some{c}, rest))
    case None{} _: Run{None{}, cams, Nil{}, out}
    case Some{_} _: Run{None{}, cams, Nil{}, out ++ "null"}
# One scripted frame: events, UpdateCamera of every camera, BeginDrawing/EndDrawing.
def run.frame(run: Run) -> Run:
  Run{core, cams, values, out} = run
  run.with(core, cams, values, out)
def frames(n: Nat, run: Run) -> Run:
  match n:
    case 0n: run
    case 1n+k: frames(k, run.frame(run))
def run.out(run: Run) -> String:
  Run{_, _, _, out} = run
  out
def script.frames(+core: J.Core, cams: List<Cam>, values: +List<U32>) -> String:
  match values:
    case Con{count, rest}: run.out(frames(U32.to_nat(count), Run{Some{core}, cams, rest, ""}))
    case _: "malformed"
def script.cams(+core: J.Core, read: List<Cam> & +List<U32>) -> String:
  (cams, values) = read
  script.frames(core, cams, values)
def script.window(core: Maybe<J.Core>, values: +List<U32>) -> String:
  match core values:
    case Some{+c} Con{count, rest}: script.cams(c, cams.read(U32.to_nat(count), rest, Nil{}))
    case _ _: "no window"
def script(values: +List<U32>) -> String:
  match values:
    case Con{hi, Con{lo, rest}}: script.window(J.Core.init_window(800, 450, f64(hi, lo)), rest)
    case _: "malformed"
def section(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> IO(Unit):
  match result:
    case Fail{_}: IO.print("error")
    case Done{bytes}: IO.print(script(words(bytes)))
def main() -> IO(Unit):
  do IO<Unit>:
'''


def parse_line(line):
    frames = line.rstrip('|').split('|')
    rows = []
    for frame in frames:
        rows.append(tuple(None if part == 'none' else tuple(NAN if (int(w) & 0x7FFFFFFF) > 0x7F800000 else int(w) for w in part.split(','))
                          for part in frame.split(' ')))
    return rows


def configure(parser):
    parser.add_argument('--gnu-libm', choices=sorted(GNU_LIBM),
                        help='compile the pinned rcamera.h into the harness with sinf/cosf from the Arm model and atan2f from the pinned glibc source')


def main():
    args = probekit.arguments(__doc__, configure)
    name = 'camera-update' + (f'-{args.gnu_libm}' if args.gnu_libm else '')
    probe = probekit.Probe(name, args, raylib_options=ip.OPTIONS)
    definitions = ip.variant_definitions(probe.library)
    wanted = dict(SUPPORT_CUSTOM_FRAME_CONTROL=False, SUPPORT_BUSY_WAIT_LOOP=False, SUPPORT_PARTIALBUSY_WAIT_LOOP=True,
                  SUPPORT_AUTOMATION_EVENTS=True, SUPPORT_GESTURES_SYSTEM=True, SUPPORT_SCREEN_CAPTURE=True)
    if definitions != wanted:
        raise ProbeFailure(f'camera-update: reference build definitions {definitions}, expected {wanted}')
    header, objects = '', []
    if args.gnu_libm:
        libm, symbol = GNU_LIBM[args.gnu_libm]
        header, objects = gnu_objects(probe, symbol)
    else:
        selection = native_profiles.angle_profile(args.raylib_source, probe.work / 'angle', probekit.run)
        libm = ip.PROFILES[selection['selected_profile']]
        if (libm == 'AppleLibm') != (gradient_reference() == 'AppleLibm'):
            raise ProbeFailure(f'camera-update: atan2f profile {libm} and sinf/cosf profile {gradient_reference()} differ')
    items = scripts()
    source = probe.work / 'reference.c'
    binary = probe.work / 'reference'
    source.write_text(native_source(libm != 'AppleLibm', header, bool(args.gnu_libm)))
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-fno-builtin-atan2f', source, '-I' + str(args.raylib_source / 'src'),
                  *objects, probe.library, '-lm', '-o', binary])
    cases = probe.work / 'cases'
    cases.mkdir(parents=True, exist_ok=True)
    paths, expected = [], []
    for index, item in enumerate(items):
        path = cases / f'script-{index}.bin'
        path.write_bytes(b''.join(struct.pack('<I', w) for w in encode(item)))
        paths.append(path.relative_to(ROOT).as_posix())
        lines = [line for line in probekit.run([binary, path]).splitlines() if not line.startswith('INFO:')]
        if len(lines) != 1:
            raise ProbeFailure(f'camera-update: native {item["name"]} printed {len(lines)} lines')
        expected.append(parse_line(lines[0]))
    text = PROGRAM.replace('ARITH', 'M.Uncontracted{}').replace('LIBM', f'M.{libm}{{}}')

    def render(selected, gpu):
        body = text
        for index in selected:
            body += f'    Unit <- IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Unit, J.Files.load_data("{paths[index]}"), section)\n'
        return body + '    IO.print("done")\n'

    def parse(output, selected):
        rows = output.splitlines()
        if rows[-1:] != ['done'] or len(rows) != len(selected) + 1:
            raise ProbeFailure('camera-update: candidate output did not finish')
        return [parse_line(line) for line in rows[:-1]]

    actions = list(range(len(items)))
    lanes = probe.candidates(render, actions, batch=len(actions), parse=parse)
    lanes = {lane: rows for lane, rows in lanes.items() if lane != 'gpu'}

    def describe(index):
        rows = next(iter(lanes.values()))[index]
        frame = next((k for k, (a, b) in enumerate(zip(expected[index], rows)) if a != b), None)
        camera = frame is not None and next((k for k, (a, b) in enumerate(zip(expected[index][frame], rows[frame])) if a != b), None)
        return f'script {items[index]["name"]} frame {frame} camera {camera}'

    probe.compare(expected, lanes, describe=describe)
    results = sum(len(frame) for rows in expected for frame in rows)
    refused = sum(part is None for rows in expected for frame in rows for part in frame)
    probe.finish(reference=('rcamera.h control with ' + args.gnu_libm + ' sinf/cosf/atan2f models') if args.gnu_libm else 'linked raylib',
                 profile='Uncontracted', libm=libm, scripts=len(items), cameras=sum(len(item['cameras']) for item in items),
                 frames=sum(len(item['frames']) for item in items), results=results, refused_results=refused,
                 scripts_sha256=hashlib.sha256(json.dumps(items, default=repr).encode()).hexdigest())


if __name__ == '__main__':
    main()
