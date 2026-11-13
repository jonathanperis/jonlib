---
name: bend
description: Write, fix, check and optimize Bend 2 code (the HigherOrderCO language: pure, affine, dependent types, compiles to native C, JavaScript and Metal/CUDA). Use whenever editing any .bend file in this repo (jonlib.bend, jonmath.bend, src/*.bend, LAWS.bend, PROOF.bend, probe programs in tools/*.py), reading a Bend compiler error, writing a Bend benchmark, or profiling/optimizing Bend performance.
---

# Bend 2 for Jonlib

Jonlib pins **Bend 2.0.39 (`a3efe8a3`) plus a four-patch overlay**
(`toolchain.json`, `patches/`). The pinned checkout is the reference, not the
website or a newer `bend`: never run `bend update` or install anything
(AGENTS.md). Locally the toolchain is `$BEND_SOURCE` (on this Mac
`~/Projetos/jonlib-toolchain/bend`); the CLI is `bun $BEND_SOURCE/bend2/main.ts`.

Primary sources, in the pinned checkout (read the relevant one before guessing):

| Need | Source |
|---|---|
| Language guide (syntax, kinds, quantities, laws, IO, tooling) | `bun $BEND_SOURCE/bend2/main.ts guide` = `guide/GUIDE.md` |
| Parallel / GPU performance | `... guide shaders` = `guide/SHADERS.md` |
| Foreign effects (C/JS) | `... guide effects` = `guide/EFFECTS.md` |
| Every Base def and type | `... base`, `... base Map`, `... base --types`, or `bend2/base.bend` |
| Known limits and non-bugs | `WONTFIX.txt` |
| What changed per release | `CHANGELOG.md` |
| Runtime design | `paper/BendRT.pdf`; type theory `paper/BendTT.pdf` |

The website (bend-lang.com, checked 2026-11-12) shows v2.0.39 and links the
same GUIDE.md; it adds only the installer and its advice to agents (run
`bend guide`, keep rules in `LAWS.bend`, run `PROOF.bend` before committing,
parallelize where measurements support it). `--check-only` is a CLI flag of
this pin, not documented on the site.

[reference.md](reference.md) has the syntax cheat sheet, the error-message
decoder and the performance notes in full.

## Commands

```sh
B="bun $BEND_SOURCE/bend2/main.ts"; export BEND_NO_TELEMETRY=1
$B file.bend --check-only      # type/termination check only, seconds (do this first)
$B file.bend -o out            # native binary (clang 14+; a ! call needs clang 19+/Metal)
$B file.bend -o out.c          # the emitted C: map hot spin_N loops, count term_keep
$B file.bend -o out.js         # the JavaScript lane
$B PROOF.bend --check-only     # required before every implementation commit
./out +RTS --gpu off --threads 1 -RTS   # runtime options live between +RTS and -RTS
```

`--check-only` prints `ALL PROOFS CHECK` or `SOME PROOFS FAIL` and the first
error. A compile of anything importing `jonlib.bend` peaks near 8 GB: one at a
time. A running probe compiles from the working tree, so do not edit library
files under a running probe.

## Rules that the checker enforces (most common errors first)

1. **Define before use.** A def must be above every def that calls it; no
   mutual recursion at all. Error: `expected : a filled definition (an
   unfilled law ...)` naming the callee. Move the callee up. Two
   mutually recursive defs become one def with a selector argument.
2. **Termination reads arguments left to right**: each argument is passed
   unchanged until one is a structurally smaller part of its parameter (from a
   `match`). Put the shrinking argument first. Error: `expected : a
   decreasing self-call`. A changing Bool/accumulator before the shrinking
   list fails; reorder parameters.
3. **`match` only a parameter or a pattern-bound name**, never a computed
   value: `match (x < 3 : U32):` and `match f(y):` are refused (`a parameter
   or field scrutinee`). Pass the value to a helper def that matches its
   parameter.
4. **Scrutinee/binder order**: parameters are destructured in declaration
   order, a matched scalar last; no `let` before a destructuring of a
   parameter (`'x' can't be matched in this position`). Destructure first,
   compute after; or reorder parameters.
5. **Affine by default**: a variable is used at most once. `+x` (in a
   parameter, a pattern or a let) allows reuse and needs a `Data` type.
   `Array`, closures and IO handles are `Type`: never copied. A read of an
   Array returns `(array, value)`.
6. **Annotate everything that is not inferred**: operators need a type,
   `(a + b : U32)`; list literals passed where the type is open need
   `{[1, 2] : +List<U32>}`; constructors in lets `{Vector3{x, y, z} : Vector3}`.
   `Result` is `Done{v}` / `Fail{e}`.
7. **`do` binds are typed** (`x : T <- m`); a `+x = ...` let after a bind
   inside `do` is refused. Put the rest in a helper `def go(+t: U32) -> IO(Unit)`
   and bind into it. Raw form: `IO.bind(A, B, m, f)`.
8. **No negative literals**: `-2.0` is a parse error; write `F32.neg(2.0)`.
   Operators need spaces on both sides. `==` is only the equality *type*;
   compare with `U32.is_eq(a, b)`.
9. **Templates** (`~f`) take closed arguments, come first, and are inlined
   per distinct argument set.
10. **`Bool.pick(T, c, a, b)` is strict**: both branches evaluate (a `%`
    by zero traps), and `Bool.pick(Bool, ...)` feeding `||` is miscompiled on
    the native lanes (diagnostic gate `bend-defects`): use a `match` def.

## Jonlib conventions (see CONTRIBUTING.md "Known pitfalls")

- Library is Bend only; C lives in the reference side (`tools/`). No
  `@unsafe` in library files (`tools/conformance.py source_gate`).
- Keep raylib's float evaluation order exactly; use the numerical profiles
  (`M.Libm`, `M.Contraction`, `_for(profile, ...)` forms) for host-dependent
  results. Strings are C byte strings (UTF-8 bytes as `\u{..}` chars).
- `jonlib.bend` ends with generated enumerations: new sections go above them.
- Long inputs on the JS lane: avoid non-tail `List.take`/`List.append` on
  file-sized lists; keep list literals under ~2000 elements.
- Laws close by evaluation; F32 primitives do not evaluate in the checker.
  When a type changes shape (a field added), update literal values in
  `LAWS.bend` too.

## Performance facts (measured on this repo, M1, 2.0.39)

- `Array<U32>` is a flat buffer natively: about 2.4 ns per get/set pair.
  The `ALeaf`/`ANode` tree is only the logical view; `Array.fork`/`join`
  exist (`@unsafe`) and the parallel shape is a fork tree, not shared writes.
- `Nat` and Base shifts compile to machine operations; Peano style is fine.
- The expensive thing is **sharing**: matching a `+` (shared, reference-
  counted) list or record bumps a count per field (`span_fade`,
  `term_drop` in a profile). Walking a long shared list from its head on
  every call is the classic hot spot (fixed in `src/mixer.bend` with chunks).
- Software-emulated arithmetic (no F64 or U64 in Bend yet) costs microseconds:
  `src/resize_numeric.bend` `Double`, `src/fma.bend`, `src/trig.bend`.
- A process has ~0.18 s fixed startup. `String` is a cons list of chars:
  building big output strings is slow.
- Two CPU threads gain nothing unless the code forks (`a b = f(x) g(y)`) into
  balanced halves. Read `guide shaders` before any parallel or GPU work.

## Benchmarking and profiling Bend code

- **Defeat compile-time evaluation**: a pure `main` or closed computation may
  be folded by Bend or clang (a 100M-iteration loop "taking" 0.01 s). Seed
  inputs from a runtime value, e.g. `t : U32 <- IO.thread_count()` and use
  `(t .&. 0 : U32)` as a zero.
- Time the binary with `+RTS --gpu off --threads 1 -RTS`; repeat runs (the
  first is cold).
- Profile with macOS `sample <pid> <secs> 1 -file out` on the native binary
  (start the process, then attach). Flat defs appear as `spin_N`, others as
  `WL_FID_<path>_<def>`. Map `spin_N` back by compiling to C (`-o x.c`) and
  reading the parameter names of `spin_N`.
- Check equivalence of an optimization by importing the old file version
  (`git show HEAD:src/x.bend > old.bend`) next to the new one and comparing
  results on many inputs in one Bend program, on native and JS lanes.
