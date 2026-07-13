// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "llorcs",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "llorcs", targets: ["LlorcsApp"])
    ],
    targets: [
        .target(
            name: "LlorcsCore",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "LlorcsApp",
            dependencies: ["LlorcsCore"]
        ),
        .testTarget(
            name: "LlorcsCoreTests",
            dependencies: ["LlorcsCore"]
        )
    ]
)
