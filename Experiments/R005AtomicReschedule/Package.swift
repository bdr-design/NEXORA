// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NexoraAtomicRescheduleMicro",
    platforms: [.macOS(.v15)],
    products: [.library(name: "AtomicRescheduleMicro", targets: ["AtomicRescheduleMicro"])],
    targets: [
        .target(name: "AtomicRescheduleMicro"),
        .testTarget(name: "AtomicRescheduleMicroTests", dependencies: ["AtomicRescheduleMicro"])
    ],
    swiftLanguageModes: [.v6]
)
