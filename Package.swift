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

let PlatformPackageDependencies: [Package.Dependency]
let PlatformTargetDependencies: [Target.Dependency]
let PlatformProducts: [Product]
let PlatformTargets: [Target]

#if os(Linux)
PlatformPackageDependencies = [.package(url: "https://github.com/PADL/IORingSwift", from: "0.1.2")]

PlatformTargetDependencies = [
  .target(
    name: "dnssd",
    condition: .when(platforms: [.linux])
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

PlatformProducts = []
PlatformTargets = []
#elseif os(macOS) || os(iOS)
PlatformPackageDependencies = [
  .package(url: "https://github.com/swhitty/FlyingFox", from: "0.20.0"),
  .package(
    url: "https://github.com/spacenation/swiftui-sliders",
    from: "2.1.0"
  ),
]

PlatformTargetDependencies = [
  .product(
    name: "FlyingFox",
    package: "FlyingFox",
    condition: .when(platforms: [.macOS, .iOS, .android])
  ),
  .product(
    name: "FlyingSocks",
    package: "FlyingFox",
    condition: .when(platforms: [.macOS, .iOS, .android])
  ),
]

PlatformProducts = [
  .library(
    name: "SwiftOCAUI",
    targets: ["SwiftOCAUI"]
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
#else
PlatformPackageDependencies = []
PlatformTargetDependencies = []
PlatformProducts = []
PlatformTargets = []
#endif

let CommonPackageDependencies: [Package.Dependency] = [
  .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
  .package(url: "https://github.com/apple/swift-log", from: "1.6.2"),
  .package(url: "https://github.com/apple/swift-system", from: "1.2.1"),
  .package(url: "https://github.com/apple/swift-atomics", from: "1.2.0"),
  .package(url: "https://github.com/PADL/SocketAddress", from: "0.0.1"),
  .package(url: "https://github.com/lhoward/AsyncExtensions", from: "0.9.0"),
  .package(url: "https://github.com/Flight-School/AnyCodable", from: "0.6.7"),
  .package(url: "https://github.com/1024jp/GzipSwift", from: "6.1.0"),
]

let CommonProducts: [Product] = [
  .library(
    name: "SwiftOCA",
    targets: ["SwiftOCA"]
  ),
  .library(
    name: "SwiftOCADevice",
    targets: ["SwiftOCADevice"]
  ),
]

let CommonTargets: [Target] = [
  .systemLibrary(
    name: "dnssd",
    providers: [.apt(["libavahi-compat-libdnssd-dev"])]
  ),
  .target(
    name: "SwiftOCA",
    dependencies: [
      "AsyncExtensions",
      "AnyCodable",
      "SocketAddress",
      .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
      .product(name: "SystemPackage", package: "swift-system"),
      .product(name: "Logging", package: "swift-log"),
      .product(name: "Atomics", package: "swift-atomics"),
    ] + PlatformTargetDependencies,
    swiftSettings: [
      .enableExperimentalFeature("StrictConcurrency"),
    ]
  ),
  .target(
    name: "SwiftOCADevice",
    dependencies: [
      "SwiftOCA",
      .product(name: "Logging", package: "swift-log"),
      .product(name: "Gzip", package: "GzipSwift"),
    ] + PlatformTargetDependencies,
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
  .executableTarget(
    name: "OCAEventBenchmark",
    dependencies: [
      "SwiftOCA",
    ],
    path: "Examples/OCAEventBenchmark",
    swiftSettings: [
      .unsafeFlags(ASANSwiftFlags),
    ],
    linkerSettings: [] + ASANLinkerSettings

  ),

  .testTarget(
    name: "SwiftOCATests",
    dependencies: [
      .target(name: "SwiftOCADevice"),
    ],
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
]

let package = Package(
  name: "SwiftOCA",
  platforms: [
    .macOS(.v14),
    .iOS(.v17),
  ],
  products: CommonProducts + PlatformProducts,
  dependencies: CommonPackageDependencies + PlatformPackageDependencies,
  targets: CommonTargets + PlatformTargets,
  swiftLanguageVersions: [.v5]
)
