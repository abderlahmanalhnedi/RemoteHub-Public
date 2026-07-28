import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class LibraryStore {
    private let context: ModelContext

    private(set) var groups: [ConnectionGroup] = []
    private(set) var credentials: [CredentialProfile] = []
    private(set) var connections: [ConnectionProfile] = []
    private(set) var knownHosts: [KnownHostRecord] = []
    private(set) var attempts: [ConnectionAttempt] = []
    private(set) var lastError: RemoteHubError?

    init(context: ModelContext) {
        self.context = context
        reload()
    }

    func reload() {
        do {
            groups = try context.fetch(FetchDescriptor<ConnectionGroup>()).sorted {
                ($0.sortOrder, $0.name.localizedLowercase) < ($1.sortOrder, $1.name.localizedLowercase)
            }
            credentials = try context.fetch(FetchDescriptor<CredentialProfile>()).sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            connections = try context.fetch(FetchDescriptor<ConnectionProfile>())
            knownHosts = try context.fetch(FetchDescriptor<KnownHostRecord>())
            attempts = try context.fetch(FetchDescriptor<ConnectionAttempt>()).sorted {
                $0.startedAt > $1.startedAt
            }
            lastError = nil
        } catch {
            lastError = persistenceError(error)
        }
    }

    func saveGroup(_ group: ConnectionGroup) throws {
        let issues = Validators.groupName(
            group.name,
            existingNames: groups.map(\.name),
            excluding: groups.contains(where: { $0.id == group.id }) ? group.name : nil
        )
        guard issues.isEmpty else {
            throw RemoteHubError(.validation, message: issues[0].message)
        }
        if !groups.contains(where: { $0.id == group.id }) {
            context.insert(group)
        }
        group.updatedAt = .now
        try saveAndReload()
    }

    func deleteGroup(_ group: ConnectionGroup) throws {
        for connection in connections where connection.groupID == group.id {
            connection.groupID = nil
            connection.updatedAt = .now
        }
        context.delete(group)
        try saveAndReload()
    }

    func saveCredential(_ credential: CredentialProfile) throws {
        guard !credential.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RemoteHubError(.validation, message: "Credential name is required.")
        }
        if !credentials.contains(where: { $0.id == credential.id }) {
            context.insert(credential)
        }
        credential.updatedAt = .now
        try saveAndReload()
    }

    func linkedConnections(for credential: CredentialProfile) -> [ConnectionProfile] {
        connections.filter { $0.credentialProfileID == credential.id }
    }

    func deleteCredential(_ credential: CredentialProfile, confirmed: Bool) throws {
        let linked = linkedConnections(for: credential)
        guard linked.isEmpty || confirmed else {
            throw RemoteHubError(
                .validation,
                message: "This credential is used by \(linked.count) connection(s).",
                recoverySuggestion: "Confirm deletion after reviewing the linked connections."
            )
        }
        for connection in linked {
            connection.credentialProfileID = nil
            connection.updatedAt = .now
        }
        context.delete(credential)
        try saveAndReload()
    }

    func saveConnection(_ connection: ConnectionProfile) throws {
        let issues = Validators.connectionName(connection.name)
            + Validators.host(connection.host)
            + Validators.port(connection.port)
        guard issues.isEmpty else {
            throw RemoteHubError(.validation, message: issues[0].message)
        }
        if !connections.contains(where: { $0.id == connection.id }) {
            context.insert(connection)
        }
        connection.updatedAt = .now
        try saveAndReload()
    }

    func duplicate(_ connection: ConnectionProfile) throws -> ConnectionProfile {
        let copy = ConnectionProfile(
            name: "\(connection.name) Copy",
            kind: connection.kind,
            host: connection.host,
            port: connection.port,
            groupID: connection.groupID,
            credentialProfileID: connection.credentialProfileID,
            tags: connection.tags,
            notes: connection.notes,
            isFavorite: connection.isFavorite,
            sortOrder: connection.sortOrder + 1,
            settings: connection.protocolSettings
        )
        try saveConnection(copy)
        return copy
    }

    func deleteConnection(_ connection: ConnectionProfile) throws {
        context.delete(connection)
        try saveAndReload()
    }

    func move(_ connection: ConnectionProfile, to groupID: UUID?) throws {
        connection.groupID = groupID
        connection.updatedAt = .now
        try saveAndReload()
    }

    func toggleFavorite(_ connection: ConnectionProfile) throws {
        connection.isFavorite.toggle()
        connection.updatedAt = .now
        try saveAndReload()
    }

    func recordAttempt(
        for connection: ConnectionProfile,
        startedAt: Date,
        outcome: AttemptOutcome,
        error: RemoteHubError? = nil
    ) throws {
        let attempt = ConnectionAttempt(
            connectionID: connection.id,
            startedAt: startedAt,
            endedAt: .now,
            outcome: outcome,
            errorCategory: error?.category
        )
        context.insert(attempt)
        connection.lastUsedAt = outcome == .success ? .now : connection.lastUsedAt
        connection.lastResult = switch outcome {
        case .success: .success
        case .failure: .failure
        case .cancelled: .cancelled
        }
        connection.updatedAt = .now

        let allAttempts = try context.fetch(FetchDescriptor<ConnectionAttempt>()).sorted {
            $0.startedAt > $1.startedAt
        }
        for oldAttempt in allAttempts.dropFirst(AppConstants.maximumConnectionAttempts) {
            context.delete(oldAttempt)
        }
        try saveAndReload()
    }

    func clearKnownHosts() throws {
        for host in knownHosts { context.delete(host) }
        try saveAndReload()
    }

    func applyImport(_ document: ExportDocument, policy: DuplicateImportPolicy) throws {
        var groupIDs: [UUID: UUID] = [:]
        for imported in document.groups {
            if let existing = groups.first(where: {
                $0.id == imported.id || $0.name.localizedCaseInsensitiveCompare(imported.name) == .orderedSame
            }) {
                switch policy {
                case .skip:
                    groupIDs[imported.id] = existing.id
                case .replace:
                    existing.name = imported.name
                    existing.sortOrder = imported.sortOrder
                    existing.updatedAt = .now
                    groupIDs[imported.id] = existing.id
                case .keepBoth:
                    let group = ConnectionGroup(name: uniqueGroupName(imported.name), sortOrder: imported.sortOrder)
                    context.insert(group)
                    groupIDs[imported.id] = group.id
                }
            } else {
                let group = ConnectionGroup(id: imported.id, name: imported.name, sortOrder: imported.sortOrder)
                context.insert(group)
                groupIDs[imported.id] = group.id
            }
        }

        var credentialIDs: [UUID: UUID] = [:]
        for imported in document.credentialMetadata {
            if let existing = credentials.first(where: { $0.id == imported.id }) {
                switch policy {
                case .skip:
                    credentialIDs[imported.id] = existing.id
                case .replace:
                    existing.displayName = imported.displayName
                    existing.username = imported.username
                    existing.domain = imported.domain
                    existing.authenticationType = imported.authenticationType
                    existing.updatedAt = .now
                    credentialIDs[imported.id] = existing.id
                case .keepBoth:
                    let credential = makeImportedCredential(imported, id: UUID(), suffix: " (Imported)")
                    context.insert(credential)
                    credentialIDs[imported.id] = credential.id
                }
            } else {
                let credential = makeImportedCredential(imported, id: imported.id, suffix: "")
                context.insert(credential)
                credentialIDs[imported.id] = credential.id
            }
        }

        for imported in document.connections {
            let duplicate = connections.first {
                $0.id == imported.id ||
                ($0.name.localizedCaseInsensitiveCompare(imported.name) == .orderedSame
                    && $0.host.localizedCaseInsensitiveCompare(imported.host) == .orderedSame
                    && $0.kind == imported.kind)
            }
            if let duplicate {
                switch policy {
                case .skip:
                    continue
                case .replace:
                    try update(
                        duplicate,
                        from: imported,
                        groupID: imported.groupID.flatMap { groupIDs[$0] },
                        credentialID: imported.credentialMetadataID.flatMap { credentialIDs[$0] }
                    )
                case .keepBoth:
                    let copy = makeImportedConnection(
                        imported,
                        id: UUID(),
                        name: "\(imported.name) (Imported)",
                        groupID: imported.groupID.flatMap { groupIDs[$0] },
                        credentialID: imported.credentialMetadataID.flatMap { credentialIDs[$0] }
                    )
                    context.insert(copy)
                }
            } else {
                let connection = makeImportedConnection(
                    imported,
                    id: imported.id,
                    name: imported.name,
                    groupID: imported.groupID.flatMap { groupIDs[$0] },
                    credentialID: imported.credentialMetadataID.flatMap { credentialIDs[$0] }
                )
                context.insert(connection)
            }
        }
        try saveAndReload()
    }

    private func saveAndReload() throws {
        do {
            try context.save()
            reload()
        } catch {
            let mapped = persistenceError(error)
            lastError = mapped
            throw mapped
        }
    }

    private func persistenceError(_ error: Error) -> RemoteHubError {
        RemoteHubError(
            .persistenceFailure,
            message: "RemoteHub could not save its local data.",
            recoverySuggestion: "Check available disk space and try again.",
            technicalDetails: error.localizedDescription
        )
    }

    private func uniqueGroupName(_ base: String) -> String {
        var index = 2
        var value = "\(base) (Imported)"
        while groups.contains(where: { $0.name.localizedCaseInsensitiveCompare(value) == .orderedSame }) {
            value = "\(base) (Imported \(index))"
            index += 1
        }
        return value
    }

    private func makeImportedCredential(
        _ imported: ExportCredentialMetadata,
        id: UUID,
        suffix: String
    ) -> CredentialProfile {
        CredentialProfile(
            id: id,
            displayName: imported.displayName + suffix,
            username: imported.username,
            domain: imported.domain,
            authenticationType: imported.authenticationType,
            notes: "Imported metadata — credentials required"
        )
    }

    private func makeImportedConnection(
        _ imported: ExportConnection,
        id: UUID,
        name: String,
        groupID: UUID?,
        credentialID: UUID?
    ) -> ConnectionProfile {
        ConnectionProfile(
            id: id,
            name: name,
            kind: imported.kind,
            host: imported.host,
            port: imported.port,
            groupID: groupID,
            credentialProfileID: credentialID,
            tags: imported.tags,
            notes: imported.notes,
            isFavorite: imported.isFavorite,
            settings: imported.protocolSettings
        )
    }

    private func update(
        _ connection: ConnectionProfile,
        from imported: ExportConnection,
        groupID: UUID?,
        credentialID: UUID?
    ) throws {
        connection.name = imported.name
        connection.kind = imported.kind
        connection.host = imported.host
        connection.port = imported.port
        connection.groupID = groupID
        connection.credentialProfileID = credentialID
        connection.tags = imported.tags
        connection.notes = imported.notes
        connection.isFavorite = imported.isFavorite
        try connection.updateProtocolSettings(imported.protocolSettings)
        connection.updatedAt = .now
    }
}

@MainActor
final class SwiftDataKnownHostStore: KnownHostStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func record(host: String, port: Int, algorithm: String) async throws -> KnownHostSnapshot? {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return try context.fetch(FetchDescriptor<KnownHostRecord>()).first {
            $0.normalizedHost == normalized &&
                $0.port == port &&
                $0.keyAlgorithm == algorithm
        }.map {
            KnownHostSnapshot(
                normalizedHost: $0.normalizedHost,
                port: $0.port,
                algorithm: $0.keyAlgorithm,
                fingerprint: $0.sha256Fingerprint,
                publicKeyData: $0.publicKeyData
            )
        }
    }

    func save(_ candidate: HostKeyCandidate) async throws {
        if let existing = try find(candidate) {
            existing.keyAlgorithm = candidate.algorithm
            existing.sha256Fingerprint = candidate.sha256Fingerprint
            existing.publicKeyData = candidate.publicKeyData
            existing.lastSeenAt = .now
        } else {
            context.insert(KnownHostRecord(
                normalizedHost: candidate.normalizedHost,
                port: candidate.port,
                keyAlgorithm: candidate.algorithm,
                sha256Fingerprint: candidate.sha256Fingerprint,
                publicKeyData: candidate.publicKeyData
            ))
        }
        try context.save()
    }

    func replace(_ candidate: HostKeyCandidate, confirmed: Bool) async throws {
        guard confirmed else {
            throw RemoteHubError(.hostKeyChanged, message: "Host-key replacement was not confirmed.")
        }
        if let existing = try find(candidate) {
            existing.keyAlgorithm = candidate.algorithm
            existing.sha256Fingerprint = candidate.sha256Fingerprint
            existing.publicKeyData = candidate.publicKeyData
            existing.lastSeenAt = .now
        } else {
            try await save(candidate)
            return
        }
        try context.save()
    }

    func removeAll() async throws {
        for item in try context.fetch(FetchDescriptor<KnownHostRecord>()) {
            context.delete(item)
        }
        try context.save()
    }

    private func find(_ candidate: HostKeyCandidate) throws -> KnownHostRecord? {
        try context.fetch(FetchDescriptor<KnownHostRecord>()).first {
            $0.normalizedHost == candidate.normalizedHost &&
                $0.port == candidate.port &&
                $0.keyAlgorithm == candidate.algorithm
        }
    }
}
