# raylib [shapes] example - math sine cosine, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_math_sine_cosine.c
# (zlib/libpng, Copyright (c) 2025 Jopestpe (@jopestpe)); see
# LICENSES/raylib.txt.
#
# The unit circle with the sine, cosine, tangent and cotangent of an angle
# that advances a degree a frame (the Pause toggle stops it, the slider sets
# it), the two waves and the complementary, supplementary and explementary
# angles. sinf, cosf and tanf come from the M.Libm profile: a profile without
# them (tanf is glibc 2.39's only) refuses the frame. The controls are raygui's
# (Jongui): GuiToggle, GuiSliderBar and GuiGroupBox, which run inside the
# drawing and change the angle and the pause of the next frame, so the whole
# loop body is the draw step. See docs/GUI.md and docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

type State is Data:
  State{gui: G.Gui, angle: F32, pause: Bool, sine: +List<M.Vector2>, cosine: +List<M.Vector2>, ok: Bool}

def float(+word: U32) -> F32:
  U32{bits} = word
  F32{bits}

# DEG2RAD (PI/180.0f).
def deg2rad() -> F32:
  float(1016003125)

# The two waves: 36 points over start = (20, 330, 200, 100); ok is False when a sine or cosine is refused.
type Waves is Data:
  Waves{ok: Bool, sine: +List<M.Vector2>, cosine: +List<M.Vector2>}

def waves.more(+x: F32, +sv: F32, +cv: F32, +rest: Waves) -> Waves:
  Waves{+ok, +sine, +cosine} = rest
  Waves{ok, Con{M.Vector2{x, (380.0 - sv * 50.0 : F32)}, sine}, Con{M.Vector2{x, (380.0 - cv * 50.0 : F32)}, cosine}}

def waves.joined(s: Maybe<F32>, c: Maybe<F32>, +x: F32, +rest: Waves) -> Waves:
  match s c:
    case Some{+sv} Some{+cv}: waves.more(x, sv, cv, rest)
    case _ _: Waves{False{}, Nil{}, Nil{}}

# t = i/35.0f, currentAngle = t*360.0f*DEG2RAD, from the last point back to the first.
def waves(n: Nat, +libm: M.Libm, +index: F32, +rest: Waves) -> Waves:
  match n:
    case 0n: rest
    case 1n+p:
      +t = (index / 35.0 : F32)
      +angle = ((t * 360.0 : F32) * deg2rad() : F32)
      waves(p, libm, (index - 1.0 : F32), waves.joined(M.Libm.sin(libm, angle), M.Libm.cos(libm, angle), (20.0 + t * 200.0 : F32), rest))

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def text6(text: Maybe<String>, +y: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 640.0, y, 6.0, color)

def v(+x: F32, +y: F32) -> M.Vector2:
  M.Vector2{x, y}

# Everything up to the controls. s, c and tangent are of the angle before it advanced, turn is the new angle.
def scene(+libm: M.Libm, +s: F32, +c: F32, +tangent: F32, +old: F32, +turn: F32, +sine: +List<M.Vector2>, +cosine: +List<M.Vector2>, frame: J.Frame) -> J.Frame:
  +px = (370.0 + c * 130.0 : F32)
  +py = (225.0 - s * 130.0 : F32)
  +cotangent = Bool.pick(F32, (F32.abs(tangent) > float(981668463) : F32), M.Math.clamp((1.0 / tangent : F32), F32.neg(130.0), 130.0), 0.0)
  +tx = (370.0 + cotangent * 130.0 : F32)
  +ty = (225.0 - tangent * 130.0 : F32)
  +wave = (20.0 + (turn / 360.0) * 200.0 : F32)
  f1 = J.Draw.line_ex(J.Frame.clear_background(frame, J.Color.RAYWHITE()), v(370.0, 95.0), v(tx, 95.0), 2.0, J.Color.ORANGE())
  f2 = J.Draw.line_dashed(f1, v(370.0, 225.0), v(tx, 95.0), 10.0, 4.0, J.Color.ORANGE())
  f3 = J.Draw.rectangle(J.Draw.line(f2, 580.0, 0.0, 580.0, 450.0, J.Color.rgba(218, 218, 218, 255)), 580.0, 0.0, 800.0, 450.0, J.Color.rgba(232, 232, 232, 255))
  f4 = J.Draw.circle_lines_v_for(libm, f3, v(370.0, 225.0), 130.0, J.Color.GRAY())
  f5 = J.Draw.line_ex(J.Draw.line_ex(f4, v(370.0, 95.0), v(370.0, 355.0), 1.0, J.Color.GRAY()), v(240.0, 225.0), v(500.0, 225.0), 1.0, J.Color.GRAY())
  f6 = J.Draw.line_ex(J.Draw.line_ex(f5, v(20.0, 330.0), v(20.0, 430.0), 2.0, J.Color.GRAY()), v(220.0, 330.0), v(220.0, 430.0), 2.0, J.Color.GRAY())
  f7 = J.Draw.line_ex(f6, v(20.0, 380.0), v(220.0, 380.0), 2.0, J.Color.GRAY())
  f8 = J.Draw.text(J.Draw.text(J.Draw.text(f7, "1", 12.0, 330.0, 6.0, J.Color.GRAY()), "0", 12.0, 374.0, 6.0, J.Color.GRAY()), "-1", 8.0, 422.0, 6.0, J.Color.GRAY())
  f9 = J.Draw.text(J.Draw.text(f8, "0", 18.0, 434.0, 6.0, J.Color.GRAY()), "360", 212.0, 434.0, 6.0, J.Color.GRAY())
  f10 = J.Draw.line_dashed(J.Draw.line_ex(f9, v(370.0, 225.0), v(370.0, py), 2.0, J.Color.RED()), v(px, 225.0), v(px, py), 10.0, 4.0, J.Color.RED())
  f11 = text6(J.Text.format("Sine %.2f", [J.TextFloat{s}]), 190.0, J.Color.RED(), f10)
  f12 = J.Draw.spline_linear(J.Draw.circle_v_for(libm, f11, v(wave, (330.0 + ((F32.neg(s) + 1.0) * 100.0) / 2.0 : F32)), 4.0, J.Color.RED()), sine, 1.0, J.Color.RED())
  f13 = J.Draw.line_dashed(J.Draw.line_ex(f12, v(370.0, 225.0), v(px, 225.0), 2.0, J.Color.BLUE()), v(370.0, py), v(px, py), 10.0, 4.0, J.Color.BLUE())
  f14 = text6(J.Text.format("Cosine %.2f", [J.TextFloat{c}]), 210.0, J.Color.BLUE(), f13)
  f15 = J.Draw.spline_linear(J.Draw.circle_v_for(libm, f14, v(wave, (330.0 + ((F32.neg(c) + 1.0) * 100.0) / 2.0 : F32)), 4.0, J.Color.BLUE()), cosine, 1.0, J.Color.BLUE())
  f16 = J.Draw.line_dashed(J.Draw.line_ex(f15, v(500.0, 225.0), v(500.0, ty), 2.0, J.Color.PURPLE()), v(370.0, 225.0), v(500.0, ty), 10.0, 4.0, J.Color.PURPLE())
  f17 = text6(J.Text.format("Cotangent %.2f", [J.TextFloat{cotangent}]), 250.0, J.Color.ORANGE(), text6(J.Text.format("Tangent %.2f", [J.TextFloat{tangent}]), 230.0, J.Color.PURPLE(), f16))
  f18 = text6(J.Text.format("Complementary  %0.f\u{c2}\u{b0}", [J.TextFloat{(90.0 - old : F32)}]), 150.0, J.Color.BEIGE(),
    J.Draw.circle_sector_lines_for(libm, f17, v(370.0, 225.0), (130.0 * float(1058642330) : F32), F32.neg(turn), F32.neg(90.0), 36.0, J.Color.BEIGE()))
  f19 = text6(J.Text.format("Supplementary  %0.f\u{c2}\u{b0}", [J.TextFloat{(180.0 - old : F32)}]), 130.0, J.Color.DARKBLUE(),
    J.Draw.circle_sector_lines_for(libm, f18, v(370.0, 225.0), (130.0 * 0.5 : F32), F32.neg(turn), F32.neg(180.0), 36.0, J.Color.DARKBLUE()))
  f20 = text6(J.Text.format("Explementary  %0.f\u{c2}\u{b0}", [J.TextFloat{(360.0 - old : F32)}]), 170.0, J.Color.PINK(),
    J.Draw.circle_sector_lines_for(libm, f19, v(370.0, 225.0), (130.0 * float(1053609165) : F32), F32.neg(turn), F32.neg(360.0), 36.0, J.Color.PINK()))
  f21 = J.Draw.circle_sector_lines_for(libm, f20, v(370.0, 225.0), (130.0 * float(1060320051) : F32), F32.neg(turn), 0.0, 36.0, J.Color.LIME())
  J.Draw.circle_v_for(libm, J.Draw.line_ex(f21, v(370.0, 225.0), v(px, py), 2.0, J.Color.BLACK()), v(px, py), 4.0, J.Color.BLACK())

def draw.fps.at(+state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(+state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# GuiGroupBox((620, 110, 140, 170), "Angle Values"), DrawFPS(10, 10).
def controls.boxed(+core: J.Core, +pause: Bool, +sine: +List<M.Vector2>, +cosine: +List<M.Vector2>, +gui: G.Gui, +angle: F32, frame: J.Frame) -> J.Core & (State & J.Frame):
  draw.fps.done(State{gui, angle, pause, sine, cosine, True{}}, G.Gui.group_box(gui, frame, J.Rectangle{620.0, 110.0, 140.0, 170.0}, Some{"Angle Values"}),
    J.Core.get_fps(core, J.Core.get_time(core)), core)

def controls.value(+core: J.Core, +pause: Bool, +sine: +List<M.Vector2>, +cosine: +List<M.Vector2>, +gui: G.Gui, frame: J.Frame, pair: F32 & Bool) -> J.Core & (State & J.Frame):
  (+angle, _) = pair
  controls.boxed(core, pause, sine, cosine, gui, angle, frame)

def controls.gui(+core: J.Core, +pause: Bool, +sine: +List<M.Vector2>, +cosine: +List<M.Vector2>, frame: J.Frame, rest: G.Gui & (F32 & Bool)) -> J.Core & (State & J.Frame):
  (+gui, pair) = rest
  controls.value(core, pause, sine, cosine, gui, frame, pair)

def controls.slid(+core: J.Core, +pause: Bool, +sine: +List<M.Vector2>, +cosine: +List<M.Vector2>, r: J.Frame & (G.Gui & (F32 & Bool))) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  controls.gui(core, pause, sine, cosine, frame, rest)

# GuiSetStyle(LABEL, TEXT_COLOR_NORMAL, LIME) and GuiSliderBar((640, 40, 120, 20), "Angle", TextFormat("%.0f°", angle), &angle, 0, 360).
def controls.slider(text: Maybe<String>, +core: J.Core, +pause: Bool, +sine: +List<M.Vector2>, +cosine: +List<M.Vector2>, +gui: G.Gui, +angle: F32, frame: J.Frame) -> J.Core & (State & J.Frame):
  match text:
    case None{}: (core, (State{gui, angle, pause, sine, cosine, False{}}, J.Frame.refuse(frame)))
    case Some{t}: controls.slid(core, pause, sine, cosine, G.Gui.slider_bar(G.Gui.set_style(gui, 1, 2, J.Color.LIME()), core, frame, J.Rectangle{640.0, 40.0, 120.0, 20.0}, Some{"Angle"}, Some{t}, angle, 0.0, 360.0))

def controls.toggled(+core: J.Core, +sine: +List<M.Vector2>, +cosine: +List<M.Vector2>, +gui: G.Gui, +angle: F32, r: J.Frame & Bool) -> J.Core & (State & J.Frame):
  (frame, +pause) = r
  controls.slider(J.Text.format("%.0f\u{c2}\u{b0}", [J.TextFloat{angle}]), core, pause, sine, cosine, gui, angle, frame)

# GuiSetStyle(LABEL, TEXT_COLOR_NORMAL, GRAY) and GuiToggle((640, 70, 120, 20), "Pause", &pause).
def controls(+core: J.Core, +gui: G.Gui, +angle: F32, +pause: Bool, +sine: +List<M.Vector2>, +cosine: +List<M.Vector2>, frame: J.Frame) -> J.Core & (State & J.Frame):
  +gray = G.Gui.set_style(gui, 1, 2, J.Color.GRAY())
  controls.toggled(core, sine, cosine, gray, angle, G.Gui.toggle(gray, core, frame, J.Rectangle{640.0, 70.0, 120.0, 20.0}, "Pause", pause))

# angle = Wrap(angle + (!pause ? 1.0f : 0.0f), 0.0f, 360.0f) before the drawing, which uses the new angle
# for the sectors, the wave markers and the slider.
def draw.turned(+libm: M.Libm, +core: J.Core, +state: State, +s: F32, +c: F32, +tangent: F32, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +angle, +pause, +sine, +cosine, _} = state
  +turn = M.Math.wrap((angle + Bool.pick(F32, pause, 0.0, 1.0) : F32), 0.0, 360.0)
  controls(core, gui, turn, pause, sine, cosine, scene(libm, s, c, tangent, angle, turn, sine, cosine, frame))

def draw.known(s: Maybe<F32>, c: Maybe<F32>, tangent: Maybe<F32>, +libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  match s c tangent:
    case Some{+sv} Some{+cv} Some{+tv}: draw.turned(libm, core, state, sv, cv, M.Math.clamp(tv, F32.neg(10.0), 10.0), frame)
    case _ _ _: (core, (state, J.Frame.refuse(frame)))

def draw.valid(valid: Bool, +libm: M.Libm, +core: J.Core, +state: State, +radians: F32, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid:
    case False{}: (core, (state, J.Frame.refuse(frame)))
    case True{}: draw.known(M.Libm.sin(libm, radians), M.Libm.cos(libm, radians), M.Libm.tanf(libm, radians), libm, core, state, frame)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{_, +angle, _, _, _, +ok} = state
  draw.valid(ok, libm, core, state, (angle * deg2rad() : F32), frame)

# The main loop's body; libm is the profile of sinf, cosf and tanf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def started(+waves: Waves) -> State:
  Waves{+ok, +sine, +cosine} = waves
  State{G.Gui.new(), 0.0, False{}, sine, cosine, ok}

# After InitWindow(800, 450): the two waves, angle 0, SetTargetFPS(60).
def setup(+libm: M.Libm, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, started(waves(36n, libm, 35.0, Waves{True{}, Nil{}, Nil{}}))))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run_flags(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, J.ConfigFlags.FLAG_MSAA_4X_HINT(), "raylib [shapes] example - math sine cosine", 800, 450,
    J.Desktop.frames_arg(args), core => frame => IO.pure(J.Core & (J.Frame & State), setup(M.Glibc239Libm{}, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
