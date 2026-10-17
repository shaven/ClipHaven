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
    private lazy var editor = SnippetEditor(store: snippets) {}
    var layout = MenuLayout()
    /// Shown in the status menu, e.g. "Hotkey: ⌃⌘V".
    var hotKeyNote: String?

    init(store: HistoryStore, snippets: SnippetStore, paster: Paster) {
        self.store = store
        self.snippets = snippets
        self.paster = paster
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
        menu.addItem(actionItem("Import ClipMenu Snippets…", #selector(importClipMenuSnippets)))
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
            guard let snippet = try? snippets.snippet(id: id) else { return }
            paster.paste([Representation(type: ClipType.string.pasteboardType, data: Data(snippet.content.utf8))])
        }
    }

    private func popUpActions(for id: Int64) {
        guard let clip = try? store.clip(id: id) else { return }
        let menu = NSMenu(title: "Actions")
        for action in ClipAction.available(for: clip.representations) {
            let item = actionItem(action.title, #selector(runAction(_:)))
            item.representedObject = ActionChoice(action: action, clipID: id)
            menu.addItem(item)
        }
        // Pop after the current menu has closed.
        DispatchQueue.main.async {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    @objc private func runAction(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? ActionChoice else { return }
        report { try paster.perform(choice.action, clipID: choice.clipID) }
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
    let action: ClipAction
    let clipID: Int64

    init(action: ClipAction, clipID: Int64) {
        self.action = action
        self.clipID = clipID
    }
}
