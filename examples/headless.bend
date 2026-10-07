# Render a real Jonlib surface without opening a window.
import Base
import ../jonlib.bend as J

def finished(result: Result<&1, &1, J.Surface.IOError, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "image export failed")
    case Done{_}: IO.pure(Unit, Unit{})

def draw(created: Maybe<J.Surface>) -> IO(Unit):
  match created:
    case None{}:
      IO.die(Unit, 1, "image creation failed")
    case Some{surface}:
      red = J.Color.rgba(255, 0, 0, 255)
      blue = J.Color.rgba(0, 0, 255, 255)
      rectangle = J.Surface.draw_rectangle(surface, 8.0, 8.0, 32.0, 24.0, red)
      circle = J.Surface.draw_circle(rectangle, 32.0, 24.0, 12, blue)
      IO.bind(Result<&1, &1, J.Surface.IOError, Unit>, Unit, J.Surface.write_ppm(circle, ".build/headless.ppm"), finished)

def main() -> IO(Unit):
  draw(J.Surface.create(64, 64, J.Color.rgba(0, 0, 0, 255)))
