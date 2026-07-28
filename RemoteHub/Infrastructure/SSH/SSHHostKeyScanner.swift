import CryptoKit
import Foundation

struct ScannedHostKey: Sendable {
    let candidate: HostKeyCandidate
}

protocol SSHHostKeyScanning: Sendable {
    func scan(host: String, port: Int, timeoutSeconds: Int) async throws -> [ScannedHostKey]
}

struct SSHHostKeyScanner: SSHHostKeyScanning {
    private let runner: any ProcessRunning

    init(runner: any ProcessRunning = FoundationProcessRunner()) {
        self.runner = runner
    }

    func scan(host: String, port: Int, timeoutSeconds: Int) async throws -> [ScannedHostKey] {
        let executable = URL(fileURLWithPath: "/usr/bin/ssh-keyscan")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw RemoteHubError(.processLaunchFailed, message: "The system SSH host-key scanner is unavailable.")
        }
        let result = try await runner.run(ProcessRequest(
            executableURL: executable,
            arguments: [
                "-T", String(max(1, timeoutSeconds)),
                "-p", String(port),
                "-t", "ed25519,ecdsa,rsa",
                host
            ],
            standardInput: nil
        ))
        guard result.terminationStatus == 0 || !result.standardOutput.isEmpty,
              let output = String(data: result.standardOutput, encoding: .utf8)
        else {
            throw RemoteHubError(
                .networkUnavailable,
                message: "RemoteHub could not retrieve the SSH host key.",
                recoverySuggestion: "Verify the host, port, network, and SSH service."
            )
        }

        let keys = output.split(whereSeparator: \.isNewline).compactMap { line -> ScannedHostKey? in
            let parts = line.split(separator: " ", maxSplits: 2)
            guard parts.count >= 3,
                  let blob = Data(base64Encoded: String(parts[2]))
            else { return nil }
            let publicLine = "\(parts[1]) \(parts[2])"
            let digest = Data(SHA256.hash(data: blob))
                .base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
            let candidate = HostKeyCandidate(
                host: host,
                port: port,
                algorithm: String(parts[1]),
                sha256Fingerprint: "SHA256:\(digest)",
                publicKeyData: Data(publicLine.utf8)
            )
            return ScannedHostKey(candidate: candidate)
        }
        guard !keys.isEmpty else {
            throw RemoteHubError(.unsupportedAlgorithm, message: "The server returned no supported SSH host key.")
        }
        return keys
    }
}
