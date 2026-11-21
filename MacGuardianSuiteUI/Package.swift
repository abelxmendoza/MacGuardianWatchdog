// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacGuardianSuiteUI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacGuardianSuiteUI", targets: ["MacGuardianSuiteUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.1")
    ],
    targets: [
        .executableTarget(
            name: "MacGuardianSuiteUI",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/MacGuardianSuiteUI",
            resources: [
                .process("../../Resources")
            ]
        )
    ]
)
