# raylib [text] example - animations, ported to Jonlib.
# Adapted from raylib 6.2 examples/text/text_animations.c (zlib/libpng,
# Copyright (c) 2026 Gabriel Piangers (@gabriel-piangers)); see
# LICENSES/raylib.txt. EaseSineIn, EaseSineOut, EaseSineInOut and
# EaseLinearNone are Joneasings' (docs/EASINGS.md).
#
# "This is an animated text!" drawn glyph by glyph (DrawTextEx with the
# default font at 30, no spacing), each glyph at its own time
# (frameCount + i*offset) % duration: waving (sine in and out), flashing
# (sine in out on the alpha) or shaking (GetRandomValue offsets, linear).
# Q and E pick the animation, W and S the intensity, D and A the duration,
# X and Z the offset between glyphs. The glyphs' x positions (MeasureText of
# each one-byte TextSubtext at 30 plus 4) are the same every frame and are
# computed once in the setup.
#
# The sine easings' cosf and sinf follow the libm profile (M.Libm.sin and
# M.Libm.cos, docs/SINCOSF.md): a value outside it refuses that frame and
# every later one. raylib seeds GetRandomValue from time(NULL) in
# InitWindow; here the seed is a setup argument. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../joneasings.bend as E

# A glyph's one-byte text and its x (text.position.x + offsetX).
type Glyph is Data:
  Glyph{text: String, x: F32}

# A glyph as the frame draws it: glyphPosition[i] and glyphAlpha[i].
type Placed is Data:
  Placed{text: String, x: F32, y: F32, alpha: U32}

# The glyphs placed so far (last first), the random state and whether every
# easing was answered.
type Placing is Type:
  Placing{rng: J.Random.State, ok: Bool, placed: +List<Placed>}

# The glyphs measured so far (last first): the next index, offsetX and
# whether every TextSubtext and MeasureText was answered.
type Made is Data:
  Made{index: U32, offset: U32, ok: Bool, glyphs: +List<Glyph>}

# text.delta, text.offset and text.duration (floats), frameCount and
# currentAnimation; ok: no refusal so far.
type State is Type:
  State{rng: J.Random.State, font: J.Font, glyphs: +List<Glyph>, placed: +List<Placed>, frames: U32, delta: F32, offset: F32, duration: F32, current: U32, ok: Bool}

def message() -> String:
  "This is an animated text!"

def Glyph.text(g: Glyph) -> String:
  Glyph{text, _} = g
  text

def Glyph.x(g: Glyph) -> F32:
  Glyph{_, x} = g
  x

# -----------------------------------------------------------------------------
# The glyphs' x positions: offsetX += MeasureText(TextSubtext(text.str, i, 1), 30) + TEXT_SPACING.

def glyph.width(size: Maybe<U32>, t: String, +i: U32, +offset: U32, +ok: Bool, +list: +List<Glyph>) -> Made:
  match size:
    case None{}: Made{(i + 1 : U32), offset, False{}, list}
    case Some{+w}: Made{(i + 1 : U32), (offset + (w + 4) : U32), ok, Con{Glyph{t, (200.0 + U32.to_f32(offset) : F32)}, list}}

def glyph.sub(part: Maybe<String>, +i: U32, +offset: U32, +ok: Bool, +list: +List<Glyph>) -> Made:
  match part:
    case None{}: Made{(i + 1 : U32), offset, False{}, list}
    case Some{+t}: glyph.width(J.Font.measure_text(t, 30.0), t, i, offset, ok, list)

def glyph.next(made: Made) -> Made:
  Made{+i, +offset, +ok, +list} = made
  glyph.sub(J.Text.subtext(message(), i, 1), i, offset, ok, list)

def measured(n: Nat, made: Made) -> Made:
  match n:
    case 0n: made
    case 1n+rest: measured(rest, glyph.next(made))

# -----------------------------------------------------------------------------
# Update

# float time = (int)(frameCount + i*text.offset)%(int)text.duration: i and
# frameCount converted to float, the sum truncated, an int remainder.
def moment(+frames: U32, +i: U32, +offset: F32, +duration: F32) -> F32:
  U32.to_f32((F32.to_u32((U32.to_f32(frames) + U32.to_f32(i) * offset : F32)) % F32.to_u32(duration) : U32))

# Waving: EaseSineIn(time, position.y, delta, duration) in the first half,
# EaseSineOut(time, position.y + delta, -delta, duration) in the second.
def wave.y(early: Bool, +libm: M.Libm, +at: F32, +delta: F32, +duration: F32) -> Maybe<F32>:
  match early:
    case True{}: E.Ease.sine_in_for(libm, at, 250.0, delta, duration)
    case False{}: E.Ease.sine_out_for(libm, at, (250.0 + delta : F32), F32.neg(delta), duration)

def waved.at(y: Maybe<F32>, +g: Glyph, rng: J.Random.State, +ok: Bool, +list: +List<Placed>) -> Placing:
  match y:
    case None{}: Placing{rng, False{}, Con{Placed{Glyph.text(g), Glyph.x(g), 250.0, 255}, list}}
    case Some{+v}: Placing{rng, ok, Con{Placed{Glyph.text(g), Glyph.x(g), v, 255}, list}}

def waved(acc: Placing, +libm: M.Libm, +g: Glyph, +at: F32, +delta: F32, +duration: F32) -> Placing:
  Placing{rng, +ok, +list} = acc
  waved.at(wave.y((at < (duration / 2.0) : F32), libm, at, delta, duration), g, rng, ok, list)

# Flashing: glyphAlpha[i] = (unsigned char)EaseSineInOut(time, 255, -255,
# duration), which lies in [0, 255] (127.5*(cosf - 1) + 255): the conversion
# truncates.
def flashed.at(alpha: Maybe<F32>, +g: Glyph, rng: J.Random.State, +ok: Bool, +list: +List<Placed>) -> Placing:
  match alpha:
    case None{}: Placing{rng, False{}, Con{Placed{Glyph.text(g), Glyph.x(g), 250.0, 255}, list}}
    case Some{+v}: Placing{rng, ok, Con{Placed{Glyph.text(g), Glyph.x(g), 250.0, F32.to_u32(v)}, list}}

def flashed(acc: Placing, +libm: M.Libm, +g: Glyph, +at: F32, +duration: F32) -> Placing:
  Placing{rng, +ok, +list} = acc
  flashed.at(E.Ease.sine_in_out_for(libm, at, 255.0, F32.neg(255.0), duration), g, rng, ok, list)

# Shaking: EaseLinearNone over each half of the duration, from the glyph's
# place to deltaX, deltaY away and back.
def shaken.glyph(early: Bool, +g: Glyph, +at: F32, +duration: F32, +dx: F32, +dy: F32) -> Placed:
  match early:
    case True{}: Placed{Glyph.text(g), E.Ease.linear_none(at, Glyph.x(g), dx, (duration / 2.0 : F32)), E.Ease.linear_none(at, 250.0, dy, (duration / 2.0 : F32)), 255}
    case False{}: Placed{Glyph.text(g), E.Ease.linear_none((at - duration / 2.0 : F32), (Glyph.x(g) + dx : F32), F32.neg(dx), (duration / 2.0 : F32)),
      E.Ease.linear_none((at - duration / 2.0 : F32), (250.0 + dy : F32), F32.neg(dy), (duration / 2.0 : F32)), 255}

def shook.y(+g: Glyph, +at: F32, +duration: F32, +ok: Bool, +list: +List<Placed>, +dx: F32, r: J.Random.State & F32) -> Placing:
  (rng, +dy) = r
  Placing{rng, ok, Con{shaken.glyph((at < (duration / 2.0) : F32), g, at, duration, dx, dy), list}}

# deltaX = (float)GetRandomValue(-text.delta/10, text.delta/10), then deltaY
# the same: the float bounds truncate to ints (J.Random.value).
def shook.x(+g: Glyph, +at: F32, +delta: F32, +duration: F32, +ok: Bool, +list: +List<Placed>, r: J.Random.State & F32) -> Placing:
  (rng, +dx) = r
  shook.y(g, at, duration, ok, list, dx, J.Random.value(rng, (F32.neg(delta) / 10.0 : F32), (delta / 10.0 : F32)))

def shook(acc: Placing, +g: Glyph, +at: F32, +delta: F32, +duration: F32) -> Placing:
  Placing{rng, +ok, +list} = acc
  shook.x(g, at, delta, duration, ok, list, J.Random.value(rng, (F32.neg(delta) / 10.0 : F32), (delta / 10.0 : F32)))

# One glyph of the switch (currentAnimation).
def place(current: U32, +libm: M.Libm, +g: Glyph, +i: U32, +frames: U32, +delta: F32, +offset: F32, +duration: F32, acc: Placing) -> Placing:
  match current:
    case 0: waved(acc, libm, g, moment(frames, i, offset, duration), delta, duration)
    case 1: flashed(acc, libm, g, moment(frames, i, offset, duration), duration)
    case _: shook(acc, g, moment(frames, i, offset, duration), delta, duration)

def arranged(glyphs: +List<Glyph>, +i: U32, +libm: M.Libm, +current: U32, +frames: U32, +delta: F32, +offset: F32, +duration: F32, acc: Placing) -> Placing:
  match glyphs:
    case Nil{}: acc
    case Con{+g, rest}: arranged(rest, (i + 1 : U32), libm, current, frames, delta, offset, duration, place(current, libm, g, i, frames, delta, offset, duration, acc))

def updated(p: Placing, font: J.Font, +glyphs: +List<Glyph>, +frames: U32, +delta: F32, +offset: F32, +duration: F32, +current: U32) -> State:
  Placing{rng, +ok, +list} = p
  State{rng, font, glyphs, List.reverse(&2, Placed, list), frames, delta, offset, duration, current, ok}

# frameCount++; S/W move delta by 2 within 10..60, A/D the duration by 5
# within 20..120 (truncated to an int), Z/X the offset by 1 within 0..15,
# Q/E the animation (the first key of each pair wins); then every glyph is
# placed.
def update(+libm: M.Libm, +core: J.Core, state: State) -> J.Core & State:
  State{rng, font, +glyphs, _, +frames, +delta, +offset, +duration, +current, +ok} = state
  +n = (frames + 1 : U32)
  +moved = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_W()), M.Math.clamp((delta + 2.0 : F32), 10.0, 60.0), delta)
  +d1 = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_S()), M.Math.clamp((delta - 2.0 : F32), 10.0, 60.0), moved)
  +longer = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_D()), F32.trunc(M.Math.clamp((duration + 5.0 : F32), 20.0, 120.0)), duration)
  +t1 = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_A()), F32.trunc(M.Math.clamp((duration - 5.0 : F32), 20.0, 120.0)), longer)
  +wider = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_X()), M.Math.clamp((offset + 1.0 : F32), 0.0, 15.0), offset)
  +o1 = Bool.pick(F32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_Z()), M.Math.clamp((offset - 1.0 : F32), 0.0, 15.0), wider)
  +next = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_E()), ((current + 1) % 3 : U32), current)
  +c1 = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_Q()), Bool.pick(U32, U32.is_eq(current, 0), 2, (current - 1 : U32)), next)
  (core, updated(arranged(glyphs, 0, libm, c1, n, d1, o1, t1, Placing{rng, ok, Nil{}}), font, glyphs, n, d1, o1, t1, c1))

# -----------------------------------------------------------------------------
# Draw

def checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def label(line: Maybe<String>, +y: F32, frame: J.Frame) -> J.Frame:
  match line:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 20.0, y, 20.0, J.Color.GRAY())

def anim.name(current: U32) -> String:
  match current:
    case 0: "Waving"
    case 1: "Flashing"
    case _: "Shaking"

# DrawTextEx(GetFontDefault(), TextSubtext(text.str, i, 1), glyphPosition[i],
# GetFontDefault().baseSize*3.0f, 0, (Color){ 200, 122, 255, glyphAlpha[i] }).
def glyph.drawn(r: J.Frame & J.Font, +p: Placed) -> J.Frame & J.Font:
  (frame, font) = r
  Placed{+t, +x, +y, +alpha} = p
  J.Draw.text_ex(frame, font, t, M.Vector2{x, y}, (U32.to_f32(10) * 3.0 : F32), 0.0, J.Color.rgba(200, 122, 255, alpha))

def lettered(placed: +List<Placed>, r: J.Frame & J.Font) -> J.Frame & J.Font:
  match placed:
    case Nil{}: r
    case Con{+p, rest}: lettered(rest, glyph.drawn(r, p))

def draw.done(+core: J.Core, rng: J.Random.State, +glyphs: +List<Glyph>, +placed: +List<Placed>, +frames: U32, +delta: F32, +offset: F32, +duration: F32, +current: U32, +ok: Bool,
    r: J.Frame & J.Font) -> J.Core & (State & J.Frame):
  (frame, font) = r
  (core, (State{rng, font, glyphs, placed, frames, delta, offset, duration, current, ok}, frame))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{rng, font, +glyphs, +placed, +frames, +delta, +offset, +duration, +current, +ok} = state
  f1 = label(J.Text.format("Duration (A | D): %d", [J.TextInt{F32.to_u32(duration)}]), 20.0, J.Frame.clear_background(checked(ok, frame), J.Color.RAYWHITE()))
  f2 = label(J.Text.format("Delta (W | S): %.1f", [J.TextFloat{delta}]), 50.0, f1)
  f3 = label(J.Text.format("Offset (Z | X): %.1f", [J.TextFloat{offset}]), 80.0, f2)
  f4 = label(J.Text.format("Curent Animation (Q | E): %s", [J.TextString{anim.name(current)}]), 110.0, f3)
  draw.done(core, rng, glyphs, placed, frames, delta, offset, duration, current, ok, lettered(placed, (f4, font)))

# The main loop's body; libm is the profile of the sine easings' cosf and sinf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(core, state, frame)}

def setup.state(+seed: U32, made: Made) -> State:
  Made{_, _, +ok, +list} = made
  State{J.Random.seed(seed), J.Font.default(), List.reverse(&2, Glyph, list), Nil{}, 0, 24.0, 6.0, 60.0, 0, ok}

# After InitWindow(800, 450) and SetRandomSeed(seed): the text at (200, 250)
# with delta 24, offset 6 and duration 60, frameCount 0, the waving
# animation, SetTargetFPS(60).
def setup(+seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, setup.state(seed, measured(U32.to_nat(J.Text.length(message())), Made{0, 0, True{}, Nil{}}))))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [text] example - animations", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
