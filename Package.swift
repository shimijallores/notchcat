// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchCat",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NotchCat",
            path: "Sources/NotchCat"
        )
    ],
    swiftLanguageVersions: [.v5]
)
