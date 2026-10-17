import AppKit
import ClipHavenCore

/// The snippet editor: folders on the left, the folder's snippets in the middle, the selected
/// snippet's text on the right. Every edit is written to the store at once.
@MainActor
final class SnippetEditor: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
    private let store: SnippetStore
    private let secrets: SecretPaster
    private let onChange: () -> Void
    private var folders: [SnippetFolder] = []
    private var selectedFolderID: Int64?
    private var selectedSnippetID: Int64?

    private var window: NSWindow?
    private let folderTable = NSTableView()
    private let snippetTable = NSTableView()
    private let contentView = NSTextView()
    private let requireAuthBox = NSButton(checkboxWithTitle: "Require Touch ID", target: nil, action: nil)
    private let keychainNote = NSTextField(labelWithString: "")
    private let moveButton = NSButton(title: "Move to Keychain…", target: nil, action: nil)
    private let linkButton = NSButton(title: "Use Keychain Item…", target: nil, action: nil)
    private let syncButton = NSButton(title: "Sync through iCloud Keychain", target: nil, action: nil)

    init(store: SnippetStore, secrets: SecretPaster, onChange: @escaping () -> Void) {
        self.store = store
        self.secrets = secrets
        self.onChange = onChange
    }

    func show() {
        if window == nil { build() }
        reload()
        // The window can be hidden behind another app's; a status-menu click does not always
        // activate us, so force both.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    // MARK: - Window

    private func build() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 440),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "ClipHaven Snippets"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        configure(folderTable, titleHeader: "Folder")
        configure(snippetTable, titleHeader: "Snippet")

        contentView.isRichText = false
        contentView.isAutomaticQuoteSubstitutionEnabled = false
        contentView.isAutomaticDashSubstitutionEnabled = false
        contentView.isAutomaticTextReplacementEnabled = false
        contentView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        contentView.allowsUndo = true
        contentView.delegate = self
        contentView.isVerticallyResizable = true
        contentView.autoresizingMask = [.width]
        let contentScroll = NSScrollView()
        contentScroll.documentView = contentView
        contentScroll.hasVerticalScroller = true
        contentScroll.borderType = .bezelBorder

        requireAuthBox.target = self
        requireAuthBox.action = #selector(toggleRequireAuth)
        moveButton.target = self
        moveButton.action = #selector(moveToKeychain)
        linkButton.target = self
        linkButton.action = #selector(linkKeychainItem)
        syncButton.target = self
        syncButton.action = #selector(syncThroughICloud)
        keychainNote.textColor = .secondaryLabelColor
        keychainNote.lineBreakMode = .byTruncatingMiddle
        let lockRow = NSStackView(views: [requireAuthBox, moveButton, linkButton])
        lockRow.spacing = 8
        let syncRow = NSStackView(views: [syncButton])
        let rightColumn = NSStackView(views: [contentScroll, keychainNote, lockRow, syncRow])
        rightColumn.orientation = .vertical
        rightColumn.alignment = .leading
        rightColumn.spacing = 6
        contentScroll.widthAnchor.constraint(equalTo: rightColumn.widthAnchor).isActive = true
        contentScroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        let panes = NSStackView(views: [
            pane(folderTable, add: #selector(addFolder), remove: #selector(deleteFolder), up: #selector(moveFolderUp), down: #selector(moveFolderDown)),
            pane(snippetTable, add: #selector(addSnippet), remove: #selector(deleteSnippet), up: #selector(moveSnippetUp), down: #selector(moveSnippetDown)),
            rightColumn,
        ])
        panes.orientation = .horizontal
        panes.distribution = .fill
        panes.spacing = 12
        panes.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        panes.arrangedSubviews[0].widthAnchor.constraint(equalToConstant: 190).isActive = true
        panes.arrangedSubviews[1].widthAnchor.constraint(equalToConstant: 210).isActive = true
        window.contentView = panes
        self.window = window
    }

    private func configure(_ table: NSTableView, titleHeader: String) {
        let on = NSTableColumn(identifier: .init("enabled"))
        on.title = "On"
        on.width = 28
        on.minWidth = 28
        on.maxWidth = 28
        let cell = NSButtonCell()
        cell.setButtonType(.switch)
        cell.title = ""
        on.dataCell = cell
        let title = NSTableColumn(identifier: .init("title"))
        title.title = titleHeader
        title.isEditable = true
        table.addTableColumn(on)
        table.addTableColumn(title)
        table.dataSource = self
        table.delegate = self
        table.allowsEmptySelection = true
    }

    private func pane(_ table: NSTableView, add: Selector, remove: Selector, up: Selector, down: Selector) -> NSView {
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        func button(_ title: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .smallSquare
            return b
        }
        let buttons = NSStackView(views: [button("+", add), button("−", remove), button("▲", up), button("▼", down)])
        buttons.spacing = 4
        let column = NSStackView(views: [scroll, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        scroll.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }

    func windowWillClose(_ notification: Notification) {
        saveContent()
        onChange()
    }

    // MARK: - Data

    private var selectedFolder: SnippetFolder? { folders.first { $0.id == selectedFolderID } }
    private var snippets: [Snippet] { selectedFolder?.snippets ?? [] }

    private func reload() {
        folders = (try? store.folders()) ?? []
        if selectedFolder == nil { selectedFolderID = folders.first?.id }
        if !snippets.contains(where: { $0.id == selectedSnippetID }) { selectedSnippetID = snippets.first?.id }
        folderTable.reloadData()
        snippetTable.reloadData()
        select(folderTable, row: folders.firstIndex { $0.id == selectedFolderID })
        select(snippetTable, row: snippets.firstIndex { $0.id == selectedSnippetID })
        showContent()
    }

    private func select(_ table: NSTableView, row: Int?) {
        if let row { table.selectRowIndexes([row], byExtendingSelection: false) } else { table.deselectAll(nil) }
    }

    private func showContent() {
        let snippet = snippets.first { $0.id == selectedSnippetID }
        let isSecret = snippet?.secret != nil
        contentView.string = snippet?.content ?? ""
        contentView.isEditable = snippet != nil && !isSecret
        requireAuthBox.isEnabled = snippet != nil && !isSecret
        requireAuthBox.state = (snippet?.requiresAuth ?? false) || isSecret ? .on : .off
        moveButton.isEnabled = snippet != nil && !isSecret
        linkButton.isEnabled = snippet != nil && (snippet?.content.isEmpty ?? false) && !isSecret
        syncButton.isEnabled = isSecret
        if let ref = snippet?.secret {
            let synced = snippet.flatMap { try? secrets.isSynchronized(snippetID: $0.id) }
            let where_ = synced == true ? "Syncs through iCloud Keychain." : synced == false ? "This Mac only." : "Item not found."
            syncButton.isEnabled = synced == false
            keychainNote.stringValue = "In the Keychain: \(ref.service) / \(ref.account). Touch ID on every paste. \(where_)"
        } else {
            keychainNote.stringValue = ""
        }
    }

    /// Writes the text pane back to the selected snippet.
    private func saveContent() {
        guard let snippet = snippets.first(where: { $0.id == selectedSnippetID }), snippet.secret == nil,
              snippet.content != contentView.string else { return }
        try? store.updateSnippet(id: snippet.id, title: snippet.title, content: contentView.string, enabled: snippet.enabled)
        folders = (try? store.folders()) ?? folders
    }

    func textDidChange(_ notification: Notification) {
        saveContent()
    }

    // MARK: - Tables

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === folderTable ? folders.count : snippets.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
        let isOn = column?.identifier.rawValue == "enabled"
        if tableView === folderTable {
            guard folders.indices.contains(row) else { return nil }
            return isOn ? folders[row].enabled : folders[row].title
        }
        guard snippets.indices.contains(row) else { return nil }
        return isOn ? snippets[row].enabled : snippets[row].title
    }

    func tableView(_ tableView: NSTableView, setObjectValue value: Any?, for column: NSTableColumn?, row: Int) {
        let isOn = column?.identifier.rawValue == "enabled"
        if tableView === folderTable, folders.indices.contains(row) {
            let folder = folders[row]
            try? store.updateFolder(id: folder.id, title: isOn ? folder.title : (value as? String ?? folder.title),
                                    enabled: isOn ? Self.flag(value, else: folder.enabled) : folder.enabled)
        } else if tableView === snippetTable, snippets.indices.contains(row) {
            let snippet = snippets[row]
            try? store.updateSnippet(id: snippet.id, title: isOn ? snippet.title : (value as? String ?? snippet.title),
                                     content: snippet.content, enabled: isOn ? Self.flag(value, else: snippet.enabled) : snippet.enabled)
        }
        reload()
        onChange()
    }

    /// A checkbox cell hands back an NSNumber.
    private static func flag(_ value: Any?, else fallback: Bool) -> Bool {
        (value as? NSNumber)?.boolValue ?? fallback
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        saveContent()
        if table === folderTable {
            selectedFolderID = folders.indices.contains(folderTable.selectedRow) ? folders[folderTable.selectedRow].id : nil
            selectedSnippetID = snippets.first?.id
            snippetTable.reloadData()
            select(snippetTable, row: snippets.isEmpty ? nil : 0)
        } else {
            selectedSnippetID = snippets.indices.contains(snippetTable.selectedRow) ? snippets[snippetTable.selectedRow].id : nil
        }
        showContent()
    }

    // MARK: - Buttons

    @objc private func addFolder() {
        saveContent()
        selectedFolderID = try? store.addFolder(title: "untitled folder")
        selectedSnippetID = nil
        changed()
        rename(folderTable)
    }

    @objc private func deleteFolder() {
        guard let id = selectedFolderID, let folder = selectedFolder else { return }
        let keychainCount = folder.snippets.filter { $0.secret != nil }.count
        var removeItems = false
        if keychainCount > 0 {
            switch askAboutKeychain(message: "Delete “\(folder.title)”?",
                                    detail: "\(keychainCount) snippet(s) in this folder are stored in the Keychain. Delete those Keychain items too?") {
            case .cancel: return
            case .snippetAndItem: removeItems = true
            case .snippetOnly: break
            }
        }
        do { try secrets.deleteFolder(id: id, removingKeychainItems: removeItems) } catch { showError("Could not delete", "\(error)") }
        selectedFolderID = nil
        selectedSnippetID = nil
        changed()
    }

    @objc private func addSnippet() {
        guard let folder = selectedFolderID else { return }
        saveContent()
        selectedSnippetID = try? store.addSnippet(folderID: folder, title: "untitled snippet", content: "")
        changed()
        rename(snippetTable)
    }

    /// Puts the selected row's name into edit mode with the text selected, ready to type over.
    private func rename(_ table: NSTableView) {
        DispatchQueue.main.async {
            let row = table.selectedRow
            guard row >= 0 else { return }
            table.window?.makeFirstResponder(table)
            table.editColumn(1, row: row, with: nil, select: true)
        }
    }

    @objc private func deleteSnippet() {
        guard let id = selectedSnippetID, let snippet = snippets.first(where: { $0.id == id }) else { return }
        var removeItem = false
        if let ref = snippet.secret {
            switch askAboutKeychain(message: "Delete “\(snippet.title)”?",
                                    detail: "Its password is in the Keychain as \(ref.service) / \(ref.account). Delete that Keychain item too? Keeping it leaves an unused item in the Keychain."
                                    + ((try? secrets.isSynchronized(snippetID: snippet.id)) == true ? " It syncs through iCloud Keychain, so removing it removes it on your other Macs too." : "")) {
            case .cancel: return
            case .snippetAndItem: removeItem = true
            case .snippetOnly: break
            }
        }
        do { try secrets.deleteSnippet(id: id, removingKeychainItem: removeItem) } catch { showError("Could not delete", "\(error)") }
        selectedSnippetID = nil
        changed()
    }

    @objc private func toggleRequireAuth() {
        guard let id = selectedSnippetID else { return }
        try? store.setRequiresAuth(id: id, requireAuthBox.state == .on)
        changed()
    }

    /// Stores the snippet's text in the Keychain and removes it from ClipHaven's own database.
    @objc private func moveToKeychain() {
        saveContent()
        guard let snippet = snippets.first(where: { $0.id == selectedSnippetID }),
              let ref = askForItem(message: "Move “\(snippet.title)” to the Keychain?",
                                   detail: "The text is stored in the Keychain and deleted from ClipHaven. Every paste will ask for Touch ID.",
                                   service: "ClipHaven", account: snippet.title, button: "Move") else { return }
        do {
            try secrets.moveToKeychain(snippetID: snippet.id, as: ref)
        } catch {
            showError("The Keychain refused the item", "\(error)")
        }
        changed()
    }

    /// Makes the password sync to the other Macs on this Apple ID. A synced item cannot carry the
    /// Keychain's own Touch ID rule; ClipHaven still asks before every paste.
    @objc private func syncThroughICloud() {
        guard let snippet = snippets.first(where: { $0.id == selectedSnippetID }) else { return }
        let alert = NSAlert()
        alert.messageText = "Sync “\(snippet.title)” through iCloud Keychain?"
        alert.informativeText = "The password will appear on your other Macs signed in to the same Apple ID with iCloud Keychain on. Touch ID is still asked before every paste in ClipHaven. Removing the item later removes it from all of them."
        alert.addButton(withTitle: "Sync")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            switch try secrets.synchronize(snippetID: snippet.id) {
            case .missing: showError("Keychain item not found", "Link the snippet to an existing item first.")
            default: break
            }
        } catch {
            showError("Could not sync", "\(error)\n\nThis needs a ClipHaven build signed with its provisioning profile.")
        }
        changed()
    }

    /// Points an empty snippet at a Keychain item that already exists.
    @objc private func linkKeychainItem() {
        guard let snippet = snippets.first(where: { $0.id == selectedSnippetID }),
              let ref = askForItem(message: "Use a Keychain item for “\(snippet.title)”?",
                                   detail: "Enter the service and account of an existing generic password. Only those two names are stored.",
                                   service: "", account: "", button: "Use Item") else { return }
        try? store.setSecret(id: snippet.id, ref)
        changed()
    }

    private func askForItem(message: String, detail: String, service: String, account: String, button: String) -> SecretRef? {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        let serviceField = NSTextField(string: service)
        let accountField = NSTextField(string: account)
        serviceField.placeholderString = "Service"
        accountField.placeholderString = "Account"
        let fields = NSStackView(views: [serviceField, accountField])
        fields.orientation = .vertical
        fields.frame = NSRect(x: 0, y: 0, width: 300, height: 52)
        serviceField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        accountField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        alert.accessoryView = fields
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn,
              !serviceField.stringValue.isEmpty, !accountField.stringValue.isEmpty else { return nil }
        return SecretRef(service: serviceField.stringValue, account: accountField.stringValue)
    }

    private enum KeychainChoice { case snippetAndItem, snippetOnly, cancel }

    private func askAboutKeychain(message: String, detail: String) -> KeychainChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "Delete and Remove Keychain Item")
        alert.addButton(withTitle: "Delete, Keep Keychain Item")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .snippetAndItem
        case .alertSecondButtonReturn: return .snippetOnly
        default: return .cancel
        }
    }

    private func showError(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }

    @objc private func moveFolderUp() { moveFolder(by: -1) }
    @objc private func moveFolderDown() { moveFolder(by: 1) }
    @objc private func moveSnippetUp() { moveSnippet(by: -1) }
    @objc private func moveSnippetDown() { moveSnippet(by: 1) }

    private func moveFolder(by offset: Int) {
        guard let id = selectedFolderID, let from = folders.firstIndex(where: { $0.id == id }),
              folders.indices.contains(from + offset) else { return }
        var ids = folders.map(\.id)
        ids.swapAt(from, from + offset)
        try? store.reorderFolders(ids)
        changed()
    }

    private func moveSnippet(by offset: Int) {
        guard let folder = selectedFolderID, let id = selectedSnippetID, let from = snippets.firstIndex(where: { $0.id == id }),
              snippets.indices.contains(from + offset) else { return }
        var ids = snippets.map(\.id)
        ids.swapAt(from, from + offset)
        try? store.reorderSnippets(ids, in: folder)
        changed()
    }

    private func changed() {
        reload()
        onChange()
    }
}
