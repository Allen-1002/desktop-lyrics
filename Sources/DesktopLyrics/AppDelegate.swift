import AppKit
import QuartzCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum LoadState {
        case idle, loading, loaded, notFound
    }

    /// 暂停超过这个秒数后隐藏歌词
    private let hideAfterPause: CFTimeInterval = 3
    private let offsetStep = 0.5

    private let music = AppleMusicSource()
    private let systemNowPlaying = SystemNowPlayingSource()
    private let clock = PlaybackClock()
    private let store = LyricsStore()
    private let panel = MenuBarLyricsPanel()
    private let settings = LyricsSettings.shared
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
        Log.info("已启动，辅助功能权限：\(MenuBarLayout.isTrusted ? "已开启" : "未开启")")
        setupStatusItem()
        MenuBarLayout.requestTrustIfNeeded()
        systemNowPlaying.start()
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
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged), name: LyricsSettings.didChange, object: nil
        )

        schedule(every: 0.5, #selector(poll))
        schedule(every: 1.0, #selector(relayout))
        schedule(every: 1.0 / 30, #selector(render))
        poll()
        relayout()
    }

    func applicationWillTerminate(_ notification: Notification) {
        systemNowPlaying.stop()
    }

    private func schedule(every interval: TimeInterval, _ selector: Selector) {
        let timer = Timer(timeInterval: interval, target: self, selector: selector, userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    // MARK: - 播放状态

    /// Apple Music 用 AppleScript 读（进度最准）；其他播放器（QQ音乐、浏览器等）用系统“正在播放”信息。
    private func currentSnapshot() -> PlaybackSnapshot? {
        if let system = systemNowPlaying.current(),
           system.bundleID != SourceApps.appleMusic,
           system.snapshot.track != nil {
            return system.snapshot
        }
        return music.poll()
    }

    @objc private func poll() {
        guard let snapshot = currentSnapshot() else { return }

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
            Log.info("正在播放：\(track.title) - \(track.artist)（\(Int(track.duration)) 秒，来自 \(track.sourceBundleID)）")
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
                Log.info("找到歌词，共 \(lines.count) 行")
                self.timeline = LyricsTimeline(lines: lines)
                self.loadState = .loaded
            } else {
                Log.info("没有找到带时间轴的歌词")
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
        let fallback = SourceApps.showsTitleWithoutLyrics.contains(track.sourceBundleID)
            ? "♪ \(track.title) - \(track.artist)"
            : ""

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

    /// 登录 macOS 时自动打开。只有装在“应用程序”文件夹里的正式版才能注册。
    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            Log.info("设置开机自启失败：\(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "没能设置开机自启"
            alert.informativeText = "请先用 ./scripts/install.sh 把桌面歌词装进“应用程序”文件夹，再从那里打开。\n\n\(error.localizedDescription)"
            alert.runModal()
        }
    }

    // MARK: - 样式设置

    @objc private func settingsChanged() { panel.redraw() }

    @objc private func setFontSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? Double else { return }
        settings.fontSize = size
    }

    @objc private func setColorPreset(_ sender: NSMenuItem) {
        let hex = sender.representedObject as? String
        settings.colorHex = (hex?.isEmpty ?? true) ? nil : hex
    }

    @objc private func chooseCustomColor() {
        let colorPanel = NSColorPanel.shared
        colorPanel.showsAlpha = false
        colorPanel.color = settings.color ?? .white
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(colorPanelChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        colorPanel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        settings.colorHex = sender.color.hexString
    }

    @objc private func setBackground(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = LyricsBackground(rawValue: raw) else { return }
        settings.background = value
    }

    private func styleMenu() -> [NSMenuItem] {
        let sizeMenu = NSMenu()
        for option in LyricsSettings.fontSizes {
            let item = sizeMenu.addItem(action: option.title, #selector(setFontSize(_:)), target: self, enabled: true)
            item.representedObject = option.size
            item.state = abs(settings.fontSize - option.size) < 0.1 ? .on : .off
        }

        let colorMenu = NSMenu()
        var matchedPreset = false
        for preset in LyricsSettings.colorPresets {
            let item = colorMenu.addItem(action: preset.title, #selector(setColorPreset(_:)), target: self, enabled: true)
            item.representedObject = preset.hex ?? ""
            let selected = preset.hex?.uppercased() == settings.colorHex?.uppercased()
            item.state = selected ? .on : .off
            matchedPreset = matchedPreset || selected
        }
        colorMenu.addItem(.separator())
        let custom = colorMenu.addItem(action: "自定义颜色…", #selector(chooseCustomColor), target: self, enabled: true)
        custom.state = matchedPreset ? .off : .on

        let backgroundMenu = NSMenu()
        for option in LyricsBackground.allCases {
            let item = backgroundMenu.addItem(action: option.title, #selector(setBackground(_:)), target: self, enabled: true)
            item.representedObject = option.rawValue
            item.state = settings.background == option ? .on : .off
        }

        let groups: [(String, NSMenu)] = [("字号", sizeMenu), ("文字颜色", colorMenu), ("背景", backgroundMenu)]
        return groups.map { group in
            let item = NSMenuItem(title: group.0, action: nil, keyEquivalent: "")
            item.submenu = group.1
            return item
        }
    }

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
            menu.addItem(disabled: "没有在播放音乐")
        }

        menu.addItem(.separator())
        let hasTrack = currentTrack != nil
        menu.addItem(action: "歌词提前 0.5 秒", #selector(lyricsEarlier), target: self, enabled: hasTrack)
        menu.addItem(action: "歌词延后 0.5 秒", #selector(lyricsLater), target: self, enabled: hasTrack)
        menu.addItem(action: "重置偏移", #selector(resetOffset), target: self, enabled: hasTrack)
        menu.addItem(action: "重新获取歌词", #selector(refetchLyrics), target: self, enabled: hasTrack)

        menu.addItem(.separator())
        for item in styleMenu() {
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let hide = menu.addItem(action: "隐藏歌词", #selector(toggleHidden), target: self, enabled: true)
        hide.state = userHidden ? .on : .off
        let login = menu.addItem(action: "登录时自动打开", #selector(toggleLaunchAtLogin), target: self, enabled: true)
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
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
