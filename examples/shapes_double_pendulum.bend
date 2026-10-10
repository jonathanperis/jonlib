# raylib [shapes] example - double pendulum, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_double_pendulum.c
# (zlib/libpng, Copyright (c) 2025 JoeCheong (@Joecheong2006)); see
# LICENSES/raylib.txt.
#
# A double pendulum integrated thirty steps a frame, its trail drawn into a
# render texture that a nearly transparent black rectangle fades each frame,
# and the two rods as turned rectangles. The simulation's and the end
# points' sinf/cosf follow the libm profile, as do DrawCircleV's and
# DrawRectanglePro's; an argument outside the profile refuses the frame and
# every later one (docs/SINCOSF.md). The float expressions keep the
# example's order of operations. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Sim is Data:
  Sim{valid: Bool, theta1: F32, w1: F32, theta2: F32, w2: F32}

type Ends is Data:
  Ends{valid: Bool, end1: M.Vector2, end2: M.Vector2}

# end1: the first rod's end point; previous, current: the trail's.
type Pendulum is Data:
  Pendulum{valid: Bool, theta1: F32, w1: F32, theta2: F32, w2: F32, end1: M.Vector2, previous: M.Vector2, current: M.Vector2}

type State is Type:
  State{target: Maybe<J.RenderTexture>, pendulum: Pendulum}

# m1 = 0.2f, m2 = 0.1f, G = 9.81f; L1 = L2 = 15*lengthScaler; totalM = m1 + m2.
def mass1() -> F32:
  0.2

def mass2() -> F32:
  0.1

def gravity() -> F32:
  9.81

def length() -> F32:
  (15.0 * 0.1 : F32)

def total() -> F32:
  (0.2 + 0.1 : F32)

# One step of the example's loop, every product and sum in its C order:
# a1 = (-G*(2*m1 + m2)*sinf(theta1) - m2*G*sinf(theta1 - 2*theta2)
#       - 2*sinD*m2*(ww2*L2 + ww1*L1*cosD))/(L1*(2*m1 + m2 - m2*cos2D))
# a2 = (2*sinD*(ww1*L1*totalM + G*totalM*cosf(theta1) + ww2*L2*m2*cosD))/(L2*(2*m1 + m2 - m2*cos2D))
def stepped(+valid: Bool, +t1: F32, +w1: F32, +t2: F32, +w2: F32, +step: F32, +step2: F32,
    sd: Maybe<F32>, cd: Maybe<F32>, c2: Maybe<F32>, s1: Maybe<F32>, s12: Maybe<F32>, c1: Maybe<F32>) -> Sim:
  match sd cd c2 s1 s12 c1:
    case Some{+sinD} Some{+cosD} Some{+cos2D} Some{+sin1} Some{+sin12} Some{+cos1}:
      +ww1 = (w1 * w1 : F32)
      +ww2 = (w2 * w2 : F32)
      +below = (((2.0 * mass1()) + mass2()) - (mass2() * cos2D) : F32)
      +first = ((F32.neg(gravity()) * ((2.0 * mass1()) + mass2())) * sin1 : F32)
      +second = ((mass2() * gravity()) * sin12 : F32)
      +third = (((2.0 * sinD) * mass2()) * ((ww2 * length()) + ((ww1 * length()) * cosD)) : F32)
      +a1 = (((first - second) - third) / (length() * below) : F32)
      +a2 = (((2.0 * sinD) * ((((ww1 * length()) * total()) + ((gravity() * total()) * cos1)) + (((ww2 * length()) * mass2()) * cosD))) / (length() * below) : F32)
      Sim{valid, (t1 + ((w1 * step) + ((0.5 * a1) * step2)) : F32), (w1 + (a1 * step) : F32), (t2 + ((w2 * step) + ((0.5 * a2) * step2)) : F32), (w2 + (a2 * step) : F32)}
    case _ _ _ _ _ _: Sim{False{}, t1, w1, t2, w2}

def advance(+libm: M.Libm, +step: F32, +step2: F32, +sim: Sim) -> Sim:
  Sim{+valid, +t1, +w1, +t2, +w2} = sim
  +delta = (t1 - t2 : F32)
  stepped(valid, t1, w1, t2, w2, step, step2, M.Libm.sin(libm, delta), M.Libm.cos(libm, delta), M.Libm.cos(libm, (2.0 * delta : F32)),
    M.Libm.sin(libm, t1), M.Libm.sin(libm, (t1 - (2.0 * t2) : F32)), M.Libm.cos(libm, t1))

# for (int i = 0; i < SIMULATION_STEPS; i++).
def steps(n: Nat, +libm: M.Libm, +step: F32, +step2: F32, +sim: Sim) -> Sim:
  match n:
    case 0n: sim
    case 1n+p: steps(p, libm, step, step2, advance(libm, step, step2, sim))

# CalculatePendulumEndPoint(l, theta) = (10*l*sinf(theta), 10*l*cosf(theta)) for both rods.
def ends.at(s1: Maybe<F32>, c1: Maybe<F32>, s2: Maybe<F32>, c2: Maybe<F32>) -> Ends:
  match s1 c1 s2 c2:
    case Some{+a} Some{+b} Some{+c} Some{+d}:
      Ends{True{}, M.Vector2{((10.0 * 15.0) * a : F32), ((10.0 * 15.0) * b : F32)}, M.Vector2{((10.0 * 15.0) * c : F32), ((10.0 * 15.0) * d : F32)}}
    case _ _ _ _: Ends{False{}, M.Vector2.zero(), M.Vector2.zero()}

# CalculateDoublePendulumEndPoint, moved by (screenWidth/2, screenHeight/2 - 100).
def placed.at(+previous: M.Vector2, +sim: Sim, +ends: Ends) -> Pendulum:
  Sim{+valid, +t1, +w1, +t2, +w2} = sim
  Ends{+ok, +end1, +end2} = ends
  M.Vector2{+x, +y} = end1
  M.Vector2{+u, +v} = end2
  Pendulum{valid && ok, t1, w1, t2, w2, end1, previous, M.Vector2{((x + u) + (800.0 / 2.0) : F32), ((y + v) + (450.0 / 2.0 - 100.0) : F32)}}

def placed(+libm: M.Libm, +previous: M.Vector2, +sim: Sim) -> Pendulum:
  Sim{_, +t1, _, +t2, _} = sim
  placed.at(previous, sim, ends.at(M.Libm.sin(libm, t1), M.Libm.cos(libm, t1), M.Libm.sin(libm, t2), M.Libm.cos(libm, t2)))

# step = GetFrameTime()/SIMULATION_STEPS; the trail runs from the last end point to the new one.
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{target, +pendulum} = state
  Pendulum{+valid, +t1, +w1, +t2, +w2, _, _, +current} = pendulum
  +step = (J.Core.get_frame_time(core) / 30.0 : F32)
  (core, State{target, placed(libm, current, steps(30n, libm, step, (step * step : F32), Sim{valid, t1, w1, t2, w2}))})

# DrawRectangle(0, 0, 800, 450, Fade(BLACK, 0.01f)); DrawCircleV(previous, 2, RED);
# DrawLineEx(previous, current, 4, RED).
def trail(+libm: M.Libm, +pendulum: Pendulum, frame: J.Frame) -> J.Frame:
  Pendulum{_, _, _, _, _, _, +previous, +current} = pendulum
  f1 = J.Draw.rectangle(frame, 0.0, 0.0, 800.0, 450.0, J.Color.with_alpha(J.Color.BLACK(), 0.01))
  f2 = J.Draw.circle_v_for(libm, f1, previous, 2.0, J.Color.RED())
  J.Draw.line_ex(f2, previous, current, (2.0 * 2.0 : F32), J.Color.RED())

# The rods: (400, 125, 10*l1, 20) turned 90 - RAD2DEG*theta1 about (0, 10),
# and the second from the first's end point.
def rods(+libm: M.Libm, +pendulum: Pendulum, frame: J.Frame) -> J.Frame:
  Pendulum{_, +t1, _, +t2, _, +end1, _, _} = pendulum
  M.Vector2{+x, +y} = end1
  f1 = J.Draw.rectangle_pro_for(libm, frame, J.Rectangle{(800.0 / 2.0 : F32), (450.0 / 2.0 - 100.0 : F32), (10.0 * 15.0 : F32), 20.0},
    M.Vector2{0.0, (20.0 * 0.5 : F32)}, (90.0 - M.Math.RAD2DEG() * t1 : F32), J.Color.RAYWHITE())
  J.Draw.rectangle_pro_for(libm, f1, J.Rectangle{(800.0 / 2.0 + x : F32), ((450.0 / 2.0 - 100.0) + y : F32), (10.0 * 15.0 : F32), 20.0},
    M.Vector2{0.0, (20.0 * 0.5 : F32)}, (90.0 - M.Math.RAD2DEG() * t2 : F32), J.Color.RAYWHITE())

def shown(+id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, texture) = r
  (frame, Some{J.RenderTexture{id, texture, depth}})

# DrawTextureRec(target.texture, (0, 0, width, -height), (0, 0), WHITE).
def show(frame: J.Frame, target: J.RenderTexture) -> J.Frame & Maybe<J.RenderTexture>:
  J.RenderTexture{+id, texture, +depth} = target
  J.Texture{+tid, +w, +h, +format, +linear, +alpha, texels} = texture
  shown(id, depth, J.Draw.texture_rec(frame, J.Texture{tid, w, h, format, linear, alpha, texels},
    J.Rectangle{0.0, 0.0, U32.to_f32(w), F32.neg(U32.to_f32(h))}, M.Vector2.zero(), J.Color.WHITE()))

def draw.rods(+libm: M.Libm, +core: J.Core, +pendulum: Pendulum, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  (core, (State{target, pendulum}, rods(libm, pendulum, frame)))

def draw.screen(+libm: M.Libm, +core: J.Core, +pendulum: Pendulum, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  match target:
    case None{}: draw.rods(libm, core, pendulum, (J.Frame.clear_background(frame, J.Color.BLACK()), None{}))
    case Some{t}: draw.rods(libm, core, pendulum, show(J.Frame.clear_background(frame, J.Color.BLACK()), t))

def draw.textured(+libm: M.Libm, +core: J.Core, +pendulum: Pendulum, frame: J.Frame, target: Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  match target:
    case Some{t}: draw.screen(libm, core, pendulum, J.Frame.end_texture_mode(trail(libm, pendulum, J.Frame.begin_texture_mode(frame, t))))
    case None{}: draw.rods(libm, core, pendulum, (J.Frame.clear_background(frame, J.Color.BLACK()), None{}))

def draw.valid(valid: Bool, +libm: M.Libm, +core: J.Core, +pendulum: Pendulum, frame: J.Frame, target: Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  match valid:
    case True{}: draw.textured(libm, core, pendulum, frame, target)
    case False{}: (core, (State{target, pendulum}, J.Frame.refuse(frame)))

# The trail pass (raylib draws it before BeginDrawing; here the draw does
# that first, the same pixels), then the screen.
def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{target, +pendulum} = state
  Pendulum{+valid, _, _, _, _, _, _, _} = pendulum
  draw.valid(valid, libm, core, pendulum, frame, target)

# The main loop's body; libm is the profile of the simulation's sinf/cosf, DrawCircleV's and DrawRectanglePro's.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# previousPosition starts at the end point.
def started(+pendulum: Pendulum) -> Pendulum:
  Pendulum{+valid, +t1, +w1, +t2, +w2, +end1, _, +current} = pendulum
  Pendulum{valid, t1, w1, t2, w2, end1, current, current}

# SetTextureFilter(target.texture, TEXTURE_FILTER_BILINEAR).
def filtered(target: Maybe<J.RenderTexture>) -> Maybe<J.RenderTexture>:
  match target:
    case None{}: None{}
    case Some{t}:
      J.RenderTexture{+id, texture, +depth} = t
      Some{J.RenderTexture{id, J.Texture.set_filter(texture, J.TextureFilter.TEXTURE_FILTER_BILINEAR()), depth}}

def setup.loaded(+libm: M.Libm, +core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  (J.Core.set_target_fps(core, 60), (frame, State{filtered(target),
    started(placed(libm, M.Vector2.zero(), Sim{True{}, (M.Math.DEG2RAD() * 170.0 : F32), 0.0, (M.Math.DEG2RAD() * 0.0 : F32), 0.0}))}))

# After SetConfigFlags(FLAG_WINDOW_HIGHDPI) and InitWindow(800, 450): theta1 =
# DEG2RAD*170, the 800x450 render texture, SetTargetFPS(60).
def setup(+libm: M.Libm, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.loaded(libm, core, J.RenderTexture.load(frame, 800, 450))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - double pendulum", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(M.Glibc239Libm{}, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
