// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OneToOne",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "OneToOne", targets: ["OneToOne"])
    ],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", branch: "main"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.30.6"),
        .package(url: "https://github.com/soniqo/speech-swift", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "OneToOne",
            dependencies: [
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "SpeechVAD", package: "speech-swift"),
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "OneToOne",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "OneToOneTests",
            dependencies: ["OneToOne"],
            path: "Tests"
        )
    ]
)
