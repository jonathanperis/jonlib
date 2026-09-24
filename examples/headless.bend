# Render a real Jonlib surface without opening a window.
import Base
import ../jonlib.bend as J

def draw(created: Maybe<J.Surface>) -> IO(Unit):
  match created:
    case None{}:
      IO.die(Unit, 1, "image creation failed")
    case Some{surface}:
      red = J.Color.rgba(255, 0, 0, 255)
      blue = J.Color.rgba(0, 0, 255, 255)
      rectangle = J.Surface.draw_rectangle(surface, 8.0, 8.0, 32.0, 24.0, red)
      circle = J.Surface.draw_circle(rectangle, 32.0, 24.0, 12, blue)
      IO.try(Unit, J.Surface.write_ppm(circle, ".build/headless.ppm"))

def main() -> IO(Unit):
  draw(J.Surface.create(64, 64, J.Color.rgba(0, 0, 0, 255)))
