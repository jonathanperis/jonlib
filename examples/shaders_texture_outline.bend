# raylib [shaders] example - texture outline, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_texture_outline.c
# (zlib/libpng, Copyright (c) 2021-2025 Serenity Skiff (@GoldenThumbs) and
# Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The fudesumi texture through the outline shader; the mouse wheel changes
# the outline size (at least 1). On the software renderer shaders do not
# exist (docs/SHADERS.md): the shader loads with id 0, its uniforms are
# ignored and the texture draws as in the default mode, which is what the
# reference draws too. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{texture: Maybe<J.Texture>, shader: J.Shader, size: F32}

def float(+value: F32) -> +List<U32>:
  [F32.bits(value)]

# outlineSize += GetMouseWheelMove(), at least 1, and its uniform.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{texture, +shader, +size} = state
  +grown = (size + J.Input.get_mouse_wheel_move(core) : F32)
  +next = Bool.pick(F32, (grown < 1.0 : F32), 1.0, grown)
  (core, State{texture, J.Shader.set_value(shader, J.Shader.get_location(shader, "outlineSize"), float(next), 0), next})

def draw.kept(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

# DrawTexture(texture, GetScreenWidth()/2 - texture.width/2, -30, WHITE).
def draw.at(frame: J.Frame, texture: J.Texture) -> J.Frame & Maybe<J.Texture>:
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  +x = U32.to_f32((400 - w / 2 : U32))
  +left = Bool.pick(F32, (w / 2 > 400 : U32), F32.neg(U32.to_f32((w / 2 - 400 : U32))), x)
  draw.kept(J.Draw.texture(frame, J.Texture{id, w, h, format, linear, alpha, texels}, left, F32.neg(30.0), J.Color.WHITE()))

def draw.texture(frame: J.Frame, texture: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (frame, None{})
    case Some{t}: draw.at(frame, t)

def draw.label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, 120.0, 20.0, J.Color.MAROON())

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 710.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.done(+core: J.Core, +shader: J.Shader, +size: F32, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  f1 = J.Draw.text(J.Frame.end_shader_mode(frame), "Shader-based\ntexture\noutline", 10.0, 10.0, 20.0, J.Color.GRAY())
  f2 = J.Draw.text(f1, "Scroll mouse wheel to\nchange outline size", 10.0, 72.0, 20.0, J.Color.GRAY())
  f3 = draw.label(J.Text.format("Outline size: %i px", [J.TextInt{F32.to_u32(F32.trunc(size))}]), f2)
  draw.fps.done(State{texture, shader, size}, f3, J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{texture, +shader, +size} = state
  draw.done(core, shader, size, draw.texture(J.Frame.begin_shader_mode(J.Frame.clear_background(frame, J.Color.RAYWHITE()), shader), texture))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# LoadShader(0, outline.fs) with outlineSize 2, outlineColor RED (normalized)
# and textureSize (ignored here, as on the software renderer).
def shader(+w: U32, +h: U32) -> J.Shader:
  +s0 = J.Shader.load(None{}, Some{"resources/shaders/glsl330/outline.fs"})
  +s1 = J.Shader.set_value(s0, J.Shader.get_location(s0, "outlineSize"), float(2.0), 0)
  +s2 = J.Shader.set_value(s1, J.Shader.get_location(s1, "outlineColor"), [F32.bits(1.0), F32.bits(0.0), F32.bits(0.0), F32.bits(1.0)], 3)
  J.Shader.set_value(s2, J.Shader.get_location(s2, "textureSize"), [F32.bits(U32.to_f32(w)), F32.bits(U32.to_f32(h))], 1)

def setup.texture(+core: J.Core, frame: J.Frame, texture: J.Texture) -> J.Core & (J.Frame & State):
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  (J.Core.set_target_fps(core, 60), (frame, State{Some{J.Texture{id, w, h, format, linear, alpha, texels}}, shader(w, h), 2.0}))

def setup.uploaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  match texture:
    case None{}: (J.Core.set_target_fps(core, 60), (frame, State{None{}, shader(0, 0), 2.0}))
    case Some{t}: setup.texture(core, frame, t)

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: (J.Core.set_target_fps(core, 60), (frame, State{None{}, shader(0, 0), 2.0}))
    case Done{image}: setup.uploaded(core, J.Texture.load_from_image(frame, image))

# After InitWindow(800, 450): LoadTexture("resources/fudesumi.png") (the PNG
# loader, as LoadTexture selects it), the shader, SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/fudesumi.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shaders] example - texture outline", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
