// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "TopNotch",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "TopNotch", targets: ["TopNotch"]),
    ],
    dependencies: [
        // Autoupdater. Ships as a prebuilt framework; bundle.sh embeds it and
        // release.sh signs its nested pieces for notarization.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.5"),
    ],
    targets: [
        // Contracts, design tokens and motion. Owned by the orchestrator.
        // Feature modules read from it and never modify it.
        .target(name: "NotchCore", swiftSettings: swiftSettings),

        // The window, the panel, the idle bar, the pane host.
        .target(name: "NotchShell", dependencies: ["NotchCore"], swiftSettings: swiftSettings),

        // One module per pane. Each is owned by exactly one agent.
        .target(name: "PaneMusic", dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "PaneDrop",  dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "PaneNotes", dependencies: ["NotchCore"], swiftSettings: swiftSettings),
        .target(name: "PaneFocus", dependencies: ["NotchCore"], swiftSettings: swiftSettings),

        .executableTarget(
            name: "TopNotch",
            dependencies: [
                "NotchCore", "NotchShell", "PaneMusic", "PaneDrop", "PaneNotes", "PaneFocus",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: swiftSettings,
            linkerSettings: [
                // The bundled app carries Sparkle.framework in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),

        // One test target per module that has anything worth testing. Both use `@testable`
        // rather than widening a module's public surface to suit its tests.
        .testTarget(
            name: "PaneNotesTests",
            dependencies: ["PaneNotes"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "PaneFocusTests",
            dependencies: ["PaneFocus"],
            swiftSettings: swiftSettings
        ),
    ]
)
