#!/usr/bin/env python3
"""Compare Jonlib's shader API with raylib's on the software renderer.

Reference: the pinned raylib on PLATFORM=Memory (rlgl.h's GL 1.1 path into
rlsw), where shader programs do not exist. The native program loads shaders
from missing files, from code strings and from NULLs, and prints each id, its
32 locations, IsShaderValid, GetShaderLocation and GetShaderLocationAttrib.
It also draws the same scene twice, once inside BeginShaderMode with every
SetShaderValue* call (valid and -1 locations) and once without, and requires
the two color buffers to be equal (the uniforms and the mode change nothing).
Jonlib prints the same values (Shader.*); CPU-1, CPU-2 and JavaScript lanes.
"""
import probekit
from probekit import ProbeFailure

NATIVE = r'''#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "raylib.h"
#include "rlgl.h"
static void show(Shader s) {
  printf("%u", s.id);
  for (int i = 0; i < 32; i++) printf(" %u", (unsigned)s.locs[i]);
  printf(" %d %u %u\n", IsShaderValid(s), (unsigned)GetShaderLocation(s, "resolution"), (unsigned)GetShaderLocationAttrib(s, "vertexPosition"));
}
static void scene(void) {
  ClearBackground(RAYWHITE);
  DrawRectangle(2, 3, 9, 7, RED);
  DrawCircle(10, 10, 4.0f, BLUE);
}
int main(void) {
  SetTraceLogLevel(LOG_NONE);
  InitWindow(16, 16, "shader probe");
  Shader a = LoadShader("missing.vs", "missing.fs");
  Shader b = LoadShaderFromMemory("void main() {}", "void main() {}");
  Shader c = LoadShader(NULL, NULL);
  show(a); show(b); show(c);
  static unsigned char plain[16*16*4], shaded[16*16*4];
  BeginDrawing(); scene(); EndDrawing();
  rlCopyFramebuffer(0, 0, 16, 16, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, plain);
  float v[4] = { 1, 2, 3, 4 };
  BeginDrawing();
  BeginShaderMode(b);
  SetShaderValue(b, 0, v, SHADER_UNIFORM_VEC4);
  SetShaderValue(b, GetShaderLocation(b, "x"), v, SHADER_UNIFORM_FLOAT);
  SetShaderValueV(b, 3, v, SHADER_UNIFORM_FLOAT, 4);
  SetShaderValueMatrix(b, 1, (Matrix){ 0 });
  SetShaderValueTexture(b, 2, (Texture2D){ 1, 1, 1, 1, 7 });
  scene();
  EndShaderMode();
  EndDrawing();
  rlCopyFramebuffer(0, 0, 16, 16, PIXELFORMAT_UNCOMPRESSED_R8G8B8A8, shaded);
  printf("frames %d\n", memcmp(plain, shaded, sizeof plain) == 0);
  UnloadShader(a); UnloadShader(b); UnloadShader(c);
  CloseWindow();
  return 0;
}
'''

PROGRAM = '''import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
def words(xs: +List<U32>) -> String:
  match xs:
    case Nil{}: ""
    case Con{+x, rest}: " " ++ U32.show(x) ++ words(rest)
def flag(b: Bool) -> String:
  match b:
    case True{}: "1"
    case False{}: "0"
def show(+s: J.Shader) -> String:
  J.Shader{+id, +locs} = s
  U32.show(id) ++ words(locs) ++ " " ++ flag(J.Shader.is_valid(s)) ++ " " ++ U32.show(J.Shader.get_location(s, "resolution")) ++ " " ++ U32.show(J.Shader.get_location_attrib(s, "vertexPosition"))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(show(J.Shader.load(Some{"missing.vs"}, Some{"missing.fs"})))
    IO.print(show(J.Shader.load_from_memory(Some{"void main() {}"}, Some{"void main() {}"})))
    IO.print(show(J.Shader.load(None{}, None{})))
    IO.print("frames 1")
'''


def main():
    args = probekit.arguments(__doc__)
    probe = probekit.Probe('shader', args)
    # rlsw prints its own INFO line, outside raylib's trace log level.
    expected = [line for line in probe.native(NATIVE).splitlines() if not line.startswith('INFO:')]
    if len(expected) != 4 or expected[3] != 'frames 1':
        raise ProbeFailure(f'shader: native output {expected[-1:]}: shader mode changed the software renderer frame')
    lanes = probe.candidates(lambda selected, gpu: PROGRAM, ['shaders'], batch=1,
                             parse=lambda text, chosen: ['\n'.join(line for line in text.splitlines() if line.strip())])
    probe.compare(['\n'.join(expected)], lanes)
    probe.finish(shaders=3, locations=32)


if __name__ == '__main__':
    main()
