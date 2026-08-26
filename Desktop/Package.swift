// swift-tools-version:5.5
// macOS host of Stash Native desktop payments. The package root is Desktop/ so the shared C++
// contract (Desktop/shared) and the ObjC++ host (Desktop/macOS) build as one SwiftPM package.
// swift build / swift test run natively on macOS. The distributable is the bundle produced by
// Desktop/macOS/build_bundle.sh; this package is for the tests and for SPM consumers of the
// AppKit facade.

import PackageDescription

let package = Package(
    name: "StashNativeDesktop",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "StashNativeDesktop",
            targets: ["StashNativeDesktop"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "StashDesktopShared",
            dependencies: [],
            path: "shared",
            exclude: ["tests", "test-pages", "CMakeLists.txt"],
            publicHeadersPath: ".",
            cxxSettings: [
                .headerSearchPath("../include"),
            ]
        ),
        .target(
            name: "StashNativeDesktop",
            dependencies: ["StashDesktopShared"],
            path: "macOS/Sources/StashNativeDesktop",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../../../include"),
                .headerSearchPath("../../../shared"),
                .define("STASH_NATIVE_DESKTOP_BUILDING"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        .testTarget(
            name: "StashNativeDesktopTests",
            dependencies: ["StashNativeDesktop", "StashDesktopShared"],
            path: "macOS/Tests/StashNativeDesktopTests",
            cxxSettings: [
                .headerSearchPath("../../../include"),
                .headerSearchPath("../../../shared"),
            ],
            linkerSettings: [
                .linkedFramework("XCTest"),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
