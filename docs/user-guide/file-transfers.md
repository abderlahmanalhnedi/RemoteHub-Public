# File Transfers

Status: **Partial**. The browser and transfer paths are implemented, but no
live SFTP, FTP, or FTPS endpoint operation is recorded.

RemoteHub uses one file-browser interface for SFTP, FTP, Explicit FTPS, and
Implicit FTPS. An SSH tab can also show the SFTP browser beside its terminal.

## Open the file browser

- Open an SFTP, FTP, or FTPS profile to create a file-only workspace.
- In a connected SSH tab, select **Toggle SFTP** or press Command-Shift-F.

The full file workspace has a local pane on the left and remote pane on the
right. The compact SSH layout shows only the remote pane beside the terminal.

## Local pane

Select **Choose…** to authorize a local folder. The pane lists its contents in
case-insensitive name order.

- Double-click a local folder to enter it.
- Double-click a local file to open it with macOS.

The local pane has no back button. Use **Choose…** again to select a different
root or navigate by double-clicking child folders.

## Remote pane

The toolbar provides:

- **Up** — move to the parent path;
- editable **Remote path** — press Return to refresh that path;
- **Refresh** — reload the current listing; and
- an action menu for create, upload, download, rename, permissions, and
  delete.

The table shows Name, Size, Permissions, Owner, and Modified values where the
server supplies them. Double-click a directory to enter it. Double-click a
file to open the Download save panel.

Settings > File Transfers > **Show hidden files** controls whether names
beginning with `.` appear. It filters the fetched listing; it is not a
server-side visibility request.

## Create a remote directory

1. Open the remote action menu.
2. Select **New Folder**.
3. Enter a non-empty single path component without `/`.
4. Select **Create**.

RemoteHub issues SFTP create-directory or FTP `MKD`, then refreshes the
listing. A failure appears as a permissions-category error banner with
sanitized details.

## Upload

1. Select **Upload Files or Folders…**.
2. Choose one or more local files or directories.
3. RemoteHub queues one top-level record per selection.

Directories are traversed recursively. RemoteHub creates each destination
directory before uploading its children. The queue prevents an identical
active source/destination key from being enqueued twice.

The application does not yet provide drag-and-drop upload.

## Download

Select a remote item and choose **Download…**, use its context menu, or
double-click a file. The macOS save panel selects the local destination.

Remote directories are downloaded recursively. RemoteHub creates the local
directory and then lists and downloads each child.

The transfer overwrite preference described below is applied to upload names
found in the current remote listing. Downloads rely on the macOS save panel
and do not apply the same RemoteHub overwrite-policy switch.

## Rename and delete

**Rename…** accepts one non-empty path component without `/`, performs the
protocol rename operation, and refreshes the directory.

**Delete** always presents a confirmation in the current browser. Files and
directories use their respective protocol operations. Directory deletion is
not a general recursive delete; it can fail if the server requires the
directory to be empty.

Deleting or renaming remote data is irreversible unless the server provides
its own recovery mechanism.

## Permissions

**Change Permissions…** is available only when an SFTP session exists. Enter
an octal mode from `0000` through `7777`, for example `0644`, then select
**Apply**.

FTP and FTPS do not expose the permissions action in the main action menu.
Permissions displayed in a server listing may be informational only.

## Upload overwrite behavior

Set the policy under Settings > File Transfers:

| Policy | Behavior when the selected top-level upload name already exists in the current remote listing |
| --- | --- |
| Ask | Fail-safe: do not enqueue that item; show an error directing the user to choose Replace, Skip, or Keep Both |
| Replace | Submit the upload to the existing destination path |
| Skip | Do not enqueue the conflicting item |
| Keep Both | Generate `name 2`, `name 3`, and so on, preserving an extension |

**Ask** does not currently open a per-item inline choice. The check is based on
the current listing and compares names case-insensitively. Refresh before
uploading when other clients may have changed the directory.

Server behavior ultimately determines whether writing an existing destination
replaces it successfully. RemoteHub does not promise atomic remote
replacement.

## Transfer queue

The toolbar's **Transfers** popover shows the same queue that appears below an
active workspace when records exist.

Records move through Queued, Running, Succeeded, Failed, or Cancelled. A
running record shows byte progress when the protocol reports a total and an
indeterminate indicator otherwise.

- **Cancel** is available for queued or running records.
- **Retry** is available for failed or cancelled records and increments the
  attempt count internally.
- **Clear Finished** removes succeeded, failed, and cancelled records.
- Settings allows 1 through 8 concurrent transfers; the default is 3.

SFTP streams file chunks and reports byte progress. The curl FTP/FTPS adapter
reports final byte totals with zero transfer speed instead of continuous
progress.

## Cancellation limitations

SFTP upload/download loops check task cancellation between chunks. Recursive
folder operations check cancellation between children.

The curl adapter runs the system `/usr/bin/curl` helper. Queue cancellation
changes the RemoteHub record, but immediate helper-process termination is not
guaranteed by the current process runner. After cancelling FTP/FTPS:

1. verify the queue state;
2. refresh the remote directory;
3. confirm whether a partial local or remote file remains; and
4. clean up only after reviewing both sides.

## FTP and FTPS behavior

RemoteHub invokes the system curl executable and supplies the username and
password through curl's standard-input configuration, not as command-line
arguments.

- Passive mode is the default. Turning it off requests active FTP mode.
- Plain FTP is unencrypted and requires explicit profile acknowledgement.
- Explicit FTPS uses FTP with a required TLS upgrade.
- Implicit FTPS uses the `ftps` scheme with TLS required from connection
  start.
- Certificate verification is on by default. Turning it off passes curl's
  insecure mode and should not be a routine troubleshooting step.
- Listings support the implemented Unix LIST, DOS LIST, and MLSD parsers.

Anonymous FTP uses an anonymous username and a non-secret placeholder email.
Live server compatibility, certificate cases, active mode, anonymous login,
and listing variations remain unverified.

## Current limitations

- No recorded live SFTP, FTP, or FTPS file operation exists.
- No remote back/forward history, drag-and-drop, or per-column sorting.
- Ask overwrite mode has no inline per-item decision.
- Upload conflict detection uses the current directory snapshot.
- Recursive delete is not implemented.
- Curl progress is completion-oriented and cancellation may not immediately
  terminate the helper.
- Live behavior depends on server permissions, path semantics, listing format,
  TLS configuration, and protocol implementation.

## Evidence

- [`FileTransferWorkspace.swift`](../../RemoteHub/Features/Workspace/FileTransferWorkspace.swift)
- [`RemoteTransferService.swift`](../../RemoteHub/Features/Transfers/RemoteTransferService.swift)
- [`TransferQueue.swift`](../../RemoteHub/Features/Transfers/TransferQueue.swift)
- [`CitadelSFTPSession.swift`](../../RemoteHub/Infrastructure/SFTP/CitadelSFTPSession.swift)
- [`CurlCLIFTPClient.swift`](../../RemoteHub/Infrastructure/FTP/CurlCLIFTPClient.swift)
- [Known limitations](../known-limitations.md)
