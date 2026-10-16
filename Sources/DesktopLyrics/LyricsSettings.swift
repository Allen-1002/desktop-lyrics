import AppKit

/// 歌词底色：在花哨的壁纸上加一层半透明底，文字更清楚。
enum LyricsBackground: String, CaseIterable {
    case none, dark, light

    var title: String {
        switch self {
        case .none: return "无"
        case .dark: return "深色底"
        case .light: return "浅色底"
        }
    }
}

/// 用户在菜单里调的显示设置，保存在 UserDefaults。
final class LyricsSettings {
    static let shared = LyricsSettings()
    static let didChange = Notification.Name("LyricsSettingsDidChange")

    static let fontSizes: [(title: String, size: Double)] = [("小", 12), ("中", 13), ("大", 15), ("特大", 17)]
    /// hex 为 nil 表示跟随系统（菜单栏文字颜色）。
    static let colorPresets: [(title: String, hex: String?)] = [
        ("跟随系统", nil), ("白色", "#FFFFFF"), ("黑色", "#1C1C1E"), ("天蓝", "#64D2FF"),
        ("薄荷绿", "#63E6BE"), ("樱花粉", "#FF8FB1"), ("柠檬黄", "#FFD60A"),
    ]

    private let defaults = UserDefaults.standard

    var fontSize: Double {
        get {
            let value = defaults.double(forKey: "fontSize")
            return value > 0 ? value : 13
        }
        set { defaults.set(newValue, forKey: "fontSize"); notify() }
    }

    var colorHex: String? {
        get { defaults.string(forKey: "textColor") }
        set { defaults.set(newValue, forKey: "textColor"); notify() }
    }

    var color: NSColor? { colorHex.flatMap(NSColor.init(hex:)) }

    var background: LyricsBackground {
        get { LyricsBackground(rawValue: defaults.string(forKey: "background") ?? "") ?? .none }
        set { defaults.set(newValue.rawValue, forKey: "background"); notify() }
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String? {
        guard let c = usingColorSpace(.sRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int((c.redComponent * 255).rounded()),
            Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent * 255).rounded())
        )
    }

    /// 0（黑）...1（白）的感知亮度。
    var perceivedBrightness: CGFloat {
        guard let c = usingColorSpace(.sRGB) else { return 1 }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
    }
}
