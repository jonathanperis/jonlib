# raylib [textures] example - fog of war, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_fog_of_war.c
# (zlib/libpng, Copyright (c) 2018-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A 25x15 map of two random tile kinds and a player the arrow keys move; the
# fog (unseen, seen before, in sight) is drawn one pixel a tile into a
# render texture and stretched over the map with bilinear filtering.
# SetTextureWrap(CLAMP) changes nothing in raylib's software renderer, nor
# here (docs/TEXTURES.md). raylib seeds GetRandomValue from time(NULL) in
# InitWindow; here the seed is a setup argument (docs/DRIVER.md).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# ids, fog: the 375 tiles in row order; fog 0 unseen, 1 in sight, 2 seen before.
type State is Type:
  State{target: Maybe<J.RenderTexture>, ids: +List<U32>, fog: +List<U32>, position: M.Vector2, tx: U32, ty: U32}

# A tile within PLAYER_TILE_VISIBILITY of the player's ([t - 2, t + 2) both
# ways) is in sight; one in sight before becomes seen.
def fog.state(+state: U32, +i: U32, +tx: U32, +ty: U32) -> U32:
  +near = ((((i % 25) + 2) - tx < 4 : U32)) && ((((i / 25) + 2) - ty < 4 : U32))
  Bool.pick(U32, near, 1, Bool.pick(U32, U32.is_eq(state, 1), 2, state))

def fog.seen(fog: +List<U32>, +i: U32, +tx: U32, +ty: U32) -> +List<U32>:
  match fog:
    case Nil{}: Nil{}
    case Con{+state, rest}: Con{fog.state(state, i, tx, ty), fog.seen(rest, (i + 1 : U32), tx, ty)}

# The arrows move 5 pixels inside the map; the player's tile is the one under its middle.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{target, +ids, +fog, +position, _, _} = state
  M.Vector2{+x, +y} = position
  +right = Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_RIGHT()), (x + 5.0 : F32), x)
  +left = Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT()), (right - 5.0 : F32), right)
  +down = Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_DOWN()), (y + 5.0 : F32), y)
  +up = Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_UP()), (down - 5.0 : F32), down)
  +px = Bool.pick(F32, (left < 0.0 : F32), 0.0, Bool.pick(F32, ((left + 16.0) > 800.0 : F32), (25.0 * 32.0 - 16.0 : F32), left))
  +py = Bool.pick(F32, (up < 0.0 : F32), 0.0, Bool.pick(F32, ((up + 16.0) > 480.0 : F32), (15.0 * 32.0 - 16.0 : F32), up))
  +tx = F32.to_u32(((px + 32.0 / 2.0) / 32.0 : F32))
  +ty = F32.to_u32(((py + 32.0 / 2.0) / 32.0 : F32))
  (core, State{target, ids, fog.seen(fog, 0, tx, ty), M.Vector2{px, py}, tx, ty})

# DrawRectangle(x, y, 1, 1, BLACK) for unseen, Fade(BLACK, 0.8f) for seen before.
def fog.cell(state: U32, +i: U32, frame: J.Frame) -> J.Frame:
  match state:
    case 0: J.Draw.rectangle(frame, U32.to_f32((i % 25 : U32)), U32.to_f32((i / 25 : U32)), 1.0, 1.0, J.Color.BLACK())
    case 2: J.Draw.rectangle(frame, U32.to_f32((i % 25 : U32)), U32.to_f32((i / 25 : U32)), 1.0, 1.0, J.Color.with_alpha(J.Color.BLACK(), 0.8))
    case _: frame

def fog.cells(fog: +List<U32>, +i: U32, frame: J.Frame) -> J.Frame:
  match fog:
    case Nil{}: frame
    case Con{+state, rest}: fog.cells(rest, (i + 1 : U32), fog.cell(state, i, frame))

# A tile by its id (BLUE or Fade(BLUE, 0.9f)) and its border.
def tile(+id: U32, +i: U32, frame: J.Frame) -> J.Frame:
  +x = U32.to_f32(((i % 25) * 32 : U32))
  +y = U32.to_f32(((i / 25) * 32 : U32))
  f1 = J.Draw.rectangle(frame, x, y, 32.0, 32.0, Bool.pick(U32, U32.is_eq(id, 0), J.Color.BLUE(), J.Color.with_alpha(J.Color.BLUE(), 0.9)))
  J.Draw.rectangle_lines(f1, x, y, 32.0, 32.0, J.Color.with_alpha(J.Color.DARKBLUE(), 0.5))

def tiles(ids: +List<U32>, +i: U32, frame: J.Frame) -> J.Frame:
  match ids:
    case Nil{}: frame
    case Con{+id, rest}: tiles(rest, (i + 1 : U32), tile(id, i, frame))

def label(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, 10.0, 20.0, J.Color.RAYWHITE())

def labels(+tx: U32, +ty: U32, frame: J.Frame) -> J.Frame:
  J.Draw.text(label(J.Text.format("Current tile: [%i,%i]", [J.TextInt{tx}, J.TextInt{ty}]), frame), "ARROW KEYS to move", 10.0, (450.0 - 25.0 : F32), 20.0, J.Color.RAYWHITE())

def shown(+id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Frame & Maybe<J.RenderTexture>:
  (frame, texture) = r
  (frame, Some{J.RenderTexture{id, texture, depth}})

# DrawTexturePro(fogOfWar.texture, (0, 0, width, -height), the whole map, (0, 0), 0, WHITE).
def show(+libm: M.Libm, frame: J.Frame, target: J.RenderTexture) -> J.Frame & Maybe<J.RenderTexture>:
  J.RenderTexture{+id, texture, +depth} = target
  J.Texture{+tid, +w, +h, +format, +linear, +alpha, texels} = texture
  shown(id, depth, J.Draw.texture_pro_for(libm, frame, J.Texture{tid, w, h, format, linear, alpha, texels}, J.Rectangle{0.0, 0.0, U32.to_f32(w), F32.neg(U32.to_f32(h))},
    J.Rectangle{0.0, 0.0, (25.0 * 32.0 : F32), (15.0 * 32.0 : F32)}, M.Vector2.zero(), 0.0, J.Color.WHITE()))

def draw.done(+core: J.Core, +ids: +List<U32>, +fog: +List<U32>, +position: M.Vector2, +tx: U32, +ty: U32, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  (core, (State{target, ids, fog, position, tx, ty}, labels(tx, ty, frame)))

# The map and the player (DrawRectangleV(playerPosition, (16, 16), RED)).
def scene(+ids: +List<U32>, +position: M.Vector2, frame: J.Frame) -> J.Frame:
  J.Draw.rectangle_v(tiles(ids, 0, J.Frame.clear_background(frame, J.Color.RAYWHITE())), position, M.Vector2{16.0, 16.0}, J.Color.RED())

def draw.screen(+libm: M.Libm, +core: J.Core, +ids: +List<U32>, +fog: +List<U32>, +position: M.Vector2, +tx: U32, +ty: U32, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, target) = r
  match target:
    case None{}: draw.done(core, ids, fog, position, tx, ty, (scene(ids, position, frame), None{}))
    case Some{t}: draw.done(core, ids, fog, position, tx, ty, show(libm, scene(ids, position, frame), t))

# The fog pass (raylib draws it before BeginDrawing; here the draw does that
# first, the same pixels), then the screen.
def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{target, +ids, +fog, +position, +tx, +ty} = state
  match target:
    case None{}: draw.done(core, ids, fog, position, tx, ty, (scene(ids, position, frame), None{}))
    case Some{t}: draw.screen(libm, core, ids, fog, position, tx, ty,
      J.Frame.end_texture_mode(fog.cells(fog, 0, J.Frame.clear_background(J.Frame.begin_texture_mode(frame, t), J.Color.BLANK()))))

# The main loop's body; libm is the profile of DrawTexturePro's sinf/cosf (rotation 0).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def ids.push(done: +List<U32>, draw: J.Random.State & F32) -> J.Random.State & +List<U32>:
  (rng, +value) = draw
  (rng, Con{F32.to_u32(value), done})

def ids.one(acc: J.Random.State & +List<U32>) -> J.Random.State & +List<U32>:
  (rng, done) = acc
  ids.push(done, J.Random.value(rng, 0.0, 1.0))

# map.tileIds[i] = GetRandomValue(0, 1); they come back newest first.
def ids(n: Nat, acc: J.Random.State & +List<U32>) -> J.Random.State & +List<U32>:
  match n:
    case 0n: acc
    case 1n+p: ids(p, ids.one(acc))

def ids.made(r: J.Random.State & +List<U32>) -> +List<U32>:
  (_, reversed) = r
  List.reverse(&2, U32, reversed)

# map.tileFog: every tile unseen (RL_CALLOC).
def unseen(n: Nat) -> +List<U32>:
  match n:
    case 0n: Nil{}
    case 1n+p: Con{0, unseen(p)}

# SetTextureFilter(fogOfWar.texture, TEXTURE_FILTER_BILINEAR); SetTextureWrap(fogOfWar.texture, TEXTURE_WRAP_CLAMP).
def filtered(target: Maybe<J.RenderTexture>) -> Maybe<J.RenderTexture>:
  match target:
    case None{}: None{}
    case Some{t}:
      J.RenderTexture{+id, texture, +depth} = t
      Some{J.RenderTexture{id, J.Texture.set_wrap(J.Texture.set_filter(texture, J.TextureFilter.TEXTURE_FILTER_BILINEAR()), J.TextureWrap.TEXTURE_WRAP_CLAMP()), depth}}

def setup.loaded(+seed: U32, +core: J.Core, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, target) = r
  (J.Core.set_target_fps(core, 60), (frame, State{filtered(target), ids.made(ids(U32.to_nat(375), (J.Random.seed(seed), Nil{}))),
    unseen(U32.to_nat(375)), M.Vector2{180.0, 130.0}, 0, 0}))

# After InitWindow(800, 450) and SetRandomSeed(seed): the tile ids, the player
# at (180, 130), the 25x15 fog texture, SetTargetFPS(60).
def setup(+seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.loaded(seed, core, J.RenderTexture.load(frame, 25, 15))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - fog of war", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
