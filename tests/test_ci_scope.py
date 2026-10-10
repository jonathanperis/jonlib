import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import ci_scope

PROBE = """EXAMPLES = {
    'core_basic_window': ('core/core_basic_window.c', 'Ex.setup(core, frame)'),
    'core_2d_camera': ('core/core_2d_camera.c', 'Ex.setup(seed, core, frame)'),
    'textures_logo_raylib': ('textures/textures_logo_raylib.c', 'Ex.setup(logo, core, frame)'),
    'core_undo_redo': ('core/core_undo_redo.c', 'Ex.setup(seed, core, frame)'),
    'text_inline_styling': ('text/text_inline_styling.c', 'Ex.setup(seed, core, frame)'),
}
SEEDED = {'text_inline_styling',
          'core_undo_redo'}
def scripts():
    return []
C_DRIVER = r'''#include "raylib.h"
'''
def build_reference(probe, name):
    pass
"""
DIFF = """--- a/tools/examples_probe.py
+++ b/tools/examples_probe.py
@@ -4,0 +5 @@
+    'core_undo_redo': ('core/core_undo_redo.c', 'Ex.setup(seed, core, frame)'),
@@ -6 +8,2 @@
-SEEDED = {'text_inline_styling'}
+SEEDED = {'text_inline_styling',
+          'core_undo_redo'}
"""


class ScopeTests(unittest.TestCase):
    def test_a_library_change_runs_everything(self):
        for path in ('jonlib.bend', 'jonmath.bend', 'src/frame.bend', 'LAWS.bend', 'toolchain.json', 'tools/probekit.py', 'tools/gates.json', 'tools/api_plan.py',
                     'tests/fixtures/images.json', 'api/progress.json', '.github/actions/setup-pinned/action.yml', 'something/new.txt'):
            self.assertEqual(ci_scope.scope([path, 'examples/core_undo_redo.bend'], PROBE)['mode'], 'full', path)

    def test_an_example_port_replays_itself_and_the_canaries(self):
        result = ci_scope.scope(['examples/core_undo_redo.bend', 'tools/examples_probe.py', 'api/examples.json', 'docs/EXAMPLES.md'], PROBE, DIFF)
        self.assertEqual(result, dict(mode='examples', examples=['core_2d_camera', 'core_basic_window', 'core_undo_redo', 'text_inline_styling', 'textures_logo_raylib']))

    def test_an_edited_port_alone_replays_only_itself(self):
        self.assertEqual(ci_scope.scope(['examples/core_undo_redo.bend'], PROBE), dict(mode='examples', examples=['core_undo_redo']))

    def test_a_script_edit_replays_the_examples_its_lines_name(self):
        self.assertEqual(ci_scope.named(DIFF, ci_scope.registered(PROBE)), {'core_undo_redo', 'text_inline_styling'})

    def test_a_change_to_the_probe_harness_runs_everything(self):
        for hunk in ('@@ -12 +12 @@', '@@ -14,2 +14,3 @@', '@@ -15,0 +15 @@', '@@ -10,3 +10,4 @@', '@@ -13,2 +12,0 @@'):
            diff = f'--- a/tools/examples_probe.py\n+++ b/tools/examples_probe.py\n{hunk}\n+    changed\n'
            self.assertEqual(ci_scope.scope(['tools/examples_probe.py'], PROBE, diff)['mode'], 'full', hunk)
        self.assertFalse(ci_scope.harness_changed(PROBE, DIFF))
        self.assertTrue(ci_scope.harness_changed('EXAMPLES = {}', DIFF))
        self.assertTrue(ci_scope.harness_changed(PROBE, ''))

    def test_a_deletion_above_the_driver_stays_scoped(self):
        diff = '--- a/tools/examples_probe.py\n+++ b/tools/examples_probe.py\n@@ -10,2 +9,0 @@\n-def scripts():\n-    return []\n'
        self.assertEqual(ci_scope.scope(['tools/examples_probe.py'], PROBE, diff)['mode'], 'examples')

    def test_an_unregistered_port_runs_everything(self):
        self.assertEqual(ci_scope.scope(['examples/models_new_thing.bend'], PROBE)['mode'], 'full')

    def test_harness_and_documentation_need_no_gate(self):
        paths = ['.github/workflows/conformance.yml', 'tests/test_ci_scope.py', 'tools/ci_scope.py', 'docs/CI.md', 'README.md', 'tools/example_tables.py']
        self.assertEqual(ci_scope.scope(paths, PROBE), dict(mode='none', examples=[]))

    def test_fixtures_under_tests_are_not_harness(self):
        self.assertEqual(ci_scope.kind('tests/fixtures/README.md'), 'none')
        self.assertEqual(ci_scope.kind('tests/fixtures/images.json'), 'full')
        self.assertEqual(ci_scope.kind('tests/decoding.bend'), 'full')

    def test_no_change_needs_nothing(self):
        self.assertEqual(ci_scope.scope([], PROBE), dict(mode='none', examples=[]))


class BaseTests(unittest.TestCase):
    def test_scheduled_and_manual_runs_are_full(self):
        self.assertIsNone(ci_scope.base_ref({'GITHUB_EVENT_NAME': 'schedule'}))
        self.assertIsNone(ci_scope.base_ref({'GITHUB_EVENT_NAME': 'workflow_dispatch'}))

    def test_a_first_push_to_main_is_full(self):
        self.assertIsNone(ci_scope.base_ref({'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF_NAME': 'main'}))


class VerifiedTests(unittest.TestCase):
    def test_another_successful_run_of_the_commit_counts(self):
        main = ci_scope.accepted_events({'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF_NAME': 'main'})
        self.assertTrue(ci_scope.verified([dict(id=7, conclusion='success', event='push')], '9', main))

    def test_this_run_a_failure_or_a_pull_request_merge_does_not(self):
        main = ci_scope.accepted_events({'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF_NAME': 'main'})
        self.assertFalse(ci_scope.verified([dict(id=9, conclusion='success', event='push')], '9', main))
        self.assertFalse(ci_scope.verified([dict(id=7, conclusion='failure', event='push')], '9', main))
        self.assertFalse(ci_scope.verified([dict(id=7, conclusion='success', event='pull_request')], '9', main))

    def test_a_nightly_run_accepts_only_full_runs(self):
        nightly = ci_scope.accepted_events({'GITHUB_EVENT_NAME': 'schedule', 'GITHUB_REF_NAME': 'main'})
        self.assertFalse(ci_scope.verified([dict(id=7, conclusion='success', event='push')], '9', nightly))
        self.assertTrue(ci_scope.verified([dict(id=7, conclusion='success', event='schedule')], '9', nightly))
        self.assertTrue(ci_scope.verified([dict(id=7, conclusion='success', event='workflow_dispatch')], '9', nightly))

    def test_branches_pull_requests_and_runs_without_a_token_never_ask(self):
        self.assertEqual(ci_scope.accepted_events({'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF_NAME': 'feature/x'}), ())
        self.assertEqual(ci_scope.accepted_events({'GITHUB_EVENT_NAME': 'pull_request', 'GITHUB_REF_NAME': 'main'}), ())
        self.assertEqual(ci_scope.accepted_events({'GITHUB_EVENT_NAME': 'workflow_dispatch', 'GITHUB_REF_NAME': 'main'}), ())
        self.assertFalse(ci_scope.already_verified({'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF_NAME': 'feature/x', 'GH_TOKEN': 't'}))
        self.assertFalse(ci_scope.already_verified({'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF_NAME': 'main'}))


if __name__ == '__main__':
    unittest.main()
