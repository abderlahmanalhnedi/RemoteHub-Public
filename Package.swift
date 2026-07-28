// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "RemoteHub",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RemoteHub", targets: ["RemoteHub"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.14.0"),
        .package(url: "https://github.com/orlandos-nl/Citadel.git", exact: "0.12.1"),
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", exact: "0.3.4"),
        // NIO 2.84+ conditionally references Swift 6.2 stdlib-only APIs. Pin the
        // newest pre-change release so Command Line Tools with the macOS 15.4
        // SDK remains a supported bootstrap path.
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.83.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.12.3"),
        // Constrains NIO's transitive dependency to a Swift 6.1-compatible release.
        .package(url: "https://github.com/apple/swift-collections.git", exact: "1.2.1")
    ],
    targets: [
        .target(
            name: "RemoteHub",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Collections", package: "swift-collections")
            ],
            path: "RemoteHub",
            exclude: ["App/RemoteHubApp.swift"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RemoteHubTests",
            dependencies: ["RemoteHub"],
            path: "RemoteHubTests",
            resources: []
        )
    ]
)
