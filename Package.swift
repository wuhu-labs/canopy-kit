// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WuhuUI",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DocEngineDemo",
            path: "Demo"
        ),
    ]
)
