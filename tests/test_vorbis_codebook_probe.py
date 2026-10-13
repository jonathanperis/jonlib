import struct
import sys
import unittest
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import vorbis_codebook_probe as vp


def kraft(lengths):
    """How much of a binary tree the codes of these lengths take: 1 is all of it."""
    return sum(Fraction(1, 2 ** length) for length in lengths if length != 255)


class TreeTests(unittest.TestCase):
    def test_a_tree_is_complete(self):
        rng = vp.Rng(7)
        for count in (1, 2, 3, 17, 300):
            lengths = vp.tree(count, rng)
            self.assertEqual((len(lengths), kraft(lengths) if count > 1 else Fraction(1)), (count, Fraction(1)))
            self.assertTrue(all(1 <= length <= 31 for length in lengths))
        self.assertEqual(vp.tree(1, rng), [1])                                 # one symbol: half a tree

    def test_a_tree_keeps_to_its_limit(self):
        lengths = vp.tree(600, vp.Rng(3), limit=10)
        self.assertEqual((max(lengths) <= 10, kraft(lengths)), (True, Fraction(1)))

    def test_shuffling_and_holes_keep_the_lengths(self):
        rng = vp.Rng(11)
        lengths = vp.tree(40, rng)
        mixed = vp.shuffled(lengths, rng)
        self.assertEqual((sorted(mixed), mixed != lengths), (sorted(lengths), True))
        holed = vp.with_holes(lengths, rng, 3)
        self.assertEqual(([length for length in holed if length != 255], 255 in holed), (lengths, True))


class BooksTests(unittest.TestCase):
    def test_the_books(self):
        books = dict(vp.books())
        self.assertEqual(len(books), len(vp.books()))                          # every name once
        self.assertTrue(all(length == 255 or 1 <= length <= 31 for lengths in books.values() for length in lengths))
        # no tree: more codes than a tree has
        over = sorted(name for name, lengths in books.items() if kraft(lengths) > 1)
        self.assertEqual(over, ['short-then-full', 'too-many', 'too-many-late'])
        self.assertEqual((kraft(books['chain']), kraft(books['chain-open']) < 1, kraft(books['eleven']), kraft(books['ten'])), (1, True, 1, 1))
        self.assertTrue(all(kraft(books[f'tree-{count}-incomplete']) < 1 for count in (2, 3, 5, 16, 100, 300, 1024, 3000)))
        self.assertEqual({max(l for l in books[name] if l != 255) > 10 for name in ('tree-3000', 'tree-1024', 'chain')}, {True})
        self.assertEqual(max(books['shallow']), 10)
        # symbols on both sides of what the accelerated table's shorts hold
        far = books['far-edge']
        self.assertEqual((len(far), far[32766], far[32767], far[39999]), (40000, 3, 3, 2))
        self.assertTrue(len(books['tree-3000-holes']) > 3000 and len(books['none']) == 3)

    def test_the_generator_is_seeded(self):
        self.assertEqual(vp.books(), vp.books())


class Lookup1Tests(unittest.TestCase):
    def test_the_root(self):
        self.assertEqual([vp.root(n, d) for n, d in ((1, 1), (7, 1), (8, 3), (7, 3), (4096, 2), (4095, 2), (16777215, 24), (16777215, 23), (5, 65535))], [1, 7, 2, 1, 64, 63, 1, 2, 1])
        rng = vp.Rng(5)
        for _ in range(300):
            n, d = 1 + rng.next((1 << 24) - 1), 1 + rng.next(30)
            r = vp.root(n, d)
            self.assertTrue(r ** d <= n < (r + 1) ** d)

    def test_the_rule(self):
        self.assertEqual((vp.lookup1(0, 3), vp.lookup1(0, 0), vp.lookup1(5, 0), vp.lookup1(1, 9)), (0, -1, None, 1))
        self.assertEqual((vp.lookup1(6561, 8), vp.lookup1(6560, 8), vp.lookup1(1 << 19, 1), vp.lookup1((1 << 19) + 1, 1)), (3, 2, 1 << 19, None))
        # past 2^19 entries: sure unless just under a perfect power, by 17/2^23 of it
        self.assertEqual([vp.lookup1(4096 ** 2 - under, 2) for under in (1, 34, 35, 36)], [None, None, 4095, 4095])
        self.assertEqual((vp.lookup1(1000 ** 2, 2), vp.lookup1(1000 ** 2 - 1, 2), vp.lookup1(1000 ** 2 - 3, 2)), (1000, None, 999))
        # a power of 2^31 or more converted to int
        self.assertEqual((vp.lookup1(5, 30), vp.lookup1(5, 31), vp.lookup1(1 << 19, 19), vp.lookup1(1 << 20, 20), vp.lookup1(600000, 20)), (1, None, 2, None, 1))
        self.assertEqual((vp.lookup1(1 << 24, 2), vp.lookup1(5, 1 << 16)), (None, None))

    def test_the_pairs(self):
        pairs = vp.pairs()
        self.assertEqual((pairs, len(pairs) == len(set(pairs)), len(pairs) > 8000), (vp.pairs(), True, True))
        answers = [vp.lookup1(entries, dim) for entries, dim in pairs]
        self.assertTrue(-1 in answers and 0 in answers and 4095 in answers and answers.count(None) > 2000)
        self.assertTrue({(0, 0), (16777215, 1), (16777215, 65535), (1 << 24, 2), (524288, 1), (524289, 1)} <= set(pairs))

    def test_the_recorded_checks(self):
        found = dict(vp.evidence())
        self.assertEqual((sorted(found), found['fma'] == found['sse2'] > 300000000), (['fma', 'sse2'], True))


class WordsTests(unittest.TestCase):
    def test_unpacking_is_exact(self):
        word = lambda value: struct.unpack('<I', struct.pack('<f', value))[0]
        self.assertEqual(vp.unpacked(788 << 21 | 1), word(1.0))
        self.assertEqual(vp.unpacked(0x80000000 | 788 << 21 | 3), word(-3.0))
        self.assertEqual(vp.unpacked(768 << 21 | 0x100000), word(1.0))        # 2^20 * 2^-20
        self.assertEqual(vp.unpacked(639 << 21 | 1), 1)                        # 2^-149, the smallest float
        self.assertEqual((vp.unpacked(638 << 21 | 1), vp.unpacked(638 << 21 | 3)), (0, 2))   # ties to even
        self.assertEqual((vp.unpacked(916 << 21 | 1), vp.unpacked(0x80000000 | 1023 << 21 | 5)), (0x7F800000, 0xFF800000))
        self.assertEqual((vp.unpacked(895 << 21 | 0x1FFFFF), vp.unpacked(0), vp.unpacked(0x80000000)), (0x7F7FFFF8, 0, 0x80000000))

    def test_the_words(self):
        words = vp.words()
        self.assertEqual((len(words), len(set(words)) > 1300, words == vp.words()), (1443, True, True))
        floats = [vp.unpacked(w) for w in words]
        self.assertTrue(0x7F800000 in floats and 0xFF800000 in floats and 0 in floats and 0x80000000 in floats)
        self.assertTrue(any(0 < f < 0x00800000 for f in floats) and any(0x00800000 <= f < 0x7F800000 for f in floats))
        self.assertTrue({0, 1, 0x80000000, 0xFFFFFFFF, 0x7FFFFFFF} <= set(words))  # ilog's and bit_reverse's ends


if __name__ == '__main__':
    unittest.main()
