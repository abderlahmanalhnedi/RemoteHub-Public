import Foundation
import XCTest
@testable import RemoteHub

private enum SSHPTYTestError: Error {
    case lateFailure
    case timeout
}

private struct LeakySSHPTYTestError: LocalizedError {
    var errorDescription: String? {
        "password=should-not-escape"
    }
}

private struct ForwardingPTYDriver: SSHPTYDriving {
    let data: Data

    func run(with bridge: SSHPTYBridge) async throws {
        await bridge.forward(data)
    }
}

private struct CancellingPTYDriver: SSHPTYDriving {
    func run(with bridge: SSHPTYBridge) async throws {
        throw CancellationError()
    }
}

private struct FailingPTYDriver: SSHPTYDriving {
    func run(with bridge: SSHPTYBridge) async throws {
        throw LeakySSHPTYTestError()
    }
}

private actor SSHPTYDriverProbe {
    private(set) var started = false
    private(set) var cancellationCount = 0

    func markStarted() {
        started = true
    }

    func markCancelled() {
        cancellationCount += 1
    }
}

private actor SSHPTYWriterProbe {
    private(set) var sent: [Data] = []
    private(set) var sizes: [(Int, Int)] = []

    func recordSend(_ data: Data) {
        sent.append(data)
    }

    func recordResize(columns: Int, rows: Int) {
        sizes.append((columns, rows))
    }
}

private struct SuspendedPTYDriver: SSHPTYDriving {
    let probe: SSHPTYDriverProbe

    func run(with bridge: SSHPTYBridge) async throws {
        await probe.markStarted()
        do {
            try await Task.sleep(for: .seconds(60))
        } catch is CancellationError {
            await probe.markCancelled()
            throw CancellationError()
        }
    }
}

final class SSHPTYControllerTests: XCTestCase {
    func testSendAndResizeFailWhileTerminalWriterIsNotReady() async {
        let controller = SSHPTYController()

        await assertTerminalError(
            message: "The SSH terminal is not ready yet.",
            operation: { try await controller.send(Data("input".utf8)) }
        )
        await assertTerminalError(
            message: "The SSH terminal is not ready yet.",
            operation: { try await controller.resize(columns: 120, rows: 40) }
        )
    }

    func testOutputIsForwardedAndCompletedWhenDriverReturns() async throws {
        let controller = SSHPTYController()
        let expected = Data("terminal output".utf8)
        var iterator = controller.output.makeAsyncIterator()

        try await controller.start(driver: ForwardingPTYDriver(data: expected))

        let forwarded = try await iterator.next()
        let completion = try await iterator.next()
        XCTAssertEqual(forwarded, expected)
        XCTAssertNil(completion)
    }

    func testInstalledWriterForwardsInputAndResize() async throws {
        let stream = AsyncThrowingStream<Data, Error>.makeStream()
        let bridge = SSHPTYBridge(continuation: stream.continuation)
        let probe = SSHPTYWriterProbe()
        try await bridge.install(SSHPTYWriter(
            send: { data in await probe.recordSend(data) },
            resize: { columns, rows in
                await probe.recordResize(columns: columns, rows: rows)
            }
        ))
        let input = Data("input".utf8)

        try await bridge.send(input)
        try await bridge.resize(columns: 132, rows: 48)

        let sent = await probe.sent
        let sizes = await probe.sizes
        XCTAssertEqual(sent, [input])
        XCTAssertEqual(sizes.first?.0, 132)
        XCTAssertEqual(sizes.first?.1, 48)
    }

    func testBridgeCompletesStreamExactlyOnce() async throws {
        let stream = AsyncThrowingStream<Data, Error>.makeStream()
        let bridge = SSHPTYBridge(continuation: stream.continuation)
        var iterator = stream.stream.makeAsyncIterator()

        await bridge.finish()
        await bridge.finish(throwing: SSHPTYTestError.lateFailure)

        let completion = try await iterator.next()
        XCTAssertNil(completion)
    }

    func testDriverCancellationCompletesStreamWithoutAnError() async throws {
        let controller = SSHPTYController()
        var iterator = controller.output.makeAsyncIterator()

        try await controller.start(driver: CancellingPTYDriver())

        let completion = try await iterator.next()
        XCTAssertNil(completion)
    }

    func testDriverFailureCompletesStreamWithSanitizedError() async throws {
        let controller = SSHPTYController()
        var iterator = controller.output.makeAsyncIterator()
        try await controller.start(driver: FailingPTYDriver())

        do {
            _ = try await iterator.next()
            XCTFail("Expected the output stream to fail.")
        } catch let error as RemoteHubError {
            XCTAssertEqual(error.category, .networkUnavailable)
            XCTAssertEqual(error.message, "The SSH terminal connection ended unexpectedly.")
            XCTAssertEqual(error.technicalDetails, "password=<redacted>")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDisconnectCancelsDriverOnceAndIsIdempotent() async throws {
        let controller = SSHPTYController()
        let probe = SSHPTYDriverProbe()
        var iterator = controller.output.makeAsyncIterator()
        try await controller.start(driver: SuspendedPTYDriver(probe: probe))
        try await waitUntil { await probe.started }

        await controller.disconnect()
        await controller.disconnect()

        let cancellationCount = await probe.cancellationCount
        let completion = try await iterator.next()
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertNil(completion)
        await assertTerminalError(
            message: "The SSH terminal is closed.",
            operation: { try await controller.send(Data("input".utf8)) }
        )
    }

    private func assertTerminalError(
        message: String,
        operation: @escaping @Sendable () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected the terminal operation to fail.")
        } catch let error as RemoteHubError {
            XCTAssertEqual(error.category, .networkUnavailable)
            XCTAssertEqual(error.message, message)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw SSHPTYTestError.timeout
    }
}
