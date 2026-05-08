// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "macos-clipboard-manager",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "ClipboardCore", targets: ["ClipboardCore"]),
    .library(name: "ClipboardPlatform", targets: ["ClipboardPlatform"]),
    .executable(name: "ClipboardApp", targets: ["ClipboardApp"]),
    .executable(name: "ClipboardManualProbe", targets: ["ClipboardManualProbe"])
  ],
  targets: [
    .target(
      name: "ClipboardCore",
      dependencies: [],
      path: "Sources/ClipboardCore"
    ),
    .target(
      name: "ClipboardPlatform",
      dependencies: ["ClipboardCore"],
      path: "Sources/ClipboardPlatform"
    ),
    .executableTarget(
      name: "ClipboardApp",
      dependencies: ["ClipboardCore", "ClipboardPlatform"],
      path: "Sources/ClipboardApp"
    ),
    .executableTarget(
      name: "ClipboardManualProbe",
      dependencies: ["ClipboardCore", "ClipboardPlatform"],
      path: "Sources/ClipboardManualProbe"
    ),
    .testTarget(
      name: "ClipboardCoreTests",
      dependencies: ["ClipboardCore"],
      path: "Tests/ClipboardCoreTests"
    ),
    .testTarget(
      name: "ClipboardPlatformTests",
      dependencies: ["ClipboardCore", "ClipboardPlatform"],
      path: "Tests/ClipboardPlatformTests"
    ),
    .testTarget(
      name: "ClipboardAppTests",
      dependencies: ["ClipboardApp"],
      path: "Tests/ClipboardAppTests"
    )
  ]
)
