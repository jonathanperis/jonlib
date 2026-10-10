# raylib [shaders] example - shapes textures, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_shapes_textures.c
# (zlib/libpng, Copyright (c) 2015-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# Shapes and the fudesumi texture, some drawn through the grayscale shader.
# On the software renderer shaders do not exist (docs/SHADERS.md): the
# shader loads with id 0 and everything keeps its colors, which is what the
# reference draws too. The circles and the hexagon follow the libm profile's
# sinf/cosf (docs/SINCOSF.md). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{texture: Maybe<J.Texture>, shader: J.Shader}

def update(+core: J.Core, state: State) -> J.Core & State:
  (core, state)

def draw.kept(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

def draw.texture(frame: J.Frame, texture: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (frame, None{})
    case Some{t}: draw.kept(J.Draw.texture(frame, t, 500.0, F32.neg(30.0), J.Color.WHITE()))

def shapes(+libm: M.Libm, +shader: J.Shader, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.text(J.Frame.clear_background(frame, J.Color.RAYWHITE()), "USING DEFAULT SHADER", 20.0, 40.0, 10.0, J.Color.RED())
  f2 = J.Draw.circle_for(libm, f1, 80.0, 120.0, 35.0, J.Color.DARKBLUE())
  f3 = J.Draw.circle_gradient_for(libm, f2, M.Vector2{80.0, 220.0}, 60.0, J.Color.GREEN(), J.Color.SKYBLUE())
  f4 = J.Draw.circle_lines_for(libm, f3, 80.0, 340.0, 80.0, J.Color.DARKBLUE())
  f5 = J.Draw.text(J.Frame.begin_shader_mode(f4, shader), "USING CUSTOM SHADER", 190.0, 40.0, 10.0, J.Color.RED())
  f6 = J.Draw.rectangle_gradient_h(J.Draw.rectangle(f5, 190.0, 90.0, 120.0, 60.0, J.Color.RED()), 160.0, 170.0, 180.0, 130.0, J.Color.MAROON(), J.Color.GOLD())
  f7 = J.Frame.end_shader_mode(J.Draw.rectangle_lines(f6, 210.0, 320.0, 80.0, 60.0, J.Color.ORANGE()))
  f8 = J.Draw.text(f7, "USING DEFAULT SHADER", 370.0, 40.0, 10.0, J.Color.RED())
  f9 = J.Draw.triangle(f8, M.Vector2{430.0, 80.0}, M.Vector2{370.0, 150.0}, M.Vector2{490.0, 150.0}, J.Color.VIOLET())
  f10 = J.Draw.triangle_lines(f9, M.Vector2{430.0, 160.0}, M.Vector2{410.0, 230.0}, M.Vector2{450.0, 230.0}, J.Color.DARKBLUE())
  J.Frame.begin_shader_mode(J.Draw.poly_for(libm, f10, M.Vector2{430.0, 320.0}, 6.0, 80.0, 0.0, J.Color.BROWN()), shader)

def draw.done(+core: J.Core, +shader: J.Shader, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  (core, (State{texture, shader}, J.Draw.text(J.Frame.end_shader_mode(frame), "(c) Fudesumi sprite by Eiden Marsal", 380.0, (450.0 - 20.0 : F32), 10.0, J.Color.GRAY())))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{texture, +shader} = state
  draw.done(core, shader, draw.texture(shapes(libm, shader, frame), texture))

# The main loop's body; libm is the sinf/cosf profile of the circles and DrawPoly.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def shader() -> J.Shader:
  J.Shader.load(None{}, Some{"resources/shaders/glsl330/grayscale.fs"})

def setup.uploaded(+core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  (J.Core.set_target_fps(core, 60), (frame, State{texture, shader()}))

def setup.loaded(+core: J.Core, frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  match result:
    case Fail{_}: (J.Core.set_target_fps(core, 60), (frame, State{None{}, shader()}))
    case Done{image}: setup.uploaded(core, J.Texture.load_from_image(frame, image))

# After InitWindow(800, 450): LoadTexture("resources/fudesumi.png") (the PNG
# loader, as LoadTexture selects it), LoadShader(0, grayscale.fs), SetTargetFPS(60).
def setup(dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/fudesumi.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.loaded(core, frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shaders] example - shapes textures", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
