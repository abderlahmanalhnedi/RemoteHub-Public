import Foundation
import Observation

struct HostTrustRequest: Identifiable, Equatable {
    let id = UUID()
    let evaluation: HostTrustEvaluation
}

@MainActor
@Observable
final class HostTrustPromptCenter {
    private(set) var request: HostTrustRequest?
    @ObservationIgnored
    private var continuation: CheckedContinuation<HostTrustDecision, Error>?

    func prompt(_ evaluation: HostTrustEvaluation) async throws -> HostTrustDecision {
        guard request == nil else {
            throw RemoteHubError(.hostKeyUnknown, message: "Another host-key decision is already pending.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            request = HostTrustRequest(evaluation: evaluation)
        }
    }

    func resolve(_ decision: HostTrustDecision) {
        let pending = continuation
        continuation = nil
        request = nil
        pending?.resume(returning: decision)
    }

    func cancel() {
        let pending = continuation
        continuation = nil
        request = nil
        pending?.resume(throwing: CancellationError())
    }
}

struct SecretPromptRequest: Identifiable, Equatable {
    let id = UUID()
    let connectionName: String
    let suggestedUsername: String
    let needsUsername: Bool
}

struct PromptedCredential: Equatable, Sendable {
    let username: String
    let password: String
}

@MainActor
@Observable
final class SecretPromptCenter {
    private(set) var request: SecretPromptRequest?
    @ObservationIgnored
    private var continuation: CheckedContinuation<PromptedCredential, Error>?

    func prompt(
        connectionName: String,
        suggestedUsername: String,
        needsUsername: Bool
    ) async throws -> PromptedCredential {
        guard request == nil else {
            throw RemoteHubError(.authenticationFailed, message: "Another credential prompt is already open.")
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            request = SecretPromptRequest(
                connectionName: connectionName,
                suggestedUsername: suggestedUsername,
                needsUsername: needsUsername
            )
        }
    }

    func resolve(username: String, password: String) {
        let pending = continuation
        continuation = nil
        request = nil
        pending?.resume(returning: PromptedCredential(username: username, password: password))
    }

    func cancel() {
        let pending = continuation
        continuation = nil
        request = nil
        pending?.resume(throwing: CancellationError())
    }
}
