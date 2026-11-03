// swift-tools-version: 6.0
// ABOUTME: Defines the shared Camera Bar models and file storage package.
// ABOUTME: Runs core tests without app or media playback dependencies.
import PackageDescription

let package = Package(
  name: "CameraBarCore",
  platforms: [.macOS(.v14)],
  products: [.library(name: "CameraBarCore", targets: ["CameraBarCore"])],
  targets: [
    .target(name: "CameraBarCore"),
    .testTarget(name: "CameraBarCoreTests", dependencies: ["CameraBarCore"]),
  ]
)
