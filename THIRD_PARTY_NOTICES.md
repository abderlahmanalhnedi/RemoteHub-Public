# Third-Party Notices

## SwiftTerm 1.14.0

Copyright its contributors. Licensed under the MIT License.
Source: https://github.com/migueldeicaza/SwiftTerm

## Citadel 0.12.1

Copyright © 2022 Orlandos and contributors. Licensed under the MIT License.
Source: https://github.com/orlandos-nl/Citadel

## SwiftNIO 2.83.0

Copyright Apple Inc. and the SwiftNIO project authors. Licensed under Apache License 2.0.
Source: https://github.com/apple/swift-nio

## SwiftNIO SSH fork 0.3.4

Copyright Apple Inc. and project contributors. Licensed under Apache License 2.0.
Source: https://github.com/Wellz26/swift-nio-ssh

## Swift Crypto 3.12.3

Copyright Apple Inc. and the Swift Crypto project authors. Licensed under Apache License 2.0.
Source: https://github.com/apple/swift-crypto

## Swift Collections 1.2.1

Copyright Apple Inc. and project contributors. Licensed under Apache License 2.0.
Source: https://github.com/apple/swift-collections

Citadel also resolves Swift Log, Swift Atomics, Swift System, Swift ASN.1, BigInt, and related packages under permissive licenses. Exact versions and revisions are recorded in `Package.resolved`.

## System curl

RemoteHub invokes the curl executable supplied by macOS. It is not
redistributed by this repository.

## Reviewed FreeRDP payload

No FreeRDP binary is currently committed or redistributed from this source
tree. RemoteHub's release packaging contract is prepared for FreeRDP 3.30.0
(including WinPR and the SDL3 client), licensed under Apache License 2.0:
https://github.com/FreeRDP/FreeRDP/tree/3.30.0

The proposed minimized native macOS payload has the following license
inventory. Versions/commits and inclusion remain subject to the binary
dependency-closure and maintainer review described in
`Packaging/FreeRDP/README.md`.

| Candidate component | Proposed version | License |
| --- | --- | --- |
| FreeRDP, WinPR, and SDL FreeRDP client | 3.30.0 | Apache-2.0 |
| OpenSSL | 3.6.0 | Apache-2.0 |
| zlib | 1.3.1.2 | Zlib |
| SDL | 3.2.28 | Zlib |
| SDL_ttf | 3.2.2 | Zlib |
| FreeType | SDL_ttf pinned commit `9973564cfa63763a3e4ac67c09147899539b1e07` | FreeType License |
| HarfBuzz | SDL_ttf pinned commit `564bf9818a18709776856533829c0c04950773d6` | Old MIT |
| uriparser | 1.0.2 | BSD-3-Clause |
| Opus | 1.6 candidate | BSD-3-Clause |

H.264 support is intentionally unresolved. OpenH264 and FFmpeg are not
approved for redistribution until maintainers choose an implementation and
review its license, patent, source-pinning, and runtime-dependency impact.
The upstream macOS script's moving OpenH264 `master` reference is not an
acceptable deterministic release input.

The reviewed payload must include its own complete
`THIRD-PARTY-NOTICES.md`, including full required attribution/license text
for every dynamically or statically linked dependency. The build copies that
reviewed document into `RemoteHub.app/Contents/Resources`.
