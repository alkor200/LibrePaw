// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScentrailKit",
    platforms: [
        .iOS(.v17),
        // macOS is only declared so `swift test` can run on the host Mac;
        // the app itself targets iOS exclusively (see ADR-0003).
        .macOS(.v13)
    ],
    products: [
        .library(name: "ScentrailKit", targets: ["ScentrailKit"])
    ],
    dependencies: [
        .package(path: "../TraccarKit")
    ],
    targets: [
        .target(name: "ScentrailKit", dependencies: ["TraccarKit"]),
        .testTarget(name: "ScentrailKitTests", dependencies: ["ScentrailKit"])
    ],
    swiftLanguageModes: [.v6]
)
