import AppKit
import ClipHavenCore
import UniformTypeIdentifiers

/// Builds the NSMenu from `MenuModel` for both the status item and the hotkey, and turns a choice
/// into a paste. Control-click on a clip opens its action menu, as ClipMenu does.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let store: HistoryStore
    private let snippets: SnippetStore
    private let paster: Paster
    private let secretPaster: SecretPaster
    private let actions: ActionService
    private let actionStore: ActionStore
    private let scriptsFolder: URL
    private let actionFolders: [URL]
    private lazy var editor = SnippetEditor(store: snippets, secrets: secretPaster) {}
    var layout = MenuLayout()
    /// Opens the Preferences window; set by the app delegate.
    var showPreferences: () -> Void = {}
    /// Shown in the status menu, e.g. "Hotkey: ⌃⌘V".
    var hotKeyNote: String?

    init(store: HistoryStore, snippets: SnippetStore, paster: Paster, secretPaster: SecretPaster,
         actions: ActionService, actionStore: ActionStore, scriptsFolder: URL, actionFolders: [URL]) {
        self.actions = actions
        self.actionStore = actionStore
        self.scriptsFolder = scriptsFolder
        self.actionFolders = actionFolders
        self.store = store
        self.snippets = snippets
        self.paster = paster
        self.secretPaster = secretPaster
    }

    /// The status item's menu; rebuilt each time it opens.
    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        fill(menu)
    }

    /// Pops the history menu at the mouse pointer, without activating ClipHaven, so focus
    /// stays in the app the clip will be pasted into.
    func popUpAtCursor() {
        let menu = NSMenu()
        fill(menu)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func fill(_ menu: NSMenu) {
        let clips = (try? store.summaries(limit: store.limits.maxCount)) ?? []
        let types = Dictionary(clips.map { ($0.id, $0.primaryType) }, uniquingKeysWith: { a, _ in a })
        for entry in MenuModel.build(clips: clips, snippetFolders: (try? snippets.menuSummaries()) ?? [], layout: layout) {
            switch entry {
            case .item(let item):
                menu.addItem(menuItem(item, types: types))
            case .folder(let title, let items):
                let folder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                folder.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
                let submenu = NSMenu(title: title)
                items.forEach { submenu.addItem(menuItem($0, types: types)) }
                folder.submenu = submenu
                menu.addItem(folder)
            case .separator:
                menu.addItem(.separator())
            }
        }
        if clips.isEmpty {
            menu.addItem(NSMenuItem(title: "No clips yet", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Clear History…", #selector(clearHistory)))
        menu.addItem(actionItem("Edit Snippets…", #selector(editSnippets)))
        menu.addItem(actionItem("Preferences…", #selector(openPreferences)))
        menu.addItem(actionItem("Import ClipMenu Snippets…", #selector(importClipMenuSnippets)))
        menu.addItem(actionItem("Import ClipMenu Actions…", #selector(importClipMenuActions)))
        menu.addItem(actionItem("Open Scripts Folder", #selector(openScriptsFolder)))
        menu.addItem(actionItem("Export…", #selector(exportAll)))
        menu.addItem(actionItem("Import…", #selector(importAll)))
        menu.addItem(.separator())
        let about = NSMenuItem(title: "ClipHaven \(ClipHaven.version)", action: nil, keyEquivalent: "")
        menu.addItem(about)
        if let hotKeyNote { menu.addItem(NSMenuItem(title: hotKeyNote, action: nil, keyEquivalent: "")) }
        menu.addItem(NSMenuItem(title: "Quit ClipHaven", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func menuItem(_ entry: MenuItemEntry, types: [Int64: String]) -> NSMenuItem {
        let item = actionItem(entry.title, #selector(choose(_:)))
        item.representedObject = entry.target
        if case .clip(let id) = entry.target, let type = types[id] {
            item.image = Self.icon(for: type)
        }
        if entry.isLocked {
            item.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Locked")
        }
        return item
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Choosing

    @objc private func choose(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MenuTarget else { return }
        switch target {
        case .clip(let id):
            if NSApp.currentEvent?.modifierFlags.contains(.control) == true {
                popUpActions(for: id)
            } else {
                report { try paster.choose(clipID: id) }
            }
        case .snippet(let id):
            pasteSnippet(id)
        }
    }

    /// A locked snippet asks for Touch ID first; an ordinary one is pasted like a clip.
    private func pasteSnippet(_ id: Int64) {
        do {
            switch try secretPaster.paste(snippetID: id) {
            case .notLocked:
                guard let snippet = try snippets.snippet(id: id) else { return }
                paster.paste([Representation(type: ClipType.string.pasteboardType, data: Data(snippet.content.utf8))])
            case .missing:
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Keychain item not found"
                alert.informativeText = "The item this snippet points to is not in the Keychain. Open Edit Snippets… to move or link it again."
                NSApp.activate()
                alert.runModal()
            case .pasted, .cancelled, .notFound:
                break
            }
        } catch {
            NSLog("ClipHaven: locked snippet failed: \(error)")
        }
    }

    /// The saved action list, or the default one (built-ins plus every script found).
    private func actionTree() -> [ActionNode] {
        if let saved = try? actionStore.load() { return saved }
        return ActionList.defaultTree(scripts: ActionList.discoverScripts(in: actionFolders))
    }

    private func popUpActions(for id: Int64) {
        guard let clip = try? store.clip(id: id) else { return }
        let menu = NSMenu(title: "Actions")
        addActions(ActionList.visible(actionTree(), for: clip.representations), to: menu, clipID: id)
        // Pop after the current menu has closed.
        DispatchQueue.main.async {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    private func addActions(_ nodes: [ActionNode], to menu: NSMenu, clipID: Int64) {
        for node in nodes {
            if case .folder(let children) = node.kind {
                let folder = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
                folder.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
                let submenu = NSMenu(title: node.title)
                addActions(children, to: submenu, clipID: clipID)
                folder.submenu = submenu
                menu.addItem(folder)
            } else {
                let item = actionItem(node.title, #selector(runAction(_:)))
                item.representedObject = ActionChoice(node: node, clipID: clipID)
                if case .script = node.kind { item.image = NSImage(systemSymbolName: "curlybraces", accessibilityDescription: nil) }
                menu.addItem(item)
            }
        }
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? ActionChoice else { return }
        Task {
            do {
                try await actions.perform(choice.node, clipID: choice.clipID)
            } catch {
                show("\(choice.node.title) failed", "\(error)")
            }
        }
    }

    /// Replaces the action list with ClipMenu's `actions.plist`, after backing it up.
    @objc private func importClipMenuActions() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let source = support.appendingPathComponent("ClipMenu/actions.plist")
        let backups = support.appendingPathComponent("ClipHaven/backups", isDirectory: true)
        NSApp.activate()
        do {
            let result = try ActionList.importFile(at: source, backupDirectory: backups)
            try actionStore.save(result.tree)
            show("Imported \(Self.countActions(result.tree)) actions", "ClipMenu's file was copied to \(result.backup.path) first. The action list was replaced.")
        } catch {
            show("Import failed", "\(error)")
        }
    }

    private static func countActions(_ nodes: [ActionNode]) -> Int {
        nodes.reduce(0) { total, node in
            if case .folder(let children) = node.kind { return total + countActions(children) }
            return total + 1
        }
    }

    /// Your own scripts go in `action/` (the menu entries) and `lib/` (helpers for `ClipMenu.require`).
    @objc private func openScriptsFolder() {
        for sub in ["action", "lib"] {
            try? FileManager.default.createDirectory(at: scriptsFolder.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(scriptsFolder)
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear the clipboard history?"
        alert.informativeText = "Every clip is deleted. Snippets are kept."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        report { try store.clear() }
    }

    @objc private func openPreferences() {
        showPreferences()
    }

    @objc private func editSnippets() {
        editor.show()
    }

    /// Imports the live ClipMenu `Snippets.xml` after copying it to ClipHaven's backups folder.
    /// The alert shows counts only, never snippet text.
    @objc private func importClipMenuSnippets() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let source = support.appendingPathComponent("ClipMenu/Snippets.xml")
        let backups = support.appendingPathComponent("ClipHaven/backups", isDirectory: true)
        let alert = NSAlert()
        NSApp.activate()

        if ((try? snippets.folderCount()) ?? 0) > 0 {
            alert.messageText = "Import ClipMenu snippets?"
            alert.informativeText = "ClipHaven already has snippet folders. The imported folders are added after them; nothing is replaced."
            alert.addButton(withTitle: "Import")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        let done = NSAlert()
        do {
            let result = try ClipMenuImport.importFile(at: source, into: snippets, backupDirectory: backups)
            done.messageText = "Imported \(result.counts.folders) folders and \(result.counts.snippets) snippets"
            done.informativeText = "ClipMenu's file was copied to \(result.backup.path) first."
        } catch {
            done.alertStyle = .warning
            done.messageText = "Import failed"
            done.informativeText = "\(error)"
        }
        done.runModal()
    }

    /// Writes history and snippets to a JSON file. Keychain snippets go out as service and account only.
    @objc private func exportAll() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ClipHaven Export.json"
        panel.allowedContentTypes = [.json]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Export.data(history: store, snippets: snippets).write(to: url, options: .atomic)
        } catch {
            show("Export failed", "\(error)")
        }
    }

    /// Adds the contents of an export file to the current history and snippets; nothing is replaced.
    @objc private func importAll() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let counts = try Export.restore(Data(contentsOf: url), history: store, snippets: snippets)
            show("Imported \(counts.clips) clips, \(counts.folders) folders and \(counts.snippets) snippets", "Nothing was replaced.")
        } catch {
            show("Import failed", "\(error)")
        }
    }

    private func show(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }

    private func report(_ body: () throws -> Void) {
        do { try body() } catch { NSLog("ClipHaven: \(error)") }
    }

    // MARK: - Icons

    private static var iconCache: [String: NSImage] = [:]

    /// The Finder icon for a clip's primary type, at menu size.
    private static func icon(for type: String) -> NSImage? {
        if let cached = iconCache[type] { return cached }
        let icon = NSWorkspace.shared.icon(for: UTType(type) ?? .data)
        icon.size = NSSize(width: 16, height: 16)
        iconCache[type] = icon
        return icon
    }
}

private final class ActionChoice: NSObject {
    let node: ActionNode
    let clipID: Int64

    init(node: ActionNode, clipID: Int64) {
        self.node = node
        self.clipID = clipID
    }
}
