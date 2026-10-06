import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

def rejected(value: Maybe<J.Surface>) -> Bool:
  match value:
    case None{}:
      True{}
    case Some{_}:
      False{}

def after_outside(result: J.Surface & Maybe<&2, U32>, ok: Bool) -> Bool:
  match result:
    case Tuple{_, None{}}:
      ok
    case Tuple{_, Some{_}}:
      False{}

def after_changed(result: J.Surface & Maybe<&2, U32>, ok: Bool) -> Bool:
  match result:
    case Tuple{surface, Some{value}}:
      after_outside(J.Surface.get(surface, 3, 0), Bool.and(ok, U32.is_eq(value, 2864434397)))
    case Tuple{_, None{}}:
      False{}

def after_original(changed: J.Surface, result: J.Surface & Maybe<&2, U32>) -> Bool:
  match result:
    case Tuple{_, Some{value}}:
      after_changed(J.Surface.get(changed, 2, 4), U32.is_eq(value, 16909060))
    case Tuple{_, None{}}:
      False{}

def copied(pair: J.Surface & J.Surface) -> Bool:
  (original, duplicate) = pair
  after_original(J.Surface.draw_pixel(duplicate, 2.0, 4.0, 2864434397), J.Surface.get(original, 2, 4))

def owned(created: Maybe<J.Surface>) -> Bool:
  match created:
    case None{}:
      False{}
    case Some{surface}:
      copied(J.Surface.copy(surface))

# Sample Base.Image independently of the library's conversion implementation.
def image_pixel(+depth: Nat, image: Image, +x: U32, +y: U32) -> U32:
  match depth image:
    case _ Pix{color}:
      color
    case 0n Qua{_, _, _, _}:
      4294967295
    case 1n+k Qua{a, b, c, d}:
      +half = U32.shln(1, k)
      +right = U32.is_ne((x .&. half : U32), 0)
      bottom = U32.is_ne((y .&. half : U32), 0)
      image_pixel(k, Bool.pick(Image, bottom, Bool.pick(Image, right, d, c),
        Bool.pick(Image, right, b, a)), x, y)

def image_matches(colors: List<U32>, +image: Image, +index: U32) -> Bool:
  match colors:
    case Nil{}:
      True{}
    case Con{color, rest}:
      Bool.and(U32.is_eq(image_pixel(3n, image, (index % 3 : U32), (index / 3 : U32)),
        (color >> 8n : U32)), image_matches(rest, image, (index + 1 : U32)))

def converted(pair: J.Surface & J.Surface) -> Bool:
  (source, copy) = pair
  +image = J.Surface.to_image(copy)
  image_matches(J.Surface.colors(source), image, 0)
    && U32.is_eq(image_pixel(3n, image, 7, 7), 0)
    && U32.is_eq(image_pixel(3n, image, 3, 1), 0)

def adapter(created: Maybe<J.Surface>) -> Bool:
  match created:
    case None{}:
      False{}
    case Some{surface}:
      a = J.Surface.draw_pixel(surface, 0.0, 0.0, 4278190335)
      b = J.Surface.draw_pixel(a, 2.0, 4.0, 65535)
      c = J.Surface.draw_pixel(b, 1.0, 3.0, 287454020)
      converted(J.Surface.copy(c))

# Large inputs that once overflowed the JS lane's stack (per-pixel/per-value
# non-tail recursion). Every helper here is tail-recursive on purpose.
def text_length(text: String, +n: U32) -> U32:
  match text:
    case SNil{}: n
    case SCon{_, rest}: text_length(rest, (n + 1 : U32))

def large_ppm(created: Maybe<J.Surface>) -> Bool:
  match created:
    case None{}:
      False{}
    case Some{surface}:
      U32.is_eq(text_length(J.Surface.to_ppm(surface), 0), 6291473)

def sequence_sum(values: +List<F32>, +count: U32, +sum: U32) -> U32 & U32:
  match values:
    case Nil{}: (count, sum)
    case Con{+value, rest}: sequence_sum(rest, (count + 1 : U32), (sum + F32.to_u32(value) : U32))

def permutation(totals: U32 & U32) -> Bool:
  (+count, +sum) = totals
  U32.is_eq(count, 30000) && U32.is_eq(sum, 449985000)

def large_sequence(result: J.Random.State & Result<&1, &1, J.Random.Sequence.Error, J.Random.Sequence>) -> Bool:
  (_, outcome) = result
  match outcome:
    case Fail{_}:
      False{}
    case Done{sequence}:
      permutation(sequence_sum(J.Random.Sequence.values(sequence), 0, 0))

# Bottom edge sampled at every integer x, closed by (n,n) and (0,n).
def comb(n: Nat, acc: +List<M.Vector2>) -> +List<M.Vector2>:
  match n:
    case 0n: Con{M.Vector2{0.0, 0.0}, acc}
    case 1n+(+k): comb(k, Con{M.Vector2{U32.to_f32(U32.from_nat(1n+k)), 0.0}, acc})

def large_polygon(+points: +List<M.Vector2>) -> Bool:
  J.Collision.point_poly(M.Vector2{0.5, 0.5}, points)
    && Bool.not(J.Collision.point_poly(M.Vector2{F32.neg(1.0), 0.5}, points))

def verdict(ok: Bool) -> IO(Unit):
  match ok:
    case False{}:
      IO.die(Unit, 1, "Jonlib ownership/color/adapter contract failed")
    case True{}:
      IO.print("contracts ok")

def main() -> IO(Unit):
  verdict(rejected(J.Surface.create(0, 1, 0))
    && rejected(J.Surface.create(1, 4097, 0))
    && owned(J.Surface.create(3, 5, 16909060))
    && adapter(J.Surface.create(3, 5, 151653132))
    && U32.is_eq(J.Color.rgba(257, 258, 259, 260), 16909060)
    && U32.is_eq(J.Color.red(16909060), 1)
    && U32.is_eq(J.Color.green(16909060), 2)
    && U32.is_eq(J.Color.blue(16909060), 3)
    && U32.is_eq(J.Color.alpha(16909060), 4)
    && large_ppm(J.Surface.create(1024, 1024, 66051))
    && large_sequence(J.Random.load_sequence(J.Random.seed(7), 30000, 0.0, 29999.0, 100000000n))
    && large_polygon(comb(60000n, Con{M.Vector2{60000.0, 60000.0}, Con{M.Vector2{0.0, 60000.0}, Nil{}}})))
