#!/usr/bin/env python3
"""Record known pinned-toolchain defects on each lane (diagnostic, no parity claim).

tests/compiler/bool_pick_or.bend: a Bool.pick(Bool, ...) result feeding || in
the same def must give 2 on all eight calls. The native lanes of the pinned
overlay give 1 from the sixth call while JavaScript gives 2. The run records
which lanes still show the defect; it fails only if JavaScript is wrong too,
which would mean the repro itself is broken.
"""
import probekit
from probekit import ROOT, ProbeFailure

REPRO = ROOT / 'tests/compiler/bool_pick_or.bend'


def main():
    probe = probekit.Probe('bend-defects', probekit.arguments(__doc__, raylib=False))
    source = REPRO.read_text().replace('import Base', 'import Base', 1)
    lanes = probe.candidates(lambda selected, gpu: source, ['bool_pick_or'], batch=1,
                             parse=lambda text, selected: [text.split()])
    results = {lane: rows[0] for lane, rows in lanes.items()}
    if results.get('javascript') != ['2'] * 8:
        raise ProbeFailure(f'bend-defects: the JavaScript lane disagrees with the repro: {results.get("javascript")}')
    probe.diagnostic(bool_pick_or={lane: 'defect' if values != ['2'] * 8 else 'fixed' for lane, values in results.items()})


if __name__ == '__main__':
    main()
