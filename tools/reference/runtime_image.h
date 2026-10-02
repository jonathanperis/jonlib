#ifndef JONLIB_RUNTIME_IMAGE_H
#define JONLIB_RUNTIME_IMAGE_H
#include <stdio.h>
/* Darwin only. The caller must independently establish that the actual
 * volatile function pointer equals dlsym(RTLD_DEFAULT, expected_symbol).
 * Returns 1 on success, 0 on unsupported/invalid/unverifiable provenance.
 * Collects and validates before writing: an identity failure writes nothing.
 * An output-stream error can of course leave a partial JSON object.
 * No newline is written. Does not change floating-point control state.
 * The JSON observations object is process-local; all other fields are stable
 * across ASLR for the same mapped code/file/cache. Non-Darwin returns 0. */
int jon_runtime_image_write_json(FILE *out, const void *function);
/* Captures the exact supported DYLD environment keys; no normalization or
 * environment mutation. Returns 1 unless out is null, UTF-8 is invalid, or a stream error occurs. */
int jon_runtime_loader_write_json(FILE *out);
#endif
