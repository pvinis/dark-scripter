// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "dark-scripter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "dark-scripter", path: "Sources")
    ]
)
