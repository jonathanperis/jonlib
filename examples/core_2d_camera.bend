# raylib [core] example - 2d camera, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_2d_camera.c (zlib/libpng,
# Copyright (c) 2016-2025 Ramon Santamaria (@raysan5)); see LICENSES/raylib.txt.
#
# Right/Left move the player, A/S rotate the camera, R resets. raylib seeds
# GetRandomValue from time(NULL) in InitWindow; here the seed is a setup
# argument (the replay fixes it, the interactive run takes the clock).
# The zoom is expf(logf(zoom) + wheel*0.1f): Jonmath has no expf/logf
# profile, so only zoom 1 with no wheel move (exactly 1 in every libm) is
# reproduced; otherwise the frames are refused (Frame.refuse). Base has no
# mouse wheel, so interactively the zoom stays 1. BeginMode2D's sinf/cosf
# follow the M.Libm profile (the Apple profile refuses rotations of 13, 19 and
# 22 degrees; the interactive run uses glibc 2.39's). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

# A building: its rectangle and color.
type Building is Data:
  Building{rec: J.Rectangle, color: U32}

type State is Data:
  State{player: J.Rectangle, buildings: +List<Building>, camera: J.Camera2D, refused: Bool}

# -----------------------------------------------------------------------------
# Setup: MAX_BUILDINGS 100 random buildings, in raylib's GetRandomValue order.

type Made is Type:
  Made{rng: J.Random.State, buildings: +List<Building>, spacing: F32}

# spacing += (int)width: the widths are integral, so the F32 sum is exact.
def made.color(+rec: J.Rectangle, +w: F32, +r: F32, +g: F32, +spacing: F32, +buildings: +List<Building>, drawn: J.Random.State & F32) -> Made:
  (rng, +b) = drawn
  Made{rng, Con{Building{rec, J.Color.rgba(F32.to_u32(r), F32.to_u32(g), F32.to_u32(b), 255)}, buildings}, (spacing + w : F32)}

def made.green(+rec: J.Rectangle, +w: F32, +r: F32, +spacing: F32, +buildings: +List<Building>, drawn: J.Random.State & F32) -> Made:
  (rng, +g) = drawn
  made.color(rec, w, r, g, spacing, buildings, J.Random.value(rng, 200.0, 250.0))

def made.red(+rec: J.Rectangle, +w: F32, +spacing: F32, +buildings: +List<Building>, drawn: J.Random.State & F32) -> Made:
  (rng, +r) = drawn
  made.green(rec, w, r, spacing, buildings, J.Random.value(rng, 200.0, 240.0))

# y = screenHeight - 130.0f - height, x = -6000.0f + spacing.
def made.height(+w: F32, +spacing: F32, +buildings: +List<Building>, drawn: J.Random.State & F32) -> Made:
  (rng, +h) = drawn
  made.red(J.Rectangle{(F32.neg(6000.0) + spacing : F32), ((450.0 - 130.0 : F32) - h : F32), w, h}, w, spacing, buildings, J.Random.value(rng, 200.0, 240.0))

def made.width(+spacing: F32, +buildings: +List<Building>, drawn: J.Random.State & F32) -> Made:
  (rng, +w) = drawn
  made.height(w, spacing, buildings, J.Random.value(rng, 100.0, 800.0))

def made.next(made: Made) -> Made:
  Made{rng, +buildings, +spacing} = made
  made.width(spacing, buildings, J.Random.value(rng, 50.0, 200.0))

def buildings(n: Nat, made: Made) -> Made:
  match n:
    case 0n: made
    case 1n+k: buildings(k, made.next(made))

def buildings.list(made: Made) -> +List<Building>:
  Made{_, +list, _} = made
  List.reverse(&2, Building, list)

# After InitWindow(800, 450) and SetRandomSeed(seed): the buildings, the
# player at (400, 280, 40, 40), the camera on the player with offset
# (400, 225), rotation 0 and zoom 1, SetTargetFPS(60).
def setup(+seed: U32, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{J.Rectangle{400.0, 280.0, 40.0, 40.0},
    buildings.list(buildings(100n, Made{J.Random.seed(seed), Nil{}, 0.0})),
    J.Camera2D{M.Vector2{420.0, 300.0}, M.Vector2{400.0, 225.0}, 0.0, 1.0}, False{}}))

# -----------------------------------------------------------------------------
# Update

def down(+core: J.Core, +key: U32) -> Bool:
  J.Input.is_key_down(core, key)

def player.x(+core: J.Core, +x: F32) -> F32:
  Bool.pick(F32, down(core, J.KeyboardKey.KEY_RIGHT()), (x + 2.0 : F32), Bool.pick(F32, down(core, J.KeyboardKey.KEY_LEFT()), (x - 2.0 : F32), x))

def rotated(+core: J.Core, +rotation: F32) -> F32:
  +r = Bool.pick(F32, down(core, J.KeyboardKey.KEY_A()), (rotation - 1.0 : F32), Bool.pick(F32, down(core, J.KeyboardKey.KEY_S()), (rotation + 1.0 : F32), rotation))
  Bool.pick(F32, (r > 40.0 : F32), 40.0, Bool.pick(F32, (r < F32.neg(40.0) : F32), F32.neg(40.0), r))

# The camera follows the moved player; R resets rotation and zoom. A wheel
# move (or a zoom other than 1) needs expf/logf: refused from then on.
def update.camera(+core: J.Core, +x: F32, +y: F32, +w: F32, +h: F32, +buildings: +List<Building>, +rotation: F32, +zoom: F32, +refused: Bool) -> J.Core & State:
  +reset = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_R())
  +unsupported = refused || F32.is_ne(J.Input.get_mouse_wheel_move(core), 0.0) || F32.is_ne(zoom, 1.0)
  (core, State{J.Rectangle{x, y, w, h}, buildings, J.Camera2D{M.Vector2{400.0, 225.0}, M.Vector2{(x + 20.0 : F32), (y + 20.0 : F32)},
    Bool.pick(F32, reset, 0.0, rotated(core, rotation)), 1.0}, unsupported})

def update.player(+core: J.Core, +player: J.Rectangle, +buildings: +List<Building>, +rotation: F32, +zoom: F32, +refused: Bool) -> J.Core & State:
  J.Rectangle{+x, +y, +w, +h} = player
  update.camera(core, player.x(core, x), y, w, h, buildings, rotation, zoom, refused)

def update.parts(+core: J.Core, +player: J.Rectangle, +buildings: +List<Building>, +camera: J.Camera2D, +refused: Bool) -> J.Core & State:
  J.Camera2D{_, _, +rotation, +zoom} = camera
  update.player(core, player, buildings, rotation, zoom, refused)

def update(+core: J.Core, +state: State) -> J.Core & State:
  State{+player, +buildings, +camera, +refused} = state
  update.parts(core, player, buildings, camera, refused)

# -----------------------------------------------------------------------------
# Draw

def draw.building(+building: Building, frame: J.Frame) -> J.Frame:
  Building{+rec, +color} = building
  J.Draw.rectangle_rec(frame, rec, color)

def draw.buildings(buildings: +List<Building>, frame: J.Frame) -> J.Frame:
  match buildings:
    case Nil{}: frame
    case Con{+building, rest}: draw.buildings(rest, draw.building(building, frame))

def target(+camera: J.Camera2D) -> M.Vector2:
  J.Camera2D{_, +t, _, _} = camera
  t

def draw.world.at(+libm: M.Libm, +player: J.Rectangle, +buildings: +List<Building>, +camera: J.Camera2D, +tx: F32, +ty: F32, frame: J.Frame) -> J.Frame:
  f1 = J.Frame.begin_mode_2d_for(libm, frame, camera)
  f2 = J.Draw.rectangle(f1, F32.neg(6000.0), 320.0, 13000.0, 8000.0, J.Color.DARKGRAY())
  f3 = draw.buildings(buildings, f2)
  f4 = J.Draw.rectangle_rec(f3, player, J.Color.RED())
  f5 = J.Draw.line(f4, tx, F32.neg(4500.0), tx, 4500.0, J.Color.GREEN())
  f6 = J.Draw.line(f5, F32.neg(8000.0), ty, 8000.0, ty, J.Color.GREEN())
  J.Frame.end_mode_2d(f6)

def draw.world.target(+libm: M.Libm, +player: J.Rectangle, +buildings: +List<Building>, +camera: J.Camera2D, +t: M.Vector2, frame: J.Frame) -> J.Frame:
  M.Vector2{+tx, +ty} = t
  draw.world.at(libm, player, buildings, camera, tx, ty, frame)

# BeginMode2D, the world, EndMode2D; the lines are DrawLine((int)target.x,
# -screenHeight*10, ...) and DrawLine(-screenWidth*10, (int)target.y, ...).
def draw.world(+libm: M.Libm, +player: J.Rectangle, +buildings: +List<Building>, +camera: J.Camera2D, frame: J.Frame) -> J.Frame:
  draw.world.target(libm, player, buildings, camera, target(camera), frame)

def draw.screen(frame: J.Frame) -> J.Frame:
  f1 = J.Draw.text(frame, "SCREEN AREA", 640.0, 10.0, 20.0, J.Color.RED())
  f2 = J.Draw.rectangle(f1, 0.0, 0.0, 800.0, 5.0, J.Color.RED())
  f3 = J.Draw.rectangle(f2, 0.0, 5.0, 5.0, 440.0, J.Color.RED())
  f4 = J.Draw.rectangle(f3, 795.0, 5.0, 5.0, 440.0, J.Color.RED())
  f5 = J.Draw.rectangle(f4, 0.0, 445.0, 800.0, 5.0, J.Color.RED())
  f6 = J.Draw.rectangle(f5, 10.0, 10.0, 250.0, 113.0, J.Color.with_alpha(J.Color.SKYBLUE(), 0.5))
  f7 = J.Draw.rectangle_lines(f6, 10.0, 10.0, 250.0, 113.0, J.Color.BLUE())
  f8 = J.Draw.text(f7, "Free 2D camera controls:", 20.0, 20.0, 10.0, J.Color.BLACK())
  f9 = J.Draw.text(f8, "- Right/Left to move player", 40.0, 40.0, 10.0, J.Color.DARKGRAY())
  f10 = J.Draw.text(f9, "- Mouse Wheel to Zoom in-out", 40.0, 60.0, 10.0, J.Color.DARKGRAY())
  f11 = J.Draw.text(f10, "- A / S to Rotate", 40.0, 80.0, 10.0, J.Color.DARKGRAY())
  J.Draw.text(f11, "- R to reset Zoom and Rotation", 40.0, 100.0, 10.0, J.Color.DARKGRAY())

def draw.checked(+refused: Bool, frame: J.Frame) -> J.Frame:
  match refused:
    case True{}: J.Frame.refuse(frame)
    case False{}: frame

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+player, +buildings, +camera, +refused} = state
  f1 = J.Frame.clear_background(frame, J.Color.RAYWHITE())
  f2 = draw.world(libm, player, buildings, camera, f1)
  (core, (State{player, buildings, camera, refused}, draw.checked(refused, draw.screen(f2))))

# The main loop's body; libm is the sinf/cosf profile of BeginMode2D.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(libm, core, state, frame)}

def run.seeded(+limit: U32, +seed: Nat) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.Glibc239Libm{}), ~M.Glibc239Libm{}, "raylib [core] example - 2d camera", 800, 450, limit,
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(U32.from_nat(seed), core, frame)))

def run(args: List<String>) -> IO(Unit):
  IO.bind(Nat, Unit, IO.now(), seed => run.seeded(J.Desktop.frames_arg(args), seed))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
