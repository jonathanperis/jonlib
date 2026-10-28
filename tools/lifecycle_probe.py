#!/usr/bin/env python3
"""Compare lifecycle calls that return no pixels with the pinned raylib.

UnloadImage, UnloadImageColors, IsImageValid, MemAlloc/MemRealloc/MemFree,
UnloadFontData, UnloadModelAnimations,
UnloadAutomationEventList, UnloadVrStereoConfig, CloseWindow, the screen
sizes, rlEnableTexture, rlDisableTexture, rlUnloadTexture, rlLoadTextureCubemap
and rlglClose. Each Bend call is the symbol in the progress record. CPU-1,
CPU-2 and JavaScript lanes.
"""
import probekit

# C names the native program calls. A name is coverage only because that call
# is in NATIVE and the Bend program runs the matching symbol.
NATIVE_CALLS = (
    'IsImageValid', 'UnloadImage', 'LoadImageColors', 'UnloadImageColors',
    'MemAlloc', 'MemRealloc', 'MemFree',
    'UnloadFontData', 'UnloadModelAnimations',
    'UnloadAutomationEventList', 'UnloadVrStereoConfig',
    'GetScreenWidth', 'GetScreenHeight', 'GetRenderWidth', 'GetRenderHeight', 'CloseWindow',
    'LoadTextureFromImage', 'rlEnableTexture', 'rlDisableTexture', 'rlUnloadTexture',
    'rlLoadTextureCubemap', 'rlglClose',
)

NATIVE = r'''#include "raylib.h"
#include "rlgl.h"
#include <stdio.h>
#include <string.h>
static void colors(Color *c, int n) {
  printf("colors [");
  for (int i = 0; i < n; i++)
    printf("%s%u", i ? ", " : "", ((unsigned)c[i].r << 24) | ((unsigned)c[i].g << 16) | ((unsigned)c[i].b << 8) | c[i].a);
  printf("]\n");
}
int main(void) {
  SetTraceLogLevel(LOG_NONE);
  Color tint = {10, 20, 30, 40};
  Image im = GenImageColor(2, 1, tint);
  Image blank = {0};
  printf("valid %d\n", IsImageValid(im));
  Color *cols = LoadImageColors(im);
  colors(cols, 2);
  UnloadImageColors(cols);
  UnloadImage(im);
  printf("unloaded-colors 1\n");
  printf("invalid %d\n", IsImageValid(blank));
  Image gone = GenImageColor(2, 1, tint);
  UnloadImage(gone);
  printf("unloaded-image 1\n");

  unsigned char *mem = MemAlloc(4);
  printf("alloc [");
  for (int i = 0; i < 4; i++) printf("%s%u", i ? ", " : "", mem[i]);
  printf("]\n");
  mem[0] = 1; mem[1] = 2; mem[2] = 3; mem[3] = 4;
  unsigned char *kept = MemRealloc(mem, 2);
  printf("realloc [%u, %u]\n", kept[0], kept[1]);
  MemFree(kept);
  printf("freed 1\n");

  UnloadFontData(NULL, 0);
  printf("font 1\n");
  UnloadModelAnimations(NULL, 0);
  printf("model 1\n");
  AutomationEventList events = {0};
  UnloadAutomationEventList(events);
  printf("auto 1\n");
  VrStereoConfig vr = {0};
  UnloadVrStereoConfig(vr);
  printf("vr 1\n");

  InitWindow(16, 9, "lifecycle");
  printf("screen %d %d %d %d\n", GetScreenWidth(), GetScreenHeight(), GetRenderWidth(), GetRenderHeight());
  CloseWindow();

  InitWindow(8, 8, "lifecycle-tex");
  Image src = GenImageColor(2, 2, tint);
  Texture2D first = LoadTextureFromImage(src);
  unsigned id = first.id;
  rlEnableTexture(id);
  rlDisableTexture();
  rlUnloadTexture(id);
  Image src2 = GenImageColor(2, 2, tint);
  Texture2D second = LoadTextureFromImage(src2);
  int reused = id != 0 && second.id == id;
  rlUnloadTexture(second.id);
  UnloadImage(src);
  UnloadImage(src2);
  unsigned cube = rlLoadTextureCubemap(NULL, 1, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, 1);
  printf("tex %d\n", reused);
  printf("cube %u\n", cube);
  rlglClose();
  printf("rlgl 1\n");
  return 0;
}
'''

PROGRAM = r'''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M

def then_text(done: Unit, +text: String) -> String:
  text

def drop_frame(frame: J.Frame, +text: String) -> String:
  text

def flag(value: Bool) -> String:
  match value:
    case True{}: "1"
    case False{}: "0"

def show_owned(bytes: +List<U32>) -> String:
  List.show(~&2, ~U32, ~U32.show, bytes)

def show_bytes(bytes: List<U32>) -> String:
  List.show(~&1, ~U32, ~U32.show, bytes)

def owned_invalid_of(pair: J.Surface & Bool) -> String:
  (kept, +ok) = pair
  then_text(J.Surface.unload(kept), "invalid " ++ flag(ok))

def owned_invalid() -> String:
  owned_invalid_of(J.Surface.is_valid(J.Surface{0, 1, 7, J.Words{Array.new(U32, 0n, 0)}}))

def color_text(result: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> String:
  match result:
    case Fail{_}: "colors"
    case Done{colors}: "colors " ++ show_bytes(colors)

def unloaded_colors_of(result: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> String:
  match result:
    case Fail{_}: "unloaded-colors 0"
    case Done{colors}: then_text(J.Surface.unload_colors(colors), "unloaded-colors 1")

def unloaded_colors_line(found: Maybe<J.Surface>) -> String:
  match found:
    case None{}: "unloaded-colors 0"
    case Some{image}: unloaded_colors_of(J.Surface.colors(image))

def alloc_line() -> String:
  "alloc " ++ show_owned(J.Memory.alloc(4))

def realloc_line() -> String:
  "realloc " ++ show_owned(J.Memory.realloc([1, 2, 3, 4], 2))

def freed_line() -> String:
  then_text(J.Memory.free(J.Memory.alloc(4)), then_text(J.Memory.free(J.Memory.realloc([1, 2, 3, 4], 2)), "freed 1"))

def unloaded_font() -> Unit:
  J.Font.unload_data(Nil{})

def unloaded_model() -> Unit:
  J.Model.unload_animations(Nil{})

def unloaded_events() -> Unit:
  J.AutomationEventList.unload(J.AutomationEventList{0, 0, Nil{}})

def unloaded_vr() -> Unit:
  J.Vr.unload_stereo_config(J.VrStereoConfig{M.Matrix.identity(), M.Matrix.identity(), M.Matrix.identity(), M.Matrix.identity(), M.Vector2{0.0, 0.0}, M.Vector2{0.0, 0.0}, M.Vector2{0.0, 0.0}, M.Vector2{0.0, 0.0}, M.Vector2{0.0, 0.0}, M.Vector2{0.0, 0.0}})

def closed_frame_of(found: Maybe<J.Frame>) -> Unit:
  match found:
    case None{}: Unit{}
    case Some{frame}: J.Frame.close_window(frame)

def closed_frame() -> Unit:
  closed_frame_of(J.Frame.init_window(16, 9))

def screen_line(+core: J.Core) -> String:
  U32.show(J.Core.get_screen_width(core)) ++ " " ++ U32.show(J.Core.get_screen_height(core)) ++ " " ++ U32.show(J.Core.get_render_width(core)) ++ " " ++ U32.show(J.Core.get_render_height(core))

def closed_core_of(found: Maybe<J.Core>) -> String:
  match found:
    case None{}: "screen 0 0 0 0"
    case Some{core}: screen_line(core)

def closed_core() -> String:
  closed_core_of(J.Core.init_window(16, 9, M.Float64{0, 0}))

def closed_core_window(found: Maybe<J.Core>) -> Unit:
  match found:
    case None{}: Unit{}
    case Some{core}: J.Core.close_window(core)

def cube_line(pair: J.Frame & U32) -> String:
  (rest, +cube) = pair
  then_text(J.Rlgl.gl_close(rest), "tex 1\ncube " ++ U32.show(cube))

def tex_finish(back: Maybe<J.Texture>, frame: J.Frame) -> String:
  match back:
    case None{}: "tex 0"
    case Some{held}: cube_line(J.Rlgl.load_texture_cubemap(J.Rlgl.unload_texture(frame, held), Nil{}, 1, 7, 1))

def tex_disabled(pair: J.Frame & Maybe<J.Texture>) -> String:
  (cleared, back) = pair
  tex_finish(back, cleared)

def tex_enabled_of(pair: J.Frame & Maybe<J.Texture>) -> String:
  (moved, prev) = pair
  match prev:
    case Some{old}: drop_frame(J.Rlgl.unload_texture(moved, old), "tex 0")
    case None{}: tex_disabled(J.Rlgl.disable_texture(moved))

def tex_enabled(loaded: Maybe<J.Texture>, frame: J.Frame) -> String:
  match loaded:
    case None{}: "tex 0"
    case Some{texture}: tex_enabled_of(J.Rlgl.enable_texture(frame, texture))

def tex_loaded(pair: J.Frame & Maybe<J.Texture>) -> String:
  (frame, loaded) = pair
  tex_enabled(loaded, frame)

def tex_from(found: Maybe<J.Surface>, frame: J.Frame) -> String:
  match found:
    case None{}: "tex 0"
    case Some{image}: tex_loaded(J.Texture.load_from_image(frame, image))

def tex_opened(found: Maybe<J.Frame>) -> String:
  match found:
    case None{}: "tex 0"
    case Some{frame}: tex_from(J.Surface.create(2, 2, 169090600), frame)

def tex_line() -> String:
  tex_opened(J.Frame.init_window(8, 8))

def valid_text(pair: J.Surface & Bool) -> String:
  (kept, +ok) = pair
  "valid " ++ flag(ok) ++ "\n" ++ color_text(J.Surface.colors(kept))

def image_lines(found: Maybe<J.Surface>) -> String:
  match found:
    case None{}: "valid 0"
    case Some{image}: valid_text(J.Surface.is_valid(image))

def unloaded_image(found: Maybe<J.Surface>) -> String:
  match found:
    case None{}: "unloaded-image 0"
    case Some{image}: then_text(J.Surface.unload(image), "unloaded-image 1")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(image_lines(J.Surface.create(2, 1, 169090600)))
    IO.print(unloaded_colors_line(J.Surface.create(2, 1, 169090600)))
    IO.print(owned_invalid())
    IO.print(unloaded_image(J.Surface.create(2, 1, 169090600)))
    IO.print(alloc_line())
    IO.print(realloc_line())
    IO.print(freed_line())
    Unit <- IO.pure(Unit, unloaded_font())
    IO.print("font 1")
    Unit <- IO.pure(Unit, unloaded_model())
    IO.print("model 1")
    Unit <- IO.pure(Unit, unloaded_events())
    IO.print("auto 1")
    Unit <- IO.pure(Unit, unloaded_vr())
    IO.print("vr 1")
    Unit <- IO.pure(Unit, closed_frame())
    Unit <- IO.pure(Unit, closed_core_window(J.Core.init_window(16, 9, M.Float64{0, 0})))
    IO.print("screen " ++ closed_core())
    IO.print(tex_line())
    IO.print("rlgl 1")
'''


def kept_lines(text):
    return [line for line in text.splitlines() if line and not line.startswith('INFO:')]


def main():
    probe = probekit.Probe('lifecycle', probekit.arguments(__doc__))
    expected = kept_lines(probe.native(NATIVE))
    lanes = probe.candidates(lambda selected, gpu: PROGRAM, ['lifecycle'], batch=1,
                             parse=lambda text, selected: ['\n'.join(kept_lines(text))])
    probe.compare(['\n'.join(expected)], lanes, describe=lambda index: 'lifecycle')
    probe.finish(lines=len(expected), calls=len(NATIVE_CALLS))


if __name__ == '__main__':
    main()
