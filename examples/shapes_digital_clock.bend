# raylib [shapes] example - digital clock, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_digital_clock.c
# (zlib/libpng, Copyright (c) 2025 Hamza RAHAL (@hmz-rhl) and Ramon
# Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# The time of day on a seven-segment display made of triangle strips, with
# its text below, or (SPACE) on an analog face. The example reads the C
# library's time() and localtime() every frame; Base has no wall clock, so
# here the time is the seconds of the day at InitWindow, a setup argument
# (as a seeded example takes its seed), plus the whole seconds of GetTime
# (docs/DRIVER.md). The face's marks take the libm profile's sinf/cosf of
# whole degrees, and DrawRectanglePro turns the hands by angles that are
# tenths of a degree: under a profile without them the frame is refused
# (docs/SINCOSF.md).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: no refusal so far. start is the seconds of the day at InitWindow;
# analog is clockMode == CLOCK_ANALOG; hour, minute and second are the
# hands' values (tm_hour, tm_min, tm_sec).
type State is Data:
  State{valid: Bool, start: U32, analog: Bool, hour: U32, minute: U32, second: U32}

# UpdateClock: time(&rawtime); localtime(&rawtime), here start plus GetTime's whole seconds.
def clock(elapsed: Maybe<U32>, +start: U32, +analog: Bool) -> State:
  match elapsed:
    case None{}: State{False{}, start, analog, 0, 0, 0}
    case Some{+seconds}: State{True{}, start, analog, (((start + seconds) / 3600) % 24 : U32), (((start + seconds) / 60) % 60 : U32), ((start + seconds) % 60 : U32)}

# SPACE toggles the clock mode; UpdateClock(&clock).
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{_, +start, +analog, _, _, _} = state
  (core, clock(M.Float64.to_int(J.Core.get_time(core)), start, Bool.pick(Bool, J.Input.is_key_pressed(core, 32), Bool.not(analog), analog)))

# A horizontal segment's six points around its center (length 60, thick 20), as a triangle strip.
def segment.flat(frame: J.Frame, +cx: F32, +cy: F32, +color: U32) -> J.Frame:
  J.Draw.triangle_strip(frame, [M.Vector2{((cx - 60.0 / 2.0) - 20.0 / 2.0 : F32), cy}, M.Vector2{(cx - 60.0 / 2.0 : F32), (cy + 20.0 / 2.0 : F32)},
    M.Vector2{(cx - 60.0 / 2.0 : F32), (cy - 20.0 / 2.0 : F32)}, M.Vector2{(cx + 60.0 / 2.0 : F32), (cy + 20.0 / 2.0 : F32)},
    M.Vector2{(cx + 60.0 / 2.0 : F32), (cy - 20.0 / 2.0 : F32)}, M.Vector2{((cx + 60.0 / 2.0) + 20.0 / 2.0 : F32), cy}], color)

# A vertical segment's.
def segment.tall(frame: J.Frame, +cx: F32, +cy: F32, +color: U32) -> J.Frame:
  J.Draw.triangle_strip(frame, [M.Vector2{cx, ((cy - 60.0 / 2.0) - 20.0 / 2.0 : F32)}, M.Vector2{(cx - 20.0 / 2.0 : F32), (cy - 60.0 / 2.0 : F32)},
    M.Vector2{(cx + 20.0 / 2.0 : F32), (cy - 60.0 / 2.0 : F32)}, M.Vector2{(cx - 20.0 / 2.0 : F32), (cy + 60.0 / 2.0 : F32)},
    M.Vector2{(cx + 20.0 / 2.0 : F32), (cy + 60.0 / 2.0 : F32)}, M.Vector2{cx, ((cy + 60.0 / 2.0) + 20.0 / 2.0 : F32)}], color)

# (segments & bit)? colorOn : colorOff, with RED and Fade(LIGHTGRAY, 0.3f).
def lit(+segments: U32, +bit: U32) -> U32:
  Bool.pick(U32, U32.is_ne((segments .&. bit : U32), 0), J.Color.RED(), J.Color.with_alpha(J.Color.LIGHTGRAY(), 0.3))

# Draw7SDisplay: segments A to G (segmentLen 60, segmentThick 20, offsetYAdjust = segmentThick*0.3f).
def display(frame: J.Frame, +x: F32, +y: F32, +segments: U32) -> J.Frame:
  +adjust = (20.0 * 0.3 : F32)
  f1 = segment.flat(frame, ((x + 20.0) + 60.0 / 2.0 : F32), (y + 20.0 : F32), lit(segments, 1))
  f2 = segment.tall(f1, (((x + 20.0) + 60.0) + 20.0 / 2.0 : F32), (((y + 2.0 * 20.0) + 60.0 / 2.0) - adjust : F32), lit(segments, 2))
  f3 = segment.tall(f2, (((x + 20.0) + 60.0) + 20.0 / 2.0 : F32), ((((y + 4.0 * 20.0) + 60.0) + 60.0 / 2.0) - 3.0 * adjust : F32), lit(segments, 4))
  f4 = segment.flat(f3, ((x + 20.0) + 60.0 / 2.0 : F32), (((y + 5.0 * 20.0) + 2.0 * 60.0) - 4.0 * adjust : F32), lit(segments, 8))
  f5 = segment.tall(f4, (x + 20.0 / 2.0 : F32), ((((y + 4.0 * 20.0) + 60.0) + 60.0 / 2.0) - 3.0 * adjust : F32), lit(segments, 16))
  f6 = segment.tall(f5, (x + 20.0 / 2.0 : F32), (((y + 2.0 * 20.0) + 60.0 / 2.0) - adjust : F32), lit(segments, 32))
  segment.flat(f6, ((x + 20.0) + 60.0 / 2.0 : F32), (((y + 3.0 * 20.0) + 60.0) - 2.0 * adjust : F32), lit(segments, 64))

# DrawDisplayValue's segments of a digit.
def pattern(digit: U32) -> U32:
  match digit:
    case 0: 63
    case 1: 6
    case 2: 91
    case 3: 79
    case 4: 102
    case 5: 109
    case 6: 125
    case 7: 7
    case 8: 127
    case _: 111

def digit(frame: J.Frame, +x: F32, +value: U32) -> J.Frame:
  display(frame, x, 60.0, pattern(value))

# The two dots between the displays: RED on odd seconds.
def dots(+libm: M.Libm, frame: J.Frame, +x: F32, +second: U32) -> J.Frame:
  +color = Bool.pick(U32, U32.is_eq((second % 2 : U32), 1), J.Color.RED(), J.Color.with_alpha(J.Color.LIGHTGRAY(), 0.3))
  J.Draw.circle_for(libm, J.Draw.circle_for(libm, frame, x, 130.0, 12.0, color), x, 210.0, 12.0, color)

def centered(width: Maybe<U32>, text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match width text:
    case Some{+w} Some{t}: J.Draw.text(frame, t, U32.to_f32((800 / 2 - w / 2 : U32)), 300.0, 150.0, J.Color.BLACK())
    case _ _: J.Frame.refuse(frame)

def timed(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{+t}: centered(J.Font.measure_text(t, 150.0), Some{t}, frame)

# DrawClockDigital(clock, (30, 60)) and the time in the default font, centered.
def digital(+libm: M.Libm, +hour: U32, +minute: U32, +second: U32, frame: J.Frame) -> J.Frame:
  f1 = dots(libm, digit(digit(frame, 30.0, (hour / 10 : U32)), 150.0, (hour % 10 : U32)), 270.0, second)
  f2 = dots(libm, digit(digit(f1, 290.0, (minute / 10 : U32)), 410.0, (minute % 10 : U32)), 530.0, second)
  timed(J.Text.format("%02i:%02i:%02i", [J.TextInt{hour}, J.TextInt{minute}, J.TextInt{second}]), digit(digit(f2, 550.0, (second / 10 : U32)), 670.0, (second % 10 : U32)))

# A mark of the face: a line from 146 (150 between the fives) to 160 from the center, 3 (1) thick.
def mark(sine: Maybe<F32>, cosine: Maybe<F32>, +five: Bool, frame: J.Frame) -> J.Frame:
  match sine cosine:
    case Some{+s} Some{+c}: J.Draw.line_ex(frame, M.Vector2{(400.0 + Bool.pick(F32, five, 146.0, 150.0) * c : F32), (240.0 + Bool.pick(F32, five, 146.0, 150.0) * s : F32)},
      M.Vector2{(400.0 + 160.0 * c : F32), (240.0 + 160.0 * s : F32)}, Bool.pick(F32, five, 3.0, 1.0), J.Color.DARKGRAY())
    case _ _: J.Frame.refuse(frame)

# The 60 marks at (6.0f*i - 90.0f)*DEG2RAD.
def marks(n: Nat, +i: U32, +libm: M.Libm, frame: J.Frame) -> J.Frame:
  match n:
    case 0n: frame
    case 1n+k: marks(k, (i + 1 : U32), libm, mark(M.Libm.sin(libm, ((6.0 * U32.to_f32(i) - 90.0) * M.Math.DEG2RAD() : F32)),
      M.Libm.cos(libm, ((6.0 * U32.to_f32(i) - 90.0) * M.Math.DEG2RAD() : F32)), U32.is_eq((i % 5 : U32), 0), frame))

# A hand: DrawRectanglePro((position, length, thickness), (0, thickness/2.0f), angle, color).
def hand(+libm: M.Libm, frame: J.Frame, +length: F32, +thickness: F32, +angle: F32, +color: U32) -> J.Frame:
  J.Draw.rectangle_pro_for(libm, frame, J.Rectangle{400.0, 240.0, length, thickness}, M.Vector2{0.0, (thickness / 2.0 : F32)}, angle, color)

# DrawClockAnalog(clock, (400, 240)): the base, the marks and the hands, whose angles UpdateClock sets from the time.
def dial(+libm: M.Libm, +hour: U32, +minute: U32, +second: U32, frame: J.Frame) -> J.Frame:
  f1 = J.Draw.circle_v_for(libm, J.Draw.circle_v_for(libm, frame, M.Vector2{400.0, 240.0}, (140.0 + 40.0 : F32), J.Color.LIGHTGRAY()), M.Vector2{400.0, 240.0}, 12.0, J.Color.GRAY())
  f2 = hand(libm, marks(60n, 0, libm, f1), 140.0, 3.0, (U32.to_f32((second % 60 : U32)) * 6.0 - 90.0 : F32), J.Color.MAROON())
  f3 = hand(libm, f2, 130.0, 7.0, ((U32.to_f32((minute % 60 : U32)) * 6.0 + U32.to_f32(((second % 60) * 6 : U32)) / 60.0) - 90.0 : F32), J.Color.DARKGRAY())
  hand(libm, f3, 100.0, 7.0, (((U32.to_f32((hour % 12 : U32)) * 180.0) / 6.0 + U32.to_f32(((minute % 60) * 30 : U32)) / 60.0) - 90.0 : F32), J.Color.BLACK())

def face(analog: Bool, +libm: M.Libm, +hour: U32, +minute: U32, +second: U32, frame: J.Frame) -> J.Frame:
  match analog:
    case True{}: J.Draw.text(dial(libm, hour, minute, second, frame), "Press [SPACE] to switch clock mode: ANALOGUE CLOCK", 10.0, 10.0, 20.0, J.Color.DARKGRAY())
    case False{}: J.Draw.text(digital(libm, hour, minute, second, frame), "Press [SPACE] to switch clock mode: DIGITAL CLOCK", 10.0, 10.0, 20.0, J.Color.DARKGRAY())

def draw.at(valid: Bool, +libm: M.Libm, +analog: Bool, +hour: U32, +minute: U32, +second: U32, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: J.Frame.refuse(frame)
    case True{}: face(analog, libm, hour, minute, second, J.Frame.clear_background(frame, J.Color.RAYWHITE()))

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, _, +analog, +hour, +minute, +second} = state
  (core, (state, draw.at(valid, libm, analog, hour, minute, second, frame)))

# The main loop's body; libm is the sinf/cosf profile of the face's marks, DrawRectanglePro and the circles.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After SetConfigFlags(FLAG_MSAA_4X_HINT) and InitWindow(800, 450): the clock in digital mode, SetTargetFPS(60).
# seconds is the time of day at InitWindow (0 to 86399).
def setup(+seconds: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{True{}, seconds, False{}, 0, 0, 0}))

# The time of day is the "--time" argument (seconds; 0 without one): docs/DRIVER.md.
def run.clocked(r: U32 & U32) -> IO(Unit):
  (+frames, +seconds) = r
  J.Desktop.run_flags(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, 32, "raylib [shapes] example - digital clock", 800, 450, frames,
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(seconds, core, frame)))

def run(args: List<String>) -> IO(Unit):
  run.clocked(J.Desktop.clock_args(args))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
