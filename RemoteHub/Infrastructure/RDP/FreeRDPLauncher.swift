import Foundation

struct FreeRDPCandidate: Equatable, Sendable {
    let url: URL
    let source: RDPInstallationSource
}

struct FreeRDPExecutableResolver: Sendable {
    let appBundleURL: URL
    let environmentPath: String?
    let allowsLegacyDiscovery: Bool

    init(
        appBundleURL: URL = Bundle.main.bundleURL,
        environmentPath: String? = ProcessInfo.processInfo.environment["PATH"],
        allowsLegacyDiscovery: Bool = Self.defaultAllowsLegacyDiscovery
    ) {
        self.appBundleURL = appBundleURL
        self.environmentPath = environmentPath
        self.allowsLegacyDiscovery = allowsLegacyDiscovery
    }

    func candidates(customExecutablePath: String?) -> [FreeRDPCandidate] {
        var values = [
            FreeRDPCandidate(
                url: appBundleURL.appendingPathComponent("Contents/Helpers/sdl-freerdp"),
                source: .bundled
            ),
            FreeRDPCandidate(
                url: appBundleURL.appendingPathComponent("Contents/MacOS/sdl-freerdp"),
                source: .bundled
            )
        ]

        if let customExecutablePath = customExecutablePath?.nilIfBlank {
            values.append(FreeRDPCandidate(
                url: URL(fileURLWithPath: customExecutablePath),
                source: .customOverride
            ))
        }

        if allowsLegacyDiscovery {
            let fixedPaths = [
                "/opt/homebrew/bin/sdl-freerdp",
                "/opt/homebrew/bin/xfreerdp",
                "/opt/homebrew/bin/freerdp",
                "/usr/local/bin/sdl-freerdp",
                "/usr/local/bin/xfreerdp",
                "/usr/local/bin/freerdp"
            ]
            values += fixedPaths.map {
                FreeRDPCandidate(url: URL(fileURLWithPath: $0), source: .legacyDevelopment)
            }
            if let environmentPath {
                for folder in environmentPath.split(separator: ":") {
                    for name in ["sdl-freerdp", "xfreerdp", "freerdp"] {
                        values.append(FreeRDPCandidate(
                            url: URL(fileURLWithPath: String(folder)).appendingPathComponent(name),
                            source: .legacyDevelopment
                        ))
                    }
                }
            }
        }

        var seen = Set<String>()
        return values.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }

    private static var defaultAllowsLegacyDiscovery: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

protocol FreeRDPDetecting: Sendable {
    func detect(customExecutablePath: String?) async -> RDPInstallationStatus
}

struct FreeRDPDetector: FreeRDPDetecting, Sendable {
    let runner: any ProcessRunning
    let resolver: FreeRDPExecutableResolver
    let customExecutablePath: String?

    init(
        runner: any ProcessRunning = FoundationProcessRunner(),
        resolver: FreeRDPExecutableResolver = FreeRDPExecutableResolver(),
        customExecutablePath: String? = nil
    ) {
        self.runner = runner
        self.resolver = resolver
        self.customExecutablePath = customExecutablePath
    }

    func detect() async -> RDPInstallationStatus {
        await detect(customExecutablePath: customExecutablePath)
    }

    func detect(customExecutablePath: String?) async -> RDPInstallationStatus {
        for candidate in resolver.candidates(customExecutablePath: customExecutablePath) {
            guard FileManager.default.isExecutableFile(atPath: candidate.url.path) else { continue }
            do {
                let version = try await inspect(url: candidate.url, arguments: ["--version"])
                let help = (try? await inspect(url: candidate.url, arguments: ["--help"])) ?? ""
                let lowerHelp = help.lowercased()
                let safeInput = lowerHelp.contains("from-stdin")
                let name = candidate.url.lastPathComponent.lowercased()
                return .available(RDPInstallation(
                    executableURL: candidate.url,
                    versionDescription: version.firstLine ?? candidate.url.lastPathComponent,
                    supportsSafePasswordInput: safeInput,
                    requiresXQuartz: name.contains("xfreerdp"),
                    source: candidate.source
                ))
            } catch {
                return .incompatible(
                    path: candidate.url.path,
                    reason: Redactor.sanitize(error.localizedDescription)
                )
            }
        }
        return .missing
    }

    private func inspect(url: URL, arguments: [String]) async throws -> String {
        let result = try await runner.run(ProcessRequest(
            executableURL: url,
            arguments: arguments,
            standardInput: nil
        ))
        let combined = result.standardOutput + result.standardError
        guard result.terminationStatus == 0 else {
            throw RemoteHubError(
                .incompatibleFreeRDP,
                message: "FreeRDP inspection failed.",
                technicalDetails: Redactor.sanitize(String(decoding: combined, as: UTF8.self))
            )
        }
        guard let value = String(data: combined, encoding: .utf8),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw RemoteHubError(.incompatibleFreeRDP, message: "FreeRDP returned no version/help information.")
        }
        return Redactor.sanitize(value)
    }
}

actor FreeRDPLauncher: RDPLaunching {
    private let detector: any FreeRDPDetecting
    private let preflight: any RDPPreflighting
    private let processLauncher: any RDPProcessLaunching
    private var launchingSessions = Set<UUID>()
    private var activeSessions: [UUID: any RDPSessionHandle] = [:]

    init(
        detector: any FreeRDPDetecting = FreeRDPDetector(),
        preflight: any RDPPreflighting = RDPPreflightService(),
        processLauncher: any RDPProcessLaunching = FoundationRDPProcessLauncher()
    ) {
        self.detector = detector
        self.preflight = preflight
        self.processLauncher = processLauncher
    }

    func detectInstallation() async -> RDPInstallationStatus {
        await detector.detect(customExecutablePath: nil)
    }

    func launch(
        sessionIdentifier: UUID,
        configuration: RDPConnectionConfiguration,
        secretProvider: any SecretProvider
    ) async throws -> any RDPSessionHandle {
        guard !launchingSessions.contains(sessionIdentifier),
              activeSessions[sessionIdentifier]?.isRunning != true
        else {
            throw RemoteHubError(
                .duplicateSession,
                message: "This workspace already has an active RDP process.",
                recoverySuggestion: "Bring the existing RDP window to the front or terminate it before reconnecting."
            )
        }
        launchingSessions.insert(sessionIdentifier)
        defer { launchingSessions.remove(sessionIdentifier) }

        let installation: RDPInstallation
        switch await detector.detect(customExecutablePath: configuration.customExecutablePath) {
        case .available(let value):
            installation = value
        case .missing:
            throw RemoteHubError(
                .freeRDPMissing,
                message: "The bundled Remote Desktop client is unavailable.",
                recoverySuggestion: "Reinstall RemoteHub, or choose a compatible SDL FreeRDP executable in RDP Settings → Advanced."
            )
        case .incompatible(_, let reason):
            throw RemoteHubError(
                .incompatibleFreeRDP,
                message: "The Remote Desktop client is incompatible.",
                recoverySuggestion: "Reinstall RemoteHub or clear the Advanced executable override.",
                technicalDetails: reason
            )
        }

        try await preflight.check(
            host: configuration.host,
            port: configuration.port,
            timeoutSeconds: configuration.preflightTimeoutSeconds
        )

        let password = try await secretProvider.password()
        let specification = try RDPArgumentBuilder.build(
            installation: installation,
            configuration: configuration,
            password: password
        )
        let handle = try await processLauncher.launch(specification)
        activeSessions[sessionIdentifier] = handle

        Task { [weak self] in
            _ = await handle.waitForExit()
            await self?.removeSession(sessionIdentifier, handleID: handle.id)
        }
        return handle
    }

    private func removeSession(_ sessionIdentifier: UUID, handleID: UUID) {
        guard activeSessions[sessionIdentifier]?.id == handleID else { return }
        activeSessions.removeValue(forKey: sessionIdentifier)
    }
}

private extension String {
    var firstLine: String? {
        split(whereSeparator: \.isNewline).first.map(String.init)
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
