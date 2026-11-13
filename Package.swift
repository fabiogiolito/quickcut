// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "QuickCut",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "QuickCut"),
        .testTarget(name: "QuickCutTests", dependencies: ["QuickCut"]),
    ],
    swiftLanguageModes: [.v5]
)
