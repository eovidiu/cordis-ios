// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
  name: "Cordis",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "Cordis", targets: ["Cordis"]),
    .executable(name: "cordis-demo", targets: ["CordisDemo"]),
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0"),
  ],
  targets: [
    .macro(name: "CordisMacros", dependencies: [
      .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
      .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
    ]),
    .target(name: "Cordis", dependencies: ["CordisMacros"]),
    .executableTarget(name: "CordisDemo", dependencies: ["Cordis"], resources: [.copy("entries.json")]),
    .testTarget(name: "CordisTests", dependencies: ["Cordis"]),
    .testTarget(name: "CordisMacrosTests", dependencies: [
      "CordisMacros",
      .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
    ]),
  ],
  swiftLanguageModes: [.v6]
)
