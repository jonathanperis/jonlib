# raylib [shaders] example - color correction, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_color_correction.c
# (zlib/libpng, Copyright (c) 2025 Jordi Santonja (@JordSant)); see
# LICENSES/raylib.txt.
#
# One of four pictures (keys 1 to 4 or the raygui toggle group) through the
# color-correction shader, with slider bars for contrast, saturation and
# brightness and a reset button (Jongui). On the software renderer shaders do
# not exist (docs/SHADERS.md): the shader loads with id 0, its three uniforms
# are ignored and the picture keeps its colors, which is what the reference
# draws too. The reset button acts on the next frame, as in the example.
# LoadTexture of a .png is the PNG loader (Surface.load_png). See
# docs/GUI.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# values: contrast, saturation, brightness.
type State is Type:
  State{textures: List<Maybe<J.Texture>>, index: U32, values: +List<F32>, reset: Bool, gui: G.Gui, shader: J.Shader}

# 1 to 4 pick the picture (the first pressed, as raylib's else-if); R or the
# reset button of the last frame zero the values.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{textures, +index, +values, +reset, +gui, +shader} = state
  +one = J.Input.is_key_pressed(core, 49)
  +two = Bool.not(one) && J.Input.is_key_pressed(core, 50)
  +three = Bool.not(one || two) && J.Input.is_key_pressed(core, 51)
  +four = Bool.not(one || two || three) && J.Input.is_key_pressed(core, 52)
  +picked = Bool.pick(U32, one, 0, Bool.pick(U32, two, 1, Bool.pick(U32, three, 2, Bool.pick(U32, four, 3, index))))
  +zero = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_R()) || reset
  (core, State{textures, picked, Bool.pick(+List<F32>, zero, [0.0, 0.0, 0.0], values), reset, gui, shader})

def kept(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

# DrawTexture(texture, 580/2 - texture.width/2, GetScreenHeight()/2 - texture.height/2, WHITE).
def picture.at(frame: J.Frame, texture: J.Texture) -> J.Frame & Maybe<J.Texture>:
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  kept(J.Draw.texture(frame, J.Texture{id, w, h, format, linear, alpha, texels},
    (290.0 - U32.to_f32((w / 2 : U32)) : F32), (225.0 - U32.to_f32((h / 2 : U32)) : F32), J.Color.WHITE()))

def picture(frame: J.Frame, texture: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (frame, None{})
    case Some{t}: picture.at(frame, t)

def cons(rest: List<Maybe<J.Texture>>, r: J.Frame & Maybe<J.Texture>) -> J.Frame & List<Maybe<J.Texture>>:
  (frame, t) = r
  (frame, Con{t, rest})

def consed(t: Maybe<J.Texture>, r: J.Frame & List<Maybe<J.Texture>>) -> J.Frame & List<Maybe<J.Texture>>:
  (frame, rest) = r
  (frame, Con{t, rest})

# Draws textures[index], handing every texture back.
def nth(textures: List<Maybe<J.Texture>>, n: Nat, frame: J.Frame) -> J.Frame & List<Maybe<J.Texture>>:
  match textures n:
    case Nil{} _: (frame, Nil{})
    case Con{t, rest} 0n: cons(rest, picture(frame, t))
    case Con{t, rest} 1n+p: consed(t, nth(rest, p, frame))

def bars() -> +List<G.Gui.Bar>:
  [G.GuiBar{J.Rectangle{645.0, 100.0, 120.0, 20.0}, "Contrast", "%.0f", F32.neg(100.0), 100.0},
   G.GuiBar{J.Rectangle{645.0, 130.0, 120.0, 20.0}, "Saturation", "%.0f", F32.neg(100.0), 100.0},
   G.GuiBar{J.Rectangle{645.0, 160.0, 120.0, 20.0}, "Brightness", "%.0f", F32.neg(100.0), 100.0}]

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 710.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.reset(+core: J.Core, textures: List<Maybe<J.Texture>>, +index: U32, +gui: G.Gui, +values: +List<F32>, +shader: J.Shader, r: J.Frame & Bool) -> J.Core & (State & J.Frame):
  (frame, +reset) = r
  draw.fps.done(State{textures, index, values, reset, gui, shader}, frame, J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw.values(+core: J.Core, textures: List<Maybe<J.Texture>>, +index: U32, +shader: J.Shader, frame: J.Frame, rest: G.Gui & +List<F32>) -> J.Core & (State & J.Frame):
  (+gui, +values) = rest
  draw.reset(core, textures, index, gui, values, shader, G.Gui.button(gui, core, frame, J.Rectangle{645.0, 190.0, 40.0, 20.0}, "Reset"))

def draw.bars(+core: J.Core, textures: List<Maybe<J.Texture>>, +index: U32, +shader: J.Shader, r: J.Frame & (G.Gui & +List<F32>)) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.values(core, textures, index, shader, frame, rest)

def draw.group(+core: J.Core, textures: List<Maybe<J.Texture>>, +values: +List<F32>, +gui: G.Gui, +shader: J.Shader, r: J.Frame & U32) -> J.Core & (State & J.Frame):
  (frame, +index) = r
  draw.bars(core, textures, index, shader, G.Gui.slider_bars(gui, core, frame, bars(), values))

def draw.picture(+core: J.Core, +index: U32, +values: +List<F32>, +gui: G.Gui, +shader: J.Shader, r: J.Frame & List<Maybe<J.Texture>>) -> J.Core & (State & J.Frame):
  (frame, textures) = r
  f1 = J.Draw.line(J.Frame.end_shader_mode(frame), 580.0, 0.0, 580.0, 450.0, J.Color.rgba(218, 218, 218, 255))
  f2 = J.Draw.rectangle(f1, 580.0, 0.0, 800.0, 450.0, J.Color.rgba(232, 232, 232, 255))
  f3 = J.Draw.text(J.Draw.text(f2, "Color Correction", 585.0, 40.0, 20.0, J.Color.GRAY()), "Picture", 602.0, 75.0, 10.0, J.Color.GRAY())
  f4 = J.Draw.text(f3, "Press [1] - [4] to Change Picture", 600.0, 230.0, 8.0, J.Color.GRAY())
  f5 = J.Draw.text(f4, "Press [R] to Reset Values", 600.0, 250.0, 8.0, J.Color.GRAY())
  draw.group(core, textures, values, gui, shader, G.Gui.toggle_group(gui, core, f5, J.Rectangle{645.0, 70.0, 20.0, 20.0}, "1;2;3;4", index))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{textures, +index, +values, _, +gui, +shader} = state
  draw.picture(core, index, values, gui, shader, nth(textures, U32.to_nat(index), J.Frame.begin_shader_mode(J.Frame.clear_background(frame, J.Color.RAYWHITE()), shader)))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def upload(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

def loaded(acc: List<Maybe<J.Texture>>, r: J.Frame & Maybe<J.Texture>) -> J.Frame & List<Maybe<J.Texture>>:
  (frame, texture) = r
  (frame, Con{texture, acc})

# LoadShader(0, color_correction.fs) with contrast, saturation and brightness 0.
def shader() -> J.Shader:
  +s0 = J.Shader.load(None{}, Some{"resources/shaders/glsl330/color_correction.fs"})
  +s1 = J.Shader.set_value(s0, J.Shader.get_location(s0, "contrast"), [F32.bits(0.0)], 0)
  +s2 = J.Shader.set_value(s1, J.Shader.get_location(s1, "saturation"), [F32.bits(0.0)], 0)
  J.Shader.set_value(s2, J.Shader.get_location(s2, "brightness"), [F32.bits(0.0)], 0)

def setup.done(+core: J.Core, r: J.Frame & List<Maybe<J.Texture>>) -> J.Core & (J.Frame & State):
  (frame, reversed) = r
  (J.Core.set_target_fps(core, 60), (frame, State{List.reverse(&1, Maybe<J.Texture>, reversed), 0, [0.0, 0.0, 0.0], False{}, G.Gui.new(), shader()}))

def setup.fourth(+core: J.Core, frame: J.Frame, acc: List<Maybe<J.Texture>>, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Core & (J.Frame & State):
  setup.done(core, loaded(acc, upload(frame, result)))

def setup.third(+dir: String, +core: J.Core, r: J.Frame & List<Maybe<J.Texture>>) -> IO(J.Core & (J.Frame & State)):
  (frame, acc) = r
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/fudesumi.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.fourth(core, frame, acc, result)))

def setup.second(+dir: String, +core: J.Core, r: J.Frame & List<Maybe<J.Texture>>) -> IO(J.Core & (J.Frame & State)):
  (frame, acc) = r
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/mandrill.png"),
    result => setup.third(dir, core, loaded(acc, upload(frame, result))))

def setup.first(+dir: String, +core: J.Core, r: J.Frame & List<Maybe<J.Texture>>) -> IO(J.Core & (J.Frame & State)):
  (frame, acc) = r
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/cat.png"),
    result => setup.second(dir, core, loaded(acc, upload(frame, result))))

# After InitWindow(800, 450): the four textures in order (parrots, cat,
# mandrill, fudesumi), the shader, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/parrots.png"),
    result => setup.first(dir, core, loaded(Nil{}, upload(frame, result))))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shaders] example - color correction", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
