import Citadel
import NIO
import NIOSSH
import XCTest
@testable import RemoteHub

final class SSHNegotiatedHostKeyValidationTests: XCTestCase {
    private let host = "192.0.2.10"
    private let port = 22
    // Synthetic Ed25519 fixture derived from the ascending-byte test seed
    // 0x00...0x1f. It is reproducible and must never be used by an SSH server.
    private let expectedED25519Fingerprint =
        "SHA256:lbmsoA0yIEcEiVDRnMWuzm+nV+3ZEEpVIURqFoeSspg"
    private let ed25519PublicKey =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAOhB7/zzhC+HXDdGOdLwJln5NYwm6UNXx3chmQSVTG4"

    func testPresentedNIOSSHKeyResolvesAlgorithmAndSHA256Fingerprint() throws {
        let candidate = try presentedED25519()

        XCTAssertEqual(candidate.algorithm, "ssh-ed25519")
        XCTAssertEqual(candidate.sha256Fingerprint, expectedED25519Fingerprint)
        XCTAssertEqual(candidate.host, host)
        XCTAssertEqual(candidate.port, port)
    }

    func testED25519NegotiatedKeySucceedsWhenScanOrderStartsWithRSA() async throws {
        let presented = try presentedED25519()
        let recorder = HostTrustPromptRecorder(decision: .trustOnce)
        let validator = makeValidator(
            scanned: [rsaCandidate(), ecdsaCandidate(), presented],
            recorder: recorder
        )

        try await validator.validate(presented)

        let evaluations = await recorder.recordedEvaluations()
        XCTAssertEqual(evaluations, [.unknown(presented)])
    }

    func testUnknownNegotiatedKeyPromptsForExactPresentedKey() async throws {
        let presented = try presentedED25519()
        let recorder = HostTrustPromptRecorder(decision: .trustAndSave)
        let store = InMemoryKnownHostStore()
        let validator = SSHNegotiatedHostKeyValidator(
            scannedCandidates: [rsaCandidate(), ecdsaCandidate(), presented],
            trustController: HostTrustController(store: store),
            trustPrompt: { evaluation in
                await recorder.respond(to: evaluation)
            }
        )

        try await validator.validate(presented)

        let evaluations = await recorder.recordedEvaluations()
        let savedEvaluation = try await HostTrustController(store: store).evaluate(presented)
        XCTAssertEqual(evaluations, [.unknown(presented)])
        XCTAssertEqual(savedEvaluation, .trusted)
    }

    func testStoredMatchingNegotiatedKeySucceedsWithoutPrompt() async throws {
        let presented = try presentedED25519()
        let store = InMemoryKnownHostStore()
        let controller = HostTrustController(store: store)
        try await controller.apply(.trustAndSave, candidate: presented)
        let recorder = HostTrustPromptRecorder(decision: .cancel)
        let validator = SSHNegotiatedHostKeyValidator(
            scannedCandidates: [rsaCandidate(), ecdsaCandidate(), presented],
            trustController: controller,
            trustPrompt: { evaluation in
                await recorder.respond(to: evaluation)
            }
        )

        try await validator.validate(presented)

        let evaluations = await recorder.recordedEvaluations()
        XCTAssertEqual(evaluations, [])
    }

    func testChangedFingerprintIsBlockedWithoutExplicitReplacement() async throws {
        let presented = try presentedED25519()
        let saved = HostKeyCandidate(
            host: host,
            port: port,
            algorithm: presented.algorithm,
            sha256Fingerprint: "SHA256:old-ed25519",
            publicKeyData: Data("old-ed25519".utf8)
        )
        let store = InMemoryKnownHostStore()
        try await store.save(saved)
        let recorder = HostTrustPromptRecorder(decision: .trustOnce)
        let validator = SSHNegotiatedHostKeyValidator(
            scannedCandidates: [presented],
            trustController: HostTrustController(store: store),
            trustPrompt: { evaluation in
                await recorder.respond(to: evaluation)
            }
        )

        do {
            try await validator.validate(presented)
            XCTFail("A changed key must require explicit replacement")
        } catch let error as RemoteHubError {
            XCTAssertEqual(error.category, .hostKeyChanged)
        }

        let evaluations = await recorder.recordedEvaluations()
        XCTAssertEqual(
            evaluations,
            [.changed(savedFingerprint: saved.sha256Fingerprint, candidate: presented)]
        )
    }

    func testPresentedKeyMissingFromScanIsRejectedWithoutPrompt() async throws {
        let presented = try presentedED25519()
        let recorder = HostTrustPromptRecorder(decision: .trustOnce)
        let validator = makeValidator(
            scanned: [rsaCandidate(), ecdsaCandidate()],
            recorder: recorder
        )

        do {
            try await validator.validate(presented)
            XCTFail("A negotiated key absent from the scan must be rejected")
        } catch let error as RemoteHubError {
            XCTAssertEqual(error.category, .hostKeyUnknown)
            XCTAssertTrue(error.message.contains("did not match"))
        }

        let evaluations = await recorder.recordedEvaluations()
        XCTAssertEqual(evaluations, [])
    }

    func testAuthenticationFailureRemainsDistinctFromHostKeyFailure() async throws {
        let key = try NIOSSHPublicKey(openSSHPublicKey: ed25519PublicKey)
        let eventLoop = EmbeddedEventLoop()
        let promise = eventLoop.makePromise(of: Void.self)
        SSHHostKeyValidator.trustedKeys([]).validateHostKey(
            hostKey: key,
            validationCompletePromise: promise
        )
        let underlyingHostKeyError: Error
        do {
            try await promise.futureResult.get()
            XCTFail("An empty trusted-key set must reject the presented key")
            return
        } catch {
            underlyingHostKeyError = error
        }

        XCTAssertTrue(underlyingHostKeyError is InvalidHostKey)
        let hostKeyError = mapCitadelSSHConnectionError(underlyingHostKeyError)
        let authenticationError = mapCitadelSSHConnectionError(
            SSHClientError.allAuthenticationOptionsFailed
        )

        XCTAssertEqual((hostKeyError as? RemoteHubError)?.category, .hostKeyUnknown)
        XCTAssertEqual(
            (authenticationError as? RemoteHubError)?.category,
            .authenticationFailed
        )
    }

    func testErrorDiagnosticsAreSanitizedAndIncludeCategory() {
        let error = RemoteHubError(
            .hostKeyUnknown,
            message: "Host validation failed.",
            recoverySuggestion: "Verify the fingerprint.",
            technicalDetails: "password=secret"
        )

        XCTAssertTrue(error.diagnostics.contains("Category: hostKeyUnknown"))
        XCTAssertTrue(error.diagnostics.contains("password=<redacted>"))
        XCTAssertFalse(error.diagnostics.contains("secret"))
    }

    private func makeValidator(
        scanned: [HostKeyCandidate],
        recorder: HostTrustPromptRecorder
    ) -> SSHNegotiatedHostKeyValidator {
        SSHNegotiatedHostKeyValidator(
            scannedCandidates: scanned,
            trustController: HostTrustController(store: InMemoryKnownHostStore()),
            trustPrompt: { evaluation in
                await recorder.respond(to: evaluation)
            }
        )
    }

    private func presentedED25519() throws -> HostKeyCandidate {
        let key = try NIOSSHPublicKey(openSSHPublicKey: ed25519PublicKey)
        return try SSHHostKeyCandidateFactory.candidate(
            host: host,
            port: port,
            presentedKey: key
        )
    }

    private func rsaCandidate() -> HostKeyCandidate {
        HostKeyCandidate(
            host: host,
            port: port,
            algorithm: "ssh-rsa",
            sha256Fingerprint: "SHA256:rsa-first",
            publicKeyData: Data("ssh-rsa test".utf8)
        )
    }

    private func ecdsaCandidate() -> HostKeyCandidate {
        HostKeyCandidate(
            host: host,
            port: port,
            algorithm: "ecdsa-sha2-nistp256",
            sha256Fingerprint: "SHA256:ecdsa-second",
            publicKeyData: Data("ecdsa-sha2-nistp256 test".utf8)
        )
    }
}

private actor HostTrustPromptRecorder {
    private let decision: HostTrustDecision
    private var evaluations: [HostTrustEvaluation] = []

    init(decision: HostTrustDecision) {
        self.decision = decision
    }

    func respond(to evaluation: HostTrustEvaluation) -> HostTrustDecision {
        evaluations.append(evaluation)
        return decision
    }

    func recordedEvaluations() -> [HostTrustEvaluation] {
        evaluations
    }
}
