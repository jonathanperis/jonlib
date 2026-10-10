# raylib [core] example - window letterbox, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_window_letterbox.c (zlib/libpng,
# Copyright (c) 2019-2025 Anata (@anatagawa) and Ramon Santamaria (@raysan5));
# see LICENSES/raylib.txt.
#
# A 640x480 game screen (ten random color bars, the real and virtual mouse
# positions) drawn into a bilinear render texture and scaled into the 800x450
# window with black bars; SPACE draws new colors. raylib seeds GetRandomValue
# from time(NULL) in InitWindow; here the seed is a setup argument. A color's
# three GetRandomValue calls are an initializer list, whose order C leaves
# unspecified; the reference compiler (clang) draws them left to right, as here.
# Vector2Clamp's fminf/fmaxf follow the libm profile. The window is not
# resized here (the memory platform never is). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{rng: J.Random.State, colors: +List<U32>, target: Maybe<J.RenderTexture>}

# colors[i] = (GetRandomValue(100, 250), GetRandomValue(50, 150), GetRandomValue(10, 100), 255), i ascending.
def colors.blue(+r: F32, +g: F32, drawn: J.Random.State & F32) -> J.Random.State & U32:
  (rng, +b) = drawn
  (rng, J.Color.rgba(F32.to_u32(r), F32.to_u32(g), F32.to_u32(b), 255))

def colors.green(+r: F32, drawn: J.Random.State & F32) -> J.Random.State & U32:
  (rng, +g) = drawn
  colors.blue(r, g, J.Random.value(rng, 10.0, 100.0))

def colors.red(drawn: J.Random.State & F32) -> J.Random.State & U32:
  (rng, +r) = drawn
  colors.green(r, J.Random.value(rng, 50.0, 150.0))

def colors.push(acc: +List<U32>, one: J.Random.State & U32) -> J.Random.State & +List<U32>:
  (rng, +color) = one
  (rng, Con{color, acc})

def colors.step(r: J.Random.State & +List<U32>) -> J.Random.State & +List<U32>:
  (rng, acc) = r
  colors.push(acc, colors.red(J.Random.value(rng, 100.0, 250.0)))

def colors.reversed(r: J.Random.State & +List<U32>) -> J.Random.State & +List<U32>:
  (rng, acc) = r
  (rng, List.reverse(&2, U32, acc))

def colors.go(n: Nat, r: J.Random.State & +List<U32>) -> J.Random.State & +List<U32>:
  match n:
    case 0n: colors.reversed(r)
    case 1n+p: colors.go(p, colors.step(r))

def colors(rng: J.Random.State) -> J.Random.State & +List<U32>:
  colors.go(10n, (rng, Nil{}))

def recolored(target: Maybe<J.RenderTexture>, r: J.Random.State & +List<U32>) -> State:
  (rng, colors) = r
  State{rng, colors, target}

# SPACE draws ten new colors.
def update.at(space: Bool, +core: J.Core, state: State) -> J.Core & State:
  match space:
    case True{}:
      State{rng, _, target} = state
      (core, recolored(target, colors(rng)))
    case False{}: (core, state)

def update(+core: J.Core, state: State) -> J.Core & State:
  update.at(J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), core, state)

# DrawRectangle(0, (gameScreenHeight/10)*i, gameScreenWidth, gameScreenHeight/10, colors[i]).
def bars(colors: +List<U32>, +i: U32, frame: J.Frame) -> J.Frame:
  match colors:
    case Nil{}: frame
    case Con{+c, rest}: bars(rest, (i + 1 : U32), J.Draw.rectangle(frame, 0.0, U32.to_f32((48 * i : U32)), 640.0, 48.0, c))

# (int)v for a C int in range, as a two's-complement word.
def int(+v: F32) -> U32:
  Bool.pick(U32, (v < 0.0 : F32), (0 - F32.to_u32(F32.trunc(F32.neg(v))) : U32), F32.to_u32(F32.trunc(v)))

def label(text: Maybe<String>, +y: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 350.0, y, 20.0, color)

# The game screen: the bars, the note and both mouse positions.
def game.at(+colors: +List<U32>, mouse: M.Vector2, virtual: M.Vector2, frame: J.Frame) -> J.Frame:
  M.Vector2{+mx, +my} = mouse
  M.Vector2{+cx, +cy} = virtual
  f1 = bars(colors, 0, J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  f2 = J.Draw.text(f1, "If executed inside a window,\nyou can resize the window,\nand see the screen scaling!", 10.0, 25.0, 20.0, J.Color.WHITE())
  f3 = label(J.Text.format("Default Mouse: [%i , %i]", [J.TextInt{int(mx)}, J.TextInt{int(my)}]), 25.0, J.Color.GREEN(), f2)
  label(J.Text.format("Virtual Mouse: [%i , %i]", [J.TextInt{int(cx)}, J.TextInt{int(cy)}]), 55.0, J.Color.YELLOW(), f3)

# virtualMouse = Vector2Clamp(((mouse - (screen - game*scale)*0.5)/scale), (0, 0), (640, 480)).
def virtual(+libm: M.Libm, mouse: M.Vector2) -> M.Vector2:
  M.Vector2{+mx, +my} = mouse
  +scale = F32.min((800.0 / 640.0 : F32), (450.0 / 480.0 : F32))
  M.Vector2.clamp_for(libm, M.Vector2{((mx - (800.0 - (640.0 * scale)) * 0.5) / scale : F32), ((my - (450.0 - (480.0 * scale)) * 0.5) / scale : F32)},
    M.Vector2.zero(), M.Vector2{640.0, 480.0})

def game(+libm: M.Libm, +core: J.Core, +colors: +List<U32>, frame: J.Frame) -> J.Frame:
  game.at(colors, J.Input.get_mouse_position(core), virtual(libm, J.Input.get_mouse_position(core)), frame)

def shown(+id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, texture) = r
  (frame, Some{J.RenderTexture{id, texture, depth}})

# DrawTexturePro(target.texture, (0, 0, width, -height), the centered scaled rectangle, (0, 0), 0, WHITE).
def show(frame: J.Frame, target: J.RenderTexture) -> J.Frame & Maybe<J.RenderTexture>:
  J.RenderTexture{+id, texture, +depth} = target
  J.Texture{+tid, +w, +h, +format, +linear, +alpha, texels} = texture
  +scale = F32.min((800.0 / 640.0 : F32), (450.0 / 480.0 : F32))
  shown(id, depth, J.Draw.texture_pro(frame, J.Texture{tid, w, h, format, linear, alpha, texels},
    J.Rectangle{0.0, 0.0, U32.to_f32(w), F32.neg(U32.to_f32(h))},
    J.Rectangle{((800.0 - (640.0 * scale)) * 0.5 : F32), ((450.0 - (480.0 * scale)) * 0.5 : F32), (640.0 * scale : F32), (480.0 * scale : F32)},
    M.Vector2.zero(), 0.0, J.Color.WHITE()))

def displayed.done(+core: J.Core, rng: J.Random.State, +colors: +List<U32>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  (core, (State{rng, colors, target}, frame))

def displayed(+core: J.Core, rng: J.Random.State, +colors: +List<U32>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  match target:
    case None{}: (core, (State{rng, colors, None{}}, J.Frame.clear_background(frame, J.Color.BLACK())))
    case Some{t}: displayed.done(core, rng, colors, show(J.Frame.clear_background(frame, J.Color.BLACK()), t))

# The texture pass (raylib draws it before BeginDrawing; here the draw does
# that first, the same pixels), then the screen.
def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{rng, +colors, target} = state
  match target:
    case None{}: (core, (State{rng, colors, None{}}, J.Frame.clear_background(frame, J.Color.BLACK())))
    case Some{t}: displayed(core, rng, colors, J.Frame.end_texture_mode(game(libm, core, colors, J.Frame.begin_texture_mode(frame, t))))

# The main loop's body; libm is the fminf/fmaxf profile of Vector2Clamp.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def filtered.at(target: J.RenderTexture) -> J.RenderTexture:
  J.RenderTexture{id, texture, depth} = target
  J.RenderTexture{id, J.Texture.set_filter(texture, 1), depth}

# SetTextureFilter(target.texture, TEXTURE_FILTER_BILINEAR).
def filtered(target: Maybe<J.RenderTexture>) -> Maybe<J.RenderTexture>:
  match target:
    case None{}: None{}
    case Some{t}: Some{filtered.at(t)}

def setup.colors(+core: J.Core, frame: J.Frame, target: Maybe<J.RenderTexture>, r: J.Random.State & +List<U32>) -> J.Core & (J.Frame & State):
  (rng, colors) = r
  (J.Core.set_target_fps(core, 60), (frame, State{rng, colors, target}))

def setup.loaded(+seed: U32, +core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  setup.colors(core, frame, filtered(target), colors(J.Random.seed(seed)))

# After SetConfigFlags(FLAG_WINDOW_RESIZABLE | FLAG_VSYNC_HINT), InitWindow(800, 450)
# and SetRandomSeed(seed): SetWindowMinSize(320, 240) (nothing to do here), the
# 640x480 bilinear render texture, ten colors, SetTargetFPS(60).
def setup(+seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.loaded(seed, core, J.RenderTexture.load(frame, 640, 480))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - window letterbox", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
