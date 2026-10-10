# raylib [core] example - undo redo, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_undo_redo.c (zlib/libpng,
# Copyright (c) 2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# A player moved on a grid by the arrows and recolored by SPACE, its states
# recorded every second frame in a ring of 26 undo slots; CTRL+Z steps back
# and CTRL+Y forward. The ring and the cells of the earlier states are drawn
# with the example's ranges. raylib seeds GetRandomValue from time(NULL) in
# InitWindow; here the seed is a setup argument (docs/DRIVER.md).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# PlayerState: the cell and the color.
type Player is Data:
  Player{x: U32, y: U32, color: U32}

# current, first, last: the undo indices; counter: undoFrameCounter.
type Undo is Data:
  Undo{player: Player, states: +List<Player>, current: U32, first: U32, last: U32, counter: U32}

type State is Type:
  State{rng: J.Random.State, undo: Undo}

def same(+a: Player, +b: Player) -> Bool:
  Player{+ax, +ay, +ac} = a
  Player{+bx, +by, +bc} = b
  U32.is_eq(ax, bx) && U32.is_eq(ay, by) && U32.is_eq(ac, bc)

def head(states: +List<Player>) -> Player:
  match states:
    case Con{+p, _}: p
    case Nil{}: Player{0, 0, 0}

def at(+states: +List<Player>, +index: U32) -> Player:
  head(List.drop(&2, Player, states, U32.to_nat(index)))

def put(states: +List<Player>, index: Nat, +player: Player) -> +List<Player>:
  match states index:
    case Nil{} _: Nil{}
    case Con{_, rest} 0n: Con{player, rest}
    case Con{+first, rest} 1n+p: Con{first, put(rest, p, player)}

# Every second frame a changed player takes the next slot of the ring (pushing the first one on when full).
def recorded(+undo: Undo) -> Undo:
  Undo{+player, +states, +current, +first, +last, +counter} = undo
  +tick = ((counter + 1) >= 2 : U32)
  +changed = tick && Bool.not(same(at(states, current), player))
  +next = Bool.pick(U32, ((current + 1) >= 26 : U32), 0, (current + 1 : U32))
  +pushed = Bool.pick(U32, U32.is_eq(next, first), (first + 1 : U32), first)
  Undo{player, Bool.pick(+List<Player>, changed, put(states, U32.to_nat(next), player), states), Bool.pick(U32, changed, next, current),
    Bool.pick(U32, changed, Bool.pick(U32, (pushed >= 26 : U32), 0, pushed), first), Bool.pick(U32, changed, next, last), Bool.pick(U32, tick, 0, (counter + 1 : U32))}

# CTRL+Z: back one slot (not past the first), the player restored.
def undone(+pressed: Bool, +undo: Undo) -> Undo:
  Undo{+player, +states, +current, +first, +last, +counter} = undo
  +back = Bool.pick(U32, U32.is_eq(current, 0), 25, (current - 1 : U32))
  Bool.pick(Undo, pressed && Bool.not(U32.is_eq(current, first)), Undo{at(states, back), states, back, first, last, counter}, undo)

# CTRL+Y: forward one slot (not past the last, nor onto the first), the player restored.
def redone(+pressed: Bool, +undo: Undo) -> Undo:
  Undo{+player, +states, +current, +first, +last, +counter} = undo
  +next = Bool.pick(U32, ((current + 1) >= 26 : U32), 0, (current + 1 : U32))
  Bool.pick(Undo, pressed && Bool.not(U32.is_eq(current, last)) && Bool.not(U32.is_eq(next, first)), Undo{at(states, next), states, next, first, last, counter}, undo)

# RIGHT, else LEFT, else UP, else DOWN moves a cell, inside the 30x13 grid.
def moved(+core: J.Core, +player: Player) -> Player:
  Player{+x, +y, +color} = player
  +right = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT())
  +left = Bool.not(right) && J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT())
  +up = Bool.not(right) && Bool.not(left) && J.Input.is_key_pressed(core, J.KeyboardKey.KEY_UP())
  +down = Bool.not(right) && Bool.not(left) && Bool.not(up) && J.Input.is_key_pressed(core, J.KeyboardKey.KEY_DOWN())
  Player{Bool.pick(U32, right, U32.min((x + 1 : U32), 29), Bool.pick(U32, left && (x > 0 : U32), (x - 1 : U32), x)),
    Bool.pick(U32, down, U32.min((y + 1 : U32), 12), Bool.pick(U32, up && (y > 0 : U32), (y - 1 : U32), y)), color}

def stepped(+core: J.Core, +undo: Undo, +player: Player) -> Undo:
  Undo{_, +states, +current, +first, +last, +counter} = undo
  +control = J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT_CONTROL())
  redone(control && J.Input.is_key_pressed(core, J.KeyboardKey.KEY_Y()), undone(control && J.Input.is_key_pressed(core, J.KeyboardKey.KEY_Z()),
    recorded(Undo{player, states, current, first, last, counter})))

def color.blue(+core: J.Core, +undo: Undo, +x: U32, +y: U32, +r: U32, +g: U32, draw: J.Random.State & F32) -> State:
  (rng, +b) = draw
  State{rng, stepped(core, undo, Player{x, y, J.Color.rgba(r, g, F32.to_u32(b), 255)})}

def color.green(+core: J.Core, +undo: Undo, +x: U32, +y: U32, +r: U32, draw: J.Random.State & F32) -> State:
  (rng, +g) = draw
  color.blue(core, undo, x, y, r, F32.to_u32(g), J.Random.value(rng, 20.0, 240.0))

def color.red(+core: J.Core, +undo: Undo, +x: U32, +y: U32, draw: J.Random.State & F32) -> State:
  (rng, +r) = draw
  color.green(core, undo, x, y, F32.to_u32(r), J.Random.value(rng, 20.0, 220.0))

def colored.at(+core: J.Core, +undo: Undo, +player: Player, rng: J.Random.State) -> State:
  Player{+x, +y, _} = player
  color.red(core, undo, x, y, J.Random.value(rng, 20.0, 255.0))

# SPACE: color.r = GetRandomValue(20, 255); color.g = GetRandomValue(20, 220); color.b = GetRandomValue(20, 240).
def colored(recolor: Bool, +core: J.Core, +undo: Undo, +player: Player, rng: J.Random.State) -> State:
  match recolor:
    case False{}: State{rng, stepped(core, undo, player)}
    case True{}: colored.at(core, undo, player, rng)

def update(+core: J.Core, state: State) -> J.Core & State:
  State{rng, +undo} = state
  Undo{+player, _, _, _, _, _} = undo
  (core, colored(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), core, undo, moved(core, player), rng))

def trail.cell(+player: Player, frame: J.Frame) -> J.Frame:
  Player{+x, +y, _} = player
  J.Draw.rectangle(frame, U32.to_f32((40 + x * 24 : U32)), U32.to_f32((60 + y * 24 : U32)), 24.0, 24.0, J.Color.LIGHTGRAY())

# The cells of the states i..i + n - 1 in LIGHTGRAY.
def trail(n: Nat, +i: U32, +states: +List<Player>, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: trail(p, (i + 1 : U32), states, trail.cell(at(states, i), frame))

def span(+from: U32, +to: U32) -> Nat:
  U32.to_nat(Bool.pick(U32, (to > from : U32), (to - from : U32), 0))

# The earlier states' cells, by the example's three cases of the ring.
def trails(+undo: Undo, frame: J.Frame) -> J.Frame:
  Undo{_, +states, +current, +first, +last, _} = undo
  +plain = (last > first : U32) || ((first > last : U32) && (current < 26 : U32) && (current > last : U32))
  +wrapped = (first > last : U32) && Bool.not((current < 26 : U32) && (current > last : U32))
  trail(Bool.pick(Nat, wrapped, span(0, current), 0n), 0, states, trail(Bool.pick(Nat, plain, span(first, current), Bool.pick(Nat, wrapped, span(first, 26), 0n)), first, states, frame))

def rows(n: Nat, +y: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: rows(p, (y + 1 : U32), J.Draw.line(frame, 40.0, U32.to_f32((60 + y * 24 : U32)), U32.to_f32((40 + 30 * 24 : U32)), U32.to_f32((60 + y * 24 : U32)), J.Color.GRAY()))

def columns(n: Nat, +x: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: columns(p, (x + 1 : U32), J.Draw.line(frame, U32.to_f32((40 + x * 24 : U32)), 60.0, U32.to_f32((40 + x * 24 : U32)), U32.to_f32((60 + 13 * 24 : U32)), J.Color.GRAY()))

# n slots of the undo buffer from i: a filled square and its outline.
def slots(n: Nat, +i: U32, +fill: U32, +line: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: slots(p, (i + 1 : U32), fill, line, J.Draw.rectangle_lines(J.Draw.rectangle(frame, U32.to_f32((110 + 24 * i : U32)), 400.0, 24.0, 24.0, fill),
      U32.to_f32((110 + 24 * i : U32)), 400.0, 24.0, 24.0, line))

# DrawUndoBuffer((110, 400), first, last, current, 24).
def buffer(+undo: Undo, frame: J.Frame) -> J.Frame:
  Undo{_, _, +current, +first, +last, _} = undo
  f1 = J.Draw.rectangle(frame, U32.to_f32((110 + 8 + 24 * current : U32)), 390.0, 8.0, 8.0, J.Color.RED())
  f2 = J.Draw.rectangle_lines(f1, U32.to_f32((110 + 2 + 24 * first : U32)), 427.0, 8.0, 8.0, J.Color.BLACK())
  f3 = slots(26n, 0, J.Color.LIGHTGRAY(), J.Color.GRAY(), J.Draw.rectangle(f2, U32.to_f32((110 + 14 + 24 * last : U32)), 427.0, 8.0, 8.0, J.Color.BLACK()))
  +whole = (first <= last : U32)
  f4 = slots(Bool.pick(Nat, whole, 0n, span(0, (last + 1 : U32))), 0, J.Color.SKYBLUE(), J.Color.BLUE(),
    slots(Bool.pick(Nat, whole, span(first, (last + 1 : U32)), span(first, 26)), first, J.Color.SKYBLUE(), J.Color.BLUE(), f3))
  +behind = (first < current : U32)
  +around = (current < first : U32)
  f5 = slots(Bool.pick(Nat, around, span(0, current), 0n), 0, J.Color.GREEN(), J.Color.LIME(),
    slots(Bool.pick(Nat, behind, span(first, current), Bool.pick(Nat, around, span(first, 26), 0n)), first, J.Color.GREEN(), J.Color.LIME(), f4))
  slots(1n, current, J.Color.GOLD(), J.Color.ORANGE(), f5)

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{rng, +undo} = state
  Undo{+player, _, _, _, _, _} = undo
  Player{+x, +y, +color} = player
  f1 = J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "[ARROWS] MOVE PLAYER - [SPACE] CHANGE PLAYER COLOR", 40.0, 20.0, 20.0, J.Color.DARKGRAY())
  f2 = columns(31n, 0, rows(14n, 0, trails(undo, f1)))
  f3 = J.Draw.rectangle(f2, U32.to_f32((40 + x * 24 : U32)), U32.to_f32((60 + y * 24 : U32)), 25.0, 25.0, color)
  (core, (State{rng, undo}, buffer(undo, J.Draw.text(f3, "UNDO STATES:", (110.0 - 85.0 : F32), (400.0 + 9.0 : F32), 10.0, J.Color.DARKGRAY()))))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def filled(n: Nat, +player: Player) -> +List<Player>:
  match n:
    case 0n: Nil{}
    case 1n+p: Con{player, filled(p, player)}

# After InitWindow(800, 450) and SetRandomSeed(seed): the red player at (10, 10) in every undo slot, SetTargetFPS(60).
def setup(+seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{J.Random.seed(seed), Undo{Player{10, 10, J.Color.RED()}, filled(26n, Player{10, 10, J.Color.RED()}), 0, 0, 0, 0}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - undo redo", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
