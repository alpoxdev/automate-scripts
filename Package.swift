// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AutomateScripts",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AutomateCore", targets: ["AutomateCore"]),
        .executable(name: "automate", targets: ["AutomateCLI"]),
        .executable(name: "AutomateMenuBarApp", targets: ["AutomateMenuBarApp"])
    ],
    targets: [
        .target(name: "AutomateCore"),
        .target(name: "PrivilegedExecutionShim"),
        .executableTarget(name: "AutomateCLI", dependencies: ["AutomateCore"]),
        .executableTarget(
            name: "AutomateMenuBarApp",
            dependencies: ["AutomateCore", "PrivilegedExecutionShim"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "AutomateCoreTests", dependencies: ["AutomateCore"]),
        .testTarget(name: "AutomateCLITests", dependencies: ["AutomateCore"])
    ]
)
