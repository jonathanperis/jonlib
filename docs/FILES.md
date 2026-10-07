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
| `Files.exists(path) -> IO(Bool)` | `FileExists` | The path opens for reading (directories included). raylib asks `access()`, which also accepts existing unreadable files. |
| `Files.length(path) -> IO(U32)` | `GetFileLength` | The size in bytes; 0 when the file does not open. |
| `Files.load_data(path)` / `unload_data` | `LoadFileData` / `UnloadFileData` | Every byte, up to raylib's `INT_MAX` size, as `Result<&1, &1, Surface.IOError, +List<U32>>`; an existing empty file is an empty list (raylib: `NULL` with size 0). |
| `Files.save_data(path, bytes)` | `SaveFileData` | Writes every byte; values above 255 are `InvalidRequest` before opening. |
| `Files.load_text(path)` / `unload_text` | `LoadFileText` / `UnloadFileText` | Every byte as a character, including NULs. |
| `Files.save_text(path, text)` | `SaveFileText` | The text up to its first NUL; characters above 255 are `InvalidRequest`. |
| `Files.text_find_index(path, search) -> IO(Maybe<U32>)` | `FileTextFindIndex` | Byte index of the first occurrence in the text up to its first NUL; `None` when absent or the file is missing. An empty file, which raylib scans through a `NULL` text, is `None`. |
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

## Not yet available

Base exposes only open, read, write, size and close, so the functions needing
other OS primitives are recorded as blocked: `FileRename`, `FileRemove`,
`FileCopy`/`FileMove` (directory creation and removal), `DirectoryExists`,
`IsPathFile`, `GetFileModTime`, `GetWorkingDirectory`,
`GetApplicationDirectory`, `MakeDirectory`, `ChangeDirectory`,
`LoadDirectoryFiles(Ex)`, `UnloadDirectoryFiles` and
`GetDirectoryFileCount(Ex)`. Dropped files need the window runtime (Phase 2);
`FileTextReplace` needs the text utilities (`TextReplaceAlloc`).

## How it is verified

`tools/files_probe.py` (gate `files`) runs the pure functions over a corpus of
drive, root, relative, dotted and long paths, extension lists and names, then
compares existence, length, loaded data/text, text search and files each side
saves (data, text, data-as-code) read back byte for byte, on CPU-1, CPU-2 and
JavaScript. Inputs where raylib's C code is undefined are checked as `None`
contracts without running them natively.

`tools/loaders_probe.py` (gate `loaders`) installs native callbacks serving an
in-memory file table and logging every call, passes the same callbacks to the
`_with` forms, and compares the complete call logs and results: data and text
loads and saves, `FileTextFindIndex` on a virtual-only and a real file,
`LoadImage` (PNG, QOI, missing), `LoadImageRaw` (fitting, ignored and
truncated headers), `LoadImageAnim`, `ExportImage` to `.png`, `.raw` and a
directly written `.bmp`, `ExportImageAsCode` and `ExportDataAsCode`.
