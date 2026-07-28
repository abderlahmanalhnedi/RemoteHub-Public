import XCTest
@testable import RemoteHub

final class TransportContractTests: XCTestCase {
    func testFakeSSHDataFlowsBothDirectionsAndResizes() async throws {
        let session = FakeSSHSession()
        let transport = FakeSSHTransport(session: session)
        let connected = try await transport.connect(configuration: SSHConnectionConfiguration(
            host: "server.example",
            port: 22,
            authentication: .password(username: "demo-user", password: "not-real"),
            terminalType: "xterm-256color",
            timeoutSeconds: 10,
            keepaliveSeconds: 30,
            opensInteractiveShell: true
        ))
        try await connected.send(Data("input".utf8))
        try await connected.resize(columns: 120, rows: 40)
        await connected.disconnect()
        let sent = await session.sent
        let firstWidth = await session.sizes.first?.0
        let disconnected = await session.disconnected
        XCTAssertEqual(sent, [Data("input".utf8)])
        XCTAssertEqual(firstWidth, 120)
        XCTAssertTrue(disconnected)
    }

    func testFilePickerBookmarkFakeRoundTrip() {
        let fake = FakeFilePickerBookmarkProvider()
        let url = URL(fileURLWithPath: "/Users/demo-user/My Files")
        XCTAssertEqual(fake.resolve(fake.bookmark(for: url)), url)
    }
}
