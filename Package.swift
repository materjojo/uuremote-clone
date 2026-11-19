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
        .target(
            name: "OfficialStreamerABI",
            path: "native/official",
            sources: ["official_streamer_abi.cpp"],
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "UURemoteClone",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC"),
                "OfficialStreamerABI"
            ],
            path: "Sources/UURemoteClone"
        ),
        .testTarget(
            name: "OfficialStreamerTests",
            dependencies: ["UURemoteClone"],
            path: "Tests/OfficialStreamerTests"
        )
    ],
    cxxLanguageStandard: .cxx17
)
