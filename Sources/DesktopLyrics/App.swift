import AppKit

@main
struct DesktopLyricsApp {
    @MainActor
    static func main() {
        quitOtherInstances()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// 同一时间只保留一个：新启动的这个接管，把之前还在跑的（比如终端里那个）退出掉，
    /// 不然菜单栏会出现两个 ♪、两行歌词叠在一起。
    @MainActor
    private static func quitOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        for other in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        where other.processIdentifier != me {
            Log.info("发现另一个正在运行的桌面歌词（pid \(other.processIdentifier)），已让它退出")
            if !other.terminate() { other.forceTerminate() }
        }
    }
}
