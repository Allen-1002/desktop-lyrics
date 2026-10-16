// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesktopLyrics",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DesktopLyrics", targets: ["DesktopLyrics"]),
        // 由 /usr/bin/perl 加载，用来读取系统“正在播放”信息
        .library(name: "NowPlayingHelper", type: .dynamic, targets: ["NowPlayingHelper"]),
    ],
    targets: [
        .executableTarget(
            name: "DesktopLyrics",
            path: "Sources/DesktopLyrics"
        ),
        .target(
            name: "NowPlayingHelper",
            path: "Sources/NowPlayingHelper",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [.linkedFramework("Foundation"), .linkedFramework("AppKit")]
        ),
    ]
)
