import Foundation

struct ExportDocument: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let application: String
    let groups: [ExportGroup]
    let credentialMetadata: [ExportCredentialMetadata]
    let connections: [ExportConnection]
}

struct ExportGroup: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let sortOrder: Int
}

struct ExportCredentialMetadata: Codable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let username: String
    let domain: String?
    let authenticationType: AuthenticationType
}

struct ExportConnection: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let kind: ConnectionKind
    let host: String
    let port: Int
    let groupID: UUID?
    let credentialMetadataID: UUID?
    let tags: [String]
    let notes: String?
    let isFavorite: Bool
    let protocolSettings: ProtocolSettings
}

enum DuplicateImportPolicy: String, Codable, CaseIterable, Sendable {
    case skip
    case replace
    case keepBoth
}

enum ImportExportService {
    static func export(
        groups: [ConnectionGroup],
        credentials: [CredentialProfile],
        connections: [ConnectionProfile],
        includeCredentialMetadata: Bool,
        exportedAt: Date = .now
    ) throws -> Data {
        let document = ExportDocument(
            schemaVersion: AppConstants.exportSchemaVersion,
            exportedAt: exportedAt,
            application: AppConstants.productName,
            groups: groups.map { ExportGroup(id: $0.id, name: $0.name, sortOrder: $0.sortOrder) },
            credentialMetadata: includeCredentialMetadata ? credentials.map {
                ExportCredentialMetadata(
                    id: $0.id,
                    displayName: $0.displayName,
                    username: $0.username,
                    domain: $0.domain,
                    authenticationType: $0.authenticationType
                )
            } : [],
            connections: connections.map {
                ExportConnection(
                    id: $0.id,
                    name: $0.name,
                    kind: $0.kind,
                    host: $0.host,
                    port: $0.port,
                    groupID: $0.groupID,
                    credentialMetadataID: includeCredentialMetadata ? $0.credentialProfileID : nil,
                    tags: $0.tags,
                    notes: $0.notes,
                    isFavorite: $0.isFavorite,
                    protocolSettings: $0.protocolSettings
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    static func preview(data: Data) throws -> ExportDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document: ExportDocument
        do {
            document = try decoder.decode(ExportDocument.self, from: data)
        } catch {
            throw RemoteHubError(
                .importExportFailure,
                message: "The selected file is not a valid RemoteHub export.",
                recoverySuggestion: "Choose an unmodified version-one RemoteHub JSON export.",
                technicalDetails: error.localizedDescription
            )
        }
        guard document.schemaVersion == AppConstants.exportSchemaVersion else {
            throw RemoteHubError(
                .importExportFailure,
                message: "This export schema version is not supported.",
                recoverySuggestion: "Use a version-one export or update RemoteHub."
            )
        }
        return document
    }
}
