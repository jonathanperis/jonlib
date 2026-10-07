#!/usr/bin/env python3
"""Native-format binary PGM/PPM file loading against pinned raylib (shared driver: codec_files)."""
import codec_files
from pnm_format_probe import CODEC as MEMORY, header

SUFFIXES = (('upper-pgm', '.PGM'), ('upper-ppm', '.PPM'), ('cross', lambda case: '.ppm' if case['channels'] == 1 else '.pgm'),
            ('raster-alias', '.png'), ('spaces', ' with spaces.pgm'), ('dots', '.a.b.ppm'), ('dotfile', '/.pgm'), ('jpg', '.jpg'),
            ('gif', '.gif'), ('mixed', '.PgM'), ('pnm', '.pnm'), ('suffixless', ''), ('qoi', '.qoi'), ('unsupported', '.dat'),
            ('mixed-ppm', '.PpM'))
OTHER_CODECS = (('not-pnm-qoi', list(b'qoif' + bytes(40))), ('not-pnm-png', list(b'\x89PNG\r\n\x1a\n' + bytes(40))),
                ('ascii-P3', list(b'P3\n1 1\n255\n0 0 0\n')))
SPECIALS = (('missing', 'missing.qoi', 'missing', 5), ('missing-parent', 'missing-parent/input.pnm', 'missing', 5),
            ('directory', 'directory.ppm', 'directory', 5), ('cap-plus-one', 'cap-plus-one.ppm', 'sparse', 2),
            ('cap-misleading', 'cap-plus-one.qoi', 'sparse', 2), ('larger-file', 'larger-file.pgm', 'large', 2),
            ('host-size-overflow', 'host-size-overflow.pnm', 'overflow', 5))

CODEC = codec_files.FileCodec(
    memory=MEMORY, suffixes=SUFFIXES, other_codecs=OTHER_CODECS, specials=SPECIALS,
    path_bases=('c1-max255-single', 'c1-max256-single', 'c3-max255-single', 'c3-max256-single'),
    loop_loads=('c1-max255-single', 'c3-max256-single', 'not-pnm-qoi', 'directory', 'cap-plus-one', 'host-size-overflow'),
    token_for=lambda case: '.pgm' if case['channels'] == 1 else '.ppm', control_suffix='.pgm', other_suffix='.ppm',
    sparse_prefix=list(header() + b'\x7f'), exact_cap_base='c1-max255-single', bad_size=list(header(width=0)))


def main(argv=None):
    codec_files.main(CODEC, argv, __doc__)


if __name__ == '__main__':
    main()
