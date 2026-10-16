import AppKit
import ApplicationServices

/// 用辅助功能接口读出最前面那个应用的菜单在菜单栏里占到哪里，
/// 让歌词紧跟在菜单后面，不压住菜单。
enum MenuBarLayout {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 首次启动时弹出系统的“辅助功能”授权提示。
    static func requestTrustIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 应用菜单最右端的 x 坐标（全局坐标）。没有权限或读取失败时返回 nil。
    static func appMenusMaxX(for app: NSRunningApplication?) -> CGFloat? {
        guard isTrusted, let app else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)

        var menuBarRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBarValue = menuBarRef, CFGetTypeID(menuBarValue) == AXUIElementGetTypeID() else { return nil }
        let menuBar = menuBarValue as! AXUIElement

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }

        var maxX: CGFloat?
        for item in children {
            guard let frame = frame(of: item), frame.width > 0 else { continue }
            maxX = max(maxX ?? frame.maxX, frame.maxX)
        }
        return maxX
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef, let sizeValue = sizeRef,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
