# raylib [core] example - random sequence, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_random_sequence.c (zlib/libpng,
# Copyright (c) 2023-2025 Dalton Overmyer (@REDl3east)); see
# LICENSES/raylib.txt.
#
# Bars of random colors whose heights are a random permutation
# (LoadRandomSequence) remapped to the screen; SPACE shuffles colors and
# heights through another sequence, UP and DOWN regenerate with one bar more
# or fewer. raylib seeds GetRandomValue from time(NULL) in InitWindow; here
# the seed is a setup argument (docs/DRIVER.md). GenerateRandomColor's three
# GetRandomValue calls run in clang's left-to-right initializer order. A
# sequence that does not complete within the draw budget refuses the frame.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Cell is Data:
  Cell{color: U32, rect: J.Rectangle}

type Loaded is Data:
  Loaded{valid: Bool, values: +List<F32>}

type State is Type:
  State{valid: Bool, rng: J.Random.State, cells: +List<Cell>, count: U32}

# LoadRandomSequence(count, 0, count - 1): the draws rprand makes until every value is out.
def sequence(rng: J.Random.State, +count: U32) -> J.Random.State & Result<&1, &1, J.Random.Sequence.Error, J.Random.Sequence>:
  J.Random.load_sequence(rng, count, 0.0, U32.to_f32((count - 1 : U32)), U32.to_nat(65536))

def loaded(result: Result<&1, &1, J.Random.Sequence.Error, J.Random.Sequence>) -> Loaded:
  match result:
    case Fail{_}: Loaded{False{}, Nil{}}
    case Done{sequence}: Loaded{True{}, J.Random.Sequence.values(sequence)}

# rectHeight = (int)Remap(seq[i], 0, rectCount - 1, 0, 0.75f*screenHeight); the
# bar stands on that line, rectSize = screenWidth/rectCount wide, the row centered.
def rect(+value: F32, +i: U32, +count: U32) -> J.Rectangle:
  +n = U32.to_f32(count)
  +width = (800.0 / n : F32)
  +start = ((800.0 - n * width) * 0.5 : F32)
  +height = F32.trunc(M.Math.remap(value, 0.0, (n - 1.0 : F32), 0.0, (0.75 * 450.0 : F32)))
  J.Rectangle{(start + U32.to_f32(i) * width : F32), ((0.75 * 450.0) - height : F32), width, height}

def cells.blue(+rect: J.Rectangle, +r: U32, +g: U32, done: +List<Cell>, draw: J.Random.State & F32) -> J.Random.State & +List<Cell>:
  (rng, +b) = draw
  (rng, Con{Cell{J.Color.rgba(r, g, F32.to_u32(b), 255), rect}, done})

def cells.green(+rect: J.Rectangle, +r: U32, done: +List<Cell>, draw: J.Random.State & F32) -> J.Random.State & +List<Cell>:
  (rng, +g) = draw
  cells.blue(rect, r, F32.to_u32(g), done, J.Random.value(rng, 0.0, 255.0))

def cells.red(+rect: J.Rectangle, done: +List<Cell>, draw: J.Random.State & F32) -> J.Random.State & +List<Cell>:
  (rng, +r) = draw
  cells.green(rect, F32.to_u32(r), done, J.Random.value(rng, 0.0, 255.0))

# GenerateRandomColor: GetRandomValue(0, 255) for red, green and blue.
def cells.one(+rect: J.Rectangle, acc: J.Random.State & +List<Cell>) -> J.Random.State & +List<Cell>:
  (rng, done) = acc
  cells.red(rect, done, J.Random.value(rng, 0.0, 255.0))

# The bars in order; they come back newest first.
def cells(values: +List<F32>, +i: U32, +count: U32, acc: J.Random.State & +List<Cell>) -> J.Random.State & +List<Cell>:
  match values:
    case Nil{}: acc
    case Con{+value, rest}: cells(rest, (i + 1 : U32), count, cells.one(rect(value, i, count), acc))

def generate.done(+valid: Bool, +count: U32, r: J.Random.State & +List<Cell>) -> State:
  (rng, reversed) = r
  State{valid, rng, List.reverse(&2, Cell, reversed), count}

def generate.values(+count: U32, rng: J.Random.State, +loaded: Loaded) -> State:
  Loaded{+valid, +values} = loaded
  generate.done(valid, count, cells(values, 0, count, (rng, Nil{})))

def generate.loaded(+count: U32, r: J.Random.State & Result<&1, &1, J.Random.Sequence.Error, J.Random.Sequence>) -> State:
  (rng, result) = r
  generate.values(count, rng, loaded(result))

# GenerateRandomColorRectSequence.
def generate(rng: J.Random.State, +count: U32) -> State:
  generate.loaded(count, sequence(rng, count))

def nth.head(cells: +List<Cell>) -> Cell:
  match cells:
    case Con{+cell, _}: cell
    case Nil{}: Cell{0, J.Rectangle{0.0, 0.0, 0.0, 0.0}}

def nth(+cells: +List<Cell>, +index: U32) -> Cell:
  nth.head(List.drop(&2, Cell, cells, U32.to_nat(index)))

def put(cells: +List<Cell>, index: Nat, +cell: Cell) -> +List<Cell>:
  match cells index:
    case Nil{} _: Nil{}
    case Con{_, rest} 0n: Con{cell, rest}
    case Con{+head, rest} 1n+p: Con{head, put(rest, p, cell)}

# The color, height and y of other on self's x and width.
def taking(+self: Cell, +other: Cell) -> Cell:
  Cell{_, +mine} = self
  J.Rectangle{+x, _, +w, _} = mine
  Cell{+color, +theirs} = other
  J.Rectangle{_, +y, _, +h} = theirs
  Cell{color, J.Rectangle{x, y, w, h}}

def swapped(+cells: +List<Cell>, +i: U32, +j: U32) -> +List<Cell>:
  put(put(cells, U32.to_nat(i), taking(nth(cells, i), nth(cells, j))), U32.to_nat(j), taking(nth(cells, j), nth(cells, i)))

# for (i1 = 0; i1 < rectCount; i1++) swap rectangles[i1] and rectangles[seq[i1]].
def shuffled(values: +List<F32>, +i: U32, +cells: +List<Cell>) -> +List<Cell>:
  match values:
    case Nil{}: cells
    case Con{+value, rest}: shuffled(rest, (i + 1 : U32), swapped(cells, i, F32.to_u32(value)))

def shuffle.values(+cells: +List<Cell>, +count: U32, rng: J.Random.State, +loaded: Loaded) -> State:
  Loaded{+valid, +values} = loaded
  State{valid, rng, shuffled(values, 0, cells), count}

def shuffle.loaded(+cells: +List<Cell>, +count: U32, r: J.Random.State & Result<&1, &1, J.Random.Sequence.Error, J.Random.Sequence>) -> State:
  (rng, result) = r
  shuffle.values(cells, count, rng, loaded(result))

# ShuffleColorRectSequence.
def shuffle(pressed: Bool, state: State) -> State:
  match pressed:
    case False{}: state
    case True{}:
      State{_, rng, +cells, +count} = state
      shuffle.loaded(cells, count, sequence(rng, count))

# UP: one bar more, a new sequence.
def grow(pressed: Bool, state: State) -> State:
  match pressed:
    case False{}: state
    case True{}:
      State{_, rng, _, +count} = state
      generate(rng, (count + 1 : U32))

# DOWN: one bar fewer while there are four or more.
def shrink(pressed: Bool, state: State) -> State:
  match pressed:
    case False{}: state
    case True{}:
      State{_, rng, _, +count} = state
      generate(rng, (count - 1 : U32))

def count(state: State) -> State & U32:
  State{+valid, rng, +cells, +count} = state
  (State{valid, rng, cells, count}, count)

def update.down(+core: J.Core, r: State & U32) -> J.Core & State:
  (state, +count) = r
  (core, shrink(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_DOWN()) && (count >= 4 : U32), state))

def update(+core: J.Core, state: State) -> J.Core & State:
  update.down(core, count(grow(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_UP()), shuffle(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), state))))

# DrawRectangleRec, then the three help lines (the example draws them once a bar).
def bar(+cell: Cell, frame: J.Frame) -> J.Frame:
  Cell{+color, +rect} = cell
  f1 = J.Draw.text(J.Draw.rectangle_rec(frame, rect, color), "Press SPACE to shuffle the current sequence", 10.0, (450.0 - 96.0 : F32), 20.0, J.Color.BLACK())
  f2 = J.Draw.text(f1, "Press UP to add a rectangle and generate a new sequence", 10.0, (450.0 - 64.0 : F32), 20.0, J.Color.BLACK())
  J.Draw.text(f2, "Press DOWN to remove a rectangle and generate a new sequence", 10.0, (450.0 - 32.0 : F32), 20.0, J.Color.BLACK())

def bars(cells: +List<Cell>, frame: J.Frame) -> J.Frame:
  match cells:
    case Nil{}: frame
    case Con{+cell, rest}: bars(rest, bar(cell, frame))

def label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, 10.0, 20.0, J.Color.MAROON())

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, (800.0 - 80.0 : F32), 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.valid(valid: Bool, +core: J.Core, rng: J.Random.State, +cells: +List<Cell>, +count: U32, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid:
    case False{}: (core, (State{False{}, rng, cells, count}, J.Frame.refuse(frame)))
    case True{}: draw.fps.done(State{True{}, rng, cells, count},
      label(J.Text.format("Count: %d rectangles", [J.TextInt{count}]), bars(cells, J.Frame.clear_background(frame, J.Color.RAYWHITE()))),
      J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, rng, +cells, +count} = state
  draw.valid(valid, core, rng, cells, count, frame)

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450) and SetRandomSeed(seed): twenty bars, SetTargetFPS(60).
def setup(+seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, generate(J.Random.seed(seed), 20)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - random sequence", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
