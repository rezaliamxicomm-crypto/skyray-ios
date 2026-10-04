// swift-tools-version:5.9
import PackageDescription

// LibXray.xcframework is not in git: scripts/fetch-libxray.sh downloads the release pinned in
// Vendor/libxray.lock (sha256 verified) into Packages/SkyRayXray/Vendor/ before any build. That release is this
// repository's own build of XTLS/libXray with the subscription fetch compiled in (.github/workflows/libxray.yml).
let package = Package(
    name: "SkyRayXray",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "SkyRayXray", targets: ["SkyRayXray"])],
    targets: [
        .binaryTarget(name: "LibXray", path: "Vendor/LibXray.xcframework"),
        .target(
            name: "SkyRayXray",
            dependencies: ["LibXray"],
            linkerSettings: [
                .linkedLibrary("resolv"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security")
            ]
        )
    ]
)
