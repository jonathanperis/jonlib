# raylib [core] example - drop files, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_drop_files.c (zlib/libpng,
# Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Lists the paths of files dropped on the window. Neither the memory platform
# nor Base's windows deliver dropped files (J.Core.is_file_dropped is always
# false), so the list stays empty; the program keeps raylib's logic for it
# (MAX_FILEPATH_RECORDED 4096 paths). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{paths: +List<String>, count: U32}

def float(+word: U32) -> F32:
  U32{bits} = word
  F32{bits}

def append(paths: +List<String>, +path: String) -> +List<String>:
  match paths:
    case Nil{}: [path]
    case Con{+p, rest}: Con{p, append(rest, path)}

def record(room: Bool, +paths: +List<String>, +count: U32, +path: String) -> +List<String> & U32:
  match room:
    case True{}: (append(paths, path), (count + 1 : U32))
    case False{}: (paths, count)

def record.pair(kept: +List<String> & U32, +path: String) -> +List<String> & U32:
  (+paths, +count) = kept
  record((count < 4095 : U32), paths, count, path)

# Appends the dropped paths while fewer than MAX_FILEPATH_RECORDED - 1 are
# recorded (TextCopy into the preallocated 2048-byte slots keeps paths below
# that size; longer ones would overflow raylib's buffers and are not
# expected from a platform).
def recorded(dropped: +List<String>, kept: +List<String> & U32) -> +List<String> & U32:
  match dropped:
    case Nil{}: kept
    case Con{+path, rest}: recorded(rest, record.pair(kept, path))

def update.recorded(+core: J.Core, +files: J.FilePathList, kept: +List<String> & U32) -> J.Core & State:
  (+paths, +count) = kept
  (J.Core.unload_dropped_files(core, files), State{paths, count})

def update.dropped(+core: J.Core, +paths: +List<String>, +count: U32, +files: J.FilePathList) -> J.Core & State:
  J.FilePathList{_, +dropped} = files
  update.recorded(core, files, recorded(dropped, (paths, count)))

def update.check(dropped: Bool, +core: J.Core, +paths: +List<String>, +count: U32) -> J.Core & State:
  match dropped:
    case True{}: update.dropped(core, paths, count, J.Core.load_dropped_files(core))
    case False{}: (core, State{paths, count})

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+paths, +count} = state
  update.check(J.Core.is_file_dropped(core), core, paths, count)

# One recorded path on its band: Fade(LIGHTGRAY, 0.5f) for even rows, 0.3f odd.
def draw.paths(paths: +List<String>, +i: U32, frame: J.Frame) -> J.Frame:
  match paths:
    case Nil{}: frame
    case Con{+path, rest}:
      +y = U32.to_f32((85 + 40 * i : U32))
      +alpha = Bool.pick(F32, U32.is_eq((i % 2 : U32), 0), 0.5, float(1050253722))
      f1 = J.Draw.rectangle(frame, 0.0, y, 800.0, 40.0, J.Color.with_alpha(J.Color.LIGHTGRAY(), alpha))
      draw.paths(rest, (i + 1 : U32), J.Draw.text(f1, path, 120.0, U32.to_f32((100 + 40 * i : U32)), 10.0, J.Color.GRAY()))

def draw.list(empty: Bool, +paths: +List<String>, +count: U32, frame: J.Frame) -> J.Frame:
  match empty:
    case True{}: J.Draw.text(frame, "Drop your files to this window!", 100.0, 40.0, 20.0, J.Color.DARKGRAY())
    case False{}:
      f1 = J.Draw.text(frame, "Dropped files:", 100.0, 40.0, 20.0, J.Color.DARKGRAY())
      f2 = draw.paths(paths, 0, f1)
      J.Draw.text(f2, "Drop new files...", 100.0, U32.to_f32((110 + 40 * count : U32)), 20.0, J.Color.DARKGRAY())

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+paths, +count} = state
  (core, (State{paths, count}, draw.list(U32.is_eq(count, 0), paths, count, J.Frame.clear_background(frame, J.Color.RAYWHITE()))))

# The main loop's body; libm is the sinf/cosf profile (unused here).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): no recorded paths, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{Nil{}, 0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - drop files", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
