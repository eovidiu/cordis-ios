// swift-tools-version: 6.0
import PackageDescription

/// Engine, plugins and observable store of the CordisShowcase app. Kept in a
/// package so the showcase's behaviour is tested with `swift test` on macOS;
/// the iOS app target only adds SwiftUI views.
let package = Package(
  name: "ShowcaseKit",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "ShowcaseKit", targets: ["ShowcaseKit"]),
  ],
  dependencies: [
    .package(name: "cordis-ios", path: "../../.."),
  ],
  targets: [
    .target(name: "ShowcaseKit", dependencies: [.product(name: "Cordis", package: "cordis-ios")]),
    .testTarget(name: "ShowcaseKitTests", dependencies: ["ShowcaseKit"]),
  ],
  swiftLanguageModes: [.v6]
)
