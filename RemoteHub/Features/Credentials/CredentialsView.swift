import SwiftUI

struct CredentialsView: View {
    @Environment(AppContainer.self) private var app
    @State private var deleteTarget: CredentialProfile?
    @State private var operationError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Credentials").font(.title.bold())
                    Text("Reusable metadata with secrets stored separately in macOS Keychain.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("New Credential", systemImage: "plus") {
                    app.router.showsNewCredential = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            if app.library.credentials.isEmpty {
                ContentUnavailableView {
                    Label("No credential profiles", systemImage: "key")
                } description: {
                    Text("Create one credential and link it to multiple connections.")
                } actions: {
                    Button("Create Credential") { app.router.showsNewCredential = true }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(app.library.credentials) { credential in
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(credential.displayName).fontWeight(.medium)
                            Text(summary(credential))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if credential.passwordKeychainAccount != nil || credential.passphraseKeychainAccount != nil {
                            Label("Stored securely", systemImage: "lock.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                        Text("\(app.library.linkedConnections(for: credential).count) linked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        app.router.credentialEditorID = credential.id
                    }
                    .contextMenu {
                        Button("Edit") { app.router.credentialEditorID = credential.id }
                        Button("Delete", role: .destructive) { deleteTarget = credential }
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete credential profile?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Credential and Saved Secrets", role: .destructive) {
                guard let target = deleteTarget else { return }
                Task { await delete(target) }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            if let target = deleteTarget {
                let names = app.library.linkedConnections(for: target).map(\.name).joined(separator: ", ")
                Text(names.isEmpty
                    ? "This removes its saved Keychain secrets."
                    : "Linked connections will require another credential: \(names)")
            }
        }
        .alert(
            "Credential Operation Failed",
            isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )
        ) {
            Button("Dismiss", role: .cancel) { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
    }

    private func summary(_ credential: CredentialProfile) -> String {
        let identity = [credential.domain, credential.username].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\\")
        return identity.isEmpty
            ? credential.authenticationType.displayName
            : "\(identity) • \(credential.authenticationType.displayName)"
    }

    private func delete(_ credential: CredentialProfile) async {
        do {
            if let account = credential.passwordKeychainAccount {
                try await app.credentialStore.remove(account: account)
            }
            if let account = credential.passphraseKeychainAccount {
                try await app.credentialStore.remove(account: account)
            }
            try app.library.deleteCredential(credential, confirmed: true)
        } catch {
            operationError = Redactor.sanitize(error.localizedDescription)
            app.library.reload()
        }
        deleteTarget = nil
    }
}
