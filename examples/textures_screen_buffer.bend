# raylib [textures] example - screen buffer, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_screen_buffer.c
# (zlib/libpng, Copyright (c) 2025 Agnis Aldiņš (@nezvers)); see
# LICENSES/raylib.txt.
#
# A fire effect on a 400x225 buffer of palette indices: a random flame root
# feeds the bottom row and every lit cell moves a row up each frame, drifting
# one column either way and decaying at random; the buffer goes through a
# 256-color palette (ColorFromHSV) into an image whose texture is drawn at
# twice its size. The example moves the cells in place, row by row; a row's
# cells only ever land on the row above, already emptied, so here each row
# is built from the one below it (the last cell written wins, as in place),
# and only the image pixels whose index changed are redrawn (the others
# already hold that color). raylib seeds GetRandomValue from time(NULL) in
# InitWindow; here the seed is a setup argument. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Row is Data:
  Row{cells: +List<U32>}

# root: flameRootBuffer; rows: indexBuffer's 225 rows.
type State is Type:
  State{rng: J.Random.State, root: +List<U32>, rows: +List<Row>, image: Maybe<J.Surface>, texture: Maybe<J.Texture>}

def zeros(n: Nat) -> +List<U32>:
  match n:
    case 0n: Nil{}
    case 1n+p: Con{0, zeros(p)}

def blank(n: Nat) -> +List<Row>:
  match n:
    case 0n: Nil{}
    case 1n+p: Con{Row{zeros(400n)}, blank(p)}

def root.drawn(+flame: U32, done: +List<U32>, draw: J.Random.State & F32) -> J.Random.State & +List<U32>:
  (rng, +add) = draw
  (rng, Con{U32.min((flame + F32.to_u32(add) : U32), 255), done})

# flame += GetRandomValue(0, 2), up to 255, for x from 2.
def root.step(+flame: U32, acc: J.Random.State & +List<U32>, growing: Bool) -> J.Random.State & +List<U32>:
  (rng, done) = acc
  match growing:
    case False{}: (rng, Con{flame, done})
    case True{}: root.drawn(flame, done, J.Random.value(rng, 0.0, 2.0))

# The flame root grown in order; it comes back newest first.
def root.grow(root: +List<U32>, +x: U32, acc: J.Random.State & +List<U32>) -> J.Random.State & +List<U32>:
  match root:
    case Nil{}: acc
    case Con{+flame, rest}: root.grow(rest, (x + 1 : U32), root.step(flame, acc, (x >= 2 : U32)))

# One row moving up: out holds the finished cells of the row above, newest first, starting with the
# cell left of column 0; a and b are the cells under columns x - 1 and x so far.
type Scan is Type:
  Scan{rng: J.Random.State, out: +List<U32>, a: U32, b: U32}

# colorIndex -= (decay < colorIndex)? decay : colorIndex, written a column left, above or right.
def step.decayed(+value: U32, +move: U32, +out: +List<U32>, +a: U32, +b: U32, draw: J.Random.State & F32) -> Scan:
  (rng, +decay) = draw
  +left = (value - U32.min(F32.to_u32(decay), value) : U32)
  Scan{rng, Con{Bool.pick(U32, U32.is_eq(move, 0), left, a), out}, Bool.pick(U32, U32.is_eq(move, 1), left, b), Bool.pick(U32, U32.is_eq(move, 2), left, 0)}

# if ((newX > 0) && (newX < imageWidth)): decay = GetRandomValue(0, 3).
def step.placed(inside: Bool, +value: U32, +move: U32, +out: +List<U32>, +a: U32, +b: U32, rng: J.Random.State) -> Scan:
  match inside:
    case False{}: Scan{rng, Con{a, out}, b, 0}
    case True{}: step.decayed(value, move, out, a, b, J.Random.value(rng, 0.0, 3.0))

# moveX = GetRandomValue(0, 2) - 1; newX = x + moveX.
def step.moved(+value: U32, +x: U32, +out: +List<U32>, +a: U32, +b: U32, draw: J.Random.State & F32) -> Scan:
  (rng, +raw) = draw
  step.placed(((x + F32.to_u32(raw)) > 1 : U32) && ((x + F32.to_u32(raw)) < 401 : U32), value, F32.to_u32(raw), out, a, b, rng)

def step(+value: U32, +x: U32, scan: Scan, lit: Bool) -> Scan:
  Scan{rng, +out, +a, +b} = scan
  match lit:
    case False{}: Scan{rng, Con{a, out}, b, 0}
    case True{}: step.moved(value, x, out, a, b, J.Random.value(rng, 0.0, 2.0))

def scan(cells: +List<U32>, +x: U32, state: Scan) -> Scan:
  match cells:
    case Nil{}: state
    case Con{+value, rest}: scan(rest, (x + 1 : U32), step(value, x, state, Bool.not(U32.is_eq(value, 0))))

# The row above: the finished cells in order, without the one left of column 0, and the cell under the last column.
def scan.row(state: Scan) -> J.Random.State & Row:
  Scan{rng, +out, +a, _} = state
  (rng, Row{List.drop(&2, U32, List.reverse(&2, U32, Con{a, out}), 1n)})

def moved.push(done: +List<Row>, r: J.Random.State & Row) -> J.Random.State & +List<Row>:
  (rng, +row) = r
  (rng, Con{row, done})

def moved.row(+row: Row, acc: J.Random.State & +List<Row>) -> J.Random.State & +List<Row>:
  Row{+cells} = row
  (rng, done) = acc
  moved.push(done, scan.row(scan(cells, 0, Scan{rng, Nil{}, 0, 0})))

# Rows 1 to 224 each moved onto the row above, in order; they come back newest first.
def moved(rows: +List<Row>, acc: J.Random.State & +List<Row>) -> J.Random.State & +List<Row>:
  match rows:
    case Nil{}: acc
    case Con{+row, rest}: moved(rest, moved.row(row, acc))

# palette[i] = ColorFromHSV(250 + 150*t*t, t, t), t = i/255.
def palette(+index: U32) -> U32:
  +t = (U32.to_f32(index) / 255.0 : F32)
  J.Color.from_hsv((250.0 + 150.0 * (t * t) : F32), t, t)

def pixel(changed: Bool, +value: U32, +x: U32, +y: U32, image: J.Surface) -> J.Surface:
  match changed:
    case False{}: image
    case True{}: J.Surface.draw_pixel(image, U32.to_f32(x), U32.to_f32(y), palette(value))

# ImageDrawPixel(&screenImage, x, y, palette[index]) where the index changed.
def paint.cells(cells: +List<U32>, before: +List<U32>, +x: U32, +y: U32, image: J.Surface) -> J.Surface:
  match cells before:
    case Con{+value, rest} Con{+old, more}: paint.cells(rest, more, (x + 1 : U32), y, pixel(Bool.not(U32.is_eq(value, old)), value, x, y, image))
    case _ _: image

def paint.row(+row: Row, +before: Row, +y: U32, image: J.Surface) -> J.Surface:
  Row{+cells} = row
  Row{+old} = before
  paint.cells(cells, old, 0, y, image)

# for (y = 1; y < imageHeight; y++): the rows from 1.
def paint(rows: +List<Row>, before: +List<Row>, +y: U32, image: J.Surface) -> J.Surface:
  match rows before:
    case Con{+row, rest} Con{+old, more}: paint(rest, more, (y + 1 : U32), paint.row(row, old, y, image))
    case _ _: image

def updated(result: Result<&1, &1, J.Texture & J.Surface.Error, J.Texture>) -> Maybe<J.Texture>:
  match result:
    case Fail{_}: None{}
    case Done{texture}: Some{texture}

# UpdateTexture(screenTexture, screenImage.data).
def update.uploaded(rng: J.Random.State, +root: +List<U32>, +rows: +List<Row>, texture: J.Texture, pair: J.Surface & J.Surface) -> State:
  (image, copy) = pair
  State{rng, root, rows, Some{image}, updated(J.Texture.update(texture, copy))}

def update.painted(rng: J.Random.State, +root: +List<U32>, +rows: +List<Row>, +before: +List<Row>, image: Maybe<J.Surface>, texture: Maybe<J.Texture>) -> State:
  match image texture:
    case Some{i} Some{t}: update.uploaded(rng, root, rows, t, J.Surface.copy(paint(List.drop(&2, Row, rows, 1n), List.drop(&2, Row, before, 1n), 1, i)))
    case _ _: State{rng, root, rows, None{}, None{}}

# The moved rows 0..223 and an empty bottom row.
def update.moved(+root: +List<U32>, +before: +List<Row>, image: Maybe<J.Surface>, texture: Maybe<J.Texture>, r: J.Random.State & +List<Row>) -> State:
  (rng, reversed) = r
  update.painted(rng, root, List.append(&2, Row, List.reverse(&2, Row, reversed), [Row{zeros(400n)}]), before, image, texture)

# The bottom row takes the flame root, the top row is cleared (it is not a source), and the rows move up.
def update.grown(+rows: +List<Row>, image: Maybe<J.Surface>, texture: Maybe<J.Texture>, r: J.Random.State & +List<U32>) -> State:
  (rng, +reversed) = r
  update.moved(List.reverse(&2, U32, reversed), rows, image, texture,
    moved(List.append(&2, Row, List.take(&2, Row, List.drop(&2, Row, rows, 1n), 223n), [Row{List.reverse(&2, U32, reversed)}]), (rng, Nil{})))

def update(+core: J.Core, state: State) -> J.Core & State:
  State{rng, +root, +rows, image, texture} = state
  (core, update.grown(rows, image, texture, root.grow(root, 0, (rng, Nil{}))))

def draw.shown(+core: J.Core, rng: J.Random.State, +root: +List<U32>, +rows: +List<Row>, image: Maybe<J.Surface>, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  (frame, texture) = r
  (core, (State{rng, root, rows, image, Some{texture}}, frame))

# DrawTextureEx(screenTexture, (0, 0), 0, 2, WHITE).
def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{rng, +root, +rows, image, texture} = state
  match texture:
    case None{}: (core, (State{rng, root, rows, image, None{}}, J.Frame.refuse(frame)))
    case Some{t}: draw.shown(core, rng, root, rows, image, J.Draw.texture_ex_for(libm, J.Frame.clear_background(frame, J.Color.RAYWHITE()), t, M.Vector2.zero(), 0.0, 2.0, J.Color.WHITE()))

# The main loop's body; libm is the profile of DrawTextureEx's sinf/cosf (rotation 0).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def setup.uploaded(+seed: U32, +core: J.Core, image: J.Surface, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, texture) = r
  (J.Core.set_target_fps(core, 60), (frame, State{J.Random.seed(seed), zeros(400n), blank(225n), Some{image}, texture}))

def setup.copied(+seed: U32, +core: J.Core, frame: J.Frame, pair: J.Surface & J.Surface) -> J.Core & (J.Frame & State):
  (image, copy) = pair
  setup.uploaded(seed, core, image, J.Texture.load_from_image(frame, copy))

def setup.image(+seed: U32, +core: J.Core, frame: J.Frame, image: Maybe<J.Surface>) -> J.Core & (J.Frame & State):
  match image:
    case None{}: (J.Core.set_target_fps(core, 60), (frame, State{J.Random.seed(seed), Nil{}, Nil{}, None{}, None{}}))
    case Some{i}: setup.copied(seed, core, frame, J.Surface.copy(i))

# After InitWindow(800, 450) and SetRandomSeed(seed): GenImageColor(400, 225, BLACK), its texture, SetTargetFPS(60).
def setup(+seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.image(seed, core, frame, J.Surface.create(400, 225, J.Color.BLACK()))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - screen buffer", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
