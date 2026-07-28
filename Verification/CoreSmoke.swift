import Foundation

enum CoreSmokeFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): message
        }
    }
}

@main
struct CoreSmoke {
    static func main() async throws {
        var checks = 0

        try expect(ConnectionKind.ssh.defaultPort == 22, "SSH default port")
        checks += 1
        try expect(ConnectionKind.rdp.defaultPort == 3389, "RDP default port")
        checks += 1
        try expect(Validators.host("server.example").isEmpty, "DNS validation")
        checks += 1
        try expect(!Validators.host("user:password@server.example").isEmpty, "credential-bearing host rejection")
        checks += 1

        var selection = PortSelectionState(kind: .ssh)
        selection.setPort(2222)
        selection.changeKind(to: .rdp)
        try expect(selection.port == 2222, "manual port preservation")
        checks += 1

        let listings = try FTPListingParser.parse(
            """
            drwxr-xr-x 2 demo users 4096 Jan 02 2025 Folder With Spaces
            -rw-r--r-- 1 demo users 123 Jan 03 12:30 résumé.txt
            """,
            basePath: "/pub"
        )
        try expect(listings.count == 2 && listings[0].type == .directory, "FTP listing parsing")
        checks += 1

        let secret = "REMOTEHUB-CORE-SMOKE-SECRET"
        let ftpConfiguration = FTPConnectionConfiguration(
            kind: .ftpsExplicit,
            host: "server.example",
            port: 21,
            username: "demo-user",
            password: secret,
            passiveMode: true,
            verifyTLSCertificate: true,
            timeoutSeconds: 15
        )
        let curl = try CurlCommandBuilder.build(configuration: ftpConfiguration, remotePath: "/folder with spaces")
        try expect(!curl.arguments.joined().contains(secret), "curl argument secret isolation")
        checks += 1
        try expect(String(decoding: curl.standardInput, as: UTF8.self).contains(secret), "curl stdin credential delivery")
        checks += 1

        let installation = RDPInstallation(
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/sdl-freerdp"),
            versionDescription: "FreeRDP 3",
            supportsSafePasswordInput: true,
            requiresXQuartz: false
        )
        let rdp = try RDPArgumentBuilder.build(
            installation: installation,
            configuration: RDPConnectionConfiguration(
                host: "2001:db8::10",
                port: 3389,
                username: "demo-user",
                domain: nil,
                settings: RDPSettings()
            ),
            password: secret
        )
        try expect(rdp.arguments.contains("/v:[2001:db8::10]:3389"), "RDP IPv6 formatting")
        checks += 1
        try expect(rdp.arguments.contains("/from-stdin:force") && !rdp.arguments.joined().contains(secret), "RDP argument secret isolation")
        checks += 1

        let credentials = InMemoryCredentialStore()
        let account = SecretType.loginPassword.account(for: UUID())
        try await credentials.save(secret, account: account)
        let storedSecret = try await credentials.read(account: account)
        try expect(storedSecret == secret, "credential store round trip")
        checks += 1
        try await credentials.remove(account: account)
        let secretStillExists = try await credentials.contains(account: account)
        try expect(!secretStillExists, "credential store deletion")
        checks += 1

        let candidate = HostKeyCandidate(
            host: "server.example",
            port: 22,
            algorithm: "ssh-ed25519",
            sha256Fingerprint: "SHA256:first",
            publicKeyData: Data("first".utf8)
        )
        let hostTrust = HostTrustController(store: InMemoryKnownHostStore())
        let unknownEvaluation = try await hostTrust.evaluate(candidate)
        try expect(unknownEvaluation == .unknown(candidate), "unknown-host evaluation")
        checks += 1
        try await hostTrust.apply(.trustAndSave, candidate: candidate)
        let trustedEvaluation = try await hostTrust.evaluate(candidate)
        try expect(trustedEvaluation == .trusted, "saved-host evaluation")
        checks += 1

        let redacted = Redactor.sanitize("ftp://demo:\(secret)@server.example password=\(secret)")
        try expect(!redacted.contains(secret), "diagnostic redaction")
        checks += 1

        print("RemoteHub core smoke checks passed: \(checks)")
    }

    private static func expect(
        _ condition: @autoclosure () throws -> Bool,
        _ description: String
    ) throws {
        guard try condition() else {
            throw CoreSmokeFailure.failed("Core smoke check failed: \(description)")
        }
    }
}
