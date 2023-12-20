// swift-tools-version:5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let EnableASAN = false
var ASANCFlags: [String] = []
var ASANSwiftFlags: [String] = []
var ASANLinkerSettings: [LinkerSetting] = []

if EnableASAN {
    ASANCFlags.append("-fsanitize=address")
    ASANSwiftFlags.append("-sanitize=address")
    ASANLinkerSettings.append(LinkerSetting.linkedLibrary("asan"))
}

let TransportDependencies: [Target.Dependency]
let mDNSDependencies: [Target.Dependency]

#if os(Linux)
mDNSDependencies = [
    "dnssd",
]
TransportDependencies = [
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
#else
mDNSDependencies = []
TransportDependencies = [
    .product(
        name: "FlyingSocks",
        package: "FlyingFox",
        condition: .when(platforms: [.macOS, .iOS])
    ),
]
#endif

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
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
            ] + TransportDependencies,
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "SwiftOCADevice",
            dependencies: [
                "SwiftOCA",
            ] + mDNSDependencies + TransportDependencies,
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .executableTarget(
            name: "OCADevice",
            dependencies: [
                "SwiftOCADevice",
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
