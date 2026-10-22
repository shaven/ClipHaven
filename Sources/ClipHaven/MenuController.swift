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
    private let syncStore: SnapshotStore
    private let scriptsFolder: URL
    private let actionFolders: [URL]
    private lazy var editor = SnippetEditor(store: snippets, secrets: secretPaster) {}
    private lazy var actionEditor = ActionEditor(
        load: { [unowned self] in actionTree() },
        save: { [unowned self] tree in
            do { try actionStore.save(tree) } catch { NSLog("ClipHaven: action list not saved: \(error)") }
        },
        scripts: { [unowned self] in ActionList.discoverScripts(in: actionFolders) },
        defaults: { [unowned self] in ActionList.defaultTree(scripts: ActionList.discoverScripts(in: actionFolders)) })
    var layout = MenuLayout()
    private let icons = MenuIcons()
    private let secrets: SecretProvider
    private let clicks = ActionClickTracker()
    private weak var statusMenu: NSMenu?
    /// Remembered between openings and launches.
    private var searchScope = SearchScope(rawValue: UserDefaults.standard.integer(forKey: "searchScope")) ?? .all {
        didSet { UserDefaults.standard.set(searchScope.rawValue, forKey: "searchScope") }
    }
    private let preview = PreviewPanel()
    private let watcher = HighlightWatcher()
    private var previewTask: Task<Void, Never>?
    /// Set when the menu was opened with Control-right-click: choosing a clip opens its actions.
    private var actionMode = false
    var appearance: MenuAppearance {
        get { icons.appearance }
        set { icons.appearance = newValue }
    }
    /// Opens the Preferences window; set by the app delegate.
    var showPreferences: () -> Void = {}
    /// Shown in the status menu, e.g. "Hotkey: ⌃⌘V".
    var hotKeyNote: String?

    init(store: HistoryStore, snippets: SnippetStore, paster: Paster, secretPaster: SecretPaster,
         actions: ActionService, actionStore: ActionStore, scriptsFolder: URL, actionFolders: [URL],
         syncStore: SnapshotStore, secrets: SecretProvider) {
        self.syncStore = syncStore
        self.secrets = secrets
        self.actions = actions
        self.actionStore = actionStore
        self.scriptsFolder = scriptsFolder
        self.actionFolders = actionFolders
        self.store = store
        self.snippets = snippets
        self.paster = paster
        self.secretPaster = secretPaster
        super.init()
        watcher.onHighlight = { [unowned self] in highlighted($0) }
    }

    /// The status item's menu; rebuilt each time it opens.
    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        statusMenu = menu
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // The hotkey menu is filled before it opens; only the status menu is rebuilt each time.
        guard menu === statusMenu else { return }
        menu.removeAllItems()
        fill(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        clicks.start()
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        highlighted(item)
    }

    func menuDidClose(_ menu: NSMenu) {
        hidePreview()
        // The chosen item's action runs just after the menu closes, so sampling stops later.
        clicks.stop(after: 0.6)
    }

    /// Pops the history menu at the mouse pointer, without activating ClipHaven, so focus
    /// stays in the app the clip will be pasted into.
    func popUpAtCursor(actions: Bool = false) {
        actionMode = actions
        let menu = NSMenu()
        menu.delegate = self
        fill(menu)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func fill(_ menu: NSMenu) {
        let field = MenuSearchField(frame: .zero)
        field.scope = searchScope
        field.onChange = { [unowned self, unowned menu] in search($0, scope: searchScope, in: menu) }
        field.onScope = { [unowned self, unowned menu, unowned field] in
            searchScope = $0
            search(field.text, scope: $0, in: menu)
        }
        field.onReturn = { [unowned self, unowned menu] in chooseFirstMatch(in: menu) }
        let fieldItem = NSMenuItem()
        fieldItem.view = field
        menu.addItem(fieldItem)
        fillBody(menu)
    }

    private func fillBody(_ menu: NSMenu) {
        let clips = (try? store.summaries(limit: store.limits.maxCount)) ?? []
        let types = Dictionary(clips.map { ($0.id, $0.primaryType) }, uniquingKeysWith: { a, _ in a })
        let snippetFolders = (try? snippets.menuSummaries()) ?? []
        let entries = MenuModel.build(clips: clips, snippetFolders: snippetFolders, layout: layout)

        // Snippet folders come first, then a separator, then the history.
        let historyStart = snippetFolders.count + (!snippetFolders.isEmpty && !clips.isEmpty ? 1 : 0)
        var shortcuts = Array("1234567890").makeIterator()
        for (index, entry) in entries.enumerated() {
            if index == 0, !snippetFolders.isEmpty { menu.addItem(.sectionHeader(title: "Snippets")) }
            if index == historyStart, !clips.isEmpty { menu.addItem(.sectionHeader(title: "History")) }
            switch entry {
            case .item(let item):
                let menuItem = menuItem(item, types: types)
                // ⌘1 … ⌘0 choose the first ten clips, as in ClipMenu.
                if case .clip = item.target, let key = shortcuts.next() { menuItem.keyEquivalent = String(key) }
                menu.addItem(menuItem)
            case .folder(let title, let items):
                let folder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                if appearance.showIcons { folder.image = icons.image(.folder) }
                let submenu = makeSubmenu(title)
                items.forEach { submenu.addItem(menuItem($0, types: types)) }
                addEmptyNote(to: submenu)
                folder.submenu = submenu
                menu.addItem(folder)
            case .folderWithSubfolders(let title, let items, let subfolders):
                let folder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                if appearance.showIcons { folder.image = icons.image(.folder) }
                let submenu = makeSubmenu(title)
                for sub in subfolders {
                    let subItem = NSMenuItem(title: sub.title, action: nil, keyEquivalent: "")
                    if appearance.showIcons { subItem.image = icons.image(.folder) }
                    let inner = makeSubmenu(sub.title)
                    sub.items.forEach { inner.addItem(menuItem($0, types: types)) }
                    addEmptyNote(to: inner)
                    subItem.submenu = inner
                    submenu.addItem(subItem)
                }
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
        menu.addItem(actionItem("Edit Snippets…", #selector(editSnippets)))
        menu.addItem(actionItem("Edit Actions…", #selector(editActions)))
        menu.addItem(actionItem("Clear History…", #selector(clearHistory)))
        menu.addItem(actionItem("Preferences…", #selector(openPreferences)))

        let tools = NSMenuItem(title: "Import, Export and Scripts", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: tools.title)
        submenu.addItem(actionItem("Import ClipMenu Snippets…", #selector(importClipMenuSnippets)))
        submenu.addItem(actionItem("Import ClipMenu Actions…", #selector(importClipMenuActions)))
        submenu.addItem(actionItem("Import ClipMenu History…", #selector(importClipMenuHistory)))
        submenu.addItem(.separator())
        submenu.addItem(actionItem("Sync Snippets with iCloud Keychain…", #selector(syncSnippets)))
        submenu.addItem(.separator())
        submenu.addItem(actionItem("Export…", #selector(exportAll)))
        submenu.addItem(actionItem("Import…", #selector(importAll)))
        submenu.addItem(actionItem("Export Everything for Another Mac…", #selector(exportTransfer)))
        submenu.addItem(actionItem("Import from Another Mac…", #selector(importTransfer)))
        submenu.addItem(.separator())
        submenu.addItem(actionItem("Open Scripts Folder", #selector(openScriptsFolder)))
        submenu.addItem(actionItem("Help: Writing Scripts", #selector(openScriptsHelp)))
        tools.submenu = submenu
        menu.addItem(tools)

        menu.addItem(.separator())
        let about = ["ClipHaven \(ClipHaven.version)", hotKeyNote].compactMap { $0 }.joined(separator: "  ·  ")
        menu.addItem(NSMenuItem(title: about, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit ClipHaven", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// macOS will not open a submenu with nothing in it, so an empty folder says so.
    private func addEmptyNote(to submenu: NSMenu) {
        guard submenu.numberOfItems == 0 else { return }
        let note = NSMenuItem(title: "(empty)", action: nil, keyEquivalent: "")
        note.isEnabled = false
        submenu.addItem(note)
    }

    private func makeSubmenu(_ title: String) -> NSMenu {
        let submenu = NSMenu(title: title)
        submenu.delegate = watcher
        return submenu
    }

    private func menuItem(_ entry: MenuItemEntry, types: [Int64: String]) -> NSMenuItem {
        let item = actionItem(entry.title, #selector(choose(_:)))
        item.representedObject = entry.target
        var kind = MenuIconKind.snippet
        switch entry.target {
        case .clip(let id):
            kind = .kind(forClipType: types[id] ?? "")
            if kind == .image, appearance.showThumbnails { item.image = icons.thumbnail(for: id, in: store) }
            if kind == .files, appearance.showIcons { item.image = icons.fileIcon(for: id, in: store) }
        case .snippet:
            if entry.isLocked { kind = .lockedSnippet }
        }
        if item.image == nil, appearance.showIcons { item.image = icons.image(kind) }
        return item
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Filtering

    /// Swaps the menu's contents for the matches of `text`, each showing where it sits in the
    /// normal menu; an empty field brings the normal menu back. The field itself stays put.
    private func search(_ text: String, scope: SearchScope, in menu: NSMenu) {
        while menu.numberOfItems > 1 { menu.removeItem(at: 1) }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else {
            fillBody(menu)
            return
        }
        let clips = (try? store.summaries(limit: store.limits.maxCount)) ?? []
        let types = Dictionary(clips.map { ($0.id, $0.primaryType) }, uniquingKeysWith: { a, _ in a })
        let found = MenuSearch.results(query: text, clips: clips, matchingClipIDs: (try? store.search(words: words, scope: scope, limit: 200)) ?? [],
                                       snippetFolders: (try? snippets.folders()) ?? [], layout: layout, scope: scope)
        for result in found {
            let item = menuItem(MenuItemEntry(target: result.target, title: result.title, isLocked: result.isLocked), types: types)
            let title = NSMutableAttributedString(string: result.title + "\n")
            title.append(NSAttributedString(string: result.path, attributes: [.font: NSFont.menuFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]))
            item.attributedTitle = title
            menu.addItem(item)
        }
        if found.isEmpty { menu.addItem(NSMenuItem(title: "No matches", action: nil, keyEquivalent: "")) }
    }

    /// Return in the filter field chooses the first match, as clicking it would.
    private func chooseFirstMatch(in menu: NSMenu) {
        guard let first = menu.items.dropFirst().first(where: { $0.representedObject is MenuTarget }) else { return }
        menu.cancelTracking()
        DispatchQueue.main.async { [self] in choose(first) }
    }

    // MARK: - Preview

    private func hidePreview() {
        previewTask?.cancel()
        previewTask = nil
        preview.hide()
    }

    /// Shows the hover preview for the highlighted item after a short pause, so moving down the
    /// list does not load every clip on the way.
    private func highlighted(_ item: NSMenuItem?) {
        hidePreview()
        guard let target = item?.representedObject as? MenuTarget else { return }
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, let content = previewContent(for: target) else { return }
            preview.show(content)
        }
    }

    private func previewContent(for target: MenuTarget) -> PreviewContent? {
        switch target {
        case .clip(let id):
            guard let clip = try? store.clip(id: id) else { return nil }
            return ClipPreview.content(for: clip.representations)
        case .snippet(let id):
            guard let snippet = try? snippets.snippet(id: id) else { return nil }
            return ClipPreview.content(for: snippet)
        }
    }

    // MARK: - Choosing

    @objc private func choose(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MenuTarget else { return }
        switch target {
        case .clip(let id):
            if isActionClick() {
                popUpActions(for: id)
            } else {
                report { try paster.choose(clipID: id) }
            }
        case .snippet(let id):
            pasteSnippet(id)
        }
    }

    /// Control-click (or a right-click) on a clip opens its actions. macOS turns a Control-click on
    /// a menu item into a right-click and the event can arrive without its Control flag, so the keys
    /// held right now count as well as the event's own flags.
    private func isActionClick() -> Bool {
        defer { clicks.reset(); actionMode = false }
        if actionMode { return true }
        let held = NSEvent.modifierFlags
        let event = NSApp.currentEvent
        let eventFlags = event?.modifierFlags ?? []
        let rightClick = event.map { $0.type == .rightMouseUp || $0.type == .rightMouseDown } ?? false
        let result = clicks.sawActionClick || held.contains(.control) || held.contains(.option)
            || eventFlags.contains(.control) || eventFlags.contains(.option) || rightClick
        NSLog("ClipHaven: choose sampled=\(clicks.sawActionClick) held=\(held.rawValue) event=\(event.map { "\($0.type.rawValue)/\($0.modifierFlags.rawValue)" } ?? "none") -> actions=\(result)")
        return result
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
        guard let saved = try? actionStore.load() else {
            return ActionList.defaultTree(scripts: ActionList.discoverScripts(in: actionFolders))
        }
        // Scripts in the user folder that the saved list lacks appear under "My Scripts".
        let mine = ActionList.discoverScripts(in: [scriptsFolder.appendingPathComponent("action")])
        return ActionList.withMyScripts(saved, userScripts: mine)
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
                folder.image = icons.image(.folder)
                let submenu = NSMenu(title: node.title)
                addActions(children, to: submenu, clipID: clipID)
                folder.submenu = submenu
                menu.addItem(folder)
            } else {
                let item = actionItem(node.title, #selector(runAction(_:)))
                item.representedObject = ActionChoice(node: node, clipID: clipID)
                if case .script = node.kind { item.image = icons.image(.script) }
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
        let backups = support.appendingPathComponent("ClipHaven/backups", isDirectory: true)
        NSApp.activate()
        guard let source = chooseFile("Choose the ClipMenu actions file to import",
                                      startingAt: support.appendingPathComponent("ClipMenu/actions.plist")) else { return }
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

    /// Adds ClipMenu's old clipboard history below the current clips. It runs in a child process.
    @objc private func importClipMenuHistory() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        NSApp.activate()
        guard let source = chooseFile("Choose the ClipMenu history file (clips.data) to import",
                                      startingAt: support.appendingPathComponent("ClipMenu/clips.data")) else { return }
        let ask = NSAlert()
        ask.messageText = "Import ClipMenu's clipboard history?"
        ask.informativeText = "ClipMenu's clips are added below the ones ClipHaven already has, in ClipMenu's order. Clips already here are skipped, and nothing is replaced. Images over the size limit are stored as PNG when that fits. The file is large, so this can take a minute."
        ask.addButton(withTitle: "Import")
        ask.addButton(withTitle: "Cancel")
        guard ask.runModal() == .alertFirstButtonReturn else { return }

        let database = store.url
        Task {
            switch await HistoryImportMode.run(source: source, database: database, limit: nil) {
            case .success(let counts):
                var detail = "Skipped \(counts.duplicates) already here and \(counts.skipped) with nothing storable (images over the limit even as PNG)."
                if counts.stoppedFull { detail += " History reached its size limit, so the oldest clips were left out." }
                show("Imported \(counts.imported) clips", detail)
            case .failure(let failure):
                show("Import failed", failure.message)
            }
        }
    }

    /// Takes in the snippets the other Macs shared, then shares this Mac's list. Nothing is
    /// replaced and no password value is sent: Keychain snippets travel as service and account.
    @objc private func syncSnippets() {
        NSApp.activate()
        do {
            let report = try SnippetSync.sync(snippets, with: syncStore, device: Host.current().localizedName ?? "Mac")
            var detail = "Shared \(report.sent) snippets. Passwords sync separately: use “Sync through iCloud Keychain” on each Keychain snippet in Edit Snippets…."
            if report.skipped > 0 {
                detail += " \(report.skipped) plain snippet(s) flagged Require Touch ID were not shared; move them to the Keychain first."
            }
            show("Added \(report.added.folders) folders and \(report.added.snippets) snippets from your other Macs", detail)
        } catch {
            show("Sync failed", "\(error)\n\nThis needs a ClipHaven build signed with its provisioning profile, and iCloud Keychain turned on.")
        }
    }

    /// Your own scripts go in `action/` (the menu entries) and `lib/` (helpers for `ClipMenu.require`).
    @objc private func openScriptsFolder() {
        for sub in ["action", "lib"] {
            try? FileManager.default.createDirectory(at: scriptsFolder.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(scriptsFolder)
    }

    /// The bundled guide to writing and adding scripts, opened in the default text editor.
    @objc private func openScriptsHelp() {
        guard let help = Bundle.main.resourceURL?.appendingPathComponent("Help/Writing-Scripts.txt") else { return }
        NSWorkspace.shared.open(help)
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

    @objc private func editActions() {
        actionEditor.show()
    }

    @objc private func editSnippets() {
        editor.show()
    }

    /// Imports the live ClipMenu `Snippets.xml` after copying it to ClipHaven's backups folder.
    /// The alert shows counts only, never snippet text.
    @objc private func importClipMenuSnippets() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let backups = support.appendingPathComponent("ClipHaven/backups", isDirectory: true)
        NSApp.activate()
        guard let source = chooseFile("Choose the ClipMenu snippets file to import",
                                      startingAt: support.appendingPathComponent("ClipMenu/Snippets.xml")) else { return }
        let alert = NSAlert()

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

    /// Asks for the transfer passphrase; `confirm` asks twice, as when the file is made.
    private func askPassphrase(_ message: String, confirm: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = confirm
            ? "Type the same passphrase on the other Mac to open the file. It is not stored anywhere; if you forget it the file cannot be opened."
            : "The passphrase you chose when the file was made."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        let first = NSSecureTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        first.placeholderString = "Passphrase"
        let second = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        second.placeholderString = "Again"
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: confirm ? 58 : 24))
        first.frame.origin.y = confirm ? 34 : 0
        box.addSubview(first)
        if confirm { box.addSubview(second) }
        alert.accessoryView = box
        NSApp.activate()
        alert.window.initialFirstResponder = first
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        guard !first.stringValue.isEmpty else { show("No passphrase", "Type a passphrase to seal the file."); return nil }
        if confirm, first.stringValue != second.stringValue {
            show("The passphrases differ", "Nothing was exported.")
            return nil
        }
        return first.stringValue
    }

    /// History, snippets, passwords, the action list and settings in one file sealed with a passphrase.
    @objc private func exportTransfer() {
        guard let passphrase = askPassphrase("Passphrase for the transfer file", confirm: true) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ClipHaven Transfer.cliphaven"
        panel.message = "Passwords are read from the Keychain, so you may be asked for Touch ID."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Transfer.seal(history: store, snippets: snippets, secrets: secrets, actions: actionStore,
                                         preferences: Preferences(), passphrase: passphrase)
            try data.write(to: url, options: .atomic)
            show("Transfer file saved", "Copy it to the other Mac and choose Import from Another Mac…. Delete it afterwards.")
        } catch {
            show("Export failed", "\(error)")
        }
    }

    @objc private func importTransfer() {
        let panel = NSOpenPanel()
        panel.message = "Choose a ClipHaven transfer file."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url,
              let passphrase = askPassphrase("Passphrase for the transfer file", confirm: false) else { return }
        do {
            let counts = try Transfer.open(Data(contentsOf: url), passphrase: passphrase, history: store, snippets: snippets,
                                           secrets: secrets, actions: actionStore, preferences: Preferences())
            show("Imported \(counts.clips) clips, \(counts.folders) folders, \(counts.snippets) snippets and \(counts.secrets) passwords",
                 "Your action list and settings were replaced. Restart ClipHaven for the history size to apply.")
        } catch {
            show("Import failed", "\(error)")
        }
    }

    /// A file browser that opens in the folder where ClipMenu keeps the file, with that file
    /// selected when it is there, so a backup kept anywhere else can be picked instead.
    private func chooseFile(_ message: String, startingAt file: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.fileExists(atPath: file.path) ? file : file.deletingLastPathComponent()
        return panel.runModal() == .OK ? panel.url : nil
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
