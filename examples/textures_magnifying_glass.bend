# raylib [textures] example - magnifying glass, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_magnifying_glass.c
# (zlib/libpng, Copyright (c) 2026 Luke Vaughan (@badram)); see
# LICENSES/raylib.txt.
#
# The scene drawn again at twice the size into a 256x256 render texture
# around the mouse, with four bunnies only that copy shows, masked by a
# circle and drawn over the scene with a ring. raylib's software renderer
# has one blend function, so BLEND_MULTIPLIED and the custom mask factors
# draw as plain alpha blending there and here (docs/TEXTURES.md). DrawRing's
# and DrawCircle's sinf/cosf follow the libm profile. LoadTexture of a .png
# is the PNG loader (Surface.load_png). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Kit is Type:
  Kit{bunny: J.Texture, parrots: J.Texture, mask: J.Texture, target: J.RenderTexture}

type State is Type:
  State{kit: Maybe<Kit>, mouse: M.Vector2}

def update(+core: J.Core, state: State) -> J.Core & State:
  State{kit, _} = state
  (core, State{kit, J.Input.get_mouse_position(core)})

def title(frame: J.Frame) -> J.Frame:
  J.Draw.text(frame, "Use the magnifying glass to find hidden bunnies!", 154.0, 6.0, 20.0, J.Color.BLACK())

# DrawRing(mPos, 126, 130, 0, 360, 64, BLACK) and the highlight: DrawCircle((int)(mPos.x - 64*rx) - 32,
# (int)(mPos.y - 64*ry) - 32, 4, ColorAlpha(WHITE, 0.5)), rx = mPos.x/800, ry = mPos.y/800.
def glass(+libm: M.Libm, +mouse: M.Vector2, frame: J.Frame) -> J.Frame:
  M.Vector2{+x, +y} = mouse
  f1 = J.Draw.ring_for(libm, frame, mouse, 126.0, 130.0, 0.0, 360.0, 64.0, J.Color.BLACK())
  J.Draw.circle_for(libm, f1, (F32.trunc((x - 64.0 * (x / 800.0) : F32)) - 32.0 : F32), (F32.trunc((y - 64.0 * (y / 800.0) : F32)) - 32.0 : F32), 4.0,
    J.Color.with_alpha(J.Color.WHITE(), 0.5))

def draw.done(+libm: M.Libm, +core: J.Core, +mouse: M.Vector2, bunny: J.Texture, parrots: J.Texture, mask: J.Texture, +id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  (core, (State{Some{Kit{bunny, parrots, mask, J.RenderTexture{id, texture, depth}}}, mouse}, glass(libm, mouse, frame)))

# DrawTextureRec(magnifiedWorld.texture, (0, 0, 256, -256), (mPos.x - 128, mPos.y - 128), WHITE).
def draw.shown(+libm: M.Libm, +core: J.Core, +mouse: M.Vector2, bunny: J.Texture, parrots: J.Texture, mask: J.Texture, frame: J.Frame, target: J.RenderTexture) -> J.Core & (State & J.Frame):
  M.Vector2{+x, +y} = mouse
  J.RenderTexture{+id, texture, +depth} = target
  draw.done(libm, core, mouse, bunny, parrots, mask, id, depth,
    J.Draw.texture_rec(frame, texture, J.Rectangle{0.0, 0.0, 256.0, F32.neg(256.0)}, M.Vector2{(x - 128.0 : F32), (y - 128.0 : F32)}, J.Color.WHITE()))

def draw.ended(+libm: M.Libm, +core: J.Core, +mouse: M.Vector2, bunny: J.Texture, parrots: J.Texture, mask: J.Texture, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  match target:
    case None{}: (core, (State{None{}, mouse}, J.Frame.refuse(frame)))
    case Some{t}: draw.shown(libm, core, mouse, bunny, parrots, mask, frame, t)

def draw.masked(+libm: M.Libm, +core: J.Core, +mouse: M.Vector2, bunny: J.Texture, parrots: J.Texture, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, mask) = r
  draw.ended(libm, core, mouse, bunny, parrots, mask, J.Frame.end_texture_mode(J.Frame.end_blend_mode(frame)))

# EndBlendMode(); EndMode2D(); BeginBlendMode(BLEND_CUSTOM_SEPARATE) with
# rlSetBlendFactorsSeparate(RL_ZERO, RL_ONE, RL_ONE, RL_ZERO, RL_FUNC_ADD, RL_FUNC_ADD); DrawTexture(mask, 0, 0, WHITE).
def draw.bunnies(+libm: M.Libm, +core: J.Core, +mouse: M.Vector2, parrots: J.Texture, mask: J.Texture, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, bunny) = r
  f1 = J.Frame.begin_blend_mode(J.Frame.end_mode_2d(J.Frame.end_blend_mode(frame)), J.BlendMode.BLEND_CUSTOM_SEPARATE())
  draw.masked(libm, core, mouse, bunny, parrots, J.Draw.texture(J.Rlgl.set_blend_factors_separate(f1, 0, 1, 1, 0, 32774, 32774), mask, 0.0, 0.0, J.Color.WHITE()))

def bunny.at(+x: F32, +y: F32, r: J.Frame & J.Texture) -> J.Frame & J.Texture:
  (frame, bunny) = r
  J.Draw.texture(frame, bunny, x, y, J.Color.WHITE())

# The magnified copy: the scene through the camera, then the bunnies under BLEND_MULTIPLIED.
def draw.zoomed(+libm: M.Libm, +core: J.Core, +mouse: M.Vector2, bunny: J.Texture, mask: J.Texture, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, parrots) = r
  draw.bunnies(libm, core, mouse, parrots, mask,
    bunny.at(650.0, 10.0, bunny.at(420.0, 300.0, bunny.at(500.0, 100.0, bunny.at(250.0, 350.0, (J.Frame.begin_blend_mode(title(frame), J.BlendMode.BLEND_MULTIPLIED()), bunny))))))

# BeginTextureMode(magnifiedWorld); ClearBackground(RAYWHITE); BeginMode2D(camera); the parrots again.
def draw.scene(+libm: M.Libm, +core: J.Core, +mouse: M.Vector2, bunny: J.Texture, mask: J.Texture, target: J.RenderTexture, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, parrots) = r
  draw.zoomed(libm, core, mouse, bunny, mask, J.Draw.texture(J.Frame.begin_mode_2d_for(libm,
    J.Frame.clear_background(J.Frame.begin_texture_mode(title(frame), target), J.Color.RAYWHITE()),
    J.Camera2D{M.Vector2{128.0, 128.0}, mouse, 0.0, 2.0}), parrots, 144.0, 33.0, J.Color.WHITE()))

def draw.kit(+libm: M.Libm, +core: J.Core, +mouse: M.Vector2, frame: J.Frame, kit: Kit) -> J.Core & (State & J.Frame):
  Kit{bunny, parrots, mask, target} = kit
  draw.scene(libm, core, mouse, bunny, mask, target, J.Draw.texture(J.Frame.clear_background(frame, J.Color.RAYWHITE()), parrots, 144.0, 33.0, J.Color.WHITE()))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{kit, +mouse} = state
  match kit:
    case None{}: (core, (State{None{}, mouse}, J.Frame.refuse(frame)))
    case Some{k}: draw.kit(libm, core, mouse, frame, k)

# The main loop's body; libm is the profile of BeginMode2D's, DrawRing's and DrawCircle's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def kit(bunny: Maybe<J.Texture>, parrots: Maybe<J.Texture>, mask: Maybe<J.Texture>, target: Maybe<J.RenderTexture>) -> Maybe<Kit>:
  match bunny parrots mask target:
    case Some{b} Some{p} Some{m} Some{t}: Some{Kit{b, p, m, t}}
    case _ _ _ _: None{}

def setup.target(+core: J.Core, bunny: Maybe<J.Texture>, parrots: Maybe<J.Texture>, mask: Maybe<J.Texture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  (J.Core.set_target_fps(core, 60), (frame, State{kit(bunny, parrots, mask, target), M.Vector2.zero()}))

# magnifiedWorld = LoadRenderTexture(256, 256).
def setup.mask(+core: J.Core, bunny: Maybe<J.Texture>, parrots: Maybe<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, mask) = r
  setup.target(core, bunny, parrots, mask, J.RenderTexture.load(frame, 256, 256))

def upload(frame: J.Frame, image: Maybe<J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match image:
    case None{}: (frame, None{})
    case Some{i}: J.Texture.load_from_image(frame, i)

# circle = GenImageColor(256, 256, BLANK); ImageDrawCircle(&circle, 128, 128, 128, WHITE).
def circle(image: Maybe<J.Surface>) -> Maybe<J.Surface>:
  match image:
    case None{}: None{}
    case Some{i}: Some{J.Surface.draw_circle(i, 128.0, 128.0, 128, J.Color.WHITE())}

def setup.parrots(+core: J.Core, bunny: Maybe<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, parrots) = r
  setup.mask(core, bunny, parrots, upload(frame, circle(J.Surface.create(256, 256, J.Color.BLANK()))))

def loaded(result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> Maybe<J.Surface>:
  match result:
    case Fail{_}: None{}
    case Done{image}: Some{image}

def setup.bunny(+dir: String, +core: J.Core, r: J.Frame & Maybe<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  (frame, bunny) = r
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/parrots.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.parrots(core, bunny, upload(frame, loaded(result)))))

# After InitWindow(800, 450): the bunny and parrots textures, the circle
# mask, the render texture, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/raybunny.png"),
    result => setup.bunny(dir, core, upload(frame, loaded(result))))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [textures] example - magnifying glass", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
