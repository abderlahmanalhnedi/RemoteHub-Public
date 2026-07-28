import SwiftUI
import SwiftData

private struct ConnectionDraft: Equatable {
    var name = ""
    var kind: ConnectionKind = .ssh
    var host = ""
    var port = ConnectionKind.ssh.defaultPort
    var groupID: UUID?
    var credentialID: UUID?
    var tags = ""
    var notes = ""
    var isFavorite = false
    var settings = ProtocolSettings.default

    init() {}

    init(_ connection: ConnectionProfile) {
        name = connection.name
        kind = connection.kind
        host = connection.host
        port = connection.port
        groupID = connection.groupID
        credentialID = connection.credentialProfileID
        tags = connection.tags.joined(separator: ", ")
        notes = connection.notes ?? ""
        isFavorite = connection.isFavorite
        settings = connection.protocolSettings
    }
}

struct ConnectionEditorView: View {
    @Environment(AppContainer.self) private var app
    @Environment(\.dismiss) private var dismiss
    let connection: ConnectionProfile?

    @State private var draft: ConnectionDraft
    @State private var initialDraft: ConnectionDraft
    @State private var portWasManuallyEdited: Bool
    @State private var updatesDefaultPort = false
    @State private var errorMessage: String?
    @State private var testMessage: String?
    @State private var isTesting = false
    @State private var showsCredentialEditor = false
    @State private var saveAndConnect = false

    init(connection: ConnectionProfile?) {
        self.connection = connection
        let value = connection.map(ConnectionDraft.init) ?? ConnectionDraft()
        _draft = State(initialValue: value)
        _initialDraft = State(initialValue: value)
        _portWasManuallyEdited = State(initialValue: connection.map { $0.port != $0.kind.defaultPort } ?? false)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(connection == nil ? "New Connection" : "Edit Connection")
                    .font(.title2.bold())
                Spacer()
                ProtocolBadge(kind: draft.kind)
            }
            .padding()

            Form {
                if let errorMessage {
                    Section { ErrorBanner(error: RemoteHubError(.validation, message: errorMessage)) }
                }
                if let testMessage {
                    Section {
                        Label(testMessage, systemImage: testMessage.hasPrefix("Connected") ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(testMessage.hasPrefix("Connected") ? .green : .red)
                    }
                }

                Section("Connection") {
                    TextField("Name", text: $draft.name)
                        .accessibilityIdentifier("connection.name")
                    Picker("Protocol", selection: $draft.kind) {
                        ForEach(ConnectionKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    .onChange(of: draft.kind) { oldKind, newKind in
                        guard oldKind != newKind, !portWasManuallyEdited else { return }
                        updatesDefaultPort = true
                        draft.port = newKind.defaultPort
                        updatesDefaultPort = false
                    }
                    TextField("Host", text: $draft.host)
                        .accessibilityIdentifier("connection.host")
                    TextField("Port", value: $draft.port, format: PortDisplayFormatter.inputFormat)
                        .accessibilityIdentifier("connection.port")
                        .accessibilityValue(
                            Text(verbatim: PortDisplayFormatter.string(draft.port))
                        )
                        .onChange(of: draft.port) { _, _ in
                            if !updatesDefaultPort { portWasManuallyEdited = true }
                        }
                    Picker("Group", selection: $draft.groupID) {
                        Text("Ungrouped").tag(Optional<UUID>.none)
                        ForEach(app.library.groups) { group in
                            Text(group.name).tag(Optional(group.id))
                        }
                    }
                    Toggle("Favorite", isOn: $draft.isFavorite)
                }

                Section("Credential") {
                    Picker("Credential profile", selection: $draft.credentialID) {
                        Text("Ask every time").tag(Optional<UUID>.none)
                        ForEach(app.library.credentials) { credential in
                            Text(credential.displayName).tag(Optional(credential.id))
                        }
                    }
                    HStack {
                        Button("New Credential", systemImage: "plus") {
                            showsCredentialEditor = true
                        }
                        if let credentialID = draft.credentialID,
                           let credential = app.library.credentials.first(where: { $0.id == credentialID }) {
                            Spacer()
                            Label(
                                credential.passwordKeychainAccount != nil || credential.passphraseKeychainAccount != nil
                                    ? "Secret stored securely"
                                    : "Will prompt if needed",
                                systemImage: credential.passwordKeychainAccount != nil || credential.passphraseKeychainAccount != nil
                                    ? "lock.fill"
                                    : "questionmark.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                protocolSettings

                Section("Organization") {
                    TextField("Tags (comma-separated)", text: $draft.tags)
                        .accessibilityIdentifier("connection.tags")
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 70)
                        .accessibilityLabel("Connection notes")
                        .accessibilityIdentifier("connection.notes")
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("connection.cancel")
                Button("Test Connection") { Task { await testConnection() } }
                    .disabled(isTesting)
                if isTesting { ProgressView().controlSize(.small) }
                Spacer()
                Button("Save") {
                    saveAndConnect = false
                    save()
                }
                Button("Save and Connect") {
                    saveAndConnect = true
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 680, minHeight: 720)
        .interactiveDismissDisabled(draft != initialDraft)
        .sheet(isPresented: $showsCredentialEditor) {
            CredentialEditorView(credential: nil) { credential in
                draft.credentialID = credential.id
            }
            .environment(app)
            .modelContainer(app.modelContainer)
        }
        .modifier(PromptSheets())
    }

    @ViewBuilder
    private var protocolSettings: some View {
        switch draft.kind {
        case .ssh, .sftp:
            Section("SSH and SFTP") {
                TextField("Initial remote directory", text: $draft.settings.ssh.initialRemoteDirectory)
                    .accessibilityIdentifier("connection.remoteDirectory")
                if draft.kind == .ssh {
                    TextField("Terminal type", text: $draft.settings.ssh.terminalType)
                        .accessibilityIdentifier("connection.terminalType")
                    Stepper(
                        "Keepalive: \(draft.settings.ssh.keepaliveSeconds) seconds",
                        value: $draft.settings.ssh.keepaliveSeconds,
                        in: 0...300,
                        step: 5
                    )
                    Stepper(
                        "Connect timeout: \(draft.settings.ssh.connectTimeoutSeconds) seconds",
                        value: $draft.settings.ssh.connectTimeoutSeconds,
                        in: 5...120,
                        step: 5
                    )
                    Toggle("Reconnect automatically (maximum three attempts)", isOn: $draft.settings.ssh.autoReconnect)
                    Toggle("Open SFTP panel by default", isOn: $draft.settings.ssh.openSFTPPanelByDefault)
                }
            }
        case .ftp, .ftpsExplicit, .ftpsImplicit:
            Section("FTP and FTPS") {
                if draft.kind == .ftp {
                    Label("Unencrypted: credentials and files may travel in plain text.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Toggle("I understand the plain FTP risk", isOn: $draft.settings.ftp.plainFTPWarningAcknowledged)
                }
                TextField("Initial remote directory", text: $draft.settings.ftp.initialRemoteDirectory)
                Toggle("Passive mode", isOn: $draft.settings.ftp.passiveMode)
                if draft.kind != .ftp {
                    Toggle("Verify TLS certificate", isOn: $draft.settings.ftp.verifyTLSCertificate)
                    if !draft.settings.ftp.verifyTLSCertificate {
                        Label("Certificate verification is disabled for this profile.", systemImage: "exclamationmark.shield")
                            .foregroundStyle(.red)
                    }
                }
            }
        case .rdp:
            Section("Remote Desktop") {
                Picker("Display mode", selection: $draft.settings.rdp.displayMode) {
                    Text("Windowed").tag(RDPDisplayMode.windowed)
                    Text("Full Screen").tag(RDPDisplayMode.fullScreen)
                }
                Toggle("Dynamic resolution", isOn: $draft.settings.rdp.dynamicResolution)
                if !draft.settings.rdp.dynamicResolution {
                    HStack {
                        TextField("Width", value: $draft.settings.rdp.width, format: .number)
                        TextField("Height", value: $draft.settings.rdp.height, format: .number)
                    }
                }
                Toggle("Multiple monitors", isOn: $draft.settings.rdp.multiMonitor)
                Toggle("Clipboard", isOn: $draft.settings.rdp.clipboard)
                Toggle("Audio", isOn: $draft.settings.rdp.audio)
                Toggle("Microphone", isOn: $draft.settings.rdp.microphone)
                Toggle("Admin / console session", isOn: $draft.settings.rdp.adminSession)
                Picker("Certificate policy", selection: $draft.settings.rdp.certificatePolicy) {
                    Text("Prompt").tag(RDPCertificatePolicy.prompt)
                    Text("Trust on first use").tag(RDPCertificatePolicy.trustOnFirstUse)
                    Text("Ignore (unsafe)").tag(RDPCertificatePolicy.ignore)
                }
                if draft.settings.rdp.certificatePolicy == .ignore {
                    Label("Certificate errors will be ignored for this profile.", systemImage: "exclamationmark.shield.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func validate() -> [ValidationIssue] {
        var issues = Validators.connectionName(draft.name)
            + Validators.host(draft.host)
            + Validators.port(draft.port)
        if draft.kind == .rdp {
            issues += Validators.rdpResolution(
                dynamic: draft.settings.rdp.dynamicResolution,
                width: draft.settings.rdp.width,
                height: draft.settings.rdp.height
            )
        }
        return issues
    }

    private func makeModel(id: UUID? = nil) -> ConnectionProfile {
        ConnectionProfile(
            id: id ?? UUID(),
            name: draft.name,
            kind: draft.kind,
            host: draft.host,
            port: draft.port,
            groupID: draft.groupID,
            credentialProfileID: draft.credentialID,
            tags: draft.tags.split(separator: ",").map(String.init),
            notes: draft.notes,
            isFavorite: draft.isFavorite,
            settings: draft.settings
        )
    }

    private func testConnection() async {
        let issues = validate()
        guard issues.isEmpty else {
            errorMessage = issues[0].message
            return
        }
        errorMessage = nil
        testMessage = nil
        isTesting = true
        let result = await app.workspace.test(makeModel())
        switch result {
        case .success:
            testMessage = "Connected successfully. The test session was closed."
        case .failure(let error):
            testMessage = "Test failed: \(error.message)"
        }
        isTesting = false
    }

    private func save() {
        let issues = validate()
        guard issues.isEmpty else {
            errorMessage = issues[0].message
            return
        }
        do {
            let model: ConnectionProfile
            if let connection {
                connection.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                connection.kind = draft.kind
                connection.host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
                connection.port = draft.port
                connection.groupID = draft.groupID
                connection.credentialProfileID = draft.credentialID
                connection.tags = draft.tags.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                connection.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                connection.isFavorite = draft.isFavorite
                try connection.updateProtocolSettings(draft.settings)
                model = connection
            } else {
                model = makeModel()
            }
            try app.library.saveConnection(model)
            initialDraft = draft
            if saveAndConnect {
                app.workspace.open(model)
                app.router.sidebarSelection = .workspace
            }
            dismiss()
        } catch {
            errorMessage = Redactor.sanitize(error.localizedDescription)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
