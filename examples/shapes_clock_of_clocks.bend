# raylib [shapes] example - clock of clocks, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_clock_of_clocks.c
# (zlib/libpng, Copyright (c) 2025 JP Mortiboys (@themushroompirates)); see
# LICENSES/raylib.txt.
#
# The time of day as six digits, each drawn by a 4x6 grid of small clocks
# whose two hands turn to trace it; when the second changes the hands move
# to the new digit in half a second. SPACE switches 12 and 24 hours. The
# example reads the C library's time() and localtime() every frame; Base has
# no wall clock, so here the time is the seconds of the day at InitWindow, a
# setup argument, plus the whole seconds of GetTime (docs/DRIVER.md). The
# rings' and DrawRectanglePro's sinf/cosf follow the libm profile: the hands
# turn by arbitrary angles on their way, which the Apple profile does not
# cover (docs/SINCOSF.md).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# valid: no refusal so far. start is the seconds of the day at InitWindow and
# previous prevSeconds (none yet: 4294967295). current, source and target are
# currentAngles, srcAngles and dstAngles: the six digits' 24 cells in order,
# the big hand's angle in x and the little one's in y. timer is
# handsMoveTimer and mode hourMode.
type State is Data:
  State{valid: Bool, start: U32, previous: U32, current: +List<M.Vector2>, source: +List<M.Vector2>, target: +List<M.Vector2>, timer: F32, mode: U32}

# The hands of a cell: TL (0), TR, BR, BL, HH, VV and ZZ (6, not relevant).
def angles(symbol: U32) -> M.Vector2:
  match symbol:
    case 0: M.Vector2{0.0, 90.0}
    case 1: M.Vector2{90.0, 180.0}
    case 2: M.Vector2{180.0, 270.0}
    case 3: M.Vector2{0.0, 270.0}
    case 4: M.Vector2{0.0, 180.0}
    case 5: M.Vector2{90.0, 270.0}
    case _: M.Vector2{135.0, 135.0}

# digitAngles[digit]: its 24 cells, row by row.
def cells(digit: U32) -> +List<U32>:
  match digit:
    case 0: [0, 4, 4, 1, 5, 0, 1, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 2, 5, 3, 4, 4, 2]
    case 1: [0, 4, 1, 6, 3, 1, 5, 6, 6, 5, 5, 6, 6, 5, 5, 6, 0, 2, 3, 1, 3, 4, 4, 2]
    case 2: [0, 4, 4, 1, 3, 4, 1, 5, 0, 4, 2, 5, 5, 0, 4, 2, 5, 3, 4, 1, 3, 4, 4, 2]
    case 3: [0, 4, 4, 1, 3, 4, 1, 5, 0, 4, 2, 5, 3, 4, 1, 5, 0, 4, 2, 5, 3, 4, 4, 2]
    case 4: [0, 1, 0, 1, 5, 5, 5, 5, 5, 3, 2, 5, 3, 4, 1, 5, 6, 6, 5, 5, 6, 6, 3, 2]
    case 5: [0, 4, 4, 1, 5, 0, 4, 2, 5, 3, 4, 1, 3, 4, 1, 5, 0, 4, 2, 5, 3, 4, 4, 2]
    case 6: [0, 4, 4, 1, 5, 0, 4, 2, 5, 3, 4, 1, 5, 0, 1, 5, 5, 3, 2, 5, 3, 4, 4, 2]
    case 7: [0, 4, 4, 1, 3, 4, 1, 5, 6, 6, 5, 5, 6, 6, 5, 5, 6, 6, 5, 5, 6, 6, 3, 2]
    case 8: [0, 4, 4, 1, 5, 0, 1, 5, 5, 3, 2, 5, 5, 0, 1, 5, 5, 3, 2, 5, 3, 4, 4, 2]
    case _: [0, 4, 4, 1, 5, 0, 1, 5, 5, 3, 2, 5, 3, 4, 1, 5, 0, 4, 2, 5, 3, 4, 4, 2]

# A digit's cells in front of the rest; blank is the 12-hour mode's leading 0 (every cell ZZ).
def cells.of(symbols: +List<U32>, +blank: Bool, +rest: +List<M.Vector2>) -> +List<M.Vector2>:
  match symbols:
    case Nil{}: rest
    case Con{+symbol, more}: Con{angles(Bool.pick(U32, blank, 6, symbol)), cells.of(more, blank, rest)}

# dstAngles for the digits of TextFormat("%02d%02d%02d", hour%hourMode, minute, second).
def targets(digits: +List<U32>, +twelve: Bool, +first: Bool) -> +List<M.Vector2>:
  match digits:
    case Nil{}: Nil{}
    case Con{+digit, rest}: cells.of(cells(digit), first && twelve && U32.is_eq(digit, 0), targets(rest, twelve, False{}))

# if (src > dst) src -= 360.0f.
def wound(+from: F32, +to: F32) -> F32:
  Bool.pick(F32, (from > to : F32), (from - 360.0 : F32), from)

def source.of(+current: M.Vector2, +target: M.Vector2) -> M.Vector2:
  M.Vector2{+cx, +cy} = current
  M.Vector2{+tx, +ty} = target
  M.Vector2{wound(cx, tx), wound(cy, ty)}

# srcAngles: currentAngles, a turn back where it is past the target.
def sources(current: +List<M.Vector2>, target: +List<M.Vector2>) -> +List<M.Vector2>:
  match current target:
    case Con{+c, cs} Con{+t, ts}: Con{source.of(c, t), sources(cs, ts)}
    case _ _: Nil{}

def lerp.of(+source: M.Vector2, +target: M.Vector2, +t: F32) -> M.Vector2:
  M.Vector2{+sx, +sy} = source
  M.Vector2{+tx, +ty} = target
  M.Vector2{(sx + t * (tx - sx) : F32), (sy + t * (ty - sy) : F32)}

# currentAngles = Lerp(srcAngles, dstAngles, t).
def lerped(source: +List<M.Vector2>, target: +List<M.Vector2>, +t: F32) -> +List<M.Vector2>:
  match source target:
    case Con{+s, ss} Con{+g, gs}: Con{lerp.of(s, g, t), lerped(ss, gs, t)}
    case _ _: Nil{}

def placed(moving: Bool, +current: +List<M.Vector2>, +source: +List<M.Vector2>, +target: +List<M.Vector2>, +t: F32) -> +List<M.Vector2>:
  match moving:
    case False{}: current
    case True{}: lerped(source, target, t)

# The hands on their way: handsMoveTimer = Clamp(handsMoveTimer + GetFrameTime(), 0, handsMoveDuration); t = timer/duration;
# t = t*t*(3.0f - 2.0f*t); every hand at Lerp(src, dst, t). SPACE: hourMode = 36 - hourMode.
def update.moved(+core: J.Core, +start: U32, +previous: U32, +current: +List<M.Vector2>, +source: +List<M.Vector2>, +target: +List<M.Vector2>, +timer: F32, +mode: U32) -> State:
  +moving = (timer < 0.5 : F32)
  +clamped = M.Math.clamp((timer + J.Core.get_frame_time(core) : F32), 0.0, 0.5)
  +t = (clamped / 0.5 : F32)
  +smooth = ((t * t) * (3.0 - 2.0 * t) : F32)
  State{True{}, start, previous, placed(moving, current, source, target, smooth), source, target, Bool.pick(F32, moving, clamped, timer),
    Bool.pick(U32, J.Input.is_key_pressed(core, 32), (36 - mode : U32), mode)}

# The second changed: the hands start from where they are toward the new digits; handsMoveTimer = -GetFrameTime().
def update.ticked(+core: J.Core, +start: U32, +seconds: U32, +current: +List<M.Vector2>, +mode: U32) -> State:
  +hour = (((seconds / 3600) % 24) % mode : U32)
  +minute = ((seconds / 60) % 60 : U32)
  +second = (seconds % 60 : U32)
  +target = targets([(hour / 10 : U32), (hour % 10 : U32), (minute / 10 : U32), (minute % 10 : U32), (second / 10 : U32), (second % 10 : U32)], U32.is_eq(mode, 12), True{})
  update.moved(core, start, second, current, sources(current, target), target, F32.neg(J.Core.get_frame_time(core)), mode)

def update.timed(+core: J.Core, +state: State, elapsed: Maybe<U32>) -> State:
  State{_, +start, +previous, +current, +source, +target, +timer, +mode} = state
  match elapsed:
    case None{}: State{False{}, start, previous, current, source, target, timer, mode}
    case Some{+e}: Bool.pick(State, U32.is_ne(((start + e) % 60 : U32), previous), update.ticked(core, start, (start + e : U32), current, mode),
      update.moved(core, start, previous, current, source, target, timer, mode))

# time(&rawtime); localtime(&rawtime), here start plus GetTime's whole seconds.
def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, update.timed(core, state, M.Float64.to_int(J.Core.get_time(core))))

# handsColor = ColorLerp(YELLOW, RAYWHITE, .25f).
def hands() -> U32:
  J.Color.lerp(J.Color.YELLOW(), J.Color.RAYWHITE(), 0.25)

# After an odd digit: the two rings between the pairs, at xOffset + 4 once the digit's width was added.
def separators(odd: Bool, +libm: M.Libm, +x: F32, frame: J.Frame) -> J.Frame:
  match odd:
    case False{}: frame
    case True{}: J.Draw.ring_for(libm, J.Draw.ring_for(libm, frame, M.Vector2{x, 160.0}, 6.0, 8.0, 0.0, 360.0, 24.0, hands()), M.Vector2{x, 225.0}, 6.0, 8.0, 0.0, 360.0, 24.0, hands())

# A small clock: its ring and its two hands.
def face(+libm: M.Libm, frame: J.Frame, +cx: F32, +cy: F32, +angle: M.Vector2) -> J.Frame:
  M.Vector2{+big, +little} = angle
  f1 = J.Draw.ring_for(libm, frame, M.Vector2{cx, cy}, (24.0 * 0.5 - 2.0 : F32), (24.0 * 0.5 : F32), 0.0, 360.0, 24.0, J.Color.DARKGRAY())
  f2 = J.Draw.rectangle_pro_for(libm, f1, J.Rectangle{cx, cy, (24.0 * 0.5 + 4.0 : F32), 4.0}, M.Vector2{2.0, 2.0}, big, hands())
  J.Draw.rectangle_pro_for(libm, f2, J.Rectangle{cx, cy, (24.0 * 0.5 + 2.0 : F32), 4.0}, M.Vector2{2.0, 2.0}, little, hands())

# The cells in order: cell i is digit i/24, row (i%24)/4, column i%4; xOffset starts at 4, grows by four cells a
# digit and by sectionSpacing (16) after each odd one.
def faces(list: +List<M.Vector2>, +i: U32, +libm: M.Libm, frame: J.Frame) -> J.Frame:
  match list:
    case Nil{}: frame
    case Con{+angle, rest}:
      +digit = (i / 24 : U32)
      +offset = (4.0 + U32.to_f32((digit * 128 + (digit / 2) * 16 : U32)) : F32)
      drawn = face(libm, frame, ((offset + U32.to_f32((i % 4 : U32)) * (24.0 + 8.0)) + 24.0 * 0.5 : F32), ((100.0 + U32.to_f32(((i % 24) / 4 : U32)) * (24.0 + 8.0)) + 24.0 * 0.5 : F32), angle)
      faces(rest, (i + 1 : U32), libm, separators(U32.is_eq((i % 24 : U32), 23) && U32.is_eq((digit % 2 : U32), 1), libm, ((offset + (24.0 + 8.0) * 4.0) + 4.0 : F32), drawn))

def label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, 30.0, 20.0, J.Color.RAYWHITE())

def draw.fps.at(+state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps(+state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

# ClearBackground(bgColor), bgColor = ColorLerp(DARKBLUE, BLACK, 0.75f); the mode; the clocks; DrawFPS(10, 10).
def draw.at(valid: Bool, +libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid:
    case False{}: (core, (state, J.Frame.refuse(frame)))
    case True{}:
      State{_, _, _, +current, _, _, _, +mode} = state
      f1 = label(J.Text.format("%d-h mode, space to change", [J.TextInt{mode}]), J.Frame.clear_background(frame, J.Color.lerp(J.Color.DARKBLUE(), J.Color.BLACK(), 0.75)))
      draw.fps(state, faces(current, 0, libm, f1), J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, _, _, _, _, _, _, _} = state
  draw.at(valid, libm, core, state, frame)

# The main loop's body; libm is the sinf/cosf profile of the rings and DrawRectanglePro.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def zeros(n: Nat) -> +List<M.Vector2>:
  match n:
    case 0n: Nil{}
    case 1n+k: Con{M.Vector2{0.0, 0.0}, zeros(k)}

# After SetConfigFlags(FLAG_MSAA_4X_HINT) and InitWindow(800, 450): every hand at 0, prevSeconds -1, the 24-hour mode,
# SetTargetFPS(60). seconds is the time of day at InitWindow (0 to 86399).
def setup(+seconds: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{True{}, seconds, 4294967295, zeros(144n), zeros(144n), zeros(144n), 0.0, 24}))

# The time of day is the "--time" argument (seconds; 0 without one): docs/DRIVER.md.
def run.clocked(r: U32 & U32) -> IO(Unit):
  (+frames, +seconds) = r
  J.Desktop.run_flags(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, 32, "raylib [shapes] example - clock of clocks", 800, 450, frames,
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(seconds, core, frame)))

def run(args: List<String>) -> IO(Unit):
  run.clocked(J.Desktop.clock_args(args))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
