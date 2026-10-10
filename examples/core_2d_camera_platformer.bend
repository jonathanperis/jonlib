# raylib [core] example - 2d camera platformer, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_2d_camera_platformer.c
# (zlib/libpng, Copyright (c) 2019-2025 arvyy (@arvyy)); see
# LICENSES/raylib.txt.
#
# A player that runs and jumps over five platforms under one of five camera
# behaviours (C cycles them): centered, clamped to the map, smoothed, evened
# out after landing, and pushed by the player near the screen edge. The
# wheel zooms and R resets. The clamped and pushed cameras go through
# GetWorldToScreen2D and GetScreenToWorld2D; a conversion Jonlib refuses
# refuses the frame. BeginMode2D's and DrawCircleV's sinf/cosf follow the
# libm profile (whole degrees only). See docs/DRIVER.md.
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Player is Data:
  Player{position: M.Vector2, speed: F32, jump: Bool}

type Item is Data:
  Item{rect: J.Rectangle, blocking: Bool, color: U32}

# UpdateCameraEvenOutOnLanding's statics: eveningOut and evenOutTarget.
type Even is Data:
  Even{on: Bool, goal: F32}

type Cam is Data:
  Cam{valid: Bool, camera: J.Camera2D, even: Even}

type Hit is Data:
  Hit{hit: Bool, y: F32}

type State is Data:
  State{valid: Bool, player: Player, camera: J.Camera2D, option: U32, even: Even}

def items() -> +List<Item>:
  [Item{J.Rectangle{0.0, 0.0, 1000.0, 400.0}, False{}, J.Color.LIGHTGRAY()},
   Item{J.Rectangle{0.0, 400.0, 1000.0, 200.0}, True{}, J.Color.GRAY()},
   Item{J.Rectangle{300.0, 200.0, 400.0, 10.0}, True{}, J.Color.GRAY()},
   Item{J.Rectangle{250.0, 300.0, 100.0, 10.0}, True{}, J.Color.GRAY()},
   Item{J.Rectangle{650.0, 300.0, 100.0, 10.0}, True{}, J.Color.GRAY()}]

def center() -> M.Vector2:
  M.Vector2{(800.0 / 2.0 : F32), (450.0 / 2.0 : F32)}

def description(option: U32) -> String:
  match option:
    case 0: "Follow player center"
    case 1: "Follow player center, but clamp to map edges"
    case 2: "Follow player center; smoothed"
    case 3: "Follow player center horizontally; update player center vertically after landing"
    case _: "Player push camera on getting too close to screen edge"

# ei->blocking && rect.x <= p.x && rect.x + rect.width >= p.x && rect.y >= p.y && rect.y <= p.y + speed*delta.
def blocks(+item: Item, +x: F32, +y: F32, +reach: F32) -> Hit:
  Item{rect, +blocking, _} = item
  J.Rectangle{+rx, +ry, +rw, _} = rect
  Hit{blocking && (rx <= x : F32) && ((rx + rw) >= x : F32) && (ry >= y : F32) && (ry <= reach : F32), ry}

def first(+here: Hit, +later: Hit) -> Hit:
  Hit{+found, _} = here
  Bool.pick(Hit, found, here, later)

# The first item hit, in order.
def hit(list: +List<Item>, +x: F32, +y: F32, +reach: F32) -> Hit:
  match list:
    case Nil{}: Hit{False{}, 0.0}
    case Con{+item, rest}: first(blocks(item, x, y, reach), hit(rest, x, y, reach))

# An obstacle stops the fall on its top; otherwise the player moves and gravity (G = 400) pulls.
def player.landed(+x: F32, +y: F32, +speed: F32, +delta: F32, +hit: Hit) -> Player:
  Hit{+landed, +top} = hit
  Bool.pick(Player, landed, Player{M.Vector2{x, top}, 0.0, True{}}, Player{M.Vector2{x, (y + speed * delta : F32)}, (speed + 400.0 * delta : F32), False{}})

# UpdatePlayer: LEFT/RIGHT run at 200 a second, SPACE jumps at -350 from the ground.
def player.update(+core: J.Core, +delta: F32, +player: Player) -> Player:
  Player{+position, +speed, +jump} = player
  M.Vector2{+x, +y} = position
  +left = Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT()), (x - 200.0 * delta : F32), x)
  +right = Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_RIGHT()), (left + 200.0 * delta : F32), left)
  +jumped = Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_SPACE()) && jump, F32.neg(350.0), speed)
  player.landed(right, y, jumped, delta, hit(items(), right, y, (y + jumped * delta : F32)))

# R: player.position = (400, 280) (its speed stays).
def player.reset(+player: Player) -> Player:
  Player{_, +speed, +jump} = player
  Player{M.Vector2{400.0, 280.0}, speed, jump}

# UpdateCameraCenterInsideMap: the map's corners ((0, 0) and (1000, 600),
# the fminf/fmaxf of the items) on screen pull the offset back inside.
def inside.in(+target: M.Vector2, +rotation: F32, +zoom: F32, +even: Even, +max: M.Vector2, +min: M.Vector2) -> Cam:
  M.Vector2{+ax, +ay} = max
  M.Vector2{+bx, +by} = min
  +x1 = Bool.pick(F32, (ax < 800.0 : F32), (800.0 - (ax - (800.0 / 2.0)) : F32), (800.0 / 2.0 : F32))
  +y1 = Bool.pick(F32, (ay < 450.0 : F32), (450.0 - (ay - (450.0 / 2.0)) : F32), (450.0 / 2.0 : F32))
  +x2 = Bool.pick(F32, (bx > 0.0 : F32), ((800.0 / 2.0) - bx : F32), x1)
  +y2 = Bool.pick(F32, (by > 0.0 : F32), ((450.0 / 2.0) - by : F32), y1)
  Cam{True{}, J.Camera2D{M.Vector2{x2, y2}, target, rotation, zoom}, even}

def inside.at(+target: M.Vector2, +rotation: F32, +zoom: F32, +even: Even, max: Maybe<M.Vector2>, min: Maybe<M.Vector2>) -> Cam:
  match max min:
    case Some{+a} Some{+b}: inside.in(target, rotation, zoom, even, a, b)
    case _ _: Cam{False{}, J.Camera2D{center(), target, rotation, zoom}, even}

def inside(+libm: M.Libm, +camera: J.Camera2D, +position: M.Vector2, +even: Even) -> Cam:
  J.Camera2D{_, _, +rotation, +zoom} = camera
  +centered = {J.Camera2D{center(), position, rotation, zoom} : J.Camera2D}
  inside.at(position, rotation, zoom, even, J.Camera.world_to_screen_2d_for(M.Uncontracted{}, libm, M.Vector2{1000.0, 600.0}, centered),
    J.Camera.world_to_screen_2d_for(M.Uncontracted{}, libm, M.Vector2{0.0, 0.0}, centered))

# UpdateCameraCenterSmoothFollow: past 10 pixels the target closes in at
# fmaxf(0.8*length, 30) a second.
def smooth(+camera: J.Camera2D, +position: M.Vector2, +delta: F32, +even: Even) -> Cam:
  J.Camera2D{_, +target, +rotation, +zoom} = camera
  +diff = M.Vector2.subtract(position, target)
  +length = M.Vector2.length(diff)
  +speed = F32.max((0.8 * length : F32), 30.0)
  +moved = Bool.pick(M.Vector2, (length > 10.0 : F32), M.Vector2.add(target, M.Vector2.scale(diff, ((speed * delta) / length : F32))), target)
  Cam{True{}, J.Camera2D{center(), moved, rotation, zoom}, even}

# UpdateCameraEvenOutOnLanding: the target follows x; after a landing its y
# moves 700 a second to the player's.
def evening.at(+target: M.Vector2, +rotation: F32, +zoom: F32, +position: M.Vector2, +speed: F32, +jump: Bool, +delta: F32, +even: Even) -> Cam:
  M.Vector2{_, +ty} = target
  M.Vector2{+px, +py} = position
  Even{+on, +goal} = even
  +rising = (goal > ty : F32)
  +stepped = Bool.pick(F32, rising, (ty + 700.0 * delta : F32), (ty - 700.0 * delta : F32))
  +reached = (rising && (stepped > goal : F32)) || (Bool.not(rising) && (stepped < goal : F32))
  +starts = jump && F32.is_eq(speed, 0.0) && F32.is_ne(py, ty)
  +y = Bool.pick(F32, on && reached, goal, Bool.pick(F32, on, stepped, ty))
  +next = Bool.pick(Even, on, Even{Bool.not(reached), goal}, Bool.pick(Even, starts, Even{True{}, py}, even))
  Cam{True{}, J.Camera2D{center(), M.Vector2{px, y}, rotation, zoom}, next}

def evening(+camera: J.Camera2D, +player: Player, +delta: F32, +even: Even) -> Cam:
  J.Camera2D{_, +target, +rotation, +zoom} = camera
  Player{+position, +speed, +jump} = player
  evening.at(target, rotation, zoom, position, speed, jump, delta, even)

# The inner box's corner: ((1 - bbox)*0.5*width, (1 - bbox)*0.5*height), bbox = 0.2.
def box.min() -> M.Vector2:
  M.Vector2{(((1.0 - 0.2) * 0.5) * 800.0 : F32), (((1.0 - 0.2) * 0.5) * 450.0 : F32)}

def box.max() -> M.Vector2:
  M.Vector2{(((1.0 + 0.2) * 0.5) * 800.0 : F32), (((1.0 + 0.2) * 0.5) * 450.0 : F32)}

# UpdateCameraPlayerBoundsPush: the player outside the box's world corners moves the target.
def push.in(+target: M.Vector2, +rotation: F32, +zoom: F32, +position: M.Vector2, +even: Even, +low: M.Vector2, +high: M.Vector2) -> Cam:
  M.Vector2{+tx, +ty} = target
  M.Vector2{+px, +py} = position
  M.Vector2{+ax, +ay} = low
  M.Vector2{+bx, +by} = high
  +x1 = Bool.pick(F32, (px < ax : F32), px, tx)
  +y1 = Bool.pick(F32, (py < ay : F32), py, ty)
  +x2 = Bool.pick(F32, (px > bx : F32), (ax + (px - bx) : F32), x1)
  +y2 = Bool.pick(F32, (py > by : F32), (ay + (py - by) : F32), y1)
  Cam{True{}, J.Camera2D{box.min(), M.Vector2{x2, y2}, rotation, zoom}, even}

def push.at(+target: M.Vector2, +rotation: F32, +zoom: F32, +position: M.Vector2, +even: Even, low: Maybe<M.Vector2>, high: Maybe<M.Vector2>) -> Cam:
  match low high:
    case Some{+a} Some{+b}: push.in(target, rotation, zoom, position, even, a, b)
    case _ _: Cam{False{}, J.Camera2D{box.min(), target, rotation, zoom}, even}

def push(+libm: M.Libm, +camera: J.Camera2D, +position: M.Vector2, +even: Even) -> Cam:
  J.Camera2D{_, +target, +rotation, +zoom} = camera
  push.at(target, rotation, zoom, position, even, J.Camera.screen_to_world_2d_for(M.Uncontracted{}, libm, box.min(), camera),
    J.Camera.screen_to_world_2d_for(M.Uncontracted{}, libm, box.max(), camera))

# cameraUpdaters[cameraOption].
def follow(+libm: M.Libm, +camera: J.Camera2D, +player: Player, +delta: F32, +even: Even, option: U32) -> Cam:
  J.Camera2D{_, _, +rotation, +zoom} = camera
  Player{+position, _, _} = player
  match option:
    case 0: Cam{True{}, J.Camera2D{center(), position, rotation, zoom}, even}
    case 1: inside(libm, camera, position, even)
    case 2: smooth(camera, position, delta, even)
    case 3: evening(camera, player, delta, even)
    case _: push(libm, camera, position, even)

def update.done(+player: Player, +option: U32, +cam: Cam) -> State:
  Cam{+valid, +camera, +even} = cam
  State{valid, player, camera, option, even}

# UpdatePlayer; the wheel zooms inside [0.25, 3]; R resets zoom and
# position; C takes the next camera, which then updates.
def update(+libm: M.Libm, +core: J.Core, +state: State) -> J.Core & State:
  State{_, +player, +camera, +option, +even} = state
  J.Camera2D{+offset, +target, +rotation, +zoom} = camera
  +delta = J.Core.get_frame_time(core)
  +moved = player.update(core, delta, player)
  +wheel = (zoom + J.Input.get_mouse_wheel_move(core) * 0.05 : F32)
  +clamped = Bool.pick(F32, (wheel > 3.0 : F32), 3.0, Bool.pick(F32, (wheel < 0.25 : F32), 0.25, wheel))
  +reset = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_R())
  +placed = Bool.pick(Player, reset, player.reset(moved), moved)
  +next = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_C()), ((option + 1) % 5 : U32), option)
  (core, update.done(placed, next, follow(libm, J.Camera2D{offset, target, rotation, Bool.pick(F32, reset, 1.0, clamped)}, placed, delta, even, next)))

def rects(list: +List<Item>, frame: J.Frame) -> J.Frame:
  match list:
    case Nil{}: frame
    case Con{+item, rest}:
      Item{+rect, _, +color} = item
      rects(rest, J.Draw.rectangle_rec(frame, rect, color))

def draw.valid(valid: Bool, +libm: M.Libm, +state: State, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: J.Frame.refuse(frame)
    case True{}:
      State{_, +player, +camera, +option, _} = state
      Player{+position, _, _} = player
      M.Vector2{+x, +y} = position
      f1 = rects(items(), J.Frame.begin_mode_2d_for(libm, J.Frame.clear_background(frame, J.Color.LIGHTGRAY()), camera))
      f2 = J.Draw.rectangle_rec(f1, J.Rectangle{(x - 20.0 : F32), (y - 40.0 : F32), 40.0, 40.0}, J.Color.RED())
      f3 = J.Frame.end_mode_2d(J.Draw.circle_v_for(libm, f2, position, 5.0, J.Color.GOLD()))
      f4 = J.Draw.text(f3, "Controls:", 20.0, 20.0, 10.0, J.Color.BLACK())
      f5 = J.Draw.text(f4, "- Right/Left to move", 40.0, 40.0, 10.0, J.Color.DARKGRAY())
      f6 = J.Draw.text(f5, "- Space to jump", 40.0, 60.0, 10.0, J.Color.DARKGRAY())
      f7 = J.Draw.text(f6, "- Mouse Wheel to Zoom in-out", 40.0, 80.0, 10.0, J.Color.DARKGRAY())
      f8 = J.Draw.text(f7, "- R to reset position + zoom", 40.0, 100.0, 10.0, J.Color.DARKGRAY())
      f9 = J.Draw.text(f8, "- C to change camera mode", 40.0, 120.0, 10.0, J.Color.DARKGRAY())
      J.Draw.text(J.Draw.text(f9, "Current camera mode:", 20.0, 140.0, 10.0, J.Color.BLACK()), description(option), 40.0, 160.0, 10.0, J.Color.DARKGRAY())

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, _, _, _, _} = state
  (core, (state, draw.valid(valid, libm, state, frame)))

# The main loop's body; libm is the sinf/cosf profile of the camera matrices and DrawCircleV.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(libm, core, state), core => state => frame => draw(libm, core, state, frame)}

# After InitWindow(800, 450): the player at (400, 280), the camera on it, SetTargetFPS(60).
def setup(+core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, State{True{}, Player{M.Vector2{400.0, 280.0}, 0.0, False{}},
    J.Camera2D{center(), M.Vector2{400.0, 280.0}, 0.0, 1.0}, 0, Even{False{}, 0.0}}))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - 2d camera platformer", 800, 450, J.Desktop.frames_arg(args),
    core => frame => IO.pure(J.Core & (J.Frame & State), setup(core, frame)))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
