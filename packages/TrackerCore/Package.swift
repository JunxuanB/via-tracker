// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TrackerCore", platforms: [.iOS("26.0"), .macOS(.v15)],
  products: [.library(name: "TrackerCore", targets: ["TrackerCore"])],
  targets: [
    .target(name: "TrackerCore"),
    .testTarget(name: "TrackerCoreTests", dependencies: ["TrackerCore"]),
  ])
