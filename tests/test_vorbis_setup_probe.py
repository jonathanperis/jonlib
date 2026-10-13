import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import vorbis_setup_probe as sp
from vorbis_ogg_probe import pages

ONE = 788 << 21 | 1                                                           # the packed float 1.0


class WriterTests(unittest.TestCase):
    def test_bits_are_packed_low_first(self):
        self.assertEqual(sp.Writer().put(1, 1).put(0, 2).put(31, 5).bytes(), bytes([0b11111001]))
        self.assertEqual(sp.Writer(b'\x05').put(0x1FF, 9).put(1, 1).bytes(), bytes([5, 0xFF, 0b11]))
        self.assertEqual(sp.Writer().put(0x12345678, 32).bytes(), struct.pack('<I', 0x12345678))
        self.assertEqual(sp.Writer().put(7, 0).bytes(), b'')

    def test_a_packet_reads_them_back(self):
        p = sp.Packet(sp.Writer(b'\x05').put(5, 3).put(1000, 13).put(0xABCDEF01, 32).bytes())
        self.assertEqual((p.byte(), p.bits(3), p.bits(13), p.bits(32), p.bits(0)), (5, 5, 1000, 0xABCDEF01, 0))
        self.assertEqual((p.bits(1), p.bits(8), p.byte(), p.valid), (0, 0, -1, 0))     # past the end: zeros, then EOP
        q = sp.Packet(b'\x01\x02')
        self.assertEqual((q.bits(12), q.bits(8), q.bits(1)), (0x201, 0, 0))            # a request past the end is all zero, and so are the next
        self.assertEqual(sp.Packet(b'\x01\x02\x03').word(), (0x030201 + (-1 << 24)) & 0xFFFFFFFF)

    def test_a_packet_skips(self):
        p = sp.Packet(bytes(range(10)))
        p.bits(4)
        p.skip(0)
        self.assertEqual(p.valid, 4)                                                   # no call, the bits stay
        p.skip(3)
        self.assertEqual((p.valid, p.byte()), (0, 4))
        p.skip(100)
        self.assertEqual(p.byte(), -1)


class HeaderTests(unittest.TestCase):
    def test_the_identification(self):
        data = sp.identification(channels=1, rate=8000, small=6, large=13)
        self.assertEqual((len(data), data[:7], data[11], struct.unpack('<I', data[12:16])[0], data[28], data[29]), (30, b'\x01vorbis', 1, 8000, 6 | 13 << 4, 1))

    def test_the_comment(self):
        data = sp.comment(vendor=b'ab', comments=(b'X=1',))
        self.assertEqual(data, b'\x03vorbis' + struct.pack('<I', 2) + b'ab' + struct.pack('<II', 1, 3) + b'X=1\x01')
        self.assertEqual(sp.comment(vendor=b'ab', comments=(), vendor_length=9, count=7, tail=b'')[7:], struct.pack('<I', 9) + b'ab' + struct.pack('<I', 7))

    def test_a_setup_is_read_back(self):
        books = [sp.book(2, [2, 2, 2, 2]), sp.book(1, [255, 1, 255, 255, 255, 255, 255, 255], sparse=True), sp.book(3, runs=(1, [1, 1, 2])),
                 sp.book(2, [2, 2, 2, 2], lookup=(1, 0, ONE, 5, True, [1, 2])), sp.book(2, [1, 1], lookup=(2, ONE, 0, 3, False, [1, 2, 3, 4]))]
        # without floors the header ends in zeros: a floor of type 0, which stb_vorbis does not decode
        kind, code, stage, head, made = sp.model(sp.stream(third=sp.setup(books)))
        self.assertEqual((kind, code, stage, head, len(made)), (sp.FAILED, 4, 1, [2, 44100, 256, 2048], 5))
        self.assertEqual([(m['dimensions'], m['entries'], m['sparse'], m['lookup'], m['values'], m['count']) for m in made],
                         [(2, 4, 0, 0, 0, 0), (1, 8, 1, 0, 0, 0), (3, 4, 0, 0, 0, 0), (2, 4, 0, 2, 2, 8), (2, 2, 0, 2, 4, 4)])
        self.assertEqual((made[3]['least'], made[3]['step'], made[3]['bits'], made[3]['sequence']), (0, 0x3F800000, 5, 1))

    def test_what_the_model_fails(self):
        fails = lambda **parts: sp.model(sp.stream(**parts))
        self.assertEqual(fails(first=sp.identification(channels=17)), (sp.FAILED, 5, 0))
        self.assertEqual(fails(first=sp.identification(small=5)), (sp.FAILED, 20, 0))
        self.assertEqual(fails(flag=0), (sp.FAILED, 34, 0))
        self.assertEqual(fails(first=b'fishead\x00' + bytes(56)), (sp.FAILED, 38, 0))
        self.assertEqual(fails(second=b''), (sp.FAILED, 0, 0))
        self.assertEqual(fails(second=sp.comment(vendor_length=0x80000000)), (sp.FAILED, 3, 0))
        self.assertEqual(fails(packets=[sp.comment()]), (sp.FAILED, 30, 0))
        self.assertEqual(fails(third=sp.setup([sp.book(1, [1, 1, 1])])), (sp.FAILED, 20, 0))         # no tree
        self.assertEqual(fails(third=sp.setup([sp.book(1, [])])), (sp.FAILED, 3, 0))                 # no entries
        self.assertEqual(fails(third=sp.setup([sp.book(1, [1, 1])], transfers=(0, 1))), (sp.FAILED, 20, 0))

    def test_a_whole_setup_is_read_back(self):
        floors = [sp.floor(), sp.floor(partitions=(0, 1), classes=((2, 0, 0, (-1,)), (1, 1, 0, (0, -1))), multiplier=3, rangebits=5, places=(9, 30, 4))]
        residues = [sp.residue(kind=2, begin=3, end=40, part_size=8, cascades=(0, 5, 0x81), books=(0, 0, 0, 0))]
        mappings = [sp.mapping(coupling=((1, 0),), submaps=((1, 0), (0, 0)), mux=(1, 0))]
        made = sp.model(sp.stream(third=sp.whole(floors=floors, residues=residues, mappings=mappings, modes=[sp.mode(1), sp.mode()])))
        self.assertEqual((made[:3], len(made)), ((sp.GOING, 0, 5), 10))
        none = 0xFFFFFFFF
        self.assertEqual(made[5], [[[], [], 1, 4, [0, 16], [0, 1], [], []],
                                   [[0, 1], [[2, 0, 0, [none]], [1, 1, 0, [0, none]]], 3, 5, [0, 32, 9, 30, 4], [0, 4, 2, 3, 1], [0, 2, 0], [1, 1, 2]]])
        self.assertEqual(made[6], [[2, 3, 40, 8, 3, 0, [[none] * 8, [0, none, 0] + [none] * 5, [0] + [none] * 6 + [0]]]])
        self.assertEqual((made[7], made[8]), ([[[1], [0], [1, 0], 2, [1, 0], [0, 0]]], [[1, 0], [0, 0]]))
        self.assertEqual(made[9], len(sp.stream(third=sp.whole(floors=floors, residues=residues, mappings=mappings, modes=[sp.mode(1), sp.mode()]))))   # the audio would begin after the header's page

    def test_the_stage_a_setup_fails_in(self):
        fails = lambda **parts: sp.model(sp.stream(third=sp.whole(**parts)))[:3]
        self.assertEqual(fails(floors=[sp.floor(kind=0)]), (sp.FAILED, 4, 1))
        self.assertEqual(fails(floors=[sp.floor(partitions=(0,), classes=((2, 0, 0, (0,)),), places=(3, 3))]), (sp.FAILED, 20, 1))    # two points at one place
        self.assertEqual(fails(residues=[sp.residue(begin=9, end=8)]), (sp.FAILED, 20, 2))
        self.assertEqual(fails(mappings=[sp.mapping(coupling=((0, 0),))]), (sp.FAILED, 20, 3))
        self.assertEqual(fails(modes=[sp.mode(mapped=1)]), (sp.FAILED, 20, 4))
        self.assertEqual(sp.model(sp.stream(third=sp.setup([sp.book(1, [1, 1])], floors=[sp.floor()])))[:3], (sp.GOING, 0, 5))        # the sections that are not there are zeros

    def test_what_the_model_refuses(self):
        refused = lambda **parts: sp.model(sp.stream(**parts))
        self.assertEqual(refused(second=sp.comment(vendor_length=sp.BUDGET + 1)), (sp.REFUSED, 3))
        self.assertEqual(refused(second=sp.comment(vendor_length=sp.BUDGET))[:3], (sp.FAILED, 4, 1))   # read; the least setup has no floor
        self.assertEqual(refused(second=sp.comment(count=(1 << 21) + 1)), (sp.REFUSED, 3))
        self.assertEqual(refused(second=sp.comment(count=1 << 28)), (sp.FAILED, 3, 0))
        self.assertEqual(refused(third=sp.setup([sp.book(1, runs=(20, [sp.ENTRIES + 1]))])), (sp.REFUSED, 4))
        self.assertEqual(refused(third=sp.setup([sp.book(31, [1, 1], lookup=(1, 0, ONE, 1, False, [1]))])), (sp.REFUSED, 1))
        self.assertEqual(refused(third=sp.setup([sp.book(65535, runs=(16, [1 << 16]), lookup=(2, 0, ONE, 1, False, []))])), (sp.REFUSED, 2))
        self.assertEqual(refused(third=sp.setup([sp.book(1100, runs=(12, [1 << 12]), lookup=(2, 0, ONE, 1, False, []))])), (sp.REFUSED, 3))
        sixteen = [(0, 0)] * 16
        self.assertEqual(refused(third=sp.whole(mappings=[sp.mapping(submaps=sixteen, mux=(15, 0))])), (sp.REFUSED, 2))
        self.assertEqual(refused(third=sp.whole(mappings=[sp.mapping(submaps=sixteen[:15], mux=(14, 0))]))[:3], (sp.GOING, 0, 5))
        self.assertEqual(refused(third=sp.whole(mappings=[sp.mapping(submaps=sixteen, mux=(15, 0), reserved=1)]))[:3], (sp.FAILED, 20, 3))   # it fails before the sixteenth
        self.assertEqual(refused(third=sp.whole(books=[sp.book(4097, runs=(12, [4096]))])), (sp.REFUSED, 3))
        self.assertEqual(refused(third=sp.whole(books=[sp.book(4096, runs=(12, [4096]))]))[:3], (sp.GOING, 0, 5))

    def test_leaves(self):
        self.assertEqual([sp.leafed(lengths) for lengths in ([1, 1], [1, 1, 1], [2, 1, 2], [255, 255], [1, 2, 3, 3], [1, 2, 3, 3, 9], [5], [31, 31])], [True, False, True, True, True, False, True, True])


class PagingTests(unittest.TestCase):
    def test_packets_over_pages(self):
        data = sp.paged([bytes(10), bytes(255), bytes(600)])
        self.assertEqual(list(data[27:27 + data[26]]), [10, 255, 0, 255, 255, 90])
        many = sp.paged([bytes(255 * 300 + 7), b'x'])
        where = pages(many)
        self.assertEqual(([many[at + 5] for at, _ in where], [many[at + 26] for at, _ in where]), ([0, 1], [255, 47]))
        self.assertEqual(sum(size for _, size in where), len(many))

    def test_a_stream(self):
        data = sp.stream()
        where = pages(data)
        self.assertEqual((where[0], data[5], data[58 + 5], len(where)), ((0, 58), 2, 0, 2))
        # where the codebooks of the setup header are: after its type, its name and their count
        built = sp.stream(third=sp.setup([sp.book(1, [1, 1]), sp.book(2, [2, 2, 2, 2])]))
        start, end, last = sp.codebooks_end(built)
        self.assertEqual((built[start - 8:start - 1], built[start - 1], built[start:start + 3], end - start, last), (b'\x05vorbis', 1, b'BCV', 22, len(built)))   # 80 and 90 bits


class CasesTests(unittest.TestCase):
    def test_the_built_streams(self):
        streams = sp.built()
        self.assertEqual(streams, sp.built())
        read = {name: sp.model(data) for name, data in streams.items()}
        kinds = [made[0] for made in read.values()]
        self.assertTrue(kinds.count(sp.GOING) >= 15 and kinds.count(sp.REFUSED) >= 14)
        self.assertEqual({made[1] for made in read.values() if made[0] == sp.FAILED}, {0, 3, 4, 5, 10, 20, 30, 34, 38})
        self.assertEqual({made[1] for made in read.values() if made[0] == sp.REFUSED}, {1, 2, 3, 4})
        self.assertEqual({made[2] for made in read.values() if made[0] == sp.FAILED}, {0, 1, 2, 3, 4})
        # read to the floors, which the streams of codebooks alone do not have
        self.assertEqual((read['at-budget'][:3], read['over-budget'], read['lookup-1-30-dimensions'][:3], read['lookup-1-31-dimensions']), ((sp.FAILED, 4, 1), (sp.REFUSED, 4), (sp.FAILED, 4, 1), (sp.REFUSED, 1)))
        self.assertEqual(len(read['many'][4]), 256)
        self.assertEqual((read['whole-all'][:3], max(len(floor[4]) for floor in read['whole-floors'][5]), read['whole-then-a-packet'][9], read['whole-then-a-page'][9] > 58), ((sp.GOING, 0, 5), 250, 0, True))

    def test_places(self):
        found = sp.places(sp.Rng(3), 248, 9)
        self.assertEqual((len(found), len(set(found)), 0 in found, max(found) < 512), (248, 248, False, True))


if __name__ == '__main__':
    unittest.main()
