// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "WuhuUI",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "WuhuUI", targets: ["WuhuUI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.7.3"),
  ],
  targets: [
    .target(
      name: "WuhuUI",
      dependencies: [
        .product(name: "Markdown", package: "swift-markdown"),
      ],
      path: "Sources/WuhuUI"
    ),
    .executableTarget(
      name: "WuhuUIDemo",
      dependencies: ["WuhuUI"],
      path: "Demo"
    ),
    .testTarget(
      name: "WuhuUITests",
      dependencies: ["WuhuUI"],
      path: "Tests"
    ),
  ]
)
