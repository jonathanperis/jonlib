#!/usr/bin/env python3
"""Replay Jonlib's example programs headless against the unmodified raylib
examples, frame by frame and byte for byte.

Reference. Each raylib example source (examples/<module>/<name>.c of the
pinned checkout, not modified) is compiled with
"-include tools/reference/example_driver.h", which renames InitWindow,
WindowShouldClose, BeginDrawing and EndDrawing in its translation unit to the
hooks of this probe's driver (C_DRIVER below), and linked with the
clock-injected memory-platform raylib of tools/input_probe.py
(-ffp-contract=off, tools/reference/input_clock.h, config.h's frame control).
The hooks read a script (JONLIB_EXAMPLE_SCRIPT): InitWindow sets the scripted
clock and then SetRandomSeed(seed) (raylib seeds from time(NULL));
WindowShouldClose plays the next frame's automation events with
PlayAutomationEvent and answers the real WindowShouldClose (the loop ends
after the last scripted frame); BeginDrawing and EndDrawing set the frame's
clocks (a SetTargetFPS wait ends at the scripted `after`, computed in
binary64 as raylib computes its destination) and EndDrawing prints the color
buffer read with rlCopyFramebuffer (top-down, BGRA swapped to RGBA) as runs of
0xRRGGBBAA words. Each script runs in a fresh process (stdin /dev/null for
the memory platform's ESC check), textures_logo_raylib from
examples/textures so that its relative resource path loads the pinned
raylib_logo.png (the asset is read in place, never copied).

Candidate. examples/<name>.bend's Program, replayed by J.Program.replay with
the same events and clocks (setup as the example's InitWindow and
SetTargetFPS, the same seed). Per frame it prints J.Frame.framebuffer as the
same runs and J.Frame.present's quadtree Image in preorder ("q" for Qua,
"p<color>" for Pix): the framebuffer must equal raylib's, and the Image must
equal the one built here from raylib's bytes (0x00RRGGBB colors, squares past
the edges Pix 0, uniform quads collapsed), so what the desktop driver
presents is raylib's frame.

Contracts (Jonlib must answer "null null" from the stated frame on): a mouse
wheel move in core_2d_camera (its zoom needs expf/logf, without an M.Libm
profile), camera rotations outside the host profile's verified sinf/cosf
arguments (the Apple profile refuses 13, 19 and 22 degrees), and every frame
of shapes_basic_shapes (DrawPoly turning by 0.2 degrees evaluates sinf/cosf
outside every verified set). Frames before a refusal are compared with
raylib. The refusals are computed for the host's M.Libm profile (Apple on
macOS, glibc 2.39 on glibc hosts, conformance.gradient_reference): the
13-degree rotation is a contract on macOS and compared on Linux. Native code
only runs what C defines: the wheel and rotation scripts are defined in C
(raylib computes expf/logf and sinf/cosf), and shapes_basic_shapes, refused
from its first frame, is not run natively. CPU-1, CPU-2 and JavaScript lanes.

--interactive (diagnostic, needs a desktop session) instead builds each
example and runs it in a Base window for --frames frames on CPU-1 and CPU-2,
recording the frame rates the driver reports.
"""
import hashlib
import json
import math
import os
import platform
import re
import shutil
import struct
import subprocess

from conformance import gradient_reference
import frame_probe as fp
import input_probe as ip
import probekit
from probekit import ROOT, ProbeFailure

SHIM = ROOT / 'tools/reference/example_driver.h'
WIDTH, HEIGHT = 800, 450
TARGET = 1.0 / 60

(KEY_UP_EVENT, KEY_DOWN_EVENT, MOUSE_UP, MOUSE_DOWN, MOUSE_POSITION, MOUSE_WHEEL, WINDOW_CLOSE) = (1, 2, 5, 6, 7, 8, 18)
KEY_RIGHT, KEY_LEFT, KEY_DOWN, KEY_UP, KEY_A, KEY_H, KEY_R, KEY_S = 262, 263, 264, 265, 65, 72, 82, 83
KEY_G, KEY_SPACE, KEY_C, KEY_ENTER = 71, 32, 67, 257

# name: (raylib source, setup expression, State is Data, needs the logo image)
EXAMPLES = {
    'core_basic_window': ('core/core_basic_window.c', 'Ex.setup(core, frame)'),
    'core_input_keys': ('core/core_input_keys.c', 'Ex.setup(core, frame)'),
    'core_input_mouse': ('core/core_input_mouse.c', 'Ex.setup(core, frame)'),
    'core_2d_camera': ('core/core_2d_camera.c', 'Ex.setup(seed, core, frame)'),
    'shapes_logo_raylib': ('shapes/shapes_logo_raylib.c', 'Ex.setup(core, frame)'),
    'textures_logo_raylib': ('textures/textures_logo_raylib.c', 'Ex.setup(Ex.image(logo), core, frame)'),
    'shapes_basic_shapes': ('shapes/shapes_basic_shapes.c', 'Ex.setup(core, frame)'),
    'textures_srcrec_dstrec': ('textures/textures_srcrec_dstrec.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_sprite_animation': ('textures/textures_sprite_animation.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_background_scrolling': ('textures/textures_background_scrolling.c', 'Ex.setup(RESOURCES, core, frame)'),
    'core_drop_files': ('core/core_drop_files.c', 'Ex.setup(core, frame)'),
    'shapes_bouncing_ball': ('shapes/shapes_bouncing_ball.c', 'Ex.setup(core, frame)'),
    'shapes_lines_bezier': ('shapes/shapes_lines_bezier.c', 'Ex.setup(core, frame)'),
    'shapes_colors_palette': ('shapes/shapes_colors_palette.c', 'Ex.setup(core, frame)'),
    'shapes_logo_raylib_anim': ('shapes/shapes_logo_raylib_anim.c', 'Ex.setup(core, frame)'),
    'shapes_rectangle_scaling': ('shapes/shapes_rectangle_scaling.c', 'Ex.setup(core, frame)'),
    'shapes_collision_area': ('shapes/shapes_collision_area.c', 'Ex.setup(core, frame)'),
    'shapes_dashed_line': ('shapes/shapes_dashed_line.c', 'Ex.setup(core, frame)'),
    'shapes_mouse_trail': ('shapes/shapes_mouse_trail.c', 'Ex.setup(core, frame)'),
    'shapes_lines_drawing': ('shapes/shapes_lines_drawing.c', 'Ex.setup(core, frame)'),
    'shapes_rlgl_triangle': ('shapes/shapes_rlgl_triangle.c', 'Ex.setup(core, frame)'),
    'shapes_starfield_effect': ('shapes/shapes_starfield_effect.c', 'Ex.setup(seed, core, frame)'),
    'text_writing_anim': ('text/text_writing_anim.c', 'Ex.setup(core, frame)'),
    'text_format_text': ('text/text_format_text.c', 'Ex.setup(core, frame)'),
    'text_input_box': ('text/text_input_box.c', 'Ex.setup(core, frame)'),
    'core_input_mouse_wheel': ('core/core_input_mouse_wheel.c', 'Ex.setup(core, frame)'),
    'core_scissor_test': ('core/core_scissor_test.c', 'Ex.setup(core, frame)'),
    'core_random_values': ('core/core_random_values.c', 'Ex.setup(seed, core, frame)'),
    'core_render_texture': ('core/core_render_texture.c', 'Ex.setup(core, frame)'),
    'core_delta_time': ('core/core_delta_time.c', 'Ex.setup(core, frame)'),
    'core_3d_camera_mode': ('core/core_3d_camera_mode.c', 'Ex.setup(core, frame)'),
    'core_3d_camera_free': ('core/core_3d_camera_free.c', 'Ex.setup(core, frame)'),
    'core_world_screen': ('core/core_world_screen.c', 'Ex.setup(core, frame)'),
    'core_3d_picking': ('core/core_3d_picking.c', 'Ex.setup(core, frame)'),
    'models_basic_voxel': ('models/models_basic_voxel.c', 'Ex.setup(core, frame)'),
    'models_rotating_cube': ('models/models_rotating_cube.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_image_loading': ('textures/textures_image_loading.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_image_rotate': ('textures/textures_image_rotate.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'textures_to_image': ('textures/textures_to_image.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_blend_modes': ('textures/textures_blend_modes.c', 'Ex.setup(RESOURCES, core, frame)'),
}

# Examples whose setup is IO (LoadTexture: Ex.setup(dir, core, frame) with raylib's
# examples/<module>/ directory) and the flags SetConfigFlags sets before InitWindow.
IO_SETUP = {'textures_srcrec_dstrec', 'textures_sprite_animation', 'textures_background_scrolling', 'models_rotating_cube',
            'textures_image_loading', 'textures_image_rotate', 'textures_to_image', 'textures_blend_modes'}
# Examples whose setup takes the script's seed (GetRandomValue after InitWindow's SetRandomSeed).
# Examples drawing through a perspective camera from their first frame: BeginMode3D's binary64 tan has no
# AppleLibm profile (docs/PERSPECTIVE.md), so on macOS every frame is a contract and nothing runs natively.
PERSPECTIVE = {'core_3d_camera_mode', 'core_3d_camera_free', 'core_world_screen', 'core_3d_picking', 'models_basic_voxel', 'models_rotating_cube'}
SEEDED = {'core_2d_camera', 'shapes_starfield_effect', 'core_random_values'}
CONFIG_FLAGS = {'shapes_bouncing_ball': 32, 'shapes_lines_bezier': 32, 'shapes_rlgl_triangle': 32}


# -----------------------------------------------------------------------------
# Scripts: frames of (automation events, gap before BeginDrawing, draw time)

def key(code, down=True):
    return (KEY_DOWN_EVENT if down else KEY_UP_EVENT, code, 0, 0)


def mouse_at(x, y):
    return (MOUSE_POSITION, x, y, 0)


def button(index, down=True):
    return (MOUSE_DOWN if down else MOUSE_UP, index, 0, 0)


def script(example, name, frames, seed=0, start=0.25):
    return dict(example=example, name=f'{example}-{name}', frames=frames, seed=seed, start=start)


def quick(events=()):
    """A frame shorter than the 60 FPS target: EndDrawing waits."""
    return (list(events), 0.002, 0.004)


def slow(events=()):
    """A frame longer than the target: no wait."""
    return (list(events), 0.003, 0.021)


def scripts():
    out = [
        script('core_basic_window', 'frames', [quick(), slow(), quick()]),
        script('core_basic_window', 'close', [quick(), quick(), quick([(WINDOW_CLOSE, 0, 0, 0)]), quick()]),
        script('core_input_keys', 'arrows', [quick(), quick([key(KEY_RIGHT)]), slow(), quick([key(KEY_UP)]), quick([key(KEY_RIGHT, False)]),
                                             slow([key(KEY_LEFT), key(KEY_DOWN)]), quick([key(KEY_UP, False)]), quick(),
                                             quick([key(KEY_LEFT, False), key(KEY_DOWN, False)]), quick([key(KEY_RIGHT), key(KEY_LEFT)])]),
        script('core_input_keys', 'close', [quick([key(KEY_DOWN)]), quick([(WINDOW_CLOSE, 0, 0, 0)]), quick()]),
        script('core_input_mouse', 'buttons', [quick(), quick([mouse_at(120, 80)]), quick([button(0)]), slow([mouse_at(300, 200), button(0, False)]),
                                               quick([button(2)]), quick([button(1), mouse_at(799, 449)]), quick([button(3), button(1, False)]),
                                               quick([button(4)]), quick([button(5), mouse_at(0, 0)]), quick([button(6)]),
                                               quick([key(KEY_H), mouse_at(400, 300)]), quick([key(KEY_H, False)]), quick([key(KEY_H)]),
                                               quick([mouse_at(-30, 500)])]),
        script('core_2d_camera', 'move-rotate', [quick(), quick([key(KEY_RIGHT)]), quick(), slow([key(KEY_RIGHT, False), key(KEY_LEFT)]),
                                                 quick([key(KEY_LEFT, False), key(KEY_S)]), quick(), quick(), quick([key(KEY_S, False), key(KEY_A)]),
                                                 quick(), quick([key(KEY_A, False), key(KEY_R)]), quick([key(KEY_R, False), key(KEY_A)]),
                                                 slow(), quick([key(KEY_A, False)])], seed=0x5EED),
        script('core_2d_camera', 'seed', [quick(), quick([key(KEY_LEFT)])], seed=1234567),
        script('core_2d_camera', 'wheel', [quick(), quick([key(KEY_RIGHT)]), quick([(MOUSE_WHEEL, 0, 1, 0)]), quick(), quick([key(KEY_R)])],
               seed=77),
        script('core_2d_camera', 'rotate-13', [quick([key(KEY_S)])] + [quick() for _ in range(13)] + [quick([key(KEY_S, False), key(KEY_R)])],
               seed=99),
        script('shapes_logo_raylib', 'frames', [quick(), slow()]),
        script('textures_logo_raylib', 'frames', [quick(), slow()]),
        script('shapes_basic_shapes', 'refused', [quick(), quick()]),
        script('textures_srcrec_dstrec', 'rotate', [quick() for _ in range(14)] + [slow()]),
        script('textures_sprite_animation', 'speed', [quick(), quick(), slow(), quick([key(KEY_RIGHT)]), quick(), quick([key(KEY_RIGHT, False)]),
                                                      quick([key(KEY_LEFT)]), quick([key(KEY_LEFT, False)]), quick(), slow(), quick(), quick()]),
        script('textures_background_scrolling', 'scroll', [quick(), slow(), quick(), quick()]),
        script('core_drop_files', 'frames', [quick(), slow(), quick([(WINDOW_CLOSE, 0, 0, 0)]), quick()]),
        script('shapes_bouncing_ball', 'keys', [quick(), quick(), slow(), quick([key(KEY_G)]), quick([key(KEY_G, False)]), quick(),
                                                quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]), quick(), slow(), quick([key(KEY_SPACE)]),
                                                quick([key(KEY_SPACE, False), key(KEY_G)]), quick()]),
        script('shapes_lines_bezier', 'drag', [quick(), quick([mouse_at(31, 28)]), quick([button(0)]), quick([mouse_at(120, 200)]),
                                               slow([mouse_at(400, 100), button(0, False)]), quick([mouse_at(765, 425)]), quick([button(0)]),
                                               quick([mouse_at(600, 300)]), quick([mouse_at(-20, 500)])]),
        script('shapes_colors_palette', 'hover', [quick(), quick([mouse_at(50, 100)]), slow(), quick([key(KEY_SPACE)]), quick([mouse_at(400, 250)]),
                                                  quick([key(KEY_SPACE, False)]), quick([mouse_at(129, 120)]), quick([mouse_at(130, 120)]),
                                                  quick([mouse_at(790, 440)]), quick([mouse_at(-5, -5)])]),
        # Every state: the blinking box (120 frames), both bar pairs (60 each), ten letters and the
        # fade to state 4, then R replays from state 0.
        script('shapes_logo_raylib_anim', 'replay', [quick() for _ in range(420)] + [quick([key(KEY_R)]), quick([key(KEY_R, False)]), quick(), quick(), quick()]),
        script('shapes_rectangle_scaling', 'drag', [quick(), quick([mouse_at(250, 150)]), quick([mouse_at(295, 175)]), quick([button(0)]),
                                                    quick([mouse_at(500, 300)]), slow([mouse_at(50, 50)]), quick([mouse_at(900, 600)]),
                                                    quick([mouse_at(640, 333)]), quick([button(0, False)]), quick([mouse_at(400, 200)]),
                                                    quick([button(0)]), quick([button(0, False)])]),
        script('shapes_collision_area', 'overlap', [quick(), quick([mouse_at(120, 220)]), quick(), slow([mouse_at(215, 260)]),
                                                    quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]), quick([mouse_at(90, 180)]), quick(),
                                                    quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False), mouse_at(700, 30)]),
                                                    quick([mouse_at(790, 445)]), quick([mouse_at(5, 5)])]),
        # boxA reaches the right edge after 148 frames and bounces back.
        script('shapes_collision_area', 'bounce', [quick([mouse_at(400, 300)])] + [quick() for _ in range(169)]),
        # The dash length falls to its floor of 1 while DOWN is held; C wraps through all 8 colors.
        script('shapes_dashed_line', 'controls', [quick(), quick([mouse_at(400, 300)]), quick([key(KEY_UP)]), quick(), slow([key(KEY_UP, False)]),
                                                  quick([key(KEY_DOWN)])] + [quick() for _ in range(30)]
               + [quick([key(KEY_DOWN, False), key(KEY_RIGHT)]), quick(), quick([key(KEY_RIGHT, False), key(KEY_LEFT)])] + [quick() for _ in range(18)]
               + [quick([key(KEY_LEFT, False)])] + [f([key(KEY_C, i % 2 == 0)]) for i, f in enumerate([quick] * 18)]
               + [quick([mouse_at(20, 50)]), quick([mouse_at(-40, 500)])]),
        # A 36-step path fills the 30 positions; the mouse then rests at (0, 0), which the trail skips.
        script('shapes_mouse_trail', 'path', [quick()] + [quick([mouse_at(100 + 17 * i, 80 + (i * 37) % 300)]) for i in range(36)]
               + [quick([mouse_at(0, 0)]), quick(), slow()]),
        # Paint (long strokes wrap the hue past 360), erase with the right button, change the thickness with the
        # wheel and clear with the middle button.
        script('shapes_lines_drawing', 'paint', [quick(), quick([mouse_at(300, 200)]), quick([button(0)]), quick([mouse_at(340, 230)]),
                                                 quick([mouse_at(750, 400)]), quick([mouse_at(50, 50)]), slow([mouse_at(760, 420)]),
                                                 quick([mouse_at(60, 40)]), quick([button(0, False)]), quick([mouse_at(400, 220)]),
                                                 quick([button(1)]), quick([mouse_at(420, 260)]), quick([button(1, False)]),
                                                 quick([(MOUSE_WHEEL, 0, 3, 0)]), quick([button(0), mouse_at(200, 300)]), quick([mouse_at(260, 330)]),
                                                 quick([button(0, False), (MOUSE_WHEEL, 0, -20, 0)]), quick([button(2)]), quick([button(2, False)]),
                                                 quick([mouse_at(500, 100)])]),
        # Drag a vertex, toggle lines, then drag vertex 1 past vertex 2 (the triangle turns back-facing) with the
        # culling disabled and enabled again, and reset with R.
        script('shapes_rlgl_triangle', 'drag', [quick(), quick([mouse_at(402, 152)]), quick([button(0)]), quick([mouse_at(420, 120)]),
                                                quick([mouse_at(450, 100)]), quick([button(0, False)]), quick([key(KEY_SPACE)]),
                                                quick([key(KEY_SPACE, False)]), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False), mouse_at(300, 300)]),
                                                quick([button(0)]), quick([mouse_at(600, 320)]), quick([button(0, False), key(KEY_RIGHT)]),
                                                quick([key(KEY_RIGHT, False)]), quick([key(KEY_LEFT)]), quick([key(KEY_LEFT, False)]),
                                                quick([key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False), key(KEY_R)]), quick([key(KEY_R, False)])]),
        # The wheel clamps the speed at 2 on the second frame, so stars pass the viewer (z < 0) and respawn within
        # about 30 frames; SPACE switches to circles and back; a large negative move resets the speed to 0.1.
        # (The JavaScript lane needs about 9 s a frame for 420 stars.)
        script('shapes_starfield_effect', 'fly', [quick(), quick([(MOUSE_WHEEL, 0, 9, 0)])] + [quick() for _ in range(30)]
               + [quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]), slow([(MOUSE_WHEEL, 0, -30, 0)]), quick(),
                  quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)])], seed=0x57A2),
        # SPACE reveals the whole message (72 characters, 8 counts a frame), ENTER restarts it.
        script('text_writing_anim', 'reveal', [quick() for _ in range(10)] + [quick([key(KEY_SPACE)])] + [quick() for _ in range(48)]
               + [quick([key(KEY_SPACE, False)]), quick([key(KEY_ENTER)]), quick([key(KEY_ENTER, False)]), slow(), quick()]),
        script('text_format_text', 'frames', [quick(), slow(), quick(), slow([key(KEY_SPACE)])]),
        # Replayed events never reach GetCharPressed's queue (raylib's PlayAutomationEvent fills key states only), so
        # the name stays empty: hover, the caret blink, BACKSPACE and leaving the box.
        script('text_input_box', 'hover', [quick(), quick([mouse_at(350, 200)])] + [quick() for _ in range(44)]
               + [quick([key(259)]), quick([key(259, False), key(KEY_A)]), quick([key(KEY_A, False), mouse_at(600, 300)]), quick(),
                  quick([mouse_at(524, 229)]), slow()]),
        # The wheel moves the box both ways, then 60 notches up take it above the screen (a negative %03i).
        script('core_input_mouse_wheel', 'scroll', [quick(), quick([(MOUSE_WHEEL, 0, 1, 0)]), quick(), slow([(MOUSE_WHEEL, 0, 3, 0)]),
                                                    quick([(MOUSE_WHEEL, 0, -2, 0)]), quick([(MOUSE_WHEEL, 0, 60, 0)]), quick(),
                                                    quick([(MOUSE_WHEEL, 0, -20, 0)])]),
        script('core_scissor_test', 'reveal', [quick(), quick([mouse_at(400, 210)]), quick([mouse_at(250, 230)]), slow([key(KEY_S)]),
                                               quick([key(KEY_S, False)]), quick([key(KEY_S)]), quick([key(KEY_S, False), mouse_at(50, 50)]),
                                               quick([mouse_at(790, 440)]), quick([mouse_at(401, 199)])]),
        # Two new values, at frames 120 and 240.
        script('core_random_values', 'rolls', [quick() for _ in range(245)], seed=0xD1CE),
        script('core_random_values', 'seed', [quick(), slow()], seed=42),
        # The ball bounces off the right edge at frame 26 and the bottom at frame 32 while the texture turns.
        script('core_render_texture', 'spin', [quick() for _ in range(34)] + [slow(), quick()]),
        # The wheel changes the target (61, unlimited at 0 or below, then 90); R resets the circles. Targets below 60
        # are not scripted: the frozen scripted clock would never reach raylib's later busy-wait destination.
        script('core_delta_time', 'targets', [quick(), slow(), quick([(MOUSE_WHEEL, 0, 1, 0)]), quick(), slow(), quick([(MOUSE_WHEEL, 0, -70, 0)]),
                                              quick(), slow(), quick([(MOUSE_WHEEL, 0, 90, 0)]), quick(), slow([key(KEY_R)]), quick([key(KEY_R, False)])]),
        script('core_3d_camera_mode', 'frames', [quick(), slow(), quick()]),
        # Mouse look, wheel zoom, a middle-button pan and Z back to the origin.
        script('core_3d_camera_free', 'controls', [quick(), quick([mouse_at(410, 230)]), quick([mouse_at(450, 210)]), slow([mouse_at(380, 260)]),
                                                   quick([(MOUSE_WHEEL, 0, 2, 0)]), quick([(MOUSE_WHEEL, 0, -1, 0)]), quick([button(2)]),
                                                   quick([mouse_at(420, 250)]), quick([mouse_at(470, 280), button(2, False)]), quick([key(90)]),
                                                   quick([key(90, False)]), quick()]),
        # Third-person mouse look and W/A/S/D moves; the label follows the cube's projection.
        script('core_world_screen', 'orbit', [quick(), quick([mouse_at(420, 230)]), quick([mouse_at(470, 215)]), slow([key(87)]), quick(),
                                              quick([key(87, False), key(68)]), quick(), quick([key(68, False), key(83), mouse_at(380, 240)]),
                                              quick([key(83, False), key(65)]), quick([key(65, False)]), quick()]),
        # Select the cube, deselect it, miss it (the ray stays drawn), then toggle first-person controls and look around.
        script('core_3d_picking', 'pick', [quick(), quick([mouse_at(400, 220)]), quick([button(0)]), quick([button(0, False)]), quick([button(0)]),
                                           quick([button(0, False), mouse_at(120, 90)]), quick([button(0)]), quick([button(0, False)]),
                                           quick([button(1)]), quick([button(1, False), mouse_at(140, 100)]), quick([mouse_at(170, 95)]),
                                           slow([key(87)]), quick([key(87, False), button(1)]), quick([button(1, False)]), quick()]),
        # 512 cubes a frame. The camera starts level (y 0 looking at y 0): a ray with a zero y component makes
        # GetRayCollisionBox's (int) normal cast undefined for the missed boxes, which Jonlib refuses, so the
        # mouse first tilts the view (the cursor is disabled at the center); then a click removes the voxel at
        # the screen center and the camera steps forward.
        script('models_basic_voxel', 'dig', [quick(), quick([mouse_at(400, 240)]), quick([button(0)]), quick([button(0, False), mouse_at(420, 236)]),
                                             slow([key(87)]), quick([key(87, False)])]),
        script('models_rotating_cube', 'turn', [quick() for _ in range(6)] + [slow(), quick()]),
        script('textures_image_loading', 'frames', [quick(), slow()]),
        script('textures_image_rotate', 'cycle', [quick(), quick([button(0)]), quick([button(0, False)]), quick([key(KEY_RIGHT)]),
                                                  quick([key(KEY_RIGHT, False), button(0)]), quick([button(0, False)])]),
        script('textures_to_image', 'frames', [quick(), slow()]),
        script('textures_blend_modes', 'cycle', [quick(), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]), quick([key(KEY_SPACE)]),
                                                 quick([key(KEY_SPACE, False)]), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]),
                                                 quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)])]),
    ]
    return [timed(item) for item in out]


# The C driver's script capacity (MAX_FRAMES, MAX_EVENTS in C_DRIVER below).
MAX_FRAMES, MAX_EVENTS = 1024, 64


def timed(item):
    """Scripted clocks: BeginDrawing after the frame's gap, EndDrawing after its
    draw time, and the end of a SetTargetFPS wait exactly at raylib's
    destination (binary64, as rcore.c's EndDrawing and WaitTime compute it)."""
    if len(item['frames']) >= MAX_FRAMES or any(len(events) > MAX_EVENTS for events, _, _ in item['frames']):
        raise ProbeFailure(f'examples: {item["name"]} exceeds the driver\'s {MAX_FRAMES - 1} frames or {MAX_EVENTS} events per frame')
    previous = item['start']
    frames = []
    for events, gap, draw in item['frames']:
        begin = previous + gap
        update = begin - previous
        end = begin + draw
        frame = update + (end - begin)
        after = end + (TARGET - frame) if frame < TARGET else end
        frames.append(dict(events=events, begin=begin, end=end, after=after))
        previous = after
    return dict(item, frames=frames)


# -----------------------------------------------------------------------------
# Contract predictions

def refusal(item, libm):
    """The index of the first frame Jonlib refuses (None when none is)."""
    if item['example'] in PERSPECTIVE and libm == 'AppleLibm':
        return 0
    if item['example'] == 'shapes_basic_shapes':
        rotation = 0.0
        for index in range(len(item['frames'])):
            rotation = fp.f32(rotation + fp.f32(0.2))
            central, step = fp.f32(rotation * fp.DEG2RAD), fp.f32(fp.f32(360.0 / 6.0) * fp.DEG2RAD)
            angles = [central]
            for _ in range(6):
                central = fp.f32(central + step)
                angles.append(central)
            if not all(fp.accepted(libm, a) for a in angles):
                return index
        raise ProbeFailure('examples: shapes_basic_shapes is expected to be refused')
    if item['example'] == 'textures_srcrec_dstrec':
        # DrawTexturePro's sinf/cosf of (float)rotation*DEG2RAD, rotation = frame + 1.
        for index in range(len(item['frames'])):
            if not fp.accepted(libm, fp.f32(float(index + 1) * fp.DEG2RAD)):
                return index
        return None
    if item['example'] == 'core_render_texture':
        # DrawTexturePro's sinf/cosf of rotation*DEG2RAD, rotation = 0.5*(frame + 1) degrees.
        for index in range(len(item['frames'])):
            if not fp.accepted(libm, fp.f32(fp.f32(0.5 * (index + 1)) * fp.DEG2RAD)):
                return index
        return None
    if item['example'] != 'core_2d_camera':
        return None
    down, previous, rotation, wheel = set(), set(), 0.0, False
    for index, frame in enumerate(item['frames']):
        for kind, p0, p1, _ in frame['events']:
            if kind == KEY_DOWN_EVENT:
                down.add(p0)
            elif kind == KEY_UP_EVENT:
                down.discard(p0)
            elif kind == MOUSE_WHEEL:
                wheel = wheel or p0 != 0 or p1 != 0
        if KEY_A in down:
            rotation -= 1.0
        elif KEY_S in down:
            rotation += 1.0
        rotation = max(-40.0, min(40.0, rotation))
        if KEY_R in down and KEY_R not in previous:
            rotation = 0.0
        if wheel or not fp.accepted(libm, fp.f32(rotation * fp.DEG2RAD)):
            return index
        previous = set(down)
    return None


# -----------------------------------------------------------------------------
# Reference (raylib's own example sources)

C_DRIVER = r'''#include "raylib.h"
#include "rlgl.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double probe_clock = 0.0, probe_after = 0.0;
double JonlibProbeTime(void) { return probe_clock; }
int JonlibProbeUsleep(unsigned int us) { (void)us; probe_clock = probe_after; return 0; }
int JonlibProbeNanosleep(const struct timespec *req, struct timespec *rem) { (void)req; (void)rem; probe_clock = probe_after; return 0; }

#define MAX_FRAMES 1024
#define MAX_EVENTS 64
typedef struct { double begin, end, after; int count; int events[MAX_EVENTS][4]; } Frame;
static Frame frames[MAX_FRAMES];
static int frame_count = 0, frame_index = 0, width = 0, height = 0;
static unsigned seed = 0;
static double start = 0.0;

static double dbl(unsigned long long b) { double d; memcpy(&d, &b, 8); return d; }

static void load_script(void)
{
    const char *path = getenv("JONLIB_EXAMPLE_SCRIPT");
    FILE *f = path ? fopen(path, "r") : NULL;
    if (!f) { fprintf(stderr, "no script\n"); exit(2); }
    unsigned long long b0, b1, b2;
    if (fscanf(f, "seed %u start %llu", &seed, &b0) != 2) exit(3);
    start = dbl(b0);
    while (fscanf(f, " frame %llu %llu %llu %d", &b0, &b1, &b2, &frames[frame_count].count) == 4)
    {
        Frame *fr = &frames[frame_count];
        if (frame_count == MAX_FRAMES - 1 || fr->count > MAX_EVENTS) exit(5);
        fr->begin = dbl(b0); fr->end = dbl(b1); fr->after = dbl(b2);
        for (int i = 0; i < fr->count; i++)
            if (fscanf(f, " event %d %d %d %d", &fr->events[i][0], &fr->events[i][1], &fr->events[i][2], &fr->events[i][3]) != 4) exit(4);
        frame_count++;
    }
    fclose(f);
}

static void dump(void)
{
    unsigned char *p = malloc((size_t)width*height*4);
    rlCopyFramebuffer(0, 0, width, height, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, p);
    printf("F ");
    unsigned run = 0, count = 0;
    for (int i = 0; i < width*height; i++)
    {
        unsigned w = ((unsigned)p[4*i + 2] << 24) | ((unsigned)p[4*i + 1] << 16) | ((unsigned)p[4*i] << 8) | p[4*i + 3];
        if (count > 0 && w == run) { count++; continue; }
        if (count > 0) printf("%u*%08x,", count, run);
        run = w; count = 1;
    }
    printf("%u*%08x,\n", count, run);
    fflush(stdout);
    free(p);
}

void JonlibExampleInitWindow(int w, int h, const char *title)
{
    load_script();
    width = w; height = h;
    probe_clock = start;
    SetTraceLogLevel(LOG_NONE);
    InitWindow(w, h, title);
    SetRandomSeed(seed);
}

bool JonlibExampleWindowShouldClose(void)
{
    if (frame_index >= frame_count) return true;
    Frame *fr = &frames[frame_index];
    for (int i = 0; i < fr->count; i++)
    {
        AutomationEvent e = { 0, (unsigned)fr->events[i][0], { fr->events[i][1], fr->events[i][2], fr->events[i][3], 0 } };
        PlayAutomationEvent(e);
    }
    return WindowShouldClose();
}

void JonlibExampleBeginDrawing(void)
{
    probe_clock = frames[frame_index].begin;
    BeginDrawing();
}

void JonlibExampleEndDrawing(void)
{
    probe_clock = frames[frame_index].end;
    probe_after = frames[frame_index].after;
    EndDrawing();
    probe_clock = probe_after;
    dump();
    frame_index++;
}
'''


def dbits(value):
    return struct.unpack('<Q', struct.pack('<d', value))[0]


def script_text(item):
    lines = [f'seed {item["seed"]} start {dbits(item["start"])}']
    for frame in item['frames']:
        lines.append(f'frame {dbits(frame["begin"])} {dbits(frame["end"])} {dbits(frame["after"])} {len(frame["events"])}')
        lines += [f'event {k} {a} {b} {c}' for k, a, b, c in frame['events']]
    return '\n'.join(lines) + '\n'


def build_reference(probe, name):
    source, _ = EXAMPLES[name]
    driver = probe.work / 'driver.c'
    driver.write_text(C_DRIVER)
    binary = probe.work / f'reference-{name}'
    include = '-I' + str(probe.args.raylib_source / 'src')
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', '-include', SHIM, include, '-c',
                  probe.args.raylib_source / 'examples' / source, '-o', probe.work / f'{name}.o'])
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', include, '-c', driver, '-o', probe.work / 'driver.o'])
    probekit.run(['clang', probe.work / f'{name}.o', probe.work / 'driver.o', probe.library, '-lm', '-o', binary])
    return binary


def native_frames(probe, binary, index, item):
    path = probe.work / f'script-{index}.txt'
    path.write_text(script_text(item))
    source, _ = EXAMPLES[item['example']]
    in_module = item['example'] == 'textures_logo_raylib' or item['example'] in IO_SETUP
    cwd = probe.args.raylib_source / 'examples' / source.split('/')[0] if in_module else probe.work
    result = subprocess.run([str(binary)], cwd=cwd, env=dict(probekit.ENV, JONLIB_EXAMPLE_SCRIPT=str(path)), stdin=subprocess.DEVNULL,
                            capture_output=True, text=True, timeout=600)
    if result.returncode:
        raise ProbeFailure(f'examples: native {item["name"]} failed ({result.returncode}): {result.stderr[-2000:]}')
    return [line[2:] for line in result.stdout.splitlines() if line.startswith('F ')]


# -----------------------------------------------------------------------------
# The presented Image built from raylib's bytes (src/present.bend's rules)

def decode(runs):
    words = []
    for token in runs.split(',')[:-1]:
        count, word = token.split('*')
        words += [int(word, 16)] * int(count)
    if len(words) != WIDTH * HEIGHT:
        raise ProbeFailure(f'examples: a frame decodes to {len(words)} words')
    return words


def quadtree(words, width, height):
    """Canonical quadtree: ints are Pix colors, 4-tuples Qua; a quad of four
    equal Pix is that Pix; squares past the edges are Pix 0."""
    grid = [[w >> 8 for w in words[y * width:(y + 1) * width]] for y in range(height)]
    k = 0
    while (1 << k) < max(width, height):
        k += 1
    for _ in range(k):
        rows = []
        for y in range(0, len(grid), 2):
            top = grid[y]
            bottom = grid[y + 1] if y + 1 < len(grid) else []
            row = []
            for x in range(0, len(top), 2):
                a = top[x]
                b = top[x + 1] if x + 1 < len(top) else 0
                c = bottom[x] if x < len(bottom) else 0
                d = bottom[x + 1] if x + 1 < len(bottom) else 0
                same = all(isinstance(v, int) for v in (a, b, c, d)) and a == b == c == d
                row.append(a if same else (a, b, c, d))
            rows.append(row)
        grid = rows
    return grid[0][0]


def preorder(node):
    out, stack = [], [node]
    while stack:
        n = stack.pop()
        if isinstance(n, int):
            out.append(f'p{n}')
        else:
            out.append('q')
            stack.extend(reversed(n))
    return ''.join(out)


def expected_row(runs):
    return runs + ' ' + preorder(quadtree(decode(runs), WIDTH, HEIGHT))


# -----------------------------------------------------------------------------
# Bend candidate: one program per example

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../examples/EXAMPLE.bend as Ex

def hex.digit(+d: U32) -> Char:
  Chr{Bool.pick(U32, (d < 10 : U32), (d + 48 : U32), (d + 87 : U32))}

def hex.word(+w: U32, rest: String) -> String:
  SCon{hex.digit((w >> 28n : U32)), SCon{hex.digit(((w >> 24n) .&. 15 : U32)), SCon{hex.digit(((w >> 20n) .&. 15 : U32)),
    SCon{hex.digit(((w >> 16n) .&. 15 : U32)), SCon{hex.digit(((w >> 12n) .&. 15 : U32)), SCon{hex.digit(((w >> 8n) .&. 15 : U32)),
    SCon{hex.digit(((w >> 4n) .&. 15 : U32)), SCon{hex.digit((w .&. 15 : U32)), rest}}}}}}}}

def run.token(+word: U32, +count: U32, rest: String) -> String:
  U32.show(count) ++ "*" ++ hex.word(word, "," ++ rest)

def run.flush(same: Bool, +word: U32, +count: U32, acc: String) -> String:
  match same:
    case True{}: acc
    case False{}: run.token(word, count, acc)

# Runs of the words from index i down to 0, in index order: (word, count) is
# the run after index i.
def runs(n: Nat, +i: U32, +word: U32, +count: U32, read: Array<U32> & U32, acc: String) -> String:
  match n read:
    case 0n _: run.token(word, count, acc)
    case 1n+k Tuple{a, +w}:
      +same = U32.is_eq(w, word) || U32.is_eq(count, 0)
      runs(k, (i - 1 : U32), w, Bool.pick(U32, U32.is_eq(w, word), (count + 1 : U32), 1), Array.get(U32, a, (i - 1 : U32)), run.flush(same, word, count, acc))

def runs.pixels(+count: U32, pixels: J.Surface.Pixels) -> String:
  match pixels:
    case J.Words{values}: runs(U32.to_nat(count), (count - 1 : U32), 0, 0, Array.get(U32, values, (count - 1 : U32)), "")
    case J.Quads{_}: "quads"

def runs.of(s: J.Surface) -> String:
  J.Surface{+w, +h, _, pixels} = s
  runs.pixels((w * h : U32), pixels)

def runs.surface(surface: Maybe<J.Surface>) -> String:
  match surface:
    case None{}: "null"
    case Some{s}: runs.of(s)

def tree(img: Image, acc: String) -> String:
  match img:
    case Pix{+c}: "p" ++ U32.show(c) ++ acc
    case Qua{a, b, c, d}: "q" ++ tree(a, tree(b, tree(c, tree(d, acc))))

def tree.of(img: Maybe<Image>) -> String:
  match img:
    case None{}: "null"
    case Some{i}: tree(i, "")

def show.tree(+text: String, r: J.Frame & Maybe<Image>) -> J.Frame & String:
  (frame, img) = r
  (frame, text ++ " " ++ tree.of(img))

def show.fb(r: J.Frame & Maybe<J.Surface>) -> J.Frame & String:
  (frame, s) = r
  show.tree(runs.surface(s), J.Frame.present(frame))

def show(frame: J.Frame) -> J.Frame & String:
  show.fb(J.Frame.framebuffer(frame))

def show.fn() -> J.Frame -> J.Frame & String:
  frame => show(frame)

def ev(+kind: U32, +p0: U32, +p1: U32, +p2: U32) -> J.AutomationEvent:
  J.AutomationEvent{0, kind, p0, p1, p2, 0}

def f64(+high: U32, +low: U32) -> M.Float64:
  M.Float64{high, low}

def fr(events: +List<J.AutomationEvent>, +bh: U32, +bl: U32, +eh: U32, +el: U32, +ah: U32, +al: U32) -> J.ReplayFrame:
  J.ReplayFrame{events, f64(bh, bl), f64(eh, el), f64(ah, al)}

def join(lines: List<String>) -> String:
  match lines:
    case Nil{}: ""
    case Con{line, rest}: line ++ "|" ++ join(rest)

def replay.parts(+core: J.Core, script: +List<J.ReplayFrame>, parts: J.Frame & Ex.State) -> String:
  (frame, state) = parts
  join(J.Program.replay(~Ex.State, ~Ex.program(M.LIBM{}), ~show.fn(), script, core, frame, state))

def replay.ready(script: +List<J.ReplayFrame>, ready: J.Core & (J.Frame & Ex.State)) -> String:
  (+core, parts) = ready
  replay.parts(core, script, parts)

REPLAY
'''

PURE_REPLAY = '''def replay(SETUP_PARAMS script: +List<J.ReplayFrame>, core: Maybe<J.Core>, frame: Maybe<J.Frame>) -> String:
  match core frame:
    case Some{+core} Some{frame}: replay.ready(script, SETUP)
    case _ _: "no window"
'''

IO_REPLAY = '''def replay(script: +List<J.ReplayFrame>, core: Maybe<J.Core>, frame: Maybe<J.Frame>) -> IO(String):
  match core frame:
    case Some{+core} Some{frame}: IO.bind(J.Core & (J.Frame & Ex.State), String, SETUP, ready => IO.pure(String, replay.ready(script, ready)))
    case _ _: IO.pure(String, "no window")
'''


def bend_u32(value):
    return str(value & 0xFFFFFFFF)


def bend_script(item):
    frames = []
    for frame in item['frames']:
        events = ', '.join(f'ev({k}, {bend_u32(a)}, {bend_u32(b)}, {bend_u32(c)})' for k, a, b, c in frame['events'])
        words = []
        for key_ in ('begin', 'end', 'after'):
            bits = dbits(frame[key_])
            words += [str(bits >> 32), str(bits & 0xFFFFFFFF)]
        frames.append(f'fr([{events}], {", ".join(words)})')
    return '[' + ', '.join(frames) + ']'


def render(items, libm, logo, raylib_source):
    """One program per example (actions are example names): every script of
    the example, one output line each."""
    def build(selected, gpu):
        if len(selected) != 1:
            raise ProbeFailure('examples: one example per batch')
        name = selected[0]
        _, setup = EXAMPLES[name]
        setup_params = '+seed: U32, ' if name in SEEDED else {'textures_logo_raylib': 'logo: Result<&1, &1, J.Surface.IOError, J.Surface>, '}.get(name, '')
        io = name in IO_SETUP
        resources = json.dumps(str(raylib_source / 'examples' / EXAMPLES[name][0].split('/')[0]) + '/')
        body = (PROGRAM.replace('REPLAY', IO_REPLAY if io else PURE_REPLAY).replace('EXAMPLE', name)
                .replace('SETUP_PARAMS ', setup_params).replace('SETUP', setup).replace('LIBM', libm).replace('RESOURCES', resources))
        indexes = [i for i, item in enumerate(items) if item['example'] == name]
        logo_param = 'logo: Result<&1, &1, J.Surface.IOError, J.Surface>' if name == 'textures_logo_raylib' else ''
        if logo_param and len(indexes) != 1:
            raise ProbeFailure('examples: textures_logo_raylib takes one script (its image is consumed)')
        calls = []
        for index in indexes:
            item = items[index]
            start = dbits(item['start'])
            flags = CONFIG_FLAGS.get(name, 0)
            window = (f'J.Core.init_window_flags({flags}, {WIDTH}, {HEIGHT}, f64({start >> 32}, {start & 0xFFFFFFFF})), '
                      f'J.Frame.init_window_flags({flags}, {WIDTH}, {HEIGHT})')
            args = f'{item["seed"]}, ' if name in SEEDED else {'textures_logo_raylib': 'logo, '}.get(name, '')
            result = 'IO(String)' if io else 'String'
            calls.append(f'def script.{index}() -> +List<J.ReplayFrame>:\n  {bend_script(item)}\n\n'
                         f'def run.{index}({logo_param}) -> {result}:\n  replay({args}script.{index}(), {window})\n')
        if logo_param:
            main = (f'def main.loaded(logo: Result<&1, &1, J.Surface.IOError, J.Surface>) -> IO(Unit):\n'
                    f'  IO.print(run.{indexes[0]}(logo))\n\n'
                    f'def main() -> IO(Unit):\n  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, Unit, J.Surface.load_png("{logo}"), main.loaded)\n')
        elif io:
            main = 'def main() -> IO(Unit):\n  do IO<Unit>:\n' + '\n'.join(f'    Unit <- IO.bind(String, Unit, run.{index}(), IO.print)'
                                                                       for index in indexes) + '\n    IO.pure(Unit, Unit{})\n'
        else:
            main = 'def main() -> IO(Unit):\n  do IO<Unit>:\n' + '\n'.join(f'    IO.print(run.{index}())' for index in indexes) + '\n'
        return body + '\n' + '\n'.join(calls) + '\n' + main
    return build


# -----------------------------------------------------------------------------
# Interactive frame rates (diagnostic)

def interactive(probe, frames):
    cli = ['bun', probe.args.bend_source / 'bend2/main.ts']
    logo = probe.args.raylib_source / 'examples/textures/resources/raylib_logo.png'
    results = {}
    for name in (probe.args.example or EXAMPLES):
        binary = probe.work / f'interactive-{name}'
        probekit.run([*cli, ROOT / f'examples/{name}.bend', '-o', binary], timeout=probekit.COMPILE_TIMEOUT)
        results[name] = {}
        for lane, threads in (('cpu-1', '1'), ('cpu-2', '2')):
            command = [binary, '--gpu', 'off', '--threads', threads, '--frames', str(frames)]
            if name == 'textures_logo_raylib':
                command += ['--logo', logo]
            if name in IO_SETUP:
                command += ['--resources', str(probe.args.raylib_source / 'examples' / EXAMPLES[name][0].split('/')[0]) + '/']
            output = probekit.run(command, timeout=600).strip().splitlines()
            line = output[-1] if output else ''
            match = re.search(r'(\d+) frames in (\d+) ms \(([\d.]+) FPS\); per frame: render (\d+) ms, present (\d+) ms, wait (\d+) ms', line)
            results[name][lane] = dict(report=line, fps=float(match.group(3)) if match else None,
                                       frames=int(match.group(1)) if match else None)
            print(f'{name} {lane}: {line}', flush=True)
    (probe.work / 'interactive.json').write_text(json.dumps(results, indent=2) + '\n')
    probe.diagnostic(**{f'{name}_{lane}_fps': r['fps'] for name, lanes in results.items() for lane, r in lanes.items()})


# -----------------------------------------------------------------------------

def configure(parser):
    parser.add_argument('--interactive', type=int, metavar='FRAMES', default=0,
                        help='run each example in a window for FRAMES frames and record its frame rate (diagnostic)')
    parser.add_argument('--example', action='append', choices=sorted(EXAMPLES),
                        help='only these examples (diagnostic subset)')
    parser.add_argument('--category', choices=sorted({name.split('_')[0] for name in EXAMPLES}),
                        help="only one category's examples (the examples-<category> gates)")


def main():
    args = probekit.arguments(__doc__, configure)
    name = ('examples-interactive' if args.interactive else f'examples-{args.category}' if args.category
            else 'examples' + ('-subset' if args.example else ''))
    probe = probekit.Probe(name, args, raylib_options=ip.OPTIONS)
    if args.interactive:
        interactive(probe, args.interactive)
        return
    definitions = ip.variant_definitions(probe.library)
    wanted = dict(SUPPORT_CUSTOM_FRAME_CONTROL=False, SUPPORT_BUSY_WAIT_LOOP=False, SUPPORT_PARTIALBUSY_WAIT_LOOP=True,
                  SUPPORT_AUTOMATION_EVENTS=True, SUPPORT_GESTURES_SYSTEM=True, SUPPORT_SCREEN_CAPTURE=True)
    if definitions != wanted:
        raise ProbeFailure(f'examples: reference build definitions {definitions}, expected {wanted}')
    libm = gradient_reference()
    logo = probe.args.raylib_source / 'examples/textures/resources/raylib_logo.png'
    if not logo.is_file():
        raise ProbeFailure(f'examples: {logo} is missing from the pinned raylib checkout')

    items = [item for item in scripts() if (not args.example or item['example'] in args.example)
             and (not args.category or item['example'].split('_')[0] == args.category)]
    names = [name for name in EXAMPLES if any(item['example'] == name for item in items)]
    rows_by_script, refused, binaries = [], {}, {}
    for index, item in enumerate(items):
        cut = refusal(item, libm)
        refused[item['name']] = cut
        rows = []
        if cut != 0:
            name = item['example']
            if name not in binaries:
                binaries[name] = build_reference(probe, name)
            rows = [expected_row(runs) for runs in native_frames(probe, binaries[name], index, item)]
        if cut is not None:
            rows = rows[:cut] + ['null null'] * (len(item['frames']) - cut)
        rows_by_script.append('|'.join(rows) + '|')
    expected = ['\n'.join(row for row, item in zip(rows_by_script, items) if item['example'] == name) for name in names]

    lanes = probe.candidates(render(items, libm, logo, probe.args.raylib_source), names, batch=1,
                             parse=lambda text, chosen: ['\n'.join(line for line in text.splitlines() if line.strip())])

    def describe(i):
        scripts_of = [item for item in items if item['example'] == names[i]]
        wanted, got = expected[i].split('\n'), lanes['cpu-1'][i].split('\n')
        for item, a, b in zip(scripts_of, wanted, got):
            if a != b:
                fa, fb = a.split('|'), b.split('|')
                first = next((k for k, (x, y) in enumerate(zip(fa, fb)) if x != y), min(len(fa), len(fb)))
                return f'example {names[i]}, script {item["name"]}, frame {first} ({len(fa) - 1} frames expected, {len(fb) - 1} drawn)'
        return f'example {names[i]} ({len(wanted)} scripts expected, {len(got)} printed)'

    probe.compare(expected, lanes, describe=describe)
    frames = sum(row.count('|') for row in rows_by_script)
    contract_frames = sum(row.count('null null') for row in rows_by_script)
    probe.finish(examples=len(names), scripts=len(items), frames=frames, compared_frames=frames - contract_frames,
                 refused_frames=contract_frames, libm=libm, refusals=refused,
                 scripts_sha256=hashlib.sha256(json.dumps(items, default=repr).encode()).hexdigest())


if __name__ == '__main__':
    main()
