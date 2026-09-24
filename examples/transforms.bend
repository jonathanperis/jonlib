import Base
import ../jonlib.bend as J

def save(result: Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}:
      IO.die(Unit, 1, "image transformation failed")
    case Done{surface}:
      IO.try(Unit, J.Surface.write_ppm(surface, ".build/transforms.ppm"))

def transform(surface: J.Surface) -> Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
  do Result<&1, &1, J.Surface & J.Surface.Error, J.Surface>:
    cropped : J.Surface <- J.Surface.crop(surface, J.Rectangle{1.0, 0.0, 4.0, 5.0})
    J.Surface.resize_nn(cropped, 32, 40)

def draw(created: Maybe<J.Surface>) -> IO(Unit):
  match created:
    case None{}:
      IO.die(Unit, 1, "image creation failed")
    case Some{surface}:
      top = J.Surface.draw_rectangle(surface, 1.0, 0.0, 4.0, 1.0, J.Color.rgba(240, 240, 255, 255))
      +orange = J.Color.rgba(255, 140, 40, 255)
      stem = J.Surface.draw_rectangle(top, 3.0, 1.0, 1.0, 4.0, orange)
      base = J.Surface.draw_rectangle(stem, 1.0, 4.0, 3.0, 1.0, orange)
      hooked = J.Surface.draw_pixel(base, 1.0, 3.0, orange)
      save(transform(hooked))

def main() -> IO(Unit):
  draw(J.Surface.create(6, 6, J.Color.rgba(32, 24, 64, 255)))
