// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StockBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "StockBar",
            path: "StockBar"
        ),
    ]
)
