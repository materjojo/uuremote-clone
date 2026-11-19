// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UURemoteClone",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "UURemoteClone", targets: ["UURemoteClone"])
    ],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC.git", from: "120.0.0")
    ],
    targets: [
        .executableTarget(
            name: "UURemoteClone",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "Sources/UURemoteClone"
        )
    ]
)
