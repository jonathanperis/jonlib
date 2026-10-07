#!/usr/bin/env python3
"""Native-format TGA file loading against pinned raylib (shared driver: codec_files)."""
import codec_files
from tga_format_probe import CODEC as MEMORY, targa

SUFFIXES = (('upper', '.TGA'), ('png', '.png'), ('bmp', '.BMP'), ('gif', '.gif'), ('spaces', ' with spaces.tga'), ('dots', '.a.b.tga'),
            ('dotfile', '/.tga'), ('mixed', '.TgA'), ('suffixless', ''), ('qoi', '.qoi'), ('QOI', '.QOI'), ('arbitrary', '.dat'),
            ('directory-dot', '.tga/leaf'), ('trailing-dot', '.'))
# Other-codec content saved as .tga stays candidate-only (native uses content detection).
OTHER_CODECS = (('not-tga-qoi', list(b'qoif' + bytes(40))), ('not-tga-png', list(b'\x89PNG\r\n\x1a\n' + bytes(40))),
                ('not-tga-pnm', list(b'P5\n1 1\n255\n\x7f')))

CODEC = codec_files.FileCodec(memory=MEMORY, suffixes=SUFFIXES, path_bases=('c1-single', 'c2-single', 'c3-single', 'c4-single'), other_codecs=OTHER_CODECS,
                                 sparse_prefix=targa(1, 1, 1, [127]), exact_cap_base='c1-single', bad_size=targa(0, 1, 1, []),
                                 synthetic=False)


def main(argv=None):
    codec_files.main(CODEC, argv, __doc__)


if __name__ == '__main__':
    main()
