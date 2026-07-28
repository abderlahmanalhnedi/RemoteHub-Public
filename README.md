# RemoteHub

RemoteHub is a native, local-first macOS connection manager for SSH, SFTP,
FTP, FTPS, and FreeRDP sessions. It stores reusable connection metadata with
SwiftData and saved passwords or passphrases in macOS Keychain.

> [!WARNING]
> RemoteHub is under active development. It has not received an independent
> security audit and is not a notarized, production-ready distribution. Review
> the [known limitations](docs/known-limitations.md) before using it with
> sensitive systems.

## Features

- Dashboard, searchable connection library, groups, favorites, and workspace
  tabs.
- Reusable credential profiles with non-synchronizing, device-local Keychain
  items.
- Interactive SwiftTerm SSH terminal with exact negotiated host-key
  validation.
- SFTP, FTP, and FTPS file browser with a bounded transfer queue.
- Bundle-first SDL FreeRDP discovery, preflight checks, standard-input
  password delivery, diagnostics, and process lifecycle controls.
- Versioned JSON import and export that excludes secrets.

RemoteHub targets macOS 14 or newer. Interactive SSH requires macOS 15 or
newer because Citadel 0.12.1 marks its public PTY API with that availability.

## Build and test

A current full Xcode installation is required. From the repository root:

```bash
make bootstrap
make build
make test
make lint
make core-check
```

The native UI suite can be run separately:

```bash
make ui-test
```

`RemoteHub.xcodeproj` is generated from `project.yml`. `Package.swift` exposes
the shared source as a library for unit tests; it does not define a second
application entry point.

Debug builds tolerate a missing FreeRDP payload. Release builds require a
separately reviewed payload through `REMOTEHUB_FREERDP_PAYLOAD_DIR` or the
ignored `Vendor/FreeRDP/payload` location. No FreeRDP binary payload is
included in this repository. See
[`Packaging/FreeRDP/README.md`](Packaging/FreeRDP/README.md).

## Screenshots

The documentation screenshots use synthetic profiles and a disposable
localhost SSH endpoint.

![RemoteHub SSH terminal](docs/assets/screenshots/ssh-terminal.png)

The [Getting Started guide](docs/user-guide/getting-started.md) contains the
complete walkthrough and screenshot set.

## Documentation

Documentation starts at [`docs/index.md`](docs/index.md):

- [Getting started](docs/user-guide/getting-started.md)
- [Complete user guide](docs/user-guide/index.md)
- [Product overview](docs/product/overview.md)
- [System architecture](docs/architecture/system-overview.md)
- [Security overview](docs/security/security-overview.md)
- [Known limitations](docs/known-limitations.md)

## Security

Exports omit passwords, passphrases, Keychain data, private-key contents, and
terminal/session data, but they can still contain sensitive infrastructure
metadata. Never commit real exports, keys, credentials, diagnostics, or
unreviewed screenshots.

See [SECURITY.md](SECURITY.md) for the assurance boundary and private
vulnerability-reporting process.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development, testing, and
submission guidance.

RemoteHub is available under the [MIT License](LICENSE). Third-party notices
are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
