#!/usr/bin/env python3
"""Check the generated header modules jonlgl.bend, joncamera.bend and jongestures.bend.

The modules must be what tools/facades.py generates from the API ledger and
jonlib.bend (a stale module fails), and a program importing all three must
compile and give, on every lane, the values Jonlib's own definitions give:
rlgl's version, a macro constant and the default far clip plane through
jonlgl, a camera's forward vector through joncamera and a fresh core's
detected gesture through jongestures. Bend-only: the definitions delegate to
Jonlib's, whose gates compare them with raylib. CPU-1, CPU-2 and JavaScript
lanes.
"""
import facades
import probekit
from probekit import ProbeFailure

PROGRAM = '''import Base
import ../../jonmath.bend as M
import ../../jonlib.bend as J
import ../../jonlgl.bend as Lgl
import ../../joncamera.bend as Cam
import ../../jongestures.bend as Gest
def vec(v: M.Vector3) -> String:
  M.Vector3{x, y, z} = v
  U32.show(F32.bits(x)) ++ " " ++ U32.show(F32.bits(y)) ++ " " ++ U32.show(F32.bits(z))
def camera() -> J.Camera3D:
  J.Camera3D{M.Vector3{2.0, 4.0, 6.0}, M.Vector3{0.0, 0.5, 0.0}, M.Vector3{0.0, 1.0, 0.0}, 45.0, 0}
def far(r: J.Frame & M.Float64) -> String:
  (_, value) = r
  M.Float64{high, low} = value
  U32.show(high) ++ " " ++ U32.show(low)
def far.of(frame: Maybe<J.Frame>) -> String:
  match frame:
    case None{}: "no frame"
    case Some{f}: far(Lgl.Rlgl.get_cull_distance_far(f))
def far.jonlib(frame: Maybe<J.Frame>) -> String:
  match frame:
    case None{}: "no frame"
    case Some{f}: far(J.Rlgl.get_cull_distance_far(f))
def gesture(core: Maybe<J.Core>) -> String:
  match core:
    case None{}: "no core"
    case Some{c}: U32.show(Gest.Gestures.get_detected(c))
def gesture.jonlib(core: Maybe<J.Core>) -> String:
  match core:
    case None{}: "no core"
    case Some{c}: U32.show(J.Gestures.get_detected(c))
def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(Lgl.Rlgl.get_version()) ++ " " ++ U32.show(J.Rlgl.get_version()))
    IO.print(U32.show(Lgl.Rlgl.RL_TEXTURE_WRAP_S()) ++ " " ++ U32.show(J.Rlgl.RL_TEXTURE_WRAP_S()))
    IO.print(far.of(J.Frame.init_window(8, 6)) ++ " " ++ far.jonlib(J.Frame.init_window(8, 6)))
    IO.print(vec(Cam.Camera.forward_for(M.Uncontracted{}, camera())) ++ " " ++ vec(J.Camera.forward_for(M.Uncontracted{}, camera())))
    IO.print(gesture(J.Core.init_window(8, 6, M.Float64{0, 0})) ++ " " ++ gesture.jonlib(J.Core.init_window(8, 6, M.Float64{0, 0})))
    IO.print("done")
'''


def main():
    args = probekit.arguments(__doc__, raylib=False)
    probe = probekit.Probe('facades', args)
    for module in facades.MODULES:
        if (facades.ROOT / module).read_text() != facades.generate(module):
            raise ProbeFailure(f'facades: {module} is stale; rerun tools/facades.py')

    def render(items, gpu):
        return PROGRAM

    def parse(text, items):
        lines = [line for line in text.split('\n') if line.strip()]
        if not lines or lines[-1] != 'done' or len(lines) != 6:
            raise ProbeFailure(f'facades: the candidate printed {text[-300:]!r}')
        # Each line holds the module's value, then Jonlib's: they must agree.
        return [[not line.startswith('no ') and line[:len(line) // 2] == line[len(line) // 2 + 1:] for line in lines[:-1]]]

    lanes = probe.candidates(render, [0], batch=1, parse=parse)
    lanes = {lane: rows for lane, rows in lanes.items() if lane != 'gpu'}
    probe.compare([[True] * 5], lanes, describe=lambda i: 'module values against Jonlib')
    probe.finish(modules=list(facades.MODULES), definitions={m: facades.generate(m).count('\ndef ') for m in facades.MODULES})


if __name__ == '__main__':
    main()
