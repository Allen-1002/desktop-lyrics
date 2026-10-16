import Foundation

/// 从 QQ音乐获取歌词（非官方接口，中文歌覆盖率高）。
/// 先按“歌名 + 歌手”搜索，挑时长最接近的一首，再取它的 LRC。
final class QQMusicProvider {
    private struct Candidate {
        let mid: String
        let title: String
        let artists: [String]
        let duration: Double
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    func fetchSynced(for track: TrackInfo) async -> String? {
        let candidates = await search("\(track.searchTitle) \(track.artist)")
        guard let best = pick(from: candidates, for: track) else {
            Log.info("QQ音乐：没有找到匹配的歌曲（搜到 \(candidates.count) 首）")
            return nil
        }
        guard let lrc = await lyric(mid: best.mid) else {
            Log.info("QQ音乐：找到歌曲但没有拿到歌词")
            return nil
        }
        return lrc
    }

    // MARK: - 搜索

    private func search(_ keyword: String) async -> [Candidate] {
        let body: [String: Any] = [
            "comm": ["ct": "19", "cv": "1859", "uin": "0"],
            "req": [
                "module": "music.search.SearchCgiService",
                "method": "DoSearchForQQMusicDesktop",
                "param": ["query": keyword, "num_per_page": 10, "page_num": 1, "search_type": 0, "grp": 1] as [String: Any],
            ] as [String: Any],
        ]
        var request = URLRequest(url: URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let json = await fetchJSON(request) as? [String: Any],
              let req = json["req"] as? [String: Any],
              let data = req["data"] as? [String: Any],
              let bodyDict = data["body"] as? [String: Any],
              let song = bodyDict["song"] as? [String: Any],
              let list = song["list"] as? [[String: Any]] else {
            Log.info("QQ音乐：搜索接口没有返回结果")
            return []
        }
        return list.compactMap { item in
            guard let mid = item["mid"] as? String, let title = item["name"] as? String else { return nil }
            let artists = (item["singer"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            let duration = (item["interval"] as? NSNumber)?.doubleValue ?? 0
            return Candidate(mid: mid, title: title, artists: artists, duration: duration)
        }
    }

    /// 时长相差 4 秒以内；歌手对得上的优先，其次时长最接近。
    private func pick(from candidates: [Candidate], for track: TrackInfo) -> Candidate? {
        let artist = track.artist.lowercased()
        func artistMatches(_ c: Candidate) -> Bool {
            c.artists.contains { name in
                let n = name.lowercased()
                return artist.contains(n) || n.contains(artist)
            }
        }
        return candidates
            .filter { track.duration <= 0 || abs($0.duration - track.duration) <= 4 }
            .min { a, b in
                let am = artistMatches(a), bm = artistMatches(b)
                if am != bm { return am }
                return abs(a.duration - track.duration) < abs(b.duration - track.duration)
            }
    }

    // MARK: - 歌词

    private func lyric(mid: String) async -> String? {
        var components = URLComponents(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg")!
        components.queryItems = [
            URLQueryItem(name: "songmid", value: mid),
            URLQueryItem(name: "g_tk", value: "5381"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "inCharset", value: "utf8"),
            URLQueryItem(name: "outCharset", value: "utf-8"),
        ]
        guard let url = components.url else { return nil }
        guard let json = await fetchJSON(URLRequest(url: url)) as? [String: Any],
              let encoded = json["lyric"] as? String, !encoded.isEmpty,
              let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
              let lrc = String(data: data, encoding: .utf8) else { return nil }
        return lrc
    }

    // MARK: - 网络

    private func fetchJSON(_ request: URLRequest) async -> Any? {
        var request = request
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        guard let result = try? await session.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200,
              var text = String(data: result.0, encoding: .utf8) else { return nil }
        // 有时会包一层 JSONP：callback({...})
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
            text = String(text[start...end])
        }
        return try? JSONSerialization.jsonObject(with: Data(text.utf8))
    }
}
