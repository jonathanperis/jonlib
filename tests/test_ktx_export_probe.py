"""The KTX oracle pads malloc without GNU ld --wrap on Darwin."""
import platform
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import ktx_export_probe as probe


class KtxOracleTests(unittest.TestCase):
    def test_darwin_does_not_pass_gnu_wrap_to_ld(self):
        flags = probe.link_flags()
        if platform.system() == 'Darwin':
            self.assertEqual(flags, [])
        else:
            self.assertEqual(flags, ['-Wl,--wrap=malloc', '-Wl,--wrap=calloc', '-Wl,--wrap=realloc'])

    def test_the_oracle_pads_malloc_on_both_linkers(self):
        text = probe.c_source(probe.fixtures(), Path('/tmp/ktx'))
        self.assertIn('malloc_default_zone', text)
        self.assertIn('__wrap_malloc', text)
        self.assertLess(text.index('#ifdef __APPLE__'), text.index('#else'))
