# raylib [shapes] example - dashed line, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_dashed_line.c (zlib/libpng,
# Copyright (c) 2025 Luís Almeida (@luis605)); see LICENSES/raylib.txt.
#
# A dashed line to the mouse; arrows change the dash and space lengths, C
# cycles the color. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{end: M.Vector2, dash: F32, blank: F32, color: U32}

# lineColors[colorIndex]
def color(index: U32) -> U32:
  match index:
    case 0: J.Color.RED()
    case 1: J.Color.ORANGE()
    case 2: J.Color.GOLD()
    case 3: J.Color.GREEN()
    case 4: J.Color.BLUE()
    case 5: J.Color.VIOLET()
    case 6: J.Color.PINK()
    case _: J.Color.BLACK()

def key(+core: J.Core, +code: U32) -> Bool:
  J.Input.is_key_down(core, code)

# UP/DOWN change the dash length and RIGHT/LEFT the blank length by 1, never
# below 1 (the decrement needs a length above 1); C cycles the 8 colors.
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{_, +dash, +blank, +index} = state
  +d1 = Bool.pick(F32, key(core, J.KeyboardKey.KEY_UP()), (dash + 1.0 : F32), dash)
  +d2 = Bool.pick(F32, key(core, J.KeyboardKey.KEY_DOWN()) && (d1 > 1.0 : F32), (d1 - 1.0 : F32), d1)
  +b1 = Bool.pick(F32, key(core, J.KeyboardKey.KEY_RIGHT()), (blank + 1.0 : F32), blank)
  +b2 = Bool.pick(F32, key(core, J.KeyboardKey.KEY_LEFT()) && (b1 > 1.0 : F32), (b1 - 1.0 : F32), b1)
  +i = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_C()), ((index + 1) % 8 : U32), index)
  (core, State{J.Input.get_mouse_position(core), d2, b2, i})

def draw.status(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 15.0, 115.0, 10.0, J.Color.DARKGRAY())

def draw.fps.at(+state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 720.0, 10.0, fps)))

def draw.fps.done(+state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# DrawLineDashed with (int)dashLength and (int)blankLength (Draw.line_dashed
# converts its F32 sizes as C does).
def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+end, +dash, +blank, +index} = state
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = J.Draw.line_dashed(f1, M.Vector2{20.0, 50.0}, end, dash, blank, color(index))
  f3 = J.Draw.rectangle(f2, 5.0, 5.0, 265.0, 95.0, J.Color.with_alpha(J.Color.SKYBLUE(), 0.5))
  f4 = J.Draw.rectangle_lines(f3, 5.0, 5.0, 265.0, 95.0, J.Color.BLUE())
  f5 = J.Draw.text(f4, "CONTROLS:", 15.0, 15.0, 10.0, J.Color.BLACK())
  f6 = J.Draw.text(f5, "UP/DOWN: Change Dash Length", 15.0, 35.0, 10.0, J.Color.BLACK())
  f7 = J.Draw.text(f6, "LEFT/RIGHT: Change Space Length", 15.0, 55.0, 10.0, J.Color.BLACK())
  f8 = J.Draw.text(f7, "C: Cycle Color", 15.0, 75.0, 10.0, J.Color.BLACK())
  f9 = draw.status(J.Text.format("Dash: %.0f | Space: %.0f", [J.TextFloat{dash}, J.TextFloat{blank}]), f8)
  draw.fps.done(state, f9, J.Core.get_fps(core, J.Core.get_time(core)), core)

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): the end at (780, 400), dash 25, blank 15, red; SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{M.Vector2{780.0, 400.0}, 25.0, 15.0, 0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shapes] example - dashed line", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
