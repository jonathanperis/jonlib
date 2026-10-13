import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import vorbis_ogg_probe as op


class PageTests(unittest.TestCase):
    def test_a_page(self):
        data = op.page(2, 0x100000005, 7, [3, 0, 255])
        self.assertEqual((data[:6], len(data), data[26], list(data[27:30])), (b'OggS\x00\x02', 27 + 3 + 258, 3, [3, 0, 255]))
        self.assertEqual(struct.unpack('<QIII', data[6:26]), (0x100000005, 0x1D, 7, 0))
        self.assertEqual(list(data[30:33]), [7, 14, 21])                      # a body that is not all one byte
        self.assertEqual(op.page(0, 0, 0, [9], body=b'ab')[28:], b'ab')        # a body shorter than its segments say
        self.assertEqual((op.page(0, 0, 0, [], version=3)[4], op.page(0, 0, 0, [], capture=b'OggT')[:4]), (3, b'OggT'))

    def test_the_pages_of_a_stream(self):
        first, second = op.page(2, 0, 0, [30]), op.page(0, 9, 1, [255, 4])
        self.assertEqual(op.pages(first + second), [(0, len(first)), (len(first), len(second))])
        with self.assertRaises(ValueError):
            op.pages(first + b'junk' + second)

    def test_the_built_streams(self):
        streams = op.built()
        self.assertEqual(len(op.pages(streams['many-pages'])), 60)
        self.assertEqual([size for _, size in op.pages(streams['spanning'])][:2], [27 + 2 + 510, 27 + 6 + 525])
        self.assertEqual((streams['spanning'][5], streams['spanning'][539 + 5], streams['spanning-unflagged'][539 + 5]), (2, 1, 0))
        self.assertEqual(streams['no-segments'][27 + 3 + 93 + 26], 0)        # a page without segments
        self.assertEqual(max(len(data) for data in streams.values()), len(streams['full-table']))
        self.assertTrue(len(streams['table-cut']) == 58 + 87 and streams['table-cut'][58 + 26] == 100)
        # a body shorter than its page says, and bytes that are no page
        self.assertEqual(sum(size for _, size in op.pages(streams['body-cut'])), len(streams['body-cut']) + 170)
        with self.assertRaises(ValueError):
            op.pages(streams['junk-between'])


class CasesTests(unittest.TestCase):
    def test_the_cases_of_a_stream(self):
        source = op.built()['many-pages']
        cases = op.cases(source)
        self.assertEqual((cases['whole'], cases['empty'], cases['twice'], cases['cut-27']), (source, b'', source + source, source[:27]))
        where = op.pages(source)
        at = where[3][0]
        self.assertEqual((cases['capture-3'][at:at + 4], cases['continued-3'][at + 5], cases['version-3'][at + 4], cases['unknown-3'][at + 6:at + 14]),
                         (b'OggX', source[at + 5] ^ 1, 2, b'\xff' * 8))
        self.assertEqual(cases['count-3'][at + 26], source[at + 26] + 9)
        damaged = [name for name in cases if name.startswith('damage-')]
        self.assertEqual((len(damaged), all(len(cases[name]) == len(source) for name in damaged), cases == op.cases(source)), (14, True, True))
        self.assertTrue(set(op.built()) <= set(cases))


class ScriptTests(unittest.TestCase):
    def test_the_scripts(self):
        scripts = op.scripts()
        self.assertEqual(([name for name, _ in scripts], scripts), (['walk', 'decoder', 'bits', 'raw', 'mix-1', 'mix-2'], op.scripts()))
        calls = [call for _, script in scripts for call in script]
        self.assertEqual({function for function, _ in calls}, set(range(14)))                          # every function
        self.assertEqual({argument for function, argument in calls if function == op.GET_BITS}, set(range(33)))   # every width
        self.assertTrue(all(argument <= 40 for function, argument in calls if function in (op.GETN, op.SKIP)))
        self.assertTrue(all(argument == 0 for function, argument in calls if function not in (op.GET_BITS, op.GETN, op.SKIP, op.FIRST_DECODE)))
        walk = dict(scripts)['walk']
        self.assertEqual((walk[:2], set(walk[2:])), ([(op.FIRST_DECODE, 1), (op.START_PAGE, 0)], {(op.MAYBE_START_PACKET, 0), (op.FLUSH_PACKET, 0)}))

    def test_a_list_in_chunks(self):
        self.assertEqual(op.lists([1, 2, 3]), 'List.concat(&2, U32, [[1, 2, 3]])')
        self.assertEqual(op.lists(list(range(130))).count('], ['), 2)


if __name__ == '__main__':
    unittest.main()
