# raylib [core] example - directory files, ported to Jonlib.
# Adapted from raylib 6.0 examples/core/core_directory_files.c (zlib/libpng,
# Copyright (c) 2025 Hugo ARNAL (@hugoarnal)); see LICENSES/raylib.txt.
#
# The working directory's .png and .c files in a raygui list view; the "<"
# button goes to the directory above and lists everything in it.
#
# Base has no directory listing and no working directory (docs/FILES.md), so
# the port is handed what the example would read: a list of directories, the
# working directory first, each with its entries in the order readdir gives
# them (without "." and "..") and whether each is a file (IsPathFile). The
# example's own code runs on them: LoadDirectoryFilesEx's filter,
# LoadDirectoryFiles, GetPrevDirectoryPath. A frame is refused, and every
# later one, where the example goes to a directory it was not handed, a path
# does not fit the example's 1024-byte buffer or raylib's 4096-byte one, or
# IsFileExtension would write past its buffer (an extension of 16 bytes or
# more).
import Base
import ../jonlib.bend as J
import ../jonmath.bend as M
import ../jongui.bend as G

# A directory entry: d_name and IsPathFile of its path.
type Entry is Data:
  Entry{name: String, file: Bool}

# A directory the port was handed: its path and its entries.
type Listing is Data:
  Listing{path: String, entries: +List<Entry>}

# files.paths, and whether they could be made.
type Paths is Data:
  Paths{valid: Bool, list: +List<String>}

# valid: no refusal so far. directory and files are the example's; back is
# btnBackPressed, the button's answer in the frame before; scroll, active
# and focused are the list view's three ints as words (-1 is 4294967295).
type State is Data:
  State{valid: Bool, gui: G.Gui, listings: +List<Listing>, directory: String, files: +List<String>, back: Bool, scroll: U32, active: U32, focused: U32}

# What ScanDirectoryFiles does with an entry: 0 leaves it out, 1 takes it, 2
# is a refusal. With the example's filter (".png;.c") a file is taken where
# IsFileExtension says so and a directory is not; without one
# (LoadDirectoryFiles, "*.*") every entry is taken.
def entry.kind(matched: Maybe<Bool>, +filtered: Bool, +file: Bool) -> U32:
  match matched:
    case None{}: Bool.pick(U32, filtered && file, 2, Bool.pick(U32, filtered, 0, 1))
    case Some{+yes}: Bool.pick(U32, filtered, Bool.pick(U32, file && yes, 1, 0), 1)

# The paths of a directory's entries, basePath/d_name each, in their order.
def scan(entries: +List<Entry>, +directory: String, +filtered: Bool, +valid: Bool, +acc: +List<String>) -> Paths:
  match entries:
    case Nil{}: Paths{valid, List.reverse(&2, String, acc)}
    case Con{Entry{+name, +file}, +rest}:
      +path = directory ++ "/" ++ name
      +kind = Bool.pick(U32, Nat.is_lt(String.length(path), 4095n), entry.kind(J.Files.has_extension(path, ".png;.c"), filtered, file), 2)
      scan(rest, directory, filtered, valid && U32.is_ne(kind, 2), Bool.pick(+List<String>, U32.is_eq(kind, 1), Con{path, acc}, acc))

# LoadDirectoryFilesEx(directory, filter, false) for a directory the port
# was handed; not valid for any other.
def load(listings: +List<Listing>, +directory: String, +filtered: Bool) -> Paths:
  match listings:
    case Nil{}: Paths{False{}, Nil{}}
    case Con{Listing{+path, +entries}, +rest}:
      Bool.pick(Paths, String.eq(path, directory), scan(entries, directory, filtered, True{}, Nil{}), load(rest, directory, filtered))

def Paths.valid(paths: Paths) -> Bool:
  Paths{valid, _} = paths
  valid

def Paths.list(paths: Paths) -> +List<String>:
  Paths{_, list} = paths
  list

# The directory fits the example's char directory[MAX_FILEPATH_SIZE].
def fits(+directory: String) -> Bool:
  Nat.is_lt(String.length(directory), 1024n)

def update.back(previous: Maybe<String>, +core: J.Core, +gui: G.Gui, +listings: +List<Listing>, +scroll: U32, +active: U32, +focused: U32) -> J.Core & State:
  match previous:
    case None{}: (core, State{False{}, gui, listings, "", Nil{}, False{}, scroll, active, focused})
    case Some{+directory}:
      +paths = load(listings, directory, False{})
      (core, State{fits(directory) && Paths.valid(paths), gui, listings, directory, Paths.list(paths), False{}, scroll, active, focused})

def update.at(go: Bool, +core: J.Core, +valid: Bool, +gui: G.Gui, +listings: +List<Listing>, +directory: String, +files: +List<String>, +scroll: U32, +active: U32, +focused: U32) -> J.Core & State:
  match go:
    case False{}: (core, State{valid, gui, listings, directory, files, False{}, scroll, active, focused})
    case True{}: update.back(J.Files.previous_directory_given(directory, False{}), core, gui, listings, scroll, active, focused)

# if (btnBackPressed): TextCopy(directory, GetPrevDirectoryPath(directory))
# and files = LoadDirectoryFiles(directory).
def update(+core: J.Core, state: State) -> J.Core & State:
  State{+valid, +gui, +listings, +directory, +files, +back, +scroll, +active, +focused} = state
  update.at(valid && back, core, valid, gui, listings, directory, files, scroll, active, focused)

def draw.listed(rest: G.Gui & G.Gui.Listed, frame: J.Frame, +core: J.Core, +listings: +List<Listing>, +directory: String, +files: +List<String>, +back: Bool) -> J.Core & (State & J.Frame):
  (+gui, +listed) = rest
  G.GuiListed{+scroll, +active, +focused} = listed
  (core, (State{True{}, gui, listings, directory, files, back, scroll, active, focused}, frame))

def draw.list(r: J.Frame & (G.Gui & G.Gui.Listed), +core: J.Core, +listings: +List<Listing>, +directory: String, +files: +List<String>, +back: Bool) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.listed(rest, frame, core, listings, directory, files, back)

# The label with a TEXT_SIZE of twice the font's base size, then the list
# view with its texts at the left, 40 pixels in.
def draw.button(r: J.Frame & Bool, +core: J.Core, +gui: G.Gui, +listings: +List<Listing>, +directory: String, +files: +List<String>, +scroll: U32, +active: U32, +focused: U32) -> J.Core & (State & J.Frame):
  (frame, +back) = r
  +base = G.Gui.font_base_size(gui)
  f1 = G.Gui.label(G.Gui.set_style(gui, 0, 16, (base * 2 : U32)), frame, J.Rectangle{98.0, 10.0, 700.0, 28.0}, directory)
  draw.list(G.Gui.list_view_ex(G.Gui.set_style(G.Gui.set_style(G.Gui.set_style(gui, 0, 16, base), 12, 14, 0), 12, 13, 40), core, f1,
    J.Rectangle{0.0, 50.0, U32.to_f32(J.Core.get_screen_width(core)), (U32.to_f32(J.Core.get_screen_height(core)) - 50.0 : F32)}, files, scroll, active, focused), core, listings, directory, files, back)

def draw.valid(valid: Bool, +core: J.Core, +state: State, +gui: G.Gui, +listings: +List<Listing>, +directory: String, +files: +List<String>, +scroll: U32, +active: U32, +focused: U32, frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid:
    case False{}: (core, (state, J.Frame.refuse(frame)))
    case True{}:
      draw.button(G.Gui.button(gui, core, J.Frame.clear_background(frame, J.Color.RAYWHITE()), J.Rectangle{40.0, 10.0, 48.0, 28.0}, "<"), core, gui, listings, directory, files, scroll, active, focused)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +gui, +listings, +directory, +files, _, +scroll, +active, +focused} = state
  draw.valid(valid, core, state, gui, listings, directory, files, scroll, active, focused, frame)

# The main loop's body; nothing in it follows the libm profile.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

def setup.at(+listings: +List<Listing>, +directory: String, +paths: Paths) -> State:
  State{fits(directory) && Paths.valid(paths), G.Gui.new(), listings, directory, Paths.list(paths), False{}, 0, 4294967295, 4294967295}

# The working directory is the first directory handed.
def setup.state(first: +List<Listing>, +listings: +List<Listing>) -> State:
  match first:
    case Nil{}: State{False{}, G.Gui.new(), listings, "", Nil{}, False{}, 0, 4294967295, 4294967295}
    case Con{Listing{+path, _}, _}: setup.at(listings, path, load(listings, path, True{}))

# After InitWindow(800, 450): strcpy(directory, GetWorkingDirectory()),
# files = LoadDirectoryFilesEx(directory, ".png;.c", false), nothing
# selected, SetTargetFPS(60).
def setup(+listings: +List<Listing>, +core: J.Core, frame: J.Frame) -> J.Core & (J.Frame & State):
  (J.Core.set_target_fps(core, 60), (frame, setup.state(listings, listings)))

# The working directory and its entries from the command line:
# "--directory DIR", then "--file NAME" or "--dir NAME" for each entry in
# readdir's order, and "--frames N".
def options(args: List<String>, +mode: U32, +dir: String, +frames: U32, +entries: +List<Entry>) -> (String & U32) & +List<Entry>:
  match args:
    case Nil{}: ((dir, frames), List.reverse(&2, Entry, entries))
    case Con{+a, rest}:
      match mode:
        case 1: options(rest, 0, a, frames, entries)
        case 2: options(rest, 0, dir, J.Desktop.frames_arg(["--frames", a]), entries)
        case 3: options(rest, 0, dir, frames, Con{Entry{a, True{}}, entries})
        case 4: options(rest, 0, dir, frames, Con{Entry{a, False{}}, entries})
        case _:
          options(rest, Bool.pick(U32, String.eq(a, "--directory"), 1, Bool.pick(U32, String.eq(a, "--frames"), 2, Bool.pick(U32, String.eq(a, "--file"), 3, Bool.pick(U32, String.eq(a, "--dir"), 4, 0)))),
            dir, frames, entries)

def run.with(named: String & U32, +entries: +List<Entry>) -> IO(Unit):
  (+dir, +limit) = named
  J.Desktop.run(~State, ~program(M.AppleLibm{}), ~M.AppleLibm{}, "raylib [core] example - directory files", 800, 450, limit,
    core => frame => IO.pure(J.Core & (J.Frame & State), setup([Listing{dir, entries}], core, frame)))

def run.parsed(parsed: (String & U32) & +List<Entry>) -> IO(Unit):
  (named, +entries) = parsed
  run.with(named, entries)

def run(args: List<String>) -> IO(Unit):
  run.parsed(options(args, 0, ".", 0, Nil{}))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
