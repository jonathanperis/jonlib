# raylib [textures] example - polygon drawing, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_polygon_drawing.c
# (zlib/libpng, Copyright (c) 2021-2025 Chris Camacho (@chriscamacho) and
# Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A ten-sided textured polygon turning a degree a frame, drawn as a triangle
# fan through rlgl (rlSetTexture, rlBegin(RL_TRIANGLES), rlTexCoord2f,
# rlVertex2f). Vector2Rotate's sinf/cosf of angle*DEG2RAD follow the libm
# profile; an angle outside it refuses the frame (docs/SINCOSF.md).
# LoadTexture of a .png is the PNG loader (Surface.load_png). See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{texture: Maybe<J.Texture>, angle: F32}

# texcoords[1..10]; texcoords[0] is (0.75, 0), which also closes the polygon.
def coords() -> +List<M.Vector2>:
  [M.Vector2{0.25, 0.0}, M.Vector2{0.0, 0.5}, M.Vector2{0.0, 0.75}, M.Vector2{0.25, 1.0}, M.Vector2{0.375, 0.875},
   M.Vector2{0.625, 0.875}, M.Vector2{0.75, 1.0}, M.Vector2{1.0, 0.75}, M.Vector2{1.0, 0.5}, M.Vector2{0.75, 0.0}]

# angle++.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{texture, +angle} = state
  (core, State{texture, (angle + 1.0 : F32)})

# rlTexCoord2f(texcoord); rlVertex2f(Vector2Rotate(point, angle) + center), point = (texcoord - 0.5)*256.
def corner(+c: F32, +s: F32, +coord: M.Vector2, frame: J.Frame) -> J.Frame:
  M.Vector2{+u, +v} = coord
  +x = ((u - 0.5) * 256.0 : F32)
  +y = ((v - 0.5) * 256.0 : F32)
  J.Rlgl.vertex2f(J.Rlgl.tex_coord2f(frame, u, v), ((x * c - y * s) + 800.0 / 2.0 : F32), ((x * s + y * c) + 450.0 / 2.0 : F32))

# One triangle a side: the center (texcoord (0.5, 0.5)), a point and the next.
def fan(rest: +List<M.Vector2>, +previous: M.Vector2, +c: F32, +s: F32, frame: J.Frame) -> J.Frame:
  match rest:
    case Nil{}: frame
    case Con{+next, more}: fan(more, next, c, s,
      corner(c, s, next, corner(c, s, previous, J.Rlgl.vertex2f(J.Rlgl.tex_coord2f(frame, 0.5, 0.5), (800.0 / 2.0 : F32), (450.0 / 2.0 : F32)))))

# rlBegin(RL_TRIANGLES); rlColor4ub(WHITE); the fan; rlEnd().
def poly(frame: J.Frame, cosine: Maybe<F32>, sine: Maybe<F32>) -> J.Frame:
  match cosine sine:
    case Some{+c} Some{+s}: J.Rlgl.end(fan(coords(), M.Vector2{0.75, 0.0}, c, s, J.Rlgl.color4ub(J.Rlgl.begin(frame, 4), 255, 255, 255, 255)))
    case _ _: J.Frame.refuse(frame)

def bound(r: J.Frame & Maybe<J.Texture>) -> J.Frame:
  (frame, _) = r
  frame

def draw.done(+core: J.Core, +angle: F32, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  (core, (State{texture, angle}, frame))

# DrawTexturePoly: rlSetTexture(texture.id), the triangles, rlSetTexture(0).
def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{texture, +angle} = state
  match texture:
    case None{}: (core, (State{None{}, angle}, J.Frame.refuse(frame)))
    case Some{t}: draw.done(core, angle, J.Rlgl.set_texture(poly(bound(J.Rlgl.set_texture(
      J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "textured polygon", 20.0, 20.0, 20.0, J.Color.DARKGRAY()), Some{t})),
      M.Libm.cos(libm, (angle * M.Math.DEG2RAD() : F32)), M.Libm.sin(libm, (angle * M.Math.DEG2RAD() : F32))), None{}))

# The main loop's body; libm is the profile of Vector2Rotate's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.uploaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  (J.Core.set_target_fps(core, 60), (frame, State{texture, 0.0}))

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: (J.Core.set_target_fps(core, 60), (frame, State{None{}, 0.0}))
    case Done{image}: setup.uploaded(core, J.Texture.load_from_image(frame, image))

# After InitWindow(800, 450): LoadTexture("resources/cat.png"), SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/cat.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [textures] example - polygon drawing", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
