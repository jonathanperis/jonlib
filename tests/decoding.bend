import Base
import ../jonlib.bend as J

def error_code(result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> U32:
  match result:
    case Done{_}: 99
    case Fail{error}:
      match error:
        case J.InvalidImageHeader{}: 0
        case J.InvalidImageByte{}: 1
        case J.UnsupportedImageSize{}: 2
        case J.TruncatedImageData{}: 3
        case J.InvalidImageStream{}: 4

def checks() -> Bool:
  U32.is_eq(error_code(J.Surface.decode_qoi([113,111,105])), 0)
    && U32.is_eq(error_code(J.Surface.decode_qoi([256])), 1)
    && U32.is_eq(error_code(J.Surface.decode_qoi([113,111,105,102,0,0,16,1,0,0,0,1,4,0,0,0,0,0,0,0,0,1])), 2)
    && U32.is_eq(error_code(J.Surface.decode_qoi([113,111,105,102,0,0,0,1,0,0,0,1,4,0,254,1,2])), 3)
    && U32.is_eq(error_code(J.Surface.decode_qoi([113,111,105,102,0,0,0,1,0,0,0,1,4,0,193,0,0,0,0,0,0,0,1])), 4)
    && U32.is_eq(error_code(J.Surface.decode_qoi([113,111,105,102,0,0,0,1,0,0,0,1,4,0,192,0,0,0,0,0,0,0,2])), 4)

def verdict(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.print("decode contracts ok")
    case False{}: IO.die(Unit, 1, "invalid QOI input was accepted or misclassified")

def main() -> IO(Unit):
  verdict(checks())
