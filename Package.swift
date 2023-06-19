// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftOCA",
    platforms: [
        // specify each minimum deployment requirement,
        //otherwise the platform default minimum is used.
       .macOS(.v10_15),
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "SwiftOCA",
            targets: ["SwiftOCA"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "0.1.0"),
        .package(url: "https://github.com/PureSwift/Socket", .branch("main")),
        .package(url: "https://github.com/sideeffect-io/AsyncExtensions.git", from: "0.5.2"),
        .package(url: "https://github.com/PADL/swift-binary-coder", .branch("inferno")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "SwiftOCA",
            dependencies: [
		"Socket",
		"AsyncExtensions",
		.product(name: "BinaryCoder", package: "swift-binary-coder"),
		.product(name: "AsyncAlgorithms", package: "swift-async-algorithms")
	    ]),
    ],
    swiftLanguageVersions: [.v5]
)

