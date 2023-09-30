// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let EnableASAN = true
var ASANCFlags: [String] = []
var ASANSwiftFlags: [String] = []
var ASANLinkerSettings: [LinkerSetting] = []

if EnableASAN {
    ASANCFlags.append("-fsanitize=address")
    ASANSwiftFlags.append("-sanitize=address")
    ASANLinkerSettings.append(LinkerSetting.linkedLibrary("asan"))
}

let package = Package(
    name: "SwiftOCA",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "SwiftOCA",
            targets: ["SwiftOCA"]
        ),
        .library(
            name: "SwiftOCADevice",
            targets: ["SwiftOCADevice"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "0.1.0"),
        .package(url: "https://github.com/PADL/swift-binary-coder", branch: "inferno"),
        .package(url: "https://github.com/lhoward/AsyncExtensions", branch: "linux"),
        .package(url: "https://github.com/swhitty/FlyingFox", branch: "main"),
        .package(url: "https://github.com/PADL/IORingSwift", branch: "main"),
    ],
    targets: [
        .systemLibrary(
            name: "dnssd",
            providers: [.apt(["libavahi-compat-libdnssd-dev"])]
        ),
        .target(
            name: "SwiftOCA",
            dependencies: [
                "AsyncExtensions",
                .product(name: "BinaryCoder", package: "swift-binary-coder"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(
                    name: "FlyingSocks",
                    package: "FlyingFox",
                    condition: .when(platforms: [.macOS, .iOS])
                ),
                .product(
                    name: "IORing",
                    package: "IORingSwift",
                    condition: .when(platforms: [.linux])
                ),
                .product(
                    name: "IORingUtils",
                    package: "IORingSwift",
                    condition: .when(platforms: [.linux])
                ),
                .product(
                    name: "IORingFoundation",
                    package: "IORingSwift",
                    condition: .when(platforms: [.linux])
                ),
            ]
        ),
        .target(
            name: "SwiftOCADevice",
            dependencies: [
                "SwiftOCA",
                "dnssd",
                .product(
                    name: "FlyingSocks",
                    package: "FlyingFox",
                    condition: .when(platforms: [.macOS, .iOS])
                ),
                .product(
                    name: "IORing",
                    package: "IORingSwift",
                    condition: .when(platforms: [.linux])
                ),
                .product(
                    name: "IORingUtils",
                    package: "IORingSwift",
                    condition: .when(platforms: [.linux])
                ),
            ]
        ),
        .executableTarget(
            name: "OCADevice",
            dependencies: [
                "SwiftOCADevice",
                .product(name: "FlyingSocks", package: "FlyingFox"),
            ],
            path: "Examples/OCADevice",
            swiftSettings: [
                .unsafeFlags(ASANSwiftFlags),
            ],
            linkerSettings: [] + ASANLinkerSettings

        ),
        .testTarget(
            name: "SwiftOCADeviceTests",
            dependencies: [
                .target(name: "SwiftOCADevice"),
            ],
            swiftSettings: [
                .unsafeFlags(ASANSwiftFlags),
            ],
            linkerSettings: [] + ASANLinkerSettings
        ),
    ],
    swiftLanguageVersions: [.v5]
)
