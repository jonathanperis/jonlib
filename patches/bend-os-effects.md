# Proposal: path, directory and process effects for Bend's Base

`bend-os-effects.patch` adds nine IO effects to Bend's base library, written
the way Base's own `File.*` effects are: a foreign def in `bend2/base.bend`
whose body imports one C source and one JavaScript source from
`bend2/effs/`. Nothing in the language, the checker or the compiler changes.
The patch applies alone to Bend `a3efe8a3` (2.0.39). Bend 2.0.39 already
ships `Process.run(program, args, input, max_output, timeout_ms)`, which
spawns a program, captures stdout and stderr and stops at a timeout, through
one worker on Bun and Node. That is not `system(3)` through `/bin/sh -c` with
inherited standard streams, so the shell effect is `Process.shell` and upstream
`Process.run` is left in place. The two tests in `tests/io/` passed on Bend
2.0.38 on the check, the C binary and the JavaScript lane on Linux x86_64 with
Bun 1.3.12. The 2.0.39 rebase has not re-run them.

It was written for Jonlib, a Bend 2 library inspired by raylib, whose file-system API
(`LoadDirectoryFiles`, `GetFileModTime`, `ChangeDirectory`, `OpenURL`, ...)
needs what Base cannot do today: list a directory, look at a path, rename or
remove one, make a directory, know and change the working directory, find the
running program and run a command. It is meant to be useful to any Bend
program, not only to Jonlib.

## The effects

| Def | What it does | C (POSIX) | JavaScript (Node API, run by Bun) |
|---|---|---|---|
| `Path.stat(path) -> IO(Result<U32 & String, U32 & Nat & Nat>)` | kind (1 a regular file, 2 a directory, 3 anything else), size in bytes, last modification in whole seconds since the epoch; links followed | `stat` | `fs.statSync(path, {bigint: true})` |
| `Path.rename(source, target) -> IO(Result<.., Unit>)` | renames, replacing `target` where the host allows | `rename` | `fs.renameSync` |
| `Path.remove(path) -> IO(Result<.., Unit>)` | a file, or an empty directory | `remove` | `unlinkSync`, then `rmdirSync` where unlink refuses a directory |
| `Dir.read(path) -> IO(Result<.., List<String>>)` | the names in a directory in the host's order, without `.` and `..` | `opendir`/`readdir` | `fs.readdirSync(path, {encoding: "buffer"})` |
| `Dir.make(path) -> IO(Result<.., Unit>)` | one directory, mode 0777 under the umask | `mkdir` | `fs.mkdirSync` |
| `Dir.change(path) -> IO(Result<.., Unit>)` | the process's working directory | `chdir` | `process.chdir` |
| `Dir.current() -> IO(Result<.., String>)` | the working directory | `getcwd` (any length) | `process.cwd()` |
| `Process.path() -> IO(Result<.., String>)` | the running program's file, absolute, links resolved | `realpath("/proc/self/exe")`; `_NSGetExecutablePath` on macOS | the script the runtime runs (`process.argv[1]`) |
| `Process.shell(command) -> IO(Result<.., U32>)` | runs `command` with `/bin/sh -c` to its end, its output where the program's goes; the exit status, or 128 plus the signal that ended it | `system` (standard streams flushed first) | `child_process.spawnSync("/bin/sh", ["-c", command], {stdio: "inherit"})` |

`Process.shell` is the only effect in this patch that executes something. It
is its own def so that it can be taken or left without the others. It is not
upstream `Process.run`.

## Conventions kept from Base

- **Errors** are `Fail{(errno, strerror(errno))}`, as `File.open` gives them:
  the host's errno, and its message from the C library on both lanes (the
  JavaScript lane reads `strerror` through `bun:ffi`, as Base's sockets do).
- **A NUL in a path** is `EILSEQ` before any call, as in `File.open`.
- **Paths and names are UTF-8** at the edge: a path is encoded as Base's
  `io_cstr` encodes it, and a name read back is decoded as `io_str` decodes
  (WHATWG: a broken sequence becomes U+FFFD), so a directory's names are the
  same strings on both lanes.
- **Blocking calls** (`stat`, `readdir`, `rename`, `remove`, `mkdir`,
  `chdir`, `system`) run on Base's IO helper threads through `io_work`, like
  the file effects; `Dir.current` and `Process.path` answer at once.
- **Nat** carries sizes and times: a size past Nat's 2^48 - 1 fails with
  `EOVERFLOW`, as `File.size` does past 4 GiB; a time before 1970 is 0. On
  the JavaScript lane a Nat is a host number, not a BigInt, so a value that
  passes the 2^48 - 1 check is converted with `Number`.

## Where the lanes differ, and why that is acceptable

- `Dir.read` keeps the host's order. Sorting would hide what `readdir`
  gives, and C programs that list directories (raylib's among them) answer in
  that order. On Linux, glibc's `readdir` and Bun's `readdirSync` were
  checked to give the same order for the same directory.
- `Process.path` is the executable for a native program and the script for
  the JavaScript one: each is "the program that is running" on its lane.
- `Dir.change` on the JavaScript lane goes through a JavaScript string, so a
  path that is not valid UTF-8 cannot be reached there.

## Tests

- `tests/io/path_dir.bend`: in a directory of its own under `/tmp`,
  `Dir.make`, `Dir.make` again (`File exists`), a file written in it,
  `Path.stat` of the file (kind and size) and of the directory (kind),
  `Dir.read`, `Path.rename`, `Dir.read` again, `Path.remove` of the file then
  of the directory, and `Path.stat` of the removed path (`No such file or
  directory`). What an earlier run left is removed first.
- `tests/io/cwd_process.bend`: `Dir.change("/")` and `Dir.current()`,
  `Dir.change` to a missing directory, `Process.path` (a regular file), and
  `Process.shell` of `exit 3`, of `echo from-sh` (its output lands before the
  status after it) and of `kill -TERM $$` (143).

On Bend 2.0.38 both pass on the check, the C binary and the JavaScript lane
on Linux x86_64 with Bun 1.3.12. The interpreter lane and the upstream tests
next to them were not re-run for that rebase, and the 2.0.39 rebase has not
re-run them either. The effect sources are byte-identical to the 2.0.38 patch.
The new files fit the
repository gate's allow list (`bend2/effs/*.c|js`, `tests/io/*.bend`) without
changing it. macOS has not been run yet: `_NSGetExecutablePath`, the errno
numbers `EILSEQ` (92) and `EOVERFLOW` (84) and `remove`'s `EPERM` for a
directory are written for it. Registration follows 2.0.38: `io_eff(CID(Name), fn)`
with two arguments, and a JavaScript constructor tag is the bare name.

## Applying it

```sh
git -C /path/to/bend apply --check patches/bend-os-effects.patch
git -C /path/to/bend apply patches/bend-os-effects.patch
```

It touches `bend2/base.bend` (nine defs after `File.close` and before
`TCP.listen`, and a modification notice at the top that an upstream version
would drop) and adds 18 files in `bend2/effs/` (`process_shell`, not a second
`process_run`) and 2 in `tests/io/`.

## License

Under Apache-2.0, as is the Bend code it extends. Copyright 2026
HigherOrderCO for the original Bend work; the effects and tests were written
for Jonathan Peris's Jonlib project in 2026 and are offered to Bend under the
same license.
