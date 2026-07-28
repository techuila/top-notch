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
            dependencies: ["NotchCore", "NotchShell", "PaneMusic", "PaneDrop", "PaneNotes", "PaneFocus"],
            swiftSettings: swiftSettings
        ),
    ]
)
