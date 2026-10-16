// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesktopLyrics",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DesktopLyrics",
            path: "Sources/DesktopLyrics"
        ),
    ]
)
