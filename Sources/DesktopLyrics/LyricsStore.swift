import CryptoKit
import Foundation

/// 从 LRCLIB（https://lrclib.net）获取带时间轴的歌词。
final class LRCLibProvider {
    private struct Record: Decodable {
        let duration: Double?
        let instrumental: Bool?
        let syncedLyrics: String?
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    func fetchSynced(for track: TrackInfo) async -> String? {
        // 1. 精确匹配：歌名 + 歌手 + 专辑 + 时长
        var exact = URLComponents(string: "https://lrclib.net/api/get")!
        exact.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        if let record: Record = await get(exact.url),
           let lyrics = record.syncedLyrics, !lyrics.isEmpty {
            return lyrics
        }

        // 2. 模糊搜索：按时长最接近的结果
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [
            URLQueryItem(name: "track_name", value: track.searchTitle),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        guard let records: [Record] = await get(search.url) else { return nil }
        let candidate = records
            .filter { !($0.syncedLyrics ?? "").isEmpty }
            .min { abs(($0.duration ?? 0) - track.duration) < abs(($1.duration ?? 0) - track.duration) }
        guard let best = candidate, let duration = best.duration, abs(duration - track.duration) <= 5 else { return nil }
        return best.syncedLyrics
    }

    private func get<T: Decodable>(_ url: URL?) async -> T? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("DesktopLyrics/0.1 (https://github.com/Allen-1002/desktop-lyrics)", forHTTPHeaderField: "User-Agent")
        guard let result = try? await session.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: result.0)
    }
}

/// 歌词获取 + 本地缓存（~/Library/Application Support/DesktopLyrics/Lyrics）。
final class LyricsStore {
    private let lrclib = LRCLibProvider()
    private let qqMusic = QQMusicProvider()
    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("DesktopLyrics/Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 返回 nil 表示没找到带时间轴的歌词。
    func lyrics(for track: TrackInfo, ignoreCache: Bool) async -> [LyricLine]? {
        let file = cacheFile(for: track)
        if !ignoreCache, let cached = try? String(contentsOf: file, encoding: .utf8) {
            let lines = LRCParser.parse(cached)
            if !lines.isEmpty { return lines }
        }
        // 中文歌先查 QQ音乐，其他先查 LRCLIB
        let sources: [(name: String, fetch: (TrackInfo) async -> String?)] = track.looksChinese
            ? [("QQ音乐", qqMusic.fetchSynced), ("LRCLIB", lrclib.fetchSynced)]
            : [("LRCLIB", lrclib.fetchSynced), ("QQ音乐", qqMusic.fetchSynced)]
        for source in sources {
            guard let lrc = await source.fetch(track) else {
                Log.info("\(source.name)：没有找到歌词")
                continue
            }
            let lines = LRCParser.parse(lrc)
            guard lines.count > 1 else {
                Log.info("\(source.name)：歌词没有时间轴")
                continue
            }
            Log.info("歌词来源：\(source.name)")
            try? lrc.write(to: file, atomically: true, encoding: .utf8)
            return lines
        }
        return nil
    }

    private func cacheFile(for track: TrackInfo) -> URL {
        let hash = SHA256.hash(data: Data(track.key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash).appendingPathExtension("lrc")
    }
}
