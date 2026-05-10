// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MahoImg",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MahoImg", targets: ["MahoImg"])
    ],
    targets: [
        .executableTarget(
            name: "MahoImg",
            path: "Sources/MahoImg"
        ),
        .testTarget(
            name: "MahoImgTests",
            dependencies: ["MahoImg"],
            path: "Tests/MahoImgTests"
        )
    ]
)
