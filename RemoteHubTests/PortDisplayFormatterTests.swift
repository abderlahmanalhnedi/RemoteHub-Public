import Foundation
import XCTest
@testable import RemoteHub

final class PortDisplayFormatterTests: XCTestCase {
    func testPortsUsePlainASCIIDecimalDigits() {
        XCTAssertEqual(PortDisplayFormatter.string(22), "22")
        XCTAssertEqual(PortDisplayFormatter.string(443), "443")
        XCTAssertEqual(PortDisplayFormatter.string(22_422), "22422")
        XCTAssertEqual(PortDisplayFormatter.string(65_535), "65535")
    }

    func testEndpointPortRemainsUngroupedUnderGermanLocalization() {
        let endpoint = PortDisplayFormatter.endpoint(host: "127.0.0.1", port: 22_422)
        let localized = String(
            localized: "Endpoint: \(endpoint)",
            locale: Locale(identifier: "de_DE")
        )

        XCTAssertEqual(endpoint, "127.0.0.1:22422")
        XCTAssertEqual(localized, "Endpoint: 127.0.0.1:22422")
        XCTAssertFalse(localized.contains("22.422"))
    }

    func testInputFormatUsesUngroupedASCIIDigits() {
        XCTAssertEqual(PortDisplayFormatter.inputFormat.format(22_422), "22422")
    }
}
