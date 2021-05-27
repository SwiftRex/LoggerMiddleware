// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LoggerMiddleware",
    platforms: [
        .iOS(.v13), .macOS(.v10_15), .tvOS(.v13), .watchOS(.v6)
    ],
    products: [
        .library(name: "LoggerMiddleware", targets: ["LoggerMiddleware"])
    ],
    dependencies: [
        .package(url: "https://github.com/SwiftRex/SwiftRex.git", .upToNextMajor(from: "0.8.2"))
    ],
    targets: [
        .target(
            name: "LoggerMiddleware",
            dependencies: [
                .product(name: "CombineRex", package: "SwiftRex")
            ]
//            Enable this for build performance warnings. Works only when building the Package, works not when building the workspace! Obey the comma.
//            , swiftSettings: [SwiftSetting.unsafeFlags(["-Xfrontend", "-warn-long-expression-type-checking=10", "-Xfrontend", "-warn-long-function-bodies=10"])]

        ),
        .testTarget(name: "LoggerMiddlewareTests", dependencies: ["LoggerMiddleware"])
    ]
)
