import Foundation
import QuartzCore

/// 读取系统“正在播放”信息（控制中心里的那张卡片），覆盖 QQ音乐、浏览器等所有接入了系统媒体控制的播放器。
///
/// 实际读取由 /usr/bin/perl 加载 libNowPlayingHelper.dylib 完成（macOS 15.4 起只有系统程序能读），
/// 它每 0.5 秒输出一行 JSON，这里负责启动它并解析输出。
final class SystemNowPlayingSource {
    struct Reading {
        let snapshot: PlaybackSnapshot
        let bundleID: String
    }

    /// 超过这个秒数没收到新数据，就当作读不到
    private let staleAfter: CFTimeInterval = 3

    private var process: Process?
    private var buffer = Data()
    private var latest: (reading: Reading, receivedAt: CFTimeInterval)?

    func start() {
        guard let resources = Bundle.main.resourceURL else { return }
        let script = resources.appendingPathComponent("now-playing.pl")
        let library = resources.appendingPathComponent("libNowPlayingHelper.dylib")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: library.path) else {
            Log.info("没有找到系统播放信息组件，只支持 Apple Music（请用 ./scripts/build-app.sh 打包后启动）")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [script.path, library.path]

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.consume(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return }
            DispatchQueue.main.async { Log.info("系统播放信息组件：\(text)") }
        }
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                Log.info("系统播放信息组件已退出（状态 \(finished.terminationStatus)），只支持 Apple Music")
                self?.latest = nil
                self?.process = nil
            }
        }

        do {
            try process.run()
            self.process = process
            Log.info("已启动系统播放信息组件")
        } catch {
            Log.info("无法启动系统播放信息组件：\(error.localizedDescription)")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    /// 最新的播放状态；播放位置按收到数据后经过的时间往后推。
    func current() -> Reading? {
        guard let latest else { return nil }
        let age = CACurrentMediaTime() - latest.receivedAt
        guard age < staleAfter else { return nil }
        let snapshot = latest.reading.snapshot
        let position = snapshot.isPlaying ? snapshot.position + age : snapshot.position
        return Reading(
            snapshot: PlaybackSnapshot(track: snapshot.track, position: position, isPlaying: snapshot.isPlaying),
            bundleID: latest.reading.bundleID
        )
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(line)
        }
    }

    private func handle(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line),
              let json = object as? [String: Any] else { return }
        let bundleID = json["bundle"] as? String ?? ""
        let reading: Reading
        if let title = json["title"] as? String, !title.isEmpty {
            let track = TrackInfo(
                title: title,
                artist: json["artist"] as? String ?? "",
                album: json["album"] as? String ?? "",
                duration: (json["duration"] as? NSNumber)?.doubleValue ?? 0,
                sourceBundleID: bundleID
            )
            reading = Reading(
                snapshot: PlaybackSnapshot(
                    track: track,
                    position: (json["position"] as? NSNumber)?.doubleValue ?? 0,
                    isPlaying: (json["playing"] as? NSNumber)?.boolValue ?? false
                ),
                bundleID: bundleID
            )
        } else {
            reading = Reading(snapshot: .stopped, bundleID: bundleID)
        }
        latest = (reading, CACurrentMediaTime())
    }
}
