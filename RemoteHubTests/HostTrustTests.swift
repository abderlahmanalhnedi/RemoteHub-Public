import XCTest
@testable import RemoteHub

final class HostTrustTests: XCTestCase {
    private let first = HostKeyCandidate(
        host: "server.example",
        port: 22,
        algorithm: "ssh-ed25519",
        sha256Fingerprint: "SHA256:first",
        publicKeyData: Data("first".utf8)
    )

    func testUnknownHostAsksForTrust() async throws {
        let controller = HostTrustController(store: InMemoryKnownHostStore())
        let evaluation = try await controller.evaluate(first)
        XCTAssertEqual(evaluation, .unknown(first))
    }

    func testTrustOnceDoesNotPersist() async throws {
        let store = InMemoryKnownHostStore()
        let controller = HostTrustController(store: store)
        try await controller.apply(.trustOnce, candidate: first)
        let evaluation = try await controller.evaluate(first)
        XCTAssertEqual(evaluation, .unknown(first))
    }

    func testTrustAndSaveThenMatchingSucceeds() async throws {
        let store = InMemoryKnownHostStore()
        let controller = HostTrustController(store: store)
        try await controller.apply(.trustAndSave, candidate: first)
        let evaluation = try await controller.evaluate(first)
        XCTAssertEqual(evaluation, .trusted)
    }

    func testChangedKeyBlocks() async throws {
        let store = InMemoryKnownHostStore()
        let controller = HostTrustController(store: store)
        try await controller.apply(.trustAndSave, candidate: first)
        let changed = HostKeyCandidate(
            host: first.host,
            port: first.port,
            algorithm: first.algorithm,
            sha256Fingerprint: "SHA256:changed",
            publicKeyData: Data("changed".utf8)
        )
        let evaluation = try await controller.evaluate(changed)
        XCTAssertEqual(
            evaluation,
            .changed(savedFingerprint: first.sha256Fingerprint, candidate: changed)
        )
    }

    func testReplacementRequiresExplicitConfirmation() async throws {
        let store = InMemoryKnownHostStore()
        try await store.save(first)
        await XCTAssertThrowsErrorAsync {
            try await store.replace(
                HostKeyCandidate(
                    host: self.first.host,
                    port: self.first.port,
                    algorithm: self.first.algorithm,
                    sha256Fingerprint: "SHA256:changed",
                    publicKeyData: nil
                ),
                confirmed: false
            )
        }
    }

    func testMultipleAlgorithmsForOneHostAreStoredIndependently() async throws {
        let store = InMemoryKnownHostStore()
        let controller = HostTrustController(store: store)
        let rsa = HostKeyCandidate(
            host: first.host,
            port: first.port,
            algorithm: "ssh-rsa",
            sha256Fingerprint: "SHA256:rsa",
            publicKeyData: Data("rsa".utf8)
        )

        try await controller.apply(.trustAndSave, candidate: rsa)
        try await controller.apply(.trustAndSave, candidate: first)

        let rsaEvaluation = try await controller.evaluate(rsa)
        let ed25519Evaluation = try await controller.evaluate(first)
        XCTAssertEqual(rsaEvaluation, .trusted)
        XCTAssertEqual(ed25519Evaluation, .trusted)
    }

    func testNewAlgorithmForKnownHostPromptsIndependently() async throws {
        let store = InMemoryKnownHostStore()
        let controller = HostTrustController(store: store)
        let rsa = HostKeyCandidate(
            host: first.host,
            port: first.port,
            algorithm: "ssh-rsa",
            sha256Fingerprint: "SHA256:rsa",
            publicKeyData: Data("rsa".utf8)
        )

        try await controller.apply(.trustAndSave, candidate: rsa)

        let evaluation = try await controller.evaluate(first)
        XCTAssertEqual(evaluation, .unknown(first))
    }
}

func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        // Expected.
    }
}
