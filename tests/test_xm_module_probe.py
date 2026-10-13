import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import xm_module_probe as xp


class BuilderTests(unittest.TestCase):
    def test_packed_and_plain_slots(self):
        self.assertEqual(xp.slots([(49, 1, 0x40, 0x0F, 6)]), bytes([49, 1, 0x40, 0x0F, 6]))
        self.assertEqual(xp.slots([(None, None, None, None, None)]), b'\x80')
        self.assertEqual(xp.slots([(60, None, None, None, None), (None, 2, None, 4, 0x37)]), b'\x81\x3c' + b'\x9a\x02\x04\x37')
        # a note of 128 or more cannot be a plain slot's first byte
        self.assertEqual(xp.slots([(200, 1, 2, 3, 4)]), b'\x9f\xc8\x01\x02\x03\x04')

    def test_a_pattern(self):
        made = xp.pattern(64, b'abc')
        self.assertEqual((struct.unpack('<I', made[:4])[0], struct.unpack('<H', made[5:7])[0], struct.unpack('<H', made[7:9])[0], made[9:]), (9, 64, 3, b'abc'))
        self.assertEqual(struct.unpack('<H', xp.pattern(2, b'abc', size=6)[7:9])[0], 6)
        self.assertEqual(len(xp.pattern(1, b'', header=20)), 20)

    def test_an_instrument(self):
        bare = xp.instrument()
        self.assertEqual((len(bare), struct.unpack('<I', bare[:4])[0], struct.unpack('<H', bare[27:29])[0]), (29, 29, 0))
        made = xp.instrument([xp.sample(b'\x01\x02\x03', loop=1, start=1, span=2, volume=50, finetune=-3, panning=9, relative=-2), xp.sample(b'\x05' * 4, wide=True, stereo=True)],
                             notes=[1] * 96, volume=xp.envelope([(0, 64), (9, 3)], sustain=1, loop=(0, 1), flags=5), vibrato=(2, 3, 4, 5), fadeout=700)
        self.assertEqual((struct.unpack('<I', made[:4])[0], struct.unpack('<H', made[27:29])[0], struct.unpack('<I', made[29:33])[0]), (263, 2, 40))
        self.assertEqual((made[33:129], struct.unpack('<HHHH', made[129:137]), made[225], made[227:230], made[233]), (bytes([1] * 96), (0, 64, 9, 3), 2, bytes([1, 0, 1]), 5))
        self.assertEqual((made[235:239], struct.unpack('<H', made[239:241])[0]), (bytes([2, 3, 4, 5]), 700))
        first = made[263:303]
        self.assertEqual(struct.unpack('<IIIBbBBb', first[:17]), (3, 1, 2, 50, -3, 1, 9, -2))
        self.assertEqual(made[303 + 14], 0x30)                                         # 16 bits and stereo
        self.assertEqual(made[343:], b'\x01\x02\x03' + b'\x05' * 4)
        self.assertEqual(len(xp.instrument([xp.sample(b'ab')], sample_header=18)), 263 + 18 + 2)
        self.assertEqual(xp.instrument(volume=xp.envelope([(1, 2)], count=13), count=1)[225], 13)

    def test_a_module(self):
        made = xp.module([xp.pattern(1)], [xp.instrument()], channels=3, order=(0, 0), restart=1, flags=0, tempo=5, bpm=99)
        self.assertEqual((made[:17], made[37], made[58:60]), (b'Extended Module: ', 0x1A, b'\x04\x01'))
        self.assertEqual(struct.unpack('<IHHHHHHHH', made[60:80]), (276, 2, 1, 3, 1, 1, 0, 5, 99))
        self.assertEqual((made[80:82], len(made)), (b'\x00\x00', 336 + 9 + 29))
        self.assertEqual(struct.unpack('<HH', xp.module(counts=(40, 3))[70:74]), (40, 3))
        self.assertEqual(len(xp.module([xp.pattern(1)], header=22, order=(0, 0))), 82 + 9)


class ModelTests(unittest.TestCase):
    def test_what_is_no_module(self):
        fine = xp.module([xp.pattern(1)])
        self.assertEqual(xp.model(fine)[0], 'loaded')
        for wrong in (b'', fine[:59], xp.module([xp.pattern(1)], magic=b'Extended module: '), xp.module([xp.pattern(1)], mark=0), xp.module([xp.pattern(1)], version=0x0103)):
            self.assertEqual(xp.model(wrong), ('failed', 1))

    def test_the_block_s_room(self):
        # the order's 256 bytes an entry, less the 8 bytes the estimate is short of
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], channels=1)), ('loaded', 248))
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], order=(0, 0, 0))), ('loaded', 760))
        # ... and less what the samples' data lacks of a multiple of 16: 4 bytes for a 3-byte sample
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], [xp.instrument([xp.sample(b'abc')])])), ('loaded', 244))

    def test_writes_outside_an_array(self):
        slot = [(49, 1, 2, 3, 4)]
        self.assertEqual(xp.model(xp.module([xp.pattern(1, xp.slots(slot * 2))]))[0], 'loaded')
        self.assertEqual(xp.model(xp.module([xp.pattern(1, xp.slots(slot * 3))])), ('refused', 1))
        self.assertEqual(xp.model(xp.module([xp.pattern(0, xp.slots(slot))])), ('refused', 1))
        twelve = [(k, k) for k in range(12)]
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], [xp.instrument([xp.sample(b'a')], volume=xp.envelope(twelve))]))[0], 'loaded')
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], [xp.instrument([xp.sample(b'a')], panning=xp.envelope(twelve, count=13))])), ('refused', 1))
        # no order: the channels have no room in the block; without channels nothing is written
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], order=(), length=0)), ('refused', 1))
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], order=(), length=0, channels=0)), ('loaded', 0))

    def test_loops_without_end(self):
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], channels=255))[0], 'loaded')
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], channels=256)), ('refused', 2))
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], order=[0] * 255))[0], 'loaded')
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], order=[0] * 256, length=256)), ('refused', 2))
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], order=[0] * 255 + [3], length=256))[0], 'loaded')     # the last entry is dropped
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], order=[0] * 256, length=999)), ('refused', 2))
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], order=[0, 3, 0])), ('failed', 1))
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], order=[0, 0, 3]))[0], 'loaded')
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], order=[3])), ('failed', 1))

    def test_the_port_s_limits(self):
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], [xp.instrument([xp.sample(b'', length=5000000)])])), ('refused', 4))
        self.assertEqual(xp.model(xp.module([xp.pattern(1)], [xp.instrument([xp.sample(b'', length=4000000)])]))[0], 'loaded')
        self.assertEqual(xp.model(xp.module([xp.pattern(2048, b'\x80' * 65535)], channels=32))[0], 'loaded')
        self.assertEqual(xp.model(xp.module([xp.pattern(2048, b'\x80' * 65534 + bytes(5), size=65535)], channels=32)), ('refused', 4))


class CasesTests(unittest.TestCase):
    def setUp(self):
        self.source = xp.module([xp.pattern(4, xp.slots([(49, 1, 2, 3, 4)] * 8))] * 3, [xp.instrument([xp.sample(bytes(range(200)))])] * 2, order=(0, 1, 2))

    def test_the_files(self):
        cases = xp.cases(self.source)
        built = xp.built()
        self.assertEqual(len(cases), 1 + 10 + 24 + len(built))
        self.assertEqual(cases['mini'], self.source)
        self.assertEqual(xp.cases(self.source), cases)                                 # seeded
        cuts = [data for name, data in cases.items() if name.startswith('cut-')]
        self.assertTrue(len(cuts) == 10 and all(self.source.startswith(data) and len(data) < len(self.source) for data in cuts))
        changed = [data for name, data in cases.items() if name.startswith('byte-')]
        self.assertTrue(all(len(data) == len(self.source) and sum(a != b for a, b in zip(data, self.source)) <= 1 for data in changed))
        self.assertTrue(sum(data != self.source for data in changed) >= 16)

    def test_the_built_modules(self):
        built = xp.built()
        kinds = {name: xp.model(data) for name, data in built.items()}
        self.assertEqual({name: value for name, (kind, value) in kinds.items() if kind == 'refused'},
                         {'slots-over': 1, 'slots-rowless': 1, 'slots-wrap': 4, 'sixteen-odd': 1, 'envelope-13': 1, 'envelope-pan-255': 1, 'order-none': 1, 'order-256': 2, 'order-300': 2, 'channels-256': 2,
                          'large-sample': 4, 'large-pattern': 4})
        self.assertEqual(sorted(name for name, (kind, _) in kinds.items() if kind == 'failed'), ['empty', 'magic', 'mark', 'order-300-wrong', 'order-one-wrong', 'order-wrong', 'short', 'version'])
        self.assertEqual(xp.built(), built)

    def test_the_reference_checks_the_sizes(self):
        self.assertIn('sizeof(jar_xm_context_t) != 424', xp.NATIVE)
        self.assertIn('sizeof(jar_xm_channel_context_t) != 256', xp.NATIVE)
        self.assertIn('PATTERN_ORDER_TABLE_LENGTH', xp.NATIVE)
        self.assertNotIn('SIZE_', xp.NATIVE)
        self.assertIn('#define JAR_XM_IMPLEMENTATION', xp.NATIVE)


if __name__ == '__main__':
    unittest.main()
