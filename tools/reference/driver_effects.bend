# The loop of tools/reference/driver_effects.c as a J.Effects program
# (tools/effects_probe.py): the update writes and reads a file, `after`
# writes it once EndDrawing is over.
import Base
import ../../jonlib.bend as J
import ../../jonmath.bend as M

# The directory of effects.txt, the frames so far, the counter S wrote, the
# number L read and the counter of the last write after EndDrawing.
type State is Data:
  State{dir: String, counter: U32, saved: U32, loaded: U32, late: U32}

def file(+state: State) -> String:
  State{dir, _, _, _, _} = state
  dir ++ "effects.txt"

def counted(+state: State) -> State:
  State{dir, counter, saved, loaded, late} = state
  State{dir, (counter + 1 : U32), saved, loaded, late}

def counter.of(+state: State) -> U32:
  State{_, counter, _, _, _} = state
  counter

def with.saved(+state: State) -> State:
  State{dir, +counter, _, loaded, late} = state
  State{dir, counter, counter, loaded, late}

def with.loaded(+state: State, +value: U32) -> State:
  State{dir, counter, saved, _, late} = state
  State{dir, counter, saved, value, late}

def with.late(+state: State) -> State:
  State{dir, +counter, saved, loaded, _} = state
  State{dir, counter, saved, loaded, counter}

def done(+core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  IO.pure(J.Core & (State & J.Frame), (core, (state, frame)))

def number(value: Maybe<&2, U32>) -> U32:
  match value:
    case None{}: 0
    case Some{n}: n

# atoi of the text, 0 without a file.
def read(result: Result<&1, &1, J.Surface.IOError, String>) -> U32:
  match result:
    case Fail{_}: 0
    case Done{text}: number(U32.read(text))

# L: loaded = atoi(LoadFileText("effects.txt")).
def update.load(pressed: Bool, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match pressed:
    case False{}: done(core, state, frame)
    case True{}: IO.bind(Result<&1, &1, J.Surface.IOError, String>, J.Core & (State & J.Frame), J.Files.load_text(file(state)), r => done(core, with.loaded(state, read(r)), frame))

# S: SaveFileText("effects.txt", TextFormat("%i", counter)); saved = counter.
def update.save(pressed: Bool, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match pressed:
    case False{}: update.load(J.Input.is_key_pressed(core, 76), core, state, frame)
    case True{}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, J.Core & (State & J.Frame), J.Files.save_text(file(state), U32.show(counter.of(state))),
      r => update.load(J.Input.is_key_pressed(core, 76), core, with.saved(state), frame))

def update(+core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  update.save(J.Input.is_key_pressed(core, 83), core, counted(state), frame)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{dir, +counter, +saved, +loaded, +late} = state
  (core, (State{dir, counter, saved, loaded, late}, J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()),
    U32.show(counter) ++ " " ++ U32.show(saved) ++ " " ++ U32.show(loaded) ++ " " ++ U32.show(late), 10.0, 10.0, 20.0, J.Color.DARKGRAY())))

def after.down(down: Bool, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match down:
    case False{}: done(core, state, frame)
    case True{}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, J.Core & (State & J.Frame), J.Files.save_text(file(state), U32.show((counter.of(state) + 1000 : U32))),
      r => done(core, with.late(state), frame))

# After EndDrawing: F still down writes counter + 1000; late = counter.
def after(+core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  after.down(J.Input.is_key_down(core, 70), core, state, frame)

def program(+libm: M.Libm) -> J.Program<State>:
  J.Effects{core => state => frame => update(core, state, frame), core => state => frame => draw(core, state, frame), core => state => frame => after(core, state, frame)}

# After InitWindow(160, 90): SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.pure(J.Core & (J.Frame & State), (J.Core.set_target_fps(core, 60), (frame, State{dir, 0, 0, 0, 0})))
