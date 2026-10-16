import Foundation

/// 解析 LRC 歌词：支持一行多个时间标签、[offset:] 标签，并去掉逐字时间标签 <mm:ss.xx>。
enum LRCParser {
    private static let timeTag = try! NSRegularExpression(pattern: #"^\[(\d{1,3}):(\d{1,2}(?:[.:]\d{1,3})?)\]"#)
    private static let inlineTag = try! NSRegularExpression(pattern: #"<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>"#)

    static func parse(_ content: String) -> [LyricLine] {
        var offset = 0.0
        var lines: [LyricLine] = []

        for rawLine in content.components(separatedBy: .newlines) {
            var rest = rawLine.trimmingCharacters(in: .whitespaces)

            if rest.lowercased().hasPrefix("[offset:"), let end = rest.firstIndex(of: "]") {
                let start = rest.index(rest.startIndex, offsetBy: 8)
                offset = (Double(rest[start..<end].trimmingCharacters(in: .whitespaces)) ?? 0) / 1000
                continue
            }

            var times: [Double] = []
            while let match = timeTag.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
                  let whole = Range(match.range, in: rest),
                  let minutes = Range(match.range(at: 1), in: rest),
                  let seconds = Range(match.range(at: 2), in: rest) {
                let m = Double(rest[minutes]) ?? 0
                let s = Double(rest[seconds].replacingOccurrences(of: ":", with: ".")) ?? 0
                times.append(m * 60 + s)
                rest = String(rest[whole.upperBound...])
            }
            guard !times.isEmpty else { continue }

            let text = inlineTag
                .stringByReplacingMatches(in: rest, range: NSRange(rest.startIndex..., in: rest), withTemplate: "")
                .trimmingCharacters(in: .whitespaces)
            for t in times {
                lines.append(LyricLine(time: t, text: text))
            }
        }

        // LRC 规范里 offset 为正表示歌词提前
        return lines
            .map { LyricLine(time: max(0, $0.time - offset), text: $0.text) }
            .sorted { $0.time < $1.time }
    }
}

/// 按时间查找当前行，并估算这一行的演唱进度（用于逐字高亮）。
struct LyricsTimeline {
    let lines: [LyricLine]

    static let empty = LyricsTimeline(lines: [])

    var isEmpty: Bool { lines.isEmpty }

    /// 最后一个开始时间 <= t 的行。
    func index(at t: Double) -> Int? {
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= t {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// 返回当前行文字和 0...1 的进度；还没到第一行时返回 nil。
    func display(at t: Double) -> (text: String, progress: Double)? {
        guard let i = index(at: t) else { return nil }
        let line = lines[i]
        let next = i + 1 < lines.count ? lines[i + 1].time : line.time + 6
        // LRC 只有行级时间，按字数估一个演唱时长，避免长间奏时高亮走得太慢
        let gap = max(0.1, next - line.time)
        let singing = min(gap, max(1.5, Double(line.text.count) * 0.3))
        let progress = min(1, max(0, (t - line.time) / singing))
        return (line.text, progress)
    }
}
