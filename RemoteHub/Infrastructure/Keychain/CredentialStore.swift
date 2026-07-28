import Foundation
import Security

enum SecretType: String, Codable, Sendable {
    case loginPassword = "login-password"
    case sshKeyPassphrase = "ssh-key-passphrase"

    func account(for credentialID: UUID) -> String {
        "\(credentialID.uuidString.lowercased()).\(rawValue)"
    }
}

protocol CredentialStore: Sendable {
    func save(_ secret: String, account: String) async throws
    func read(account: String) async throws -> String?
    func remove(account: String) async throws
    func contains(account: String) async throws -> Bool
}

actor KeychainCredentialStore: CredentialStore {
    private let service: String

    init(service: String = AppConstants.keychainService) {
        self.service = service
    }

    func save(_ secret: String, account: String) async throws {
        let data = Data(secret.utf8)
        let query = baseQuery(account: account)
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable: kCFBooleanFalse as Any
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw mappedError(status: updateStatus)
        }

        var addition = query
        attributes.forEach { key, value in addition[key] = value }
        let addStatus = SecItemAdd(addition as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw mappedError(status: addStatus) }
    }

    func read(account: String) async throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            if status == errSecSuccess {
                throw RemoteHubError(
                    .keychainUnavailable,
                    message: "The saved credential could not be decoded.",
                    recoverySuggestion: "Remove and save the credential again."
                )
            }
            throw mappedError(status: status)
        }
        return value
    }

    func remove(account: String) async throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw mappedError(status: status)
        }
    }

    func contains(account: String) async throws -> Bool {
        var query = baseQuery(account: account)
        query[kSecMatchLimit] = kSecMatchLimitOne
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound { return false }
        throw mappedError(status: status)
    }

    private func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrSynchronizable: kCFBooleanFalse as Any
        ]
    }

    func mappedError(status: OSStatus) -> RemoteHubError {
        AppLog.keychain.error("Keychain operation failed with OSStatus \(status, privacy: .public)")
        let details = SecCopyErrorMessageString(status, nil) as? String
        return RemoteHubError(
            .keychainUnavailable,
            message: "macOS Keychain is unavailable.",
            recoverySuggestion: "Unlock your Mac, verify Keychain access, and try again.",
            technicalDetails: details
        )
    }
}

actor InMemoryCredentialStore: CredentialStore {
    enum TestError: Error, Sendable {
        case forced
    }

    private var values: [String: String] = [:]
    private var shouldFail = false

    func setFailure(_ enabled: Bool) {
        shouldFail = enabled
    }

    func save(_ secret: String, account: String) async throws {
        try checkFailure()
        values[account] = secret
    }

    func read(account: String) async throws -> String? {
        try checkFailure()
        return values[account]
    }

    func remove(account: String) async throws {
        try checkFailure()
        values.removeValue(forKey: account)
    }

    func contains(account: String) async throws -> Bool {
        try checkFailure()
        return values[account] != nil
    }

    private func checkFailure() throws {
        if shouldFail { throw TestError.forced }
    }
}

enum SecretEdit: Equatable, Sendable {
    case unchanged
    case replace(String)
    case remove
}

enum CredentialSecretCoordinator {
    static func apply(
        edit: SecretEdit,
        type: SecretType,
        credentialID: UUID,
        existingAccount: String?,
        store: any CredentialStore
    ) async throws -> String? {
        switch edit {
        case .unchanged:
            return existingAccount
        case .replace(let secret):
            let account = type.account(for: credentialID)
            try await store.save(secret, account: account)
            return account
        case .remove:
            if let existingAccount {
                try await store.remove(account: existingAccount)
            }
            return nil
        }
    }
}
