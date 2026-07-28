# Workspace

The Workspace holds one tab per opened connection attempt. Open a tab by
connecting from Dashboard or the Connection Library, then select
**Workspace** in the sidebar to return to it.

## Basic workflow

1. Connect from Dashboard or the Connection Library.
2. Select the new tab in **Workspace** and complete any trust or credential
   prompt.
3. Use the terminal, file browser, or external RDP session for the selected
   profile.
4. Select **Disconnect** to leave the tab open, **Reconnect** to start again,
   or **Close Tab** when finished.

## Tabs and connection states

Opening the same profile again creates another tab; it does not reuse an
existing one. Select a tab in the horizontal tab strip to make it active.

The dot beside each tab title indicates:

| Color | State |
| --- | --- |
| Green | Connected |
| Orange | Connecting or reconnecting |
| Red | Failed |
| Secondary/gray | Idle or disconnected |

An SSH server can change the tab title through the terminal title sequence.
A cancelled connection attempt returns the tab to the disconnected state;
there is no separate cancelled tab state.

## Session controls

| Action | Where | Result |
| --- | --- | --- |
| Disconnect | Workspace toolbar while connected | Disconnects the active protocol sessions or terminates FreeRDP; leaves the tab open |
| Reconnect | Toolbar when not connected, tab context menu, RDP status view, or Command-R | Cancels the active connection task, initiates disconnect of current handles, and starts the profile again |
| Duplicate Tab | Tab context menu | Opens a new tab from the same saved profile |
| Close Tab | Tab close button, context menu, or Command-W | Cancels the connection task, initiates disconnect, and removes the tab |

Closing the selected tab selects the last remaining tab. If no tabs remain,
Workspace shows **No open sessions** and a **Browse Connections** action.

Automatic reconnect is not active. The profile toggle labeled **Reconnect
automatically (maximum three attempts)** is saved but not consumed by the
workspace.

## SSH terminal

A connected SSH tab embeds SwiftTerm and forwards:

- physical keyboard and pasted terminal input;
- PTY output;
- terminal resize events;
- title changes;
- cancellation and disconnect; and
- output-stream completion or a sanitized terminal error.

Click inside the terminal before typing when focus is elsewhere. Terminal font
family and size come from Settings. Terminal type is configured per SSH
connection and defaults to `xterm-256color`.

SwiftTerm provides native selection, copy/paste, Unicode and color rendering.
The live SSH record verifies a basic password-authenticated PTY and command
output, but control keys, function keys, extensive Unicode, network
interruption, and sleep/wake recovery still require manual verification.

## Terminal focus and application shortcuts

The application commands use explicit modifiers:

- Command-N opens a connection editor.
- Command-K focuses library search.
- Command-R reconnects the active SSH or RDP tab.
- Command-Shift-F toggles remote files for the active SSH tab.
- Command-W closes the active tab.

Unmodified `n`, `k`, `r`, and `w` are normal text input in editable fields.
The native UI regression covers that distinction. In a terminal, remote shell
bindings and SwiftTerm behavior still apply to other keys.

## SFTP panel on an SSH tab

Use **Toggle SFTP** in the toolbar or Command-Shift-F. When the panel is first
shown, RemoteHub asks the existing SSH session to open SFTP and refreshes the
current remote path.

The terminal and remote browser appear side-by-side. Hiding the panel does not
disconnect the SSH session. If SFTP cannot open, the tab displays a sanitized
error while retaining the SSH workspace when possible.

The **Open SFTP panel by default** profile option requests the same behavior
when the SSH tab starts. SFTP panel behavior is implemented but does not yet
have recorded live endpoint evidence.

## File-only tabs

SFTP, FTP, Explicit FTPS, and Implicit FTPS profiles create a file workspace
instead of an SSH terminal. The local browser appears on the left and remote
browser on the right. Command-R refreshes the active remote path for a file
tab.

See [File transfers](file-transfers.md) for navigation, operations, conflicts,
progress, cancellation, and protocol limitations.

## RDP workspace

An RDP connection launches FreeRDP in an external window. The RemoteHub tab
tracks the process and shows:

- whether the external process is running;
- relative start time;
- exit status after termination; and
- **Bring RDP Window to Front**, **Terminate Session**, and **Reconnect**
  controls.

Terminating the process does not close the RemoteHub tab. When FreeRDP exits
with status zero, the tab becomes disconnected; a nonzero exit marks it
failed.

RemoteHub has automated argument and password-isolation evidence but no
recorded live RDP session. See [Settings](settings.md) for executable discovery
and safe password-input requirements.

## Session errors and diagnostics

Connection and file-operation errors appear above the active content in an
error banner.

1. Read the user-facing message and recovery suggestion.
2. Select **Show Details** to expand category, message, recovery text, and
   technical details.
3. Select **Copy Diagnostics** to place the displayed sanitized block on the
   pasteboard.
4. Review the copied text before sharing it.
5. Select **Dismiss** to hide the banner without changing connection state.

The redactor removes common credential-bearing URL user/password pairs and
password/passphrase/token assignments. It cannot identify every sensitive
hostname, path, command, or arbitrary secret.

Host-key and attempt-time credential prompts are modal overlays:

- an unknown SSH key allows Cancel, Trust Once, or Trust and Save;
- a changed SSH key remains blocked until an explicit, independently verified
  replacement; and
- an attempt-only credential prompt does not save the password.

See [Troubleshooting](troubleshooting.md) for symptom-based recovery.

## Disconnect and cancellation notes

- Disconnect closes SSH, SFTP, and FTP handles and terminates an RDP process.
- Reconnect and Close cancel the active connection task before initiating
  disconnect.
- Transfer operations have their own queue cancellation controls. Closing a
  workspace does not remove completed queue records.
- Curl-based FTP/FTPS helper-process cancellation is not guaranteed to stop
  immediately; consult the transfer limitation before assuming the remote
  side is idle.

## Evidence

- [`WorkspaceView.swift`](../../RemoteHub/Features/Workspace/WorkspaceView.swift)
- [`WorkspaceStore.swift`](../../RemoteHub/Features/Workspace/WorkspaceStore.swift)
- [`ConnectionConnector.swift`](../../RemoteHub/Features/Workspace/ConnectionConnector.swift)
- [`SwiftTermView.swift`](../../RemoteHub/SharedUI/Components/SwiftTermView.swift)
- [`PromptViews.swift`](../../RemoteHub/Features/Workspace/PromptViews.swift)
