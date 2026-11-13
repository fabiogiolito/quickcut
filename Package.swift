// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "QuickCut",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "QuickCut",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            // Only Release builds (./build.sh --release) check for updates, so development copies never do.
            swiftSettings: [.define("UPDATER", .when(configuration: .release))],
            // Sparkle.framework is embedded in Contents/Frameworks by build.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "QuickCutTests", dependencies: ["QuickCut"]),
    ],
    swiftLanguageModes: [.v5]
)
