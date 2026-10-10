# raylib [text] example - rectangle bounds, ported to Jonlib.
# Adapted from raylib 6.0 examples/text/text_rectangle_bounds.c (zlib/libpng,
# Copyright (c) 2018-2025 Vlad Adrian (@demizdor) and Ramon Santamaria (@raysan5));
# see LICENSES/raylib.txt.
#
# The example's DrawTextBoxed: the default font's text kept inside a
# container resized by dragging its corner, wrapped by words (a measuring
# pass up to the last space that fits, then a drawing pass over that line)
# or by characters; SPACE toggles the word wrap. The text is ASCII, so each
# byte is a codepoint, and nothing is selected (selectLength 0), so the
# selection counters are left out. The default font's glyphs have no
# advanceX: a glyph's width is its atlas rectangle's. The loop is bounded
# (16 steps per character); a text that needed more would be refused.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# A character: its codepoint and font.recs[index].width*scaleFactor.
type Glyph is Data:
  Glyph{code: U32, width: F32}

# The container's size, resizing, wordWrap, lastMouse and borderColor.
type Box is Data:
  Box{width: F32, height: F32, resizing: Bool, wrap: Bool, last: M.Vector2, border: U32}

type State is Type:
  State{box: Box, count: U32, glyphs: +List<Glyph>, font: J.Font}

# DrawTextBoxed's loop variables: i, state == MEASURE_STATE, startLine + 1, endLine (4294967295 is -1),
# textOffsetX, textOffsetY; done after the last character or the break.
type Cursor is Data:
  Cursor{i: U32, measuring: Bool, first: U32, end: U32, x: F32, y: F32, done: Bool}

# rest: the characters from i; line: those from startLine + 1.
type Loop is Type:
  Loop{cursor: Cursor, rest: +List<Glyph>, line: +List<Glyph>, frame: J.Frame, font: J.Font}

def text() -> String:
  "Text cannot escape\tthis container\t...word wrap also works when active so here's a long text for testing.\n\nLorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Nec ullamcorper sit amet risus nullam eget felis eget."

def container(+width: F32, +height: F32) -> J.Rectangle:
  J.Rectangle{25.0, 25.0, width, height}

# resizer = { container.x + container.width - 17, container.y + container.height - 17, 14, 14 }.
def resizer(+width: F32, +height: F32) -> J.Rectangle:
  J.Rectangle{(25.0 + width - 17.0 : F32), (25.0 + height - 17.0 : F32), 14.0, 14.0}

def pred(+value: U32) -> U32:
  Bool.pick(U32, U32.is_eq(value, 0), 4294967295, (value - 1 : U32))

def step.kept(+cursor: Cursor, +rest: +List<Glyph>, +line: +List<Glyph>, r: J.Frame & J.Font) -> Loop:
  (frame, font) = r
  Loop{cursor, rest, line, frame, font}

# DrawTextCodepoint(font, codepoint, (rec.x + textOffsetX, rec.y + textOffsetY), fontSize, tint).
def step.drawn(draw: Bool, +cursor: Cursor, +rest: +List<Glyph>, +line: +List<Glyph>, +code: U32, +px: F32, +py: F32, frame: J.Frame, font: J.Font) -> Loop:
  match draw:
    case False{}: Loop{cursor, rest, line, frame, font}
    case True{}: step.kept(cursor, rest, line, J.Draw.text_codepoint(frame, font, code, M.Vector2{px, py}, 20.0, J.Color.GRAY()))

# One pass of the for loop on the character at i.
def step.glyph(+count: U32, +wrap: Bool, +rw: F32, +rh: F32, +i: U32, +measuring: Bool, +first: U32, +end: U32, +x: F32, +y: F32, +glyph: Glyph, +tail: +List<Glyph>,
    +line: +List<Glyph>, frame: J.Frame, font: J.Font) -> Loop:
  Glyph{+code, +width} = glyph
  +newline = U32.is_eq(code, 10)
  +blank = U32.is_eq(code, 32)
  # glyphWidth: zero for '\n'; the spacing (2) is added before the last character.
  +gw = Bool.pick(F32, newline, 0.0, Bool.pick(F32, ((i + 1) < count : U32), (width + 2.0 : F32), width))
  +over = ((x + gw) > rw : F32)
  # MEASURE_STATE: endLine at a space, tab or line feed; past the width, at the last character or at a line feed the line is drawn from startLine.
  +e1 = Bool.pick(U32, blank || U32.is_eq(code, 9) || newline, i, end)
  +e2 = Bool.pick(U32, U32.is_eq(e1, 4294967295) || U32.is_eq(e1, 0), i, e1)
  +e3 = Bool.pick(U32, U32.is_eq(i, e2), pred(e2), e2)
  +e4 = Bool.pick(U32, U32.is_eq(first, e3), pred(i), e3)
  +final = U32.is_eq((i + 1 : U32), count)
  +switch = over || final || newline
  +mx = Bool.pick(F32, switch, 0.0, Bool.pick(F32, Bool.not(F32.is_eq(x, 0.0)) || Bool.not(blank), (x + gw : F32), x))
  # DRAW_STATE: a line break (without word wrap) at a line feed or past the width; the break below the height.
  +broken = Bool.not(wrap) && (newline || over)
  +dx = Bool.pick(F32, broken, 0.0, x)
  +dy = Bool.pick(F32, broken, (y + 30.0 : F32), y)
  +stop = Bool.not(newline) && ((dy + 20.0) > rh : F32)
  # The end of a measured line: the next one starts after it.
  +ended = wrap && U32.is_eq(i, end)
  +nx = Bool.pick(F32, ended, 0.0, Bool.pick(F32, Bool.not(F32.is_eq(dx, 0.0)) || Bool.not(blank), (dx + gw : F32), dx))
  +ny = Bool.pick(F32, ended, (dy + 30.0 : F32), dy)
  +next = (i + 1 : U32)
  +drawing = {Cursor{next, ended, Bool.pick(U32, ended, next, first), Bool.pick(U32, ended, 4294967295, end), nx, ny, stop} : Cursor}
  +measured = {Cursor{Bool.pick(U32, switch, first, next), Bool.not(switch), first, Bool.pick(U32, over, e4, Bool.pick(U32, final, i, e1)), mx, y, False{}} : Cursor}
  step.drawn(Bool.not(measuring) && Bool.not(newline) && Bool.not(stop) && Bool.not(blank) && Bool.not(U32.is_eq(code, 9)),
    Bool.pick(Cursor, measuring, measured, drawing),
    Bool.pick(+List<Glyph>, measuring && switch, line, tail), Bool.pick(+List<Glyph>, Bool.not(measuring) && ended, tail, line),
    code, (25.0 + 4.0 + dx : F32), (25.0 + 4.0 + dy : F32), frame, font)

def step.rest(rest: +List<Glyph>, +count: U32, +wrap: Bool, +rw: F32, +rh: F32, +i: U32, +measuring: Bool, +first: U32, +end: U32, +x: F32, +y: F32,
    +line: +List<Glyph>, frame: J.Frame, font: J.Font) -> Loop:
  match rest:
    case Nil{}: Loop{Cursor{i, measuring, first, end, x, y, True{}}, Nil{}, line, frame, font}
    case Con{+glyph, +tail}: step.glyph(count, wrap, rw, rh, i, measuring, first, end, x, y, glyph, tail, line, frame, font)

def finished(cursor: Cursor) -> Bool:
  Cursor{_, _, _, _, _, _, +done} = cursor
  done

def step.at(+count: U32, +wrap: Bool, +rw: F32, +rh: F32, cursor: Cursor, +rest: +List<Glyph>, +line: +List<Glyph>, frame: J.Frame, font: J.Font) -> Loop:
  Cursor{+i, +measuring, +first, +end, +x, +y, _} = cursor
  step.rest(rest, count, wrap, rw, rh, i, measuring, first, end, x, y, line, frame, font)

def step.live(done: Bool, +count: U32, +wrap: Bool, +rw: F32, +rh: F32, +cursor: Cursor, +rest: +List<Glyph>, +line: +List<Glyph>, frame: J.Frame, font: J.Font) -> Loop:
  match done:
    case True{}: Loop{cursor, rest, line, frame, font}
    case False{}: step.at(count, wrap, rw, rh, cursor, rest, line, frame, font)

def step(+count: U32, +wrap: Bool, +rw: F32, +rh: F32, loop: Loop) -> Loop:
  Loop{+cursor, +rest, +line, frame, font} = loop
  step.live(finished(cursor), count, wrap, rw, rh, cursor, rest, line, frame, font)

# DrawTextBoxed(font, text, rec, 20.0f, 2.0f, wordWrap, GRAY): the loop, a step per unit of fuel.
def boxed(fuel: Nat, +count: U32, +wrap: Bool, +rw: F32, +rh: F32, loop: Loop) -> Loop:
  match fuel:
    case 0n: loop
    case 1n+p: boxed(p, count, wrap, rw, rh, step(count, wrap, rw, rh, loop))

def checked(done: Bool, frame: J.Frame) -> J.Frame:
  match done:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def finish(loop: Loop) -> J.Frame & J.Font:
  Loop{+cursor, _, _, frame, font} = loop
  (checked(finished(cursor), frame), font)

# if (wordWrap) DrawText("ON", 447, screenHeight - 115, 20, RED); else DrawText("OFF", ..., BLACK).
def wrap.label(wrap: Bool, frame: J.Frame) -> J.Frame:
  match wrap:
    case True{}: J.Draw.text(frame, "ON", 447.0, (450.0 - 115.0 : F32), 20.0, J.Color.RED())
    case False{}: J.Draw.text(frame, "OFF", 447.0, (450.0 - 115.0 : F32), 20.0, J.Color.BLACK())

# After the text: the resize box, the bottom info.
def draw.done(+core: J.Core, +box: Box, +count: U32, +glyphs: +List<Glyph>, r: J.Frame & J.Font) -> J.Core & (State & J.Frame):
  Box{+width, +height, _, +wrap, _, +border} = box
  (frame, font) = r
  f1 = J.Draw.rectangle(J.Draw.rectangle_rec(frame, resizer(width, height), border), 0.0, (450.0 - 54.0 : F32), 800.0, 54.0, J.Color.GRAY())
  f2 = J.Draw.rectangle_rec(f1, J.Rectangle{382.0, (450.0 - 34.0 : F32), 12.0, 12.0}, J.Color.MAROON())
  f3 = wrap.label(wrap, J.Draw.text(f2, "Word Wrap: ", 313.0, (450.0 - 115.0 : F32), 20.0, J.Color.BLACK()))
  f4 = J.Draw.text(f3, "Press [SPACE] to toggle word wrap", 218.0, (450.0 - 86.0 : F32), 20.0, J.Color.GRAY())
  (core, (State{box, count, glyphs, font}, J.Draw.text(f4, "Click hold & drag the    to resize the container", 155.0, (450.0 - 38.0 : F32), 20.0, J.Color.RAYWHITE())))

# DrawRectangleLinesEx(container, 3, borderColor); the text in (x + 4, y + 4, width - 4, height - 4).
def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+box, +count, +glyphs, font} = state
  Box{+width, +height, _, +wrap, _, +border} = box
  f1 = J.Draw.rectangle_lines_ex(J.Frame.clear_background(frame, J.Color.RAYWHITE()), container(width, height), 3.0, border)
  draw.done(core, box, count, glyphs, finish(boxed(U32.to_nat((16 * count + 64 : U32)), count, wrap, (width - 4.0 : F32), (height - 4.0 : F32),
    Loop{Cursor{0, wrap, 0, 4294967295, 0.0, 0.0, False{}}, glyphs, glyphs, f1, font})))

def clamp(+value: F32, +low: F32, +high: F32) -> F32:
  Bool.pick(F32, (value > low : F32), Bool.pick(F32, (value < high : F32), value, high), low)

def update.at(+core: J.Core, +box: Box, +mouse: M.Vector2) -> Box:
  Box{+width, +height, +resizing, +wrap, +last, +border} = box
  M.Vector2{+lx, +ly} = last
  M.Vector2{+mx, +my} = mouse
  +inside = J.Collision.point_rec(mouse, container(width, height))
  +left = J.MouseButton.MOUSE_BUTTON_LEFT()
  Box{Bool.pick(F32, resizing, clamp((width + (mx - lx) : F32), 60.0, (800.0 - 50.0 : F32)), width),
    Bool.pick(F32, resizing, clamp((height + (my - ly) : F32), 60.0, (450.0 - 160.0 : F32)), height),
    Bool.pick(Bool, resizing, Bool.not(J.Input.is_mouse_button_released(core, left)), J.Input.is_mouse_button_down(core, left) && J.Collision.point_rec(mouse, resizer(width, height))),
    Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), Bool.not(wrap), wrap), mouse,
    Bool.pick(U32, inside, J.Color.with_alpha(J.Color.MAROON(), 0.4), Bool.pick(U32, resizing, border, J.Color.MAROON()))}

# The word wrap toggle, the border color under the mouse, then the resizing (clamped to 60..750 by 60..290).
def update(+core: J.Core, state: State) -> J.Core & State:
  State{+box, +count, +glyphs, font} = state
  (core, State{update.at(core, box, J.Input.get_mouse_position(core)), count, glyphs, font})

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def glyph.made(+code: U32, +acc: +List<Glyph>, r: J.Font & J.Rectangle) -> J.Font & +List<Glyph>:
  (font, rec) = r
  J.Rectangle{_, _, +w, _} = rec
  (font, Con{Glyph{code, (w * (20.0 / 10.0) : F32)}, acc})

def glyph.next(+code: U32, state: J.Font & +List<Glyph>) -> J.Font & +List<Glyph>:
  (font, +acc) = state
  glyph.made(code, acc, J.Font.glyph_atlas_rec(font, code))

# Each character's width: font.recs[GetGlyphIndex(font, codepoint)].width*scaleFactor (the list comes out reversed).
def glyphs(codes: +List<U32>, state: J.Font & +List<Glyph>) -> J.Font & +List<Glyph>:
  match codes:
    case Nil{}: state
    case Con{+code, rest}: glyphs(rest, glyph.next(code, state))

def setup.done(+core: J.Core, frame: J.Frame, r: J.Font & +List<Glyph>) -> J.Core & (J.Frame & State):
  (font, +reversed) = r
  (J.Core.set_target_fps(core, 60), (frame, State{Box{(800.0 - 50.0 : F32), (450.0 - 250.0 : F32), False{}, True{}, M.Vector2.zero(), J.Color.MAROON()},
    U32.from_nat(List.length(&2, Glyph, reversed)), List.reverse(&2, Glyph, reversed), font}))

# After InitWindow(800, 450): the container, the text's glyphs in GetFontDefault(), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.done(core, frame, glyphs(J.Font.codepoints(text()), (J.Font.default(), Nil{})))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [text] example - rectangle bounds", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
