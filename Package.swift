// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OneToOne",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OneToOne", targets: ["OneToOne"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "OneToOne",
            dependencies: [],
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
