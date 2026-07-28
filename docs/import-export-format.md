# Import and Export Format

This document describes export schema version 1 in the current source tree.

RemoteHub exports UTF-8 JSON with this illustrative shape:

```json
{
  "schemaVersion": 1,
  "exportedAt": "2026-07-25T00:00:00Z",
  "application": "RemoteHub",
  "groups": [],
  "credentialMetadata": [],
  "connections": []
}
```

Connections include typed protocol settings, tags, notes, favorites, and optional group references. Credential metadata is excluded by default and, when explicitly selected, contains only display name, username, domain, and authentication type.

Exports never contain passwords, key passphrases, private-key contents, Keychain data, or session/terminal data. Import accepts schema version 1, previews changes, and applies Skip, Replace, or Keep Both duplicate policies. Imported profiles deliberately have no linked saved secret and show “Credentials required.”

## Evidence

- [`ImportExport.swift`](../RemoteHub/Domain/UseCases/ImportExport.swift)
- [`LibraryStore.swift`](../RemoteHub/Infrastructure/Persistence/LibraryStore.swift)
- [`ImportExportTests.swift`](../RemoteHubTests/ImportExportTests.swift)
- [`CredentialSecurityTests.swift`](../RemoteHubTests/CredentialSecurityTests.swift)

## Known limitations

- Schema version 1 is the only accepted version.
- Exported hosts, usernames (when metadata is selected), tags, notes, and
  protocol settings can reveal sensitive infrastructure information even
  though secrets are excluded.
- Export files are not encrypted or signed by RemoteHub.
- Import establishes metadata only; credentials must be supplied again.
- Cross-version fixture retention and a formal compatibility policy have not
  been defined.
