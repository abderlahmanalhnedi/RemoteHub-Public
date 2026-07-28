import XCTest
@testable import RemoteHub

final class ValidationTests: XCTestCase {
    func testDefaultPorts() {
        XCTAssertEqual(ConnectionKind.ssh.defaultPort, 22)
        XCTAssertEqual(ConnectionKind.sftp.defaultPort, 22)
        XCTAssertEqual(ConnectionKind.ftp.defaultPort, 21)
        XCTAssertEqual(ConnectionKind.ftpsExplicit.defaultPort, 21)
        XCTAssertEqual(ConnectionKind.ftpsImplicit.defaultPort, 990)
        XCTAssertEqual(ConnectionKind.rdp.defaultPort, 3389)
    }

    func testHosts() {
        XCTAssertTrue(Validators.host("server.example").isEmpty)
        XCTAssertTrue(Validators.host("192.0.2.10").isEmpty)
        XCTAssertTrue(Validators.host("2001:db8::10").isEmpty)
        XCTAssertTrue(Validators.host("my-server.example").isEmpty)
        XCTAssertFalse(Validators.host("user:password@server.example").isEmpty)
        XCTAssertFalse(Validators.host("ssh://server.example/path").isEmpty)
        XCTAssertFalse(Validators.host("server.example\u{0007}").isEmpty)
    }

    func testPortBoundariesAndName() {
        XCTAssertTrue(Validators.port(1).isEmpty)
        XCTAssertTrue(Validators.port(65_535).isEmpty)
        XCTAssertFalse(Validators.port(0).isEmpty)
        XCTAssertFalse(Validators.port(65_536).isEmpty)
        XCTAssertFalse(Validators.connectionName("  ").isEmpty)
        XCTAssertTrue(Validators.connectionName("Demo Server").isEmpty)
    }

    func testProtocolChangesPreserveManualPort() {
        var automatic = PortSelectionState(kind: .ssh)
        automatic.changeKind(to: .rdp)
        XCTAssertEqual(automatic.port, 3389)

        var manual = PortSelectionState(kind: .ssh)
        manual.setPort(2222)
        manual.changeKind(to: .rdp)
        XCTAssertEqual(manual.port, 2222)
    }

    func testDuplicateGroupNamesAreCaseInsensitive() {
        let issues = Validators.groupName("  Production ", existingNames: ["production"])
        XCTAssertEqual(issues, [.duplicateGroup])
    }

    func testRDPResolutionValidation() {
        XCTAssertTrue(Validators.rdpResolution(dynamic: true, width: -1, height: -1).isEmpty)
        XCTAssertTrue(Validators.rdpResolution(dynamic: false, width: 1920, height: 1080).isEmpty)
        XCTAssertFalse(Validators.rdpResolution(dynamic: false, width: 10, height: 10).isEmpty)
    }
}
