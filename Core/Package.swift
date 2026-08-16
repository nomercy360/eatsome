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
    name: "EatsomeCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "EatsomeCore", targets: ["EatsomeCore"])
    ],
    dependencies: usesTestingPackage
        ? [.package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.2.4")]
        : [],
    targets: [
        // Framework-free: no UIKit, AVFoundation, HealthKit. That is what
        // makes the log, the arithmetic and the wire types testable on any
        // machine with a Swift toolchain.
        .target(
            name: "EatsomeCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "EatsomeCoreTests",
            dependencies: usesTestingPackage
                ? ["EatsomeCore", .product(name: "Testing", package: "swift-testing")]
                : ["EatsomeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
