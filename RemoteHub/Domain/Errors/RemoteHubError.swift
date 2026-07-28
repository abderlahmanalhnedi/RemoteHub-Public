import Foundation

struct RemoteHubError: LocalizedError, Equatable, Sendable {
    enum Category: String, Codable, CaseIterable, Sendable {
        case validation
        case dns
        case timeout
        case connectionRefused
        case networkUnavailable
        case authenticationFailed
        case hostKeyUnknown
        case hostKeyChanged
        case certificateError
        case unsupportedAlgorithm
        case unsupportedKeyFormat
        case permissionDenied
        case fileNotFound
        case transferCancelled
        case insufficientDiskSpace
        case keychainUnavailable
        case freeRDPMissing
        case incompatibleFreeRDP
        case processLaunchFailed
        case duplicateSession
        case networkLevelAuthenticationFailed
        case externalClientCrash
        case persistenceFailure
        case importExportFailure
        case unknown
    }

    let category: Category
    let message: String
    let recoverySuggestion: String?
    let technicalDetails: String?

    var errorDescription: String? { message }

    var diagnostics: String {
        var lines = [
            "Category: \(category.rawValue)",
            "Message: \(message)"
        ]
        if let recoverySuggestion {
            lines.append("Recovery: \(recoverySuggestion)")
        }
        if let technicalDetails {
            lines.append("Details: \(technicalDetails)")
        }
        return Redactor.sanitize(lines.joined(separator: "\n"))
    }

    init(
        _ category: Category,
        message: String,
        recoverySuggestion: String? = nil,
        technicalDetails: String? = nil
    ) {
        self.category = category
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.technicalDetails = technicalDetails.map(Redactor.sanitize)
    }
}
