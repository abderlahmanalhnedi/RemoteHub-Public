import XCTest
@testable import RemoteHub

final class RDPArgumentBuilderTests: XCTestCase {
    private let secret = "TEST-SECRET-MUST-NEVER-LEAK-94721"
    private let installation = RDPInstallation(
        executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/sdl-freerdp"),
        versionDescription: "FreeRDP 3",
        supportsSafePasswordInput: true,
        requiresXQuartz: false
    )

    func testDefaultsAndPasswordSafety() throws {
        let spec = try build(settings: RDPSettings())
        XCTAssertTrue(spec.arguments.contains("/dynamic-resolution"))
        XCTAssertTrue(spec.arguments.contains("+clipboard"))
        XCTAssertTrue(spec.arguments.contains("/from-stdin:force"))
        XCTAssertFalse(spec.arguments.joined().contains(secret))
        XCTAssertTrue(String(decoding: try XCTUnwrap(spec.standardInput), as: UTF8.self).contains(secret))
    }

    func testFullScreenCustomResolutionAndDomain() throws {
        var settings = RDPSettings()
        settings.displayMode = .fullScreen
        settings.dynamicResolution = false
        let full = try build(settings: settings)
        XCTAssertTrue(full.arguments.contains("/f"))
        XCTAssertFalse(full.arguments.contains(where: { $0.hasPrefix("/w:") }))

        settings.displayMode = .windowed
        settings.width = 1920
        settings.height = 1080
        let custom = try build(settings: settings, domain: "EXAMPLE")
        XCTAssertTrue(custom.arguments.contains("/w:1920"))
        XCTAssertTrue(custom.arguments.contains("/h:1080"))
        XCTAssertTrue(custom.arguments.contains("/d:EXAMPLE"))
    }

    func testIPv6ClipboardAndDrivePathWithSpaces() throws {
        var settings = RDPSettings()
        settings.clipboard = false
        settings.redirectDrive = true
        settings.redirectedFolderBookmark = Data("/Users/demo-user/My Files".utf8)
        let spec = try build(settings: settings, host: "2001:db8::10")
        XCTAssertTrue(spec.arguments.contains("/v:[2001:db8::10]:3389"))
        XCTAssertTrue(spec.arguments.contains("-clipboard"))
        XCTAssertTrue(spec.arguments.contains("/drive:RemoteHub,/Users/demo-user/My Files"))
        XCTAssertFalse(spec.arguments.contains { $0.contains(";") || $0.contains("&&") })
    }

    func testUnsafeInputIsRejectedByDefault() {
        let incompatible = RDPInstallation(
            executableURL: installation.executableURL,
            versionDescription: "old",
            supportsSafePasswordInput: false,
            requiresXQuartz: false
        )
        XCTAssertThrowsError(try RDPArgumentBuilder.build(
            installation: incompatible,
            configuration: configuration(settings: RDPSettings()),
            password: secret
        ))
    }

    func testCommandLinePasswordFallbackIsNeverAvailable() {
        let incompatible = RDPInstallation(
            executableURL: installation.executableURL,
            versionDescription: "old",
            supportsSafePasswordInput: false,
            requiresXQuartz: false
        )
        XCTAssertThrowsError(try RDPArgumentBuilder.build(
            installation: incompatible,
            configuration: configuration(settings: RDPSettings()),
            password: secret
        ))
    }

    private func build(
        settings: RDPSettings,
        domain: String? = nil,
        host: String = "server.example"
    ) throws -> RDPLaunchSpecification {
        try RDPArgumentBuilder.build(
            installation: installation,
            configuration: configuration(settings: settings, domain: domain, host: host),
            password: secret
        )
    }

    private func configuration(
        settings: RDPSettings,
        domain: String? = nil,
        host: String = "server.example"
    ) -> RDPConnectionConfiguration {
        RDPConnectionConfiguration(
            host: host,
            port: 3389,
            username: "demo-user",
            domain: domain,
            settings: settings
        )
    }
}
