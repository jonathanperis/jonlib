# raylib [textures] example - clipboard image, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_clipboard_image.c (zlib/libpng,
# Copyright (c) 2026 Maicon Santana (@maiconpintoabreu)); see LICENSES/raylib.txt.
#
# CTRL+V pastes the clipboard's image as a texture at the mouse (20 at
# most) and R clears the collection. GetClipboardImage has no image on the
# platform Jonlib models, as on raylib's desktop platform outside Windows
# (docs/DRIVER.md), so the collection stays empty and only the header is
# drawn. An image would be uploaded inside the update, which J.Program's
# pure update cannot do: that frame and every later one would be refused.
# The INFO line of a failed paste is not printed.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# currentCollectionIndex; ok: no refusal so far.
type State is Data:
  State{count: U32, ok: Bool}

# IsImageValid(GetClipboardImage()) is false: nothing joins the collection.
def empty(image: Maybe<J.Surface>) -> Bool:
  match image:
    case None{}: True{}
    case Some{_}: False{}

def pasted(paste: Bool, +core: J.Core) -> Bool:
  match paste:
    case False{}: True{}
    case True{}: empty(J.Core.get_clipboard_image(core))

# R: the textures unloaded (none is loaded) and the collection emptied; CTRL+V below 20 textures: the paste.
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+count, +ok} = state
  +cleared = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_R()), 0, count)
  (core, State{cleared, ok && pasted(J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT_CONTROL()) && J.Input.is_key_pressed(core, J.KeyboardKey.KEY_V()) && (cleared < 20 : U32), core)})

def checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

# The collection (empty), then the header.
def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{_, +ok} = state
  f1 = J.Draw.rectangle(J.Frame.clear_background(checked(ok, frame), J.Color.RAYWHITE()), 0.0, 0.0, 800.0, 40.0, J.Color.BLACK())
  (core, (state, J.Draw.text(f1, "Clipboard Image - Ctrl+V to Paste and R to Reset ", 120.0, 10.0, 20.0, J.Color.LIGHTGRAY())))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): an empty collection, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{0, True{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - clipboard image", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
