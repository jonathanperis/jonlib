"""Byte-exact CI topology contract, with no third-party test dependencies.

The frozen, hash-checked workflow is the reviewed pre-split checkpoint. This is
deliberately not a YAML parser: only job/step boundaries are recognized, then
every remaining byte is compared. Unknown syntax, settings, steps, or jobs fail
closed. YAML layout comments outside scripts and job separators are immaterial;
run-block bytes, expressions, action pins, and all settings are not.
"""

from collections import Counter
import hashlib
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
''',)
ADDED_FORMATTED_PATHS = ('.build/tga-format-probe/',)
PLATFORMS = (('Ubuntu', 'ubuntu-24.04'), ('Mac', 'macos-15'))
WORKERS = ('coreUbuntu', 'coreMac', 'formattedUbuntu', 'formattedMac')
RESULT_VARIABLES = ('CORE_UBUNTU_RESULT', 'CORE_MAC_RESULT',
                    'FORMATTED_UBUNTU_RESULT', 'FORMATTED_MAC_RESULT')
AGGREGATE = '''    name: CPU and JavaScript (__PLATFORM__)
    if: ${{ always() }}
    needs: [coreUbuntu, coreMac, formattedUbuntu, formattedMac]
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
        run: |
          set -eu
          printf 'Core Ubuntu: %s; core macOS: %s; formatted Ubuntu: %s; formatted macOS: %s\\n' "${CORE_UBUNTU_RESULT:-missing}" "${CORE_MAC_RESULT:-missing}" "${FORMATTED_UBUNTU_RESULT:-missing}" "${FORMATTED_MAC_RESULT:-missing}"
          test "${CORE_UBUNTU_RESULT:-}" = success
          test "${CORE_MAC_RESULT:-}" = success
          test "${FORMATTED_UBUNTU_RESULT:-}" = success
          test "${FORMATTED_MAC_RESULT:-}" = success
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
    reviewed_gates = gates + list(ADDED_FORMATTED_GATES)
    formatted = formatted + list(ADDED_FORMATTED_GATES)
    require(len(reviewed_gates) == 80 and len(formatted) == 8, 'Reviewed added gate count changed')
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
    reviewed_paths = old_paths + list(ADDED_FORMATTED_PATHS)
    require(len(paths_by_shard['formatted']) == 17 and len(reviewed_paths) == 157,
            'Reviewed added artifact count changed')
    for suffix, platform in PLATFORMS:
        actual_gates = []
        actual_paths = []
        for shard, name, expected_gates in (
            ('core', 'Core CPU and JavaScript', core),
            ('formatted', 'Formatted images CPU and JavaScript', formatted),
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



class ConformanceWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.text = WORKFLOW.read_text()

    def test_exact_reviewed_gate_setup_settings_and_artifact_partition(self):
        validate_workflow(self.text)

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
            'lost dependency': ('needs: [coreUbuntu, coreMac, formattedUbuntu, formattedMac]', 'needs: [coreUbuntu, formattedUbuntu]'),
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
            self.assertEqual(len(steps[7:-1]), 8)
            self.assertEqual(steps[-2], gate)
            self.assertEqual(upload_parts(steps[-1])[1][-1], ADDED_FORMATTED_PATHS[0])
            mutations = {
                'missing TGA gate': job.replace(gate, '', 1),
                'duplicate TGA gate': job.replace(gate, gate * 2, 1),
                'altered TGA command': job.replace('tools/tga_format_probe.py', 'tools/tga_probe.py', 1),
                'missing TGA loader flag': job.replace('tools/tga_format_probe.py --reference-env clean-loader', 'tools/tga_format_probe.py', 1),
                'altered TGA loader flag': job.replace('tools/tga_format_probe.py --reference-env clean-loader', 'tools/tga_format_probe.py --reference-env inherited', 1),
                'optional TGA gate': job.replace(gate, gate.replace('        run:', '        continue-on-error: true\n        run:'), 1),
                'reordered TGA gate': job.replace(steps[-3] + gate, gate + steps[-3], 1),
                'missing TGA artifact': job.replace(path, '', 1),
                'altered TGA artifact': job.replace(path, '            .build/tga-format-probe/results.json\n', 1),
                'broader TGA artifact': job.replace(path, '            .build/\n', 1),
            }
            for label, mutated_job in mutations.items():
                with self.subTest(job=job_id, mutation=label):
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
                    env.update((variable, result) for variable, result in zip(RESULT_VARIABLES, results)
                               if result is not None)
                    result = subprocess.run(['bash', '--noprofile', '--norc', '-e', '-o',
                                             'pipefail', '-c', script], env=env,
                                            capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode == 0,
                                     all(value == 'success' for value in results),
                                     result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
