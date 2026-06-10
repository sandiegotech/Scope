// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Scope",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Scope", targets: ["Scope"])
    ],
    targets: [
        .executableTarget(
            name: "Scope",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Metal")
            ]
        )
    ]
)
