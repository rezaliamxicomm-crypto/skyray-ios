// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SkyRayCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "SkyRayCore", targets: ["SkyRayCore"])],
    targets: [
        .target(name: "SkyRayCore"),
        .testTarget(name: "SkyRayCoreTests", dependencies: ["SkyRayCore"])
    ]
)
