import Foundation

/// 正在播放的歌曲。
struct TrackInfo: Equatable {
    let title: String
    let artist: String
    let album: String
    /// 秒；有些播放器不提供时长，这时为 0
    let duration: Double
    /// 正在播放这首歌的应用
    let sourceBundleID: String

    var isFromQQMusic: Bool { sourceBundleID == SourceApps.qqMusic }

    /// 用于缓存和每首歌的偏移量。
    var key: String { "\(artist)\u{1F}\(title)\u{1F}\(Int(duration.rounded()))" }

    /// 歌名或歌手里有汉字。
    var looksChinese: Bool {
        (title + artist).unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    /// 去掉 “(Live)”“- Remastered” 之类的后缀，用于模糊搜索。
    var searchTitle: String {
        var t = title
        if let r = t.range(of: #"\s*[\(（\[【].*?[\)）\]】]"#, options: .regularExpression) {
            t.removeSubrange(r)
        }
        if let r = t.range(of: #"\s+-\s+.*$"#, options: .regularExpression) {
            t.removeSubrange(r)
        }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? title : t
    }
}

enum SourceApps {
    static let appleMusic = "com.apple.Music"
    static let qqMusic = "com.tencent.QQMusicMac"

    /// 音乐 App：同时有浏览器在放视频时，优先跟随它们。
    static let musicApps: Set<String> = [appleMusic, qqMusic]

    /// 只为这些应用显示“歌名 - 歌手”占位；其他来源（比如浏览器里的视频）没找到歌词时就不显示。
    static let showsTitleWithoutLyrics = musicApps
}

/// 播放器某一刻的状态。
struct PlaybackSnapshot {
    /// nil 表示没有在播放任何歌曲。
    let track: TrackInfo?
    /// 秒
    let position: Double
    let isPlaying: Bool

    static let stopped = PlaybackSnapshot(track: nil, position: 0, isPlaying: false)
}

struct LyricLine: Equatable {
    /// 秒
    let time: Double
    let text: String
}
