// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "TrackerCore", defaultLocalization: "en", platforms: [.iOS("26.0"), .macOS(.v15)],
  products: [.library(name: "TrackerCore", targets: ["TrackerCore"])],
  targets: [
    .target(name: "TrackerCore", resources: [.process("Resources")]),
    .testTarget(name: "TrackerCoreTests", dependencies: ["TrackerCore"]),
  ])
