// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NEXORA",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "NexoraIdentity", targets: ["NexoraIdentity"]),
        .library(name: "NexoraObservability", targets: ["NexoraObservability"]),
        .executable(name: "nexora-check", targets: ["NexoraCheck"])
    ],
    targets: [
        .target(name: "NexoraIdentity"),
        .target(name: "NexoraObservability"),
        .executableTarget(name: "NexoraCheck", dependencies: ["NexoraIdentity", "NexoraObservability"]),
        .testTarget(name: "NexoraFoundationTests", dependencies: ["NexoraIdentity", "NexoraObservability"])
    ],
    swiftLanguageModes: [.v6]
)
