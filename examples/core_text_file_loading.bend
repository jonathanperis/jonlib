# raylib [core] example - text file loading, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_text_file_loading.c
# (zlib/libpng, Copyright (c) 0 Aanjishnu Bhattacharyya (@NimComPoo-04));
# see LICENSES/raylib.txt.
#
# A text file loaded with LoadFileText and LoadTextLines, each line wrapped
# to the window by replacing the last space before the overflowing word with
# a newline (measured with MeasureText), drawn through a 2D camera the mouse
# wheel scrolls, with a scrollbar. A width or a format Jonlib cannot answer
# refuses the frames. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# One wrapped line and the pixels the drawing loop advances after it: (int)MeasureTextEx(line or " ").y + 10.
type Row is Data:
  Row{text: String, advance: U32}

# codes: the line's bytes; last: lastSpace; start: lastWrapStart.
type Wrap is Data:
  Wrap{valid: Bool, codes: +List<U32>, last: U32, start: U32}

# height: textHeight; bar: the scrollbar's height; y: cam.target.y.
type State is Data:
  State{valid: Bool, rows: +List<Row>, height: U32, bar: F32, y: F32}

def codes(text: String) -> +List<U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{c, rest}: Con{Char.to_u32(c), codes(rest)}

def chars(list: +List<U32>) -> String:
  match list:
    case Nil{}: SNil{}
    case Con{code, rest}: SCon{Char.from_u32(code), chars(rest)}

def count(list: +List<U32>, +n: U32) -> U32:
  match list:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

def head(list: +List<U32>) -> U32:
  match list:
    case Con{+code, _}: code
    case Nil{}: 0

# lines[i][index] = code.
def put(list: +List<U32>, index: Nat, +code: U32) -> +List<U32>:
  match list index:
    case Nil{} _: Nil{}
    case Con{_, rest} 0n: Con{code, rest}
    case Con{+first, rest} 1n+p: Con{first, put(rest, p, code)}

# if (MeasureText(lines[i] + lastWrapStart, fontSize) > wrapWidth) the newline goes on lastSpace and the
# wrapped line starts after it; lastSpace = j either way.
def wrap.measured(+valid: Bool, +codes: +List<U32>, +last: U32, +start: U32, +j: U32, width: Maybe<U32>) -> Wrap:
  match width:
    case None{}: Wrap{False{}, codes, j, start}
    case Some{+w}: Bool.pick(Wrap, (w > 780 : U32), Wrap{valid, put(codes, U32.to_nat(last), 10), j, (last + 1 : U32)}, Wrap{valid, codes, j, start})

def wrap.boundary(boundary: Bool, +w: Wrap, +j: U32) -> Wrap:
  match boundary:
    case False{}: w
    case True{}:
      Wrap{+valid, +codes, +last, +start} = w
      wrap.measured(valid, codes, last, start, j,
        J.Font.measure_text(chars(List.take(&2, U32, List.drop(&2, U32, codes, U32.to_nat(start)), U32.to_nat((j - start : U32)))), 20.0))

# At a space or the end of the line: measure from lastWrapStart and move lastSpace here.
def wrap.step(+w: Wrap, +n: U32, +j: U32) -> Wrap:
  Wrap{_, +codes, _, _} = w
  wrap.boundary(U32.is_eq(j, n) || U32.is_eq(head(List.drop(&2, U32, codes, U32.to_nat(j))), 32), w, j)

# while (j <= strlen(lines[i])).
def wrap(fuel: Nat, +w: Wrap, +n: U32, +j: U32) -> Wrap:
  match fuel:
    case 0n: w
    case 1n+p: wrap(p, wrap.step(w, n, j), n, (j + 1 : U32))

def height.of(r: J.Font & M.Vector2) -> U32:
  (_, size) = r
  M.Vector2{_, +y} = size
  F32.to_u32(y)

# (int)MeasureTextEx(GetFontDefault(), text, fontSize, 2).y.
def height(+text: String) -> U32:
  height.of(J.Font.measure_text_ex(J.Font.default(), text, 20.0, 2.0))

def blank(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{_, _}: False{}

# textHeight += (int)size.y + 10 measures the line itself; the drawing loop measures " " for an empty one.
type Sized is Data:
  Sized{valid: Bool, rows: +List<Row>, height: U32}

def sized.row(+text: String, +rest: Sized, +valid: Bool) -> Sized:
  Sized{+ok, +rows, +total} = rest
  Sized{valid && ok, Con{Row{text, (height(Bool.pick(String, blank(text), " ", text)) + 10 : U32)}, rows}, (total + (height(text) + 10) : U32)}

def sized.wrapped(+rest: Sized, +w: Wrap) -> Sized:
  Wrap{+valid, +codes, _, _} = w
  sized.row(chars(codes), rest, valid)

def sized.line(+bytes: +List<U32>, +rest: Sized) -> Sized:
  sized.wrapped(rest, wrap(U32.to_nat((count(bytes, 0) + 1 : U32)), Wrap{True{}, bytes, 0, 0}, count(bytes, 0), 0))

def sized(lines: +List<String>) -> Sized:
  match lines:
    case Nil{}: Sized{True{}, Nil{}, 0}
    case Con{+line, rest}: sized.line(codes(line), sized(rest))

# cam.target.y -= scroll*fontSize*1.5f, kept inside [0, textHeight - screenHeight + textTop].
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+valid, +rows, +height, +bar, +y} = state
  +moved = (y - (J.Input.get_mouse_wheel_move(core) * 20.0) * 1.5 : F32)
  +low = Bool.pick(F32, (moved < 0.0 : F32), 0.0, moved)
  +limit = ((U32.to_f32(height) - 450.0) + 45.0 : F32)
  (core, State{valid, rows, height, bar, Bool.pick(F32, (low > limit : F32), limit, low)})

# DrawText(lines[i], 10, t, fontSize, RED); t += (int)size.y + 10.
def lines(rows: +List<Row>, +t: U32, frame: J.Frame) -> J.Frame:
  match rows:
    case Nil{}: frame
    case Con{+row, rest}:
      Row{+text, +advance} = row
      lines(rest, (t + advance : U32), J.Draw.text(frame, text, 10.0, U32.to_f32(t), 20.0, J.Color.RED()))

def label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, 10.0, 20.0, J.Color.MAROON())

# scrollBar.y = Lerp(textTop, screenHeight - scrollBar.height, (cam.target.y - textTop)/(textHeight - screenHeight)).
def draw.valid(valid: Bool, +libm: M.Libm, +state: State, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: J.Frame.refuse(frame)
    case True{}:
      State{_, +rows, +height, +bar, +y} = state
      f1 = J.Frame.begin_mode_2d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), J.Camera2D{M.Vector2.zero(), M.Vector2{0.0, y}, 0.0, 1.0})
      f2 = J.Draw.rectangle(J.Frame.end_mode_2d(lines(rows, 45, f1)), 0.0, 0.0, 800.0, 35.0, J.Color.BEIGE())
      f3 = label(J.Text.format("File: %s", [J.TextString{"resources/text_file.txt"}]), f2)
      J.Draw.rectangle_rec(f3, J.Rectangle{(800.0 - 5.0 : F32), M.Math.lerp(45.0, (450.0 - bar : F32), ((y - 45.0) / (U32.to_f32(height) - 450.0) : F32)), 5.0, bar}, J.Color.MAROON())

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, _, _, _, _} = state
  (core, (state, draw.valid(valid, libm, state, frame)))

# The main loop's body; libm is the profile of BeginMode2D's sinf/cosf (rotation 0).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# scrollBar.height = screenHeight*100.0f/(textHeight - screenHeight).
def started(+sized: Sized) -> State:
  Sized{+valid, +rows, +height} = sized
  State{valid, rows, height, ((450.0 * 100.0) / (U32.to_f32(height) - 450.0) : F32), 0.0}

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, String>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: (J.Core.set_target_fps(core, 60), (frame, State{False{}, Nil{}, 0, 0.0, 0.0}))
    case Done{text}: (J.Core.set_target_fps(core, 60), (frame, started(sized(J.Text.load_lines(text)))))

# After InitWindow(800, 450): LoadFileText("resources/text_file.txt"), its wrapped lines, SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, String>, J.Core & (J.Frame & State), J.Files.load_text(dir ++ "resources/text_file.txt"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - text file loading", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
