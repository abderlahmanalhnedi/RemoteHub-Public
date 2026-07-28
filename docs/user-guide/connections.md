# Connections

Connection profiles hold reusable endpoint metadata and protocol settings.
They may link to a credential profile, but they never contain the credential's
saved password or SSH key passphrase.

## Browse the Connection Library

Select **All Connections** to see every saved profile. The sidebar also
provides:

- **Favorites**;
- one entry per group; and
- filters for SSH, SFTP, FTP, FTPS (Explicit), FTPS (Implicit), and RDP.

Each row shows the connection name, an ungrouped ASCII host-and-port endpoint,
group, protocol, favorite star when applicable, and the result of the latest
recorded attempt.

Double-click a row to connect. Select a row and use the toolbar's **Connect**
or **Edit** action for the same operations.

## Search and sort

Use the sidebar search field or Command-K. Search is case- and
diacritic-insensitive across:

- connection name;
- host;
- protocol display name;
- group name; and
- tags.

Notes are not searched. The sort picker supports **Name**, **Host**,
**Protocol**, **Last Used**, and **Created**. Last Used sorts by the most
recent successful connection; Created sorts newest first.

## Groups

1. Select **New Group** in the sidebar.
2. Enter a unique, non-empty name.
3. Use a connection's context menu and **Move to Group** to assign it.

Deleting a group moves its profiles to **Ungrouped**; it does not delete the
connections. Group names are local metadata and can appear in exports and
screenshots.

## Create or edit a profile

Open **New Connection** from Dashboard or All Connections, use the toolbar
plus button, or press Command-N.

The editor's common fields are:

| Field | Purpose |
| --- | --- |
| Name | Local display name; required |
| Protocol | Selects the protocol-specific fields and default port |
| Host | DNS name or IP literal; required |
| Port | TCP port from 1 through 65535 |
| Group | Optional library grouping |
| Favorite | Adds the profile to Favorites and Dashboard |
| Credential profile | Reusable credential metadata, or **Ask every time** |
| Tags | Comma-separated searchable metadata |
| Notes | Free-form local metadata; not searched |

Changing the protocol updates the default port only until the port has been
manually edited. Default ports are SSH/SFTP 22, FTP/Explicit FTPS 21,
Implicit FTPS 990, and RDP 3389.

The bottom actions are:

- **Cancel** — close without saving. A changed draft cannot be interactively
  dismissed without resolving the editor.
- **Test Connection** — open a temporary session, report success or failure,
  and close it. The test does not save an attempt record.
- **Save** — persist the profile without opening a workspace.
- **Save and Connect** — persist the profile, create a workspace tab, and
  start connecting.

**Test Connection performs a real outbound connection.** It can display SSH
trust or credential prompts, contact FTP/FTPS endpoints, or launch external
FreeRDP for an RDP profile. Use it only with an authorized reachable endpoint;
do not select it for a documentation-only example host. “Temporary” describes
the unsaved workspace session, not a simulated network test.

## SSH and SFTP fields

Both protocols expose **Initial remote directory**. SSH also exposes:

| Field | Current behavior |
| --- | --- |
| Terminal type | Sent when requesting the interactive PTY; default `xterm-256color` |
| Connect timeout | Applied to the Citadel connection timeout |
| Keepalive | Saved and passed through the internal configuration, but no periodic keepalive behavior is implemented in the current transport |
| Reconnect automatically | Saved and displayed, but automatic bounded reconnect is not active |
| Open SFTP panel by default | Opens the remote-files panel with an SSH workspace and requests SFTP on the SSH session |

An SFTP profile opens directly into the file workspace and does not request an
interactive shell. Citadel's public interactive PTY API requires macOS 15 or
newer; SFTP-only profiles remain available to the macOS 14 application target.

The model also contains future jump-host and legacy-algorithm fields. They are
not exposed or active. RemoteHub does not silently enable legacy SSH
algorithms.

## FTP and FTPS fields

FTP, Explicit FTPS, and Implicit FTPS expose:

- initial remote directory;
- passive mode; and
- for FTPS, **Verify TLS certificate**.

Plain FTP additionally requires **I understand the plain FTP risk**. RemoteHub
blocks an unacknowledged FTP profile because the login and traffic are
unencrypted.

Certificate verification is enabled by default for FTPS. Disabling it adds an
unsafe curl option and removes server-certificate protection. Correct the
certificate or trust environment instead of disabling verification. If a
temporary exception is unavoidable in an authorized test environment, treat
the profile as high risk and restore verification immediately afterward.

Explicit FTPS upgrades an FTP connection with TLS. Implicit FTPS starts with
TLS on the implicit FTPS endpoint. Current automated evidence covers command
construction and certificate-verification defaults; there is no recorded live
FTP or FTPS endpoint run.

## RDP fields

RDP launches RemoteHub's bundled native SDL FreeRDP helper in its own window;
RemoteHub does not embed a desktop renderer. Profile fields include:

- windowed or full-screen display;
- dynamic resolution, or explicit width and height;
- multiple monitors;
- clipboard;
- audio and microphone;
- admin/console session;
- certificate policy: Prompt, Trust on first use, or Ignore (unsafe).

**Ignore (unsafe)** disables FreeRDP certificate protection for that profile.
Do not use it as a routine fix for certificate errors.

Network profile and redirected-drive values exist in the data model and
argument builder but are not exposed in the current connection editor. Do not
rely on them as a supported UI workflow. See [Workspace](workspace.md) and
[Settings](settings.md) for process lifecycle and executable discovery.

## Manage existing profiles

The row context menu provides:

- **Connect**;
- **Edit**;
- **Duplicate**;
- **Add to Favorites** or **Remove from Favorites**;
- **Move to Group**; and
- **Delete**.

Duplicate creates a new profile named with a `Copy` suffix and preserves the
endpoint, credential link, tags, notes, favorite state, group, and
protocol-specific settings.

Deleting a connection requires confirmation. It does not delete the linked
credential or its Keychain secret. Deleting a connection also does not close
an already-open workspace tab created from it.

## Safe metadata practices

Treat all profile fields as potentially disclosive:

- Do not put passwords, bearer tokens, authenticated URLs, or private keys in
  Name, Host, Tags, or Notes.
- Prefer stable DNS names only when disclosure is acceptable. Use IPv6
  literals without adding your own display brackets.
- Keep customer names, ticket data, and production incident notes outside
  general-purpose tags and notes.
- Review profile metadata before exporting, screen sharing, or copying a
  repository screenshot.

The error redactor targets common credential URLs and password assignments; it
does not make arbitrary notes or hostnames safe.

## Evidence and limitations

Library search/sort and profile behavior have automated or source-level
evidence. Broader connection-library CRUD still requires manual verification.
Only one sanitized SSH password/host-key/PTY path has live endpoint evidence;
SFTP, FTP, FTPS, and RDP interoperability still require live verification.

- [`ConnectionLibraryView.swift`](../../RemoteHub/Features/Connections/ConnectionLibraryView.swift)
- [`ConnectionEditorView.swift`](../../RemoteHub/Features/Connections/ConnectionEditorView.swift)
- [`SidebarView.swift`](../../RemoteHub/Features/Connections/SidebarView.swift)
- [`SearchSorter.swift`](../../RemoteHub/Domain/UseCases/SearchSorter.swift)
- [`ProtocolSettings.swift`](../../RemoteHub/Domain/Models/ProtocolSettings.swift)
- [Known limitations](../known-limitations.md)
