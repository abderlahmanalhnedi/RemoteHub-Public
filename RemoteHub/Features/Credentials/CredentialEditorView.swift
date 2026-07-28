import AppKit
import SwiftUI

private struct CredentialDraft: Equatable {
    var displayName = ""
    var username = ""
    var domain = ""
    var authenticationType: AuthenticationType = .usernamePassword
    var privateKeyPath = ""
    var notes = ""
    var savePasswordSecurely = true
    var savePassphraseSecurely = true

    init() {}

    init(_ credential: CredentialProfile) {
        displayName = credential.displayName
        username = credential.username
        domain = credential.domain ?? ""
        authenticationType = credential.authenticationType
        privateKeyPath = credential.privateKeyDisplayPath ?? ""
        notes = credential.notes ?? ""
        savePasswordSecurely = credential.passwordKeychainAccount != nil
        savePassphraseSecurely = credential.passphraseKeychainAccount != nil
    }
}

struct CredentialEditorView: View {
    @Environment(AppContainer.self) private var app
    @Environment(\.dismiss) private var dismiss
    let credential: CredentialProfile?
    var onSaved: ((CredentialProfile) -> Void)?

    @State private var draft: CredentialDraft
    @State private var initialDraft: CredentialDraft
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var passphrase = ""
    @State private var passphraseConfirmation = ""
    @State private var replacesPassword: Bool
    @State private var replacesPassphrase: Bool
    @State private var removesPassword = false
    @State private var removesPassphrase = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(credential: CredentialProfile?, onSaved: ((CredentialProfile) -> Void)? = nil) {
        self.credential = credential
        self.onSaved = onSaved
        let value = credential.map(CredentialDraft.init) ?? CredentialDraft()
        _draft = State(initialValue: value)
        _initialDraft = State(initialValue: value)
        _replacesPassword = State(initialValue: credential == nil)
        _replacesPassphrase = State(initialValue: credential == nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(credential == nil ? "New Credential" : "Edit Credential")
                    .font(.title2.bold())
                Spacer()
                Text("\(linkedCount) linked connection\(linkedCount == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }
            .padding()

            Form {
                if let errorMessage {
                    Section { ErrorBanner(error: RemoteHubError(.validation, message: errorMessage)) }
                }
                Section("Identity") {
                    TextField("Display name", text: $draft.displayName)
                        .accessibilityIdentifier("credential.displayName")
                    TextField("Username", text: $draft.username)
                        .accessibilityIdentifier("credential.username")
                    TextField("Domain (optional)", text: $draft.domain)
                    Picker("Authentication", selection: $draft.authenticationType) {
                        ForEach(AuthenticationType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                if draft.authenticationType == .usernamePassword {
                    passwordSection
                }

                if draft.authenticationType == .sshPrivateKey ||
                    draft.authenticationType == .sshPrivateKeyWithPassphrase {
                    keySection
                }

                Section("Notes") {
                    TextEditor(text: $draft.notes).frame(minHeight: 72)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .accessibilityIdentifier("credential.cancel")
                Spacer()
                Button("Save") { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 600)
        .interactiveDismissDisabled(draft != initialDraft || !password.isEmpty || !passphrase.isEmpty)
    }

    @ViewBuilder
    private var passwordSection: some View {
        Section("Password") {
            if credential?.passwordKeychainAccount != nil && !replacesPassword && !removesPassword {
                Label("Stored securely in macOS Keychain", systemImage: "lock.fill")
                    .foregroundStyle(.green)
                Button("Replace Password") { replacesPassword = true }
                Button("Remove Stored Password", role: .destructive) { removesPassword = true }
            } else if removesPassword {
                Label("The stored password will be removed when you save.", systemImage: "trash")
                    .foregroundStyle(.red)
                Button("Keep Stored Password") { removesPassword = false }
            } else {
                SecureField("New password", text: $password)
                    .accessibilityIdentifier("credential.password")
                SecureField("Confirm password", text: $passwordConfirmation)
                Toggle("Save securely in macOS Keychain", isOn: $draft.savePasswordSecurely)
            }
        }
    }

    @ViewBuilder
    private var keySection: some View {
        Section("Private Key") {
            HStack {
                TextField("Private-key file", text: $draft.privateKeyPath)
                Button("Choose…") { choosePrivateKey() }
            }
            if draft.authenticationType == .sshPrivateKeyWithPassphrase {
                if credential?.passphraseKeychainAccount != nil && !replacesPassphrase && !removesPassphrase {
                    Label("Passphrase stored securely", systemImage: "lock.fill")
                        .foregroundStyle(.green)
                    Button("Replace Passphrase") { replacesPassphrase = true }
                    Button("Remove Stored Passphrase", role: .destructive) { removesPassphrase = true }
                } else if removesPassphrase {
                    Label("The stored passphrase will be removed when you save.", systemImage: "trash")
                        .foregroundStyle(.red)
                    Button("Keep Stored Passphrase") { removesPassphrase = false }
                } else {
                    SecureField("Key passphrase", text: $passphrase)
                    SecureField("Confirm passphrase", text: $passphraseConfirmation)
                    Toggle("Save passphrase securely", isOn: $draft.savePassphraseSecurely)
                }
            }
        }
    }

    private var linkedCount: Int {
        credential.map { app.library.linkedConnections(for: $0).count } ?? 0
    }

    private func choosePrivateKey() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Private Key"
        if panel.runModal() == .OK, let url = panel.url {
            draft.privateKeyPath = url.path
        }
    }

    private func save() async {
        errorMessage = nil
        let name = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Display name is required."
            return
        }
        let usernameIssues = Validators.username(draft.username, authenticationType: draft.authenticationType)
        guard usernameIssues.isEmpty else {
            errorMessage = usernameIssues[0].message
            return
        }
        if replacesPassword, !password.isEmpty, password != passwordConfirmation {
            errorMessage = "Password confirmation does not match."
            return
        }
        if replacesPassphrase, !passphrase.isEmpty, passphrase != passphraseConfirmation {
            errorMessage = "Passphrase confirmation does not match."
            return
        }
        if draft.authenticationType == .sshPrivateKey ||
            draft.authenticationType == .sshPrivateKeyWithPassphrase {
            let keyIssues = Validators.privateKey(url: URL(fileURLWithPath: draft.privateKeyPath))
            guard keyIssues.isEmpty else {
                errorMessage = keyIssues[0].message
                return
            }
        }

        isSaving = true
        let model = credential ?? CredentialProfile(displayName: name)
        do {
            let passwordEdit: SecretEdit = removesPassword
                ? .remove
                : (replacesPassword && draft.savePasswordSecurely && !password.isEmpty ? .replace(password) : .unchanged)
            model.passwordKeychainAccount = try await CredentialSecretCoordinator.apply(
                edit: passwordEdit,
                type: .loginPassword,
                credentialID: model.id,
                existingAccount: model.passwordKeychainAccount,
                store: app.credentialStore
            )
            let passphraseEdit: SecretEdit = removesPassphrase
                ? .remove
                : (replacesPassphrase && draft.savePassphraseSecurely && !passphrase.isEmpty ? .replace(passphrase) : .unchanged)
            model.passphraseKeychainAccount = try await CredentialSecretCoordinator.apply(
                edit: passphraseEdit,
                type: .sshKeyPassphrase,
                credentialID: model.id,
                existingAccount: model.passphraseKeychainAccount,
                store: app.credentialStore
            )
            model.displayName = name
            model.username = draft.username.trimmingCharacters(in: .whitespacesAndNewlines)
            model.domain = draft.domain.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            model.authenticationType = draft.authenticationType
            model.privateKeyDisplayPath = draft.privateKeyPath.nilIfEmpty
            model.privateKeyBookmarkData = draft.privateKeyPath.nilIfEmpty.map { Data($0.utf8) }
            model.notes = draft.notes.nilIfEmpty
            try app.library.saveCredential(model)
            onSaved?(model)
            initialDraft = draft
            dismiss()
        } catch {
            errorMessage = Redactor.sanitize(error.localizedDescription)
        }
        isSaving = false
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
