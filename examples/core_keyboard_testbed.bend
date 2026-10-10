# raylib [core] example - keyboard testbed, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_keyboard_testbed.c (zlib/libpng,
# Copyright (c) 2026 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A US keyboard of six lines of keys, each outlined in MAROON with its text
# while the key is down (IsKeyDown) and highlighted under the mouse. The
# example also reads GetKeyPressed and GetCharPressed every frame and
# prints an INFO line for each; the queues are read here too, but the
# lines are not printed (J.Program's update is pure, docs/DRIVER.md). The
# key texts and the lines' keycodes and widths are generated from the
# example's tables with raylib.h's keycodes.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{}

# A key of a line: its keycode and its rectangle's width.
type Cap is Data:
  Cap{code: U32, width: U32}

# GetKeyText: the key's text on a US keyboard (the cases by keycode, as raylib.h numbers them).
def key.text(key: U32) -> String:
  match key:
    case 32: "SPACE"
    case 39: "'"
    case 44: ","
    case 45: "-"
    case 46: "."
    case 47: "/"
    case 48: "0"
    case 49: "1"
    case 50: "2"
    case 51: "3"
    case 52: "4"
    case 53: "5"
    case 54: "6"
    case 55: "7"
    case 56: "8"
    case 57: "9"
    case 59: ";"
    case 61: "="
    case 65: "A"
    case 66: "B"
    case 67: "C"
    case 68: "D"
    case 69: "E"
    case 70: "F"
    case 71: "G"
    case 72: "H"
    case 73: "I"
    case 74: "J"
    case 75: "K"
    case 76: "L"
    case 77: "M"
    case 78: "N"
    case 79: "O"
    case 80: "P"
    case 81: "Q"
    case 82: "R"
    case 83: "S"
    case 84: "T"
    case 85: "U"
    case 86: "V"
    case 87: "W"
    case 88: "X"
    case 89: "Y"
    case 90: "Z"
    case 91: "["
    case 92: "\\"
    case 93: "]"
    case 96: "`"
    case 256: "ESC"
    case 257: "ENTER"
    case 258: "TAB"
    case 259: "BACK"
    case 260: "INS"
    case 261: "DEL"
    case 262: "RIGHT"
    case 263: "LEFT"
    case 264: "DOWN"
    case 265: "UP"
    case 266: "PGUP"
    case 267: "PGDOWN"
    case 268: "HOME"
    case 269: "END"
    case 280: "CAPS"
    case 281: "LOCK"
    case 282: "NUMLOCK"
    case 283: "PRINTSCR"
    case 284: "PAUSE"
    case 290: "F1"
    case 291: "F2"
    case 292: "F3"
    case 293: "F4"
    case 294: "F5"
    case 295: "F6"
    case 296: "F7"
    case 297: "F8"
    case 298: "F9"
    case 299: "F10"
    case 300: "F11"
    case 301: "F12"
    case 320: "KP0"
    case 321: "KP1"
    case 322: "KP2"
    case 323: "KP3"
    case 324: "KP4"
    case 325: "KP5"
    case 326: "KP6"
    case 327: "KP7"
    case 328: "KP8"
    case 329: "KP9"
    case 330: "KPDEC"
    case 331: "KPDIV"
    case 332: "KPMUL"
    case 333: "KPSUB"
    case 334: "KPADD"
    case 335: "KPENTER"
    case 336: "KPEQU"
    case 340: "LSHIFT"
    case 341: "LCTRL"
    case 342: "LALT"
    case 343: "WIN"
    case 344: "RSHIFT"
    case 345: "RCTRL"
    case 346: "ALTGR"
    case 347: "RSUPER"
    case 348: "KBMENU"
    case _: ""

# Keyboard line 01: KEY_ESCAPE, KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11, KEY_F12, KEY_PRINT_SCREEN, KEY_PAUSE.
def line01() -> +List<Cap>:
  [Cap{256, 45}, Cap{290, 45}, Cap{291, 45}, Cap{292, 45}, Cap{293, 45}, Cap{294, 45}, Cap{295, 45}, Cap{296, 45}, Cap{297, 45}, Cap{298, 45}, Cap{299, 45}, Cap{300, 45}, Cap{301, 45}, Cap{283, 62}, Cap{284, 45}]

# Keyboard line 02: KEY_GRAVE, KEY_ONE, KEY_TWO, KEY_THREE, KEY_FOUR, KEY_FIVE, KEY_SIX, KEY_SEVEN, KEY_EIGHT, KEY_NINE, KEY_ZERO, KEY_MINUS, KEY_EQUAL, KEY_BACKSPACE, KEY_DELETE.
def line02() -> +List<Cap>:
  [Cap{96, 25}, Cap{49, 45}, Cap{50, 45}, Cap{51, 45}, Cap{52, 45}, Cap{53, 45}, Cap{54, 45}, Cap{55, 45}, Cap{56, 45}, Cap{57, 45}, Cap{48, 45}, Cap{45, 45}, Cap{61, 45}, Cap{259, 82}, Cap{261, 45}]

# Keyboard line 03: KEY_TAB, KEY_Q, KEY_W, KEY_E, KEY_R, KEY_T, KEY_Y, KEY_U, KEY_I, KEY_O, KEY_P, KEY_LEFT_BRACKET, KEY_RIGHT_BRACKET, KEY_BACKSLASH, KEY_INSERT.
def line03() -> +List<Cap>:
  [Cap{258, 50}, Cap{81, 45}, Cap{87, 45}, Cap{69, 45}, Cap{82, 45}, Cap{84, 45}, Cap{89, 45}, Cap{85, 45}, Cap{73, 45}, Cap{79, 45}, Cap{80, 45}, Cap{91, 45}, Cap{93, 45}, Cap{92, 57}, Cap{260, 45}]

# Keyboard line 04: KEY_CAPS_LOCK, KEY_A, KEY_S, KEY_D, KEY_F, KEY_G, KEY_H, KEY_J, KEY_K, KEY_L, KEY_SEMICOLON, KEY_APOSTROPHE, KEY_ENTER, KEY_PAGE_UP.
def line04() -> +List<Cap>:
  [Cap{280, 68}, Cap{65, 45}, Cap{83, 45}, Cap{68, 45}, Cap{70, 45}, Cap{71, 45}, Cap{72, 45}, Cap{74, 45}, Cap{75, 45}, Cap{76, 45}, Cap{59, 45}, Cap{39, 45}, Cap{257, 88}, Cap{266, 45}]

# Keyboard line 05: KEY_LEFT_SHIFT, KEY_Z, KEY_X, KEY_C, KEY_V, KEY_B, KEY_N, KEY_M, KEY_COMMA, KEY_PERIOD, KEY_SLASH, KEY_RIGHT_SHIFT, KEY_UP, KEY_PAGE_DOWN.
def line05() -> +List<Cap>:
  [Cap{340, 80}, Cap{90, 45}, Cap{88, 45}, Cap{67, 45}, Cap{86, 45}, Cap{66, 45}, Cap{78, 45}, Cap{77, 45}, Cap{44, 45}, Cap{46, 45}, Cap{47, 45}, Cap{344, 76}, Cap{265, 45}, Cap{267, 45}]

# Keyboard line 06: KEY_LEFT_CONTROL, KEY_LEFT_SUPER, KEY_LEFT_ALT, KEY_SPACE, KEY_RIGHT_ALT, 162, KEY_NULL, KEY_RIGHT_CONTROL, KEY_LEFT, KEY_DOWN, KEY_RIGHT.
def line06() -> +List<Cap>:
  [Cap{341, 80}, Cap{343, 45}, Cap{342, 45}, Cap{32, 208}, Cap{346, 45}, Cap{162, 45}, Cap{0, 45}, Cap{345, 60}, Cap{263, 45}, Cap{264, 45}, Cap{262, 45}]

def tone(+down: Bool) -> U32:
  Bool.pick(U32, down, J.Color.MAROON(), J.Color.DARKGRAY())

# KEY_NULL: a LIGHTGRAY outline; else the outline and GetKeyText at (x + 4, y + 4) in MAROON while down, DARKGRAY otherwise.
def key.labeled(null: Bool, +down: Bool, +code: U32, +bounds: J.Rectangle, +x: F32, +y: F32, frame: J.Frame) -> J.Frame:
  match null:
    case True{}: J.Draw.rectangle_lines_ex(frame, bounds, 2.0, J.Color.LIGHTGRAY())
    case False{}: J.Draw.text(J.Draw.rectangle_lines_ex(frame, bounds, 2.0, tone(down)), key.text(code), F32.trunc((x + 4.0 : F32)), F32.trunc((y + 4.0 : F32)), 10.0, tone(down))

# Under the mouse: DrawRectangleRec(bounds, Fade(RED, 0.2f)) and a RED outline.
def key.hovered(hover: Bool, +bounds: J.Rectangle, frame: J.Frame) -> J.Frame:
  match hover:
    case False{}: frame
    case True{}: J.Draw.rectangle_lines_ex(J.Draw.rectangle_rec(frame, bounds, J.Color.with_alpha(J.Color.RED(), 0.2)), bounds, 3.0, J.Color.RED())

# GuiKeyboardKey(bounds, key).
def key(+core: J.Core, +mouse: M.Vector2, +bounds: J.Rectangle, +x: F32, +y: F32, +code: U32, frame: J.Frame) -> J.Frame:
  key.hovered(J.Collision.point_rec(mouse, bounds), bounds, key.labeled(U32.is_eq(code, 0), J.Input.is_key_down(core, code), code, bounds, x, y, frame))

# A line of keys from keyboardOffset.x (26): recOffsetX += width + KEY_REC_SPACING (4).
def row(keys: +List<Cap>, +core: J.Core, +mouse: M.Vector2, +offset: U32, +y: F32, +height: F32, frame: J.Frame) -> J.Frame:
  match keys:
    case Nil{}: frame
    case Con{Cap{+code, +width}, rest}: row(rest, core, mouse, (offset + width + 4 : U32), y, height,
      key(core, mouse, J.Rectangle{(26.0 + U32.to_f32(offset) : F32), y, U32.to_f32(width), height}, (26.0 + U32.to_f32(offset) : F32), y, code, frame))

# The six lines from keyboardOffset.y (80): the first 30 high, the others 38, 4 apart.
def draw.at(+core: J.Core, +mouse: M.Vector2, frame: J.Frame) -> J.Frame:
  f1 = row(line01(), core, mouse, 0, 80.0, 30.0, J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "KEYBOARD LAYOUT: ENG-US", 26.0, 38.0, 20.0, J.Color.LIGHTGRAY()))
  f2 = row(line02(), core, mouse, 0, (80.0 + 30.0 + 4.0 : F32), 38.0, f1)
  f3 = row(line03(), core, mouse, 0, (80.0 + 30.0 + 38.0 + 4.0 * 2.0 : F32), 38.0, f2)
  f4 = row(line04(), core, mouse, 0, (80.0 + 30.0 + 38.0 * 2.0 + 4.0 * 3.0 : F32), 38.0, f3)
  f5 = row(line05(), core, mouse, 0, (80.0 + 30.0 + 38.0 * 3.0 + 4.0 * 4.0 : F32), 38.0, f4)
  row(line06(), core, mouse, 0, (80.0 + 30.0 + 38.0 * 4.0 + 4.0 * 5.0 : F32), 38.0, f5)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  (core, (state, draw.at(core, J.Input.get_mouse_position(core), frame)))

def popped(r: J.Core & U32) -> J.Core:
  (core, _) = r
  core

def chars(+core: J.Core) -> J.Core:
  popped(J.Input.get_char_pressed(core))

# key = GetKeyPressed(); ch = GetCharPressed().
def update(+core: J.Core, +state: State) -> J.Core & State:
  (chars(popped(J.Input.get_key_pressed(core))), state)

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): SetExitKey(KEY_NULL), SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(J.Input.set_exit_key(core, J.KeyboardKey.KEY_NULL()), 60), (frame, State{}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - keyboard testbed", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
