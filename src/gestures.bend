# Original additions: zlib, Copyright (c) 2026 Jonathan Peris.
# Altered Bend adaptation of raylib 6.0 src/rgestures.h (Copyright (c)
# 2014-2026 Ramon Santamaria and contributors, zlib, LICENSES/raylib.txt): the
# GESTURES state machine as an explicit value, with rgGetCurrentTime() replaced
# by an explicit binary64 clock argument (the time raylib's GetTime() would
# return at that call).
#
# Arithmetic follows the C source in uncontracted binary32 (rgVector2Distance's
# sqrt of a float sum is the correctly rounded F32 square root), time
# differences in binary64 (src/clock.bend) and rgVector2Angle's
# atan2f(dy, dx)*(180.0f/PI) as a binary64 product narrowed to float. atan2f
# takes the M.Libm angle profile (src/checked_angle.bend): its arguments must be
# zero or normal and its result zero or normal, else the step is None, as is a
# time outside the binary64 helpers' domain. See docs/INPUT.md.
import Base
import ./binary64_fma.bend as W
import ./clock.bend as Clock
import ./checked_angle.bend as CheckedAngle
import ./input.bend as In

# GESTURES.Touch (firstId and Hold.resetRequired are omitted: rgestures.h never
# reads the first nor sets the second).
type Points is Data:
  Points{count: U32, event_time: W.Words, up: In.Point, down_a: In.Point, down_b: In.Point, down_drag: In.Point,
    move_a: In.Point, move_b: In.Point, previous_a: In.Point, previous_b: In.Point, taps: U32}

# The drag distance/intensity and pinch distance are not stored: no query reads them.
type Gestures is Data:
  Gestures{current: U32, enabled: U32, points: Points, hold_time: W.Words, drag_vector: In.Point, drag_angle: F32,
    swipe_start: W.Words, pinch_vector: In.Point, pinch_angle: F32}

def zero2() -> In.Point:
  In.Point{0.0, 0.0}

def Points.new() -> Points:
  Points{0, Clock.zero(), zero2(), zero2(), zero2(), zero2(), zero2(), zero2(), zero2(), zero2(), 0}

# GESTURE_NONE, every gesture enabled (0b0000001111111111).
def Gestures.new() -> Gestures:
  Gestures{0, 1023, Points.new(), Clock.zero(), zero2(), 0.0, Clock.zero(), zero2(), 0.0}

def float(+bits: U32) -> F32:
  U32{b} = bits
  F32{b}

# Constants: TAP_TIMEOUT and DRAG_TIMEOUT 0.3f and their binary64 promotions,
# FORCE_TO_SWIPE 0.2f, MINIMUM_PINCH 0.005f, DOUBLETAP_RANGE 0.03f, 180.0f/PI.
def timeout() -> W.Words:
  W.Words{1070805811, 1073741824}

def force_to_swipe() -> F32:
  float(1045220557)

def minimum_pinch() -> F32:
  float(1000593162)

def doubletap_range() -> F32:
  float(1022739087)

def degrees_per_radian() -> W.Words:
  W.Words{1078765020, 442745336}

def signed_less(+a: U32, +b: U32) -> Bool:
  ((a .^. 2147483648) < (b .^. 2147483648) : U32)

# rgVector2Distance
def distance(+a: In.Point, +b: In.Point) -> F32:
  In.Point{ax, ay} = a
  In.Point{bx, by} = b
  +dx = (bx - ax : F32)
  +dy = (by - ay : F32)
  F32.sqrt((dx * dx + dy * dy : F32))

def difference(+a: In.Point, +b: In.Point) -> In.Point:
  In.Point{ax, ay} = a
  In.Point{bx, by} = b
  In.Point{(bx - ax : F32), (by - ay : F32)}

# rgVector2Angle
def angle.wrap(+angle: F32) -> F32:
  Bool.pick(F32, (angle < 0.0 : F32), (angle + 360.0 : F32), angle)

def angle.wrapped(value: Maybe<F32>) -> Maybe<F32>:
  match value:
    case None{}: None{}
    case Some{+a}: Some{angle.wrap(a)}

def angle.degrees(product: Maybe<W.Words>) -> Maybe<F32>:
  match product:
    case None{}: None{}
    case Some{+value}: angle.wrapped(Clock.narrow(value))

def angle.product(promoted: Maybe<W.Words>) -> Maybe<W.Words>:
  match promoted:
    case None{}: None{}
    case Some{+r}: Clock.multiply(r, degrees_per_radian())

def angle.scaled(radians: Maybe<F32>) -> Maybe<F32>:
  match radians:
    case None{}: None{}
    case Some{+r}: angle.degrees(angle.product(Clock.promote(r)))

def angle.checked(valid: Bool, +profile: U32, +dy: F32, +dx: F32) -> Maybe<F32>:
  match valid:
    case False{}: None{}
    case True{}: angle.scaled(CheckedAngle.maybe(CheckedAngle.scalar(profile, dy, dx)))

def angle(+profile: U32, +a: In.Point, +b: In.Point) -> Maybe<F32>:
  In.Point{+ax, +ay} = a
  In.Point{+bx, +by} = b
  +dy = (by - ay : F32)
  +dx = (bx - ax : F32)
  angle.checked(CheckedAngle.normal_or_zero(dy) && CheckedAngle.normal_or_zero(dx), profile, dy, dx)

# 360.0f - angle
def angle.inverted(angle: Maybe<F32>) -> Maybe<F32>:
  match angle:
    case None{}: None{}
    case Some{a}: Some{(360.0 - a : F32)}

# -----------------------------------------------------------------------------
# Accessors

def Gestures.current(+g: Gestures) -> U32:
  Gestures{current, _, _, _, _, _, _, _, _} = g
  current

def Gestures.enabled(+g: Gestures) -> U32:
  Gestures{_, enabled, _, _, _, _, _, _, _} = g
  enabled

def Gestures.points(+g: Gestures) -> Points:
  Gestures{_, _, points, _, _, _, _, _, _} = g
  points

def Gestures.hold_time(+g: Gestures) -> W.Words:
  Gestures{_, _, _, hold, _, _, _, _, _} = g
  hold

def Gestures.drag_vector(+g: Gestures) -> In.Point:
  Gestures{_, _, _, _, vector, _, _, _, _} = g
  vector

def Gestures.drag_angle(+g: Gestures) -> F32:
  Gestures{_, _, _, _, _, angle, _, _, _} = g
  angle

def Gestures.pinch_vector(+g: Gestures) -> In.Point:
  Gestures{_, _, _, _, _, _, _, vector, _} = g
  vector

def Gestures.pinch_angle(+g: Gestures) -> F32:
  Gestures{_, _, _, _, _, _, _, _, angle} = g
  angle

def Points.count(+p: Points) -> U32:
  Points{count, _, _, _, _, _, _, _, _, _, _} = p
  count

def Gestures.with_current(g: Gestures, +current: U32) -> Gestures:
  Gestures{_, enabled, points, hold, dv, da, swipe, pv, pa} = g
  Gestures{current, enabled, points, hold, dv, da, swipe, pv, pa}

# SetGesturesEnabled
def Gestures.with_enabled(g: Gestures, +enabled: U32) -> Gestures:
  Gestures{current, _, points, hold, dv, da, swipe, pv, pa} = g
  Gestures{current, enabled, points, hold, dv, da, swipe, pv, pa}

def Gestures.with_count(g: Gestures, +count: U32) -> Gestures:
  Gestures{current, enabled, Points{_, time, up, a, b, drag, ma, mb, pa0, pb0, taps}, hold, dv, da, swipe, pv, pa} = g
  Gestures{current, enabled, Points{count, time, up, a, b, drag, ma, mb, pa0, pb0, taps}, hold, dv, da, swipe, pv, pa}

# GetGestureDetected and IsGestureDetected
def Gestures.detected(+g: Gestures) -> U32:
  (Gestures.enabled(g) .&. Gestures.current(g) : U32)

def Gestures.is_detected(+g: Gestures, +gesture: U32) -> Bool:
  U32.is_eq(Gestures.detected(g), gesture)

# GetGestureHoldDuration: (float)(now - Hold.timeDuration) while GESTURE_HOLD.
def narrowed(value: Maybe<W.Words>) -> Maybe<F32>:
  match value:
    case None{}: None{}
    case Some{+v}: Clock.narrow(v)

def Gestures.hold_duration.held(held: Bool, +g: Gestures, +now: W.Words) -> Maybe<F32>:
  match held:
    case False{}: Some{0.0}
    case True{}: narrowed(Clock.sub(now, Gestures.hold_time(g)))

def Gestures.hold_duration(+g: Gestures, +now: W.Words) -> Maybe<F32>:
  Gestures.hold_duration.held(U32.is_eq(Gestures.current(g), 4), g, now)

# -----------------------------------------------------------------------------
# ProcessGestureEvent (touchAction 0 up, 1 down, 2 move; pointCount; the first
# two positions), at time now.

def lt.timeout(elapsed: Maybe<W.Words>) -> Maybe<Bool>:
  match elapsed:
    case None{}: None{}
    case Some{+e}: Some{Clock.less(e, timeout())}

def gt.timeout(elapsed: Maybe<W.Words>) -> Maybe<Bool>:
  match elapsed:
    case None{}: None{}
    case Some{+e}: Some{Clock.greater(e, timeout())}

# GESTURE_DOUBLETAP condition, in C's short-circuit order (the clock difference
# is only evaluated after the current-gesture and tap-count tests).
def double.range(within: Bool, +down_a: In.Point, +position: In.Point) -> Bool:
  match within:
    case False{}: False{}
    case True{}: (distance(down_a, position) < doubletap_range() : F32)

def double.timed(timed: Maybe<Bool>, +down_a: In.Point, +position: In.Point) -> Maybe<Bool>:
  match timed:
    case None{}: None{}
    case Some{within}: Some{double.range(within, down_a, position)}

def double.tapped(candidate: Bool, +now: W.Words, +time: W.Words, +down_a: In.Point, +position: In.Point) -> Maybe<Bool>:
  match candidate:
    case False{}: Some{False{}}
    case True{}: double.timed(lt.timeout(Clock.sub(now, time)), down_a, position)

def one.down.apply(+double: Bool, g: Gestures, +taps: U32, +position: In.Point, +now: W.Words) -> Gestures:
  Gestures{current, enabled, Points{count, _, _, _, b, _, ma, mb, pa0, pb0, _}, hold, _, da, _, pv, pa} = g
  Gestures{Bool.pick(U32, double, 2, 1), enabled, Points{count, now, position, position, b, position, ma, mb, pa0, pb0, Bool.pick(U32, double, 0, 1)},
    hold, zero2(), da, now, pv, pa}

def one.down.decided(double: Maybe<Bool>, g: Gestures, +taps: U32, +position: In.Point, +now: W.Words) -> Maybe<Gestures>:
  match double:
    case None{}: None{}
    case Some{d}: Some{one.down.apply(d, g, taps, position, now)}

def one.down(+g: Gestures, +position: In.Point, +now: W.Words) -> Maybe<Gestures>:
  Gestures{+current, _, Points{_, +time, _, +down_a, _, _, _, _, _, _, +taps}, _, _, _, _, _, _} = g
  +counted = (taps + 1 : U32)
  one.down.decided(double.tapped(U32.is_eq(current, 0) && Bool.not(signed_less(counted, 2)), now, time, down_a, position), g, counted, position, now)

# The swipe direction of a drag angle (NaN: GESTURE_NONE).
def swipe.direction(+angle: F32) -> U32:
  Bool.pick(U32, (angle < 30.0 : F32) || (angle > 330.0 : F32), 16,
    Bool.pick(U32, (angle >= 30.0 : F32) && (angle <= 150.0 : F32), 64,
      Bool.pick(U32, (angle > 150.0 : F32) && (angle < 210.0 : F32), 32,
        Bool.pick(U32, (angle >= 210.0 : F32) && (angle <= 330.0 : F32), 128, 0))))

def one.up.finish(g: Gestures, +current: U32, +up: In.Point, +angle: F32) -> Gestures:
  Gestures{_, enabled, Points{_, time, _, a, b, _, ma, mb, pa0, pb0, taps}, hold, dv, _, swipe, pv, pa} = g
  Gestures{current, enabled, Points{0, time, up, a, b, zero2(), ma, mb, pa0, pb0, taps}, hold, dv, angle, swipe, pv, pa}

def one.up.angled(angle: Maybe<F32>, g: Gestures, +up: In.Point) -> Maybe<Gestures>:
  match angle:
    case None{}: None{}
    case Some{+a}: Some{one.up.finish(g, swipe.direction(a), up, a)}

def one.up.swiped(swiped: Bool, +profile: U32, g: Gestures, +down_a: In.Point, +up: In.Point) -> Maybe<Gestures>:
  match swiped:
    case False{}: Some{one.up.finish(g, 0, up, 0.0)}
    case True{}: one.up.angled(angle.inverted(angle(profile, down_a, up)), g, up)

def one.up.timed(elapsed: Maybe<F32>, +profile: U32, +g: Gestures, +down_a: In.Point, +up: In.Point) -> Maybe<Gestures>:
  match elapsed:
    case None{}: None{}
    case Some{+seconds}:
      +intensity = (distance(down_a, up) / seconds : F32)
      one.up.swiped((intensity > force_to_swipe() : F32) && U32.is_ne(Gestures.current(g), 8), profile, g, down_a, up)

def one.up(+profile: U32, +g: Gestures, +position: In.Point, +now: W.Words) -> Maybe<Gestures>:
  Gestures{+current, _, Points{_, _, +up, +down_a, _, _, _, _, _, _, _}, _, _, _, +swipe, _, _} = g
  +dragged = U32.is_eq(current, 8) || U32.is_eq(current, 4)
  one.up.timed(narrowed(Clock.sub(now, swipe)), profile, g, down_a, Bool.pick(In.Point, dragged, position, up))

def one.move.apply(+drag: Bool, g: Gestures, +position: In.Point, +now: W.Words) -> Gestures:
  Gestures{+current, enabled, Points{count, +time, up, a, b, +drag_from, _, mb, pa0, pb0, taps}, hold, _, da, swipe, pv, pa} = g
  Gestures{Bool.pick(U32, drag, 8, current), enabled, Points{count, Bool.pick(W.Words, drag, now, time), up, a, b, drag_from, position, mb, pa0, pb0, taps},
    hold, difference(drag_from, position), da, swipe, pv, pa}

def one.move.decided(drag: Maybe<Bool>, g: Gestures, +position: In.Point, +now: W.Words) -> Maybe<Gestures>:
  match drag:
    case None{}: None{}
    case Some{d}: Some{one.move.apply(d, g, position, now)}

def one.move.held(held: Bool, +g: Gestures, +position: In.Point, +now: W.Words) -> Maybe<Gestures>:
  match held:
    case False{}: Some{one.move.apply(False{}, g, position, now)}
    case True{}:
      Gestures{_, _, Points{_, +time, _, _, _, _, _, _, _, _, _}, _, _, _, _, _, _} = g
      one.move.decided(gt.timeout(Clock.sub(now, time)), g, position, now)

def one.move(+g: Gestures, +position: In.Point, +now: W.Words) -> Maybe<Gestures>:
  one.move.held(U32.is_eq(Gestures.current(g), 4), g, position, now)

def one(+action: U32, +profile: U32, +g: Gestures, +position: In.Point, +now: W.Words) -> Maybe<Gestures>:
  match action:
    case 0: one.up(profile, g, position, now)
    case 1: one.down(g, position, now)
    case 2: one.move(g, position, now)
    case _: Some{g}

def two.down(g: Gestures, +p0: In.Point, +p1: In.Point, +now: W.Words) -> Gestures:
  Gestures{_, enabled, Points{count, time, up, _, _, drag, ma, mb, _, _, taps}, _, dv, da, swipe, _, pa} = g
  Gestures{4, enabled, Points{count, time, up, p0, p1, drag, ma, mb, p0, p1, taps}, now, dv, da, swipe, difference(p0, p1), pa}

def two.move.apply(angle: Maybe<F32>, g: Gestures, +current: U32, +held: Bool, +p0: In.Point, +p1: In.Point, +now: W.Words) -> Maybe<Gestures>:
  match angle:
    case None{}: None{}
    case Some{+a}:
      Gestures{_, enabled, Points{count, time, up, da0, db0, drag, _, _, pa0, pb0, taps}, +hold, dv, dang, swipe, _, _} = g
      Some{Gestures{current, enabled, Points{count, time, up, da0, db0, drag, p0, p1, pa0, pb0, taps}, Bool.pick(W.Words, held, now, hold), dv, dang, swipe, difference(p0, p1), a}}

def two.move(+profile: U32, +g: Gestures, +p0: In.Point, +p1: In.Point, +now: W.Words) -> Maybe<Gestures>:
  Gestures{_, _, Points{_, _, _, _, _, _, _, _, +pa0, +pb0, _}, _, _, _, _, _, _} = g
  +moved = (distance(pa0, p0) >= minimum_pinch() : F32) || (distance(pb0, p1) >= minimum_pinch() : F32)
  +inward = (distance(pa0, pb0) > distance(p0, p1) : F32)
  two.move.apply(angle.inverted(angle(profile, p0, p1)), g, Bool.pick(U32, moved, Bool.pick(U32, inward, 256, 512), 4), Bool.not(moved), p0, p1, now)

def two.up(g: Gestures) -> Gestures:
  Gestures{_, enabled, Points{_, time, up, a, b, drag, ma, mb, pa0, pb0, taps}, hold, dv, da, swipe, _, _} = g
  Gestures{0, enabled, Points{0, time, up, a, b, drag, ma, mb, pa0, pb0, taps}, hold, dv, da, swipe, zero2(), 0.0}

def two(+action: U32, +profile: U32, +g: Gestures, +p0: In.Point, +p1: In.Point, +now: W.Words) -> Maybe<Gestures>:
  match action:
    case 0: Some{two.up(g)}
    case 1: Some{two.down(g, p0, p1, now)}
    case 2: two.move(profile, g, p0, p1, now)
    case _: Some{g}

def process.points(+count: U32, +action: U32, +profile: U32, +g: Gestures, +p0: In.Point, +p1: In.Point, +now: W.Words) -> Maybe<Gestures>:
  Bool.pick(Maybe<Gestures>, U32.is_eq(count, 1), one(action, profile, g, p0, now),
    Bool.pick(Maybe<Gestures>, U32.is_eq(count, 2), two(action, profile, g, p0, p1, now), Some{g}))

# ProcessGestureEvent with the atan2f profile (CheckedAngle profile number).
def process(+profile: U32, g: Gestures, +action: U32, +count: U32, +p0: In.Point, +p1: In.Point, +now: W.Words) -> Maybe<Gestures>:
  process.points(count, action, profile, Gestures.with_count(g, count), p0, p1, now)

# UpdateGestures at time now.
def update.held(hold: Bool, g: Gestures, +now: W.Words) -> Gestures:
  match hold:
    case False{}: g
    case True{}:
      Gestures{_, enabled, points, _, dv, da, swipe, pv, pa} = g
      Gestures{4, enabled, points, now, dv, da, swipe, pv, pa}

def update.swipe(+g: Gestures) -> Gestures:
  +current = Gestures.current(g)
  Bool.pick(Gestures, U32.is_eq(current, 16) || U32.is_eq(current, 32) || U32.is_eq(current, 64) || U32.is_eq(current, 128),
    Gestures.with_current(g, 0), g)

def update(+g: Gestures, +now: W.Words) -> Gestures:
  +current = Gestures.current(g)
  update.swipe(update.held((U32.is_eq(current, 1) || U32.is_eq(current, 2)) && signed_less(Points.count(Gestures.points(g)), 2), g, now))
