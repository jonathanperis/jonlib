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
# Exact 83-gate workflow at 1312479cf9cd8ae1acc35b17cd99d0a2be5366a8.
PNG_PREDECESSOR_SHA256 = '056713e25bab0092e22a4bfb1d68b687c821dbe77b8174b2932b7db7208c082b'
# Exact 84-gate workflow at 7dcfdb98a51af5dc0aa28f3affb060f185762a52.
TGA_SPLIT_PREDECESSOR_SHA256 = 'bf6f62710566b8c186548330d18437079349e00283f6ffc3842c63bd6de98b09'
# Exact ten-worker 84-gate workflow at 9cb5a7e7cabdb76005a76119616e33ca9516d73b.
PNG_FILE_PREDECESSOR_SHA256 = '8bfab667d418967d2427f41079411c1ef8d2e6698068127cde4cd4a950eb6b91'
# Exact twelve-worker 85-gate workflow at e6ac05e6d1daf64d050e6da3f783ed60cc3130e1.
PIC_PREDECESSOR_SHA256 = '3b5f0be5c6ee604316f3e9015f72d4316b9792c3949bff91698053617cc7268e'
# Exact twelve-worker 86-gate workflow at e481d3c257c6add2b9f756a583c648fcc5c92b7d.
PIC_FILE_PREDECESSOR_SHA256 = '60a3a85fce8531c38690eb2ccce7cf16157eeddce04e324778f4f58351935d7b'
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
PNG_GATES = ('''      - name: Verify native PNG formats and exact memory bytes
        run: >-
          python3 tools/png_format_probe.py --reference-env clean-loader
          --bend-source "${{ github.workspace }}/.build/dependencies/bend"
          --raylib-source "${{ github.workspace }}/.build/dependencies/raylib"
''',)
PNG_PATHS = ('.build/png-format-probe/',)
PNG_FILE_GATES = ('''      - name: Verify format-preserving PNG file loading and bounded closure
        run: >-
          python3 tools/png_file_probe.py --reference-env clean-loader
          --bend-source "${{ github.workspace }}/.build/dependencies/bend"
          --raylib-source "${{ github.workspace }}/.build/dependencies/raylib"
''',)
PNG_FILE_PATHS = (
    '.build/png-file-probe/',
    '!.build/png-file-probe/run-*/fixtures/cap-plus-one.png',
    '!.build/png-file-probe/run-*/fixtures/cap-plus-one.qoi',
    '!.build/png-file-probe/run-*/fixtures/larger-file.png',
    '!.build/png-file-probe/run-*/fixtures/host-size-overflow.png',
)
PIC_GATES = ('''      - name: Verify native PIC formats and exact memory bytes
        run: >-
          python3 tools/pic_format_probe.py --reference-env clean-loader
          --bend-source "${{ github.workspace }}/.build/dependencies/bend"
          --raylib-source "${{ github.workspace }}/.build/dependencies/raylib"
''',)
PIC_PATHS = ('.build/pic-format-probe/',)
PIC_FILE_GATES = ('''      - name: Verify format-preserving PIC file loading and bounded closure
        run: |
          python3 tools/pic_file_probe.py --reference-env clean-loader \\
            --bend-source "${{ github.workspace }}/.build/dependencies/bend" \\
            --raylib-source "${{ github.workspace }}/.build/dependencies/raylib"
          python3 tools/pic_file_audit.py .build/pic-file-probe/results.json
''',)
PIC_FILE_PATHS = (
    '.build/pic-file-probe/',
    '!.build/pic-file-probe/run-*/fixtures/cap-plus-one.pic',
    '!.build/pic-file-probe/run-*/fixtures/cap-plus-one.qoi',
    '!.build/pic-file-probe/run-*/fixtures/larger-file.pic',
    '!.build/pic-file-probe/run-*/fixtures/host-size-overflow.pic',
)
PLATFORMS = (('Ubuntu', 'ubuntu-24.04'), ('Mac', 'macos-15'))
ORIGINAL_WORKERS = ('coreUbuntu', 'coreMac', 'formattedUbuntu', 'formattedMac')
BMP_WORKERS = ('bmpUbuntu', 'bmpMac')
PRE_PNG_WORKERS = (*ORIGINAL_WORKERS, *BMP_WORKERS)
PNG_WORKERS = ('pngUbuntu', 'pngMac')
PRE_TGA_WORKERS = (*PRE_PNG_WORKERS, *PNG_WORKERS)
TGA_WORKERS = ('tgaUbuntu', 'tgaMac')
PRE_PNG_FILE_WORKERS = (*PRE_TGA_WORKERS, *TGA_WORKERS)
PNG_FILE_WORKERS = ('pngFileUbuntu', 'pngFileMac')
PRE_PIC_FILE_WORKERS = (*PRE_PNG_FILE_WORKERS, *PNG_FILE_WORKERS)
PIC_FILE_WORKERS = ('picFileUbuntu', 'picFileMac')
WORKERS = (*PRE_PIC_FILE_WORKERS, *PIC_FILE_WORKERS)
ORIGINAL_RESULT_VARIABLES = ('CORE_UBUNTU_RESULT', 'CORE_MAC_RESULT',
                             'FORMATTED_UBUNTU_RESULT', 'FORMATTED_MAC_RESULT')
BMP_RESULT_VARIABLES = ('BMP_UBUNTU_RESULT', 'BMP_MAC_RESULT')
PRE_PNG_RESULT_VARIABLES = (*ORIGINAL_RESULT_VARIABLES, *BMP_RESULT_VARIABLES)
PNG_RESULT_VARIABLES = ('PNG_UBUNTU_RESULT', 'PNG_MAC_RESULT')
PRE_TGA_RESULT_VARIABLES = (*PRE_PNG_RESULT_VARIABLES, *PNG_RESULT_VARIABLES)
TGA_RESULT_VARIABLES = ('TGA_UBUNTU_RESULT', 'TGA_MAC_RESULT')
PRE_PNG_FILE_RESULT_VARIABLES = (*PRE_TGA_RESULT_VARIABLES, *TGA_RESULT_VARIABLES)
PNG_FILE_RESULT_VARIABLES = ('PNG_FILE_UBUNTU_RESULT', 'PNG_FILE_MAC_RESULT')
PRE_PIC_FILE_RESULT_VARIABLES = (*PRE_PNG_FILE_RESULT_VARIABLES, *PNG_FILE_RESULT_VARIABLES)
PIC_FILE_RESULT_VARIABLES = ('PIC_FILE_UBUNTU_RESULT', 'PIC_FILE_MAC_RESULT')
RESULT_VARIABLES = (*PRE_PIC_FILE_RESULT_VARIABLES, *PIC_FILE_RESULT_VARIABLES)
AGGREGATE = '''    name: CPU and JavaScript (__PLATFORM__)
    if: ${{ always() }}
    needs: [coreUbuntu, coreMac, formattedUbuntu, formattedMac, bmpUbuntu, bmpMac, pngUbuntu, pngMac, tgaUbuntu, tgaMac, pngFileUbuntu, pngFileMac, picFileUbuntu, picFileMac]
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
          PNG_UBUNTU_RESULT: ${{ needs.pngUbuntu.result }}
          PNG_MAC_RESULT: ${{ needs.pngMac.result }}
          TGA_UBUNTU_RESULT: ${{ needs.tgaUbuntu.result }}
          TGA_MAC_RESULT: ${{ needs.tgaMac.result }}
          PNG_FILE_UBUNTU_RESULT: ${{ needs.pngFileUbuntu.result }}
          PNG_FILE_MAC_RESULT: ${{ needs.pngFileMac.result }}
          PIC_FILE_UBUNTU_RESULT: ${{ needs.picFileUbuntu.result }}
          PIC_FILE_MAC_RESULT: ${{ needs.picFileMac.result }}
        run: |
          set -eu
          printf 'Core Ubuntu: %s; core macOS: %s; formatted Ubuntu: %s; formatted macOS: %s\\n' "${CORE_UBUNTU_RESULT:-missing}" "${CORE_MAC_RESULT:-missing}" "${FORMATTED_UBUNTU_RESULT:-missing}" "${FORMATTED_MAC_RESULT:-missing}"
          printf 'BMP Ubuntu: %s; BMP macOS: %s\\n' "${BMP_UBUNTU_RESULT:-missing}" "${BMP_MAC_RESULT:-missing}"
          printf 'PNG Ubuntu: %s; PNG macOS: %s\\n' "${PNG_UBUNTU_RESULT:-missing}" "${PNG_MAC_RESULT:-missing}"
          printf 'TGA Ubuntu: %s; TGA macOS: %s\\n' "${TGA_UBUNTU_RESULT:-missing}" "${TGA_MAC_RESULT:-missing}"
          printf 'PNG files Ubuntu: %s; PNG files macOS: %s\\n' "${PNG_FILE_UBUNTU_RESULT:-missing}" "${PNG_FILE_MAC_RESULT:-missing}"
          printf 'PIC files Ubuntu: %s; PIC files macOS: %s\\n' "${PIC_FILE_UBUNTU_RESULT:-missing}" "${PIC_FILE_MAC_RESULT:-missing}"
          test "${CORE_UBUNTU_RESULT:-}" = success
          test "${CORE_MAC_RESULT:-}" = success
          test "${FORMATTED_UBUNTU_RESULT:-}" = success
          test "${FORMATTED_MAC_RESULT:-}" = success
          test "${BMP_UBUNTU_RESULT:-}" = success
          test "${BMP_MAC_RESULT:-}" = success
          test "${PNG_UBUNTU_RESULT:-}" = success
          test "${PNG_MAC_RESULT:-}" = success
          test "${TGA_UBUNTU_RESULT:-}" = success
          test "${TGA_MAC_RESULT:-}" = success
          test "${PNG_FILE_UBUNTU_RESULT:-}" = success
          test "${PNG_FILE_MAC_RESULT:-}" = success
          test "${PIC_FILE_UBUNTU_RESULT:-}" = success
          test "${PIC_FILE_MAC_RESULT:-}" = success
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
    reviewed_gates = gates + list(ADDED_FORMATTED_GATES) + list(BMP_GATES) + list(ADDED_BMP_FILE_GATES) + list(PNG_GATES) + list(PNG_FILE_GATES) + list(PIC_GATES) + list(PIC_FILE_GATES)
    require(len(reviewed_gates) == 87 and len(formatted) == 7
            and len(ADDED_FORMATTED_GATES) == 2
            and len(BMP_GATES) == len(ADDED_BMP_FILE_GATES) == len(PNG_GATES) == len(PNG_FILE_GATES) == len(PIC_GATES) == len(PIC_FILE_GATES) == 1,
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
    paths_by_shard['formatted'] += list(PIC_PATHS)
    paths_by_shard['tga'] = list(ADDED_FORMATTED_PATHS)
    paths_by_shard['bmp'] = list(BMP_PATHS) + list(ADDED_BMP_FILE_PATHS)
    paths_by_shard['png'] = list(PNG_PATHS)
    paths_by_shard['pngFile'] = list(PNG_FILE_PATHS)
    paths_by_shard['picFile'] = list(PIC_FILE_PATHS)
    reviewed_paths = old_paths + list(ADDED_FORMATTED_PATHS) + list(BMP_PATHS) + list(ADDED_BMP_FILE_PATHS) + list(PNG_PATHS) + list(PNG_FILE_PATHS) + list(PIC_PATHS) + list(PIC_FILE_PATHS)
    require(len(paths_by_shard['formatted']) == 17 and len(paths_by_shard['tga']) == 6 and len(paths_by_shard['bmp']) == 6
            and len(paths_by_shard['png']) == 1 and len(paths_by_shard['pngFile']) == 5
            and len(PIC_PATHS) == 1 and len(paths_by_shard['picFile']) == 5
            and len(reviewed_paths) == 180,
            'Reviewed added artifact count changed')
    for suffix, platform in PLATFORMS:
        actual_gates = []
        actual_paths = []
        for shard, name, expected_gates in (
            ('core', 'Core CPU and JavaScript', core),
            ('formatted', 'Formatted images CPU and JavaScript', formatted + list(PIC_GATES)),
            ('bmp', 'BMP memory CPU and JavaScript', list(BMP_GATES) + list(ADDED_BMP_FILE_GATES)),
            ('png', 'PNG memory CPU and JavaScript', list(PNG_GATES)),
            ('tga', 'TGA memory and files CPU and JavaScript', list(ADDED_FORMATTED_GATES)),
            ('pngFile', 'PNG files CPU and JavaScript', list(PNG_FILE_GATES)),
            ('picFile', 'PIC files CPU and JavaScript', list(PIC_FILE_GATES)),
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
                'name: conformance-' + platform + '-' + ({'pngFile': 'png-files', 'picFile': 'pic-files'}.get(shard, shard)) + '\n')
            expected_upload += ''.join('            ' + path + '\n' for path in paths_by_shard[shard])
            require(steps[-1] == expected_upload, job_id + ': upload settings, name or paths changed')
            actual_paths.extend(upload_parts(steps[-1])[1])
        require(Counter(actual_gates) == Counter(reviewed_gates), platform + ': gate payload multiset changed')
        require(Counter(actual_paths) == Counter(reviewed_paths), platform + ': artifact path multiset changed')
        require(jobs['conformance' + suffix] == AGGREGATE.replace('__PLATFORM__', platform),
                platform + ': fail-closed compatibility aggregate changed')



def aggregate_conjunction_variables(job):
    # A closed grammar: no branches, functions, OR lists, substitutions,
    # redirects, extra statements or changed errexit options are permitted.
    _, steps = job_parts(job)
    require(len(steps) == 1, 'Aggregate must contain exactly one shell step')
    prefix, separator, body = steps[0].partition('        run: |\n')
    require(bool(separator) and '        shell: bash\n' in prefix, 'Aggregate must use Bash')
    require(all(line.startswith('          ') for line in body.splitlines()), 'Shell indentation changed')
    lines = [line[10:] for line in body.splitlines()]
    diagnostics = [
        'set -eu',
        'printf \'Core Ubuntu: %s; core macOS: %s; formatted Ubuntu: %s; formatted macOS: %s\\n\' "${CORE_UBUNTU_RESULT:-missing}" "${CORE_MAC_RESULT:-missing}" "${FORMATTED_UBUNTU_RESULT:-missing}" "${FORMATTED_MAC_RESULT:-missing}"',
        'printf \'BMP Ubuntu: %s; BMP macOS: %s\\n\' "${BMP_UBUNTU_RESULT:-missing}" "${BMP_MAC_RESULT:-missing}"',
        'printf \'PNG Ubuntu: %s; PNG macOS: %s\\n\' "${PNG_UBUNTU_RESULT:-missing}" "${PNG_MAC_RESULT:-missing}"',
        'printf \'TGA Ubuntu: %s; TGA macOS: %s\\n\' "${TGA_UBUNTU_RESULT:-missing}" "${TGA_MAC_RESULT:-missing}"',
        'printf \'PNG files Ubuntu: %s; PNG files macOS: %s\\n\' "${PNG_FILE_UBUNTU_RESULT:-missing}" "${PNG_FILE_MAC_RESULT:-missing}"',
        'printf \'PIC files Ubuntu: %s; PIC files macOS: %s\\n\' "${PIC_FILE_UBUNTU_RESULT:-missing}" "${PIC_FILE_MAC_RESULT:-missing}"',
    ]
    require(lines[:7] == diagnostics, 'Aggregate preamble/diagnostics changed')
    variables = []
    for line in lines[7:]:
        match = re.fullmatch(r'test "\$\{([A-Z_]+):-\}" = success', line)
        require(match is not None, 'Non-conjunctive aggregate command: ' + line)
        variables.append(match.group(1))
    require(tuple(variables) == RESULT_VARIABLES, 'All fourteen exact success tests are required')
    return tuple(variables)


def restore_reviewed_tga_split(text):
    # Independent raw inverse: extract the moved payloads from each new job,
    # reinsert those exact bytes at their old positions, then remove only the
    # two new jobs and reviewed aggregate extensions. Never normalize YAML.
    for suffix, _ in PLATFORMS:
        start = text.index('  tga' + suffix + ':\n')
        next_job = '  tgaMac:\n' if suffix == 'Ubuntu' else '  # Keep both prior required-check names'
        end = text.index(next_job, start)
        job = text[start:end]
        gate_start = job.index(ADDED_FORMATTED_GATES[0].splitlines()[0] + '\n')
        gate_end = job.index('      - name: Upload scoped conformance evidence\n', gate_start)
        gates = job[gate_start:gate_end]
        require(gates == ''.join(ADDED_FORMATTED_GATES), 'Moved TGA gate payload changed')
        paths = job.split('          path: |\n', 1)[1].removesuffix('\n')
        require(paths == ''.join('            ' + path + '\n' for path in ADDED_FORMATTED_PATHS),
                'Moved TGA upload payload changed')
        text = text[:start] + text[end:]
        start = text.index('  formatted' + suffix + ':\n')
        next_job = '  formattedMac:\n' if suffix == 'Ubuntu' else '  bmpUbuntu:\n'
        end = text.index(next_job, start)
        original = text[start:end]
        upload_at = original.index('      - name: Upload scoped conformance evidence\n')
        restored = original[:upload_at] + gates + original[upload_at:]
        anchor = '            ' + FORMATTED_PATHS[-1] + '\n'
        require(restored.count(anchor) == 1, 'Original formatted upload position changed')
        restored = restored.replace(anchor, anchor + paths, 1)
        text = text[:start] + restored + text[end:]
    additions = (
        ('directly require all ten workers.', 'directly require all eight workers.', 1),
        ('needs: [coreUbuntu, coreMac, formattedUbuntu, formattedMac, bmpUbuntu, bmpMac, pngUbuntu, pngMac, tgaUbuntu, tgaMac]',
         'needs: [coreUbuntu, coreMac, formattedUbuntu, formattedMac, bmpUbuntu, bmpMac, pngUbuntu, pngMac]', 2),
        ('          TGA_UBUNTU_RESULT: ${{ needs.tgaUbuntu.result }}\n', '', 2),
        ('          TGA_MAC_RESULT: ${{ needs.tgaMac.result }}\n', '', 2),
        ('          printf \'TGA Ubuntu: %s; TGA macOS: %s\\n\' "${TGA_UBUNTU_RESULT:-missing}" "${TGA_MAC_RESULT:-missing}"\n', '', 2),
        ('          test "${TGA_UBUNTU_RESULT:-}" = success\n', '', 2),
        ('          test "${TGA_MAC_RESULT:-}" = success\n', '', 2),
    )
    for addition, original, count in additions:
        require(text.count(addition) == count, 'Unexpected TGA aggregate extension count')
        text = text.replace(addition, original)
    return text


def remove_reviewed_png_additions(text):
    # Do not parse or normalize the preserved six workers. Remove only the new
    # raw job blocks and the explicitly reviewed aggregate additions first.
    start = text.index('  pngUbuntu:\n')
    end = text.index('  # Keep both prior required-check names', start)
    text = text[:start] + text[end:]
    additions = (
        ('directly require all eight workers.', 'directly require all six workers.', 1),
        ('needs: [coreUbuntu, coreMac, formattedUbuntu, formattedMac, bmpUbuntu, bmpMac, pngUbuntu, pngMac]',
         'needs: [coreUbuntu, coreMac, formattedUbuntu, formattedMac, bmpUbuntu, bmpMac]', 2),
        ('          PNG_UBUNTU_RESULT: ${{ needs.pngUbuntu.result }}\n', '', 2),
        ('          PNG_MAC_RESULT: ${{ needs.pngMac.result }}\n', '', 2),
        ('          printf \'PNG Ubuntu: %s; PNG macOS: %s\\n\' "${PNG_UBUNTU_RESULT:-missing}" "${PNG_MAC_RESULT:-missing}"\n', '', 2),
        ('          test "${PNG_UBUNTU_RESULT:-}" = success\n', '', 2),
        ('          test "${PNG_MAC_RESULT:-}" = success\n', '', 2),
    )
    for addition, original, count in additions:
        require(text.count(addition) == count, 'Unexpected PNG aggregate extension count')
        text = text.replace(addition, original)
    return text


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


def remove_reviewed_png_file_additions(text):
    # Independent raw inverse; do not normalize any of the ten old worker jobs.
    start = text.index('  pngFileUbuntu:\n')
    end = text.index('  # Keep both prior required-check names', start)
    text = text[:start] + text[end:]
    additions = (
        ('directly require all twelve workers.', 'directly require all ten workers.', 1),
        ('needs: [coreUbuntu, coreMac, formattedUbuntu, formattedMac, bmpUbuntu, bmpMac, pngUbuntu, pngMac, tgaUbuntu, tgaMac, pngFileUbuntu, pngFileMac]',
         'needs: [coreUbuntu, coreMac, formattedUbuntu, formattedMac, bmpUbuntu, bmpMac, pngUbuntu, pngMac, tgaUbuntu, tgaMac]', 2),
        ('          PNG_FILE_UBUNTU_RESULT: ${{ needs.pngFileUbuntu.result }}\n', '', 2),
        ('          PNG_FILE_MAC_RESULT: ${{ needs.pngFileMac.result }}\n', '', 2),
        ('          printf \'PNG files Ubuntu: %s; PNG files macOS: %s\\n\' "${PNG_FILE_UBUNTU_RESULT:-missing}" "${PNG_FILE_MAC_RESULT:-missing}"\n', '', 2),
        ('          test "${PNG_FILE_UBUNTU_RESULT:-}" = success\n', '', 2),
        ('          test "${PNG_FILE_MAC_RESULT:-}" = success\n', '', 2),
    )
    for addition, original, count in additions:
        require(text.count(addition) == count, 'Unexpected PNG-file aggregate extension count')
        text = text.replace(addition, original)
    return text


def remove_reviewed_pic_file_additions(text):
    # Delete exactly the two added jobs and explicit aggregate extensions.
    # The predecessor SHA checks every untouched byte, including comments.
    start = text.index('  picFileUbuntu:\n')
    end = text.index('  # Keep both prior required-check names', start)
    text = text[:start] + text[end:]
    additions = (
        ('directly require all fourteen workers.', 'directly require all twelve workers.', 1),
        ('needs: [coreUbuntu, coreMac, formattedUbuntu, formattedMac, bmpUbuntu, bmpMac, pngUbuntu, pngMac, tgaUbuntu, tgaMac, pngFileUbuntu, pngFileMac, picFileUbuntu, picFileMac]', 'needs: [coreUbuntu, coreMac, formattedUbuntu, formattedMac, bmpUbuntu, bmpMac, pngUbuntu, pngMac, tgaUbuntu, tgaMac, pngFileUbuntu, pngFileMac]', 2),
        ('          PIC_FILE_UBUNTU_RESULT: ${{ needs.picFileUbuntu.result }}\n          PIC_FILE_MAC_RESULT: ${{ needs.picFileMac.result }}\n', '', 2),
        ('          printf \'PIC files Ubuntu: %s; PIC files macOS: %s\\n\' "${PIC_FILE_UBUNTU_RESULT:-missing}" "${PIC_FILE_MAC_RESULT:-missing}"\n', '', 2),
        ('          test "${PIC_FILE_UBUNTU_RESULT:-}" = success\n          test "${PIC_FILE_MAC_RESULT:-}" = success\n', '', 2),
    )
    for addition, original, count in additions:
        require(text.count(addition) == count, 'Unexpected PIC-file aggregate extension count')
        text = text.replace(addition, original)
    return text


def remove_reviewed_pic_additions(text):
    text = remove_reviewed_pic_file_additions(text)
    # Independent raw inverse: remove only the two exact new gate payloads and
    # one exact upload line per OS. Preserve every other byte and line ending.
    for gate in PIC_GATES:
        require(text.count(gate) == 2, 'Expected one exact PIC gate per platform')
        text = text.replace(gate, '')
    for path in PIC_PATHS:
        line = '            ' + path + '\n'
        require(text.count(line) == 2, 'Expected one exact PIC upload path per platform')
        text = text.replace(line, '')
    return text


class ConformanceWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.text = WORKFLOW.read_bytes().decode('utf-8')

    def test_exact_reviewed_gate_setup_settings_and_artifact_partition(self):
        validate_workflow(self.text)

    def test_removing_only_reviewed_pic_additions_restores_exact_85_gate_bytes(self):
        stripped = remove_reviewed_pic_additions(self.text)
        self.assertEqual(hashlib.sha256(stripped.encode('utf-8')).hexdigest(),
                         PIC_PREDECESSOR_SHA256)

    def test_reviewed_pic_addition_is_mandatory_exact_and_scoped_on_both_platforms(self):
        _, jobs = workflow_parts(self.text)
        gate = PIC_GATES[0]
        path = '            ' + PIC_PATHS[0] + '\n'
        for suffix, _ in PLATFORMS:
            job_id = 'formatted' + suffix
            job = jobs[job_id]
            _, steps = job_parts(job)
            self.assertEqual(len(steps[7:-1]), 8)
            self.assertEqual(tuple(map(gate_name, steps[7:-2])), FORMATTED_GATES)
            self.assertEqual(steps[-2], gate)
            self.assertEqual(upload_parts(steps[-1])[1], list(FORMATTED_PATHS) + list(PIC_PATHS))
            mutations = {
                'missing PIC gate': job.replace(gate, '', 1),
                'duplicate PIC gate': job.replace(gate, gate * 2, 1),
                'altered PIC command': job.replace('tools/pic_format_probe.py', 'tools/pic_probe.py', 1),
                'missing PIC loader flag': job.replace('tools/pic_format_probe.py --reference-env clean-loader', 'tools/pic_format_probe.py', 1),
                'altered PIC loader flag': job.replace('tools/pic_format_probe.py --reference-env clean-loader', 'tools/pic_format_probe.py --reference-env inherited', 1),
                'optional PIC gate': job.replace(gate, gate.replace('        run:', '        continue-on-error: true\n        run:'), 1),
                'skipped PIC gate': job.replace(gate, gate.replace('        run:', '        if: false\n        run:'), 1),
                'bypassed PIC failure': job.replace(gate, gate.rstrip('\n') + ' || true\n', 1),
                'changed PIC Bend source': job.replace(gate, gate.replace('/.build/dependencies/bend', '/.build/dependencies/other-bend'), 1),
                'changed PIC raylib source': job.replace(gate, gate.replace('/.build/dependencies/raylib', '/.build/dependencies/other-raylib'), 1),
                'reordered PIC gate': job.replace(steps[-3] + gate, gate + steps[-3], 1),
                'PIC before original seven gates': job.replace(gate, '', 1).replace(steps[7], gate + steps[7], 1),
                'missing PIC artifact': job.replace(path, '', 1),
                'duplicate PIC artifact': job.replace(path, path * 2, 1),
                'altered PIC artifact': job.replace(path, '            .build/pic-format-probe/results.json\n', 1),
                'stale PIC artifact': job.replace(path, '            .build/pic-probe/\n', 1),
                'broader PIC artifact': job.replace(path, '            .build/\n', 1),
                'reordered PIC artifact': job.replace(path, '', 1).replace('            ' + FORMATTED_PATHS[0] + '\n', path + '            ' + FORMATTED_PATHS[0] + '\n', 1),
            }
            for label, mutated_job in mutations.items():
                with self.subTest(job=job_id, mutation=label):
                    self.assertNotEqual(job, mutated_job)
                    with self.assertRaises(ValueError):
                        validate_workflow(structural_text(self.text).replace(job, mutated_job, 1))

    def test_removing_only_reviewed_png_file_additions_restores_exact_84_gate_bytes(self):
        stripped = remove_reviewed_png_file_additions(remove_reviewed_pic_additions(self.text))
        self.assertEqual(hashlib.sha256(stripped.encode('utf-8')).hexdigest(),
                         PNG_FILE_PREDECESSOR_SHA256)

    def test_reversing_only_tga_scheduling_restores_exact_84_gate_bytes(self):
        restored = restore_reviewed_tga_split(remove_reviewed_png_file_additions(remove_reviewed_pic_additions(self.text)))
        self.assertEqual(hashlib.sha256(restored.encode('utf-8')).hexdigest(),
                         TGA_SPLIT_PREDECESSOR_SHA256)

    def test_tga_gate_partition_cannot_move_back_duplicate_or_swap_platforms(self):
        _, jobs = workflow_parts(self.text)
        for suffix, _ in PLATFORMS:
            formatted_id, tga_id = 'formatted' + suffix, 'tga' + suffix
            formatted, tga = jobs[formatted_id], jobs[tga_id]
            _, formatted_steps = job_parts(formatted)
            _, tga_steps = job_parts(tga)
            self.assertEqual(tuple(map(gate_name, formatted_steps[7:-2])), FORMATTED_GATES)
            self.assertEqual(formatted_steps[-2], PIC_GATES[0])
            self.assertEqual(upload_parts(formatted_steps[-1])[1], list(FORMATTED_PATHS) + list(PIC_PATHS))
            for gate in ADDED_FORMATTED_GATES:
                duplicated = formatted.replace(formatted_steps[-1], gate + formatted_steps[-1], 1)
                changed = structural_text(self.text).replace(formatted, duplicated, 1)
                for label, mutation in (
                    ('duplicate across workers', changed),
                    ('move back to formatted', changed.replace(tga, tga.replace(gate, '', 1), 1)),
                ):
                    with self.subTest(platform=suffix, gate=gate_name(gate), mutation=label):
                        with self.assertRaises(ValueError):
                            validate_workflow(mutation)
            for path in ADDED_FORMATTED_PATHS:
                line = '            ' + path + '\n'
                duplicated = formatted + line
                changed = structural_text(self.text).replace(formatted, duplicated, 1)
                for label, mutation in (
                    ('duplicate path across workers', changed),
                    ('move path back to formatted', changed.replace(tga, tga.replace(line, '', 1), 1)),
                ):
                    with self.subTest(platform=suffix, path=path, mutation=label):
                        with self.assertRaises(ValueError):
                            validate_workflow(mutation)
            other = 'Mac' if suffix == 'Ubuntu' else 'Ubuntu'
            with self.subTest(platform=suffix, mutation='wrong-platform TGA job'):
                with self.assertRaises(ValueError):
                    validate_workflow(structural_text(self.text).replace(tga, jobs['tga' + other], 1))

    def test_removing_only_reviewed_png_additions_restores_exact_83_gate_bytes(self):
        stripped = remove_reviewed_png_additions(restore_reviewed_tga_split(remove_reviewed_png_file_additions(remove_reviewed_pic_additions(self.text))))
        self.assertEqual(hashlib.sha256(stripped.encode('utf-8')).hexdigest(),
                         PNG_PREDECESSOR_SHA256)

    def test_removing_only_reviewed_bmp_file_additions_restores_exact_82_gate_bytes(self):
        stripped = remove_reviewed_bmp_file_additions(remove_reviewed_png_additions(restore_reviewed_tga_split(remove_reviewed_png_file_additions(remove_reviewed_pic_additions(self.text)))))
        self.assertEqual(hashlib.sha256(stripped.encode('utf-8')).hexdigest(),
                         BMP_FILE_PREDECESSOR_SHA256)

    def test_raw_workflow_preservation_rejects_crlf(self):
        changed = self.text.replace('\n', '\r\n')
        with self.assertRaises(ValueError):
            validate_workflow(changed)
        with self.assertRaises(ValueError):
            restore_reviewed_tga_split(changed)
        with self.assertRaises(ValueError):
            remove_reviewed_png_additions(changed)
        with self.assertRaises(ValueError):
            remove_reviewed_bmp_file_additions(changed)
        with self.assertRaises(ValueError):
            remove_reviewed_png_file_additions(changed)
        with self.assertRaises(ValueError):
            remove_reviewed_pic_additions(changed)

    def test_removing_only_reviewed_bmp_additions_restores_exact_predecessor_bytes(self):
        # Independent raw-text comparison: do not reuse the structural parser
        # or strip comments/whitespace from the four preserved workers.
        predecessor = remove_reviewed_bmp_file_additions(remove_reviewed_png_additions(restore_reviewed_tga_split(remove_reviewed_png_file_additions(remove_reviewed_pic_additions(self.text)))))
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
            'lost dependency': ('needs: [coreUbuntu, coreMac, formattedUbuntu, formattedMac, bmpUbuntu, bmpMac, pngUbuntu, pngMac, tgaUbuntu, tgaMac, pngFileUbuntu, pngFileMac, picFileUbuntu, picFileMac]', 'needs: [coreUbuntu, formattedUbuntu]'),
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
            job_id = 'tga' + suffix
            job = jobs[job_id]
            _, steps = job_parts(job)
            self.assertEqual(len(steps[7:-1]), 2)
            self.assertEqual(steps[-3], gate)
            self.assertEqual(upload_parts(steps[-1])[1][-len(ADDED_FORMATTED_PATHS)], ADDED_FORMATTED_PATHS[0])
            mutations = {
                'missing TGA gate': job.replace(gate, '', 1),
                'duplicate TGA gate': job.replace(gate, gate * 2, 1),
                'altered TGA command': job.replace('tools/tga_format_probe.py', 'tools/tga_probe.py', 1),
                'missing TGA loader flag': job.replace('tools/tga_format_probe.py --reference-env clean-loader', 'tools/tga_format_probe.py', 1),
                'altered TGA loader flag': job.replace('tools/tga_format_probe.py --reference-env clean-loader', 'tools/tga_format_probe.py --reference-env inherited', 1),
                'optional TGA gate': job.replace(gate, gate.replace('        run:', '        continue-on-error: true\n        run:'), 1),
                'reordered TGA gate': job.replace(gate + ADDED_FORMATTED_GATES[1], ADDED_FORMATTED_GATES[1] + gate, 1),
                'skipped TGA gate': job.replace(gate, gate.replace('        run:', '        if: false\n        run:'), 1),
                'bypassed TGA failure': job.replace(gate, gate.rstrip('\n') + ' || true\n', 1),
                'changed TGA Bend source': job.replace(gate, gate.replace('/.build/dependencies/bend', '/.build/dependencies/other-bend'), 1),
                'changed TGA raylib source': job.replace(gate, gate.replace('/.build/dependencies/raylib', '/.build/dependencies/other-raylib'), 1),
                'duplicate TGA artifact': job.replace(path, path * 2, 1),
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
            job_id = 'tga' + suffix
            job = jobs[job_id]
            _, steps = job_parts(job)
            self.assertEqual(len(steps[7:-1]), 2)
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
        root = '.build/tga-file-probe/'
        retained = (
            'results.json', 'run-example/fixtures/exact-cap.tga',
            'run-example/inputs.json', 'run-example/qualification.c',
            'run-example/reference.c', 'run-example/candidate.bend',
            'run-example/candidate.stdout', 'run-example/candidate.stderr',
            'run-example/candidate.command.json', 'run-example/candidate.resource.json',
            'run-example/native/libraylib.a',
        )
        for suffix, _ in PLATFORMS:
            job_id = 'tga' + suffix
            job = jobs[job_id]
            _, steps = job_parts(job)
            paths = upload_parts(steps[-1])[1]
            self.assertEqual(len(paths), 6)
            self.assertIn('.build/tga-file-probe/', paths)
            self.assertEqual([path for path in paths if path.startswith('!')],
                             list(excluded_paths))
            for relative in retained:
                self.assertFalse(any(fnmatch.fnmatchcase(root + relative, excluded[1:])
                                     for excluded in excluded_paths), relative)
            for excluded in excluded_paths:
                candidate = excluded[1:].replace('run-*', 'run-example')
                self.assertTrue(fnmatch.fnmatchcase(candidate, excluded[1:]))
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
                    'excluded all TGA bodies': job.replace(path, '            !.build/tga-file-probe/run-*/fixtures/*.tga\n', 1),
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

    def test_png_workers_are_independent_mandatory_exact_and_scoped(self):
        _, jobs = workflow_parts(self.text)
        gate, = PNG_GATES
        path = '            ' + PNG_PATHS[0] + '\n'
        for suffix, platform in PLATFORMS:
            job_id = 'png' + suffix
            job = jobs[job_id]
            _, steps = job_parts(job)
            _, formatted_steps = job_parts(jobs['formatted' + suffix])
            self.assertEqual(steps[:7], formatted_steps[:7])
            self.assertEqual(steps[7:-1], [gate])
            self.assertEqual(upload_parts(steps[-1])[1], list(PNG_PATHS))
            mutations = {
                'wrong PNG platform': job.replace('runs-on: ' + platform, 'runs-on: other'),
                'optional PNG worker': '    continue-on-error: true\n' + job,
                'skipped PNG worker': '    if: false\n' + job,
                'dependent PNG worker': '    needs: formatted' + suffix + '\n' + job,
                'PNG matrix': '    strategy:\n      matrix:\n        os: [' + platform + ']\n' + job,
                'changed PNG timeout': job.replace('timeout-minutes: 120', 'timeout-minutes: 180'),
                'changed PNG environment': job.replace('CC: clang', 'CC: gcc'),
                'changed PNG permissions': '    permissions: write-all\n' + job,
                'missing PNG setup': job.replace(steps[0], '', 1),
                'changed PNG setup pin': job.replace('actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1', 'actions/checkout@main', 1),
                'missing PNG gate': job.replace(gate, '', 1),
                'duplicate PNG gate': job.replace(gate, gate * 2, 1),
                'changed PNG command': job.replace('tools/png_format_probe.py', 'tools/png_probe.py', 1),
                'missing PNG loader flag': job.replace('--reference-env clean-loader', '', 1),
                'changed PNG loader flag': job.replace('--reference-env clean-loader', '--reference-env inherited', 1),
                'changed PNG Bend source': job.replace(gate, gate.replace('/.build/dependencies/bend', '/.build/dependencies/other-bend'), 1),
                'changed PNG raylib source': job.replace(gate, gate.replace('/.build/dependencies/raylib', '/.build/dependencies/other-raylib'), 1),
                'optional PNG gate': job.replace(gate, gate.replace('        run:', '        continue-on-error: true\n        run:'), 1),
                'skipped PNG gate': job.replace(gate, gate.replace('        run:', '        if: false\n        run:'), 1),
                'bypassed PNG failure': job.replace(gate, gate.rstrip('\n') + ' || true\n', 1),
                'PNG gate before setup': job.replace(steps[6] + gate, gate + steps[6], 1),
                'missing PNG artifact': job.replace(path, '', 1),
                'duplicate PNG artifact': job.replace(path, path * 2, 1),
                'incomplete PNG receipts': job.replace(path, '            .build/png-format-probe/results.json\n', 1),
                'broader PNG artifact': job.replace(path, '            .build/\n', 1),
                'excluded PNG receipts': job.replace(path, path + '            !.build/png-format-probe/run-*/*.resource.json\n', 1),
                'PNG artifact collision': job.replace('conformance-' + platform + '-png', 'conformance-' + platform + '-formatted', 1),
                'optional PNG upload': job.replace('if: always()', 'if: success()', 1),
                'changed PNG upload pin': job.replace('actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a', 'actions/upload-artifact@main', 1),
                'changed PNG retention': job.replace('retention-days: 14', 'retention-days: 1', 1),
            }
            for index, setup in enumerate(steps[:7]):
                mutations['missing PNG setup step ' + str(index)] = job.replace(setup, '', 1)
            for label, before, after in (
                ('Python action', 'actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97', 'actions/setup-python@main'),
                ('Python version', "python-version: '3.12'", "python-version: '3.13'"),
                ('Bun action', 'oven-sh/setup-bun@0c5077e51419868618aeaa5fe8019c62421857d6', 'oven-sh/setup-bun@main'),
                ('Bun version', '${{ steps.pins.outputs.bun }}', 'latest'),
                ('Bend revision', '${{ steps.pins.outputs.bend }}', 'main'),
                ('raylib revision', '${{ steps.pins.outputs.raylib }}', 'master'),
                ('overlay hash', "if hashlib.sha256(patch.read_bytes()).hexdigest() != overlay['sha256']:", 'if False:'),
            ):
                mutations['changed PNG ' + label] = job.replace(before, after, 1)
            for label, mutated_job in mutations.items():
                with self.subTest(job=job_id, mutation=label):
                    self.assertNotEqual(job, mutated_job)
                    with self.assertRaises(ValueError):
                        validate_workflow(structural_text(self.text).replace(job, mutated_job, 1))

    def test_tga_workers_are_independent_mandatory_exact_and_scoped(self):
        _, jobs = workflow_parts(self.text)
        gate = ADDED_FORMATTED_GATES[0]
        path = '            ' + ADDED_FORMATTED_PATHS[0] + '\n'
        for suffix, platform in PLATFORMS:
            job_id = 'tga' + suffix
            job = jobs[job_id]
            _, steps = job_parts(job)
            _, formatted_steps = job_parts(jobs['formatted' + suffix])
            self.assertEqual(steps[:7], formatted_steps[:7])
            self.assertEqual(steps[7:-1], list(ADDED_FORMATTED_GATES))
            self.assertEqual(upload_parts(steps[-1])[1], list(ADDED_FORMATTED_PATHS))
            mutations = {
                'wrong TGA platform': job.replace('runs-on: ' + platform, 'runs-on: other'),
                'optional TGA worker': '    continue-on-error: true\n' + job,
                'skipped TGA worker': '    if: false\n' + job,
                'dependent TGA worker': '    needs: formatted' + suffix + '\n' + job,
                'TGA matrix': '    strategy:\n      matrix:\n        os: [' + platform + ']\n' + job,
                'changed TGA timeout': job.replace('timeout-minutes: 120', 'timeout-minutes: 180'),
                'changed TGA environment': job.replace('CC: clang', 'CC: gcc'),
                'changed TGA permissions': '    permissions: write-all\n' + job,
                'missing TGA setup': job.replace(steps[0], '', 1),
                'changed TGA setup pin': job.replace('actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1', 'actions/checkout@main', 1),
                'missing TGA gate': job.replace(gate, '', 1),
                'duplicate TGA gate': job.replace(gate, gate * 2, 1),
                'changed TGA command': job.replace('tools/tga_format_probe.py', 'tools/tga_probe.py', 1),
                'missing TGA loader flag': job.replace('--reference-env clean-loader', '', 1),
                'changed TGA loader flag': job.replace('--reference-env clean-loader', '--reference-env inherited', 1),
                'changed TGA Bend source': job.replace(gate, gate.replace('/.build/dependencies/bend', '/.build/dependencies/other-bend'), 1),
                'changed TGA raylib source': job.replace(gate, gate.replace('/.build/dependencies/raylib', '/.build/dependencies/other-raylib'), 1),
                'optional TGA gate': job.replace(gate, gate.replace('        run:', '        continue-on-error: true\n        run:'), 1),
                'skipped TGA gate': job.replace(gate, gate.replace('        run:', '        if: false\n        run:'), 1),
                'bypassed TGA failure': job.replace(gate, gate.rstrip('\n') + ' || true\n', 1),
                'TGA gate before setup': job.replace(steps[6] + gate, gate + steps[6], 1),
                'missing TGA artifact': job.replace(path, '', 1),
                'duplicate TGA artifact': job.replace(path, path * 2, 1),
                'incomplete TGA receipts': job.replace(path, '            .build/tga-format-probe/results.json\n', 1),
                'broader TGA artifact': job.replace(path, '            .build/\n', 1),
                'excluded TGA receipts': job.replace(path, path + '            !.build/tga-format-probe/run-*/*.resource.json\n', 1),
                'TGA artifact collision': job.replace('conformance-' + platform + '-tga', 'conformance-' + platform + '-formatted', 1),
                'optional TGA upload': job.replace('if: always()', 'if: success()', 1),
                'changed TGA upload pin': job.replace('actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a', 'actions/upload-artifact@main', 1),
                'changed TGA retention': job.replace('retention-days: 14', 'retention-days: 1', 1),
            }
            for index, setup in enumerate(steps[:7]):
                mutations['missing TGA setup step ' + str(index)] = job.replace(setup, '', 1)
            for label, before, after in (
                ('Python action', 'actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97', 'actions/setup-python@main'),
                ('Python version', "python-version: '3.12'", "python-version: '3.13'"),
                ('Bun action', 'oven-sh/setup-bun@0c5077e51419868618aeaa5fe8019c62421857d6', 'oven-sh/setup-bun@main'),
                ('Bun version', '${{ steps.pins.outputs.bun }}', 'latest'),
                ('Bend revision', '${{ steps.pins.outputs.bend }}', 'main'),
                ('raylib revision', '${{ steps.pins.outputs.raylib }}', 'master'),
                ('overlay hash', "if hashlib.sha256(patch.read_bytes()).hexdigest() != overlay['sha256']:", 'if False:'),
            ):
                mutations['changed TGA ' + label] = job.replace(before, after, 1)
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

    def test_png_file_workers_are_independent_mandatory_exact_and_scoped(self):
        _, jobs = workflow_parts(self.text)
        gate, = PNG_FILE_GATES
        path = '            ' + PNG_FILE_PATHS[0] + '\n'
        for suffix, platform in PLATFORMS:
            job_id = 'pngFile' + suffix
            job = jobs[job_id]
            _, steps = job_parts(job)
            _, formatted_steps = job_parts(jobs['formatted' + suffix])
            self.assertEqual(steps[:7], formatted_steps[:7])
            self.assertEqual(steps[7:-1], [gate])
            self.assertEqual(upload_parts(steps[-1])[1], list(PNG_FILE_PATHS))
            mutations = {
                'wrong PNG-file platform': job.replace('runs-on: ' + platform, 'runs-on: other'),
                'optional PNG-file worker': '    continue-on-error: true\n' + job,
                'skipped PNG-file worker': '    if: false\n' + job,
                'dependent PNG-file worker': '    needs: formatted' + suffix + '\n' + job,
                'PNG-file matrix': '    strategy:\n      matrix:\n        os: [' + platform + ']\n' + job,
                'changed PNG-file timeout': job.replace('timeout-minutes: 120', 'timeout-minutes: 180'),
                'changed PNG-file environment': job.replace('CC: clang', 'CC: gcc'),
                'changed PNG-file permissions': '    permissions: write-all\n' + job,
                'missing PNG-file setup': job.replace(steps[0], '', 1),
                'changed PNG-file setup pin': job.replace('actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1', 'actions/checkout@main', 1),
                'missing PNG-file gate': job.replace(gate, '', 1),
                'duplicate PNG-file gate': job.replace(gate, gate * 2, 1),
                'changed PNG-file command': job.replace('tools/png_file_probe.py', 'tools/png_probe.py', 1),
                'missing PNG-file loader flag': job.replace('--reference-env clean-loader', '', 1),
                'changed PNG-file loader flag': job.replace('--reference-env clean-loader', '--reference-env inherited', 1),
                'changed PNG-file Bend source': job.replace(gate, gate.replace('/.build/dependencies/bend', '/.build/dependencies/other-bend'), 1),
                'changed PNG-file raylib source': job.replace(gate, gate.replace('/.build/dependencies/raylib', '/.build/dependencies/other-raylib'), 1),
                'optional PNG-file gate': job.replace(gate, gate.replace('        run:', '        continue-on-error: true\n        run:'), 1),
                'skipped PNG-file gate': job.replace(gate, gate.replace('        run:', '        if: false\n        run:'), 1),
                'bypassed PNG-file failure': job.replace(gate, gate.rstrip('\n') + ' || true\n', 1),
                'PNG-file gate before setup': job.replace(steps[6] + gate, gate + steps[6], 1),
                'missing PNG-file artifact': job.replace(path, '', 1),
                'duplicate PNG-file artifact': job.replace(path, path * 2, 1),
                'incomplete PNG-file receipts': job.replace(path, '            .build/png-file-probe/results.json\n', 1),
                'broader PNG-file artifact': job.replace(path, '            .build/\n', 1),
                'excluded PNG-file receipts': job.replace(path, path + '            !.build/png-file-probe/run-*/*.resource.json\n', 1),
                'PNG-file artifact collision': job.replace('conformance-' + platform + '-png-files', 'conformance-' + platform + '-formatted', 1),
                'optional PNG-file upload': job.replace('if: always()', 'if: success()', 1),
                'changed PNG-file upload pin': job.replace('actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a', 'actions/upload-artifact@main', 1),
                'changed PNG-file retention': job.replace('retention-days: 14', 'retention-days: 1', 1),
            }
            for index, setup in enumerate(steps[:7]):
                mutations['missing PNG-file setup step ' + str(index)] = job.replace(setup, '', 1)
            for label, before, after in (
                ('Python action', 'actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97', 'actions/setup-python@main'),
                ('Python version', "python-version: '3.12'", "python-version: '3.13'"),
                ('Bun action', 'oven-sh/setup-bun@0c5077e51419868618aeaa5fe8019c62421857d6', 'oven-sh/setup-bun@main'),
                ('Bun version', '${{ steps.pins.outputs.bun }}', 'latest'),
                ('Bend revision', '${{ steps.pins.outputs.bend }}', 'main'),
                ('raylib revision', '${{ steps.pins.outputs.raylib }}', 'master'),
                ('overlay hash', "if hashlib.sha256(patch.read_bytes()).hexdigest() != overlay['sha256']:", 'if False:'),
            ):
                mutations['changed PNG-file ' + label] = job.replace(before, after, 1)
            for label, mutated_job in mutations.items():
                with self.subTest(job=job_id, mutation=label):
                    self.assertNotEqual(job, mutated_job)
                    with self.assertRaises(ValueError):
                        validate_workflow(structural_text(self.text).replace(job, mutated_job, 1))

    def test_png_file_upload_excludes_only_sparse_fixture_bodies_on_both_platforms(self):
        _, jobs = workflow_parts(self.text)
        excluded_paths = PNG_FILE_PATHS[1:]
        self.assertEqual(len(excluded_paths), 4)
        root = '.build/png-file-probe/'
        retained = (
            'results.json', 'run-example/fixtures/exact-cap.png',
            'run-example/fixtures/c3-single.png', 'run-example/inputs.json',
            'run-example/qualification.c', 'run-example/reference.c',
            'run-example/candidate.bend', 'run-example/candidate.stdout',
            'run-example/candidate.stderr', 'run-example/candidate.command.json',
            'run-example/candidate.resource.json', 'run-example/native/libraylib.a',
        )
        for suffix, _ in PLATFORMS:
            job_id = 'pngFile' + suffix
            job = jobs[job_id]
            _, steps = job_parts(job)
            paths = upload_parts(steps[-1])[1]
            self.assertEqual(len(paths), 5)
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
                    'excluded ordinary exact cap': job.replace(path, '            !.build/png-file-probe/run-*/fixtures/exact-cap.png\n', 1),
                    'excluded all fixtures': job.replace(path, '            !.build/png-file-probe/run-*/fixtures/\n', 1),
                    'excluded fixture recipes': job.replace(path, '            !.build/png-file-probe/run-*/inputs.json\n', 1),
                    'excluded command receipts': job.replace(path, '            !.build/png-file-probe/run-*/*.command.json\n', 1),
                    'excluded resource receipts': job.replace(path, '            !.build/png-file-probe/run-*/*.resource.json\n', 1),
                    'excluded all PNG bodies': job.replace(path, '            !.build/png-file-probe/run-*/fixtures/*.png\n', 1),
                    'excluded source evidence': job.replace(path, '            !.build/png-file-probe/run-*/*.c\n', 1),
                    'excluded candidate source': job.replace(path, '            !.build/png-file-probe/run-*/*.bend\n', 1),
                    'excluded native-build evidence': job.replace(path, '            !.build/png-file-probe/run-*/native/\n', 1),
                    'excluded output receipts': job.replace(path, '            !.build/png-file-probe/run-*/*.stdout\n', 1),
                    'excluded error receipts': job.replace(path, '            !.build/png-file-probe/run-*/*.stderr\n', 1),
                }
                for label, mutated_job in mutations.items():
                    with self.subTest(job=job_id, exclusion=excluded, mutation=label):
                        self.assertNotEqual(job, mutated_job)
                        with self.assertRaises(ValueError):
                            validate_workflow(structural_text(self.text).replace(job, mutated_job, 1))

    def test_both_aggregates_require_each_of_fourteen_direct_workers(self):
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
                    env.update((variable, 'success') for variable in (*BMP_RESULT_VARIABLES, *PNG_RESULT_VARIABLES, *TGA_RESULT_VARIABLES, *PNG_FILE_RESULT_VARIABLES, *PIC_FILE_RESULT_VARIABLES))
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
        base_env.update((variable, 'success') for variable in (*ORIGINAL_RESULT_VARIABLES, *PNG_RESULT_VARIABLES, *TGA_RESULT_VARIABLES, *PNG_FILE_RESULT_VARIABLES, *PIC_FILE_RESULT_VARIABLES))
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

    def test_both_actual_aggregate_shells_fail_closed_for_all_png_results(self):
        _, jobs = workflow_parts(self.text)
        statuses = ('success', 'failure', 'cancelled', 'skipped', '', 'unknown', None)
        base_env = {key: value for key, value in os.environ.items()
                    if key not in (*RESULT_VARIABLES, 'BASH_ENV')}
        base_env.update((variable, 'success') for variable in (*PRE_PNG_RESULT_VARIABLES, *TGA_RESULT_VARIABLES, *PNG_FILE_RESULT_VARIABLES, *PIC_FILE_RESULT_VARIABLES))
        for suffix, _ in PLATFORMS:
            _, steps = job_parts(jobs['conformance' + suffix])
            _, separator, body = steps[0].partition('        run: |\n')
            self.assertTrue(separator)
            self.assertTrue(all(line.startswith('          ') for line in body.splitlines()))
            script = '\n'.join(line[10:] for line in body.splitlines()) + '\n'
            for results in itertools.product(statuses, repeat=2):
                with self.subTest(aggregate=suffix, results=results):
                    env = dict(base_env)
                    env.update((variable, result) for variable, result in zip(PNG_RESULT_VARIABLES, results)
                               if result is not None)
                    result = subprocess.run(['bash', '--noprofile', '--norc', '-e', '-o',
                                             'pipefail', '-c', script], env=env,
                                            capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode == 0,
                                     all(value == 'success' for value in results),
                                     result.stdout + result.stderr)

    def test_both_actual_aggregate_shells_fail_closed_for_all_tga_results(self):
        _, jobs = workflow_parts(self.text)
        statuses = ('success', 'failure', 'cancelled', 'skipped', '', 'unknown', None)
        base_env = {key: value for key, value in os.environ.items()
                    if key not in (*RESULT_VARIABLES, 'BASH_ENV')}
        base_env.update((variable, 'success') for variable in (*PRE_TGA_RESULT_VARIABLES, *PNG_FILE_RESULT_VARIABLES, *PIC_FILE_RESULT_VARIABLES))
        for suffix, _ in PLATFORMS:
            _, steps = job_parts(jobs['conformance' + suffix])
            _, separator, body = steps[0].partition('        run: |\n')
            self.assertTrue(separator)
            self.assertTrue(all(line.startswith('          ') for line in body.splitlines()))
            script = '\n'.join(line[10:] for line in body.splitlines()) + '\n'
            for results in itertools.product(statuses, repeat=2):
                with self.subTest(aggregate=suffix, results=results):
                    env = dict(base_env)
                    env.update((variable, result) for variable, result in zip(TGA_RESULT_VARIABLES, results)
                               if result is not None)
                    result = subprocess.run(['bash', '--noprofile', '--norc', '-e', '-o',
                                             'pipefail', '-c', script], env=env,
                                            capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode == 0,
                                     all(value == 'success' for value in results),
                                     result.stdout + result.stderr)

    def test_both_actual_aggregate_shells_fail_closed_for_all_png_file_results(self):
        _, jobs = workflow_parts(self.text)
        statuses = ('success', 'failure', 'cancelled', 'skipped', '', 'unknown', None)
        base_env = {key: value for key, value in os.environ.items()
                    if key not in (*RESULT_VARIABLES, 'BASH_ENV')}
        base_env.update((variable, 'success') for variable in (*PRE_PNG_FILE_RESULT_VARIABLES, *PIC_FILE_RESULT_VARIABLES))
        for suffix, _ in PLATFORMS:
            _, steps = job_parts(jobs['conformance' + suffix])
            _, separator, body = steps[0].partition('        run: |\n')
            self.assertTrue(separator)
            self.assertTrue(all(line.startswith('          ') for line in body.splitlines()))
            script = '\n'.join(line[10:] for line in body.splitlines()) + '\n'
            for results in itertools.product(statuses, repeat=2):
                with self.subTest(aggregate=suffix, results=results):
                    env = dict(base_env)
                    env.update((variable, result) for variable, result in zip(PNG_FILE_RESULT_VARIABLES, results)
                               if result is not None)
                    result = subprocess.run(['bash', '--noprofile', '--norc', '-e', '-o',
                                             'pipefail', '-c', script], env=env,
                                            capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode == 0,
                                     all(value == 'success' for value in results),
                                     result.stdout + result.stderr)

    def test_six_way_conjunction_structure_and_exhaustive_truth_table(self):
        # The actual scripts must consist only of set -eu, six literal printf
        # diagnostics and fourteen straight-line test commands. Under errexit this
        # grammar is a conjunction: no conditional/function/OR can mask failure.
        # Extract the tested variables from the actual script, then exhaust all
        # 117,649 six-result assignments per aggregate in-process, with PNG
        # and TGA, PNG-file and PIC-file successful. The original 4,802 shell cases and 98 BMP-pair shell cases
        # independently exercise
        # real Bash, including missing/empty values, without 235,298 processes.
        validate_workflow(self.text)
        _, jobs = workflow_parts(self.text)
        statuses = ('success', 'failure', 'cancelled', 'skipped', '', 'unknown', None)
        for suffix, _ in PLATFORMS:
            variables = aggregate_conjunction_variables(jobs['conformance' + suffix])
            assignments = passing = 0
            for results in itertools.product(statuses, repeat=6):
                env = {variable: 'success' for variable in (*PNG_RESULT_VARIABLES, *TGA_RESULT_VARIABLES, *PNG_FILE_RESULT_VARIABLES, *PIC_FILE_RESULT_VARIABLES)}
                env.update((variable, result) for variable, result in zip(PRE_PNG_RESULT_VARIABLES, results)
                           if result is not None)
                actual = all(env.get(variable, '') == 'success' for variable in variables)
                expected = all(value == 'success' for value in results)
                self.assertEqual(actual, expected, (suffix, results))
                assignments += 1
                passing += actual
            self.assertEqual(assignments, 117649)
            self.assertEqual(passing, 1)

    def test_eight_way_conjunction_structure_and_exhaustive_truth_table(self):
        # Interpret only the independently checked straight-line equality
        # grammar. This is exhaustive in-process evaluation, not shell runs.
        validate_workflow(self.text)
        _, jobs = workflow_parts(self.text)
        statuses = ('success', 'failure', 'cancelled', 'skipped', '', 'unknown', None)
        for suffix, _ in PLATFORMS:
            variables = aggregate_conjunction_variables(jobs['conformance' + suffix])
            indices = tuple(RESULT_VARIABLES.index(variable) for variable in variables)
            assignments = passing = 0
            for results in itertools.product(statuses, repeat=8):
                # Both absent (None) and empty expand to '' under ${NAME:-}.
                actual = all(((results + ('success', 'success', 'success', 'success', 'success', 'success'))[index] or '') == 'success'
                             for index in indices)
                expected = results == ('success',) * 8
                if actual != expected:
                    self.fail('Eight-way conjunction mismatch: ' + repr((suffix, results)))
                assignments += 1
                passing += actual
            self.assertEqual(assignments, 5764801)
            self.assertEqual(passing, 1)
            # The ten-test grammar factors into exactly the old eight tests
            # and the two TGA tests. Exhaust all 49 TGA status pairs against
            # both possible old-eight outcomes, retaining missing/empty cases.
            # This covers 7**10 assignments without iterating 282,475,249 rows
            # or creating millions of Bash processes for each aggregate.
            self.assertEqual(variables[:8], PRE_TGA_RESULT_VARIABLES)
            self.assertEqual(variables[8:10], TGA_RESULT_VARIABLES)
            pair_assignments = pair_passing = 0
            combined_assignments = combined_passing = 0
            for pair in itertools.product(statuses, repeat=2):
                env = {variable: value for variable, value in zip(TGA_RESULT_VARIABLES, pair)
                       if value is not None}
                tga_success = all(env.get(variable, '') == 'success' for variable in variables[8:10])
                self.assertEqual(tga_success, pair == ('success', 'success'))
                for old_success, count in ((False, assignments - passing), (True, passing)):
                    actual = old_success and tga_success
                    expected = old_success and pair == ('success', 'success')
                    self.assertEqual(actual, expected, (suffix, old_success, pair))
                    combined_assignments += count
                    combined_passing += count if actual else 0
                pair_assignments += 1
                pair_passing += tga_success
            self.assertEqual((pair_assignments, pair_passing), (49, 1))
            self.assertEqual((combined_assignments, combined_passing), (282475249, 1))

    def test_twelve_way_conjunction_structure_and_factorized_truth_table(self):
        # The closed grammar proves an AND over twelve unique direct results.
        # Keep the separate old-eight exhaustive/old-ten factorized test intact.
        # Enumerate each old variable's seven statuses to derive the old-ten
        # counts, then enumerate all 49 new pairs against both old-ten outcomes.
        # Weight those outcomes by their counts: never loop over 7**12 rows.
        validate_workflow(self.text)
        _, jobs = workflow_parts(self.text)
        statuses = ('success', 'failure', 'cancelled', 'skipped', '', 'unknown', None)
        for suffix, _ in PLATFORMS:
            variables = aggregate_conjunction_variables(jobs['conformance' + suffix])[:12]
            self.assertEqual(variables[:10], PRE_PNG_FILE_RESULT_VARIABLES)
            self.assertEqual(variables[10:], PNG_FILE_RESULT_VARIABLES)
            self.assertEqual(len(set(variables)), 12)
            old_assignments = old_passing = 1
            for variable in variables[:10]:
                outcomes = []
                for status in statuses:
                    env = {} if status is None else {variable: status}
                    actual = env.get(variable, '') == 'success'
                    self.assertEqual(actual, status == 'success')
                    outcomes.append(actual)
                self.assertEqual((len(outcomes), sum(outcomes)), (7, 1))
                old_assignments *= len(outcomes)
                old_passing *= sum(outcomes)
            self.assertEqual((old_assignments, old_passing), (282475249, 1))
            pair_assignments = pair_passing = combined_assignments = combined_passing = 0
            for pair in itertools.product(statuses, repeat=2):
                env = {variable: value for variable, value in zip(variables[10:], pair)
                       if value is not None}
                new_success = all(env.get(variable, '') == 'success' for variable in variables[10:])
                self.assertEqual(new_success, pair == ('success', 'success'))
                for old_success, count in ((False, old_assignments - old_passing), (True, old_passing)):
                    actual = old_success and new_success
                    expected = old_success and pair == ('success', 'success')
                    self.assertEqual(actual, expected, (suffix, old_success, pair))
                    combined_assignments += count
                    combined_passing += count if actual else 0
                pair_assignments += 1
                pair_passing += new_success
            self.assertEqual((pair_assignments, pair_passing), (49, 1))
            self.assertEqual((combined_assignments, combined_passing), (13841287201, 1))

    def test_twelve_way_grammar_rejects_new_pair_substitution(self):
        _, jobs = workflow_parts(self.text)
        for suffix, _ in PLATFORMS:
            job = jobs['conformance' + suffix]
            first = '          test "${PNG_FILE_UBUNTU_RESULT:-}" = success\n'
            second = '          test "${PNG_FILE_MAC_RESULT:-}" = success\n'
            mutations = {
                'duplicate Ubuntu instead of Mac': job.replace(second, first, 1),
                'duplicate Mac instead of Ubuntu': job.replace(first, second, 1),
                'new pair reordered': job.replace(first + second, second + first, 1),
                'old worker substituted': job.replace(first, first.replace('PNG_FILE_UBUNTU_RESULT', 'PNG_UBUNTU_RESULT'), 1),
                'new diagnostic injection': job.replace('PNG files Ubuntu: %s', 'PNG files Ubuntu: $(true) %s', 1),
            }
            for label, changed in mutations.items():
                with self.subTest(aggregate=suffix, mutation=label):
                    self.assertNotEqual(job, changed)
                    with self.assertRaises(ValueError):
                        aggregate_conjunction_variables(changed)
                    with self.assertRaises(ValueError):
                        validate_workflow(structural_text(self.text).replace(job, changed, 1))

    def test_ten_way_conjunction_grammar_rejects_masked_failure(self):
        _, jobs = workflow_parts(self.text)
        for suffix, _ in PLATFORMS:
            job = jobs['conformance' + suffix]
            mutations = {
                'no errexit': job.replace('set -eu', 'set -u', 1),
                'disable errexit': job.replace('set -eu', 'set -eu; set +e', 1),
                'extra success': job + '          true\n',
                'conditional group': job.replace('          set -eu\n', '          set -eu\n          if true; then\n', 1) + '          fi\n',
                'diagnostic command substitution': job.replace('PNG Ubuntu: %s', 'PNG Ubuntu: $(true) %s', 1),
            }
            for variable in RESULT_VARIABLES:
                test = '          test "${' + variable + ':-}" = success\n'
                for label, altered in (
                    ('missing', ''), ('bypass', test.rstrip('\n') + ' || true\n'),
                    ('OR', test.rstrip('\n') + ' || exit 0\n'),
                    ('default success', test.replace(':-}', ':-success}')),
                    ('not failure', test.replace('= success', '!= failure')),
                    ('subshell', '          (' + test.strip() + ') || true\n'),
                ):
                    mutations[label + ' ' + variable] = job.replace(test, altered, 1)
            for label, changed in mutations.items():
                with self.subTest(aggregate=suffix, mutation=label):
                    self.assertNotEqual(job, changed)
                    with self.assertRaises(ValueError):
                        aggregate_conjunction_variables(changed)
                    with self.assertRaises(ValueError):
                        validate_workflow(structural_text(self.text).replace(job, changed, 1))


    def test_removing_only_reviewed_pic_file_additions_restores_exact_86_gate_bytes(self):
        restored = remove_reviewed_pic_file_additions(self.text)
        self.assertEqual(hashlib.sha256(restored.encode('utf-8')).hexdigest(),
                         PIC_FILE_PREDECESSOR_SHA256)
        _, before = workflow_parts(restored)
        _, after = workflow_parts(self.text)
        for worker in PRE_PIC_FILE_WORKERS:
            self.assertEqual(before[worker], after[worker])
        with self.assertRaises(ValueError):
            remove_reviewed_pic_file_additions(self.text.replace('\n', '\r\n'))

    def test_pic_file_workers_are_independent_mandatory_exact_and_scoped(self):
        _, jobs = workflow_parts(self.text)
        gate, = PIC_FILE_GATES
        path = '            ' + PIC_FILE_PATHS[0] + '\n'
        for suffix, platform in PLATFORMS:
            job_id = 'picFile' + suffix
            job = jobs[job_id]
            _, steps = job_parts(job)
            _, formatted_steps = job_parts(jobs['formatted' + suffix])
            self.assertEqual(steps[:7], formatted_steps[:7])
            self.assertEqual(steps[7:-1], [gate])
            self.assertEqual(upload_parts(steps[-1])[1], list(PIC_FILE_PATHS))
            mutations = {
                'wrong PIC-file platform': job.replace('runs-on: ' + platform, 'runs-on: other'),
                'optional PIC-file worker': '    continue-on-error: true\n' + job,
                'skipped PIC-file worker': '    if: false\n' + job,
                'dependent PIC-file worker': '    needs: formatted' + suffix + '\n' + job,
                'PIC-file matrix': '    strategy:\n      matrix:\n        os: [' + platform + ']\n' + job,
                'changed PIC-file timeout': job.replace('timeout-minutes: 120', 'timeout-minutes: 180'),
                'changed PIC-file environment': job.replace('CC: clang', 'CC: gcc'),
                'changed PIC-file permissions': '    permissions: write-all\n' + job,
                'missing PIC-file setup': job.replace(steps[0], '', 1),
                'changed PIC-file setup pin': job.replace('actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1', 'actions/checkout@main', 1),
                'missing PIC-file gate': job.replace(gate, '', 1),
                'duplicate PIC-file gate': job.replace(gate, gate * 2, 1),
                'changed PIC-file command': job.replace('tools/pic_file_probe.py', 'tools/pic_probe.py', 1),
                'missing PIC-file loader flag': job.replace('--reference-env clean-loader', '', 1),
                'changed PIC-file loader flag': job.replace('--reference-env clean-loader', '--reference-env inherited', 1),
                'changed PIC-file Bend source': job.replace(gate, gate.replace('/.build/dependencies/bend', '/.build/dependencies/other-bend'), 1),
                'changed PIC-file raylib source': job.replace(gate, gate.replace('/.build/dependencies/raylib', '/.build/dependencies/other-raylib'), 1),
                'optional PIC-file gate': job.replace(gate, gate.replace('        run:', '        continue-on-error: true\n        run:'), 1),
                'skipped PIC-file gate': job.replace(gate, gate.replace('        run:', '        if: false\n        run:'), 1),
                'bypassed PIC-file failure': job.replace(gate, gate.rstrip('\n') + ' || true\n', 1),
                'PIC-file gate before setup': job.replace(steps[6] + gate, gate + steps[6], 1),
                'missing PIC-file artifact': job.replace(path, '', 1),
                'duplicate PIC-file artifact': job.replace(path, path * 2, 1),
                'incomplete PIC-file receipts': job.replace(path, '            .build/pic-file-probe/results.json\n', 1),
                'broader PIC-file artifact': job.replace(path, '            .build/\n', 1),
                'excluded PIC-file receipts': job.replace(path, path + '            !.build/pic-file-probe/run-*/*.resource.json\n', 1),
                'PIC-file artifact collision': job.replace('conformance-' + platform + '-pic-files', 'conformance-' + platform + '-formatted', 1),
                'optional PIC-file upload': job.replace('if: always()', 'if: success()', 1),
                'changed PIC-file upload pin': job.replace('actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a', 'actions/upload-artifact@main', 1),
                'changed PIC-file retention': job.replace('retention-days: 14', 'retention-days: 1', 1),
            }
            for index, setup in enumerate(steps[:7]):
                mutations['missing PIC-file setup step ' + str(index)] = job.replace(setup, '', 1)
            for label, before, after in (
                ('Python action', 'actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97', 'actions/setup-python@main'),
                ('Python version', "python-version: '3.12'", "python-version: '3.13'"),
                ('Bun action', 'oven-sh/setup-bun@0c5077e51419868618aeaa5fe8019c62421857d6', 'oven-sh/setup-bun@main'),
                ('Bun version', '${{ steps.pins.outputs.bun }}', 'latest'),
                ('Bend revision', '${{ steps.pins.outputs.bend }}', 'main'),
                ('raylib revision', '${{ steps.pins.outputs.raylib }}', 'master'),
                ('overlay hash', "if hashlib.sha256(patch.read_bytes()).hexdigest() != overlay['sha256']:", 'if False:'),
            ):
                mutations['changed PIC-file ' + label] = job.replace(before, after, 1)
            for label, mutated_job in mutations.items():
                with self.subTest(job=job_id, mutation=label):
                    self.assertNotEqual(job, mutated_job)
                    with self.assertRaises(ValueError):
                        validate_workflow(structural_text(self.text).replace(job, mutated_job, 1))

    def test_pic_file_upload_excludes_only_sparse_fixture_bodies_on_both_platforms(self):
        _, jobs = workflow_parts(self.text)
        excluded_paths = PIC_FILE_PATHS[1:]
        self.assertEqual(len(excluded_paths), 4)
        root = '.build/pic-file-probe/'
        retained = (
            'results.json', 'run-example/fixtures/exact-cap.pic',
            'run-example/fixtures/c3-single.pic',
            'run-example/fixtures/error-encoded-over-one-mib.pic', 'run-example/inputs.json',
            'run-example/qualification.c', 'run-example/reference.c',
            'run-example/candidate.bend', 'run-example/candidate.stdout',
            'run-example/candidate.stderr', 'run-example/candidate.command.json',
            'run-example/candidate.resource.json', 'run-example/native/libraylib.a',
        )
        for suffix, _ in PLATFORMS:
            job_id = 'picFile' + suffix
            job = jobs[job_id]
            _, steps = job_parts(job)
            paths = upload_parts(steps[-1])[1]
            self.assertEqual(len(paths), 5)
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
                    'excluded ordinary exact cap': job.replace(path, '            !.build/pic-file-probe/run-*/fixtures/exact-cap.pic\n', 1),
                    'excluded all fixtures': job.replace(path, '            !.build/pic-file-probe/run-*/fixtures/\n', 1),
                    'excluded fixture recipes': job.replace(path, '            !.build/pic-file-probe/run-*/inputs.json\n', 1),
                    'excluded command receipts': job.replace(path, '            !.build/pic-file-probe/run-*/*.command.json\n', 1),
                    'excluded resource receipts': job.replace(path, '            !.build/pic-file-probe/run-*/*.resource.json\n', 1),
                    'excluded all PIC bodies': job.replace(path, '            !.build/pic-file-probe/run-*/fixtures/*.pic\n', 1),
                    'excluded source evidence': job.replace(path, '            !.build/pic-file-probe/run-*/*.c\n', 1),
                    'excluded candidate source': job.replace(path, '            !.build/pic-file-probe/run-*/*.bend\n', 1),
                    'excluded native-build evidence': job.replace(path, '            !.build/pic-file-probe/run-*/native/\n', 1),
                    'excluded output receipts': job.replace(path, '            !.build/pic-file-probe/run-*/*.stdout\n', 1),
                    'excluded error receipts': job.replace(path, '            !.build/pic-file-probe/run-*/*.stderr\n', 1),
                }
                for label, mutated_job in mutations.items():
                    with self.subTest(job=job_id, exclusion=excluded, mutation=label):
                        self.assertNotEqual(job, mutated_job)
                        with self.assertRaises(ValueError):
                            validate_workflow(structural_text(self.text).replace(job, mutated_job, 1))

    def test_pic_file_audit_is_mandatory_after_the_native_probe(self):
        _, jobs = workflow_parts(self.text)
        command = '          python3 tools/pic_file_audit.py .build/pic-file-probe/results.json\n'
        for suffix, _ in PLATFORMS:
            job = jobs['picFile' + suffix]
            gate = PIC_FILE_GATES[0]
            for label, changed in (
                ('missing audit', job.replace(command, '', 1)),
                ('bypassed audit', job.replace(command, command.rstrip('\n') + ' || true\n', 1)),
                ('wrong audit report', job.replace(command, command.replace('pic-file-probe/', 'pic-format-probe/'), 1)),
                ('audit before probe', job.replace(gate, gate.replace(command, '').replace('        run: |\n', '        run: |\n' + command), 1)),
                ('excluded encoded-over-one-mib input', job + '            !.build/pic-file-probe/run-*/fixtures/error-encoded-over-one-mib.pic\n'),
            ):
                with self.subTest(platform=suffix, mutation=label):
                    self.assertNotEqual(job, changed)
                    with self.assertRaises(ValueError):
                        validate_workflow(structural_text(self.text).replace(job, changed, 1))

    def test_both_actual_aggregate_shells_fail_closed_for_all_pic_file_results(self):
        _, jobs = workflow_parts(self.text)
        statuses = ('success', 'failure', 'cancelled', 'skipped', '', 'unknown', None)
        base_env = {key: value for key, value in os.environ.items()
                    if key not in (*RESULT_VARIABLES, 'BASH_ENV')}
        base_env.update((variable, 'success') for variable in PRE_PIC_FILE_RESULT_VARIABLES)
        for suffix, _ in PLATFORMS:
            _, steps = job_parts(jobs['conformance' + suffix])
            _, separator, body = steps[0].partition('        run: |\n')
            self.assertTrue(separator)
            self.assertTrue(all(line.startswith('          ') for line in body.splitlines()))
            script = '\n'.join(line[10:] for line in body.splitlines()) + '\n'
            for results in itertools.product(statuses, repeat=2):
                with self.subTest(aggregate=suffix, results=results):
                    env = dict(base_env)
                    env.update((variable, result) for variable, result in zip(PIC_FILE_RESULT_VARIABLES, results)
                               if result is not None)
                    result = subprocess.run(['bash', '--noprofile', '--norc', '-e', '-o',
                                             'pipefail', '-c', script], env=env,
                                            capture_output=True, text=True, timeout=5)
                    self.assertEqual(result.returncode == 0,
                                     all(value == 'success' for value in results),
                                     result.stdout + result.stderr)

    def test_fourteen_way_conjunction_structure_and_factorized_truth_table(self):
        # The closed grammar proves an AND over fourteen unique direct results.
        # Keep the separate old-eight exhaustive/old-twelve factorized test intact.
        # Enumerate each old variable's seven statuses to derive the old-twelve
        # counts, then enumerate all 49 new pairs against both old-twelve outcomes.
        # Weight those outcomes by their counts: never loop over 7**14 rows.
        validate_workflow(self.text)
        _, jobs = workflow_parts(self.text)
        statuses = ('success', 'failure', 'cancelled', 'skipped', '', 'unknown', None)
        for suffix, _ in PLATFORMS:
            variables = aggregate_conjunction_variables(jobs['conformance' + suffix])
            self.assertEqual(variables[:12], PRE_PIC_FILE_RESULT_VARIABLES)
            self.assertEqual(variables[12:], PIC_FILE_RESULT_VARIABLES)
            self.assertEqual(len(set(variables)), 14)
            old_assignments = old_passing = 1
            for variable in variables[:12]:
                outcomes = []
                for status in statuses:
                    env = {} if status is None else {variable: status}
                    actual = env.get(variable, '') == 'success'
                    self.assertEqual(actual, status == 'success')
                    outcomes.append(actual)
                self.assertEqual((len(outcomes), sum(outcomes)), (7, 1))
                old_assignments *= len(outcomes)
                old_passing *= sum(outcomes)
            self.assertEqual((old_assignments, old_passing), (13841287201, 1))
            pair_assignments = pair_passing = combined_assignments = combined_passing = 0
            for pair in itertools.product(statuses, repeat=2):
                env = {variable: value for variable, value in zip(variables[12:], pair)
                       if value is not None}
                new_success = all(env.get(variable, '') == 'success' for variable in variables[12:])
                self.assertEqual(new_success, pair == ('success', 'success'))
                for old_success, count in ((False, old_assignments - old_passing), (True, old_passing)):
                    actual = old_success and new_success
                    expected = old_success and pair == ('success', 'success')
                    self.assertEqual(actual, expected, (suffix, old_success, pair))
                    combined_assignments += count
                    combined_passing += count if actual else 0
                pair_assignments += 1
                pair_passing += new_success
            self.assertEqual((pair_assignments, pair_passing), (49, 1))
            self.assertEqual((combined_assignments, combined_passing), (678223072849, 1))

    def test_fourteen_way_grammar_rejects_new_pair_substitution(self):
        _, jobs = workflow_parts(self.text)
        for suffix, _ in PLATFORMS:
            job = jobs['conformance' + suffix]
            first = '          test "${PIC_FILE_UBUNTU_RESULT:-}" = success\n'
            second = '          test "${PIC_FILE_MAC_RESULT:-}" = success\n'
            mutations = {
                'duplicate Ubuntu instead of Mac': job.replace(second, first, 1),
                'duplicate Mac instead of Ubuntu': job.replace(first, second, 1),
                'new pair reordered': job.replace(first + second, second + first, 1),
                'old worker substituted': job.replace(first, first.replace('PIC_FILE_UBUNTU_RESULT', 'PNG_UBUNTU_RESULT'), 1),
                'new diagnostic injection': job.replace('PIC files Ubuntu: %s', 'PIC files Ubuntu: $(true) %s', 1),
            }
            for label, changed in mutations.items():
                with self.subTest(aggregate=suffix, mutation=label):
                    self.assertNotEqual(job, changed)
                    with self.assertRaises(ValueError):
                        aggregate_conjunction_variables(changed)
                    with self.assertRaises(ValueError):
                        validate_workflow(structural_text(self.text).replace(job, changed, 1))


if __name__ == '__main__':
    unittest.main()
