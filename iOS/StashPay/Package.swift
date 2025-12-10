// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "StashPay",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "StashPay",
            targets: ["StashPay"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "StashPay",
            dependencies: [],
            path: "Sources/StashPay",
            publicHeadersPath: "include"
        ),
    ]
)
