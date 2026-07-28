import Security
import XCTest
@testable import RemoteHub

final class CredentialSecurityTests: XCTestCase {
    private let testSecret = "TEST-SECRET-MUST-NEVER-LEAK-94721"

    func testSaveUpdatePreserveAndRemoveSecret() async throws {
        let store = InMemoryCredentialStore()
        let id = UUID()
        let account = try await CredentialSecretCoordinator.apply(
            edit: .replace(testSecret),
            type: .loginPassword,
            credentialID: id,
            existingAccount: nil,
            store: store
        )
        let saved = try await store.read(account: try XCTUnwrap(account))
        XCTAssertEqual(saved, testSecret)

        let preserved = try await CredentialSecretCoordinator.apply(
            edit: .unchanged,
            type: .loginPassword,
            credentialID: id,
            existingAccount: account,
            store: store
        )
        XCTAssertEqual(preserved, account)

        _ = try await CredentialSecretCoordinator.apply(
            edit: .replace("replacement"),
            type: .loginPassword,
            credentialID: id,
            existingAccount: account,
            store: store
        )
        let updated = try await store.read(account: try XCTUnwrap(account))
        XCTAssertEqual(updated, "replacement")

        let removed = try await CredentialSecretCoordinator.apply(
            edit: .remove,
            type: .loginPassword,
            credentialID: id,
            existingAccount: account,
            store: store
        )
        XCTAssertNil(removed)
        let stillExists = try await store.contains(account: try XCTUnwrap(account))
        XCTAssertFalse(stillExists)
    }

    func testKeychainErrorMappingIsSanitized() async {
        let store = KeychainCredentialStore(service: "test.invalid")
        let error = await store.mappedError(status: errSecNotAvailable)
        XCTAssertEqual(error.category, .keychainUnavailable)
        XCTAssertFalse(error.message.contains(testSecret))
    }

    func testCredentialModelHasNoPlaintextSecretProperty() {
        let model = CredentialProfile(displayName: "Demo", username: "demo-user")
        let labels = Set(Mirror(reflecting: model).children.compactMap(\.label))
        XCTAssertFalse(labels.contains("password"))
        XCTAssertFalse(labels.contains("passphrase"))
        XCTAssertFalse(labels.contains("secret"))
    }

    func testExportAndDiagnosticsNeverContainSecret() async throws {
        let store = InMemoryCredentialStore()
        let credential = CredentialProfile(displayName: "Demo", username: "demo-user")
        let account = SecretType.loginPassword.account(for: credential.id)
        try await store.save(testSecret, account: account)
        credential.passwordKeychainAccount = account
        let connection = ConnectionProfile(
            name: "Demo",
            kind: .ssh,
            host: "server.example"
        )
        let export = try ImportExportService.export(
            groups: [],
            credentials: [credential],
            connections: [connection],
            includeCredentialMetadata: true
        )
        let diagnostic = Redactor.diagnosticSummary(protocolKind: .ssh, category: .authenticationFailed)
        XCTAssertFalse(String(decoding: export, as: UTF8.self).contains(testSecret))
        XCTAssertFalse(diagnostic.contains(testSecret))
    }

    func testRedactorRemovesURLAndAssignmentSecrets() {
        let input = "ftp://demo-user:\(testSecret)@server.example password=\(testSecret)"
        let output = Redactor.sanitize(input)
        XCTAssertFalse(output.contains(testSecret))
        XCTAssertTrue(output.contains("<redacted>"))
    }

    func testCurlArgumentsNeverContainPassword() throws {
        let invocation = try CurlCommandBuilder.build(
            configuration: FTPConnectionConfiguration(
                kind: .ftpsExplicit,
                host: "server.example",
                port: 21,
                username: "demo-user",
                password: testSecret,
                passiveMode: true,
                verifyTLSCertificate: true,
                timeoutSeconds: 15
            ),
            remotePath: "/folder with spaces"
        )
        XCTAssertFalse(invocation.arguments.joined(separator: " ").contains(testSecret))
        XCTAssertTrue(String(decoding: invocation.standardInput, as: UTF8.self).contains(testSecret))
        XCTAssertFalse(invocation.arguments.contains("--insecure"))
    }
}
