# RemoteHub User Guide

This manual describes the current RemoteHub source tree. Source review and
automated tests do not turn an untested protocol into a live-verified one.

Start with [Getting Started](getting-started.md). It is the first-use
walkthrough for building the application, creating a credential and SSH
profile, verifying the host key, and opening a terminal.

## How to use this manual

1. Complete [Getting Started](getting-started.md) with an authorized,
   non-production endpoint.
2. Use the task-specific chapter in the guide map.
3. Check that chapter's limitations and the
   [verification boundary](#verification-boundary) before relying on a
   protocol workflow.
4. Use [Troubleshooting](troubleshooting.md) for recovery, and review copied
   diagnostics before sharing them.

## Guide map

| Task | Guide |
| --- | --- |
| Understand favorites, recent activity, counters, and failures | [Dashboard](dashboard.md) |
| Create, organize, find, and open connection profiles | [Connections](connections.md) |
| Manage reusable credential metadata and Keychain secrets | [Credentials](credentials.md) |
| Use tabs, SSH terminals, SFTP panels, and RDP process controls | [Workspace](workspace.md) |
| Browse files and manage SFTP, FTP, and FTPS transfers | [File transfers](file-transfers.md) |
| Configure appearance, terminals, transfers, RDP, and security | [Settings](settings.md) |
| Move version-one connection metadata between installations | [Import and export](import-export.md) |
| Diagnose common build, credential, connection, and UI problems | [Troubleshooting](troubleshooting.md) |

Supporting references:

- [Product overview](../product/overview.md)
- [Known limitations](../known-limitations.md)
- [Import and export format](../import-export-format.md)
- [Security overview](../security/security-overview.md)

## Security baseline

RemoteHub is local-first, but local does not mean non-sensitive.

- Connection names, hosts, ports, groups, tags, notes, usernames, private-key
  paths, and trusted-host fingerprints are metadata. They are stored locally
  and can still disclose infrastructure or operational information.
- Saved passwords and SSH key passphrases are separate, non-synchronizing
  macOS Keychain items. They are not stored in the SwiftData credential model.
- SSH host keys and FTPS certificates must be verified. Do not bypass a
  warning merely to make a connection succeed.
- Export files exclude secrets but can contain sensitive connection metadata.
  Protect them according to the systems they describe.
- Error diagnostics are sanitized for common credential-bearing URLs and
  password assignments. Review copied diagnostics before sharing them.

The current target requests Hardened Runtime, but Xcode disables it for the
local ad-hoc development signing path. It is not App-Sandboxed, notarized, or
distributed as a supported release. See
[Known limitations](../known-limitations.md) before using it with sensitive
systems.

## Keyboard commands

| Command | Result |
| --- | --- |
| Command-N | Open the New Connection editor |
| Command-K | Focus connection search |
| Command-R | Reconnect the active SSH/RDP tab or refresh the active file tab |
| Command-Shift-F | Toggle the remote-files panel for the active SSH tab |
| Command-W | Close the active workspace tab and initiate disconnect |
| Command-, | Open Settings |

The shortcuts require the Command modifier. Normal `n`, `k`, `r`, and `w`
keystrokes remain text input while an editable field is focused.

## Verification boundary

| Area | Current evidence |
| --- | --- |
| Native app and text entry | Build and automated UI evidence; the recorded UI test passed on immediate retry |
| SSH password, negotiated host key, and PTY | Automated coverage plus one sanitized authorized live endpoint |
| SFTP | Implemented; no recorded live endpoint operation |
| FTP and FTPS | Parser, argument, and security tests; no recorded live endpoint operation |
| RDP | Argument and password-isolation tests; no recorded compatible endpoint session |
| Import and export | Automated round-trip, schema, duplicate-policy, and secret-exclusion evidence |

## Evidence

The manual is based on the user-facing views under
[`RemoteHub/Features`](../../RemoteHub/Features), the application commands in
[`AppCommands.swift`](../../RemoteHub/App/AppCommands.swift), the persisted
models and settings, and the documented verification record. Each chapter
links to its principal implementation sources.
