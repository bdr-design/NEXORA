// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NEXORA",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "NexoraIdentity", targets: ["NexoraIdentity"]),
        .library(name: "NexoraObservability", targets: ["NexoraObservability"]),
        .library(name: "NexoraAviation", targets: ["NexoraAviation"]),
        .executable(name: "nexora-check", targets: ["NexoraCheck"]),
        .executable(name: "nexora-aircraft-check", targets: ["NexoraAviationCheck"])
    ],
    targets: [
        .target(name: "NexoraIdentity"),
        .target(name: "NexoraObservability"),
        .target(name: "NexoraAviation", dependencies: ["NexoraIdentity"]),
        .executableTarget(name: "NexoraCheck", dependencies: ["NexoraIdentity", "NexoraObservability"]),
        .executableTarget(name: "NexoraAviationCheck", dependencies: ["NexoraAviation", "NexoraIdentity"]),
        .testTarget(name: "NexoraFoundationTests", dependencies: ["NexoraIdentity", "NexoraObservability"]),
        .testTarget(name: "NexoraAviationTests", dependencies: ["NexoraAviation", "NexoraIdentity", "NexoraObservability"])
    ],
    swiftLanguageModes: [.v6]
)
