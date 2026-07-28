import Foundation
import Network

enum RDPNetworkProbeError: Error, Equatable, Sendable {
    case dns(String)
    case connectionRefused(String)
    case networkUnavailable(String)
}

protocol RDPNetworkProbing: Sendable {
    func connect(host: String, port: UInt16) async throws
}

protocol RDPPreflighting: Sendable {
    func check(host: String, port: Int, timeoutSeconds: TimeInterval) async throws
}

struct RDPPreflightService: RDPPreflighting {
    private let probe: any RDPNetworkProbing

    init(probe: any RDPNetworkProbing = NWConnectionRDPProbe()) {
        self.probe = probe
    }

    func check(host: String, port: Int, timeoutSeconds: TimeInterval) async throws {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Validators.host(trimmedHost).isEmpty else {
            throw RemoteHubError(
                .validation,
                message: "The RDP host name is invalid.",
                recoverySuggestion: "Enter a DNS name, IPv4 address, or IPv6 address without a URL or credentials."
            )
        }
        guard Validators.port(port).isEmpty, let networkPort = UInt16(exactly: port) else {
            throw RemoteHubError(
                .validation,
                message: "The RDP port is invalid.",
                recoverySuggestion: "Use a port between 1 and 65535."
            )
        }

        let timeout = min(30, max(0.05, timeoutSeconds))
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await probe.connect(host: trimmedHost, port: networkPort)
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw RemoteHubError(
                        .timeout,
                        message: "The RDP server did not respond within \(timeout.formatted()) seconds.",
                        recoverySuggestion: "Check the host, port, VPN, firewall, and server status, then try again."
                    )
                }

                defer { group.cancelAll() }
                _ = try await group.next()
            }
        } catch let error as RemoteHubError {
            throw error
        } catch let error as RDPNetworkProbeError {
            throw map(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RemoteHubError(
                .networkUnavailable,
                message: "RemoteHub could not reach the RDP server.",
                recoverySuggestion: "Check the network, VPN, host, and port, then try again.",
                technicalDetails: error.localizedDescription
            )
        }
    }

    private func map(_ error: RDPNetworkProbeError) -> RemoteHubError {
        switch error {
        case .dns(let details):
            RemoteHubError(
                .dns,
                message: "The RDP host name could not be resolved.",
                recoverySuggestion: "Check the host name and DNS or VPN connection, then try again.",
                technicalDetails: details
            )
        case .connectionRefused(let details):
            RemoteHubError(
                .connectionRefused,
                message: "The RDP server refused the connection.",
                recoverySuggestion: "Verify that Remote Desktop is enabled and listening on the configured port.",
                technicalDetails: details
            )
        case .networkUnavailable(let details):
            RemoteHubError(
                .networkUnavailable,
                message: "The network cannot currently reach the RDP server.",
                recoverySuggestion: "Check the network route, VPN, firewall, and server status, then try again.",
                technicalDetails: details
            )
        }
    }
}

struct NWConnectionRDPProbe: RDPNetworkProbing {
    func connect(host: String, port: UInt16) async throws {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        let coordinator = NWConnectionCoordinator(connection: connection)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                coordinator.start(continuation: continuation)
            }
        } onCancel: {
            coordinator.cancel()
        }
    }
}

private final class NWConnectionCoordinator: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.alhnedi.RemoteHub.rdp-preflight")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?
    private var completed = false

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start(continuation: CheckedContinuation<Void, any Error>) {
        let shouldStart = lock.withLock {
            guard !completed else {
                continuation.resume(throwing: CancellationError())
                return false
            }
            self.continuation = continuation
            return true
        }
        guard shouldStart else { return }
        connection.stateUpdateHandler = { [weak self] state in
            self?.handle(state)
        }
        connection.start(queue: queue)
    }

    func cancel() {
        connection.cancel()
        complete(.failure(CancellationError()))
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            complete(.success(()))
        case .failed(let error):
            complete(.failure(Self.map(error)))
        case .waiting(let error):
            switch Self.map(error) {
            case .dns, .connectionRefused:
                complete(.failure(Self.map(error)))
            case .networkUnavailable:
                break
            }
        case .cancelled:
            complete(.failure(CancellationError()))
        default:
            break
        }
    }

    private func complete(_ result: Result<Void, any Error>) {
        let pending: CheckedContinuation<Void, any Error>? = lock.withLock {
            guard !completed else { return nil }
            completed = true
            let value = continuation
            continuation = nil
            return value
        }
        guard let pending else { return }
        connection.stateUpdateHandler = nil
        connection.cancel()
        pending.resume(with: result)
    }

    private static func map(_ error: NWError) -> RDPNetworkProbeError {
        switch error {
        case .dns:
            return .dns(error.localizedDescription)
        case .posix(let code) where code == .ECONNREFUSED:
            return .connectionRefused(error.localizedDescription)
        default:
            return .networkUnavailable(error.localizedDescription)
        }
    }
}
