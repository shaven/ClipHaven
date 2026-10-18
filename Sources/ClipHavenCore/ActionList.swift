import Foundation

/// One entry of the Control-click action menu: a built-in action, a JavaScript file (by its
/// path under the `action` folders, e.g. `Case/UPPERCASE.js`), or a folder of entries.
public struct ActionNode: Equatable, Codable, Sendable {
    public indirect enum Kind: Equatable, Codable, Sendable {
        case builtin(ClipAction)
        case script(String)
        case folder([ActionNode])
    }

    public var title: String
    public var kind: Kind

    public init(title: String, kind: Kind) {
        self.title = title
        self.kind = kind
    }
}

public enum ActionListError: Error, CustomStringConvertible {
    case notAnActionList

    public var description: String { "not a ClipMenu actions.plist" }
}

public enum ActionList {
    /// Reads ClipMenu's `actions.plist`. A script keeps the part of its path after
    /// `/script/action/`, so a list made on another machine finds the same scripts here. An
    /// action ClipHaven does not have, and a folder left empty by that, is dropped.
    public static func importClipMenu(_ data: Data) throws -> [ActionNode] {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            throw ActionListError.notAnActionList
        }
        return convert(root)
    }

    private static func convert(_ entries: [[String: Any]]) -> [ActionNode] {
        entries.compactMap { entry in
            let title = entry["nodeTitle"] as? String ?? ""
            if let action = entry["action"] as? [String: Any] {
                switch action["type"] as? String {
                case "builtin":
                    guard let name = action["name"] as? String, let builtin = ClipAction(clipMenuName: name) else { return nil }
                    return ActionNode(title: title, kind: .builtin(builtin))
                case "js":
                    guard let path = action["path"] as? String else { return nil }
                    let relative = path.range(of: "/script/action/").map { String(path[$0.upperBound...]) }
                        ?? (path as NSString).lastPathComponent
                    let name = title.hasSuffix(".js") ? String(title.dropLast(3)) : title
                    return ActionNode(title: name, kind: .script(relative))
                default:
                    return nil
                }
            }
            let children = convert(entry["children"] as? [[String: Any]] ?? [])
            return children.isEmpty ? nil : ActionNode(title: title, kind: .folder(children))
        }
    }

    /// Copies `source` into `backupDirectory` (dated, never overwritten), then parses it. A file
    /// that does not parse leaves the backup in place and throws.
    public static func importFile(at source: URL, backupDirectory: URL, date: Date = Date()) throws -> (tree: [ActionNode], backup: URL) {
        let data = try Data(contentsOf: source)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let day = ISO8601DateFormatter().string(from: date).prefix(10)
        let backup = backupDirectory.appendingPathComponent("actions-\(day).plist")
        if !FileManager.default.fileExists(atPath: backup.path) { try data.write(to: backup, options: .withoutOverwriting) }
        return (try importClipMenu(data), backup)
    }

    /// Every `.js` file under the folders, as a tree that follows the directories. A script
    /// found in an earlier folder hides one with the same path in a later one.
    public static func discoverScripts(in folders: [URL]) -> [ActionNode] {
        var seen = Set<String>()
        var paths: [String] = []
        for folder in folders {
            let root = folder.standardizedFileURL
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in files where url.pathExtension == "js" {
                let relative = String(url.standardizedFileURL.path.dropFirst(root.path.count + 1))
                if seen.insert(relative).inserted { paths.append(relative) }
            }
        }
        return tree(paths.map { ($0.split(separator: "/").map(String.init), $0) })
    }

    private static func tree(_ entries: [(parts: [String], path: String)]) -> [ActionNode] {
        let order: (String, String) -> Bool = { $0.localizedStandardCompare($1) == .orderedAscending }
        let folders = Dictionary(grouping: entries.filter { $0.parts.count > 1 }, by: { $0.parts[0] })
        let folderNodes = folders.keys.sorted(by: order).map { name in
            ActionNode(title: name, kind: .folder(tree(folders[name]!.map { (Array($0.parts.dropFirst()), $0.path) })))
        }
        let scripts = entries.filter { $0.parts.count == 1 }.sorted { order($0.parts[0], $1.parts[0]) }
            .map { ActionNode(title: String($0.parts[0].dropLast(3)), kind: .script($0.path)) }
        return folderNodes + scripts
    }

    /// What a new install shows: Paste as Plain Text, every script under "Scripts", Remove.
    public static func defaultTree(scripts: [ActionNode]) -> [ActionNode] {
        var tree = [ActionNode(title: ClipAction.pasteAsPlainText.title, kind: .builtin(.pasteAsPlainText))]
        if !scripts.isEmpty { tree.append(ActionNode(title: "Scripts", kind: .folder(scripts))) }
        tree.append(ActionNode(title: ClipAction.remove.title, kind: .builtin(.remove)))
        return tree
    }

    /// The tree plus a "My Scripts" folder holding every script of `userScripts` that the tree does
    /// not already list, so a script dropped into the user folder shows up without editing the list.
    public static func withMyScripts(_ tree: [ActionNode], userScripts: [ActionNode]) -> [ActionNode] {
        var listed = Set<String>()
        func collect(_ nodes: [ActionNode]) {
            for node in nodes {
                switch node.kind {
                case .script(let path): listed.insert(path)
                case .folder(let children): collect(children)
                case .builtin: break
                }
            }
        }
        collect(tree)
        func unlisted(_ nodes: [ActionNode]) -> [ActionNode] {
            nodes.compactMap { node in
                switch node.kind {
                case .script(let path): return listed.contains(path) ? nil : node
                case .folder(let children):
                    let kept = unlisted(children)
                    return kept.isEmpty ? nil : ActionNode(title: node.title, kind: .folder(kept))
                case .builtin: return nil
                }
            }
        }
        let extra = unlisted(userScripts)
        return extra.isEmpty ? tree : tree + [ActionNode(title: "My Scripts", kind: .folder(extra))]
    }

    /// The part of the tree that applies to a clip: text actions need text, file-path actions
    /// need files, and a folder with nothing left in it is hidden.
    public static func visible(_ tree: [ActionNode], for representations: [Representation]) -> [ActionNode] {
        let hasText = ClipAction.plainText(of: representations) != nil
        let builtins = ClipAction.available(for: representations)
        return tree.compactMap { node in
            switch node.kind {
            case .builtin(let action): return builtins.contains(action) ? node : nil
            case .script: return hasText ? node : nil
            case .folder(let children):
                let kept = visible(children, for: representations)
                return kept.isEmpty ? nil : ActionNode(title: node.title, kind: .folder(kept))
            }
        }
    }
}

/// The action list as a JSON file.
public struct ActionStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// The saved list, or nil when none has been saved yet.
    public func load() throws -> [ActionNode]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode([ActionNode].self, from: Data(contentsOf: url))
    }

    public func save(_ tree: [ActionNode]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(tree).write(to: url, options: .atomic)
    }
}

public enum ActionServiceError: Error, CustomStringConvertible {
    case scriptNotFound(String)

    public var description: String {
        switch self {
        case .scriptNotFound(let path): "Script not found: \(path)"
        }
    }
}

/// Runs a chosen action on a clip: a built-in through `Paster`, a script through `ScriptRunner`
/// with the clip's text, pasting what the script returns.
@MainActor
public final class ActionService {
    private let paster: Paster
    private let store: HistoryStore
    private let runner: ScriptRunner
    private let actionFolders: [URL]

    public init(paster: Paster, store: HistoryStore, runner: ScriptRunner, actionFolders: [URL]) {
        self.paster = paster
        self.store = store
        self.runner = runner
        self.actionFolders = actionFolders
    }

    public func perform(_ node: ActionNode, clipID: Int64) async throws {
        switch node.kind {
        case .builtin(let action):
            try paster.perform(action, clipID: clipID)
        case .script(let path):
            let file = try resolve(path)
            guard let clip = try store.clip(id: clipID),
                  let plain = ClipAction.plainText(of: clip.representations)?.first else { return }
            let result = try await runner.runAsync(file, clipText: String(decoding: plain.data, as: UTF8.self))
            paster.pasteString(result)
        case .folder:
            break
        }
    }

    private func resolve(_ path: String) throws -> URL {
        for folder in actionFolders {
            let root = folder.standardizedFileURL
            let candidate = root.appendingPathComponent(path).standardizedFileURL
            guard candidate.path.hasPrefix(root.path + "/") else { continue }
            if FileManager.default.isReadableFile(atPath: candidate.path) { return candidate }
        }
        throw ActionServiceError.scriptNotFound(path)
    }
}
