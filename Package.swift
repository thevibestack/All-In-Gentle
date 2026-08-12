// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "All-In-Gentle",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AllInGentleKit", targets: ["AllInGentleKit"]),
        .executable(name: "AllInGentle", targets: ["AllInGentle"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AllInGentleKit",
            path: "Sources/AllInGentle"
        ),
        .executableTarget(
            name: "AllInGentle",
            dependencies: ["AllInGentleKit"],
            path: "Sources/AllInGentleApp"
        ),
        .testTarget(
            name: "ModelsTests",
            dependencies: ["AllInGentleKit"],
            path: "Tests/ModelsTests"
        ),
        .testTarget(
            name: "ClientTests",
            dependencies: ["AllInGentleKit"],
            path: "Tests/ClientTests"
        ),
        .testTarget(
            name: "LLMServiceTests",
            dependencies: ["AllInGentleKit"],
            path: "Tests/LLMServiceTests",
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "ProjectsWikiTests",
            dependencies: ["AllInGentleKit"],
            path: "Tests/ProjectsWikiTests"
        ),
    ]
)
