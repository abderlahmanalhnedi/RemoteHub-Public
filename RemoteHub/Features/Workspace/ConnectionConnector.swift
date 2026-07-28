import Foundation

struct StaticSecretProvider: SecretProvider {
    let value: String?
    func password() async throws -> String? { value }
}

@MainActor
final class ConnectionConnector {
    private let library: LibraryStore
    private let credentialStore: any CredentialStore
    private let hostStore: any KnownHostStore
    private let hostPrompt: HostTrustPromptCenter
    private let secretPrompt: SecretPromptCenter
    private let settings: AppSettings
    private let rdpLauncher: any RDPLaunching

    init(
        library: LibraryStore,
        credentialStore: any CredentialStore,
        hostStore: any KnownHostStore,
        hostPrompt: HostTrustPromptCenter,
        secretPrompt: SecretPromptCenter,
        settings: AppSettings,
        rdpLauncher: any RDPLaunching = FreeRDPLauncher()
    ) {
        self.library = library
        self.credentialStore = credentialStore
        self.hostStore = hostStore
        self.hostPrompt = hostPrompt
        self.secretPrompt = secretPrompt
        self.settings = settings
        self.rdpLauncher = rdpLauncher
    }

    func connect(
        _ connection: ConnectionProfile,
        into tab: WorkspaceTab,
        recordsAttempt: Bool = true
    ) async {
        let startedAt = Date.now
        AppLog.app.info("Connection attempt started for protocol \(connection.kind.rawValue, privacy: .public)")
        tab.state = .connecting
        tab.error = nil
        do {
            switch connection.kind {
            case .ssh, .sftp:
                try await connectSSH(connection, into: tab)
            case .ftp, .ftpsExplicit, .ftpsImplicit:
                try await connectFTP(connection, into: tab)
            case .rdp:
                try await connectRDP(connection, into: tab)
            }
            tab.state = .connected
            AppLog.app.info("Connection attempt succeeded for protocol \(connection.kind.rawValue, privacy: .public)")
            if recordsAttempt {
                recordAttempt(for: connection, startedAt: startedAt, outcome: .success, tab: tab)
            }
        } catch is CancellationError {
            tab.state = .disconnected
            AppLog.app.info("Connection attempt cancelled")
            if recordsAttempt {
                recordAttempt(for: connection, startedAt: startedAt, outcome: .cancelled, tab: tab)
            }
        } catch let error as RemoteHubError {
            tab.state = .failed
            tab.error = error
            AppLog.app.error("Connection attempt failed in category \(error.category.rawValue, privacy: .public)")
            if recordsAttempt {
                recordAttempt(for: connection, startedAt: startedAt, outcome: .failure, error: error, tab: tab)
            }
        } catch {
            let mapped = RemoteHubError(
                .unknown,
                message: "The connection failed.",
                recoverySuggestion: "Review the profile and try again.",
                technicalDetails: error.localizedDescription
            )
            tab.state = .failed
            tab.error = mapped
            AppLog.app.error("Connection attempt failed in category unknown")
            if recordsAttempt {
                recordAttempt(for: connection, startedAt: startedAt, outcome: .failure, error: mapped, tab: tab)
            }
        }
    }

    func refreshFiles(in tab: WorkspaceTab) async {
        do {
            if let sftp = tab.sftpSession {
                tab.remoteItems = try await sftp.list(path: tab.remotePath)
            } else if let ftp = tab.ftpClient {
                tab.remoteItems = try await ftp.list(path: tab.remotePath)
            }
            tab.error = nil
        } catch {
            tab.error = RemoteHubError(
                .unknown,
                message: "The remote folder could not be refreshed.",
                technicalDetails: error.localizedDescription
            )
        }
    }

    private func connectSSH(_ connection: ConnectionProfile, into tab: WorkspaceTab) async throws {
        let authentication = try await sshAuthentication(for: connection)
        let sshSettings = connection.protocolSettings.ssh
        let controller = HostTrustController(store: hostStore)
        let transport = CitadelSSHTransport(
            trustController: controller,
            trustPrompt: { [weak hostPrompt] evaluation in
                guard let hostPrompt else { throw CancellationError() }
                return try await hostPrompt.prompt(evaluation)
            }
        )
        let session = try await transport.connect(configuration: SSHConnectionConfiguration(
            host: connection.host,
            port: connection.port,
            authentication: authentication,
            terminalType: sshSettings.terminalType,
            timeoutSeconds: sshSettings.connectTimeoutSeconds,
            keepaliveSeconds: sshSettings.keepaliveSeconds,
            opensInteractiveShell: connection.kind == .ssh
        ))
        tab.sshSession = session
        if connection.kind == .sftp || tab.isSFTPPanelVisible {
            tab.sftpSession = try await session.openSFTP()
            await refreshFiles(in: tab)
        }
    }

    private func connectFTP(_ connection: ConnectionProfile, into tab: WorkspaceTab) async throws {
        let ftpSettings = connection.protocolSettings.ftp
        if connection.kind == .ftp, !ftpSettings.plainFTPWarningAcknowledged {
            throw RemoteHubError(
                .validation,
                message: "Plain FTP is unencrypted.",
                recoverySuggestion: "Acknowledge the warning in the connection editor before connecting."
            )
        }
        let credential = credential(for: connection)
        let prompted = try await passwordCredential(
            connection: connection,
            credential: credential,
            allowsAnonymous: credential?.authenticationType == .anonymousFTP
        )
        let client = CurlCLIFTPClient()
        try await client.connect(configuration: FTPConnectionConfiguration(
            kind: connection.kind,
            host: connection.host,
            port: connection.port,
            username: prompted.username,
            password: prompted.password,
            passiveMode: ftpSettings.passiveMode,
            verifyTLSCertificate: ftpSettings.verifyTLSCertificate,
            timeoutSeconds: 20
        ))
        tab.ftpClient = client
        await refreshFiles(in: tab)
    }

    private func connectRDP(_ connection: ConnectionProfile, into tab: WorkspaceTab) async throws {
        let credential = credential(for: connection)
        let prompted = try await passwordCredential(connection: connection, credential: credential)
        tab.rdpExitStatus = nil
        let handle = try await rdpLauncher.launch(
            sessionIdentifier: tab.id,
            configuration: RDPConnectionConfiguration(
                host: connection.host,
                port: connection.port,
                username: prompted.username,
                domain: credential?.domain,
                settings: connection.protocolSettings.rdp,
                customExecutablePath: settings.freeRDPPath.nilIfBlank,
                preflightTimeoutSeconds: TimeInterval(settings.rdpPreflightTimeoutSeconds)
            ),
            secretProvider: StaticSecretProvider(value: prompted.password)
        )
        tab.rdpHandle = handle
        Task { [weak tab] in
            let termination = await handle.waitForExit()
            await MainActor.run {
                guard let tab, tab.rdpHandle?.id == handle.id else { return }
                tab.rdpExitStatus = termination.exitCode
                tab.rdpHandle = nil
                if let error = RDPErrorMapper.map(
                    termination,
                    username: prompted.username,
                    password: prompted.password
                ) {
                    tab.error = error
                    tab.state = .failed
                } else {
                    tab.state = .disconnected
                }
            }
        }
    }

    private func sshAuthentication(for connection: ConnectionProfile) async throws -> SSHAuthentication {
        guard let credential = credential(for: connection) else {
            let prompted = try await secretPrompt.prompt(
                connectionName: connection.name,
                suggestedUsername: "",
                needsUsername: true
            )
            return .password(username: prompted.username, password: prompted.password)
        }
        switch credential.authenticationType {
        case .usernamePassword:
            let prompted = try await passwordCredential(connection: connection, credential: credential)
            return .password(username: prompted.username, password: prompted.password ?? "")
        case .sshPrivateKey, .sshPrivateKeyWithPassphrase:
            guard let path = credential.privateKeyDisplayPath else {
                throw RemoteHubError(.validation, message: "Select an SSH private key for this credential.")
            }
            let passphrase: String?
            if let account = credential.passphraseKeychainAccount {
                passphrase = try await credentialStore.read(account: account)
            } else {
                passphrase = nil
            }
            return .privateKey(
                username: credential.username,
                fileURL: URL(fileURLWithPath: path),
                passphrase: passphrase
            )
        case .sshAgent:
            return .agent(username: credential.username)
        case .askEveryTime:
            let prompted = try await secretPrompt.prompt(
                connectionName: connection.name,
                suggestedUsername: credential.username,
                needsUsername: credential.username.isEmpty
            )
            return .password(username: prompted.username, password: prompted.password)
        case .anonymousFTP:
            throw RemoteHubError(.validation, message: "Anonymous FTP credentials cannot be used for SSH.")
        }
    }

    private func passwordCredential(
        connection: ConnectionProfile,
        credential: CredentialProfile?,
        allowsAnonymous: Bool = false
    ) async throws -> (username: String, password: String?) {
        if allowsAnonymous {
            return ("anonymous", "remotehub@example.com")
        }
        if let credential,
           credential.authenticationType != .askEveryTime,
           let account = credential.passwordKeychainAccount,
           let password = try await credentialStore.read(account: account) {
            return (credential.username, password)
        }
        let prompted = try await secretPrompt.prompt(
            connectionName: connection.name,
            suggestedUsername: credential?.username ?? "",
            needsUsername: credential?.username.isEmpty != false
        )
        return (prompted.username, prompted.password)
    }

    private func credential(for connection: ConnectionProfile) -> CredentialProfile? {
        guard let id = connection.credentialProfileID else { return nil }
        return library.credentials.first { $0.id == id }
    }

    private func recordAttempt(
        for connection: ConnectionProfile,
        startedAt: Date,
        outcome: AttemptOutcome,
        error: RemoteHubError? = nil,
        tab: WorkspaceTab
    ) {
        do {
            try library.recordAttempt(
                for: connection,
                startedAt: startedAt,
                outcome: outcome,
                error: error
            )
        } catch {
            if tab.error == nil {
                tab.error = RemoteHubError(
                    .persistenceFailure,
                    message: "The connection completed, but its result could not be saved.",
                    technicalDetails: error.localizedDescription
                )
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
