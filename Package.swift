// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SetWorkspace",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "SetWorkspace", path: "Sources")
    ]
)
