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
            path: "Sources/StashNative",
            publicHeadersPath: "include",
            resources: [
                .copy("PrivacyInfo.xcprivacy")
            ]
        ),
        .testTarget(
            name: "StashNativeTests",
            dependencies: ["StashNative"],
            path: "Tests/StashNativeTests"
        ),
    ]
)
