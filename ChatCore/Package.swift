// swift-tools-version: 6.0
import PackageDescription

// Platform-independent logic: the DeepSeek wire format, request building,
// stream parsing and Markdown parsing. Kept free of Apple-only frameworks so
// `swift test` runs anywhere.
let package = Package(
    name: "ChatCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ChatCore", targets: ["ChatCore"]),
    ],
    targets: [
        .target(name: "ChatCore"),
        .testTarget(name: "ChatCoreTests", dependencies: ["ChatCore"]),
    ]
)
