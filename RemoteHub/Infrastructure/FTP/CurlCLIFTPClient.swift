import Foundation

struct CurlInvocation: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let standardInput: Data
}

enum CurlCommandBuilder {
    static let executableURL = URL(fileURLWithPath: "/usr/bin/curl")

    static func build(
        configuration: FTPConnectionConfiguration,
        remotePath: String,
        operationArguments: [String] = []
    ) throws -> CurlInvocation {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw RemoteHubError(.processLaunchFailed, message: "The system curl executable is unavailable.")
        }
        let url = try remoteURL(configuration: configuration, path: remotePath)
        var arguments = ["--config", "-", "--fail", "--silent", "--show-error"]
        arguments.append(configuration.passiveMode ? "--ftp-pasv" : "--ftp-port")
        if !configuration.passiveMode { arguments.append("-") }
        arguments += ["--connect-timeout", String(configuration.timeoutSeconds)]
        switch configuration.kind {
        case .ftpsExplicit:
            arguments.append("--ssl-reqd")
        case .ftpsImplicit:
            arguments.append("--ssl-reqd")
        default:
            break
        }
        if !configuration.verifyTLSCertificate, configuration.kind != .ftp {
            arguments.append("--insecure")
        }
        arguments += operationArguments
        arguments.append(url.absoluteString)

        let user = escapeConfig(configuration.username)
        let password = escapeConfig(configuration.password ?? "")
        let config = "user = \"\(user):\(password)\"\n"
        return CurlInvocation(
            executableURL: executableURL,
            arguments: arguments,
            standardInput: Data(config.utf8)
        )
    }

    private static func remoteURL(configuration: FTPConnectionConfiguration, path: String) throws -> URL {
        var components = URLComponents()
        components.scheme = configuration.kind == .ftpsImplicit ? "ftps" : "ftp"
        components.host = configuration.host
        components.port = configuration.port
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = components.url else {
            throw RemoteHubError(.validation, message: "The remote FTP path is invalid.")
        }
        return url
    }

    private static func escapeConfig(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

actor CurlCLIFTPClient: FTPClient {
    private let runner: any ProcessRunning
    private var configuration: FTPConnectionConfiguration?

    init(runner: any ProcessRunning = FoundationProcessRunner()) {
        self.runner = runner
    }

    func connect(configuration: FTPConnectionConfiguration) async throws {
        self.configuration = configuration
        let invocation = try CurlCommandBuilder.build(
            configuration: configuration,
            remotePath: "/",
            operationArguments: ["--list-only"]
        )
        _ = try await run(invocation)
    }

    func list(path: String) async throws -> [RemoteFileItem] {
        let config = try currentConfiguration()
        let invocation = try CurlCommandBuilder.build(configuration: config, remotePath: path)
        let result = try await run(invocation)
        guard let listing = String(data: result.standardOutput, encoding: .utf8) else {
            throw RemoteHubError(.unknown, message: "The FTP listing was not valid UTF-8.")
        }
        return try FTPListingParser.parse(listing, basePath: path)
    }

    func createDirectory(path: String) async throws {
        try await quote(["MKD \(path)"])
    }

    func rename(from: String, to: String) async throws {
        try await quote(["RNFR \(from)", "RNTO \(to)"])
    }

    func removeFile(path: String) async throws {
        try await quote(["DELE \(path)"])
    }

    func removeDirectory(path: String) async throws {
        try await quote(["RMD \(path)"])
    }

    func upload(
        localURL: URL,
        to remotePath: String,
        progress: TransferProgressHandler?
    ) async throws {
        let config = try currentConfiguration()
        guard FileManager.default.isReadableFile(atPath: localURL.path) else {
            throw RemoteHubError(.fileNotFound, message: "The local upload file is not readable.")
        }
        let invocation = try CurlCommandBuilder.build(
            configuration: config,
            remotePath: remotePath,
            operationArguments: ["--upload-file", localURL.path]
        )
        _ = try await run(invocation)
        let size = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? NSNumber)?.int64Value
        progress?(TransferProgress(bytesTransferred: size ?? 0, totalBytes: size, bytesPerSecond: 0))
    }

    func download(
        remotePath: String,
        to localURL: URL,
        progress: TransferProgressHandler?
    ) async throws {
        let config = try currentConfiguration()
        let invocation = try CurlCommandBuilder.build(
            configuration: config,
            remotePath: remotePath,
            operationArguments: ["--output", localURL.path]
        )
        _ = try await run(invocation)
        let size = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? NSNumber)?.int64Value
        progress?(TransferProgress(bytesTransferred: size ?? 0, totalBytes: size, bytesPerSecond: 0))
    }

    func disconnect() async {
        configuration = nil
    }

    private func quote(_ commands: [String]) async throws {
        let config = try currentConfiguration()
        var arguments: [String] = []
        for command in commands {
            arguments += ["--quote", command]
        }
        let invocation = try CurlCommandBuilder.build(
            configuration: config,
            remotePath: "/",
            operationArguments: arguments
        )
        _ = try await run(invocation)
    }

    private func currentConfiguration() throws -> FTPConnectionConfiguration {
        guard let configuration else {
            throw RemoteHubError(.networkUnavailable, message: "The FTP client is not connected.")
        }
        return configuration
    }

    private func run(_ invocation: CurlInvocation) async throws -> ProcessResult {
        let result = try await runner.run(ProcessRequest(
            executableURL: invocation.executableURL,
            arguments: invocation.arguments,
            standardInput: invocation.standardInput
        ))
        guard result.terminationStatus == 0 else {
            let details = String(data: result.standardError, encoding: .utf8).map(Redactor.sanitize)
            throw RemoteHubError(
                .unknown,
                message: "The FTP operation failed.",
                recoverySuggestion: "Verify the server, credentials, path, and TLS settings.",
                technicalDetails: details
            )
        }
        return result
    }
}
