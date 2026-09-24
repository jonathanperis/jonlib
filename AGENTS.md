# Jonlib engineering

- Implement the library in Bend 2. Keep C/raylib solely in the reference tooling.
- Read `toolchain.json`, `docs/API.md` and `docs/COMPATIBILITY.md` before changing a contract.
- Use existing pinned checkouts; never install/update a toolchain as a side effect.
- Run `python3 -m unittest discover -s tests -v` for harness changes and
  `python3 tools/conformance.py` for affected library/fixture changes.
- Run `python3 tools/check_project.py` for project metadata/documentation changes.
- GPU evidence requires `python3 tools/conformance.py --gpu`; a CPU fallback
  does not establish GPU correctness or performance.
- Do not change expected results or loosen tolerances to hide a mismatch.
  Diagnose raylib semantics, Jonlib, fixtures and backend differences first.
- Preserve upstream notices and mark adapted algorithms. No borrowed assets
  without their specific licenses/provenance.
- `.specs/` and `.build/` are local artifacts. Keep durable API docs and the
  compatibility ledger in `docs/`.
