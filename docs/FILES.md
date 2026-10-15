# Files and paths

Jonlib adapts raylib 6.0's `rcore.c` path and file-data utilities as `Files.*`
in `jonlib.bend`. Paths and text are raylib byte strings: ASCII paths compare
byte for byte, and file text is read and written as characters 0..255, one per
byte, on every lane.

| Function | raylib | Contract |
|---|---|---|
| `Files.extension(path) -> Maybe<String>` | `GetFileExtension` | From the last `.` of the whole path; `None` when there is none or it is the first character. |
| `Files.name(path) -> String` | `GetFileName` | The text after the last `/` or `\`. |
| `Files.name_without_ext(path) -> String` | `GetFileNameWithoutExt` | The name, truncated to 255 bytes, cut at its last `.` past the first character. |
| `Files.directory(path) -> Maybe<String>` | `GetDirectoryPath` | `./` before paths without a drive letter or leading separator, then the path up to its last separator (`/` or `\` alone for a root file); paths of 1..4093 bytes, else `None` (raylib reads past an empty path and overflows its buffer). |
| `Files.previous_directory(path) -> Maybe<String>` | `GetPrevDirectoryPath` | Up to 3 bytes unchanged; otherwise the path up to its last separator, keeping a root `/` or `C:\`; `""` without a separator. Paths up to 4096 bytes. |
| `Files.has_extension(path, extensions) -> Maybe<Bool>` | `IsFileExtension` | ASCII-case-insensitive match against a `;`-separated list of at most 31 entries (the last keeps further separators); entries without a leading `.` compare without it. A file extension of 16+ bytes overflows raylib's buffer: `None`. |
| `Files.valid_name(name) -> Bool` | `IsFileNameValid` | Empty names are valid; `<>:"/\|?*`, control characters and all-period names are not. |
| `Files.exists(path) -> IO(Bool)` | `FileExists` | `access(F_OK)`, as `stat(2)` answers it (Base's `Path.stat`): a file that exists, readable or not, or a directory; a dangling link does not. |
| `Files.is_path_file(path) -> IO(Bool)` | `IsPathFile` | `stat(2)`, links followed: a regular file. |
| `Files.directory_exists(path) -> IO(Bool)` | `DirectoryExists` | `opendir` succeeds (Base's `Dir.read`): a directory that cannot be read is not one. |
| `Files.mod_time(path) -> IO(Nat)` | `GetFileModTime` | `st_mtime` in seconds, 0 where `stat` fails. A file modified before 1970 is 0 here, where raylib's `long` is negative. |
| `Files.rename(source, target) -> IO(U32)`, `Files.remove(path) -> IO(U32)` | `FileRename`, `FileRemove` | `rename(2)`'s or `remove(3)`'s result (a file, or an empty directory), -1 (4294967295) for a path `FileExists` does not see. |
| `Files.copy(source, target) -> IO(Maybe<U32>)` | `FileCopy` | The source's bytes, the target's directory (`GetDirectoryPath`) made where it is missing, then the bytes saved when there are any: 1 when `SaveFileData` succeeds, 0 when it fails or there was nothing to write, -1 when `MakeDirectory` fails; `None` where `GetDirectoryPath` overflows. |
| `Files.move(source, target) -> IO(Maybe<U32>)` | `FileMove` | -1 for a missing source; otherwise `FileCopy`, then `FileRemove` of the source only when the copy gave 0. A successful copy gives 1, which raylib takes as a failure: the source stays and the result is -1. |
| `Files.make_directory(path) -> IO(U32)` | `MakeDirectory` | -1 for an empty path, 0 for an existing directory; otherwise every prefix before a `/` or `\` (a `:` passes the character after it) is made where it is missing, then the path with those separators turned into `/`, mode 0777 under the umask; 0 when the path given is a directory then, -1 otherwise. |
| `Files.change_directory(path) -> IO(Bool)`, `Files.working_directory() -> IO(Maybe<String>)` | `ChangeDirectory`, `GetWorkingDirectory` | `chdir(2)`; `getcwd(3)` into raylib's 4095 bytes, `None` where it fails or the path does not fit. |
| `Files.application_directory() -> IO(String)` | `GetApplicationDirectory` | The running program's file (`/proc/self/exe`; the script on the JavaScript target) up to and with its last `/`, `"./"` where it is not found. |
| `Files.load_directory_files(path)`, `Files.load_directory_files_ex(path, filter, subdirs) -> IO(Maybe<FilePathList>)`, `Files.unload_directory_files(files)` | `LoadDirectoryFiles(Ex)`, `UnloadDirectoryFiles` | The paths `path/name` of a directory's entries in `readdir`'s order, a subdirectory's (with `subdirs`) right after it. `filter` `None` (or empty) is `NULL`: every regular file. Otherwise a regular file is listed for the `*.*` or `FILES*` tag or an extension of the list (`IsFileExtension`), anything else (a directory, or a path `stat` fails on) for `*.*` or `DIRS*`. A path of 4096 bytes or more is skipped and one of 4095 is cut to 4094 bytes, as `snprintf` leaves it. No directory gives no paths. `None` where `IsFileExtension`'s buffer overflows (an extension of 16+ bytes) or the cut would split a character. `LoadDirectoryFiles` is the `*.*` filter without subdirectories. |
| `Files.directory_file_count(path)`, `Files.directory_file_count_ex(path, filter, subdirs) -> IO(Maybe<U32>)` | `GetDirectoryFileCount(Ex)` | What the listing would hold, counted; the filter as given (an empty one counts nothing). |
| `System.open_url(url) -> IO(Unit)` | `OpenURL` | The reference platform's (`rcore_memory.c`): `system()` of `explorer "url"` through `/bin/sh` (Base's `Process.run`), its result unused; nothing for a URL with a `'`. |
| `Files.length(path) -> IO(U32)` | `GetFileLength` | The size in bytes; 0 when the file does not open. |
| `Files.load_data(path)` / `unload_data` | `LoadFileData` / `UnloadFileData` | Every byte, up to raylib's `INT_MAX` size, as `Result<&1, &1, Surface.IOError, +List<U32>>`; an existing empty file is an empty list (raylib: `NULL` with size 0). |
| `Files.save_data(path, bytes)` | `SaveFileData` | Writes every byte; values above 255 are `InvalidRequest` before opening. |
| `Files.load_text(path)` / `unload_text` | `LoadFileText` / `UnloadFileText` | Every byte as a character, including NULs. |
| `Files.save_text(path, text)` | `SaveFileText` | The text up to its first NUL; characters above 255 are `InvalidRequest`. |
| `Files.text_find_index(path, search) -> IO(Maybe<U32>)` | `FileTextFindIndex` | Byte index of the first occurrence in the text up to its first NUL; `None` when absent or the file is missing. An empty file, which raylib scans through a `NULL` text, is `None`. |
| `Files.text_replace(path, search, replacement) -> IO(Maybe<U32>)` | `FileTextReplace` | 0 when the file does not exist; otherwise `LoadFileText`, `TextReplaceAlloc` of its text up to the first NUL and `SaveFileText` of the result (so the file is rewritten even without a match, ending at the first NUL), answering 1 or 0. `None` where raylib passes a `NULL` text to `fprintf("%s")`: an empty or unreadable file and an empty search; also for characters above 255 in the result and `TextReplaceAlloc`'s int overflow. |
| `Core.is_file_dropped(core) -> Bool`, `Core.load_dropped_files(core) -> FilePathList`, `Core.unload_dropped_files(core, files)` | `IsFileDropped`, `LoadDroppedFiles`, `UnloadDroppedFiles` | `CORE.Window.dropFileCount` stays 0: the memory platform has no drop events and Base's windows report none, so `IsFileDropped` is false, `LoadDroppedFiles` is `FilePathList{0, []}` and unloading it frees nothing. A desktop platform with drop events would fill the list (Base gap, [DRIVER.md](DRIVER.md#gaps)). |
| `Files.data_as_code(bytes, path)` / `export_data_as_code(bytes, path)` | `ExportDataAsCode` | raylib's header text (banner, `NAME_DATA_SIZE`, 20 lower-case hex bytes per line) for 1..1048576 bytes and an ASCII basename of 1..200 characters; the name drops its last extension, upper-cases a-z and maps `.-?!+` to `_`. |

Writers open with Base's create/truncate mode and close their handle; errors are
`Surface.IOError` values (`FileError{code, message}`, `DataError{InvalidRequest}`).

## Explicit loaders

raylib's `SetLoadFileDataCallback`, `SetSaveFileDataCallback`,
`SetLoadFileTextCallback` and `SetSaveFileTextCallback` install process-wide
callbacks. Bend has no global state, so Jonlib passes the callback to `_with`
forms of the operations raylib routes through it, as a template argument
(`~load`, `~save`) like `Log.trace_with`'s handler:

| Callback | Type | `_with` forms (raylib routing) |
|---|---|---|
| load data | `String -> IO(Result<&1, &1, Surface.IOError, +List<U32>>)` | `Files.load_data_with`, `Surface.load_image_with`, `Surface.load_raw_with`, `Image.Animation.load_image_with` |
| save data | `String -> +List<U32> -> IO(Result<&1, &1, Surface.IOError, Unit>)` | `Files.save_data_with`, `Surface.write_image_with` (PNG and raw only) |
| load text | `String -> IO(Result<&1, &1, Surface.IOError, String>)` | `Files.load_text_with`, `Files.text_find_index_with` |
| save text | `String -> String -> IO(Result<&1, &1, Surface.IOError, Unit>)` | `Files.save_text_with`, `Surface.write_code_with`, `Files.export_data_as_code_with` |

The forms keep raylib's routing exactly: `ExportImage` writes BMP, TGA and QOI
files itself, so `Surface.write_image_with` calls `~save` only for `.png` and
`.raw`; `FileTextFindIndex` checks `FileExists` on disk before loading through
the callback; `SaveFileText`'s callback receives the text up to its first NUL;
the loaded bytes of an image keep the plain loader's size limits
(`UnsupportedImageSize`) and `LoadImageRaw`'s header and truncation rules.
Failures are typed `Surface.IOError` values instead of `NULL`/`false`.
Requests the plain form rejects before opening a file (bytes above 255,
invalid raw parameters) are rejected before calling the callback.

## The host's file system

The functions that look at or change the file system beyond a file's bytes
are built on Bend Base's path, directory and process effects (`Path.stat`,
`Path.rename`, `Path.remove`, `Dir.read`, `Dir.make`, `Dir.change`,
`Dir.current`, `Process.path`, `Process.run`), which the declared compiler
overlay adds to Base ([bend-os-effects.md](../patches/bend-os-effects.md)).
Paths are Base strings, as `Files.load_data`'s are, and raylib's `int`
results are the int's U32 bits.

`shaders_hot_reloading` only shows its shader file's modification time and
compares it with a later reading: its port takes that time as a setup
argument and never sees the file modified, and the examples probe answers
the example's `GetFileModTime` with the script's seed
(`tools/reference/example_driver.h`), so the reference does not depend on
the checkout's file times.

`core_directory_files` lists its working directory and the ones above it.
Its port is handed the directories it may list as a setup argument: each
with its path and its entries in the order `readdir` gives them, and whether
each is a file (`IsPathFile`). The example's own code runs on them
(`LoadDirectoryFilesEx`'s extension filter, `LoadDirectoryFiles`,
`GetPrevDirectoryPath`), and a directory it was not handed is a refusal. The
examples probe reads the listings from the very directories the reference
lists, three levels inside the script's own so that no other program writes
in them, and checks after the reference ran that they are still the same.
A file without an extension below a directory with a dot in its name (the
probe's `.build`) makes `IsFileExtension` read a 16-byte array as a string
it does not end: one script has such a file and is refused from its start.

`core_screen_recording` saves its GIF in `GetApplicationDirectory()`: its
port takes that directory as a setup argument (`--directory`), and the
examples probe answers the example's call with `"./"`, the script's own
directory, where the file is compared like any other an example writes. The
same example reads the screen with `LoadImageFromScreen`: the probe hands it
the image a desktop host reads, which `Frame.load_image_from_screen`
follows, instead of the memory platform's bottom-up one with red and blue
swapped ([FRAME.md](FRAME.md#readback)).

## How it is verified

`tools/files_os_probe.py` (gate `files-os`) runs one script of 206 operations
over the file system functions, on a tree it builds afresh before the
reference runs and before each lane does (files of several extensions, an
empty, an unreadable and a linked one, a directory that cannot be opened,
nested directories, paths past 4096 bytes and one of exactly 4095), with
fixed modification times: the queries, every listing filter with and without
subdirectories, renames, removals, directories made, copies and moves
(raylib's -1 after a successful move's copy included), `OpenURL` through a
fake `explorer` that logs its arguments, and `ChangeDirectory` and
`GetWorkingDirectory` last. `GetApplicationDirectory` is checked for its
trailing `/` and for being a directory, the programs being different on each
side. An extension that overflows `IsFileExtension` is a `None` contract.


`tools/files_probe.py` (gate `files`) runs the pure functions over a corpus of
drive, root, relative, dotted and long paths, extension lists and names, then
compares existence, length, loaded data/text, text search and files each side
saves (data, text, data-as-code) read back byte for byte, and `FileTextReplace`
on fresh copies of fixtures (matches, empty replacements, overlapping and
absent searches, a NUL inside the text, a missing file), its result and the
rewritten file, on CPU-1, CPU-2 and JavaScript. The dropped-file functions are
compared with the memory platform by `tools/window_probe.py`
([DRIVER.md](DRIVER.md#window-state)). Inputs where raylib's C code is undefined are checked as `None`
contracts without running them natively.

`tools/loaders_probe.py` (gate `loaders`) installs native callbacks serving an
in-memory file table and logging every call, passes the same callbacks to the
`_with` forms, and compares the complete call logs and results: data and text
loads and saves, `FileTextFindIndex` on a virtual-only and a real file,
`LoadImage` (PNG, QOI, missing), `LoadImageRaw` (fitting, ignored and
truncated headers), `LoadImageAnim`, `ExportImage` to `.png`, `.raw` and a
directly written `.bmp`, `ExportImageAsCode` and `ExportDataAsCode`.
