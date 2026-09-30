// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "R005SwiftExperiment", platforms: [.macOS(.v15)],
    products: [.executable(name: "nxr-swift-probe", targets: ["SwiftProbe"])],
    dependencies: [.package(name: "NEXORA", path: "../..")],
    targets: [
        .target(name: "ProbePlatform", publicHeadersPath: "include",
                linkerSettings: [.linkedLibrary("crypto", .when(platforms: [.linux]))]),
        .executableTarget(name: "SwiftProbe", dependencies: ["ProbePlatform",
            .product(name: "NexoraSimulation", package: "NEXORA"),
            .product(name: "NexoraFinance", package: "NEXORA"),
            .product(name: "NexoraIdentity", package: "NEXORA")])
    ], swiftLanguageModes: [.v6])
