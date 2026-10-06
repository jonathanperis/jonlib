#!/usr/bin/env python3
"""Native-format PNG file loading against pinned raylib (shared driver: formatted_file)."""
from bmp_probe import bitmap
import formatted_file
from png_format_probe import CODEC as MEMORY
from png_probe import png
from qoi_format_probe import stream as qoi_stream
from tga_format_probe import targa

SUFFIXES = tuple((name + '-' + case, '.' + (name if case == 'lower' else name.upper()))
                 for name in formatted_file.ALIAS_NAMES for case in ('lower', 'upper')) + (
    ('mixed', '.PnG'), ('mixed-jpeg', '.JpEg'), ('pnm', '.pnm'), ('PNM', '.PNM'), ('qoi', '.qoi'), ('QOI', '.QOI'),
    ('arbitrary', '.dat'), ('suffixless', ''), ('trailing-dot', '.'), ('spaces', ' with spaces.png'), ('dots', '.a.b.png'),
    ('dotfile', '/.png'), ('dotfile-unsupported', '/.dat'), ('directory-dot', '.png/leaf'), ('dotted-parent', '.folder/leaf.png'))
OTHER_CODECS = (('not-png-qoi', qoi_stream(1, 1, 4, 0, [255, 12, 34, 56, 78])), ('not-png-bmp', bitmap(1, 1, [0x12345678])),
                ('not-png-pnm', list(b'P5\n1 1\n255\n\x7f')), ('not-png-tga', targa(1, 1, 4, [12, 34, 56, 78])))
BAD_SIZE = next(c['bytes'] for c in MEMORY.controls() if c['id'] == 'size-before-stream')

CODEC = formatted_file.FileCodec(memory=MEMORY, suffixes=SUFFIXES, path_bases=('c1-single', 'c2-single', 'c3-single', 'c4-single'), other_codecs=OTHER_CODECS,
                                 sparse_prefix=list(png(1, 1, 6, bytes([12, 34, 56, 78]))), exact_cap_base='c3-single',
                                 bad_size=BAD_SIZE, roles=('raw', 'owner', 'bridge', 'surface', 'factory', 'raw-roundtrip'))


def main(argv=None):
    formatted_file.main(CODEC, argv, __doc__)


if __name__ == '__main__':
    main()
