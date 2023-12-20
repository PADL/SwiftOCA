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

let mDNSLibraryTarget: Target
let TransportPackage: Package.Dependency
let TransportDependencies: [Target.Dependency]

#if os(Linux)
mDNSLibraryTarget = Target.systemLibrary(
    name: "dnssd",
    providers: [.apt(["libavahi-compat-libdnssd-dev"])]
)

TransportPackage = .package(url: "https://github.com/PADL/IORingSwift", branch: "main")

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
// FIXME: [Target] doesn't type check, is there a better way?
mDNSLibraryTarget = Target.target(
    name: "__mDNSLibraryTarget__placeholder__",
    path: "Sources/dnssd",
    exclude: ["."]
)

TransportPackage = .package(url: "https://github.com/swhitty/FlyingFox", branch: "main")

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
        TransportPackage,
    ],
    targets: [
        mDNSLibraryTarget,
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
                "dnssd",
            ] + TransportDependencies,
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
