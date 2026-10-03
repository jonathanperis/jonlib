# PNM file reconstruction and verification obligations

## Source and evidence identity

The published base is `d3b938962f63b984bb6a7549de099e9a0a951d36`.
The original unpublished PNM-file checkpoint was
`36f5d0b5a811297b349c45aa6ddc3a9a067ac8d3`. Its implementation, harness and
runtime report were lost with the execution volume; original Git object IDs
alone cannot establish the contents or results of a reconstruction.

`LAWS.bend`, `PROOF.bend`, `README.md` and `api/progress.json` were recovered
byte-for-byte from original objects. Generated ledger descriptions can therefore
retain the same bounded contract. The 11-line library addition and the new
`tools/pnm_file_probe.py` / `tests/test_pnm_file_harness.py` are reconstructed
source, not recovered original bytes. The original library blob was
`812db893c0993440282620be66377c7b686e6eb2`; this reconstruction does **not** match
that blob. The new library blob is
`01962ae87a31037ccba572db34f3f3cb3566bece` (SHA-256
`1b21b882ecbed49ddb9b5b4815c5484aaed968d66c0efe1619f5fe8063ff483a`).
No old passed receipt is used to validate it.

The fresh [PNM file report](evidence/pnm-formatted-files.json) explicitly labels
its evidence origin, records exact library and dependency SHA-256 values, and
seals generated sources, compilers, native archive, inputs, output streams and
command/resource receipts. Its `base_revision` identifies the checkout before
commit; the source hashes identify the measured implementation. Its reused
filename does not mean the unavailable historical report was recovered.

## Counts do not establish equivalence

The published baseline has 495 Python tests. The lost checkpoint reportedly had
49 additional file-test methods (544 total). The new file suite has 37 methods,
including parameterized mutation/negative controls; the baseline test files and
all their predicates remain unchanged. The 12-method count difference reflects
new organization and unavailable original test source. It is not evidence of
weaker or equivalent coverage by itself. Full-suite results must come from the
new run, not subtraction or a previous checkpoint's summary.

The primary fixture matrix deliberately reconstructs 156 accepted ordinary
files / 64,542 pixels, 132 actual `LoadImage` references, 24 explicit native PNM
references, and 74 candidate-only typed controls. The new role matrix has
626 observations / 129,072 compared bytes per lane, versus the historical
552 / 127,440. It preserves all 96 published PNM-memory inputs verbatim and adds
threaded owner observations and reopened normalized regressions. The separate
exact-cap native observation and resource lanes are not hidden inside these
primary totals.

## Obligation-to-evidence matrix

`file tests` below means `tests/test_pnm_file_harness.py`; `memory tests` means
the unchanged `tests/test_pnm_format_harness.py`. Test names identify executable
checks, not a claim that static source inspection proves runtime behavior.

| Obligation | Executable checks | Fresh runtime/provenance evidence |
|---|---|---|
| Explicit P5/P6 file selection regardless of suffix | File `test_suffix_matrix_covers_both_channels_and_depths`, `test_exact_primary_matrix_and_all_memory_inputs_retained`, `test_wrapper_reuses_closed_bounded_shared_boundary` | 156 cases; 15 suffix shapes for both channels/depths; 132 actual file routes and 24 explicit native routes |
| Format 1/4 and exact reduced samples, not normalized-only comparison | File `test_native_file_route_and_raw_observation_order`, `test_action_expectations_are_native_and_modes_stay_distinct`; unchanged memory sample matrix | Actual native dimensions/mipmaps/format/raw length and bytes before independent format-7 normalization; endian/wide-byte qualification |
| Header/sample rules, dimension boundaries and unchanged decoder behavior | All 96 memory fixtures retained; file `test_typed_controls_are_file_byte_safe_and_never_native`; memory `test_all_legacy_inputs_preserved_and_matrix_discriminators` | Published parser reused; 4096-axis endpoints, maxval boundaries, separators/comments, wide sample discard/retention; independent memory regression |
| Single affine owner, high-bit invariants, threaded/rejected reads and consuming export | File `test_primary_and_owner_calls_reopen_real_public_files`; unchanged memory ownership tests | Public file factory, raw/owner/bridge observations; first/last and four rejected coordinates; every logical word's high bits checked |
| Typed open/size/read errors preserve distinction | File `test_typed_controls_are_file_byte_safe_and_never_native`, `test_closure_uses_ten_acquired_handle_paths_and_exact_messages` | Actual missing/open, directory/read and U32-overflow size paths; synthetic exact code/message preservation for size and read failures |
| Exact read before decode; short and long mismatch rejected | File closure/source tests and `test_complete_boundary_records_and_terminal_are_required` | Real acquired handles with injected short/long read results; complete ordinary truncated files separately reach decoder |
| Close calls precede read-result processing/decode on every admitted stage | File `test_wrapper_reuses_closed_bounded_shared_boundary`; restored pure cap law | Static shared-reader order plus 100 cycles at fd64 across ten acquired paths; 1,009 individually checked records per lane |
| Inclusive raster cap independent of filename; bounded resource behavior | File `test_files_are_real_exact_cap_and_sparse_are_pre_read_controls` and resource receipt tests | Accepted exact 1,048,576-byte file; cap+1, misleading `.qoi`, 256 MiB and U32-overflow controls; separate measured sparse/closure and exact-cap lanes |
| Decoder errors wrapped exactly once, no partial image on failure | File typed controls, stage error assertions; unchanged shared wrapper and decoder | 74 checked-only controls plus eight synthetic boundary checks, including invalid byte and generic `InvalidImageStream` propagation |
| Never pass malformed/oversized controls to native | File `test_native_schema_and_safety_mutations_fail_closed`, `test_native_input_safety_failure_precedes_archive_or_decoder`; unchanged independent safety parser tests | Native program generated only from separately validated accepted case schema; zero native invalid controls |
| Exact ordered typed framing, complete bytes and no trailing records | File `test_format_framing_and_byte_types_cannot_normalize_away_mismatch`, `test_complete_boundary_records_and_terminal_are_required`; unchanged memory framing tests | Every primary and closure record parsed; byte chunks, metadata fields/types, lengths, terminal and sequence all strict |
| Every CPU-1/CPU-2/JavaScript lane and contiguous batch is mandatory | File `test_all_three_lanes_require_complete_contiguous_batches_and_resources`, `test_resource_completion_rejects_forged_types_missing_and_excess_receipts`; unchanged memory lane tests | Final admission requires all primary batches plus boundary, all-sparse and exact-cap resource lanes |
| Fresh native build explicitly enables PNM | Unchanged memory `test_native_config_requires_actual_single_enabled_definition`, `test_native_build_explicit_pnm_and_configuration_checked_before_execution`; file mocked native-build failure | Fresh isolated archive; exact CMake cache and enabled compile-definition checks before/after build; compiler identity/version and artifact hashes |
| Clean-loader child environment is real and parent stays unchanged | Unchanged `tests/test_reference_environment.py` behavioral tests; file `test_all_command_receipts_preserve_clean_environment_and_actual_limits` | Replacement child environment receipts for native compiler/reference commands, parent/effective-context reassertion and tool-path resolution checks |
| Source, dependencies, outputs and ordinary/sparse inputs cannot drift | File `test_ordinary_file_and_dependency_drift_cannot_pass_input_verification`, `test_input_missing_directory_and_sparse_prefix_drift_fail`; unchanged seal/reseal tests | Source gate, dependency hashes, sealed artifacts; missing/directory conditions and sparse prefix/logical-size validation before work and final admission |
| Failed or missing compiler output cannot reuse stale success | File `test_successful_compiler_must_create_nonempty_fresh_outputs`, `test_child_start_failure_retains_fail_closed_receipt` | Scoped recorder removes `-o` outputs before invocation, requires nonempty new files, seals them and retains failed receipts |
| Outer timeouts/interruption bound compiler and candidate descendants | File real `test_compiler_timeout_kills_grandchild_and_removes_stale_output`, `test_real_outer_timeout_kills_candidate_descendants` | New scoped all-command recorder owns a POSIX process group and kills/reaps it; SIGTERM-ignoring delayed-sentinel tests verify descendants cannot outlive timeout |
| Resource receipts are genuine, separate from compilation, typed and bounded | File resource receipt/schema/completion tests, including stale/missing/duplicate/extra fields | Fresh measurement parent and real fd64 launcher; fixed 256 MiB sparse/closure and 1 GiB exact-cap ceilings; ordinary compiler receipts do not claim fd64 |
| Argument admission cannot retain a previous passed report | File default/duplicate destination reset tests, complete-argument zero/negative-timeout tests, forbidden/abbreviated loader-policy tests | Destination reports reset before parsing; only explicit clean-loader profile accepted; positive timeout required before checkout |
| Setup/qualification failures cannot reach later stages or claim success | File checkout, missing-tool, native-input, native-build and bad-qualification orchestration tests | Top-level report starts false; native qualification precedes candidates; all mandatory stages must complete before success |
| Published library and harness gates remain unchanged | Baseline Python suite, complete 133-law proof, PNM-memory/Surface and generic file/memory regressions | Fresh command receipts and unchanged-source hashes, distinct from historical results |
| Canonical comparator/fixtures/tolerances remain unchanged | Canonical `tools/conformance.py`; additional validation-only strict replay negative controls | 261 records / 40,101 words plus 333 QOI bytes and 23 palette words per CPU-1/CPU-2/JavaScript lane, comparing every emitted field |

## Completed new validation

The [validation record](evidence/pnm-files-reconstruction-validation.json)
retains the passing 532-test suite, complete 133-law verdict, focused independent
audit, PNM-memory/Surface and generic regressions, canonical conformance and
strict complete-record replay. It embeds the validation-only scripts and hashes
unchanged published gates. All three primary lanes and all resource lanes pass;
no failed/interrupted attempt supplies success evidence. The strict final replay
includes nine negative controls, specifically altered QOI, palette and alpha
border values in otherwise valid framing.

## Explicit limits

The exact original 49-test file suite and original runtime streams are not
available, so their assertion-by-assertion identity cannot be established. This
matrix covers the recovered contract and known verification obligations with
new executable evidence; it does not reconstruct lost test source by inference.
The two real descendant-lifetime defects found during reconstruction were fixed
locally in the new gate, leaving published shared helpers unchanged.

The proof is structural (133 laws, including the restored raster-cap law), not a
universal codec or IO proof. Synthetic stage results do not demonstrate actual
concurrent file mutation. No guarantee of reported OS-close success is possible
because pinned Base discards close errors. GPU/Metal IO, macOS/Windows/browser,
big-endian, maximum-area/OOM parity, native callbacks/allocation ABI, changing or
special files, generic formatted/float dispatch and representative performance
remain unqualified. `raylib:function:LoadImage` remains partial; no complete API
or configuration-control count increases.
