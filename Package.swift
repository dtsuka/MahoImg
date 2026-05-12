// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MahoImg",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MahoImg", targets: ["MahoImg"]),
        .library(name: "MahoImgCore", targets: ["MahoImgCore"])
    ],
    targets: [
        .target(
            name: "MahoImgCore",
            path: "Sources/MahoImgCore"
        ),
        .executableTarget(
            name: "MahoImg",
            dependencies: ["MahoImgCore"],
            path: "Sources/MahoImgApp"
        ),
        .testTarget(
            name: "MahoImgTests",
            dependencies: ["MahoImgCore"],
            path: "Tests/MahoImgTests"
        )
    ]
)
