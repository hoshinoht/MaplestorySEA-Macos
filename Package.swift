// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MapleSEAInstaller",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MapleSEAInstaller",
            path: "Sources/MapleSEAInstaller"
        )
    ]
)
