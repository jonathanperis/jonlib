# raylib [shaders] example - ascii rendering, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_ascii_rendering.c
# (zlib/libpng, Copyright (c) 2025 Maicon Santana (@maiconpintoabreu)); see
# LICENSES/raylib.txt.
#
# Two textures, one moving back and forth, drawn into a render texture that
# the example then draws through an ASCII-art fragment shader whose font
# size LEFT and RIGHT change (9 to 15). A shader changes nothing on raylib's
# software renderer (docs/SHADERS.md), so the render texture shows as it is
# there and here, and only the font size's text follows the keys.
# LoadTexture of a .png is the PNG loader (Surface.load_png). See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Kit is Type:
  Kit{fudesumi: J.Texture, raysan: J.Texture, target: J.RenderTexture}

# x, speed: circlePos.x and circleSpeed; size: fontSize.
type State is Type:
  State{kit: Maybe<Kit>, shader: J.Shader, x: F32, speed: F32, size: F32}

# circlePos.x += circleSpeed, turning back outside [40, 200]; LEFT and RIGHT step fontSize inside [9, 15].
def update(+core: J.Core, state: State) -> J.Core & State:
  State{kit, +shader, +x, +speed, +size} = state
  +moved = (x + speed : F32)
  +left = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_LEFT()) && (size > 9.0 : F32), (size - 1.0 : F32), size)
  +right = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_RIGHT()) && (left < 15.0 : F32), (left + 1.0 : F32), left)
  (core, State{kit, J.Shader.set_value(shader, J.Shader.get_location(shader, "fontSize"), [F32.bits(right)], 0), moved,
    Bool.pick(F32, (moved > 200.0 : F32) || (moved < 40.0 : F32), (speed * F32.neg(1.0) : F32), speed), right})

def label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 120.0, 10.0, 20.0, J.Color.LIGHTGRAY())

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# EndShaderMode(); the title bar, the font size and the frame rate.
def draw.done(+core: J.Core, +shader: J.Shader, +x: F32, +speed: F32, +size: F32, fudesumi: J.Texture, raysan: J.Texture, +id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  f1 = J.Draw.rectangle(J.Frame.end_shader_mode(frame), 0.0, 0.0, 800.0, 40.0, J.Color.BLACK())
  draw.fps.done(State{Some{Kit{fudesumi, raysan, J.RenderTexture{id, texture, depth}}}, shader, x, speed, size},
    label(J.Text.format("Ascii effect - FontSize:%2.0f - [Left] -1 [Right] +1 ", [J.TextFloat{size}]), f1), J.Core.get_fps(core, J.Core.get_time(core)), core)

# BeginShaderMode(shader); DrawTextureRec(target.texture, (0, 0, width, -height), (0, 0), WHITE).
def draw.shown(+core: J.Core, +shader: J.Shader, +x: F32, +speed: F32, +size: F32, fudesumi: J.Texture, raysan: J.Texture, frame: J.Frame, target: J.RenderTexture) -> J.Core & (State & J.Frame):
  J.RenderTexture{+id, texture, +depth} = target
  J.Texture{+tid, +w, +h, +format, +linear, +alpha, texels} = texture
  draw.done(core, shader, x, speed, size, fudesumi, raysan, id, depth,
    J.Draw.texture_rec(J.Frame.begin_shader_mode(J.Frame.clear_background(frame, J.Color.RAYWHITE()), shader), J.Texture{tid, w, h, format, linear, alpha, texels},
      J.Rectangle{0.0, 0.0, U32.to_f32(w), F32.neg(U32.to_f32(h))}, M.Vector2.zero(), J.Color.WHITE()))

def draw.ended(+core: J.Core, +shader: J.Shader, +x: F32, +speed: F32, +size: F32, fudesumi: J.Texture, raysan: J.Texture, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  match target:
    case None{}: (core, (State{None{}, shader, x, speed, size}, J.Frame.refuse(frame)))
    case Some{t}: draw.shown(core, shader, x, speed, size, fudesumi, raysan, frame, t)

def draw.raysan(+core: J.Core, +shader: J.Shader, +x: F32, +speed: F32, +size: F32, fudesumi: J.Texture, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, raysan) = r
  draw.ended(core, shader, x, speed, size, fudesumi, raysan, J.Frame.end_texture_mode(frame))

# DrawTextureV(raysan, circlePos, WHITE).
def draw.fudesumi(+core: J.Core, +shader: J.Shader, +x: F32, +speed: F32, +size: F32, raysan: J.Texture, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, fudesumi) = r
  draw.raysan(core, shader, x, speed, size, fudesumi, J.Draw.texture_v(frame, raysan, M.Vector2{x, (450.0 * 0.5 : F32)}, J.Color.WHITE()))

# The texture pass (raylib draws it before BeginDrawing; here the draw does that first, the same pixels):
# ClearBackground(WHITE); DrawTexture(fudesumi, 500, -30, WHITE).
def draw.kit(+core: J.Core, +shader: J.Shader, +x: F32, +speed: F32, +size: F32, frame: J.Frame, kit: Kit) -> J.Core & (State & J.Frame):
  Kit{fudesumi, raysan, target} = kit
  draw.fudesumi(core, shader, x, speed, size, raysan,
    J.Draw.texture(J.Frame.clear_background(J.Frame.begin_texture_mode(frame, target), J.Color.WHITE()), fudesumi, 500.0, F32.neg(30.0), J.Color.WHITE()))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{kit, +shader, +x, +speed, +size} = state
  match kit:
    case None{}: (core, (State{None{}, shader, x, speed, size}, J.Frame.refuse(frame)))
    case Some{k}: draw.kit(core, shader, x, speed, size, frame, k)

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# LoadShader(0, ascii.fs) with resolution (800, 450).
def shader() -> J.Shader:
  +s0 = J.Shader.load(None{}, Some{"resources/shaders/glsl330/ascii.fs"})
  J.Shader.set_value(s0, J.Shader.get_location(s0, "resolution"), [F32.bits(800.0), F32.bits(450.0)], 1)

def kit(fudesumi: Maybe<J.Texture>, raysan: Maybe<J.Texture>, target: Maybe<J.RenderTexture>) -> Maybe<Kit>:
  match fudesumi raysan target:
    case Some{f} Some{r} Some{t}: Some{Kit{f, r, t}}
    case _ _ _: None{}

# target = LoadRenderTexture(800, 450).
def setup.target(+core: J.Core, fudesumi: Maybe<J.Texture>, raysan: Maybe<J.Texture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  (J.Core.set_target_fps(core, 60), (frame, State{kit(fudesumi, raysan, target), shader(), 40.0, 1.0, 9.0}))

def setup.raysan(+core: J.Core, fudesumi: Maybe<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, raysan) = r
  setup.target(core, fudesumi, raysan, J.RenderTexture.load(frame, 800, 450))

def upload(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

def setup.fudesumi(+dir: String, +core: J.Core, r: J.Frame & Maybe<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  (frame, fudesumi) = r
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/raysan.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.raysan(core, fudesumi, upload(frame, result))))

# After InitWindow(800, 450): the two textures, the shader, the render texture, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/fudesumi.png"),
    result => setup.fudesumi(dir, core, upload(frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shaders] example - ascii rendering", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
