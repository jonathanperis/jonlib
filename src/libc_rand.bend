# Jonlib - zlib license, Copyright (c) 2026 Jonathan Peris.
# glibc's rand() and srand(): the additive feedback generator random_r runs
# for its default TYPE_3 state, x[i] = x[i-31] + x[i-3] (mod 2^32) with the
# output x[i] >> 1. srand fills 31 words with the minimal standard generator
# (16807*x mod 2^31 - 1) from the seed and discards the first 310 values.
# Written from the algorithm's published description (no glibc source);
# tools/rand_probe.py compares it with the host's rand() on glibc hosts.
import Base

# The last 31 words, the oldest first.
type Rand is Data:
  Rand{window: +List<U32>}

# 16807*r mod 2147483647 by Schrage's method, for 0 < r < 2^31.
def lcg(+r: U32) -> U32:
  +a = (16807 * (r % 127773) : U32)
  +b = (2836 * (r / 127773) : U32)
  Bool.pick(U32, (a >= b : U32), (a - b : U32), (a + 2147483647 - b : U32))

def seeds(n: Nat, +r: U32) -> +List<U32>:
  match n:
    case 0n: Nil{}
    case 1n+p: Con{r, seeds(p, lcg(r))}

def head(words: +List<U32>) -> U32:
  match words:
    case Nil{}: 0
    case Con{+word, _}: word

def tail(words: +List<U32>) -> +List<U32>:
  match words:
    case Nil{}: Nil{}
    case Con{_, +rest}: rest

# The next word: the oldest plus the third newest.
def word(+window: +List<U32>) -> U32:
  (head(window) + head(List.drop(&2, U32, window, 28n)) : U32)

def advance(+window: +List<U32>) -> +List<U32>:
  List.append(&2, U32, tail(window), Con{word(window), Nil{}})

def discard(n: Nat, +window: +List<U32>) -> +List<U32>:
  match n:
    case 0n: window
    case 1n+p: discard(p, advance(window))

# The window after the seeds r[0..30]: r[3..30] then r[0..2] (the words 31 to 33 repeat the first three).
def primed(+r: +List<U32>) -> +List<U32>:
  List.append(&2, U32, List.drop(&2, U32, r, 3n), List.take(&2, U32, r, 3n))

# srand(seed) for a seed below 2^31 (0 seeds as 1, as glibc does); None for a larger one, which glibc treats as a negative int.
def seed(+seed: U32) -> Maybe<Rand>:
  Bool.pick(Maybe<Rand>, (seed < 2147483648 : U32), Some{Rand{discard(310n, primed(seeds(31n, Bool.pick(U32, U32.is_eq(seed, 0), 1, seed))))}}, None{})

# rand(): the next value (31 bits) and the generator after it.
def next(rand: Rand) -> Rand & U32:
  Rand{+window} = rand
  (Rand{advance(window)}, (word(window) >> 1n : U32))

# The value rand() gives next, for a seeded generator.
def value(rand: Maybe<Rand>) -> Maybe<U32>:
  match rand:
    case None{}: None{}
    case Some{Rand{+window}}: Some{(word(window) >> 1n : U32)}
