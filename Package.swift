// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StockBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.28.0"),
    ],
    targets: [
        .executableTarget(
            name: "StockBar",
            dependencies: [
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            path: "StockBar",
            resources: [
                .process("Assets.xcassets"),
                .copy("Resources/AppIcon.icns")
            ]
        ),
    ]
)
