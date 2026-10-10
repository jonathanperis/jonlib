# raylib [core] example - smooth pixelperfect, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_smooth_pixelperfect.c
# (zlib/libpng, Copyright (c) 2021-2025 Giancamillo Alessandroni
# (@NotManyIdeasDev) and Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Three turning rectangles drawn into a 160x90 render texture through a
# world camera snapped to whole pixels, the texture then scaled five times
# through a screen camera that carries the fraction, so the motion stays
# smooth. The cameras follow sinf/cosf of GetTime and the rectangles turn
# with the frame time; both follow the libm profile, and an argument outside
# it refuses the frame (docs/SINCOSF.md). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# world: the world camera's target (whole pixels); screen: the screen
# camera's (the fraction times the virtual ratio).
type Motion is Data:
  Motion{valid: Bool, rotation: F32, wx: F32, wy: F32, sx: F32, sy: F32}

type State is Type:
  State{target: Maybe<J.RenderTexture>, motion: Motion}

def moved.at(+rotation: F32, sine: Maybe<F32>, cosine: Maybe<F32>) -> Motion:
  match sine cosine:
    case Some{+s} Some{+c}:
      +x = (s * 50.0 - 10.0 : F32)
      +y = (c * 30.0 : F32)
      Motion{True{}, rotation, F32.trunc(x), F32.trunc(y), ((x - F32.trunc(x)) * (800.0 / 160.0) : F32), ((y - F32.trunc(y)) * (800.0 / 160.0) : F32)}
    case _ _: Motion{False{}, rotation, 0.0, 0.0, 0.0, 0.0}

def moved(+libm: M.Libm, +rotation: F32, time: Maybe<F32>) -> Motion:
  match time:
    case None{}: Motion{False{}, rotation, 0.0, 0.0, 0.0, 0.0}
    case Some{+t}: moved.at(rotation, M.Libm.sin(libm, t), M.Libm.cos(libm, t))

# rotation += 60*GetFrameTime(); the camera at (sinf(time)*50 - 10, cosf(time)*30).
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{target, +motion} = state
  Motion{_, +rotation, _, _, _, _} = motion
  (core, State{target, moved(libm, (rotation + 60.0 * J.Core.get_frame_time(core) : F32), M.Float64.to_f32(J.Core.get_time(core)))})

def camera(+x: F32, +y: F32) -> J.Camera2D:
  J.Camera2D{M.Vector2.zero(), M.Vector2{x, y}, 0.0, 1.0}

# The world: three rectangles turning about their corners.
def world(+libm: M.Libm, +motion: Motion, frame: J.Frame) -> J.Frame:
  Motion{_, +rotation, +wx, +wy, _, _} = motion
  f1 = J.Frame.begin_mode_2d_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), camera(wx, wy))
  f2 = J.Draw.rectangle_pro_for(libm, f1, J.Rectangle{70.0, 35.0, 20.0, 20.0}, M.Vector2.zero(), rotation, J.Color.BLACK())
  f3 = J.Draw.rectangle_pro_for(libm, f2, J.Rectangle{90.0, 55.0, 30.0, 10.0}, M.Vector2.zero(), F32.neg(rotation), J.Color.RED())
  J.Frame.end_mode_2d(J.Draw.rectangle_pro_for(libm, f3, J.Rectangle{80.0, 65.0, 15.0, 25.0}, M.Vector2.zero(), (rotation + 45.0 : F32), J.Color.BLUE()))

def shown(+id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, texture) = r
  (J.Frame.end_mode_2d(frame), Some{J.RenderTexture{id, texture, depth}})

# DrawTexturePro(target.texture, (0, 0, width, -height), (-ratio, -ratio, 800 + 2*ratio, 450 + 2*ratio), (0, 0), 0, WHITE).
def show(frame: J.Frame, target: J.RenderTexture) -> J.Frame & Maybe<J.RenderTexture>:
  J.RenderTexture{+id, texture, +depth} = target
  J.Texture{+tid, +w, +h, +format, +linear, +alpha, texels} = texture
  +ratio = (800.0 / 160.0 : F32)
  shown(id, depth, J.Draw.texture_pro(frame, J.Texture{tid, w, h, format, linear, alpha, texels}, J.Rectangle{0.0, 0.0, U32.to_f32(w), F32.neg(U32.to_f32(h))},
    J.Rectangle{F32.neg(ratio), F32.neg(ratio), (800.0 + (ratio * 2.0) : F32), (450.0 + (ratio * 2.0) : F32)}, M.Vector2.zero(), 0.0, J.Color.WHITE()))

def label(text: Maybe<String>, +y: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, y, 20.0, color)

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, (800.0 - 95.0 : F32), 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.screen(+core: J.Core, +motion: Motion, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  f1 = label(J.Text.format("Screen resolution: %ix%i", [J.TextInt{800}, J.TextInt{450}]), 10.0, J.Color.DARKBLUE(), frame)
  f2 = label(J.Text.format("World resolution: %ix%i", [J.TextInt{160}, J.TextInt{90}]), 40.0, J.Color.DARKGREEN(), f1)
  draw.fps.done(State{target, motion}, f2, J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw.world(+libm: M.Libm, +core: J.Core, +motion: Motion, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  Motion{_, _, _, _, +sx, +sy} = motion
  (frame, target) = r
  match target:
    case None{}: (core, (State{None{}, motion}, J.Frame.clear_background(frame, J.Color.RED())))
    case Some{t}: draw.screen(core, motion, show(J.Frame.begin_mode_2d_for(libm, J.Frame.clear_background(frame, J.Color.RED()), camera(sx, sy)), t))

def draw.textured(+libm: M.Libm, +core: J.Core, +motion: Motion, frame: J.Frame, target: Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  match target:
    case Some{t}: draw.world(libm, core, motion, J.Frame.end_texture_mode(world(libm, motion, J.Frame.begin_texture_mode(frame, t))))
    case None{}: (core, (State{None{}, motion}, J.Frame.clear_background(frame, J.Color.RED())))

def draw.valid(valid: Bool, +libm: M.Libm, +core: J.Core, +motion: Motion, frame: J.Frame, target: Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  match valid:
    case True{}: draw.textured(libm, core, motion, frame, target)
    case False{}: (core, (State{target, motion}, J.Frame.refuse(frame)))

# The texture pass (raylib draws it before BeginDrawing; here the draw does
# that first, the same pixels), then the screen.
def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{target, +motion} = state
  Motion{+valid, _, _, _, _, _} = motion
  draw.valid(valid, libm, core, motion, frame, target)

# The main loop's body; libm is the profile of the cameras' sinf/cosf and DrawRectanglePro's.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.loaded(+core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  (J.Core.set_target_fps(core, 60), (frame, State{target, Motion{True{}, 0.0, 0.0, 0.0, 0.0, 0.0}}))

# After InitWindow(800, 450): the 160x90 render texture, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.loaded(core, J.RenderTexture.load(frame, 160, 90))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [core] example - smooth pixelperfect", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
