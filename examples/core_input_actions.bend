# raylib [core] example - input actions, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_input_actions.c (zlib/libpng,
# Copyright (c) 2025 Jett (@JettMonstersGoBoom)); see LICENSES/raylib.txt.
#
# A rectangle moved by actions, each bound to a key and a gamepad button of
# gamepad 0; TAB switches between the WASD set (left face buttons) and the
# arrow-key set (right face buttons). The fire action (SPACE) centers the
# rectangle and its release turns it blue for that frame. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# set: 0 the default keyset, 1 the cursor keyset; released: the fire action was released this frame.
type State is Data:
  State{set: U32, released: Bool, position: M.Vector2}

def at(codes: +List<U32>, n: Nat) -> U32:
  match codes n:
    case Nil{} _: 0
    case Con{+code, _} 0n: code
    case Con{_, rest} 1n+p: at(rest, p)

# actionInputs[action].key for the keyset: actions 1 up, 2 down, 3 left, 4 right, 5 fire.
def key(set: U32, +action: U32) -> U32:
  match set:
    case 0: at([0, J.KeyboardKey.KEY_W(), J.KeyboardKey.KEY_S(), J.KeyboardKey.KEY_A(), J.KeyboardKey.KEY_D(), J.KeyboardKey.KEY_SPACE()], U32.to_nat(action))
    case _: at([0, J.KeyboardKey.KEY_UP(), J.KeyboardKey.KEY_DOWN(), J.KeyboardKey.KEY_LEFT(), J.KeyboardKey.KEY_RIGHT(), J.KeyboardKey.KEY_SPACE()], U32.to_nat(action))

# actionInputs[action].button for the keyset.
def button(set: U32, +action: U32) -> U32:
  match set:
    case 0: at([0, J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_UP(), J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_DOWN(),
      J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_LEFT(), J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_RIGHT(), J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_DOWN()], U32.to_nat(action))
    case _: at([0, J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_UP(), J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_DOWN(),
      J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_LEFT(), J.GamepadButton.GAMEPAD_BUTTON_RIGHT_FACE_RIGHT(), J.GamepadButton.GAMEPAD_BUTTON_LEFT_FACE_DOWN()], U32.to_nat(action))

# A gamepad answer; gamepad 0 always has one.
def pad(answer: Maybe<Bool>) -> Bool:
  match answer:
    case None{}: False{}
    case Some{+b}: b

def down(+core: J.Core, +set: U32, +action: U32) -> Bool:
  J.Input.is_key_down(core, key(set, action)) || pad(J.Input.is_gamepad_button_down(core, 0, button(set, action)))

def pressed(+core: J.Core, +set: U32, +action: U32) -> Bool:
  J.Input.is_key_pressed(core, key(set, action)) || pad(J.Input.is_gamepad_button_pressed(core, 0, button(set, action)))

def released(+core: J.Core, +set: U32, +action: U32) -> Bool:
  J.Input.is_key_released(core, key(set, action)) || pad(J.Input.is_gamepad_button_released(core, 0, button(set, action)))

# The four moves by 2, fire to ((screenWidth - size.x)/2, (screenHeight - size.y)/2), then TAB switches the keyset.
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+set, _, +position} = state
  M.Vector2{+x, +y} = position
  +up = Bool.pick(F32, down(core, set, 1), (y - 2.0 : F32), y)
  +low = Bool.pick(F32, down(core, set, 2), (up + 2.0 : F32), up)
  +left = Bool.pick(F32, down(core, set, 3), (x - 2.0 : F32), x)
  +right = Bool.pick(F32, down(core, set, 4), (left + 2.0 : F32), left)
  +fire = pressed(core, set, 5)
  (core, State{Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_TAB()), (1 - set : U32), set), released(core, set, 5),
    M.Vector2{Bool.pick(F32, fire, ((800.0 - 40.0) / 2.0 : F32), right), Bool.pick(F32, fire, ((450.0 - 40.0) / 2.0 : F32), low)}})

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+set, +released, +position} = state
  f1 = J.Draw.rectangle_v(J.Frame.clear_background(frame, J.Color.GRAY()), position, M.Vector2{40.0, 40.0}, Bool.pick(U32, released, J.Color.BLUE(), J.Color.RED()))
  f2 = J.Draw.text(f1, Bool.pick(String, U32.is_eq(set, 0), "Current input set: WASD (default)", "Current input set: Arrow keys"), 10.0, 10.0, 20.0, J.Color.WHITE())
  (core, (state, J.Draw.text(f2, "Use TAB key to toggles Actions keyset", 10.0, 50.0, 20.0, J.Color.GREEN())))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): the default keyset, the rectangle at (400, 200), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{0, False{}, M.Vector2{400.0, 200.0}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - input actions", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
