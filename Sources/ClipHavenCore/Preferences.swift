import Foundation

/// ClipHaven's settings, kept in `UserDefaults` under the key names the app has used since
/// Phase 4 (`autoPaste`, `hotKeyCode`, `hotKeyModifiers`). Defaults are ClipMenu's own; setters
/// clamp, so a stale or hand-edited value cannot break the menu.
public struct Preferences {
    // Carbon values, spelled out so the core does not link Carbon: kVK_ANSI_V, cmdKey | controlKey.
    public static let defaultHotKeyCode: UInt32 = 9
    public static let defaultHotKeyModifiers: UInt32 = 256 | 4096

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var autoPaste: Bool {
        get { bool("autoPaste", true) }
        set { defaults.set(newValue, forKey: "autoPaste") }
    }

    public var hotKeyCode: UInt32 {
        get { UInt32(clamping: defaults.object(forKey: "hotKeyCode") as? Int ?? Int(Self.defaultHotKeyCode)) }
        set { defaults.set(Int(newValue), forKey: "hotKeyCode") }
    }

    public var hotKeyModifiers: UInt32 {
        get { UInt32(clamping: defaults.object(forKey: "hotKeyModifiers") as? Int ?? Int(Self.defaultHotKeyModifiers)) }
        set { defaults.set(Int(newValue), forKey: "hotKeyModifiers") }
    }

    /// Whether the owner chose a hotkey, which then wins over the ClipMenu-running fallback.
    public var hasCustomHotKey: Bool {
        defaults.object(forKey: "hotKeyCode") != nil || defaults.object(forKey: "hotKeyModifiers") != nil
    }

    public var maxCount: Int {
        get { int("maxCount", 1_000, 10...10_000) }
        set { defaults.set(newValue.clamped(10...10_000), forKey: "maxCount") }
    }

    public var maxImageBytes: Int {
        get { int("maxImageBytes", 10_000_000, 100_000...200_000_000) }
        set { defaults.set(newValue.clamped(100_000...200_000_000), forKey: "maxImageBytes") }
    }

    public var inlineCount: Int {
        get { int("inlineCount", 20, 0...100) }
        set { defaults.set(newValue.clamped(0...100), forKey: "inlineCount") }
    }

    public var folderSize: Int {
        get { int("folderSize", 25, 1...100) }
        set { defaults.set(newValue.clamped(1...100), forKey: "folderSize") }
    }

    public var titleLength: Int {
        get { int("titleLength", 20, 8...100) }
        set { defaults.set(newValue.clamped(8...100), forKey: "titleLength") }
    }

    public var numbered: Bool {
        get { bool("numbered", true) }
        set { defaults.set(newValue, forKey: "numbered") }
    }

    /// Seconds before a pasted secret is replaced by the clipboard it displaced.
    public var restoreDelay: TimeInterval {
        get { min(max(defaults.object(forKey: "restoreDelay") as? Double ?? 2, 0.5), 30) }
        set { defaults.set(min(max(newValue, 0.5), 30), forKey: "restoreDelay") }
    }

    public var showIcons: Bool {
        get { bool("showIcons", true) }
        set { defaults.set(newValue, forKey: "showIcons") }
    }

    /// Menu icon size in points: 16, 32 or 48, as in ClipMenu. Other values snap to the nearest.
    public var iconSize: Int {
        get { Self.snap(defaults.object(forKey: "iconSize") as? Int ?? 16) }
        set { defaults.set(Self.snap(newValue), forKey: "iconSize") }
    }

    public var showThumbnails: Bool {
        get { bool("showThumbnails", true) }
        set { defaults.set(newValue, forKey: "showThumbnails") }
    }

    public var thumbnailWidth: Int {
        get { int("thumbnailWidth", 100, 16...256) }
        set { defaults.set(newValue.clamped(16...256), forKey: "thumbnailWidth") }
    }

    public var thumbnailHeight: Int {
        get { int("thumbnailHeight", 32, 16...128) }
        set { defaults.set(newValue.clamped(16...128), forKey: "thumbnailHeight") }
    }

    /// A `StatusIconChoice.id`.
    public var statusIcon: String {
        get { StatusIconChoice.resolve(defaults.string(forKey: "statusIcon") ?? "").id }
        set { defaults.set(newValue, forKey: "statusIcon") }
    }

    /// A plain right-click on a text field, in any app, opens the clip menu there.
    public var rightClickMenu: Bool {
        get { bool("rightClickMenu", true) }
        set { defaults.set(newValue, forKey: "rightClickMenu") }
    }

    public var appearance: MenuAppearance {
        var look = MenuAppearance()
        look.showIcons = showIcons
        look.iconSize = iconSize
        look.showThumbnails = showThumbnails
        look.thumbnailSize = CGSize(width: thumbnailWidth, height: thumbnailHeight)
        return look
    }

    private static func snap(_ size: Int) -> Int {
        [16, 32, 48].min { abs($0 - size) < abs($1 - size) }!
    }

    public var layout: MenuLayout {
        var layout = MenuLayout()
        layout.inlineCount = inlineCount
        layout.folderSize = folderSize
        layout.titleLength = titleLength
        layout.numbered = numbered
        return layout
    }

    public var limits: HistoryStore.Limits {
        HistoryStore.Limits(maxCount: maxCount, maxImageBytes: maxImageBytes)
    }

    public mutating func reset() {
        for key in ["autoPaste", "hotKeyCode", "hotKeyModifiers", "maxCount", "maxImageBytes", "inlineCount",
                    "folderSize", "titleLength", "numbered", "restoreDelay", "showIcons", "iconSize",
                    "showThumbnails", "thumbnailWidth", "thumbnailHeight", "statusIcon", "rightClickMenu"] {
            defaults.removeObject(forKey: key)
        }
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }

    private func int(_ key: String, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
        (defaults.object(forKey: key) as? Int ?? fallback).clamped(range)
    }
}

private extension Int {
    func clamped(_ range: ClosedRange<Int>) -> Int { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
