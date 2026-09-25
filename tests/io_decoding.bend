import Base
import ../jonlib.bend as J

def confirmed(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.pure(Unit, Unit{})
    case False{}: IO.die(Unit, 1, "expected file/decode error was not preserved")

def expected_error(expected: U32, result: Result<&1, &1, J.Image.LoadError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{J.ImageFileError{_, _}}:
      confirmed(U32.is_eq(expected, 0))
    case Fail{J.ImageDecodeError{J.InvalidImageHeader{}}}:
      confirmed(U32.is_eq(expected, 1))
    case Fail{J.ImageDecodeError{J.UnsupportedImageSize{}}}:
      confirmed(U32.is_eq(expected, 2))
    case _: IO.die(Unit, 1, "expected file/decode error was not preserved")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.bind(Result<&1, &1, J.Image.LoadError, J.Surface>, Unit, J.Surface.load_qoi(".build/qoi-roundtrip.missing"), expected_error(0))
    IO.bind(Result<&1, &1, J.Image.LoadError, J.Surface>, Unit, J.Surface.load_qoi(".build/qoi-roundtrip.bad"), expected_error(1))
    IO.bind(Result<&1, &1, J.Image.LoadError, J.Surface>, Unit, J.Surface.load_qoi(".build/qoi-roundtrip.large"), expected_error(2))
    IO.print("qoi file errors ok")
