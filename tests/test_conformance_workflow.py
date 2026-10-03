"""Byte-exact CI topology contract, with no third-party test dependencies.

The frozen, hash-checked workflow is the reviewed pre-split checkpoint. This is
deliberately not a YAML parser: only job/step boundaries are recognized, then
every remaining byte is compared. Unknown syntax, settings, steps, or jobs fail
closed. YAML layout comments outside scripts and job separators are immaterial;
run-block bytes, expressions, action pins, and all settings are not.
"""

from collections import Counter
import hashlib
import fnmatch
import itertools
import os
from pathlib import Path
import re
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / 'tests/fixtures/conformance-before-runtime-split.yml'
WORKFLOW = ROOT / '.github/workflows/conformance.yml'
BASELINE_SHA256 = '610acab9fa0ca7fa6c3db8b93a828693c47e8ac202d89f76f0246053c45b84f9'
# Exact 81-gate workflow at 08dd860ebd24c8d1f49eb130d848764723e1f5c7.
# This adds a preservation anchor without replacing the original baseline.
BMP_PREDECESSOR_SHA256 = '34fa72b91f6e4ab3e7e555c51e621364bf1b68e1dba4945db2442ad8e463ce7e'
# Exact 82-gate workflow at 82a81b12e61ede4ec2d9901baddd4bf773651a5d.
BMP_FILE_PREDECESSOR_SHA256 = '809c8d6c02b715b44cfa013a1c2644ac5d15cf0a8b1d8dc5d2f5745ce5c5e4f1'
FORMATTED_GATES = (
    'Verify checked formatted BMP bytes and typed IO',
    'Verify checked formatted TGA bytes and typed IO',
    'Verify checked formatted QOI bytes, source rejection and typed IO',
    'Verify native QOI formats and exact memory bytes',
    'Verify native PNM formats and exact reduced memory bytes',
    'Verify format-preserving PNM file loading and bounded closure',
    'Verify original-format QOI files and descriptor closure',
)
FORMATTED_PATHS = (
    '.build/formatted-bmp-export-probe/',
    '.build/formatted-tga-export-probe/',
    '.build/formatted-qoi-export-probe/',
    '.build/qoi-format-probe/',
    '.build/pnm-format-probe/',
    '.build/pnm-file-probe/results.json',
    '.build/pnm-file-probe/run-*/*.command.json',
    '.build/pnm-file-probe/run-*/*.resource.json',
    '.build/qoi-file-probe/results.json',
    '.build/qoi-file-probe/run-*/inputs.json',
    '.build/qoi-file-probe/run-*/*.bend',
    '.build/qoi-file-probe/run-*/*.c',
    '.build/qoi-file-probe/run-*/*.stdout',
    '.build/qoi-file-probe/run-*/*.stderr',
    '.build/qoi-file-probe/run-*/*.command.json',
    '.build/qoi-file-probe/run-*/*.resource.json',
)
# Explicitly reviewed additions are separate from the immutable 79-gate baseline.
ADDED_FORMATTED_GATES = ('''      - name: Verify native TGA formats and exact memory bytes
        run: >-
          python3 tools/tga_format_probe.py --reference-env clean-loader
          --bend-source "${{ github.workspace }}/.build/dependencies/bend"
          --raylib-source "${{ github.workspace }}/.build/dependencies/raylib"
''', '''      - name: Verify format-preserving TGA file loading and bounded closure
        run: >-
          python3 tools/tga_file_probe.py --reference-env clean-loader
          --bend-source "${{ github.workspace }}/.build/dependencies/bend"
          --raylib-source "${{ github.workspace }}/.build/dependencies/raylib"
''',)
ADDED_FORMATTED_PATHS = (
    '.build/tga-format-probe/',
    '.build/tga-file-probe/',
    '!.build/tga-file-probe/run-*/fixtures/cap-plus-one.tga',
    '!.build/tga-file-probe/run-*/fixtures/cap-plus-one.qoi',
    '!.build/tga-file-probe/run-*/fixtures/larger-file.tga',
    '!.build/tga-file-probe/run-*/fixtures/host-size-overflow.tga',
)
BMP_GATES = ('''      - name: Verify native BMP formats and exact memory bytes
        run: >-
          python3 tools/bmp_format_probe.py --reference-env clean-loader
          --bend-source "${{ github.workspace }}/.build/dependencies/bend"
          --raylib-source "${{ github.workspace }}/.build/dependencies/raylib"
''',)
BMP_PATHS = ('.build/bmp-format-probe/',)
ADDED_BMP_FILE_GATES = ('''      - name: Verify format-preserving BMP file loading and bounded closure
        run: >-
          python3 tools/bmp_file_probe.py --reference-env clean-loader
          --bend-source "${{ github.workspace }}/.build/dependencies/bend"
          --raylib-source "${{ github.workspace }}/.build/dependencies/raylib"
''',)
ADDED_BMP_FILE_PATHS = (
    '.build/bmp-file-probe/',
    '!.build/bmp-file-probe/run-*/fixtures/cap-plus-one.bmp',
    '!.build/bmp-file-probe/run-*/fixtures/cap-plus-one.qoi',
    '!.build/bmp-file-probe/run-*/fixtures/larger-file.bmp',
    '!.build/bmp-file-probe/run-*/fixtures/host-size-overflow.bmp',
)
PLATFORMS = (('Ubuntu', 'ubuntu-24.04'), ('Mac', 'macos-15'))
ORIGINAL_WORKERS = ('coreUbuntu', 'coreMac', 'formattedUbuntu', 'formattedMac')
BMP_WORKERS = ('bmpUbuntu', 'bmpMac')
WORKERS = (*ORIGINAL_WORKERS, *BMP_WORKERS)
ORIGINAL_RESULT_VARIABLES = ('CORE_UBUNTU_RESULT', 'CORE_MAC_RESULT',
                             'FORMATTED_UBUNTU_RESULT', 'FORMATTED_MAC_RESULT')
BMP_RESULT_VARIABLES = ('BMP_UBUNTU_RESULT', 'BMP_MAC_RESULT')
RESULT_VARIABLES = (*ORIGINAL_RESULT_VARIABLES, *BMP_RESULT_VARIABLES)
AGGREGATE = '''    name: CPU and JavaScript (__PLATFORM__)
    if: ${{ always() }}
    needs: [coreUbuntu, coreMac, formattedUbuntu, formattedMac, bmpUbuntu, bmpMac]
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - name: Require every conformance shard
        shell: bash
        env:
          CORE_UBUNTU_RESULT: ${{ needs.coreUbuntu.result }}
          CORE_MAC_RESULT: ${{ needs.coreMac.result }}
          FORMATTED_UBUNTU_RESULT: ${{ needs.formattedUbuntu.result }}
          FORMATTED_MAC_RESULT: ${{ needs.formattedMac.result }}
          BMP_UBUNTU_RESULT: ${{ needs.bmpUbuntu.result }}
          BMP_MAC_RESULT: ${{ needs.bmpMac.result }}
        run: |
          set -eu
          printf 'Core Ubuntu: %s; core macOS: %s; formatted Ubuntu: %s; formatted macOS: %s\\n' "${CORE_UBUNTU_RESULT:-missing}" "${CORE_MAC_RESULT:-missing}" "${FORMATTED_UBUNTU_RESULT:-missing}" "${FORMATTED_MAC_RESULT:-missing}"
          printf 'BMP Ubuntu: %s; BMP macOS: %s\\n' "${BMP_UBUNTU_RESULT:-missing}" "${BMP_MAC_RESULT:-missing}"
          test "${CORE_UBUNTU_RESULT:-}" = success
          test "${CORE_MAC_RESULT:-}" = success
          test "${FORMATTED_UBUNTU_RESULT:-}" = success
          test "${FORMATTED_MAC_RESULT:-}" = success
          test "${BMP_UBUNTU_RESULT:-}" = success
          test "${BMP_MAC_RESULT:-}" = success
'''


def require(condition, message):
    if not condition:
        raise ValueError(message)


def structural_text(text):
    # Never remove indented shell/Python comments or lines inside a run block.
    return ''.join(line for line in text.splitlines(keepends=True)
                   if not re.match(r'^ {0,6}#', line))


def workflow_parts(text):
    text = structural_text(text)
    header, separator, jobs_text = text.partition('jobs:\n')
    require(bool(separator), 'Missing workflow jobs')
    matches = list(re.finditer(r'^  ([A-Za-z_][A-Za-z0-9_-]*):\n', jobs_text, re.MULTILINE))
    require(bool(matches) and matches[0].start() == 0, 'Invalid job boundary')
    jobs = {}
    for index, match in enumerate(matches):
        job_id = match.group(1)
        require(job_id not in jobs, 'Duplicate job: ' + job_id)
        end = matches[index + 1].start() if index + 1 < len(matches) else len(jobs_text)
        jobs[job_id] = jobs_text[match.end():end].rstrip('\n') + '\n'
    return header, jobs


def job_parts(job):
    pieces = re.split(r'(?m)^      - ', job)
    return pieces[0], ['      - ' + piece for piece in pieces[1:]]


def gate_name(step):
    return step.splitlines()[0].removeprefix('      - name: ')


def upload_parts(step):
    header, separator, payload = step.partition('          path: |\n')
    require(bool(separator), 'Missing scoped upload paths')
    paths = payload.splitlines()
    require(all(line.startswith('            ') for line in paths), 'Invalid upload path layout')
    return header + separator, [line.removeprefix('            ') for line in paths]


def validate_workflow(text):
    baseline_bytes = BASELINE.read_bytes()
    require(hashlib.sha256(baseline_bytes).hexdigest() == BASELINE_SHA256,
            'Reviewed baseline changed; requires explicit baseline review')
    old_header, old_jobs = workflow_parts(baseline_bytes.decode())
    header, jobs = workflow_parts(text)
    require(header == old_header, 'Workflow trigger, permission or concurrency changed')
    require(list(jobs) == [*WORKERS, 'conformanceUbuntu', 'conformanceMac'],
            'Worker/aggregate topology changed')
    old_settings, old_steps = job_parts(old_jobs['conformance'])
    setup, gates, upload = old_steps[:7], old_steps[7:-1], old_steps[-1]
    require(len(gates) == 79, 'Expected 79 reviewed gates')
    formatted = [step for step in gates if gate_name(step) in FORMATTED_GATES]
    core = [step for step in gates if gate_name(step) not in FORMATTED_GATES]
    require(tuple(map(gate_name, formatted)) == FORMATTED_GATES, 'Formatted ownership changed')
    require(len(core) == 72 and len(formatted) == 7, 'Original gate counts changed')
    reviewed_gates = gates + list(ADDED_FORMATTED_GATES) + list(BMP_GATES) + list(ADDED_BMP_FILE_GATES)
    formatted = formatted + list(ADDED_FORMATTED_GATES)
    require(len(reviewed_gates) == 83 and len(formatted) == 9
            and len(BMP_GATES) == len(ADDED_BMP_FILE_GATES) == 1,
            'Reviewed added gate count changed')
    upload_header, old_paths = upload_parts(upload)
    require(len(old_paths) == len(set(old_paths)) == 156, 'Expected 156 distinct baseline paths')
    paths_by_shard = {
        'core': [path for path in old_paths if path not in FORMATTED_PATHS],
        'formatted': list(FORMATTED_PATHS),
    }
    require(len(paths_by_shard['core']) == 140, 'Expected 140 core paths')
    require(Counter(paths_by_shard['core'] + paths_by_shard['formatted']) == Counter(old_paths),
            'Artifact partitions must be the disjoint baseline union')
    paths_by_shard['formatted'].extend(ADDED_FORMATTED_PATHS)
    paths_by_shard['bmp'] = list(BMP_PATHS) + list(ADDED_BMP_FILE_PATHS)
    reviewed_paths = old_paths + list(ADDED_FORMATTED_PATHS) + list(BMP_PATHS) + list(ADDED_BMP_FILE_PATHS)
    require(len(paths_by_shard['formatted']) == 22 and len(paths_by_shard['bmp']) == 6
            and len(reviewed_paths) == 168,
            'Reviewed added artifact count changed')
    for suffix, platform in PLATFORMS:
        actual_gates = []
        actual_paths = []
        for shard, name, expected_gates in (
            ('core', 'Core CPU and JavaScript', core),
            ('formatted', 'Formatted images CPU and JavaScript', formatted),
            ('bmp', 'BMP memory CPU and JavaScript', list(BMP_GATES) + list(ADDED_BMP_FILE_GATES)),
        ):
            job_id = shard + suffix
            settings, steps = job_parts(jobs[job_id])
            expected_settings = old_settings.replace(
                'name: CPU and JavaScript', 'name: ' + name).replace(
                '    strategy:\n      fail-fast: false\n      matrix:\n'
                '        os: [ubuntu-24.04, macos-15]\n', '').replace(
                '${{ matrix.os }}', platform)
            require(settings == expected_settings,
                    job_id + ': platform, environment, budget or job settings changed')
            require(steps[:7] == setup, job_id + ': independent pinned setup changed')
            require(steps[7:-1] == expected_gates, job_id + ': gate payload, count or order changed')
            actual_gates.extend(steps[7:-1])
            expected_upload = upload_header.replace(
                'name: conformance-${{ matrix.os }}\n',
                'name: conformance-' + platform + '-' + shard + '\n')
            expected_upload += ''.join('            ' + path + '\n' for path in paths_by_shard[shard])
            require(steps[-1] == expected_upload, job_id + ': upload settings, name or paths changed')
            actual_paths.extend(upload_parts(steps[-1])[1])
        require(Counter(actual_gates) == Counter(reviewed_gates), platform + ': gate payload multiset changed')
        require(Counter(actual_paths) == Counter(reviewed_paths), platform + ': artifact path multiset changed')
        require(jobs['conformance' + suffix] == AGGREGATE.replace('__PLATFORM__', platform),
                platform + ': fail-closed compatibility aggregate changed')



def remove_reviewed_bmp_file_additions(text):
    # Raw replacement only: preserve every other byte, including comments and
    # line endings. The separate anchor tests protect both predecessor stages.
    for gate in ADDED_BMP_FILE_GATES:
        require(text.count(gate) == 2, 'Expected one exact BMP-file gate per platform')
        text = text.replace(gate, '')
    for path in ADDED_BMP_FILE_PATHS:
        line = '            ' + path + '\n'
        require(text.count(line) == 2, 'Expected one exact BMP-file upload path per platform')
        text = text.replace(line, '')
    return text


class ConformanceWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.text = WORKFLOW.read_bytes().decode('utf-8')

    def test_exact_reviewed_gate_setup_settings_and_artifact_partition(self):
        validate_workflow(self.text)

    def test_removing_only_reviewed_bmp_file_additions_restores_exact_82_gate_bytes(self):
        stripped = remove_reviewed_bmp_file_additions(self.text)
        self.assertEqual(hashlib.sha256(stripped.encode('utf-8')).hexdigest(),
                         BMP_FILE_PREDECESSOR_SHA256)

    def test_raw_workflow_preservation_rejects_crlf(self):
        changed = self.text.replace('\n', '\r\n')
        with self.assertRaises(ValueError):
            validate_workflow(changed)
        with self.assertRaises(ValueError):
            remove_reviewed_bmp_file_additions(changed)

    def test_removing_only_reviewed_bmp_additions_restores_exact_predecessor_bytes(self):
        # Independent raw-text comparison: do not reuse the structural parser
        # or strip comments/whitespace from the four preserved workers.
        predecessor = remove_reviewed_bmp_file_additions(self.text)
        start = predecessor.index('  bmpUbuntu:\n')
        end = predecessor.index('  # Keep both prior required-check names', start)
        stripped = predecessor[:start] + predecessor[end:]
        additions = (
            ('directly require all six workers.', 'directly require all four workers.', 1),
            ('needs: [coreUbuntu, coreMac, formattedUbuntu, formattedMac, bmpUbuntu, bmpMac]',
             'needs: [coreUbuntu, coreMac, formattedUbuntu, formattedMac]', 2),
            ('          BMP_UBUNTU_RESULT: ${{ needs.bmpUbuntu.result }}\n', '', 2),
            ('          BMP_MAC_RESULT: ${{ needs.bmpMac.result }}\n', '', 2),
            ('          printf \'BMP Ubuntu: %s; BMP macOS: %s\\n\' "${BMP_UBUNTU_RESULT:-missing}" "${BMP_MAC_RESULT:-missing}"\n', '', 2),
            ('          test "${BMP_UBUNTU_RESULT:-}" = success\n', '', 2),
            ('          test "${BMP_MAC_RESULT:-}" = success\n', '', 2),
        )
        for addition, original, count in additions:
            self.assertEqual(stripped.count(addition), count)
            stripped = stripped.replace(addition, original)
        self.assertEqual(hashlib.sha256(stripped.encode()).hexdigest(), BMP_PREDECESSOR_SHA256)

    def test_guard_rejects_weakened_or_changed_workflows(self):
        # Exercise the guard itself so permissive extraction cannot make a
        # weakened workflow look like the reviewed contract.
        mutations = {
            'wrong platform': ('runs-on: macos-15', 'runs-on: ubuntu-24.04'),
            'matrix worker': ('  coreUbuntu:\n', '  coreUbuntu:\n    strategy:\n      matrix:\n        os: [ubuntu-24.04]\n'),
            'optional worker': ('  coreUbuntu:\n', '  coreUbuntu:\n    continue-on-error: true\n'),
            'skipped worker': ('  coreUbuntu:\n', '  coreUbuntu:\n    if: false\n'),
            'unbounded worker': ('timeout-minutes: 120', 'timeout-minutes: 180'),
            'lost gate': ('python3 tools/r32_raw_file_probe.py', 'true # removed gate'),
            'loader change': ('tools/pnm_file_probe.py --reference-env clean-loader', 'tools/pnm_file_probe.py'),
            'Linux guard': ("if: runner.os == 'Linux'", "if: false"),
            'legacy assertion': ("assert report['samples'] == 1086", "assert report['samples'] > 0"),
            'changed pin': ('actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1', 'actions/checkout@main'),
            'changed environment': ('CC: clang\n', 'CC: gcc\n'),
            'lost upload': ('.build/pnm-file-probe/run-*/*.resource.json\n', ''),
            'sparse upload': ('.build/pnm-file-probe/results.json', '.build/pnm-file-probe/**'),
            'artifact collision': ('name: conformance-ubuntu-24.04-formatted', 'name: conformance-ubuntu-24.04-core'),
            'lost dependency': ('needs: [coreUbuntu, coreMac, formattedUbuntu, formattedMac, bmpUbuntu, bmpMac]', 'needs: [coreUbuntu, formattedUbuntu]'),
            'matrix reduction': ('${{ needs.coreUbuntu.result }}', '${{ needs.core.result }}'),
            'wrong dependency result': ('${{ needs.formattedMac.result }}', '${{ needs.formattedUbuntu.result }}'),
            'skipped aggregate': ('if: ${{ always() }}', 'if: ${{ success() }}'),
            'renamed old check': ('    name: CPU and JavaScript', '    name: New compatibility check'),
            'extra job': ('  conformanceUbuntu:\n', '  ignored:\n    runs-on: ubuntu-24.04\n  conformanceUbuntu:\n'),
        }
        for variable in RESULT_VARIABLES:
            mutations['permissive ' + variable] = ('test "${' + variable + ':-}" = success', 'true')
        for label, (before, after) in mutations.items():
            with self.subTest(mutation=label):
                self.assertIn(before, self.text)
                with self.assertRaises(ValueError):
                    validate_workflow(self.text.replace(before, after, 1))
        _, jobs = workflow_parts(self.text)
        for job_id in WORKERS:
            with self.subTest(mutation='missing worker', job=job_id), self.assertRaises(ValueError):
                validate_workflow(structural_text(self.text).replace('  ' + job_id + ':\n' + jobs[job_id], '', 1))
            _, steps = job_parts(jobs[job_id])
            for label, replacement in (('duplicate gate', steps[7] * 2), ('omitted gate', ''),
                                       ('reordered gate', steps[8] + steps[7])):
                mutated_job = jobs[job_id].replace(steps[7], replacement, 1)
                with self.subTest(mutation=label, job=job_id), self.assertRaises(ValueError):
                    validate_workflow(structural_text(self.text).replace(jobs[job_id], mutated_job, 1))

    def test_reviewed_tga_addition_is_mandatory_exact_and_scoped_on_both_platforms(self):
        _, jobs = workflow_parts(self.text)
        gate = ADDED_FORMATTED_GATES[0]
        path = '            ' + ADDED_FORMATTED_PATHS[0] + '\n'
        for suffix, _ in PLATFORMS:
            job_id = 'formatted' + suffix
            job = jobs[job_id]
            _, steps = job_parts(job)
            self.assertEqual(len(steps[7:-1]), 9)
            self.assertEqual(steps[-3], gate)
            self.assertEqual(upload_parts(steps[-1])[1][-len(ADDED_FORMATTED_PATHS)], ADDED_FORMATTED_PATHS[0])
            mutations = {
                'missing TGA gate': job.replace(gate, '', 1),
                'duplicate TGA gate': job.replace(gate, gate * 2, 1),
                'altered TGA command': job.replace('tools/tga_format_probe.py', 'tools/tga_probe.py', 1),
                'missing TGA loader flag': job.replace('tools/tga_format_probe.py --reference-env clean-loader', 'tools/tga_format_probe.py', 1),
                'altered TGA loader flag': job.replace('tools/tga_format_probe.py --reference-env clean-loader', 'tools/tga_format_probe.py --reference-env inherited', 1),
                'optional TGA gate': job.replace(gate, gate.replace('        run:', '        continue-on-error: true\n        run:'), 1),
                'reordered TGA gate': job.replace(steps[-4] + gate, gate + steps[-4], 1),
                'missing TGA artifact': job.replace(path, '', 1),
                'altered TGA artifact': job.replace(path, '            .build/tga-format-probe/results.json\n', 1),
                'broader TGA artifact': job.replace(path, '            .build/\n', 1),
            }
            for label, mutated_job in mutations.items():
                with self.subTest(job=job_id, mutation=label):
                    self.assertNotEqual(job, mutated_job)
                    with self.assertRaises(ValueError):
                        validate_workflow(structural_text(self.text).replace(job, mutated_job, 1))

    def test_reviewed_tga_file_addition_is_mandatory_exact_and_scoped_on_both_platforms(self):
        _, jobs = workflow_parts(self.text)
        memory_gate, gate = ADDED_FORMATTED_GATES
        artifact = ADDED_FORMATTED_PATHS[1]
        path = '            ' + artifact + '\n'
        for suffix, _ in PLATFORMS:
            job_id = 'formatted' + suffix
            job = jobs[job_id]
            _, steps = job_parts(job)
            self.assertEqual(len(steps[7:-1]), 9)
            self.assertEqual(steps[-3:-1], [memory_gate, gate])
            self.assertEqual(upload_parts(steps[-1])[1][-5:], list(ADDED_FORMATTED_PATHS[1:]))
            mutations = {
                'missing TGA-file gate': job.replace(gate, '', 1),
                'duplicate TGA-file gate': job.replace(gate, gate * 2, 1),
                'altered TGA-file command': job.replace('tools/tga_file_probe.py', 'tools/tga_format_probe.py', 1),
                'missing TGA-file loader flag': job.replace('tools/tga_file_probe.py --reference-env clean-loader', 'tools/tga_file_probe.py', 1),
                'altered TGA-file loader flag': job.replace('tools/tga_file_probe.py --reference-env clean-loader', 'tools/tga_file_probe.py --reference-env inherited', 1),
                'optional TGA-file gate': job.replace(gate, gate.replace('        run:', '        continue-on-error: true\n        run:'), 1),
                'skipped TGA-file gate': job.replace(gate, gate.replace('        run:', '        if: false\n        run:'), 1),
                'bypassed TGA-file failure': job.replace(gate, gate.rstrip('\n') + ' || true\n', 1),
                'changed TGA-file Bend source': job.replace(gate, gate.replace('/.build/dependencies/bend', '/.build/dependencies/other-bend'), 1),
                'changed TGA-file raylib source': job.replace(gate, gate.replace('/.build/dependencies/raylib', '/.build/dependencies/other-raylib'), 1),
                'reordered TGA-file gate': job.replace(memory_gate + gate, gate + memory_gate, 1),
                'missing TGA-file artifact': job.replace(path, '', 1),
                'duplicate TGA-file artifact': job.replace(path, path * 2, 1),
                'altered TGA-file artifact': job.replace(path, '            .build/tga-file-probe/results.json\n', 1),
                'broader TGA-file artifact': job.replace(path, '            .build/\n', 1),
            }
            for label, mutated_job in mutations.items():
                with self.subTest(job=job_id, mutation=label):
                    self.assertNotEqual(job, mutated_job)
                    with self.assertRaises(ValueError):
                        validate_workflow(structural_text(self.text).replace(job, mutated_job, 1))

    def test_tga_file_upload_excludes_only_sparse_fixture_bodies_on_both_platforms(self):
        _, jobs = workflow_parts(self.text)
        excluded_paths = ADDED_FORMATTED_PATHS[2:]
        self.assertEqual(len(excluded_paths), 4)
        for suffix, _ in PLATFORMS:
            job_id = 'formatted' + suffix
            job = jobs[job_id]
            _, steps = job_parts(job)
            paths = upload_parts(steps[-1])[1]
            self.assertIn('.build/tga-file-probe/', paths)
            self.assertEqual([path for path in paths if path.startswith('!')],
                             list(excluded_paths))
            for excluded in excluded_paths:
                path = '            ' + excluded + '\n'
                mutations = {
                    'missing sparse exclusion': job.replace(path, '', 1),
                    'duplicate sparse exclusion': job.replace(path, path * 2, 1),
                    'included sparse body': job.replace(path, path.replace('!.build/', '.build/'), 1),
                    'excluded ordinary exact cap': job.replace(path, '            !.build/tga-file-probe/run-*/fixtures/exact-cap.tga\n', 1),
                    'excluded all fixtures': job.replace(path, '            !.build/tga-file-probe/run-*/fixtures/\n', 1),
                    'excluded fixture recipes': job.replace(path, '            !.build/tga-file-probe/run-*/inputs.json\n', 1),
                    'excluded command receipts': job.replace(path, '            !.build/tga-file-probe/run-*/*.command.json\n', 1),
                    'excluded resource receipts': job.replace(path, '            !.build/tga-file-probe/run-*/*.resource.json\n', 1),
                }
                for label, mutated_job in mutations.items():
                    with self.subTest(job=job_id, exclusion=excluded, mutation=label):
                        self.assertNotEqual(job, mutated_job)
                        with self.assertRaises(ValueError):
                            validate_workflow(structural_text(self.text).replace(job, mutated_job, 1))

    def test_bmp_workers_are_independent_mandatory_exact_and_scoped(self):
        _, jobs = workflow_parts(self.text)
        gate, = BMP_GATES
        path = '            ' + BMP_PATHS[0] + '\n'
        for suffix, platform in PLATFORMS:
            job_id = 'bmp' + suffix
            job = jobs[job_id]
            _, steps = job_parts(job)
            _, formatted_steps = job_parts(jobs['formatted' + suffix])
            self.assertEqual(steps[:7], formatted_steps[:7])
            self.assertEqual(steps[7:-1], [gate, *ADDED_BMP_FILE_GATES])
            self.assertEqual(upload_parts(steps[-1])[1], list(BMP_PATHS) + list(ADDED_BMP_FILE_PATHS))
            mutations = {
                'wrong BMP platform': job.replace('runs-on: ' + platform, 'runs-on: other'),
                'optional BMP worker': '    continue-on-error: true\n' + job,
                'skipped BMP worker': '    if: false\n' + job,
                'dependent BMP worker': '    needs: formatted' + suffix + '\n' + job,
                'BMP matrix': '    strategy:\n      matrix:\n        os: [' + platform + ']\n' + job,
                'changed BMP timeout': job.replace('timeout-minutes: 120', 'timeout-minutes: 180'),
                'changed BMP environment': job.replace('CC: clang', 'CC: gcc'),
                'changed BMP permissions': '    permissions: write-all\n' + job,
                'missing BMP setup': job.replace(steps[0], '', 1),
                'changed BMP setup pin': job.replace('actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1', 'actions/checkout@main', 1),
                'missing BMP gate': job.replace(gate, '', 1),
                'duplicate BMP gate': job.replace(gate, gate * 2, 1),
                'changed BMP command': job.replace('tools/bmp_format_probe.py', 'tools/bmp_probe.py', 1),
                'missing BMP loader flag': job.replace('--reference-env clean-loader', '', 1),
                'changed BMP loader flag': job.replace('--reference-env clean-loader', '--reference-env inherited', 1),
                'changed BMP Bend source': job.replace(gate, gate.replace('/.build/dependencies/bend', '/.build/dependencies/other-bend'), 1),
                'changed BMP raylib source': job.replace(gate, gate.replace('/.build/dependencies/raylib', '/.build/dependencies/other-raylib'), 1),
                'optional BMP gate': job.replace(gate, gate.replace('        run:', '        continue-on-error: true\n        run:'), 1),
                'skipped BMP gate': job.replace(gate, gate.replace('        run:', '        if: false\n        run:'), 1),
                'bypassed BMP failure': job.replace(gate, gate.rstrip('\n') + ' || true\n', 1),
                'BMP gate before setup': job.replace(steps[6] + gate, gate + steps[6], 1),
                'missing BMP artifact': job.replace(path, '', 1),
                'duplicate BMP artifact': job.replace(path, path * 2, 1),
                'incomplete BMP receipts': job.replace(path, '            .build/bmp-format-probe/results.json\n', 1),
                'broader BMP artifact': job.replace(path, '            .build/\n', 1),
                'excluded BMP receipts': job.replace(path, path + '            !.build/bmp-format-probe/run-*/*.resource.json\n', 1),
                'BMP artifact collision': job.replace('conformance-' + platform + '-bmp', 'conformance-' + platform + '-formatted', 1),
                'optional BMP upload': job.replace('if: always()', 'if: success()', 1),
                'changed BMP upload pin': job.replace('actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a', 'actions/upload-artifact@main', 1),
                'changed BMP retention': job.replace('retention-days: 14', 'retention-days: 1', 1),
            }
            for label, mutated_job in mutations.items():
                with self.subTest(job=job_id, mutation=label):
                    self.assertNotEqual(job, mutated_job)
                    with self.assertRaises(ValueError):
                        validate_workflow(structural_text(self.text).replace(job, mutated_job, 1))

    def test_reviewed_bmp_file_addition_is_mandatory_exact_and_scoped_on_both_platforms(self):
        _, jobs = workflow_parts(self.text)
        memory_gate, = BMP_GATES
        gate, = ADDED_BMP_FILE_GATES
        path = '            ' + ADDED_BMP_FILE_PATHS[0] + '\n'
        for suffix, _ in PLATFORMS:
            job_id = 'bmp' + suffix
            job = jobs[job_id]
            _, steps = job_parts(job)
            self.assertEqual(steps[7:-1], [memory_gate, gate])
            self.assertEqual(upload_parts(steps[-1])[1], list(BMP_PATHS) + list(ADDED_BMP_FILE_PATHS))
            mutations = {
                'missing BMP-file gate': job.replace(gate, '', 1),
                'duplicate BMP-file gate': job.replace(gate, gate * 2, 1),
                'altered BMP-file command': job.replace('tools/bmp_file_probe.py', 'tools/bmp_format_probe.py', 1),
                'missing BMP-file loader flag': job.replace('tools/bmp_file_probe.py --reference-env clean-loader', 'tools/bmp_file_probe.py', 1),
                'altered BMP-file loader flag': job.replace('tools/bmp_file_probe.py --reference-env clean-loader', 'tools/bmp_file_probe.py --reference-env inherited', 1),
                'optional BMP-file gate': job.replace(gate, gate.replace('        run:', '        continue-on-error: true\n        run:'), 1),
                'skipped BMP-file gate': job.replace(gate, gate.replace('        run:', '        if: false\n        run:'), 1),
                'bypassed BMP-file failure': job.replace(gate, gate.rstrip('\n') + ' || true\n', 1),
                'changed BMP-file Bend source': job.replace(gate, gate.replace('/.build/dependencies/bend', '/.build/dependencies/other-bend'), 1),
                'changed BMP-file raylib source': job.replace(gate, gate.replace('/.build/dependencies/raylib', '/.build/dependencies/other-raylib'), 1),
                'reordered BMP-file gate': job.replace(memory_gate + gate, gate + memory_gate, 1),
                'missing BMP-file artifact': job.replace(path, '', 1),
                'duplicate BMP-file artifact': job.replace(path, path * 2, 1),
                'altered BMP-file artifact': job.replace(path, '            .build/bmp-file-probe/results.json\n', 1),
                'broader BMP-file artifact': job.replace(path, '            .build/\n', 1),
            }
            for label, mutated_job in mutations.items():
                with self.subTest(job=job_id, mutation=label):
                    self.assertNotEqual(job, mutated_job)
                    with self.assertRaises(ValueError):
                        validate_workflow(structural_text(self.text).replace(job, mutated_job, 1))

    def test_bmp_file_upload_excludes_only_sparse_fixture_bodies_on_both_platforms(self):
        _, jobs = workflow_parts(self.text)
        excluded_paths = ADDED_BMP_FILE_PATHS[1:]
        self.assertEqual(len(excluded_paths), 4)
        root = '.build/bmp-file-probe/'
        retained = (
            'results.json', 'run-example/fixtures/exact-cap.bmp',
            'run-example/fixtures/c3-single.bmp', 'run-example/inputs.json',
            'run-example/qualification.c', 'run-example/reference.c',
            'run-example/candidate.bend', 'run-example/candidate.stdout',
            'run-example/candidate.stderr', 'run-example/candidate.command.json',
            'run-example/candidate.resource.json', 'run-example/native/libraylib.a',
        )
        for suffix, _ in PLATFORMS:
            job_id = 'bmp' + suffix
            job = jobs[job_id]
            _, steps = job_parts(job)
            paths = upload_parts(steps[-1])[1]
            self.assertEqual(len(paths), 6)
            self.assertIn(root, paths)
            self.assertEqual([path for path in paths if path.startswith('!')], list(excluded_paths))
            # Only exact sparse filenames are excluded. Positive ordinary-file
            # coverage guards against dropping cap, recipe or replay evidence.
            for relative in retained:
                candidate = root + relative
                self.assertFalse(any(fnmatch.fnmatchcase(candidate, excluded[1:])
                                     for excluded in excluded_paths), candidate)
            for excluded in excluded_paths:
                candidate = excluded[1:].replace('run-*', 'run-example')
                self.assertTrue(fnmatch.fnmatchcase(candidate, excluded[1:]))
                path = '            ' + excluded + '\n'
                mutations = {
                    'missing sparse exclusion': job.replace(path, '', 1),
                    'duplicate sparse exclusion': job.replace(path, path * 2, 1),
                    'included sparse body': job.replace(path, path.replace('!.build/', '.build/'), 1),
                    'excluded ordinary exact cap': job.replace(path, '            !.build/bmp-file-probe/run-*/fixtures/exact-cap.bmp\n', 1),
                    'excluded all fixtures': job.replace(path, '            !.build/bmp-file-probe/run-*/fixtures/\n', 1),
                    'excluded fixture recipes': job.replace(path, '            !.build/bmp-file-probe/run-*/inputs.json\n', 1),
                    'excluded command receipts': job.replace(path, '            !.build/bmp-file-probe/run-*/*.command.json\n', 1),
                    'excluded resource receipts': job.replace(path, '            !.build/bmp-file-probe/run-*/*.resource.json\n', 1),
                    'excluded all BMP bodies': job.replace(path, '            !.build/bmp-file-probe/run-*/fixtures/*.bmp\n', 1),
                }
                for label, mutated_job in mutations.items():
                    with self.subTest(job=job_id, exclusion=excluded, mutation=label):
                        self.assertNotEqual(job, mutated_job)
                        with self.assertRaises(ValueError):
                            validate_workflow(structural_text(self.text).replace(job, mutated_job, 1))

    def test_both_aggregates_require_each_of_six_direct_workers(self):
        _, jobs = workflow_parts(self.text)
        for suffix, _ in PLATFORMS:
            job = jobs['conformance' + suffix]
            for variable, worker in zip(RESULT_VARIABLES, WORKERS):
                dependencies = 'needs: [' + ', '.join(WORKERS) + ']'
                fewer = 'needs: [' + ', '.join(item for item in WORKERS if item != worker) + ']'
                result = '          ' + variable + ': ${{ needs.' + worker + '.result }}\n'
                test = '          test "${' + variable + ':-}" = success\n'
                mutations = {
                    'missing direct dependency': job.replace(dependencies, fewer, 1),
                    'missing result': job.replace(result, '', 1),
                    'wrong result': job.replace(result, result.replace('needs.' + worker, 'needs.otherWorker'), 1),
                    'assumed success': job.replace(result, '          ' + variable + ': success\n', 1),
                    'missing success test': job.replace(test, '', 1),
                    'bypassed success test': job.replace(test, test.rstrip('\n') + ' || true\n', 1),
                    'allowed empty result': job.replace(test, test.replace(':-}', ':-success}'), 1),
                }
                for label, mutated_job in mutations.items():
                    with self.subTest(aggregate=suffix, worker=worker, mutation=label):
                        self.assertNotEqual(job, mutated_job)
                        with self.assertRaises(ValueError):
                            validate_workflow(structural_text(self.text).replace(job, mutated_job, 1))

    def test_both_actual_aggregate_shells_fail_closed_for_all_four_results(self):
        _, jobs = workflow_parts(self.text)
        statuses = ('success', 'failure', 'cancelled', 'skipped', '', 'unknown', None)
        base_env = {key: value for key, value in os.environ.items()
                    if key not in (*RESULT_VARIABLES, 'BASH_ENV')}
        for suffix, _ in PLATFORMS:
            _, steps = job_parts(jobs['conformance' + suffix])
            prefix, separator, body = steps[0].partition('        run: |\n')
            self.assertTrue(separator)
            self.assertIn('shell: bash\n', prefix)
            for variable, worker in zip(RESULT_VARIABLES, WORKERS):
                self.assertIn(variable + ': ${{ needs.' + worker + '.result }}\n', prefix)
            self.assertTrue(all(line.startswith('          ') for line in body.splitlines()))
            script = '\n'.join(line[10:] for line in body.splitlines()) + '\n'
            # None is absent; empty and unknown are separate values. Testing
            # each direct worker result avoids matrix/partial-rerun reduction.
            for results in itertools.product(statuses, repeat=4):
                with self.subTest(aggregate=suffix, results=results):
                    env = dict(base_env)
                    env.update((variable, 'success') for variable in BMP_RESULT_VARIABLES)
                    env.update((variable, result) for variable, result in zip(ORIGINAL_RESULT_VARIABLES, results)
                               if result is not None)
                    result = subprocess.run(['bash', '--noprofile', '--norc', '-e', '-o',
                                             'pipefail', '-c', script], env=env,
                                            capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode == 0,
                                     all(value == 'success' for value in results),
                                     result.stdout + result.stderr)

    def test_both_actual_aggregate_shells_fail_closed_for_all_bmp_results(self):
        _, jobs = workflow_parts(self.text)
        statuses = ('success', 'failure', 'cancelled', 'skipped', '', 'unknown', None)
        base_env = {key: value for key, value in os.environ.items()
                    if key not in (*RESULT_VARIABLES, 'BASH_ENV')}
        base_env.update((variable, 'success') for variable in ORIGINAL_RESULT_VARIABLES)
        for suffix, _ in PLATFORMS:
            _, steps = job_parts(jobs['conformance' + suffix])
            _, separator, body = steps[0].partition('        run: |\n')
            self.assertTrue(separator)
            self.assertTrue(all(line.startswith('          ') for line in body.splitlines()))
            script = '\n'.join(line[10:] for line in body.splitlines()) + '\n'
            for results in itertools.product(statuses, repeat=2):
                with self.subTest(aggregate=suffix, results=results):
                    env = dict(base_env)
                    env.update((variable, result) for variable, result in zip(BMP_RESULT_VARIABLES, results)
                               if result is not None)
                    result = subprocess.run(['bash', '--noprofile', '--norc', '-e', '-o',
                                             'pipefail', '-c', script], env=env,
                                            capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode == 0,
                                     all(value == 'success' for value in results),
                                     result.stdout + result.stderr)

    def test_six_way_conjunction_structure_and_exhaustive_truth_table(self):
        # The actual scripts must consist only of set -eu, two literal printf
        # diagnostics and six straight-line test commands. Under errexit this
        # grammar is a conjunction: no conditional/function/OR can mask failure.
        # Extract the tested variables from the actual script, then exhaust all
        # 117,649 six-result assignments per aggregate in-process. The original
        # 4,802 shell cases and 98 new BMP-pair shell cases independently exercise
        # real Bash, including missing/empty values, without 235,298 processes.
        validate_workflow(self.text)
        _, jobs = workflow_parts(self.text)
        statuses = ('success', 'failure', 'cancelled', 'skipped', '', 'unknown', None)
        diagnostics = [
            'set -eu',
            'printf \'Core Ubuntu: %s; core macOS: %s; formatted Ubuntu: %s; formatted macOS: %s\\n\' "${CORE_UBUNTU_RESULT:-missing}" "${CORE_MAC_RESULT:-missing}" "${FORMATTED_UBUNTU_RESULT:-missing}" "${FORMATTED_MAC_RESULT:-missing}"',
            'printf \'BMP Ubuntu: %s; BMP macOS: %s\\n\' "${BMP_UBUNTU_RESULT:-missing}" "${BMP_MAC_RESULT:-missing}"',
        ]
        for suffix, _ in PLATFORMS:
            _, steps = job_parts(jobs['conformance' + suffix])
            _, separator, body = steps[0].partition('        run: |\n')
            self.assertTrue(separator)
            self.assertTrue(all(line.startswith('          ') for line in body.splitlines()))
            lines = [line[10:] for line in body.splitlines()]
            self.assertEqual(lines[:3], diagnostics)
            variables = []
            for line in lines[3:]:
                match = re.fullmatch(r'test "\$\{([A-Z_]+):-\}" = success', line)
                self.assertIsNotNone(match, 'Non-conjunctive aggregate command: ' + line)
                variables.append(match.group(1))
            self.assertEqual(tuple(variables), RESULT_VARIABLES)
            assignments = passing = 0
            for results in itertools.product(statuses, repeat=6):
                env = {variable: result for variable, result in zip(RESULT_VARIABLES, results)
                       if result is not None}
                actual = all(env.get(variable, '') == 'success' for variable in variables)
                expected = all(value == 'success' for value in results)
                self.assertEqual(actual, expected, (suffix, results))
                assignments += 1
                passing += actual
            self.assertEqual(assignments, 117649)
            self.assertEqual(passing, 1)


if __name__ == '__main__':
    unittest.main()
