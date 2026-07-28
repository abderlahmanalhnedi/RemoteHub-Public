# Reviewed FreeRDP Payload Contract

RemoteHub release builds expect an externally produced and maintainer-reviewed
payload. Third-party binaries are intentionally ignored by Git until the
license inventory, architecture report, dependency closure, and maintainer
review are complete.

The pinned candidate is FreeRDP 3.30.0, upstream commit
`6b107f0aadbabc47941c5a5b893b88c01792af6d`, built as the native SDL3 client
for macOS 14 or newer. The release review must decide whether one universal
payload or two architecture-specific payloads will ship. The default
RemoteHub Release configuration expects every Mach-O file to contain both
`arm64` and `x86_64`; separate releases can override `ARCHS` and
`REMOTEHUB_FREERDP_PAYLOAD_DIR`.

## Required input layout

```text
payload/
├── Helpers/
│   └── sdl-freerdp
├── Frameworks/
│   ├── libfreerdp3.dylib
│   ├── libfreerdp-client3.dylib
│   ├── libwinpr3.dylib
│   └── every non-system dependency discovered by otool -L
├── manifest.json
├── SHA256SUMS
└── THIRD-PARTY-NOTICES.md
```

`SHA256SUMS` must cover every file copied into the app except itself.
`manifest.json` must record exact source tags/commits, build flags,
architectures, deployment target, compiler/SDK versions, every output file,
and its license.

Run:

```bash
Scripts/verify-freerdp-payload.sh /reviewed/payload arm64 x86_64
```

The verifier rejects missing checksums, missing architectures, non-Mach-O
files in the binary closure, absolute non-system dependency paths, missing
`@rpath` libraries, and a helper without
`@loader_path/../Frameworks`.

For an Xcode Release build, either place the reviewed payload at
`Vendor/FreeRDP/payload` (ignored by Git) or set
`REMOTEHUB_FREERDP_PAYLOAD_DIR`. Debug builds remain usable without the
payload and retain PATH discovery strictly for development compatibility.

## Proposed minimized build

Start from the upstream macOS bundle recipe, but pin every source by immutable
commit and disable unused features. Build SDL3 only; disable X11, SDL2,
servers, samples, tests, manpages, SDL image dialogs, USB redirection,
smartcards, printers, PKCS#11, FDK AAC, FFmpeg, and debug credential logging.
Keep OpenSSL, zlib, SDL3, SDL3_ttf, FreeType, HarfBuzz, uriparser, Opus, and a
maintainer-approved H.264 implementation only if the resulting feature and
license review requires them.

Do not accept upstream's moving OpenH264 `master` reference as a reproducible
input. The final manifest and notices must be generated from the actual
`otool -L` closure and static-link map, not from this proposed list.
