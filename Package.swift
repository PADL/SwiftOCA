// swift-tools-version:6.1
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

var PlatformPackageDependencies: [Package.Dependency] = []
var PlatformTargetDependencies: [Target.Dependency] = []
// Linux-only OpenSSL + IORing deps for SwiftOCASecure / SwiftOCASecureDevice.
// Populated inside #if os(Linux) below; empty on Apple platforms, where these
// packages are not declared as package dependencies (the secure targets are
// compiled with the Linux OpenSSL/IORing code paths #if'd out).
var SecureLinuxTargetDependencies: [Target.Dependency] = []
// Opt-in SwiftNIO + NIOSSL deps for the cross-platform NIO TLS backend in
// SwiftOCASecure / SwiftOCASecureDevice. Gated by the `SwiftNIOBackend` trait
// which is NOT in the default set; default builds do not fetch swift-nio.
let SecureNIOTargetDependencies: [Target.Dependency] = [
  .product(
    name: "NIOCore",
    package: "swift-nio",
    condition: .when(traits: ["SwiftNIOBackend"])
  ),
  .product(
    name: "NIOPosix",
    package: "swift-nio",
    condition: .when(traits: ["SwiftNIOBackend"])
  ),
  .product(
    name: "NIOTLS",
    package: "swift-nio",
    condition: .when(traits: ["SwiftNIOBackend"])
  ),
  .product(
    name: "NIOSSL",
    package: "swift-nio-ssl",
    condition: .when(traits: ["SwiftNIOBackend"])
  ),
  // For SHA-256 peer-cert fingerprints. On Apple, `Crypto` re-exports
  // `CryptoKit`; on Linux it ships its own implementation.
  .product(
    name: "Crypto",
    package: "swift-crypto",
    condition: .when(traits: ["SwiftNIOBackend"])
  ),
]
let PlatformProducts: [Product]
let PlatformTargets: [Target]

PlatformPackageDependencies += [
  .package(url: "https://github.com/swhitty/FlyingFox", from: "0.26.2"),
]

PlatformTargetDependencies += [
  .product(
    name: "FlyingSocks",
    package: "FlyingFox"
  ),
  .product(
    name: "FlyingFox",
    package: "FlyingFox",
    condition: .when(traits: ["NonEmbeddedBuild"])
  ),
]

#if os(Linux)
PlatformPackageDependencies += [.package(url: "https://github.com/PADL/IORingSwift", from: "1.0.0")]

PlatformTargetDependencies += [
  .target(
    name: "dnssd",
    condition: .when(platforms: [.linux])
  ),
  .target(
    name: "COpenSSL",
    condition: .when(platforms: [.linux], traits: ["NonEmbeddedBuild"])
  ),
  .product(
    name: "IORing",
    package: "IORingSwift",
    condition: .when(platforms: [.linux], traits: ["NonEmbeddedBuild"])
  ),
  .product(
    name: "IORingUtils",
    package: "IORingSwift",
    condition: .when(platforms: [.linux], traits: ["NonEmbeddedBuild"])
  ),
  .product(
    name: "IORingFoundation",
    package: "IORingSwift",
    condition: .when(platforms: [.linux], traits: ["NonEmbeddedBuild"])
  ),
  // FlyingFox/FlyingSocks are common to all platforms and added at the top.
]

SecureLinuxTargetDependencies = [
  .target(
    name: "COpenSSL",
    condition: .when(platforms: [.linux], traits: ["NonEmbeddedBuild"])
  ),
  .product(
    name: "IORing",
    package: "IORingSwift",
    condition: .when(platforms: [.linux], traits: ["NonEmbeddedBuild"])
  ),
  .product(
    name: "IORingUtils",
    package: "IORingSwift",
    condition: .when(platforms: [.linux], traits: ["NonEmbeddedBuild"])
  ),
]

PlatformProducts = []
PlatformTargets = []
#elseif os(macOS) || os(iOS)
PlatformPackageDependencies += [
  .package(
    url: "https://github.com/spacenation/swiftui-sliders",
    from: "2.1.0"
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
// Other platforms (e.g. Windows): keep the common FlyingFox/FlyingSocks
// baseline appended above — FlyingSocks is the socket transport, since
// CoreFoundation/Network.framework is not available here. No extra
// platform packages, products, or targets.
PlatformProducts = []
PlatformTargets = []
#endif

let CommonPackageDependencies: [Package.Dependency] = [
  .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
  .package(url: "https://github.com/apple/swift-log", from: "1.6.2"),
  .package(url: "https://github.com/apple/swift-system", from: "1.6.4"),
  .package(url: "https://github.com/apple/swift-atomics", from: "1.2.0"),
  .package(url: "https://github.com/PADL/SocketAddress", from: "0.5.1"),
  .package(url: "https://github.com/lhoward/AsyncExtensions", from: "0.9.0"),
  .package(url: "https://github.com/Flight-School/AnyCodable", from: "0.6.7"),
  .package(url: "https://github.com/1024jp/GzipSwift", from: "6.1.0"),
  .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.16.0"),
  .package(url: "https://github.com/apple/swift-nio", from: "2.65.0"),
  .package(url: "https://github.com/apple/swift-nio-ssl", from: "2.27.0"),
  .package(url: "https://github.com/apple/swift-crypto", from: "3.6.0"),
]

let CommonProducts: [Product] = [
  .library(
    name: "SwiftOCA",
    targets: ["SwiftOCA"]
  ),
  .library(
    name: "SwiftOCASecure",
    targets: ["SwiftOCASecure"]
  ),
  .library(
    name: "SwiftOCADevice",
    targets: ["SwiftOCADevice"]
  ),
  .library(
    name: "SwiftOCASecureDevice",
    targets: ["SwiftOCASecureDevice"]
  ),
]

let CommonTargets: [Target] = [
  .systemLibrary(
    name: "dnssd",
    providers: [.apt(["libavahi-compat-libdnssd-dev"])]
  ),
  .systemLibrary(
    name: "COpenSSL",
    pkgConfig: "openssl",
    providers: [
      .apt(["libssl-dev"]),
      .yum(["openssl-devel"]),
    ]
  ),
  .target(
    name: "SwiftOCA",
    dependencies: [
      "AsyncExtensions",
      .product(
        name: "AnyCodable",
        package: "AnyCodable",
        condition: .when(traits: ["NonEmbeddedBuild"])
      ),
      "SocketAddress",
      .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
      .product(name: "SystemPackage", package: "swift-system"),
      .product(name: "Logging", package: "swift-log"),
      .product(name: "Atomics", package: "swift-atomics"),
    ] + PlatformTargetDependencies,
    swiftSettings: [
      .enableExperimentalFeature("StrictConcurrency"),
      .enableExperimentalFeature("Extern"),
    ]
  ),
  .target(
    name: "SwiftOCASecure",
    dependencies: [
      "SwiftOCA",
      "SocketAddress",
      .product(name: "Logging", package: "swift-log"),
    ] + SecureLinuxTargetDependencies + SecureNIOTargetDependencies,
    swiftSettings: [
      .enableExperimentalFeature("StrictConcurrency"),
    ]
  ),
  .target(
    name: "SwiftOCADevice",
    dependencies: [
      "SwiftOCA",
      .product(name: "Logging", package: "swift-log"),
      .product(
        name: "Gzip",
        package: "GzipSwift",
        // GzipSwift relies on a system `zlib` module, which is unavailable on
        // Windows. Dataset compression in this target is already guarded by
        // `#if canImport(Gzip)`, so it degrades gracefully when absent.
        condition: .when(
          platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .linux, .android]
        )
      ),
      .product(
        name: "SQLite",
        package: "SQLite.swift",
        condition: .when(
          platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .linux],
          traits: ["NonEmbeddedBuild"]
        )
      )
    ] + PlatformTargetDependencies,
    swiftSettings: [
      .enableExperimentalFeature("StrictConcurrency"),
    ]
  ),
  .target(
    name: "SwiftOCASecureDevice",
    dependencies: [
      "SwiftOCA",
      "SwiftOCASecure",
      "SwiftOCADevice",
      "SocketAddress",
      .product(name: "Logging", package: "swift-log"),
      .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
      "AsyncExtensions",
    ] + SecureLinuxTargetDependencies + SecureNIOTargetDependencies,
    swiftSettings: [
      .enableExperimentalFeature("StrictConcurrency"),
    ]
  ),
  .executableTarget(
    name: "OCADevice",
    dependencies: [
      "SwiftOCADevice",
      .target(name: "SwiftOCASecure", condition: .when(traits: ["NonEmbeddedBuild"])),
      .target(name: "SwiftOCASecureDevice", condition: .when(traits: ["NonEmbeddedBuild"])),
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
  .executableTarget(
    name: "OCABrokerTest",
    dependencies: [
      "SwiftOCA",
    ],
    path: "Examples/OCABrokerTest",
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
      .target(name: "SwiftOCASecure", condition: .when(traits: ["NonEmbeddedBuild"])),
      .target(name: "SwiftOCASecureDevice", condition: .when(traits: ["NonEmbeddedBuild"])),
      // Apple-only test files (WebSocketConnectionTests, AppleTLSPolicyRegressionTests)
      // import these directly. SwiftPM doesn't re-export a target's deps, so
      // we have to declare them on the test target too.
      .product(
        name: "FlyingSocks",
        package: "FlyingFox",
        condition: .when(platforms: [.macOS, .iOS])
      ),
      .product(
        name: "FlyingFox",
        package: "FlyingFox",
        condition: .when(platforms: [.macOS, .iOS], traits: ["NonEmbeddedBuild"])
      ),
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
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: CommonProducts + PlatformProducts,
  traits: [
    .default(enabledTraits: ["NonEmbeddedBuild"]),
    .init(name: "NonEmbeddedBuild", description: "Default build footprint"),
    .init(
      name: "SwiftNIOBackend",
      description: "Opt-in SwiftNIO + NIOSSL TLS backend for SwiftOCASecure[Device] (TCP, cert credentials only)"
    ),
  ],
  dependencies: CommonPackageDependencies + PlatformPackageDependencies,
  targets: CommonTargets + PlatformTargets
)
