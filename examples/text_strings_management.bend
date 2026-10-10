# raylib [text] example - strings management, ported to Jonlib.
# Adapted from raylib 6.0 examples/text/text_strings_management.c (zlib/libpng,
# Copyright (c) 2025 David Buzatto (@davidbuzatto)); see LICENSES/raylib.txt.
#
# Text particles that bounce around the screen: grabbed and thrown with the
# left button, sliced in halves (TextSubtext) with the right one or
# shattered into characters with LEFT SHIFT, shaken with the middle one,
# glued (two texts joined) while LEFT CTRL is held, reset by 1 to 6 through
# TextToUpper, TextToLower, TextToPascal, TextToSnake and TextToCamel, and
# sliced at a typed character (TextSplit) while there is only one.
#
# The example keeps the grabbed particle as a pointer into its array, which
# stays on the same slot when the array is repacked; here it is that slot's
# index. Refused, with every later frame: gluing with no grabbed pointer
# (a NULL read in C) or with the pointer on a slot past the particles (the
# example reads a stale copy there, which is not kept here), and a particle
# whose position does not fit DrawText's int conversion (a frame time of 0
# while dragging, or TextSplit's empty token, divide by 0). raylib seeds
# GetRandomValue from time(NULL) in InitWindow; here the seed is a setup
# argument (docs/DRIVER.md). See docs/TEXT.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# A TextParticle: padding and borderWidth are 5, friction 0.99 and elasticity 0.9 for all of them.
type Particle is Data:
  Particle{text: String, x: F32, y: F32, width: F32, height: F32, vel: M.Vector2, ppos: M.Vector2, color: U32, grabbed: Bool}

# textParticles (particleCount of them), grabbedTextParticle (held: not NULL; its slot) and pressOffset; ok: no refusal so far.
type Table is Data:
  Table{particles: +List<Particle>, held: Bool, slot: U32, offset: M.Vector2, ok: Bool}

type State is Type:
  State{rng: J.Random.State, table: Table}

type Hit is Data:
  Hit{found: Bool, index: U32}

type Shake is Type:
  Shake{rng: J.Random.State, done: +List<Particle>}

def blank() -> Particle:
  Particle{"", 0.0, 0.0, 0.0, 0.0, M.Vector2.zero(), M.Vector2.zero(), 0, False{}}

def first(particles: +List<Particle>) -> Particle:
  match particles:
    case Nil{}: blank()
    case Con{+particle, _}: particle

def at(+particles: +List<Particle>, +index: U32) -> Particle:
  first(List.drop(&2, Particle, particles, U32.to_nat(index)))

def size(+particles: +List<Particle>) -> U32:
  U32.from_nat(List.length(&2, Particle, particles))

def put(particles: +List<Particle>, index: Nat, +particle: Particle) -> +List<Particle>:
  match particles index:
    case Nil{} _: Nil{}
    case Con{_, rest} 0n: Con{particle, rest}
    case Con{+head, rest} 1n+n: Con{head, put(rest, n, particle)}

def removed(particles: +List<Particle>, index: Nat) -> +List<Particle>:
  match particles index:
    case Nil{} _: Nil{}
    case Con{_, rest} 0n: rest
    case Con{+head, rest} 1n+n: Con{head, removed(rest, n)}

def rect(particle: Particle) -> J.Rectangle:
  Particle{_, +x, +y, +width, +height, _, _, _, _} = particle
  J.Rectangle{x, y, width, height}

def gripping(particle: Particle) -> Bool:
  Particle{_, _, _, _, _, _, _, _, +grabbed} = particle
  grabbed

def gripped(particle: Particle, +grabbed: Bool) -> Particle:
  Particle{+text, +x, +y, +width, +height, +vel, +ppos, +color, _} = particle
  Particle{text, x, y, width, height, vel, ppos, color, grabbed}

def listed(table: Table) -> +List<Particle>:
  Table{+particles, _, _, _, _} = table
  particles

def relisted(table: Table, +particles: +List<Particle>) -> Table:
  Table{_, +held, +slot, +offset, +ok} = table
  Table{particles, held, slot, offset, ok}

def failed(table: Table) -> Table:
  Table{+particles, +held, +slot, +offset, _} = table
  Table{particles, held, slot, offset, False{}}

def refused(state: State) -> State:
  State{rng, +table} = state
  State{rng, failed(table)}

# RealocateTextParticles(tps, index, &particleCount).
def unlisted(+index: U32, state: State) -> State:
  State{rng, +table} = state
  State{rng, relisted(table, removed(listed(table), U32.to_nat(index)))}

def made.sized(rng: J.Random.State, +table: Table, +text: String, +x: F32, +y: F32, +color: U32, +grabbed: Bool, +vx: F32, +vy: F32, width: Maybe<U32>) -> State:
  match width:
    case None{}: State{rng, failed(table)}
    case Some{+w}: State{rng, relisted(table, List.append(&2, Particle, listed(table),
      Con{Particle{text, x, y, (U32.to_f32(w) + 5.0 * 2.0 : F32), (30.0 + 5.0 * 2.0 : F32), M.Vector2{vx, vy}, M.Vector2.zero(), color, grabbed}, Nil{}}))}

def made.vy(+table: Table, +text: String, +x: F32, +y: F32, +color: U32, +grabbed: Bool, +vx: F32, r: J.Random.State & F32) -> State:
  (rng, +vy) = r
  made.sized(rng, table, text, x, y, color, grabbed, vx, vy, J.Font.measure_text(text, 30.0))

def made.vx(+table: Table, +text: String, +x: F32, +y: F32, +color: U32, +grabbed: Bool, r: J.Random.State & F32) -> State:
  (rng, +vx) = r
  made.vy(table, text, x, y, color, grabbed, vx, J.Random.value(rng, F32.neg(200.0), 200.0))

# tps[particleCount++] = CreateTextParticle(text, x, y, color): the velocity from GetRandomValue(-200, 200) twice,
# the width MeasureText(text, FONT_SIZE) + 2*padding, the height FONT_SIZE + 2*padding.
def made(state: State, +text: String, +x: F32, +y: F32, +color: U32, +grabbed: Bool) -> State:
  State{rng, +table} = state
  made.vx(table, text, x, y, color, grabbed, J.Random.value(rng, F32.neg(200.0), 200.0))

def tinted.b(+table: Table, +text: String, +x: F32, +y: F32, +red: F32, +green: F32, r: J.Random.State & F32) -> State:
  (rng, +blue) = r
  made(State{rng, table}, text, x, y, J.Color.rgba(F32.to_u32(red), F32.to_u32(green), F32.to_u32(blue), 255), False{})

def tinted.g(+table: Table, +text: String, +x: F32, +y: F32, +red: F32, r: J.Random.State & F32) -> State:
  (rng, +green) = r
  tinted.b(table, text, x, y, red, green, J.Random.value(rng, 0.0, 255.0))

def tinted.r(+table: Table, +text: String, +x: F32, +y: F32, r: J.Random.State & F32) -> State:
  (rng, +red) = r
  tinted.g(table, text, x, y, red, J.Random.value(rng, 0.0, 255.0))

# A new particle of color (GetRandomValue(0, 255), GetRandomValue(0, 255), GetRandomValue(0, 255), 255).
def tinted(state: State, +text: String, +x: F32, +y: F32) -> State:
  State{rng, +table} = state
  tinted.r(table, text, x, y, J.Random.value(rng, 0.0, 255.0))

# The last particle under the mouse (the example searches from the end).
def hit(particles: +List<Particle>, +mouse: M.Vector2, +i: U32, +found: Hit) -> Hit:
  match particles:
    case Nil{}: found
    case Con{+particle, rest}: hit(rest, mouse, (i + 1 : U32), Bool.pick(Hit, J.Collision.point_rec(mouse, rect(particle)), Hit{True{}, i}, found))

def away(mouse: M.Vector2, particle: Particle) -> M.Vector2:
  M.Vector2{+mx, +my} = mouse
  Particle{_, +x, +y, _, _, _, _, _, _} = particle
  M.Vector2{(mx - x : F32), (my - y : F32)}

# The left button pressed: pressOffset from each particle searched (the hit one, else the first), the hit one grabbed.
def grab.at(+mouse: M.Vector2, table: Table, hit: Hit) -> Table:
  Table{+particles, +held, +slot, +offset, +ok} = table
  Hit{+found, +index} = hit
  +target = at(particles, Bool.pick(U32, found, index, 0))
  Table{Bool.pick(+List<Particle>, found, put(particles, U32.to_nat(index), gripped(target, True{})), particles), held || found, Bool.pick(U32, found, index, slot),
    Bool.pick(M.Vector2, U32.is_eq(size(particles), 0), offset, away(mouse, target)), ok}

def grab(pressed: Bool, +mouse: M.Vector2, +table: Table) -> Table:
  match pressed:
    case False{}: table
    case True{}: grab.at(mouse, table, hit(listed(table), mouse, 0, Hit{False{}, 0}))

def drop.at(table: Table) -> Table:
  Table{+particles, +held, +slot, +offset, +ok} = table
  Table{Bool.pick(+List<Particle>, held && (slot < size(particles) : U32), put(particles, U32.to_nat(slot), gripped(at(particles, slot), False{})), particles), False{}, slot, offset, ok}

# The left button released: the pointed slot is no longer grabbed, the pointer NULL.
def drop(released: Bool, +table: Table) -> Table:
  match released:
    case False{}: table
    case True{}: drop.at(table)

def piece.text(text: Maybe<String>, +x: F32, +y: F32, state: State) -> State:
  match text:
    case None{}: refused(state)
    case Some{+t}: tinted(state, t, x, y)

def piece(live: Bool, +text: String, +i: U32, +step: U32, +x: F32, +y: F32, state: State) -> State:
  match live:
    case False{}: state
    case True{}: piece.text(J.Text.subtext(text, i, step), x, y, state)

# for (i = 0; i < length; i += sliceLength): a particle of TextSubtext(text, i, sliceLength) at rect.x + i*rect.width/length.
def slices(fuel: Nat, +i: U32, +length: U32, +step: U32, +text: String, +x: F32, +y: F32, +width: F32, state: State) -> State:
  match fuel:
    case 0n: state
    case 1n+p: slices(p, (i + step : U32), length, step, text, x, y, width, piece((i < length : U32), text, i, step, (x + U32.to_f32(i) * width / U32.to_f32(length) : F32), y, state))

def sliced.go(sliceable: Bool, +index: U32, +length: U32, +step: U32, +text: String, +x: F32, +y: F32, +width: F32, state: State) -> State:
  match sliceable:
    case False{}: state
    case True{}: unlisted(index, slices(U32.to_nat(length), 0, length, step, text, x, y, width, state))

# SliceTextParticle(tp, index, sliceLength): a text of 2 characters or more, with room in the array (100), is replaced by its slices.
def sliced(+shatter: Bool, +index: U32, +population: U32, particle: Particle, state: State) -> State:
  Particle{+text, +x, +y, +width, _, _, _, _, _} = particle
  +length = J.Text.length(text)
  sliced.go((length > 1 : U32) && ((population + length) < 100 : U32), index, length, Bool.pick(U32, shatter, 1, (length / 2 : U32)), text, x, y, width, state)

def cut.found(found: Bool, +shatter: Bool, +index: U32, +table: Table, rng: J.Random.State) -> State:
  match found:
    case False{}: State{rng, table}
    case True{}: sliced(shatter, index, size(listed(table)), at(listed(table), index), State{rng, table})

def cut.hit(+shatter: Bool, +table: Table, hit: Hit, rng: J.Random.State) -> State:
  Hit{+found, +index} = hit
  cut.found(found, shatter, index, table, rng)

def cut.state(+shatter: Bool, +mouse: M.Vector2, state: State) -> State:
  State{rng, +table} = state
  cut.hit(shatter, table, hit(listed(table), mouse, 0, Hit{False{}, 0}), rng)

# The right button pressed: the last particle under the mouse shattered (LEFT SHIFT) or sliced in halves.
def cut(pressed: Bool, +shatter: Bool, +mouse: M.Vector2, state: State) -> State:
  match pressed:
    case False{}: state
    case True{}: cut.state(shatter, mouse, state)

def sped(particle: Particle, +vx: F32, +vy: F32) -> Particle:
  Particle{+text, +x, +y, +width, +height, _, +ppos, +color, +grabbed} = particle
  Particle{text, x, y, width, height, M.Vector2{vx, vy}, ppos, color, grabbed}

def shake.vy(+done: +List<Particle>, +particle: Particle, +vx: F32, r: J.Random.State & F32) -> Shake:
  (rng, +vy) = r
  Shake{rng, Con{sped(particle, vx, vy), done}}

def shake.vx(+done: +List<Particle>, +particle: Particle, r: J.Random.State & F32) -> Shake:
  (rng, +vx) = r
  shake.vy(done, particle, vx, J.Random.value(rng, F32.neg(2000.0), 2000.0))

def shake.one(still: Bool, +particle: Particle, +done: +List<Particle>, rng: J.Random.State) -> Shake:
  match still:
    case True{}: Shake{rng, Con{particle, done}}
    case False{}: shake.vx(done, particle, J.Random.value(rng, F32.neg(2000.0), 2000.0))

def shake.step(+particle: Particle, shake: Shake) -> Shake:
  Shake{rng, +done} = shake
  shake.one(gripping(particle), particle, done, rng)

def shaken(particles: +List<Particle>, shake: Shake) -> Shake:
  match particles:
    case Nil{}: shake
    case Con{+particle, rest}: shaken(rest, shake.step(particle, shake))

def shook.done(+table: Table, shake: Shake) -> State:
  Shake{rng, +done} = shake
  State{rng, relisted(table, List.reverse(&2, Particle, done))}

def shook.state(state: State) -> State:
  State{rng, +table} = state
  shook.done(table, shaken(listed(table), Shake{rng, Nil{}}))

# The middle button pressed: every particle not grabbed takes a velocity of (GetRandomValue(-2000, 2000), GetRandomValue(-2000, 2000)).
def shook(pressed: Bool, state: State) -> State:
  match pressed:
    case False{}: state
    case True{}: shook.state(state)

# PrepareFirstTextParticle(text): tps[0] = CreateTextParticle(text, width/2, height/2, RAYWHITE); particleCount = 1.
def prepared(state: State, +text: String) -> State:
  State{rng, +table} = state
  made(State{rng, relisted(table, Nil{})}, text, (800.0 / 2.0 : F32), (450.0 / 2.0 : F32), J.Color.RAYWHITE(), False{})

def phrase(which: U32) -> Maybe<String>:
  match which:
    case 1: Some{"raylib => fun videogames programming!"}
    case 2: Some{J.Text.to_upper("raylib => fun videogames programming!")}
    case 3: Some{J.Text.to_lower("raylib => fun videogames programming!")}
    case 4: J.Text.to_pascal("raylib_fun_videogames_programming")
    case 5: J.Text.to_snake("RaylibFunVideogamesProgramming")
    case _: J.Text.to_camel("raylib_fun_videogames_programming")

def reset.text(text: Maybe<String>, state: State) -> State:
  match text:
    case None{}: refused(state)
    case Some{+t}: prepared(state, t)

# Keys 1 to 6: the first particle again, through the TextTo* functions.
def reset(pressed: Bool, +which: U32, state: State) -> State:
  match pressed:
    case False{}: state
    case True{}: reset.text(phrase(which), state)

# A particle for each token at rect.x + i*rect.width/TextLength(token).
def tokens.made(tokens: +List<String>, +i: U32, +x: F32, +y: F32, +width: F32, state: State) -> State:
  match tokens:
    case Nil{}: state
    case Con{+token, rest}: tokens.made(rest, (i + 1 : U32), x, y, width, tinted(state, token, (x + U32.to_f32(i) * width / U32.to_f32(J.Text.length(token)) : F32), y))

# A particle of the character for each one in the text.
def marks.made(n: Nat, +mark: String, +x: F32, +y: F32, state: State) -> State:
  match n:
    case 0n: state
    case 1n+p: marks.made(p, mark, x, y, tinted(state, mark, x, y))

def split.marks(mark: Maybe<String>, +tokens: +List<String>, +x: F32, +y: F32, +width: F32, state: State) -> State:
  match mark:
    case None{}: refused(state)
    case Some{+m}: unlisted(0, tokens.made(tokens, 0, x, y, width, marks.made(List.length(&2, String, List.drop(&2, String, tokens, 1n)), m, x, y, state)))

def split.many(many: Bool, +code: U32, +tokens: +List<String>, +x: F32, +y: F32, +width: F32, state: State) -> State:
  match many:
    case False{}: state
    case True{}: split.marks(J.Text.format("%c", [J.TextInt{code}]), tokens, x, y, width, state)

def split.tokens(+code: U32, +x: F32, +y: F32, +width: F32, tokens: Maybe<+List<String>>, state: State) -> State:
  match tokens:
    case None{}: refused(state)
    case Some{+list}: split.many((U32.from_nat(List.length(&2, String, list)) > 1 : U32), code, list, x, y, width, state)

# SliceTextParticleByChar(&tps[0], charPressed): with more than one token, the characters and the tokens replace the particle.
def split.particle(+code: U32, particle: Particle, state: State) -> State:
  Particle{+text, +x, +y, +width, _, _, _, _, _} = particle
  split.tokens(code, x, y, width, J.Text.split(text, Char.from_u32(code)), state)

def split.single(single: Bool, +code: U32, +particle: Particle, state: State) -> State:
  match single:
    case False{}: state
    case True{}: split.particle(code, particle, state)

# charPressed = (char)GetCharPressed(): from 'A' to 'z' with one particle only.
def split(+pressed: U32, state: State) -> State:
  State{rng, +table} = state
  +code = (pressed .&. 255 : U32)
  split.single((code >= 65 : U32) && (code <= 122 : U32) && U32.is_eq(size(listed(table)), 1), code, at(listed(table), 0), State{rng, table})

# Not grabbed: the move by the velocity, the bounce off the screen's sides (elasticity) and the friction.
def free(+dt: F32, particle: Particle) -> Particle:
  Particle{+text, +x, +y, +width, +height, +vel, +ppos, +color, +grabbed} = particle
  M.Vector2{+vx, +vy} = vel
  +x1 = (x + vx * dt : F32)
  +y1 = (y + vy * dt : F32)
  +right = ((x1 + width) >= 800.0 : F32)
  +left = Bool.not(right) && (x1 <= 0.0 : F32)
  +bottom = ((y1 + height) >= 450.0 : F32)
  +top = Bool.not(bottom) && (y1 <= 0.0 : F32)
  Particle{text, Bool.pick(F32, right, (800.0 - width : F32), Bool.pick(F32, left, 0.0, x1)), Bool.pick(F32, bottom, (450.0 - height : F32), Bool.pick(F32, top, 0.0, y1)), width, height,
    M.Vector2{(Bool.pick(F32, right || left, (F32.neg(vx) * 0.9 : F32), vx) * 0.99 : F32), (Bool.pick(F32, bottom || top, (F32.neg(vy) * 0.9 : F32), vy) * 0.99 : F32)}, ppos, color, grabbed}

# Grabbed: at the mouse less pressOffset, the velocity from the previous position.
def dragged(+dt: F32, mouse: M.Vector2, offset: M.Vector2, particle: Particle) -> Particle:
  M.Vector2{+mx, +my} = mouse
  M.Vector2{+ox, +oy} = offset
  Particle{+text, _, _, +width, +height, _, +ppos, +color, +grabbed} = particle
  M.Vector2{+px, +py} = ppos
  Particle{text, (mx - ox : F32), (my - oy : F32), width, height, M.Vector2{(((mx - ox) - px) / dt : F32), (((my - oy) - py) / dt : F32)}, M.Vector2{(mx - ox : F32), (my - oy : F32)}, color, grabbed}

# The two removed (the higher slot first), the pointer on the new last particle.
def glue.merged(+p1: U32, +p2: U32, state: State) -> State:
  State{rng, +table} = state
  Table{+particles, +held, _, +offset, +ok} = table
  +kept = removed(removed(particles, U32.to_nat(U32.max(p1, p2))), U32.to_nat(U32.min(p1, p2)))
  State{rng, Table{kept, held, (size(kept) - 1 : U32), offset, ok}}

# GlueTextParticles(grabbed, target): a grabbed particle of both texts (TextFormat("%s%s")) at the grabbed one's place.
def glue(+p1: U32, +p2: U32, grabbed: Particle, target: Particle, state: State) -> State:
  Particle{+text, +x, +y, _, _, _, _, _, _} = grabbed
  Particle{+other, _, _, _, _, _, _, _, _} = target
  glue.merged(p1, p2, made(state, text ++ other, x, y, J.Color.RAYWHITE(), True{}))

def stick.at(collide: Bool, +slot: U32, +j: U32, +grabbed: Particle, +target: Particle, state: State) -> State:
  match collide:
    case False{}: state
    case True{}: glue(slot, j, grabbed, target, state)

def stick.checked(bad: Bool, +collide: Bool, +slot: U32, +j: U32, +grabbed: Particle, +target: Particle, state: State) -> State:
  match bad:
    case True{}: refused(state)
    case False{}: stick.at(collide, slot, j, grabbed, target, state)

# if (&tps[j] != grabbedTextParticle && grabbedTextParticle->grabbed && CheckCollisionRecs(...)) the two are glued.
def stick.one(+j: U32, state: State) -> State:
  State{rng, +table} = state
  Table{+particles, +held, +slot, _, _} = table
  +live = (j < size(particles) : U32)
  +grabbed = at(particles, slot)
  +target = at(particles, j)
  stick.checked(live && Bool.not(held && (slot < size(particles) : U32)),
    live && Bool.not(U32.is_eq(j, slot)) && gripping(grabbed) && J.Collision.recs(rect(grabbed), rect(target)), slot, j, grabbed, target, State{rng, table})

def stuck(fuel: Nat, +j: U32, state: State) -> State:
  match fuel:
    case 0n: state
    case 1n+p: stuck(p, (j + 1 : U32), stick.one(j, state))

def stuck.all(state: State) -> State:
  State{rng, +table} = state
  stuck(List.length(&2, Particle, listed(table)), 0, State{rng, table})

# LEFT CTRL while a particle is dragged: the glue loop over every particle.
def moved.glue(ctrl: Bool, state: State) -> State:
  match ctrl:
    case False{}: state
    case True{}: stuck.all(state)

def pressed.offset(table: Table) -> M.Vector2:
  Table{_, _, _, +offset, _} = table
  offset

def replaced(+table: Table, +index: U32, +particle: Particle) -> Table:
  relisted(table, put(listed(table), U32.to_nat(index), particle))

def moved.kind(grip: Bool, +live: Bool, +i: U32, +dt: F32, +mouse: M.Vector2, +ctrl: Bool, +particle: Particle, +table: Table, rng: J.Random.State) -> State:
  match grip:
    case False{}: State{rng, Bool.pick(Table, live, replaced(table, i, free(dt, particle)), table)}
    case True{}: moved.glue(ctrl, State{rng, replaced(table, i, dragged(dt, mouse, pressed.offset(table), particle))})

# Particle i of the update loop (the array may shrink while it runs).
def moved.one(+i: U32, +dt: F32, +mouse: M.Vector2, +ctrl: Bool, state: State) -> State:
  State{rng, +table} = state
  moved.kind((i < size(listed(table)) : U32) && gripping(at(listed(table), i)), (i < size(listed(table)) : U32), i, dt, mouse, ctrl, at(listed(table), i), table, rng)

def moves(fuel: Nat, +i: U32, +dt: F32, +mouse: M.Vector2, +ctrl: Bool, state: State) -> State:
  match fuel:
    case 0n: state
    case 1n+p: moves(p, (i + 1 : U32), dt, mouse, ctrl, moved.one(i, dt, mouse, ctrl, state))

def moves.all(+core: J.Core, state: State) -> State:
  State{rng, +table} = state
  moves(List.length(&2, Particle, listed(table)), 0, J.Core.get_frame_time(core), J.Input.get_mouse_position(core), J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT_CONTROL()), State{rng, table})

def update.char(+inputs: J.Core, state: State, r: J.Core & U32) -> J.Core & State:
  (core, +pressed) = r
  (core, moves.all(inputs, split(pressed, state)))

def key(+core: J.Core, +code: U32) -> Bool:
  J.Input.is_key_pressed(core, code)

# The grab and the release, the slice or shatter, the shake, the resets, the slice by a typed character, then every particle.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{rng, +table} = state
  +mouse = J.Input.get_mouse_position(core)
  s1 = {State{rng, drop(J.Input.is_mouse_button_released(core, J.MouseButton.MOUSE_BUTTON_LEFT()), grab(J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_LEFT()), mouse, table))} : State}
  s2 = shook(J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_MIDDLE()),
    cut(J.Input.is_mouse_button_pressed(core, J.MouseButton.MOUSE_BUTTON_RIGHT()), J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT_SHIFT()), mouse, s1))
  s3 = reset(key(core, J.KeyboardKey.KEY_THREE()), 3, reset(key(core, J.KeyboardKey.KEY_TWO()), 2, reset(key(core, J.KeyboardKey.KEY_ONE()), 1, s2)))
  s4 = reset(key(core, J.KeyboardKey.KEY_SIX()), 6, reset(key(core, J.KeyboardKey.KEY_FIVE()), 5, reset(key(core, J.KeyboardKey.KEY_FOUR()), 4, s3)))
  update.char(core, s4, J.Input.get_char_pressed(core))

# (int)(rect.x + padding) and (int)(rect.y + padding) are defined.
def fits(+value: F32) -> Bool:
  (value >= F32.neg(2147483648.0) : F32) && (value < 2147483648.0 : F32)

# The border (borderWidth around), the rectangle and the text at the padding.
def box.drawn(drawable: Bool, +text: String, +x: F32, +y: F32, +width: F32, +height: F32, +color: U32, frame: J.Frame) -> J.Frame:
  match drawable:
    case False{}: J.Frame.refuse(frame)
    case True{}: J.Draw.text(J.Draw.rectangle_rec(J.Draw.rectangle_rec(frame, J.Rectangle{(x - 5.0 : F32), (y - 5.0 : F32), (width + 5.0 * 2.0 : F32), (height + 5.0 * 2.0 : F32)}, J.Color.BLACK()),
      J.Rectangle{x, y, width, height}, color), text, F32.trunc((x + 5.0 : F32)), F32.trunc((y + 5.0 : F32)), 30.0, J.Color.BLACK())

def box(particle: Particle, frame: J.Frame) -> J.Frame:
  Particle{+text, +x, +y, +width, +height, _, _, +color, _} = particle
  box.drawn(fits((x + 5.0 : F32)) && fits((y + 5.0 : F32)), text, x, y, width, height, color, frame)

def boxes(particles: +List<Particle>, frame: J.Frame) -> J.Frame:
  match particles:
    case Nil{}: frame
    case Con{+particle, rest}: boxes(rest, box(particle, frame))

def checked(ok: Bool, frame: J.Frame) -> J.Frame:
  match ok:
    case True{}: frame
    case False{}: J.Frame.refuse(frame)

def help(frame: J.Frame, text: String, +y: F32) -> J.Frame:
  J.Draw.text(frame, text, 10.0, y, 10.0, J.Color.DARKGRAY())

def counted(text: Maybe<String>, frame: J.Frame) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 10.0, (450.0 - 30.0 : F32), 20.0, J.Color.BLACK())

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{rng, +table} = state
  Table{+particles, _, _, _, +ok} = table
  f1 = help(help(boxes(particles, J.Frame.clear_background(checked(ok, frame), J.Color.RAYWHITE())), "grab a text particle by pressing with the mouse and throw it by releasing", 10.0),
    "slice a text particle by pressing it with the mouse right button", 30.0)
  f2 = help(help(f1, "shatter a text particle keeping left shift pressed and pressing it with the mouse right button", 50.0), "glue text particles by grabbing than and keeping left control pressed", 70.0)
  f3 = help(help(f2, "1 to 6 to reset", 90.0), "when you have only one text particle, you can slice it by pressing a char", 110.0)
  (core, (State{rng, table}, counted(J.Text.format("TEXT PARTICLE COUNT: %d", [J.TextInt{size(particles)}]), f3)))

# No libm call in the loop: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# After InitWindow(800, 450) and SetRandomSeed(seed): PrepareFirstTextParticle("raylib => fun videogames programming!"), SetTargetFPS(60).
def setup(+seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, prepared(State{J.Random.seed(seed), Table{Nil{}, False{}, 0, M.Vector2.zero(), True{}}}, "raylib => fun videogames programming!")))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [text] example - strings management", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(0, core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
