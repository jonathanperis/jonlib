# A headless scene exercising the current primitive/compositing batch.
import Base
import ../jonlib.bend as J

def save(pair: J.Surface & J.Surface) -> IO(Unit):
  (destination, source) = pair
  IO.try(Unit, J.Surface.write_ppm(destination, ".build/composite.ppm"))

def with_icon(destination: J.Surface, created: Maybe<J.Surface>) -> IO(Unit):
  match created:
    case None{}:
      IO.die(Unit, 1, "icon creation failed")
    case Some{source}:
      a = J.Surface.draw_pixel(source, 0.0, 0.0, J.Color.rgba(255, 80, 40, 255))
      b = J.Surface.draw_pixel(a, 1.0, 0.0, J.Color.rgba(80, 160, 255, 128))
      c = J.Surface.draw_pixel(b, 0.0, 1.0, J.Color.rgba(220, 40, 240, 200))
      d = J.Surface.draw_pixel(c, 1.0, 1.0, J.Color.rgba(255, 255, 255, 0))
      save(J.Surface.draw_image(destination, d, 30.0, 25.0, J.Color.rgba(255, 200, 255, 220)))

def draw(created: Maybe<J.Surface>) -> IO(Unit):
  match created:
    case None{}:
      IO.die(Unit, 1, "image creation failed")
    case Some{surface}:
      +a = {J.Vector2{4.0, 40.0} : J.Vector2}
      +b = {J.Vector2{32.0, 5.0} : J.Vector2}
      +c = {J.Vector2{60.0, 40.0} : J.Vector2}
      filled = J.Surface.draw_triangle(surface, a, b, c, J.Color.rgba(40, 170, 100, 255))
      outlined = J.Surface.draw_triangle_lines(filled, a, b, c, J.Color.rgba(230, 240, 255, 255))
      ground = J.Surface.draw_line(outlined, 2.0, 44.0, 62.0, 44.0, J.Color.rgba(255, 210, 40, 255))
      with_icon(ground, J.Surface.create(2, 2, 0))

def main() -> IO(Unit):
  draw(J.Surface.create(64, 48, J.Color.rgba(18, 26, 40, 255)))
