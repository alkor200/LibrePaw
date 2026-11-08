// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LibrePawKit",
    platforms: [
        .iOS(.v17),
        // macOS is only declared so `swift test` can run on the host Mac;
        // the app itself targets iOS exclusively (see ADR-0003).
        .macOS(.v13)
    ],
    products: [
        .library(name: "LibrePawKit", targets: ["LibrePawKit"])
    ],
    dependencies: [
        .package(path: "../TraccarKit")
    ],
    targets: [
        .target(name: "LibrePawKit", dependencies: ["TraccarKit"]),
        .testTarget(name: "LibrePawKitTests", dependencies: ["LibrePawKit", "TraccarKit"])
    ],
    swiftLanguageModes: [.v6]
)
