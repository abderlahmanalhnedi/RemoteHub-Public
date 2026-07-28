import Foundation
import XCTest
@testable import RemoteHub

final class FreeRDPDiscoveryTests: XCTestCase {
    func testBundledExecutableTakesPrecedenceOverCustomOverride() async throws {
        let fixture = try ExecutableFixture()
        defer { fixture.remove() }
        let bundled = try fixture.makeExecutable("RemoteHub.app/Contents/Helpers/sdl-freerdp")
        let custom = try fixture.makeExecutable("custom/sdl-freerdp")
        let runner = FreeRDPInspectionRunner()
        let detector = FreeRDPDetector(
            runner: runner,
            resolver: FreeRDPExecutableResolver(
                appBundleURL: fixture.root.appendingPathComponent("RemoteHub.app"),
                environmentPath: nil,
                allowsLegacyDiscovery: false
            )
        )

        let status = await detector.detect(customExecutablePath: custom.path)

        guard case .available(let installation) = status else {
            return XCTFail("Expected bundled FreeRDP to be detected.")
        }
        XCTAssertEqual(installation.executableURL, bundled)
        XCTAssertEqual(installation.source, .bundled)
        XCTAssertTrue(installation.supportsSafePasswordInput)
        let inspected = await runner.inspectedURLs
        XCTAssertEqual(Set(inspected), [bundled])
    }

    func testCustomOverrideIsUsedWhenBundleDoesNotContainHelper() async throws {
        let fixture = try ExecutableFixture()
        defer { fixture.remove() }
        let custom = try fixture.makeExecutable("custom/sdl-freerdp")
        let detector = FreeRDPDetector(
            runner: FreeRDPInspectionRunner(),
            resolver: FreeRDPExecutableResolver(
                appBundleURL: fixture.root.appendingPathComponent("RemoteHub.app"),
                environmentPath: nil,
                allowsLegacyDiscovery: false
            )
        )

        let status = await detector.detect(customExecutablePath: custom.path)

        guard case .available(let installation) = status else {
            return XCTFail("Expected custom FreeRDP to be detected.")
        }
        XCTAssertEqual(installation.executableURL, custom)
        XCTAssertEqual(installation.source, .customOverride)
    }
}

final class RDPPreflightTests: XCTestCase {
    func testInvalidHostDoesNotStartNetworkProbe() async {
        let probe = RecordingRDPNetworkProbe()
        let service = RDPPreflightService(probe: probe)

        await assertRemoteHubError(category: .validation) {
            try await service.check(host: "https://bad.example", port: 3389, timeoutSeconds: 1)
        }
        let callCount = await probe.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testDNSFailureMapsToNativeRecoveryError() async {
        let probe = RecordingRDPNetworkProbe(error: .dns("No such host"))
        let service = RDPPreflightService(probe: probe)

        await assertRemoteHubError(category: .dns) {
            try await service.check(host: "missing.example", port: 3389, timeoutSeconds: 1)
        }
    }

    func testPreflightTimeoutStopsLaunchPath() async {
        let probe = RecordingRDPNetworkProbe(delay: .seconds(10))
        let service = RDPPreflightService(probe: probe)
        let started = ContinuousClock.now

        await assertRemoteHubError(category: .timeout) {
            try await service.check(host: "slow.example", port: 3389, timeoutSeconds: 0.05)
        }
        XCTAssertLessThan(started.duration(to: .now), .seconds(1))
    }

    private func assertRemoteHubError(
        category: RemoteHubError.Category,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(category.rawValue) error.")
        } catch let error as RemoteHubError {
            XCTAssertEqual(error.category, category)
            XCTAssertNotNil(error.recoverySuggestion)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

final class FreeRDPLauncherTests: XCTestCase {
    private let secret = "RDP-SECRET-DO-NOT-LEAK-23491"

    func testLaunchUsesDirectExecutableAndStandardInputWithoutShell() async throws {
        let processLauncher = RecordingRDPProcessLauncher()
        let launcher = FreeRDPLauncher(
            detector: StubFreeRDPDetector(),
            preflight: ImmediateRDPPreflight(),
            processLauncher: processLauncher
        )
        let sessionID = UUID()

        let handle = try await launcher.launch(
            sessionIdentifier: sessionID,
            configuration: configuration(),
            secretProvider: StaticSecretProvider(value: secret)
        )
        let recordedSpecifications = await processLauncher.specifications
        let specification = try XCTUnwrap(recordedSpecifications.first)
        XCTAssertEqual(specification.executableURL.path, "/Applications/RemoteHub.app/Contents/Helpers/sdl-freerdp")
        XCTAssertNotEqual(specification.executableURL.path, "/bin/zsh")
        XCTAssertNotEqual(specification.executableURL.path, "/bin/sh")
        XCTAssertFalse(specification.arguments.contains("-c"))
        XCTAssertFalse(specification.arguments.joined(separator: " ").contains(secret))
        XCTAssertEqual(String(decoding: try XCTUnwrap(specification.standardInput), as: UTF8.self), "\(secret)\n")

        handle.terminate()
        _ = await handle.waitForExit()
    }

    func testPreflightFailureDoesNotLaunchFreeRDP() async {
        let processLauncher = RecordingRDPProcessLauncher()
        let launcher = FreeRDPLauncher(
            detector: StubFreeRDPDetector(),
            preflight: RejectingRDPPreflight(),
            processLauncher: processLauncher
        )

        do {
            _ = try await launcher.launch(
                sessionIdentifier: UUID(),
                configuration: configuration(),
                secretProvider: StaticSecretProvider(value: secret)
            )
            XCTFail("Expected preflight failure.")
        } catch let error as RemoteHubError {
            XCTAssertEqual(error.category, .connectionRefused)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let recordedSpecifications = await processLauncher.specifications
        XCTAssertTrue(recordedSpecifications.isEmpty)
    }

    func testDuplicateWorkspaceSessionIsRejected() async throws {
        let processLauncher = RecordingRDPProcessLauncher()
        let launcher = FreeRDPLauncher(
            detector: StubFreeRDPDetector(),
            preflight: ImmediateRDPPreflight(),
            processLauncher: processLauncher
        )
        let sessionID = UUID()
        let first = try await launcher.launch(
            sessionIdentifier: sessionID,
            configuration: configuration(),
            secretProvider: StaticSecretProvider(value: nil)
        )

        do {
            _ = try await launcher.launch(
                sessionIdentifier: sessionID,
                configuration: configuration(),
                secretProvider: StaticSecretProvider(value: nil)
            )
            XCTFail("Expected duplicate-session rejection.")
        } catch let error as RemoteHubError {
            XCTAssertEqual(error.category, .duplicateSession)
        }
        let recordedSpecifications = await processLauncher.specifications
        XCTAssertEqual(recordedSpecifications.count, 1)

        first.terminate()
        _ = await first.waitForExit()
    }

    func testFoundationProcessCanBeTerminatedAndCapturesOutput() async throws {
        let launcher = FoundationRDPProcessLauncher()
        let handle = try await launcher.launch(RDPLaunchSpecification(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["30"],
            standardInput: nil
        ))
        XCTAssertTrue(handle.isRunning)

        handle.terminate()
        let termination = await handle.waitForExit()

        XCTAssertTrue(termination.wasUserInitiated)
        XCTAssertFalse(handle.isRunning)
        XCTAssertEqual(termination.reason, .uncaughtSignal)
    }

    func testFoundationProcessCapturesStdoutAndStderrWithoutInheritingStreams() async throws {
        let launcher = FoundationRDPProcessLauncher()
        let handle = try await launcher.launch(RDPLaunchSpecification(
            executableURL: URL(fileURLWithPath: "/bin/ls"),
            arguments: ["/", "/definitely-not-a-real-remotehub-path"],
            standardInput: nil
        ))

        let termination = await handle.waitForExit()

        XCTAssertNotEqual(termination.exitCode, 0)
        XCTAssertFalse(termination.standardOutput.isEmpty)
        XCTAssertTrue(
            String(decoding: termination.standardError, as: UTF8.self)
                .contains("definitely-not-a-real-remotehub-path")
        )
    }

    private func configuration() -> RDPConnectionConfiguration {
        RDPConnectionConfiguration(
            host: "rdp.example",
            port: 3389,
            username: "demo-user",
            domain: nil,
            settings: RDPSettings()
        )
    }
}

final class RDPErrorMapperTests: XCTestCase {
    func testCommonStderrFailuresAreMapped() {
        let cases: [(String, RemoteHubError.Category)] = [
            ("ERRCONNECT_DNS_NAME_NOT_FOUND", .dns),
            ("connection timed out", .timeout),
            ("Connection refused", .connectionRefused),
            ("STATUS_LOGON_FAILURE", .authenticationFailed),
            ("certificate verify failed", .certificateError),
            ("NLA begin failed", .networkLevelAuthenticationFailed)
        ]

        for (standardError, category) in cases {
            let error = RDPErrorMapper.map(
                termination(standardError: standardError),
                username: "demo-user"
            )
            XCTAssertEqual(error?.category, category, "Failed to map: \(standardError)")
        }
    }

    func testCrashAndDiagnosticsRedaction() {
        let result = RDPProcessTermination(
            exitCode: 11,
            reason: .uncaughtSignal,
            standardOutput: Data(),
            standardError: Data("fatal for demo-user top-secret /p:top-secret /u:demo-user".utf8),
            wasUserInitiated: false
        )

        let error = RDPErrorMapper.map(
            result,
            username: "demo-user",
            password: "top-secret"
        )

        XCTAssertEqual(error?.category, .externalClientCrash)
        XCTAssertFalse(error?.diagnostics.contains("top-secret") == true)
        XCTAssertFalse(error?.diagnostics.contains("demo-user") == true)
        XCTAssertTrue(error?.diagnostics.contains("<redacted>") == true)
    }

    private func termination(standardError: String) -> RDPProcessTermination {
        RDPProcessTermination(
            exitCode: 1,
            reason: .exited,
            standardOutput: Data(),
            standardError: Data(standardError.utf8),
            wasUserInitiated: false
        )
    }
}

private actor FreeRDPInspectionRunner: ProcessRunning {
    private(set) var inspectedURLs: [URL] = []

    func run(_ request: ProcessRequest) async throws -> ProcessResult {
        inspectedURLs.append(request.executableURL)
        let output = request.arguments.contains("--help")
            ? "Usage: sdl-freerdp /from-stdin:force"
            : "FreeRDP version 3.0"
        return ProcessResult(
            terminationStatus: 0,
            standardOutput: Data(output.utf8),
            standardError: Data()
        )
    }
}

private struct StubFreeRDPDetector: FreeRDPDetecting {
    func detect(customExecutablePath: String?) async -> RDPInstallationStatus {
        .available(RDPInstallation(
            executableURL: URL(fileURLWithPath: "/Applications/RemoteHub.app/Contents/Helpers/sdl-freerdp"),
            versionDescription: "FreeRDP test",
            supportsSafePasswordInput: true,
            requiresXQuartz: false,
            source: .bundled
        ))
    }
}

private struct ImmediateRDPPreflight: RDPPreflighting {
    func check(host: String, port: Int, timeoutSeconds: TimeInterval) async throws {}
}

private struct RejectingRDPPreflight: RDPPreflighting {
    func check(host: String, port: Int, timeoutSeconds: TimeInterval) async throws {
        throw RemoteHubError(.connectionRefused, message: "Refused")
    }
}

private actor RecordingRDPNetworkProbe: RDPNetworkProbing {
    private(set) var callCount = 0
    let error: RDPNetworkProbeError?
    let delay: Duration?

    init(error: RDPNetworkProbeError? = nil, delay: Duration? = nil) {
        self.error = error
        self.delay = delay
    }

    func connect(host: String, port: UInt16) async throws {
        callCount += 1
        if let delay { try await Task.sleep(for: delay) }
        if let error { throw error }
    }
}

private actor RecordingRDPProcessLauncher: RDPProcessLaunching {
    private(set) var specifications: [RDPLaunchSpecification] = []

    func launch(_ specification: RDPLaunchSpecification) async throws -> any RDPSessionHandle {
        specifications.append(specification)
        return TestRDPSessionHandle()
    }
}

private final class TestRDPSessionHandle: RDPSessionHandle, @unchecked Sendable {
    let id = UUID()
    let processIdentifier: Int32 = 123
    let startedAt = Date.now

    private let state = RDPProcessState()
    private let continuation: AsyncStream<RDPProcessTermination>.Continuation
    private let exitTask: Task<RDPProcessTermination, Never>

    var isRunning: Bool { state.isRunning }

    init() {
        let pair = AsyncStream<RDPProcessTermination>.makeStream()
        continuation = pair.continuation
        exitTask = Task {
            for await value in pair.stream { return value }
            return RDPProcessTermination(
                exitCode: -1,
                reason: .uncaughtSignal,
                standardOutput: Data(),
                standardError: Data(),
                wasUserInitiated: false
            )
        }
        state.markRunning()
    }

    func waitForExit() async -> RDPProcessTermination {
        await exitTask.value
    }

    func bringToFront() -> Bool { isRunning }

    func terminate() {
        guard state.requestTermination() else { return }
        state.markStopped()
        continuation.yield(RDPProcessTermination(
            exitCode: 15,
            reason: .uncaughtSignal,
            standardOutput: Data(),
            standardError: Data(),
            wasUserInitiated: true
        ))
        continuation.finish()
    }
}

private final class ExecutableFixture: @unchecked Sendable {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteHub-RDP-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func makeExecutable(_ relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data()))
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
        return url
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
