import Base
import ../jonlib.bend as J

def pixels_kept(values: List<U32>) -> Bool:
  match values:
    case Con{16909060, Con{16909060, Nil{}}}:
      True{}
    case _:
      False{}

def failed(result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>, expected: U32) -> Bool:
  match result:
    case Done{_}:
      False{}
    case Fail{Tuple{surface, error}}:
      match error:
        case J.InvalidSize{}:
          U32.is_eq(expected, 0) && pixels_kept(J.Surface.colors(surface))
        case J.InvalidRectangle{}:
          U32.is_eq(expected, 1) && pixels_kept(J.Surface.colors(surface))
        case J.UnsafeNearestMapping{}:
          U32.is_eq(expected, 2) && pixels_kept(J.Surface.colors(surface))

def invalid(created: Maybe<J.Surface>, operation: U32) -> Bool:
  match created:
    case None{}:
      False{}
    case Some{surface}:
      match operation:
        case 0:
          failed(J.Surface.resize_nn(surface, 0, 1), 0)
        case 1:
          failed(J.Surface.crop(surface, J.Rectangle{2.0, 0.0, 1.0, 1.0}), 1)
        case _:
          failed(J.Surface.resize_nn(surface, 512, 1), 2)

def pair_failed(result: Result<&1, &1, (J.Surface & J.Surface) & J.Surface.Error, J.Surface & J.Surface>) -> Bool:
  match result:
    case Done{_}:
      False{}
    case Fail{Tuple{Tuple{destination, source}, J.InvalidRectangle{}}}:
      pixels_kept(J.Surface.colors(destination)) && pixels_kept(J.Surface.colors(source))
    case Fail{_}:
      False{}

def invalid_region(pair: J.Surface & J.Surface) -> Bool:
  (destination, source) = pair
  pair_failed(J.Surface.draw_image_region(destination, source,
    J.Rectangle{1.0, 0.0, 2.0, 1.0}, 0.0, 0.0, 4294967295))

def region(created: Maybe<J.Surface>) -> Bool:
  match created:
    case None{}:
      False{}
    case Some{surface}:
      invalid_region(J.Surface.copy(surface))

def verdict(ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("transform contracts ok")
    case False{}:
      IO.die(Unit, 1, "transform error ownership was not preserved")

def checks() -> Bool:
  invalid(J.Surface.create(2, 1, 16909060), 0)
    && invalid(J.Surface.create(2, 1, 16909060), 1)
    && invalid(J.Surface.create(2, 1, 16909060), 2)
    && region(J.Surface.create(2, 1, 16909060))

def main() -> IO(Unit):
  verdict(checks())
