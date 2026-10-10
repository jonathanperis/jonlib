import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import ci_scope

PROBE = """KEY_A, KEY_B = 65, 66
EXAMPLES = {
    'core_basic_window': ('core/core_basic_window.c', 'Ex.setup(core, frame)'),
    'core_2d_camera': ('core/core_2d_camera.c', 'Ex.setup(seed, core, frame)'),
    'textures_logo_raylib': ('textures/textures_logo_raylib.c', 'Ex.setup(logo, core, frame)'),
    'core_undo_redo': ('core/core_undo_redo.c', 'Ex.setup(seed, core, frame)'),
    'text_inline_styling': ('text/text_inline_styling.c', 'Ex.setup(seed, core, frame)'),
}
SEEDED = {'core_2d_camera', 'text_inline_styling',
          'core_undo_redo'}
FLAGS = {'core_2d_camera': 32, 'text_inline_styling': 4}
def quick(events=()):
    return events
def scripts():
    out = [
        script('core_basic_window', 'frames', [quick(), quick()]),
        # Undo twice, redo once.
        script('core_undo_redo', 'undo', [quick(), quick([KEY_A]),
                                          quick([KEY_B])]),
        script('text_inline_styling', 'still', [quick()]),
    ]
    return out
REPORTED = {'text_inline_styling'}
def refusal(item):
    if item['example'] == 'core_2d_camera':
        return 3
    return None
C_DRIVER = r\'\'\'#include "raylib.h"
\'\'\'
def build_reference(probe, name):
    pass
"""
NAMES = {'core_basic_window', 'core_2d_camera', 'textures_logo_raylib', 'core_undo_redo', 'text_inline_styling'}
CANARIES = ['core_2d_camera', 'core_basic_window', 'textures_logo_raylib']


def diff(*hunks):
    """A -U0 diff of the probe: (old start, removed lines, new start, added lines) per hunk."""
    text = '--- a/tools/examples_probe.py\n+++ b/tools/examples_probe.py\n'
    for old, removed, new, added in hunks:
        text += f'@@ -{old},{len(removed)} +{new},{len(added)} @@\n' + ''.join(f'-{line}\n' for line in removed) + ''.join(f'+{line}\n' for line in added)
    return text


def line(number):
    return PROBE.splitlines()[number - 1]


class ProbeTests(unittest.TestCase):
    def affected(self, *hunks):
        return ci_scope.probe_examples(PROBE, diff(*hunks), NAMES)

    def test_a_new_registration_names_its_example(self):
        self.assertEqual(self.affected((5, [], 6, [line(6)])), {'core_undo_redo'})

    def test_a_changed_setup_expression_names_its_example(self):
        self.assertEqual(self.affected((6, [line(6).replace('seed, ', '')], 6, [line(6)])), {'core_undo_redo'})

    def test_a_new_set_member_names_itself_and_the_entry_it_follows(self):
        old = "SEEDED = {'core_2d_camera', 'text_inline_styling'}"
        self.assertEqual(self.affected((9, [old], 9, [line(9), line(10)])), {'core_undo_redo', 'text_inline_styling'})

    def test_a_reflowed_set_names_nothing(self):
        old = "SEEDED = {'core_2d_camera', 'text_inline_styling', 'core_undo_redo'}"
        self.assertEqual(self.affected((9, [old], 9, [line(9), line(10)])), set())

    def test_a_changed_table_value_names_its_example(self):
        self.assertEqual(self.affected((11, [line(11).replace('32', '64')], 11, [line(11)])), {'core_2d_camera'})

    def test_a_script_line_belongs_to_the_script_it_continues(self):
        self.assertEqual(self.affected((19, ['                                          quick()]),'], 19, [line(19)])), {'core_undo_redo'})
        self.assertEqual(self.affected((19, [line(19)], 18, [])), {'core_undo_redo'})

    def test_a_new_script_with_its_comment_names_only_itself(self):
        self.assertEqual(self.affected((16, [], 17, [line(17), line(18), line(19)])), {'core_undo_redo'})
        self.assertEqual(self.affected((17, ['        # Undo once.'], 17, [line(17)])), set())

    def test_a_prediction_naming_its_example_is_scoped(self):
        self.assertEqual(self.affected((24, [], 25, [line(25), line(26)])), {'core_2d_camera'})
        self.assertEqual(self.affected((23, ['REPORTED = set()'], 23, [line(23)])), {'text_inline_styling'})
        self.assertEqual(self.affected((25, ["    if frame > 2 and item['example'] == 'core_2d_camera':"], 25, [line(25)])), {'core_2d_camera'})

    def test_new_constants_and_comments_name_nothing(self):
        self.assertEqual(self.affected((1, [], 2, ['KEY_TWO, KEY_ONE = 50, 49', '(GAMEPAD_UP, GAMEPAD_DOWN) = (11, 12)', '# More keys.', ''])), set())

    def test_shared_code_runs_everything(self):
        for name, hunk in dict(constant_changed=(1, ['KEY_A, KEY_B = 65, 67'], 1, [line(1)]), helper=(13, ['    return ()'], 13, [line(13)]),
                               list_end=(22, ['    return list(out)'], 22, [line(22)]), prediction=(27, ['    return 0'], 27, [line(27)]),
                               driver=(28, ['C_DRIVER = r\'\'\'#include "rlgl.h"'], 28, [line(28)]), below=(31, ['    return'], 31, [line(31)]),
                               below_deleted=(31, ['    pass'], 30, []), across=(14, [line(14), line(15)], 14, [line(14), line(15)])).items():
            self.assertIsNone(self.affected(hunk), name)

    def test_an_unreadable_probe_or_diff_runs_everything(self):
        self.assertIsNone(ci_scope.probe_examples('EXAMPLES = {}', diff((1, [], 1, ['x'])), NAMES))
        self.assertIsNone(ci_scope.probe_examples(PROBE, '', NAMES))


class ScopeTests(unittest.TestCase):
    NEW = diff((5, [], 6, [line(6)]), (9, ["SEEDED = {'core_2d_camera', 'text_inline_styling'}"], 9, [line(9), line(10)]), (16, [], 17, [line(17), line(18), line(19)]))

    def test_a_library_change_runs_everything(self):
        for path in ('jonlib.bend', 'jonmath.bend', 'src/frame.bend', 'LAWS.bend', 'toolchain.json', 'tools/probekit.py', 'tools/gates.json', 'tools/api_plan.py',
                     'tests/fixtures/images.json', 'api/progress.json', '.github/actions/setup-pinned/action.yml', 'something/new.txt'):
            self.assertEqual(ci_scope.scope([path, 'examples/core_undo_redo.bend'], PROBE)['mode'], 'full', path)

    def test_an_example_port_replays_itself_and_the_canaries(self):
        result = ci_scope.scope(['examples/core_undo_redo.bend', 'tools/examples_probe.py', 'api/examples.json', 'docs/EXAMPLES.md'], PROBE, self.NEW)
        self.assertEqual(result, dict(mode='examples', examples=sorted([*CANARIES, 'core_undo_redo', 'text_inline_styling'])))

    def test_an_edited_port_alone_replays_only_itself(self):
        self.assertEqual(ci_scope.scope(['examples/core_undo_redo.bend'], PROBE), dict(mode='examples', examples=['core_undo_redo']))

    def test_a_change_to_the_probe_harness_runs_everything(self):
        self.assertEqual(ci_scope.scope(['tools/examples_probe.py'], PROBE, diff((31, ['    return'], 31, [line(31)])))['mode'], 'full')

    def test_a_probe_comment_replays_the_canaries(self):
        self.assertEqual(ci_scope.scope(['tools/examples_probe.py'], PROBE, diff((17, ['        # Undo.'], 17, [line(17)]))), dict(mode='examples', examples=CANARIES))

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
    MAIN = {'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF_NAME': 'main', 'GH_TOKEN': 't'}

    def test_another_successful_run_of_the_commit_counts(self):
        self.assertTrue(ci_scope.verified([dict(id=7, conclusion='success', event='push')], '9', ci_scope.RUN_EVENTS))

    def test_this_run_a_failure_or_a_pull_request_merge_does_not(self):
        self.assertFalse(ci_scope.verified([dict(id=9, conclusion='success', event='push')], '9', ci_scope.RUN_EVENTS))
        self.assertFalse(ci_scope.verified([dict(id=7, conclusion='failure', event='push')], '9', ci_scope.RUN_EVENTS))
        self.assertFalse(ci_scope.verified([dict(id=7, conclusion='success', event='pull_request')], '9', ci_scope.RUN_EVENTS))

    def test_a_fast_forward_merge_compares_the_head_with_itself(self):
        self.assertEqual(ci_scope.verified_base(['head', 'parent'], self.MAIN, lambda sha, events, env: sha == 'head'), 'head')

    def test_a_merge_commit_compares_with_the_merged_branch(self):
        asked = []
        passed = lambda sha, events, env: asked.append(sha) or sha in ('main', 'branch')
        self.assertEqual(ci_scope.verified_base(['merge', 'main', 'branch'], self.MAIN, passed), 'branch')
        self.assertEqual(asked, ['merge', 'branch'])

    def test_without_a_passing_commit_the_event_decides(self):
        self.assertIsNone(ci_scope.verified_base(['head', 'parent'], self.MAIN, lambda sha, events, env: False))

    def test_only_a_push_to_main_with_a_token_asks(self):
        never = lambda sha, events, env: self.fail('asked')
        for env in ({'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF_NAME': 'feature/x', 'GH_TOKEN': 't'}, {'GITHUB_EVENT_NAME': 'push', 'GITHUB_REF_NAME': 'main'},
                    {'GITHUB_EVENT_NAME': 'pull_request', 'GITHUB_REF_NAME': 'main', 'GH_TOKEN': 't'}, {'GITHUB_EVENT_NAME': 'schedule', 'GITHUB_REF_NAME': 'main', 'GH_TOKEN': 't'}):
            self.assertIsNone(ci_scope.verified_base(['head', 'parent'], env, never))

    def test_a_nightly_run_accepts_only_complete_runs(self):
        env = {'GITHUB_EVENT_NAME': 'schedule', 'GITHUB_REF_NAME': 'main', 'GH_TOKEN': 't', 'GITHUB_SHA': 'head'}
        self.assertTrue(ci_scope.nightly_done(env, lambda sha, events, env: sha == 'head' and events == ci_scope.FULL_EVENTS))
        self.assertFalse(ci_scope.nightly_done(env, lambda sha, events, env: 'push' in events))
        self.assertFalse(ci_scope.nightly_done(dict(self.MAIN, GITHUB_SHA='head'), lambda sha, events, env: True))
        self.assertFalse(ci_scope.verified([dict(id=7, conclusion='success', event='push')], '9', ci_scope.FULL_EVENTS))


if __name__ == '__main__':
    unittest.main()
