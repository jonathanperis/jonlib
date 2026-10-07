#!/usr/bin/env python3
"""Native-format Softimage PIC file loading against pinned raylib (shared driver: codec_files)."""
from bmp_probe import bitmap
import codec_files
from pic_format_probe import CODEC as MEMORY
from pic_probe import pic
from png_probe import png
from qoi_format_probe import stream as qoi_stream
from tga_format_probe import targa

SUFFIXES = tuple((name + '-' + case, '.' + (name if case == 'lower' else name.upper()))
                 for name in codec_files.ALIAS_NAMES for case in ('lower', 'upper')) + (
    ('mixed', '.PiC'), ('mixed-jpeg', '.JpEg'), ('pnm', '.pnm'), ('PNM', '.PNM'), ('qoi', '.qoi'), ('QOI', '.QOI'),
    ('arbitrary', '.dat'), ('suffixless', ''), ('trailing-dot', '.'), ('spaces', ' with spaces.pic'), ('dots', '.a.b.pic'),
    ('dotfile', '/.pic'), ('dotfile-unsupported', '/.dat'), ('directory-dot', '.pic/leaf'), ('dotted-parent', '.folder/leaf.pic'))
OTHER_CODECS = (('not-pic-qoi', qoi_stream(1, 1, 4, 0, [255, 12, 34, 56, 78])), ('not-pic-bmp', bitmap(1, 1, [0x12345678])),
                ('not-pic-png', list(png(1, 1, 6, bytes([12, 34, 56, 78])))), ('not-pic-tga', targa(1, 1, 4, [12, 34, 56, 78])))
BAD_SIZE = next(c['bytes'] for c in MEMORY.controls() if c['id'] == 'axis-92-0')

CODEC = codec_files.FileCodec(memory=MEMORY, suffixes=SUFFIXES, path_bases=('c3-single', 'c4-single'), other_codecs=OTHER_CODECS,
                                 sparse_prefix=list(pic(1, 1, [(0xe0, [0x0c22384e])])), exact_cap_base='c3-single',
                                 bad_size=BAD_SIZE, roles=('raw', 'owner', 'bridge', 'surface', 'factory', 'raw-roundtrip'),
                                 upper_suffix_names=('PNM', 'QOI'))


def main(argv=None):
    codec_files.main(CODEC, argv, __doc__)


if __name__ == '__main__':
    main()
