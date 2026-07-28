# Security Overview

## Scope and assurance boundary

This document records controls visible in the current source tree. It is not a
penetration test, independent security audit, threat-model approval,
certification, or guarantee. Controls are distinguished from configuration
options that can weaken them.

## Data classification

| Data | Treatment in the current design |
| --- | --- |
| Login passwords and SSH key passphrases | Secrets; macOS Keychain boundary |
| SSH private keys | Secrets managed as user-selected files; RemoteHub stores reference metadata, not key content |
| Hosts, usernames, tags, notes, group names, paths, known-host fingerprints | Potentially sensitive infrastructure metadata; local SwiftData or user-selected exports |
| Terminal content and transferred file content | Potentially sensitive; passed through active sessions/files and not intentionally added to RemoteHub persistence or logs |
| Error categories and connection outcomes | Local operational metadata |

## Secret storage boundary

Saved login passwords and SSH key passphrases are handled by
`KeychainCredentialStore`. `CredentialProfile` stores deterministic Keychain
account identifiers, not plaintext secret properties. Editing a credential
supports explicit unchanged, replace, or remove operations, which reduces
accidental replacement of an existing secret.

One-time credential prompts return values for the current connection attempt
and do not save them. Secrets necessarily exist in process memory while being
passed to an adapter; the source makes no secure-memory erasure guarantee.

Evidence:

- [`CredentialStore.swift`](../../RemoteHub/Infrastructure/Keychain/CredentialStore.swift)
- [`CredentialEditorView.swift`](../../RemoteHub/Features/Credentials/CredentialEditorView.swift)
- [`ConnectionConnector.swift`](../../RemoteHub/Features/Workspace/ConnectionConnector.swift)
- [`CredentialSecurityTests.swift`](../../RemoteHubTests/CredentialSecurityTests.swift)

## Keychain configuration

The implementation uses:

- generic-password items (`kSecClassGenericPassword`);
- service `com.alhnedi.RemoteHub.credentials`;
- deterministic accounts formed from credential UUID and secret type;
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; and
- `kSecAttrSynchronizable = false`.

These settings keep saved secrets device-local and unavailable while the
device Keychain is locked. The current code does not configure biometric/user
presence access control, access groups, or iCloud synchronization. Keychain
errors are mapped to a sanitized RemoteHub error category, while OSStatus is
logged as a public numeric value.

## SwiftData metadata boundary

SwiftData stores:

- connections, hosts, ports, tags, notes, groups, and protocol settings;
- credential display name, username, domain, authentication type, Keychain
  account identifiers, private-key display path/reference metadata, and notes;
- known SSH host, port, algorithm, fingerprint, and public-key data; and
- a bounded history of connection outcome/error categories.

It does not define plaintext password or passphrase properties. SwiftData is
therefore a metadata boundary, not a general secret store. The metadata can
still disclose server inventory or user identifiers to anyone with sufficient
local access. No application-level encryption of the SwiftData store is
implemented. Despite its `privateKeyBookmarkData` name, the current editor
stores UTF-8 path bytes in that field rather than creating a macOS
security-scoped bookmark.

Evidence:
[`PersistenceModels.swift`](../../RemoteHub/Domain/Models/PersistenceModels.swift),
[`AppContainer.swift`](../../RemoteHub/App/AppContainer.swift), and
[`LibraryStore.swift`](../../RemoteHub/Infrastructure/Persistence/LibraryStore.swift).

## SSH host-key trust

RemoteHub requests Ed25519, ECDSA, and RSA candidates with the system
`ssh-keyscan` process. During the actual NIOSSH handshake, a custom
authentication delegate receives the negotiated `NIOSSHPublicKey`, derives
its algorithm, encoded key data, and SHA-256 fingerprint, and requires that
exact key to be present in the preflight results.

The preflight scan order does not select a key. The exact presented key is then
evaluated by `HostTrustController`:

- no record for host, port, and algorithm: prompt for the presented key;
- matching algorithm, fingerprint, and available key data: allow;
- same host, port, and algorithm with different fingerprint/key: block as
  changed;
- additional algorithm: prompt and store independently.

**Trust Once** does not persist. **Trust and Save** persists the exact key.
Changed-key replacement requires a separate confirmation action after the UI
shows saved and presented fingerprints. Host-key and authentication failures
are mapped to different error categories.

The trust prompt is awaited outside the NIO event loop; the validation promise
is completed back on its event loop. This avoids blocking network progress.

Evidence:

- [`SSHHostKeyScanner.swift`](../../RemoteHub/Infrastructure/SSH/SSHHostKeyScanner.swift)
- [`CitadelSSHTransport.swift`](../../RemoteHub/Infrastructure/SSH/CitadelSSHTransport.swift)
- [`HostKeyTrust.swift`](../../RemoteHub/Infrastructure/SSH/HostKeyTrust.swift)
- [`PromptViews.swift`](../../RemoteHub/Features/Workspace/PromptViews.swift)
- [`SSHNegotiatedHostKeyValidationTests.swift`](../../RemoteHubTests/SSHNegotiatedHostKeyValidationTests.swift)
- [`HostTrustTests.swift`](../../RemoteHubTests/HostTrustTests.swift)

### SSH trust limitations

`ssh-keyscan` is not itself an authenticated trust source. Exact scan-to-
handshake binding prevents RemoteHub from trusting a different scanned
algorithm, but first-use trust remains vulnerable if the user does not compare
the presented fingerprint through a separate trusted channel. Known-host
records are local SwiftData metadata and are not protected as Keychain secrets.

## FTPS certificate policy

`FTPSettings.verifyTLSCertificate` defaults to `true`. The curl adapter adds
`--ssl-reqd` for explicit and implicit FTPS. It adds `--insecure` only when the
user configuration disables certificate verification for a non-FTP
connection. The editor exposes this as an explicit toggle.

This is a secure default, not certificate pinning. Validation behavior and
trust anchors are those of the system curl/TLS environment. Client
certificates are not implemented.

Evidence:
[`ProtocolSettings.swift`](../../RemoteHub/Domain/Models/ProtocolSettings.swift),
[`CurlCLIFTPClient.swift`](../../RemoteHub/Infrastructure/FTP/CurlCLIFTPClient.swift),
and
[`CredentialSecurityTests.swift`](../../RemoteHubTests/CredentialSecurityTests.swift).

## Plain FTP warning

Plain FTP is unencrypted. `ConnectionConnector` rejects a plain-FTP connection
until `plainFTPWarningAcknowledged` is set in the profile. The acknowledgement
does not encrypt traffic or credentials; it records an informed opt-in.

Evidence:
[`ConnectionConnector.swift`](../../RemoteHub/Features/Workspace/ConnectionConnector.swift)
and
[`ConnectionEditorView.swift`](../../RemoteHub/Features/Connections/ConnectionEditorView.swift).

## RDP password and certificate handling

RemoteHub launches its bundled SDL FreeRDP helper directly with
`Foundation.Process`; it does not invoke a shell. The password is sent through
standard input with `/from-stdin:force` and is never included in arguments.
Standard output and standard error are captured with pipes rather than
inherited from a parent terminal.

If safe standard input is unavailable, RemoteHub refuses automatic password
delivery. No command-line password fallback exists.

The default RDP certificate policy is `prompt`. TOFU and ignore policies are
available configuration choices; ignore weakens server authentication.
FreeRDP remains a separate native-process security boundary. The repository
defines a contract for pinning and reviewing the bundled version and dependency
closure, but the source tree does not include a binary payload. A distributable
release remains blocked until that separate review is complete.

Evidence:

- [`RDPArgumentBuilder.swift`](../../RemoteHub/Infrastructure/RDP/RDPArgumentBuilder.swift)
- [`FreeRDPLauncher.swift`](../../RemoteHub/Infrastructure/RDP/FreeRDPLauncher.swift)
- [`AppSettings.swift`](../../RemoteHub/Infrastructure/Settings/AppSettings.swift)
- [`RDPArgumentBuilderTests.swift`](../../RemoteHubTests/RDPArgumentBuilderTests.swift)

## Process isolation

The FTP/FTPS adapter invokes `/usr/bin/curl` directly. Its credential-bearing
curl configuration is written to standard input, not arguments or a temporary
file. The RDP adapter invokes the selected executable directly. Neither adapter
uses a shell.

Process boundaries still expose data to the invoked process. RemoteHub relies
on the operating system and the selected executable. Users must not select an
untrusted FreeRDP binary.

## Logging, errors, and diagnostics

`AppLog` defines protocol and feature categories. Reviewed connection log
messages contain protocol and error categories rather than hostname, username,
terminal content, authenticated URL, or secret. `RemoteHubError` sanitizes
technical details and exposes a controlled diagnostic string through **Show
Details** and **Copy Diagnostics**.

`Redactor` removes credentials embedded in URL user-info and values assigned to
common password/passphrase/token labels. This is a targeted safeguard, not a
general data-loss-prevention engine. Users must review diagnostics before
sharing them; arbitrary server messages or metadata can contain sensitive
content not matched by the current patterns.

Evidence:
[`AppLog.swift`](../../RemoteHub/Infrastructure/Logging/AppLog.swift),
[`Redactor.swift`](../../RemoteHub/Infrastructure/Logging/Redactor.swift),
[`RemoteHubError.swift`](../../RemoteHub/Domain/Errors/RemoteHubError.swift),
and
[`ProtocolBadge.swift`](../../RemoteHub/SharedUI/Components/ProtocolBadge.swift).

## Import and export

Version-one JSON exports exclude:

- passwords and key passphrases;
- Keychain item data and account identifiers;
- private-key contents;
- terminal/session data; and
- connection-attempt records.

Credential metadata is excluded by default. If explicitly included, it can
contain display name, username, domain, and authentication type, and
connections can reference that metadata. All exports contain connection
metadata such as hosts, tags, notes, and protocol settings, which may be
sensitive even without secrets. Export files must be handled accordingly.

Import validates schema version and creates metadata without a saved secret.
Duplicate policies are skip, replace, and keep both.

Evidence:
[`ImportExport.swift`](../../RemoteHub/Domain/UseCases/ImportExport.swift),
[`ImportExportTests.swift`](../../RemoteHubTests/ImportExportTests.swift), and
[`import-export-format.md`](../import-export-format.md).

## Current signing and distribution model

The native target is configured with:

- automatic code-sign style;
- ad-hoc identity `-`;
- no development team;
- App Sandbox disabled; and
- Hardened Runtime requested by the target.

The generated development application is locally signed to run on the build
host. Xcode disables Hardened Runtime for this ad-hoc signing path, so the
repository does not include evidence of a hardened distribution artifact.
No notarization, Developer ID distribution, App Store distribution, release
installer, or update-signing process is included. UI testing can add temporary
test entitlements to its instrumented debug build; these are not a distribution
control.

Evidence:
[`project.yml`](../../project.yml),
[`RemoteHub.xcodeproj`](../../RemoteHub.xcodeproj), and
[`RemoteHub-Info.plist`](../../Configuration/RemoteHub-Info.plist).

## Missing hardening

The following controls are not implemented:

- App Sandbox and security-scoped access for all external files;
- Developer ID signing, verified Hardened Runtime, and notarization;
- biometric/user-presence Keychain access control;
- application-level encryption of connection metadata;
- a signed update channel and defined supported-version policy;
- a complete threat model or independent security assessment; and
- formal retention/secure-deletion controls for metadata and exports.

## Security assumptions

- The macOS user account and login Keychain are trusted and appropriately
  protected.
- Users connect only to systems they are authorized to access.
- Users verify first-use and changed SSH fingerprints independently.
- System `curl`, `ssh-keyscan`, macOS frameworks, and selected FreeRDP binaries
  are trusted and maintained.
- The local filesystem can contain sensitive metadata and private-key files.
- A compromised local account or process can undermine these controls.

## Known risks

| Risk | Existing mitigation | Residual risk |
| --- | --- | --- |
| First-use SSH interception | Exact presented-key prompt and independent-verification instruction | User can still trust an attacker's first key |
| Local disclosure of inventory metadata | Local-only SwiftData; secrets separated into Keychain | No application-level metadata encryption or sandbox |
| FTPS/RDP trust weakened by settings | Secure defaults and explicit settings | User can disable FTPS verification or select RDP certificate ignore |
| RDP password in arguments | Standard input is mandatory; no command-line fallback exists | The FreeRDP process necessarily receives the secret |
| External process compromise | Bundle-first direct invocation, reviewed payload, and Advanced override isolation | curl/FreeRDP remain separate trusted-code boundaries |
| Diagnostic leakage | Typed errors, redaction, protocol/category-only logging | Redaction patterns cannot identify every sensitive value |
| Private-key file access | User explicitly selects a path | Unsandboxed process and path metadata increase local exposure |
| Incomplete interoperability evidence | Status labels separate implemented from live-verified | Unknown behavior remains for untested servers and failure modes |

## Security follow-up list

1. Complete FreeRDP license/architecture review, Developer ID signing,
   notarization, and a Hardened Runtime entitlement review.
2. Design App Sandbox and security-scoped bookmark handling for private keys,
   transfers, and external FreeRDP execution.
3. Produce and review a threat model covering local compromise, TOFU, malicious
   endpoints, subprocesses, imports, and transferred files.
4. Remove or require stronger confirmation for settings that weaken TLS/RDP
   certificate handling and command-line password isolation.
5. Expand structured redaction tests for arbitrary adapter errors and define a
   diagnostic-sharing policy.
6. Add repeatable live compatibility tests using non-production endpoints
   without committing endpoint details.
7. Define dependency monitoring, vulnerability triage, release signing,
   update, incident-response, and supported-version policies.
8. Evaluate Keychain access control requiring user presence for selected
   credentials.
9. Define metadata retention, backup, export classification, and secure
   deletion expectations.

## Known limitations

The complete product limitation register is
[`known-limitations.md`](../known-limitations.md). Current public-release
validation is summarized in
[`PUBLIC_RELEASE_AUDIT.md`](../../PUBLIC_RELEASE_AUDIT.md).
