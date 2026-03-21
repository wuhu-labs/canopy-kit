// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CanopyKit",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "CanopyKit", targets: ["CanopyKit"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),
    .package(url: "https://github.com/pointfreeco/swift-identified-collections", from: "1.0.0"),
    .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.7.3"),
  ],
  targets: [
    .target(
      name: "CanopyKit",
      dependencies: [
        .product(name: "Collections", package: "swift-collections"),
        .product(name: "IdentifiedCollections", package: "swift-identified-collections"),
        .product(name: "Markdown", package: "swift-markdown"),
      ],
      path: "Sources/CanopyKit"
    ),
    .testTarget(
      name: "CanopyKitTests",
      dependencies: ["CanopyKit"],
      path: "Tests"
    ),
  ]
)
