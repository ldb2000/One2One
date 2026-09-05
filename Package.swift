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
        // Embeddings locaux et dépendances partagées avec la transcription.
        // Conserver la révision actuelle pendant le retrait du LLM intégré.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", branch: "main"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.3.0"),
        // Éditeur/rendu markdown natif macOS (TextKit 2). Cœur sans dépendance ;
        // highlighting/LaTeX = produits optionnels non embarqués. Apache 2.0.
        .package(url: "https://github.com/nodes-app/swift-markdown-engine", from: "0.1.0"),
        // Moteur de layout utilisé par la copie locale modifiable de
        // BeautifulMermaidSwift (MIT, voir Vendor/BeautifulMermaidSwift).
        .package(url: "https://github.com/lukilabs/elk-swift", from: "1.0.2"),
    ],
    targets: [
        .target(
            name: "BeautifulMermaid",
            dependencies: [
                .product(name: "ElkSwift", package: "elk-swift")
            ],
            path: "Vendor/BeautifulMermaidSwift/Sources"
        ),
        .executableTarget(
            name: "OneToOne",
            dependencies: [
                "BeautifulMermaid",
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "SpeechVAD", package: "speech-swift"),
                .product(name: "Markdown", package: "swift-markdown"),
                // Embeddings et runtime partagé avec les moteurs audio.
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "MarkdownEngine", package: "swift-markdown-engine"),
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
