"""Explicit native-child loader policy, with no parent or candidate mutation."""
import contextlib
import io
import runpy
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

from tools import conformance, reference_environment as policy
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))


class ReferenceEnvironmentTests(unittest.TestCase):
    def test_clean_is_explicit_preserves_unrelated_values_and_parent(self):
        values={key:'' for key in policy.LOADER_NAMES}
        values.update(PATH='/unchanged/path',UNRELATED='retained')
        with patch.dict(os.environ,values,clear=True):
            inherited=policy.ReferenceEnvironment()
            clean=policy.ReferenceEnvironment('clean-loader')
            self.assertEqual(inherited.child(),values)
            self.assertEqual(clean.child(),{'PATH':'/unchanged/path','UNRELATED':'retained'})
            self.assertEqual(dict(os.environ),values)
            self.assertNotIn('UNRELATED',json.dumps(clean.receipt()))
            with self.assertRaisesRegex(ValueError,'Loader overrides'): inherited.require_clear()
            clean.require_clear()
            changed=clean.child();changed['LD_LIBRARY_PATH']='injected'
            self.assertNotIn('LD_LIBRARY_PATH',clean.child())

    def test_unknown_conflicting_policy_and_typed_receipt_reject(self):
        for bad in ('auto','python',None,False,{},[]):
            with self.assertRaises(ValueError):policy.ReferenceEnvironment(bad)
        env=policy.ReferenceEnvironment()
        with self.assertRaises(ValueError):policy.select(env,'clean-loader')
        for value in (None,{},dict(env.receipt(),policy='clean-loader'),dict(env.receipt(),schema=True)):
            with self.assertRaises(ValueError):env.assert_receipt(value)

    def test_parent_loader_drift_rejected_before_child(self):
        env=policy.ReferenceEnvironment('clean-loader')
        with patch.dict(os.environ,{'LD_LIBRARY_PATH':'changed'}):
            with self.assertRaisesRegex(ValueError,'context drift'):env.child()
            with self.assertRaisesRegex(ValueError,'context drift'):env.assert_receipt(env.receipt())

    @unittest.skipUnless(shutil.which('clang'),'clang required for actual native child observation')
    def test_actual_c_compiler_and_exec_receive_clean_replacement(self):
        with tempfile.TemporaryDirectory() as directory,patch.dict(os.environ,{'LD_LIBRARY_PATH':directory}):
            work=Path(directory);source=work/'observe.c';binary=work/'observe'
            source.write_text('#include <stdio.h>\n#include <stdlib.h>\nint main(void){const char *v=getenv("LD_LIBRARY_PATH");puts(v?v:"absent");}\n')
            env=policy.ReferenceEnvironment('clean-loader')
            conformance.run(['clang',source,'-o',binary],env=env.child())
            self.assertEqual(conformance.run([binary],env=env.child()),'absent\n')
            self.assertEqual(conformance.run([binary],env=dict(os.environ)),directory+'\n')
            self.assertEqual(os.environ['LD_LIBRARY_PATH'],directory)

    def test_unknown_policy_invalidates_fixed_destination_reports(self):
        metal=runpy.run_path(str(conformance.ROOT/'tools/metal_probe.py'))
        cases=[(conformance.main,conformance.__dict__,'conformance.json',['conformance']),
               (metal['main'],metal['main'].__globals__,'metal-probe.json',['metal'])]
        for main,namespace,destination,argv in cases:
            with self.subTest(destination=destination),tempfile.TemporaryDirectory() as directory:
                work=Path(directory);report=work/destination;report.parent.mkdir(parents=True,exist_ok=True)
                report.write_text('{"passed":true}')
                with patch.dict(namespace,BUILD=work),patch.object(sys,'argv',argv+['--reference-loader-policy','unknown']),contextlib.redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit):main()
                self.assertIs(json.loads(report.read_text())['passed'],False)


if __name__=='__main__': unittest.main()
