# raylib [shaders] example - palette switch, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_palette_switch.c
# (zlib/libpng, Copyright (c) 2019-2025 Marco Lizza (@MarcoLizza) and Ramon
# Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Eight gray bands (colors 0..7) through the palette-switch shader; RIGHT and
# LEFT cycle the three palettes. On the software renderer shaders do not
# exist (docs/SHADERS.md): the shader loads with id 0, the palette uniform is
# ignored and the bands draw in their own near-black grays, which is what the
# reference draws too. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Data:
  State{palette: U32, shader: J.Shader}

# The palettes' RGB integers (SHADER_UNIFORM_IVEC3, 8 colors).
def palette(index: U32) -> +List<U32>:
  match index:
    case 0: [0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 255, 255, 255, 0, 255, 255, 255, 0, 255, 255, 255]
    case 1: [4, 12, 6, 17, 35, 24, 30, 58, 41, 48, 93, 66, 77, 128, 97, 137, 162, 87, 190, 220, 127, 238, 255, 204]
    case _: [21, 25, 26, 138, 76, 88, 217, 98, 117, 230, 184, 193, 69, 107, 115, 75, 151, 166, 165, 189, 194, 255, 245, 247]

def name(index: U32) -> String:
  match index:
    case 0: "3-BIT RGB"
    case 1: "AMMO-8 (GameBoy-like)"
    case _: "RKBV (2-strip film)"

# RIGHT (else LEFT) moves the palette, wrapping in 0..2; then SetShaderValueV.
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+current, +shader} = state
  +right = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT())
  +left = Bool.not(right) && J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT())
  +moved = Bool.pick(U32, right, (current + 1 : U32), Bool.pick(U32, left && U32.is_eq(current, 0), 2, Bool.pick(U32, left, (current - 1 : U32), current)))
  +next = Bool.pick(U32, (moved >= 3 : U32), 0, moved)
  (core, State{next, J.Shader.set_value_v(shader, J.Shader.get_location(shader, "palette"), palette(next), 6, 8)})

def bands(n: Nat, +i: U32, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+p: bands(p, (i + 1 : U32), J.Draw.rectangle(frame, 0.0, U32.to_f32((56 * i : U32)), 800.0, 56.0, J.Color.rgba(i, i, i, 255)))

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 700.0, 15.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+current, +shader} = state
  f1 = J.Frame.end_shader_mode(bands(8n, 0, J.Frame.begin_shader_mode(J.Frame.clear_background(frame, J.Color.RAYWHITE()), shader)))
  f2 = J.Draw.text(J.Draw.text(f1, "< >", 10.0, 10.0, 30.0, J.Color.DARKBLUE()), "CURRENT PALETTE:", 60.0, 15.0, 20.0, J.Color.RAYWHITE())
  draw.fps.done(state, J.Draw.text(f2, name(current), 300.0, 15.0, 20.0, J.Color.RED()), J.Core.get_fps(core, J.Core.get_time(core)), core)

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450): LoadShader(0, palette_switch.fs), palette 0, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{0, J.Shader.load(None{}, Some{"resources/shaders/glsl330/palette_switch.fs"})}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shaders] example - palette switch", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
