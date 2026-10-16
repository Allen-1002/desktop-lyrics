import QuartzCore

/// 根据最近一次读到的播放位置，在本地推算当前播放时间。
/// 两次读取之间不用等播放器，画面可以按帧平滑刷新。
final class PlaybackClock {
    /// 推算值和读到的值相差超过这个秒数才校准，避免歌词来回抖动。
    private let tolerance = 0.25

    private(set) var isPlaying = false
    private var anchorPosition: Double = 0
    private var anchorTime: CFTimeInterval = CACurrentMediaTime()

    var now: Double {
        isPlaying ? anchorPosition + (CACurrentMediaTime() - anchorTime) : anchorPosition
    }

    func update(position: Double, isPlaying playing: Bool, force: Bool = false) {
        if force || playing != isPlaying || abs(now - position) > tolerance {
            anchorPosition = position
            anchorTime = CACurrentMediaTime()
        }
        isPlaying = playing
    }
}
