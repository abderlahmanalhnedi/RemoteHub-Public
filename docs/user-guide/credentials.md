# Credentials

Credential profiles let multiple connections reuse identity metadata and,
when requested, separately stored secrets. Select **Credentials** in the
sidebar to create and manage them.

## Metadata and secrets

RemoteHub deliberately separates the two:

| Category | Examples | Storage |
| --- | --- | --- |
| Credential metadata | Display name, username, domain, authentication type, notes, private-key display path | Local SwiftData store |
| Secret | Login password or SSH private-key passphrase | macOS Keychain when secure saving is selected |
| External key material | SSH private-key file | Remains at the selected filesystem path |
| Keychain reference | Opaque account identifier indicating where a secret is stored | Credential metadata |

The credential model has no plaintext password or passphrase property. A lock
label in the list means that the profile has a saved Keychain account
reference; it does not prove that an external endpoint will accept the secret.

RemoteHub stores Keychain secrets under service
`com.alhnedi.RemoteHub.credentials` as non-synchronizing, device-local items
available only while the Mac is unlocked.

## Credential list

Each row shows:

- display name;
- domain and username when present;
- authentication type;
- whether a saved secret reference exists; and
- the number of linked connection profiles.

Double-click a row to edit it. The context menu provides **Edit** and
**Delete**.

## Create a reusable password profile

1. Select **New Credential**.
2. Enter a non-sensitive display name.
3. Enter the endpoint username and optional domain.
4. Select **Username and Password**.
5. Enter and confirm the password.
6. Leave **Save securely in macOS Keychain** enabled to reuse it.
7. Select **Save**.

When creating a profile, disabling secure saving means the entered password is
not retained. A later connection will prompt for the password.

RemoteHub never displays an existing saved password in the editor.

## Ask Every Time

There are two ways to obtain an attempt-only password:

- select **Ask every time** instead of a credential profile in the connection
  editor; or
- link a credential whose authentication type is **Ask Every Time**.

When connecting, RemoteHub opens **Credentials Required**. It may prefill a
saved username, but the password field starts empty. The entered value is used
for that attempt only and is not saved.

Use this mode when local password reuse is not appropriate. It does not add
keyboard-interactive SSH or multifactor support; the resulting SSH attempt
still uses the SSH password method.

## Private-key credentials

Select **SSH Private Key** for an unencrypted supported key or
**SSH Private Key with Passphrase** for a protected key.

1. Enter the SSH username.
2. Choose the private-key file.
3. For a protected key, enter and confirm the passphrase.
4. Choose whether to save the passphrase securely.
5. Save the profile.

The selected path is stored as display metadata. The current
`privateKeyBookmarkData` field contains the UTF-8 path bytes, not a macOS
security-scoped bookmark. The key itself is not copied into SwiftData or
Keychain. Moving, renaming, or removing the file can therefore break the
profile.

Current parsing supports the implemented OpenSSH Ed25519 and RSA paths. Other
key types or unsupported encrypted formats return a clear error. The recorded
live SSH evidence covers password authentication, not a complete private-key
matrix.

If a key-with-passphrase profile has no saved passphrase, the current
connection flow does not open a separate passphrase prompt. Save a verified
passphrase in Keychain or use another supported workflow.

## Other authentication types

| Type | Current use |
| --- | --- |
| Anonymous FTP | Uses the conventional anonymous username and a non-secret placeholder email; valid only for FTP-family connections |
| SSH Agent | Visible in the model/editor, but Citadel 0.12.1 does not expose supported macOS agent authentication; connecting returns an unsupported error |

Do not select Anonymous FTP for SSH. RemoteHub rejects that combination.

## Replace or remove a stored password

Edit an existing password credential:

- **Replace Password** reveals new and confirmation fields. The replacement is
  committed to Keychain when secure saving remains enabled and you save.
- **Remove Stored Password** marks the existing Keychain item for removal when
  you save.
- **Keep Stored Password** cancels a pending removal.

If an existing profile already has a saved password, selecting **Replace
Password** and then disabling secure saving does not remove the old Keychain
item. Saving discards the entered replacement and leaves the existing saved
password unchanged. Use **Remove Stored Password** and save when removal is
the intended result.

Closing the editor without saving does not apply the requested secret change.
Replacement reuses the credential's deterministic Keychain account identifier.

Protected private-key profiles provide the equivalent **Replace Passphrase**,
**Remove Stored Passphrase**, and **Keep Stored Passphrase** actions, including
the same secure-saving behavior.

Changing the authentication type does not automatically delete an existing
password or passphrase from Keychain. Explicitly remove the stored secret and
save the profile when it should no longer be retained.

## Linked connections

The editor and list show how many connection profiles link to a credential.
The deletion confirmation names linked connections so you can review the
impact.

To move a connection to a different identity, edit the connection and select a
different credential profile. To force an attempt-only prompt, select
**Ask every time**.

## Delete a credential safely

1. Review the linked count and linked connection names.
2. Select **Delete** from the credential's context menu.
3. Confirm **Delete Credential and Saved Secrets**.

RemoteHub first removes referenced password and passphrase items from
Keychain, then deletes the credential metadata and unlinks associated
connections. Linked connections remain in the library and will require
another credential or an attempt-time prompt.

If Keychain deletion fails, RemoteHub reports a sanitized error and reloads the
library. Confirm the final credential and Keychain state before retrying; do
not assume a partial operation completed.

## Keychain health and recovery

Settings > Security provides **Run Keychain Health Check**. The check writes,
reads, and removes a generated temporary item.

If Keychain is unavailable:

1. Unlock the Mac and confirm the login Keychain is accessible.
2. Run the health check.
3. Edit the credential and replace the secret if its reference no longer
   resolves.
4. If replacement is not appropriate, remove the stored secret and use
   Ask Every Time.

Never paste a real password into Notes, connection metadata, diagnostics, or a
support ticket.

## Import and export

Exports omit credential metadata by default. If metadata is explicitly
included, only display name, username, domain, and authentication type are
written. Passwords, passphrases, Keychain references, private-key paths,
bookmark/path data, and private-key content are excluded.

Imported credential metadata contains no saved secret and is labeled
**Imported metadata — credentials required**. See
[Import and export](import-export.md).

## Current limitations and verification boundary

- SSH-agent authentication is modeled but unsupported by the current Citadel
  integration.
- Supported private-key parsing is limited to the implemented OpenSSH Ed25519
  and RSA paths.
- A missing saved private-key passphrase does not open an attempt-time
  passphrase prompt.
- Credential editor and Keychain behavior have automated and source-level
  evidence. The recorded live SSH evidence covers password authentication,
  not the complete private-key and FTP credential matrix.

## Evidence

- [`CredentialsView.swift`](../../RemoteHub/Features/Credentials/CredentialsView.swift)
- [`CredentialEditorView.swift`](../../RemoteHub/Features/Credentials/CredentialEditorView.swift)
- [`CredentialStore.swift`](../../RemoteHub/Infrastructure/Keychain/CredentialStore.swift)
- [`ConnectionConnector.swift`](../../RemoteHub/Features/Workspace/ConnectionConnector.swift)
- [`CredentialSecurityTests.swift`](../../RemoteHubTests/CredentialSecurityTests.swift)
- [Security overview](../security/security-overview.md)
