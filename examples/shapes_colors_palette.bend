# raylib [shapes] example - colors palette, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_colors_palette.c (zlib/libpng,
# Copyright (c) 2014-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Hovering a color fades it and shows its name; SPACE shows every name. See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{mouse: M.Vector2}

# colorsRecs[i]: x = 20 + 100*(i%7) + 10*(i%7), y = 80 + 100*(i/7) + 10*((float)i/7),
# 100x100, in the example's F32 order.
def rec(+i: U32) -> J.Rectangle:
  +col = U32.to_f32((i % 7 : U32))
  +row = U32.to_f32((i / 7 : U32))
  J.Rectangle{(20.0 + 100.0 * col + 10.0 * col : F32), (80.0 + 100.0 * row + 10.0 * (U32.to_f32(i) / 7.0) : F32), 100.0, 100.0}

# colors[i] and colorNames[i], i = 0..20.
def color(i: U32) -> U32:
  match i:
    case 0: J.Color.DARKGRAY()
    case 1: J.Color.MAROON()
    case 2: J.Color.ORANGE()
    case 3: J.Color.DARKGREEN()
    case 4: J.Color.DARKBLUE()
    case 5: J.Color.DARKPURPLE()
    case 6: J.Color.DARKBROWN()
    case 7: J.Color.GRAY()
    case 8: J.Color.RED()
    case 9: J.Color.GOLD()
    case 10: J.Color.LIME()
    case 11: J.Color.BLUE()
    case 12: J.Color.VIOLET()
    case 13: J.Color.BROWN()
    case 14: J.Color.LIGHTGRAY()
    case 15: J.Color.PINK()
    case 16: J.Color.YELLOW()
    case 17: J.Color.GREEN()
    case 18: J.Color.SKYBLUE()
    case 19: J.Color.PURPLE()
    case _: J.Color.BEIGE()

def name(i: U32) -> String:
  match i:
    case 0: "DARKGRAY"
    case 1: "MAROON"
    case 2: "ORANGE"
    case 3: "DARKGREEN"
    case 4: "DARKBLUE"
    case 5: "DARKPURPLE"
    case 6: "DARKBROWN"
    case 7: "GRAY"
    case 8: "RED"
    case 9: "GOLD"
    case 10: "LIME"
    case 11: "BLUE"
    case 12: "VIOLET"
    case 13: "BROWN"
    case 14: "LIGHTGRAY"
    case 15: "PINK"
    case 16: "YELLOW"
    case 17: "GREEN"
    case 18: "SKYBLUE"
    case 19: "PURPLE"
    case _: "BEIGE"

# The name's x: (int)(x + width - MeasureText(name, 10) - 12); a refused
# MeasureText refuses the frame.
def label.text(+m: U32, +rec: J.Rectangle, +i: U32, frame: J.Frame) -> J.Frame:
  J.Rectangle{+x, +y, +w, +h} = rec
  J.Draw.text(frame, name(i), (x + w - U32.to_f32(m) - 12.0 : F32), (y + h - 20.0 : F32), 10.0, color(i))

def label.at(width: Maybe<U32>, +rec: J.Rectangle, +i: U32, frame: J.Frame) -> J.Frame:
  match width:
    case None{}: J.Frame.refuse(frame)
    case Some{+m}: label.text(m, rec, i, frame)

# The black band, the faded outline and the name.
def label(+rec: J.Rectangle, +i: U32, frame: J.Frame) -> J.Frame:
  J.Rectangle{+x, +y, +w, +h} = rec
  f1 = J.Draw.rectangle(frame, x, (y + h - 26.0 : F32), w, 20.0, J.Color.BLACK())
  f2 = J.Draw.rectangle_lines_ex(f1, rec, 6.0, J.Color.with_alpha(J.Color.BLACK(), 0.3))
  label.at(J.Font.measure_text(name(i), 10.0), rec, i, f2)

def entry.shown(shown: Bool, +rec: J.Rectangle, +i: U32, frame: J.Frame) -> J.Frame:
  match shown:
    case True{}: label(rec, i, frame)
    case False{}: frame

# DrawRectangleRec(colorsRecs[i], Fade(colors[i], colorState[i]? 0.6f : 1.0f)), then the label
# while SPACE is down or the mouse is over the rectangle.
def entry(+space: Bool, +mouse: M.Vector2, +i: U32, frame: J.Frame) -> J.Frame:
  +r = rec(i)
  +hover = J.Collision.point_rec(mouse, r)
  f1 = J.Draw.rectangle_rec(frame, r, J.Color.with_alpha(color(i), Bool.pick(F32, hover, 0.6, 1.0)))
  entry.shown(space || hover, r, i, f1)

# i counts up while n counts the remaining entries down.
def entries(n: Nat, +space: Bool, +mouse: M.Vector2, +i: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+rest: entries(rest, space, mouse, (i + 1 : U32), entry(space, mouse, i, frame))

# colorState follows the mouse position read in the update.
def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, State{J.Input.get_mouse_position(core)})

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+mouse} = state
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = J.Draw.text(f1, "raylib colors palette", 28.0, 42.0, 20.0, J.Color.BLACK())
  +sw = U32.to_f32(J.Core.get_screen_width(core))
  +sh = U32.to_f32(J.Core.get_screen_height(core))
  f3 = J.Draw.text(f2, "press SPACE to see all colors", (sw - 180.0 : F32), (sh - 40.0 : F32), 10.0, J.Color.GRAY())
  (core, (state, entries(21n, J.Input.is_key_down(core, J.KeyboardKey.KEY_SPACE()), mouse, 0, f3)))

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): the mouse at (0, 0), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{M.Vector2{0.0, 0.0}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shapes] example - colors palette", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
