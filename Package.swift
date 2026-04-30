// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "macos-clipboard-manager",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "ClipboardCore", targets: ["ClipboardCore"]),
    .executable(name: "ClipboardApp", targets: ["ClipboardApp"])
  ],
  targets: [
    .target(
      name: "ClipboardCore",
      dependencies: [],
      path: "Sources/ClipboardCore"
    ),
    .executableTarget(
      name: "ClipboardApp",
      dependencies: ["ClipboardCore"],
      path: "Sources/ClipboardApp"
    ),
    .testTarget(
      name: "ClipboardCoreTests",
      dependencies: ["ClipboardCore"],
      path: "Tests/ClipboardCoreTests"
    )
  ]
)
