# raylib [core] example - directory files, ported to Jonlib.
# Adapted from raylib 6.2 examples/core/core_directory_files.c (zlib/libpng,
# Copyright (c) 2025 Hugo ARNAL (@hugoarnal)); see LICENSES/raylib.txt.
#
# The working directory's subdirectories and .png and .c files in a raygui
# list view (LoadDirectoryFilesEx with the filter "DIRS*;.png;.c"); the "<"
# button goes to the directory above, and a click on a directory of the list
# goes into it (raylib 6.2: 6.0 listed only the files and its "<" listed
# everything above); either lists that directory with the same filter and
# resets the list view.
#
# Base has no directory listing and no working directory (docs/FILES.md), so
# the port is handed what the example would read: a list of directories, the
# working directory first, each with its entries in the order readdir gives
# them (without "." and "..") and whether each is a file (IsPathFile; any
# other entry is a directory, DirectoryExists of it). The example's own code
# runs on them: LoadDirectoryFilesEx's filter (a file by IsFileExtension, a
# directory by "DIRS*"; an entry whose path does not fit raylib's 4096 bytes
# is skipped), GetPrevDirectoryPath. A frame is refused, and every later one,
# where the example goes to a directory it was not handed or a path does not
# fit the example's 1024-byte buffer or GetPrevDirectoryPath's 4096-byte one.
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

# files.paths, whether each is a directory, and whether they could be made.
type Paths is Data:
  Paths{valid: Bool, list: +List<String>, dirs: +List<Bool>}

# valid: no refusal so far. directory and files are the example's (dirs:
# DirectoryExists of each file); back is btnBackPressed, the button's answer
# in the frame before; scroll, active and focused are the list view's three
# ints as words (-1 is 4294967295).
type State is Data:
  State{valid: Bool, gui: G.Gui, listings: +List<Listing>, directory: String, files: +List<String>, dirs: +List<Bool>, back: Bool, scroll: U32, active: U32, focused: U32}

# What ScanDirectoryFiles does with an entry under FILE_FILTER: 0 leaves it
# out, 1 takes it, 2 is a refusal. A file is taken where IsFileExtension
# matches the filter's list, a directory always ("DIRS*").
def entry.kind(matched: Maybe<Bool>, +file: Bool) -> U32:
  match matched:
    case None{}: Bool.pick(U32, file, 2, 1)
    case Some{+yes}: Bool.pick(U32, file, Bool.pick(U32, yes, 1, 0), 1)

# The paths of a directory's entries, basePath/d_name each, in their order;
# a path of 4096 bytes or more is left out (raylib warns and skips it).
def scan(entries: +List<Entry>, +directory: String, +valid: Bool, +acc: +List<String>, +dirs: +List<Bool>) -> Paths:
  match entries:
    case Nil{}: Paths{valid, List.reverse(&2, String, acc), List.reverse(&2, Bool, dirs)}
    case Con{Entry{+name, +file}, +rest}:
      +path = directory ++ "/" ++ name
      +kind = Bool.pick(U32, Nat.is_lt(String.length(path), 4096n), entry.kind(J.Files.has_extension(path, "DIRS*;.png;.c"), file), 0)
      scan(rest, directory, valid && U32.is_ne(kind, 2), Bool.pick(+List<String>, U32.is_eq(kind, 1), Con{path, acc}, acc),
        Bool.pick(+List<Bool>, U32.is_eq(kind, 1), Con{Bool.not(file), dirs}, dirs))

# LoadDirectoryFilesEx(directory, FILE_FILTER, false) for a directory the
# port was handed; not valid for any other.
def load(listings: +List<Listing>, +directory: String) -> Paths:
  match listings:
    case Nil{}: Paths{False{}, Nil{}, Nil{}}
    case Con{Listing{+path, +entries}, +rest}:
      Bool.pick(Paths, String.eq(path, directory), scan(entries, directory, True{}, Nil{}, Nil{}), load(rest, directory))

def Paths.valid(paths: Paths) -> Bool:
  Paths{valid, _, _} = paths
  valid

def Paths.list(paths: Paths) -> +List<String>:
  Paths{_, list, _} = paths
  list

def Paths.dirs(paths: Paths) -> +List<Bool>:
  Paths{_, _, dirs} = paths
  dirs

# The directory fits the example's char directory[MAX_FILEPATH_SIZE].
def fits(+directory: String) -> Bool:
  Nat.is_lt(String.length(directory), 1024n)

# TextCopy(directory, target); UnloadDirectoryFiles(files); files =
# LoadDirectoryFilesEx(directory, FILE_FILTER, false); listScrollIndex = 0,
# listItemActive = -1, listItemFocused = -1.
def moved(+valid: Bool, +gui: G.Gui, +listings: +List<Listing>, +target: String) -> State:
  +paths = load(listings, target)
  State{valid && fits(target) && Paths.valid(paths), gui, listings, target, Paths.list(paths), Paths.dirs(paths), False{}, 0, 4294967295, 4294967295}

# The item at `index` (-1 or past the list: none).
def item.path(paths: +List<String>, +index: U32) -> Maybe<String>:
  match paths:
    case Nil{}: None{}
    case Con{+path, rest}: Bool.pick(Maybe<String>, U32.is_eq(index, 0), Some{path}, item.path(rest, (index - 1 : U32)))

def item.dir(dirs: +List<Bool>, +index: U32) -> Bool:
  match dirs:
    case Nil{}: False{}
    case Con{+dir, rest}: (U32.is_eq(index, 0) && dir) || (U32.is_ne(index, 0) && item.dir(rest, (index - 1 : U32)))

# if ((listItemActive >= 0) && (listItemActive < (int)files.count) &&
# DirectoryExists(files.paths[listItemActive])): into that directory.
def update.entered(+core: J.Core, +state: State, found: Maybe<String>) -> J.Core & State:
  State{+valid, +gui, +listings, _, _, _, _, _, _, _} = state
  match found:
    case None{}: (core, state)
    case Some{+path}: (core, moved(valid, gui, listings, path))

def update.into(+core: J.Core, +state: State) -> J.Core & State:
  State{+valid, _, _, _, +files, +dirs, _, _, +active, _} = state
  update.entered(core, state, Bool.pick(Maybe<String>, valid && (active < 2147483648 : U32) && item.dir(dirs, active), item.path(files, active), None{}))

def update.back(previous: Maybe<String>, +core: J.Core, +gui: G.Gui, +listings: +List<Listing>, +scroll: U32, +active: U32, +focused: U32) -> J.Core & State:
  match previous:
    case None{}: (core, State{False{}, gui, listings, "", Nil{}, Nil{}, False{}, scroll, active, focused})
    case Some{+directory}: update.into(core, moved(True{}, gui, listings, directory))

def update.at(go: Bool, +core: J.Core, +valid: Bool, +gui: G.Gui, +listings: +List<Listing>, +directory: String, +files: +List<String>, +dirs: +List<Bool>, +scroll: U32, +active: U32,
    +focused: U32) -> J.Core & State:
  match go:
    case False{}: update.into(core, State{valid, gui, listings, directory, files, dirs, False{}, scroll, active, focused})
    case True{}: update.back(J.Files.previous_directory_given(directory, False{}), core, gui, listings, scroll, active, focused)

# if (btnBackPressed): TextCopy(directory, GetPrevDirectoryPath(directory))
# and the directory listed; then a directory chosen in the list.
def update(+core: J.Core, state: State) -> J.Core & State:
  State{+valid, +gui, +listings, +directory, +files, +dirs, +back, +scroll, +active, +focused} = state
  update.at(valid && back, core, valid, gui, listings, directory, files, dirs, scroll, active, focused)

def draw.listed(rest: G.Gui & G.Gui.Listed, frame: J.Frame, +core: J.Core, +listings: +List<Listing>, +directory: String, +files: +List<String>, +dirs: +List<Bool>, +back: Bool) -> J.Core & (State & J.Frame):
  (+gui, +listed) = rest
  G.GuiListed{+scroll, +active, +focused} = listed
  (core, (State{True{}, gui, listings, directory, files, dirs, back, scroll, active, focused}, frame))

def draw.list(r: J.Frame & (G.Gui & G.Gui.Listed), +core: J.Core, +listings: +List<Listing>, +directory: String, +files: +List<String>, +dirs: +List<Bool>, +back: Bool) -> J.Core & (State & J.Frame):
  (frame, rest) = r
  draw.listed(rest, frame, core, listings, directory, files, dirs, back)

# The label with a TEXT_SIZE of twice the font's base size, then the list
# view with its texts at the left, 40 pixels in.
def draw.button(r: J.Frame & Bool, +core: J.Core, +gui: G.Gui, +listings: +List<Listing>, +directory: String, +files: +List<String>, +dirs: +List<Bool>, +scroll: U32, +active: U32, +focused: U32) -> J.Core & (State & J.Frame):
  (frame, +back) = r
  +base = G.Gui.font_base_size(gui)
  f1 = G.Gui.label(G.Gui.set_style(gui, 0, 16, (base * 2 : U32)), frame, J.Rectangle{98.0, 10.0, 700.0, 28.0}, directory)
  draw.list(G.Gui.list_view_ex(G.Gui.set_style(G.Gui.set_style(G.Gui.set_style(gui, 0, 16, base), 12, 14, 0), 12, 13, 40), core, f1,
    J.Rectangle{0.0, 50.0, U32.to_f32(J.Core.get_screen_width(core)), (U32.to_f32(J.Core.get_screen_height(core)) - 50.0 : F32)}, files, scroll, active, focused), core, listings, directory, files, dirs, back)

def draw.valid(valid: Bool, +core: J.Core, +state: State, +gui: G.Gui, +listings: +List<Listing>, +directory: String, +files: +List<String>, +dirs: +List<Bool>, +scroll: U32, +active: U32, +focused: U32,
    frame: J.Frame) -> J.Core & (State & J.Frame):
  match valid:
    case False{}: (core, (state, J.Frame.refuse(frame)))
    case True{}:
      draw.button(G.Gui.button(gui, core, J.Frame.clear_background(frame, J.Color.RAYWHITE()), J.Rectangle{40.0, 10.0, 48.0, 28.0}, "<"), core, gui, listings, directory, files, dirs, scroll, active, focused)

def draw(+core: J.Core, +state: State, frame: J.Frame) -> J.Core & (State & J.Frame):
  State{+valid, +gui, +listings, +directory, +files, +dirs, _, +scroll, +active, +focused} = state
  draw.valid(valid, core, state, gui, listings, directory, files, dirs, scroll, active, focused, frame)

# The main loop's body; nothing in it follows the libm profile.
def program(+libm: M.Libm) -> J.Program<State>:
  J.Program{core => state => update(core, state), core => state => frame => draw(core, state, frame)}

# The working directory is the first directory handed.
def setup.state(first: +List<Listing>, +listings: +List<Listing>) -> State:
  match first:
    case Nil{}: State{False{}, G.Gui.new(), listings, "", Nil{}, Nil{}, False{}, 0, 4294967295, 4294967295}
    case Con{Listing{+path, _}, _}: moved(True{}, G.Gui.new(), listings, path)

# After InitWindow(800, 450): strcpy(directory, GetWorkingDirectory()),
# files = LoadDirectoryFilesEx(directory, FILE_FILTER, false), nothing
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
