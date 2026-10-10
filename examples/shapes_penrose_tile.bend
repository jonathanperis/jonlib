# raylib [shapes] example - penrose tile, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_penrose_tile.c (zlib/libpng,
# Copyright (c) 2025 David Buzatto (@davidbuzatto)); see LICENSES/raylib.txt.
#
# A Penrose tiling drawn by a turtle walking an L-system's production,
# twelve symbols more each frame; UP and DOWN change the generations (0 to
# 4) and rebuild the production. The productions of these generations stay
# under the example's 10000-character buffer (9558 at most), so its
# truncating copies never cut. The turtle's cosf/sinf of DEG2RAD*angle
# follow the libm profile; an angle outside it refuses the frame
# (docs/SINCOSF.md). The example runs at 120 frames a second. See
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Turtle is Data:
  Turtle{x: F32, y: F32, angle: F32}

# repeats: the count a digit sets for the next move or turn; stack: the pushed turtles, newest first.
type Walk is Data:
  Walk{turtle: Turtle, repeats: U32, stack: +List<Turtle>}

# size: the production's length; length: drawLength; steps: the symbols drawn so far.
type State is Data:
  State{generations: U32, production: String, size: U32, length: F32, steps: U32}

# BuildProductionStep on one symbol: W, X, Y and Z become their rules, F is dropped, the rest is kept.
def piece(code: U32, +symbol: Char, +tail: String) -> String:
  match code:
    case 87: "YF++ZF4-XF[-YF4-WF]++" ++ tail
    case 88: "+YF--ZF[3-WF--XF]+" ++ tail
    case 89: "-WF++XF[+++YF++ZF]-" ++ tail
    case 90: "--YF++++WF[+ZF++++XF]--XF" ++ tail
    case 70: tail
    case _: SCon{symbol, tail}

def expand(text: String) -> String:
  match text:
    case SNil{}: SNil{}
    case SCon{+symbol, rest}: piece(Char.to_u32(symbol), symbol, expand(rest))

def expanded(n: Nat, +text: String) -> String:
  match n:
    case 0n: text
    case 1n+p: expanded(p, expand(text))

# ls->drawLength *= 0.5f, once a step.
def halved(n: Nat, +length: F32) -> F32:
  match n:
    case 0n: length
    case 1n+p: halved(p, (length * 0.5 : F32))

def size(text: String, +n: U32) -> U32:
  match text:
    case SNil{}: n
    case SCon{_, rest}: size(rest, (n + 1 : U32))

def system.sized(+generations: U32, +production: String) -> State:
  State{generations, production, size(production, 0), halved(U32.to_nat(generations), (460.0 * (U32.to_f32(generations) / 4.0) : F32)), 0}

# CreatePenroseLSystem(drawLength*(generations/(float)maxGenerations)), then generations steps.
def system(+generations: U32) -> State:
  system.sized(generations, expanded(U32.to_nat(generations), "[X]++[X]++[X]++[X]++[X]"))

def update.rebuilt(rebuild: Bool, +next: U32, +state: State) -> State:
  match rebuild:
    case True{}: system(next)
    case False{}:
      State{_, +production, +size, +length, +steps} = state
      State{next, production, size, length, steps}

# UP adds a generation (up to 4); otherwise DOWN removes one, rebuilding unless none is left.
def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+generations, _, _, _, _} = state
  +up = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_UP())
  +grow = up && (generations < 4 : U32)
  +shrink = Bool.not(up) && J.Input.is_key_pressed(core, J.KeyboardKey.KEY_DOWN()) && (generations > 0 : U32)
  +next = Bool.pick(U32, grow, (generations + 1 : U32), Bool.pick(U32, shrink, (generations - 1 : U32), generations))
  (core, update.rebuilt(grow || (shrink && (next > 0 : U32)), next, state))

# One line from the turtle, drawLength long: origin += drawLength*(cosf, sinf)(DEG2RAD*angle),
# DrawLineEx between the two points moved to the screen center, 2 thick, Fade(BLACK, 0.2f).
def forward.at(+length: F32, +x: F32, +y: F32, +angle: F32, frame: J.Frame, cosine: Maybe<F32>, sine: Maybe<F32>) -> J.Frame & Turtle:
  match cosine sine:
    case Some{+c} Some{+s}:
      +u = (x + length * c : F32)
      +v = (y + length * s : F32)
      (J.Draw.line_ex(frame, M.Vector2{(x + 800.0 / 2.0 : F32), (y + 450.0 / 2.0 : F32)}, M.Vector2{(u + 800.0 / 2.0 : F32), (v + 450.0 / 2.0 : F32)}, 2.0,
        J.Color.with_alpha(J.Color.BLACK(), 0.2)), Turtle{u, v, angle})
    case _ _: (J.Frame.refuse(frame), Turtle{x, y, angle})

def forward.one(+libm: M.Libm, +length: F32, r: J.Frame & Turtle) -> J.Frame & Turtle:
  (frame, +turtle) = r
  Turtle{+x, +y, +angle} = turtle
  +radians = (M.Math.DEG2RAD() * angle : F32)
  forward.at(length, x, y, angle, frame, M.Libm.cos(libm, radians), M.Libm.sin(libm, radians))

def forward(n: Nat, +libm: M.Libm, +length: F32, r: J.Frame & Turtle) -> J.Frame & Turtle:
  match n:
    case 0n: r
    case 1n+p: forward(p, libm, length, forward.one(libm, length, r))

def moved(+stack: +List<Turtle>, r: J.Frame & Turtle) -> J.Frame & Walk:
  (frame, +turtle) = r
  (frame, Walk{turtle, 1, stack})

# for (j = 0; j < repeats; j++) turtle.angle += theta.
def turned(n: Nat, +turtle: Turtle, +theta: F32) -> Turtle:
  match n:
    case 0n: turtle
    case 1n+p:
      Turtle{+x, +y, +angle} = turtle
      turned(p, Turtle{x, y, (angle + theta : F32)}, theta)

def depth(stack: +List<Turtle>, +n: U32) -> U32:
  match stack:
    case Nil{}: n
    case Con{_, rest}: depth(rest, (n + 1 : U32))

# PopTurtleState: the newest pushed turtle, or a zero one from an empty stack.
def popped(stack: +List<Turtle>, +repeats: U32) -> Walk:
  match stack:
    case Nil{}: Walk{Turtle{0.0, 0.0, 0.0}, repeats, Nil{}}
    case Con{+turtle, rest}: Walk{turtle, repeats, rest}

# One symbol: F draws, + and - turn by 36 degrees (repeats times), [ and ]
# push and pop the turtle (the stack holds 50), a digit sets repeats.
def step(+libm: M.Libm, +length: F32, r: J.Frame & Walk, +code: U32, symbol: U32) -> J.Frame & Walk:
  (frame, +walk) = r
  Walk{+turtle, +repeats, +stack} = walk
  match symbol:
    case 70: moved(stack, forward(U32.to_nat(repeats), libm, length, (frame, turtle)))
    case 43: (frame, Walk{turned(U32.to_nat(repeats), turtle, 36.0), 1, stack})
    case 45: (frame, Walk{turned(U32.to_nat(repeats), turtle, F32.neg(36.0)), 1, stack})
    case 91: (frame, Walk{turtle, repeats, Bool.pick(+List<Turtle>, (depth(stack, 0) < 50 : U32), Con{turtle, stack}, stack)})
    case 93: (frame, popped(stack, repeats))
    case _: (frame, Walk{turtle, Bool.pick(U32, (code >= 48 : U32) && (code <= 57 : U32), (code - 48 : U32), repeats), stack})

# The first n symbols of the production.
def walk(text: String, n: Nat, +libm: M.Libm, +length: F32, r: J.Frame & Walk) -> J.Frame & Walk:
  match text n:
    case SNil{} _: r
    case _ 0n: r
    case SCon{+symbol, rest} 1n+p: walk(rest, p, libm, length, step(libm, length, r, Char.to_u32(symbol), Char.to_u32(symbol)))

def walked(r: J.Frame & Walk) -> J.Frame:
  (frame, _) = r
  frame

# DrawPenroseLSystem: the turtle starts at the origin heading -90 degrees.
def tiling(drawn: Bool, +libm: M.Libm, +production: String, +length: F32, +steps: U32, frame: J.Frame) -> J.Frame:
  match drawn:
    case False{}: frame
    case True{}: walked(walk(production, U32.to_nat(steps), libm, length, (frame, Walk{Turtle{0.0, 0.0, F32.neg(90.0)}, 1, Nil{}})))

def label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, 50.0, 20.0, J.Color.DARKGRAY())

# ls->steps += 12 (up to the production's length) each time the tiling is drawn.
def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+generations, +production, +size, +length, +steps} = state
  +drawn = (generations > 0 : U32)
  +count = Bool.pick(U32, drawn, U32.min((steps + 12 : U32), size), steps)
  f1 = tiling(drawn, libm, production, length, count, J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  f2 = J.Draw.text(f1, "penrose l-system", 10.0, 10.0, 20.0, J.Color.DARKGRAY())
  f3 = J.Draw.text(f2, "press up or down to change generations", 10.0, 30.0, 20.0, J.Color.DARKGRAY())
  (core, (State{generations, production, size, length, count}, label(J.Text.format("generations: %d", [J.TextInt{generations}]), f3)))

# The main loop's body; libm is the profile of the turtle's cosf/sinf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After SetConfigFlags(FLAG_MSAA_4X_HINT) and InitWindow(800, 450): no generations yet, SetTargetFPS(120).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 120), (frame, system(0)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - penrose tile", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
