import Foundation

/// 正在播放的歌曲。
struct TrackInfo: Equatable {
    let title: String
    let artist: String
    let album: String
    /// 秒
    let duration: Double

    /// 用于缓存和每首歌的偏移量。
    var key: String { "\(artist)\u{1F}\(title)\u{1F}\(Int(duration.rounded()))" }

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
