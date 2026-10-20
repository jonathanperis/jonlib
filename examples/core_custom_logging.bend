# raylib [core] example - custom logging, ported to Jonlib.
# Adapted from raylib 6.2 examples/core/core_custom_logging.c (zlib/libpng,
# Copyright (c) 2018-2025 Pablo Marcos Oltra (@pamarcos) and Ramon
# Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The example installs a TraceLog callback (SetTraceLogCallback) that prints
# each message with a time stamp and its level, and draws one line of text.
# The only messages it ever receives are raylib's own log lines (InitWindow's
# and CloseWindow's): the example calls TraceLog nowhere. Jonlib emits no log
# line of its own (docs/LOGGING.md), so the callback is never called here: it is
# custom below, the handler Log.trace_with would take, with the level tags
# of the example. Its time stamp is strftime of the C library's time(), for
# which Base has no source (docs/DRIVER.md): the handler takes the stamp's
# text. The frames are the text alone.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{frames: U32}

# The tag of a message type: LOG_INFO (3), LOG_ERROR (5), LOG_WARNING (4), LOG_DEBUG (2); none for the others.
def tag(kind: U32) -> String:
  match kind:
    case 3: "[INFO] : "
    case 5: "[ERROR]: "
    case 4: "[WARN] : "
    case 2: "[DEBUG]: "
    case _: ""

# CustomTraceLog(msgType, text, args) with the text already formatted: "[<time>] <tag><text>" and a line break.
def custom(+stamp: String, +kind: U32, text: String) -> IO(Unit):
  IO.print("[" ++ stamp ++ "] " ++ tag(kind) ++ text)

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+frames} = state
  (core, State{(frames + 1 : U32)})

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  (core, (state, J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "Check out the console output to see the custom logger in action!", 60.0, 200.0, 20.0, J.Color.LIGHTGRAY())))

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After SetTraceLogCallback(CustomTraceLog) and InitWindow(800, 450): SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{0}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - custom logging", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
