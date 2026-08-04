// swift-tools-version: 6.0
import Foundation
import PackageDescription

// swift-testing ships inside the Xcode toolchain, but not inside the bare
// Command Line Tools. Set SHAMAN_TESTING_PACKAGE=1 to pull it in as a package
// instead, so `swift test` works on a machine without Xcode installed:
//
//     SHAMAN_TESTING_PACKAGE=1 swift test
//
// With Xcode present, leave it unset — the toolchain's own Testing module is
// used and this dependency would collide with it.
let usesTestingPackage = ProcessInfo.processInfo.environment["SHAMAN_TESTING_PACKAGE"] == "1"

let package = Package(
    name: "ShamanCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ShamanCore", targets: ["ShamanCore"])
    ],
    dependencies: usesTestingPackage
        ? [.package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.4")]
        : [],
    targets: [
        .target(
            name: "ShamanCore",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ShamanCoreTests",
            dependencies: usesTestingPackage
                ? ["ShamanCore", .product(name: "Testing", package: "swift-testing")]
                : ["ShamanCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
