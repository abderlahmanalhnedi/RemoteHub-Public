# Product Overview

## Purpose

RemoteHub is a native macOS connection manager for keeping reusable connection
and credential profiles in one local workspace. It addresses the repeated,
error-prone work of remembering endpoint settings, selecting credentials,
checking SSH host identity, opening terminals, transferring files, and
launching an external remote-desktop client.

The intended users are developers, administrators, support engineers, and
technical users who manage multiple remote systems from a Mac. RemoteHub is
currently a development-stage project, not an audited enterprise product or a
published App Store release.

## Platform

- The application target is configured for macOS 14 or newer in
  [`project.yml`](../../project.yml).
- Citadel 0.12.1 exposes its interactive PTY API only on macOS 15 or newer, so
  interactive SSH terminals require macOS 15. SFTP-only connections remain
  available to the macOS 14 target.
- The recorded public-release validation is on Apple Silicon (`arm64`). An
  Intel build is not part of the recorded results.
- A full Xcode installation is required to compile the native application and
  SwiftData models.

## Supported protocols

| Protocol | Implemented behavior | Current verification boundary |
| --- | --- | --- |
| SSH | Password and supported private-key authentication, preflight key scan, exact negotiated-key validation, TOFU decisions, interactive SwiftTerm PTY, resize, cancellation, disconnect, and optional SFTP panel | Automated tests plus a sanitized live password/PTY/host-key run |
| SFTP | Citadel session, directory operations, streaming upload/download, permissions, and shared transfer browser | Implemented but not live-tested |
| FTP | System curl adapter, passive or active mode, listing parsers, file operations, and mandatory plain-FTP warning acknowledgement | Automated tests only |
| FTPS | Explicit and implicit modes with certificate verification enabled by default | Automated tests only |
| RDP | Bundle-first SDL FreeRDP discovery, DNS/TCP preflight, typed arguments, stdin-only password input, captured diagnostics, and lifecycle controls | Automated tests only; reviewed binary payload and live endpoint run pending |

Current release-preparation validation is summarized in the
[public release audit](../../PUBLIC_RELEASE_AUDIT.md). “Automated tests only”
does not establish compatibility with a particular server.

## Main features

- Dashboard, favorites, recent connections, protocol counts, and failed-attempt
  indicators.
- Searchable connection library with groups, tags, notes, sorting, duplication,
  and favorites.
- Reusable credential profiles with Keychain-backed passwords and SSH key
  passphrases.
- SSH workspace tabs with an interactive terminal and optional SFTP browser.
- Shared SFTP/FTP/FTPS file browser and bounded transfer queue.
- Bundled FreeRDP preflight and lifecycle tracking.
- Versioned JSON import/export that excludes secrets.
- Sanitized error details and copyable diagnostics.
- Native keyboard commands and a tested macOS text-input responder chain.

Primary feature sources include
[`DashboardView.swift`](../../RemoteHub/Features/Dashboard/DashboardView.swift),
[`ConnectionLibraryView.swift`](../../RemoteHub/Features/Connections/ConnectionLibraryView.swift),
[`CredentialEditorView.swift`](../../RemoteHub/Features/Credentials/CredentialEditorView.swift),
[`WorkspaceView.swift`](../../RemoteHub/Features/Workspace/WorkspaceView.swift),
and
[`ConnectionConnector.swift`](../../RemoteHub/Features/Workspace/ConnectionConnector.swift).

## Local-first design

RemoteHub does not require a RemoteHub cloud account. The reviewed source
contains no application telemetry client or application-managed cloud sync.
Connection metadata is stored locally with SwiftData, preferences use
`UserDefaults`, and saved passwords/passphrases use non-synchronizing macOS
Keychain items. The application still communicates with user-configured remote
endpoints, and its build resolves third-party packages from their upstream
repositories.

See the [security overview](../security/security-overview.md) for the precise
storage boundaries and limitations.

## Distribution status

The repository builds a native `RemoteHub.app` with bundle identifier
`com.alhnedi.RemoteHub` and configured version `1.0` (build `1`). The current
target requests Hardened Runtime, but Xcode disables it for the local ad-hoc
development signing path. No verified Hardened Runtime distribution, notarized
package, App Sandbox entitlement, App Store submission, release installer, or
supported automatic-update channel exists. The configured version therefore
must not be interpreted as proof of a formal release.

## Implemented versus verified

“Implemented” means a code path exists and compiles. “Verified” means the
specific behavior has evidence from the recorded automated or manual run.

| Subject | Implemented | Verified |
| --- | --- | --- |
| Native app launch and keyboard input | Yes | Native UI test passed on retry; an initial window-detection failure is recorded |
| Credential secret separation | Yes | Unit tests cover lifecycle, model boundary, export, diagnostics, and process arguments |
| SSH password terminal | Yes | Verified against one sanitized live endpoint |
| SSH exact negotiated host key | Yes | Unit tests and one sanitized live ED25519 negotiation |
| SSH private-key variants | Yes for supported Ed25519/RSA parsing paths | Automated compilation/tests do not constitute a complete live matrix |
| SFTP operations | Yes | No live endpoint evidence |
| FTP/FTPS operations | Yes | Parser and argument/security tests; no live endpoint evidence |
| RDP launch | Yes, through the bundle-first SDL FreeRDP adapter | Automated discovery, preflight, argument, lifecycle, and error-mapping tests; no compatible endpoint evidence |
| Import/export | Yes | Round-trip, schema, duplicate-policy, and redaction tests |

## Current limitations

Material limitations include:

- no App Sandbox, notarization, or distribution signing;
- interactive SSH requires macOS 15 or newer;
- no SSH-agent integration or promised keyboard-interactive MFA;
- modeled keepalive, bounded automatic reconnect, jump-host, and
  legacy-algorithm settings are not active;
- remote browsing lacks back/forward history, drag-and-drop, and per-column
  sorting;
- curl transfer progress is completion-oriented rather than continuous; and
- live interoperability evidence is incomplete outside the recorded SSH run.

The maintained detailed register is
[`known-limitations.md`](../known-limitations.md).

## Out of scope

The current implementation does not claim:

- embedded RDP rendering;
- VNC, Telnet, or SCP support;
- cloud synchronization or encrypted secret backup;
- FTPS client-certificate authentication;
- in-process RDP rendering;
- certification, regulatory compliance, availability guarantees, or universal
  server compatibility; or
- production release management.

## Evidence

- [`Package.swift`](../../Package.swift)
- [`project.yml`](../../project.yml)
- [`ConnectionTypes.swift`](../../RemoteHub/Domain/Models/ConnectionTypes.swift)
- [`ConnectionConnector.swift`](../../RemoteHub/Features/Workspace/ConnectionConnector.swift)
- [`CitadelSSHTransport.swift`](../../RemoteHub/Infrastructure/SSH/CitadelSSHTransport.swift)
- [`CitadelSFTPSession.swift`](../../RemoteHub/Infrastructure/SFTP/CitadelSFTPSession.swift)
- [`CurlCLIFTPClient.swift`](../../RemoteHub/Infrastructure/FTP/CurlCLIFTPClient.swift)
- [`FreeRDPLauncher.swift`](../../RemoteHub/Infrastructure/RDP/FreeRDPLauncher.swift)
- [`PUBLIC_RELEASE_AUDIT.md`](../../PUBLIC_RELEASE_AUDIT.md)
