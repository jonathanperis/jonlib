import copy
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tools import api_plan as plan
from tools.api_catalog import extract_header
from tools.conformance import BUILD, inventory


class ApiPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.reference = plan.read('reference.json')
        cls.policy = plan.read('milestones.json')
        cls.progress = plan.read('progress.json')

    def test_conditional_support_and_overloads_keep_source_contracts(self):
        source = '''#ifndef RAYMATH_H
#define RAYMATH_H
#if FIRST
#define VALUE 1
#elif SECOND
#define VALUE (2 + 3)
#else
#define VALUE 8
#endif
#define CALL(x) ((x) + 1)
typedef struct Vec { float x, y; } Vec;
typedef enum { LEFT = 4, RIGHT, LAST = 1 << 5 } Side;
typedef void (*Hook)(Vec point);
RMAPI Vec Move(Vec value) {
    typedef int Private;
    return value;
}
#if defined(__cplusplus)
static constexpr Vec Origin = {0, 0};
inline Vec operator + (const Vec& lhs, const Vec& rhs) { return lhs; }
inline Vec operator + (const Vec& lhs, const float& rhs) { return lhs; }
#endif
#endif
'''
        rows = {row['id']: row for row in extract_header(source, 'raymath.h')}
        self.assertEqual(len(rows), 13)
        variants = rows['raymath:macro:VALUE']['variants']
        self.assertEqual([row['value'] for row in variants], ['1', '(2 + 3)', '8'])
        self.assertEqual(variants[1]['conditions'][-1], '!( FIRST ) && (SECOND)')
        self.assertEqual(variants[2]['conditions'][-1], '!( FIRST || SECOND )')
        self.assertEqual(rows['raymath:macro:CALL']['variants'][0]['parameters'], '(x)')
        self.assertEqual(rows['raymath:enumerator:RIGHT']['variants'][0]['value'], 'LEFT + 1')
        self.assertEqual(rows['raymath:type:Vec']['variants'][0]['members'], ['float x, y'])
        self.assertIn('raymath:operator:operator+(const Vec&,const float&)', rows)
        self.assertIn('raymath:operator:operator+(const Vec&,const Vec&)', rows)
        self.assertNotIn('raymath:alias:Private', rows)
        for row in rows.values():
            self.assertIn(row['name'].split('(')[0].replace('operator+', 'operator +'), source.splitlines()[row['line']-1])
        boundary = 'RLAPI void Public(void);\n#ifdef RLGL_IMPLEMENTATION\nvoid private_fn(void) {}\n#define PRIVATE 1\n#endif\n'
        self.assertEqual([row['name'] for row in extract_header(boundary, 'rlgl.h')], ['Public', 'RLGL_IMPLEMENTATION'])

    def test_pinned_inventory_migration_and_dependency_order(self):
        policy = copy.deepcopy(self.policy)
        policy['priority_overrides'] = {'raylib:function:ImageDraw':0, 'raylib:function:ImageResize':1}
        outputs, report = plan.generated(self.reference, policy, self.progress)
        counts = {header: sum(row['header'] == header and row['kind'] == 'function'
                              for row in self.reference['entries']) for header in self.reference['scope']}
        self.assertEqual(counts, {'raylib.h':600, 'raymath.h':146, 'rlgl.h':163,
                                  'rcamera.h':12, 'rgestures.h':10, 'config.h':0})
        self.assertEqual(report['next_work'][0]['id'], 'raylib:function:ImageDraw')
        self.assertEqual(report['next_work'][1]['id'], 'raylib:function:ImageResize')
        legacy = json.loads(outputs['docs/api-map.json'])
        baseline = {'GenImageColor','ImageClearBackground','ImageDrawPixel','ImageDrawRectangle','ImageDrawCircle',
                    'ImageFlipHorizontal','ImageFlipVertical','LoadImageColors','GetImageColor','ImageCopy','GetColor',
                    'ColorToInt','ColorAlphaBlend','ImageDrawLine','ImageDrawLineV','ImageDrawTriangle','ImageDrawTriangleLines',
                    'ImageDraw','ImageFromImage','ImageCrop','ImageResizeNN','ImageResize'}
        self.assertLessEqual(baseline, set(legacy))
        self.assertIn('Surface.draw_image_rect', legacy['ImageDraw']['jonlib'])
        self.assertEqual(legacy['ImageResize']['jonlib'], 'Surface.resize')
        seen = set()
        for milestone in report['milestones']:
            self.assertLessEqual(set(milestone['depends_on']), seen)
            seen.add(milestone['id'])
        rows = {row['name']: row for row in json.loads(outputs['api/ledger.json'])['entries'] if row['header']=='raylib.h'}
        for name, milestone in {'GetImageColor':'images', 'Fade':'pixels', 'ImageDrawText':'fonts',
                                'LoadImageFromScreen':'textures', 'PlayAutomationEvent':'frame',
                                'LoadSoundFromWave':'audio-device', 'ToggleFullscreen':'window'}.items():
            self.assertEqual(rows[name]['milestone'], milestone)
        previous = json.loads(outputs['api/ledger.json'])
        next(row for row in previous['entries'] if row['id'] == 'raylib:function:ImageDraw')['evidence'] = []
        with patch('sys.argv', ['api_plan.py','report','--since','baseline','--json']), patch.object(plan.subprocess, 'check_output', return_value=json.dumps(previous)), patch('sys.stdout', new_callable=io.StringIO) as output:
            plan.main()
        changed = json.loads(output.getvalue())['changed']
        self.assertEqual(changed, [dict(id='raylib:function:ImageDraw', before='partial', after='partial', changes=['evidence'])])

    def test_invalid_plan_and_unproved_completion_fail(self):
        key = 'raylib:function:ImageDraw'
        def update_progress(progress, **changes):
            progress['entries'][key].update(changes)
        cases = [
            ('unknown ID', lambda p, u: u['entries'].update({'raylib:function:Typo':{}})),
            ('unknown dependency', lambda p, u: p['api_dependencies'].update({key:['unknown']})),
            ('API cycle', lambda p, u: p['api_dependencies'].update({key:[key]})),
            ('milestone cycle', lambda p, u: p['milestones'][0]['depends_on'].append('images')),
            ('invalid status', lambda p, u: update_progress(u, status='done')),
            ('missing evidence', lambda p, u: update_progress(u, evidence=['missing-evidence.json'])),
            ('unsupported completion', lambda p, u: update_progress(u, status='complete')),
            ('no blocker', lambda p, u: update_progress(u, status='blocked')),
            ('weakened gates', lambda p, u: p['completion_gates'].clear()),
            ('empty targets', lambda p, u: p['targets'].clear()),
        ]
        for name, mutate in cases:
            with self.subTest(name=name):
                policy, progress = copy.deepcopy(self.policy), copy.deepcopy(self.progress)
                mutate(policy, progress)
                with self.assertRaises(ValueError):
                    plan.make_ledger(self.reference, policy, progress)
        # A structurally complete claim is allowed only with all required evidence.
        # This synthetic record exercises validation; it is never written to progress.
        evidence = ['tests/test_api_plan.py']
        completed = dict(status='complete', jonlib='Surface.draw_image', symbols=['Surface.draw_image'],
                         gaps=[], evidence=evidence, gates={g:'verified' for g in plan.GATES},
                         gate_evidence={g:evidence for g in plan.GATES},
                         target_results={t['id']:dict(status='verified', evidence=evidence) for t in self.policy['targets']})
        progress = copy.deepcopy(self.progress)
        progress['entries'][key] = completed
        plan.make_ledger(self.reference, self.policy, progress)
        for field in ('gate_evidence', 'target_results', 'symbols'):
            with self.subTest(missing=field):
                bad = copy.deepcopy(progress)
                bad['entries'][key].pop(field)
                with self.assertRaises(ValueError):
                    plan.make_ledger(self.reference, self.policy, bad)

    def test_check_rejects_stale_outputs_and_source_drift(self):
        BUILD.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=BUILD, prefix='api-plan-') as directory:
            root = Path(directory)
            file = root / 'generated.json'
            report = dict(declaration_inventory={'total':1}, core_functions={'partial':0, 'complete':0})
            with patch.object(plan, 'ROOT', root), patch.object(plan, 'generated', return_value=({'generated.json':'expected'}, report)), patch('sys.argv', ['api_plan.py','check']), patch('sys.stdout', new_callable=io.StringIO):
                for content in (None, 'stale'):
                    if content is not None:
                        file.write_text(content)
                    with self.assertRaisesRegex(ValueError, 'Stale generated'):
                        plan.main()
                file.write_text('expected')
                plan.main()
                with patch('sys.argv', ['api_plan.py','check','--raylib-source',str(root)]), patch.object(plan, 'source_catalog', return_value={}):
                    with self.assertRaisesRegex(ValueError, 'catalog differ'):
                        plan.main()
        with self.assertRaisesRegex(ValueError, 'differs from the committed API reference'):
            inventory('RLAPI void Fake(void);')
