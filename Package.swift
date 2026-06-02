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
        // Génération LLM locale in-process (provider "Directe", ex. Gemma MLX).
        // mlx-swift-lm est déjà tiré transitivement par mlx-audio-swift ; on
        // l'expose en direct pour utiliser MLXLLM/MLXLMCommon. swift-huggingface
        // + swift-transformers fournissent le downloader Hub et le tokenizer.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "3.31.3"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.0"),
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
                // Provider "Directe" : LLM MLX in-process (Gemma).
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
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
