import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppContainer.self) private var app
    @State private var selectedSection: SettingsSection? = .general
    @State private var rdpStatus: RDPInstallationStatus?
    @State private var securityMessage: String?
    @State private var showsClearHostsConfirmation = false
    @State private var includeCredentialMetadata = false
    @State private var showsExportSummary = false
    @State private var duplicatePolicy: DuplicateImportPolicy = .skip
    @State private var importPreview: ExportDocument?
    @State private var importError: String?

    var body: some View {
        @Bindable var settings = app.settings
        HSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .frame(minWidth: 180, idealWidth: 200)

            Form {
                switch selectedSection ?? .general {
                case .general:
                    general(settings: settings)
                case .terminal:
                    terminal(settings: settings)
                case .transfers:
                    transfers(settings: settings)
                case .rdp:
                    rdp(settings: settings)
                case .security:
                    security
                case .importExport:
                    importExport
                case .about:
                    about
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 480)
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Export \(app.library.connections.count) connections and \(app.library.groups.count) groups?",
            isPresented: $showsExportSummary,
            titleVisibility: .visible
        ) {
            Button("Write Export…") { writeExport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(includeCredentialMetadata
                ? "Credential names and usernames are included. Passwords, passphrases, and private keys are always excluded."
                : "Credential metadata and every secret are excluded.")
        }
        .confirmationDialog(
            "Clear all trusted SSH host keys?",
            isPresented: $showsClearHostsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Trusted Hosts", role: .destructive) {
                do {
                    try app.library.clearKnownHosts()
                    securityMessage = "Trusted host keys cleared."
                } catch {
                    securityMessage = Redactor.sanitize(error.localizedDescription)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Future SSH connections will ask for trust again.")
        }
        .sheet(
            isPresented: Binding(
                get: { importPreview != nil },
                set: { if !$0 { importPreview = nil } }
            )
        ) {
            if let preview = importPreview {
                ImportPreviewView(
                    document: preview,
                    policy: $duplicatePolicy,
                    apply: {
                        do {
                            try app.library.applyImport(preview, policy: duplicatePolicy)
                            importPreview = nil
                        } catch {
                            importError = Redactor.sanitize(error.localizedDescription)
                        }
                    },
                    cancel: { importPreview = nil }
                )
            }
        }
    }

    @ViewBuilder
    private func general(settings: AppSettings) -> some View {
        @Bindable var settings = settings
        Section("General") {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppearancePreference.allCases) { value in
                    Text(value.displayName).tag(value)
                }
            }
            Toggle("Confirm destructive actions", isOn: $settings.confirmDestructiveActions)
        }
        Section("Library") {
            LabeledContent("Connections", value: "\(app.library.connections.count)")
            LabeledContent("Groups", value: "\(app.library.groups.count)")
            LabeledContent("Credentials", value: "\(app.library.credentials.count)")
        }
    }

    @ViewBuilder
    private func terminal(settings: AppSettings) -> some View {
        @Bindable var settings = settings
        Section("Terminal") {
            Picker("Font family", selection: $settings.terminalFontName) {
                ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            Stepper(
                "Font size: \(Int(settings.terminalFontSize)) pt",
                value: $settings.terminalFontSize,
                in: 9...32,
                step: 1
            )
            LabeledContent("Terminal type", value: "xterm-256color")
            LabeledContent("Scrollback", value: "10,000 lines")
        }
        Section {
            Text("SwiftTerm provides native selection, copy/paste, Unicode, 256-color rendering, and the standard Find interface.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func transfers(settings: AppSettings) -> some View {
        @Bindable var settings = settings
        Section("File Transfers") {
            Picker("Overwrite behavior", selection: $settings.overwriteBehavior) {
                ForEach(OverwriteBehavior.allCases) { value in
                    Text(value.displayName).tag(value)
                }
            }
            Stepper(
                "Concurrent transfers: \(settings.concurrentTransfers)",
                value: $settings.concurrentTransfers,
                in: 1...8
            )
            .onChange(of: settings.concurrentTransfers) { _, value in
                app.transfers.maximumConcurrent = value
            }
            Toggle("Show hidden files", isOn: $settings.showHiddenFiles)
        }
    }

    @ViewBuilder
    private func rdp(settings: AppSettings) -> some View {
        @Bindable var settings = settings
        Section("FreeRDP") {
            Button("Check Again", systemImage: "arrow.clockwise") {
                Task { await checkRDP() }
            }
            rdpStatusView
            Text("RemoteHub uses its bundled native SDL FreeRDP client. No separate installation is required.")
                .foregroundStyle(.secondary)
        }
        Section {
            DisclosureGroup("Advanced") {
                HStack {
                    TextField("Custom executable path", text: $settings.freeRDPPath)
                    Button("Choose…") { chooseFreeRDP(settings: settings) }
                }
                Stepper(
                    "Preflight timeout: \(settings.rdpPreflightTimeoutSeconds) seconds",
                    value: $settings.rdpPreflightTimeoutSeconds,
                    in: 2...15
                )
                Text("The override is intended for development and support. The bundled client always takes precedence.")
                    .foregroundStyle(.secondary)
            }
        }
        Section("Password Security") {
            Text("RemoteHub never places RDP passwords in process arguments. The bundled client receives passwords through standard input.")
                .foregroundStyle(.secondary)
        }
        .task { if rdpStatus == nil { await checkRDP() } }
    }

    @ViewBuilder
    private var rdpStatusView: some View {
        switch rdpStatus {
        case .available(let installation):
            Label("Detected \(installation.versionDescription)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            LabeledContent("Executable", value: installation.executableURL.path)
            LabeledContent("Safe password input", value: installation.supportsSafePasswordInput ? "Supported" : "Not reported")
            if installation.requiresXQuartz {
                Label("This X11 client requires XQuartz.", systemImage: "info.circle")
            }
        case .missing:
            Label("Bundled FreeRDP client unavailable", systemImage: "xmark.circle")
                .foregroundStyle(.orange)
            Text("Reinstall RemoteHub. Developers can select an override under Advanced.")
                .foregroundStyle(.secondary)
        case .incompatible(let path, let reason):
            Label("Incompatible FreeRDP executable", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(path).font(.caption).textSelection(.enabled)
            Text(reason).font(.caption).foregroundStyle(.secondary)
        case nil:
            ProgressView("Checking FreeRDP…")
        }
    }

    @ViewBuilder
    private var security: some View {
        Section("Keychain") {
            Button("Run Keychain Health Check") { Task { await checkKeychain() } }
            if let securityMessage {
                Text(securityMessage).foregroundStyle(.secondary)
            }
        }
        Section("Trusted SSH Hosts") {
            LabeledContent("Saved host keys", value: "\(app.library.knownHosts.count)")
            ForEach(app.library.knownHosts) { host in
                let endpoint = PortDisplayFormatter.endpoint(
                    host: host.normalizedHost,
                    port: host.port
                )
                VStack(alignment: .leading) {
                    Text(verbatim: endpoint)
                        .accessibilityLabel(Text(verbatim: endpoint))
                    Text("\(host.keyAlgorithm) • \(host.sha256Fingerprint)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Button("Clear Trusted Host Keys", role: .destructive) {
                showsClearHostsConfirmation = true
            }
            .disabled(app.library.knownHosts.isEmpty)
        }
        Section {
            Text("Secrets use non-synchronizing, device-local Keychain items accessible only while this Mac is unlocked.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var importExport: some View {
        Section("Export") {
            Toggle("Include non-secret credential metadata", isOn: $includeCredentialMetadata)
            Button("Export Connections…", systemImage: "square.and.arrow.up") {
                showsExportSummary = true
            }
            Text("Exports never include passwords, passphrases, private-key contents, Keychain data, or terminal history.")
                .foregroundStyle(.secondary)
        }
        Section("Import") {
            Picker("Duplicate handling", selection: $duplicatePolicy) {
                Text("Skip").tag(DuplicateImportPolicy.skip)
                Text("Replace").tag(DuplicateImportPolicy.replace)
                Text("Keep Both").tag(DuplicateImportPolicy.keepBoth)
            }
            Button("Choose RemoteHub Export…", systemImage: "square.and.arrow.down") {
                readImport()
            }
            if let importError {
                Text(importError).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var about: some View {
        Section("RemoteHub") {
            LabeledContent("Version", value: "1.0.0")
            LabeledContent("Bundle identifier", value: AppConstants.bundleIdentifier)
            LabeledContent("Platform", value: "Native macOS 14+")
            LabeledContent("License", value: "MIT")
        }
        Section("Dependencies") {
            LabeledContent("SwiftTerm", value: "1.14.0 • MIT")
            LabeledContent("Citadel", value: "0.12.1 • MIT")
            LabeledContent("NIO SSH fork", value: "0.3.4 • Apache-2.0")
        }
        Section {
            Text("No cloud account, analytics, telemetry, or subscription.")
                .foregroundStyle(.secondary)
        }
    }

    private func chooseFreeRDP(settings: AppSettings) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.freeRDPPath = url.path
            Task { await checkRDP() }
        }
    }

    private func checkRDP() async {
        rdpStatus = nil
        rdpStatus = await FreeRDPDetector().detect(
            customExecutablePath: app.settings.freeRDPPath.nilIfBlank
        )
    }

    private func checkKeychain() async {
        let account = "health-check.\(UUID().uuidString.lowercased())"
        let value = "remotehub-health-\(UUID().uuidString)"
        do {
            try await app.credentialStore.save(value, account: account)
            let roundTrip = try await app.credentialStore.read(account: account)
            try await app.credentialStore.remove(account: account)
            securityMessage = roundTrip == value ? "Keychain is working." : "Keychain returned unexpected data."
        } catch {
            try? await app.credentialStore.remove(account: account)
            securityMessage = "Keychain check failed: \(Redactor.sanitize(error.localizedDescription))"
        }
    }

    private func writeExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "RemoteHubExport.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try ImportExportService.export(
                groups: app.library.groups,
                credentials: app.library.credentials,
                connections: app.library.connections,
                includeCredentialMetadata: includeCredentialMetadata
            )
            try data.write(to: url, options: .atomic)
        } catch {
            importError = Redactor.sanitize(error.localizedDescription)
        }
    }

    private func readImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            importPreview = try ImportExportService.preview(data: data)
            importError = nil
        } catch {
            importError = Redactor.sanitize(error.localizedDescription)
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case terminal
    case transfers
    case rdp
    case security
    case importExport
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .terminal: "Terminal"
        case .transfers: "File Transfers"
        case .rdp: "RDP"
        case .security: "Security"
        case .importExport: "Import / Export"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .terminal: "terminal"
        case .transfers: "arrow.up.arrow.down"
        case .rdp: "display"
        case .security: "lock.shield"
        case .importExport: "arrow.up.arrow.down.square"
        case .about: "info.circle"
        }
    }
}

private struct ImportPreviewView: View {
    let document: ExportDocument
    @Binding var policy: DuplicateImportPolicy
    let apply: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Import Preview").font(.title.bold())
            Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 10) {
                GridRow { Text("Connections"); Text("\(document.connections.count)") }
                GridRow { Text("Groups"); Text("\(document.groups.count)") }
                GridRow { Text("Credential metadata"); Text("\(document.credentialMetadata.count)") }
                GridRow { Text("Exported"); Text(document.exportedAt.formatted()) }
            }
            Picker("Duplicates", selection: $policy) {
                Text("Skip").tag(DuplicateImportPolicy.skip)
                Text("Replace").tag(DuplicateImportPolicy.replace)
                Text("Keep Both").tag(DuplicateImportPolicy.keepBoth)
            }
            Text("Imported profiles do not contain secrets. They will prompt until a credential is saved in Keychain.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel", action: cancel)
                Spacer()
                Button("Import", action: apply)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
