# raylib [shapes] example - recursive tree, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_recursive_tree.c (zlib/libpng,
# Copyright (c) 2025 Jopestpe (@jopestpe)); see LICENSES/raylib.txt.
#
# A binary tree of branches grown breadth first (each branch two shorter
# ones turned by the angle, up to 2^depth branches), drawn as lines or Bezier
# curves, with five raygui slider bars and a check box (Jongui). The branch
# ends come from the example's own sinf/cosf and the branch limit from
# powf(2, floorf(depth)), which follow the libm profile: an argument outside
# it refuses the frame (docs/SINCOSF.md, M.Libm.pow2). See docs/GUI.md and
# docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# values: angle, length, branchDecay, treeDepth, thick.
type State is Data:
  State{gui: G.Gui, values: +List<F32>, bezier: Bool}

type Branch is Data:
  Branch{sx: F32, sy: F32, ex: F32, ey: F32, angle: F32, length: F32}

# The branches visited so far (newest first), their count with the queued
# ones, and whether every sinf/cosf was inside the profile.
type Tree is Data:
  Tree{valid: Bool, count: U32, visited: +List<Branch>}

def update(+core: J.Core, +state: State) -> J.Core & State:
  (core, state)

def first(values: +List<F32>) -> F32:
  match values:
    case Con{v, _}: v
    case Nil{}: 0.0

def at(+values: +List<F32>, n: Nat) -> F32:
  first(List.drop(&2, F32, values, n))

def child.at(+x: F32, +y: F32, +angle: F32, +length: F32, sine: Maybe<F32>, cosine: Maybe<F32>) -> Maybe<Branch>:
  match sine cosine:
    case Some{s} Some{c}: Some{Branch{x, y, (x + length * s : F32), (y - length * c : F32), angle, length}}
    case _ _: None{}

# A branch from (x, y): its end is (x + length*sinf(angle), y - length*cosf(angle)).
def child(+libm: M.Libm, +x: F32, +y: F32, +angle: F32, +length: F32) -> Maybe<Branch>:
  child.at(x, y, angle, length, M.Libm.sin(libm, angle), M.Libm.cos(libm, angle))

# What a branch adds: its two children (none when it does not split) and
# whether their sinf/cosf were inside the profile.
type Split is Data:
  Split{valid: Bool, count: U32, children: +List<Branch>}

def split.made(left: Maybe<Branch>, right: Maybe<Branch>) -> Split:
  match left right:
    case Some{a} Some{b}: Split{True{}, 2, [a, b]}
    case _ _: Split{False{}, 2, Nil{}}

# The two children of a branch, when it splits: its length at least 2, room
# under maxBranches and a next length of at least 2.
def split(+libm: M.Libm, +b: Branch, +theta: F32, +decay: F32, +count: U32, +limit: U32) -> Split:
  Branch{_, _, +ex, +ey, +angle, +length} = b
  +next = (length * decay : F32)
  Bool.pick(Split, (length >= 2.0 : F32) && (count < limit : U32) && (next >= 2.0 : F32),
    split.made(child(libm, ex, ey, (angle + theta : F32), next), child(libm, ex, ey, (angle - theta : F32), next)), Split{True{}, 0, Nil{}})

def children(made: Split) -> +List<Branch>:
  Split{_, _, children} = made
  children

def children.valid(made: Split) -> Bool:
  Split{valid, _, _} = made
  valid

def children.count(made: Split) -> U32:
  Split{_, count, _} = made
  count

# for (i = 0; i < count; i++): visit the queue's first branch and append its children.
def grow(n: Nat, queue: +List<Branch>, +libm: M.Libm, +theta: F32, +decay: F32, +limit: U32, +tree: Tree) -> Tree:
  match n queue:
    case 1n+p Con{+b, +rest}:
      Tree{+ok, +count, +visited} = tree
      +made = split(libm, b, theta, decay, count, limit)
      grow(p, List.append(&2, Branch, rest, children(made)), libm, theta, decay, limit,
        Tree{ok && children.valid(made), (count + children.count(made) : U32), Con{b, visited}})
    case _ _: tree

def stroke.at(bezier: Bool, +start: M.Vector2, +end: M.Vector2, +thick: F32, frame: J.Frame) -> J.Frame:
  match bezier:
    case True{}: J.Draw.line_bezier(frame, start, end, thick, J.Color.RED())
    case False{}: J.Draw.line_ex(frame, start, end, thick, J.Color.RED())

def stroke(bezier: Bool, +b: Branch, +thick: F32, frame: J.Frame) -> J.Frame:
  Branch{+sx, +sy, +ex, +ey, _, _} = b
  stroke.at(bezier, M.Vector2{sx, sy}, M.Vector2{ex, ey}, thick, frame)

def branch(long: Bool, +bezier: Bool, +b: Branch, +thick: F32, frame: J.Frame) -> J.Frame:
  match long:
    case False{}: frame
    case True{}: stroke(bezier, b, thick, frame)

def strokes(branches: +List<Branch>, +bezier: Bool, +thick: F32, frame: J.Frame) -> J.Frame:
  match branches:
    case Nil{}: frame
    case Con{+b, rest}:
      Branch{_, _, _, _, _, +length} = b
      strokes(rest, bezier, thick, branch((length >= 2.0 : F32), bezier, b, thick, frame))

def drawn(valid: Bool, +visited: +List<Branch>, +bezier: Bool, +thick: F32, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: J.Frame.refuse(frame)
    case True{}: strokes(List.reverse(&2, Branch, visited), bezier, thick, frame)

def tree.drawn(tree: Tree, +bezier: Bool, +thick: F32, frame: J.Frame) -> J.Frame:
  Tree{valid, _, +visited} = tree
  drawn(valid, visited, bezier, thick, frame)

# The root from start (275, 450) straight up, then the breadth-first growth
# (at most 1030 branches, as the example's array).
def tree.limited(limit: Maybe<F32>, root: Maybe<Branch>, +libm: M.Libm, +v: +List<F32>, +bezier: Bool, frame: J.Frame) -> J.Frame:
  match limit root:
    case Some{+most} Some{+r}:
      tree.drawn(grow(1030n, [r], libm, (at(v, 0n) * (3.14159265358979323846 / 180.0) : F32), at(v, 2n), F32.to_u32(most), Tree{True{}, 1, Nil{}}), bezier, at(v, 4n), frame)
    case _ _: J.Frame.refuse(frame)

def tree(+libm: M.Libm, +v: +List<F32>, +bezier: Bool, frame: J.Frame) -> J.Frame:
  tree.limited(M.Libm.pow2(libm, F32.floor(at(v, 3n))), child(libm, (800.0 / 2.0 - 125.0 : F32), 450.0, 0.0, at(v, 1n)), libm, v, bezier, frame)

def bars() -> +List<G.Gui.Bar>:
  [G.GuiBar{J.Rectangle{640.0, 40.0, 120.0, 20.0}, "Angle", "%.0f", 0.0, 180.0},
   G.GuiBar{J.Rectangle{640.0, 70.0, 120.0, 20.0}, "Length", "%.0f", 12.0, 240.0},
   G.GuiBar{J.Rectangle{640.0, 100.0, 120.0, 20.0}, "Decay", "%.2f", 0.1, 0.78},
   G.GuiBar{J.Rectangle{640.0, 130.0, 120.0, 20.0}, "Depth", "%.0f", 1.0, 10.0},
   G.GuiBar{J.Rectangle{640.0, 160.0, 120.0, 20.0}, "Thick", "%.0f", 1.0, 8.0}]

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 10.0, 10.0, fps)))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def draw.checked(+core: J.Core, +gui: G.Gui, +values: +List<F32>, frame: J.Frame, pair: Bool & Bool) -> J.Core & (State & J.Frame):
  (bezier, _) = pair
  draw.fps.done(State{gui, values, bezier}, frame, J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw.box(+core: J.Core, +gui: G.Gui, +values: +List<F32>, r: J.Frame & (Bool & Bool)) -> J.Core & (State & J.Frame):
  (frame, pair) = r
  draw.checked(core, gui, values, frame, pair)

def draw.values(+core: J.Core, +bezier: Bool, frame: J.Frame, rest: G.Gui & +List<F32>) -> J.Core & (State & J.Frame):
  (+gui, +values) = rest
  draw.box(core, gui, values, G.Gui.check_box(gui, core, frame, J.Rectangle{640.0, 190.0, 20.0, 20.0}, "Bezier", bezier))

def draw.bars(+core: J.Core, +bezier: Bool, r: J.Frame & (G.Gui & +List<F32>)) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.values(core, bezier, frame, rest)

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+gui, +values, +bezier} = state
  f1 = tree(libm, values, bezier, J.Frame.clear_background(frame, J.Color.RAYWHITE()))
  f2 = J.Draw.line(f1, 580.0, 0.0, 580.0, 450.0, J.Color.rgba(218, 218, 218, 255))
  f3 = J.Draw.rectangle(f2, 580.0, 0.0, 800.0, 450.0, J.Color.rgba(232, 232, 232, 255))
  draw.bars(core, bezier, G.Gui.slider_bars(gui, core, f3, bars(), values))

# The main loop's body; libm is the profile of the example's sinf/cosf and powf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): angle 40, length 120, decay 0.66, depth 10,
# thickness 1, straight lines, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{G.Gui.new(), [40.0, 120.0, 0.66, 10.0, 1.0], False{}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [shapes] example - recursive tree", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
