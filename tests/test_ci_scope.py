import json
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
import probekit
from conformance import gradient_reference
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


def gate(name, tool, minutes, *extra):
    return dict(id=name, title=name, run=['{python}', f'tools/{tool}.py', '--bend-source={bend}', *extra], os=['linux', 'macos'], minutes=minutes)


GATES = [gate('conformance', 'conformance', 45), gate('examples-core', 'examples_probe', 25, '--category=core'),
         gate('examples-shapes', 'examples_probe', 45, '--category=shapes'), gate('rand', 'rand_probe', 1), gate('api-audit', 'api_plan', 1, 'check'),
         gate('png-file', 'png_file_probe', 117), gate('bmp-file', 'bmp_file_probe', 89), gate('pic-file', 'pic_file_probe', 70), gate('tga-format', 'tga_format_probe', 59)]
FORMAT = 'import probekit\nfrom conformance import gradient_reference\n'
JONMATH = 'import Base\n\n# Sines.\ndef sin(x: F32) -> F32:\n  x\n\ntype Libm:\n  Apple{}\n  Glibc{}\n'
TREE = {
    'tools/gates.json': json.dumps(dict(description='gates', gates=GATES)),
    'tools/conformance.py': "import probekit\nPROOFS = [ROOT / 'LAWS.bend', ROOT / 'PROOF.bend']\nrun([sys.executable, ROOT / 'tools/api_plan.py', 'check'])\n",
    'tools/probekit.py': 'import os\n', 'tools/api_plan.py': 'import json\n', 'tools/examples_probe.py': PROBE,
    'tools/rand_probe.py': "import probekit\nMODEL = ROOT / 'tools/reference/glibc_rand/model.c'\n",
    'tools/png_file_probe.py': FORMAT, 'tools/bmp_file_probe.py': FORMAT, 'tools/pic_file_probe.py': FORMAT, 'tools/tga_format_probe.py': FORMAT,
    'tools/metal_probe.py': 'import probekit\n', 'jonmath.bend': JONMATH, 'jonlib.bend': 'import ./jonmath.bend as M\n\ndef one() -> U32:\n  1\n',
}


def scope(changes, diffs=None):
    """The scope of {path: new text, or None when deleted} applied to TREE."""
    new = {**TREE, **{path: text for path, text in changes.items() if text is not None}}
    for path, text in changes.items():
        if text is None:
            new.pop(path, None)
    status = {path: 'D' if text is None else 'M' if path in TREE else 'A' for path, text in changes.items()}
    return ci_scope.scope(status, lambda path: TREE.get(path, ''), lambda path: new.get(path, ''), lambda path: (diffs or {}).get(path, ''))


class AdditiveTests(unittest.TestCase):
    def test_whole_new_definitions_are_additive(self):
        self.assertTrue(ci_scope.additive(JONMATH, JONMATH + '\ndef cos(x: F32) -> F32:\n  x\n'))
        self.assertTrue(ci_scope.additive(JONMATH, JONMATH.replace('# Sines.', 'import ./src/power.bend as Power\n\ndef exp(x: F32) -> F32:\n  x\n\n# Sines.')))
        self.assertTrue(ci_scope.additive('', JONMATH))
        self.assertTrue(ci_scope.additive(JONMATH, JONMATH))

    def test_a_touched_definition_is_not(self):
        for name, new in dict(body=JONMATH.replace('  x\n', '  x + 1.0\n'), signature=JONMATH.replace('x: F32', 'y: F32'), removed=JONMATH.replace('def sin(x: F32) -> F32:\n  x\n', ''),
                              constructor=JONMATH + '  Musl{}\n', split=JONMATH.replace('  Apple{}\n', '  Apple{}\ndef two() -> U32:\n  2\n'),
                              moved=JONMATH.replace('# Sines.\ndef sin(x: F32) -> F32:\n  x\n\n', '') + '\ndef sin(x: F32) -> F32:\n  x\n', comment=JONMATH.replace('Sines', 'Sine')).items():
            self.assertFalse(ci_scope.additive(JONMATH, new), name)


class ScopeTests(unittest.TestCase):
    NEW = diff((5, [], 6, [line(6)]), (9, ["SEEDED = {'core_2d_camera', 'text_inline_styling'}"], 9, [line(9), line(10)]), (16, [], 17, [line(17), line(18), line(19)]))
    KERNEL = {'src/libc_rand.bend': 'def lcg(x: U32) -> U32:\n  x\n', 'jonmath.bend': JONMATH + '\ndef rand(x: U32) -> U32:\n  x\n', 'LAWS.bend': 'law', 'PROOF.bend': 'proof',
              'tools/reference/glibc_rand/model.c': 'int main;', 'tests/test_rand_probe.py': 'import unittest\n', 'docs/RANDOM.md': '# Random\n', 'api/progress.json': '{}'}

    def test_a_new_kernel_runs_the_corpus_the_core_examples_and_its_own_gate(self):
        result = scope(self.KERNEL)
        self.assertEqual((result['mode'], result['gates']), ('scoped', ['api-audit', 'conformance', 'examples-core', 'rand']))
        self.assertEqual(result['matrix'], dict(include=[
            dict(os=runner, part='gates 1', gates='--only=conformance --only=examples-core --only=api-audit --only=rand', examples='') for runner in ('ubuntu-24.04', 'macos-15')]))

    def test_a_changed_or_removed_definition_runs_everything(self):
        for name, change in dict(changed={'jonmath.bend': JONMATH.replace('  x\n', '  x + 1.0\n')}, removed={'jonmath.bend': None}, core={'jonlib.bend': 'def one() -> U32:\n  2\n'}).items():
            result = scope({**self.KERNEL, **change})
            self.assertEqual(result['mode'], 'full', name)
            self.assertIn('changed or lost a definition', result['reason'])

    def test_the_proofs_run_the_gate_that_checks_them(self):
        self.assertEqual(scope({'LAWS.bend': 'law', 'PROOF.bend': 'proof'})['gates'], ['conformance'])

    def test_a_ledger_runs_the_gates_that_run_the_api_plan(self):
        self.assertEqual(scope({'api/progress.json': '{}'})['gates'], ['api-audit', 'conformance'])

    def test_a_probe_runs_its_gate(self):
        self.assertEqual(scope({'tools/png_file_probe.py': FORMAT + '# changed\n'})['gates'], ['png-file'])
        self.assertEqual(scope({'tools/api_plan.py': 'import json\n# changed\n'})['gates'], ['api-audit', 'conformance'])

    def test_a_shared_tool_runs_everything(self):
        result = scope({'tools/probekit.py': 'import os\n# changed\n'})
        self.assertEqual(result['mode'], 'full')
        self.assertIn('8 gates are affected', result['reason'])

    def test_gates_are_packed_into_jobs_per_host(self):
        result = scope({'tools/png_file_probe.py': FORMAT + '#\n', 'tools/bmp_file_probe.py': FORMAT + '#\n', 'tools/rand_probe.py': TREE['tools/rand_probe.py'] + '#\n'})
        self.assertEqual([(row['os'], row['part'], row['gates']) for row in result['matrix']['include']],
                         [(runner, part, gates) for runner in ('ubuntu-24.04', 'macos-15') for part, gates in (('gates 1', '--only=png-file'), ('gates 2', '--only=bmp-file --only=rand'))])

    def test_a_gate_on_one_host_is_not_asked_of_the_other(self):
        gates = [dict(entry, os=['linux']) if entry['id'] == 'rand' else entry for entry in GATES]
        result = scope({'tools/gates.json': json.dumps(dict(description='gates', gates=gates))})
        self.assertEqual(result['matrix'], dict(include=[dict(os='ubuntu-24.04', part='gates 1', gates='--only=rand', examples='')]))

    def test_the_manifest_runs_the_gates_whose_command_changed(self):
        timed = [dict(entry, minutes=3, title='again') for entry in GATES]
        self.assertEqual(scope({'tools/gates.json': json.dumps(dict(description='gates', gates=timed))})['mode'], 'none')
        added = GATES + [gate('sha', 'sha_probe', 2)]
        self.assertEqual(scope({'tools/gates.json': json.dumps(dict(description='gates', gates=added)), 'tools/sha_probe.py': 'import probekit\n'})['gates'], ['sha'])
        self.assertEqual(scope({'tools/gates.json': 'not json'})['mode'], 'full')

    def test_reference_material_runs_the_gates_that_name_it(self):
        self.assertEqual(scope({'tools/reference/glibc_rand/results/x.json': '{}'})['gates'], ['rand'])
        self.assertEqual(scope({'tools/reference/input_clock.h': '//'})['mode'], 'full')

    def test_an_example_port_replays_itself_and_the_canaries(self):
        result = scope({'examples/core_undo_redo.bend': 'def setup', 'tools/examples_probe.py': PROBE, 'api/examples.json': '{}', 'docs/EXAMPLES.md': '#'}, {'tools/examples_probe.py': self.NEW})
        self.assertEqual((result['mode'], result['gates'], result['examples']), ('scoped', [], sorted([*CANARIES, 'core_undo_redo', 'text_inline_styling'])))
        self.assertEqual([(row['os'], row['part'], row['gates']) for row in result['matrix']['include']], [('ubuntu-24.04', 'examples', ''), ('macos-15', 'examples', '')])
        self.assertEqual(result['matrix']['include'][0]['examples'], ' '.join(f'--example={name}' for name in result['examples']))

    def test_an_edited_port_alone_replays_only_itself(self):
        self.assertEqual(scope({'examples/core_undo_redo.bend': 'def setup'})['examples'], ['core_undo_redo'])

    def test_a_change_to_the_probe_harness_runs_every_examples_gate(self):
        result = scope({'tools/examples_probe.py': PROBE}, {'tools/examples_probe.py': diff((31, ['    return'], 31, [line(31)]))})
        self.assertEqual((result['gates'], result['examples']), (['examples-core', 'examples-shapes'], []))

    def test_a_probe_comment_replays_the_canaries(self):
        self.assertEqual(scope({'tools/examples_probe.py': PROBE}, {'tools/examples_probe.py': diff((17, ['        # Undo.'], 17, [line(17)]))})['examples'], CANARIES)

    def test_an_unregistered_port_runs_everything(self):
        self.assertEqual(scope({'examples/models_new_thing.bend': 'def setup'})['mode'], 'full')

    def test_what_no_rule_places_runs_everything(self):
        for path in ('toolchain.json', 'tools/run_gates.py', 'tests/fixtures/images.json', 'tests/decoding.bend', '.github/actions/setup-pinned/action.yml', 'something/new.txt', 'src/data.bin'):
            result = scope({path: 'x', 'examples/core_undo_redo.bend': 'def setup'})
            self.assertEqual((result['mode'], result['reason']), ('full', f'no rule places {path}'))

    def test_a_tool_no_gate_reaches_runs_everything_unless_it_is_new(self):
        self.assertEqual(scope({'tools/metal_probe.py': 'import probekit\n# changed\n'})['mode'], 'full')
        self.assertEqual(scope({'tools/png_file_probe.py': None})['mode'], 'full')
        self.assertEqual(scope({'tools/new_helper.py': 'import os\n'})['mode'], 'none')

    def test_harness_and_documentation_need_no_gate(self):
        paths = ['.github/workflows/conformance.yml', 'tests/test_ci_scope.py', 'tools/ci_scope.py', 'docs/CI.md', 'README.md', 'tools/example_tables.py']
        self.assertEqual(scope({path: 'x' for path in paths}), ci_scope.NONE)
        self.assertEqual(ci_scope.kind('tests/fixtures/README.md'), 'none')

    def test_no_change_needs_nothing(self):
        self.assertEqual(scope({}), ci_scope.NONE)


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
