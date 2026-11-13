# Bend 2 reference (pinned 2.0.39)

Condensed from the pinned `guide/GUIDE.md`, `guide/SHADERS.md`, `WONTFIX.txt`
and this repo's experience. When in doubt, the pinned guide wins.

## Syntax cheat sheet

```python
import Base
import ./src/fma.bend as Fma              # a module; M.x names its defs (path: plain names)

type Shape is Data:                        # Data: copyable (+); Type: one owner
  Circle{r: U32}
  Square{s: U32}

def area(x: Shape) -> U32:                 # affine params by default
  match x:
    case Circle{+r}: (3 * r * r : U32)     # +r: reusable field
    case Square{+s}: (s * s : U32)

def f(-A: Data, n: Nat, +x: A) -> List<A>: # -A erased, n affine, +x reusable
def t(~g: U32 -> U32, x: U32) -> U32:      # template (closed arg, inlined)
law add_zero:                              # a claim, proven by def add_zero
  for x: Nat
  {Nat.add(x, 0n) == x : Nat}
```

Terms: `42` U32, `1.5` F32, `3n` Nat, `'c'`, `"s"`; `[a, b]` list, `h <> t`
cons, `(a, b)` tuple, `K{a, b}` constructor, `x => e` lambda, `f!(a)` GPU call,
`[v : T*n]` / `[v : T^d]` array of n / 2^d slots, `a[i]`, `a[i] <- v`.

Statements: `x = v`, `+x = v`, `-x = v`, `(a, b) = v`, `K{x, y} = v`,
`a b = f(x) g(y)` (parallel let), `match a b:` with `case K{x, _} 1n+p:`,
`do M<xs.., R>:` with `x : A <- m`, `x : A = v`, `return v`.

Operators exist only inside `(... : T)`: `+ - * / %`, `.&. .|. .^.`,
`<< >>` (by a Nat), `< <= > >=`. `&&`, `||` on Bool and `++` on String work
anywhere. Nat literal past `256n` is `U32.to_nat(n)` underneath.

Types: `Type = Kind(&1)`, `Data = Kind(&2)`; `List<U32>` = `List<&1, U32>`,
`+List<U32>` = `List<&2, U32>`; `A & B` pair, `A | B` sum, `{a == b : T}`.
A compound type argument needs parens: `Maybe<(U32 & U32)>`.

Base naming: `Type.verb` (`U32.add`, `F32.to_u32`, `U32.to_nat`,
`U32.show`, `U32.read -> Maybe`). Conversions are `T.to_x` / `T.from_x`.
`Array.get(T, a, i) -> Array<T> & T`, `Array.set(T, a, i, v)`,
`Array.swap`, `Array.clone`. `Map` is string-keyed. No F64, no U64 yet.
`F32` from bits: `U32{b} = word; F32{b}` (see `float` in `src/fma.bend`).

## Error decoder

| Message | Meaning and fix |
|---|---|
| `a filled definition (an unfilled law ...)` observed `X` | `X` is defined below its caller (or not at all). Move it up. |
| `a decreasing self-call (arguments are read left to right ...)` | Reorder parameters so the shrinking one comes first and earlier ones pass unchanged. |
| `a parameter or field scrutinee` | Matching a computed value. Use a helper def. |
| `'x' can't be matched in this position` | Matched after a let or after a later binder. Destructure parameters in order, before any let. |
| `an annotated term (cannot infer)` | Add `{... : T}` (list literals, constructors). |
| `a declared constructor (unknown: Ok)` | Wrong constructor name (Result is `Done`/`Fail`). `bend base Result`. |
| `expected : a term, observed : '-'` | Negative literal: `F32.neg(2.0)`. |
| `expected : a term, observed : '~'` | A template argument where none is expected (e.g. no `List.eq`). |
| `an open Array element type` | An Array op without its element type argument resolved. |
| `expected : a pattern (a binder or a constructor)` in a `do` | A `+x = v` after a bind; move the rest into a helper def. |
| `Error: ... an arity over 247` | Too many words in one def/continuation: wrap records. |

## Performance model (GUIDE "Under the Hood" + SHADERS)

- A term is one 64-bit word; no GC; a `match` frees the node it opens. Copying
  a value of a datatype makes its nodes count their fields ("hot type").
- Each def compiles to a segment of a flat state machine; a def with no
  parallel let, bang, closure apply or non-tail self call is *flat*: one native
  tail loop (`spin_N`). A non-tail self call costs a frame per call.
- The compiler decides borrows: a boxed parameter the def only matches or
  passes on is borrowed (`term_peek`, free); one it returns, stores or passes to
  an owner is owned. An owned use of a value used later shares it (counts).
  In emitted C: `term_peek` = borrow; `term_keep`, `ctr_take`, `rfc_seal` =
  counts. A new keep in a hot def is a regression.
- `Bool.pick` on words or trees boxes values; prefer typed pick helpers or a
  `match` def. A `match` on many U32 literals is a bit-by-bit tree (+C size).
- No common-subexpression elimination: bind a value once.
- Parallelism is binary fork-join, contention-free, never rebalanced: halves
  must take about the same time. `!` ships a call to the GPU (16384 lanes, aim
  for 4^7 leaves per bang); `!` only goes to the GPU at the root of an IO step.
  The JS lane is sequential.
- A fast frame is one fork tree ending in flat loops over per-tile lists; a
  per-pixel tree walk or reading a shared scene through counts doubles cost.
- JS lane: F32 NaN payloads and signs are not preserved; deep non-tail
  recursion overflows the host stack.
- Runtime limits: Nat < 2^48, at most 2^24-1 live copies of a `+` value,
  unbalanced Array trees fail-stop, allocation failure is fatal.

## Laws and proofs

`LAWS.bend` states the laws (human-owned), `PROOF.bend` imports it and proves
each with a def of the same name. Proof terms: `{==}` reflexivity, `%e : P`
rewrite, matches refine the goal, recursion is induction, `?name` prints the
goal, `?TODO` leaves it open. `--verdict` rechecks with the Lean-proven
kernel. Jonlib's laws close by evaluation; F32 operations are axioms in the
checker, so state word-level results.
