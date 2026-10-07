import Base
import ../jonlib.bend as J
import ../jonmath.bend as M

def error_code(result: Result<&1, &1, J.Surface.Error, J.Surface>) -> U32:
  match result:
    case Done{_}: 99
    case Fail{error}:
      match error:
        case J.InvalidImageHeader{}: 0
        case J.InvalidImageByte{}: 1
        case J.UnsupportedImageSize{}: 2
        case J.TruncatedImageData{}: 3
        case J.InvalidImageStream{}: 4
        case _: 98

def file_kind(kind: J.Image.FileKind) -> U32:
  match kind:
    case J.QoiFile{}: 0
    case J.RasterFile{}: 1
    case J.UnsupportedImageFile{}: 2
    case J.DdsFile{}: 3

def short_read(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> Bool:
  match result:
    case Fail{J.DataError{J.TruncatedImageData{}}}: True{}
    case _: False{}

def raw_short_read(result: Result<&1, &1, J.Surface.IOError, +List<U32>>) -> Bool:
  match result:
    case Fail{J.DataError{J.TruncatedImageData{}}}: True{}
    case _: False{}

def one_color(expected: U32, colors: List<U32>) -> Bool:
  match colors:
    case Con{actual, Nil{}}: U32.is_eq(expected, actual)
    case _: False{}

def surface_colors(expected: U32, result: Result<&1, &1, J.Surface & J.Surface.Error, List<U32>>) -> Bool:
  match result:
    case Done{colors}: one_color(expected, colors)
    case _: False{}

def decoded_color(expected: U32, result: Result<&1, &1, J.Surface.Error, J.Surface>) -> Bool:
  match result:
    case Done{J.Surface{1, 1, format, pixels}}: surface_colors(expected, J.Surface.colors(J.Surface{1, 1, format, pixels}))
    case _: False{}

def psd_profiles() -> Bool:
  +bytes = {[56,66,80,83,0,1,0,0,0,0,0,0,0,4,0,0,0,1,0,0,0,1,0,8,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,255,255,255,11] : +List<U32>}
  decoded_color(J.Color.rgba(255, 255, 255, 11), J.Surface.decode_psd(bytes))
    && decoded_color(J.Color.rgba(255, 255, 255, 11), J.Surface.decode_image(".psd", bytes))
    && decoded_color(J.Color.rgba(254, 254, 254, 11), J.Surface.decode_image_for(M.Fused{}, ".psd", bytes))

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
    && U32.is_eq(file_kind(J.Image.file.kind("texture.dds")), 3)
    && U32.is_eq(file_kind(J.Image.file.kind("texture.DDS")), 3)
    && U32.is_eq(file_kind(J.Image.file.kind("texture.Dds")), 2)
    && short_read(J.Image.file.payload(2, Done{[1]}))
    && raw_short_read(J.Image.raw.payload(12, Done{[0,0,0,0]}))
    && String.eq(J.Image.Animation.file.token(J.Image.file.token(".GiF")), "")
    && psd_profiles()

def verdict(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.print("decode contracts ok")
    case False{}: IO.die(Unit, 1, "decode or file-selection contract failed")

def main() -> IO(Unit):
  verdict(checks())
