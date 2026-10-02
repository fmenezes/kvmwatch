// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "kvmwatch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "kvmwatch",
            path: "Sources/kvmwatch"
        )
    ]
)
