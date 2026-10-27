# Logging and memory

raylib keeps its trace-log threshold and callback in process-wide state, which
Bend does not have. Jonlib passes them explicitly (a language adaptation):

| Function | raylib | Contract |
|---|---|---|
| `Log.default()` / `Log.level(level)` | `SetTraceLogLevel` | A `Log.Logger` value carrying the threshold (default `LOG_INFO`, 3). |
| `Log.message(logger, kind, text) -> Maybe<String>` | `TraceLog` text | The line raylib prints: the `TRACE: `/`DEBUG: `/`INFO: `/`WARNING: `/`ERROR: `/`FATAL: ` prefix (none for other types), at most 244 characters of text (its 256-byte buffer) and a newline; `None` below the threshold. |
| `Log.trace(logger, kind, text) -> IO(Unit)` | `TraceLog` | Prints the line; `LOG_FATAL` (6) then exits with status 1. |
| `Log.trace_with(~handler, logger, kind, text)` | `SetTraceLogCallback` + `TraceLog` | Messages at or above the threshold go to `handler(kind, text)` instead of standard output. |
| `Memory.alloc(size)` | `MemAlloc` | `size` zero bytes (`RL_CALLOC`). |
| `Memory.realloc(bytes, size)` | `MemRealloc` | Keeps the first `size` bytes; growth is zero (C leaves it uninitialized). |
| `Memory.free(bytes)` | `MemFree` | Consumes the bytes. |

`Files.change_directory_with` emits `ChangeDirectory`'s own lines through the
caller's logger: `INFO: SYSTEM: Working Directory: ` plus the path when
`chdir` succeeds, and `WARNING: SYSTEM: Failed to change to directory: ` plus
the path when it fails, when that level is at or above the threshold. The
path is copied literally, as `%s` does. Other `TRACELOG` calls (InitWindow's
and CloseWindow's reports, a loader's warnings) are not reproduced, so a
handler only receives what a program gives `Log.trace_with`.
`core_custom_logging` installs a callback that only ever receives raylib's
own lines: its port's handler is never called, and its frames are the text
it draws.

Texts are preformatted: Bend has no variadic arguments, so a `%` prints
literally, where raylib would interpret a conversion specifier. Formatting
belongs to the text utilities (`TextFormat`).

`tools/directory_log_probe.py` (gate `directory-log`) compares `ChangeDirectory`'s
stdout at thresholds 3, 4 and 7 for a short success, a missing path, a `%` in
the path and a path longer than `Log.message`'s 244 characters.
`tools/log_probe.py` (gate `log`) compares the complete standard output of
`SetTraceLogLevel`/`TraceLog` sequences (every type against thresholds 0, 3, 5
and 7, empty and 300-character texts) with `Log.trace`, and checks that
`LOG_FATAL` prints its line and exits with status 1 on both sides. Memory
results are contract checks in `tests/transforms.bend`.
