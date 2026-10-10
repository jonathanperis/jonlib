# raylib [core] example - 3d camera split screen, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_3d_camera_split_screen.c (zlib/libpng,
# Copyright (c) 2021-2025 Jeffery Myers (@JeffM2501)); see LICENSES/raylib.txt.
#
# Two perspective cameras render a field of cubes into two 400x450 render
# textures shown side by side; W/S and UP/DOWN move them by 10*GetFrameTime().
# raylib draws the textures before BeginDrawing; here the draw does that
# first (the same pixels). The perspective needs the libm profile's binary64
# tan (docs/PERSPECTIVE.md). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{c1: J.Camera3D, c2: J.Camera3D, rt1: Maybe<J.RenderTexture>, rt2: Maybe<J.RenderTexture>}

def shift.z(+c: J.Camera3D, +d: F32) -> J.Camera3D:
  J.Camera3D{M.Vector3{+px, +py, +pz}, M.Vector3{+tx, +ty, +tz}, +u, +f, +k} = c
  J.Camera3D{M.Vector3{px, py, (pz + d : F32)}, M.Vector3{tx, ty, (tz + d : F32)}, u, f, k}

def shift.x(+c: J.Camera3D, +d: F32) -> J.Camera3D:
  J.Camera3D{M.Vector3{+px, +py, +pz}, M.Vector3{+tx, +ty, +tz}, +u, +f, +k} = c
  J.Camera3D{M.Vector3{(px + d : F32), py, pz}, M.Vector3{(tx + d : F32), ty, tz}, u, f, k}

def key(+core: J.Core, +code: U32) -> Bool:
  J.Input.is_key_down(core, code)

def update(+core: J.Core, state: State) -> J.Core & State:
  State{+c1, +c2, rt1, rt2} = state
  +o = (10.0 * J.Core.get_frame_time(core) : F32)
  +n1 = Bool.pick(J.Camera3D, key(core, J.KeyboardKey.KEY_W()), shift.z(c1, o), Bool.pick(J.Camera3D, key(core, J.KeyboardKey.KEY_S()), shift.z(c1, F32.neg(o)), c1))
  +n2 = Bool.pick(J.Camera3D, key(core, J.KeyboardKey.KEY_UP()), shift.x(c2, o), Bool.pick(J.Camera3D, key(core, J.KeyboardKey.KEY_DOWN()), shift.x(c2, F32.neg(o)), c2))
  (core, State{n1, n2, rt1, rt2})

# for (x = -count*spacing; x <= count*spacing; x += spacing), the same for z: 11 x 11 posts.
def posts(n: Nat, +k: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p:
      +x = (F32.neg(20.0) + 4.0 * U32.to_f32((k / 11 : U32)) : F32)
      +z = (F32.neg(20.0) + 4.0 * U32.to_f32((k % 11 : U32)) : F32)
      f1 = J.Draw.cube(frame, M.Vector3{x, 1.5, z}, 1.0, 1.0, 1.0, J.Color.LIME())
      posts(p, (k + 1 : U32), J.Draw.cube(f1, M.Vector3{x, 0.5, z}, 0.25, 1.0, 0.25, J.Color.BROWN()))

def position(+c: J.Camera3D) -> M.Vector3:
  J.Camera3D{+p, _, _, _, _} = c
  p

def view(+libm: M.Libm, +eye: J.Camera3D, +c1: J.Camera3D, +c2: J.Camera3D, text: String, +color: U32, frame: J.Frame) -> J.Frame:
  f1 = J.Frame.begin_mode_3d_for(libm, J.Frame.clear_background(frame, J.Color.SKYBLUE()), eye)
  f2 = posts(121n, 0, J.Draw.plane(f1, M.Vector3.zero(), M.Vector2{50.0, 50.0}, J.Color.BEIGE()))
  f3 = J.Frame.end_mode_3d(J.Draw.cube(J.Draw.cube(f2, position(c1), 1.0, 1.0, 1.0, J.Color.RED()), position(c2), 1.0, 1.0, 1.0, J.Color.BLUE()))
  J.Draw.text(J.Draw.rectangle(f3, 0.0, 0.0, 400.0, 40.0, J.Color.with_alpha(J.Color.RAYWHITE(), 0.8)), text, 10.0, 10.0, 20.0, color)

def painted(frame: J.Frame, target: Maybe<J.RenderTexture>, paint: J.Frame -> J.Frame) -> J.Frame & Maybe<J.RenderTexture>:
  match target:
    case None{}: (frame, None{})
    case Some{t}: J.Frame.end_texture_mode(paint(J.Frame.begin_texture_mode(frame, t)))

def shown(+id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, texture) = r
  (frame, Some{J.RenderTexture{id, texture, depth}})

def show.at(+x: F32, frame: J.Frame, target: J.RenderTexture) -> J.Frame & Maybe<J.RenderTexture>:
  J.RenderTexture{+id, texture, +depth} = target
  J.Texture{+tid, +w, +h, +format, +linear, +alpha, texels} = texture
  shown(id, depth, J.Draw.texture_rec(frame, J.Texture{tid, w, h, format, linear, alpha, texels},
    J.Rectangle{0.0, 0.0, U32.to_f32(w), F32.neg(U32.to_f32(h))}, M.Vector2{x, 0.0}, J.Color.WHITE()))

def show(+x: F32, frame: J.Frame, target: Maybe<J.RenderTexture>) -> J.Frame & Maybe<J.RenderTexture>:
  match target:
    case None{}: (frame, None{})
    case Some{t}: show.at(x, frame, t)

def draw.done(+core: J.Core, +c1: J.Camera3D, +c2: J.Camera3D, rt1: Maybe<J.RenderTexture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, rt2) = r
  (core, (State{c1, c2, rt1, rt2}, J.Draw.rectangle(frame, (400.0 - 2.0 : F32), 0.0, 4.0, 450.0, J.Color.LIGHTGRAY())))

def draw.second(+core: J.Core, +c1: J.Camera3D, +c2: J.Camera3D, rt2: Maybe<J.RenderTexture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, rt1) = r
  draw.done(core, c1, c2, rt1, show((800.0 / 2.0 : F32), frame, rt2))

def draw.shown(+core: J.Core, +c1: J.Camera3D, +c2: J.Camera3D, rt1: Maybe<J.RenderTexture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, rt2) = r
  draw.second(core, c1, c2, rt2, show(0.0, J.Frame.clear_background(frame, J.Color.BLACK()), rt1))

def draw.painted(+libm: M.Libm, +core: J.Core, +c1: J.Camera3D, +c2: J.Camera3D, rt2: Maybe<J.RenderTexture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, rt1) = r
  draw.shown(core, c1, c2, rt1, painted(frame, rt2, f => view(libm, c2, c1, c2, "PLAYER2: UP/DOWN to move", J.Color.DARKBLUE(), f)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+c1, +c2, rt1, rt2} = state
  draw.painted(libm, core, c1, c2, rt2, painted(frame, rt1, f => view(libm, c1, c1, c2, "PLAYER1: W/S to move", J.Color.MAROON(), f)))

# The main loop's body; libm is the profile of BeginMode3D's tan.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.second(+core: J.Core, rt1: Maybe<J.RenderTexture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, rt2) = r
  +c1 = {J.Camera3D{M.Vector3{0.0, 1.0, F32.neg(3.0)}, M.Vector3{0.0, 1.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, 0} : J.Camera3D}
  +c2 = {J.Camera3D{M.Vector3{F32.neg(3.0), 3.0, 0.0}, M.Vector3{0.0, 3.0, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, 0} : J.Camera3D}
  (J.Core.set_target_fps(core, 60), (frame, State{c1, c2, rt1, rt2}))

def setup.first(+core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, rt1) = r
  setup.second(core, rt1, J.RenderTexture.load(frame, 400, 450))

# After InitWindow(800, 450): the two zero-initialized cameras (projection 0,
# CAMERA_PERSPECTIVE) and two 400x450 render textures, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.first(core, J.RenderTexture.load(frame, 400, 450))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [core] example - 3d camera split screen", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
