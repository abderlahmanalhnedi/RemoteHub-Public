import SwiftUI

struct PromptSheets: ViewModifier {
    @Environment(AppContainer.self) private var app

    func body(content: Content) -> some View {
        content.overlay {
            if let request = app.hostTrustPrompt.request {
                modalBackdrop {
                    HostTrustPromptCard(request: request)
                }
            } else if let request = app.secretPrompt.request {
                modalBackdrop {
                    SecretPromptCard(request: request)
                }
            }
        }
    }

    private func modalBackdrop<Prompt: View>(@ViewBuilder prompt: () -> Prompt) -> some View {
        ZStack {
            Color.black.opacity(0.42).ignoresSafeArea()
            prompt()
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .shadow(radius: 24)
                .frame(maxWidth: 520)
                .padding()
        }
        .transition(.opacity)
        .zIndex(100)
    }
}

private struct HostTrustPromptCard: View {
    @Environment(AppContainer.self) private var app
    let request: HostTrustRequest
    @State private var showsReplacementConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch request.evaluation {
            case .unknown(let candidate):
                Label("Unknown SSH Host Key", systemImage: "questionmark.shield")
                    .font(.title2.bold())
                Text("Confirm this fingerprint through a trusted channel before continuing.")
                    .foregroundStyle(.secondary)
                fingerprint(candidate)
                HStack {
                    Button("Cancel", role: .cancel) { app.hostTrustPrompt.cancel() }
                    Spacer()
                    Button("Trust Once") { app.hostTrustPrompt.resolve(.trustOnce) }
                    Button("Trust and Save") { app.hostTrustPrompt.resolve(.trustAndSave) }
                        .buttonStyle(.borderedProminent)
                }
            case .changed(let saved, let candidate):
                Label("SSH Host Key Changed", systemImage: "exclamationmark.shield.fill")
                    .font(.title2.bold())
                    .foregroundStyle(.red)
                Text("The connection is blocked. This can indicate a rebuilt server or an active interception attempt.")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Saved fingerprint").font(.caption).foregroundStyle(.secondary)
                    Text(saved).font(.system(.body, design: .monospaced))
                    Text("Presented fingerprint").font(.caption).foregroundStyle(.secondary)
                    Text(candidate.sha256Fingerprint).font(.system(.body, design: .monospaced))
                }
                .textSelection(.enabled)
                HStack {
                    Button("Review Replacement…") {
                        showsReplacementConfirmation = true
                    }
                    Spacer()
                    Button("Block Connection") { app.hostTrustPrompt.cancel() }
                        .buttonStyle(.borderedProminent)
                }
            case .trusted:
                EmptyView()
            }
        }
        .accessibilityElement(children: .contain)
        .confirmationDialog(
            "Replace the saved SSH host key?",
            isPresented: $showsReplacementConfirmation,
            titleVisibility: .visible
        ) {
            Button("I Verified It — Replace Key", role: .destructive) {
                app.hostTrustPrompt.resolve(.replaceConfirmed)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only continue after verifying the new fingerprint with the server administrator through a separate trusted channel.")
        }
    }

    private func fingerprint(_ candidate: HostKeyCandidate) -> some View {
        let endpoint = PortDisplayFormatter.endpoint(
            host: candidate.host,
            port: candidate.port
        )
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Host").foregroundStyle(.secondary)
                Text(verbatim: endpoint)
                    .accessibilityLabel(Text(verbatim: endpoint))
            }
            GridRow {
                Text("Algorithm").foregroundStyle(.secondary)
                Text(candidate.algorithm)
            }
            GridRow {
                Text("SHA-256").foregroundStyle(.secondary)
                Text(candidate.sha256Fingerprint)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }
}

private struct SecretPromptCard: View {
    @Environment(AppContainer.self) private var app
    let request: SecretPromptRequest
    @State private var username: String
    @State private var password = ""

    init(request: SecretPromptRequest) {
        self.request = request
        _username = State(initialValue: request.suggestedUsername)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Credentials Required", systemImage: "key")
                .font(.title2.bold())
            Text(request.connectionName)
                .foregroundStyle(.secondary)
            if request.needsUsername {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
            } else {
                LabeledContent("Username", value: username)
            }
            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
            Text("This value is used for this connection attempt only and is not saved.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel", role: .cancel) { app.secretPrompt.cancel() }
                Spacer()
                Button("Connect") {
                    app.secretPrompt.resolve(username: username, password: password)
                }
                .buttonStyle(.borderedProminent)
                .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
