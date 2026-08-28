// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VPSControl",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VPSControl", targets: ["VPSControl"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/migueldeicaza/SwiftTerm.git",
            exact: "1.15.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "VPSControl",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/VPSControl",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "VPSControlTests",
            dependencies: ["VPSControl"],
            path: "Tests/VPSControlTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
