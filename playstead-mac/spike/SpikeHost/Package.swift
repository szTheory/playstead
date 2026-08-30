// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpikeHost",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SpikeHost",
            path: "Sources/SpikeHost"
        )
    ]
)
