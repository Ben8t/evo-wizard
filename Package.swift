// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EvoWizard",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "EvoWizard",
            linkerSettings: [.linkedFramework("IOKit")]
        )
    ],
    swiftLanguageModes: [.v5]
)
