# Performance

This page compares Jonlib's example programs with the native raylib 6.2 examples
on frame time, setup time and peak memory, and compares the work of mixing one
audio period without a device. These are measurements, not gates: no budget has
been set, and none is claimed as met. Every measured program also produced
output equal to raylib's, so each timing is for a correct result.

## Method

[`tools/perf_examples.py`](../tools/perf_examples.py) builds both sides the
way the `examples-*` gates do ([EXAMPLES.md](EXAMPLES.md),
`tools/examples_probe.py`):

- **raylib**: the unmodified example, compiled with the probe's driver and
  linked with its clock-injected memory-platform raylib (`-O2`,
  `-ffp-contract=off`). The scripted clock ends `SetTargetFPS` waits
  immediately, so neither side sleeps.
- **Jonlib**: the probe's generated replay program for the example, compiled
  by the pinned Bend to a native binary and run on one thread
  (`+RTS --gpu off --threads 1 -RTS`). With `--js`, the tool also measures the JavaScript
  lane.

Both sides use the same working directory, the same resource paths, the same
scratch files and the same input events.

**Workload.** Each example runs one probe script, its *base*: the first
script whose frames Jonlib answers on this host. The *steady* script is the
base followed by 30 idle frames (no input, a 4 ms frame at the 60 FPS
target). Both sides serialize every frame:

- raylib prints the color buffer as runs, one flushed line per frame.
- Jonlib prints the same runs plus the quadtree it would present.

That serialization is included in both frame times. For scenes that draw
little, it makes up most of raylib's frame time, so the ratios below
understate the renderer gap for those examples. The rendering-only
measurement in [FRAME.md](FRAME.md#performance) puts the renderer gap at
about 23x.

**Frame time.** raylib runs base and steady as two processes. Its time per
frame is the difference of their wall times divided by 30. The tool also
measures it directly from the arrival times of the steady run's last 30
frame lines (median and 95th percentile). The two methods agree within about
10%.

Jonlib's replay is a pure function of the script and prints one line per
script, so it has no per-frame timestamps. Its program runs base, steady and
base again in one process, and its time per frame is (steady − second base)
/ 30, taken from the arrival times of the output lines. The ratio column
divides Jonlib's differential time by raylib's.

**Setup time.** For raylib, this is the base script's whole process: start,
`InitWindow`, setup, the script's frames and exit. For Jonlib, the table
gives two times:

- the time from process start to the first script's line, which includes
  one-time work;
- the base script's repeat, which covers setup and frames without the
  process start.

**Peak memory.** This is the maximum resident set of the measured process,
in kibibytes. The launcher reads `ru_maxrss` from `wait4`. Linux reports
that field in kibibytes and macOS reports it in bytes, so the tool divides
the macOS reading by 1024 before storing it. On Linux, `ru_maxrss` survives
`exec`, so a program forked from the Python harness would inherit the
harness's high-water mark. The tool therefore starts each program through a
small C launcher and reads the launcher's child.

**Runs.** Each program runs three times. The tables give medians, and peak
memory is the maximum across runs.

## Baseline: Apple M1, 2026-11-12

The reference point for the optimization work. Every later change in
[Optimizations](#optimizations) is measured against these numbers on the same
machine, with the same command:

```sh
python3 tools/perf_examples.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE" --js
```

| | |
|---|---|
| Machine | Apple M1, 8 cores, 16 GB, macOS 27.2 (arm64) |
| C compiler | Apple clang 21.0.0 |
| Bend | 2.0.39 `a3efe8a3` with the declared overlay, Bun 1.3.12 |
| raylib | 6.2, `02566453` |
| Jonlib | `main` at `80582c9` |
| Host profiles | `AppleLibm`, `Fused` |

| Example | Frames (base + extra) | raylib ms/frame (median, p95) | raylib ms/frame (diff) | Jonlib ms/frame (diff) | Ratio | raylib base script ms (process) | Jonlib base script ms (first, repeated) | raylib peak MiB | Jonlib peak MiB | Output equal |
|---|---|---|---|---|---|---|---|---|---|---|
| shapes_basic_shapes | no script Jonlib answers on every frame under AppleLibm | | | | | | | | | |
| shapes_bouncing_ball | 13 + 30 | 0.8030, 1.08 | 0.7771 | 3.60 | 4.6x | 17.49 | 457, 1.27 | 8 | 96 | yes |
| textures_bunnymark | 12 + 30 | 5.14, 5.89 | 4.90 | 44.91 | 9.2x | 39.02 | 306, 296 | 8 | 609 | yes |
| textures_sprite_animation | 12 + 30 | 3.31, 3.40 | 3.27 | 31.28 | 9.6x | 48.46 | 524, 496 | 9 | 636 | yes |
| text_font_spritefont | 2 + 30 | 2.56, 3.36 | 2.53 | 22.28 | 8.8x | 15.86 | 120, 109 | 12 | 394 | yes |
| text_format_text | 4 + 30 | 0.7652, 1.39 | 0.7449 | 0.9366 | 1.3x | 10.42 | 258, 0.3387 | 8 | 49 | yes |
| models_loading_gltf | no script Jonlib answers on every frame under AppleLibm | | | | | | | | | |
| models_animation_timing | no script Jonlib answers on every frame under AppleLibm | | | | | | | | | |
| core_2d_camera | 13 + 30 | 3.92, 3.98 | 3.92 | 15.48 | 3.9x | 57.25 | 2026, 3.72 | 8 | 285 | yes |
| gui_style | 9 + 30 | 0.7235, 1.16 | 0.6908 | 20.81 | 30x | 13.55 | 211, 206 | 5 | 133 | yes |
| audio_music_stream | 14 + 30 | 1.07, 1.28 | 0.4749 | 17.90 | 38x | 40.68 | 486, 498 | 8 | 235 | yes |

| Example | JavaScript ms/frame (diff) | Ratio to raylib | JavaScript wall ms | JavaScript peak MiB |
|---|---|---|---|---|
| shapes_bouncing_ball | 44.93 | 58x | 3202 | 811 |
| textures_bunnymark | 539 | 110x | 34374 | 3220 |
| textures_sprite_animation | 316 | 97x | 21456 | 3401 |
| text_font_spritefont | 179 | 71x | 7178 | 2395 |
| text_format_text | 37.29 | 50x | 1629 | 555 |
| core_2d_camera | 560 | 143x | 40058 | 1676 |
| gui_style | 85.20 | 123x | 5055 | 896 |
| audio_music_stream | 139 | 293x | 11174 | 1871 |

| Audio (country.mp3 music stream) | raylib | Jonlib CPU-1 | Ratio |
|---|---|---|---|
| ms per 10 ms period (callback + UpdateMusicStream) | 0.0085 | 2.54 | 298x |
| share of real time | 0.1% | 25.4% | |
| peak MiB (30000 / 300 periods) | 2 | 44 | |
| time played equal | yes | | |

Every measured output was equal to raylib's. Three examples have no probe
script that Jonlib answers on every frame under the Apple libm profile
(their scripts reach a `sinf`/`cosf` argument Jonlib refuses there), so they
are measured only on Linux, below. The first of each example's three runs
showed a negative raylib per-frame difference: that process starts cold, so
its base run is slower than the steady run of the next. The medians are not
affected; `perf_examples.py` runs each program once before measuring from
now on.

Compared with the Linux measurement below, the M1 is faster in absolute
terms on both sides and the ratios are close: textured and text scenes are
9-10x raylib, raygui 30x, and the audio period is the largest gap, 298x
raylib (2.54 ms of every 10 ms period on one thread).

## Earlier measurement: Linux x86-64, 2026-10-20

### Machine and toolchain

Measured on 2026-10-20. The current pin is Bend 2.0.39 (`a3efe8a3`). The Bend
row is the compiler this table was measured with, the previous pin:

| | |
|---|---|
| CPU | AMD EPYC 9354P, 4 virtual CPUs (a hypervisor guest) |
| Memory | 16 GB host, 8 GiB cgroup v2 limit (`memory.max`), no swap |
| OS | Linux 6.8.0 x86-64, glibc 2.39 (host libm profile `Glibc239Libm`) |
| C compiler | Ubuntu clang 18.1.3 |
| Bend | `b7ebee9` with the 2.0.27 overlay (`metal.1`, `os-effects.1`), Bun 1.3.12 |
| raylib | 6.2, `0256645` |

The machine is shared with other workloads, so expect a few percent of noise
between runs. One raylib run of `textures_bunnymark` was 50% slower than the
other two.

### Results

Times are in milliseconds and memory is in MiB. "diff" is the differential
time per frame described above.

| Example | Frames (base + idle) | raylib ms/frame (median, p95 of lines) | raylib ms/frame (diff) | Jonlib CPU-1 ms/frame (diff) | Ratio | raylib base script (process) | Jonlib first script, repeated base | raylib peak MiB | Jonlib peak MiB |
|---|---|---|---|---|---|---|---|---|---|
| shapes_basic_shapes | 4 + 30 | 6.80, 12.25 | 6.69 | 10.6 | 1.6x | 35 | 3434, 55 | 8 | 688 |
| shapes_bouncing_ball | 13 + 30 | 1.23, 1.82 | 1.31 | 8.7 | 6.6x | 26 | 1120, 3 | 8 | 97 |
| textures_bunnymark | 12 + 30 | 8.97, 17.00 | 8.19 | 91.8 | 11x | 95 | 578, 531 | 9 | 610 |
| textures_sprite_animation | 12 + 30 | 5.45, 8.66 | 5.48 | 62.9 | 11x | 75 | 953, 769 | 9 | 629 |
| text_font_spritefont | 2 + 30 | 4.71, 6.38 | 4.70 | 48.8 | 10x | 27 | 253, 195 | 12 | 394 |
| text_format_text | 4 + 30 | 1.14, 2.80 | 1.26 | 2.2 | 1.8x | 17 | 563, 1 | 8 | 50 |
| models_loading_gltf | 6 + 30 | 3.61, 4.58 | 3.92 | 207 | 53x | 91 | 5428, 5924 | 12 | 386 |
| models_animation_timing | 14 + 30 | 3.59, 4.72 | 3.31 | 107 | 32x | 151 | 6279, 6866 | 12 | 592 |
| core_2d_camera | 13 + 30 | 10.37, 17.10 | 9.76 | 28.3 | 2.9x | 160 | 3694, 27 | 8 | 284 |
| gui_style | 9 + 30 | 1.56, 2.82 | 1.55 | 35.4 | 23x | 20 | 368, 349 | 5 | 134 |
| audio_music_stream | 14 + 30 | 1.90, 2.73 | 2.03 | 38.4 | 19x | 51 | 930, 941 | 9 | 270 |

Every lane's output was equal to raylib's in every row.

The measured scripts are `shapes_basic_shapes-turn`, `shapes_bouncing_ball-keys`,
`textures_bunnymark-bunnies`, `textures_sprite_animation-speed`,
`text_font_spritefont-frames`, `text_format_text-frames`, `models_loading_gltf-switch`,
`models_animation_timing-controls`, `core_2d_camera-move-rotate`, `gui_style-text`
and `audio_music_stream-keys`.

Jonlib's per-frame times varied most between runs in
`models_animation_timing` (87.6, 106.6 and 174.8 ms) and
`models_loading_gltf` (202 to 236 ms). The other examples stayed within about
15%, except the cheapest frames (`shapes_basic_shapes` and
`text_format_text`, a few milliseconds each), where one millisecond is a
large share.

#### Audio

Without a device, latency cannot be measured: the device period, host
scheduling and the output buffer are all missing. What can be measured is
the work one period costs.

The test plays `country.mp3` as a music stream. Each period is one device
callback of 480 frames (10 ms at 48000 Hz) followed by `UpdateMusicStream`:

- raylib: `raudio.c` with miniaudio's null backend, driven the way
  `tools/reference/audio_clock.c` drives it.
- Jonlib: `AudioDevice.mix(device, 480)` and `Music.update`, the steps
  `AudioClock.advance` takes.

The cost of one period is the difference between process wall times with and
without the periods, divided by their count. raylib's side is timed over
30000 periods because 300 are too few to resolve; the music loops. After 300
periods, both sides report the same `GetMusicTimePlayed` bits.

| Country.mp3 music stream | raylib | Jonlib CPU-1 | Ratio |
|---|---|---|---|
| ms per 10 ms period (mix + MP3 decoding + update) | 0.0138 | 5.14 | 372x |
| Share of real time | 0.14% | 51% | |
| Load (`InitAudioDevice` + `LoadMusicStream`, whole process) | 16 ms | 129 ms | |
| Peak memory | 3 MiB | 42 MiB | |

Jonlib therefore keeps up with real time on this host, but with half of each
period spent on mixing and decoding, leaving the other half for a frame. A
program that draws a frame each period cannot fit both on one thread. Jonlib
has no audio thread: `AudioClock.advance` mixes inside the program's update.

## Profile, 2026-11-12

Where the time goes, measured on the M1 baseline build with macOS `sample`
(1 ms interval) on the native CPU-1 binaries. A Bend def that compiles to a
flat loop appears as a `spin_N` C function; everything else runs through the
runtime's evaluator (`WL_FID_*`). Shares below exclude idle runtime threads.

**What it is not: pixel storage.** An `Array<U32>` is a flat buffer in the
native runtime: 8.4 million sequential `Array.get`/`Array.set` pairs on a
2^19-slot array take about 20 ms (2.4 ns a pair), as fast as C. The
balanced-tree view in Base is the program's model, not the machine's. A
native process also has about 0.18 s of fixed startup, part of every
"first script" and setup time above.

**Renderer** (`tools/frame_probe.py --benchmark`, the 640x480 frame of 100
rectangles and circles, 40 frames in one process):

| | Time per frame |
|---|---|
| native rlsw (`-O2`) | 3.2 ms |
| Jonlib CPU-1 | 46.3 ms (an empty frame: 9.7 ms) |
| Jonlib CPU-2 | 47.4 ms |
| Jonlib JavaScript | 714 ms |

About 45% of the samples are emulated binary64 arithmetic
(`src/resize_numeric.bend` `Double.*`, called by `src/trig.bend`): the Apple
libm profile's correctly rounded `sinf`/`cosf` for every circle vertex, in
software extended precision because Bend has no F64. About 50% are the
per-pixel span loops of `src/frame.bend` (`cols` and `pixel.*` compiled to
flat loops): arithmetic-bound, with 30-40 values threaded through each
iteration. Evaluator and allocation are under 5%. Two threads gain nothing:
the rasterizer is one sequential recursion.

**Examples** (`textures_bunnymark`): 54% raster loops, 38% writing each
frame's output as a Bend `String` (a list of characters) in the probe's
replay program, 8% evaluator and allocation. The serialization is the
measurement harness (`tools/examples_probe.py`), not the library, but it is
in every example's frame time: the frame benchmark above is the library-only
number.

**Audio** (`country.mp3` music stream, 3000 periods): about 55% of the
samples are the runtime dropping and reference-counting shared terms
(`term_drop`, `span_fade`), not arithmetic:

- `src/mixer.bend` `read` (18%): every read takes the buffer's frames with
  `List.drop(data, cursor * channels)` from the head of a shared
  `+List<U32>`, so each read costs the cursor's position in list steps, each
  step a reference-count bump on a shared cons cell.
- `src/mp3_layer3.bend` `synth.call` (16%): the synthesis filterbank builds
  and drops short-lived lists per granule.
- `List.append` in the mixer and stream paths (4%).

**Codecs**: PNG decoding of the 512x384 RGB `parrots.png` takes under 80 ms
for the whole Jonlib process (decode plus startup) against 4.9 ms for
stb_image (`-O2`): at most about 16x.

**Memory** (50-690 MiB peaks) has not been broken down yet.

### What to change first

1. The mixer's buffer reads: read from where the last read ended instead of
   walking from the head (the shared-list walk is the largest single cost in
   audio, and audio is the largest ratio: 298x).
2. The MP3 synthesis filterbank's per-granule list churn.
3. The Apple-profile `sinf`/`cosf`: the same correctly rounded results with
   cheaper extended-precision arithmetic, checked against the current
   implementation on every input it accepts.
4. The span loops, by parallel rendering (the experiment below).

## Observations

- **Simple scenes are close; textured, text and model scenes are 10-50x
  slower.** The examples that draw a few shapes or a line of text
  (`shapes_basic_shapes`, `text_format_text`, `core_2d_camera`) run at 1.6-3x
  raylib's frame time, and serialization dominates both sides there. Textures
  (bunnymark, sprite animation), sprite fonts and raygui are about 10-23x.
  The two 3D model examples are 32-53x. As in [FRAME.md](FRAME.md#performance),
  the renderer is single-threaded: each pixel is a read and a write on a
  balanced `Array` tree, and the rasterizers are sequential recursions. Every
  textured span also samples its texture through that tree.
- **Setup.** Loading a glTF model and its animations takes 5.4-6.9 s in
  Jonlib against 0.09-0.15 s for raylib's whole process: a factor of about
  45-65. This covers the `.glb` parsing, the embedded PNG decoding and the
  animation data; how the time divides among them has not been profiled.
- **One-time work in the first script.** For `shapes_basic_shapes`,
  `core_2d_camera`, `shapes_bouncing_ball` and `text_format_text`, the first
  script takes 0.6-3.7 s, while the same script run again takes 1-55 ms.
  Constants built on first use (for example the libm profile's tables) are
  the likely cause. This has not been profiled.
- **Memory.** Jonlib's peaks are 50-690 MiB against raylib's 5-12 MiB. Values
  are boxed nodes: pixels in `Array` trees, bytes and strings in cons lists.
  Each frame's printed text also stays in memory until the script ends; that
  belongs to the harness, not to an interactive program.
- **Audio.** Mixing and MP3 decoding run at about 370x raylib's cost. The
  decoder's samples and the mixer's buffers are lists of `U32`/`F32`.
- **JavaScript** was not part of this run. In FRAME.md's rendering benchmark
  it was about 47x slower than the native lane
  ([FRAME.md](FRAME.md#performance)).
- **Untried levers**, none assumed before it is measured: rows or tiles
  rendered in parallel, a flat store per tile, byte buffers instead of lists
  in the decoders, and the Metal lane.

## Status against the roadmap

The measurements exist; the performance item stays open. No frame-time,
memory or audio budget has been agreed, so no example can be marked as meeting
one. An interactive budget would be 16.7 ms per frame at 60 FPS. Of the
measured examples, only `shapes_basic_shapes`, `shapes_bouncing_ball` and
`text_format_text` stay within it on this host once running, with the
harness's serialization included; their first script still pays the one-time
work above. Not measured:

- device latency;
- multi-threaded lanes (CPU-2) and the GPU lane;
- macOS;
- examples other than the eleven above.

## Reproduce

```sh
export PATH=$HOME/.bun-1.3.12/bin:$PATH PROBEKIT_JOBS=1
python3 tools/perf_examples.py --bend-source "$BEND_SOURCE" --raylib-source "$RAYLIB_SOURCE"
# a subset, another script, more frames, the JavaScript lane:
python3 tools/perf_examples.py ... --example textures_bunnymark --script bunnies --extra-frames 60 --js
python3 tools/perf_examples.py ... --category models --runs 5
# re-measure one example (or only the audio) and keep the rest of an earlier run:
python3 tools/perf_examples.py ... --merge --example models_loading_gltf
python3 tools/perf_examples.py ... --merge --audio-only
```

Results are written to `.build/perf/results.json` (every run's samples) and
`.build/perf/results.md` (the tables above). Compiled candidates are cached
beside their sources and reused while the source, the repository's Bend files
and the compiler pin are unchanged.

The default set compiles eleven candidates plus the audio program, one at a
time (each 1-6 min). On this 8 GiB machine, the `models_loading_gltf` compile
was killed by the OOM killer twice and passed on the third try; an exit code
of -9 means "run it again". With every candidate cached, a run of the default
set takes about 11 minutes.

## Optimizations

Each change is listed with its before/after numbers against the M1 baseline.
None yet.
