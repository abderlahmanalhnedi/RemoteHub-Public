import XCTest
@testable import RemoteHub

final class FTPListingParserTests: XCTestCase {
    func testUnixFormatSpacesUnicodeAndSymlink() throws {
        let listing = """
        drwxr-xr-x 2 demo users 4096 Jan 02 2025 Folder With Spaces
        -rw-r--r-- 1 demo users 123 Jan 03 12:30 résumé.txt
        lrwxrwxrwx 1 demo users 7 Jan 04 2025 latest -> release
        """
        let items = try FTPListingParser.parse(listing, basePath: "/pub")
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].name, "Folder With Spaces")
        XCTAssertEqual(items[0].type, .directory)
        XCTAssertEqual(items[1].name, "résumé.txt")
        XCTAssertEqual(items[2].type, .symbolicLink)
        XCTAssertEqual(items[2].symbolicLinkTarget, "release")
    }

    func testDOSFormat() throws {
        let item = try FTPListingParser.parseLine(
            "07-25-2026  10:42PM       <DIR>          Folder With Spaces",
            basePath: "/"
        )
        XCTAssertEqual(item.name, "Folder With Spaces")
        XCTAssertEqual(item.type, .directory)
    }

    func testMLSDFormat() throws {
        let item = try FTPListingParser.parseLine(
            "type=file;size=42;modify=20260725103045;unix.mode=0644; résumé data.txt",
            basePath: "/pub"
        )
        XCTAssertEqual(item.name, "résumé data.txt")
        XCTAssertEqual(item.size, 42)
        XCTAssertEqual(item.permissions, "0644")
    }

    func testUnparseableLineReturnsError() {
        XCTAssertThrowsError(try FTPListingParser.parseLine("not a listing", basePath: "/"))
    }
}
