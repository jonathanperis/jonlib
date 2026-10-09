# raylib [textures] example - background scrolling, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_background_scrolling.c
# (zlib/libpng, Copyright (c) 2019-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# Loads the three resources/cyberpunk_street_*.png layers from raylib's
# examples/textures (not copied into this repository; Cyberpunk Street
# Environment by Luis Zuno, @ansimuz): run it from that directory, or pass
# `--resources <dir/>`. See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# A layer: its texture (None when it did not load: raylib's id 0, width 0) and
# width.
type Layer is Type:
  Layer{texture: Maybe<J.Texture>, width: U32}

type State is Type:
  State{back: Layer, mid: Layer, fore: Layer, scroll_back: F32, scroll_mid: F32, scroll_fore: F32}

def float(+word: U32) -> F32:
  U32{bits} = word
  F32{bits}

# scrolling -= step; if (scrolling <= -width*2) scrolling = 0 (the int product
# converted to float).
def scrolled(+scrolling: F32, +step: F32, +width: U32) -> F32:
  +moved = (scrolling - step : F32)
  Bool.pick(F32, (moved <= F32.neg(U32.to_f32((width * 2 : U32))) : F32), 0.0, moved)

def Layer.width(layer: Layer) -> Layer & U32:
  Layer{texture, +width} = layer
  (Layer{texture, width}, width)

def update.widths(+core: J.Core, +sb: F32, +sm: F32, +sf: F32, b: Layer & U32, m: Layer & U32, f: Layer & U32) -> J.Core & State:
  (back, +wb) = b
  (mid, +wm) = m
  (fore, +wf) = f
  (core, State{back, mid, fore, scrolled(sb, float(1036831949), wb), scrolled(sm, 0.5, wm), scrolled(sf, 1.0, wf)})

def update(+core: J.Core, state: State) -> J.Core & State:
  State{back, mid, fore, +sb, +sm, +sf} = state
  update.widths(core, sb, sm, sf, Layer.width(back), Layer.width(mid), Layer.width(fore))

def drawn(+width: U32, r: J.Frame & J.Texture) -> J.Frame & Layer:
  (frame, texture) = r
  (frame, Layer{Some{texture}, width})

def draw.second(+libm: M.Libm, +width: U32, +scroll: F32, +y: F32, r: J.Frame & J.Texture) -> J.Frame & Layer:
  (frame, texture) = r
  drawn(width, J.Draw.texture_ex_for(libm, frame, texture, M.Vector2{(U32.to_f32((width * 2 : U32)) + scroll : F32), y}, 0.0, 2.0, J.Color.WHITE()))

def draw.texture(+libm: M.Libm, frame: J.Frame, texture: Maybe<J.Texture>, +width: U32, +scroll: F32, +y: F32) -> J.Frame & Layer:
  match texture:
    case None{}: (frame, Layer{None{}, width})
    case Some{t}: draw.second(libm, width, scroll, y, J.Draw.texture_ex_for(libm, frame, t, M.Vector2{scroll, y}, 0.0, 2.0, J.Color.WHITE()))

# DrawTextureEx(layer, (scroll, y), 0.0f, 2.0f, WHITE), then at
# (width*2 + scroll, y).
def draw.layer(+libm: M.Libm, frame: J.Frame, layer: Layer, +scroll: F32, +y: F32) -> J.Frame & Layer:
  Layer{texture, +width} = layer
  draw.texture(libm, frame, texture, width, scroll, y)

def draw.done(+core: J.Core, back: Layer, mid: Layer, +sb: F32, +sm: F32, +sf: F32, r: J.Frame & Layer) -> J.Core & (State & J.Frame):
  (frame, fore) = r
  f1 = J.Draw.text(frame, "BACKGROUND SCROLLING & PARALLAX", 10.0, 10.0, 20.0, J.Color.RED())
  f2 = J.Draw.text(f1, "(c) Cyberpunk Street Environment by Luis Zuno (@ansimuz)", 470.0, 430.0, 10.0, J.Color.RAYWHITE())
  (core, (State{back, mid, fore, sb, sm, sf}, f2))

def draw.fore(+core: J.Core, +libm: M.Libm, back: Layer, fore: Layer, +sb: F32, +sm: F32, +sf: F32, r: J.Frame & Layer) -> J.Core & (State & J.Frame):
  (frame, mid) = r
  draw.done(core, back, mid, sb, sm, sf, draw.layer(libm, frame, fore, sf, 70.0))

def draw.mid(+core: J.Core, +libm: M.Libm, mid: Layer, fore: Layer, +sb: F32, +sm: F32, +sf: F32, r: J.Frame & Layer) -> J.Core & (State & J.Frame):
  (frame, back) = r
  draw.fore(core, libm, back, fore, sb, sm, sf, draw.layer(libm, frame, mid, sm, 20.0))

def draw(+libm: M.Libm, +core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{back, mid, fore, +sb, +sm, +sf} = state
  draw.mid(core, libm, mid, fore, sb, sm, sf, draw.layer(libm, J.Frame.clear_background(frame, 86787839), back, sb, 20.0))

# The main loop's body; libm is the sinf/cosf profile (unused: no rotation).
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def layer.sized(texture: J.Texture) -> Layer:
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  Layer{Some{J.Texture{id, w, h, format, linear, alpha, texels}}, w}

def layer.of(texture: Maybe<J.Texture>) -> Layer:
  match texture:
    case None{}: Layer{None{}, 0}
    case Some{t}: layer.sized(t)

def setup.fore(+core: J.Core, back: Layer, mid: Layer, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, fore) = r
  (J.Core.set_target_fps(core, 60), (frame, State{back, mid, layer.of(fore), 0.0, 0.0, 0.0}))

def setup.mid(dir: String, +core: J.Core, back: Layer, r: J.Frame & Maybe<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  (frame, mid) = r
  IO.bind(J.Frame & Maybe<J.Texture>, J.Core & (J.Frame & State), J.Texture.load(frame, dir ++ "resources/cyberpunk_street_foreground.png"),
    f => IO.pure(J.Core & (J.Frame & State), setup.fore(core, back, layer.of(mid), f)))

def setup.back(+dir: String, +core: J.Core, r: J.Frame & Maybe<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  (frame, back) = r
  IO.bind(J.Frame & Maybe<J.Texture>, J.Core & (J.Frame & State), J.Texture.load(frame, dir ++ "resources/cyberpunk_street_midground.png"),
    m => setup.mid(dir, core, layer.of(back), m))

# After InitWindow(800, 450): the background, midground and foreground
# textures, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(J.Frame & Maybe<J.Texture>, J.Core & (J.Frame & State), J.Texture.load(frame, dir ++ "resources/cyberpunk_street_background.png"),
    b => setup.back(dir, core, b))

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
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - background scrolling", 800, 450, limit,
    core => frame => setup(dir, core, frame))

def run(args: List<String>) -> IO(Unit):
  run.with(options(args, 0, "", 0))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
