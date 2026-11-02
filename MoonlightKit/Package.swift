// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MoonlightKit",
    platforms: [.tvOS(.v17), .iOS(.v17), .macOS(.v14)],
    products: [.library(name: "MoonlightKit", targets: ["MoonlightKit"])],
    targets: [
        .target(name: "MoonlightKit"),
        .testTarget(name: "MoonlightKitTests", dependencies: ["MoonlightKit"]),
    ]
)
