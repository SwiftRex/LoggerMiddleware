// swift-tools-version:5.1
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
        .package(url: "https://github.com/SwiftRex/SwiftRex.git", from: "0.7.0")
    ],
    targets: [
        .target(name: "LoggerMiddleware", dependencies: ["CombineRex"]),
        .testTarget(name: "LoggerMiddlewareTests", dependencies: ["LoggerMiddleware"])
    ]
)
