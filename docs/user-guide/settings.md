# Settings

Select **Settings** in the sidebar, use the toolbar gear, or press Command-,.
Preferences are stored in local `UserDefaults` unless this chapter identifies
a different storage boundary.

## Change a setting

1. Open **Settings** from the sidebar, toolbar, or Command-,.
2. Select General, Terminal, File Transfers, RDP, Security, Diagnostics,
   Import / Export, or About.
3. Change the required control. Preferences apply through `UserDefaults`; the
   view has no separate Save button.
4. Recheck any security-sensitive exception, such as disabled FTPS
   verification, and restore the safe setting after an authorized temporary
   test.

## General

| Control | Default | Current behavior |
| --- | --- | --- |
| Appearance | System | Applies System, Light, or Dark color scheme to the main application |
| Confirm destructive actions | On | The preference is stored, but current destructive workflows do not consult it; their confirmations remain present regardless of the toggle |
| Connections, Groups, Credentials | Current counts | Read-only library summary |

Because **Confirm destructive actions** is not active, do not interpret either
toggle position as a guarantee that every destructive action will or will not
prompt.

## Terminal

| Control or value | Current behavior |
| --- | --- |
| Font family | Applied to new and existing SwiftTerm views when they update; falls back to the system monospaced font if unavailable |
| Font size | Applied from 9 through 32 points |
| Terminal type | Informational `xterm-256color` label; the actual PTY terminal type is set per SSH connection |
| Scrollback | Informational `10,000 lines` label; the application source does not set a separate user-configurable scrollback value |

SwiftTerm supplies selection, copy/paste, Unicode, color rendering, and its
standard find behavior. Terminal behavior outside the recorded basic SSH run
still needs the manual input/control-key matrix.

## File Transfers

| Control | Default | Current behavior |
| --- | --- | --- |
| Overwrite behavior | Ask | Controls top-level upload conflicts found in the current remote listing |
| Concurrent transfers | 3 | Changes the queue limit immediately; range 1 through 8 |
| Show hidden files | Off | Filters remote names beginning with `.` from the visible table |

Ask mode is fail-safe: it blocks a conflicting upload and directs the user to
select Replace, Skip, or Keep Both. It does not yet open an inline per-item
decision. The overwrite preference does not replace the macOS Save Panel's
handling of download destinations.

See [File transfers](file-transfers.md) for conflict and cancellation details.

## RDP

RemoteHub release builds are designed to include a native SDL FreeRDP
executable and its runtime libraries. This source repository does not include
that payload; a distributable build requires the separate reviewed payload
described in [`Packaging/FreeRDP/README.md`](../../Packaging/FreeRDP/README.md).

### Executable discovery

The detector checks, in order:

1. `RemoteHub.app/Contents/Helpers/sdl-freerdp` (then the supported
   `Contents/MacOS` alternative);
2. an optional custom path under **RDP > Advanced**; and
3. common package-manager locations and `PATH` only in Debug builds.

It runs version/help inspection and reports:

- detected version and executable;
- whether the help output reports safe `from-stdin` password input;
- whether a development override uses an X11 executable;
- missing installation; or
- an incompatible custom executable and sanitized reason.

Use **Choose…** to set a custom executable and **Check Again** to rerun
detection. The custom path applies globally and remains lower priority than
the bundled helper.

### Password compatibility

RemoteHub never places an RDP password on the command line. The bundled client
receives it through standard input. There is no insecure fallback setting.

The **Advanced** disclosure also configures the short DNS/TCP preflight
timeout. The custom executable path is intended for development and support;
the bundled helper takes precedence.

## Security

### Keychain health check

**Run Keychain Health Check** creates a generated temporary value, reads it,
and removes it. The result reports whether the round trip succeeded. It does
not test an existing credential or remote authentication.

### Trusted SSH hosts

The list shows each stored:

- normalized host and ungrouped port;
- key algorithm; and
- SHA-256 fingerprint.

Records are scoped by host, port, and algorithm. A server that presents a new
additional algorithm is evaluated independently.

**Clear Trusted Host Keys** removes every saved record after confirmation.
There is no per-record removal control in the current Settings UI. The next
SSH connection to any cleared host will prompt again.

Clearing trust does not make a host safe and does not change the server. Verify
the next presented algorithm and fingerprint through an independent channel.

If the same host, port, and algorithm presents a different fingerprint,
RemoteHub blocks it. Replacement occurs only from the changed-key prompt:

1. verify the new key independently;
2. select **Review Replacement…**; and
3. explicitly select **I Verified It — Replace Key**.

Do not clear all records merely to bypass a changed-key warning.

### Secret storage statement

The Security section states that secrets use non-synchronizing, device-local
Keychain items available while the Mac is unlocked. See
[Credentials](credentials.md) for replacement and removal.

## Diagnostics

Settings has no telemetry, log-level, diagnostic-host inclusion, or automatic
support-upload preference. Its diagnostic actions are limited to the Keychain
health check and FreeRDP detection/status.

Connection and operation errors expose **Show Details** and **Copy
Diagnostics** in the workspace error banner. The copied block is sanitized but
must still be reviewed before sharing. See
[Troubleshooting](troubleshooting.md#copy-diagnostics).

## Import / Export

This section controls:

- optional inclusion of non-secret credential metadata;
- JSON export;
- duplicate policy: Skip, Replace, or Keep Both;
- JSON selection and validation; and
- the Import Preview.

Passwords, passphrases, private-key paths/content, Keychain data, and terminal
history are excluded. See [Import and export](import-export.md) before moving a
file.

## About

The About section displays:

- application version `1.0.0`;
- bundle identifier `com.alhnedi.RemoteHub`;
- platform label `Native macOS 14+`;
- MIT license;
- principal dependency versions and licenses; and
- the no-cloud-account/analytics/telemetry/subscription statement.

The application Info.plist independently uses version `1.0` and build `1`.
The About view and Info.plist currently use different textual version formats;
neither should be interpreted as proof of a formal distribution release.

## Modeled but inactive or unavailable settings

| Setting | Visibility | Current status |
| --- | --- | --- |
| Confirm destructive actions | Settings > General | Stored but not consulted by current destructive workflows |
| SSH keepalive interval | SSH connection editor | Saved and passed into internal configuration, but no periodic transport keepalive is implemented |
| SSH automatic reconnect | SSH connection editor | Saved but not used |
| SSH jump-host connection | Model only | No current UI or connection behavior |
| SSH legacy-algorithm overrides | Model only | No current UI or connection behavior |
| RDP redirected drive | Model/argument builder | No current editor control to select or enable a folder |
| RDP network profile | Model/argument builder | No current editor control; default auto-detect is used |

Settings that are absent from the UI should not be edited through JSON as an
undocumented configuration mechanism.

## Evidence

- [`SettingsView.swift`](../../RemoteHub/Features/Settings/SettingsView.swift)
- [`AppSettings.swift`](../../RemoteHub/Infrastructure/Settings/AppSettings.swift)
- [`HostKeyTrust.swift`](../../RemoteHub/Infrastructure/SSH/HostKeyTrust.swift)
- [`FreeRDPLauncher.swift`](../../RemoteHub/Infrastructure/RDP/FreeRDPLauncher.swift)
- [`RDPArgumentBuilder.swift`](../../RemoteHub/Infrastructure/RDP/RDPArgumentBuilder.swift)
- [Known limitations](../known-limitations.md)
