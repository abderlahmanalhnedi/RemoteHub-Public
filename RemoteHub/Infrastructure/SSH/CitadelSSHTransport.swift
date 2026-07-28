@preconcurrency import Citadel
import Crypto
import Foundation
import NIO
import NIOSSH

typealias HostTrustPrompt = @Sendable (HostTrustEvaluation) async throws -> HostTrustDecision

enum SSHHostKeyCandidateFactory {
    static func candidate(
        host: String,
        port: Int,
        presentedKey: NIOSSHPublicKey
    ) throws -> HostKeyCandidate {
        var buffer = ByteBufferAllocator().buffer(capacity: 512)
        presentedKey.write(to: &buffer)
        let blob = Data(buffer.readableBytesView)
        let bytes = [UInt8](blob)
        guard bytes.count >= 4 else {
            throw invalidPresentedKey("The encoded host key did not contain an algorithm length.")
        }

        let algorithmLength = Int(bytes[0]) << 24 |
            Int(bytes[1]) << 16 |
            Int(bytes[2]) << 8 |
            Int(bytes[3])
        guard algorithmLength > 0, algorithmLength <= bytes.count - 4,
              let algorithm = String(
                  bytes: bytes[4..<(4 + algorithmLength)],
                  encoding: .utf8
              )
        else {
            throw invalidPresentedKey("The encoded host-key algorithm was invalid.")
        }

        let fingerprint = Data(SHA256.hash(data: blob))
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let publicKeyLine = "\(algorithm) \(blob.base64EncodedString())"
        return HostKeyCandidate(
            host: host,
            port: port,
            algorithm: algorithm,
            sha256Fingerprint: "SHA256:\(fingerprint)",
            publicKeyData: Data(publicKeyLine.utf8)
        )
    }

    private static func invalidPresentedKey(_ details: String) -> RemoteHubError {
        RemoteHubError(
            .unsupportedAlgorithm,
            message: "The SSH server presented an unsupported host key.",
            recoverySuggestion: "Verify that the server uses a host-key algorithm supported by RemoteHub.",
            technicalDetails: details
        )
    }
}

struct SSHNegotiatedHostKeyValidator: Sendable {
    let scannedCandidates: [HostKeyCandidate]
    let trustController: HostTrustController
    let trustPrompt: HostTrustPrompt

    func validate(_ presented: HostKeyCandidate) async throws {
        guard scannedCandidates.contains(where: { scanned in
            scanned.normalizedHost == presented.normalizedHost &&
                scanned.port == presented.port &&
                scanned.algorithm == presented.algorithm &&
                scanned.sha256Fingerprint == presented.sha256Fingerprint &&
                (
                    scanned.publicKeyData == nil ||
                        presented.publicKeyData == nil ||
                        scanned.publicKeyData == presented.publicKeyData
                )
        }) else {
            let scanned = scannedCandidates
                .map { "\($0.algorithm) \($0.sha256Fingerprint)" }
                .joined(separator: ", ")
            throw RemoteHubError(
                .hostKeyUnknown,
                message: "The SSH host key presented during the connection did not match the preflight scan.",
                recoverySuggestion: "Stop and verify the server fingerprints through a trusted channel.",
                technicalDetails: """
                Presented: \(presented.algorithm) \(presented.sha256Fingerprint)
                Scanned: \(scanned.isEmpty ? "none" : scanned)
                """
            )
        }

        let evaluation = try await trustController.evaluate(presented)
        guard evaluation != .trusted else { return }

        let decision = try await trustPrompt(evaluation)
        if case .changed = evaluation, decision != .replaceConfirmed {
            throw RemoteHubError(
                .hostKeyChanged,
                message: "The SSH host key has changed.",
                recoverySuggestion: "Verify the new fingerprint independently before replacing the saved key."
            )
        }
        try await trustController.apply(decision, candidate: presented)
    }
}

private final class CitadelNegotiatedHostKeyDelegate:
    NIOSSHClientServerAuthenticationDelegate,
    Sendable
{
    private let host: String
    private let port: Int
    private let validator: SSHNegotiatedHostKeyValidator

    init(host: String, port: Int, validator: SSHNegotiatedHostKeyValidator) {
        self.host = host
        self.port = port
        self.validator = validator
    }

    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        let presented: HostKeyCandidate
        do {
            presented = try SSHHostKeyCandidateFactory.candidate(
                host: host,
                port: port,
                presentedKey: hostKey
            )
        } catch {
            complete(.failure(error), promise: validationCompletePromise)
            return
        }

        Task { [validator] in
            do {
                try await validator.validate(presented)
                complete(.success(()), promise: validationCompletePromise)
            } catch {
                complete(.failure(error), promise: validationCompletePromise)
            }
        }
    }

    private func complete(
        _ result: Result<Void, Error>,
        promise: EventLoopPromise<Void>
    ) {
        promise.futureResult.eventLoop.execute {
            switch result {
            case .success:
                promise.succeed(())
            case .failure(let error):
                promise.fail(error)
            }
        }
    }
}

private final class SSHAuthenticationBox: @unchecked Sendable {
    let value: SSHAuthenticationMethod
    init(_ value: SSHAuthenticationMethod) { self.value = value }
}

/// Citadel 0.12.1 does not declare `SSHClient` as `Sendable`. The client is
/// backed by NIO channels, whose operations are serialized on their event
/// loops. Keep the unchecked conformance at this dependency boundary only.
private final class CitadelSSHClientBox: @unchecked Sendable {
    let value: SSHClient

    init(_ value: SSHClient) {
        self.value = value
    }
}

@available(macOS 15.0, *)
/// Citadel 0.12.1 does not declare `TTYStdinWriter` as `Sendable`, even though
/// it only forwards operations to its NIO channel. Do not expose the unchecked
/// conformance outside the Citadel PTY driver.
private final class CitadelTTYWriterBox: @unchecked Sendable {
    let writer: TTYStdinWriter

    init(_ writer: TTYStdinWriter) {
        self.writer = writer
    }
}

struct SSHPTYWriter: Sendable {
    let send: @Sendable (Data) async throws -> Void
    let resize: @Sendable (Int, Int) async throws -> Void
}

actor SSHPTYBridge {
    private enum State {
        case waitingForWriter
        case ready(SSHPTYWriter)
        case finished
    }

    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private var state = State.waitingForWriter

    init(continuation: AsyncThrowingStream<Data, Error>.Continuation) {
        self.continuation = continuation
    }

    func install(_ writer: SSHPTYWriter) throws {
        switch state {
        case .waitingForWriter:
            state = .ready(writer)
        case .ready:
            throw RemoteHubError(
                .unknown,
                message: "The SSH terminal writer was installed more than once."
            )
        case .finished:
            throw CancellationError()
        }
    }

    func send(_ data: Data) async throws {
        let writer = try readyWriter()
        do {
            try await writer.send(data)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw sanitizedPTYError(error)
        }
    }

    func resize(columns: Int, rows: Int) async throws {
        let writer = try readyWriter()
        do {
            try await writer.resize(columns, rows)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw sanitizedPTYError(error)
        }
    }

    func forward(_ data: Data) {
        guard case .finished = state else {
            continuation.yield(data)
            return
        }
    }

    func finish(throwing error: Error? = nil) {
        guard case .finished = state else {
            state = .finished
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
            return
        }
    }

    private func readyWriter() throws -> SSHPTYWriter {
        switch state {
        case .waitingForWriter:
            throw RemoteHubError(
                .networkUnavailable,
                message: "The SSH terminal is not ready yet."
            )
        case .ready(let writer):
            return writer
        case .finished:
            throw RemoteHubError(
                .networkUnavailable,
                message: "The SSH terminal is closed."
            )
        }
    }
}

protocol SSHPTYDriving: Sendable {
    func run(with bridge: SSHPTYBridge) async throws
}

actor SSHPTYController {
    nonisolated let output: AsyncThrowingStream<Data, Error>

    private let bridge: SSHPTYBridge
    private var terminalTask: Task<Void, Never>?
    private var isDisconnected = false

    init() {
        let stream = AsyncThrowingStream<Data, Error>.makeStream()
        output = stream.stream
        bridge = SSHPTYBridge(continuation: stream.continuation)
    }

    func start(driver: any SSHPTYDriving) throws {
        guard !isDisconnected else {
            throw RemoteHubError(
                .networkUnavailable,
                message: "The SSH terminal is closed."
            )
        }
        guard terminalTask == nil else { return }
        terminalTask = Self.makeTerminalTask(driver: driver, bridge: bridge)
    }

    func send(_ data: Data) async throws {
        try await bridge.send(data)
    }

    func resize(columns: Int, rows: Int) async throws {
        try await bridge.resize(columns: columns, rows: rows)
    }

    func disconnect() async {
        guard !isDisconnected else { return }
        isDisconnected = true

        let task = terminalTask
        terminalTask = nil
        task?.cancel()
        await bridge.finish()
        await task?.value
    }

    private nonisolated static func makeTerminalTask(
        driver: any SSHPTYDriving,
        bridge: SSHPTYBridge
    ) -> Task<Void, Never> {
        Task {
            do {
                try await driver.run(with: bridge)
                await bridge.finish()
            } catch is CancellationError {
                await bridge.finish()
            } catch {
                if Task.isCancelled {
                    await bridge.finish()
                } else {
                    await bridge.finish(throwing: sanitizedPTYError(error))
                }
            }
        }
    }
}

private struct CitadelPTYDriver: SSHPTYDriving {
    let client: CitadelSSHClientBox
    let terminalType: String

    func run(with bridge: SSHPTYBridge) async throws {
        guard #available(macOS 15.0, *) else {
            throw RemoteHubError(
                .unsupportedAlgorithm,
                message: "Interactive Citadel terminals require macOS 15 or newer."
            )
        }

        let request = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: terminalType,
            terminalCharacterWidth: 80,
            terminalRowHeight: 24,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: .init([.ECHO: 1])
        )
        try await client.value.withPTY(request) { inbound, outbound in
            let outbound = CitadelTTYWriterBox(outbound)
            try await bridge.install(SSHPTYWriter(
                send: { data in
                    try await outbound.writer.write(ByteBuffer(bytes: data))
                },
                resize: { columns, rows in
                    try await outbound.writer.changeSize(
                        cols: columns,
                        rows: rows,
                        pixelWidth: 0,
                        pixelHeight: 0
                    )
                }
            ))
            for try await item in inbound {
                try Task.checkCancellation()
                switch item {
                case .stdout(let buffer), .stderr(let buffer):
                    await bridge.forward(Data(buffer.readableBytesView))
                }
            }
        }
    }
}

private func sanitizedPTYError(_ error: Error) -> Error {
    if let error = error as? RemoteHubError {
        return error
    }
    return RemoteHubError(
        .networkUnavailable,
        message: "The SSH terminal connection ended unexpectedly.",
        recoverySuggestion: "Check the network connection and reconnect.",
        technicalDetails: error.localizedDescription
    )
}

struct CitadelSSHTransport: SSHTransport {
    let scanner: any SSHHostKeyScanning
    let trustController: HostTrustController
    let trustPrompt: HostTrustPrompt

    init(
        scanner: any SSHHostKeyScanning = SSHHostKeyScanner(),
        trustController: HostTrustController,
        trustPrompt: @escaping HostTrustPrompt
    ) {
        self.scanner = scanner
        self.trustController = trustController
        self.trustPrompt = trustPrompt
    }

    func connect(configuration: SSHConnectionConfiguration) async throws -> any SSHSession {
        if configuration.opensInteractiveShell, #unavailable(macOS 15.0) {
            throw RemoteHubError(
                .unsupportedAlgorithm,
                message: "Interactive Citadel terminals require macOS 15 or newer.",
                recoverySuggestion: "Upgrade macOS or use an SFTP-only profile on macOS 14."
            )
        }
        let scanned = try await scanner.scan(
            host: configuration.host,
            port: configuration.port,
            timeoutSeconds: configuration.timeoutSeconds
        )
        let negotiatedKeyValidator = SSHNegotiatedHostKeyValidator(
            scannedCandidates: scanned.map(\.candidate),
            trustController: trustController,
            trustPrompt: trustPrompt
        )
        let hostKeyDelegate = CitadelNegotiatedHostKeyDelegate(
            host: configuration.host,
            port: configuration.port,
            validator: negotiatedKeyValidator
        )
        let authentication = SSHAuthenticationBox(try makeAuthentication(configuration.authentication))
        var settings = SSHClientSettings(
            host: configuration.host,
            port: configuration.port,
            authenticationMethod: { authentication.value },
            hostKeyValidator: .custom(hostKeyDelegate)
        )
        settings.connectTimeout = .seconds(Int64(configuration.timeoutSeconds))
        let client: SSHClient
        do {
            client = try await SSHClient.connect(to: settings)
        } catch {
            throw mapCitadelSSHConnectionError(error)
        }
        let session = CitadelSSHSession(client: client, terminalType: configuration.terminalType)
        if configuration.opensInteractiveShell {
            try await session.start()
        }
        return session
    }

    private func makeAuthentication(_ authentication: SSHAuthentication) throws -> SSHAuthenticationMethod {
        switch authentication {
        case .password(let username, let password):
            return .passwordBased(username: username, password: password)
        case .privateKey(let username, let fileURL, let passphrase):
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            guard let value = String(data: data, encoding: .utf8) else {
                throw RemoteHubError(.unsupportedKeyFormat, message: "The private key is not valid UTF-8.")
            }
            let type: SSHKeyType
            do {
                type = try SSHKeyDetection.detectPrivateKeyType(from: value)
            } catch {
                throw RemoteHubError(
                    .unsupportedKeyFormat,
                    message: "The SSH private-key format is unsupported.",
                    recoverySuggestion: "Use a supported OpenSSH Ed25519 or RSA private key.",
                    technicalDetails: error.localizedDescription
                )
            }
            let decryptionKey = passphrase.map { Data($0.utf8) }
            do {
                if type == .ed25519 {
                    return .ed25519(
                        username: username,
                        privateKey: try Curve25519.Signing.PrivateKey(
                            sshEd25519: data,
                            decryptionKey: decryptionKey
                        )
                    )
                }
                if type == .rsa {
                    return .rsa(
                        username: username,
                        privateKey: try Insecure.RSA.PrivateKey(
                            sshRsa: data,
                            decryptionKey: decryptionKey
                        )
                    )
                }
                throw RemoteHubError(
                    .unsupportedKeyFormat,
                    message: "This SSH key type is detected but not supported for authentication in this build."
                )
            } catch let error as RemoteHubError {
                throw error
            } catch {
                throw RemoteHubError(
                    .authenticationFailed,
                    message: "The private key could not be unlocked.",
                    recoverySuggestion: "Verify the passphrase and key format.",
                    technicalDetails: error.localizedDescription
                )
            }
        case .agent:
            throw RemoteHubError(
                .unsupportedAlgorithm,
                message: "Citadel 0.12.1 does not expose macOS SSH-agent authentication.",
                recoverySuggestion: "Choose password or private-key authentication."
            )
        }
    }
}

func mapCitadelSSHConnectionError(_ error: Error) -> Error {
    if error is CancellationError || error is RemoteHubError {
        return error
    }
    if error is InvalidHostKey {
        return RemoteHubError(
            .hostKeyUnknown,
            message: "The SSH server host key could not be validated.",
            recoverySuggestion: "Stop and verify the server fingerprint through a trusted channel.",
            technicalDetails: String(reflecting: type(of: error))
        )
    }
    if error is AuthenticationFailed {
        return sshAuthenticationError(error)
    }
    if let clientError = error as? SSHClientError {
        switch clientError {
        case .allAuthenticationOptionsFailed,
             .unsupportedPasswordAuthentication,
             .unsupportedPrivateKeyAuthentication,
             .unsupportedHostBasedAuthentication:
            return sshAuthenticationError(error)
        case .channelCreationFailed:
            break
        }
    }
    return RemoteHubError(
        .networkUnavailable,
        message: "The SSH connection failed.",
        recoverySuggestion: "Check the host, port, network connection, and SSH service.",
        technicalDetails: String(reflecting: error)
    )
}

private func sshAuthenticationError(_ error: Error) -> RemoteHubError {
    RemoteHubError(
        .authenticationFailed,
        message: "SSH authentication failed.",
        recoverySuggestion: "Verify the username, password, or private key and try again.",
        technicalDetails: String(reflecting: error)
    )
}

actor CitadelSSHSession: SSHSession {
    nonisolated let output: AsyncThrowingStream<Data, Error>

    private let client: CitadelSSHClientBox
    private let terminalType: String
    private let terminal: SSHPTYController
    private var sftpSession: CitadelSFTPSession?

    init(client: SSHClient, terminalType: String) {
        let terminal = SSHPTYController()
        self.output = terminal.output
        self.client = CitadelSSHClientBox(client)
        self.terminalType = terminalType
        self.terminal = terminal
    }

    func start() async throws {
        guard #available(macOS 15.0, *) else {
            throw RemoteHubError(
                .unsupportedAlgorithm,
                message: "Interactive Citadel terminals require macOS 15 or newer."
            )
        }
        try await terminal.start(driver: CitadelPTYDriver(
            client: client,
            terminalType: terminalType
        ))
    }

    func send(_ data: Data) async throws {
        try await terminal.send(data)
    }

    func resize(columns: Int, rows: Int) async throws {
        try await terminal.resize(columns: columns, rows: rows)
    }

    func openSFTP() async throws -> any SFTPSession {
        if let sftpSession { return sftpSession }
        let raw = try await client.value.openSFTP()
        let session = CitadelSFTPSession(client: raw)
        sftpSession = session
        return session
    }

    func disconnect() async {
        await terminal.disconnect()
        if let sftpSession { await sftpSession.disconnect() }
        try? await client.value.close()
    }
}
