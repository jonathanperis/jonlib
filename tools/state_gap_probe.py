#!/usr/bin/env python3
"""Compare frame-state edges with raylib's software renderer.

ClearBackground fills only the active scissor. rlBegin while a primitive is
already active is an rlsw error and leaves that primitive in place. rlSetTexture
during that primitive is refused and the texture stays with the caller, so a
later quad can still sample it. BeginVrStereoMode and EndVrStereoMode leave
the frame unchanged. LoadTextureCubemap ('TextureCubemap') keeps id 0 and the
layout's face size. CPU-1, CPU-2 and JavaScript.
"""
import probekit

# Quoted API names this probe compares, including the TextureCubemap alias.
WITNESSED = ('TextureCubemap', 'BeginVrStereoMode', 'EndVrStereoMode', 'rlSetTexture', 'LoadTextureCubemap')

NATIVE = r'''#include "raylib.h"
#include "rlgl.h"
#include <stdio.h>
static void dump(const char *name) {
  unsigned char p[8*8*4];
  rlCopyFramebuffer(0, 0, 8, 8, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, p);
  printf("%s", name);
  for (int i = 0; i < 8*8; i++) {
    unsigned char t = p[4*i]; p[4*i] = p[4*i+2]; p[4*i+2] = t;
    printf(" %u %u %u %u", p[4*i], p[4*i+1], p[4*i+2], p[4*i+3]);
  }
  printf("\n");
}
int main(void) {
  SetTraceLogLevel(LOG_NONE);
  InitWindow(8, 8, "state");
  BeginDrawing();
  ClearBackground(BLACK);
  BeginScissorMode(2, 3, 4, 2);
  ClearBackground(RED);
  EndScissorMode();
  EndDrawing();
  dump("scissor");
  BeginDrawing();
  ClearBackground(WHITE);
  rlBegin(RL_LINES);
  rlBegin(RL_TRIANGLES);
  rlColor4ub(255, 0, 0, 255);
  rlVertex2i(1, 1);
  rlVertex2i(6, 1);
  rlEnd();
  EndDrawing();
  dump("begin");
  CloseWindow();
  InitWindow(8, 8, "bind");
  Image redImage = GenImageColor(2, 2, RED);
  Image blueImage = GenImageColor(2, 2, BLUE);
  Texture2D redTex = LoadTextureFromImage(redImage);
  Texture2D blueTex = LoadTextureFromImage(blueImage);
  UnloadImage(redImage);
  UnloadImage(blueImage);
  BeginDrawing();
  ClearBackground(WHITE);
  rlSetTexture(redTex.id);
  rlBegin(RL_QUADS);
  rlSetTexture(blueTex.id);
  rlColor4ub(255, 255, 255, 255);
  rlTexCoord2f(0.0f, 0.0f); rlVertex2f(1.0f, 1.0f);
  rlTexCoord2f(0.0f, 1.0f); rlVertex2f(1.0f, 4.0f);
  rlTexCoord2f(1.0f, 1.0f); rlVertex2f(4.0f, 4.0f);
  rlTexCoord2f(1.0f, 0.0f); rlVertex2f(4.0f, 1.0f);
  rlEnd();
  rlSetTexture(0);
  rlSetTexture(blueTex.id);
  rlBegin(RL_QUADS);
  rlColor4ub(255, 255, 255, 255);
  rlTexCoord2f(0.0f, 0.0f); rlVertex2f(1.0f, 5.0f);
  rlTexCoord2f(0.0f, 1.0f); rlVertex2f(1.0f, 7.0f);
  rlTexCoord2f(1.0f, 1.0f); rlVertex2f(4.0f, 7.0f);
  rlTexCoord2f(1.0f, 0.0f); rlVertex2f(4.0f, 5.0f);
  rlEnd();
  rlSetTexture(0);
  EndDrawing();
  dump("bind");
  UnloadTexture(redTex);
  UnloadTexture(blueTex);
  CloseWindow();
  InitWindow(8, 8, "vr");
  BeginDrawing();
  ClearBackground(WHITE);
  VrStereoConfig stereo = { 0 };
  BeginVrStereoMode(stereo);
  DrawRectangle(1, 2, 3, 2, RED);
  EndVrStereoMode();
  EndDrawing();
  dump("vr");
  CloseWindow();
  InitWindow(8, 8, "cube");
  Image strip = GenImageColor(6, 36, RED);
  Image square = GenImageColor(8, 8, BLUE);
  TextureCubemap stripMap = LoadTextureCubemap(strip, CUBEMAP_LAYOUT_AUTO_DETECT);
  TextureCubemap squareMap = LoadTextureCubemap(square, CUBEMAP_LAYOUT_AUTO_DETECT);
  printf("cube %u %d %d %d %d\n", stripMap.id, stripMap.width, stripMap.height, stripMap.mipmaps, stripMap.format);
  printf("cube %u %d %d %d %d\n", squareMap.id, squareMap.width, squareMap.height, squareMap.mipmaps, squareMap.format);
  UnloadImage(strip);
  UnloadImage(square);
  CloseWindow();
  return 0;
}
'''

HEADER = r'''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def bytes(values: List<U32>) -> String:
  match values:
    case Nil{}: ""
    case Con{head, rest}: " " ++ U32.show(head) ++ bytes(rest)
def image_bytes(data: (U32 & U32) & (U32 & List<U32>)) -> String:
  ((_, _), (_, values)) = data
  bytes(values)
def frame_text(done: Unit, found: Maybe<J.Surface>) -> String:
  match found:
    case None{}: " none"
    case Some{image}: image_bytes(J.Surface.export(image))
def frame_bytes(pair: J.Frame & Maybe<J.Surface>) -> String:
  (frame, found) = pair
  frame_text(J.Frame.close_window(frame), found)
def scissor_frame(frame: J.Frame) -> J.Frame & Maybe<J.Surface>:
  J.Frame.framebuffer(J.Frame.end_drawing(J.Frame.end_scissor_mode(J.Frame.clear_background(J.Frame.begin_scissor_mode(J.Frame.clear_background(J.Frame.begin_drawing(frame), J.Color.BLACK()), 2.0, 3.0, 4.0, 2.0), J.Color.RED()))))
def scissor_lines(opened: Maybe<J.Frame>) -> String:
  match opened:
    case None{}: "scissor none"
    case Some{frame}: "scissor" ++ frame_bytes(scissor_frame(frame))
def begin_frame(frame: J.Frame) -> J.Frame & Maybe<J.Surface>:
  J.Frame.framebuffer(J.Frame.end_drawing(J.Rlgl.end(J.Rlgl.vertex2i(J.Rlgl.vertex2i(J.Rlgl.color4ub(J.Rlgl.begin(J.Rlgl.begin(J.Frame.clear_background(J.Frame.begin_drawing(frame), J.Color.WHITE()), 1), 4), 255, 0, 0, 255), 1.0, 1.0), 6.0, 1.0))))
def begin_lines(opened: Maybe<J.Frame>) -> String:
  match opened:
    case None{}: "begin none"
    case Some{frame}: "begin" ++ frame_bytes(begin_frame(frame))
def quad.at(frame: J.Frame, +x0: F32, +y0: F32, +x1: F32, +y1: F32) -> J.Frame:
  J.Rlgl.vertex2f(J.Rlgl.tex_coord2f(J.Rlgl.vertex2f(J.Rlgl.tex_coord2f(J.Rlgl.vertex2f(J.Rlgl.tex_coord2f(J.Rlgl.vertex2f(J.Rlgl.tex_coord2f(frame, 0.0, 0.0), x0, y0), 0.0, 1.0), x0, y1), 1.0, 1.0), x1, y1), 1.0, 0.0), x1, y0)
def quad.open(frame: J.Frame, +x0: F32, +y0: F32, +x1: F32, +y1: F32) -> J.Frame:
  J.Rlgl.end(quad.at(J.Rlgl.color4ub(frame, 255, 255, 255, 255), x0, y0, x1, y1))
def unload.maybe(frame: J.Frame, tex: Maybe<J.Texture>) -> J.Frame:
  match tex:
    case None{}: frame
    case Some{texture}: J.Texture.unload(frame, texture)
def bind.after_paint(pair: J.Frame & Maybe<J.Texture>, prev: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  (drawn, blue_back) = pair
  (unload.maybe(drawn, prev), blue_back)
def bind.paint(pair: J.Frame & Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  (bound, prev) = pair
  bind.after_paint(J.Rlgl.set_texture(quad.open(J.Rlgl.begin(bound, 7), 1.0, 5.0, 4.0, 7.0), None{}), prev)
def bind.second(back: Maybe<J.Texture>, frame: J.Frame) -> J.Frame & Maybe<J.Texture>:
  match back:
    case None{}: (frame, None{})
    case Some{blue}: bind.paint(J.Rlgl.set_texture(frame, Some{blue}))
def bind.finish(pair: J.Frame & Maybe<J.Texture>, red: Maybe<J.Texture>, prev: Maybe<J.Texture>) -> J.Frame & Maybe<J.Surface>:
  (drawn, blue_back) = pair
  J.Frame.framebuffer(unload.maybe(unload.maybe(unload.maybe(J.Frame.end_drawing(drawn), red), blue_back), prev))
def bind.after_quad(pair: J.Frame & Maybe<J.Texture>, back: Maybe<J.Texture>, prev: Maybe<J.Texture>) -> J.Frame & Maybe<J.Surface>:
  (ended, red) = pair
  bind.finish(bind.second(back, ended), red, prev)
def bind.after_begin(pair: J.Frame & Maybe<J.Texture>, prev: Maybe<J.Texture>) -> J.Frame & Maybe<J.Surface>:
  (mid, back) = pair
  bind.after_quad(J.Rlgl.set_texture(quad.open(mid, 1.0, 1.0, 4.0, 4.0), None{}), back, prev)
def bind.loaded(pair: J.Frame & Maybe<J.Texture>, blue: Maybe<J.Texture>) -> J.Frame & Maybe<J.Surface>:
  (held, prev) = pair
  bind.after_begin(J.Rlgl.set_texture(J.Rlgl.begin(held, 7), blue), prev)
def bind.none(blue: Maybe<J.Texture>, frame: J.Frame) -> J.Frame & Maybe<J.Surface>:
  J.Frame.framebuffer(unload.maybe(J.Frame.end_drawing(J.Frame.clear_background(J.Frame.begin_drawing(frame), J.Color.WHITE())), blue))
def bind.with_blue(pair: J.Frame & Maybe<J.Texture>, red: Maybe<J.Texture>) -> J.Frame & Maybe<J.Surface>:
  (frame, blue) = pair
  match red:
    case None{}: bind.none(blue, frame)
    case Some{texture}: bind.loaded(J.Rlgl.set_texture(J.Frame.clear_background(J.Frame.begin_drawing(frame), J.Color.WHITE()), Some{texture}), blue)
def bind.with_red(pair: J.Frame & Maybe<J.Texture>, blue_image: Maybe<J.Surface>) -> J.Frame & Maybe<J.Surface>:
  (frame, red) = pair
  match blue_image:
    case None{}: bind.none(red, frame)
    case Some{image}: bind.with_blue(J.Texture.load_from_image(frame, image), red)
def bind.drop_blue(pair: J.Frame & Maybe<J.Texture>) -> J.Frame & Maybe<J.Surface>:
  (frame, blue) = pair
  bind.none(blue, frame)
def bind.no_red(blue_image: Maybe<J.Surface>, frame: J.Frame) -> J.Frame & Maybe<J.Surface>:
  match blue_image:
    case None{}: bind.none(None{}, frame)
    case Some{image}: bind.drop_blue(J.Texture.load_from_image(frame, image))
def bind.from(red_image: Maybe<J.Surface>, blue_image: Maybe<J.Surface>, frame: J.Frame) -> J.Frame & Maybe<J.Surface>:
  match red_image:
    case None{}: bind.no_red(blue_image, frame)
    case Some{image}: bind.with_red(J.Texture.load_from_image(frame, image), blue_image)
def bind.frame(frame: J.Frame) -> J.Frame & Maybe<J.Surface>:
  bind.from(J.Surface.create(2, 2, J.Color.RED()), J.Surface.create(2, 2, J.Color.BLUE()), frame)
def bind_lines(opened: Maybe<J.Frame>) -> String:
  match opened:
    case None{}: "bind none"
    case Some{frame}: "bind" ++ frame_bytes(bind.frame(frame))
def vr.config() -> J.VrStereoConfig:
  J.VrStereoConfig{M.Matrix.identity(), M.Matrix.identity(), M.Matrix.identity(), M.Matrix.identity(), M.Vector2{0.0, 0.0}, M.Vector2{0.0, 0.0}, M.Vector2{0.0, 0.0}, M.Vector2{0.0, 0.0}, M.Vector2{0.0, 0.0}, M.Vector2{0.0, 0.0}}
def vr.frame(frame: J.Frame) -> J.Frame & Maybe<J.Surface>:
  J.Frame.framebuffer(J.Frame.end_drawing(J.Frame.end_vr_stereo_mode(J.Draw.rectangle(J.Frame.begin_vr_stereo_mode(J.Frame.clear_background(J.Frame.begin_drawing(frame), J.Color.WHITE()), vr.config()), 1.0, 2.0, 3.0, 2.0, J.Color.RED()))))
def vr_lines(opened: Maybe<J.Frame>) -> String:
  match opened:
    case None{}: "vr none"
    case Some{frame}: "vr" ++ frame_bytes(vr.frame(frame))
def cube.fields(info: J.TextureInfo) -> String:
  J.TextureInfo{+id, +width, +height, +mipmaps, +format} = info
  "cube " ++ U32.show(id) ++ " " ++ U32.show(width) ++ " " ++ U32.show(height) ++ " " ++ U32.show(mipmaps) ++ " " ++ U32.show(format)
def cube.use(gone: Unit, closed: Unit, text: String) -> String:
  text
def cube.drop(image: J.Surface, frame: J.Frame, text: String) -> String:
  cube.use(J.Surface.unload(image), J.Frame.close_window(frame), text)
def cube.go(pair: J.Frame & (J.Surface & J.TextureInfo)) -> String:
  (frame, (image, info)) = pair
  cube.drop(image, frame, cube.fields(info))
def cube.some(frame: J.Frame, image: J.Surface, +layout: U32) -> String:
  cube.go(J.Texture.load_cubemap(frame, image, layout))
def cube.closed(closed: Unit) -> String:
  "cube none"
def cube.miss(frame: J.Frame) -> String:
  cube.closed(J.Frame.close_window(frame))
def cube.with(frame: J.Frame, found: Maybe<J.Surface>, +layout: U32) -> String:
  match found:
    case None{}: cube.miss(frame)
    case Some{image}: cube.some(frame, image, layout)
def cube_lines(opened: Maybe<J.Frame>, +width: U32, +height: U32, +color: U32, +layout: U32) -> String:
  match opened:
    case None{}: "cube none"
    case Some{frame}: cube.with(frame, J.Surface.create(width, height, color), layout)
'''


def program():
    return HEADER + '''def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(scissor_lines(J.Frame.init_window(8, 8)))
    IO.print(begin_lines(J.Frame.init_window(8, 8)))
    IO.print(bind_lines(J.Frame.init_window(8, 8)))
    IO.print(vr_lines(J.Frame.init_window(8, 8)))
    IO.print(cube_lines(J.Frame.init_window(8, 8), 6, 36, J.Color.RED(), 0))
    IO.print(cube_lines(J.Frame.init_window(8, 8), 8, 8, J.Color.BLUE(), 0))
'''


def kept(text):
    return [line for line in text.splitlines() if line and not line.startswith('INFO:')]


def main():
    probe = probekit.Probe('state-gap', probekit.arguments(__doc__))
    expected = kept(probe.native(NATIVE))
    lanes = probe.candidates(lambda selected, gpu: program(), ['state'], batch=1,
                             parse=lambda text, selected: ['\n'.join(kept(text))])
    probe.compare(['\n'.join(expected)], lanes, describe=lambda index: 'state')
    probe.finish(lines=len(expected))


if __name__ == '__main__':
    main()
