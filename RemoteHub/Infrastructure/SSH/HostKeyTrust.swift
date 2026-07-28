import Foundation

struct HostKeyCandidate: Equatable, Sendable {
    let host: String
    let port: Int
    let algorithm: String
    let sha256Fingerprint: String
    let publicKeyData: Data?

    var normalizedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum HostTrustEvaluation: Equatable, Sendable {
    case unknown(HostKeyCandidate)
    case trusted
    case changed(savedFingerprint: String, candidate: HostKeyCandidate)
}

enum HostTrustDecision: Equatable, Sendable {
    case cancel
    case trustOnce
    case trustAndSave
    case replaceConfirmed
}

protocol KnownHostStore: Sendable {
    func record(host: String, port: Int, algorithm: String) async throws -> KnownHostSnapshot?
    func save(_ candidate: HostKeyCandidate) async throws
    func replace(_ candidate: HostKeyCandidate, confirmed: Bool) async throws
    func removeAll() async throws
}

struct KnownHostSnapshot: Equatable, Sendable {
    let normalizedHost: String
    let port: Int
    let algorithm: String
    let fingerprint: String
    let publicKeyData: Data?
}

actor InMemoryKnownHostStore: KnownHostStore {
    private var values: [String: KnownHostSnapshot] = [:]

    func record(host: String, port: Int, algorithm: String) async throws -> KnownHostSnapshot? {
        values[key(host: host, port: port, algorithm: algorithm)]
    }

    func save(_ candidate: HostKeyCandidate) async throws {
        values[key(
            host: candidate.host,
            port: candidate.port,
            algorithm: candidate.algorithm
        )] = snapshot(candidate)
    }

    func replace(_ candidate: HostKeyCandidate, confirmed: Bool) async throws {
        guard confirmed else {
            throw RemoteHubError(
                .hostKeyChanged,
                message: "Replacing a changed host key requires explicit confirmation."
            )
        }
        values[key(
            host: candidate.host,
            port: candidate.port,
            algorithm: candidate.algorithm
        )] = snapshot(candidate)
    }

    func removeAll() async throws {
        values.removeAll()
    }

    private func key(host: String, port: Int, algorithm: String) -> String {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(normalizedHost):\(port):\(algorithm.lowercased())"
    }

    private func snapshot(_ candidate: HostKeyCandidate) -> KnownHostSnapshot {
        KnownHostSnapshot(
            normalizedHost: candidate.normalizedHost,
            port: candidate.port,
            algorithm: candidate.algorithm,
            fingerprint: candidate.sha256Fingerprint,
            publicKeyData: candidate.publicKeyData
        )
    }
}

struct HostTrustController: Sendable {
    let store: any KnownHostStore

    func evaluate(_ candidate: HostKeyCandidate) async throws -> HostTrustEvaluation {
        guard let known = try await store.record(
            host: candidate.host,
            port: candidate.port,
            algorithm: candidate.algorithm
        ) else {
            return .unknown(candidate)
        }
        guard known.fingerprint == candidate.sha256Fingerprint,
              known.algorithm == candidate.algorithm,
              known.publicKeyData == nil || candidate.publicKeyData == nil || known.publicKeyData == candidate.publicKeyData
        else {
            return .changed(savedFingerprint: known.fingerprint, candidate: candidate)
        }
        return .trusted
    }

    func apply(_ decision: HostTrustDecision, candidate: HostKeyCandidate) async throws {
        switch decision {
        case .cancel:
            throw CancellationError()
        case .trustOnce:
            return
        case .trustAndSave:
            try await store.save(candidate)
        case .replaceConfirmed:
            try await store.replace(candidate, confirmed: true)
        }
    }
}
