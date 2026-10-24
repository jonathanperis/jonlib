import re
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import font_probe as fpb
import ttf_probe as tp


class Refused(Exception):
    pass


def c_int(v):
    v &= 0xFFFFFFFF
    return v - (1 << 32) if v >= 1 << 31 else v


def scan_ints(text, prefix, n):
    """sscanf(text, "<prefix> %i %i ...") with n conversions: the values assigned, left to right."""
    if not text.startswith(prefix):
        return []
    k, out = len(prefix), []
    for _ in range(n):
        while k < len(text) and text[k] in ' \t\n\v\f\r':
            k += 1
        if re.match(r'[+-]?0[xX]', text[k:]) and not re.match(r'[+-]?0[xX][0-9a-fA-F]', text[k:]):
            raise Refused('"0x" without a hex digit')
        m = re.match(r'([+-]?)(0[xX][0-9a-fA-F]+|0[0-7]*|[1-9][0-9]*)', text[k:])
        if not m:
            break
        sign, digits = m.groups()
        value = int(digits, 16) if digits[:2].lower() == '0x' else int(digits, 8) if digits.startswith('0') else int(digits)
        value = -value if sign == '-' else value
        if not -2**31 <= value < 2**31:
            raise Refused('int overflow')
        out.append(value)
        k += m.end()
    return out


def bdf_model(data, cps, size):
    """raylib 6.2's LoadFontDataBDF: (size, [(value, ox, oy, adv, w, h, pixels)]); Refused for undefined C."""
    glyphs = [(0, 0, 0, 0, 0, 0, [])] * len(cps)
    total, started, chr_, bitmap = 0, False, False, False
    fbh = fby = ascent = 0
    enc, w, h, x, y, dw = -1, 0, 0, 0, 0, 0
    target, rows = None, []

    def commit():
        if target is not None:
            value, ox, oy, adv, gw, gh = rows[0]
            pixels = [p for row in rows[1:] for p in row]
            glyphs[target] = (value, ox, oy, adv, gw, gh, pixels + [0] * (gw * gh - len(pixels)))

    while total <= len(data):
        count = 0
        while count < 255:
            if total + count >= len(data):
                raise Refused('GetLine reads past the data')
            if data[total + count] == 10:
                break
            count += 1
        raw = data[total:total + count]
        text = raw.split(b'\0')[0].decode('latin-1')
        total += count + 1
        if 'COMMENT' in text:
            continue
        if chr_:
            if 'ENDCHAR' in text:
                chr_ = False
                commit()
                target = None
            elif bitmap:
                if target is not None:
                    value, ox, oy, adv, gw, gh = rows[0]
                    if len(rows) - 1 >= gh:
                        break
                    nib = [int(chr(c), 16) if chr(c) in '0123456789abcdefABCDEF' else 0 for c in raw]
                    rows.append([255 if (px // 4 < len(nib) and nib[px // 4] & (8 >> (px % 4))) else 0 for px in range(gw)])
            elif 'ENCODING' in text:
                enc = (scan_ints(text, 'ENCODING', 1) or [enc])[0]
            elif 'BBX' in text:
                v = scan_ints(text, 'BBX', 4)
                w, h, x, y = (v + [w, h, x, y][len(v):])[:4]
            elif 'DWIDTH' in text:
                dw = (scan_ints(text, 'DWIDTH', 2) or [dw])[0]
            elif 'BITMAP' in text:
                commit()
                index = next((i for i, c in enumerate(cps) if c_int(c) == enc), None)
                if index is not None:
                    if not (0 <= w <= 4096 and 0 <= h <= 4096) or not -2**31 <= ascent - (h + y) < 2**31:
                        raise Refused('BBX')
                    target, rows = index, [(enc & 0xFFFFFFFF, x, ascent - (h + y), dw, w, h)]
                else:
                    target = None
                bitmap = True
        elif started:
            if 'ENDFONT' in text:
                break
            elif 'SIZE' in text:
                size = (scan_ints(text, 'SIZE', 1) or [size])[0]
            elif 'FONTBOUNDINGBOX' in text:
                v = scan_ints(text, 'FONTBOUNDINGBOX', 4)
                fbh = v[1] if len(v) > 1 else fbh
                fby = v[3] if len(v) > 3 else fby
                ascent = fbh + fby
            elif 'FONT_ASCENT' in text:
                ascent = (scan_ints(text, 'FONT_ASCENT', 1) or [ascent])[0]
            elif 'STARTCHAR' in text:
                chr_, bitmap, enc, w, h, x, y, dw, target = True, False, -1, 0, 0, 0, 0, 0, None
        elif 'STARTFONT' in text:
            started = True
    commit()
    return size, [(v & 0xFFFFFFFF, ox, oy, adv, gw, gh, px) for v, ox, oy, adv, gw, gh, px in glyphs]


def law_bytes(name):
    text = (ROOT / 'LAWS.bend').read_text()
    body = text[text.index(f'law {name}:'):]
    body = body[:body.index('\n\n')]
    return [int(v) for v in re.search(r'FontData\.bdf\(\[([0-9, ]+)\]', body).group(1).split(', ')]


class BdfModelTests(unittest.TestCase):
    """The model of raylib 6.2's reader agrees with the laws' closed instances."""

    def test_law_reads_a_requested_glyph(self):
        size, glyphs = bdf_model(bytes(law_bytes('font_bdf_reads_a_requested_glyph')), [66, 65], 9)
        self.assertEqual(size, 9)
        self.assertEqual(glyphs, [(0, 0, 0, 0, 0, 0, []), (65, 1, 0, 4, 3, 3, [255, 0, 255, 0, 255, 0, 0, 0, 0])])

    def test_law_row_past_the_height(self):
        size, glyphs = bdf_model(bytes(law_bytes('font_bdf_row_past_the_height_ends_the_read')), [65, 66], 9)
        self.assertEqual(glyphs, [(65, 0, -1, 0, 2, 1, [255, 0]), (0, 0, 0, 0, 0, 0, [])])


class TtfProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory()
        cls.paths = tp.font_files(Path(cls.work.name), Path('/nonexistent-raylib'))
        cls.items = tp.scenes(cls.paths, 'Glibc239Libm')

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    def bdf_ops(self):
        for scene in self.items:
            for op in scene['ops']:
                if op[0] == 'mem' and op[3].lower() == '.bdf':
                    yield scene['id'], op

    def test_scene_ids_unique_and_ops_render(self):
        ids = [s['id'] for s in self.items]
        self.assertEqual(len(ids), len(set(ids)))
        for scene in self.items:
            for op in scene['ops']:
                tp.c_op(op, '/tmp/codes')
                tp.b_op(op)

    def test_bdf_contracts_match_the_model(self):
        """Exactly the BDF loads marked refused are undefined in raylib 6.2's reader."""
        seen = set()
        for scene, op in self.bdf_ops():
            _, _, path, _, size, cps, count = tp.strip(op)
            n = count if c_int(count) > 0 else 95
            cps = list(range(32, 32 + n)) if not cps else cps[:n]
            data = Path(path).read_bytes()
            seen.add(Path(path).name)
            if tp.declared(op):
                with self.assertRaises(Refused, msg=(scene, path)):
                    bdf_model(data, cps, size)
            else:
                bdf_model(data, cps, size)
        self.assertTrue({'glyphs.bdf', 'crlf.bdf', 'ascent.bdf', 'rows.bdf', 'dup.bdf', 'negbbx.bdf', 'bigenc.bdf', 'crash.bdf'} <= seen)

    def test_bdf_fixtures_decode_as_meant(self):
        P = self.paths
        size, g = bdf_model(Path(P['glyphs.bdf']).read_bytes(), list(range(32, 127)), 20)
        self.assertEqual(size, 12)
        self.assertEqual(g[33][:6], (65, 0, 3, 6, 5, 7))          # A: FONT_ASCENT 10 - 7
        self.assertEqual(g[103 - 32][:6], (103, 0, 5, 6, 5, 7))   # g: 10 - (7 - 2), a COMMENT between rows
        self.assertEqual(g[0][:6], (32, 0, 10, 6, 0, 0))
        size, g = bdf_model(Path(P['glyphs.bdf']).read_bytes(), [65, 103, 33, 233, 1000, 0xFFFFFFFF], 16)
        self.assertEqual(g[3][6][-5:], [0] * 5)                    # eacute: 7 rows of 8
        self.assertEqual(g[4][0], 0)
        self.assertEqual(g[5][:6], (0xFFFFFFFF, 0, 8, 4, 2, 2))    # no ENCODING
        size, g = bdf_model(Path(P['crlf.bdf']).read_bytes(), [65, 103, 33], 20)
        self.assertEqual(size, 13)
        self.assertEqual(g[0][6], [0, 0, 255, 255, 255, 255] + [0] * 6 + [255] * 6 + [255, 0, 255, 0, 0, 255] + [255] * 6 + [0] * 6)
        self.assertEqual(g[2][3], 0)                               # no DWIDTH
        size, g = bdf_model(Path(P['ascent.bdf']).read_bytes(), [65, 66, 67], 20)
        self.assertEqual(size, 20)
        self.assertEqual([x[:6] for x in g], [(65, -1, 12, 0, 4, 3), (66, 0, 9, 4, 3, 2), (67, 0, 6, 3, 2, 2)])
        size, g = bdf_model(Path(P['rows.bdf']).read_bytes(), [65, 66, 67], 20)
        self.assertEqual(g[2][6], [255, 0, 255, 0, 0, 255, 0, 255] * 2)  # one 300-digit line, two rows
        self.assertEqual(g[0][6], [255] * 4 + [255, 0, 0, 255])
        self.assertEqual(g[1], (0, 0, 0, 0, 0, 0, []))              # never read
        size, g = bdf_model(Path(P['dup.bdf']).read_bytes(), [66, 65, 65, 0xFFFFFFFF, 67], 20)
        self.assertEqual(g[1], (65, 1, 5, 6, 2, 2, [0, 255, 0, 0]))
        self.assertEqual(g[2][0], 0)
        self.assertEqual(g[3][:6], (0xFFFFFFFF, 0, 7, 4, 2, 1))

    def test_spaces_font_maps_every_space(self):
        import ttf_fonts as T
        _, mapping = T.build_font(**dict(seed=14, cmap='4', kind='lines', codepoints=list(range(32, 127)) + tp.SPACES[1:] + [0x200B, 0x2010],
                                         empty=(32, 0xA0, 0x2003, 0x2007, 0x202F, 0x3000, 0x200B)))
        self.assertTrue(set(tp.SPACES) <= set(mapping))
        self.assertEqual(len(tp.SPACES), 17)

    def test_a_line_font_sdf_stays_compared_without_the_cubic_solver(self):
        apple = next(s for s in tp.scenes(self.paths, 'AppleLibm') if s['id'] == 'data-sdf-curves')
        curve, bitmap, gothic = apple['ops']
        self.assertEqual((curve[0], curve[-1], curve[5]), ('datafor', 'J', 2))
        self.assertEqual(bitmap[0], 'datafor')
        self.assertNotIn(bitmap[-1], ('J', 'R'))
        self.assertEqual((gothic[0], gothic[5]), ('datafor', 2))
        self.assertNotIn(gothic[-1], ('J', 'R'))
        glibc = next(s for s in tp.scenes(self.paths, 'Glibc239Libm', cubic=True) if s['id'] == 'data-sdf-curves')
        self.assertFalse(any(tp.declared(op) for op in glibc['ops']))

    def test_space_codepoints_match_the_library(self):
        source = (ROOT / 'src' / 'font_data.bend').read_text()
        body = source[source.index('def blank.codepoint('):]
        body = body[:body.index('\n\n')]
        listed = {int(v) for v in re.findall(r'U32\.is_eq\(cp, (\d+)\)', body)}
        lo, hi = map(int, re.search(r'\(cp >= (\d+) : U32\) && \(cp <= (\d+) : U32\)', body).groups())
        self.assertEqual(listed | set(range(lo, hi + 1)), set(tp.SPACES))


class FontProbeTests(unittest.TestCase):
    def test_image_draw_text_pro_ops(self):
        ops = [op for s in fpb.scenes('Glibc239Libm') for op in s['ops'] if op[0] == 'image_draw_text_pro']
        self.assertEqual(len(ops), 4)
        for op in ops:
            self.assertIn('ImageDrawTextPro(&im, f[0]', fpb.c_op(op))
            self.assertTrue(fpb.b_op(op).startswith('OFont{0, FImageDrawTextPro{'))


if __name__ == '__main__':
    unittest.main()
