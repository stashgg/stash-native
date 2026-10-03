// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "StashNative",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "StashNative",
            targets: ["StashNative"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "StashNative",
            dependencies: [],
            path: "iOS/StashNative/Sources/StashNative",
            publicHeadersPath: "include"
        ),
        .target(
            name: "RegressionSupport",
            dependencies: ["StashNative"],
            path: "iOS/StashNative/Tests/RegressionSupport",
            publicHeadersPath: "include"
        ),
        .testTarget(
            name: "StashNativeTests",
            dependencies: ["StashNative", "RegressionSupport"],
            path: "iOS/StashNative/Tests/StashNativeTests"
        ),
    ]
)
