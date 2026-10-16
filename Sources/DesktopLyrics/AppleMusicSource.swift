import AppKit

/// 通过 AppleScript 读取“音乐”App 的当前歌曲和播放进度。
final class AppleMusicSource {
    static let bundleID = "com.apple.Music"
    private static let separator = "\u{1F}"

    private let script = NSAppleScript(source: """
    tell application id "com.apple.Music"
        set st to (player state as text)
        if st is "stopped" then return "stopped"
        set t to current track
        set sep to (character id 31)
        return st & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) as text) & sep & ((player position) as text)
    end tell
    """)

    /// 返回 nil 表示这次读取失败（比如还没授权），调用方应保留上一次的状态。
    func poll() -> PlaybackSnapshot? {
        // 不在运行时直接返回，避免 AppleScript 把“音乐”App 拉起来
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty else {
            return .stopped
        }
        var error: NSDictionary?
        guard let output = script?.executeAndReturnError(&error).stringValue else {
            return nil
        }
        if output == "stopped" { return .stopped }

        let parts = output.components(separatedBy: Self.separator)
        guard parts.count == 6 else { return nil }
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
