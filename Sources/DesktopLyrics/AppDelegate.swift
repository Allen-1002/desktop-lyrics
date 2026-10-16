import AppKit
import QuartzCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum LoadState {
        case idle, loading, loaded, notFound
    }

    /// 暂停超过这个秒数后隐藏歌词
    private let hideAfterPause: CFTimeInterval = 3
    private let offsetStep = 0.5

    private let music = AppleMusicSource()
    private let clock = PlaybackClock()
    private let store = LyricsStore()
    private let panel = MenuBarLyricsPanel()
    private var statusItem: NSStatusItem?

    private var currentTrack: TrackInfo?
    private var timeline = LyricsTimeline.empty
    private var loadState = LoadState.idle
    private var loadTask: Task<Void, Never>?
    private var pausedSince: CFTimeInterval?
    private var userHidden = false
    private var lastOtherApp: NSRunningApplication?
    private var timers: [Timer] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        MenuBarLayout.requestTrustIfNeeded()
        panel.orderFrontRegardless()

        // “音乐”App 切歌、播放、暂停时会立即广播，不用等下一次轮询
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(poll), name: Notification.Name("com.apple.Music.playerInfo"), object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(relayout), name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(relayout), name: NSApplication.didChangeScreenParametersNotification, object: nil
        )

        schedule(every: 0.5, #selector(poll))
        schedule(every: 1.0, #selector(relayout))
        schedule(every: 1.0 / 30, #selector(render))
        poll()
        relayout()
    }

    private func schedule(every interval: TimeInterval, _ selector: Selector) {
        let timer = Timer(timeInterval: interval, target: self, selector: selector, userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    // MARK: - 播放状态

    @objc private func poll() {
        guard let snapshot = music.poll() else { return }

        guard let track = snapshot.track else {
            if currentTrack != nil {
                currentTrack = nil
                loadTask?.cancel()
                timeline = .empty
                loadState = .idle
            }
            clock.update(position: 0, isPlaying: false, force: true)
            return
        }

        if track != currentTrack {
            currentTrack = track
            clock.update(position: snapshot.position, isPlaying: snapshot.isPlaying, force: true)
            loadLyrics(for: track, ignoreCache: false)
        } else {
            clock.update(position: snapshot.position, isPlaying: snapshot.isPlaying)
        }

        if snapshot.isPlaying {
            pausedSince = nil
        } else if pausedSince == nil {
            pausedSince = CACurrentMediaTime()
        }
    }

    private func loadLyrics(for track: TrackInfo, ignoreCache: Bool) {
        loadTask?.cancel()
        timeline = .empty
        loadState = .loading
        let store = self.store
        loadTask = Task { [weak self] in
            let lines = await store.lyrics(for: track, ignoreCache: ignoreCache)
            guard let self, !Task.isCancelled, self.currentTrack == track else { return }
            if let lines {
                self.timeline = LyricsTimeline(lines: lines)
                self.loadState = .loaded
            } else {
                self.loadState = .notFound
            }
        }
    }

    // MARK: - 显示

    @objc private func render() {
        guard let track = currentTrack, !userHidden else {
            panel.show(text: "", progress: 0, dimmed: false, visible: false)
            return
        }
        let pausedTooLong = pausedSince.map { CACurrentMediaTime() - $0 > hideAfterPause } ?? false
        let fallback = "♪ \(track.title) - \(track.artist)"

        var text = fallback
        var progress = 0.0
        var dimmed = true
        if loadState == .loaded {
            if let line = timeline.display(at: clock.now + offset(for: track)) {
                text = line.text
                progress = line.progress
                dimmed = false
            }
        } else if loadState == .idle {
            text = ""
        }

        panel.show(text: text, progress: progress, dimmed: dimmed, visible: !pausedTooLong && !text.isEmpty)
    }

    @objc private func relayout() {
        guard let screen = NSScreen.screens.first else { return }
        // 打开本应用的菜单时自己会变成最前面的应用，这时沿用上一个应用的菜单宽度
        var front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            front = lastOtherApp
        } else {
            lastOtherApp = front
        }
        panel.layout(on: screen, menusEndX: MenuBarLayout.appMenusMaxX(for: front))
    }

    // MARK: - 偏移量（每首歌单独保存）

    private func offsetKey(for track: TrackInfo) -> String { "offset.\(track.key)" }

    /// 正数表示歌词提前显示。
    private func offset(for track: TrackInfo) -> Double {
        UserDefaults.standard.double(forKey: offsetKey(for: track))
    }

    private func adjustOffset(by delta: Double?) {
        guard let track = currentTrack else { return }
        let value = delta.map { offset(for: track) + $0 } ?? 0
        UserDefaults.standard.set(value, forKey: offsetKey(for: track))
    }

    @objc private func lyricsEarlier() { adjustOffset(by: offsetStep) }
    @objc private func lyricsLater() { adjustOffset(by: -offsetStep) }
    @objc private func resetOffset() { adjustOffset(by: nil) }

    @objc private func refetchLyrics() {
        guard let track = currentTrack else { return }
        loadLyrics(for: track, ignoreCache: true)
    }

    @objc private func toggleHidden() { userHidden.toggle() }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 菜单栏图标和菜单

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "桌面歌词")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let track = currentTrack {
            menu.addItem(disabled: "\(track.title) - \(track.artist)")
            switch loadState {
            case .loading: menu.addItem(disabled: "正在获取歌词…")
            case .notFound: menu.addItem(disabled: "没有找到带时间轴的歌词")
            case .loaded, .idle: break
            }
            let value = offset(for: track)
            if value != 0 {
                menu.addItem(disabled: String(format: "当前偏移：%@%.1f 秒", value > 0 ? "提前 " : "延后 ", abs(value)))
            }
        } else {
            menu.addItem(disabled: "Apple Music 没有在播放")
        }

        menu.addItem(.separator())
        let hasTrack = currentTrack != nil
        menu.addItem(action: "歌词提前 0.5 秒", #selector(lyricsEarlier), target: self, enabled: hasTrack)
        menu.addItem(action: "歌词延后 0.5 秒", #selector(lyricsLater), target: self, enabled: hasTrack)
        menu.addItem(action: "重置偏移", #selector(resetOffset), target: self, enabled: hasTrack)
        menu.addItem(action: "重新获取歌词", #selector(refetchLyrics), target: self, enabled: hasTrack)

        menu.addItem(.separator())
        let hide = menu.addItem(action: "隐藏歌词", #selector(toggleHidden), target: self, enabled: true)
        hide.state = userHidden ? .on : .off
        if !MenuBarLayout.isTrusted {
            menu.addItem(action: "开启辅助功能权限（让歌词紧跟菜单）…", #selector(openAccessibilitySettings), target: self, enabled: true)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出桌面歌词", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }
}

private extension NSMenu {
    func addItem(disabled title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }

    @discardableResult
    func addItem(action title: String, _ selector: Selector, target: AnyObject, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: enabled ? selector : nil, keyEquivalent: "")
        item.target = target
        addItem(item)
        return item
    }
}
