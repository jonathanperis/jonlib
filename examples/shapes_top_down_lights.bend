# raylib [shapes] example - top down lights, ported to Jonlib.
# Adapted from raylib 6.0 examples/shapes/shapes_top_down_lights.c (zlib/libpng,
# Copyright (c) 2022-2025 Jeffery Myers (@JeffM2501)); see LICENSES/raylib.txt.
#
# Lights over a checkerboard with boxes that cast shadow volumes: each light
# has a mask (a render texture: a radial gradient with the shadow quads cut
# out) and the masks are merged into one screen-sized light mask. The left
# button drags the first light, the right one adds a light (16 at most), F1
# shows the shadow volumes. The example's custom blend modes
# (rlSetBlendFactors, rlSetBlendMode) exist for OpenGL 3.3/ES2 only and
# leave the software renderer's blending as it is (docs/RLGL.md), so they
# are not called here. The example draws the masks in its update, before
# BeginDrawing; here the draw does that first (the same pixels), and a new
# light's render texture is loaded there. DrawCircleGradient's and
# DrawCircle's sinf/cosf follow the libm profile (docs/SINCOSF.md). raylib
# seeds GetRandomValue from time(NULL) in InitWindow; here the seed is a
# setup argument (docs/DRIVER.md).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# A ShadowGeometry: the four vertices of a triangle fan.
type Quad is Data:
  Quad{a: M.Vector2, b: M.Vector2, c: M.Vector2, d: M.Vector2}

# A LightInfo without its mask: redraw is UpdateLight's (or SetupLight's) request to draw the mask this frame.
type Glow is Data:
  Glow{position: M.Vector2, radius: F32, dirty: Bool, valid: Bool, redraw: Bool, shadows: +List<Quad>}

# The lights in slot order, the boxes, showLines; merge: dirtyLights; ok: no refusal so far.
type Scene is Data:
  Scene{glows: +List<Glow>, boxes: +List<J.Rectangle>, show: Bool, merge: Bool, ok: Bool}

# backgroundTexture, lightMask and the lights' masks (one per glow, after the draw).
type State is Type:
  State{background: Maybe<J.Texture>, global: Maybe<J.RenderTexture>, masks: List<J.RenderTexture>, scene: Scene}

# The masks already visited (reversed) while the frame is drawn; ok: every texture mode ended.
type Pass is Type:
  Pass{frame: J.Frame, done: List<J.RenderTexture>, ok: Bool}

# ComputeShadowVolumeForEdge: the edge and its two ends projected away from the light by twice its radius.
def edge(+position: M.Vector2, +radius: F32, +sp: M.Vector2, +ep: M.Vector2) -> Quad:
  Quad{sp, ep, M.Vector2.add(ep, M.Vector2.scale(M.Vector2.normalize(M.Vector2.subtract(ep, position)), (radius * 2.0 : F32))),
    M.Vector2.add(sp, M.Vector2.scale(M.Vector2.normalize(M.Vector2.subtract(sp, position)), (radius * 2.0 : F32)))}

def cast(+on: Bool, +quad: Quad, +shadows: +List<Quad>) -> +List<Quad>:
  Bool.pick(+List<Quad>, on, List.append(&2, Quad, shadows, Con{quad, Nil{}}), shadows)

# A box inside the light's bounds: the edges on the light's side (top, right, bottom, left, at most MAX_SHADOWS volumes),
# then the box itself.
def shadowed(+position: M.Vector2, +radius: F32, box: J.Rectangle, +shadows: +List<Quad>) -> +List<Quad>:
  M.Vector2{+px, +py} = position
  J.Rectangle{+x, +y, +w, +h} = box
  +right = (x + w : F32)
  +bottom = (y + h : F32)
  +left = (right - w : F32)
  +top = (bottom - h : F32)
  +s1 = cast((py > y : F32) && (U32.from_nat(List.length(&2, Quad, shadows)) < 60 : U32), edge(position, radius, M.Vector2{x, y}, M.Vector2{right, y}), shadows)
  +s2 = cast((px < right : F32) && (U32.from_nat(List.length(&2, Quad, s1)) < 60 : U32), edge(position, radius, M.Vector2{right, y}, M.Vector2{right, bottom}), s1)
  +s3 = cast((py < bottom : F32) && (U32.from_nat(List.length(&2, Quad, s2)) < 60 : U32), edge(position, radius, M.Vector2{right, bottom}, M.Vector2{left, bottom}), s2)
  +s4 = cast((px > left : F32) && (U32.from_nat(List.length(&2, Quad, s3)) < 60 : U32), edge(position, radius, M.Vector2{left, bottom}, M.Vector2{left, top}), s3)
  List.append(&2, Quad, s4, Con{Quad{M.Vector2{x, y}, M.Vector2{x, bottom}, M.Vector2{right, bottom}, M.Vector2{right, y}}, Nil{}})

# lights[slot].bounds: a square of the radius around the position.
def bounds(+position: M.Vector2, +radius: F32) -> J.Rectangle:
  M.Vector2{+x, +y} = position
  J.Rectangle{(x - radius : F32), (y - radius : F32), (radius * 2.0 : F32), (radius * 2.0 : F32)}

# The shadow volumes so far, and whether the light is still valid (inside no box; the scan stops at the first box it is in).
type Lit is Data:
  Lit{shadows: +List<Quad>, valid: Bool}

def lit.box(+position: M.Vector2, +radius: F32, +box: J.Rectangle, lit: Lit) -> Lit:
  Lit{+shadows, +valid} = lit
  +inside = J.Collision.point_rec(position, box)
  +near = J.Collision.recs(bounds(position, radius), box)
  Lit{Bool.pick(+List<Quad>, valid && Bool.not(inside) && near, shadowed(position, radius, box, shadows), shadows), valid && Bool.not(inside)}

def lit(boxes: +List<J.Rectangle>, +position: M.Vector2, +radius: F32, +state: Lit) -> Lit:
  match boxes:
    case Nil{}: state
    case Con{+box, rest}: lit(rest, position, radius, lit.box(position, radius, box, state))

def glow.lit(+position: M.Vector2, +radius: F32, lit: Lit) -> Glow:
  Lit{+shadows, +valid} = lit
  Glow{position, radius, False{}, valid, valid, shadows}

# UpdateLight: a dirty light recomputes its shadow volumes; it is valid, and its mask is drawn again, unless it is inside a box.
def glow.updated(+boxes: +List<J.Rectangle>, glow: Glow) -> Glow:
  Glow{+position, +radius, +dirty, +valid, +redraw, +shadows} = glow
  Bool.pick(Glow, dirty, glow.lit(position, radius, lit(boxes, position, radius, Lit{Nil{}, True{}})), Glow{position, radius, dirty, valid, redraw, shadows})

def glows.updated(glows: +List<Glow>, +boxes: +List<J.Rectangle>) -> +List<Glow>:
  match glows:
    case Nil{}: Nil{}
    case Con{+glow, rest}: Con{glow.updated(boxes, glow), glows.updated(rest, boxes)}

# MoveLight(0, mouse): the first light at the mouse, dirty.
def dragged(glows: +List<Glow>, +mouse: M.Vector2) -> +List<Glow>:
  match glows:
    case Nil{}: Nil{}
    case Con{Glow{_, +radius, _, +valid, +redraw, +shadows}, rest}: Con{Glow{mouse, radius, True{}, valid, redraw, shadows}, rest}

def calm(glow: Glow) -> Glow:
  Glow{+position, +radius, +dirty, +valid, _, +shadows} = glow
  Glow{position, radius, dirty, valid, False{}, shadows}

def calmed(glows: +List<Glow>) -> +List<Glow>:
  match glows:
    case Nil{}: Nil{}
    case Con{+glow, rest}: Con{calm(glow), calmed(rest)}

def redrawn(glows: +List<Glow>) -> Bool:
  match glows:
    case Nil{}: False{}
    case Con{Glow{_, _, _, _, +redraw, _}, rest}: redraw || redrawn(rest)

# The left button drags light 0; a right press adds a light of radius 200 at the mouse (below 16); F1 toggles the volumes;
# then every dirty light is updated, and the light mask is merged again when one was.
def update.scene(+core: J.Core, scene: Scene) -> Scene:
  Scene{+glows, +boxes, +show, _, +ok} = scene
  +mouse = J.Input.get_mouse_position(core)
  +moved = Bool.pick(+List<Glow>, J.Input.is_mouse_button_down(core, J.MouseButton.MOUSE_BUTTON_LEFT()), dragged(calmed(glows), mouse), calmed(glows))
  +added = Bool.pick(+List<Glow>, J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_RIGHT()) && (U32.from_nat(List.length(&2, Glow, moved)) < 16 : U32),
    List.append(&2, Glow, moved, Con{Glow{mouse, 200.0, True{}, False{}, False{}, Nil{}}, Nil{}}), moved)
  +lights = glows.updated(added, boxes)
  Scene{lights, boxes, Bool.pick(Bool, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_F1()), Bool.not(show), show), redrawn(lights), ok}

def update(+core: J.Core, state: State) -> J.Core & State:
  State{background, global, masks, +scene} = state
  (core, State{background, global, masks, update.scene(core, scene)})

def fans(quads: +List<Quad>, +color: U32, frame: J.Frame) -> J.Frame:
  match quads:
    case Nil{}: frame
    case Con{Quad{+a, +b, +c, +d}, rest}: fans(rest, color, J.Draw.triangle_fan(frame, [a, b, c, d], color))

# if (lights[slot].valid) DrawCircleGradient(position, outerRadius, ColorAlpha(WHITE, 0), WHITE).
def halo(valid: Bool, +libm: M.Libm, +position: M.Vector2, +radius: F32, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: frame
    case True{}: J.Draw.circle_gradient_for(libm, frame, position, radius, J.Color.with_alpha(J.Color.WHITE(), 0.0), J.Color.WHITE())

def pass.ended(done: List<J.RenderTexture>, +ok: Bool, r: J.Frame & Maybe<J.RenderTexture>) -> Pass:
  (frame, mask) = r
  match mask:
    case None{}: Pass{frame, done, False{}}
    case Some{m}: Pass{frame, Con{m, done}, ok}

# DrawLightMask: the mask cleared to WHITE, the light's gradient when it is valid, then the shadow volumes in WHITE.
def mask.drawn(+libm: M.Libm, glow: Glow, mask: J.RenderTexture, frame: J.Frame, done: List<J.RenderTexture>, +ok: Bool) -> Pass:
  Glow{+position, +radius, _, +valid, _, +shadows} = glow
  pass.ended(done, ok, J.Frame.end_texture_mode(fans(shadows, J.Color.WHITE(), halo(valid, libm, position, radius, J.Frame.clear_background(J.Frame.begin_texture_mode(frame, mask), J.Color.WHITE())))))

def mask.kept(redraw: Bool, +libm: M.Libm, +glow: Glow, mask: J.RenderTexture, frame: J.Frame, done: List<J.RenderTexture>, +ok: Bool) -> Pass:
  match redraw:
    case False{}: Pass{frame, Con{mask, done}, ok}
    case True{}: mask.drawn(libm, glow, mask, frame, done, ok)

def wanted(glow: Glow) -> Bool:
  Glow{_, _, _, _, +redraw, _} = glow
  redraw

def mask.step(+libm: M.Libm, +glow: Glow, mask: J.RenderTexture, pass: Pass) -> Pass:
  Pass{frame, done, +ok} = pass
  mask.kept(wanted(glow), libm, glow, mask, frame, done, ok)

def mask.loaded(+libm: M.Libm, +glow: Glow, done: List<J.RenderTexture>, +ok: Bool, r: J.Frame & Maybe<J.RenderTexture>) -> Pass:
  (frame, mask) = r
  match mask:
    case None{}: Pass{frame, done, False{}}
    case Some{m}: mask.drawn(libm, glow, m, frame, done, ok)

# SetupLight's LoadRenderTexture(GetScreenWidth(), GetScreenHeight()) and first DrawLightMask, for a light without a mask yet.
def mask.new(+libm: M.Libm, +glow: Glow, pass: Pass) -> Pass:
  Pass{frame, done, +ok} = pass
  mask.loaded(libm, glow, done, ok, J.RenderTexture.load(frame, 800, 450))

def masks.drawn(glows: +List<Glow>, masks: List<J.RenderTexture>, +libm: M.Libm, pass: Pass) -> Pass:
  match glows masks:
    case Nil{} _: pass
    case Con{+glow, rest} Con{mask, others}: masks.drawn(rest, others, libm, mask.step(libm, glow, mask, pass))
    case Con{+glow, rest} Nil{}: masks.drawn(rest, Nil{}, libm, mask.new(libm, glow, pass))

def merged.kept(+id: U32, +depth: U32, done: List<J.RenderTexture>, +ok: Bool, r: J.Frame & J.Texture) -> Pass:
  (frame, texture) = r
  Pass{frame, Con{J.RenderTexture{id, texture, depth}, done}, ok}

# DrawTextureRec(lights[i].mask.texture, (0, 0, width, -height), Vector2Zero(), WHITE).
def merged.one(mask: J.RenderTexture, pass: Pass) -> Pass:
  J.RenderTexture{+id, texture, +depth} = mask
  Pass{frame, done, +ok} = pass
  merged.kept(id, depth, done, ok, J.Draw.texture_rec(frame, texture, J.Rectangle{0.0, 0.0, 800.0, F32.neg(450.0)}, M.Vector2.zero(), J.Color.WHITE()))

def merged.all(masks: List<J.RenderTexture>, pass: Pass) -> Pass:
  match masks:
    case Nil{}: pass
    case Con{mask, rest}: merged.all(rest, merged.one(mask, pass))

# for (i < MAX_LIGHTS) if (lights[i].active) DrawCircle((int)position.x, (int)position.y, 10, (i == 0)? YELLOW : WHITE).
def bulb(+libm: M.Libm, glow: Glow, +color: U32, frame: J.Frame) -> J.Frame:
  Glow{+position, _, _, _, _, _} = glow
  M.Vector2{+x, +y} = position
  J.Draw.circle_for(libm, frame, F32.trunc(x), F32.trunc(y), 10.0, color)

def bulbs(glows: +List<Glow>, +libm: M.Libm, +color: U32, frame: J.Frame) -> J.Frame:
  match glows:
    case Nil{}: frame
    case Con{+glow, rest}: bulbs(rest, libm, J.Color.WHITE(), bulb(libm, glow, color, frame))

# if (CheckCollisionRecs(boxes[b], lights[0].bounds)) DrawRectangleRec(boxes[b], PURPLE); the box's outline in DARKBLUE.
def box.lit(lit: Bool, +box: J.Rectangle, frame: J.Frame) -> J.Frame:
  match lit:
    case False{}: frame
    case True{}: J.Draw.rectangle_rec(frame, box, J.Color.PURPLE())

# DrawRectangleLines((int)x, (int)y, (int)width, (int)height, DARKBLUE).
def outlined(box: J.Rectangle, frame: J.Frame) -> J.Frame:
  J.Rectangle{+x, +y, +w, +h} = box
  J.Draw.rectangle_lines(frame, F32.trunc(x), F32.trunc(y), F32.trunc(w), F32.trunc(h), J.Color.DARKBLUE())

def outlines(boxes: +List<J.Rectangle>, +area: J.Rectangle, frame: J.Frame) -> J.Frame:
  match boxes:
    case Nil{}: frame
    case Con{+box, rest}: outlines(rest, area, outlined(box, box.lit(J.Collision.recs(box, area), box, frame)))

def first(glows: +List<Glow>) -> Glow:
  match glows:
    case Nil{}: Glow{M.Vector2.zero(), 0.0, False{}, False{}, False{}, Nil{}}
    case Con{+glow, _}: glow

def debug.volumes(glow: Glow, +boxes: +List<J.Rectangle>, frame: J.Frame) -> J.Frame:
  Glow{+position, +radius, _, _, _, +shadows} = glow
  outlines(boxes, bounds(position, radius), fans(shadows, J.Color.DARKPURPLE(), frame))

# showLines: light 0's shadow volumes, the boxes, and the hint to hide them; else the hint to show them.
def debug(shown: Bool, +glow: Glow, +boxes: +List<J.Rectangle>, frame: J.Frame) -> J.Frame:
  match shown:
    case False{}: J.Draw.text(frame, "(F1) Show Shadow Volumes", 10.0, 50.0, 10.0, J.Color.GREEN())
    case True{}: J.Draw.text(debug.volumes(glow, boxes, frame), "(F1) Hide Shadow Volumes", 10.0, 50.0, 10.0, J.Color.GREEN())

def draw.fps.at(state: State, frame: J.Frame, pair: J.Core & U32) -> J.Core & (State & J.Frame):
  (core, +fps) = pair
  f1 = J.Draw.text(J.Draw.fps(frame, (800.0 - 80.0 : F32), 10.0, fps), "Drag to move light #1", 10.0, 10.0, 10.0, J.Color.DARKGREEN())
  (core, (state, J.Draw.text(f1, "Right click to add new light", 10.0, 30.0, 10.0, J.Color.DARKGREEN())))

def draw.fps.done(state: State, frame: J.Frame, result: Maybe<(J.Core & U32)>, +core: J.Core) -> J.Core & (State & J.Frame):
  match result:
    case None{}: (core, (state, J.Frame.refuse(frame)))
    case Some{pair}: draw.fps.at(state, frame, pair)

def checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

# The light mask over the tiles (ColorAlpha(WHITE, showLines? 0.75f : 1.0f)), the lights, the volumes and the texts.
def draw.lit(+libm: M.Libm, +core: J.Core, +scene: Scene, masks: List<J.RenderTexture>, +fine: Bool, background: J.Texture, +id: U32, +depth: U32, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  Scene{+glows, +boxes, +show, +merge, +ok} = scene
  (frame, texture) = r
  f1 = debug(show, first(glows), boxes, bulbs(glows, libm, J.Color.YELLOW(), checked(fine, frame)))
  draw.fps.done(State{Some{background}, Some{J.RenderTexture{id, texture, depth}}, masks, Scene{glows, boxes, show, merge, ok && fine}}, f1, J.Core.get_fps(core, J.Core.get_time(core)), core)

def draw.tiles(+libm: M.Libm, +core: J.Core, +scene: Scene, masks: List<J.RenderTexture>, +fine: Bool, global: J.RenderTexture, r: J.Frame & J.Texture) -> J.Core & (State & J.Frame):
  Scene{_, _, +show, _, _} = scene
  J.RenderTexture{+id, texture, +depth} = global
  (frame, background) = r
  draw.lit(libm, core, scene, masks, fine, background, id, depth,
    J.Draw.texture_rec(frame, texture, J.Rectangle{0.0, 0.0, 800.0, F32.neg(450.0)}, M.Vector2.zero(), J.Color.with_alpha(J.Color.WHITE(), Bool.pick(F32, show, 0.75, 1.0))))

# ClearBackground(BLACK); DrawTextureRec(backgroundTexture, (0, 0, width, height), Vector2Zero(), WHITE).
def draw.screen(+libm: M.Libm, +core: J.Core, +scene: Scene, masks: List<J.RenderTexture>, +fine: Bool, background: J.Texture, frame: J.Frame, global: Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  match global:
    case None{}: (core, (State{Some{background}, None{}, masks, scene}, J.Frame.refuse(frame)))
    case Some{g}: draw.tiles(libm, core, scene, masks, fine, g,
      J.Draw.texture_rec(J.Frame.clear_background(frame, J.Color.BLACK()), background, J.Rectangle{0.0, 0.0, 800.0, 450.0}, M.Vector2.zero(), J.Color.WHITE()))

def draw.merged.done(+libm: M.Libm, +core: J.Core, +scene: Scene, background: J.Texture, masks: List<J.RenderTexture>, +fine: Bool, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  (frame, global) = r
  draw.screen(libm, core, scene, masks, fine, background, frame, global)

def draw.merged.pass(+libm: M.Libm, +core: J.Core, +scene: Scene, background: J.Texture, pass: Pass) -> J.Core & (State & J.Frame):
  Pass{frame, done, +ok} = pass
  draw.merged.done(libm, core, scene, background, List.reverse(&1, J.RenderTexture, done), ok, J.Frame.end_texture_mode(frame))

# if (dirtyLights): the light mask cleared to BLACK and every light's mask drawn into it.
def draw.merge(merge: Bool, +libm: M.Libm, +core: J.Core, +scene: Scene, background: J.Texture, global: J.RenderTexture, masks: List<J.RenderTexture>, +fine: Bool, frame: J.Frame) -> J.Core & (State & J.Frame):
  match merge:
    case False{}: draw.screen(libm, core, scene, masks, fine, background, frame, Some{global})
    case True{}: draw.merged.pass(libm, core, scene, background, merged.all(masks, Pass{J.Frame.clear_background(J.Frame.begin_texture_mode(frame, global), J.Color.BLACK()), Nil{}, fine}))

def draw.masked(+libm: M.Libm, +core: J.Core, +scene: Scene, background: J.Texture, global: J.RenderTexture, pass: Pass) -> J.Core & (State & J.Frame):
  Scene{_, _, _, +merge, _} = scene
  Pass{frame, done, +ok} = pass
  draw.merge(merge, libm, core, scene, background, global, List.reverse(&1, J.RenderTexture, done), ok, frame)

def draw.loaded(+libm: M.Libm, +core: J.Core, +scene: Scene, masks: List<J.RenderTexture>, frame: J.Frame, background: Maybe<J.Texture>, global: Maybe<J.RenderTexture>) -> J.Core & (State & J.Frame):
  Scene{+glows, _, _, _, _} = scene
  match background global:
    case Some{b} Some{g}: draw.masked(libm, core, scene, b, g, masks.drawn(glows, masks, libm, Pass{frame, Nil{}, True{}}))
    case Some{b} None{}: (core, (State{Some{b}, None{}, masks, scene}, J.Frame.refuse(frame)))
    case None{} g: (core, (State{None{}, g, masks, scene}, J.Frame.refuse(frame)))

def fine(scene: Scene) -> Bool:
  Scene{_, _, _, _, +ok} = scene
  ok

# The masks of the lights that asked for it (a new light's is loaded first), the merge, then the screen.
def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{background, global, masks, +scene} = state
  draw.loaded(libm, core, scene, masks, checked(fine(scene), frame), background, global)

# The main loop's body; libm is the profile of DrawCircleGradient's and DrawCircle's sinf/cosf.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

# A random box: (GetRandomValue(0, width), GetRandomValue(0, height), GetRandomValue(10, 100), GetRandomValue(10, 100)).
type Boxes is Type:
  Boxes{rng: J.Random.State, boxes: +List<J.Rectangle>}

def box.h(+boxes: +List<J.Rectangle>, +x: F32, +y: F32, +w: F32, r: J.Random.State & F32) -> Boxes:
  (rng, +h) = r
  Boxes{rng, List.append(&2, J.Rectangle, boxes, Con{J.Rectangle{x, y, w, h}, Nil{}})}

def box.w(+boxes: +List<J.Rectangle>, +x: F32, +y: F32, r: J.Random.State & F32) -> Boxes:
  (rng, +w) = r
  box.h(boxes, x, y, w, J.Random.value(rng, 10.0, 100.0))

def box.y(+boxes: +List<J.Rectangle>, +x: F32, r: J.Random.State & F32) -> Boxes:
  (rng, +y) = r
  box.w(boxes, x, y, J.Random.value(rng, 10.0, 100.0))

def box.x(+boxes: +List<J.Rectangle>, r: J.Random.State & F32) -> Boxes:
  (rng, +x) = r
  box.y(boxes, x, J.Random.value(rng, 0.0, 450.0))

def box.random(state: Boxes) -> Boxes:
  Boxes{rng, +boxes} = state
  box.x(boxes, J.Random.value(rng, 0.0, 800.0))

def boxes.random(n: Nat, state: Boxes) -> Boxes:
  match n:
    case 0n: state
    case 1n+p: boxes.random(p, box.random(state))

# SetupBoxes: five fixed boxes and fifteen random ones.
def boxes(+seed: U32) -> Boxes:
  boxes.random(15n, Boxes{J.Random.seed(seed), [J.Rectangle{150.0, 80.0, 40.0, 40.0}, J.Rectangle{1200.0, 700.0, 40.0, 40.0}, J.Rectangle{200.0, 600.0, 40.0, 40.0},
    J.Rectangle{1000.0, 50.0, 40.0, 40.0}, J.Rectangle{500.0, 350.0, 40.0, 40.0}]})

def setup.scene(set: Boxes) -> Scene:
  Boxes{_, +list} = set
  Scene{[Glow{M.Vector2{600.0, 400.0}, 300.0, True{}, False{}, True{}, Nil{}}], list, False{}, False{}, True{}}

def setup.global(+seed: U32, +core: J.Core, background: Maybe<J.Texture>, r: J.Frame & Maybe<J.RenderTexture>) -> J.Core & (J.Frame & State):
  (frame, global) = r
  (J.Core.set_target_fps(core, 60), (frame, State{background, global, Nil{}, setup.scene(boxes(seed))}))

def setup.background(+seed: U32, +core: J.Core, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, background) = r
  setup.global(seed, core, background, J.RenderTexture.load(frame, 800, 450))

def setup.image(+seed: U32, +core: J.Core, frame: J.Frame, image: Maybe<J.Surface>) -> J.Core & (J.Frame & State):
  match image:
    case None{}: setup.background(seed, core, (frame, None{}))
    case Some{i}: setup.background(seed, core, J.Texture.load_from_image(frame, i))

# After InitWindow(800, 450) and SetRandomSeed(seed): the boxes, the checkerboard texture (GenImageChecked(64, 64, 32, 32,
# DARKBROWN, DARKGRAY)), the light mask and the first light at (600, 400) with radius 300 (its mask is loaded and drawn by
# the first draw), SetTargetFPS(60).
def setup(+seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  setup.image(seed, core, frame, J.Surface.create_checked(64, 64, 32, 32, J.Color.DARKBROWN(), J.Color.DARKGRAY()))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [shapes] example - top down lights", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
