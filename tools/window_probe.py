#!/usr/bin/env python3
"""Compare Jonlib's window state, monitor, clipboard, dropped-file, clock,
screenshot and texture-file functions with pinned raylib's memory platform.

Reference. The clock-injected memory-platform raylib of tools/input_probe.py
(-ffp-contract=off, tools/reference/input_clock.h, config.h's frame control).
Each script runs in a fresh native process inside its own directory
(TakeScreenshot writes to the working directory, CORE.Storage.basePath).
Operations: SetConfigFlags before InitWindow (also FLAG_MSAA_4X_HINT, which
moves the shapes texture rectangle) and after it; every IsWindow* query and
IsWindowState over single flags, combinations, 0 and ~0; the setters the
memory platform only logs (SetWindowState, ClearWindowState, the toggles,
Maximize/Minimize/RestoreWindow, SetWindowIcon(s), position, monitor, size,
opacity, focus, clipboard, cursor shape, gamepad vibration) followed by
queries showing that nothing changed; SetWindowTitle, Min/MaxSize and event
waiting; the monitor, DPI, window position, clipboard (text and image), key
name, window handle and gamepad-mapping answers; IsFileDropped,
LoadDroppedFiles and UnloadDroppedFiles; GetTime after InitWindow, BeginDrawing,
EndDrawing and WaitTime (negative, zero, fractional and -infinity seconds;
WaitTime's sleep ends at the scripted destination, as tools/input_probe.py's
shim does); framebuffers of shapes drawn with and without FLAG_MSAA_4X_HINT;
LoadTexture of PNG fixtures (and a missing file) drawn into the frame;
LoadTextureCubemap's fields for every layout and auto-detected aspect; and
TakeScreenshot (PNG, BMP, no suffix, a name with a quote).

Screenshots. raylib's memory platform writes the screen bottom-up with red and
blue swapped (rlReadScreenPixels over rlsw's BGRA buffer); Jonlib follows
LoadImageFromScreen's desktop contract (top-down RGBA, alpha 255,
docs/FRAME.md). The harness loads raylib's file, flips it and swaps red and
blue, and exports that with ExportImage: Jonlib's file must equal it byte for
byte. Existence (FileExists) is compared for every name.

Contracts (Jonlib must answer null; never run natively): WaitTime of NaN,
+infinity and more than 4096 seconds (raylib's sleep converts them with
undefined behavior). CPU-1, CPU-2 and JavaScript lanes.
"""
import hashlib
import json
import math
import shutil
import struct
import zlib

import input_probe as ip
import probekit
from probekit import ROOT, ProbeFailure

W, H = 48, 32
FLAGS = [0, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 34, 0xFFFFFFFF]
RED, BLUE, GREEN, WHITE, RAYWHITE = 3861460991, 7926271, 0x00E430FF, 0xFFFFFFFF, 0xF5F5F5FF

# Op kinds (shared by both sides).
(QUERY, CONFIG, SET_STATE, CLEAR_STATE, FULLSCREEN, BORDERLESS, MAXIMIZE, MINIMIZE, RESTORE, TITLE, POSITION, MONITOR,
 MIN_SIZE, MAX_SIZE, SIZE, OPACITY, FOCUSED, CLIPBOARD, EVENTS_ON, EVENTS_OFF, CURSOR, MAPPINGS, VIBRATION, UNLOAD_DROPPED,
 ICON, ICONS) = range(26)
WAIT, BEGIN, END = 30, 31, 32
SCENE, FRAMEBUFFER, SCREENSHOT, TEXTURE, DRAW_TEXTURE, UNLOAD_TEXTURE, CUBEMAP, SCREEN_SPACE = 40, 41, 42, 43, 44, 45, 46, 47


def dbits(value):
    return struct.unpack('<Q', struct.pack('<d', value))[0]


def fbits(value):
    return struct.unpack('<I', struct.pack('<f', value))[0]


def op(kind, a=0, b=0, c=0, d=0, s=''):
    return (kind, a & 0xFFFFFFFF, b & 0xFFFFFFFF, c & 0xFFFFFFFF, d & 0xFFFFFFFF, s)


def clock(kind, value, after=None):
    bits = dbits(value)
    if after is None:
        return op(kind, bits >> 32, bits & 0xFFFFFFFF)
    later = dbits(after)
    return op(kind, bits >> 32, bits & 0xFFFFFFFF, later >> 32, later & 0xFFFFFFFF)


def png(width, height, pixels, color_type=6):
    """A plain zlib PNG (filter 0) of RGBA or RGB rows."""
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)
    channels = 4 if color_type == 6 else 3
    raw = b''.join(b'\0' + bytes(v for p in pixels[y * width:(y + 1) * width] for v in p[:channels]) for y in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, color_type, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def fixtures(work):
    rgba = [(x * 40 % 256, y * 60 % 256, (x + y) * 25 % 256, 255 if (x + y) % 3 else 128) for y in range(5) for x in range(7)]
    rgb = [((x * 90) % 256, 200, (y * 70) % 256, 255) for y in range(4) for x in range(3)]
    (work / 'fixture-rgba.png').write_bytes(png(7, 5, rgba))
    (work / 'fixture-rgb.png').write_bytes(png(3, 4, rgb, color_type=2))
    return {name: (work / name).relative_to(ROOT).as_posix() for name in ('fixture-rgba.png', 'fixture-rgb.png')}


def scripts(paths):
    start = 0.5
    out = []
    out.append(dict(name='flags', pre=[FLAGS[1] | 64 | 4096], start=start, ops=[
        op(QUERY), op(CONFIG, 128 | 512), op(QUERY), op(CONFIG, 1024 | 2048), op(QUERY),
        op(SET_STATE, 2), op(CLEAR_STATE, 2), op(FULLSCREEN), op(BORDERLESS), op(MAXIMIZE), op(MINIMIZE), op(RESTORE), op(QUERY),
        op(TITLE, s='renamed'), op(POSITION, 10, 20), op(MONITOR, 1), op(MIN_SIZE, 320, 240), op(MAX_SIZE, 1920, 1080),
        op(SIZE, 640, 480), op(OPACITY, fbits(0.5)), op(FOCUSED), op(CLIPBOARD, s='clip'), op(EVENTS_ON), op(EVENTS_OFF),
        op(CURSOR, 3), op(MAPPINGS, s='mapping'), op(VIBRATION, 0, fbits(0.5), fbits(1.0), fbits(2.0)), op(UNLOAD_DROPPED),
        op(ICON, 4, 4), op(ICONS, 2), op(QUERY)]))
    out.append(dict(name='plain', pre=[], start=0.0, ops=[op(QUERY), op(CONFIG, 0), op(QUERY), op(CONFIG, 0xFFFFFFFF), op(QUERY)]))
    out.append(dict(name='clock', pre=[], start=start, ops=[
        op(QUERY), clock(WAIT, 0.25), op(QUERY), clock(WAIT, -1.0), op(QUERY), clock(WAIT, 0.0), op(QUERY), clock(WAIT, -0.0),
        clock(WAIT, float('-inf')), clock(WAIT, 1.0 / 60), clock(BEGIN, 1.0), op(QUERY), clock(WAIT, 0.003), op(QUERY),
        clock(END, 1.01, 1.01), op(QUERY), clock(WAIT, 4096.0), clock(WAIT, 1e-3), op(QUERY)]))
    out.append(dict(name='clock-contracts', pre=[], start=start, ops=[op(QUERY), clock(WAIT, 0.125), clock(WAIT, float('nan'))],
                    contract=2))
    out.append(dict(name='clock-inf', pre=[], start=start, ops=[op(QUERY), clock(WAIT, float('inf'))], contract=1))
    out.append(dict(name='clock-long', pre=[], start=start, ops=[clock(WAIT, 4096.0000000000005)], contract=0))
    for msaa in (0, 32):
        out.append(dict(name=f'shapes-{msaa}', pre=[msaa], start=start, ops=[
            clock(BEGIN, 0.6), op(SCENE, 0), clock(END, 0.62, 0.62), op(FRAMEBUFFER), op(QUERY)]))
    out.append(dict(name='screenshot', pre=[], start=start, ops=[
        clock(BEGIN, 0.6), op(SCENE, 0), clock(END, 0.62, 0.62), op(SCREENSHOT, s='shot.png'), op(SCREENSHOT, s='shot.BMP'),
        op(SCREENSHOT, s='noext'), op(SCREENSHOT, s="it's.png"), clock(BEGIN, 0.7), op(SCENE, 1), clock(END, 0.71, 0.71),
        op(SCREENSHOT, s='second.png')]))
    out.append(dict(name='textures', pre=[], start=start, ops=[
        op(TEXTURE, s=paths['fixture-rgba.png']), clock(BEGIN, 0.6), op(SCENE, 1), op(DRAW_TEXTURE, 3, 4), op(DRAW_TEXTURE, 40, 28),
        clock(END, 0.62, 0.62), op(FRAMEBUFFER), op(UNLOAD_TEXTURE), op(TEXTURE, s=paths['fixture-rgb.png']),
        clock(BEGIN, 0.7), op(SCENE, 1), op(DRAW_TEXTURE, 10, 10), op(DRAW_TEXTURE, -1, -2), clock(END, 0.71, 0.71), op(FRAMEBUFFER),
        op(UNLOAD_TEXTURE), op(TEXTURE, s='.build/window-probe/missing.png'), op(TEXTURE, s=paths['fixture-rgba.png']),
        op(UNLOAD_TEXTURE)]))
    cubes = [(6, 36, 0), (36, 6, 0), (12, 9, 0), (9, 12, 0), (8, 8, 0), (13, 7, 0), (6, 36, 1), (36, 6, 2), (9, 12, 3),
             (12, 9, 4), (8, 8, 1), (8, 8, 2), (8, 8, 3), (8, 8, 4), (8, 8, 5), (40, 30, 4), (30, 40, 3), (2, 2, 1)]
    out.append(dict(name='cubemap', pre=[], start=start, ops=[op(CUBEMAP, w, h, layout) for w, h, layout in cubes] + [op(QUERY)]))
    # GetWorldToScreen/GetScreenToWorldRay at the window size: orthographic and
    # another projection value (identity); perspective is refused (not run).
    out.append(dict(name='screen-space', pre=[], start=start, ops=[op(SCREEN_SPACE, 1), op(SCREEN_SPACE, 2)]))
    return out


# -----------------------------------------------------------------------------
# Reference

C_PROGRAM = r'''#include "raylib.h"
#include "rlgl.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double probe_clock = 0.0, probe_after = 0.0;
double JonlibProbeTime(void) { return probe_clock; }
int JonlibProbeUsleep(unsigned int us) { (void)us; probe_clock = probe_after; return 0; }
int JonlibProbeNanosleep(const struct timespec *req, struct timespec *rem) { (void)req; (void)rem; probe_clock = probe_after; return 0; }

static double dbl(unsigned hi, unsigned lo) { unsigned long long b = ((unsigned long long)hi << 32) | lo; double d; memcpy(&d, &b, 8); return d; }
static float flt(unsigned b) { float f; memcpy(&f, &b, 4); return f; }
static unsigned fb(float f) { unsigned b; memcpy(&b, &f, 4); return b; }
static void tok(const char *s) { printf("%s;", s); }
static void num(unsigned v) { printf("%u,", v); }
static void str(const char *s) { printf("s:%s,", s ? s : "(null)"); }
static const unsigned FLAGS[] = { FLAGLIST };
static int shots = 0;

static void query(void)
{
    num(IsWindowReady()); num(IsWindowFullscreen()); num(IsWindowHidden()); num(IsWindowMinimized()); num(IsWindowMaximized());
    num(IsWindowFocused()); num(IsWindowResized());
    for (unsigned i = 0; i < sizeof FLAGS/sizeof FLAGS[0]; i++) num(IsWindowState(FLAGS[i]));
    num(GetScreenWidth()); num(GetScreenHeight()); num(GetRenderWidth()); num(GetRenderHeight());
    num(GetMonitorCount()); num(GetCurrentMonitor());
    Vector2 p = GetMonitorPosition(0), q = GetMonitorPosition(5);
    num(fb(p.x)); num(fb(p.y)); num(fb(q.x)); num(fb(q.y));
    num(GetMonitorWidth(0)); num(GetMonitorHeight(0)); num(GetMonitorPhysicalWidth(0)); num(GetMonitorPhysicalHeight(0));
    num(GetMonitorRefreshRate(0)); str(GetMonitorName(0));
    Vector2 w = GetWindowPosition(), d = GetWindowScaleDPI();
    num(fb(w.x)); num(fb(w.y)); num(fb(d.x)); num(fb(d.y));
    num(GetClipboardText() == NULL);
    Image clip = GetClipboardImage(); num(clip.data == NULL); UnloadImage(clip);
    num(IsFileDropped());
    FilePathList files = LoadDroppedFiles(); num(files.count); UnloadDroppedFiles(files);
    str(GetKeyName(KEY_A));
    double t = GetTime(); unsigned long long b; memcpy(&b, &t, 8); num((unsigned)(b >> 32)); num((unsigned)b);
    num(GetWindowHandle() == NULL);
    printf(";");
}

static void scene(int which)
{
    ClearBackground(RAYWHITE);
    if (which == 0) { DrawRectangle(3, 4, 20, 9, RED); DrawCircle(30, 18, 9.0f, BLUE); DrawTriangle((Vector2){ 5, 30 }, (Vector2){ 20, 30 }, (Vector2){ 12, 17 }, GREEN); DrawText("Hi", 26, 2, 10, BLACK); }
    else { DrawRectangle(0, 0, 48, 6, SKYBLUE); DrawRectangleLines(2, 8, 30, 20, MAROON); DrawPixel(45, 30, BLACK); }
}

static void framebuffer(void)
{
    unsigned char *p = malloc(WIDTH*HEIGHT*4);
    rlCopyFramebuffer(0, 0, WIDTH, HEIGHT, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, p);
    printf("F:");
    for (int i = 0; i < WIDTH*HEIGHT; i++) printf("%02x%02x%02x%02x", p[4*i + 2], p[4*i + 1], p[4*i], p[4*i + 3]);
    printf(";");
    free(p);
}

static void screenshot(const char *name)
{
    TakeScreenshot(name);
    int exists = FileExists(name);
    printf("S:%d", exists);
    if (exists)
    {
        Image image = LoadImage(name);
        ImageFormat(&image, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8);
        ImageFlipVertical(&image);
        unsigned char *q = image.data;
        for (int i = 0; i < image.width*image.height; i++) { unsigned char t = q[4*i]; q[4*i] = q[4*i + 2]; q[4*i + 2] = t; }
        const char *dot = strrchr(name, '.');
        char expected[64];
        snprintf(expected, sizeof expected, "expected-%d%s", shots, dot ? dot : "");
        ExportImage(image, expected);
        UnloadImage(image);
        printf(",%d", shots);
    }
    shots++;
    printf(";");
}

int main(void)
{
    SetTraceLogLevel(LOG_NONE);
    probe_clock = START;
    PRECONFIG
    InitWindow(WIDTH, HEIGHT, "window probe");
    Texture2D texture = { 0 };
    OPS
    CloseWindow();
    printf("\n");
    return 0;
}
'''


def c_string(text):
    return '"' + ''.join(c if 32 <= ord(c) < 127 and c not in '"\\?' else f'\\{ord(c):03o}' for c in text) + '"'


def c_op(kind, a, b, c, d, s):
    if kind == QUERY:
        return 'query();'
    if kind == CONFIG:
        return f'SetConfigFlags({a}u);'
    simple = {SET_STATE: f'SetWindowState({a}u);', CLEAR_STATE: f'ClearWindowState({a}u);', FULLSCREEN: 'ToggleFullscreen();',
              BORDERLESS: 'ToggleBorderlessWindowed();', MAXIMIZE: 'MaximizeWindow();', MINIMIZE: 'MinimizeWindow();',
              RESTORE: 'RestoreWindow();', TITLE: f'SetWindowTitle({c_string(s)});', POSITION: f'SetWindowPosition({a}, {b});',
              MONITOR: f'SetWindowMonitor({a});', MIN_SIZE: f'SetWindowMinSize({a}, {b});', MAX_SIZE: f'SetWindowMaxSize({a}, {b});',
              SIZE: f'SetWindowSize({a}, {b});', OPACITY: f'SetWindowOpacity(flt({a}u));', FOCUSED: 'SetWindowFocused();',
              CLIPBOARD: f'SetClipboardText({c_string(s)});', EVENTS_ON: 'EnableEventWaiting();', EVENTS_OFF: 'DisableEventWaiting();',
              CURSOR: f'SetMouseCursor({a});', MAPPINGS: f'printf("M:%d;", SetGamepadMappings({c_string(s)}));',
              VIBRATION: f'SetGamepadVibration({a}, flt({b}u), flt({c}u), flt({d}u));',
              UNLOAD_DROPPED: 'UnloadDroppedFiles(LoadDroppedFiles());',
              ICON: f'{{ Image i = GenImageColor({a}, {b}, RED); SetWindowIcon(i); UnloadImage(i); }}',
              ICONS: f'{{ Image i[{a}]; for (int k = 0; k < {a}; k++) i[k] = GenImageColor(2 + k, 3, BLUE); SetWindowIcons(i, {a}); '
                     f'for (int k = 0; k < {a}; k++) UnloadImage(i[k]); }}'}
    if kind in simple:
        return simple[kind]
    if kind == WAIT:
        # The sleep ends at raylib's destination (GetTime() + seconds, binary64).
        return f'{{ double s = dbl({a}u, {b}u); probe_after = probe_clock + s; WaitTime(s); printf("W;"); }}'
    if kind == BEGIN:
        return f'probe_clock = dbl({a}u, {b}u); BeginDrawing();'
    if kind == END:
        return f'probe_clock = dbl({a}u, {b}u); probe_after = dbl({c}u, {d}u); EndDrawing(); probe_clock = probe_after;'
    if kind == SCENE:
        return f'scene({a});'
    if kind == FRAMEBUFFER:
        return 'framebuffer();'
    if kind == SCREENSHOT:
        return f'screenshot({c_string(s)});'
    if kind == TEXTURE:
        return (f'texture = LoadTexture("{ROOT}/{s}"); if (texture.id == 0) tok("T:null"); '
                'else printf("T:%u,%d,%d,%d,%d;", texture.id, texture.width, texture.height, texture.mipmaps, texture.format);')
    if kind == DRAW_TEXTURE:
        return f'DrawTexture(texture, {a if a < 2**31 else a - 2**32}, {b if b < 2**31 else b - 2**32}, WHITE);'
    if kind == UNLOAD_TEXTURE:
        return 'UnloadTexture(texture); texture = (Texture2D){ 0 };'
    if kind == SCREEN_SPACE:
        return (f'{{ Camera c = {{ {{ 1.5f, 10.0f, 10.0f }}, {{ 0.0f, 0.5f, -1.0f }}, {{ 0.0f, 1.0f, 0.0f }}, 20.0f, {a} }}; '
                'Vector2 p = GetWorldToScreen((Vector3){ 1.0f, 2.0f, 3.0f }, c); Ray r = GetScreenToWorldRay((Vector2){ 10.0f, 20.0f }, c); '
                'printf("P:%u,%u,%u,%u,%u,%u,%u,%u,;", fb(p.x), fb(p.y), fb(r.position.x), fb(r.position.y), fb(r.position.z), '
                'fb(r.direction.x), fb(r.direction.y), fb(r.direction.z)); }')
    if kind == CUBEMAP:
        return (f'{{ Image i = GenImageColor({a}, {b}, RED); TextureCubemap t = LoadTextureCubemap(i, {c}); '
                'printf("C:%u,%d,%d,%d,%d;", t.id, t.width, t.height, t.mipmaps, t.format); UnloadImage(i); }')
    raise ValueError(kind)


def c_program(item):
    ops = item['ops'] if item.get('contract') is None else item['ops'][:item['contract']]
    pre = ''.join(f'SetConfigFlags({f}u);' for f in item['pre'])
    return (C_PROGRAM.replace('FLAGLIST', ', '.join(f'{f}u' for f in FLAGS)).replace('START', repr(item['start']))
            .replace('PRECONFIG', pre).replace('OPS', '\n    '.join(c_op(*o) for o in ops))
            .replace('WIDTH*HEIGHT', f'{W}*{H}').replace('(WIDTH, HEIGHT', f'({W}, {H}').replace('0, WIDTH, HEIGHT', f'0, {W}, {H}'))


def native_tokens(probe, index, item):
    directory = probe.work / f'run-{index}'
    shutil.rmtree(directory, ignore_errors=True)
    directory.mkdir(parents=True)
    source, binary = directory / 'reference.c', directory / 'reference'
    source.write_text(c_program(item))
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-include', ip.SHIM, source, '-I' + str(probe.args.raylib_source / 'src'), probe.library,
                  '-lm', '-o', binary])
    lines = [line for line in probekit.run([binary], cwd=directory).splitlines() if not line.startswith('INFO:')]
    if len(lines) != 1:
        raise ProbeFailure(f'window: native {item["name"]} printed {len(lines)} lines')
    tokens = []
    for token in lines[0].split(';')[:-1]:
        if token.startswith('T:') and token != 'T:null':
            tokens.append(token)
        elif token.startswith('S:'):
            parts = token[2:].split(',')
            if parts[0] == '1':
                name = next(f for f in directory.iterdir() if f.name.startswith(f'expected-{parts[1]}'))
                tokens.append('S:1:' + hashlib.sha256(name.read_bytes()).hexdigest())
            else:
                tokens.append('S:0')
        else:
            tokens.append(token)
    if item.get('contract') is not None:
        tokens.append('null')
    return tokens


# -----------------------------------------------------------------------------
# Candidate

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def float(+w: U32) -> F32:
  U32{x} = w
  F32{x}
def f64(+hi: U32, +lo: U32) -> M.Float64:
  M.Float64{hi, lo}
def signed(+x: U32) -> F32:
  Bool.pick(F32, (x >= 2147483648 : U32), F32.neg(U32.to_f32((0 - x : U32))), U32.to_f32(x))
def num(b: Bool) -> String:
  Bool.pick(String, b, "1,", "0,")
def u(+v: U32) -> String:
  U32.show(v) ++ ","
def fv(v: M.Vector2) -> String:
  M.Vector2{x, y} = v
  u(F32.bits(x)) ++ u(F32.bits(y))
def v3(v: M.Vector3) -> String:
  M.Vector3{x, y, z} = v
  u(F32.bits(x)) ++ u(F32.bits(y)) ++ u(F32.bits(z))
def none.string(m: Maybe<String>) -> String:
  match m:
    case None{}: "1,"
    case Some{_}: "0,"
def none.surface(m: Maybe<J.Surface>) -> String:
  match m:
    case None{}: "1,"
    case Some{_}: "0,"
def none.handle(m: Maybe<Unit>) -> String:
  match m:
    case None{}: "1,"
    case Some{_}: "0,"
def states(+core: J.Core, flags: List<U32>) -> String:
  match flags:
    case Nil{}: ""
    case Con{f, rest}: num(J.Core.is_window_state(core, f)) ++ states(core, rest)
def time(t: M.Float64) -> String:
  M.Float64{hi, lo} = t
  u(hi) ++ u(lo)
def dropped(files: J.FilePathList) -> String:
  J.FilePathList{+count, _} = files
  u(count)
def query(+core: J.Core) -> String:
  num(J.Core.is_window_ready(core)) ++ num(J.Core.is_window_fullscreen(core)) ++ num(J.Core.is_window_hidden(core))
    ++ num(J.Core.is_window_minimized(core)) ++ num(J.Core.is_window_maximized(core)) ++ num(J.Core.is_window_focused(core))
    ++ num(J.Core.is_window_resized(core)) ++ states(core, FLAGLIST)
    ++ u(J.Core.get_screen_width(core)) ++ u(J.Core.get_screen_height(core)) ++ u(J.Core.get_render_width(core)) ++ u(J.Core.get_render_height(core))
    ++ u(J.Core.get_monitor_count(core)) ++ u(J.Core.get_current_monitor(core)) ++ fv(J.Core.get_monitor_position(core, 0)) ++ fv(J.Core.get_monitor_position(core, 5))
    ++ u(J.Core.get_monitor_width(core, 0)) ++ u(J.Core.get_monitor_height(core, 0)) ++ u(J.Core.get_monitor_physical_width(core, 0))
    ++ u(J.Core.get_monitor_physical_height(core, 0)) ++ u(J.Core.get_monitor_refresh_rate(core, 0)) ++ "s:" ++ J.Core.get_monitor_name(core, 0) ++ ","
    ++ fv(J.Core.get_window_position(core)) ++ fv(J.Core.get_window_scale_dpi(core)) ++ none.string(J.Core.get_clipboard_text(core))
    ++ none.surface(J.Core.get_clipboard_image(core)) ++ num(J.Core.is_file_dropped(core)) ++ dropped(J.Core.load_dropped_files(core))
    ++ "s:" ++ J.Input.get_key_name(core, 65) ++ "," ++ time(J.Core.get_time(core)) ++ none.handle(J.Core.get_window_handle(core))
type Op is Data:
  Op{kind: U32, a: U32, b: U32, c: U32, d: U32, s: String}
type Run is Type:
  Run{core: Maybe<J.Core>, frame: J.Frame, texture: Maybe<J.Texture>, out: String}
def put(core: Maybe<J.Core>, frame: J.Frame, texture: Maybe<J.Texture>, out: String) -> IO(Run):
  IO.pure(Run, Run{core, frame, texture, out})
def icons.add(s: Maybe<J.Surface>, rest: List<J.Surface>) -> List<J.Surface>:
  match s:
    case None{}: rest
    case Some{x}: Con{x, rest}
def icons(n: Nat, +k: U32) -> List<J.Surface>:
  match n:
    case 0n: Nil{}
    case 1n+m: icons.add(J.Surface.create((2 + k : U32), 3, 7926271), icons(m, (k + 1 : U32)))
def icon.done(r: J.Core & J.Surface) -> J.Core:
  (core, _) = r
  core
def icon.set(+core: J.Core, s: Maybe<J.Surface>) -> J.Core:
  match s:
    case None{}: core
    case Some{x}: icon.done(J.Core.set_window_icon(core, x))
def icons.done(r: J.Core & List<J.Surface>) -> J.Core:
  (core, _) = r
  core
def mappings(+core: J.Core, +s: String) -> String:
  "M:" ++ U32.show(J.Input.set_gamepad_mappings(core, s)) ++ ";"
# Core-only operations (Some core in, Maybe core out).
def core.op(+kind: U32, +a: U32, +b: U32, +c: U32, +d: U32, +s: String, +core: J.Core) -> Maybe<J.Core>:
  match kind:
    case 1: Some{J.Core.set_config_flags(core, a)}
    case 2: Some{J.Core.set_window_state(core, a)}
    case 3: Some{J.Core.clear_window_state(core, a)}
    case 4: Some{J.Core.toggle_fullscreen(core)}
    case 5: Some{J.Core.toggle_borderless_windowed(core)}
    case 6: Some{J.Core.maximize_window(core)}
    case 7: Some{J.Core.minimize_window(core)}
    case 8: Some{J.Core.restore_window(core)}
    case 9: Some{J.Core.set_window_title(core, s)}
    case 10: Some{J.Core.set_window_position(core, a, b)}
    case 11: Some{J.Core.set_window_monitor(core, a)}
    case 12: Some{J.Core.set_window_min_size(core, a, b)}
    case 13: Some{J.Core.set_window_max_size(core, a, b)}
    case 14: Some{J.Core.set_window_size(core, a, b)}
    case 15: Some{J.Core.set_window_opacity(core, float(a))}
    case 16: Some{J.Core.set_window_focused(core)}
    case 17: Some{J.Core.set_clipboard_text(core, s)}
    case 18: Some{J.Core.enable_event_waiting(core)}
    case 19: Some{J.Core.disable_event_waiting(core)}
    case 20: Some{J.Input.set_mouse_cursor(core, a)}
    case 22: Some{J.Input.set_gamepad_vibration(core, a, float(b), float(c), float(d))}
    case 23: Some{J.Core.unload_dropped_files(core, J.Core.load_dropped_files(core))}
    case 24: Some{icon.set(core, J.Surface.create(a, b, 3861460991))}
    case 25: Some{icons.done(J.Core.set_window_icons(core, icons(U32.to_nat(a), 0)))}
    case 30: J.Core.wait_time(core, f64(a, b))
    case 31: J.Core.begin_drawing(core, f64(a, b))
    case 32: J.Core.end_drawing(core, f64(a, b), f64(c, d))
    case _: Some{core}
def screen.camera(+projection: U32) -> J.Camera3D:
  J.Camera3D{M.Vector3{1.5, 10.0, 10.0}, M.Vector3{0.0, 0.5, F32.neg(1.0)}, M.Vector3{0.0, 1.0, 0.0}, 20.0, projection}
def screen.ray(r: Maybe<J.Ray>) -> String:
  match r:
    case None{}: "null"
    case Some{J.Ray{p, d}}: v3(p) ++ v3(d)
def screen.point(p: Maybe<M.Vector2>) -> String:
  match p:
    case None{}: "null"
    case Some{v}: fv(v)
def screen(+core: J.Core, +projection: U32) -> String:
  +c = screen.camera(projection)
  "P:" ++ screen.point(J.Camera.world_to_screen(M.Vector3{1.0, 2.0, 3.0}, c, core)) ++ screen.ray(J.Camera.screen_to_world_ray(M.Vector2{10.0, 20.0}, c, core)) ++ ";"
def core.text(+kind: U32, +a: U32, +s: String, +core: J.Core) -> String:
  match kind:
    case 0: query(core) ++ ";"
    case 21: mappings(core, s)
    case 47: screen(core, a)
    case _: ""
def scene(+which: U32, frame: J.Frame) -> J.Frame:
  match which:
    case 0:
      f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
      f2 = J.Draw.rectangle(f1, 3.0, 4.0, 20.0, 9.0, J.Color.RED())
      f3 = J.Draw.circle(f2, 30.0, 18.0, 9.0, J.Color.BLUE())
      f4 = J.Draw.triangle(f3, M.Vector2{5.0, 30.0}, M.Vector2{20.0, 30.0}, M.Vector2{12.0, 17.0}, J.Color.GREEN())
      J.Draw.text(f4, "Hi", 26.0, 2.0, 10.0, J.Color.BLACK())
    case _:
      f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
      f2 = J.Draw.rectangle(f1, 0.0, 0.0, 48.0, 6.0, J.Color.SKYBLUE())
      f3 = J.Draw.rectangle_lines(f2, 2.0, 8.0, 30.0, 20.0, J.Color.MAROON())
      J.Draw.pixel(f3, 45.0, 30.0, J.Color.BLACK())
def hex.digit(+d: U32) -> Char:
  Chr{Bool.pick(U32, (d < 10 : U32), (d + 48 : U32), (d + 87 : U32))}
def hex.word(+w: U32, rest: String) -> String:
  SCon{hex.digit((w >> 28n : U32)), SCon{hex.digit(((w >> 24n) .&. 15 : U32)), SCon{hex.digit(((w >> 20n) .&. 15 : U32)),
    SCon{hex.digit(((w >> 16n) .&. 15 : U32)), SCon{hex.digit(((w >> 12n) .&. 15 : U32)), SCon{hex.digit(((w >> 8n) .&. 15 : U32)),
    SCon{hex.digit(((w >> 4n) .&. 15 : U32)), SCon{hex.digit((w .&. 15 : U32)), rest}}}}}}}}
def hex.words(n: Nat, read: Array<U32> & U32, +i: U32, acc: String) -> String:
  match n read:
    case 0n _: acc
    case 1n+k Tuple{a, +w}: hex.words(k, Array.get(U32, a, (i - 1 : U32)), (i - 1 : U32), hex.word(w, acc))
def fb.pixels(+count: U32, pixels: J.Surface.Pixels) -> String:
  match pixels:
    case J.Words{values}: "F:" ++ hex.words(U32.to_nat(count), Array.get(U32, values, (count - 1 : U32)), (count - 1 : U32), "") ++ ";"
    case J.Quads{_}: "quads;"
def fb.surface(s: J.Surface) -> String:
  J.Surface{+w, +h, _, pixels} = s
  fb.pixels((w * h : U32), pixels)
def fb.of(s: Maybe<J.Surface>) -> String:
  match s:
    case None{}: "F:null;"
    case Some{x}: fb.surface(x)
def fb.done(core: Maybe<J.Core>, texture: Maybe<J.Texture>, out: String, r: J.Frame & Maybe<J.Surface>) -> IO(Run):
  (frame, s) = r
  put(core, frame, texture, out ++ fb.of(s))
def info(t: J.TextureInfo) -> String:
  J.TextureInfo{+id, +w, +h, +m, +f} = t
  U32.show(id) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(m) ++ "," ++ U32.show(f)
def tex.info.pair(r: J.Texture & J.TextureInfo) -> J.Texture & String:
  (t, i) = r
  (t, "T:" ++ info(i) ++ ";")
def tex.info(t: J.Texture) -> J.Texture & String:
  tex.info.pair(J.Texture.info(t))
def tex.shown(core: Maybe<J.Core>, frame: J.Frame, out: String, r: J.Texture & String) -> IO(Run):
  (t, text) = r
  put(core, frame, Some{t}, out ++ text)
def tex.loaded(core: Maybe<J.Core>, old: Maybe<J.Texture>, out: String, r: J.Frame & Maybe<J.Texture>) -> IO(Run):
  (frame, t) = r
  match t:
    case None{}: put(core, frame, old, out ++ "T:null;")
    case Some{x}: tex.shown(core, frame, out, tex.info(x))
def tex.drawn(core: Maybe<J.Core>, out: String, r: J.Frame & J.Texture) -> IO(Run):
  (frame, t) = r
  put(core, frame, Some{t}, out)
def tex.draw(core: Maybe<J.Core>, frame: J.Frame, texture: Maybe<J.Texture>, out: String, +x: U32, +y: U32) -> IO(Run):
  match texture:
    case None{}: put(core, frame, None{}, out)
    case Some{t}: tex.drawn(core, out, J.Draw.texture(frame, t, signed(x), signed(y), J.Color.WHITE()))
def tex.unload(core: Maybe<J.Core>, frame: J.Frame, texture: Maybe<J.Texture>, out: String) -> IO(Run):
  match texture:
    case None{}: put(core, frame, None{}, out)
    case Some{t}: put(core, J.Texture.unload(frame, t), None{}, out)
def cube.done(core: Maybe<J.Core>, texture: Maybe<J.Texture>, out: String, r: J.Frame & (J.Surface & J.TextureInfo)) -> IO(Run):
  (frame, pair) = r
  (_, i) = pair
  put(core, frame, texture, out ++ "C:" ++ info(i) ++ ";")
def cube(core: Maybe<J.Core>, frame: J.Frame, texture: Maybe<J.Texture>, out: String, image: Maybe<J.Surface>, +layout: U32) -> IO(Run):
  match image:
    case None{}: put(core, frame, texture, out ++ "C:image;")
    case Some{s}: cube.done(core, texture, out, J.Texture.load_cubemap(frame, s, layout))
def shot.flag(saved: Maybe<Bool>) -> String:
  match saved:
    case None{}: "null"
    case Some{b}: Bool.pick(String, b, "1", "0")
def shot.done(core: Maybe<J.Core>, texture: Maybe<J.Texture>, out: String, +name: String, r: J.Frame & Maybe<Bool>) -> IO(Run):
  (frame, saved) = r
  put(core, frame, texture, out ++ "S:" ++ shot.flag(saved) ++ ":" ++ name ++ ";")
# Frame operations; the core passes through.
def frame.op(+kind: U32, +a: U32, +b: U32, +c: U32, +s: String, core: Maybe<J.Core>, frame: J.Frame, texture: Maybe<J.Texture>, out: String) -> IO(Run):
  match kind:
    case 31: put(core, J.Frame.begin_drawing(frame), texture, out)
    case 32: put(core, J.Frame.end_drawing(frame), texture, out)
    case 40: put(core, scene(a, frame), texture, out)
    case 41: fb.done(core, texture, out, J.Frame.framebuffer(frame))
    case 42: IO.bind(J.Frame & Maybe<Bool>, Run, J.Frame.take_screenshot(frame, PREFIX ++ s), r => shot.done(core, texture, out, s, r))
    case 43: IO.bind(J.Frame & Maybe<J.Texture>, Run, J.Texture.load(frame, s), r => tex.loaded(core, texture, out, r))
    case 44: tex.draw(core, frame, texture, out, a, b)
    case 45: tex.unload(core, frame, texture, out)
    case 46: cube(core, frame, texture, out, J.Surface.create(a, b, 3861460991), c)
    case _: put(core, frame, texture, out)
def core.after(+kind: U32, core: Maybe<J.Core>, +out: String) -> Maybe<J.Core> & String:
  match core:
    case None{}: (None{}, out ++ "null;")
    case Some{+x}: (Some{x}, Bool.pick(String, U32.is_eq(kind, 30), out ++ "W;", out))
def core.step.with(+kind: U32, +a: U32, +b: U32, +c: U32, +d: U32, +s: String, core: Maybe<J.Core>, out: String) -> Maybe<J.Core> & String:
  match core:
    case None{}: (None{}, out)
    case Some{+x}: core.after(kind, core.op(kind, a, b, c, d, s, x), out ++ core.text(kind, a, s, x))
def core.step(+op: Op, core: Maybe<J.Core>, out: String) -> Maybe<J.Core> & String:
  Op{+kind, +a, +b, +c, +d, +s} = op
  core.step.with(kind, a, b, c, d, s, core, out)
def step.parts(+kind: U32, +a: U32, +b: U32, +c: U32, +s: String, frame: J.Frame, texture: Maybe<J.Texture>, stepped: Maybe<J.Core> & String) -> IO(Run):
  (core, out) = stepped
  frame.op(kind, a, b, c, s, core, frame, texture, out)
def step.with(+op: Op, frame: J.Frame, texture: Maybe<J.Texture>, stepped: Maybe<J.Core> & String) -> IO(Run):
  Op{+kind, +a, +b, +c, _, +s} = op
  step.parts(kind, a, b, c, s, frame, texture, stepped)
def step(+op: Op, run: Run) -> IO(Run):
  Run{core, frame, texture, out} = run
  step.with(op, frame, texture, core.step(op, core, out))
def ops(list: +List<Op>, run: Run) -> IO(Run):
  match list:
    case Nil{}: IO.pure(Run, run)
    case Con{+o, rest}: IO.bind(Run, Run, step(o, run), r => ops(rest, r))
def finish(run: Run) -> IO(Unit):
  Run{_, _, _, out} = run
  IO.print(out)
def start(list: +List<Op>, core: Maybe<J.Core>, frame: Maybe<J.Frame>) -> IO(Unit):
  match frame:
    case None{}: IO.print("no frame")
    case Some{f}: IO.bind(Run, Unit, ops(list, Run{core, f, None{}, ""}), finish)
'''


def bend_string(text):
    return json.dumps(text)


def bend_ops(ops):
    return '[' + ', '.join(f'Op{{{k}, {a}, {b}, {c}, {d}, {bend_string(s)}}}' for k, a, b, c, d, s in ops) + ']'


# Frame operations whose code (the image codecs behind LoadTexture, the
# exporters behind TakeScreenshot) is compiled only into the batch that uses
# them: one program with every codec exceeds the compile budget on a loaded host.
HEAVY = (SCREENSHOT, TEXTURE, DRAW_TEXTURE, UNLOAD_TEXTURE, CUBEMAP)


def render(items):
    def emit(selected, gpu):
        used = {o[0] for index in selected for o in items[index]['ops']}
        body = PROGRAM.replace('FLAGLIST', '[' + ', '.join(str(f) for f in FLAGS) + ']').replace('PREFIX', bend_string('.build/window-probe/jonlib-'))
        body = '\n'.join(line for line in body.split('\n')
                         if not any(line.startswith(f'    case {kind}: ') and kind not in used for kind in HEAVY))
        for index in selected:
            item = items[index]
            flags = 0
            for f in item['pre']:
                flags |= f
            start = dbits(item['start'])
            body += (f'def script.{index}() -> IO(Unit):\n'
                     f'  start({bend_ops(item["ops"])}, J.Core.init_window_flags({flags}, {W}, {H}, f64({start >> 32}, {start & 0xFFFFFFFF})), '
                     f'J.Frame.init_window_flags({flags}, {W}, {H}))\n')
        body += 'def main() -> IO(Unit):\n  do IO<Unit>:\n'
        for index in selected:
            body += f'    Unit <- script.{index}()\n'
        return body + '    IO.print("done")\n'
    return emit


def candidate_tokens(line, index, items, probe):
    tokens = []
    for token in line.split(';')[:-1]:
        if token.startswith('S:'):
            flag, name = token[2:].split(':', 1)
            path = probe.work / f'jonlib-{name}'
            if flag == '1':
                tokens.append('S:1:' + hashlib.sha256(path.read_bytes()).hexdigest())
            else:
                tokens.append('S:' + flag)
            if path.exists():
                path.unlink()
        else:
            tokens.append(token)
    return tokens


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('window', args, raylib_options=ip.OPTIONS)
    definitions = ip.variant_definitions(probe.library)
    wanted = dict(SUPPORT_CUSTOM_FRAME_CONTROL=False, SUPPORT_BUSY_WAIT_LOOP=False, SUPPORT_PARTIALBUSY_WAIT_LOOP=True,
                  SUPPORT_AUTOMATION_EVENTS=True, SUPPORT_GESTURES_SYSTEM=True, SUPPORT_SCREEN_CAPTURE=True)
    if definitions != wanted:
        raise ProbeFailure(f'window: reference build definitions {definitions}, expected {wanted}')
    paths = fixtures(probe.work)
    items = scripts(paths)
    expected = [native_tokens(probe, index, item) for index, item in enumerate(items)]
    for leftover in probe.work.glob('jonlib-*'):
        leftover.unlink()

    def parse_lane(text, selected, lane):
        rows = [line for line in text.splitlines() if line.strip()]
        if rows[-1:] != ['done'] or len(rows) != len(selected) + 1:
            raise ProbeFailure(f'window: {lane} output did not finish')
        return [candidate_tokens(line, index, items, probe) for line, index in zip(rows[:-1], selected)]

    # Three programs: the plain scripts, the texture-file scripts and the screenshots.
    heavy = lambda i, kinds: any(o[0] in kinds for o in items[i]['ops'])
    groups = [[i for i in range(len(items)) if not heavy(i, HEAVY)],
              [i for i in range(len(items)) if heavy(i, (TEXTURE, CUBEMAP)) and not heavy(i, (SCREENSHOT,))],
              [i for i in range(len(items)) if heavy(i, (SCREENSHOT,))]]
    order = [i for group in groups for i in group]
    if sorted(order) != list(range(len(items))):
        raise ProbeFailure('window: scripts are not partitioned')
    lanes = {}
    for group in groups:
        rows = probe.candidates(render(items), group, batch=len(group), parse_lane=parse_lane)
        for lane, values in rows.items():
            lanes.setdefault(lane, [None] * len(items))
            for index, value in zip(group, values):
                lanes[lane][index] = value
    lanes = {lane: rows for lane, rows in lanes.items() if lane != 'gpu'}

    def describe(index):
        rows = next(iter(lanes.values()))[index]
        token = next((k for k, (a, b) in enumerate(zip(expected[index], rows)) if a != b), min(len(rows), len(expected[index])))
        return f'script {items[index]["name"]} token {token}'

    probe.compare(expected, lanes, describe=describe)
    probe.finish(scripts=len(items), operations=sum(len(item['ops']) for item in items),
                 contracts=sum(item.get('contract') is not None for item in items),
                 screenshots=sum(t.startswith('S:1') for row in expected for t in row),
                 scripts_sha256=hashlib.sha256(json.dumps(items).encode()).hexdigest())


if __name__ == '__main__':
    main()
