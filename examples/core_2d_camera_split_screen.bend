# raylib [core] example - 2d camera split screen, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_2d_camera_split_screen.c (zlib/libpng,
# Copyright (c) 2023-2025 Gabriel dos Santos Sanches (@gabrielssanches)); see
# LICENSES/raylib.txt.
#
# Two players, each followed by its own 2D camera into a render texture;
# the textures fill the two halves of an 800x440 window. raylib draws the
# textures before BeginDrawing; here the draw does that first (the same
# pixels). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{p1: J.Rectangle, p2: J.Rectangle, rt1: Maybe<J.RenderTexture>, rt2: Maybe<J.RenderTexture>}

def key(+core: J.Core, +code: U32) -> Bool:
  J.Input.is_key_down(core, code)

# The first key of each pair wins (raylib's if / else if); 3 pixels a frame.
def step(+core: J.Core, +value: F32, +plus: U32, +minus: U32) -> F32:
  Bool.pick(F32, key(core, plus), (value + 3.0 : F32), Bool.pick(F32, key(core, minus), (value - 3.0 : F32), value))

def step.first(+core: J.Core, +value: F32, +minus: U32, +plus: U32) -> F32:
  Bool.pick(F32, key(core, minus), (value - 3.0 : F32), Bool.pick(F32, key(core, plus), (value + 3.0 : F32), value))

def update(+core: J.Core, state: State) -> J.Core & State:
  State{+p1, +p2, rt1, rt2} = state
  J.Rectangle{+x1, +y1, +w1, +h1} = p1
  J.Rectangle{+x2, +y2, +w2, +h2} = p2
  +ny1 = step(core, y1, J.KeyboardKey.KEY_S(), J.KeyboardKey.KEY_W())
  +nx1 = step(core, x1, J.KeyboardKey.KEY_D(), J.KeyboardKey.KEY_A())
  +ny2 = step.first(core, y2, J.KeyboardKey.KEY_UP(), J.KeyboardKey.KEY_DOWN())
  +nx2 = step(core, x2, J.KeyboardKey.KEY_RIGHT(), J.KeyboardKey.KEY_LEFT())
  (core, State{J.Rectangle{nx1, ny1, w1, h1}, J.Rectangle{nx2, ny2, w2, h2}, rt1, rt2})

def grid.vertical(n: Nat, +i: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p:
      +x = (40.0 * U32.to_f32(i) : F32)
      grid.vertical(p, (i + 1 : U32), J.Draw.line_v(frame, M.Vector2{x, 0.0}, M.Vector2{x, 440.0}, J.Color.LIGHTGRAY()))

def grid.horizontal(n: Nat, +i: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p:
      +y = (40.0 * U32.to_f32(i) : F32)
      grid.horizontal(p, (i + 1 : U32), J.Draw.line_v(frame, M.Vector2{0.0, y}, M.Vector2{800.0, y}, J.Color.LIGHTGRAY()))

def label.drawn(text: Maybe<String>, +x: F32, +y: F32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, x, y, 10.0, J.Color.LIGHTGRAY())

# DrawText(TextFormat("[%i,%i]", i, j), 10 + 40*i, 15 + 40*j, 10, LIGHTGRAY) for i < 20, j < 11 (i outer).
def labels(n: Nat, +k: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p:
      +i = (k / 11 : U32)
      +j = (k % 11 : U32)
      labels(p, (k + 1 : U32), label.drawn(J.Text.format("[%i,%i]", [J.TextInt{i}, J.TextInt{j}]), U32.to_f32((10 + 40 * i : U32)), U32.to_f32((15 + 40 * j : U32)), frame))

def camera(+target: J.Rectangle) -> J.Camera2D:
  J.Rectangle{+x, +y, _, _} = target
  J.Camera2D{M.Vector2{200.0, 200.0}, M.Vector2{x, y}, 0.0, 1.0}

# One half: the world through the camera following `follow`, then the banner.
def half(+libm: M.Libm, +follow: J.Rectangle, +p1: J.Rectangle, +p2: J.Rectangle, text: String, +color: U32, frame: J.Frame) -> J.Frame:
  f1 = J.Frame.begin_mode_2d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera(follow))
  f2 = labels(220n, 0, grid.horizontal(12n, 0, grid.vertical(21n, 0, f1)))
  f3 = J.Frame.end_mode_2d(J.Draw.rectangle_rec(J.Draw.rectangle_rec(f2, p1, J.Color.RED()), p2, J.Color.BLUE()))
  J.Draw.text(J.Draw.rectangle(f3, 0.0, 0.0, 400.0, 30.0, J.Color.with_alpha(J.Color.RAYWHITE(), 0.6)), text, 10.0, 10.0, 10.0, color)

def painted(frame: J.Frame, target: Maybe<J.RenderTexture>, paint: J.Frame -> J.Frame) -> J.Frame & Maybe<J.RenderTexture>:
  match target:
    case None{}: (frame, None{})
    case Some{t}: J.Frame.end_texture_mode(paint(J.Frame.begin_texture_mode(frame, t)))

def shown(+id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, texture) = r
  (frame, Some{J.RenderTexture{id, texture, depth}})

# DrawTextureRec(target.texture, (0, 0, 400, -440), (x, 0), WHITE).
def show.at(+x: F32, frame: J.Frame, target: J.RenderTexture) -> J.Frame & Maybe<J.RenderTexture>:
  J.RenderTexture{+id, texture, +depth} = target
  J.Texture{+tid, +w, +h, +format, +linear, +alpha, texels} = texture
  shown(id, depth, J.Draw.texture_rec(frame, J.Texture{tid, w, h, format, linear, alpha, texels},
    J.Rectangle{0.0, 0.0, U32.to_f32(w), F32.neg(U32.to_f32(h))}, M.Vector2{x, 0.0}, J.Color.WHITE()))

def show(+x: F32, frame: J.Frame, target: Maybe<J.RenderTexture>) -> J.Frame & Maybe<J.RenderTexture>:
  match target:
    case None{}: (frame, None{})
    case Some{t}: show.at(x, frame, t)

def draw.done(+core: J.Core, +p1: J.Rectangle, +p2: J.Rectangle, rt1: Maybe<J.RenderTexture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, rt2) = r
  (core, (State{p1, p2, rt1, rt2}, J.Draw.rectangle(frame, (400.0 - 2.0 : F32), 0.0, 4.0, 440.0, J.Color.LIGHTGRAY())))

def draw.second(+core: J.Core, +p1: J.Rectangle, +p2: J.Rectangle, rt2: Maybe<J.RenderTexture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, rt1) = r
  draw.done(core, p1, p2, rt1, show((800.0 / 2.0 : F32), frame, rt2))

def draw.shown(+core: J.Core, +p1: J.Rectangle, +p2: J.Rectangle, rt1: Maybe<J.RenderTexture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, rt2) = r
  draw.second(core, p1, p2, rt2, show(0.0, J.Frame.clear_background(frame, J.Color.BLACK()), rt1))

def draw.painted(+libm: M.Libm, +core: J.Core, +p1: J.Rectangle, +p2: J.Rectangle, rt2: Maybe<J.RenderTexture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, rt1) = r
  draw.shown(core, p1, p2, rt1, painted(frame, rt2, f => half(libm, p2, p1, p2, "PLAYER2: UP/DOWN/LEFT/RIGHT to move", J.Color.DARKBLUE(), f)))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+p1, +p2, rt1, rt2} = state
  draw.painted(libm, core, p1, p2, rt2, painted(frame, rt1, f => half(libm, p1, p1, p2, "PLAYER1: W/S/A/D to move", J.Color.MAROON(), f)))

# The main loop's body; libm is the profile of BeginMode2D's rotation (0 here).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.second(+core: J.Core, rt1: Maybe<J.RenderTexture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, rt2) = r
  (J.Core.set_target_fps(core, 60), (frame, State{J.Rectangle{200.0, 200.0, 40.0, 40.0}, J.Rectangle{250.0, 200.0, 40.0, 40.0}, rt1, rt2}))

def setup.first(+core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, rt1) = r
  setup.second(core, rt1, J.RenderTexture.load(frame, 400, 440))

# After InitWindow(800, 440): the players, two 400x440 render textures, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.first(core, J.RenderTexture.load(frame, 400, 440))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - 2d camera split screen", 800, 440, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
