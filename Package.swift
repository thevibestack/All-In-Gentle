// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "All-In-Gentle",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AllInGentleKit", targets: ["AllInGentleKit"]),
        .executable(name: "AllInGentle", targets: ["AllInGentle"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0")
    ],
    targets: [
        .target(
            name: "AllInGentleKit",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "Sources/AllInGentle",
            resources: [.process("../../Resources")]
        ),
        .executableTarget(
            name: "AllInGentle",
            dependencies: ["AllInGentleKit"],
            path: "Sources/AllInGentleApp"
        ),
        .target(
            name: "AllInGentleTestSupport",
            dependencies: ["AllInGentleKit"],
            path: "Tests/Support"
        ),
        .testTarget(
            name: "ModelsTests",
            dependencies: ["AllInGentleKit"],
            path: "Tests/ModelsTests"
        ),
        .testTarget(
            name: "ClientTests",
            dependencies: ["AllInGentleKit", "AllInGentleTestSupport"],
            path: "Tests/ClientTests"
        ),
        .testTarget(
            name: "LLMServiceTests",
            dependencies: ["AllInGentleKit", "AllInGentleTestSupport"],
            path: "Tests/LLMServiceTests",
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "ProjectsWikiTests",
            dependencies: ["AllInGentleKit", "AllInGentleTestSupport"],
            path: "Tests/ProjectsWikiTests"
        ),
        .testTarget(
            name: "ServicesTokensTests",
            dependencies: ["AllInGentleKit", "AllInGentleTestSupport"],
            path: "Tests/ServicesTokensTests"
        ),
        .testTarget(
            name: "ChatSessionCleanerTests",
            dependencies: ["AllInGentleKit"],
            path: "Tests/ChatSessionCleanerTests"
        ),
        .testTarget(
            name: "IntegrationTests",
            dependencies: ["AllInGentleKit", "AllInGentleTestSupport"],
            path: "Tests/IntegrationTests"
        ),
        .testTarget(
            name: "SmokeTests",
            dependencies: ["AllInGentleKit", "AllInGentleTestSupport"],
            path: "Tests/SmokeTests"
        ),
        .testTarget(
            name: "DesignSystemTests",
            dependencies: ["AllInGentleKit"],
            path: "Tests/DesignSystemTests"
        ),
        .testTarget(
            name: "SettingsTests",
            dependencies: ["AllInGentleKit", "AllInGentleTestSupport"],
            path: "Tests/SettingsTests"
        ),
    ]
)
