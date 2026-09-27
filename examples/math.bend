import Base
import ../jonmath.bend as M

def length() -> F32:
  M.Vector2.length(M.Vector2{3.0, 4.0})

def main() -> IO(Unit):
  IO.print(U32.show(F32.to_u32(length!())))
