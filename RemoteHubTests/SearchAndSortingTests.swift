import XCTest
@testable import RemoteHub

final class SearchAndSortingTests: XCTestCase {
    private let group = ConnectionGroup(name: "Production")

    func testSearchNameHostTagGroupAndProtocolCaseInsensitively() {
        let connection = ConnectionProfile(
            name: "Web Server",
            kind: .ssh,
            host: "server.example",
            groupID: group.id,
            tags: ["Linux", "Critical"]
        )
        for query in ["web", "EXAMPLE", "linux", "production", "ssh"] {
            XCTAssertEqual(
                ConnectionSearch.filter([connection], query: query, groups: [group]).count,
                1,
                "Expected match for \(query)"
            )
        }
        XCTAssertTrue(ConnectionSearch.filter([connection], query: "rdp", groups: [group]).isEmpty)
    }

    func testSorting() {
        let a = ConnectionProfile(name: "Alpha", kind: .rdp, host: "z.example")
        let b = ConnectionProfile(name: "beta", kind: .ssh, host: "a.example")
        XCTAssertEqual(ConnectionSearch.sort([b, a], by: .name).map(\.name), ["Alpha", "beta"])
        XCTAssertEqual(ConnectionSearch.sort([a, b], by: .host).map(\.host), ["a.example", "z.example"])
        XCTAssertEqual(ConnectionSearch.sort([a, b], by: .protocolKind).map(\.kind), [.rdp, .ssh])
    }
}
