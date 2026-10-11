# raylib [shaders] example - hot reloading, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_hot_reloading.c
# (zlib/libpng, Copyright (c) 2020-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A full-screen rectangle drawn through a fragment shader that is loaded
# again when its file's modification time changes (on a click, or every
# frame after A). No shader runs on the software renderer
# (docs/SHADERS.md): the rectangle is white, under the texts. Base has no
# file times (GetFileModTime is blocked on it, docs/FILES.md), so the
# file's modification time is a setup argument, as a seeded example takes
# its seed, and the file never counts as modified: nothing is reloaded. The
# last text is the C library's asctime(localtime(&time)) of it, ported here
# for a time zone without offset (gmtime).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# modified is fragShaderFileModTime (seconds since 1970), total totalTime
# and auto shaderAutoReloading.
type State is Data:
  State{modified: U32, total: F32, auto: Bool, shader: J.Shader}

def weekday(index: U32) -> String:
  match index:
    case 0: "Sun"
    case 1: "Mon"
    case 2: "Tue"
    case 3: "Wed"
    case 4: "Thu"
    case 5: "Fri"
    case _: "Sat"

def month(index: U32) -> String:
  match index:
    case 1: "Jan"
    case 2: "Feb"
    case 3: "Mar"
    case 4: "Apr"
    case 5: "May"
    case 6: "Jun"
    case 7: "Jul"
    case 8: "Aug"
    case 9: "Sep"
    case 10: "Oct"
    case 11: "Nov"
    case _: "Dec"

# asctime(gmtime(&time)): "Www Mmm dd hh:mm:ss yyyy\n", the date from the days since 1970-01-01 (a Thursday) in the
# proleptic Gregorian calendar (eras of 400 years from 0000-03-01).
def stamp(+time: U32) -> Maybe<String>:
  +days = (time / 86400 : U32)
  +z = (days + 719468 : U32)
  +era = (z / 146097 : U32)
  +doe = (z - era * 146097 : U32)
  +yoe = ((doe - doe / 1460 + doe / 36524 - doe / 146096) / 365 : U32)
  +doy = (doe - (365 * yoe + yoe / 4 - yoe / 100) : U32)
  +mp = ((5 * doy + 2) / 153 : U32)
  +m = Bool.pick(U32, (mp < 10 : U32), (mp + 3 : U32), (mp - 9 : U32))
  +year = (yoe + era * 400 + Bool.pick(U32, (m <= 2 : U32), 1, 0) : U32)
  J.Text.format("%s %s%3d %02d:%02d:%02d %d\n", [J.TextString{weekday(((days + 4) % 7 : U32))}, J.TextString{month(m)}, J.TextInt{(doy - (153 * mp + 2) / 5 + 1 : U32)},
    J.TextInt{((time % 86400) / 3600 : U32)}, J.TextInt{((time % 3600) / 60 : U32)}, J.TextInt{(time % 60 : U32)}, J.TextInt{year}])

# The shader's uniforms of a frame: time and mouse (nothing on the software renderer).
def uniforms(+shader: J.Shader, +total: F32, +mouse: M.Vector2) -> J.Shader:
  M.Vector2{+x, +y} = mouse
  +timed = J.Shader.set_value(shader, J.Shader.get_location(shader, "time"), [F32.bits(total)], 0)
  J.Shader.set_value(timed, J.Shader.get_location(timed, "mouse"), [F32.bits(x), F32.bits(y)], 1)

# totalTime += GetFrameTime(); the uniforms; the reload check finds the file unmodified; A toggles the auto reloading.
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+modified, +total, +auto, +shader} = state
  +next = (total + J.Core.get_frame_time(core) : F32)
  (core, State{modified, next, Bool.pick(Bool, J.Input.is_key_pressed(core, 65), Bool.not(auto), auto), uniforms(shader, next, J.Input.get_mouse_position(core))})

def label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, "Shader last modification: " ++ t, 10.0, 430.0, 10.0, J.Color.BLACK())

def mode(auto: Bool, frame: J.Frame) -> J.Frame:
  match auto:
    case True{}: J.Draw.text(frame, "PRESS [A] to TOGGLE SHADER AUTOLOADING: AUTO", 10.0, 10.0, 10.0, J.Color.RED())
    case False{}: J.Draw.text(J.Draw.text(frame, "PRESS [A] to TOGGLE SHADER AUTOLOADING: MANUAL", 10.0, 10.0, 10.0, J.Color.BLACK()), "MOUSE CLICK to SHADER RE-LOADING", 10.0, 30.0, 10.0, J.Color.BLACK())

# BeginShaderMode(shader); DrawRectangle(0, 0, screenWidth, screenHeight, WHITE); EndShaderMode(); the texts.
def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+modified, _, +auto, +shader} = state
  (core, (state, label(stamp(modified), mode(auto, J.Frame.end_shader_mode(J.Draw.rectangle(J.Frame.begin_shader_mode(J.Frame.clear_background(frame, J.Color.RAYWHITE()), shader), 0.0, 0.0, 800.0, 450.0, J.Color.WHITE()))))))

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# The shader with its resolution uniform.
def loaded(+dir: String) -> J.Shader:
  +shader = J.Shader.load(None{}, Some{dir ++ "resources/shaders/glsl330/reload.fs"})
  J.Shader.set_value(shader, J.Shader.get_location(shader, "resolution"), [F32.bits(800.0), F32.bits(450.0)], 1)

# After InitWindow(800, 450): fragShaderFileModTime = GetFileModTime(the shader file), here `modified`; the shader; SetTargetFPS(60).
def setup(+modified: U32, +dir: String, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{modified, 0.0, False{}, loaded(dir)}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shaders] example - hot reloading", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, "", core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
