# raylib [core] example - storage values, ported to Jonlib.
# Adapted from raylib 6.2 examples/core/core_storage_values.c (zlib/libpng,
# Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# R draws a score and a high score, ENTER saves them in storage.data and
# SPACE loads them back. The file is read and written inside the loop, so
# the program is a J.Effects one (docs/DRIVER.md). SaveStorageValue and
# LoadStorageValue are the example's own functions over LoadFileData and
# SaveFileData: an int is four bytes in the reference hosts' order (little
# endian). Where they leave what C defines the frame is refused: a save
# that would write an int past the data it loaded or leave bytes it never
# set (a file whose size is neither the position's offset nor at least an
# int more; no file and a position above 0), and a load that would read an
# int past the data. raylib seeds the generator from time(NULL) in
# InitWindow; here the seed is a setup argument.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: no refusal so far. dir is the directory of storage.data; score and
# hiscore are C ints as their words; frames is framesCounter.
type State is Type:
  State{valid: Bool, dir: String, rng: J.Random.State, score: U32, hiscore: U32, frames: U32}

# What SaveStorageValue writes: Refused where the native code leaves what C defines.
type Stored is Data:
  Refused{}
  Stored{bytes: +List<U32>}

type Rolled is Type:
  Rolled{rng: J.Random.State, score: U32, hiscore: U32}

def file(+dir: String) -> String:
  dir ++ "storage.data"

def count(bytes: +List<U32>, +n: U32) -> U32:
  match bytes:
    case Nil{}: n
    case Con{_, rest}: count(rest, (n + 1 : U32))

# An int's four bytes.
def word.bytes(+value: U32) -> +List<U32>:
  [(value .&. 255 : U32), ((value >> 8n) .&. 255 : U32), ((value >> 16n) .&. 255 : U32), (value >> 24n : U32)]

def word.go(n: Nat, bytes: +List<U32>, +scale: U32, +acc: U32) -> U32:
  match n bytes:
    case 0n _: acc
    case 1n+_ Nil{}: acc
    case 1n+k Con{+b, rest}: word.go(k, rest, (scale * 256 : U32), (acc + b * scale : U32))

# dataPtr[position] of data that holds the int.
def word.at(+bytes: +List<U32>, +position: U32) -> U32:
  word.go(4n, List.drop(&2, U32, bytes, U32.to_nat((position * 4 : U32))), 1, 0)

# dataPtr[position] = value: the four bytes replaced, or added at the end.
def word.put(+bytes: +List<U32>, +position: U32, +value: U32) -> +List<U32>:
  List.append(&2, U32, List.take(&2, U32, bytes, U32.to_nat((position * 4 : U32))),
    List.append(&2, U32, word.bytes(value), List.drop(&2, U32, bytes, U32.to_nat((position * 4 + 4 : U32)))))

# LoadFileData: NULL (here no bytes) for a file that does not open or is empty.
def loaded(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> +List<U32>:
  match result:
    case Fail{_}: Nil{}
    case Done{+bytes}: bytes

# 0: refused; 1: a new file of one int (RL_MALLOC sets no byte before the
# position); 2: the int replaced, or added when the data ends at its offset
# (RL_REALLOC to position + 1 ints).
def save.kind(+n: U32, +position: U32) -> U32:
  Bool.pick(U32, U32.is_eq(n, 0), Bool.pick(U32, U32.is_eq(position, 0), 1, 0),
    Bool.pick(U32, U32.is_eq(n, (position * 4 : U32)) || (n >= (position * 4 + 4) : U32), 2, 0))

def save.new(kind: U32, +bytes: +List<U32>, +position: U32, +value: U32) -> Stored:
  match kind:
    case 0: Refused{}
    case 1: Stored{word.bytes(value)}
    case _: Stored{word.put(bytes, position, value)}

def storage.new(+bytes: +List<U32>, +position: U32, +value: U32) -> Stored:
  save.new(save.kind(count(bytes, 0), position), bytes, position, value)

# SaveFileData(STORAGE_DATA_FILE, newFileData, newDataSize); its answer is not used.
def storage.write(+dir: String, stored: Stored) -> IO(Bool):
  match stored:
    case Refused{}: IO.pure(Bool, False{})
    case Stored{+bytes}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Bool, J.Files.save_data(file(dir), bytes), written => IO.pure(Bool, True{}))

# SaveStorageValue(position, value): False where it is refused.
def storage.save(+dir: String, +position: U32, +value: U32) -> IO(Bool):
  IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Bool, J.Files.load_data(file(dir)), r => storage.write(dir, storage.new(loaded(r), position, value)))

# 0: refused (the int would be read past the data); 1: the value 0 (no
# file, or dataSize < position*4); 2: dataPtr[position].
def load.kind(+n: U32, +position: U32) -> U32:
  Bool.pick(U32, U32.is_eq(n, 0) || (n < (position * 4) : U32), 1, Bool.pick(U32, (n >= (position * 4 + 4) : U32), 2, 0))

def load.read(kind: U32, +bytes: +List<U32>, +position: U32) -> Maybe<U32>:
  match kind:
    case 0: None{}
    case 1: Some{0}
    case _: Some{word.at(bytes, position)}

def storage.read(+bytes: +List<U32>, +position: U32) -> Maybe<U32>:
  load.read(load.kind(count(bytes, 0), position), bytes, position)

# LoadStorageValue(position): None where it is refused.
def storage.load(+dir: String, +position: U32) -> IO(Maybe<U32>):
  IO.bind(Result<&1, &1, J.Surface.IOError, +List<U32>>, Maybe<U32>, J.Files.load_data(file(dir)), r => IO.pure(Maybe<U32>, storage.read(loaded(r), position)))

def rolled.second(+score: U32, r: J.Random.State & F32) -> Rolled:
  (rng, +hiscore) = r
  Rolled{rng, score, F32.to_u32(hiscore)}

def rolled.first(r: J.Random.State & F32) -> Rolled:
  (rng, +score) = r
  rolled.second(F32.to_u32(score), J.Random.value(rng, 2000.0, 4000.0))

# R: score = GetRandomValue(1000, 2000); hiscore = GetRandomValue(2000, 4000).
def rolled(pressed: Bool, rng: J.Random.State, +score: U32, +hiscore: U32) -> Rolled:
  match pressed:
    case False{}: Rolled{rng, score, hiscore}
    case True{}: rolled.first(J.Random.value(rng, 1000.0, 2000.0))

def update.done(+valid: Bool, +core: J.Core, +dir: String, rng: J.Random.State, +score: U32, +hiscore: U32, +frames: U32, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  IO.pure(J.Core & (State & J.Frame), (core, (State{valid, dir, rng, score, hiscore, frames}, frame)))

# SaveStorageValue(STORAGE_POSITION_HISCORE, hiscore).
def update.saved(first: Bool, +core: J.Core, +dir: String, rng: J.Random.State, +score: U32, +hiscore: U32, +frames: U32, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match first:
    case False{}: update.done(False{}, core, dir, rng, score, hiscore, frames, frame)
    case True{}: IO.bind(Bool, J.Core & (State & J.Frame), storage.save(dir, 1, hiscore), second => update.done(second, core, dir, rng, score, hiscore, frames, frame))

def update.loaded.second(value: Maybe<U32>, +core: J.Core, +dir: String, rng: J.Random.State, +score: U32, +hiscore: U32, +frames: U32, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match value:
    case None{}: update.done(False{}, core, dir, rng, score, hiscore, frames, frame)
    case Some{+v}: update.done(True{}, core, dir, rng, score, v, frames, frame)

# hiscore = LoadStorageValue(STORAGE_POSITION_HISCORE).
def update.loaded.first(value: Maybe<U32>, +core: J.Core, +dir: String, rng: J.Random.State, +score: U32, +hiscore: U32, +frames: U32, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match value:
    case None{}: update.done(False{}, core, dir, rng, score, hiscore, frames, frame)
    case Some{+v}: IO.bind(Maybe<U32>, J.Core & (State & J.Frame), storage.load(dir, 1), second => update.loaded.second(second, core, dir, rng, v, hiscore, frames, frame))

# 0: refused before; 1: no key; 2: ENTER, SaveStorageValue(STORAGE_POSITION_SCORE, score) and the high score;
# 3: SPACE, score = LoadStorageValue(STORAGE_POSITION_SCORE) and the high score.
def update.keys(kind: U32, +core: J.Core, +dir: String, rng: J.Random.State, +score: U32, +hiscore: U32, +frames: U32, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match kind:
    case 0: update.done(False{}, core, dir, rng, score, hiscore, frames, frame)
    case 1: update.done(True{}, core, dir, rng, score, hiscore, frames, frame)
    case 2: IO.bind(Bool, J.Core & (State & J.Frame), storage.save(dir, 0, score), first => update.saved(first, core, dir, rng, score, hiscore, frames, frame))
    case _: IO.bind(Maybe<U32>, J.Core & (State & J.Frame), storage.load(dir, 0), first => update.loaded.first(first, core, dir, rng, score, hiscore, frames, frame))

# ENTER saves, else SPACE loads; framesCounter++.
def update.rolled(+valid: Bool, +core: J.Core, +dir: String, +frames: U32, frame: J.Frame, r: Rolled) -> IO(J.Core & (State & J.Frame)):
  Rolled{rng, +score, +hiscore} = r
  update.keys(Bool.pick(U32, valid, Bool.pick(U32, J.Input.is_key_pressed(core, 257), 2, Bool.pick(U32, J.Input.is_key_pressed(core, 32), 3, 1)), 0), core, dir, rng, score, hiscore,
    (frames + 1 : U32), frame)

def update(+core: J.Core, state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  State{+valid, +dir, rng, +score, +hiscore, +frames} = state
  update.rolled(valid, core, dir, frames, frame, rolled(J.Input.is_key_pressed(core, 82), rng, score, hiscore))

# DrawText(TextFormat(format, value), x, y, size, color).
def label(value: Maybe<String>, frame: J.Frame, +x: F32, +y: F32, +height: F32, +color: U32) -> J.Frame:
  match value:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, x, y, height, color)

def texts(+score: U32, +hiscore: U32, +frames: U32, frame: J.Frame) -> J.Frame:
  f1 = label(J.Text.format("SCORE: %i", [J.TextInt{score}]), J.Frame.clear_background(frame, J.Color.RAYWHITE()), 280.0, 130.0, 40.0, J.Color.MAROON())
  f2 = label(J.Text.format("HI-SCORE: %i", [J.TextInt{hiscore}]), f1, 210.0, 200.0, 50.0, J.Color.BLACK())
  f3 = label(J.Text.format("frames: %i", [J.TextInt{frames}]), f2, 10.0, 10.0, 20.0, J.Color.LIME())
  f4 = J.Draw.text(f3, "Press R to generate random numbers", 220.0, 40.0, 20.0, J.Color.LIGHTGRAY())
  f5 = J.Draw.text(f4, "Press ENTER to SAVE values", 250.0, 310.0, 20.0, J.Color.LIGHTGRAY())
  J.Draw.text(f5, "Press SPACE to LOAD values", 252.0, 350.0, 20.0, J.Color.LIGHTGRAY())

def draw.at(valid: Bool, +score: U32, +hiscore: U32, +frames: U32, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: J.Frame.refuse(frame)
    case True{}: texts(score, hiscore, frames, frame)

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +dir, rng, +score, +hiscore, +frames} = state
  (core, (State{valid, dir, rng, score, hiscore, frames}, draw.at(valid, score, hiscore, frames, frame)))

# No libm call: the profile argument is the examples' common signature. Nothing follows EndDrawing in the loop.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Effects{core => state => frame => update(core, state, frame), core => state => frame => draw(core, state, frame),
    core => state => frame => IO.pure(J.Core & (State & J.Frame), (core, (state, frame)))}

# After InitWindow(800, 450) and SetRandomSeed(seed): score, hiscore and framesCounter 0, SetTargetFPS(60).
def setup(+seed: U32, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.pure(J.Core & (J.Frame & State), (J.Core.set_target_fps(core, 60), (frame, State{True{}, dir, J.Random.seed(seed), 0, 0, 0})))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - storage values", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup(0, "", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
