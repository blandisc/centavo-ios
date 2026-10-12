// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CentavoCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "CentavoCore", targets: ["CentavoCore"]),
    ],
    targets: [
        .target(name: "CentavoCore"),
        .testTarget(name: "CentavoCoreTests", dependencies: ["CentavoCore"]),
    ]
)
