# raylib [textures] example - blend modes, ported to Jonlib.
# Adapted from raylib 6.0 examples/textures/textures_blend_modes.c (zlib/libpng,
# Copyright (c) 2020-2025 Karlo Licudine (@accidentalrebel)); see LICENSES/raylib.txt.
# The cyberpunk street images are raylib's example resources by Luis Zuno
# (@ansimuz), read in place from the pinned raylib checkout.
#
# A foreground drawn over a background in BLEND_ALPHA, ADDITIVE, MULTIPLIED
# or ADD_COLORS; SPACE cycles them. LoadImage of a .png file is raylib's PNG
# loader (Surface.load_png here; the generic loader compiles every decoder).
# See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type State is Type:
  State{bg: Maybe<J.Texture>, fg: Maybe<J.Texture>, mode: U32}

def update(+core: J.Core, state: State) -> J.Core & State:
  State{bg, fg, +mode} = state
  +next = Bool.pick(U32, (mode >= 3 : U32), 0, (mode + 1 : U32))
  (core, State{bg, fg, Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_SPACE()), next, mode)})

def drawn(r: J.Frame & J.Texture) -> J.Frame & Maybe<J.Texture>:
  (frame, texture) = r
  (frame, Some{texture})

# DrawTexture(t, screenWidth/2 - t.width/2, screenHeight/2 - t.height/2, WHITE).
def centered(frame: J.Frame, texture: J.Texture) -> J.Frame & Maybe<J.Texture>:
  J.Texture{+id, +w, +h, +format, +linear, +alpha, texels} = texture
  drawn(J.Draw.texture(frame, J.Texture{id, w, h, format, linear, alpha, texels}, (400.0 - U32.to_f32((w / 2 : U32)) : F32), (225.0 - U32.to_f32((h / 2 : U32)) : F32), J.Color.WHITE()))

def draw.texture(frame: J.Frame, texture: Maybe<J.Texture>) -> J.Frame & Maybe<J.Texture>:
  match texture:
    case None{}: (frame, None{})
    case Some{t}: centered(frame, t)

def label(mode: U32) -> String:
  match mode:
    case 0: "Current: BLEND_ALPHA"
    case 1: "Current: BLEND_ADDITIVE"
    case 2: "Current: BLEND_MULTIPLIED"
    case _: "Current: BLEND_ADD_COLORS"

def draw.done(+core: J.Core, bg: Maybe<J.Texture>, +mode: U32, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, fg) = r
  f1 = J.Draw.text(J.Frame.end_blend_mode(frame), "Press SPACE to change blend modes.", 310.0, 350.0, 10.0, J.Color.GRAY())
  f2 = J.Draw.text(f1, label(mode), (400.0 - 60.0 : F32), 370.0, 10.0, J.Color.GRAY())
  (core, (State{bg, fg, mode}, J.Draw.text(f2, "(c) Cyberpunk Street Environment by Luis Zuno (@ansimuz)", 470.0, 430.0, 10.0, J.Color.GRAY())))

def draw.fg(+core: J.Core, fg: Maybe<J.Texture>, +mode: U32, r: J.Frame & Maybe<J.Texture>) -> J.Core & (State & J.Frame):
  (frame, bg) = r
  draw.done(core, bg, mode, draw.texture(J.Frame.begin_blend_mode(frame, mode), fg))

def draw(+core: J.Core, state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{bg, fg, +mode} = state
  draw.fg(core, fg, mode, draw.texture(J.Frame.clear_background(frame, J.Color.RAYWHITE()), bg))

# No libm call: the profile argument is the examples' common signature.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def upload(frame: J.Frame, result: Result<&1, &1, J.Surface.IOError, J.Surface>) -> J.Frame & Maybe<J.Texture>:
  match result:
    case Fail{_}: (frame, None{})
    case Done{image}: J.Texture.load_from_image(frame, image)

def setup.done(+core: J.Core, bg: Maybe<J.Texture>, r: J.Frame & Maybe<J.Texture>) -> J.Core & (J.Frame & State):
  (frame, fg) = r
  (J.Core.set_target_fps(core, 60), (frame, State{bg, fg, 0}))

def setup.background(+dir: String, +core: J.Core, r: J.Frame & Maybe<J.Texture>) -> IO(J.Core & (J.Frame & State)):
  (frame, bg) = r
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/cyberpunk_street_foreground.png"),
    result => IO.pure(J.Core & (J.Frame & State), setup.done(core, bg, upload(frame, result))))

# After InitWindow(800, 450): both images uploaded as textures, BLEND_ALPHA, SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.bind(Result<&1, &1, J.Surface.IOError, J.Surface>, J.Core & (J.Frame & State), J.Surface.load_png(dir ++ "resources/cyberpunk_street_background.png"),
    result => setup.background(dir, core, upload(frame, result)))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [textures] example - blend modes", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
