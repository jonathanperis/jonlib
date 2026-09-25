import Base
import ../jonlib.bend as J

def loaded(result: Result<&1, &1, J.Image.LoadError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "QOI file load failed")
    case Done{J.Surface{+w, +h, pixels}}:
      IO.print("{\"id\":\"qoi-all-opcodes\",\"width\":" ++ U32.show(w) ++ ",\"height\":" ++ U32.show(h)
        ++ ",\"pixels\":" ++ List.show(~&1, ~U32, ~U32.show, J.Surface.colors(J.Surface{w, h, pixels})) ++ "}")

def written(result: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "QOI file export failed")
    case Done{_}: IO.bind(Result<&1, &1, J.Image.LoadError, J.Surface>, Unit, J.Surface.load_qoi(".build/qoi-roundtrip.qoi"), loaded)

def decoded(result: Result<&1, &1, J.Image.DecodeError, J.Surface>) -> IO(Unit):
  match result:
    case Fail{_}: IO.die(Unit, 1, "QOI input decode failed")
    case Done{image}:
      IO.bind(Result<&1, &1, U32 & String, Unit>, Unit, J.Surface.write_qoi(image, ".build/qoi-roundtrip.qoi"), written)

def main() -> IO(Unit):
  decoded(J.Surface.decode_qoi([113,111,105,102,0,0,0,4,0,0,0,2,4,0,254,10,20,30,118,165,107,255,200,100,50,64,193,9,77,0,0,0,0,0,0,0,1]))
