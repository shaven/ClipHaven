/// How the history menu is laid out; the defaults are the owner's ClipMenu settings.
public struct MenuLayout: Sendable {
    /// Clips shown directly in the menu before the folders start.
    public var inlineCount = 20
    /// Clips per folder after the inline ones.
    public var folderSize = 25
    /// Characters in a menu title, ellipsis included.
    public var titleLength = 20
    /// Prefix each clip with its number, starting at 1 in every section ("1. title").
    public var numbered = true

    public init() {}
}

/// What choosing a menu item acts on.
public enum MenuTarget: Hashable, Sendable {
    case clip(Int64)
    case snippet(Int64)
}

public struct MenuItemEntry: Equatable, Sendable {
    public let target: MenuTarget
    public let title: String
    /// Shown with a lock: pasting it asks for Touch ID first.
    public let isLocked: Bool

    public init(target: MenuTarget, title: String, isLocked: Bool = false) {
        self.target = target
        self.title = title
        self.isLocked = isLocked
    }
}

public enum MenuEntry: Equatable, Sendable {
    case item(MenuItemEntry)
    case folder(title: String, items: [MenuItemEntry])
    case separator
}

/// A snippet as the menu needs it; the snippet store supplies these.
public struct SnippetSummary: Equatable, Sendable {
    public let id: Int64
    public let title: String
    /// A Keychain snippet, or one flagged "Require Touch ID": pasting it asks first.
    public let isLocked: Bool

    public init(id: Int64, title: String, isLocked: Bool = false) {
        self.id = id
        self.title = title
        self.isLocked = isLocked
    }
}

public struct SnippetFolderSummary: Equatable, Sendable {
    public let title: String
    public let snippets: [SnippetSummary]

    public init(title: String, snippets: [SnippetSummary]) {
        self.title = title
        self.snippets = snippets
    }
}

/// Builds the menu ClipMenu shows: snippet folders first, then the newest clips inline, then the
/// older ones in folders titled by their position ("21 - 45"), each numbered from 1 again.
public enum MenuModel {
    public static func build(clips: [ClipSummary], snippetFolders: [SnippetFolderSummary], layout: MenuLayout) -> [MenuEntry] {
        var entries: [MenuEntry] = snippetFolders.map { folder in
            .folder(title: trim(folder.title, to: layout.titleLength),
                    items: folder.snippets.map { MenuItemEntry(target: .snippet($0.id), title: trim($0.title, to: layout.titleLength), isLocked: $0.isLocked) })
        }
        if !entries.isEmpty, !clips.isEmpty { entries.append(.separator) }

        func item(_ clip: ClipSummary, number: Int) -> MenuItemEntry {
            let title = trim(clip.title, to: layout.titleLength)
            return MenuItemEntry(target: .clip(clip.id), title: layout.numbered ? "\(number). \(title)" : title)
        }

        let inline = clips.prefix(max(layout.inlineCount, 0))
        entries += inline.enumerated().map { .item(item($1, number: $0 + 1)) }

        let size = max(layout.folderSize, 1)
        var start = inline.count
        while start < clips.count {
            let chunk = clips[start..<min(start + size, clips.count)]
            entries.append(.folder(title: "\(start + 1) - \(start + chunk.count)",
                                   items: chunk.enumerated().map { item($1, number: $0 + 1) }))
            start += size
        }
        return entries
    }

    /// Cuts `title` to `length` characters, the last one an ellipsis when anything was cut.
    public static func trim(_ title: String, to length: Int) -> String {
        guard title.count > length, length > 1 else { return title }
        return String(title.prefix(length - 1)) + "…"
    }
}
