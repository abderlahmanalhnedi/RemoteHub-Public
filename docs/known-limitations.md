# Known Limitations

- FreeRDP renders in its own native SDL window rather than inside a RemoteHub view.
- The source tree intentionally excludes the reviewed FreeRDP binary payload; distributable release builds remain blocked until license inventory and maintainer review are complete.
- RDP has automated integration coverage but no recorded live endpoint interoperability run.
- SSH keyboard-interactive MFA is not promised in version one.
- Dragging remote files directly to Finder is omitted unless a reliable file-promise path is available; explicit Download is supported.
- Client certificates for FTPS, VNC, Telnet, SCP, cloud sync, and encrypted secret backups are out of scope.
- The target requests Hardened Runtime, but Xcode disables it for the local
  ad-hoc development signing path. Builds are not App-Sandboxed or notarized.
  See
  [Security overview](security/security-overview.md).
- Live protocol compatibility varies by server. One sanitized SSH password/host-key/PTY path has been verified against a live endpoint; SFTP, FTP, FTPS, and RDP still lack live endpoint evidence. Automated fakes and parser/argument/security tests do not replace the outstanding manual matrix.
- Full app and XCTest compilation also require full Xcode because Command Line Tools omit `SwiftDataMacros`.
- Citadel 0.12.1 exposes its PTY API only on macOS 15+, so interactive SSH reports a clear requirement on macOS 14; SFTP-only profiles remain targeted at macOS 14.
- SSH keepalive, automatic bounded reconnect, jump hosts, and legacy-algorithm overrides are modeled but not active. RemoteHub does not reconnect forever or silently enable deprecated algorithms.
- The remote browser currently provides path entry, Up, refresh, hidden files, mkdir, recursive upload/download, rename, delete, and SFTP chmod. Back/forward history, drag-and-drop, and per-column sorting are not complete.
- “Ask” overwrite mode is fail-safe: it blocks the conflict and directs the user to select Replace, Skip, or Keep Both. A per-item inline choice is not yet implemented.
- Citadel SFTP streams chunks and reports progress. The curl CLI adapter reports completion totals; continuous curl speed/progress and guaranteed immediate helper-process cancellation remain follow-ups.

These limitations reflect the current source tree. A limitation should not be
removed solely because the code compiles or an isolated automated test passes.
