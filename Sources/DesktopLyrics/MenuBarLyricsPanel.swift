import AppKit

/// 盖在菜单栏左侧空白处的透明窗口：不抢焦点、鼠标点击直接穿透、所有桌面和全屏应用里都可见。
final class MenuBarLyricsPanel: NSPanel {
    /// 歌词左边和应用菜单之间的间距
    private let leadingGap: CGFloat = 24
    /// 屏幕右侧留给系统图标的比例（你的右侧图标比较多）
    private let reservedRightFraction: CGFloat = 0.38
    private let minimumWidth: CGFloat = 80

    private let lineView = LyricsLineView(frame: .zero)
    private var isTooNarrow = false
    private var targetAlpha: CGFloat = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 24),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        alphaValue = 0
        contentView = lineView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// - Parameter menusEndX: 当前应用菜单最右端的 x；拿不到时按屏幕宽度的 25% 估计。
    func layout(on screen: NSScreen, menusEndX: CGFloat?) {
        let full = screen.frame
        var barHeight = full.maxY - screen.visibleFrame.maxY
        if barHeight <= 0 || barHeight > 60 {
            barHeight = NSStatusBar.system.thickness
        }
        let startX = (menusEndX ?? (full.minX + full.width * 0.25)) + leadingGap
        let endX = full.maxX - full.width * reservedRightFraction
        let width = endX - startX

        isTooNarrow = width < minimumWidth
        Log.info("歌词区域：x=\(Int(startX)) 宽=\(Int(width))\(menusEndX == nil ? "（未读到菜单宽度）" : "")")
        guard !isTooNarrow else {
            applyAlpha(0)
            return
        }
        let frame = NSRect(x: startX, y: full.maxY - barHeight, width: width, height: barHeight).integral
        if frame != self.frame {
            setFrame(frame, display: true)
        }
    }

    func show(text: String, progress: Double, dimmed: Bool, visible: Bool) {
        applyAlpha(visible && !isTooNarrow ? 1 : 0)
        if visible {
            lineView.update(text: text, progress: progress, dimmed: dimmed)
        }
    }

    func redraw() {
        lineView.redraw()
    }

    private func applyAlpha(_ alpha: CGFloat) {
        guard alpha != targetAlpha else { return }
        targetAlpha = alpha
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            animator().alphaValue = alpha
        }
    }
}

/// 画一行歌词：底色是半透明的整句，再按进度从左到右覆盖一层不透明的文字。
final class LyricsLineView: NSView {
    private var text = ""
    private var progress: Double = 0
    private var dimmed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    func update(text: String, progress: Double, dimmed: Bool) {
        // 进度变化很小时不重画，省电
        guard text != self.text || dimmed != self.dimmed || abs(progress - self.progress) > 0.004 else { return }
        self.text = text
        self.progress = progress
        self.dimmed = dimmed
        needsDisplay = true
    }

    /// 设置变了，立即按新样式重画。
    func redraw() {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }

        let settings = LyricsSettings.shared
        let background = settings.background
        let font = NSFont.systemFont(ofSize: CGFloat(settings.fontSize), weight: .medium)
        let textColor: NSColor = {
            if let color = settings.color { return color }
            switch background {
            case .dark: return .white
            case .light: return .black
            case .none: return .labelColor
            }
        }()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        // 没有底色时加一圈与文字反差的阴影，浅色字配黑影、深色字配白影
        var shadow: NSShadow?
        if background == .none {
            let s = NSShadow()
            s.shadowColor = textColor.perceivedBrightness > 0.5
                ? NSColor.black.withAlphaComponent(0.6)
                : NSColor.white.withAlphaComponent(0.7)
            s.shadowBlurRadius = 3
            s.shadowOffset = .zero
            shadow = s
        }

        func attributes(alpha: CGFloat) -> [NSAttributedString.Key: Any] {
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor.withAlphaComponent(alpha),
                .paragraphStyle: paragraph,
            ]
            if let shadow { attrs[.shadow] = shadow }
            return attrs
        }

        let string = text as NSString
        let size = string.size(withAttributes: attributes(alpha: 1))
        let padding: CGFloat = background == .none ? 0 : 8
        let textWidth = min(ceil(size.width), max(0, bounds.width - padding * 2))

        if background != .none {
            let pillHeight = min(bounds.height - 2, size.height + 4)
            let pill = NSRect(x: 0, y: (bounds.height - pillHeight) / 2, width: textWidth + padding * 2, height: pillHeight)
            let fill = background == .dark
                ? NSColor.black.withAlphaComponent(0.55)
                : NSColor.white.withAlphaComponent(0.8)
            fill.setFill()
            NSBezierPath(roundedRect: pill, xRadius: pillHeight / 2, yRadius: pillHeight / 2).fill()
        }

        let rect = NSRect(x: padding, y: (bounds.height - size.height) / 2, width: textWidth, height: size.height)
        if dimmed {
            string.draw(in: rect, withAttributes: attributes(alpha: 0.6))
            return
        }

        string.draw(in: rect, withAttributes: attributes(alpha: 0.45))
        guard progress > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: padding, y: 0, width: textWidth * CGFloat(progress), height: bounds.height)).addClip()
        string.draw(in: rect, withAttributes: attributes(alpha: 1))
        NSGraphicsContext.restoreGraphicsState()
    }
}
