import AppKit

/// 通过 AppleScript 读取“音乐”App 的当前歌曲和播放进度。
final class AppleMusicSource {
    static let bundleID = "com.apple.Music"
    private static let separator = "\u{1F}"

    private let script = NSAppleScript(source: """
    tell application id "com.apple.Music"
        set playerStateText to (player state as text)
        if playerStateText is "stopped" then return "stopped"
        set theTrack to current track
        set fieldSeparator to (character id 31)
        return playerStateText & fieldSeparator & (name of theTrack) & fieldSeparator & (artist of theTrack) & fieldSeparator & (album of theTrack) & fieldSeparator & ((duration of theTrack) as text) & fieldSeparator & ((player position) as text)
    end tell
    """)

    /// 返回 nil 表示这次读取失败（比如还没授权），调用方应保留上一次的状态。
    func poll() -> PlaybackSnapshot? {
        // 不在运行时直接返回，避免 AppleScript 把“音乐”App 拉起来
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty else {
            Log.info("“音乐”App 没有在运行")
            return .stopped
        }
        var error: NSDictionary?
        guard let output = script?.executeAndReturnError(&error).stringValue else {
            Log.info("读取“音乐”App 失败：\(error ?? [:])")
            return nil
        }
        if output == "stopped" { return .stopped }

        let parts = output.components(separatedBy: Self.separator)
        guard parts.count == 6 else {
            Log.info("无法解析“音乐”App 的返回：\(output)")
            return nil
        }
        let track = TrackInfo(
            title: parts[1],
            artist: parts[2],
            album: parts[3],
            duration: Self.number(parts[4])
        )
        return PlaybackSnapshot(track: track, position: Self.number(parts[5]), isPlaying: parts[0] == "playing")
    }

    /// AppleScript 的数字转文本会跟随系统区域设置，小数点可能是逗号。
    private static func number(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
}
