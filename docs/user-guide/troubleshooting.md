# Troubleshooting

Start with the visible user-facing message. If a workspace error banner is
present, expand **Show Details** and review the recovery suggestion before
changing settings.

## The application does not build

Symptoms can include a missing SDK, unavailable package, signing failure, or a
toolchain that differs from the recorded baseline.

1. Confirm that full Xcode, not only Command Line Tools, is installed.
2. Confirm the active developer directory:

   ```bash
   xcode-select -p
   ```

3. If necessary, select the installed Xcode:

   ```bash
   sudo xcode-select --switch /Applications/Xcode.app
   ```

4. From the repository root, run:

   ```bash
   make bootstrap
   make build
   ```

5. Preserve the first complete diagnostic. Do not change Swift language mode,
   disable strict concurrency, or modify dependencies merely to hide an error.

The maintained local baseline uses Xcode 26.6 and Swift 6.3.3. A build on
another toolchain is a new verification environment.

## The build reports a SwiftData macro error

Full application and XCTest compilation require the `SwiftDataMacros` plug-in
provided by full Xcode. Install/select full Xcode, rerun `make bootstrap`, and
then rerun the failing command.

Command Line Tools alone are insufficient for this target.

## Keychain is unavailable

The error category is `keychainUnavailable`.

1. Unlock the Mac and make sure the login Keychain is available.
2. Open Settings > Security.
3. Run **Keychain Health Check**.
4. Retry the credential edit only after the health check succeeds.

If the health check still fails, preserve sanitized diagnostics and investigate
macOS Keychain access. Do not move the password into Notes or connection
metadata as a workaround.

## A stored password cannot be read

A lock label means a Keychain reference exists; the item may still be missing
or unavailable.

1. Run the Keychain health check.
2. Edit the credential.
3. Choose **Replace Password** and save a verified replacement, or choose
   **Remove Stored Password** and use Ask Every Time.
4. Retry the connection.

RemoteHub does not display or recover the previous plaintext password.

## Authentication failed

The error category is `authenticationFailed`.

Check:

- the username and optional domain;
- whether the endpoint supports the selected authentication method;
- password accuracy;
- private-key path, supported key format, and saved passphrase;
- that Anonymous FTP is not linked to SSH; and
- whether an imported credential still needs a secret.

SSH password authentication is distinct from keyboard-interactive
authentication. The current release does not claim keyboard-interactive MFA or
SSH-agent support. Do not weaken server authentication configuration to fit
the client.

## An unknown SSH host key appears

This is expected on first contact or after trusted-host records were cleared.
The prompt represents the exact key presented by the negotiated SSH
handshake.

1. Compare host, ungrouped port, algorithm, and SHA-256 fingerprint with an
   independent trusted source.
2. Select **Cancel** if verification is unavailable.
3. Use **Trust Once** only for the current verified attempt.
4. Use **Trust and Save** to persist that exact host, port, algorithm, and key.

Do not accept a key because another algorithm from the same host was already
trusted.

## The SSH host key changed

RemoteHub blocks the connection when the same host, port, and algorithm
presents a different fingerprint or key.

1. Stop and verify whether the endpoint was rebuilt or rotated.
2. Consider redirection or interception as a possible cause.
3. Compare the new key through a separate trusted channel.
4. Only after verification, select **Review Replacement…** and
   **I Verified It — Replace Key**.

Do not clear trusted hosts or select a different algorithm merely to bypass the
warning.

## The SSH terminal is unavailable

Check:

- macOS version: Citadel's interactive PTY API requires macOS 15 or newer;
- that the profile protocol is SSH rather than SFTP;
- that host-key validation and authentication completed;
- the terminal type, normally `xterm-256color`;
- connection timeout and endpoint shell availability; and
- the error banner and diagnostics.

If the terminal is visible but typing does not go to it, click inside the
terminal. If the session ended, use **Reconnect**. SFTP-only profiles remain
available on the macOS 14 application target.

## An SFTP operation failed

1. Confirm the SSH/SFTP session is connected.
2. Refresh the remote path.
3. Verify the remote path and server permissions.
4. For chmod, enter a valid octal mode no greater than `7777`.
5. For delete, confirm that a remote directory is empty if required.
6. Expand the error details.

For a failed transfer, inspect the queue and use **Retry** only after resolving
the cause. For cancellation, check for partial files on both sides.

There is no recorded live SFTP verification. A server-specific failure may
represent interoperability behavior not covered by compilation or unit tests.

## FTP acknowledgement is required

Plain FTP sends credentials and data without transport encryption. Edit the
FTP profile and enable **I understand the plain FTP risk** only after
confirming that unencrypted FTP is authorized for that environment.

Prefer an encrypted protocol when available. The acknowledgement does not make
FTP secure.

## FTPS reports a certificate failure

1. Confirm system time, endpoint name, port, and Explicit versus Implicit
   mode.
2. Inspect certificate validity, hostname coverage, chain, and trust
   configuration.
3. Correct the endpoint or local trust configuration.
4. Retry with **Verify TLS certificate** enabled.

Disabling certificate verification removes protection against the wrong or
intercepted server. It is not a safe general fix. If an isolated authorized
test requires the unsafe setting, document the exception and restore
verification immediately.

## Bundled FreeRDP is missing or incompatible

Open Settings > RDP and select **Check Again**.

- If the bundle helper is missing, reinstall the reviewed RemoteHub release.
- Developers and support staff can choose a compatible SDL FreeRDP executable
  under **Advanced**.
- If incompatible, review the selected path and sanitized reason.
- If the executable lacks safe standard-input password support, use a
  compatible build.

RemoteHub opens FreeRDP in its own native window and has no live RDP
interoperability record.

## The UI or connection appears stuck

1. Determine whether the active tab is Connecting, Reconnecting, Connected,
   Failed, or Disconnected.
2. Check for a modal host-key or credential prompt.
3. If connected, use **Disconnect** and wait for state change.
4. Use **Reconnect** or Command-R once; automatic reconnect is not active.
5. If necessary, close the tab with its close button or Command-W.
6. Check the transfer queue separately for active helper operations.

Do not repeatedly create tabs or submit prompts while another decision is
pending. For FTP/FTPS transfer cancellation, confirm whether the curl helper
left a partial file because immediate process termination is not guaranteed.

If the entire app stops responding, preserve the minimum sanitized diagnostic
evidence and reproduce with isolated demo data before filing a report.

## Copy Diagnostics

For a workspace error:

1. Select **Show Details**.
2. Read the category, message, recovery, and details.
3. Select **Copy Diagnostics**.
4. Paste into a private scratch location.
5. Remove any remaining host, path, username, command, filename, or other
   sensitive data before sharing.

The copy action includes the error's diagnostics block. It does not
automatically include terminal history or a general system profile.

The sanitizer recognizes common credential-bearing URLs and
password/passphrase/token assignments. It is not a complete data-loss
prevention system. Never add secrets to diagnostics to make a report more
specific.

## Evidence

- [`RemoteHubError.swift`](../../RemoteHub/Domain/Errors/RemoteHubError.swift)
- [`ProtocolBadge.swift`](../../RemoteHub/SharedUI/Components/ProtocolBadge.swift)
- [`Redactor.swift`](../../RemoteHub/Infrastructure/Logging/Redactor.swift)
- [`ConnectionConnector.swift`](../../RemoteHub/Features/Workspace/ConnectionConnector.swift)
- [`CredentialStore.swift`](../../RemoteHub/Infrastructure/Keychain/CredentialStore.swift)
