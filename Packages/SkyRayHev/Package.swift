// swift-tools-version:5.9
import PackageDescription

// HevSocks5Tunnel.xcframework is not in git: scripts/fetch-hev.sh builds the release pinned in Vendor/hev.lock
// (sha256 verified) into Packages/SkyRayHev/Vendor/ before any build.
let package = Package(
    name: "SkyRayHev",
    platforms: [.iOS(.v15)],
    products: [.library(name: "SkyRayHev", targets: ["SkyRayHev"])],
    targets: [
        .binaryTarget(name: "HevSocks5Tunnel", path: "Vendor/HevSocks5Tunnel.xcframework"),
        .target(name: "SkyRayHev", dependencies: ["HevSocks5Tunnel"])
    ]
)
