# System Overview

## Scope

RemoteHub is a native SwiftUI macOS application with local persistence and
protocol adapters for SSH, SFTP, FTP, FTPS, and external RDP. This document
describes the architecture at commit `b4f0316`; it is not a deployment diagram
for any particular infrastructure.

## System context

```mermaid
flowchart LR
    User[Authorized macOS user]
    App[RemoteHub.app]
    Keychain[(macOS Keychain)]
    LocalData[(SwiftData and UserDefaults)]
    SSH[User-configured SSH/SFTP endpoint]
    FTP[User-configured FTP/FTPS endpoint]
    RDP[User-configured RDP endpoint]
    SystemTools[ssh-keyscan and curl]
    FreeRDP[External FreeRDP process]

    User --> App
    App <--> Keychain
    App <--> LocalData
    App --> SystemTools
    SystemTools --> SSH
    SystemTools --> FTP
    App <--> SSH
    App --> FreeRDP
    FreeRDP <--> RDP
```

RemoteHub has no application-managed cloud service in the reviewed source. It
connects directly or through local system/external tools to endpoints selected
by the user.

## Layered architecture

```mermaid
flowchart TB
    UI[App and SharedUI<br/>SwiftUI, AppKit, SwiftTerm adapter]
    Features[Feature coordination<br/>library, editors, workspace, transfers, settings]
    Domain[Domain<br/>models, validation, errors, contracts, use cases]
    Infrastructure[Infrastructure<br/>SwiftData, Keychain, SSH/SFTP, curl, FreeRDP, logging]
    Platform[macOS and external boundaries<br/>Security, SwiftData, NIO, system tools, endpoints]

    UI --> Features
    Features --> Domain
    Features --> Infrastructure
    Infrastructure --> Domain
    Infrastructure --> Platform
```

The dependency direction is enforced primarily through domain protocols such
as `SSHTransport`, `SSHSession`, `SFTPSession`, `FTPClient`, and
`RDPLaunching` in
[`TransportProtocols.swift`](../../RemoteHub/Domain/Protocols/TransportProtocols.swift).
Tests supply fakes for these boundaries.

## Main runtime components

| Component | Responsibility | Source |
| --- | --- | --- |
| Application entry | Creates the native scenes, model container, settings scene, and commands | [`RemoteHubApp.swift`](../../RemoteHub/App/RemoteHubApp.swift) |
| Composition root | Constructs SwiftData, Keychain store, prompts, transfer queue, connector, and workspace | [`AppContainer.swift`](../../RemoteHub/App/AppContainer.swift) |
| Root navigation | Routes dashboard, library, credentials, workspace, settings, sheets, and command notifications | [`RootView.swift`](../../RemoteHub/App/RootView.swift) |
| App commands | Defines Command-N, Command-K, Command-R, Command-Shift-F, and Command-W | [`AppCommands.swift`](../../RemoteHub/App/AppCommands.swift) |
| Local library | Validates and persists groups, credentials, connections, known hosts, attempts, and imports | [`LibraryStore.swift`](../../RemoteHub/Infrastructure/Persistence/LibraryStore.swift) |
| Connection coordinator | Resolves credentials and settings, selects the protocol adapter, records outcome categories | [`ConnectionConnector.swift`](../../RemoteHub/Features/Workspace/ConnectionConnector.swift) |
| Workspace lifecycle | Owns tabs, connection tasks, reconnect, close, and protocol disconnect | [`WorkspaceStore.swift`](../../RemoteHub/Features/Workspace/WorkspaceStore.swift) |
| SSH transport | Scans keys, validates the negotiated key, authenticates, and creates SSH/PTTY sessions | [`CitadelSSHTransport.swift`](../../RemoteHub/Infrastructure/SSH/CitadelSSHTransport.swift) |
| SFTP adapter | Wraps Citadel SFTP operations and streaming transfers | [`CitadelSFTPSession.swift`](../../RemoteHub/Infrastructure/SFTP/CitadelSFTPSession.swift) |
| FTP/FTPS adapter | Builds and executes typed system-curl requests with credentials on standard input | [`CurlCLIFTPClient.swift`](../../RemoteHub/Infrastructure/FTP/CurlCLIFTPClient.swift) |
| RDP adapter | Resolves bundled FreeRDP first, performs DNS/TCP preflight, launches it directly, captures output, maps failures, and tracks lifecycle | [`FreeRDPLauncher.swift`](../../RemoteHub/Infrastructure/RDP/FreeRDPLauncher.swift) |
| Transfer queue | Bounds concurrency, prevents active duplicates, and handles cancel/retry/progress | [`TransferQueue.swift`](../../RemoteHub/Features/Transfers/TransferQueue.swift) |
| Error/log boundary | Uses typed error categories, sanitization, and protocol-only OSLog events | [`RemoteHubError.swift`](../../RemoteHub/Domain/Errors/RemoteHubError.swift), [`Redactor.swift`](../../RemoteHub/Infrastructure/Logging/Redactor.swift), [`AppLog.swift`](../../RemoteHub/Infrastructure/Logging/AppLog.swift) |

Observable UI and feature state is main-actor isolated. Network/session
interfaces are asynchronous and `Sendable`. Private unchecked-Sendable wrappers
are limited to dependency types that Citadel 0.12.1 does not annotate.

## Connection flow

```mermaid
sequenceDiagram
    actor User
    participant Library as Connection profile
    participant Workspace as WorkspaceStore
    participant Connector as ConnectionConnector
    participant Secrets as CredentialStore or prompt
    participant Adapter as Protocol adapter
    participant Endpoint as Remote endpoint
    participant Attempts as LibraryStore

    User->>Workspace: Open saved connection
    Workspace->>Connector: connect(profile, tab)
    Connector->>Library: Read protocol settings and credential link
    Connector->>Secrets: Resolve saved or one-time secret
    Connector->>Adapter: Build typed configuration
    Adapter->>Endpoint: Connect and authenticate
    alt Success
        Endpoint-->>Adapter: Session ready
        Adapter-->>Connector: Session handle
        Connector-->>Workspace: Connected tab
        Connector->>Attempts: Record success category
    else Cancellation
        Connector-->>Workspace: Disconnected
        Connector->>Attempts: Record cancellation
    else Failure
        Adapter-->>Connector: Typed or mapped error
        Connector-->>Workspace: Sanitized error
        Connector->>Attempts: Record error category
    end
```

Protocol selection and attempt recording are in
[`ConnectionConnector.swift`](../../RemoteHub/Features/Workspace/ConnectionConnector.swift).
Only outcome and error category are retained in a `ConnectionAttempt`; no
terminal content or password is part of that model.

## Credential and Keychain flow

```mermaid
sequenceDiagram
    actor User
    participant Editor as CredentialEditorView
    participant Coordinator as CredentialSecretCoordinator
    participant Keychain as KeychainCredentialStore
    participant SwiftData as CredentialProfile metadata
    participant Connector as ConnectionConnector
    participant Adapter as SSH, FTP/FTPS, or RDP adapter

    User->>Editor: Create or edit credential
    Editor->>Coordinator: unchanged, replace, or remove
    Coordinator->>Keychain: Save/read/delete generic password item
    Keychain-->>Coordinator: Deterministic account identifier
    Coordinator-->>SwiftData: Store account identifier only
    Connector->>SwiftData: Resolve linked credential metadata
    Connector->>Keychain: Read secret when connecting
    Keychain-->>Connector: Secret in memory
    Connector->>Adapter: Typed authentication/configuration
```

The Keychain service and accessibility settings are implemented in
[`CredentialStore.swift`](../../RemoteHub/Infrastructure/Keychain/CredentialStore.swift).
Credential metadata is defined in
[`PersistenceModels.swift`](../../RemoteHub/Domain/Models/PersistenceModels.swift).
The source does not assert secure memory erasure after Swift strings leave
scope.

## SSH host-key trust flow

```mermaid
flowchart TD
    Start[Start SSH connection]
    Scan[ssh-keyscan requests Ed25519, ECDSA, and RSA candidates]
    Handshake[NIOSSH handshake presents the negotiated public key]
    Candidate[Derive presented algorithm, key data, and SHA-256 fingerprint]
    InScan{Exact presented key in preflight scan?}
    Stored{Stored record for host + port + algorithm?}
    Match{Fingerprint and key data match?}
    Prompt[Prompt for exact presented key]
    Decision{User decision}
    Changed[Block and show changed-key review]
    Replace{Explicit verified replacement?}
    Allow[Complete validation promise on NIO EventLoop]
    Reject[Fail validation]

    Start --> Scan --> Handshake --> Candidate --> InScan
    InScan -- No --> Reject
    InScan -- Yes --> Stored
    Stored -- No --> Prompt
    Stored -- Yes --> Match
    Match -- Yes --> Allow
    Match -- No --> Changed --> Replace
    Prompt --> Decision
    Decision -- Cancel --> Reject
    Decision -- Trust once --> Allow
    Decision -- Trust and save --> Allow
    Replace -- No --> Reject
    Replace -- Yes --> Allow
```

`ssh-keyscan` order does not select the trusted key. The custom NIOSSH
authentication delegate receives the actual handshake key, resolves its
algorithm and SHA-256 fingerprint, binds it to the matching scan result, and
then evaluates that exact key. Trust records are separated by normalized host,
port, and algorithm. A changed fingerprint for an existing algorithm is
blocked until explicit replacement; an additional algorithm is prompted
independently.

The delegate leaves the NIO event loop before awaiting the UI/trust actor and
completes the NIO promise back on its event loop. Sources:
[`CitadelSSHTransport.swift`](../../RemoteHub/Infrastructure/SSH/CitadelSSHTransport.swift),
[`SSHHostKeyScanner.swift`](../../RemoteHub/Infrastructure/SSH/SSHHostKeyScanner.swift),
[`HostKeyTrust.swift`](../../RemoteHub/Infrastructure/SSH/HostKeyTrust.swift),
and
[`LibraryStore.swift`](../../RemoteHub/Infrastructure/Persistence/LibraryStore.swift).

## PTY concurrency boundary

The Citadel PTY closure is created by the non-actor-isolated
`CitadelPTYDriver`; it does not capture the `CitadelSSHSession` actor. A
`SSHPTYBridge` actor installs a writer, forwards output, rejects send/resize
before readiness, and completes the output stream once. `SSHPTYController`
serializes start and disconnect, cancels its task, and waits for completion.
This design is contained in
[`CitadelSSHTransport.swift`](../../RemoteHub/Infrastructure/SSH/CitadelSSHTransport.swift)
and tested by
[`SSHPTYControllerTests.swift`](../../RemoteHubTests/SSHPTYControllerTests.swift).

## Persistence boundary

```mermaid
flowchart LR
    UI[Editors and workspace]
    Library[LibraryStore]
    SwiftData[(SwiftData)]
    KeychainStore[KeychainCredentialStore]
    Keychain[(macOS Keychain)]
    Defaults[AppSettings]
    UserDefaults[(UserDefaults)]
    Files[User-selected private keys and transfer files]

    UI --> Library --> SwiftData
    UI --> KeychainStore --> Keychain
    UI --> Defaults --> UserDefaults
    UI <--> Files
```

| Boundary | Stored data | Explicit exclusions or caveats |
| --- | --- | --- |
| SwiftData | Connection/group/credential metadata, settings, host-key records, recent attempt categories | No plaintext password/passphrase property; metadata such as hostnames and notes can still be sensitive |
| Keychain | Login passwords and SSH key passphrases | Non-synchronizing, `WhenUnlockedThisDeviceOnly`; no claim of biometric access control |
| UserDefaults | UI, transfer, FreeRDP, and security-related preferences | Not a secret store |
| Filesystem | User-selected private keys and transfer files | Application is not sandboxed; private keys remain user-managed; the current credential “bookmark” data is path bytes rather than a security-scoped bookmark |
| Export JSON | Selected connection/group data and optional credential metadata | No passwords, passphrases, Keychain data, private-key contents, or sessions |

SwiftData is initialized with an explicit schema and migration plan in
[`AppContainer.swift`](../../RemoteHub/App/AppContainer.swift) and
[`PersistenceModels.swift`](../../RemoteHub/Domain/Models/PersistenceModels.swift).
The code lets SwiftData select its standard local storage location rather than
hard-coding a database path.

## External dependencies and platform services

| Dependency or service | Role | Boundary evidence |
| --- | --- | --- |
| SwiftUI, AppKit, SwiftData | Native UI, responder chain, and local model persistence | Application source and [`project.yml`](../../project.yml) |
| Security framework | Generic-password Keychain items | [`CredentialStore.swift`](../../RemoteHub/Infrastructure/Keychain/CredentialStore.swift) |
| SwiftTerm 1.14.0 | Terminal view/emulation | [`SwiftTermView.swift`](../../RemoteHub/SharedUI/Components/SwiftTermView.swift) |
| Citadel 0.12.1 | High-level SSH/SFTP client | SSH/SFTP infrastructure source |
| SwiftNIO SSH fork 0.3.4 and SwiftNIO 2.83.0 | SSH protocol and event-loop transport | [`Package.resolved`](../../Package.resolved) |
| Swift Crypto 3.12.3 | SSH key parsing/cryptographic operations | SSH transport and resolved dependencies |
| `/usr/bin/ssh-keyscan` | Preflight collection of supported host-key candidates | [`SSHHostKeyScanner.swift`](../../RemoteHub/Infrastructure/SSH/SSHHostKeyScanner.swift) |
| `/usr/bin/curl` | FTP and FTPS subprocess adapter | [`CurlCLIFTPClient.swift`](../../RemoteHub/Infrastructure/FTP/CurlCLIFTPClient.swift) |
| Bundled SDL FreeRDP | Separately signed native RDP client process with dylibraries under `Contents/Frameworks` | [`FreeRDPLauncher.swift`](../../RemoteHub/Infrastructure/RDP/FreeRDPLauncher.swift) |
| OSLog | Categorized local application logging | [`AppLog.swift`](../../RemoteHub/Infrastructure/Logging/AppLog.swift) |

Versions and notices are maintained in
[`Package.resolved`](../../Package.resolved) and
[`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md).

## Build architecture

```mermaid
flowchart TD
    ProjectYML[project.yml]
    XcodeGen[XcodeGen regeneration]
    XcodeProject[RemoteHub.xcodeproj]
    AppTarget[RemoteHub application target]
    UITestTarget[RemoteHubUITests target]
    AppProduct[RemoteHub.app]
    Package[Package.swift]
    Library[RemoteHub library target<br/>excludes RemoteHubApp.swift]
    Tests[RemoteHubTests]
    Shared[Shared RemoteHub source tree]

    ProjectYML --> XcodeGen --> XcodeProject
    XcodeProject --> AppTarget --> AppProduct
    XcodeProject --> UITestTarget
    Shared --> AppTarget
    Shared --> Library
    Package --> Library --> Tests
```

The native Xcode target is the only application entry point. It supplies the
macOS application product, Info.plist, bundle identifier, local signing,
asset catalog, dependencies, and UI-test host. `project.yml` is the declarative
source used to regenerate the checked-in project.

`Package.swift` defines the same application source as a library, excluding
only `RemoteHubApp.swift`, so unit tests remain reproducible through Swift
Package Manager without creating a second bare executable. Build and
verification commands are coordinated by [`Makefile`](../../Makefile) and
[`Scripts/`](../../Scripts/).

The current GitHub Actions workflow runs package resolution, `make build`, and
`make test` on `macos-latest`. It does not currently run `make ui-test`,
`make lint`, or `make core-check`, and it does not pin an exact Xcode image.
See [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml).

## Evidence and known limitations

This architecture was reconciled against source, build configuration,
dependency resolution, and tests. Current release-preparation command results
are in
[`PUBLIC_RELEASE_AUDIT.md`](../../PUBLIC_RELEASE_AUDIT.md).

Known gaps include incomplete live interoperability coverage, no sandbox,
pending FreeRDP payload review/notarization, and modeled but inactive SSH
reconnect/keepalive settings. See
[`known-limitations.md`](../known-limitations.md).
