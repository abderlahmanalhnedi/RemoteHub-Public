import XCTest
@testable import RemoteHub

private actor ConcurrencyProbe {
    private(set) var running = 0
    private(set) var maximum = 0
    private(set) var attempts = 0

    func begin() {
        running += 1
        attempts += 1
        maximum = max(maximum, running)
    }

    func end() { running -= 1 }
}

@MainActor
final class TransferQueueTests: XCTestCase {
    func testProgressDuplicatePreventionAndSuccess() async throws {
        let queue = TransferQueue(maximumConcurrent: 1)
        let id = try XCTUnwrap(queue.enqueue(key: "same", title: "One") { progress in
            progress?(TransferProgress(bytesTransferred: 5, totalBytes: 10, bytesPerSecond: 5))
        })
        XCTAssertNil(queue.enqueue(key: "same", title: "Duplicate") { _ in })
        try await waitUntil { queue.records.first(where: { $0.id == id })?.status == .succeeded }
        XCTAssertEqual(queue.records.first(where: { $0.id == id })?.progress.bytesTransferred, 5)
    }

    func testConcurrencyLimit() async throws {
        let queue = TransferQueue(maximumConcurrent: 2)
        let probe = ConcurrencyProbe()
        for index in 0..<5 {
            queue.enqueue(key: "\(index)", title: "\(index)") { _ in
                await probe.begin()
                try await Task.sleep(for: .milliseconds(40))
                await probe.end()
            }
        }
        try await waitUntil { queue.records.allSatisfy { $0.status == .succeeded } }
        let maximum = await probe.maximum
        XCTAssertLessThanOrEqual(maximum, 2)
    }

    func testCancellationAndRetry() async throws {
        let queue = TransferQueue(maximumConcurrent: 1)
        let probe = ConcurrencyProbe()
        let id = try XCTUnwrap(queue.enqueue(key: "retry", title: "Retry") { _ in
            await probe.begin()
            let attempt = await probe.attempts
            await probe.end()
            if attempt == 1 {
                throw RemoteHubError(.timeout, message: "Expected failure")
            }
        })
        try await waitUntil { queue.records.first(where: { $0.id == id })?.status == .failed }
        queue.retry(id)
        try await waitUntil { queue.records.first(where: { $0.id == id })?.status == .succeeded }
        XCTAssertEqual(queue.records.first(where: { $0.id == id })?.attempt, 2)

        let cancelID = try XCTUnwrap(queue.enqueue(key: "cancel", title: "Cancel") { _ in
            try await Task.sleep(for: .seconds(2))
        })
        queue.cancel(cancelID)
        XCTAssertEqual(queue.records.first(where: { $0.id == cancelID })?.status, .cancelled)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline {
                XCTFail("Timed out waiting for condition")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
