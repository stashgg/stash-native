// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "StashNative",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "StashNative",
            targets: ["StashNative"]),
        // Optional QR scanner. Hosts that never scan omit it and ship no camera code.
        .library(
            name: "StashNativeCodeLink",
            targets: ["StashNativeCodeLink"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "StashNative",
            dependencies: [],
            path: "Sources/StashNative",
            publicHeadersPath: "include"
        ),
        .target(
            name: "StashNativeCodeLink",
            dependencies: ["StashNative"],
            path: "Sources/StashNativeCodeLink",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("AVFoundation")]
        ),
        .target(
            name: "RegressionSupport",
            dependencies: ["StashNative", "StashNativeCodeLink"],
            path: "Tests/RegressionSupport",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "StashNativeTests",
            dependencies: ["StashNative", "StashNativeCodeLink", "RegressionSupport"],
            path: "Tests/StashNativeTests"
        ),
    ]
)
