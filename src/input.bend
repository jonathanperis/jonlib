# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 rcore.c (CORE.Input, PlayAutomationEvent's
# input events, the keyboard/mouse/touch/gamepad queries) and of
# src/platforms/rcore_memory.c (PollInputEvents, SetMousePosition and the cursor
# functions) as pinned raylib 6.0 runs them on PLATFORM=Memory (zlib,
# LICENSES/raylib.txt); the key and char callbacks follow
# src/platforms/rcore_desktop_glfw.c.
#
# The state is an explicit value instead of raylib's CORE.Input global. C ints are
# U32 two's-complement words. Writes or reads raylib would make outside its arrays
# (an event key outside 0..511, a negative gamepad index, ...) are refused
# (None); queries raylib bounds-checks answer as raylib does. See docs/INPUT.md.
import Base

# -----------------------------------------------------------------------------
# Words, bits and signed ints

# A raylib Vector2 (jonlib.bend converts to and from Point).
type Point is Data:
  Point{x: F32, y: F32}

def negative(+x: U32) -> Bool:
  (x >= 2147483648 : U32)

# a < b as C ints.
def signed_less(+a: U32, +b: U32) -> Bool:
  ((a .^. 2147483648) < (b .^. 2147483648) : U32)

# (float) of a C int (round to nearest).
def int_to_f32(+word: U32) -> F32:
  Bool.pick(F32, negative(word), F32.neg(U32.to_f32((0 - word : U32))), U32.to_f32(word))

# C's float-to-int conversion: defined when trunc(x) is in [-2^31, 2^31) (NaN
# excluded); no float lies strictly between -2^31 - 1 and -2^31.
def f32_int.valid(+x: F32) -> Bool:
  (x >= F32.neg(2147483648.0) : F32) && (x < 2147483648.0 : F32)

# The int word of a valid x (0 otherwise).
def f32_int.word(+x: F32) -> U32:
  +magnitude = F32.to_u32(Bool.pick(F32, f32_int.valid(x), F32.trunc(F32.abs(x)), 0.0))
  Bool.pick(U32, (x < 0.0 : F32), (0 - magnitude : U32), magnitude)

def f32_int.checked(valid: Bool, +x: F32) -> Maybe<U32>:
  match valid:
    case False{}: None{}
    case True{}: Some{f32_int.word(x)}

# (int)x, None where C's conversion is undefined.
def f32_int(+x: F32) -> Maybe<U32>:
  f32_int.checked(f32_int.valid(x), x)

def item(-A: Data, xs: +List<A>, n: Nat, +default: A) -> A:
  match xs n:
    case Nil{} _: default
    case Con{+x, _} 0n: x
    case Con{_, rest} 1n+k: item(A, rest, k, default)

def words(n: Nat) -> +List<U32>:
  List.replicate(U32, n, 0)

def bit.of(+word: U32, +index: U32) -> Bool:
  U32.is_ne(((word >> U32.to_nat((index .&. 31 : U32))) .&. 1 : U32), 0)

def bit.masked(value: Bool, +word: U32, +mask: U32) -> U32:
  match value:
    case False{}: (word .&. (mask .^. 4294967295) : U32)
    case True{}: (word .|. mask : U32)

def bit.with(value: Bool, +word: U32, +index: U32) -> U32:
  bit.masked(value, word, (1 << U32.to_nat((index .&. 31 : U32)) : U32))

# Bit index of a list of 32-bit words.
def bits.get(+list: +List<U32>, +index: U32) -> Bool:
  bit.of(item(U32, list, U32.to_nat((index >> 5n : U32)), 0), index)

def bits.set(+list: +List<U32>, +index: U32, value: Bool) -> +List<U32>:
  +n = U32.to_nat((index >> 5n : U32))
  List.set(&2, U32, list, n, bit.with(value, item(U32, list, n, 0), index))

def queue.length(xs: +List<U32>) -> U32:
  match xs:
    case Nil{}: 0
    case Con{_, rest}: (1 + queue.length(rest) : U32)

def queue.add(room: Bool, +xs: +List<U32>, +x: U32) -> +List<U32>:
  match room:
    case False{}: xs
    case True{}: List.append(&2, U32, xs, [x])

# Appends x when the queue holds fewer than 16 entries (MAX_KEY_PRESSED_QUEUE,
# MAX_CHAR_PRESSED_QUEUE).
def queue.push(wanted: Bool, +xs: +List<U32>, +x: U32) -> +List<U32>:
  queue.add(wanted && (queue.length(xs) < 16 : U32), xs, x)

def queue.pop(xs: +List<U32>) -> +List<U32> & U32:
  match xs:
    case Nil{}: (Nil{}, 0)
    case Con{x, rest}: (rest, x)

def vector.zero() -> Point:
  Point{0.0, 0.0}

def vector.ints(+x: U32, +y: U32) -> Point:
  Point{int_to_f32(x), int_to_f32(y)}

def vector.at(+list: +List<Point>, +index: U32) -> Point:
  item(Point, list, U32.to_nat(index), vector.zero())

# -----------------------------------------------------------------------------
# State (CORE.Input after InitWindow: zeroed, exit key KEY_ESCAPE, mouse scale 1)

# Key states are 16 words of 32 keys (MAX_KEYBOARD_KEYS 512); keys and chars are
# the pressed-key and char queues in order (at most 16 entries each).
type Keyboard is Data:
  Keyboard{exit_key: U32, current: +List<U32>, previous: +List<U32>, repeat: +List<U32>, keys: +List<U32>, chars: +List<U32>}

# Button states are bits of one word (MAX_MOUSE_BUTTONS 8).
type MouseState is Data:
  MouseState{offset: Point, scale: Point, position: Point, previous: Point, hidden: Bool, on_screen: Bool,
    buttons: U32, previous_buttons: U32, wheel: Point, previous_wheel: Point}

# MAX_TOUCH_POINTS 8: ids, positions and states (bits of one word).
type Touch is Data:
  Touch{count: U32, ids: +List<U32>, positions: +List<Point>, previous_positions: +List<Point>, current: U32, previous: U32}

# MAX_GAMEPADS 4: ready bits, one word of MAX_GAMEPAD_BUTTONS 32 buttons per
# gamepad and MAX_GAMEPAD_AXES 8 axes per gamepad (index gamepad*8 + axis).
type Gamepads is Data:
  Gamepads{last: U32, axis_counts: +List<U32>, ready: U32, current: +List<U32>, previous: +List<U32>, axes: +List<F32>}

type Input is Data:
  Input{keyboard: Keyboard, mouse: MouseState, touch: Touch, gamepads: Gamepads}

def Keyboard.new() -> Keyboard:
  Keyboard{256, words(16n), words(16n), words(16n), Nil{}, Nil{}}

def MouseState.new() -> MouseState:
  MouseState{vector.zero(), Point{1.0, 1.0}, vector.zero(), vector.zero(), False{}, False{}, 0, 0, vector.zero(), vector.zero()}

def Touch.new() -> Touch:
  Touch{0, words(8n), List.replicate(Point, 8n, vector.zero()), List.replicate(Point, 8n, vector.zero()), 0, 0}

def Gamepads.new() -> Gamepads:
  Gamepads{0, words(4n), 0, words(4n), words(4n), List.replicate(F32, 32n, 0.0)}

def Input.new() -> Input:
  Input{Keyboard.new(), MouseState.new(), Touch.new(), Gamepads.new()}

def Input.keyboard(+input: Input) -> Keyboard:
  Input{keyboard, _, _, _} = input
  keyboard

def Input.mouse(+input: Input) -> MouseState:
  Input{_, mouse, _, _} = input
  mouse

def Input.touch(+input: Input) -> Touch:
  Input{_, _, touch, _} = input
  touch

def Input.gamepads(+input: Input) -> Gamepads:
  Input{_, _, _, gamepads} = input
  gamepads

def Input.with_keyboard(input: Input, keyboard: Keyboard) -> Input:
  Input{_, mouse, touch, gamepads} = input
  Input{keyboard, mouse, touch, gamepads}

def Input.with_mouse(input: Input, mouse: MouseState) -> Input:
  Input{keyboard, _, touch, gamepads} = input
  Input{keyboard, mouse, touch, gamepads}

def Input.with_touch(input: Input, touch: Touch) -> Input:
  Input{keyboard, mouse, _, gamepads} = input
  Input{keyboard, mouse, touch, gamepads}

def Input.with_gamepads(input: Input, gamepads: Gamepads) -> Input:
  Input{keyboard, mouse, touch, _} = input
  Input{keyboard, mouse, touch, gamepads}

# -----------------------------------------------------------------------------
# Keyboard

def Keyboard.current(+kb: Keyboard) -> +List<U32>:
  Keyboard{_, current, _, _, _, _} = kb
  current

def Keyboard.previous(+kb: Keyboard) -> +List<U32>:
  Keyboard{_, _, previous, _, _, _} = kb
  previous

def Keyboard.repeat(+kb: Keyboard) -> +List<U32>:
  Keyboard{_, _, _, repeat, _, _} = kb
  repeat

def Keyboard.exit_key(+kb: Keyboard) -> U32:
  Keyboard{exit, _, _, _, _, _} = kb
  exit

# INPUT_KEY_UP: currentKeyState[key] = 0.
def Keyboard.release(kb: Keyboard, +key: U32) -> Keyboard:
  Keyboard{exit, current, previous, repeat, keys, chars} = kb
  Keyboard{exit, bits.set(current, key, False{}), previous, repeat, keys, chars}

# INPUT_KEY_DOWN: currentKeyState[key] = 1, queued when it was up last frame.
def Keyboard.press(kb: Keyboard, +key: U32) -> Keyboard:
  Keyboard{exit, current, +previous, repeat, keys, chars} = kb
  Keyboard{exit, bits.set(current, key, True{}), previous, repeat, queue.push(Bool.not(bits.get(previous, key)), keys, key), chars}

def Keyboard.set_exit_key(kb: Keyboard, +key: U32) -> Keyboard:
  Keyboard{_, current, previous, repeat, keys, chars} = kb
  Keyboard{key, current, previous, repeat, keys, chars}

def Keyboard.popped_key(exit: U32, current: +List<U32>, previous: +List<U32>, repeat: +List<U32>, chars: +List<U32>, popped: +List<U32> & U32) -> Keyboard & U32:
  (keys, key) = popped
  (Keyboard{exit, current, previous, repeat, keys, chars}, key)

def Keyboard.pop_key(kb: Keyboard) -> Keyboard & U32:
  Keyboard{exit, current, previous, repeat, keys, chars} = kb
  Keyboard.popped_key(exit, current, previous, repeat, chars, queue.pop(keys))

def Keyboard.popped_char(exit: U32, current: +List<U32>, previous: +List<U32>, repeat: +List<U32>, keys: +List<U32>, popped: +List<U32> & U32) -> Keyboard & U32:
  (chars, code) = popped
  (Keyboard{exit, current, previous, repeat, keys, chars}, code)

def Keyboard.pop_char(kb: Keyboard) -> Keyboard & U32:
  Keyboard{exit, current, previous, repeat, keys, chars} = kb
  Keyboard.popped_char(exit, current, previous, repeat, keys, queue.pop(chars))

# PollInputEvents (memory platform): previousKeyState = currentKeyState for keys
# 0..259 only (its "Android supports up to 260 keys" loop); keys 260..511 keep
# their previous state.
def Keyboard.previous.copy(current: +List<U32>, previous: +List<U32>, +index: U32) -> +List<U32>:
  match current previous:
    case Nil{} _: previous
    case _ Nil{}: Nil{}
    case Con{+c, crest} Con{+p, prest}:
      +word = Bool.pick(U32, (index < 8 : U32), c, Bool.pick(U32, U32.is_eq(index, 8), ((p .&. 4294967280) .|. (c .&. 15) : U32), p))
      Con{word, Keyboard.previous.copy(crest, prest, (index + 1 : U32))}

def Keyboard.poll(kb: Keyboard) -> Keyboard:
  Keyboard{exit, +current, previous, _, _, _} = kb
  Keyboard{exit, current, Keyboard.previous.copy(current, previous, 0), words(16n), Nil{}, Nil{}}

# Queries: keys outside 1..511 answer false.
def key.valid(+key: U32) -> Bool:
  ((key >= 1) && (key < 512) : U32)

def Keyboard.is_pressed(+kb: Keyboard, +key: U32) -> Bool:
  key.valid(key) && Bool.not(bits.get(Keyboard.previous(kb), key)) && bits.get(Keyboard.current(kb), key)

def Keyboard.is_pressed_repeat(+kb: Keyboard, +key: U32) -> Bool:
  key.valid(key) && bits.get(Keyboard.repeat(kb), key)

def Keyboard.is_down(+kb: Keyboard, +key: U32) -> Bool:
  key.valid(key) && bits.get(Keyboard.current(kb), key)

def Keyboard.is_released(+kb: Keyboard, +key: U32) -> Bool:
  key.valid(key) && bits.get(Keyboard.previous(kb), key) && Bool.not(bits.get(Keyboard.current(kb), key))

def Keyboard.is_up(+kb: Keyboard, +key: U32) -> Bool:
  key.valid(key) && Bool.not(bits.get(Keyboard.current(kb), key))

# rcore_desktop_glfw.c KeyCallback (action 0 release, 1 press, 2 repeat; mods as
# GLFW flags). Negative keys are ignored; other keys outside 0..511 are None.
def Keyboard.callback.lock(+key: U32, +mods: U32) -> Bool:
  (U32.is_eq(key, 280) && U32.is_eq((mods .&. 16 : U32), 16)) || (U32.is_eq(key, 282) && U32.is_eq((mods .&. 32 : U32), 32))

def Keyboard.callback.state(+action: U32, +lock: Bool, +current: +List<U32>, +key: U32) -> +List<U32>:
  +pressed = Bool.pick(+List<U32>, U32.is_eq(action, 1), bits.set(current, key, True{}), current)
  +released = Bool.pick(+List<U32>, U32.is_eq(action, 0), bits.set(current, key, False{}), pressed)
  Bool.pick(+List<U32>, lock, bits.set(released, key, True{}), released)

def Keyboard.callback(kb: Keyboard, +key: U32, +action: U32, +mods: U32) -> Keyboard:
  Keyboard{exit, current, previous, +repeat, keys, chars} = kb
  Keyboard{exit, Keyboard.callback.state(action, Keyboard.callback.lock(key, mods), current, key), previous,
    Bool.pick(+List<U32>, U32.is_eq(action, 2), bits.set(repeat, key, True{}), repeat), queue.push(U32.is_eq(action, 1), keys, key), chars}

# rcore_desktop_glfw.c CharCallback: queued while fewer than 16 are pending.
def Keyboard.char_callback(kb: Keyboard, +codepoint: U32) -> Keyboard:
  Keyboard{exit, current, previous, repeat, keys, chars} = kb
  Keyboard{exit, current, previous, repeat, keys, queue.push(True{}, chars, codepoint)}

# -----------------------------------------------------------------------------
# Mouse

def MouseState.buttons(+mouse: MouseState) -> U32:
  MouseState{_, _, _, _, _, _, buttons, _, _, _} = mouse
  buttons

def MouseState.previous_buttons(+mouse: MouseState) -> U32:
  MouseState{_, _, _, _, _, _, _, previous, _, _} = mouse
  previous

def MouseState.position(+mouse: MouseState) -> Point:
  MouseState{_, _, position, _, _, _, _, _, _, _} = mouse
  position

def MouseState.previous(+mouse: MouseState) -> Point:
  MouseState{_, _, _, previous, _, _, _, _, _, _} = mouse
  previous

def MouseState.wheel(+mouse: MouseState) -> Point:
  MouseState{_, _, _, _, _, _, _, _, wheel, _} = mouse
  wheel

def MouseState.previous_wheel(+mouse: MouseState) -> Point:
  MouseState{_, _, _, _, _, _, _, _, _, previous} = mouse
  previous

def MouseState.hidden(+mouse: MouseState) -> Bool:
  MouseState{_, _, _, _, hidden, _, _, _, _, _} = mouse
  hidden

def MouseState.on_screen(+mouse: MouseState) -> Bool:
  MouseState{_, _, _, _, _, on_screen, _, _, _, _} = mouse
  on_screen

def MouseState.set_button(mouse: MouseState, +button: U32, value: Bool) -> MouseState:
  MouseState{offset, scale, position, previous, hidden, on_screen, +buttons, previous_buttons, wheel, previous_wheel} = mouse
  MouseState{offset, scale, position, previous, hidden, on_screen, bit.with(value, buttons, button), previous_buttons, wheel, previous_wheel}

def MouseState.set_position(mouse: MouseState, position: Point) -> MouseState:
  MouseState{offset, scale, _, previous, hidden, on_screen, buttons, previous_buttons, wheel, previous_wheel} = mouse
  MouseState{offset, scale, position, previous, hidden, on_screen, buttons, previous_buttons, wheel, previous_wheel}

def MouseState.set_wheel(mouse: MouseState, wheel: Point) -> MouseState:
  MouseState{offset, scale, position, previous, hidden, on_screen, buttons, previous_buttons, _, previous_wheel} = mouse
  MouseState{offset, scale, position, previous, hidden, on_screen, buttons, previous_buttons, wheel, previous_wheel}

# SetMousePosition (memory platform): current and previous position.
def MouseState.move_to(mouse: MouseState, +x: U32, +y: U32) -> MouseState:
  MouseState{offset, scale, _, _, hidden, on_screen, buttons, previous_buttons, wheel, previous_wheel} = mouse
  +position = vector.ints(x, y)
  MouseState{offset, scale, position, position, hidden, on_screen, buttons, previous_buttons, wheel, previous_wheel}

def MouseState.set_offset(mouse: MouseState, +x: U32, +y: U32) -> MouseState:
  MouseState{_, scale, position, previous, hidden, on_screen, buttons, previous_buttons, wheel, previous_wheel} = mouse
  MouseState{vector.ints(x, y), scale, position, previous, hidden, on_screen, buttons, previous_buttons, wheel, previous_wheel}

def MouseState.set_scale(mouse: MouseState, +x: F32, +y: F32) -> MouseState:
  MouseState{offset, _, position, previous, hidden, on_screen, buttons, previous_buttons, wheel, previous_wheel} = mouse
  MouseState{offset, Point{x, y}, position, previous, hidden, on_screen, buttons, previous_buttons, wheel, previous_wheel}

def MouseState.set_hidden(mouse: MouseState, hidden: Bool) -> MouseState:
  MouseState{offset, scale, position, previous, _, on_screen, buttons, previous_buttons, wheel, previous_wheel} = mouse
  MouseState{offset, scale, position, previous, hidden, on_screen, buttons, previous_buttons, wheel, previous_wheel}

# (current + offset)*scale per axis.
def MouseState.screen(+mouse: MouseState) -> Point:
  MouseState{Point{ox, oy}, Point{sx, sy}, Point{px, py}, _, _, _, _, _, _, _} = mouse
  Point{((px + ox) * sx : F32), ((py + oy) * sy : F32)}

def MouseState.delta(+mouse: MouseState) -> Point:
  MouseState{_, Point{sx, sy}, Point{px, py}, Point{qx, qy}, _, _, _, _, _, _} = mouse
  Point{((px - qx) * sx : F32), ((py - qy) * sy : F32)}

def MouseState.wheel_move(+mouse: MouseState) -> F32:
  MouseState{_, _, _, _, _, _, _, _, Point{+x, +y}, _} = mouse
  Bool.pick(F32, (F32.abs(x) > F32.abs(y) : F32), x, y)

# -----------------------------------------------------------------------------
# Touch

def Touch.current(+touch: Touch) -> U32:
  Touch{_, _, _, _, current, _} = touch
  current

def Touch.previous(+touch: Touch) -> U32:
  Touch{_, _, _, _, _, previous} = touch
  previous

def Touch.count(+touch: Touch) -> U32:
  Touch{count, _, _, _, _, _} = touch
  count

def Touch.ids(+touch: Touch) -> +List<U32>:
  Touch{_, ids, _, _, _, _} = touch
  ids

def Touch.positions(+touch: Touch) -> +List<Point>:
  Touch{_, _, positions, _, _, _} = touch
  positions

def Touch.previous_positions(+touch: Touch) -> +List<Point>:
  Touch{_, _, _, previous, _, _} = touch
  previous

def Touch.set_state(touch: Touch, +id: U32, value: Bool) -> Touch:
  Touch{count, ids, positions, previous_positions, +current, previous} = touch
  Touch{count, ids, positions, previous_positions, bit.with(value, current, id), previous}

def Touch.set_position(touch: Touch, +id: U32, +x: U32, +y: U32) -> Touch:
  Touch{count, ids, positions, previous_positions, current, previous} = touch
  Touch{count, ids, List.set(&2, Point, positions, U32.to_nat(id), vector.ints(x, y)), previous_positions, current, previous}

def Touch.set_point(touch: Touch, +position: Point) -> Touch:
  Touch{count, ids, positions, previous_positions, current, previous} = touch
  Touch{count, ids, List.set(&2, Point, positions, 0n, position), previous_positions, current, previous}

def Touch.poll(touch: Touch) -> Touch:
  Touch{count, ids, positions, previous_positions, +current, _} = touch
  Touch{count, ids, positions, previous_positions, current, current}

# -----------------------------------------------------------------------------
# Gamepads

def Gamepads.ready(+pads: Gamepads) -> U32:
  Gamepads{_, _, ready, _, _, _} = pads
  ready

def Gamepads.last(+pads: Gamepads) -> U32:
  Gamepads{last, _, _, _, _, _} = pads
  last

def Gamepads.axis_counts(+pads: Gamepads) -> +List<U32>:
  Gamepads{_, counts, _, _, _, _} = pads
  counts

def Gamepads.current(+pads: Gamepads) -> +List<U32>:
  Gamepads{_, _, _, current, _, _} = pads
  current

def Gamepads.previous(+pads: Gamepads) -> +List<U32>:
  Gamepads{_, _, _, _, previous, _} = pads
  previous

def Gamepads.axes(+pads: Gamepads) -> +List<F32>:
  Gamepads{_, _, _, _, _, axes} = pads
  axes

def Gamepads.set_ready(pads: Gamepads, +gamepad: U32, value: Bool) -> Gamepads:
  Gamepads{last, counts, +ready, current, previous, axes} = pads
  Gamepads{last, counts, bit.with(value, ready, gamepad), current, previous, axes}

def Gamepads.set_button(pads: Gamepads, +gamepad: U32, +button: U32, value: Bool) -> Gamepads:
  Gamepads{last, counts, ready, +current, previous, axes} = pads
  +n = U32.to_nat(gamepad)
  Gamepads{last, counts, ready, List.set(&2, U32, current, n, bit.with(value, item(U32, current, n, 0), button)), previous, axes}

# INPUT_GAMEPAD_AXIS_MOTION: (float)delta/32768.0f.
def Gamepads.set_axis(pads: Gamepads, +gamepad: U32, +axis: U32, +delta: U32) -> Gamepads:
  Gamepads{last, counts, ready, current, previous, axes} = pads
  Gamepads{last, counts, ready, current, previous, List.set(&2, F32, axes, U32.to_nat((gamepad * 8 + axis : U32)), (int_to_f32(delta) / 32768.0 : F32))}

def Gamepads.poll(pads: Gamepads) -> Gamepads:
  Gamepads{_, counts, ready, current, previous, axes} = pads
  Gamepads{0, counts, ready, current, previous, axes}

def Gamepads.is_ready(+pads: Gamepads, +gamepad: U32) -> Bool:
  (gamepad < 4 : U32) && bit.of(Gamepads.ready(pads), gamepad)

def Gamepads.button(+list: +List<U32>, +gamepad: U32, +button: U32) -> Bool:
  bit.of(item(U32, list, U32.to_nat(gamepad), 0), button)

def Gamepads.axis(+pads: Gamepads, +gamepad: U32, +axis: U32) -> F32:
  item(F32, Gamepads.axes(pads), U32.to_nat((gamepad * 8 + axis : U32)), 0.0)

# -----------------------------------------------------------------------------
# Automation events with input state (PlayAutomationEvent, types 1..16)

def checked(valid: Bool, input: Input) -> Maybe<Input>:
  match valid:
    case False{}: None{}
    case True{}: Some{input}

def play.key(+down: Bool, +key: U32, +input: Input) -> Input:
  +kb = Input.keyboard(input)
  Input.with_keyboard(input, Bool.pick(Keyboard, down, Keyboard.press(kb, key), Keyboard.release(kb, key)))

def play.button(+down: Bool, +button: U32, +input: Input) -> Input:
  Input.with_mouse(input, MouseState.set_button(Input.mouse(input), button, down))

def play.position(+x: U32, +y: U32, +input: Input) -> Input:
  Input.with_mouse(input, MouseState.set_position(Input.mouse(input), vector.ints(x, y)))

def play.wheel(+x: U32, +y: U32, +input: Input) -> Input:
  Input.with_mouse(input, MouseState.set_wheel(Input.mouse(input), vector.ints(x, y)))

def play.ready(+value: Bool, +gamepad: U32, +input: Input) -> Input:
  Input.with_gamepads(input, Gamepads.set_ready(Input.gamepads(input), gamepad, value))

def play.pad_button(+value: Bool, +gamepad: U32, +button: U32, +input: Input) -> Input:
  Input.with_gamepads(input, Gamepads.set_button(Input.gamepads(input), gamepad, button, value))

def play.axis(+gamepad: U32, +axis: U32, +delta: U32, +input: Input) -> Input:
  Input.with_gamepads(input, Gamepads.set_axis(Input.gamepads(input), gamepad, axis, delta))

def play.touch(+value: Bool, +id: U32, +input: Input) -> Input:
  Input.with_touch(input, Touch.set_state(Input.touch(input), id, value))

def play.touch_position(+id: U32, +x: U32, +y: U32, +input: Input) -> Input:
  Input.with_touch(input, Touch.set_position(Input.touch(input), id, x, y))

# The input event types of PlayAutomationEvent; other types leave the input
# unchanged. Array indexes must be in range (C would write outside the arrays).
def play(+kind: U32, +p0: U32, +p1: U32, +p2: U32, input: Input) -> Maybe<Input>:
  match kind:
    case 1: checked((p0 < 512 : U32), play.key(False{}, p0, input))
    case 2: checked((p0 < 512 : U32), play.key(True{}, p0, input))
    case 5: checked((p0 < 8 : U32), play.button(False{}, p0, input))
    case 6: checked((p0 < 8 : U32), play.button(True{}, p0, input))
    case 7: Some{play.position(p0, p1, input)}
    case 8: Some{play.wheel(p0, p1, input)}
    case 9: checked((p0 < 4 : U32), play.ready(True{}, p0, input))
    case 10: checked((p0 < 4 : U32), play.ready(False{}, p0, input))
    case 11: checked(((p0 < 4) && (p1 < 32) : U32), play.pad_button(False{}, p0, p1, input))
    case 12: checked(((p0 < 4) && (p1 < 32) : U32), play.pad_button(True{}, p0, p1, input))
    case 13: checked(((p0 < 4) && (p1 < 8) : U32), play.axis(p0, p1, p2, input))
    case 14: checked((p0 < 8 : U32), play.touch(False{}, p0, input))
    case 15: checked((p0 < 8 : U32), play.touch(True{}, p0, input))
    case 16: checked((p0 < 8 : U32), play.touch_position(p0, p1, p2, input))
    case _: Some{input}

# PollInputEvents (memory platform) for the input state: queues emptied, key
# repeats and the last gamepad button cleared, previous touch states and keys
# 0..259 copied. The mouse and gamepad button "previous" states are not updated
# on this platform.
def poll(input: Input) -> Input:
  Input{keyboard, mouse, touch, gamepads} = input
  Input{Keyboard.poll(keyboard), mouse, Touch.poll(touch), Gamepads.poll(gamepads)}

# -----------------------------------------------------------------------------
# Desktop polling (src/platforms/rcore_desktop_glfw.c PollInputEvents, before
# glfwPollEvents runs the callbacks), for the desktop driver: queues emptied,
# previous key states copied for all 512 keys and repeats cleared, previous
# mouse buttons, wheel and position registered (the wheel move reset), previous
# touch states copied, touch point 0 moved to the mouse position, the last
# gamepad button cleared and no gamepad ready (glfwJoystickPresent is false:
# the driver has no gamepads, so no gamepad state is read).

def Keyboard.poll_desktop(kb: Keyboard) -> Keyboard:
  Keyboard{exit, +current, _, _, _, _} = kb
  Keyboard{exit, current, current, words(16n), Nil{}, Nil{}}

def MouseState.poll_desktop(mouse: MouseState) -> MouseState:
  MouseState{offset, scale, +position, _, hidden, on_screen, +buttons, _, +wheel, _} = mouse
  MouseState{offset, scale, position, position, hidden, on_screen, buttons, buttons, vector.zero(), wheel}

def Touch.poll_desktop(touch: Touch, +mouse: Point) -> Touch:
  Touch{count, ids, positions, previous_positions, +current, _} = touch
  Touch{count, ids, List.set(&2, Point, positions, 0n, mouse), previous_positions, current, current}

def Gamepads.poll_desktop(pads: Gamepads) -> Gamepads:
  Gamepads{_, counts, _, current, previous, axes} = pads
  Gamepads{0, counts, 0, current, previous, axes}

def poll_desktop.with(+mouse: MouseState, keyboard: Keyboard, touch: Touch, gamepads: Gamepads) -> Input:
  Input{Keyboard.poll_desktop(keyboard), MouseState.poll_desktop(mouse), Touch.poll_desktop(touch, MouseState.position(mouse)), Gamepads.poll_desktop(gamepads)}

def poll_desktop(input: Input) -> Input:
  Input{keyboard, +mouse, touch, gamepads} = input
  poll_desktop.with(mouse, keyboard, touch, gamepads)

# MouseButtonCallback's state: currentButtonState[button] and
# currentTouchState[button] = action (buttons 0..7).
def mouse_button_callback(input: Input, +button: U32, +down: Bool) -> Input:
  Input{keyboard, mouse, touch, gamepads} = input
  Input{keyboard, MouseState.set_button(mouse, button, down), Touch.set_state(touch, button, down), gamepads}

# MouseCursorPosCallback's state: currentPosition = (float)(x, y), touch
# point 0 at the same position.
def cursor_position_callback(input: Input, +position: Point) -> Input:
  Input{keyboard, mouse, touch, gamepads} = input
  Input{keyboard, MouseState.set_position(mouse, position), Touch.set_point(touch, position), gamepads}

# -----------------------------------------------------------------------------
# Queries

def mouse.valid(+button: U32) -> Bool:
  (button <= 6 : U32)

# IsMouseButtonPressed/Down/Released/Up: buttons 0..6 (MOUSE_BUTTON_BACK); a
# touch point with the same index counts as that button.
def mouse.pressed(+input: Input, +button: U32) -> Bool:
  +m = Input.mouse(input)
  +t = Input.touch(input)
  mouse.valid(button) && ((bit.of(MouseState.buttons(m), button) && Bool.not(bit.of(MouseState.previous_buttons(m), button)))
    || (bit.of(Touch.current(t), button) && Bool.not(bit.of(Touch.previous(t), button))))

def mouse.down(+input: Input, +button: U32) -> Bool:
  mouse.valid(button) && (bit.of(MouseState.buttons(Input.mouse(input)), button) || bit.of(Touch.current(Input.touch(input)), button))

def mouse.released(+input: Input, +button: U32) -> Bool:
  +m = Input.mouse(input)
  +t = Input.touch(input)
  mouse.valid(button) && ((Bool.not(bit.of(MouseState.buttons(m), button)) && bit.of(MouseState.previous_buttons(m), button))
    || (Bool.not(bit.of(Touch.current(t), button)) && bit.of(Touch.previous(t), button)))

def mouse.up(+input: Input, +button: U32) -> Bool:
  mouse.valid(button) && (Bool.not(bit.of(MouseState.buttons(Input.mouse(input)), button)) || Bool.not(bit.of(Touch.current(Input.touch(input)), button)))

# GetTouchPosition: indexes from 8 answer (-1, -1); negative indexes are None.
def touch.position(+input: Input, +index: U32) -> Maybe<Point>:
  Bool.pick(Maybe<Point>, negative(index), None{},
    Some{Bool.pick(Point, (index < 8 : U32), vector.at(Touch.positions(Input.touch(input)), index), Point{F32.neg(1.0), F32.neg(1.0)})})

# GetTouchPointId: indexes from 8 answer -1; negative indexes are None.
def touch.point_id(+input: Input, +index: U32) -> Maybe<U32>:
  Bool.pick(Maybe<U32>, negative(index), None{},
    Some{Bool.pick(U32, (index < 8 : U32), item(U32, Touch.ids(Input.touch(input)), U32.to_nat(index), 0), 4294967295)})

def gamepad.available(+input: Input, +gamepad: U32) -> Maybe<Bool>:
  Bool.pick(Maybe<Bool>, negative(gamepad), None{}, Some{Gamepads.is_ready(Input.gamepads(input), gamepad)})

# IsGamepadButton*: kind 0 pressed, 1 down, 2 released, 3 up. A negative gamepad,
# or a negative button of a ready gamepad, is None (raylib reads outside its
# arrays); buttons from 32 answer false.
def gamepad.answer(+kind: U32, +previous: Bool, +current: Bool) -> Bool:
  match kind:
    case 0: Bool.not(previous) && current
    case 1: current
    case 2: previous && Bool.not(current)
    case _: Bool.not(current)

def gamepad.ready_button(ready: Bool, +kind: U32, +pads: Gamepads, +gamepad: U32, +button: U32) -> Maybe<Bool>:
  match ready:
    case False{}: Some{False{}}
    case True{}:
      Bool.pick(Maybe<Bool>, negative(button), None{},
        Some{(button < 32 : U32) && gamepad.answer(kind, Gamepads.button(Gamepads.previous(pads), gamepad, button), Gamepads.button(Gamepads.current(pads), gamepad, button))})

def gamepad.button(+input: Input, +kind: U32, +gamepad: U32, +button: U32) -> Maybe<Bool>:
  +pads = Input.gamepads(input)
  Bool.pick(Maybe<Bool>, negative(gamepad), None{}, gamepad.ready_button(Gamepads.is_ready(pads, gamepad), kind, pads, gamepad, button))

# GetGamepadAxisCount reads axisCount[gamepad] unchecked: 0..3 only.
def gamepad.axis_count(+input: Input, +gamepad: U32) -> Maybe<U32>:
  Bool.pick(Maybe<U32>, (gamepad < 4 : U32), Some{item(U32, Gamepads.axis_counts(Input.gamepads(input)), U32.to_nat(gamepad), 0)}, None{})

# GetGamepadName: the (empty) name of gamepads 0..3.
def gamepad.name(+gamepad: U32) -> Maybe<String>:
  Bool.pick(Maybe<String>, (gamepad < 4 : U32), Some{""}, None{})

# GetGamepadAxisMovement: triggers (axes 4 and 5) rest at -1, other axes at 0;
# the axis value replaces the rest value when its movement (signed for
# triggers, absolute otherwise) is larger.
def gamepad.movement(+rest: F32, +value: F32) -> F32:
  +movement = Bool.pick(F32, (rest < 0.0 : F32), value, F32.abs(value))
  Bool.pick(F32, (movement > rest : F32), value, rest)

def gamepad.ready_axis(ready: Bool, +rest: F32, +pads: Gamepads, +gamepad: U32, +axis: U32) -> Maybe<F32>:
  match ready:
    case False{}: Some{rest}
    case True{}:
      Bool.pick(Maybe<F32>, negative(axis), None{},
        Some{Bool.pick(F32, (axis < 8 : U32), gamepad.movement(rest, Gamepads.axis(pads, gamepad, axis)), rest)})

def gamepad.rest(+axis: U32) -> F32:
  Bool.pick(F32, U32.is_eq(axis, 4) || U32.is_eq(axis, 5), F32.neg(1.0), 0.0)

def gamepad.axis_movement(+input: Input, +gamepad: U32, +axis: U32) -> Maybe<F32>:
  +pads = Input.gamepads(input)
  Bool.pick(Maybe<F32>, negative(gamepad), None{}, gamepad.ready_axis(Gamepads.is_ready(pads, gamepad), gamepad.rest(axis), pads, gamepad, axis))
