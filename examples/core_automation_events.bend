# raylib [core] example - automation events, ported to Jonlib.
# Adapted from raylib 6.2 examples/core/core_automation_events.c
# (zlib/libpng, Copyright (c) 2023-2025 Ramon Santamaria (@raysan5)); see
# LICENSES/raylib.txt.
#
# A player that runs and jumps over five platforms under a camera kept
# inside the map, with the input recorded as automation events: S starts a
# recording (SetAutomationEventBaseFrame(180), StartAutomationEventRecording)
# and S again stops it and exports the list to automation.rae; A plays the
# recorded list from a reset scene, the events of each frame given to
# PlayAutomationEvent. The list is the one the Core records into
# (SetAutomationEventList; Core.automation_event_list). The export writes a
# file inside the loop, so the program is a J.Effects one (docs/DRIVER.md).
# No platform Jonlib runs on delivers dropped files, so the branch that loads
# a dropped .txt or .rae list never runs; it is ported as written. A list
# without events would be played by reading events past it (a dropped file
# without any): the frame is refused. While a recording runs raylib ignores
# PlayAutomationEvent, which is how the examples probe gives its input: the
# probe can start a recording and see it count, not stop it. BeginMode2D's
# and DrawCircle's sinf/cosf follow the libm profile (whole degrees only).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

type Player is Data:
  Player{position: M.Vector2, speed: F32, jump: Bool}

type Item is Data:
  Item{rect: J.Rectangle, blocking: Bool, color: U32}

# valid: no refusal so far. dir is the directory of automation.rae;
# recording and playing are eventRecording and eventPlaying; frames is
# frameCounter, ticks playFrameCounter and at currentPlayFrame.
type State is Data:
  State{valid: Bool, dir: String, player: Player, camera: J.Camera2D, recording: Bool, playing: Bool, frames: U32, ticks: U32, at: U32}

# The obstacle loop's state: whether an element stopped the player, the
# height and the speed.
type Fall is Data:
  Fall{hit: Bool, y: F32, speed: F32}

type Cam is Data:
  Cam{valid: Bool, camera: J.Camera2D}

# The events playing of a frame: the Core after the events played.
type Play is Data:
  Play{valid: Bool, core: J.Core, playing: Bool, ticks: U32, at: U32}

def items() -> +List<Item>:
  [Item{J.Rectangle{0.0, 0.0, 1000.0, 400.0}, False{}, J.Color.LIGHTGRAY()},
   Item{J.Rectangle{0.0, 400.0, 1000.0, 200.0}, True{}, J.Color.GRAY()},
   Item{J.Rectangle{300.0, 200.0, 400.0, 10.0}, True{}, J.Color.GRAY()},
   Item{J.Rectangle{250.0, 300.0, 100.0, 10.0}, True{}, J.Color.GRAY()},
   Item{J.Rectangle{650.0, 300.0, 100.0, 10.0}, True{}, J.Color.GRAY()}]

# (GetRenderWidth()/2.0f, GetRenderHeight()/2.0f) (raylib 6.2; 6.0 took
# screenWidth/2.0f): a Base window's render size is its InitWindow size
# (J.Core.get_render_width), so the offset is the same constant.
def center() -> M.Vector2:
  M.Vector2{(800.0 / 2.0 : F32), (450.0 / 2.0 : F32)}

# player.position = (400, 280); player.speed = 0; player.canJump = false.
def player.start() -> Player:
  Player{M.Vector2{400.0, 280.0}, 0.0, False{}}

# camera.target = player.position (the start); the offset centered; rotation 0; zoom 1.
def camera.start() -> J.Camera2D:
  J.Camera2D{center(), M.Vector2{400.0, 280.0}, 0.0, 1.0}

# An element of the loop (deltaTime is 0.015f): a blocking one with the
# player over it and within this frame's fall stops him on its top; the
# elements after it see that height and speed.
def fall.step(+item: Item, +x: F32, +fall: Fall) -> Fall:
  Item{rect, +blocking, _} = item
  J.Rectangle{+rx, +ry, +rw, _} = rect
  Fall{+hit, +y, +speed} = fall
  Bool.pick(Fall, blocking && (rx <= x : F32) && ((rx + rw) >= x : F32) && (ry >= y : F32) && (ry <= (y + speed * 0.015) : F32), Fall{True{}, ry, 0.0}, Fall{hit, y, speed})

def fall.all(list: +List<Item>, +x: F32, +state: Fall) -> Fall:
  match list:
    case Nil{}: state
    case Con{+item, rest}: fall.all(rest, x, fall.step(item, x, state))

# Without an obstacle the player moves and gravity (GRAVITY 400) pulls; on one he can jump.
def player.fallen(+x: F32, +fall: Fall) -> Player:
  Fall{+hit, +y, +speed} = fall
  Bool.pick(Player, hit, Player{M.Vector2{x, y}, speed, True{}}, Player{M.Vector2{x, (y + speed * 0.015 : F32)}, (speed + 400.0 * 0.015 : F32), False{}})

# LEFT and RIGHT run at PLAYER_HOR_SPD (200) a second, SPACE jumps at -PLAYER_JUMP_SPD (350) from the ground.
def player.update(+core: J.Core, +player: Player) -> Player:
  Player{+position, +speed, +jump} = player
  M.Vector2{+x, +y} = position
  +left = Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_LEFT()), (x - 200.0 * 0.015 : F32), x)
  +right = Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_RIGHT()), (left + 200.0 * 0.015 : F32), left)
  +jumped = Bool.pick(F32, J.Input.is_key_down(core, J.KeyboardKey.KEY_SPACE()) && jump, F32.neg(350.0), speed)
  player.fallen(right, fall.all(items(), right, Fall{False{}, y, jumped}))

def frame.of(event: J.AutomationEvent) -> U32:
  J.AutomationEvent{frame, _, _, _, _, _} = event
  frame

# Whether the list's first event is one of frame `ticks`.
def due.head(events: +List<J.AutomationEvent>, +ticks: U32) -> Bool:
  match events:
    case Nil{}: False{}
    case Con{+event, _}: U32.is_eq(frame.of(event), ticks)

# while (playFrameCounter == aelist.events[currentPlayFrame].frame): the
# events of this frame at the front of the list (go: whether its first is one).
def due.from(events: +List<J.AutomationEvent>, +ticks: U32, go: Bool) -> +List<J.AutomationEvent>:
  match events go:
    case Nil{} _: Nil{}
    case Con{+event, +rest} True{}: Con{event, due.from(rest, ticks, due.head(rest, ticks))}
    case Con{_, _} False{}: Nil{}

def size(events: +List<J.AutomationEvent>, +n: U32) -> U32:
  match events:
    case Nil{}: n
    case Con{_, rest}: size(rest, (n + 1 : U32))

# The events played (None: one outside the reproduced domain). The last
# event of the list ends the playing: eventPlaying = false, both counters 0,
# then playFrameCounter++. `any` is False for a list with nothing left, which
# C would play by reading past its events.
def play.done(played: Maybe<J.Core>, +before: J.Core, +any: Bool, +count: U32, +ticks: U32, +at: U32) -> Play:
  match played:
    case None{}: Play{False{}, before, True{}, ticks, at}
    case Some{+core}: Bool.pick(Play, U32.is_eq(at, count), Play{any, core, False{}, 1, 0}, Play{any, core, True{}, (ticks + 1 : U32), at})

def play.rest(+list: J.AutomationEventList, +core: J.Core, +ticks: U32, +at: U32) -> Play:
  J.AutomationEventList{_, +count, +events} = list
  +rest = List.drop(&2, J.AutomationEvent, events, U32.to_nat(at))
  +now = due.from(rest, ticks, due.head(rest, ticks))
  play.done(J.Core.play_all(now, Some{core}), core, Bool.not(U32.is_eq(size(rest, 0), 0)), count, ticks, (at + size(now, 0) : U32))

def play.list(list: Maybe<J.AutomationEventList>, +core: J.Core, +ticks: U32, +at: U32) -> Play:
  match list:
    case None{}: Play{False{}, core, True{}, ticks, at}
    case Some{+l}: play.rest(l, core, ticks, at)

# if (eventPlaying): this frame's events to PlayAutomationEvent, then playFrameCounter++.
def play(playing: Bool, +core: J.Core, +ticks: U32, +at: U32) -> Play:
  match playing:
    case False{}: Play{True{}, core, False{}, ticks, at}
    case True{}: play.list(J.Core.automation_event_list(core), core, ticks, at)

# The map's corners on screen ((1000, 600) and (0, 0), the fmaxf and fminf of the elements) pull the offset back inside.
def camera.in(+target: M.Vector2, +rotation: F32, +zoom: F32, +max: M.Vector2, +min: M.Vector2) -> Cam:
  M.Vector2{+ax, +ay} = max
  M.Vector2{+bx, +by} = min
  +x1 = Bool.pick(F32, (ax < 800.0 : F32), (800.0 - (ax - (800.0 / 2.0)) : F32), (800.0 / 2.0 : F32))
  +y1 = Bool.pick(F32, (ay < 450.0 : F32), (450.0 - (ay - (450.0 / 2.0)) : F32), (450.0 / 2.0 : F32))
  +x2 = Bool.pick(F32, (bx > 0.0 : F32), ((800.0 / 2.0) - bx : F32), x1)
  +y2 = Bool.pick(F32, (by > 0.0 : F32), ((450.0 / 2.0) - by : F32), y1)
  Cam{True{}, J.Camera2D{M.Vector2{x2, y2}, target, rotation, zoom}}

def camera.at(+target: M.Vector2, +rotation: F32, +zoom: F32, max: Maybe<M.Vector2>, min: Maybe<M.Vector2>) -> Cam:
  match max min:
    case Some{+a} Some{+b}: camera.in(target, rotation, zoom, a, b)
    case _ _: Cam{False{}, J.Camera2D{center(), target, rotation, zoom}}

# camera.target = player.position; the offset centered; the wheel zooms within [0.25, 3]; GetWorldToScreen2D of the map's corners.
def camera.update(+libm: M.Libm, +core: J.Core, +camera: J.Camera2D, +position: M.Vector2) -> Cam:
  J.Camera2D{_, _, +rotation, +zoom} = camera
  +wheel = (zoom + J.Input.get_mouse_wheel_move(core) * 0.05 : F32)
  +clamped = Bool.pick(F32, (wheel > 3.0 : F32), 3.0, Bool.pick(F32, (wheel < 0.25 : F32), 0.25, wheel))
  +centered = {J.Camera2D{center(), position, rotation, clamped} : J.Camera2D}
  camera.at(position, rotation, clamped, J.Camera.world_to_screen_2d_for(M.Uncontracted{}, libm, M.Vector2{1000.0, 600.0}, centered),
    J.Camera.world_to_screen_2d_for(M.Uncontracted{}, libm, M.Vector2{0.0, 0.0}, centered))

def recorded.of(list: Maybe<J.AutomationEventList>) -> U32:
  match list:
    case None{}: 0
    case Some{J.AutomationEventList{_, count, _}}: count

# aelist.count.
def recorded(+core: J.Core) -> U32:
  recorded.of(J.Core.automation_event_list(core))

# if (eventRecording || eventPlaying) frameCounter++; else frameCounter = 0.
def update.counted(+valid: Bool, +core: J.Core, +dir: String, +player: Player, +camera: J.Camera2D, +recording: Bool, +playing: Bool, +frames: U32, +ticks: U32, +at: U32, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  IO.pure(J.Core & (State & J.Frame), (core, (State{valid, dir, player, camera, recording, playing, Bool.pick(U32, recording || playing, (frames + 1 : U32), 0), ticks, at}, frame)))

# ExportAutomationEventList(aelist, "automation.rae"); eventRecording = false.
def update.exported(list: Maybe<J.AutomationEventList>, +valid: Bool, +core: J.Core, +dir: String, +player: Player, +camera: J.Camera2D, +playing: Bool, +frames: U32, +ticks: U32, +at: U32,
    frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match list:
    case None{}: update.counted(False{}, core, dir, player, camera, False{}, playing, frames, ticks, at, frame)
    case Some{+l}: IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, J.Core & (State & J.Frame), J.AutomationEventList.export(l, dir ++ "automation.rae"),
      written => update.counted(valid, core, dir, player, camera, False{}, playing, frames, ticks, at, frame))

# StartAutomationEventRecording(); eventRecording = true.
def update.started(started: Maybe<J.Core>, +valid: Bool, +before: J.Core, +dir: String, +player: Player, +camera: J.Camera2D, +playing: Bool, +frames: U32, +ticks: U32, +at: U32,
    frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match started:
    case None{}: update.counted(False{}, before, dir, player, camera, False{}, playing, frames, ticks, at, frame)
    case Some{+core}: update.counted(valid, core, dir, player, camera, True{}, playing, frames, ticks, at, frame)

# 0: nothing; 1: S while recording stops it and exports the list; 2: S starts a recording at base frame 180;
# 3: A plays the list from a reset scene (the next frame).
def update.key(kind: U32, +valid: Bool, +core: J.Core, +dir: String, +player: Player, +camera: J.Camera2D, +recording: Bool, +playing: Bool, +frames: U32, +ticks: U32, +at: U32,
    frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match kind:
    case 0: update.counted(valid, core, dir, player, camera, recording, playing, frames, ticks, at, frame)
    case 1: update.exported(J.Core.automation_event_list(J.Core.stop_automation_event_recording(core)), valid, J.Core.stop_automation_event_recording(core), dir, player, camera, playing,
      frames, ticks, at, frame)
    case 2: update.started(J.Core.start_automation_event_recording(J.Core.set_automation_event_base_frame(core, 180)), valid, core, dir, player, camera, playing, frames, ticks, at, frame)
    case _: update.counted(valid, core, dir, player.start(), camera.start(), False{}, True{}, frames, 0, 0, frame)

# Events management: S toggles the recording unless events are playing; else A plays a list that has events, unless one is being recorded.
def update.managed(+cam: Cam, +valid: Bool, +core: J.Core, +dir: String, +player: Player, +recording: Bool, +playing: Bool, +frames: U32, +ticks: U32, +at: U32, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  Cam{+seen, +camera} = cam
  +kind = Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_S()), Bool.pick(U32, playing, 0, Bool.pick(U32, recording, 1, 2)),
    Bool.pick(U32, J.Input.is_key_pressed(core, J.KeyboardKey.KEY_A()) && Bool.not(recording) && (recorded(core) > 0 : U32), 3, 0))
  update.key(kind, valid && seen, core, dir, player, camera, recording, playing, frames, ticks, at, frame)

# The camera follows with the Core the played events left (the wheel).
def update.played(+play: Play, +valid: Bool, +libm: M.Libm, +dir: String, +player: Player, +camera: J.Camera2D, +recording: Bool, +frames: U32, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  Play{+ok, +core, +playing, +ticks, +at} = play
  Player{+position, _, _} = player
  update.managed(camera.update(libm, core, camera, position), valid && ok, core, dir, player, recording, playing, frames, ticks, at, frame)

# The player; R resets him and the camera; the events playing.
def update.scene(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  State{+valid, +dir, +player, +camera, +recording, +playing, +frames, +ticks, +at} = state
  +reset = J.Input.is_key_pressed(core, J.KeyboardKey.KEY_R())
  update.played(play(playing, core, ticks, at), valid, libm, dir, Bool.pick(Player, reset, player.start(), player.update(core, player)), Bool.pick(J.Camera2D, reset, camera.start(), camera),
    recording, frames, frame)

# The dropped list replaces the Core's; eventRecording = false; it plays from a reset scene.
def with.list(+state: State) -> State:
  State{+valid, +dir, _, _, _, _, +frames, _, _} = state
  State{valid, dir, player.start(), camera.start(), False{}, True{}, frames, 0, 0}

def update.loaded(list: Maybe<J.AutomationEventList>, +libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match list:
    case None{}: update.scene(libm, core, with.list(state), J.Frame.refuse(frame))
    case Some{+l}: update.scene(libm, J.Core.set_automation_event_list(core, l), with.list(state), frame)

# aelist = LoadAutomationEventList(droppedFiles.paths[0]) for a .txt or .rae file.
def update.matched(matches: Bool, +path: String, +libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match matches:
    case False{}: update.scene(libm, core, state, frame)
    case True{}: IO.bind(Maybe<J.AutomationEventList>, J.Core & (State & J.Frame), J.AutomationEventList.load(path), l => update.loaded(l, libm, core, state, frame))

# IsFileExtension(droppedFiles.paths[0], ".txt;.rae") (None: an extension that overflows raylib's buffer).
def update.extension(matches: Maybe<Bool>, +path: String, +libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match matches:
    case None{}: update.scene(libm, core, state, J.Frame.refuse(frame))
    case Some{+m}: update.matched(m, path, libm, core, state, frame)

def update.first(paths: +List<String>, +libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match paths:
    case Nil{}: update.scene(libm, core, state, frame)
    case Con{+path, _}: update.extension(J.Files.has_extension(path, ".txt;.rae"), path, libm, core, state, frame)

# droppedFiles = LoadDroppedFiles(); its first path; UnloadDroppedFiles(droppedFiles).
def update.files(+files: J.FilePathList, +libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  J.FilePathList{_, +paths} = files
  update.first(paths, libm, J.Core.unload_dropped_files(core, files), state, frame)

# if (IsFileDropped()): the dropped files' first path.
def update.dropped(dropped: Bool, +libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  match dropped:
    case False{}: update.scene(libm, core, state, frame)
    case True{}: update.files(J.Core.load_dropped_files(core), libm, core, state, frame)

def update(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> IO(J.Core & (State & J.Frame)):
  update.dropped(J.Core.is_file_dropped(core), libm, core, state, frame)

def rects(list: +List<Item>, frame: J.Frame) -> J.Frame:
  match list:
    case Nil{}: frame
    case Con{+item, rest}:
      Item{+rect, _, +color} = item
      rects(rest, J.Draw.rectangle_rec(frame, rect, color))

def label(text: Maybe<String>, frame: J.Frame, +color: U32) -> J.Frame:
  match text:
    case None{}: J.Frame.refuse(frame)
    case Some{t}: J.Draw.text(frame, t, 50.0, 170.0, 10.0, color)

# The text blinks: shown while (frameCounter/15)%2 is 1.
def blink(shown: Bool, text: Maybe<String>, frame: J.Frame, +color: U32) -> J.Frame:
  match shown:
    case False{}: frame
    case True{}: label(text, frame, color)

# 1: the recording indicator with aelist.count; 2: the playing one with currentPlayFrame; 0: none.
def indicator(kind: U32, +libm: M.Libm, +count: U32, +frames: U32, +at: U32, frame: J.Frame) -> J.Frame:
  match kind:
    case 0: frame
    case 1:
      f1 = J.Draw.rectangle_lines(J.Draw.rectangle(frame, 10.0, 160.0, 290.0, 30.0, J.Color.with_alpha(J.Color.RED(), 0.3)), 10.0, 160.0, 290.0, 30.0, J.Color.with_alpha(J.Color.MAROON(), 0.8))
      blink(U32.is_eq(((frames / 15) % 2 : U32), 1), J.Text.format("RECORDING EVENTS... [%i]", [J.TextInt{count}]), J.Draw.circle_for(libm, f1, 30.0, 175.0, 10.0, J.Color.MAROON()), J.Color.MAROON())
    case _:
      f1 = J.Draw.rectangle_lines(J.Draw.rectangle(frame, 10.0, 160.0, 290.0, 30.0, J.Color.with_alpha(J.Color.LIME(), 0.3)), 10.0, 160.0, 290.0, 30.0, J.Color.with_alpha(J.Color.DARKGREEN(), 0.8))
      blink(U32.is_eq(((frames / 15) % 2 : U32), 1), J.Text.format("PLAYING RECORDED EVENTS... [%i]", [J.TextInt{at}]),
        J.Draw.triangle(f1, M.Vector2{20.0, 165.0}, M.Vector2{20.0, 185.0}, M.Vector2{40.0, 175.0}, J.Color.DARKGREEN()), J.Color.DARKGREEN())

def controls(frame: J.Frame) -> J.Frame:
  f1 = J.Draw.rectangle_lines(J.Draw.rectangle(frame, 10.0, 10.0, 290.0, 145.0, J.Color.with_alpha(J.Color.SKYBLUE(), 0.5)), 10.0, 10.0, 290.0, 145.0, J.Color.with_alpha(J.Color.BLUE(), 0.8))
  f2 = J.Draw.text(f1, "Controls:", 20.0, 20.0, 10.0, J.Color.BLACK())
  f3 = J.Draw.text(f2, "- RIGHT | LEFT: Player movement", 30.0, 40.0, 10.0, J.Color.DARKGRAY())
  f4 = J.Draw.text(f3, "- SPACE: Player jump", 30.0, 60.0, 10.0, J.Color.DARKGRAY())
  f5 = J.Draw.text(f4, "- R: Reset game state", 30.0, 80.0, 10.0, J.Color.DARKGRAY())
  f6 = J.Draw.text(f5, "- S: START/STOP RECORDING INPUT EVENTS", 30.0, 110.0, 10.0, J.Color.BLACK())
  J.Draw.text(f6, "- A: REPLAY LAST RECORDED INPUT EVENTS", 30.0, 130.0, 10.0, J.Color.BLACK())

def draw.valid(valid: Bool, +libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Frame:
  match valid:
    case False{}: J.Frame.refuse(frame)
    case True{}:
      State{_, _, +player, +camera, +recording, +playing, +frames, _, +at} = state
      Player{+position, _, _} = player
      M.Vector2{+x, +y} = position
      f1 = rects(items(), J.Frame.begin_mode_2d_for(libm, J.Frame.clear_background(frame, J.Color.LIGHTGRAY()), camera))
      f2 = J.Frame.end_mode_2d(J.Draw.rectangle_rec(f1, J.Rectangle{(x - 20.0 : F32), (y - 40.0 : F32), 40.0, 40.0}, J.Color.RED()))
      indicator(Bool.pick(U32, recording, 1, Bool.pick(U32, playing, 2, 0)), libm, recorded(core), frames, at, controls(f2))

def draw(+libm: M.Libm, +core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, _, _, _, _, _, _, _, _} = state
  (core, (state, draw.valid(valid, libm, core, state, frame)))

# The main loop's body; libm is the sinf/cosf profile of the camera matrices and DrawCircle. Nothing follows EndDrawing in the loop.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Effects{core => state => frame => update(libm, core, state, frame), core => state => frame => draw(libm, core, state, frame),
    core => state => frame => IO.pure(J.Core & (State & J.Frame), (core, (state, frame)))}

# After InitWindow(800, 450): the player, the camera on him, aelist = LoadAutomationEventList(0); SetAutomationEventList(&aelist); SetTargetFPS(60).
def setup(+dir: String, +core: J.Core, frame: J.Frame) -> IO(J.Core & (J.Frame & State)):
  IO.pure(J.Core & (J.Frame & State), (J.Core.set_target_fps(J.Core.set_automation_event_list(core, J.AutomationEventList.new()), 60),
    (frame, State{True{}, dir, player.start(), camera.start(), False{}, False{}, 0, 0, 0})))

def run(args: List<String>) -> IO(Unit):
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - automation events", 800, 450, J.Desktop.frames_arg(args),
    core => frame => setup("", core, frame))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
