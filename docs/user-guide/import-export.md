# Import and Export

RemoteHub uses a versioned JSON document to move connection-library metadata
between installations. The workflow does not back up passwords, passphrases,
private keys, or terminal sessions.

The canonical field-level reference is
[Import and Export Format](../import-export-format.md). This chapter describes
the user workflow and safety decisions rather than repeating the complete
schema.

## Export

1. Open Settings > **Import / Export**.
2. Leave **Include non-secret credential metadata** off unless the identity
   metadata is required.
3. Select **Export Connections…**.
4. Review the confirmation summary for connection and group counts.
5. Select **Write Export…**.
6. Choose a protected local destination for `RemoteHubExport.json`.

RemoteHub writes UTF-8, pretty-printed, sorted-key JSON with an atomic local
file replacement.

### Included data

Every export contains:

- schema version and export time;
- application name;
- groups;
- connection names, protocol, host, port, group reference, tags, notes,
  favorite state, and protocol settings.

If credential metadata is explicitly included, the export also contains:

- display name;
- username;
- optional domain;
- authentication type; and
- connection-to-credential metadata references.

### Always excluded

Exports never contain:

- passwords or SSH key passphrases;
- Keychain values or Keychain account references;
- private-key content;
- private-key paths or the current path/bookmark bytes;
- terminal content or history;
- workspace tabs and session state;
- known-host records or fingerprints; or
- connection-attempt history.

Excluding secrets does not make the export public. Hosts, ports, usernames,
tags, notes, group names, RDP settings, and remote paths can identify
infrastructure.

## Import

1. Open Settings > **Import / Export**.
2. Choose **Skip**, **Replace**, or **Keep Both** under Duplicate handling.
3. Select **Choose RemoteHub Export…**.
4. Choose one JSON file.
5. Review Import Preview counts for connections, groups, credential metadata,
   and export time.
6. Confirm the duplicate policy.
7. Select **Import**.

The preview rejects malformed JSON and any schema version other than version
1. Import errors are sanitized before display.

Newly created imported credential profiles contain metadata only. They have no
Keychain secret and receive the note **Imported metadata — credentials
required**. Connections linked to those profiles therefore prompt until a
suitable secret is saved.

When **Replace** targets an existing credential UUID, RemoteHub updates its
metadata but leaves any existing Keychain account references unchanged.
Review, replace, or remove that existing secret before using the imported
identity.

## Duplicate handling

Duplicate policy is applied across the imported document:

| Object | Duplicate recognition | Skip | Replace | Keep Both |
| --- | --- | --- | --- | --- |
| Group | Same UUID or case-insensitive name | Map imported references to existing group | Update existing name and sort order | Create a uniquely suffixed imported group |
| Credential metadata | Same UUID | Map to existing credential | Replace display name, username, domain, and authentication type; leave existing Keychain account references unchanged | Create a new credential with ` (Imported)` suffix and no secret |
| Connection | Same UUID, or same case-insensitive name and host plus same protocol | Leave existing connection unchanged | Replace endpoint, links, tags, notes, favorite state, and protocol settings | Create a new profile with ` (Imported)` suffix |

For Keep Both groups, RemoteHub adds **(Imported)** and increments the suffix
when necessary. A kept-both connection receives a new UUID.

Review Replace carefully: imported metadata can change a connection's host,
port, protocol, credential link, certificate policy, and other connection
settings.

## Schema and compatibility

- Schema version 1 is the only accepted version.
- Future schema versions are rejected with a supported-version message.
- No formal cross-version fixture retention or compatibility policy exists.
- The JSON is not encrypted or digitally signed by RemoteHub.
- Import validates decoding and schema version; it is not proof that the file
  came from a trusted person or safe endpoint.
- A successful import does not test any connection.

Do not hand-edit protocol settings to activate model fields that are not
supported by the current UI.

## Safe file handling

Before export:

- remove secrets accidentally placed in names, hosts, tags, notes, usernames,
  or remote paths;
- exclude credential metadata unless needed; and
- choose a destination with appropriate access controls.

Before import:

- obtain the file through a trusted channel;
- inspect it as sensitive metadata;
- confirm schema version and expected counts;
- review hosts, ports, certificate policy, and unsafe RDP/FTPS settings; and
- make a separate approved backup if replacing existing profiles matters.

After import:

- supply credentials through the Credential editor or Ask Every Time;
- independently verify SSH host keys and TLS certificates;
- test profiles only against authorized endpoints; and
- securely delete obsolete export copies according to local retention policy.

RemoteHub does not define an export retention, secure-erasure, encryption, or
signature workflow.

## Evidence

- [`ImportExport.swift`](../../RemoteHub/Domain/UseCases/ImportExport.swift)
- [`LibraryStore.swift`](../../RemoteHub/Infrastructure/Persistence/LibraryStore.swift)
- [`SettingsView.swift`](../../RemoteHub/Features/Settings/SettingsView.swift)
- [`ImportExportTests.swift`](../../RemoteHubTests/ImportExportTests.swift)
- [`CredentialSecurityTests.swift`](../../RemoteHubTests/CredentialSecurityTests.swift)
- [Import and Export Format](../import-export-format.md)
