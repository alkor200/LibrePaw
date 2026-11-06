// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TraccarKit",
    platforms: [
        .iOS(.v17),
        // macOS is only declared so `swift test` can run on the host Mac;
        // the app itself targets iOS exclusively (see ADR-0003).
        .macOS(.v13)
    ],
    products: [
        .library(name: "TraccarKit", targets: ["TraccarKit"])
    ],
    targets: [
        .target(name: "TraccarKit"),
        .testTarget(name: "TraccarKitTests", dependencies: ["TraccarKit"])
    ],
    swiftLanguageModes: [.v6]
)
