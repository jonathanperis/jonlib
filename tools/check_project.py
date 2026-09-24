#!/usr/bin/env python3
"""Fast repository checks used by CI; no downloads or compilation."""
import json
from pathlib import Path
import re
import subprocess

from conformance import ROOT, cases_from, source_gate


def main():
    pins = json.loads((ROOT / 'toolchain.json').read_text())
    for dependency in ('bend', 'raylib'):
        if not re.fullmatch(r'[0-9a-f]{40}', pins[dependency]['revision']):
            raise ValueError(f'{dependency}: expected a complete immutable commit SHA')
    if not re.fullmatch(r'\d+\.\d+\.\d+', pins['bun']['version']):
        raise ValueError('Bun must have a pinned release version')
    cases = cases_from(json.loads((ROOT / 'tests/fixtures/images.json').read_text()))
    source_gate()
    documents = [*ROOT.glob('*.md'), *(ROOT / 'docs').glob('*.md'),
                 ROOT / 'tests/fixtures/README.md']
    for document in documents:
        for target in re.findall(r'\]\(([^)]+)\)', document.read_text()):
            if target.startswith(('https://', 'http://', '#')):
                continue
            if not (document.parent / target.split('#')[0]).exists():
                raise ValueError(f'{document.relative_to(ROOT)}: broken link {target}')
    tracked = subprocess.check_output(['git', 'ls-files'], cwd=ROOT, text=True).splitlines()
    if any(path.startswith(('.build/', '.specs/')) for path in tracked):
        raise ValueError('Local build/spec artifacts must not be tracked')
    for path in ('LICENSE', 'LICENSES/raylib.txt', 'THIRD_PARTY_NOTICES.md'):
        if not (ROOT / path).is_file():
            raise ValueError(f'Missing license/provenance document: {path}')
    print(f'Project checks passed; {len(cases)} nonempty deterministic scenarios')


if __name__ == '__main__':
    main()
