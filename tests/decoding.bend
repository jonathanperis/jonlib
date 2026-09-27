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

def file_kind(kind: J.Image.FileKind) -> U32:
  match kind:
    case J.QoiFile{}: 0
    case J.RasterFile{}: 1
    case J.UnsupportedImageFile{}: 2

def short_read(result: Result<&1, &1, J.Image.LoadError, J.Surface>) -> Bool:
  match result:
    case Fail{J.ImageDecodeError{J.TruncatedImageData{}}}: True{}
    case _: False{}

def one_color(expected: U32, colors: List<U32>) -> Bool:
  match colors:
    case Con{actual, Nil{}}: U32.is_eq(expected, actual)
    case _: False{}

def decoded_color(expected: U32, result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> Bool:
  match result:
    case Done{J.Surface{1, 1, pixels}}: one_color(expected, J.Surface.colors(J.Surface{1, 1, pixels}))
    case _: False{}

def psd_profiles() -> Bool:
  +bytes = {[56,66,80,83,0,1,0,0,0,0,0,0,0,4,0,0,0,1,0,0,0,1,0,8,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,255,255,255,11] : +List<U32>}
  decoded_color(J.Color.rgba(255, 255, 255, 11), J.Surface.decode_psd(bytes))
    && decoded_color(J.Color.rgba(255, 255, 255, 11), J.Surface.decode_image(".psd", bytes))
    && decoded_color(J.Color.rgba(254, 254, 254, 11), J.Surface.decode_image_for(J.FusedDecode{}, ".psd", bytes))

def checks() -> Bool:
  U32.is_eq(error_code(J.Surface.decode_qoi([113,111,105])), 0)
    && U32.is_eq(error_code(J.Surface.decode_qoi([256])), 1)
    && U32.is_eq(error_code(J.Surface.decode_qoi([113,111,105,102,0,0,16,1,0,0,0,1,4,0,0,0,0,0,0,0,0,1])), 2)
    && U32.is_eq(error_code(J.Surface.decode_qoi([113,111,105,102,0,0,0,1,0,0,0,1,4,0,254,1,2])), 3)
    && U32.is_eq(error_code(J.Surface.decode_qoi([113,111,105,102,0,0,0,1,0,0,0,1,4,0,193,0,0,0,0,0,0,0,1])), 4)
    && U32.is_eq(error_code(J.Surface.decode_qoi([113,111,105,102,0,0,0,1,0,0,0,1,4,0,192,0,0,0,0,0,0,0,2])), 4)
    && U32.is_eq(file_kind(J.Image.file.kind(".png")), 2)
    && U32.is_eq(file_kind(J.Image.file.kind(".jpeg")), 2)
    && U32.is_eq(file_kind(J.Image.file.kind("image.PNG")), 1)
    && U32.is_eq(file_kind(J.Image.file.kind("image.PnG")), 2)
    && short_read(J.Image.file.payload(J.UncontractedDecode{}, J.RasterFile{}, 2, Done{[1]}))
    && psd_profiles()

def verdict(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.print("decode contracts ok")
    case False{}: IO.die(Unit, 1, "decode or file-selection contract failed")

def main() -> IO(Unit):
  verdict(checks())
