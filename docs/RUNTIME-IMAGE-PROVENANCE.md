# Native angle runtime-image provenance

The angle qualifier and modern source harness share an explicit Darwin Mach-O
backend. This removes the assumption that every `dladdr` path is an ordinary
file. It does not select a numerical reference from macOS, change any numeric
control, or turn an unsupported context into a successful qualification.

## Public API basis

Apple documents that `dladdr` identifies an address's loaded Mach-O header and
that cache-incorporated dylibs may be removed from disk. Its public
`_dyld_shared_cache_contains_path` API checks the active cache, with macOS 11
availability. See [Apple dyld.h](https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/dyld.h).

The task's 64-bit `TASK_DYLD_INFO` record supplies the address and size of
`dyld_all_image_infos`. The implementation requires version 15 or newer and
sufficient reported bytes through `sharedCacheBaseAddress`, then reads the active
cache UUID, slide and base. `uuidArray` is deliberately not used: Apple excludes
cache images from that array. See [task_info.h](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/task_info.h)
and [dyld_images.h](https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/dyld_images.h).

The parser independently implements the published [Mach-O64 layout](https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h).
It does not embed Apple implementation source. Read-only Mach VM calls copy
bounded process ranges into owned buffers, after checking leaf-region
protections; the checks also run after copying. See
[mach_vm.defs](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/mach_vm.defs)
and [vm_region.h](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_region.h).
The owned code copies are hashed with system `CC_SHA256_Init/Update/Final`;
Apple's [CommonDigest.h](https://github.com/apple-oss-distributions/CommonCrypto/blob/main/include/CommonDigest.h)
records availability from macOS 10.4 and libSystem linkage. No additional
crypto dependency, credentials, private dyld SPI or security-setting change is
required. Darwin compilation/linkage still needs verification on an actual SDK.

## Explicit profiles and bounds

`tools/reference/runtime_image_macho.c` accepts only little-endian Mach-O64,
x86-64 or AArch64 with recognized CPU subtype, one nonzero `LC_UUID`, one
`__TEXT` segment and one nonempty `__TEXT,__text` section. Load commands are
limited to 1 MiB/4,096 commands and code to 256 MiB. Counts, lengths, alignment,
integer overflow, segment/section containment and ambiguous overlaps are checked
without dereferencing any address encoded in the input. Writable text,
unsupported formats, missing UUIDs and ambiguous layouts reject.

`tools/reference/runtime_image.c` binds the actual function address to its
`dladdr` image. The symbol must lie within the hashed code section. Both declared
segment protections and observed VM protections must be read/execute and exclude
write, including maximum write permission. Code/header reads use
`mach_vm_read_overwrite`, not unchecked pointer loads. Header bytes, image/path
binding and file/cache identity are checked again after hashing. This is a
bounded provenance snapshot, not synchronization against hostile concurrent
mapping changes or arbitrary in-process attackers.

- `darwin-macho-shared-cache-v1`: requires the loaded header's cache flag,
  affirmative public active-cache path membership, a nonzero active cache UUID,
  image/code addresses at or above the active cache base, and an observed cache
  slide that reconstructs the loaded header address from its unslid VM address
- `darwin-macho-file-v1`: requires both cache observations to be false, an
  ordinary readable file, resolved path and stable stat identity; Python adds
  its full-file SHA-256 and checks stat again after reading

Both profiles retain Mach-O UUID, CPU identity, code section/unslid VM address,
size, actual symbol offset and mapped-code SHA-256. File hashes are additional
identity; they never replace loaded code. A cache profile has explicit null
file-only fields, never a null code digest. Active cache UUID and image UUID have
separate meanings. OS version/build is contextual evidence, not image identity.

Only `observations.image_base`, `text_address` and `symbol_address` are stripped
for cross-process comparison under ASLR. Within one process they must also agree
between initial and final metadata. Any code/UUID/cache/fenv/loader drift rejects.

## Integration and preservation

The angle qualifier links a separate Darwin metadata translation unit. Its Linux
metadata translation unit remains byte-identical. Linux continues to require its
actual glibc version, path/realpath, stat, full file hash, loaded/file GNU build-ID
agreement and successful package inventory with its existing explicit
non-membership policy. Darwin does not use that Linux package backend.

All five angle processes still run fresh, compare their initial/final state and
share one stable runtime identity. Exactly one frozen numerical signature must
match. All 76 scalar controls, 205 wrapper controls, 1,654 intermediate words,
expected outputs, original canonical generated C and numerical compiler flags
are unchanged. The additions do not authorize a default Apple selection.

The modern harness observes both actual `atan2f` and `fma` pointers, including
pointer equality to `dlsym(RTLD_DEFAULT, ...)`. Its initial/final metadata carries
the same image schema, loader observations and x87 controls where applicable.
After candidate work the original hash-checked native executable is rerun with
`--qualify`; this freshly rechecks cache-backed code instead of reopening a
potentially nonexistent dylib. Fresh recheck records and command/stdout/stderr
artifacts are retained. Existing arithmetic, FMA, narrowing, gradual-underflow,
control masks, source corpus and exact comparisons remain unchanged.

Both native paths retain compiler identity, the observed OS build, xcrun-selected
SDK path/version/settings digest and the compiler's diagnostic invocation. The
xcrun-selected SDK is labeled as such, rather than guessed to be the actual
compiler sysroot. New source dependencies are hashed and checked for drift;
the six new metadata dependency pins were added after independent review.
Every preexisting manifest field and source pin remains identical. The enclosing
manifest digest is `a08d1448072694532e24945bf32558b8d7f7b07c87571f5952cab6fa76126cd6`.

## Verification boundary

The implementation was developed in an isolated Linux checkout based on
`c8644240429c0c559ff33f4afd7d0f0565474dd5`, then integrated and freshly verified
against the formatted-TGA checkpoint
`4e014c9e1fc93e199f1a3e92ea00659dd9b4920f`. No Darwin SDK, Darwin runtime or GPU
run occurred in this environment. Linux/synthetic tests cannot establish a
macOS qualification pass; the exact published revision must pass GitHub Actions
on the real macOS runner before that claim is made.

Local verification after independent metadata review (see the
[compact retained record](evidence/darwin-runtime-provenance.json)):

- 406 Python tests pass, including existing fail-closed/stale-receipt tests and
  15 new synthetic Darwin parser/schema/protocol tests
- Native Linux qualification uniquely selects `Glibc241AngleRn`; all frozen
  scalar/wrapper/intermediate controls pass
- The native-only modern harness verifies 8,317 observations, with zero
  pinned/native differences; unchanged private arithmetic candidate gates were
  not rerun
- All 105 proof definitions check. Complete canonical comparison passes 261
  scenarios across CPU-1, CPU-2 and JavaScript, including a separate typed
  all-field comparison of every retained record and trailing contracts/examples
- The portable parser passes strict C11 warnings, 20,000 deterministic malformed
  mutations and AddressSanitizer/UndefinedBehaviorSanitizer; LeakSanitizer is
  unavailable under the container's ptrace environment

Synthetic cases include cache-only paths, ordinary files, missing/duplicate/zero
UUIDs, invalid command sizes/counts, section bounds, wrong architecture,
permissions, absent cache membership/UUID, code drift, ASLR, mixed contexts,
fenv failures, stale executables and numerical mismatch. They are protocol tests,
not fabricated Apple numerical or host evidence. No workflow, Bend source,
fixture, public API status or historical evidence receipt is changed here.
