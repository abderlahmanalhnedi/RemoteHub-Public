import AppKit
import Foundation

protocol RDPProcessLaunching: Sendable {
    func launch(_ specification: RDPLaunchSpecification) async throws -> any RDPSessionHandle
}

struct FoundationRDPProcessLauncher: RDPProcessLaunching {
    func launch(_ specification: RDPLaunchSpecification) async throws -> any RDPSessionHandle {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputBuffer = BoundedProcessOutput()
        let errorBuffer = BoundedProcessOutput()
        let state = RDPProcessState()
        let termination = AsyncStream<RDPProcessTermination>.makeStream()

        process.executableURL = specification.executableURL
        process.arguments = specification.arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { outputBuffer.append(data) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { errorBuffer.append(data) }
        }
        process.terminationHandler = { completed in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            outputBuffer.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
            errorBuffer.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
            state.markStopped()
            termination.continuation.yield(RDPProcessTermination(
                exitCode: completed.terminationStatus,
                reason: completed.terminationReason == .uncaughtSignal ? .uncaughtSignal : .exited,
                standardOutput: outputBuffer.data,
                standardError: errorBuffer.data,
                wasUserInitiated: state.wasTerminationRequested
            ))
            termination.continuation.finish()
        }

        do {
            try process.run()
            state.markRunning()
            if let standardInput = specification.standardInput {
                inputPipe.fileHandleForWriting.write(standardInput)
            }
            try inputPipe.fileHandleForWriting.close()
            return ProcessRDPSessionHandle(
                process: process,
                state: state,
                terminationStream: termination.stream
            )
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            try? inputPipe.fileHandleForWriting.close()
            termination.continuation.finish()
            throw RemoteHubError(
                .processLaunchFailed,
                message: "The Remote Desktop client could not be launched.",
                recoverySuggestion: "Verify the app installation or the Advanced executable override.",
                technicalDetails: error.localizedDescription
            )
        }
    }
}

final class ProcessRDPSessionHandle: RDPSessionHandle, @unchecked Sendable {
    let id = UUID()
    let processIdentifier: Int32
    let startedAt: Date

    private let process: Process
    private let state: RDPProcessState
    private let exitTask: Task<RDPProcessTermination, Never>

    var isRunning: Bool { state.isRunning }

    init(
        process: Process,
        state: RDPProcessState,
        terminationStream: AsyncStream<RDPProcessTermination>,
        startedAt: Date = .now
    ) {
        self.process = process
        self.state = state
        self.processIdentifier = process.processIdentifier
        self.startedAt = startedAt
        self.exitTask = Task {
            for await result in terminationStream {
                return result
            }
            return RDPProcessTermination(
                exitCode: -1,
                reason: .uncaughtSignal,
                standardOutput: Data(),
                standardError: Data("FreeRDP ended without a termination result.".utf8),
                wasUserInitiated: state.wasTerminationRequested
            )
        }
    }

    func waitForExit() async -> RDPProcessTermination {
        await exitTask.value
    }

    @discardableResult
    func bringToFront() -> Bool {
        guard isRunning,
              let application = NSRunningApplication(processIdentifier: processIdentifier)
        else { return false }
        return application.activate(options: [.activateAllWindows])
    }

    func terminate() {
        guard state.requestTermination() else { return }
        if process.isRunning { process.terminate() }
    }
}

final class RDPProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var running = false
    private var finished = false
    private var terminationRequested = false

    var isRunning: Bool { lock.withLock { running } }
    var wasTerminationRequested: Bool { lock.withLock { terminationRequested } }

    func markRunning() {
        lock.withLock {
            if !finished { running = true }
        }
    }

    func markStopped() {
        lock.withLock {
            running = false
            finished = true
        }
    }

    func requestTermination() -> Bool {
        lock.withLock {
            guard running, !terminationRequested else { return false }
            terminationRequested = true
            return true
        }
    }
}

private final class BoundedProcessOutput: @unchecked Sendable {
    private static let maximumBytes = 256 * 1_024
    private let lock = NSLock()
    private var storage = Data()

    var data: Data { lock.withLock { storage } }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock {
            storage.append(data)
            if storage.count > Self.maximumBytes {
                storage.removeFirst(storage.count - Self.maximumBytes)
            }
        }
    }
}
