// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SiriGlass",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "SiriGlass", targets: ["SiriGlass"]),
    ],
    targets: [
        .target(
            name: "SiriGlass",
            resources: [.process("Shaders")]
        ),
        .testTarget(name: "SiriGlassTests", dependencies: ["SiriGlass"]),
    ]
)
