# raylib [core] example - clipboard text, ported to Jonlib.
# Adapted from raylib 6.2 examples/core/core_clipboard_text.c (zlib/libpng,
# Copyright (c) 2025 Ananth S (@Ananth1839)); see LICENSES/raylib.txt.
#
# A raygui text box (Jongui) with cut, copy, paste, clear and random-text
# buttons drawn with icons at scale 2, and the Ctrl+X/C/V shortcuts. The
# reference's clipboard, like Jonlib's driver's, keeps nothing:
# SetClipboardText warns and GetClipboardText answers NULL, so a paste
# changes nothing and the clipboard box stays empty. See docs/GUI.md and
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# clip is clipboardText ("" for NULL); the five flags are the buttons' results of the last frame.
type State is Type:
  State{rng: J.Random.State, gui: G.Gui, editing: G.Gui.Editing, text: String, edit: Bool, clip: String, cut: Bool, copy: Bool, paste: Bool, clear: Bool, random: Bool}

# The buttons drawn so far, the last one's result first.
type Pressed is Type:
  Pressed{frame: J.Frame, flags: +List<Bool>}

def sample(index: U32) -> String:
  match index:
    case 0: "Hello from raylib!"
    case 1: "The quick brown fox jumps over the lazy dog"
    case 2: "Clipboard operations are useful!"
    case 3: "raylib is a simple and easy-to-use library"
    case _: "Copy and paste me!"

# clipboardText = GetClipboardText().
def got(clip: Maybe<String>) -> String:
  match clip:
    case None{}: ""
    case Some{t}: t

# if (clipboardText != NULL) TextCopy(inputBuffer, clipboardText).
def pasted(clip: Maybe<String>, +text: String) -> String:
  match clip:
    case None{}: text
    case Some{t}: t

def picked(r: J.Random.State & F32) -> J.Random.State & String:
  (rng, value) = r
  (rng, sample(F32.to_u32(value)))

# TextCopy(inputBuffer, sampleTexts[GetRandomValue(0, MAX_TEXT_SAMPLES - 1)]).
def random.at(random: Bool, rng: J.Random.State, +text: String) -> J.Random.State & String:
  match random:
    case False{}: (rng, text)
    case True{}: picked(J.Random.value(rng, 0.0, 4.0))

# The Ctrl shortcuts, after the buttons: X cuts, C copies, V pastes.
def update.keys(r: J.Random.State & String, +core: J.Core, +gui: G.Gui, +editing: G.Gui.Editing, +edit: Bool, +clip: String) -> J.Core & State:
  (rng, +text) = r
  +ctrl = J.Input.is_key_down(core, 341) || J.Input.is_key_down(core, 345)
  +x = ctrl && J.Input.is_key_pressed(core, 88)
  +c = ctrl && J.Input.is_key_pressed(core, 67)
  +v = ctrl && J.Input.is_key_pressed(core, 86)
  +core1 = Bool.pick(J.Core, x, J.Core.set_clipboard_text(core, text), core)
  +text1 = Bool.pick(String, x, "", text)
  +core2 = Bool.pick(J.Core, c, J.Core.set_clipboard_text(core1, text1), core1)
  (core2, State{rng, gui, editing, Bool.pick(String, v, pasted(J.Core.get_clipboard_text(core2), text1), text1), edit, Bool.pick(String, v, got(J.Core.get_clipboard_text(core2)), clip),
    False{}, False{}, False{}, False{}, False{}})

# The buttons pressed in the last frame, in the example's order: cut, copy, paste, clear, random.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{rng, +gui, +editing, +text, +edit, +clip, +cut, +copy, +paste, +clear, +random} = state
  +core1 = Bool.pick(J.Core, cut, J.Core.set_clipboard_text(core, text), core)
  +clip1 = Bool.pick(String, cut, got(J.Core.get_clipboard_text(core1)), clip)
  +text1 = Bool.pick(String, cut, "", text)
  +core2 = Bool.pick(J.Core, copy, J.Core.set_clipboard_text(core1, text1), core1)
  +clip2 = Bool.pick(String, copy || paste, got(J.Core.get_clipboard_text(core2)), clip1)
  +text2 = Bool.pick(String, paste, pasted(J.Core.get_clipboard_text(core2), text1), text1)
  update.keys(random.at(random, rng, Bool.pick(String, clear, "", text2)), core2, gui, editing, edit, clip2)

def press.take(flags: +List<Bool>, r: J.Frame & Bool) -> Pressed:
  (frame, clicked) = r
  Pressed{frame, Con{clicked, flags}}

def press(pressed: Pressed, +gui: G.Gui, +core: J.Core, +bounds: J.Rectangle, text: String) -> Pressed:
  Pressed{frame, flags} = pressed
  press.take(flags, G.Gui.button(gui, core, frame, bounds, text))

def frame.of(r: J.Frame & (J.Core & (String & (G.Gui.Editing & Bool)))) -> J.Frame:
  (frame, _) = r
  frame

# The clipboard status, drawn disabled: a label, the clipboard text in a read-only box and a hint.
def status(+gui: G.Gui, +core: J.Core, +editing: G.Gui.Editing, +clip: String, frame: J.Frame) -> J.Frame:
  +off = G.Gui.set_state(gui, 3)
  f1 = G.Gui.label(off, frame, J.Rectangle{50.0, 260.0, 700.0, 40.0}, "Clipboard current text data:")
  f2 = frame.of(G.Gui.text_box(G.Gui.set_style(off, 9, 16, 1), core, f1, J.Rectangle{50.0, 300.0, 700.0, 40.0}, clip, 256, False{}, editing))
  G.Gui.label(off, f2, J.Rectangle{50.0, 360.0, 700.0, 40.0}, "Try copying text from other applications and pasting here!")

def ui.flags(flags: +List<Bool>, frame: J.Frame, rng: J.Random.State, +gui: G.Gui, +core: J.Core, +editing: G.Gui.Editing, +text: String, +edit: Bool, +clip: String) -> J.Core & (State & J.Frame):
  match flags:
    case Con{+clear, Con{+paste, Con{+copy, Con{+cut, Con{+random, _}}}}}:
      (core, (State{rng, gui, editing, text, edit, clip, cut, copy, paste, clear, random}, status(gui, core, editing, clip, frame)))
    case _: (core, (State{rng, gui, editing, text, edit, clip, False{}, False{}, False{}, False{}, False{}}, J.Frame.refuse(frame)))

def ui.pressed(pressed: Pressed, rng: J.Random.State, +gui: G.Gui, +core: J.Core, +editing: G.Gui.Editing, +text: String, +edit: Bool, +clip: String) -> J.Core & (State & J.Frame):
  Pressed{frame, +flags} = pressed
  ui.flags(flags, frame, rng, gui, core, editing, text, edit, clip)

# The text box's result flips the edit mode; then the random-text button and the four action buttons.
def ui.pair(pair: G.Gui.Editing & Bool, +text: String, +core: J.Core, frame: J.Frame, rng: J.Random.State, +gui: G.Gui, +edit: Bool, +clip: String) -> J.Core & (State & J.Frame):
  (+editing, +toggled) = pair
  ui.pressed(press(press(press(press(press(Pressed{frame, Nil{}}, gui, core, J.Rectangle{710.0, 120.0, 40.0, 40.0}, "#77#"),
    gui, core, J.Rectangle{50.0, 180.0, 158.0, 40.0}, "#17#CUT"), gui, core, J.Rectangle{215.0, 180.0, 158.0, 40.0}, "#16#COPY"),
    gui, core, J.Rectangle{380.0, 180.0, 158.0, 40.0}, "#18#PASTE"), gui, core, J.Rectangle{545.0, 180.0, 158.0, 40.0}, "#143#CLEAR"),
    rng, gui, core, editing, text, Bool.pick(Bool, toggled, Bool.not(edit), edit), clip)

def ui.text(more: String & (G.Gui.Editing & Bool), +core: J.Core, frame: J.Frame, rng: J.Random.State, +gui: G.Gui, +edit: Bool, +clip: String) -> J.Core & (State & J.Frame):
  (+text, pair) = more
  ui.pair(pair, text, core, frame, rng, gui, edit, clip)

def ui.core(rest: J.Core & (String & (G.Gui.Editing & Bool)), frame: J.Frame, rng: J.Random.State, +gui: G.Gui, +edit: Bool, +clip: String) -> J.Core & (State & J.Frame):
  (+core, more) = rest
  ui.text(more, core, frame, rng, gui, edit, clip)

def ui.box(r: J.Frame & (J.Core & (String & (G.Gui.Editing & Bool))), rng: J.Random.State, +gui: G.Gui, +edit: Bool, +clip: String) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  ui.core(rest, frame, rng, gui, edit, clip)

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{rng, +gui, +editing, +text, +edit, +clip, _, _, _, _, _} = state
  f1 = G.Gui.label(gui, J.Frame.clear_background(frame, J.Color.RAYWHITE()), J.Rectangle{50.0, 20.0, 700.0, 36.0}, "Use the BUTTONS or KEY SHORTCUTS:")
  f2 = J.Draw.text(f1, "[CTRL+X] - CUT | [CTRL+C] COPY | [CTRL+V] | PASTE", 50.0, 60.0, 20.0, J.Color.MAROON())
  ui.box(G.Gui.text_box(gui, core, f2, J.Rectangle{50.0, 120.0, 652.0, 40.0}, text, 256, edit, editing), rng, gui, edit, clip)

# The main loop's body; nothing in it follows the libm profile.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): GuiSetStyle(DEFAULT, TEXT_SIZE, 20), GuiSetIconScale(2), SetTargetFPS(60).
def setup(+seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{J.Random.seed(seed), G.Gui.set_icon_scale(G.Gui.set_style(G.Gui.new(), 0, 16, 20), 2), G.Gui.editing(), "Hello from raylib!", False{}, "",
    False{}, False{}, False{}, False{}, False{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [core] example - clipboard text", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
