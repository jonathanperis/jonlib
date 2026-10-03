# TGA reconstruction coverage obligations

This document records the isolated reconstruction checkpoint `f6a48cd`. Its
counts and runtime receipts remain scoped to that source; the later merged
source is verified separately in [TGA integration](TGA-INTEGRATION.md).

This is a new reconstruction on published baseline
`d3b938962f63b984bb6a7549de099e9a0a951d36`. The lost local TGA checkpoint and its
full source/runtime artifacts are unavailable. This report does **not** claim
byte-for-byte restoration of that checkpoint, fixture corpus or test functions.
It maps the retained contract and verification obligations to new source tests
and fresh runtime receipts instead. [The contract](TGA.md#format-preserving-tga-memory-loading)
remains a partial `LoadImageFromMemory` increment.

## Counting tests honestly

The published baseline contains **495 Python tests**. The pre-cleanup reconstruction passed **533 = 495 + 38** tests. The current
process-lifecycle extension passed **537 = 495 + 42** tests. Seven partition
integrity tests bring the final isolated complete fresh suite to **544 = 495 + 49**,
with all published baseline tests retained. These 49 reconstructed TGA tests
are unrelated to the lost 49 PNM-file tests. The lost
combined tree's reported **582** consisted of **495 baseline + 49 PNM-file +
3 CI + 35 TGA** tests. The lost 49 PNM-file and three CI tests belonged to separate
then-unpublished work; they are not silently counted as present in this TGA-only
branch. Their obligation mapping and integration require separate verification.
Additional test counts below must be derived from fresh executions, not inferred
from historical totals. A larger count alone establishes no coverage equivalence.

All published test, fixture, probe and workflow files are retained unchanged in
this branch. The source review receipt records their baseline hashes. New
TGA tests and probes are additive. Existing gates still run with their original
fixtures, comparisons and thresholds; the compiler/toolchain pins and overlay
are unchanged.

## Obligation-to-evidence matrix

In this table, short `test_*` names refer to
[`tests/test_tga_format_harness.py`](../tests/test_tga_format_harness.py).
`focused` means the fresh `tools/tga_format_probe.py` run, whose durable report
is [tga-formatted-rebuilt.json](evidence/tga-formatted-rebuilt.json). Fresh focused, canonical and required legacy runtime gates now pass on the
isolated d3-based source. The focused and canonical records are independently
replayed in full. Formatted TGA export also receives independent complete
output/file/IO replay and seal verification. The four older Surface TGA, generic
memory/file and FloatRGB runners do not retain raw result stdout; their review
is explicitly limited to source/report/exit/manifest evidence. Any
combined integration requires fresh verification against its own source hashes.

| Obligation | New source test / fixture / probe | Fresh receipt or acceptance gate |
|---|---|---|
| Native output channels distinguish direct depth/type and indexed palette depth | `test_gray_alpha_ramps_and_identical16_semantic_discriminators`, `test_palette_depth_independent_of_index_width_and_orientation`; all direct legacy type/depth cases and both index widths under all palette depths | Native qualification plus every `raw` record's actual format and byte count; formats 1/2/4/7 |
| Actual native metadata and bytes precede normalization | `test_native_actual_raw_precedes_normalization_and_alias_reload`; real `LoadImageFromMemory` followed by raw observation, then `ImageFormat(...,7)` | Focused native `reference.stdout` and parsed raw/normalized records; no Python pixel oracle |
| Gray, gray-alpha, RGB and RGBA bytes remain exact | `test_complete_raw_gray_rgb_and_normalized`, `test_gray_alpha_and_rgba_complete_raw_payload`; full gray/alpha and independent-color ramps | Every raw/factory/owner byte compared on CPU-1, CPU-2 and JavaScript |
| RGB555 integer expansion, ignored high bit and retained zero alpha | All historical packed 15/16-bit streams plus identical-payload direct16 discriminator and alpha ramps | Raw native RGB or gray-alpha output plus normalized Surface/bridge regressions |
| Native output ignores irrelevant direct color-map header fields | Explicit direct-image fixture with map selector zero and nonzero unused palette fields | Native raw channel count and complete bytes, including factory/owner/Surface observations |
| Palette byte-skip and entry-zero fallback | Legacy skip/fallback/257-entry palette streams plus all new palette depth/index-width/orientation/RLE combinations | Focused complete native raw and normalized bytes |
| Vertical orientation, ignored horizontal/attribute bits, IDs and tails | `test_palette_depth_independent_of_index_width_and_orientation`, `test_packet_limits_cross_rows_and_complete_tails`; legacy descriptors and new maximal-ID/tail cases | Focused native comparisons of nonuniform full images |
| Raw/repeat packet limits and cross-row stepping | `test_packet_limits_cross_rows_and_complete_tails`; 127/128/129 logical pixels in all four layouts plus historical mixed packets | Complete raw and normalized comparisons, not checksums |
| 1x1, padded storage, axis limits and larger nonuniform shapes | `test_four_layouts_all_allocation_shapes_nonuniform`; all layouts at 1x1, 3x5, 4096x1, 1x4096 and 81x63 | Complete logical output bytes with no storage padding; maximum-area allocation remains unqualified |
| Affine ownership, rejected point reads and zero high bits | `test_candidate_ownership_high_bits_factory_error_routes_and_no_pixel_oracle`; first/last, width/height and U32-max reads, all logical words checked | Exact retained-owner bytes after the read chain, factory export and consuming bridge |
| Existing Surface semantics and supported aliases remain unchanged | Surface roles for every accepted fixture, selected `.tga`/`.TGA` and `_for` observations; all 64 historical accepted streams preserved | Focused normalized comparisons plus unchanged Surface TGA and generic dispatch probes |
| Checked malformed inputs never reach native | `test_controls_checked_only_and_explicit_error_precedence`, `test_complete_stream_safety_checks_every_header_palette_and_packet`, `validate_controls` | Independent complete-stream admission rejects every control; controls run only through candidate formatted/Surface APIs |
| Byte-error precedence includes ignored bytes and indexed samples | Explicit bad-byte controls for header, ID, palette, palette-skip bytes, direct/indexed samples, RLE and trailing bytes | Both candidate entrypoint error records, exact typed error codes |
| Header/size/truncation/packet-overrun distinctions | Prefix, invalid selector/depth, zero/4097/65535 axis, truncated ID/palette/sample/packet, overrun-before-truncation controls | Exact error-record identity, role and type; no native rejection claim |
| Strict complete observation framing | `test_exact_metadata_fields_types_and_order`, `test_bad_framing_empty_missing_extra_and_byte_types`, `test_chunk_boundaries_and_partial_chunk_rejection`, duplicate/nonfinite JSON controls | Exact schema, types, case order, bounded chunks, end marker and expected total length; all differing bytes retained |
| Native fixture safety and metadata are independently checked | `test_native_case_safety_fails_closed_and_checks_declarations`; bounded complete palette/raster/packet parser | Safety admission before native source generation; declared channels/dimensions rechecked |
| Fresh native TGA build is explicit and qualified | `test_native_build_explicit_tga_and_configuration_checked_before_execution`, `test_native_build_refuses_preexisting_directory`, configuration/qualification tests | New isolated archive; cache and actual TGA/Memory/external-config definitions, compiler identity and tiny native channel discriminators |
| Parent loader environment is unchanged | `test_loader_clean_children_parent_unchanged_and_receipt_checked` | Clean-loader receipts for native build/reference children; receipt rechecked after the run |
| Compile partitions preserve the entire ordered workload | Deterministic max-action/generated-source planner with nonempty, contiguous, exhaustive, identity/order and budget-boundary tests | Every planned action appears exactly once, all lane batches match the plan, and complete byte totals stay unchanged; only compile grouping changes |
| Missing outputs, stale reports, source drift and partial lanes fail closed | `test_stale_compiler_output_cannot_be_reused`, stale-report/duplicate-destination tests, seal tests, mandatory-lane tests | Fresh output files, pinned sources/tool resolution, all required contiguous complete lane batches and final seal verification |
| Failure artifacts and timeout cleanup are durable and bounded | Startup/nonzero/timeout/failed-output tests plus real harmless descendant-termination tests for the new process-group cleanup | Stdout/stderr/command/output hashes retained on failure; only the newly started group is killed and reaped |
| Structural proof obligations are retained | `LAWS.bend` / `PROOF.bend`: 132 baseline laws plus 16 metadata/packing/empty-traversal facts | Full pinned CLI verdict `All terms check.`; not a universal codec theorem |
| Published canonical behavior stays intact | Unchanged `tools/conformance.py`, contracts/transforms/decoding and examples | Fresh CPU-1/CPU-2/JavaScript canonical run plus strict complete-record replay of all words, QOI bytes and palette words |
| Existing file/export integration remains intact | Unchanged `tga_probe.py`, `image_memory_probe.py`, `image_file_probe.py`, `formatted_tga_export_probe.py`, `float_rgb_raster_export_probe.py` | Serial fresh complete-byte, owner, error and low-descriptor regression receipts; no new formatted-file claim |
| Scope/status/provenance changes are honest | API ledger build/check, source review, this matrix and new evidence report | Only `LoadImageFromMemory` remains partial with expanded TGA scope; PNM-file gap retained until its independent merge; no workflow or complete-API claims |

## Unavailable history and remaining limits

The exact lost TGA source, its 35 individual test implementations, complete
fixture bytes and all runtime hashes cannot be proven identical. Its known
contract obligations are checked anew above. The reconstructed corpus is
intentionally reported by fresh derived counts, including new maximal-ID/tail
fixtures; matching an old total is not a validation goal. A direct-image
unused-palette discriminator and invalid-byte controls for palette-skip/index
positions were explicitly restored when the obligation review found those gaps.

The isolated branch does not claim recovery of the lost PNM-file or CI test files. Their
separate reconstruction/review must establish coverage before integration.
Published baseline gates remain intact. Generic formatted dispatch, formatted
TGA file IO, unrun GPU/Metal/Windows/browser/hosted lanes, native allocation/OOM
ABI, maximum-area resources and representative performance remain open.

## Fresh first-attempt compiler failure and partition repair

The first fresh focused attempt completed 19 batches, **608 ordered observations
per lane**, before compiler batch 19 (zero-based) exited **-9** with empty stdout
and stderr. Its generated Bend source was **406,854 bytes**. Host memory had
been observed around 8.3/9.7 GiB and returned to about 1.0 GiB after termination;
the cause is not proven as OOM. There was no timeout or comparison mismatch.
The owned process group was already gone and its leader was reaped. The report
remained failed, preserving all partial outputs and receipts; the independent
reviewer verified all **868 seals** and the preceding complete records.

The repair changes compilation partitions only. It preserves the **169 accepted
images, 155 checked-only controls, 1,311 ordered candidate actions and 1,024,632
compared bytes per lane**, the native oracle, every role, toolchain, input-domain
limits and 600-second work timeout. A conservative generated-source budget
bounds each compilation while keeping the existing action-count ceiling.
Partition integrity was independently tested and reviewed. The strict source
cap is **196,608 bytes**, with at most **32 actions** per compilation. The
qualified retained input produces **43 partitions**, at most **185,894 generated
bytes**, preserving the full action-content digest. All former batches 0–19
regenerate byte-identically before regrouping. Fresh full focused
verification must restart from a new native build; replaying only the failed
batch cannot close this gate. The original failed run remains a separate,
bounded portable receipt archive with its exact reviewed source snapshot.
