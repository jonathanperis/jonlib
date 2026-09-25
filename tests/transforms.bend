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
        case 2:
          failed(J.Surface.resize_nn(surface, 512, 1), 2)
        case 3:
          failed(J.Surface.resize(surface, 0, 1), 0)
        case 4:
          failed(J.Surface.resize(surface, 1, 4097), 0)
        case 5:
          failed(J.Surface.resize_canvas(surface, 0, 2, 0.0, 0.0, 0), 0)
        case 6:
          failed(J.Surface.resize_canvas(surface, 3, 2, 0.5, 0.0, 0), 1)
        case _:
          failed(J.Surface.resize_canvas(surface, 3, 2, 3.0, 0.0, 0), 1)

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

def invalid_scaled(pair: J.Surface & J.Surface, operation: U32) -> Bool:
  (destination, source) = pair
  match operation:
    case 0:
      pair_failed(J.Surface.draw_image_rect(destination, source, J.Rectangle{3.0, 0.0, 1.0, 1.0},
        J.Rectangle{0.0, 0.0, 4.0, 3.0}, 4294967295))
    case 1:
      pair_failed(J.Surface.draw_image_rect(destination, source, J.Rectangle{0.0, 0.0, 2.0, 1.0},
        J.Rectangle{0.0, 0.0, 4097.0, 1.0}, 4294967295))
    case _:
      pair_failed(J.Surface.draw_image_rect(destination, source, J.Rectangle{0.0, 0.0, 0.5, 1.0},
        J.Rectangle{0.0, 0.0, 4.0, 3.0}, 4294967295))

def scaled(created: Maybe<J.Surface>, operation: U32) -> Bool:
  match created:
    case None{}: False{}
    case Some{surface}: invalid_scaled(J.Surface.copy(surface), operation)

def invalid_mask(result: Result<&1, &1, (J.Surface & J.Surface) & J.Surface.Error, J.Surface & J.Surface>) -> Bool:
  match result:
    case Fail{Tuple{Tuple{destination, source}, J.InvalidSize{}}}:
      pixels_kept(J.Surface.colors(destination)) && pixels_kept(J.Surface.colors(source))
    case _: False{}

def mask_sizes(destination: Maybe<J.Surface>, source: Maybe<J.Surface>) -> Bool:
  match destination source:
    case Some{dst} Some{mask}: invalid_mask(J.Surface.alpha_mask(dst, mask))
    case _ _: False{}

def no_surface(result: Maybe<J.Surface>) -> Bool:
  match result:
    case None{}: True{}
    case Some{_}: False{}

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
    && invalid(J.Surface.create(2, 1, 16909060), 3)
    && invalid(J.Surface.create(2, 1, 16909060), 4)
    && invalid(J.Surface.create(2, 1, 16909060), 5)
    && invalid(J.Surface.create(2, 1, 16909060), 6)
    && invalid(J.Surface.create(2, 1, 16909060), 7)
    && region(J.Surface.create(2, 1, 16909060))
    && scaled(J.Surface.create(2, 1, 16909060), 0)
    && scaled(J.Surface.create(2, 1, 16909060), 1)
    && scaled(J.Surface.create(2, 1, 16909060), 2)
    && mask_sizes(J.Surface.create(2, 1, 16909060), J.Surface.create(1, 2, 16909060))
    && no_surface(J.Surface.create_checked(1, 1, 0, 1, 0, 4294967295))
    && no_surface(J.Surface.create_checked(0, 1, 1, 1, 0, 4294967295))
    && no_surface(J.Surface.create_gradient_square(1, 1, 1.5, 0, 4294967295))
    && no_surface(J.Surface.create_gradient_square(0, 1, 0.5, 0, 4294967295))

def main() -> IO(Unit):
  verdict(checks())
