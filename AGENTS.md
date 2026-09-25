# Jonlib engineering

- Implement the library in Bend 2. Keep raylib in the reference tooling;
  compiler/code-generation changes belong in the separately declared Bend overlay.
- Read `toolchain.json`, `docs/API.md` and `docs/COMPATIBILITY.md` before changing a contract.
- Use the pinned revisions and exact declared Bend compiler overlay; never
  install/update a toolchain or repair its source as a side effect of verification.
- Run `python3 -m unittest discover -s tests -v` for harness changes and
  `python3 tools/conformance.py` for affected library/fixture changes.
- Run `python3 tools/check_project.py` for project metadata/documentation changes.
- Select parity work by stable IDs in `docs/PROGRESS.md`. Update
  `api/progress.json` with scope, gaps and evidence, then regenerate with
  `python3 tools/api_plan.py build`. Base delivery updates on ledger deltas;
  proposed mappings and partial profiles never count as completed APIs.
- GPU evidence requires `python3 tools/conformance.py --gpu`; a CPU fallback
  does not establish GPU correctness or performance.
- Do not change expected results or loosen tolerances to hide a mismatch.
  Diagnose raylib semantics, Jonlib, fixtures and backend differences first.
- Preserve upstream notices and mark adapted algorithms. No borrowed assets
  without their specific licenses/provenance.
- `.specs/` and `.build/` are local artifacts. Keep durable API docs and the
  compatibility ledger in `docs/`.
