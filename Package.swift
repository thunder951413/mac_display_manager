// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LumaFlow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LumaFlow", targets: ["LumaFlow"])
    ],
    targets: [
        .executableTarget(
            name: "LumaFlow",
            path: "Sources/LumaFlow",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(
            name: "LumaFlowTests",
            dependencies: ["LumaFlow"],
            path: "Tests/LumaFlowTests"
        )
    ]
)
