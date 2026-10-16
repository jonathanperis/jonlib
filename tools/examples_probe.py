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
raylib. A few examples (REPORTED) take the refusal frame Jonlib reports under
the Apple profile instead of an independent prediction; the report lists them
(reported_refusals). The refusals are computed for the host's M.Libm profile (Apple on
macOS, glibc 2.39 on glibc hosts, conformance.gradient_reference): the
13-degree rotation is a contract on macOS and compared on Linux. Native code
only runs what C defines: the wheel and rotation scripts are defined in C
(raylib computes expf/logf and sinf/cosf), and shapes_basic_shapes, refused
from its first frame, is not run natively. CPU-1, CPU-2 and JavaScript lanes.

The clock examples read the C library's time() and localtime(), which the
driver's header redirects in the example's translation unit: time() is the
script's seed (the seconds of the day at InitWindow) plus the scripted
clock's whole seconds, and localtime is gmtime. Their ports take the seed
as that time and add GetTime's whole seconds.

core_custom_frame_control waits itself after EndDrawing (WaitTime to its own
1/60 s): the header wraps its WaitTime so that the sleep ends at raylib's
destination, and each scripted frame starts from the end of that wait
(own_wait), computed in binary64 as the example computes it.

An example that writes files (SCRATCH: core_storage_values) runs each script
in an empty directory of its own, the reference as its working directory and
Jonlib as the directory its setup takes; the files left must have the same
names and bytes on both sides. A script may start from files (FILES), and
one that would take the native loop out of what C defines from some frame on
(UNDEFINED_FROM: an int read or written past the data LoadFileData
returned) is run natively up to that frame only; Jonlib must refuse from it.
An example whose loop does IO is a J.Effects program, replayed with
J.Program.replay_io.

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
AUDIO_CLOCK_UNIT = ROOT / 'tools/reference/audio_clock.c'
WIDTH, HEIGHT = 800, 450
# Examples whose InitWindow is not 800x450.
SIZES = {'core_2d_camera_split_screen': (800, 440), 'shapes_math_angle_rotation': (720, 400), 'gui_window_grid': (400, 300), 'gui_toggle_combo_list': (400, 300), 'gui_message_tabs': (500, 300), 'gui_value_input': (500, 360)}
SIZES['shaders_rlgl_compute'] = (768, 768)


def size_of(name):
    return SIZES.get(name, (WIDTH, HEIGHT))
TARGET = 1.0 / 60
LANE_TIMEOUT = 1800
# Examples whose lanes take longer: text_font_sdf's SDF glyphs with curves solve thousands of cubics in software
# binary64 under the Glibc239 profile (about 30 minutes on the JavaScript lane of a CI runner).
SLOW_LANES = {'text_font_sdf': 3600}
# Examples whose SetTargetFPS is not 60 (the scripted wait ends where raylib's does).
TARGET_FPS = {'shapes_kaleidoscope': 20, 'shapes_penrose_tile': 120, 'textures_mouse_painting': 120}
# shaders_rlgl_compute never calls SetTargetFPS: with a target of a nanosecond no scripted frame is short enough to wait.
TARGET_FPS['shaders_rlgl_compute'] = 10**9
# core_custom_frame_control never calls SetTargetFPS either; after EndDrawing it waits itself (OWN_WAIT: its target).
TARGET_FPS['core_custom_frame_control'] = 10**9
OWN_WAIT = {'core_custom_frame_control': 60}
TARGET_FPS['audio_raw_stream'] = 30
TARGET_FPS['audio_stream_callback'] = 30
TARGET_FPS['audio_music_stream'] = 30

(KEY_UP_EVENT, KEY_DOWN_EVENT, MOUSE_UP, MOUSE_DOWN, MOUSE_POSITION, MOUSE_WHEEL, INPUT_GESTURE, WINDOW_CLOSE) = (1, 2, 5, 6, 7, 8, 17, 18)
# Gamepad events: (gamepad), (gamepad, button), (gamepad, axis, value/32768).
(GAMEPAD_CONNECT, GAMEPAD_BUTTON_UP, GAMEPAD_BUTTON_DOWN, GAMEPAD_AXIS_MOTION) = (9, 11, 12, 13)
KEY_RIGHT, KEY_LEFT, KEY_DOWN, KEY_UP, KEY_A, KEY_H, KEY_R, KEY_S = 262, 263, 264, 265, 65, 72, 82, 83
KEY_G, KEY_SPACE, KEY_C, KEY_ENTER = 71, 32, 67, 257
KEY_ONE, KEY_TWO, KEY_THREE, KEY_FOUR = 49, 50, 51, 52
KEY_P, KEY_W, KEY_D, KEY_TAB = 80, 87, 68, 258
KEY_F = 70
KEY_LEFT_CONTROL = 341
# Touch point events: a touch point counts as the mouse button of its index, and the memory platform, which never
# registers a mouse button's previous state, registers a touch point's: IsMouseButtonReleased fires for it alone.
TOUCH_UP, TOUCH_DOWN = 14, 15

# name: (raylib source, setup expression, State is Data, needs the logo image)
EXAMPLES = {
    'core_basic_window': ('core/core_basic_window.c', 'Ex.setup(core, frame)'),
    'core_input_keys': ('core/core_input_keys.c', 'Ex.setup(core, frame)'),
    'core_input_mouse': ('core/core_input_mouse.c', 'Ex.setup(core, frame)'),
    'core_2d_camera': ('core/core_2d_camera.c', 'Ex.setup(seed, core, frame)'),
    'core_2d_camera_platformer': ('core/core_2d_camera_platformer.c', 'Ex.setup(core, frame)'),
    'shapes_logo_raylib': ('shapes/shapes_logo_raylib.c', 'Ex.setup(core, frame)'),
    'textures_logo_raylib': ('textures/textures_logo_raylib.c', 'Ex.setup(Ex.image(logo), core, frame)'),
    'shapes_basic_shapes': ('shapes/shapes_basic_shapes.c', 'Ex.setup(core, frame)'),
    'textures_srcrec_dstrec': ('textures/textures_srcrec_dstrec.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_tiled_drawing': ('textures/textures_tiled_drawing.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_image_drawing': ('textures/textures_image_drawing.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_image_channel': ('textures/textures_image_channel.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_image_kernel': ('textures/textures_image_kernel.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_image_processing': ('textures/textures_image_processing.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_polygon_drawing': ('textures/textures_polygon_drawing.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_magnifying_glass': ('textures/textures_magnifying_glass.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_gif_player': ('textures/textures_gif_player.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_cellular_automata': ('textures/textures_cellular_automata.c', 'Ex.setup(core, frame)'),
    'textures_mouse_painting': ('textures/textures_mouse_painting.c', 'Ex.setup(core, frame)'),
    'textures_screen_buffer': ('textures/textures_screen_buffer.c', 'Ex.setup(seed, core, frame)'),
    'textures_framebuffer_rendering': ('textures/textures_framebuffer_rendering.c', 'Ex.setup(core, frame)'),
    'textures_image_text': ('textures/textures_image_text.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_fog_of_war': ('textures/textures_fog_of_war.c', 'Ex.setup(seed, core, frame)'),
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
    'core_random_sequence': ('core/core_random_sequence.c', 'Ex.setup(seed, core, frame)'),
    'core_render_texture': ('core/core_render_texture.c', 'Ex.setup(core, frame)'),
    'core_delta_time': ('core/core_delta_time.c', 'Ex.setup(core, frame)'),
    'core_3d_camera_mode': ('core/core_3d_camera_mode.c', 'Ex.setup(core, frame)'),
    'core_3d_camera_free': ('core/core_3d_camera_free.c', 'Ex.setup(core, frame)'),
    'core_3d_camera_first_person': ('core/core_3d_camera_first_person.c', 'Ex.setup(seed, core, frame)'),
    'core_world_screen': ('core/core_world_screen.c', 'Ex.setup(core, frame)'),
    'core_3d_picking': ('core/core_3d_picking.c', 'Ex.setup(core, frame)'),
    'models_basic_voxel': ('models/models_basic_voxel.c', 'Ex.setup(core, frame)'),
    'models_rotating_cube': ('models/models_rotating_cube.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_image_loading': ('textures/textures_image_loading.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_image_rotate': ('textures/textures_image_rotate.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'textures_to_image': ('textures/textures_to_image.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_blend_modes': ('textures/textures_blend_modes.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_npatch_drawing': ('textures/textures_npatch_drawing.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_raw_data': ('textures/textures_raw_data.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_bunnymark': ('textures/textures_bunnymark.c', 'Ex.setup(seed, RESOURCES, core, frame)'),
    'textures_image_generation': ('textures/textures_image_generation.c', 'Ex.setup(seed, M.LIBM{}, core, frame)'),
    'shapes_easings_rectangles': ('shapes/shapes_easings_rectangles.c', 'Ex.setup(core, frame)'),
    'core_2d_camera_split_screen': ('core/core_2d_camera_split_screen.c', 'Ex.setup(core, frame)'),
    'core_3d_camera_split_screen': ('core/core_3d_camera_split_screen.c', 'Ex.setup(core, frame)'),
    'models_geometric_shapes': ('models/models_geometric_shapes.c', 'Ex.setup(core, frame)'),
    'models_box_collisions': ('models/models_box_collisions.c', 'Ex.setup(core, frame)'),
    'models_orthographic_projection': ('models/models_orthographic_projection.c', 'Ex.setup(core, frame)'),
    'shaders_basic_lighting': ('shaders/shaders_basic_lighting.c', 'Ex.setup(core, frame)'),
    'shapes_bullet_hell': ('shapes/shapes_bullet_hell.c', 'Ex.setup(M.LIBM{}, core, frame)'),
    'shapes_double_pendulum': ('shapes/shapes_double_pendulum.c', 'Ex.setup(M.LIBM{}, core, frame)'),
    'shapes_vector_angle': ('shapes/shapes_vector_angle.c', 'Ex.setup(core, frame)'),
    'shapes_penrose_tile': ('shapes/shapes_penrose_tile.c', 'Ex.setup(core, frame)'),
    'shaders_texture_waves': ('shaders/shaders_texture_waves.c', 'Ex.setup(RESOURCES, core, frame)'),
    'shaders_eratosthenes_sieve': ('shaders/shaders_eratosthenes_sieve.c', 'Ex.setup(core, frame)'),
    'shaders_texture_outline': ('shaders/shaders_texture_outline.c', 'Ex.setup(RESOURCES, core, frame)'),
    'shaders_palette_switch': ('shaders/shaders_palette_switch.c', 'Ex.setup(core, frame)'),
    'shaders_rounded_rectangle': ('shaders/shaders_rounded_rectangle.c', 'Ex.setup(core, frame)'),
    'shaders_julia_set': ('shaders/shaders_julia_set.c', 'Ex.setup(core, frame)'),
    'shaders_texture_rendering': ('shaders/shaders_texture_rendering.c', 'Ex.setup(core, frame)'),
    'shaders_multi_sample2d': ('shaders/shaders_multi_sample2d.c', 'Ex.setup(core, frame)'),
    'shaders_shapes_textures': ('shaders/shaders_shapes_textures.c', 'Ex.setup(RESOURCES, core, frame)'),
    'shaders_texture_tiling': ('shaders/shaders_texture_tiling.c', 'Ex.setup(RESOURCES, core, frame)'),
    'shaders_vertex_displacement': ('shaders/shaders_vertex_displacement.c', 'Ex.setup(core, frame)'),
    'shaders_normalmap_rendering': ('shaders/shaders_normalmap_rendering.c', 'Ex.setup(RESOURCES, core, frame)'),
    'shaders_cel_shading': ('shaders/shaders_cel_shading.c', 'Ex.setup(RESOURCES, core, frame)'),
    'shaders_model_shader': ('shaders/shaders_model_shader.c', 'Ex.setup(RESOURCES, core, frame)'),
    'shaders_fog_rendering': ('shaders/shaders_fog_rendering.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'shaders_ascii_rendering': ('shaders/shaders_ascii_rendering.c', 'Ex.setup(RESOURCES, core, frame)'),
    'shaders_simple_mask': ('shaders/shaders_simple_mask.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'shaders_postprocessing': ('shaders/shaders_postprocessing.c', 'Ex.setup(RESOURCES, core, frame)'),
    'shaders_custom_uniform': ('shaders/shaders_custom_uniform.c', 'Ex.setup(RESOURCES, core, frame)'),
    'shaders_mesh_instancing': ('shaders/shaders_mesh_instancing.c', 'Ex.setup(seed, M.LIBM{}, core, frame)'),
    'shaders_mandelbrot_set': ('shaders/shaders_mandelbrot_set.c', 'Ex.setup(core, frame)'),
    'shaders_raymarching_rendering': ('shaders/shaders_raymarching_rendering.c', 'Ex.setup(core, frame)'),
    'core_basic_screen_manager': ('core/core_basic_screen_manager.c', 'Ex.setup(core, frame)'),
    'core_window_letterbox': ('core/core_window_letterbox.c', 'Ex.setup(seed, core, frame)'),
    'core_input_multitouch': ('core/core_input_multitouch.c', 'Ex.setup(core, frame)'),
    'core_input_gestures': ('core/core_input_gestures.c', 'Ex.setup(core, frame)'),
    'core_input_actions': ('core/core_input_actions.c', 'Ex.setup(core, frame)'),
    'core_monitor_detector': ('core/core_monitor_detector.c', 'Ex.setup(core, frame)'),
    'core_window_flags': ('core/core_window_flags.c', 'Ex.setup(core, frame)'),
    'core_highdpi_testbed': ('core/core_highdpi_testbed.c', 'Ex.setup(core, frame)'),
    'core_highdpi_demo': ('core/core_highdpi_demo.c', 'Ex.setup(core, frame)'),
    'core_viewport_scaling': ('core/core_viewport_scaling.c', 'Ex.setup(core, frame)'),
    'core_undo_redo': ('core/core_undo_redo.c', 'Ex.setup(seed, core, frame)'),
    'core_keyboard_testbed': ('core/core_keyboard_testbed.c', 'Ex.setup(core, frame)'),
    'core_input_gestures_testbed': ('core/core_input_gestures_testbed.c', 'Ex.setup(core, frame)'),
    'core_3d_camera_fps': ('core/core_3d_camera_fps.c', 'Ex.setup(M.LIBM{}, core, frame)'),
    'core_input_gamepad': ('core/core_input_gamepad.c', 'Ex.setup(RESOURCES, core, frame)'),
    'core_2d_camera_mouse_zoom': ('core/core_2d_camera_mouse_zoom.c', 'Ex.setup(core, frame)'),
    'core_window_should_close': ('core/core_window_should_close.c', 'Ex.setup(core, frame)'),
    'core_text_file_loading': ('core/core_text_file_loading.c', 'Ex.setup(RESOURCES, core, frame)'),
    'core_input_virtual_controls': ('core/core_input_virtual_controls.c', 'Ex.setup(core, frame)'),
    'shapes_math_angle_rotation': ('shapes/shapes_math_angle_rotation.c', 'Ex.setup(core, frame)'),
    'shapes_following_eyes': ('shapes/shapes_following_eyes.c', 'Ex.setup(core, frame)'),
    'text_font_spritefont': ('text/text_font_spritefont.c', 'Ex.setup(RESOURCES, core, frame)'),
    'models_billboard_rendering': ('models/models_billboard_rendering.c', 'Ex.setup(RESOURCES, core, frame)'),
    'models_directional_billboard': ('models/models_directional_billboard.c', 'Ex.setup(RESOURCES, core, frame)'),
    'models_heightmap_rendering': ('models/models_heightmap_rendering.c', 'Ex.setup(RESOURCES, core, frame)'),
    'models_cubicmap_rendering': ('models/models_cubicmap_rendering.c', 'Ex.setup(RESOURCES, core, frame)'),
    'models_first_person_maze': ('models/models_first_person_maze.c', 'Ex.setup(RESOURCES, core, frame)'),
    'models_yaw_pitch_roll': ('models/models_yaw_pitch_roll.c', 'Ex.setup(RESOURCES, core, frame)'),
    'models_loading': ('models/models_loading.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'models_mesh_picking': ('models/models_mesh_picking.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'models_point_rendering': ('models/models_point_rendering.c', 'Ex.setup(M.LIBM{}, core, frame)'),
    'models_rlgl_solar_system': ('models/models_rlgl_solar_system.c', 'Ex.setup(M.LIBM{}, core, frame)'),
    'models_textured_cube': ('models/models_textured_cube.c', 'Ex.setup(RESOURCES, core, frame)'),
    'shapes_circle_sector_drawing': ('shapes/shapes_circle_sector_drawing.c', 'Ex.setup(core, frame)'),
    'shapes_ring_drawing': ('shapes/shapes_ring_drawing.c', 'Ex.setup(core, frame)'),
    'shapes_rounded_rectangle_drawing': ('shapes/shapes_rounded_rectangle_drawing.c', 'Ex.setup(core, frame)'),
    'shapes_triangle_strip': ('shapes/shapes_triangle_strip.c', 'Ex.setup(core, frame)'),
    'shapes_rlgl_color_wheel': ('shapes/shapes_rlgl_color_wheel.c', 'Ex.setup(core, frame)'),
    'shapes_rectangle_advanced': ('shapes/shapes_rectangle_advanced.c', 'Ex.setup(core, frame)'),
    'shapes_easings_ball': ('shapes/shapes_easings_ball.c', 'Ex.setup(core, frame)'),
    'shapes_easings_box': ('shapes/shapes_easings_box.c', 'Ex.setup(core, frame)'),
    'shapes_easings_testbed': ('shapes/shapes_easings_testbed.c', 'Ex.setup(core, frame)'),
    'shapes_top_down_lights': ('shapes/shapes_top_down_lights.c', 'Ex.setup(seed, core, frame)'),
    'shapes_simple_particles': ('shapes/shapes_simple_particles.c', 'Ex.setup(M.LIBM{}, core, frame)'),
    'shapes_ball_physics': ('shapes/shapes_ball_physics.c', 'Ex.setup(seed, core, frame)'),
    'shapes_math_sine_cosine': ('shapes/shapes_math_sine_cosine.c', 'Ex.setup(M.LIBM{}, core, frame)'),
    'shapes_hilbert_curve': ('shapes/shapes_hilbert_curve.c', 'Ex.setup(core, frame)'),
    'shapes_splines_drawing': ('shapes/shapes_splines_drawing.c', 'Ex.setup(core, frame)'),
    'core_compute_hash': ('core/core_compute_hash.c', 'Ex.setup(core, frame)'),
    'core_clipboard_text': ('core/core_clipboard_text.c', 'Ex.setup(seed, core, frame)'),
    'shapes_pie_chart': ('shapes/shapes_pie_chart.c', 'Ex.setup(core, frame)'),
    'shaders_rlgl_compute': ('shaders/shaders_rlgl_compute.c', 'Ex.setup(core, frame)'),
    'shaders_lightmap_rendering': ('shaders/shaders_lightmap_rendering.c', 'Ex.setup(RESOURCES, core, frame)'),
    'models_animation_gpu_skinning': ('models/models_animation_gpu_skinning.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'models_bone_socket': ('models/models_bone_socket.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'models_loading_gltf': ('models/models_loading_gltf.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'models_animation_timing': ('models/models_animation_timing.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'models_animation_blending': ('models/models_animation_blending.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'models_animation_blend_custom': ('models/models_animation_blend_custom.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'models_waving_cubes': ('models/models_waving_cubes.c', 'Ex.setup(core, frame)'),
    'shaders_spotlight_rendering': ('shaders/shaders_spotlight_rendering.c', 'Ex.setup(seed, RESOURCES, core, frame)'),
    'models_mesh_generation': ('models/models_mesh_generation.c', 'Ex.setup(M.LIBM{}, core, frame)'),
    'shaders_depth_writing': ('shaders/shaders_depth_writing.c', 'Ex.setup(RESOURCES, core, frame)'),
    'shaders_hybrid_rendering': ('shaders/shaders_hybrid_rendering.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'shaders_depth_rendering': ('shaders/shaders_depth_rendering.c', 'Ex.setup(RESOURCES, core, frame)'),
    'shaders_shadowmap_rendering': ('shaders/shaders_shadowmap_rendering.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'shaders_deferred_rendering': ('shaders/shaders_deferred_rendering.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'models_skybox_rendering': ('models/models_skybox_rendering.c', 'Ex.setup(RESOURCES, core, frame)'),
    'models_decals': ('models/models_decals.c', 'Ex.setup(M.LIBM{}, seed, RESOURCES, core, frame)'),
    'shaders_hot_reloading': ('shaders/shaders_hot_reloading.c', 'Ex.setup(seed, RESOURCES, core, frame)'),
    'text_codepoints_loading': ('text/text_codepoints_loading.c', 'Ex.setup(core, frame)'),
    'text_unicode_emojis': ('text/text_unicode_emojis.c', 'Ex.setup(seed, RESOURCES, core, frame)'),
    'text_3d_drawing': ('text/text_3d_drawing.c', 'Ex.setup(seed, core, frame)'),
    'models_loading_vox': ('models/models_loading_vox.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'models_loading_iqm': ('models/models_loading_iqm.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'shaders_basic_pbr': ('shaders/shaders_basic_pbr.c', 'Ex.setup(RESOURCES, core, frame)'),
    'models_loading_m3d': ('models/models_loading_m3d.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'textures_sprite_button': ('textures/textures_sprite_button.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_sprite_explosion': ('textures/textures_sprite_explosion.c', 'Ex.setup(RESOURCES, core, frame)'),
    'audio_sound_multi': ('audio/audio_sound_multi.c', 'Ex.setup(RESOURCES, core, frame)'),
    'audio_sound_positioning': ('audio/audio_sound_positioning.c', 'Ex.setup(RESOURCES, core, frame)'),
    'audio_sound_loading': ('audio/audio_sound_loading.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'audio_raw_stream': ('audio/audio_raw_stream.c', 'Ex.setup(core, frame)'),
    'audio_stream_callback': ('audio/audio_stream_callback.c', 'Ex.setup(M.LIBM{}, core, frame)'),
    'audio_music_stream': ('audio/audio_music_stream.c', 'Ex.setup(RESOURCES, core, frame)'),
    'audio_module_playing': ('audio/audio_module_playing.c', 'Ex.setup(seed, M.LIBM{}, RESOURCES, core, frame)'),
    'audio_stream_effects': ('audio/audio_stream_effects.c', 'Ex.setup(RESOURCES, core, frame)'),
    'audio_mixed_processor': ('audio/audio_mixed_processor.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'audio_spectrum_visualizer': ('audio/audio_spectrum_visualizer.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'core_screen_recording': ('core/core_screen_recording.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'core_directory_files': ('core/core_directory_files.c', 'Ex.setup(listings, core, frame)'),
    'text_unicode_ranges': ('text/text_unicode_ranges.c', 'Ex.setup(RESOURCES, core, frame)'),
    'textures_sprite_stacking': ('textures/textures_sprite_stacking.c', 'Ex.setup(RESOURCES, core, frame)'),
    'core_vr_simulator': ('core/core_vr_simulator.c', 'Ex.setup(M.LIBM{}, core, frame)'),
    'shaders_game_of_life': ('shaders/shaders_game_of_life.c', 'Ex.setup(seed, RESOURCES, core, frame)'),
    'core_custom_logging': ('core/core_custom_logging.c', 'Ex.setup(core, frame)'),
    'core_custom_frame_control': ('core/core_custom_frame_control.c', 'Ex.setup(core, frame)'),
    'shapes_digital_clock': ('shapes/shapes_digital_clock.c', 'Ex.setup(seed, core, frame)'),
    'shapes_clock_of_clocks': ('shapes/shapes_clock_of_clocks.c', 'Ex.setup(seed, core, frame)'),
    'core_storage_values': ('core/core_storage_values.c', 'Ex.setup(seed, RESOURCES, core, frame)'),
    'core_automation_events': ('core/core_automation_events.c', 'Ex.setup(RESOURCES, core, frame)'),
    'shapes_recursive_tree': ('shapes/shapes_recursive_tree.c', 'Ex.setup(core, frame)'),
    'shapes_kaleidoscope': ('shapes/shapes_kaleidoscope.c', 'Ex.setup(core, frame)'),
    'shaders_color_correction': ('shaders/shaders_color_correction.c', 'Ex.setup(RESOURCES, core, frame)'),
    'core_window_web': ('core/core_window_web.c', 'Ex.setup(core, frame)'),
    'text_sprite_fonts': ('text/text_sprite_fonts.c', 'Ex.setup(RESOURCES, core, frame)'),
    'text_font_loading': ('text/text_font_loading.c', 'Ex.setup(RESOURCES, core, frame)'),
    'text_font_filters': ('text/text_font_filters.c', 'Ex.setup(RESOURCES, core, frame)'),
    'text_font_sdf': ('text/text_font_sdf.c', 'Ex.setup(M.LIBM{}, RESOURCES, core, frame)'),
    'text_words_alignment': ('text/text_words_alignment.c', 'Ex.setup(core, frame)'),
    'text_rectangle_bounds': ('text/text_rectangle_bounds.c', 'Ex.setup(core, frame)'),
    'text_inline_styling': ('text/text_inline_styling.c', 'Ex.setup(seed, core, frame)'),
    'text_strings_management': ('text/text_strings_management.c', 'Ex.setup(seed, core, frame)'),
    'textures_clipboard_image': ('textures/textures_clipboard_image.c', 'Ex.setup(core, frame)'),
    'textures_textured_curve': ('textures/textures_textured_curve.c', 'Ex.setup(RESOURCES, core, frame)'),
    'core_smooth_pixelperfect': ('core/core_smooth_pixelperfect.c', 'Ex.setup(core, frame)'),
    'models_tesseract_view': ('models/models_tesseract_view.c', 'Ex.setup(core, frame)'),
    'textures_particles_blending': ('textures/textures_particles_blending.c', 'Ex.setup(seed, RESOURCES, core, frame)'),
}

# Probe-only raygui programs (category gui): Jongui's controls that no raylib example calls, each a C program of
# tools/reference/gui/ (its source given as jonlib/gui/...) replayed against its port in tests/gui/. They are not raylib
# examples: tools/examples_plan.py counts the literal table above only.
GUI_SCENES = {
    'gui_window_grid': ('jonlib/gui/gui_window_grid.c', 'Ex.setup(core, frame)'),
    'gui_toggle_combo_list': ('jonlib/gui/gui_toggle_combo_list.c', 'Ex.setup(core, frame)'),
    'gui_message_tabs': ('jonlib/gui/gui_message_tabs.c', 'Ex.setup(core, frame)'),
    'gui_value_input': ('jonlib/gui/gui_value_input.c', 'Ex.setup(core, frame)'),
}
EXAMPLES.update(GUI_SCENES)

# Examples whose setup is IO (LoadTexture: Ex.setup(dir, core, frame) with raylib's
# examples/<module>/ directory) and the flags SetConfigFlags sets before InitWindow.
IO_SETUP = {'textures_srcrec_dstrec', 'textures_sprite_animation', 'textures_background_scrolling', 'models_rotating_cube',
            'textures_image_loading', 'textures_image_rotate', 'textures_to_image', 'textures_blend_modes',
            'textures_npatch_drawing', 'textures_raw_data', 'textures_bunnymark', 'shaders_texture_waves',
            'shaders_texture_outline', 'shaders_shapes_textures', 'shaders_texture_tiling', 'text_font_spritefont',
            'models_billboard_rendering', 'shaders_color_correction', 'textures_particles_blending',
            'text_sprite_fonts', 'models_directional_billboard', 'textures_tiled_drawing',
            'textures_image_drawing', 'text_font_loading', 'textures_image_text',
            'text_font_filters', 'textures_image_channel', 'textures_image_kernel',
            'textures_image_processing', 'textures_polygon_drawing', 'textures_magnifying_glass',
            'models_heightmap_rendering', 'models_cubicmap_rendering',
            'models_first_person_maze', 'shaders_model_shader',
            'models_yaw_pitch_roll', 'models_loading', 'shaders_fog_rendering',
            'core_text_file_loading', 'shaders_ascii_rendering', 'shaders_simple_mask',
            'textures_gif_player', 'models_textured_cube', 'shaders_postprocessing',
            'shaders_custom_uniform', 'models_mesh_picking', 'core_input_gamepad',
            'textures_textured_curve', 'shaders_normalmap_rendering', 'shaders_cel_shading'}
# Examples whose setup takes the script's seed (GetRandomValue after InitWindow's SetRandomSeed).
# Examples drawing through a perspective camera from their first frame: BeginMode3D's binary64 tan has no
# AppleLibm profile (docs/PERSPECTIVE.md), so on macOS every frame is a contract and nothing runs natively.
PERSPECTIVE = {'core_3d_camera_mode', 'core_3d_camera_free', 'core_world_screen', 'core_3d_picking', 'models_basic_voxel', 'models_rotating_cube',
               'models_geometric_shapes', 'models_box_collisions', 'models_orthographic_projection',
               'shaders_basic_lighting', 'shaders_texture_tiling', 'models_billboard_rendering',
               'models_tesseract_view', 'models_directional_billboard', 'models_heightmap_rendering',
               'models_cubicmap_rendering', 'models_first_person_maze', 'shaders_model_shader',
               'models_yaw_pitch_roll', 'models_loading', 'shaders_fog_rendering', 'shaders_simple_mask',
               'core_3d_camera_first_person', 'models_rlgl_solar_system', 'models_textured_cube',
               'core_3d_camera_split_screen', 'shaders_postprocessing', 'textures_framebuffer_rendering',
               'shaders_custom_uniform', 'shaders_mesh_instancing', 'models_mesh_picking', 'core_3d_camera_fps',
               'shaders_vertex_displacement', 'models_point_rendering', 'shaders_normalmap_rendering',
               'shaders_cel_shading'}
SEEDED = {'core_2d_camera', 'shapes_starfield_effect', 'core_random_values', 'core_random_sequence', 'textures_fog_of_war', 'core_3d_camera_first_person', 'textures_bunnymark', 'textures_image_generation',
          'core_window_letterbox', 'textures_particles_blending', 'textures_screen_buffer', 'shaders_mesh_instancing',
          'core_undo_redo', 'text_inline_styling', 'text_strings_management', 'shapes_top_down_lights',
          'shapes_ball_physics',
          'core_clipboard_text'}
CONFIG_FLAGS = {'shapes_bouncing_ball': 32, 'shapes_lines_bezier': 32, 'shapes_rlgl_triangle': 32, 'shaders_basic_lighting': 32,
                'shaders_raymarching_rendering': 4, 'core_window_letterbox': 68, 'shapes_double_pendulum': 8192,
                'textures_tiled_drawing': 4, 'shapes_penrose_tile': 32, 'shaders_model_shader': 32, 'shaders_postprocessing': 32, 'shaders_custom_uniform': 32, 'core_highdpi_testbed': 8196, 'core_highdpi_demo': 8196, 'core_viewport_scaling': 4,
                'shaders_fog_rendering': 32, 'shapes_rlgl_color_wheel': 32, 'core_input_gamepad': 32, 'textures_textured_curve': 96,
                'shaders_normalmap_rendering': 32, 'shaders_cel_shading': 32, 'shapes_math_sine_cosine': 32,
                'shapes_splines_drawing': 32}
IO_SETUP.add('shaders_lightmap_rendering'); PERSPECTIVE.add('shaders_lightmap_rendering'); CONFIG_FLAGS['shaders_lightmap_rendering'] = 32
IO_SETUP.add('models_animation_gpu_skinning'); PERSPECTIVE.add('models_animation_gpu_skinning')
IO_SETUP.add('models_bone_socket'); PERSPECTIVE.add('models_bone_socket')
IO_SETUP.add('models_loading_gltf'); PERSPECTIVE.add('models_loading_gltf')
IO_SETUP.add('models_animation_timing'); PERSPECTIVE.add('models_animation_timing')
IO_SETUP.add('models_animation_blending'); PERSPECTIVE.add('models_animation_blending')
IO_SETUP.add('models_animation_blend_custom'); PERSPECTIVE.add('models_animation_blend_custom')
PERSPECTIVE.add('models_waving_cubes')
IO_SETUP.add('shaders_spotlight_rendering'); SEEDED.add('shaders_spotlight_rendering')
# The binary64 cos and sin of its first frame have no AppleLibm profile either (docs/MATH.md): the same contract.
PERSPECTIVE.add('shaders_spotlight_rendering')
PERSPECTIVE.add('models_mesh_generation')
PERSPECTIVE.add('shaders_depth_writing')
PERSPECTIVE.add('shaders_hybrid_rendering')
PERSPECTIVE.add('shaders_depth_rendering')
PERSPECTIVE.add('shaders_deferred_rendering')
# The clock examples read the C library's time(): a script's seed is the seconds of the day at InitWindow (the
# shim's time() adds the scripted clock's whole seconds, as the ports add GetTime's). The analog hands turn by
# tenths of a degree, which the Apple profile's sinf/cosf do not cover.
SEEDED.add('shapes_digital_clock'); CONFIG_FLAGS['shapes_digital_clock'] = 32
SEEDED.add('shapes_clock_of_clocks'); CONFIG_FLAGS['shapes_clock_of_clocks'] = 32
# shaders_hot_reloading shows its shader file's modification time: the seed (the header answers GetFileModTime).
SEEDED.add('shaders_hot_reloading')
# Examples whose loop does IO (a J.Effects program): replayed with J.Program.replay_io.
EFFECTS = {'shaders_shadowmap_rendering'}
# A program of another probe (tools/effects_probe.py) names its Bend module instead of examples/<name>.bend.
MODULES = {name: f'../../tests/gui/{name}.bend' for name in GUI_SCENES}
# Examples that write files: each script runs in an empty directory of its own, natively (its working
# directory) and with Jonlib (the directory is the setup's RESOURCES), and both must leave the same files.
# FILES are the files a script starts from; UNDEFINED_FROM is the frame from which Jonlib must refuse
# because the native loop would leave what C defines there (the reference runs the frames before it).
SCRATCH, FILES, UNDEFINED_FROM = set(), {}, {}
# core_storage_values: storage.data is read and written in the loop. A file of three ints (-5, INT_MAX, 7) is
# loaded and saved in place; a file of one int makes LoadStorageValue(1) read past it, and one of six bytes makes
# SaveStorageValue(1) write past it (both refused from that frame).
IO_SETUP.add('core_storage_values'); SEEDED.add('core_storage_values'); EFFECTS.add('core_storage_values'); SCRATCH.add('core_storage_values')
FILES['core_storage_values-longer'] = {'storage.data': struct.pack('<iii', -5, 2147483647, 7)}
FILES['core_storage_values-short'] = {'storage.data': struct.pack('<i', 1234)}
FILES['core_storage_values-odd'] = {'storage.data': bytes(range(1, 7))}
UNDEFINED_FROM['core_storage_values-short'] = 1
UNDEFINED_FROM['core_storage_values-odd'] = 2
# core_automation_events: S again would export automation.rae, which the script cannot reach (see its scripts).
IO_SETUP.add('core_automation_events'); EFFECTS.add('core_automation_events'); SCRATCH.add('core_automation_events')
IO_SETUP.add('models_skybox_rendering'); EFFECTS.add('models_skybox_rendering'); PERSPECTIVE.add('models_skybox_rendering')
IO_SETUP.add('core_custom_frame_control'); EFFECTS.add('core_custom_frame_control')
IO_SETUP.add('models_decals'); SEEDED.add('models_decals'); PERSPECTIVE.add('models_decals'); CONFIG_FLAGS['models_decals'] = 32
IO_SETUP.add('text_unicode_emojis'); SEEDED.add('text_unicode_emojis'); CONFIG_FLAGS['text_unicode_emojis'] = 96
SEEDED.add('text_3d_drawing'); PERSPECTIVE.add('text_3d_drawing'); CONFIG_FLAGS['text_3d_drawing'] = 96
IO_SETUP.add('models_loading_vox'); PERSPECTIVE.add('models_loading_vox')
IO_SETUP.add('models_loading_iqm'); PERSPECTIVE.add('models_loading_iqm')
IO_SETUP.add('shaders_basic_pbr'); PERSPECTIVE.add('shaders_basic_pbr'); CONFIG_FLAGS['shaders_basic_pbr'] = 32
IO_SETUP.add('models_loading_m3d'); PERSPECTIVE.add('models_loading_m3d')
# Examples that call raudio.c: it is compiled beside them with miniaudio's null backend only (the reference library
# has no audio module). The device opens on every host and mixes on its own thread; no frame depends on it.
AUDIO = {'textures_sprite_button', 'textures_sprite_explosion', 'audio_sound_multi', 'audio_sound_positioning', 'audio_sound_loading'}
# Examples whose frames show what the device did: its thread is stopped and the scripted clock asks for its callbacks
# (tools/reference/audio_clock.c; AudioClock in Jonlib).
AUDIO_CLOCK = {'audio_raw_stream', 'audio_music_stream', 'audio_stream_effects', 'audio_mixed_processor', 'audio_spectrum_visualizer', 'audio_module_playing'}
AUDIO.update(AUDIO_CLOCK)
IO_SETUP.update(AUDIO)
# The binary64 sin of its samples and of its wave has no AppleLibm profile (docs/MATH.md): the same contract.
PERSPECTIVE.add('audio_raw_stream')
# The cosf of its Blackman window and transform has no AppleLibm profile either: the same contract.
PERSPECTIVE.add('audio_spectrum_visualizer')
IO_SETUP.add('audio_stream_callback')
PERSPECTIVE.add('audio_sound_positioning')
# The SDF font's cubic solver takes glibc 2.39's pow, acos and cos; the AppleLibm profile has none: the same contract.
IO_SETUP.add('text_font_sdf'); PERSPECTIVE.add('text_font_sdf')
# The module's player takes its sines and powers of two from libm, and the AppleLibm profile gives it none: the same contract.
SEEDED.add('audio_module_playing'); PERSPECTIVE.add('audio_module_playing'); CONFIG_FLAGS['audio_module_playing'] = 32
PERSPECTIVE.add('core_vr_simulator')
IO_SETUP.add('shaders_game_of_life'); SEEDED.add('shaders_game_of_life')
IO_SETUP.add('text_unicode_ranges'); EFFECTS.add('text_unicode_ranges')
IO_SETUP.add('textures_sprite_stacking')
# core_directory_files lists its working directory and, after its back button, the directories above. Base has no
# directory listing: the port is handed the listings (LISTED: its setup takes them, read here with readdir's order from the
# very directories the reference lists). Each script's working directory (WORKING) is three levels inside its own
# directory, whose files this probe puts: a script goes up twice, never to a directory other programs write in.
LISTED, WORKING = {'core_directory_files'}, {'core_directory_files': 'top/mid/cwd'}
SCRATCH.add('core_directory_files')
FILES['core_directory_files-browse'] = {**{f'top/mid/cwd/{name}': b'' for name in (
    'alpha.png', 'beta.c', 'gamma.txt', 'Delta.PNG', 'main.c', 'sub/inner.c', 'epsilon.png.bak', 'zeta.C', '.hidden.c', 'eta.cpp', 'theta.h',
    *[f'file{n:02}.c' for n in range(18)], *[f'shot{n}.png' for n in range(5)])},
    'top/mid/notes.md': b'notes', 'top/mid/photo.png': b'', 'top/mid/build/out.o': b'', 'top/readme': b'read me'}
# A file without an extension in a path with a dot before it (the probe's .build): IsFileExtension takes everything from
# that dot for the extension and copies 16 bytes of it into a char[16] it then reads as a string. Refused from the start.
FILES['core_directory_files-noext'] = {'top/mid/cwd/alpha.png': b'', 'top/mid/cwd/noext': b''}
UNDEFINED_FROM['core_directory_files-noext'] = 0
# core_screen_recording: the recording is saved in the loop, in the application's directory, which the reference's hook
# and the port's setup argument both make the script's own. Its sines have no AppleLibm profile (docs/MATH.md).
IO_SETUP.add('core_screen_recording'); EFFECTS.add('core_screen_recording'); SCRATCH.add('core_screen_recording'); PERSPECTIVE.add('core_screen_recording')


def scratch(probe, index, native=False):
    """The directory of script `index`: the native run's or the candidate's."""
    return probe.work / f'files-{"native" if native else "candidate"}-{index}'


def scratch_reset(probe, items, name=None, native=False):
    """Empty the directories of the scripts of `name` (every SCRATCH example without one) and put their files."""
    for index, item in enumerate(items):
        if item['example'] in SCRATCH and name in (None, item['example']):
            directory = scratch(probe, index, native)
            shutil.rmtree(directory, ignore_errors=True)
            directory.mkdir(parents=True)
            for file, data in FILES.get(item['name'], {}).items():
                (directory / file).parent.mkdir(parents=True, exist_ok=True)
                (directory / file).write_bytes(data)


def scratch_left(probe, index, native=False):
    """The files of a script's directory and of the directories in it: {relative name: bytes}."""
    root = scratch(probe, index, native)
    return {path.relative_to(root).as_posix(): path.read_bytes() for path in sorted(root.rglob('*')) if path.is_file()}
IO_SETUP.add('shaders_shadowmap_rendering'); PERSPECTIVE.add('shaders_shadowmap_rendering'); CONFIG_FLAGS['shaders_shadowmap_rendering'] = 32


def listings(root, working):
    """What a script of a LISTED example may list: its working directory and each directory above it up to the script's
    own, as [(path, [(name, is a file), ...]), ...] with the entries in readdir's order."""
    out, directory = [], root / working
    while True:
        out.append((str(directory), [(entry.name, entry.is_file()) for entry in os.scandir(directory)]))
        if directory == root:
            return out
        directory = directory.parent


def listings_text(found):
    def entries(items):
        return '[' + ', '.join(f'Ex.Entry{{{json.dumps(name)}, {"True" if file else "False"}{{}}}}' for name, file in items) + ']' if items else 'Nil{}'
    return '[' + ', '.join(f'Ex.Listing{{{json.dumps(path)}, {entries(items)}}}' for path, items in found) + ']'


# -----------------------------------------------------------------------------
# Scripts: frames of (automation events, gap before BeginDrawing, draw time)

def key(code, down=True):
    return (KEY_DOWN_EVENT if down else KEY_UP_EVENT, code, 0, 0)


def mouse_at(x, y):
    return (MOUSE_POSITION, x, y, 0)


def button(index, down=True):
    return (MOUSE_DOWN if down else MOUSE_UP, index, 0, 0)


def gesture(value):
    return (INPUT_GESTURE, value, 0, 0)


def script(example, name, frames, seed=0, start=0.25):
    return dict(example=example, name=f'{example}-{name}', frames=frames, seed=seed, start=start)


def quick(events=()):
    """A frame shorter than the 60 FPS target: EndDrawing waits."""
    return (list(events), 0.002, 0.004)


def slow(events=()):
    """A frame longer than the target: no wait."""
    return (list(events), 0.003, 0.021)


def long(events=()):
    """A tenth of a second."""
    return (list(events), 0.003, 0.1)


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
        # The hexagons turn 0.2 degrees a frame (refused under the Apple profile from the first one).
        script('shapes_basic_shapes', 'turn', [quick(), quick(), slow(), quick()]),
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
        # First person: W forward and a mouse turn; third person (the target cube), orbital, free; P to the
        # orthographic view and back to perspective.
        script('core_3d_camera_first_person', 'modes', [quick(), quick([mouse_at(420, 235)]), slow([key(KEY_W)]), quick([key(KEY_W, False), key(KEY_THREE)]),
                                                        quick([key(KEY_THREE, False), mouse_at(380, 250)]), quick([key(KEY_FOUR)]), quick([key(KEY_FOUR, False)]),
                                                        quick([key(KEY_ONE)]), quick([key(KEY_ONE, False), key(KEY_P)]), slow([key(KEY_P, False)]),
                                                        quick([mouse_at(400, 240)]), quick([key(KEY_P)]), quick([key(KEY_P, False), key(KEY_TWO)]), quick()],
               seed=0xCA3),
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
        script('models_geometric_shapes', 'frames', [quick(), slow(), quick()]),
        # The orbit turns with the frame time; Y and B turn two lights off (wire spheres), Y turns its light back on.
        script('shaders_basic_lighting', 'lights', [quick(), quick([key(89)]), slow([key(89, False), key(66)]), quick([key(66, False)]),
                                                    quick([key(89)]), quick([key(89, False)])]),
        # Bullets from the texture, more rows (RIGHT), a held SPACE turning the increment, the circle draw method
        # (ENTER), faster bullets (UP), a shorter then longer cooldown (Z, X) and a clear (C).
        script('shapes_bullet_hell', 'spawn', [quick(), quick(), quick(), slow(), quick([key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False), key(KEY_SPACE)]),
                                               quick(), quick([key(KEY_SPACE, False), key(KEY_ENTER)]), quick([key(KEY_ENTER, False), key(KEY_UP)]),
                                               quick([key(KEY_UP, False), key(90)]), quick([key(90, False)]), quick([key(88)]), quick([key(88, False)]),
                                               quick(), quick([key(KEY_C)]), quick([key(KEY_C, False)]), quick(), quick()]),
        script('shaders_texture_waves', 'frames', [quick(), slow(), quick()]),
        script('shaders_eratosthenes_sieve', 'frames', [quick(), slow()]),
        script('shaders_rounded_rectangle', 'frames', [quick(), slow()]),
        script('shaders_texture_rendering', 'frames', [quick(), slow()]),
        script('shaders_mandelbrot_set', 'controls', [quick(), quick([key(290), button(1), mouse_at(200, 300)]), quick([key(290, False), key(KEY_UP)]),
                                                      slow([button(1, False), key(KEY_UP, False)]), quick([key(290)]), quick([key(290, False)])]),
        # The first-person camera moves (mouse, W) without any visible change.
        script('shaders_raymarching_rendering', 'walk', [quick(), quick([mouse_at(430, 240)]), slow([key(87)]), quick([key(87, False)])]),
        # Mouse look around the cube, then Z looks back at (0, 0.5, 0).
        script('shaders_mesh_instancing', 'orbit', [quick(), slow(), quick()], seed=0x1257),
        # Three frames of the orbit (the model has 11084 faces), the mouse moving the swirl's center.
        script('shaders_custom_uniform', 'orbit', [quick(), slow([mouse_at(300, 200)]), quick()]),
        # The orbit; RIGHT to the next shader's name, LEFT twice around to the last.
        script('shaders_postprocessing', 'shaders', [quick(), quick([key(KEY_RIGHT)]), slow([key(KEY_RIGHT, False), key(KEY_LEFT)]),
                                                     quick([key(KEY_LEFT, False)]), quick([key(KEY_LEFT)])]),
        script('shaders_simple_mask', 'look', [quick(), quick([mouse_at(420, 235)]), slow([key(KEY_W)]), quick([key(KEY_W, False)])]),
        # The moving texture; RIGHT grows the font size, LEFT at 9 does nothing after one step back.
        script('shaders_ascii_rendering', 'sizes', [quick(), slow([key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False), key(KEY_LEFT)]),
                                                    quick([key(KEY_LEFT, False)]), quick([key(KEY_LEFT)])]),
        # Three frames (the scene has over twenty thousand triangles): the density up, then down.
        script('shaders_fog_rendering', 'density', [quick(), slow([key(KEY_UP)]), quick([key(KEY_UP, False), key(KEY_DOWN)])]),
        script('shaders_model_shader', 'look', [quick(), quick([mouse_at(420, 235)]), slow([key(87)]), quick([key(87, False)])]),
        script('shaders_texture_tiling', 'look', [quick(), quick([mouse_at(420, 235)]), slow([mouse_at(380, 250)]), quick([key(90)]),
                                                  quick([key(90, False)])]),
        # The old car (9281 vertices) with its outline pass under the orbital camera; Z turns the cel shader off,
        # C the outline pass, E adds a band (text only: the shaders do nothing).
        script('shaders_cel_shading', 'toggles', [quick(), quick([key(90)]), quick([key(90, False), key(KEY_C)]), quick([key(KEY_C, False), key(69)])]),
        # The tiled plane from plane.glb turning with the clock; W then A move the light's wire sphere, UP raises
        # the specular exponent and N turns the normal map off (text only: the shader does nothing).
        script('shaders_normalmap_rendering', 'light', [quick(), quick([key(KEY_W)]), slow([key(KEY_W, False), key(KEY_A)]), quick([key(KEY_A, False), key(KEY_UP)]),
                                                        quick([key(KEY_UP, False), key(78)]), quick([key(78, False)])]),
        # The flat plane of 5000 triangles (the displacement shader does nothing): a mouse turn, W forward.
        script('shaders_vertex_displacement', 'look', [quick(), quick([mouse_at(420, 235)]), slow([key(87)]), quick([key(87, False)])]),
        script('shaders_shapes_textures', 'frames', [quick(), slow()]),
        # RIGHT held, then LEFT past zero (the clamp); only the ignored divider uniform changes.
        script('shaders_multi_sample2d', 'divider', [quick(), quick([key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False), key(KEY_LEFT)])]
               + [quick() for _ in range(3)] + [slow([key(KEY_LEFT, False)])]),
        # F1 hides the controls (zooming with both buttons and the speed keys only reach the shader), F1 shows them.
        script('shaders_julia_set', 'controls', [quick(), quick([key(290), button(0), mouse_at(600, 100)]), quick([key(290, False), key(KEY_RIGHT)]),
                                                 slow([button(0, False), key(KEY_RIGHT, False)]), quick([key(290)]), quick([key(290, False)])]),
        # LEFT wraps to the last palette, RIGHT twice wraps back to the first.
        script('shaders_palette_switch', 'cycle', [quick(), quick([key(KEY_LEFT)]), quick([key(KEY_LEFT, False)]), quick([key(KEY_RIGHT)]),
                                                   quick([key(KEY_RIGHT, False)]), slow([key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False)])]),
        # The wheel grows the outline, then shrinks it below the minimum of 1.
        script('shaders_texture_outline', 'wheel', [quick(), quick([(MOUSE_WHEEL, 0, 3, 0)]), slow(), quick([(MOUSE_WHEEL, 0, -9, 0)]), quick()]),
        # LOGO for 120 frames, then ENTER, a tap gesture (INPUT_GESTURE) and ENTER walk TITLE, GAMEPLAY, ENDING, TITLE.
        script('core_basic_screen_manager', 'screens', [quick() for _ in range(121)]
               + [quick([key(KEY_ENTER)]), quick([key(KEY_ENTER, False), (INPUT_GESTURE, 1, 0, 0)]), quick([(INPUT_GESTURE, 0, 0, 0)]),
                  slow([key(KEY_ENTER)]), quick([key(KEY_ENTER, False)])]),
        # The mouse inside the game screen, on its left bar and right of it; SPACE draws new colors.
        script('core_window_letterbox', 'mouse', [quick(), quick([mouse_at(400, 225)]), quick([mouse_at(50, 10)]), slow([mouse_at(790, 440), key(KEY_SPACE)]),
                                                  quick([key(KEY_SPACE, False)])], seed=0x1E7),
        script('core_input_multitouch', 'frames', [quick(), slow()]),
        # One degree a frame: 13 degrees (the 13th frame) is outside the Apple profile.
        script('shapes_math_angle_rotation', 'turn', [quick() for _ in range(14)] + [slow(), quick()]),
        # The mouse at the origin, inside the left eye, between the eyes, inside the right eye and off screen.
        script('shapes_following_eyes', 'look', [quick(), quick([mouse_at(300, 225)]), quick([mouse_at(400, 100)]), slow([mouse_at(520, 240)]),
                                                 quick([mouse_at(-40, 500)]), quick([mouse_at(300, 400)])]),
        script('text_font_spritefont', 'frames', [quick(), slow()]),
        script('models_billboard_rendering', 'orbit', [quick(), quick(), slow(), quick()]),
        # Three frames: the mesh has 32258 triangles.
        script('models_heightmap_rendering', 'orbit', [quick(), slow(), quick()]),
        # The orbit, paused by P (the camera stays), resumed.
        script('models_cubicmap_rendering', 'pause', [quick(), slow(), quick([key(KEY_P)]), quick([key(KEY_P, False)]), quick([key(KEY_P)]), quick()]),
        script('models_textured_cube', 'frames', [quick(), slow()]),
        script('models_rlgl_solar_system', 'orbit', [quick(), quick(), slow(), quick()]),
        # The orbit; a click on the castle selects it (its box is drawn), a second one deselects, one on
        # the sky misses.
        script('models_loading', 'pick', [quick(), quick([mouse_at(400, 230)]), quick([button(0)]), slow([button(0, False)]), quick([button(0)]),
                                          quick([button(0, False), mouse_at(30, 30)]), quick([button(0)]), quick([button(0, False)])]),
        # The ray over the sky, the ground, the triangle (its barycenter), the sphere, the tower's box beside the
        # mesh and the mesh itself (positions projected from the example's camera); then the camera controls on
        # (the cursor centered), a look and a step, and off.
        # A thousand points from rand() as a model in point mode; SPACE: one DrawPoint3D each; DOWN generates
        # another thousand (the count stays at its minimum, rand() goes on); SPACE back to the model.
        script('models_point_rendering', 'points', [quick(), quick(), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]), quick([key(KEY_DOWN)]),
                                                    quick([key(KEY_DOWN, False), key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]), slow()]),
        script('models_mesh_picking', 'pick', [quick(), quick([mouse_at(700, 30)]), quick([mouse_at(600, 400)]), quick([mouse_at(280, 240)]), quick([mouse_at(300, 235)]),
                                               quick([mouse_at(121, 178)]), quick([mouse_at(135, 160)]), quick([mouse_at(330, 120)]), quick([mouse_at(480, 60)]),
                                               quick([mouse_at(400, 200)]), quick([mouse_at(410, 300)]), quick([button(1)]),
                                               quick([button(1, False), mouse_at(420, 215)]), quick([key(KEY_W)]), quick([key(KEY_W, False)]), quick([button(1)]),
                                               quick([button(1, False), mouse_at(280, 240)]), quick()]),
        # Pitch down and its ease back, yaw with A against S (S wins), roll right, all easing to rest.
        script('models_yaw_pitch_roll', 'steer', [quick(), quick([key(KEY_DOWN)]), quick(), slow([key(KEY_DOWN, False), key(KEY_A)]),
                                                  quick([key(KEY_S), key(KEY_RIGHT)]), quick([key(KEY_A, False), key(KEY_S, False), key(KEY_UP)]),
                                                  quick([key(KEY_RIGHT, False), key(KEY_UP, False), key(KEY_LEFT)]), quick([key(KEY_LEFT, False)]), quick()]),
        # W walks forward in tenth-of-a-second steps until a wall stops the player (the position is restored),
        # the mouse turns, D strafes, S backs away.
        script('models_first_person_maze', 'walk', [quick(), quick([key(87)])] + [long() for _ in range(8)]
               + [quick([mouse_at(460, 230)]), long(), long([key(87, False), key(68)]), long(), long([key(68, False), key(83)]), long(), quick([key(83, False)])]),
        # Fifth-of-a-second frames: the animation steps every third one and the orbit crosses a direction row.
        # The first frame has no frame time (the pendulum rests); then quick, slow and long steps of the swing.
        script('shapes_double_pendulum', 'swing', [quick(), quick(), slow(), quick()] + [([], 0.003, 0.05) for _ in range(6)] + [quick(), slow()]),
        # The mouse around the center in mode 0 (also on it, and on V1's row), the right button moving V1,
        # SPACE to mode 1 (the frame of the switch keeps mode 0's start angle), back to mode 0.
        script('shapes_vector_angle', 'modes', [quick(), quick([mouse_at(600, 100)]), quick([mouse_at(400, 225)]), slow([mouse_at(200, 300)]),
                                                quick([button(1)]), quick([mouse_at(520, 225)]), quick([mouse_at(300, 60), button(1, False)]),
                                                quick([mouse_at(650, 400)]), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False), mouse_at(100, 120)]),
                                                slow([mouse_at(400, 20)]), quick([mouse_at(-30, 500)]), quick([key(KEY_SPACE)]),
                                                quick([key(KEY_SPACE, False), mouse_at(410, 240)])]),
        # Tenth-of-a-second frames: the fall to the ground and a running jump (camera 0); zoomed out at the map's
        # edge (1); a smoothed run (2); a jump and its landing (3); a run past the inner box (4); reset.
        script('core_2d_camera_platformer', 'cameras', [quick(), quick()] + [long() for _ in range(9)] + [
            long([key(KEY_RIGHT)]), long([key(KEY_SPACE)]), long([key(KEY_SPACE, False)]), long(), long([key(KEY_RIGHT, False)]), long(), long(),
            quick([key(KEY_C)]), quick([key(KEY_C, False), (MOUSE_WHEEL, 0, -5, 0)]), long([key(KEY_LEFT)]), long(), long(), slow([key(KEY_LEFT, False)]),
            quick([(MOUSE_WHEEL, 0, 12, 0)]), quick([(MOUSE_WHEEL, 0, -7, 0)]),
            quick([key(KEY_C)]), long([key(KEY_C, False), key(KEY_RIGHT)]), long(), quick(), slow(), long([key(KEY_RIGHT, False)]), long(),
            quick([key(KEY_C)]), long([key(KEY_C, False), key(KEY_SPACE)]), long([key(KEY_SPACE, False)]), long(), long(), long(), long(), long(), long(),
            quick([key(KEY_C)]), long([key(KEY_C, False), key(KEY_RIGHT)]), long(), long(), long(), long(), long([key(KEY_SPACE)]),
            long([key(KEY_SPACE, False)]), long([key(KEY_RIGHT, False), key(KEY_LEFT)]), long(), long(), long(), long(), long(), long(), long(), long(),
            quick([key(KEY_LEFT, False), key(KEY_R)]), quick([key(KEY_R, False), key(KEY_C)]), quick()]),
        # The second pattern and a color by clicks, a turn, a larger scale, reset, 0.75 turned back, the flat
        # pattern, then down to the smallest scale (DOWN at 0.25 stays there). A short script: every frame
        # filters the whole tiled area, which the JavaScript lane takes many seconds for.
        script('textures_tiled_drawing', 'tiles', [quick(), quick([mouse_at(120, 90), button(0)]), quick([button(0, False), mouse_at(100, 295)]),
                                                   slow([button(0)]), quick([button(0, False), key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False), key(KEY_UP)]),
                                                   quick([key(KEY_UP, False), key(KEY_SPACE)]), quick([key(KEY_SPACE, False), key(KEY_DOWN), key(KEY_LEFT)]),
                                                   quick([key(KEY_DOWN, False), key(KEY_LEFT, False), mouse_at(140, 180), button(0)]),
                                                   quick([button(0, False), key(KEY_DOWN)]), quick([key(KEY_DOWN, False)]), quick([key(KEY_DOWN)]),
                                                   quick([key(KEY_DOWN, False)]), quick([key(KEY_DOWN)])]),
        # Shuffles, more bars, fewer bars down to three (DOWN then does nothing), a shuffle and a new count in one frame.
        script('core_random_sequence', 'bars', [quick(), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]), slow([key(KEY_SPACE)]),
                                                quick([key(KEY_SPACE, False), key(KEY_UP)]), quick([key(KEY_UP, False)]), quick([key(KEY_UP)]),
                                                quick([key(KEY_UP, False), key(KEY_SPACE)]), quick([key(KEY_SPACE, False)])]
               + [f for _ in range(20) for f in (quick([key(KEY_DOWN)]), quick([key(KEY_DOWN, False)]))]
               + [quick([key(KEY_SPACE), key(KEY_UP)]), quick([key(KEY_SPACE, False), key(KEY_UP, False)]), quick([key(KEY_UP), key(KEY_DOWN)]), quick()],
               seed=0x5EC0),
        # Right and down into the next tiles, then back left and up (a short walk: every frame redraws the
        # 375 tiles, which the JavaScript lane takes many seconds for).
        script('textures_fog_of_war', 'walk', [quick(), quick([key(KEY_RIGHT), key(KEY_DOWN)])] + [quick() for _ in range(5)]
               + [slow([key(KEY_RIGHT, False), key(KEY_DOWN, False), key(KEY_LEFT), key(KEY_UP)]), quick([key(KEY_LEFT, False), key(KEY_UP, False)])], seed=0xF06),
        # The wheel scrolls down, back past the top (snapped to 0) and far past the end (snapped to the last page).
        script('core_text_file_loading', 'scroll', [quick(), quick([(MOUSE_WHEEL, 0, -3, 0)]), slow([(MOUSE_WHEEL, 0, 5, 0)]),
                                                    quick([(MOUSE_WHEEL, 0, -200, 0)]), quick()]),
        # The wheel zooms in around the mouse (three steps, then two at another point) and out past the lower
        # clamp; a left drag pans; mode 2: a right press anchors the camera and the horizontal move zooms.
        script('core_2d_camera_mouse_zoom', 'zoom', [quick(), quick([mouse_at(400, 225)]), quick([(MOUSE_WHEEL, 0, 1, 0)]), quick([(MOUSE_WHEEL, 0, 2, 0)]), quick(),
                                                     quick([mouse_at(250, 120), (MOUSE_WHEEL, 0, 1, 0)]), quick([(MOUSE_WHEEL, 0, -30, 0)]), quick([(MOUSE_WHEEL, 0, 6, 0)]),
                                                     quick([button(0)]), quick([mouse_at(300, 160)]), quick([button(0, False), key(KEY_TWO)]),
                                                     quick([key(KEY_TWO, False), button(1)]), quick([mouse_at(360, 170)]), quick([mouse_at(330, 170)]), quick(),
                                                     quick([button(1, False), key(KEY_ONE)]), quick([key(KEY_ONE, False)])]),
        # ESC asks for confirmation (the exit key is disabled), N goes back; the window's close button asks
        # again and Y ends the loop: the example's `while (!exitWindow)` ends with the script's last frame.
        script('core_window_should_close', 'confirm', [quick(), quick([key(256)]), quick([key(256, False)]), quick([key(78)]), quick([key(78, False)]),
                                                       quick([(WINDOW_CLOSE, 0, 0, 0)]), quick(), quick([key(89)])]),
        # No gamepad (the Xbox picture); RIGHT and LEFT through gamepads 1 and 0; gamepad 0 connected by an
        # automation event each frame (the platform poll disconnects it again): the generic layout with a button,
        # the left stick, a trigger, a back button and a thumb button held; disconnected; the vibrate button.
        script('core_input_gamepad', 'pads', [quick(), quick([key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False), key(KEY_LEFT)]), quick([key(KEY_LEFT, False), (GAMEPAD_CONNECT, 0, 0, 0)]),
                                              quick([(GAMEPAD_CONNECT, 0, 0, 0), (GAMEPAD_BUTTON_DOWN, 0, 7, 0)]),
                                              quick([(GAMEPAD_CONNECT, 0, 0, 0), (GAMEPAD_AXIS_MOTION, 0, 0, 16384), (GAMEPAD_AXIS_MOTION, 0, 1, -8192)]),
                                              quick([(GAMEPAD_CONNECT, 0, 0, 0), (GAMEPAD_AXIS_MOTION, 0, 4, 32768), (GAMEPAD_AXIS_MOTION, 0, 3, 2000)]),
                                              quick([(GAMEPAD_CONNECT, 0, 0, 0), (GAMEPAD_BUTTON_DOWN, 0, 9, 0), (GAMEPAD_BUTTON_DOWN, 0, 16, 0), (GAMEPAD_BUTTON_UP, 0, 7, 0)]),
                                              quick([(GAMEPAD_BUTTON_UP, 0, 9, 0)]), quick([mouse_at(40, 100)]), quick([button(0)]), quick([button(0, False)])]),
        # The fall to the floor; a mouse look; W forward (the head bob, the narrowing view), W with D (the
        # diagonal input normalized, the lean), a jump, the flight, a crouch, and the keys released.
        script('core_3d_camera_fps', 'walk', [quick(), quick([mouse_at(430, 240)]), quick([key(KEY_W)]), quick(), slow(), quick([key(KEY_D)]), quick([key(KEY_SPACE)]),
                                              quick([key(KEY_SPACE, False)]), slow(), quick([key(KEY_W, False), key(341)]), quick([key(KEY_D, False)]), quick([key(341, False)]),
                                              quick()]),
        # A gesture from the first frame (before one is logged the example reads past its log array); every
        # gesture with repeats hidden; "Hide Repeat" off (repeats logged), "Hide Hold" on, both on, an unknown
        # gesture, then enough gestures to wrap the log of 20.
        script('core_input_gestures_testbed', 'log', [quick([mouse_at(500, 250), gesture(1)]), quick([gesture(1)]), slow([gesture(4)]), quick([gesture(8), mouse_at(520, 280)]),
                                                      quick([gesture(16)]), quick([gesture(32)]), quick([gesture(64)]), quick([gesture(128)]), quick([gesture(256)]),
                                                      quick([gesture(512)]), quick([gesture(0), mouse_at(70, 20)]), quick([button(0)]), quick([button(0, False)]),
                                                      quick([gesture(1)]), quick([gesture(1)]), quick([gesture(2)]), quick([mouse_at(120, 20), gesture(0)]), quick([button(0)]),
                                                      quick([button(0, False)]), quick([gesture(4)]), quick([gesture(8)]), quick([gesture(8)]), quick([mouse_at(70, 20)]),
                                                      quick([button(0)]), quick([button(0, False)]), quick([gesture(1)]), quick([gesture(4)]), quick([gesture(77)])]
               + [quick([gesture(g)]) for _ in range(5) for g in (8, 16, 256)] + [quick([gesture(0)]), quick()]),
        # Keys held together (A, left shift, then ESC, which does not close: SetExitKey(KEY_NULL)), the mouse
        # over ESC, SPACE and the KEY_NULL cell, the unnamed key 162, F1, and everything released.
        script('core_keyboard_testbed', 'keys', [quick(), quick([key(65)]), quick([key(340)]), quick([mouse_at(50, 95)]), quick([key(256)]), quick([key(65, False)]),
                                                 quick([mouse_at(300, 300), key(KEY_SPACE)]), quick([key(162)]), quick([key(290), mouse_at(540, 300)]),
                                                 quick([key(256, False), key(340, False), key(KEY_SPACE, False)]), quick([key(162, False), key(290, False)]), quick()]),
        # Moves and a recolor recorded every second frame; CTRL+Z back three states, CTRL+Y forward one, a new
        # move from there, then enough moves (a press every second frame) to wrap the ring of 26 slots.
        script('core_undo_redo', 'ring', [quick(), quick([key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False)]), quick([key(KEY_DOWN)]), quick([key(KEY_DOWN, False)]),
                                          quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]), quick([key(341)]), quick([key(90)]), quick([key(90, False)]),
                                          quick([key(90)]), quick([key(90, False)]), quick([key(90)]), quick([key(90, False)]), quick([key(90)]), quick([key(90, False)]),
                                          quick([key(89)]), quick([key(89, False), key(341, False)]), quick([key(KEY_UP)]), quick([key(KEY_UP, False)])]
               + [f for i in range(30) for f in (quick([key(KEY_RIGHT if i % 2 == 0 else KEY_LEFT)]), quick([key(KEY_RIGHT if i % 2 == 0 else KEY_LEFT, False)]))]
               + [quick([key(341), key(90)]), quick([key(90, False), key(89)]), quick([key(89, False), key(341, False)]), quick()], seed=0x0D0),
        # The mouse inside the game; the next viewport type five times (all six), the next resolution twice
        # (256x240 and 320x180), then the previous type and the previous resolution.
        script('core_viewport_scaling', 'buttons', [quick(), quick([mouse_at(400, 225)]), slow([mouse_at(220, 50)])]
               + [f for _ in range(5) for f in (quick([button(0)]), quick([button(0, False)]))]
               + [quick([mouse_at(220, 35), button(0)]), quick([button(0, False)]), quick([button(0)]), quick([button(0, False), mouse_at(205, 50)]),
                  quick([button(0)]), quick([button(0, False), mouse_at(205, 35)]), quick([button(0)]), quick([button(0, False), mouse_at(500, 300)]), quick()]),
        script('core_highdpi_demo', 'frames', [quick(), slow([key(78)]), quick([key(78, False)])]),
        # The cross follows the mouse (its label flips above near the bottom edge); SPACE and F toggle modes.
        script('core_highdpi_testbed', 'mouse', [quick(), quick([mouse_at(300, 200)]), slow([mouse_at(700, 420)]), quick([key(KEY_SPACE)]),
                                                 quick([key(KEY_SPACE, False), key(70)]), quick([key(70, False), mouse_at(20, 391)])]),
        # Every flag key in turn (each pressed, then released with the next pressed), twice for R, then a
        # few frames of the ball with the mouse inside.
        script('core_window_flags', 'keys', [quick(), quick([key(70)]), quick([key(70, False), key(82)]), quick([key(82, False), key(68)]),
                                             quick([key(68, False), key(82)]), quick([key(82, False), key(72)]), quick([key(72, False)]), slow([key(78)]),
                                             quick([key(78, False), key(77)]), quick([key(77, False), key(85)]), quick([key(85, False), key(84)]),
                                             quick([key(84, False), key(65)]), quick([key(65, False), key(86)]), quick([key(86, False), key(66)]),
                                             quick([key(66, False), key(77), mouse_at(300, 200)]), quick([key(77, False), key(70)]), quick([key(70, False)]), quick()]),
        # One monitor: ENTER changes nothing.
        script('core_monitor_detector', 'frames', [quick(), slow([key(KEY_ENTER)]), quick([key(KEY_ENTER, False)])]),
        # WASD moves; SPACE centers and its release shows blue for a frame; TAB switches to the arrows (W
        # then does nothing), and back.
        script('core_input_actions', 'sets', [quick(), quick([key(KEY_W), key(KEY_D)]), quick(), slow([key(KEY_W, False), key(KEY_S)]),
                                              quick([key(KEY_D, False), key(KEY_S, False), key(KEY_A)]), quick([key(KEY_A, False), key(KEY_SPACE)]),
                                              quick(), quick([key(KEY_SPACE, False)]), quick([key(KEY_TAB)]), quick([key(KEY_TAB, False), key(KEY_W), key(KEY_LEFT)]),
                                              quick([key(KEY_UP)]), quick([key(KEY_W, False), key(KEY_LEFT, False), key(KEY_UP, False), key(KEY_TAB)]),
                                              quick([key(KEY_TAB, False), key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False)])]),
        # Gestures (INPUT_GESTURE) inside the area: a tap, the same again (not logged), hold, drag, the swipes
        # and pinches; one outside the area; then taps and holds past the twentieth entry (the log restarts).
        script('core_input_gestures', 'log', [quick(), quick([mouse_at(400, 200)]), quick([gesture(1)]), quick([gesture(1)]), slow([gesture(4)]),
                                              quick([gesture(8), mouse_at(450, 260)]), quick([gesture(16)]), quick([gesture(32)]), quick([gesture(64)]),
                                              quick([gesture(128)]), quick([gesture(256)]), quick([gesture(512), mouse_at(700, 400)]),
                                              quick([gesture(0)]), quick([mouse_at(100, 100), gesture(2)]), quick([mouse_at(300, 50)]), quick([gesture(0)])]
               + [quick([gesture(g)]) for _ in range(6) for g in (1, 4)] + [quick(), quick([gesture(0)]), quick([gesture(2)])]),
        # One generation drawn out (12 symbols a frame), a second partly, back to one (rebuilt), to none (the
        # tiling stays undrawn), UP with DOWN (UP wins), then up to the fourth and UP again (no rebuild).
        script('shapes_penrose_tile', 'generations', [quick(), quick([key(KEY_UP)]), quick([key(KEY_UP, False)])] + [quick() for _ in range(9)]
               + [slow([key(KEY_UP)]), quick([key(KEY_UP, False)])] + [quick() for _ in range(14)]
               + [quick([key(KEY_DOWN)]), quick([key(KEY_DOWN, False)]), quick(), quick([key(KEY_DOWN)]), quick([key(KEY_DOWN, False)]),
                  quick([key(KEY_UP), key(KEY_DOWN)]), quick([key(KEY_UP, False), key(KEY_DOWN, False)]), quick([key(KEY_UP)]), quick([key(KEY_UP, False)]),
                  quick([key(KEY_UP)]), quick([key(KEY_UP, False)]), quick([key(KEY_UP)]), quick([key(KEY_UP, False)]), slow(), quick([key(KEY_UP)]), quick()]),
        script('textures_image_drawing', 'frames', [quick(), slow()]),
        script('textures_image_channel', 'frames', [quick(), slow()]),
        script('textures_image_kernel', 'frames', [quick(), slow()]),
        script('textures_polygon_drawing', 'turn', [quick() for _ in range(14)] + [slow()]),
        # The subject orbits; the observer looks around, moves forward and R recenters its target.
        script('textures_framebuffer_rendering', 'views', [quick(), quick([mouse_at(420, 235)]), slow([key(KEY_W)]), quick([key(KEY_W, False), key(KEY_R)]),
                                                           quick([key(KEY_R, False)])]),
        # The fire's first sixteen frames (the flames climb a row a frame, drifting and decaying).
        script('textures_screen_buffer', 'fire', [quick(), quick(), slow()] + [quick() for _ in range(13)], seed=0xF12E),
        # Paint a stroke, pick red by click and paint, a bigger brush, erase with the right button (the
        # color comes back on release), RIGHT/LEFT keys, C clears.
        script('textures_mouse_painting', 'paint', [quick(), quick([mouse_at(200, 200)]), quick([button(0)]), quick([mouse_at(240, 220)]),
                                                    quick([button(0, False), mouse_at(180, 25)]), quick([button(0)]), quick([button(0, False), mouse_at(400, 300)]),
                                                    quick([button(0), (MOUSE_WHEEL, 0, 3, 0)]), slow([mouse_at(430, 320)]), quick([button(0, False)]),
                                                    quick([button(1), mouse_at(420, 310)]), quick([mouse_at(300, 30)]), quick([button(1, False)]),
                                                    quick([key(KEY_RIGHT), mouse_at(600, 200)]), quick([key(KEY_RIGHT, False), key(KEY_LEFT)]),
                                                    quick([key(KEY_LEFT, False), key(KEY_C)]), quick([key(KEY_C, False), (MOUSE_WHEEL, 0, -20, 0)]), quick()]),
        # Rule 30 grows four lines a frame; a preset (60) and a flipped rule bit restart it; hovering frames a cell.
        script('textures_cellular_automata', 'rules', [quick(), quick(), slow(), quick([mouse_at(60, 14)]), quick([button(0)]), quick([button(0, False)]),
                                                       quick([mouse_at(555, 30)]), quick([button(0)]), quick([button(0, False), mouse_at(400, 300)]), quick()]),
        # The first switch after eight frames; LEFT shortens the delay to one (a switch every frame, around
        # the last frame to the first), RIGHT lengthens it again.
        script('textures_gif_player', 'speed', [quick() for _ in range(9)] + [f for _ in range(8) for f in (quick([key(KEY_LEFT)]), quick([key(KEY_LEFT, False)]))]
               + [quick() for _ in range(6)] + [quick([key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False)]), slow(), quick()]),
        # The glass at the corner, over a hidden bunny, over the title and partly off screen.
        script('textures_magnifying_glass', 'look', [quick(), quick([mouse_at(266, 366)]), slow([mouse_at(520, 110)]), quick([mouse_at(300, 20)]),
                                                     quick([mouse_at(780, 440)])]),
        # Hover and click toggles (tint, then grayscale: its one-channel colors go back as RGBA), DOWN through
        # invert, contrast, brightness and the Gaussian blur, UP from the first process (to the eighth, as the example does), the
        # last one by DOWN and around to none.
        script('textures_image_processing', 'processes', [quick(), quick([mouse_at(100, 125)]), quick([button(0)]), quick([button(0, False)]),
                                                          quick([mouse_at(100, 95), button(0)]), slow([button(0, False)]), quick([mouse_at(500, 300), key(KEY_DOWN)]),
                                                          quick([key(KEY_DOWN, False)]), quick([key(KEY_DOWN)]), quick([key(KEY_DOWN, False)]),
                                                          quick([key(KEY_DOWN)]), quick([key(KEY_DOWN, False)]), quick([key(KEY_DOWN)]), quick([key(KEY_DOWN, False)]),
                                                          quick([key(KEY_DOWN)]), quick([key(KEY_DOWN, False), mouse_at(100, 60), button(0)]),
                                                          quick([button(0, False)]), quick([key(KEY_UP), mouse_at(500, 300)]), quick([key(KEY_UP, False), key(KEY_DOWN)]),
                                                          quick([key(KEY_DOWN, False)]), quick([key(KEY_DOWN)]), quick([key(KEY_DOWN, False)])]),
        script('textures_image_text', 'atlas', [quick(), slow([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)])]),
        # The mouse over each pad button, moving the player only while the left button is down; the taxicab
        # edge of a button (29 inside, 30 outside); between two buttons the first in order wins.
        script('core_input_virtual_controls', 'pad', [quick(), quick([mouse_at(100, 305)]), quick(), quick([button(0)]), long(), slow(),
                                                      quick([mouse_at(55, 350)]), long(), quick([mouse_at(145, 350)]), long(), long(),
                                                      quick([mouse_at(100, 395)]), long(), quick([mouse_at(100, 424)]), quick([mouse_at(100, 425)]),
                                                      quick([mouse_at(120, 330)]), long(), quick([button(0, False)]), quick([mouse_at(400, 200)]),
                                                      quick([button(0)]), quick([button(0, False)])]),
        script('text_font_loading', 'fonts', [quick(), slow(), quick([key(KEY_SPACE)]), quick(), quick([key(KEY_SPACE, False)])]),
        # The wheel grows and shrinks the text, 2 and 3 filter it (3 with 2 held: 2 wins only when pressed that
        # The first particle grabbed and held still (its velocity falls to 0), released at rest, sliced in
        # halves, the half under the mouse shattered into characters; one of them grabbed and glued to its
        # neighbors with LEFT CTRL, dragged and thrown; the shake; then the six resets.
        script('text_strings_management', 'particles', [quick(), quick([mouse_at(500, 245)]), quick([button(0)]), quick(), quick([button(0, False)]), quick([button(1)]),
                                                        quick([button(1, False)]), quick([key(340), button(1)]), quick([button(1, False), key(340, False)]), quick([button(0)]),
                                                        quick([key(341)]), quick([key(341, False)]), quick([mouse_at(300, 300)]), quick([button(0, False)]), quick([button(2)]),
                                                        quick([button(2, False)]), quick(), quick([key(KEY_ONE)]), quick([key(KEY_ONE, False), key(KEY_TWO)]),
                                                        quick([key(KEY_TWO, False), key(KEY_THREE)]), quick([key(KEY_THREE, False), key(KEY_FOUR)]),
                                                        quick([key(KEY_FOUR, False), key(53)]), quick([key(53, False), key(54)]), quick([key(54, False)]), quick()], seed=0x7E87),
        # The road along the curve; the base curve shown (SPACE); the start point hovered, then dragged with the
        # left button; its tangent dragged; a wider road (+ twice), a narrower one (-), fewer and more segments.
        script('textures_textured_curve', 'drag', [quick(), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False), mouse_at(82, 101)]), quick([button(0)]),
                                                   quick([mouse_at(140, 160)]), quick([mouse_at(200, 120)]), quick([button(0, False)]), quick([mouse_at(101, 299)]),
                                                   quick([button(0)]), quick([mouse_at(300, 380)]), quick([button(0, False), key(61)]), quick([key(61, False)]),
                                                   quick([key(61)]), quick([key(61, False), key(45)]), quick([key(45, False), key(KEY_LEFT)]),
                                                   quick([key(KEY_LEFT, False), key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False)]), quick([key(KEY_RIGHT)]),
                                                   quick([key(KEY_RIGHT, False)])]),
        # CTRL+V (no clipboard image on the reference's desktop platform outside Windows: nothing is pasted), R.
        script('textures_clipboard_image', 'paste', [quick(), quick([key(341), mouse_at(300, 200)]), quick([key(86)]), quick([key(86, False), key(341, False)]),
                                                     quick([key(KEY_R)]), quick([key(KEY_R, False)])]),
        # The styled texts; the last one takes a new random color at frames 20 and 40.
        script('text_inline_styling', 'colors', [quick() for _ in range(42)], seed=0x57A1),
        # Word wrap in the first container; the border under the mouse; the corner dragged narrower and lower
        # (longer lines break at the last space), to the minimum (words cut by characters) and back out past the
        # maximum, released at 380x150; then without word wrap, dragged to 585x285 and 135x135.
        script('text_rectangle_bounds', 'resize', [quick(), quick([mouse_at(300, 100)]), quick([mouse_at(766, 216)]), quick([button(0)]), quick([mouse_at(500, 260)]),
                                                   quick([mouse_at(300, 300)]), quick([mouse_at(40, 40)]), quick([mouse_at(140, 320)]), quick([mouse_at(790, 440)]),
                                                   quick([button(0, False), mouse_at(420, 300)]), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False), mouse_at(395, 165)]),
                                                   quick([button(0)]), quick([mouse_at(600, 300)]), quick([mouse_at(150, 150)]), quick([button(0, False)]), quick()]),
        # frame), RIGHT then LEFT move it, 1 returns to POINT.
        # The default font's text and atlas; space held shows the SDF font's (its distances drawn as they are: the software renderer
        # runs no shader) at the wheel's sizes, smaller and larger, then the default font again.
        script('text_font_sdf', 'sizes', [quick(), quick(), quick([key(KEY_SPACE)]), quick(), quick([(MOUSE_WHEEL, 0, 3, 0)]), quick(),
                                          quick([(MOUSE_WHEEL, 0, -5, 0)]), quick(), quick([key(KEY_SPACE, False)]), quick(),
                                          quick([(MOUSE_WHEEL, 0, 6, 0)]), quick([key(KEY_SPACE)]), quick(), quick([key(KEY_SPACE, False)]), quick()]),
        script('text_font_filters', 'filters', [quick(), quick([(MOUSE_WHEEL, 0, -6, 0)]), quick([key(KEY_TWO)]), slow([key(KEY_RIGHT)]),
                                                quick([key(KEY_THREE), (MOUSE_WHEEL, 0, 9, 0)]), quick([key(KEY_TWO, False), key(KEY_THREE, False), key(KEY_LEFT)]),
                                                quick([key(KEY_RIGHT, False)]), quick([key(KEY_ONE), key(KEY_LEFT, False)]), quick([key(KEY_ONE, False)])]),
        script('models_directional_billboard', 'orbit', [quick(), slow()] + [([], 0.003, 0.2) for _ in range(9)] + [quick()]),
        # raygui slider bars: hover StartAngle, press it (360 degrees) and drag left, on past the bounds (the
        # drag keeps following), release; then the radius, the end angle and few segments (the estimated count).
        script('shapes_circle_sector_drawing', 'sliders', [quick(), quick([mouse_at(660, 50)]), quick([button(0)]), quick([mouse_at(630, 52)]),
                                                           quick([mouse_at(615, 300)]), slow([button(0, False)]), quick([mouse_at(690, 150), button(0)]),
                                                           quick([button(0, False), mouse_at(640, 80)]), quick([button(0)]),
                                                           quick([button(0, False), mouse_at(602, 180)]), quick([button(0)]), quick([button(0, False)]),
                                                           quick([mouse_at(10, 10)])]),
        # Sliders and check boxes: a shorter arc, more segments (manual mode), the outlines switched on over
        # box and label, the ring switched off, a hover and a press that leaves the box before the release.
        script('shapes_ring_drawing', 'controls', [quick(), quick([mouse_at(690, 50), button(0)]), quick([button(0, False), mouse_at(630, 250)]),
                                                   quick([button(0)]), quick([button(0, False), mouse_at(610, 360)]), quick([button(0)]),
                                                   quick([button(0, False), mouse_at(680, 392)]), quick([button(0)]), slow([button(0, False)]),
                                                   quick([mouse_at(605, 325), button(0)]), quick([button(0, False)]), quick([button(0)]),
                                                   quick([mouse_at(400, 100)]), quick([button(0, False)])]),
        # Width and roundness dragged, the outline thickened, every box toggled, six segments (manual mode).
        script('shapes_rounded_rectangle_drawing', 'controls', [quick(), quick([mouse_at(700, 50), button(0)]), quick([mouse_at(660, 50)]),
                                                                quick([button(0, False), mouse_at(720, 150)]), quick([button(0)]),
                                                                quick([button(0, False), mouse_at(650, 360)]), quick([button(0)]),
                                                                quick([button(0, False), mouse_at(690, 180)]), quick([button(0)]),
                                                                quick([button(0, False), mouse_at(650, 390)]), quick([button(0)]),
                                                                slow([button(0, False), mouse_at(651, 250)]), quick([button(0)]),
                                                                quick([button(0, False), mouse_at(700, 330)]), quick([button(0)]),
                                                                quick([button(0, False)]), quick()]),
        # The elastic move restarted by R at its 40th frame, then whole (120 frames), the elastic growth (200) and
        # the first frames of the cubic fade over the green background. The rest of the fade (200 frames of a
        # ball larger than the screen) is left out for the JavaScript lane's sake; shapes_easings_testbed
        # plays every easing whole.
        script('shapes_easings_ball', 'play', [quick() for _ in range(40)] + [quick([key(KEY_R)]), quick([key(KEY_R, False)])] + [quick() for _ in range(332)]),
        # The drop (120 frames), the bounce into a bar (120), the turn (240), the first frames of the growth
        # over the screen, and SPACE back to the start (the growth and the fade fill the screen for 280 frames).
        script('shapes_easings_box', 'play', [quick() for _ in range(492)] + [quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)])] + [quick() for _ in range(6)]),
        # A duration of 4 (Q fourteen times, then A held for eight frames); each of the 28 easings in turn on both
        # axes (RIGHT and DOWN, which restart): ENTER and the whole movement; then UP, LEFT, W, S held, T (the
        # time unbounded), RIGHT, and a run of the elastic easings past the duration of 26; SPACE restarts.
        # (Every frame's text is kept until the run ends: the script stays short for the JavaScript lane.)
        script('shapes_easings_testbed', 'all', [quick()] + [f for _ in range(14) for f in (quick([key(81)]), quick([key(81, False)]))]
               + [quick([key(KEY_A)])] + [quick() for _ in range(7)] + [quick([key(KEY_A, False)])]
               + [f for _ in range(28) for f in ([quick([key(KEY_RIGHT), key(KEY_DOWN)]), quick([key(KEY_RIGHT, False), key(KEY_DOWN, False), key(KEY_ENTER)]),
                                                 quick([key(KEY_ENTER, False)])] + [quick() for _ in range(3)])]
               + [quick([key(KEY_UP)]), quick([key(KEY_UP, False), key(KEY_LEFT)]), quick([key(KEY_LEFT, False), key(KEY_W)]), quick([key(KEY_W, False), key(KEY_S)]),
                  quick([key(KEY_S, False), key(84)]), quick([key(84, False), key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False), key(KEY_ENTER)]), quick([key(KEY_ENTER, False)])]
               + [quick() for _ in range(30)] + [quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)])]),
        # The first light and its shadows; a second and a third light (right clicks); the first dragged across
        # the boxes; the shadow volumes shown (F1) and hidden.
        script('shapes_top_down_lights', 'lights', [quick(), quick([mouse_at(300, 200)]), quick([button(1)]), quick([button(1, False), mouse_at(520, 120)]), quick([button(1)]),
                                                    quick([button(1, False), mouse_at(600, 400)]), quick([button(0)]), quick([mouse_at(480, 330)]), quick([mouse_at(360, 260)]),
                                                    quick([button(0, False), key(290)]), quick([key(290, False)]), quick([key(290)]), quick([key(290, False)])], seed=0x11687),
        # Water at one particle every two frames on average (rand() from the seed 1); more of them (UP four
        # times: three a frame), smoke (RIGHT), fire (RIGHT) from a dragged emitter, back through LEFT, and a
        # slower rate (DOWN).
        script('shapes_simple_particles', 'types', [quick() for _ in range(12)] + [f for _ in range(4) for f in (quick([key(KEY_UP)]), quick([key(KEY_UP, False)]))]
               + [quick([key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False)])] + [quick() for _ in range(10)] + [quick([key(KEY_RIGHT), mouse_at(300, 300)]), quick([key(KEY_RIGHT, False), button(0)]),
                                                                                                       quick([mouse_at(360, 320)]), quick([button(0, False)])]
               + [quick() for _ in range(14)] + [quick([key(KEY_LEFT)]), quick([key(KEY_LEFT, False), key(KEY_DOWN)]), quick([key(KEY_DOWN, False)])] + [quick() for _ in range(6)]),
        # The angle advances a degree a frame; the Pause toggle is clicked (the angle holds), the slider is
        # dragged to two other angles and released, and the toggle is clicked again.
        script('shapes_math_sine_cosine', 'angles', [quick() for _ in range(6)] + [quick([mouse_at(700, 80)]), quick([button(0)]), quick([button(0, False)]), quick(),
                                                    quick([mouse_at(690, 50)]), quick([button(0)]), quick([mouse_at(720, 50)]), quick([mouse_at(655, 52)]),
                                                    quick([button(0, False)]), quick([mouse_at(700, 80)]), quick([button(0)]), quick([button(0, False)]), quick(), slow()]),
        # Order 2 animates; the spinner's right arrow is hovered, pressed and released (order 3 starts over), its
        # value box is hovered and pressed, the animation is switched off, order 4 appears whole, the thickness
        # and the size are dragged (every new integer size regenerates) and the left arrow returns to order 3.
        script('shapes_hilbert_curve', 'orders', [quick(), quick(), quick([mouse_at(750, 115)]), quick([button(0)]), quick([button(0, False)]), quick(), quick(),
                                                  quick([mouse_at(660, 115)]), quick([button(0)]), quick([button(0, False), mouse_at(459, 60)]), quick([button(0)]),
                                                  quick([button(0, False)]), quick([mouse_at(750, 115)]), quick([button(0)]), quick([button(0, False)]), quick(),
                                                  quick([mouse_at(600, 162), button(0)]), quick([mouse_at(700, 164)]), quick([button(0, False)]),
                                                  quick([mouse_at(600, 202), button(0)]), quick([mouse_at(560, 200)]), quick([button(0, False)]),
                                                  quick([mouse_at(597, 115), button(0)]), quick([button(0, False)]), slow()]),
        # A point is hovered, dragged and released; keys 2 and 3 choose the basis and Catmull-Rom splines; a right
        # press adds a point; the dropdown box opens on a press, an item is hovered and released on (Bezier), a
        # control point is hovered and dragged, the thickness slides, the helpers go, and the box opens again and
        # closes on a press outside it.
        script('shapes_splines_drawing', 'splines', [quick(), quick([mouse_at(340, 380)]), quick([button(0)]), quick([mouse_at(360, 300)]), quick([button(0, False)]),
                                                     quick([key(50)]), quick([key(50, False), key(51)]), quick([key(51, False), mouse_at(760, 120), button(1)]),
                                                     quick([button(1, False)]), quick([mouse_at(80, 46)]), quick([button(0)]), quick([button(0, False)]),
                                                     quick([mouse_at(80, 136)]), quick([mouse_at(80, 166)]), quick([button(0)]), quick([button(0, False)]), quick(),
                                                     quick([mouse_at(100, 400)]), quick([button(0)]), quick([mouse_at(120, 330)]), quick([button(0, False)]),
                                                     quick([mouse_at(60, 92), button(0)]), quick([mouse_at(100, 92)]), quick([button(0, False)]),
                                                     quick([mouse_at(22, 120), button(0)]), quick([button(0, False)]), quick([mouse_at(80, 46), button(0)]),
                                                     quick([button(0, False)]), quick([mouse_at(400, 300), button(0)]), quick([button(0, False)]), slow()]),
        # The text box is hovered and pressed (edit mode, the cursor at the end); BACKSPACE, LEFT twice, DELETE, HOME,
        # END, a press that places the cursor under the pointer, RIGHT, BACKSPACE held past the 20-frame cooldown
        # (one deletion a frame), ENTER; the button computes the hashes; the box is entered again and left by a
        # press outside. Replayed events never reach GetCharPressed, so nothing is typed.
        script('core_compute_hash', 'edit', [quick(), quick([mouse_at(400, 80)]), quick([button(0)]), quick([button(0, False)]), quick([key(259)]), quick([key(259, False)]),
                                             quick([key(263)]), quick([key(263, False)]), quick([key(263)]), quick([key(263, False), key(261)]), quick([key(261, False)]),
                                             quick([key(268)]), quick([key(268, False), key(269)]), quick([key(269, False)]), quick([mouse_at(100, 80)]),
                                             quick([button(0)]), quick([button(0, False)]), quick([key(262)]), quick([key(262, False)]), quick([key(259)])]
               + [quick() for _ in range(24)]
               + [quick([key(259, False)]), quick([key(257)]), quick([key(257, False), mouse_at(400, 120)]), quick([button(0)]), quick([button(0, False)]), quick(),
                  quick([mouse_at(400, 80), button(0)]), quick([button(0, False)]), quick([mouse_at(400, 300), button(0)]), quick([button(0, False)]), slow()]),
        # The icon buttons at scale 2: a random text (seeded), CUT, another random text, COPY, PASTE (the
        # reference's clipboard is NULL: nothing changes) and CLEAR; a third text is edited (BACKSPACE, LEFT), cut
        # with Ctrl+X while the box is in edit mode, and ENTER leaves it; Ctrl+V and Ctrl+C change nothing.
        script('core_clipboard_text', 'buttons', [quick(), quick([mouse_at(730, 140)]), quick([button(0)]), quick([button(0, False)]), quick(),
                                                  quick([mouse_at(120, 200)]), quick([button(0)]), quick([button(0, False)]), quick(),
                                                  quick([mouse_at(730, 140), button(0)]), quick([button(0, False)]), quick([mouse_at(290, 200), button(0)]),
                                                  quick([button(0, False)]), quick([mouse_at(450, 200), button(0)]), quick([button(0, False)]),
                                                  quick([mouse_at(620, 200), button(0)]), quick([button(0, False)]), quick(),
                                                  quick([mouse_at(730, 140), button(0)]), quick([button(0, False)]), quick([mouse_at(300, 140), button(0)]),
                                                  quick([button(0, False)]), quick([key(259)]), quick([key(259, False), key(263)]), quick([key(263, False)]),
                                                  quick([key(341)]), quick([key(88)]), quick([key(88, False)]), quick([key(86)]), quick([key(86, False), key(67)]),
                                                  quick([key(67, False), key(341, False)]), quick([key(257)]), quick([key(257, False)]), slow()], seed=7),
        # Two slices are hovered (atan2f of the pointer); the spinner adds an eighth slice; percentages are shown,
        # the donut switched on (its slider disabled) and off, the inner radius dragged; the wheel turns over the
        # scroll panel (its content fits: no bars); the first slice's value is dragged, the second's label entered,
        # shortened by BACKSPACE and left with ENTER.
        script('shapes_pie_chart', 'slices', [quick(), quick([mouse_at(300, 150)]), quick([mouse_at(150, 300)]), quick([mouse_at(733, 29), button(0)]), quick([button(0, False)]),
                                              quick([mouse_at(555, 97), button(0)]), quick([button(0, False)]), quick([mouse_at(555, 127), button(0)]), quick([button(0, False)]),
                                              quick(), quick([button(0)]), quick([button(0, False), mouse_at(650, 162)]), quick([button(0)]), quick([mouse_at(700, 162)]),
                                              quick([button(0, False), mouse_at(660, 300)]), quick([(MOUSE_WHEEL, 0, -1, 0)]), quick([mouse_at(700, 228), button(0)]),
                                              quick([mouse_at(740, 228)]), quick([button(0, False)]), quick([mouse_at(600, 262), button(0)]), quick([button(0, False)]),
                                              quick([key(259)]), quick([key(259, False), key(257)]), quick([key(257, False)]), slow()]),
        # The brush follows the pointer and grows by two wheel notches; commands are buffered while the left
        # button is down and sent on its release; the brush shrinks; the right button buffers and sends again.
        script('shaders_rlgl_compute', 'brush', [quick(), quick([mouse_at(300, 300)]), quick([(MOUSE_WHEEL, 0, 2, 0)]), quick([button(0)]), quick(),
                                                 quick([button(0, False)]), quick([(MOUSE_WHEEL, 0, -3, 0), mouse_at(500, 120)]), quick([button(1)]),
                                                 quick([button(1, False)]), slow()]),
        # The orbital camera turns a step a frame around the plane, with the baked lightmap beside it.
        script('shaders_lightmap_rendering', 'orbit', [quick(), quick(), quick(), slow(), quick()]),
        # The greenman in its bind pose under the orbital camera; RIGHT plays the next animation, LEFT the one
        # before and LEFT again wraps to the last one (the name is drawn; the pose is not: GPU skinning).
        script('models_animation_gpu_skinning', 'switch', [quick(), quick([key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False)]), slow([key(KEY_LEFT)]),
                                                           quick([key(KEY_LEFT, False)]), quick([key(KEY_LEFT)]), quick()]),
        # The greenman with its hat, sword and shield on their socket bones: T plays the next animation, F turns
        # the character two steps and H one back, 1, 2 and 3 hide the hat, the sword and the shield, the pointer
        # moves the third person camera, 1 shows the hat again and G goes back to the first animation.
        script('models_bone_socket', 'equip', [quick(), quick([key(84)]), quick([key(84, False), key(70)]), quick(), quick([key(70, False), key(KEY_H)]),
                                               slow([key(KEY_H, False), key(KEY_ONE)]), quick([key(KEY_ONE, False), key(KEY_TWO)]),
                                               quick([key(KEY_TWO, False), key(KEY_THREE), mouse_at(420, 240)]), quick([key(KEY_THREE, False), key(KEY_ONE)]),
                                               quick([key(KEY_ONE, False), key(KEY_G)]), quick([key(KEY_G, False)])]),
        # The robot in its bind pose under the orbital camera; LEFT wraps to its last animation and RIGHT twice
        # plays the second one (the name is drawn; the pose is not: GPU skinning).
        script('models_loading_gltf', 'switch', [quick(), quick([key(KEY_LEFT)]), quick([key(KEY_LEFT, False)]), slow([key(KEY_RIGHT)]),
                                                 quick([key(KEY_RIGHT, False)]), quick([key(KEY_RIGHT)])]),
        # The robot's eleventh animation at half a keyframe a frame, with the progress bar and its ticks. A click
        # opens the dropdown box and a release over the second name plays that animation; the slider is dragged
        # to a faster speed; P pauses (the frame and the bar hold) and plays again.
        script('models_animation_timing', 'controls', [quick(), quick([mouse_at(80, 22)]), quick([button(0)]), quick([button(0, False)]), quick([mouse_at(80, 70)]),
                                                       quick([button(0)]), slow([button(0, False)]), quick([mouse_at(500, 22)]), quick([button(0)]),
                                                       quick([mouse_at(700, 22)]), quick([button(0, False)]), quick([key(KEY_P)]), quick([key(KEY_P, False)]),
                                                       quick([key(KEY_P)])]),
        # The robot walking. SPACE starts the blend into running; two frames of more than a second carry the blend
        # factor past 1, where the blend bar is full and running plays alone. SPACE again blends back, the bar
        # filling from the right. The second dropdown box opens (its slider is disabled meanwhile) and a release
        # over the third name picks that animation; the first slider is dragged; P pauses.
        script('models_animation_blending', 'blend', [quick(), quick([key(KEY_SPACE)]), ([key(KEY_SPACE, False)], 0.003, 1.1), ([], 0.003, 1.1), quick(), quick(), quick(),
                                                      quick([key(KEY_SPACE)]), slow([key(KEY_SPACE, False)]), quick([mouse_at(700, 22)]), quick([button(0)]),
                                                      quick([button(0, False)]), quick([mouse_at(700, 95)]), quick([button(0)]), quick([button(0, False)]),
                                                      quick([mouse_at(90, 44)]), quick([button(0)]), quick([mouse_at(150, 44)]), quick([button(0, False)]),
                                                      quick([key(KEY_P)]), quick([key(KEY_P, False)])]),
        # The greenman in its bind pose with the names of the two animations the example blends bone by bone;
        # SPACE switches to uniform blending and back (the text names the mode; the bone matrices are not drawn).
        script('models_animation_blend_custom', 'modes', [quick(), quick(), quick([key(KEY_SPACE)]), slow([key(KEY_SPACE, False)]), quick(), quick([key(KEY_SPACE)])]),
        # 3375 cubes spread and sized by sin of the clock under a camera circling with cos and sin of it: the
        # first frame, and one a second and a half later.
        script('models_waving_cubes', 'wave', [quick(), ([], 0.003, 1.5)]),
        # The spotlight shader does nothing on the software renderer, so its white rectangle covers the stars and
        # the textures: the frame rate and the texts over white, whatever the seed and the pointer do.
        script('shaders_spotlight_rendering', 'white', [quick(), quick([mouse_at(300, 200)]), slow(), quick([mouse_at(640, 90)])], seed=7),
        script('shaders_spotlight_rendering', 'seeded', [quick(), quick()], seed=20261011),
        # Each generated model with the checked texture, in order: clicks and RIGHT go from the plane to the
        # triangle (cube, sphere, hemisphere, cylinder, torus, knot, polygon), RIGHT wraps to the plane and LEFT
        # back to the triangle.
        script('models_mesh_generation', 'cycle', [quick(), quick([button(0)]), quick([button(0, False)]), quick([button(0)]), quick([button(0, False), key(KEY_RIGHT)]),
                                                   quick([key(KEY_RIGHT, False)]), quick([key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False), button(0)]),
                                                   slow([button(0, False), key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False), button(0)]),
                                                   quick([button(0, False), key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False)]), quick([key(KEY_RIGHT)]),
                                                   quick([key(KEY_RIGHT, False), key(KEY_LEFT)])]),
        # Two cubes and a grid in the render texture the example builds with rlgl (a framebuffer, a color
        # texture and a depth attachment), drawn to the screen while the orbital camera turns.
        script('shaders_depth_writing', 'orbit', [quick(), quick(), slow(), quick()]),
        # The raymarching pass is a white rectangle drawn with the depth test on; the cubes and the grid follow
        # in the same hand-built render texture while the orbital camera turns.
        script('shaders_hybrid_rendering', 'orbit', [quick(), quick(), slow(), quick()]),
        # The depth attachment drawn as a texture is a white rectangle on rlsw, whatever the free camera does (W
        # moves it, the pointer turns it): the help box over white.
        script('shaders_depth_rendering', 'white', [quick(), quick([key(KEY_W)]), quick([mouse_at(430, 240)]), slow([key(KEY_W, False)])]),
        # 13:59:58 at InitWindow, a tenth of a second a frame: the hands take five frames to reach a second's
        # digits (at frames 0 and 8). SPACE at frame 2 is the 12-hour mode, whose 13:59:59 is " 1:59:59" (the first
        # digit's hands all at ZZ). A short script: 432 shapes a frame are slow in the JavaScript lane.
        script('shapes_clock_of_clocks', 'ticks', [long(), long(), long([key(KEY_SPACE)]), long([key(KEY_SPACE, False)])] + [long() for _ in range(10)],
               seed=13 * 3600 + 59 * 60 + 58),
        # 13:59:58 at InitWindow, a tenth of a second a frame: the seconds tick, the dots blink, the hour turns;
        # SPACE shows the analog face (the hands at 14:00:00 and 14:00:01), SPACE again the display.
        script('shapes_digital_clock', 'ticks', [long() for _ in range(19)] + [long([key(KEY_SPACE)])] + [long([key(KEY_SPACE, False)])] + [long() for _ in range(9)]
               + [quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)])], seed=13 * 3600 + 59 * 60 + 58),
        # Short frames end with the example's own WaitTime to 1/60 s (deltaTime is then measured), long ones do not
        # wait (deltaTime keeps its value). The example's PollInputEvents makes every press an old one: SPACE and
        # UP change nothing.
        script('core_custom_frame_control', 'paced', [quick(), quick(), quick([key(KEY_SPACE)]), slow([key(KEY_SPACE, False), key(KEY_UP)]), quick([key(KEY_UP, False)]), long(),
                                                      quick(), quick()]),
        # The file was modified on Thursday 2025-10-09 08:53:20 and on Thursday 2024-02-29 23:59:59 (a leap day):
        # a click and the auto reloading (A) find it unmodified.
        script('shaders_hot_reloading', 'stamp', [quick(), quick([button(0)]), quick([button(0, False), key(65)]), slow([key(65, False)])], seed=1760000000),
        script('shaders_hot_reloading', 'leap', [quick(), quick()], seed=1709251199),
        # The driver silences raylib's log (SetTraceLogLevel(LOG_NONE)), so the example's callback prints nothing.
        script('core_custom_logging', 'frames', [quick(), slow()]),
        # The mouse over an emoji colors it; a click selects it and its message appears in a bubble (below the
        # first row, above the others, pulled back from the right edge), wrapped by words in the language's font.
        # The emoji are 81 wide (the BMFont's lineHeight), 109.8 apart from (28.8, 10), in rows of 9, 8, 8 and 7
        # that are 105.25 apart: emoji 0, 6, 20, 31 and 13 are asked; SPACE draws new ones.
        script('text_unicode_emojis', 'talk', [quick(), quick([mouse_at(40, 30)]), quick([button(0)]), quick([button(0, False)]), quick([mouse_at(700, 30)]), quick([button(0)]),
                                               quick([button(0, False), mouse_at(400, 250)]), quick([button(0)]), quick([button(0, False), mouse_at(700, 350)]), quick([button(0)]),
                                               quick([button(0, False), mouse_at(500, 150)]), quick([button(0)]), slow([button(0, False)]), quick([key(KEY_SPACE)]),
                                               quick([key(KEY_SPACE, False)])], seed=0xE301),
        # The orbital camera: F1 and F2 show the boundaries; END adds layers and TAB colors them; RIGHT, DOWN and
        # PAGE_DOWN change the size and the spacings; ENTER breaks the line and BACKSPACE joins it again; INSERT
        # (held two frames) and DELETE move the layers; HOME removes one; a click on the cube recolors it, a
        # click beside it does not.
        script('text_3d_drawing', 'layers', [quick(), quick([key(290)]), quick([key(290, False), key(291)]), quick([key(291, False), key(269)]), quick([key(269, False), key(258)]),
                                             quick([key(258, False), key(269)]), slow([key(269, False), key(262)]), quick([key(262, False), key(264)]), quick([key(264, False), key(267)]),
                                             quick([key(267, False), key(257)]), quick([key(257, False), key(260)]), quick(), quick([key(260, False), key(261)]),
                                             quick([key(261, False), key(259)]), quick([key(259, False), key(268), key(290)]), quick([key(268, False), key(290, False), mouse_at(400, 225)]),
                                             quick([button(0)]), quick([button(0, False), mouse_at(60, 60)]), quick([button(0)]), quick([button(0, False)])], seed=0x3D7E),
        # F3 frees the camera (the mouse turns it, W moves it); LEFT twice makes the font size negative (the quads
        # turn over); UP and PAGE_UP; F3 again spins it from the start.
        script('text_3d_drawing', 'free', [quick(), quick([key(292)]), quick([key(292, False), mouse_at(420, 240)]), quick([mouse_at(440, 250)]), slow([key(87)]),
                                           quick([key(87, False), key(263)]), quick([key(263, False)]), quick([key(263)]), quick([key(263, False), key(265)]),
                                           quick([key(265, False), key(266)]), quick([key(266, False), key(292)]), quick([key(292, False)])], seed=0x3D7F),
        # Left clicks show the sword, the monument and the village (three meshes each for the last two).
        script('models_loading_vox', 'cycle', [quick(), quick([button(0)]), quick([button(0, False)]), quick([button(0)]), quick([button(0, False)]), quick([button(0)])]),
        # The knight under UpdateCameraPro: W and D move the camera, the middle button turns it with the mouse, the
        # wheel zooms in and out, DOWN with LEFT move back and left, S with UP cancel each other.
        script('models_loading_vox', 'camera', [quick(), quick([key(87)]), quick([key(87, False), key(68)]), quick([key(68, False), button(2), mouse_at(420, 240)]), quick([mouse_at(450, 250)]),
                                                slow([button(2, False), (MOUSE_WHEEL, 0, 2, 0)]), quick([key(264), key(263)]), quick([key(264, False), key(263, False), key(83), key(265)]),
                                                quick([key(83, False), key(265, False), (MOUSE_WHEEL, 0, -1, 0)]), quick()]),
        # The camera orbits while the animation plays: 61 keyframes, so the counter reaches the count (frame 61 is
        # asked of UpdateModelAnimation) and starts again within these frames.
        script('models_loading_iqm', 'orbit', [quick() for _ in range(31)] + [slow()] + [quick() for _ in range(32)]),
        # The textured car and floor under the orbital camera; 1 turns the red light off (a wire sphere), 2 the
        # green one, 3 and 4 together the blue and the yellow, then 1 turns the red one on again.
        script('shaders_basic_pbr', 'lights', [quick(), quick([key(49)]), quick([key(49, False), key(50)]), quick([key(50, False), key(51), key(52)]), quick([key(51, False), key(52, False)]),
                                               quick([key(49)])]),
        # The model under the orbital camera, then SPACE held: the skeleton at the keyframes' poses (cubes and
        # lines); RIGHT and LEFT keep the one animation; SPACE released shows the model again.
        script('models_loading_m3d', 'skeleton', [quick(), quick(), quick([key(KEY_SPACE)]), quick(), slow(), quick([key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False), key(KEY_LEFT)]), quick([key(KEY_LEFT, False)]),
                                                  quick(), quick([key(KEY_SPACE, False)]), quick()]),
        script('text_codepoints_loading', 'frames', [quick(), quick([key(KEY_SPACE)]), slow([key(KEY_SPACE, False), key(KEY_RIGHT)])]),
        # The button's frame is (288, 172) to (512, 278): hovered, pressed and released on it (the sound plays), pressed
        # outside and released inside (the action too), then its top edge and the row above it.
        script('textures_sprite_button', 'click', [quick(), quick([mouse_at(400, 225)]), quick([button(0)]), slow(), quick([button(0, False)]), quick(),
                                                   quick([mouse_at(10, 10)]), quick([button(0)]), quick([mouse_at(511, 277), button(0, False)]),
                                                   quick([mouse_at(400, 172)]), quick([mouse_at(400, 171)]), quick([mouse_at(512, 225)])]),
        # A click starts the explosion (a sprite frame every third frame, 25 of them); a second click while it is
        # active does nothing; it ends after 75 frames and a click near the corner starts one that is cut by the edges.
        script('textures_sprite_explosion', 'booms', [quick(), quick([mouse_at(300, 200)]), quick([button(0)]), quick([button(0, False)]), quick(), quick(),
                                                      quick([mouse_at(500, 300), button(0)]), quick([button(0, False)]), slow(), *[quick() for _ in range(66)],
                                                      quick(), quick([mouse_at(40, 30), button(0)]), quick([button(0, False)]), quick(), quick(), quick()]),
        # SPACE plays the WAV sound and ENTER the Ogg Vorbis one (decoded whole before the first frame: about a minute in the JavaScript
        # lane); then both in one frame, and held keys play nothing more. No frame shows a sound.
        script('audio_sound_loading', 'keys', [quick(), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]), quick([key(KEY_ENTER)]), slow(),
                                               quick([key(KEY_ENTER, False)]), quick([key(KEY_SPACE), key(KEY_ENTER)]), quick(),
                                               quick([key(KEY_SPACE, False), key(KEY_ENTER, False)]), quick()]),
        # SPACE twelve times: the ten sounds and around to the first two again (held, it plays once).
        script('audio_sound_multi', 'spaces', [quick(), *[frame for _ in range(12) for frame in (quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]))],
                                               quick([key(KEY_SPACE)]), slow(), quick(), quick([key(KEY_SPACE, False)])]),
        # Two steps (each a 2048x2048 blit: Pause is pressed on the first frame and takes on the third), the Glider preset, Draw mode with
        # a painted cell, and the wheel zooming in. Nine frames: each costs the JavaScript lane about a minute (22- and 18-frame scripts
        # with the zoom buttons, Slower and a run every second frame passed too, 2026-10-12).
        script('shaders_game_of_life', 'menu', [quick([mouse_at(750, 284), button(0)]), quick([button(0, False)]), quick([mouse_at(750, 78), button(0)]),
                                                quick([button(0, False)]), slow(), quick([mouse_at(750, 302), button(0)]), quick([button(0, False)]),
                                                quick([mouse_at(300, 200), button(0)]), quick([(MOUSE_WHEEL, 0, 1, 0), button(0, False)])], seed=7),
        # The first-person camera looks around the cube and walks (W, then A) while the scene goes through the 2160x1200 render texture.
        script('core_vr_simulator', 'walk', [quick(), quick([mouse_at(430, 240)]), slow([key(87)]), quick([key(87, False), key(65), mouse_at(380, 215)]), quick([key(65, False)])]),
        # The sphere circles at the clock's angle while the free camera turns, zooms, pans and moves (W, then D).
        script('audio_sound_positioning', 'around', [quick(), quick([mouse_at(410, 230)]), quick([mouse_at(450, 210)]), slow([mouse_at(380, 260)]),
                                                     quick([(MOUSE_WHEEL, 0, 2, 0)]), quick([(MOUSE_WHEEL, 0, -1, 0)]), quick([button(2)]),
                                                     quick([mouse_at(420, 250)]), quick([mouse_at(470, 280), button(2, False)]), quick([key(87)]),
                                                     slow(), quick([key(87, False), key(68)]), quick([key(68, False)]), quick()]),
        # The device's clock asks for 3 or 4 callbacks a frame at 30 FPS: both halves are filled in the first two
        # frames and each again once the device has read it through (93 ms); up, then down, move the frequency, which
        # the wave takes at its next period; right, then left, the pan; a slow frame and one of a tenth of a second.
        script('audio_raw_stream', 'sine', [quick(), quick(), quick([key(KEY_UP)]), quick(), quick([key(KEY_RIGHT)]), slow(),
                                            quick([key(KEY_UP, False), key(KEY_DOWN)]), long([key(KEY_RIGHT, False), key(KEY_LEFT)]), quick(),
                                            quick([key(KEY_DOWN, False)]), quick([key(KEY_LEFT, False)]), quick()]),
        # country.mp3 plays from the first frame: at 30 FPS the clock asks for 3 or 4 callbacks a frame and UpdateMusicStream
        # fills the halves they read through, decoding the MP3 as it goes. Right moves the pan, up the volume; P pauses (the
        # time bar stands still) and resumes; left and down move them back over a slow frame and one of a tenth of a
        # second; space stops the music and plays it from its start.
        script('audio_music_stream', 'keys', [quick(), quick(), quick([key(KEY_RIGHT)]), quick(), quick([key(KEY_RIGHT, False), key(KEY_UP)]), slow(),
                                              quick([key(KEY_UP, False), key(KEY_P)]), quick([key(KEY_P, False)]), quick([key(KEY_P)]),
                                              quick([key(KEY_P, False), key(KEY_LEFT)]), long([key(KEY_LEFT, False), key(KEY_DOWN)]),
                                              quick([key(KEY_DOWN, False), key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]), quick()]),
        # mini1111.xm plays once from the first frame: at 60 FPS the clock asks for one or two callbacks a frame and UpdateMusicStream
        # has the module's player generate the halves they read through (two halves of 12800 frames before the first frame). Up
        # raises the speed a hundredth a frame and down lowers it (the stream is resampled from there on); P pauses the music and the
        # circles and resumes them; the fastest circles fade out after 43 frames that move them and are made again; space stops the
        # music (its time goes back to 0) and plays it from its start.
        script('audio_module_playing', 'keys', [quick(), quick(), quick([key(KEY_UP)]), quick(), quick([key(KEY_UP, False), key(KEY_DOWN)]), slow(),
                                                quick([key(KEY_DOWN, False), key(KEY_P)]), quick([key(KEY_P, False)]), quick([key(KEY_P)]),
                                                quick([key(KEY_P, False)]), long(), *[quick() for _ in range(38)], quick([key(KEY_SPACE)]),
                                                quick([key(KEY_SPACE, False)]), quick(), quick()]),
        # country.mp3 again, at 60 FPS (one or two callbacks a frame). F puts the low-pass filter on the music's stream and
        # D the delay after it: both run in the callbacks of the frames that follow; P pauses and resumes; F takes the
        # filter off over a slow frame; space restarts the music with the delay still on.
        script('audio_stream_effects', 'toggles', [quick(), quick(), quick([key(KEY_F)]), quick([key(KEY_F, False)]), quick([key(KEY_D)]), quick([key(KEY_D, False)]),
                                                   quick(), long([key(KEY_P)]), quick([key(KEY_P, False)]), quick([key(KEY_P)]), quick([key(KEY_P, False)]),
                                                   slow([key(KEY_F)]), quick([key(KEY_F, False), key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]), quick()]),
        # country.mp3 once more, with the processor on the device's mix: every callback raises its 960 samples to the
        # exponent and leaves an average, a bar of the frame. The music begins quietly, so space plays coin.wav over it at
        # once; left lowers the exponent twice (0.95, 0.90: louder), right raises it three times (1.05) over a slow frame
        # and one of a tenth of a second, whose ten callbacks each leave a bar.
        script('audio_mixed_processor', 'powers', [quick(), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False), key(KEY_LEFT)]), quick([key(KEY_LEFT, False)]),
                                                   quick([key(KEY_LEFT)]), slow([key(KEY_LEFT, False), key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False)]),
                                                   quick([key(KEY_RIGHT)]), long([key(KEY_RIGHT, False)]), quick([key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False)]),
                                                   quick()]),
        # Ctrl+R begins a recording: the sixth frame after it and the twelfth go to the encoder (the screen read is the
        # frame drawn before, with the circle further along its wave the second time); Ctrl+R again writes
        # screenrecording.gif, which both sides must leave with the same bytes. R without Ctrl does nothing. The circle
        # reaches the right side after 180 frames: that branch is not scripted.
        script('core_screen_recording', 'record', [quick(), quick([key(KEY_LEFT_CONTROL)]), quick([key(KEY_R)]), quick([key(KEY_R, False)]), quick(), slow(), quick(),
                                                   quick(), quick(), quick(), long(), quick(), quick(), quick(), quick([key(KEY_R)]),
                                                   quick([key(KEY_R, False), key(KEY_LEFT_CONTROL, False)]), quick([key(KEY_R)]), quick()]),
        # The working directory has 27 files the filter takes, more than the 13 the list shows: the pointer focuses an
        # item, a press selects it and a second one clears it, the wheel moves the list down by one and by three, a press
        # on the bar's track jumps there and a drag follows the pointer. Then "<" twice: the directory above and the one
        # above it, listed whole (files and directories), with the scroll index and the selection the example keeps. The
        # button answers a release, which the memory platform sees for a touch point only.
        script('core_directory_files', 'browse', [quick(), quick([mouse_at(200, 150)]), quick([button(0)]), quick([button(0, False)]), quick([button(0)]),
                                                  quick([button(0, False), (MOUSE_WHEEL, 0, -1, 0)]), slow([(MOUSE_WHEEL, 0, -3, 0)]), quick([mouse_at(793, 420)]),
                                                  quick([button(0)]), quick([mouse_at(793, 150)]), quick([mouse_at(300, 200)]), quick([button(0, False)]),
                                                  quick([mouse_at(400, 30)]), quick([mouse_at(64, 24)]), quick([(TOUCH_DOWN, 0, 0, 0)]), quick([(TOUCH_UP, 0, 0, 0)]),
                                                  quick(), quick([mouse_at(300, 100)]), quick([button(0)]), quick([button(0, False), mouse_at(64, 24)]),
                                                  quick([(TOUCH_DOWN, 0, 0, 0)]), quick([(TOUCH_UP, 0, 0, 0)]), quick(), quick([mouse_at(250, 70)])]),
        script('core_directory_files', 'noext', [quick(), quick([mouse_at(200, 150)])]),
        # The whole of country.mp3 is loaded as a wave before the first frame (minutes in the JavaScript lane). The frame is
        # the empty render texture under a shader the software renderer does not run: what the frames compare is that the
        # stream is fed and the spectrum computed without a refusal, over callbacks that empty the stream's halves (a
        # tenth of a second takes more than one). The spectrum itself is the `spectrum` gate's.
        script('audio_spectrum_visualizer', 'frames', [quick(), quick(), slow(), long(), quick(), quick()]),
        # The 122 slices of a 112x11468 texture, three times their size, turning with the frame time: D speeds them up
        # over a slow frame while the wheel spreads the slices as far as they go (5); then A slows them and the wheel
        # closes them (0). Three frames: each is 122 textured quads of 336x282 pixels, more than three minutes in the
        # JavaScript lane.
        script('textures_sprite_stacking', 'spin', [quick(), slow([key(68), (MOUSE_WHEEL, 0, 40, 0)]), quick([key(68, False), key(KEY_A), (MOUSE_WHEEL, 0, -60, 0)])]),
        # The font's 95 glyphs; 1 asks for the first choice (the notice covers that frame) and the next pass loads the 7 MiB
        # font three times, once for each of its two ranges after the plain load: the Spanish line gets its letter, the
        # atlas grows to 512x512 and the font has 212 glyphs. 0 goes back to the 95. The other choices are not scripted:
        # the second loads the file five times and the fourth eighteen, the last ones for tens of thousands of codepoints.
        script('text_unicode_ranges', 'ranges', [quick(), quick([key(49)]), quick([key(49, False)]), quick(), quick([key(48)]), slow([key(48, False)]), quick()]),
        # Every frame is a refusal (UNDEFINED_NATIVE): the port still runs the clock and the stream's callback, the
        # frequency keys and both wave keys before it refuses.
        script('audio_stream_callback', 'waves', [quick(), quick([key(KEY_UP)]), quick([key(KEY_RIGHT)]), quick([key(KEY_RIGHT, False)]), slow([key(KEY_LEFT)]),
                                                  quick([key(KEY_UP, False), key(KEY_LEFT, False)])]),
        # The mouse on the character shows the placement cube; two clicks splat two decals (the table lists them);
        # RMB with a move turns the camera; a click on "Clear Decals" removes them.
        script('models_decals', 'splat', [quick(), quick([mouse_at(400, 230)]), quick([button(0)]), quick([button(0, False), mouse_at(400, 150)]), quick([button(0)]),
                                          quick([button(0, False), button(1), mouse_at(430, 160)]), slow([mouse_at(460, 170)]), quick([button(1, False), mouse_at(150, 380)]), quick([button(0)]),
                                          quick([button(0, False)])], seed=0xDECA),
        # The camera starts with the cube behind it: the mouse turns it half a turn and down (the white cube, drawn
        # without culling or depth writes, under the grid), then W walks toward it.
        script('models_skybox_rendering', 'turn', [quick(), quick([mouse_at(300, 60)]), quick([mouse_at(600, 120)]), quick([mouse_at(900, 180)]), slow([mouse_at(1050, 200)]),
                                                   quick([key(KEY_W)]), quick([key(KEY_W, False)])]),
        # The result (nothing but the lights: the yellow sphere invisible, then its wires once Y turns it off),
        # then the position, normal and albedo textures and the result again, with the blue light off.
        script('shaders_deferred_rendering', 'modes', [quick(), quick([key(89)]), quick([key(89, False), key(49)]), quick([key(49, False), key(50)]), quick([key(50, False), key(51)]),
                                                       slow([key(51, False), key(52), key(66)]), quick([key(52, False), key(66, False)])]),
        # Short scripts: the JavaScript lane takes seconds a frame for this scene. The player falls to the floor
        # (53 frames: deltaTime is the constant 0.015f), runs right, jumps and runs left in the air; the wheel
        # zooms out and in; A with an empty list does nothing; R resets.
        script('core_automation_events', 'run', [quick() for _ in range(54)] + [quick([key(KEY_RIGHT)]), quick(), quick(), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]),
                                                 quick(), slow([key(KEY_RIGHT, False), key(KEY_LEFT)]), quick(), quick([(MOUSE_WHEEL, 0, -4, 0)]), quick([key(65)]),
                                                 quick([key(65, False), (MOUSE_WHEEL, 0, 9, 0)]), quick([key(KEY_LEFT, False), key(KEY_R)]), quick([key(KEY_R, False)])]),
        # S starts a recording. raylib then ignores PlayAutomationEvent, the probe's input: RIGHT does not move the
        # player, S cannot be released (so it cannot be pressed again to stop and export) and each EndDrawing
        # records S down once more: the blinking text shows the count from the sixteenth frame on.
        script('core_automation_events', 'record', [quick(), quick([key(KEY_S)]), quick([key(KEY_S, False), key(KEY_RIGHT)])] + [quick() for _ in range(14)]
               + [slow([key(KEY_S)]), quick([key(65)]), quick()]),
        # SPACE with no file (0 and 0); R; ENTER creates the file with the score, then adds the high score; R;
        # SPACE loads what was saved; R; ENTER with SPACE saves only, both ints in place; SPACE loads them.
        script('core_storage_values', 'values', [quick(), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False), key(KEY_R)]), quick([key(KEY_R, False), key(KEY_ENTER)]),
                                                 quick([key(KEY_ENTER, False), key(KEY_R)]), slow([key(KEY_R, False), key(KEY_SPACE)]),
                                                 quick([key(KEY_SPACE, False), key(KEY_R)]), quick([key(KEY_R, False), key(KEY_ENTER), key(KEY_SPACE)]),
                                                 quick([key(KEY_ENTER, False), key(KEY_SPACE, False)]), quick([key(KEY_SPACE)])], seed=0x5C0E),
        script('core_storage_values', 'longer', [quick(), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False), key(KEY_R)]), quick([key(KEY_R, False), key(KEY_ENTER)]),
                                                 quick([key(KEY_ENTER, False), key(KEY_SPACE)])], seed=77),
        script('core_storage_values', 'short', [quick(), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)])], seed=1),
        script('core_storage_values', 'odd', [quick(), quick([key(KEY_R)]), quick([key(KEY_R, False), key(KEY_ENTER)]), quick([key(KEY_ENTER, False)])], seed=2),
        # The arrow keys turn the light, which only the dropped shadow pass sees; F is read after EndDrawing, whose
        # poll has already made the press an old one (no screenshot in the script).
        script('shaders_shadowmap_rendering', 'light', [quick(), quick([key(KEY_LEFT)]), slow([key(KEY_LEFT, False), key(265)]), quick([key(265, False), key(70)]),
                                                        quick([key(70, False), key(KEY_RIGHT), key(264)])]),
        # The ball falls; a left press on it grabs it (hypot(dx, dy) <= radius), two moves drag it and the release
        # throws it; right presses add balls (one a frame with left control held); the wheel lowers gravity; a
        # middle press shakes them; a left press on the empty corner grabs nothing.
        script('shapes_ball_physics', 'throw', [quick(), quick([mouse_at(410, 240)]), quick([button(0)]), quick([mouse_at(300, 150)]), quick([mouse_at(200, 120)]),
                                                quick([button(0, False)]), quick(), quick([button(1)]), quick([button(1, False), key(341)]), quick([button(1)]), quick(),
                                                quick([mouse_at(500, 300)]), quick([button(1, False), key(341, False)]), quick([(MOUSE_WHEEL, 0, -4, 0)]), quick([button(2)]),
                                                quick([button(2, False)]), quick(), quick(), slow(), quick([mouse_at(795, 5), button(0)]), quick([button(0, False)]),
                                                quick(), quick()], seed=0xBA11),
        # The five rounded gradients (the scene has no input).
        script('shapes_rectangle_advanced', 'still', [quick(), quick()]),
        # Two more triangles (a positive wheel move); a color picked inside the wheel, dragged, then outside it
        # (the handle snaps to the rim); the wheel scaled up and down with the handle; the lines while SPACE is
        # held; the value slider dragged down (the color follows); a pick at the center (the gray handle); CTRL+C.
        script('shapes_rlgl_color_wheel', 'pick', [quick(), quick([(MOUSE_WHEEL, 0, 2, 0)]), quick([mouse_at(450, 200)]), quick([button(0)]), quick([mouse_at(480, 150)]),
                                                   quick([mouse_at(700, 80)]), quick([button(0, False)]), quick([key(KEY_UP)]), quick(), quick([key(KEY_UP, False), key(KEY_DOWN)]),
                                                   quick(), quick(), quick([key(KEY_DOWN, False), key(KEY_SPACE)]), quick(), quick([key(KEY_SPACE, False)]),
                                                   quick([mouse_at(80, 133)]), quick([button(0)]), quick([mouse_at(60, 133)]), quick([button(0, False)]),
                                                   quick([mouse_at(402, 223)]), quick([button(0)]), quick([button(0, False)]), quick([key(341)]), quick([key(67)]),
                                                   quick([key(67, False), key(341, False)]), quick()]),
        # More segments by a slider drag (the count is the truncated value), the outlines off and on again.
        script('shapes_triangle_strip', 'segments', [quick(), quick([mouse_at(660, 50), button(0)]), quick([mouse_at(700, 52)]),
                                                     quick([button(0, False), mouse_at(650, 80)]), quick([button(0)]), slow([button(0, False)]),
                                                     quick([button(0)]), quick([button(0, False)])]),
        # The full tree, a shallower one (depth slider), a wider angle, thicker Bezier branches.
        script('shapes_recursive_tree', 'grow', [quick(), quick([mouse_at(690, 140), button(0)]), quick([button(0, False), mouse_at(700, 50)]),
                                                 quick([button(0)]), quick([button(0, False), mouse_at(680, 170)]), quick([button(0)]),
                                                 slow([button(0, False), mouse_at(650, 200)]), quick([button(0)]), quick([button(0, False)]), quick()]),
        # A stroke of three moves (six rotations and their mirrors each), two steps back, one forward, a frame
        # longer than the 20 FPS target, a press over the back button (no drawing there) and a reset.
        script('shapes_kaleidoscope', 'draw', [quick(), quick([mouse_at(430, 200)]), quick([button(0)]), quick([mouse_at(470, 180)]),
                                               quick([mouse_at(500, 230)]), quick([button(0, False), mouse_at(757, 432)]), quick([button(0)]),
                                               quick([button(0, False)]), quick([button(0)]), quick([button(0, False)]), ([], 0.003, 0.06),
                                               quick([mouse_at(782, 432), button(0)]), quick([button(0, False)]), quick(),
                                               quick([mouse_at(770, 17), button(0)]), quick([button(0, False)]), quick(), quick()]),
        # The toggle group picks the third picture (hover, press, release), key 2 the second; sliders move,
        # the reset button zeroes them on the next frame; a click on the active toggle changes nothing.
        script('shaders_color_correction', 'pictures', [quick(), quick([mouse_at(700, 80)]), quick([button(0)]), quick([button(0, False)]),
                                                        quick([key(50)]), quick([key(50, False), mouse_at(740, 110), button(0)]),
                                                        quick([button(0, False), mouse_at(660, 170)]), quick([button(0)]),
                                                        slow([button(0, False), mouse_at(665, 200)]), quick([button(0)]), quick([button(0, False)]),
                                                        quick([mouse_at(675, 80), button(0)]), quick([button(0, False)]), quick()]),
        script('core_window_web', 'frames', [quick(), slow()]),
        script('text_sprite_fonts', 'frames', [quick(), slow()]),
        # The clock crosses one second (the second word) while the arrow keys walk every alignment and its limits.
        script('text_words_alignment', 'align', [quick(), quick([key(KEY_LEFT)]), quick([key(KEY_LEFT, False), key(KEY_UP)]),
                                                 quick([key(KEY_UP, False), key(KEY_LEFT)]), quick([key(KEY_LEFT, False), key(KEY_RIGHT)]),
                                                 slow([key(KEY_RIGHT, False), key(KEY_DOWN)]), quick([key(KEY_DOWN, False), key(KEY_RIGHT)]),
                                                 quick([key(KEY_RIGHT, False), key(KEY_DOWN)]), quick([key(KEY_DOWN, False), key(KEY_RIGHT)]),
                                                 quick([key(KEY_RIGHT, False), key(KEY_DOWN)]), quick([key(KEY_DOWN, False)])], start=0.93),
        # The last word (10 seconds) wraps to the first at 11.
        script('text_words_alignment', 'wrap', [quick(), quick(), slow(), quick()], start=10.975),
        # The cameras follow GetTime and the rectangles the frame time: frames of both lengths.
        script('core_smooth_pixelperfect', 'drift', [quick(), quick(), slow(), quick(), slow(), quick()]),
        # The rotation follows GetTime: frames of both lengths.
        script('models_tesseract_view', 'turn', [quick(), quick(), slow(), quick(), slow()]),
        # A particle starts each frame at the mouse; SPACE switches to additive blending and back.
        script('textures_particles_blending', 'tail', [quick(), quick([mouse_at(300, 150)]), quick([mouse_at(360, 180)]), quick([mouse_at(420, 160)]),
                                                       quick([key(KEY_SPACE)]), slow([key(KEY_SPACE, False), mouse_at(500, 220)]),
                                                       quick([mouse_at(520, 300)]), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]), quick()],
               seed=0x5A0),
        script('models_orthographic_projection', 'switch', [quick(), quick([key(KEY_SPACE)]), slow([key(KEY_SPACE, False)]), quick([key(KEY_SPACE)]),
                                                            quick([key(KEY_SPACE, False)])]),
        # RIGHT walks the player into the sphere (touching at exactly the radius: z 2 - 0.5 = 1.5), UP goes deeper,
        # RIGHT and DOWN together move right only (raylib's else-if).
        script('models_box_collisions', 'walk', [quick(), quick([key(KEY_RIGHT)])] + [quick() for _ in range(9)]
               + [quick([key(KEY_RIGHT, False), key(KEY_UP)]), quick([key(KEY_UP, False), key(KEY_RIGHT), key(KEY_DOWN)]),
                  slow([key(KEY_RIGHT, False), key(KEY_DOWN, False)]), quick()]),
        script('textures_image_loading', 'frames', [quick(), slow()]),
        script('textures_image_rotate', 'cycle', [quick(), quick([button(0)]), quick([button(0, False)]), quick([key(KEY_RIGHT)]),
                                                  quick([key(KEY_RIGHT, False), button(0)]), quick([button(0, False)])]),
        script('textures_to_image', 'frames', [quick(), slow()]),
        script('textures_blend_modes', 'cycle', [quick(), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]), quick([key(KEY_SPACE)]),
                                                 quick([key(KEY_SPACE, False)]), quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]),
                                                 quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)])]),
        # Every clamp: sizes below 1 (mouse up-left), widths beyond 300 (far right) and ordinary stretches.
        script('textures_npatch_drawing', 'stretch', [quick(), quick([mouse_at(100, 100)]), quick([mouse_at(500, 300)]), slow([mouse_at(790, 440)]),
                                                      quick([mouse_at(300, 200)]), quick([mouse_at(181, 175)])]),
        script('textures_raw_data', 'frames', [quick(), slow()]),
        # Two frames with the button down add 200 bunnies; they bounce off the edges; P pauses and resumes.
        script('textures_bunnymark', 'bunnies', [quick(), quick([mouse_at(400, 225), button(0)]), quick([mouse_at(150, 300)]), quick([button(0, False)]),
                                                 slow(), quick(), quick([key(80)]), quick([key(80, False)]), quick(), quick([key(80)]),
                                                 quick([key(80, False)]), slow()], seed=0xB077),
        # Every procedural texture in turn (left clicks), back to the first.
        script('textures_image_generation', 'cycle', [quick()] + [f([button(0, i % 2 == 0)]) for i, f in enumerate([quick] * 18)], seed=0x6E1),
        # The 240-frame animation to its end, then SPACE plays it again.
        script('shapes_easings_rectangles', 'play', [quick() for _ in range(242)] + [quick([key(KEY_SPACE)]), quick([key(KEY_SPACE, False)]), quick()]),
        # Both players move (S and W together: the first test wins, as raylib's else-if).
        # Each player's camera forward and back (W/S and UP/DOWN) in long frames.
        script('core_3d_camera_split_screen', 'move', [quick(), long([key(KEY_W)]), slow([key(KEY_UP)]), long([key(KEY_W, False), key(KEY_S)]),
                                                       quick([key(KEY_UP, False), key(KEY_DOWN)]), quick([key(KEY_S, False), key(KEY_DOWN, False)])]),
        script('core_2d_camera_split_screen', 'move', [quick(), quick([key(68), key(83)]), quick(), slow([key(68, False), key(83, False), key(KEY_UP)]),
                                                       quick([key(KEY_LEFT)]), quick([key(KEY_UP, False), key(KEY_LEFT, False), key(83), key(87)]),
                                                       quick([key(83, False), key(87, False), key(65)]), quick([key(65, False)])]),
    ]
    # The probe-only raygui programs (tools/reference/gui/).
    # GuiWindowBox's close button (188..206 x 13..31) clicked, the label button clicked, the dummy rec hovered and pressed, the
    # grid's cells under the pointer (corners, an edge, outside) and the disabled grid, which answers no cell.
    out.append(script('gui_window_grid', 'controls', [quick(), quick([mouse_at(196, 20)]), quick([button(0)]), quick([button(0, False)]),
                                                     quick([mouse_at(30, 60)]), quick([button(0)]), slow([button(0, False)]), quick([mouse_at(300, 40)]),
                                                     quick([button(0)]), quick([button(0, False)]), quick([mouse_at(15, 145)]), quick([mouse_at(389, 289)]),
                                                     quick([mouse_at(130, 200)]), quick([mouse_at(10, 140)]), quick([mouse_at(395, 145)]),
                                                     quick([mouse_at(320, 85)]), slow()]))
    # The toggle slider clicked three times (to its last item and back to the first), the combo box pressed on its box and on
    # its selector button, a list item chosen, the list scrolled by the wheel and another item chosen, and the disabled
    # controls pressed.
    out.append(script('gui_toggle_combo_list', 'controls', [quick(), quick([mouse_at(100, 25)]), quick([button(0)]), quick([button(0, False)]),
                                                           quick([button(0)]), quick([button(0, False)]), quick([button(0)]), slow([button(0, False)]),
                                                           quick([mouse_at(60, 75)]), quick([button(0)]), quick([button(0, False)]), quick([mouse_at(200, 75)]),
                                                           quick([button(0)]), quick([button(0, False)]), quick([mouse_at(300, 30)]), quick([button(0)]),
                                                           slow([button(0, False)]), quick([(MOUSE_WHEEL, 0, -1, 0)]), quick([(MOUSE_WHEEL, 0, -1, 0)]),
                                                           quick([mouse_at(300, 100)]), quick([button(0)]), quick([button(0, False)]),
                                                           quick([mouse_at(60, 150)]), quick([button(0)]), quick([button(0, False)]),
                                                           quick([mouse_at(300, 170)]), slow()]))
    # The first tab clicked, the last one (the bar then moves left by 240), a tab's close button after the move, a middle press
    # over a tab; the message box's second and third buttons and its close button; the disabled box pressed.
    out.append(script('gui_message_tabs', 'controls', [quick(), quick([mouse_at(80, 12)]), quick([button(0)]), quick([button(0, False)]),
                                                      quick([mouse_at(470, 12)]), quick([button(0)]), slow([button(0, False)]), quick([mouse_at(200, 10)]),
                                                      quick([button(0)]), quick([button(0, False)]), quick([mouse_at(100, 12)]), quick([button(2)]),
                                                      quick([button(2, False)]), quick([mouse_at(200, 195)]), quick([button(0)]), quick([button(0, False)]),
                                                      quick([mouse_at(300, 195)]), quick([button(0)]), quick([button(0, False)]), quick([mouse_at(347, 72)]),
                                                      quick([button(0)]), quick([button(0, False)]), quick([mouse_at(430, 140)]), quick([button(0)]),
                                                      slow([button(0, False)])]))
    # The value box pressed; the secret view switched on, the secret box entered (edit mode) and Cancel pressed; the plain box
    # entered, which turns raygui's shared edit mode on for both, and Done pressed; the secret box closed, its view switched
    # off; the disabled value box pressed.
    clicks = lambda x, y: [quick([mouse_at(x, y)]), quick([button(0)]), quick([button(0, False)])]
    out.append(script('gui_value_input', 'controls', [quick()] + clicks(100, 20) + clicks(285, 130) + clicks(100, 130) + clicks(230, 175)
                      + clicks(100, 258) + clicks(150, 315) + clicks(297, 62) + clicks(285, 130) + clicks(420, 20) + [slow()]))
    repeated = sorted({item['name'] for item in out if sum(other['name'] == item['name'] for other in out) > 1})
    if repeated:
        raise ProbeFailure(f'examples: script names used more than once: {repeated}')
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
    target = 1.0 / TARGET_FPS[item['example']] if item['example'] in TARGET_FPS else TARGET
    measured = item['start']
    frames = []
    for events, gap, draw in item['frames']:
        begin = previous + gap
        update = begin - previous
        end = begin + draw
        frame = update + (end - begin)
        after = end + (target - frame) if frame < target else end
        frames.append(dict(events=events, begin=begin, end=end, after=after))
        previous = own_wait(item['example'], measured, after)
        measured = previous
    return dict(item, frames=frames)


def own_wait(example, measured, after):
    """The clock when the next frame's gap starts: `after`, or for an example that waits itself after
    EndDrawing (core_custom_frame_control, from its previousTime `measured`) the end of its WaitTime:
    waitTime = (1.0f/(float)targetFPS) - (currentTime - previousTime), then WaitTime((float)waitTime) when it is
    positive, whose destination is GetTime() + seconds in binary64."""
    if example not in OWN_WAIT:
        return after
    wait = fp.f32(1.0 / fp.f32(float(OWN_WAIT[example]))) - (after - measured)
    return after + fp.f32(wait) if wait > 0.0 else after


# -----------------------------------------------------------------------------
# Contract predictions

def frame_times(item):
    """GetFrameTime() during each frame's update: 0, then the previous frame's update + draw + wait
    (binary64 sums as rcore.c's EndDrawing computes them, read as a float)."""
    times, previous, last = [], item['start'], 0.0
    for frame in item['frames']:
        times.append(fp.f32(last))
        total = (frame['begin'] - previous) + (frame['end'] - frame['begin'])
        if frame['after'] != frame['end']:
            total += frame['after'] - frame['end']
        last, previous = total, frame['after']
    return times


def slider_bar(drag, bounds, value, low, high, mouse, down):
    """raygui's GuiSliderBar update (SLIDER_WIDTH 0) in F32: drag is guiControlExclusiveRec or None."""
    x, y, w, h = bounds
    inside = x <= mouse[0] < x + w and y <= mouse[1] < y + h
    pointed = fp.f32(fp.f32(fp.f32(high - low) * fp.f32(fp.f32(fp.f32(mouse[0] - x) - 0.0) / fp.f32(w - 0.0))) + low)
    if drag is not None:
        if not down:
            drag = None
        elif [int(v) for v in drag] == [int(v) for v in bounds]:
            value = pointed
    elif inside and down:
        drag, value = bounds, pointed
    return drag, min(max(value, low), high)


def circle_sector_refusal(item, libm):
    """shapes_circle_sector_drawing: DrawCircleSector(Lines) with the values the four slider bars left on the
    previous frames; a segment count below rshapes.c's minimum is estimated (glibc 2.39 only)."""
    start, end, radius, segments, drag = 0.0, 180.0, 180.0, 10.0, None
    down, mouse = False, (0.0, 0.0)
    for index, frame in enumerate(item['frames']):
        for kind, p0, p1, _ in frame['events']:
            if kind == MOUSE_DOWN and p0 == 0:
                down = True
            elif kind == MOUSE_UP and p0 == 0:
                down = False
            elif kind == MOUSE_POSITION:
                mouse = (float(p0), float(p1))
        for args in (fp.sector_args(start, end, float(int(segments)), libm), fp.stepped_args(start, end, float(int(segments)), libm)):
            if args is None or not all(fp.accepted(libm, a) for a in args):
                return index
        drag, start = slider_bar(drag, (600.0, 40.0, 120.0, 20.0), start, 0.0, 720.0, mouse, down)
        drag, end = slider_bar(drag, (600.0, 70.0, 120.0, 20.0), end, 0.0, 720.0, mouse, down)
        drag, radius = slider_bar(drag, (600.0, 140.0, 120.0, 20.0), radius, 0.0, 200.0, mouse, down)
        drag, segments = slider_bar(drag, (600.0, 170.0, 120.0, 20.0), segments, 0.0, 100.0, mouse, down)
    return None


def bullet_hell_refusal(item, libm):
    """shapes_bullet_hell: the frame whose spawned directions (sinf/cosf of dir*DEG2RAD, refusing that frame
    and every later one) or DrawRectanglePro rotations (frame + 1 and frame + 46 degrees) leave the profile."""
    rows, base, increment, cooldown, timer = 6, 0.0, 5, 2.0, 2.0
    down = set()
    for index, frame in enumerate(item['frames']):
        previous = set(down)
        for kind, code, _, _ in frame['events']:
            if kind == KEY_DOWN_EVENT:
                down.add(code)
            elif kind == KEY_UP_EVENT:
                down.discard(code)
        pressed = down - previous
        timer = fp.f32(timer - 1.0)
        if timer < 0:
            timer = cooldown
            per = fp.f32(360.0 / rows)
            for row in range(rows):
                direction = fp.f32(base + fp.f32(per * row))
                if not fp.accepted(libm, fp.f32(direction * fp.DEG2RAD)):
                    return index
            base = fp.f32(base + increment)
        if pressed & {KEY_RIGHT, 68} and rows < 359:
            rows += 1
        if pressed & {KEY_LEFT, KEY_A} and rows > 1:
            rows -= 1
        if 90 in pressed and cooldown > 1:
            cooldown -= 1.0
        if 88 in pressed:
            cooldown += 1.0
        if KEY_SPACE in down:
            increment = (increment + 1) % 360
        rotation = float(index + 1)
        for angle in (rotation, rotation + 45.0):
            if not fp.accepted(libm, fp.f32(fp.f32(angle) * fp.DEG2RAD)):
                return index
    return None


# Examples whose own geometry takes sinf/cosf of values their controls change, or whose rotations come from
# the seeded random stream (textures_particles_blending) or from the clock (core_smooth_pixelperfect). Under
# the glibc profiles
# they refuse nothing and every frame is compared. Under AppleLibm the refusal frame is the one Jonlib
# reports (every frame before it is still compared with raylib); it is not predicted independently.
# Examples whose native run is undefined behavior in C, with the reason. Jonlib refuses the operation, so
# every frame of the port is a contract (refused from the first one) on every profile and no frame of the
# native example is evidence.
UNDEFINED_NATIVE = {
    # ImageKernelConvolution converts alphaSum*255.0f with an (unsigned char) cast. The sharpen kernel sums to
    # 2 on the image's first and last rows (510.0f) and the Sobel kernel to -2 on its first pixel (-510.0f):
    # out-of-range conversions (C11 6.3.1.4). docs/CONVOLUTION.md.
    'textures_image_kernel': 'ImageKernelConvolution casts out-of-range alpha sums to unsigned char',
    # Its CodepointRemoveDuplicates shifts the list with codepointsNoDups[k] = codepointsNoDups[k + 1] up to
    # k = count - 1 at the first repeated codepoint: one int read past the codepointCount ints allocated. The
    # text repeats U+3000 and its line break, so the read happens before the first frame. docs/TEXT.md.
    'text_codepoints_loading': 'CodepointRemoveDuplicates reads one int past its array',
    # It draws the last 441 samples of its one-second buffer as 800 columns, and the end of the last column is
    # buffer[SAMPLE_RATE - SAMPLE_RATE/100 + 800*SAMPLE_RATE/100/screenWidth] = buffer[SAMPLE_RATE]: one float
    # past the array, in every frame. docs/AUDIO.md.
    'audio_stream_callback': 'the last column of its wave reads one float past its buffer',
}
REPORTED = {'textures_sprite_stacking', 'shapes_triangle_strip', 'shapes_recursive_tree', 'textures_particles_blending', 'core_smooth_pixelperfect',
            'shapes_double_pendulum', 'shapes_vector_angle', 'shapes_penrose_tile', 'textures_magnifying_glass',
            'shapes_rlgl_color_wheel', 'shapes_rectangle_advanced', 'core_input_gestures_testbed', 'core_input_gamepad',
            'shapes_easings_ball', 'shapes_easings_box', 'shapes_easings_testbed', 'textures_textured_curve',
            'core_2d_camera_mouse_zoom', 'shapes_simple_particles',
            'shapes_math_sine_cosine',
            'shapes_pie_chart',
            'shapes_digital_clock', 'shapes_clock_of_clocks'}


def refusal(item, libm):
    """The index of the first frame Jonlib refuses (None when none is; 'reported' to take Jonlib's own)."""
    if item['example'] in UNDEFINED_NATIVE:
        return 0
    if item['name'] in UNDEFINED_FROM:
        return UNDEFINED_FROM[item['name']]
    if item['example'] in REPORTED:
        return 'reported' if libm == 'AppleLibm' else None
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
        return None
    if item['example'] in ('textures_srcrec_dstrec', 'textures_polygon_drawing'):
        # DrawTexturePro's sinf/cosf of (float)rotation*DEG2RAD, rotation = frame + 1; the polygon's
        # Vector2Rotate takes the same angle*DEG2RAD, angle = frame + 1.
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
    if item['example'] == 'shapes_easings_rectangles':
        # DrawRectanglePro turns by EaseLinearIn(frames, 0, 360, 240) degrees while playing (240 frames); a zero
        # rotation takes no sinf/cosf. SPACE restarts the count.
        frames, playing = 0, True
        for index, frame in enumerate(item['frames']):
            space = any(kind == KEY_DOWN_EVENT and code == KEY_SPACE for kind, code, _, _ in frame['events'])
            if playing:
                frames += 1
                rotation = fp.f32(fp.f32(fp.f32(360.0 * frames) / 240.0) + 0.0)
                if rotation != 0.0 and not fp.accepted(libm, fp.f32(rotation * fp.DEG2RAD)):
                    return index
                playing = frames < 240
            elif space:
                frames, playing = 0, True
        return None
    if item['example'] == 'shaders_shapes_textures':
        # DrawPoly(center, 6, 80, 0): the F32-accumulated angles k*60 degrees.
        central, step = 0.0, fp.f32(fp.f32(360.0 / 6.0) * fp.DEG2RAD)
        angles = [central]
        for _ in range(6):
            central = fp.f32(central + step)
            angles.append(central)
        return None if all(fp.accepted(libm, a) for a in angles) else 0
    if item['example'] == 'shapes_bullet_hell':
        return bullet_hell_refusal(item, libm)
    if item['example'] == 'shapes_circle_sector_drawing':
        return circle_sector_refusal(item, libm)
    if item['example'] in ('shapes_ring_drawing', 'shapes_rounded_rectangle_drawing'):
        # Both start with 0 segments: rshapes.c estimates the count with acosf, which only the glibc 2.39
        # profile reproduces.
        return 0 if libm == 'AppleLibm' else None
    if item['example'] == 'shapes_math_angle_rotation':
        # The example's sinf/cosf of 0, 30, 60 and 90 degrees and of totalAngle = frame + 1 (below 360 here).
        for index in range(len(item['frames'])):
            if not all(fp.accepted(libm, fp.f32(fp.f32(float(d)) * fp.DEG2RAD)) for d in (0, 30, 60, 90, index + 1)):
                return index
        return None
    if item['example'] == 'shapes_following_eyes':
        # Outside a sclera's reach the iris needs atan2f and sinf/cosf of its angle, which the Apple profile
        # does not verify; the script starts with the mouse at the origin, outside both.
        return 0 if libm == 'AppleLibm' else None
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
static unsigned seed = 0;
// An example's time(): the script's seed (the seconds at InitWindow) plus the scripted clock's whole seconds.
time_t JonlibExampleTime(time_t *out) { time_t now = (time_t)seed + (time_t)probe_clock; if (out) *out = now; return now; }
// An example's GetFileModTime: the script's seed, whatever the file.
long JonlibExampleFileModTime(const char *fileName) { (void)fileName; return (long)seed; }
// An example's GetApplicationDirectory: the script's directory, which is the working directory.
const char *JonlibExampleApplicationDirectory(void) { return "./"; }
// An example's LoadImageFromScreen: the desktop's image. The memory platform's has the rows from the bottom and red and
// blue swapped; both are turned back here.
Image JonlibExampleLoadImageFromScreen(void) {
    Image image = LoadImageFromScreen();
    unsigned char *data = image.data;
    int stride = image.width*4;
    for (int y = 0; data && y < image.height/2; y++) {
        unsigned char *top = data + y*stride, *bottom = data + (image.height - 1 - y)*stride;
        for (int x = 0; x < stride; x++) { unsigned char held = top[x]; top[x] = bottom[x]; bottom[x] = held; }
    }
    for (int i = 0; data && i < image.width*image.height; i++) { unsigned char held = data[i*4]; data[i*4] = data[i*4 + 2]; data[i*4 + 2] = held; }
    return image;
}
// An example's own WaitTime: its sleep ends at raylib's destination, GetTime() + seconds.
void JonlibExampleWaitTime(double seconds) { if (!(seconds < 0)) probe_after = probe_clock + seconds; WaitTime(seconds); }

// The audio clock (tools/reference/audio_clock.c): the device's thread is stopped once it is open, and every whole
// period of 10 ms since then on the scripted clock is one callback, asked for at the start of each loop pass.
#ifdef JONLIB_EXAMPLE_AUDIO_CLOCK
void JonlibAudioClockStop(void);
void JonlibAudioClockPump(unsigned periods);
static double audio_opened = 0.0;
static unsigned audio_periods = 0;
static int audio_open = 0;
void JonlibExampleInitAudioDevice(void) { InitAudioDevice(); JonlibAudioClockStop(); audio_opened = probe_clock; audio_periods = 0; audio_open = 1; }
static void audio_tick(void)
{
    if (!audio_open) return;
    unsigned due = (unsigned)(int)((probe_clock - audio_opened)*100.0);
    if (due > audio_periods) { JonlibAudioClockPump(due - audio_periods); audio_periods = due; }
}
#else
static void audio_tick(void) {}
#endif

#define MAX_FRAMES 1024
#define MAX_EVENTS 64
typedef struct { double begin, end, after; int count; int events[MAX_EVENTS][4]; } Frame;
static Frame frames[MAX_FRAMES];
static int frame_count = 0, frame_index = 0, width = 0, height = 0;
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
    audio_tick();
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
    # -D_DEFAULT_SOURCE as raylib's examples/Makefile passes it (strnlen in shapes_penrose_tile).
    clock = ['-DJONLIB_EXAMPLE_AUDIO_CLOCK'] if name in AUDIO_CLOCK else []
    # A probe-only program (jonlib/...) is one of tools/reference/; raygui.h is the pinned examples' own.
    path = ROOT / 'tools/reference' / source[len('jonlib/'):] if source.startswith('jonlib/') else probe.args.raylib_source / 'examples' / source
    raygui = '-I' + str(probe.args.raylib_source / 'examples/core')
    probekit.run(['clang', '-std=c11', '-D_DEFAULT_SOURCE', '-O2', '-ffp-contract=off', *clock, '-include', SHIM, include, raygui, '-c',
                  path, '-o', probe.work / f'{name}.o'])
    probekit.run(['clang', '-std=c11', '-O2', '-ffp-contract=off', *clock, include, '-c', driver, '-o', probe.work / 'driver.o'])
    objects = [probe.work / f'{name}.o', probe.work / 'driver.o']
    if name in AUDIO:
        objects.append(probe.work / 'raudio.o')
        unit = AUDIO_CLOCK_UNIT if name in AUDIO_CLOCK else probe.args.raylib_source / 'src/raudio.c'
        probekit.run(['clang', '-std=c11', '-D_DEFAULT_SOURCE', '-O2', '-ffp-contract=off', '-w', '-DMA_ENABLE_ONLY_SPECIFIC_BACKENDS', '-DMA_ENABLE_NULL', include,
                      '-c', unit, '-o', objects[-1]])
    probekit.run(['clang', *objects, probe.library, '-lm', '-o', binary])
    return binary


def native_frames(probe, binary, index, item):
    path = probe.work / f'script-{index}.txt'
    # Only the frames C defines are run.
    cut = UNDEFINED_FROM.get(item['name'])
    path.write_text(script_text(item if cut is None else dict(item, frames=item['frames'][:cut])))
    source, _ = EXAMPLES[item['example']]
    in_module = item['example'] == 'textures_logo_raylib' or item['example'] in IO_SETUP
    cwd = probe.args.raylib_source / 'examples' / source.split('/')[0] if in_module else probe.work
    if item['example'] in SCRATCH:
        cwd = scratch(probe, index, native=True) / WORKING.get(item['example'], '')
    result = subprocess.run([str(binary)], cwd=cwd, env=dict(probekit.ENV, JONLIB_EXAMPLE_SCRIPT=str(path)), stdin=subprocess.DEVNULL,
                            capture_output=True, text=True, timeout=600)
    if result.returncode:
        raise ProbeFailure(f'examples: native {item["name"]} failed ({result.returncode}): {result.stderr[-2000:]}')
    return [line[2:] for line in result.stdout.splitlines() if line.startswith('F ')]


# -----------------------------------------------------------------------------
# The presented Image built from raylib's bytes (src/present.bend's rules)

def decode(runs, width=WIDTH, height=HEIGHT):
    words = []
    for token in runs.split(',')[:-1]:
        count, word = token.split('*')
        words += [int(word, 16)] * int(count)
    if len(words) != width * height:
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


def expected_row(runs, width=WIDTH, height=HEIGHT):
    return runs + ' ' + preorder(quadtree(decode(runs, width, height), width, height))


# -----------------------------------------------------------------------------
# Bend candidate: one program per example

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import MODULE as Ex

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

READY
REPLAY
'''

PURE_READY = '''def replay.parts(+core: J.Core, script: +List<J.ReplayFrame>, parts: J.Frame & Ex.State) -> String:
  (frame, state) = parts
  join(J.Program.replay(~Ex.State, ~Ex.program(M.LIBM{}), ~show.fn(), script, core, frame, state))

def replay.ready(script: +List<J.ReplayFrame>, ready: J.Core & (J.Frame & Ex.State)) -> String:
  (+core, parts) = ready
  replay.parts(core, script, parts)
'''

# An Effects program (IO in its loop) replays with J.Program.replay_io.
EFFECTS_READY = '''def replay.parts(+core: J.Core, script: +List<J.ReplayFrame>, parts: J.Frame & Ex.State) -> IO(String):
  (frame, state) = parts
  IO.bind(List<String>, String, J.Program.replay_io(~Ex.State, ~Ex.program(M.LIBM{}), ~show.fn(), script, core, frame, state), lines => IO.pure(String, join(lines)))

def replay.ready(script: +List<J.ReplayFrame>, ready: J.Core & (J.Frame & Ex.State)) -> IO(String):
  (+core, parts) = ready
  replay.parts(core, script, parts)
'''

PURE_REPLAY = '''def replay(SETUP_PARAMS script: +List<J.ReplayFrame>, core: Maybe<J.Core>, frame: Maybe<J.Frame>) -> String:
  match core frame:
    case Some{+core} Some{frame}: replay.ready(script, SETUP)
    case _ _: "no window"
'''

IO_REPLAY = '''def replay(SETUP_PARAMS script: +List<J.ReplayFrame>, core: Maybe<J.Core>, frame: Maybe<J.Frame>) -> IO(String):
  match core frame:
    case Some{+core} Some{frame}: IO.bind(J.Core & (J.Frame & Ex.State), String, SETUP, ready => IO.pure(String, replay.ready(script, ready)))
    case _ _: IO.pure(String, "no window")
'''

EFFECTS_REPLAY = '''def replay(SETUP_PARAMS script: +List<J.ReplayFrame>, core: Maybe<J.Core>, frame: Maybe<J.Frame>) -> IO(String):
  match core frame:
    case Some{+core} Some{frame}: IO.bind(J.Core & (J.Frame & Ex.State), String, SETUP, ready => replay.ready(script, ready))
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


def render(items, libm, logo, raylib_source, directories=None, listed=None):
    """One program per example (actions are example names): every script of
    the example, one output line each. `directories` gives a SCRATCH
    example's scripts their directories, by script index; `listed` gives a
    LISTED example's scripts their listings (listings())."""
    def build(selected, gpu):
        if len(selected) != 1:
            raise ProbeFailure('examples: one example per batch')
        name = selected[0]
        _, setup = EXAMPLES[name]
        setup_params = '+seed: U32, ' if name in SEEDED else {'textures_logo_raylib': 'logo: Result<&1, &1, J.Surface.IOError, J.Surface>, '}.get(name, '')
        if name in SCRATCH:
            setup_params += '+dir: String, '
        if name in LISTED:
            setup_params += '+listings: +List<Ex.Listing>, '
        io = name in IO_SETUP
        effects = name in EFFECTS
        if effects and not io:
            raise ProbeFailure(f'examples: {name}: an Effects program is replayed in IO (add it to IO_SETUP, its setup in IO)')
        resources = 'dir' if name in SCRATCH else json.dumps(str(raylib_source / 'examples' / EXAMPLES[name][0].split('/')[0]) + '/')
        body = (PROGRAM.replace('MODULE', MODULES.get(name, f'../../examples/{name}.bend')).replace('READY', EFFECTS_READY if effects else PURE_READY)
                .replace('REPLAY', EFFECTS_REPLAY if effects else IO_REPLAY if io else PURE_REPLAY).replace('EXAMPLE', name)
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
            width, height = size_of(name)
            window = (f'J.Core.init_window_flags({flags}, {width}, {height}, f64({start >> 32}, {start & 0xFFFFFFFF})), '
                      f'J.Frame.init_window_flags({flags}, {width}, {height})')
            args = f'{item["seed"]}, ' if name in SEEDED else {'textures_logo_raylib': 'logo, '}.get(name, '')
            if name in SCRATCH:
                args += json.dumps(str(directories[index]) + '/') + ', '
            if name in LISTED:
                args += listings_text(listed[index]) + ', '
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
        probekit.run([*probekit.compiler_command(cli), ROOT / f'examples/{name}.bend', '-o', binary], timeout=probekit.COMPILE_TIMEOUT, env=probekit.compiler_env())
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
    parser.add_argument('--assume-libm', choices=('AppleLibm', 'Glibc239Libm'),
                        help="run Jonlib and compute the refusals under another host's M.Libm profile (diagnostic: the "
                             'frames before a refusal are still compared with this host, whose libm may differ there)')


def main():
    args = probekit.arguments(__doc__, configure)
    name = ('examples-interactive' if args.interactive else 'examples-assumed' if args.assume_libm
            else f'examples-{args.category}' if args.category else 'examples' + ('-subset' if args.example else ''))
    probe = probekit.Probe(name, args, raylib_options=ip.OPTIONS)
    if args.interactive:
        interactive(probe, args.interactive)
        return
    definitions = ip.variant_definitions(probe.library)
    wanted = dict(SUPPORT_CUSTOM_FRAME_CONTROL=False, SUPPORT_BUSY_WAIT_LOOP=False, SUPPORT_PARTIALBUSY_WAIT_LOOP=True,
                  SUPPORT_AUTOMATION_EVENTS=True, SUPPORT_GESTURES_SYSTEM=True, SUPPORT_SCREEN_CAPTURE=True)
    if definitions != wanted:
        raise ProbeFailure(f'examples: reference build definitions {definitions}, expected {wanted}')
    libm = args.assume_libm or gradient_reference()
    logo = probe.args.raylib_source / 'examples/textures/resources/raylib_logo.png'
    if not logo.is_file():
        raise ProbeFailure(f'examples: {logo} is missing from the pinned raylib checkout')

    items = [item for item in scripts() if (not args.example or item['example'] in args.example)
             and (not args.category or item['example'].split('_')[0] == args.category)]
    names = [name for name in EXAMPLES if any(item['example'] == name for item in items)]
    # A lane may take long: the JavaScript lane rasterizes a TTF font at size 96 in about 8 minutes.
    scratch_reset(probe, items)
    directories = {index: scratch(probe, index) for index, item in enumerate(items) if item['example'] in SCRATCH}
    left = {}

    def parse_lane(text, chosen, lane):
        """The files a lane's scripts left; their directories are emptied for the next lane."""
        for index, item in enumerate(items):
            if item['example'] == chosen[0] and index in directories:
                left[lane, item['name']] = scratch_left(probe, index)
        scratch_reset(probe, items, chosen[0])
        return ['\n'.join(line for line in text.splitlines() if line.strip())]

    # The listings are read from the reference's directories, which are put again, the same way, before it runs.
    scratch_reset(probe, items, native=True)
    listed = {index: listings(scratch(probe, index, native=True).resolve(), WORKING[item['example']]) for index, item in enumerate(items) if item['example'] in LISTED}
    lanes = probe.candidates(render(items, libm, logo, probe.args.raylib_source, directories, listed), names, batch=1, timeout=max([LANE_TIMEOUT] + [SLOW_LANES.get(name, 0) for name in names]), parse_lane=parse_lane)

    def reported(item):
        """The first frame the CPU-1 lane refused in this script (None when it refused none)."""
        scripts_of = [other['name'] for other in items if other['example'] == item['example']]
        printed = lanes['cpu-1'][names.index(item['example'])].split('\n')
        if len(printed) != len(scripts_of):
            raise ProbeFailure(f'examples: {item["example"]} printed {len(printed)} scripts, expected {len(scripts_of)}')
        frames_of = printed[scripts_of.index(item['name'])].split('|')[:-1]
        return next((k for k, frame in enumerate(frames_of) if frame == 'null null'), None)

    rows_by_script, refused, binaries, unpredicted, native_left = [], {}, {}, [], {}
    scratch_reset(probe, items, native=True)
    for index, item in enumerate(items):
        cut = refusal(item, libm)
        if cut == 'reported':
            cut = reported(item)
            unpredicted.append(item['name'])
        refused[item['name']] = cut
        rows = []
        if cut != 0:
            name = item['example']
            if name not in binaries:
                binaries[name] = build_reference(probe, name)
            rows = [expected_row(runs, *size_of(name)) for runs in native_frames(probe, binaries[name], index, item)]
            if index in directories and cut is None:
                native_left[item['name']] = scratch_left(probe, index, native=True)
            if index in listed and listed[index] != listings(scratch(probe, index, native=True).resolve(), WORKING[name]):
                raise ProbeFailure(f'examples: {item["name"]}: the directories the reference listed are not the ones the port was handed')
        if cut is not None:
            rows = rows[:cut] + ['null null'] * (len(item['frames']) - cut)
        rows_by_script.append('|'.join(rows) + '|')
    expected = ['\n'.join(row for row, item in zip(rows_by_script, items) if item['example'] == name) for name in names]

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
    for (lane, script_name), files in left.items():
        if script_name in native_left and files != native_left[script_name]:
            raise ProbeFailure(f'examples: {script_name} on {lane} left {sorted(files)} with other names or bytes than the reference\'s {sorted(native_left[script_name])}')
    frames = sum(row.count('|') for row in rows_by_script)
    contract_frames = sum(row.count('null null') for row in rows_by_script)
    probe.finish(examples=len(names), scripts=len(items), frames=frames, compared_frames=frames - contract_frames,
                 refused_frames=contract_frames, libm=libm, refusals=refused, reported_refusals=unpredicted, scripts_with_files=len(native_left),
                 scripts_sha256=hashlib.sha256(json.dumps(items, default=repr).encode()).hexdigest())


if __name__ == '__main__':
    main()
