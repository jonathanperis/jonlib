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
        case 7:
          failed(J.Surface.resize_canvas(surface, 3, 2, 3.0, 0.0, 0), 1)
        case 8:
          failed(J.Surface.rotate_degrees(surface, 361.0), 1)
        case _:
          failed(J.Surface.rotate_degrees(surface, 0.5), 1)

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

def rotation_last(result: Array<U32> & U32) -> Bool:
  (_, pixel) = result
  U32.is_eq(pixel, 16909060)

def rotation_too_large(result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> Bool:
  match result:
    case Fail{Tuple{J.Surface{w, h, pixels}, J.InvalidSize{}}}:
      U32.is_eq(w, 4096) && U32.is_eq(h, 128) && rotation_last(Array.get(U32, pixels, 524287))
    case _: False{}

def rotation_size(created: Maybe<J.Surface>) -> Bool:
  match created:
    case None{}: False{}
    case Some{surface}: rotation_too_large(J.Surface.rotate_degrees(surface, 1.0))

def channel_pixels(values: List<U32>) -> Bool:
  match values:
    case Con{33686271, Con{33686271, Nil{}}}: True{}
    case _: False{}

def channel_owners(pair: J.Surface & J.Surface) -> Bool:
  (source, extracted) = pair
  pixels_kept(J.Surface.colors(source)) && channel_pixels(J.Surface.colors(extracted))

def channel_created(created: Maybe<J.Surface>) -> Bool:
  match created:
    case None{}: False{}
    case Some{surface}: channel_owners(J.Surface.from_channel(surface, 1.0))

def random_word(result: J.Random.State & F32) -> U32:
  (_, value) = result
  F32.bits(value)

def noise_rejected(result: J.Random.State & Maybe<J.Surface>) -> Bool:
  match result:
    case Tuple{state, None{}}:
      U32.is_eq(random_word(J.Random.value(state, 0.0, 99.0)), random_word(J.Random.value(J.Random.seed(123), 0.0, 99.0)))
    case _: False{}

def sequence_rejected(result: J.Random.State & Result<&1, &1, J.Random.Sequence.Error, J.Random.Sequence>) -> Bool:
  match result:
    case Tuple{state, Fail{J.InvalidSequenceRequest{}}}:
      U32.is_eq(random_word(J.Random.value(state, 0.0, 99.0)), random_word(J.Random.value(J.Random.seed(123), 0.0, 99.0)))
    case _: False{}

def sequence_budget_owner(values: +List<F32>, state: J.Random.State, baseline: J.Random.State & F32) -> Bool:
  match values baseline:
    case Con{value, Nil{}} Tuple{original, expected}:
      F32.is_eq(value, expected) && U32.is_eq(random_word(J.Random.value(state, 0.0, 99.0)), random_word(J.Random.value(original, 0.0, 99.0)))
    case _ _: False{}

def sequence_budget(result: J.Random.State & Result<&1, &1, J.Random.Sequence.Error, J.Random.Sequence>) -> Bool:
  match result:
    case Tuple{state, Fail{J.SequenceDrawLimit{partial}}}:
      sequence_budget_owner(J.Random.Sequence.values(partial), state, J.Random.value(J.Random.seed(123), 0.0, 1.0))
    case _: False{}

def sequence_unloaded(unit: Unit) -> Bool:
  match unit:
    case Unit{}: True{}

def sequence_empty(result: J.Random.State & Result<&1, &1, J.Random.Sequence.Error, J.Random.Sequence>) -> Bool:
  match result:
    case Tuple{state, Done{sequence}}:
      sequence_unloaded(J.Random.unload_sequence(sequence))
        && U32.is_eq(random_word(J.Random.value(state, 0.0, 99.0)), random_word(J.Random.value(J.Random.seed(123), 0.0, 99.0)))
    case _: False{}

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
    && invalid(J.Surface.create(2, 1, 16909060), 8)
    && invalid(J.Surface.create(2, 1, 16909060), 9)
    && region(J.Surface.create(2, 1, 16909060))
    && scaled(J.Surface.create(2, 1, 16909060), 0)
    && scaled(J.Surface.create(2, 1, 16909060), 1)
    && scaled(J.Surface.create(2, 1, 16909060), 2)
    && mask_sizes(J.Surface.create(2, 1, 16909060), J.Surface.create(1, 2, 16909060))
    && no_surface(J.Surface.create_checked(1, 1, 0, 1, 0, 4294967295))
    && no_surface(J.Surface.create_checked(0, 1, 1, 1, 0, 4294967295))
    && no_surface(J.Surface.create_gradient_square(1, 1, 1.5, 0, 4294967295))
    && no_surface(J.Surface.create_gradient_square(0, 1, 0.5, 0, 4294967295))
    && no_surface(J.Surface.create_gradient_radial(1, 1, 1.5, 0, 4294967295))
    && no_surface(J.Surface.create_gradient_linear(1, 1, 90.0, 0, 4294967295))
    && no_surface(J.Surface.create_gradient_linear(3, 2, 0.5, 0, 4294967295))
    && no_surface(J.Surface.create_gradient_linear(3, 2, 361.0, 0, 4294967295))
    && rotation_size(J.Surface.create(4096, 128, 16909060))
    && channel_created(J.Surface.create(2, 1, 16909060))
    && noise_rejected(J.Surface.create_white_noise(J.Random.seed(123), 0, 2, 0.5))
    && noise_rejected(J.Surface.create_white_noise(J.Random.seed(123), 2, 2, F32.neg(0.1)))
    && sequence_rejected(J.Random.load_sequence(J.Random.seed(123), 1, 0.5, 1.0, 1n))
    && sequence_rejected(J.Random.load_sequence(J.Random.seed(123), 3, 0.0, 1.0, 8n))
    && sequence_budget(J.Random.load_sequence(J.Random.seed(123), 2, 0.0, 1.0, 1n))
    && sequence_empty(J.Random.load_sequence(J.Random.seed(123), 0, 0.0, 0.0, 0n))
    && noise_rejected(J.Surface.create_cellular(J.Random.seed(123), 2, 2, 0))
    && noise_rejected(J.Surface.create_cellular(J.Random.seed(123), 4097, 1, 1))

def main() -> IO(Unit):
  verdict(checks())
