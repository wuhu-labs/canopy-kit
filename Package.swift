// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "WuhuUI",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "WuhuUI", targets: ["WuhuUI"]),
  ],
  targets: [
    .target(
      name: "WuhuUI",
      path: "Sources/WuhuUI"
    ),
    .executableTarget(
      name: "WuhuUIDemo",
      dependencies: ["WuhuUI"],
      path: "Demo"
    ),
  ]
)
