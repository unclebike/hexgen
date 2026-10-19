// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DialhexCore",
    platforms: [.iOS(.v17), .tvOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DialhexCore", targets: ["DialhexCore"]),
    ],
    targets: [
        .target(name: "DialhexCore"),
        .testTarget(name: "DialhexCoreTests", dependencies: ["DialhexCore"]),
    ]
)
