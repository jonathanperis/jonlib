#!/usr/bin/env python3
"""Regenerate the JPEG fixtures in tests/fixtures/jpeg (provenance record).

Pixels are synthetic (seeded gradients and noise written as PGM/PPM); the
files come from libjpeg-turbo's cjpeg, with PIL for CMYK. The fixtures are
committed so the `jpeg` gate needs no encoder; tests/fixtures/jpeg/manifest.json
records each command. Run only to change the corpus: encoder versions may
produce different bytes, which is fine since native raylib is the reference.
"""
import io
import json
import random
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'tests/fixtures/jpeg'


def pixels(width, height, channels, seed):
    rng = random.Random(seed)
    return bytes(((x * 29 + y * 13 + c * 71) + rng.randrange(48)) % 256
                 for y in range(height) for x in range(width) for c in range(channels))


def netpbm(width, height, gray, seed):
    kind = b'P5' if gray else b'P6'
    return kind + b'\n%d %d\n255\n' % (width, height) + pixels(width, height, 1 if gray else 3, seed)


CJPEG = [  # name, width, height, gray, cjpeg arguments
    ('g1x1', 1, 1, True, ['-quality', '90']),
    ('g8', 8, 8, True, ['-quality', '85']),
    ('g17x9', 17, 9, True, ['-quality', '75']),
    ('g64x48', 64, 48, True, ['-quality', '80']),
    ('c1x1', 1, 1, False, ['-sample', '1x1']),
    ('c16-444', 16, 16, False, ['-sample', '1x1']),
    ('c16-420', 16, 16, False, ['-sample', '2x2']),
    ('c13x9-422', 13, 9, False, ['-sample', '2x1']),
    ('c13x9-440', 13, 9, False, ['-sample', '1x2']),
    ('c33x16-411', 33, 16, False, ['-sample', '4x1']),
    ('c7x5-311', 7, 5, False, ['-sample', '3x1']),
    ('c12x12-mixed', 12, 12, False, ['-sample', '2x2,2x1,1x1']),
    ('c20x12-rst1', 20, 12, False, ['-sample', '2x2', '-restart', '1B']),
    ('c24x24-rst-rows', 24, 24, False, ['-sample', '2x2', '-restart', '2']),
    ('c16-q1', 16, 16, False, ['-quality', '1']),
    ('c16-q100', 16, 16, False, ['-quality', '100']),
    ('c16-optimize', 16, 16, False, ['-optimize']),
    ('c16-rgb', 16, 16, False, ['-rgb']),
    ('c64x48-420', 64, 48, False, ['-sample', '2x2', '-quality', '70']),
    ('c8-arithmetic', 8, 8, False, ['-arithmetic']),
    ('pg8', 8, 8, True, ['-progressive']),
    ('pg17x9', 17, 9, True, ['-progressive', '-quality', '60']),
    ('pc16-420', 16, 16, False, ['-progressive', '-sample', '2x2']),
    ('pc16-444', 16, 16, False, ['-progressive', '-sample', '1x1']),
    ('pc13x9-422-rst', 13, 9, False, ['-progressive', '-sample', '2x1', '-restart', '1B']),
    ('pc33x16-411', 33, 16, False, ['-progressive', '-sample', '4x1']),
    ('pc64x48-420', 64, 48, False, ['-progressive', '-sample', '2x2', '-quality', '70']),
    ('pc16-q1', 16, 16, False, ['-progressive', '-quality', '1']),
]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = []
    for name, width, height, gray, args in CJPEG:
        source = netpbm(width, height, gray, sum(name.encode()))
        data = subprocess.run(['cjpeg', *args], input=source, capture_output=True, check=True).stdout
        (OUT / f'{name}.jpg').write_bytes(data)
        manifest.append(dict(name=name, source=f'synthetic {"P5" if gray else "P6"} {width}x{height}, seed {sum(name.encode())}',
                             command='cjpeg ' + ' '.join(args)))
    from PIL import Image
    image = Image.frombytes('CMYK', (16, 16), pixels(16, 16, 4, 77))
    buffer = io.BytesIO()
    image.save(buffer, 'JPEG', quality=90)
    (OUT / 'k16-cmyk.jpg').write_bytes(buffer.getvalue())
    manifest.append(dict(name='k16-cmyk', source='synthetic CMYK 16x16, seed 77', command='PIL Image.save(JPEG, quality=90)'))
    (OUT / 'manifest.json').write_text(json.dumps(dict(encoder=subprocess.run(['cjpeg', '-version'], capture_output=True, text=True).stderr.strip(),
                                                       fixtures=manifest), indent=1) + '\n')
    print(f'{len(manifest)} fixtures in {OUT.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
