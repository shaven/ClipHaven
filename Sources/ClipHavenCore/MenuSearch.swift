import Foundation

/// One row of the menu's filter results: what to paste and where it lives in the normal menu.
public struct SearchResult: Equatable, Sendable {
    public let target: MenuTarget
    public let title: String
    /// Where the item sits in the unfiltered menu, e.g. `Snippets › Work › Login` or `History › 21 - 45 › #7`.
    public let path: String
    public let isLocked: Bool

    public init(target: MenuTarget, title: String, path: String, isLocked: Bool = false) {
        self.target = target
        self.title = title
        self.path = path
        self.isLocked = isLocked
    }
}

/// Which part of an item the filter words must be found in.
public enum SearchScope: Int, CaseIterable, Sendable {
    /// Title, folder or text.
    case all
    /// The title (and, for a snippet, its folder names) only.
    case names
    /// The text itself only.
    case contents
}

/// Filters snippets and history by the words typed in the menu's search field.
public enum MenuSearch {
    public static let separator = " › "
    static let titleLength = 60

    /// Snippets whose title, folder or text holds every word, then the clips in `matchingClipIDs`
    /// (newest first, from `HistoryStore.search`). A locked snippet matches on its title and
    /// folders only (never in `.contents`), so a search can never reveal what it protects.
    public static func results(query: String, clips: [ClipSummary], matchingClipIDs: [Int64],
                               snippetFolders: [SnippetFolder], layout: MenuLayout, scope: SearchScope = .all,
                               limit: Int = 50) -> [SearchResult] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        return Array(snippetResults(words, snippetFolders, scope).prefix(limit))
            + clipResults(matchingClipIDs, clips: clips, layout: layout).prefix(limit)
    }

    private static func snippetResults(_ words: [String], _ folders: [SnippetFolder], _ scope: SearchScope) -> [SearchResult] {
        let enabled = folders.filter(\.enabled)
        var found: [SearchResult] = []
        for folder in enabled where folder.parentID == nil {
            let group = [folder] + enabled.filter { $0.parentID == folder.id }
            for sub in group {
                let names = sub.parentID == nil ? [sub.title] : [folder.title, sub.title]
                for snippet in sub.snippets where snippet.enabled {
                    let named = [snippet.title] + names
                    let body = snippet.isLocked ? [] : [snippet.content]
                    let haystack = (scope == .names ? named : scope == .contents ? body : named + body).joined(separator: "\n")
                    guard words.allSatisfy({ haystack.localizedCaseInsensitiveContains($0) }) else { continue }
                    found.append(SearchResult(target: .snippet(snippet.id), title: MenuModel.trim(snippet.title, to: titleLength),
                                              path: (["Snippets"] + names).joined(separator: separator), isLocked: snippet.isLocked))
                }
            }
        }
        return found
    }

    private static func clipResults(_ ids: [Int64], clips: [ClipSummary], layout: MenuLayout) -> [SearchResult] {
        let wanted = Set(ids)
        let inline = max(layout.inlineCount, 0)
        let size = max(layout.folderSize, 1)
        var found: [SearchResult] = []
        for (index, clip) in clips.enumerated() where wanted.contains(clip.id) {
            let path: String
            if index < inline {
                path = "History\(separator)#\(index + 1)"
            } else {
                let start = inline + (index - inline) / size * size
                let end = min(start + size, clips.count)
                path = "History\(separator)\(start + 1) - \(end)\(separator)#\(index - start + 1)"
            }
            found.append(SearchResult(target: .clip(clip.id), title: MenuModel.trim(clip.title, to: titleLength), path: path))
        }
        return found
    }
}
