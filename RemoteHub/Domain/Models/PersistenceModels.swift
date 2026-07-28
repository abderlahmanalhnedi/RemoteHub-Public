import Foundation
import SwiftData

@Model
final class ConnectionGroup: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CredentialProfile: Identifiable {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var username: String
    var domain: String?
    var authenticationTypeRaw: String
    var passwordKeychainAccount: String?
    var privateKeyBookmarkData: Data?
    var privateKeyDisplayPath: String?
    var passphraseKeychainAccount: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    var authenticationType: AuthenticationType {
        get { AuthenticationType(rawValue: authenticationTypeRaw) ?? .askEveryTime }
        set { authenticationTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        displayName: String,
        username: String = "",
        domain: String? = nil,
        authenticationType: AuthenticationType = .usernamePassword,
        passwordKeychainAccount: String? = nil,
        privateKeyBookmarkData: Data? = nil,
        privateKeyDisplayPath: String? = nil,
        passphraseKeychainAccount: String? = nil,
        notes: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        self.domain = domain?.nilIfBlank
        self.authenticationTypeRaw = authenticationType.rawValue
        self.passwordKeychainAccount = passwordKeychainAccount
        self.privateKeyBookmarkData = privateKeyBookmarkData
        self.privateKeyDisplayPath = privateKeyDisplayPath
        self.passphraseKeychainAccount = passphraseKeychainAccount
        self.notes = notes?.nilIfBlank
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class ConnectionProfile: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var kindRaw: String
    var host: String
    var port: Int
    var groupID: UUID?
    var credentialProfileID: UUID?
    var tags: [String]
    var notes: String?
    var isFavorite: Bool
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var lastResultRaw: String
    var settingsData: Data

    var kind: ConnectionKind {
        get { ConnectionKind(rawValue: kindRaw) ?? .ssh }
        set { kindRaw = newValue.rawValue }
    }

    var lastResult: ConnectionResult {
        get { ConnectionResult(rawValue: lastResultRaw) ?? .never }
        set { lastResultRaw = newValue.rawValue }
    }

    var protocolSettings: ProtocolSettings {
        (try? JSONDecoder().decode(ProtocolSettings.self, from: settingsData)) ?? .default
    }

    func updateProtocolSettings(_ settings: ProtocolSettings) throws {
        settingsData = try JSONEncoder().encode(settings)
        updatedAt = .now
    }

    init(
        id: UUID = UUID(),
        name: String,
        kind: ConnectionKind,
        host: String,
        port: Int? = nil,
        groupID: UUID? = nil,
        credentialProfileID: UUID? = nil,
        tags: [String] = [],
        notes: String? = nil,
        isFavorite: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastUsedAt: Date? = nil,
        lastResult: ConnectionResult = .never,
        settings: ProtocolSettings = .default
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kindRaw = kind.rawValue
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.port = port ?? kind.defaultPort
        self.groupID = groupID
        self.credentialProfileID = credentialProfileID
        self.tags = tags.normalizedTags
        self.notes = notes?.nilIfBlank
        self.isFavorite = isFavorite
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.lastResultRaw = lastResult.rawValue
        self.settingsData = (try? JSONEncoder().encode(settings)) ?? Data()
    }
}

@Model
final class KnownHostRecord: Identifiable {
    @Attribute(.unique) var id: UUID
    var normalizedHost: String
    var port: Int
    var keyAlgorithm: String
    var sha256Fingerprint: String
    var publicKeyData: Data?
    var firstSeenAt: Date
    var lastSeenAt: Date
    var note: String?

    init(
        id: UUID = UUID(),
        normalizedHost: String,
        port: Int,
        keyAlgorithm: String,
        sha256Fingerprint: String,
        publicKeyData: Data? = nil,
        firstSeenAt: Date = .now,
        lastSeenAt: Date = .now,
        note: String? = nil
    ) {
        self.id = id
        self.normalizedHost = normalizedHost.lowercased()
        self.port = port
        self.keyAlgorithm = keyAlgorithm
        self.sha256Fingerprint = sha256Fingerprint
        self.publicKeyData = publicKeyData
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.note = note?.nilIfBlank
    }
}

@Model
final class ConnectionAttempt: Identifiable {
    @Attribute(.unique) var id: UUID
    var connectionID: UUID
    var startedAt: Date
    var endedAt: Date?
    var outcomeRaw: String
    var errorCategoryRaw: String?

    var outcome: AttemptOutcome {
        get { AttemptOutcome(rawValue: outcomeRaw) ?? .failure }
        set { outcomeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        connectionID: UUID,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        outcome: AttemptOutcome,
        errorCategory: RemoteHubError.Category? = nil
    ) {
        self.id = id
        self.connectionID = connectionID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.outcomeRaw = outcome.rawValue
        self.errorCategoryRaw = errorCategory?.rawValue
    }
}

enum RemoteHubSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            ConnectionGroup.self,
            CredentialProfile.self,
            ConnectionProfile.self,
            KnownHostRecord.self,
            ConnectionAttempt.self
        ]
    }
}

enum RemoteHubMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [RemoteHubSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Array where Element == String {
    var normalizedTags: [String] {
        var seen = Set<String>()
        return compactMap {
            let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = value.lowercased()
            guard !value.isEmpty, seen.insert(key).inserted else { return nil }
            return value
        }
    }
}
