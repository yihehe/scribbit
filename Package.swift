// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Scribbit",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Scribbit", targets: ["Scribbit"])],
    targets: [
        .target(name: "ScribbitCore"),
        .executableTarget(name: "Scribbit", dependencies: ["ScribbitCore"],
                          resources: [.process("Resources")]),
        .testTarget(name: "ScribbitCoreTests", dependencies: ["ScribbitCore"]),
        .testTarget(name: "ScribbitAppTests", dependencies: ["Scribbit", "ScribbitCore"])
    ],
    swiftLanguageModes: [.v5]
)
