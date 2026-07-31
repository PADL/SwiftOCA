// swift-tools-version:6.2
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

// Android NSD support, gated on the `AndroidNSD` trait.
//
// NB: this is a trait rather than a manifest `#if os(Android)`, because a
// manifest's `#if os(...)` describes the *build host*, not the build target --
// Android is cross-compiled from macOS or Linux, so `os(Android)` is never true
// here. A trait also lets SwiftPM prune swift-java (and its swift-syntax
// dependency) from the resolved graph entirely when the trait is off, so
// non-Android consumers never fetch it.
//
// The jni.h include path is resolved eagerly because the manifest cannot read
// enabled traits; when JAVA_HOME is absent we simply omit the flags, as the
// target is unreachable with the trait disabled.
var AndroidNSDSwiftSettings: [SwiftSetting] = []

if let javaHome = ProcessInfo.processInfo.environment["JAVA_HOME"] {
  let javaIncludePath = ProcessInfo.processInfo
    .environment["JAVA_INCLUDE_PATH"] ?? "\(javaHome)/include"
  #if os(Linux)
  let javaPlatformIncludePath = "\(javaIncludePath)/linux"
  #else
  let javaPlatformIncludePath = "\(javaIncludePath)/darwin"
  #endif

  AndroidNSDSwiftSettings = [
    .unsafeFlags([
      "-I\(javaIncludePath)",
      "-I\(javaPlatformIncludePath)",
    ]),
  ]
}

// The target declaration itself has to be gated on something the manifest can
// evaluate, which a trait is not: `Target.PluginUsage.plugin(name:package:)`
// takes no condition, so the swift-java plugin usage below is unconditional. If
// the trait prunes swift-java from the resolved graph, that plugin product no
// longer exists and every non-Android build fails with "product
// 'JavaCompilerPlugin' ... not found in package 'swift-java'".
//
// So SWIFTOCA_ANDROID_NSD decides whether the target exists at all (the Android
// build sets it), while the AndroidNSD trait remains the switch consumers use
// to link it. Folding the two back into one is what splitting this target into
// its own package would buy -- see Documentation/AndroidNSD.md.
let AndroidNSDBuild = (ProcessInfo.processInfo.environment["SWIFTOCA_ANDROID_NSD"]
  .flatMap(Bool.init)) ?? false

var AndroidTargets: [Target] = []

if AndroidNSDBuild {
  AndroidTargets += [
    .target(
      name: "AndroidNetworkServiceDiscovery",
      dependencies: [
        .product(
          name: "SwiftJava",
          package: "swift-java",
          condition: .when(traits: ["AndroidNSD"])
        ),
      ],
      swiftSettings: AndroidNSDSwiftSettings,
      plugins: [
        .plugin(name: "JavaCompilerPlugin", package: "swift-java"),
        .plugin(name: "SwiftJavaPlugin", package: "swift-java"),
      ]
    ),
  ]

  PlatformPackageDependencies += [
    .package(url: "https://github.com/swiftlang/swift-java", branch: "main"),
  ]

  PlatformTargetDependencies += [
    .target(
      name: "AndroidNetworkServiceDiscovery",
      condition: .when(platforms: [.android], traits: ["AndroidNSD"])
    ),
  ]
}
// Linux-only OpenSSL + IORing deps for SwiftOCASecure / SwiftOCASecureDevice.
// Populated inside #if os(Linux) below; empty on Apple platforms, where these
// packages are not declared as package dependencies (the secure targets are
// compiled with the Linux OpenSSL/IORing code paths #if'd out).
var SecureLinuxTargetDependencies: [Target.Dependency] = []
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
  .package(url: "https://github.com/apple/swift-binary-parsing", from: "0.0.2"),
  .package(url: "https://github.com/apple/swift-log", from: "1.6.2"),
  .package(url: "https://github.com/apple/swift-system", from: "1.6.4"),
  .package(url: "https://github.com/apple/swift-atomics", from: "1.2.0"),
  .package(url: "https://github.com/PADL/SocketAddress", from: "0.5.1"),
  .package(url: "https://github.com/lhoward/AsyncExtensions", from: "0.9.0"),
  .package(url: "https://github.com/Flight-School/AnyCodable", from: "0.6.7"),
  .package(url: "https://github.com/1024jp/GzipSwift", from: "6.1.0"),
  .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.16.0"),
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
      .product(name: "BinaryParsing", package: "swift-binary-parsing"),
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
    ] + SecureLinuxTargetDependencies,
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
    ] + SecureLinuxTargetDependencies,
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
      name: "AndroidNSD",
      description: "Discover OCA devices via Android's NsdManager (requires swift-java)"
    ),
  ],
  dependencies: CommonPackageDependencies + PlatformPackageDependencies,
  targets: CommonTargets + PlatformTargets + AndroidTargets
)
