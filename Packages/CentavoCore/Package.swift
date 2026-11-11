// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CentavoCore",
    // The app runs from iOS 26 (owner, 2026-11-11). This tools version has no `.v26`, so it is
    // written out; macOS stays for `swift test` on the Mac.
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [
        .library(name: "CentavoCore", targets: ["CentavoCore"]),
    ],
    targets: [
        .target(name: "CentavoCore"),
        .testTarget(name: "CentavoCoreTests", dependencies: ["CentavoCore"]),
    ]
)
