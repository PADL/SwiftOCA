// swift-tools-version:5.9
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

let PlatformPackages: [Package.Dependency]
let PlatformDependencies: [Target.Dependency]
let PlatformTargets: [Target]

#if os(Linux)
PlatformPackages = [.package(url: "https://github.com/PADL/IORingSwift", branch: "main")]

PlatformDependencies = [
    "dnssd",
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

PlatformTargets = []
#else
PlatformPackages = [.package(url: "https://github.com/swhitty/FlyingFox", branch: "main"),
                    .package(
                        url: "https://github.com/spacenation/swiftui-sliders.git",
                        from: "2.1.0"
                    )]

PlatformDependencies = [
    .product(
        name: "FlyingFox",
        package: "FlyingFox",
        condition: .when(platforms: [.macOS, .iOS])
    ),
    .product(
        name: "FlyingSocks",
        package: "FlyingFox",
        condition: .when(platforms: [.macOS, .iOS])
    ),
]

PlatformTargets = [
    .target(
        name: "SwiftOCAUI",
        dependencies: [
            "SwiftOCA",
            .product(
                name: "Sliders",
                package: "swiftui-sliders",
                condition: .when(platforms: [.macOS, .iOS])
            ),
        ]
    ),
    .executableTarget(
        name: "OCABrowser",
        dependencies: [
            "SwiftOCAUI",
        ],
        path: "Examples/OCABrowser",
        resources: [
            .process("Assets.xcassets"),
            .process("Preview Content/Preview Assets.xcassets"),
            .process("OCABrowser.entitlements"),
        ],
        swiftSettings: [
            .unsafeFlags(ASANSwiftFlags),
        ],
        linkerSettings: [] + ASANLinkerSettings
    ),
]
#endif

let package = Package(
    name: "SwiftOCA",
    platforms: [
        .macOS(.v13),
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
        .package(url: "https://github.com/apple/swift-log", branch: "main"),
        .package(url: "https://github.com/lhoward/AsyncExtensions", branch: "linux"),
        .package(url: "https://github.com/Flight-School/AnyCodable", from: "0.6.7"),
    ] + PlatformPackages,
    targets: [
        .systemLibrary(
            name: "dnssd",
            providers: [.apt(["libavahi-compat-libdnssd-dev"])]
        ),
        .target(
            name: "SwiftOCA",
            dependencies: [
                "AsyncExtensions",
                "AnyCodable",
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Logging", package: "swift-log"),
            ] + PlatformDependencies,
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .target(
            name: "SwiftOCADevice",
            dependencies: [
                "SwiftOCA",
                .product(name: "Logging", package: "swift-log"),
            ] + PlatformDependencies,
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
