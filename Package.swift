// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NEXORA",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "NEXORADiagnostics", targets: ["NEXORADiagnostics"]),
        .library(name: "NEXORAAppleDiagnostics", targets: ["NEXORAAppleDiagnostics"]),
        .library(name: "NEXORACore", targets: ["NEXORACore"]),
        .executable(name: "nexora-benchmark", targets: ["NEXORABenchmark"])
    ],
    targets: [
        .target(name: "NEXORADiagnostics"),
        .target(
            name: "NEXORAAppleDiagnostics",
            dependencies: ["NEXORADiagnostics"]
        ),
        .target(
            name: "NEXORACore",
            dependencies: ["NEXORADiagnostics"]
        ),
        .executableTarget(
            name: "NEXORABenchmark",
            dependencies: ["NEXORACore", "NEXORADiagnostics"]
        ),
        .testTarget(
            name: "NEXORACoreTests",
            dependencies: ["NEXORACore", "NEXORADiagnostics"]
        ),
        .testTarget(
            name: "NEXORAPerformanceTests",
            dependencies: ["NEXORACore", "NEXORADiagnostics"]
        )
    ],
    swiftLanguageModes: [.v6]
)
