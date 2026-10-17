/// The modifier keys held with a right-click.
public struct RightClickModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift = RightClickModifiers(rawValue: 1)
    public static let control = RightClickModifiers(rawValue: 2)
    public static let option = RightClickModifiers(rawValue: 4)
    public static let command = RightClickModifiers(rawValue: 8)

    /// The Mac symbols in menu order: ⌃⌥⇧⌘.
    public var symbols: String {
        var text = ""
        if contains(.control) { text += "⌃" }
        if contains(.option) { text += "⌥" }
        if contains(.shift) { text += "⇧" }
        if contains(.command) { text += "⌘" }
        return text
    }
}

public enum RightClickMode: Equatable, Sendable {
    /// The ordinary menu: choosing a clip pastes it.
    case paste
    /// Choosing a clip opens its actions.
    case actions
}

/// Which modifier keys, held with a right-click, open ClipHaven's menu. A right-click with no
/// modifier is never ours, so it keeps the app's own context menu.
public enum RightClickGesture {
    public static let defaultPaste: RightClickModifiers = [.shift, .control]
    public static let defaultActions: RightClickModifiers = [.control]

    /// The menu for exactly these held keys, or nil. If both gestures are the same, paste wins.
    public static func mode(for held: RightClickModifiers, paste: RightClickModifiers, actions: RightClickModifiers) -> RightClickMode? {
        guard !held.isEmpty else { return nil }
        if held == paste { return .paste }
        if held == actions { return .actions }
        return nil
    }
}
