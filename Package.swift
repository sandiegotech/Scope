// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Disko",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Disko", targets: ["Disko"])
    ],
    targets: [
        .executableTarget(
            name: "Disko",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Metal")
            ]
        )
    ]
)
