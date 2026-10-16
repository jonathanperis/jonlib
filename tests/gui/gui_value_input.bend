# Jongui's GuiValueBoxFloat (outside edit mode) and GuiTextInputBox, ported
# from tools/reference/gui/gui_value_input.c (a probe-only raygui program,
# not a raylib example) and replayed against it by tools/examples_probe.py
# (category gui). raygui's static textEditMode and the text box globals are
# shared by both input boxes: each call's are passed on to the next.
import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M
import ../../jongui.bend as G

type State is Data:
  State{gui: G.Gui, presses: U32, secret: G.Gui.Input, secret_result: U32, plain: String, plain_result: U32}

# TextFormat's "%d" of an int given as its bits.
def int(+v: U32) -> String:
  Bool.pick(String, (v >= 2147483648 : U32), "-" ++ U32.show((0 - v : U32)), U32.show(v))

# A result kept when it is 0 or more.
def kept(+got: U32, +old: U32) -> U32:
  Bool.pick(U32, (got >= 2147483648 : U32), old, got)

def first(r: J.Frame & (F32 & Bool)) -> J.Frame:
  (frame, _) = r
  frame

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

# The plain box's input carries the shared globals back to the secret one.
def draw.plained.input(+gui: G.Gui, +core: J.Core, +presses: U32, +secret: G.Gui.Input, +secret_result: U32, +plain_result: U32, frame: J.Frame, plain: G.Gui.Input) -> J.Core & (State & J.Frame):
  G.GuiInput{+stext, +sview, _, _} = secret
  G.GuiInput{+text, _, +edit, +editing} = plain
  f1 = J.Draw.text(frame, int(presses) ++ " " ++ int(secret_result) ++ " " ++ int(plain_result) ++ " " ++ int(sview), 330.0, 340.0, 10.0, J.Color.BLACK())
  f2 = first(G.Gui.value_box_float(G.Gui.disable(gui), core, f1, J.Rectangle{380.0, 10.0, 100.0, 24.0}, None{}, "1.0", 2.5, False{}))
  (core, (State{gui, presses, G.GuiInput{stext, sview, edit, editing}, secret_result, text, plain_result}, f2))

def draw.plained.rest(+gui: G.Gui, +core: J.Core, +presses: U32, +secret: G.Gui.Input, +secret_result: U32, +plain_result: U32, frame: J.Frame, rest: G.Gui.Input & U32) -> J.Core & (State & J.Frame):
  (plain, +got) = rest
  draw.plained.input(gui, core, presses, secret, secret_result, kept(got, plain_result), frame, plain)

def draw.plained(+gui: G.Gui, +presses: U32, +secret: G.Gui.Input, +secret_result: U32, +plain_result: U32, frame: J.Frame, r: J.Core & (G.Gui.Input & U32)) -> J.Core & (State & J.Frame):
  (+core, rest) = r
  draw.plained.rest(gui, core, presses, secret, secret_result, plain_result, frame, rest)

def draw.plain.frame(+gui: G.Gui, +presses: U32, +secret: G.Gui.Input, +secret_result: U32, +plain_result: U32, r: J.Frame & (J.Core & (G.Gui.Input & U32))) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.plained(gui, presses, secret, secret_result, plain_result, frame, rest)

def draw.secreted.input(+gui: G.Gui, +core: J.Core, +presses: U32, +secret_result: U32, +plain: String, +plain_result: U32, frame: J.Frame, secret: G.Gui.Input) -> J.Core & (State & J.Frame):
  G.GuiInput{+stext, +sview, +edit, +editing} = secret
  draw.plain.frame(gui, presses, G.GuiInput{stext, sview, edit, editing}, secret_result, plain_result,
    G.Gui.text_input_box(gui, core, frame, J.Rectangle{10.0, 210.0, 300.0, 130.0}, None{}, None{}, "Done", 64, G.GuiInput{plain, 2, edit, editing}))

def draw.secreted.rest(+gui: G.Gui, +core: J.Core, +presses: U32, +secret_result: U32, +plain: String, +plain_result: U32, frame: J.Frame, rest: G.Gui.Input & U32) -> J.Core & (State & J.Frame):
  (secret, +got) = rest
  draw.secreted.input(gui, core, presses, kept(got, secret_result), plain, plain_result, frame, secret)

def draw.secreted(+gui: G.Gui, +presses: U32, +secret_result: U32, +plain: String, +plain_result: U32, frame: J.Frame, r: J.Core & (G.Gui.Input & U32)) -> J.Core & (State & J.Frame):
  (+core, rest) = r
  draw.secreted.rest(gui, core, presses, secret_result, plain, plain_result, frame, rest)

def draw.secret.frame(+gui: G.Gui, +presses: U32, +secret_result: U32, +plain: String, +plain_result: U32, r: J.Frame & (J.Core & (G.Gui.Input & U32))) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.secreted(gui, presses, secret_result, plain, plain_result, frame, rest)

def draw.valued.result(+core: J.Core, +gui: G.Gui, +presses: U32, +secret: G.Gui.Input, +secret_result: U32, +plain: String, +plain_result: U32, frame: J.Frame, result: F32 & Bool) -> J.Core & (State & J.Frame):
  (_, +pressed) = result
  draw.secret.frame(gui, Bool.pick(U32, pressed, (presses + 1 : U32), presses), secret_result, plain, plain_result,
    G.Gui.text_input_box(gui, core, frame, J.Rectangle{10.0, 50.0, 300.0, 150.0}, Some{"#191#Login"}, Some{"Password:"}, "Ok;Cancel", 64, secret))

def draw.valued(+core: J.Core, +gui: G.Gui, +presses: U32, +secret: G.Gui.Input, +secret_result: U32, +plain: String, +plain_result: U32, r: J.Frame & (F32 & Bool)) -> J.Core & (State & J.Frame):
  (frame, result) = r
  draw.valued.result(core, gui, presses, secret, secret_result, plain, plain_result, frame, result)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +presses, +secret, +secret_result, +plain, +plain_result} = state
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  draw.valued(core, gui, presses, secret, secret_result, plain, plain_result,
    G.Gui.value_box_float(gui, core, f1, J.Rectangle{60.0, 10.0, 100.0, 24.0}, Some{"Value"}, "2.5", 2.5, False{}))

def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(500, 360): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), 0, G.GuiInput{"secret", 0, False{}, G.Gui.editing()}, 4294967294, "hello", 4294967294}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "jonlib gui - value box float, text input box", 500, 360, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
