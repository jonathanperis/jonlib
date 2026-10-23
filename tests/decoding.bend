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
    case J.PngFile{}: 4
    case J.PepFile{}: 5

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

def list_burn(xs: +List<U32>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{_, rest}: list_burn(rest)

def list_eq(expected: +List<U32>, actual: +List<U32>) -> Bool:
  match expected actual:
    case Nil{} Nil{}: True{}
    case Con{+a, erest} Con{+b, arest}: U32.is_eq(a, b) && list_eq(erest, arest)
    case Nil{} Con{_, rest}: list_burn(rest)
    case Con{_, rest} Nil{}: list_burn(rest)

def pep_bytes(result: Result<&1, &1, J.Surface & J.Surface.Error, +List<U32>>) -> Bool:
  match result:
    case Done{bytes}: list_eq([28, 0, 0, 0, 4, 1, 1, 2, 3, 4, 0, 0, 0, 0], bytes)
    case Fail{Tuple{_, _}}: False{}

def pep_format(result: Result<&1, &1, J.Surface & J.Surface.Error, +List<U32>>) -> Bool:
  match result:
    case Fail{Tuple{_, J.UnsupportedFormat{}}}: True{}
    case Fail{Tuple{_, _}}: False{}
    case Done{bytes}: list_burn(bytes)

def pep_size(result: Result<&1, &1, J.Surface & J.Surface.Error, +List<U32>>) -> Bool:
  match result:
    case Fail{Tuple{_, J.UnsupportedImageSize{}}}: True{}
    case Fail{Tuple{_, _}}: False{}
    case Done{bytes}: list_burn(bytes)

def pep_export() -> Bool:
  pep_bytes(J.Surface.to_pep(J.Surface{1, 1, 7, J.Words{Array.set(U32, Array.new(U32, 0n, 0), 0, J.Color.rgba(1, 2, 3, 4))}}))
    && pep_format(J.Surface.to_pep(J.Surface{1, 1, 4, J.Words{Array.new(U32, 0n, 0)}}))
    && pep_size(J.Surface.to_pep(J.Surface{4097, 1, 7, J.Words{Array.new(U32, 0n, 0)}}))

def checks() -> Bool:
  U32.is_eq(error_code(J.Surface.decode_qoi([113,111,105])), 0)
    && U32.is_eq(error_code(J.Surface.decode_qoi([256])), 1)
    && U32.is_eq(error_code(J.Surface.decode_qoi([113,111,105,102,0,0,16,1,0,0,0,1,4,0,0,0,0,0,0,0,0,1])), 2)
    && U32.is_eq(error_code(J.Surface.decode_qoi([113,111,105,102,0,0,0,1,0,0,0,1,4,0,254,1,2])), 3)
    && U32.is_eq(error_code(J.Surface.decode_qoi([113,111,105,102,0,0,0,1,0,0,0,1,4,0,193,0,0,0,0,0,0,0,1])), 4)
    && U32.is_eq(error_code(J.Surface.decode_qoi([113,111,105,102,0,0,0,1,0,0,0,1,4,0,192,0,0,0,0,0,0,0,2])), 4)
    && U32.is_eq(file_kind(J.Image.file.kind(".png")), 2)
    && U32.is_eq(file_kind(J.Image.file.kind(".jpeg")), 2)
    && U32.is_eq(file_kind(J.Image.file.kind("image.PNG")), 4)
    && U32.is_eq(file_kind(J.Image.file.kind("image.png")), 4)
    && U32.is_eq(file_kind(J.Image.file.kind("image.PnG")), 2)
    && U32.is_eq(file_kind(J.Image.file.kind("image.BMP")), 1)
    && U32.is_eq(J.Image.file.limit(J.Image.file.kind("image.png")), 2097152)
    && U32.is_eq(J.Image.file.limit(J.Image.file.kind("image.BMP")), 1048576)
    && U32.is_eq(file_kind(J.Image.file.kind("texture.dds")), 3)
    && U32.is_eq(file_kind(J.Image.file.kind("texture.DDS")), 3)
    && U32.is_eq(file_kind(J.Image.file.kind("texture.Dds")), 2)
    && short_read(J.Image.file.payload(2, Done{[1]}))
    && raw_short_read(J.Image.raw.payload(12, Done{[0,0,0,0]}))
    && String.eq(J.Image.Animation.file.token(J.Image.file.token(".GiF")), "")
    && U32.is_eq(file_kind(J.Image.file.kind("sprite.pep")), 5)
    && U32.is_eq(file_kind(J.Image.file.kind("sprite.PEP")), 5)
    && U32.is_eq(file_kind(J.Image.file.kind("sprite.Pep")), 2)
    && U32.is_eq(J.Image.file.limit(J.PepFile{}), 65536)
    && U32.is_eq(J.Image.export.kind("sprite.PeP"), 6)
    && U32.is_eq(error_code(J.Surface.decode_image(".pep", [])), 0)
    && U32.is_eq(error_code(J.Surface.decode_image(".pep", [60])), 0)
    && decoded_color(J.Color.rgba(255, 0, 0, 0), J.Surface.decode_image(".pep", [60, 0, 0, 0, 4, 1, 255, 0, 0, 0, 0, 0, 0]))
    && decoded_color(J.Color.rgba(1, 0, 0, 0), J.Surface.decode_image(".PEP", [28, 0, 0, 0, 4, 1, 1, 2, 3, 4, 0, 0, 0, 0]))
    && pep_export()
    && psd_profiles()

def verdict(ok: Bool) -> IO(Unit):
  match ok:
    case True{}: IO.print("decode contracts ok")
    case False{}: IO.die(Unit, 1, "decode or file-selection contract failed")

def main() -> IO(Unit):
  verdict(checks())
