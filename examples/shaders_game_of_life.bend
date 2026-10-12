# raylib [shaders] example - game of life, ported to Jonlib.
# Adapted from raylib 6.0 examples/shaders/shaders_game_of_life.c (zlib/libpng,
# Copyright (c) 2025 Jordi Santonja (@JordSant)); see LICENSES/raylib.txt.
#
# Two 2048x2048 worlds: each step draws the previous one into the current one
# through the game of life shader, and the window shows a part of the current
# one beside a menu of presets, modes, zoom and speed. A shader changes
# nothing on raylib's software renderer (docs/SHADERS.md), so a step copies
# the world, tinted RAYWHITE, there and here: the pattern dims instead of
# evolving. LoadImageFromTexture gives zeros on that renderer (docs/TEXTURES.md),
# which draw mode paints over. The example loads a preset's image when its
# button is pressed; the port loads the nine images in its setup. Loads
# resources/game_of_life/*.png from raylib's examples/shaders (not copied into
# this repository): run it from that directory, or pass `--resources <dir/>`.
# See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# zoom, offsetX and offsetY, framesPerStep, frame, the preset a button asked
# for (0: none; 1..10), the mode (0 RUN, 1 PAUSE, 2 DRAW), last frame's four
# buttons (zoom in and out, faster and slower), previousMousePosition and
# firstColor (2: none).
type View is Data:
  View{zoom: U32, ox: F32, oy: F32, per: U32, frame: U32, preset: U32, mode: U32, zin: Bool, zout: Bool, faster: Bool, slower: Bool, px: F32, py: F32, first: U32}

# currentWorld and previousWorld.
type Worlds is Type:
  Worlds{current: J.RenderTexture, previous: J.RenderTexture}

# The worlds (None when a render texture did not load: every frame is
# refused), the nine preset images in button order and imageToDraw.
type State is Type:
  State{view: View, gui: G.Gui, shader: J.Shader, rng: J.Random.State, worlds: Maybe<Worlds>, patterns: List<J.Surface>, image: Maybe<J.Surface>}

# -----------------------------------------------------------------------------
# The worlds

def world.ended(r: J.Frame & Maybe<J.RenderTexture>, previous: J.RenderTexture) -> J.Frame & Maybe<Worlds>:
  (frame, target) = r
  match target:
    case None{}: (frame, None{})
    case Some{current}: (frame, Some{Worlds{current, previous}})

# BeginTextureMode(*currentWorld); ClearBackground(RAYWHITE); EndTextureMode().
def cleared(frame: J.Frame, worlds: Worlds) -> J.Frame & Maybe<Worlds>:
  Worlds{current, previous} = worlds
  world.ended(J.Frame.end_texture_mode(J.Frame.clear_background(J.Frame.begin_texture_mode(frame, current), J.Color.RAYWHITE())), previous)

def updated.texture(result: Result<&1, &1, J.Texture & J.Surface.Error, J.Texture>) -> J.Texture:
  match result:
    case Done{texture}: texture
    case Fail{Tuple{texture, _}}: texture

# UpdateTextureRec(currentWorld->texture, rec, pixels).
def updated(worlds: Worlds, +rec: J.Rectangle, pixels: J.Surface) -> Worlds:
  Worlds{current, previous} = worlds
  J.RenderTexture{+id, texture, +depth} = current
  Worlds{J.RenderTexture{id, updated.texture(J.Texture.update_rec(texture, rec, pixels)), depth}, previous}

def step.drawn(r: J.Frame & J.Texture, +id: U32, +depth: U32) -> J.Frame & Maybe<Worlds>:
  (frame, texture) = r
  world.ended(J.Frame.end_texture_mode(J.Frame.end_shader_mode(frame)), J.RenderTexture{id, texture, depth})

# The worlds swap; BeginTextureMode(*currentWorld); BeginShaderMode(shdrGameOfLife);
# DrawTexturePro(previousWorld->texture, (0, 0, 2048, -2048), (0, 0, 2048,
# 2048), (0, 0), 0, RAYWHITE); EndShaderMode(); EndTextureMode().
def stepped(frame: J.Frame, worlds: Worlds, +shader: J.Shader) -> J.Frame & Maybe<Worlds>:
  Worlds{current, previous} = worlds
  J.RenderTexture{+id, texture, +depth} = current
  step.drawn(J.Draw.texture_pro(J.Frame.begin_shader_mode(J.Frame.begin_texture_mode(frame, previous), shader), texture,
    J.Rectangle{0.0, 0.0, 2048.0, F32.neg(2048.0)}, J.Rectangle{0.0, 0.0, 2048.0, 2048.0}, M.Vector2.zero(), 0.0, J.Color.RAYWHITE()), id, depth)

def show.done(r: J.Frame & J.Texture, +id: U32, +depth: U32, previous: J.RenderTexture) -> J.Frame & Worlds:
  (frame, texture) = r
  (frame, Worlds{J.RenderTexture{id, texture, depth}, previous})

# DrawTexturePro(currentWorld->texture, textureSourceToScreen, textureOnScreen, (0, 0), 0, WHITE).
def shown(frame: J.Frame, worlds: Worlds, +source: J.Rectangle) -> J.Frame & Worlds:
  Worlds{current, previous} = worlds
  J.RenderTexture{+id, texture, +depth} = current
  show.done(J.Draw.texture_pro(frame, texture, source, J.Rectangle{0.0, 0.0, 700.0, 450.0}, M.Vector2.zero(), 0.0, J.Color.WHITE()), id, depth, previous)

# -----------------------------------------------------------------------------
# Draw mode's image

type Grab is Type:
  Grab{frame: J.Frame, worlds: Maybe<Worlds>, image: Maybe<J.Surface>}

# LoadImageFromTexture(worldOnScreen.texture); UnloadRenderTexture(worldOnScreen).
def grab.read(r: J.Texture & Maybe<J.Surface>, frame: J.Frame, +sid: U32, +sdepth: U32, worlds: Worlds) -> Grab:
  (texture, image) = r
  Grab{J.RenderTexture.unload(frame, J.RenderTexture{sid, texture, sdepth}), Some{worlds}, image}

def grab.ended(r: J.Frame & Maybe<J.RenderTexture>, worlds: Worlds) -> Grab:
  (frame, screen) = r
  match screen:
    case None{}: Grab{frame, Some{worlds}, None{}}
    case Some{J.RenderTexture{+sid, texture, +sdepth}}: grab.read(J.Texture.load_image(texture), frame, sid, sdepth, worlds)

def grab.drawn(r: J.Frame & J.Texture, +id: U32, +depth: U32, previous: J.RenderTexture) -> Grab:
  (frame, texture) = r
  grab.ended(J.Frame.end_texture_mode(frame), Worlds{J.RenderTexture{id, texture, depth}, previous})

# DrawTexturePro(currentWorld->texture, (floorf(offsetX), floorf(offsetY),
# sizeInWorldX, -sizeInWorldY), (0, 0, sizeInWorldX, sizeInWorldY), (0, 0), 0, WHITE).
def grab.world(frame: J.Frame, worlds: Worlds, +ox: F32, +oy: F32, +sx: F32, +sy: F32) -> Grab:
  Worlds{current, previous} = worlds
  J.RenderTexture{+id, texture, +depth} = current
  grab.drawn(J.Draw.texture_pro(frame, texture, J.Rectangle{F32.floor(ox), F32.floor(oy), sx, F32.neg(sy)}, J.Rectangle{0.0, 0.0, sx, sy}, M.Vector2.zero(), 0.0, J.Color.WHITE()), id, depth, previous)

def grab.loaded(r: J.Frame & Maybe<J.RenderTexture>, worlds: Worlds, +ox: F32, +oy: F32, +sx: F32, +sy: F32) -> Grab:
  (frame, screen) = r
  match screen:
    case None{}: Grab{frame, Some{worlds}, None{}}
    case Some{target}: grab.world(J.Frame.begin_texture_mode(frame, target), worlds, ox, oy, sx, sy)

# worldOnScreen = LoadRenderTexture(sizeInWorldX, sizeInWorldY), the part of the
# world on screen drawn into it, and its image.
def grabbed(frame: J.Frame, worlds: Worlds, +ox: F32, +oy: F32, +sx: U32, +sy: U32) -> Grab:
  grab.loaded(J.RenderTexture.load(frame, sx, sy), worlds, ox, oy, U32.to_f32(sx), U32.to_f32(sy))

def fraction(+offset: F32) -> F32:
  (offset - F32.floor(offset) : F32)

def ceil(+x: F32) -> F32:
  F32.neg(F32.floor(F32.neg(x)))

# sizeInWorld = (int)ceilf((float)(window + offsetDecimal*zoom)/zoom), or
# world - (int)floorf(offset) when offset + sizeInWorld reaches the world's end.
def span(+window: F32, +offset: F32, +zoom: U32) -> U32:
  +size = F32.to_u32(ceil(((window + (fraction(offset) * U32.to_f32(zoom))) / U32.to_f32(zoom) : F32)))
  Bool.pick(U32, ((offset + U32.to_f32(size)) >= 2048.0 : F32), (2048 - F32.to_u32(F32.floor(offset)) : U32), size)

# (int)(mouse + offsetDecimal*zoom)/zoom in C ints, at most size - 1; a
# negative cell is 4294967295, outside every image.
def cell(+mouse: F32, +offset: F32, +zoom: U32, +size: U32) -> U32:
  +at = (mouse + (fraction(offset) * U32.to_f32(zoom)) : F32)
  +quotient = (F32.to_u32(F32.abs(at)) / zoom : U32)
  Bool.pick(U32, (at < 0.0 : F32) && (quotient > 0 : U32), 4294967295, Bool.pick(U32, (quotient >= size : U32), (size - 1 : U32), quotient))

def cell.f32(+at: U32) -> F32:
  Bool.pick(F32, U32.is_eq(at, 4294967295), F32.neg(1.0), U32.to_f32(at))

# (GetImageColor(*imageToDraw, mouseX, mouseY).r < 5)? 0 : 1; outside the image the color is blank.
def shade(color: Maybe<&2, U32>) -> U32:
  match color:
    case None{}: 0
    case Some{c}: Bool.pick(U32, (J.Color.red(c) < 5 : U32), 0, 1)

type Paint is Type:
  Paint{worlds: Worlds, image: J.Surface, first: U32}

def paint.copied(r: J.Surface & J.Surface, worlds: Worlds, +first: U32, +rec: J.Rectangle) -> Paint:
  (image, copy) = r
  Paint{updated(worlds, rec, copy), image, first}

# if (prevColor != firstColor) UpdateTextureRec(currentWorld->texture, the part on screen, imageToDraw->data).
def paint.changed(changed: Bool, image: J.Surface, worlds: Worlds, +first: U32, +rec: J.Rectangle) -> Paint:
  match changed:
    case False{}: Paint{worlds, image, first}
    case True{}: paint.copied(J.Surface.copy(image), worlds, first, rec)

def paint.shaded(+now: U32, image: J.Surface, worlds: Worlds, +first: U32, +x: U32, +y: U32, +rec: J.Rectangle) -> Paint:
  paint.changed(U32.is_ne(now, Bool.pick(U32, U32.is_eq(first, 2), now, first)),
    J.Surface.draw_pixel(image, cell.f32(x), cell.f32(y), Bool.pick(U32, U32.is_eq(Bool.pick(U32, U32.is_eq(first, 2), now, first), 1), J.Color.BLACK(), J.Color.RAYWHITE())),
    worlds, Bool.pick(U32, U32.is_eq(first, 2), now, first), rec)

# firstColor is the first cell's shade; ImageDrawPixel(imageToDraw, mouseX,
# mouseY, firstColor? BLACK : RAYWHITE).
def paint.got(r: J.Surface & Maybe<&2, U32>, worlds: Worlds, +first: U32, +x: U32, +y: U32, +rec: J.Rectangle) -> Paint:
  (image, color) = r
  paint.shaded(shade(color), image, worlds, first, x, y, rec)

def painted(image: J.Surface, worlds: Worlds, +first: U32, +x: U32, +y: U32, +rec: J.Rectangle) -> Paint:
  paint.got(J.Surface.get(image, x, y), worlds, first, x, y, rec)

# -----------------------------------------------------------------------------
# Presets

type Picked is Type:
  Picked{patterns: List<J.Surface>, pattern: Maybe<J.Surface>}

def pick.put(r: J.Surface & J.Surface, rest: List<J.Surface>) -> Picked:
  (kept, copy) = r
  Picked{Con{kept, rest}, Some{copy}}

def pick.cons(surface: J.Surface, picked: Picked) -> Picked:
  Picked{patterns, pattern} = picked
  Picked{Con{surface, patterns}, pattern}

# A copy of the n-th preset image.
def pick(patterns: List<J.Surface>, n: Nat) -> Picked:
  match patterns n:
    case Nil{} _: Picked{Nil{}, None{}}
    case Con{s, rest} 0n: pick.put(J.Surface.copy(s), rest)
    case Con{s, rest} 1n+k: pick.cons(s, pick(rest, k))

# presetPatterns[preset].position, for presets 1..10.
def position.x(+preset: U32) -> F32:
  Bool.pick(F32, U32.is_eq(preset, 4) || U32.is_eq(preset, 7) || U32.is_eq(preset, 9), 0.1, Bool.pick(F32, U32.is_eq(preset, 8), 0.2, 0.5))

def position.y(+preset: U32) -> F32:
  Bool.pick(F32, U32.is_eq(preset, 8), 0.2, 0.5)

# UpdateTextureRec(currentWorld->texture, (worldWidth*position.x -
# pattern.width/2.0f, worldHeight*position.y - pattern.height/2.0f,
# pattern.width, pattern.height), pattern.data).
def placed(pattern: J.Surface, worlds: Worlds, +px: F32, +py: F32) -> Worlds:
  J.Surface{+w, +h, format, pixels} = pattern
  updated(worlds, J.Rectangle{((2048.0 * px) - (U32.to_f32(w) / 2.0) : F32), ((2048.0 * py) - (U32.to_f32(h) / 2.0) : F32), U32.to_f32(w), U32.to_f32(h)}, J.Surface{w, h, format, pixels})

type Tiles is Type:
  Tiles{rng: J.Random.State, worlds: Worlds}

def tile.marked(dark: Bool, surface: J.Surface, +index: U32) -> J.Surface:
  match dark:
    case True{}: J.Surface.draw_pixel(surface, U32.to_f32((index / 256 : U32)), U32.to_f32((index % 256 : U32)), J.Color.BLACK())
    case False{}: surface

# for (x) for (y): if (GetRandomValue(0, 100) < 15) ImageDrawPixel(&pattern, x,
# y, BLACK): pixel `index` is (index/256, index%256), and r is its draw.
def tile.pixels(n: Nat, +index: U32, surface: J.Surface, r: J.Random.State & F32) -> J.Random.State & J.Surface:
  match n:
    case 0n:
      (rng, +v) = r
      (rng, tile.marked((v < 15.0 : F32), surface, index))
    case 1n+k:
      (rng, +v) = r
      tile.pixels(k, (index + 1 : U32), tile.marked((v < 15.0 : F32), surface, index), J.Random.value(rng, 0.0, 100.0))

# UpdateTextureRec(currentWorld->texture, (pattern.width*i, pattern.height*j,
# pattern.width, pattern.height), pattern.data) for tile t = 8*i + j.
def tile.drawn(r: J.Random.State & J.Surface, worlds: Worlds, +t: U32) -> Tiles:
  (rng, surface) = r
  Tiles{rng, updated(worlds, J.Rectangle{U32.to_f32((256 * (t / 8) : U32)), U32.to_f32((256 * (t % 8) : U32)), 256.0, 256.0}, surface)}

def tile.blank(blank: Maybe<J.Surface>, rng: J.Random.State, worlds: Worlds, +t: U32) -> Tiles:
  match blank:
    case None{}: Tiles{rng, worlds}
    case Some{surface}: tile.drawn(tile.pixels(U32.to_nat(65535), 0, surface, J.Random.value(rng, 0.0, 100.0)), worlds, t)

# A 256x256 RAYWHITE tile (GenImageColor, then ImageClearBackground for each).
def tile.one(state: Tiles, +t: U32) -> Tiles:
  Tiles{rng, worlds} = state
  tile.blank(J.Surface.create(256, 256, J.Color.RAYWHITE()), rng, worlds, t)

# The Random preset: 8x8 tiles.
def tiles(n: Nat, +t: U32, state: Tiles) -> Tiles:
  match n:
    case 0n: state
    case 1n+k: tiles(k, (t + 1 : U32), tile.one(state, t))

# -----------------------------------------------------------------------------
# The view

# The zoom buttons or the wheel change the zoom about the window's center.
def view.zooms(+view: View, +wheel: F32) -> Bool:
  View{zoom, _, _, _, _, _, _, zin, zout, _, _, _, _, _} = view
  zin || (zout && (zoom > 1 : U32)) || (wheel > 0.0 : F32) || (wheel < 0.0 : F32)

# frame++; the zoom; framesPerStep; and in the RUN and PAUSE modes the left
# button pans by the mouse's move over the window, then previousMousePosition.
def view.advanced(view: View, mouse: M.Vector2, +wheel: F32, +down: Bool) -> View:
  View{+zoom, +ox, +oy, +per, +frame, preset, +mode, +zin, +zout, +faster, +slower, +px, +py, first} = view
  M.Vector2{+mx, +my} = mouse
  +change = zin || (zout && (zoom > 1 : U32)) || (wheel > 0.0 : F32) || (wheel < 0.0 : F32)
  +z1 = Bool.pick(U32, change && (zin || (wheel > 0.0 : F32)), (zoom * 2 : U32), zoom)
  +z2 = Bool.pick(U32, change && (zout || (wheel < 0.0 : F32)) && (z1 > 1 : U32), (z1 / 2 : U32), z1)
  +ox1 = Bool.pick(F32, change, ((ox + (350.0 / U32.to_f32(zoom))) - (350.0 / U32.to_f32(z2)) : F32), ox)
  +oy1 = Bool.pick(F32, change, ((oy + (225.0 / U32.to_f32(zoom))) - (225.0 / U32.to_f32(z2)) : F32), oy)
  +per1 = Bool.pick(U32, faster && (per > 1 : U32), (per - 1 : U32), per)
  +free = (mode < 2 : U32)
  +panning = free && down && (mx < 700.0 : F32)
  View{z2, Bool.pick(F32, panning, (ox1 - ((mx - px) / U32.to_f32(z2)) : F32), ox1), Bool.pick(F32, panning, (oy1 - ((my - py) / U32.to_f32(z2)) : F32), oy1),
    Bool.pick(U32, slower, (per1 + 1 : U32), per1), (frame + 1 : U32), preset, mode, zin, zout, faster, slower, Bool.pick(F32, free, mx, px), Bool.pick(F32, free, my, py), first}

# A preset pauses and centers the window on its place.
def view.preset(view: View) -> View:
  View{+zoom, _, _, per, frame, +preset, _, zin, zout, faster, slower, px, py, first} = view
  View{zoom, ((2048.0 * position.x(preset)) - ((700.0 / U32.to_f32(zoom)) / 2.0) : F32), ((2048.0 * position.y(preset)) - ((450.0 / U32.to_f32(zoom)) / 2.0) : F32), per, frame, preset, 1, zin, zout, faster, slower, px, py, first}

def clamp(+offset: F32, +limit: F32) -> F32:
  Bool.pick(F32, (Bool.pick(F32, (offset < 0.0 : F32), 0.0, offset) > limit : F32), limit, Bool.pick(F32, (offset < 0.0 : F32), 0.0, offset))

# The window stays inside the world.
def view.clamped(view: View) -> View:
  View{+zoom, +ox, +oy, per, frame, preset, mode, zin, zout, faster, slower, px, py, first} = view
  View{zoom, clamp(ox, (2048.0 - (700.0 / U32.to_f32(zoom)) : F32)), clamp(oy, (2048.0 - (450.0 / U32.to_f32(zoom)) : F32)), per, frame, preset, mode, zin, zout, faster, slower, px, py, first}

def view.first(view: View, +first: U32) -> View:
  View{zoom, ox, oy, per, frame, preset, mode, zin, zout, faster, slower, px, py, _} = view
  View{zoom, ox, oy, per, frame, preset, mode, zin, zout, faster, slower, px, py, first}

# What the frame's controls answered: the preset, the mode and the four buttons.
def view.controls(view: View, +preset: U32, +mode: U32, +zin: Bool, +zout: Bool, +faster: Bool, +slower: Bool) -> View:
  View{zoom, ox, oy, per, frame, _, _, _, _, _, _, px, py, first} = view
  View{zoom, ox, oy, per, frame, preset, mode, zin, zout, faster, slower, px, py, first}

def View.zoom(+view: View) -> U32:
  View{zoom, _, _, _, _, _, _, _, _, _, _, _, _, _} = view
  zoom

def View.per(+view: View) -> U32:
  View{_, _, _, per, _, _, _, _, _, _, _, _, _, _} = view
  per

def View.mode(+view: View) -> U32:
  View{_, _, _, _, _, _, mode, _, _, _, _, _, _, _} = view
  mode

def View.preset(+view: View) -> U32:
  View{_, _, _, _, _, preset, _, _, _, _, _, _, _, _} = view
  preset

def View.first(+view: View) -> U32:
  View{_, _, _, _, _, _, _, _, _, _, _, _, _, first} = view
  first

def View.ox(+view: View) -> F32:
  View{_, ox, _, _, _, _, _, _, _, _, _, _, _, _} = view
  ox

def View.oy(+view: View) -> F32:
  View{_, _, oy, _, _, _, _, _, _, _, _, _, _, _} = view
  oy

# (mode == MODE_RUN) && ((frame%framesPerStep) == 0).
def View.steps(+view: View) -> Bool:
  View{_, _, _, per, frame, _, mode, _, _, _, _, _, _, _} = view
  U32.is_eq(mode, 0) && U32.is_eq((frame % U32.max(per, 1) : U32), 0)

# textureSourceToScreen = (offsetX, offsetY, windowWidth/zoom, windowHeight/zoom).
def View.source(+view: View) -> J.Rectangle:
  View{zoom, ox, oy, _, _, _, _, _, _, _, _, _, _, _} = view
  J.Rectangle{ox, oy, (700.0 / U32.to_f32(zoom) : F32), (450.0 / U32.to_f32(zoom) : F32)}

# -----------------------------------------------------------------------------
# The frame, stage by stage. A pass without worlds is refused at its end.

type Pass is Type:
  Pass{frame: J.Frame, worlds: Maybe<Worlds>, patterns: List<J.Surface>, image: Maybe<J.Surface>, rng: J.Random.State, view: View}

# Draw mode with the left button over the window: the cell under the mouse.
def draw.painted(paint: Paint, frame: J.Frame, patterns: List<J.Surface>, rng: J.Random.State, +view: View) -> Pass:
  Paint{worlds, image, +first} = paint
  Pass{frame, Some{worlds}, patterns, Some{image}, rng, view.first(view, first)}

def draw.paint(down: Bool, frame: J.Frame, worlds: Worlds, patterns: List<J.Surface>, image: J.Surface, rng: J.Random.State, +view: View, +mouse: M.Vector2, +sx: U32, +sy: U32) -> Pass:
  match down:
    case False{}: Pass{frame, Some{worlds}, patterns, Some{image}, rng, view.first(view, 2)}
    case True{}:
      M.Vector2{+mx, +my} = mouse
      draw.painted(painted(image, worlds, View.first(view), cell(mx, View.ox(view), View.zoom(view), sx), cell(my, View.oy(view), View.zoom(view), sy),
        J.Rectangle{F32.floor(View.ox(view)), F32.floor(View.oy(view)), U32.to_f32(sx), U32.to_f32(sy)}), frame, patterns, rng, view)

def draw.imaged(grab: Grab, patterns: List<J.Surface>, rng: J.Random.State, +view: View, +mouse: M.Vector2, +down: Bool, +sx: U32, +sy: U32) -> Pass:
  Grab{frame, worlds, image} = grab
  match worlds image:
    case Some{w} Some{i}: draw.paint(down, frame, w, patterns, i, rng, view, mouse, sx, sy)
    case Some{w} None{}: Pass{frame, Some{w}, patterns, None{}, rng, view.first(view, Bool.pick(U32, down, View.first(view), 2))}
    case None{} _: Pass{frame, None{}, patterns, None{}, rng, view}

# The image is made when there is none.
def draw.image(image: Maybe<J.Surface>, frame: J.Frame, worlds: Worlds, patterns: List<J.Surface>, rng: J.Random.State, +view: View, +mouse: M.Vector2, +down: Bool, +sx: U32, +sy: U32) -> Pass:
  match image:
    case Some{i}: draw.paint(down, frame, worlds, patterns, i, rng, view, mouse, sx, sy)
    case None{}: draw.imaged(grabbed(frame, worlds, View.ox(view), View.oy(view), sx, sy), patterns, rng, view, mouse, down, sx, sy)

# The RUN and PAUSE modes free the image; draw mode makes and paints it.
def stage.mode(drawing: Bool, pass: Pass, +mouse: M.Vector2, +down: Bool) -> Pass:
  match drawing:
    case False{}:
      Pass{frame, worlds, patterns, _, rng, view} = pass
      Pass{frame, worlds, patterns, None{}, rng, view}
    case True{}:
      Pass{frame, worlds, patterns, image, rng, +view} = pass
      match worlds:
        case None{}: Pass{frame, None{}, patterns, None{}, rng, view}
        case Some{w}: draw.image(image, frame, w, patterns, rng, view, mouse, down, span(700.0, View.ox(view), View.zoom(view)), span(450.0, View.oy(view), View.zoom(view)))

def preset.random(tiles: Tiles, frame: J.Frame, patterns: List<J.Surface>, image: Maybe<J.Surface>, +view: View) -> Pass:
  Tiles{rng, worlds} = tiles
  Pass{frame, Some{worlds}, patterns, image, rng, view.preset(view)}

def preset.set(pattern: Maybe<J.Surface>, worlds: Maybe<Worlds>, frame: J.Frame, patterns: List<J.Surface>, image: Maybe<J.Surface>, rng: J.Random.State, +view: View) -> Pass:
  match pattern worlds:
    case Some{p} Some{w}: Pass{frame, Some{placed(p, w, position.x(View.preset(view)), position.y(View.preset(view)))}, patterns, image, rng, view.preset(view)}
    case _ _: Pass{frame, None{}, patterns, image, rng, view}

def preset.placed(picked: Picked, r: J.Frame & Maybe<Worlds>, image: Maybe<J.Surface>, rng: J.Random.State, +view: View) -> Pass:
  Picked{patterns, pattern} = picked
  (frame, worlds) = r
  preset.set(pattern, worlds, frame, patterns, image, rng, view)

# A preset's button was pressed: the world is cleared and its image placed, or
# (the last one) the world is filled at random.
def stage.preset(kind: U32, pass: Pass) -> Pass:
  match kind:
    case 0: pass
    case 1:
      Pass{frame, worlds, patterns, image, rng, +view} = pass
      match worlds:
        case None{}: Pass{frame, None{}, patterns, image, rng, view}
        case Some{w}: preset.placed(pick(patterns, U32.to_nat((View.preset(view) - 1 : U32))), cleared(frame, w), image, rng, view)
    case _:
      Pass{frame, worlds, patterns, image, rng, +view} = pass
      match worlds:
        case None{}: Pass{frame, None{}, patterns, image, rng, view}
        case Some{w}: preset.random(tiles(64n, 0, Tiles{rng, w}), frame, patterns, image, view)

def stage.stepped(r: J.Frame & Maybe<Worlds>, patterns: List<J.Surface>, image: Maybe<J.Surface>, rng: J.Random.State, +view: View) -> Pass:
  (frame, worlds) = r
  Pass{frame, worlds, patterns, image, rng, view}

def stage.step.at(steps: Bool, frame: J.Frame, worlds: Worlds, patterns: List<J.Surface>, image: Maybe<J.Surface>, rng: J.Random.State, +view: View, +shader: J.Shader) -> Pass:
  match steps:
    case False{}: Pass{frame, Some{worlds}, patterns, image, rng, view}
    case True{}: stage.stepped(stepped(frame, worlds, shader), patterns, image, rng, view)

# The window's limits, then a step in RUN mode every framesPerStep frames.
def stage.step(pass: Pass, +shader: J.Shader) -> Pass:
  Pass{frame, worlds, patterns, image, rng, +view} = pass
  match worlds:
    case None{}: Pass{frame, None{}, patterns, image, rng, view.clamped(view)}
    case Some{w}: stage.step.at(View.steps(view.clamped(view)), frame, w, patterns, image, rng, view.clamped(view), shader)

# -----------------------------------------------------------------------------
# The screen

def names() -> +List<String>:
  ["Glider", "R-pentomino", "Acorn", "Spaceships", "Still lifes", "Oscillators", "Puffer train", "Glider Gun", "Breeder", "Random"]

# for (i) if (GuiButton((710, 70 + 18*i, 80, 16), name)) preset = i; r is the
# button before's frame and answer.
def presets(names: +List<String>, +i: U32, +gui: G.Gui, +core: J.Core, +preset: U32, r: J.Frame & Bool) -> J.Frame & U32:
  match names:
    case Nil{}:
      (frame, +pressed) = r
      (frame, Bool.pick(U32, pressed, i, preset))
    case Con{+name, rest}:
      (frame, +pressed) = r
      presets(rest, (i + 1 : U32), gui, core, Bool.pick(U32, pressed, i, preset), G.Gui.button(gui, core, frame, J.Rectangle{710.0, (70.0 + U32.to_f32((18 * i : U32)) : F32), 80.0, 16.0}, name))

def text.of(text: Maybe<String>) -> String:
  match text:
    case None{}: ""
    case Some{t}: t

def fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  (core, (state, J.Draw.fps(frame, 712.0, 426.0, fps)))

def fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: fps.at(state, frame, pair)

# buttonSlower = GuiButton((710, 400, 80, 16), "Slower"); DrawFPS(712, 426).
def gui.slower(r: J.Frame & Bool, +core: J.Core, +gui: G.Gui, +shader: J.Shader, rng: J.Random.State, worlds: Worlds, patterns: List<J.Surface>, image: Maybe<J.Surface>, +view: View, +preset: U32, +mode: U32, +zin: Bool, +zout: Bool, +faster: Bool) -> J.Core & (State & J.Frame):
  (frame, +slower) = r
  fps.done(State{view.controls(view, preset, mode, zin, zout, faster, slower), gui, shader, rng, Some{worlds}, patterns, image}, frame, J.Core.get_fps(core, J.Core.get_time(core)), core)

# buttonFaster = GuiButton((710, 382, 80, 16), "Faster").
def gui.faster(r: J.Frame & Bool, +core: J.Core, +gui: G.Gui, +shader: J.Shader, rng: J.Random.State, worlds: Worlds, patterns: List<J.Surface>, image: Maybe<J.Surface>, +view: View, +preset: U32, +mode: U32, +zin: Bool, +zout: Bool) -> J.Core & (State & J.Frame):
  (frame, +faster) = r
  gui.slower(G.Gui.button(gui, core, frame, J.Rectangle{710.0, 400.0, 80.0, 16.0}, "Slower"), core, gui, shader, rng, worlds, patterns, image, view, preset, mode, zin, zout, faster)

# buttonZomOut = GuiButton((710, 346, 80, 16), "Zoom out"); DrawText(TextFormat(
# "Speed: %i frame%s", framesPerStep, (framesPerStep > 1)? "s" : ""), 710, 370, 8, GRAY).
def gui.zout(r: J.Frame & Bool, +core: J.Core, +gui: G.Gui, +shader: J.Shader, rng: J.Random.State, worlds: Worlds, patterns: List<J.Surface>, image: Maybe<J.Surface>, +view: View, +preset: U32, +mode: U32, +zin: Bool) -> J.Core & (State & J.Frame):
  (frame, +zout) = r
  f1 = J.Draw.text(frame, text.of(J.Text.format("Speed: %i frame%s", [J.TextInt{View.per(view)}, J.TextString{Bool.pick(String, (View.per(view) > 1 : U32), "s", "")}])), 710.0, 370.0, 8.0, J.Color.GRAY())
  gui.faster(G.Gui.button(gui, core, f1, J.Rectangle{710.0, 382.0, 80.0, 16.0}, "Faster"), core, gui, shader, rng, worlds, patterns, image, view, preset, mode, zin, zout)

# buttonZoomIn = GuiButton((710, 328, 80, 16), "Zoom in").
def gui.zin(r: J.Frame & Bool, +core: J.Core, +gui: G.Gui, +shader: J.Shader, rng: J.Random.State, worlds: Worlds, patterns: List<J.Surface>, image: Maybe<J.Surface>, +view: View, +preset: U32, +mode: U32) -> J.Core & (State & J.Frame):
  (frame, +zin) = r
  gui.zout(G.Gui.button(gui, core, frame, J.Rectangle{710.0, 346.0, 80.0, 16.0}, "Zoom out"), core, gui, shader, rng, worlds, patterns, image, view, preset, mode, zin)

# GuiToggleGroup((710, 258, 80, 16), "Run\nPause\nDraw", &mode); DrawText(
# TextFormat("Zoom: %ix", zoom), 710, 316, 8, GRAY).
def gui.mode(r: J.Frame & U32, +core: J.Core, +gui: G.Gui, +shader: J.Shader, rng: J.Random.State, worlds: Worlds, patterns: List<J.Surface>, image: Maybe<J.Surface>, +view: View, +preset: U32) -> J.Core & (State & J.Frame):
  (frame, +mode) = r
  f1 = J.Draw.text(frame, text.of(J.Text.format("Zoom: %ix", [J.TextInt{View.zoom(view)}])), 710.0, 316.0, 8.0, J.Color.GRAY())
  gui.zin(G.Gui.button(gui, core, f1, J.Rectangle{710.0, 328.0, 80.0, 16.0}, "Zoom in"), core, gui, shader, rng, worlds, patterns, image, view, preset, mode)

def gui.presets(r: J.Frame & U32, +core: J.Core, +gui: G.Gui, +shader: J.Shader, rng: J.Random.State, worlds: Worlds, patterns: List<J.Surface>, image: Maybe<J.Surface>, +view: View) -> J.Core & (State & J.Frame):
  (frame, +preset) = r
  gui.mode(G.Gui.toggle_group(gui, core, frame, J.Rectangle{710.0, 258.0, 80.0, 16.0}, "Run\nPause\nDraw", View.mode(view)), core, gui, shader, rng, worlds, patterns, image, view, preset)

# The world on screen, the menu's line and panel, its titles and the presets.
def screen(r: J.Frame & Worlds, +core: J.Core, +gui: G.Gui, +shader: J.Shader, rng: J.Random.State, patterns: List<J.Surface>, image: Maybe<J.Surface>, +view: View) -> J.Core & (State & J.Frame):
  (frame, worlds) = r
  f1 = J.Draw.rectangle(J.Draw.line(frame, 700.0, 0.0, 700.0, 450.0, J.Color.rgba(218, 218, 218, 255)), 700.0, 0.0, 100.0, 450.0, J.Color.rgba(232, 232, 232, 255))
  f2 = J.Draw.text(J.Draw.text(f1, "Conway's", 704.0, 4.0, 20.0, J.Color.DARKBLUE()), " game of", 704.0, 19.0, 20.0, J.Color.DARKBLUE())
  f3 = J.Draw.text(J.Draw.text(f2, "  life", 708.0, 34.0, 20.0, J.Color.DARKBLUE()), "in raylib", 757.0, 42.0, 6.0, J.Color.BLACK())
  f4 = J.Draw.text(f3, "Presets", 710.0, 58.0, 8.0, J.Color.GRAY())
  gui.presets(presets(names(), 0, gui, core, 0, (f4, False{})), core, gui, shader, rng, worlds, patterns, image, view)

# FreeImageToDraw on a zoom change.
def draw.kept(freed: Bool, image: Maybe<J.Surface>) -> Maybe<J.Surface>:
  match freed:
    case True{}: None{}
    case False{}: image

def over(mouse: M.Vector2) -> Bool:
  M.Vector2{x, _} = mouse
  (x < 700.0 : F32)

def draw.end(pass: Pass, +core: J.Core, +gui: G.Gui, +shader: J.Shader) -> J.Core & (State & J.Frame):
  Pass{frame, worlds, patterns, image, rng, +view} = pass
  match worlds:
    case None{}: (core, (State{view, gui, shader, rng, None{}, patterns, image}, J.Frame.refuse(frame)))
    case Some{w}: screen(shown(frame, w, View.source(view)), core, gui, shader, rng, patterns, image, view)

def preset.kind(+preset: U32) -> U32:
  Bool.pick(U32, U32.is_eq(preset, 0), 0, Bool.pick(U32, U32.is_eq(preset, 10), 2, 1))

# The whole frame in the example's order: the view, the mode's mouse work, the
# preset, the limits and the step, then the screen.
def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+view, +gui, +shader, rng, worlds, patterns, image} = state
  +wheel = J.Input.get_mouse_wheel_move(core)
  +mouse = J.Input.get_mouse_position(core)
  +down = J.Input.is_mouse_button_down(core, J.MouseButton.MOUSE_BUTTON_LEFT())
  +moved = view.advanced(view, mouse, wheel, down)
  draw.end(stage.step(stage.preset(preset.kind(View.preset(moved)), stage.mode(U32.is_eq(View.mode(moved), 2),
    Pass{frame, worlds, patterns, draw.kept(view.zooms(view, wheel), image), rng, moved}, mouse, down && over(mouse))), shader), core, gui, shader)

def update(+core: J.Core, state: State) -> J.Core & State:
  (core, state)

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# -----------------------------------------------------------------------------
# Setup

def surfaces.done(whole: Bool, acc: List<J.Surface>) -> Maybe<List<J.Surface>>:
  match whole:
    case True{}: Some{List.reverse(&1, J.Surface, acc)}
    case False{}: None{}

def surfaces(results: List<Result<&1, &1, J.Surface.IOError, J.Surface>>, acc: List<J.Surface>, +whole: Bool) -> Maybe<List<J.Surface>>:
  match results:
    case Nil{}: surfaces.done(whole, acc)
    case Con{Done{surface}, rest}: surfaces(rest, Con{surface, acc}, whole)
    case Con{Fail{_}, rest}: surfaces(rest, acc, False{})

def start() -> View:
  View{1, 674.0, 799.0, 1, 0, 0, 0, False{}, False{}, False{}, False{}, 0.0, 0.0, 2}

# The shader with its "resolution" (2048, 2048).
def shader() -> J.Shader:
  +s0 = J.Shader.load(None{}, Some{"resources/shaders/glsl330/game_of_life.fs"})
  J.Shader.set_value(s0, J.Shader.get_location(s0, "resolution"), [F32.bits(2048.0), F32.bits(2048.0)], 1)

def setup.state(+core: J.Core, frame: J.Frame, worlds: Maybe<Worlds>, patterns: List<J.Surface>, rng: J.Random.State) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{start(), G.Gui.new(), shader(), rng, worlds, patterns, None{}}))

# UpdateTextureRec(world2.texture, (worldWidth/2.0f, worldHeight/2.0f,
# startPattern.width, startPattern.height), startPattern.data): the R-pentomino.
def setup.pattern(pattern: J.Surface, worlds: Worlds) -> Worlds:
  J.Surface{+w, +h, format, pixels} = pattern
  updated(worlds, J.Rectangle{1024.0, 1024.0, U32.to_f32(w), U32.to_f32(h)}, J.Surface{w, h, format, pixels})

def setup.set(pattern: Maybe<J.Surface>, worlds: Maybe<Worlds>, +core: J.Core, frame: J.Frame, patterns: List<J.Surface>, rng: J.Random.State) -> J.Core & (J.Frame & State):
  match pattern worlds:
    case Some{p} Some{w}: setup.state(core, frame, Some{setup.pattern(p, w)}, patterns, rng)
    case _ _: setup.state(core, frame, None{}, patterns, rng)

def setup.started(picked: Picked, r: J.Frame & Maybe<Worlds>, +core: J.Core, rng: J.Random.State) -> J.Core & (J.Frame & State):
  Picked{patterns, pattern} = picked
  (frame, worlds) = r
  setup.set(pattern, worlds, core, frame, patterns, rng)

# world1 and world2 = LoadRenderTexture(2048, 2048); world2 is cleared RAYWHITE
# and is the current world.
def setup.second(r: J.Frame & Maybe<J.RenderTexture>, first: J.RenderTexture, +core: J.Core, patterns: List<J.Surface>, rng: J.Random.State) -> J.Core & (J.Frame & State):
  (frame, second) = r
  match second:
    case None{}: setup.state(core, frame, None{}, patterns, rng)
    case Some{current}: setup.started(pick(patterns, 1n), cleared(frame, Worlds{current, first}), core, rng)

def setup.first(r: J.Frame & Maybe<J.RenderTexture>, +core: J.Core, patterns: List<J.Surface>, rng: J.Random.State) -> J.Core & (J.Frame & State):
  (frame, first) = r
  match first:
    case None{}: setup.state(core, frame, None{}, patterns, rng)
    case Some{world}: setup.second(J.RenderTexture.load(frame, 2048, 2048), world, core, patterns, rng)

def setup.done(+seed: U32, +core: J.Core, frame: J.Frame, patterns: Maybe<List<J.Surface>>) -> J.Core & (J.Frame & State):
  match patterns:
    case None{}: setup.state(core, frame, None{}, Nil{}, J.Random.seed(seed))
    case Some{p}: setup.first(J.RenderTexture.load(frame, 2048, 2048), core, p, J.Random.seed(seed))

# After InitWindow(800, 450): the shader, the two worlds and the start pattern,
# SetTargetFPS(60); and the nine preset images, in the buttons' order.
def setup(+seed: U32, +dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  do IO<J.Core & (J.Frame & State)>:
    a : Result<&1, &1, J.Surface.IOError, J.Surface> <- J.Surface.load_image(dir ++ "resources/game_of_life/glider.png")
    b : Result<&1, &1, J.Surface.IOError, J.Surface> <- J.Surface.load_image(dir ++ "resources/game_of_life/r_pentomino.png")
    c : Result<&1, &1, J.Surface.IOError, J.Surface> <- J.Surface.load_image(dir ++ "resources/game_of_life/acorn.png")
    d : Result<&1, &1, J.Surface.IOError, J.Surface> <- J.Surface.load_image(dir ++ "resources/game_of_life/spaceships.png")
    e : Result<&1, &1, J.Surface.IOError, J.Surface> <- J.Surface.load_image(dir ++ "resources/game_of_life/still_lifes.png")
    f : Result<&1, &1, J.Surface.IOError, J.Surface> <- J.Surface.load_image(dir ++ "resources/game_of_life/oscillators.png")
    g : Result<&1, &1, J.Surface.IOError, J.Surface> <- J.Surface.load_image(dir ++ "resources/game_of_life/puffer_train.png")
    h : Result<&1, &1, J.Surface.IOError, J.Surface> <- J.Surface.load_image(dir ++ "resources/game_of_life/glider_gun.png")
    i : Result<&1, &1, J.Surface.IOError, J.Surface> <- J.Surface.load_image(dir ++ "resources/game_of_life/breeder.png")
    IO.pure(J.Core & (J.Frame & State), setup.done(seed, core, frame, surfaces([a, b, c, d, e, f, g, h, i], Nil{}, True{})))

# "--resources DIR/" (default: the working directory) and "--frames N".
def options(args: List<String>, +mode: U32, dir: String, +frames: U32) -> String & U32:
  match args:
    case Nil{}: (dir, frames)
    case Con{+a, rest}:
      match mode:
        case 1: options(rest, 0, a, frames)
        case 2: options(rest, 0, dir, J.Desktop.frames_arg(["--frames", a]))
        case _: options(rest, Bool.pick(U32, String.eq(a, "--resources"), 1, Bool.pick(U32, String.eq(a, "--frames"), 2, 0)), dir, frames)

def run.with(parsed: String & U32) -> IO(Unit):
  (+dir, +limit) = parsed
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shaders] example - game of life", 800, 450, limit,
    core => frame => setup(0, dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
