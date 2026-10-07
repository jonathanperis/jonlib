#!/usr/bin/env python3
"""Native-format BMP file loading against pinned raylib (shared driver: codec_files)."""
from bmp_format_probe import CODEC as MEMORY
from bmp_probe import bitmap
import codec_files
from png_probe import png
from qoi_format_probe import stream as qoi_stream
from tga_format_probe import targa

SUFFIXES = tuple((name + '-' + case, '.' + (name if case == 'lower' else name.upper()))
                 for name in codec_files.ALIAS_NAMES for case in ('lower', 'upper')) + (
    ('mixed', '.BmP'), ('mixed-jpeg', '.JpEg'), ('pnm', '.pnm'), ('PNM', '.PNM'), ('qoi', '.qoi'), ('QOI', '.QOI'),
    ('arbitrary', '.dat'), ('suffixless', ''), ('trailing-dot', '.'), ('spaces', ' with spaces.bmp'), ('dots', '.a.b.bmp'),
    ('dotfile', '/.bmp'), ('dotfile-unsupported', '/.dat'), ('directory-dot', '.bmp/leaf'), ('dotted-parent', '.folder/leaf.bmp'))

# Other-codec content saved as .bmp stays candidate-only: native .bmp uses stb
# content detection and is not a content-exclusive BMP oracle.
OTHER_CODECS = (('not-bmp-qoi', qoi_stream(1, 1, 4, 0, [255, 12, 34, 56, 78])), ('not-bmp-png', list(png(1, 1, 6, bytes([12, 34, 56, 78])))),
                ('not-bmp-pnm', list(b'P5\n1 1\n255\n\x7f')), ('not-bmp-tga', targa(1, 1, 4, [12, 34, 56, 78])))

CODEC = codec_files.FileCodec(memory=MEMORY, suffixes=SUFFIXES, path_bases=('c3-single', 'c4-single'), other_codecs=OTHER_CODECS,
                                 sparse_prefix=bitmap(1, 1, [0x12345678]), exact_cap_base='c3-single', bad_size=bitmap(0, 1, []))


def main(argv=None):
    codec_files.main(CODEC, argv, __doc__)


if __name__ == '__main__':
    main()
