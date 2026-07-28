import XCTest
@testable import RemoteHub

final class ImportExportTests: XCTestCase {
    func testRoundTripUnicodeAndRedaction() throws {
        let group = ConnectionGroup(name: "خوادم München")
        let credential = CredentialProfile(
            displayName: "Admin 🔐",
            username: "demo-user",
            authenticationType: .usernamePassword,
            passwordKeychainAccount: "opaque.account"
        )
        let connection = ConnectionProfile(
            name: "خادم München",
            kind: .sftp,
            host: "server.example",
            groupID: group.id,
            credentialProfileID: credential.id,
            tags: ["اختبار", "München"],
            notes: "Unicode ✓",
            isFavorite: true
        )
        let data = try ImportExportService.export(
            groups: [group],
            credentials: [credential],
            connections: [connection],
            includeCredentialMetadata: true,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let decoded = try ImportExportService.preview(data: data)
        XCTAssertEqual(decoded.connections.first?.name, connection.name)
        XCTAssertEqual(decoded.connections.first?.tags, connection.tags)
        XCTAssertEqual(decoded.credentialMetadata.first?.username, "demo-user")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("opaque.account"))
    }

    func testDefaultExportOmitsCredentialMetadataAndLink() throws {
        let credential = CredentialProfile(displayName: "Admin", username: "demo-user")
        let connection = ConnectionProfile(
            name: "Demo",
            kind: .ssh,
            host: "server.example",
            credentialProfileID: credential.id
        )
        let data = try ImportExportService.export(
            groups: [],
            credentials: [credential],
            connections: [connection],
            includeCredentialMetadata: false
        )
        let decoded = try ImportExportService.preview(data: data)
        XCTAssertTrue(decoded.credentialMetadata.isEmpty)
        XCTAssertNil(decoded.connections.first?.credentialMetadataID)
    }

    func testRejectsFutureSchema() throws {
        let data = Data("""
        {"schemaVersion":99,"exportedAt":"2026-07-25T00:00:00Z","application":"RemoteHub","groups":[],"credentialMetadata":[],"connections":[]}
        """.utf8)
        XCTAssertThrowsError(try ImportExportService.preview(data: data))
    }

    func testDuplicatePoliciesAreDistinct() {
        XCTAssertEqual(Set(DuplicateImportPolicy.allCases).count, 3)
    }
}
