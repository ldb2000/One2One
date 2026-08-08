// swift-tools-version: 5.9
import PackageDescription

// Prototype jetable — sonde du risque central de la réécriture de l'éditeur.
// Paquet autonome : aucune dépendance, aucun lien avec le paquet racine.
// Se supprime entièrement par `rm -rf Prototypes/`.
let package = Package(
    name: "BlockEditorProbe",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "block-editor-probe", targets: ["block-editor-probe"])
    ],
    targets: [
        .target(name: "ProbeCore"),
        .executableTarget(
            name: "block-editor-probe",
            dependencies: ["ProbeCore"]
        ),
        .testTarget(
            name: "ProbeCoreTests",
            dependencies: ["ProbeCore"]
        )
    ]
)
